#!/usr/bin/env bash
set -euo pipefail

# ---- Change only these three lines (respect upper/lowercase) ----
GH_USER="su-usuario-github"
GH_REPO="gitops-lab"
BILLING_ACCOUNT="XXXXXX-XXXXXX-XXXXXX"   # gcloud billing accounts list
# -----------------------------------------------------------------

REGION="us-central1"
SUFFIX="$(openssl rand -hex 3)"
P_STATE="gitops-state-${SUFFIX}"
P_DEV="gitops-dev-${SUFFIX}"
P_PROD="gitops-prod-${SUFFIX}"
BUCKET="tfstate-${P_STATE}"
SA_NAME="sa-gitops-github"
SA_EMAIL="${SA_NAME}@${P_STATE}.iam.gserviceaccount.com"
POOL="github-pool"
PROVIDER="github-provider"

echo "1/6 Projects (the GCP equivalent of Azure resource groups)"
for p in "$P_STATE" "$P_DEV" "$P_PROD"; do
  gcloud projects create "$p" --name="$p" --quiet
  gcloud billing projects link "$p" --billing-account="$BILLING_ACCOUNT" --quiet
done

echo "2/6 APIs"
gcloud services enable storage.googleapis.com iam.googleapis.com \
  iamcredentials.googleapis.com sts.googleapis.com \
  cloudresourcemanager.googleapis.com --project="$P_STATE"
for p in "$P_DEV" "$P_PROD"; do
  gcloud services enable storage.googleapis.com \
    cloudresourcemanager.googleapis.com --project="$p"
done

echo "3/6 Terraform state bucket (versioned, no public access)"
gcloud storage buckets create "gs://${BUCKET}" --project="$P_STATE" \
  --location="$REGION" --uniform-bucket-level-access \
  --public-access-prevention
gcloud storage buckets update "gs://${BUCKET}" --versioning

echo "4/6 Service account (no keys are ever created)"
gcloud iam service-accounts create "$SA_NAME" --project="$P_STATE" \
  --display-name="GitHub Actions GitOps"

echo "5/6 Workload Identity Federation for GitHub"
GH_JSON=$(curl -fsS "https://api.github.com/repos/${GH_USER}/${GH_REPO}") || {
  echo "Repo github.com/${GH_USER}/${GH_REPO} not found. Create it first (public)."
  exit 1
}
OWNER=$(echo "$GH_JSON" | jq -r .owner.login); OWNER_ID=$(echo "$GH_JSON" | jq -r .owner.id)
REPO=$(echo "$GH_JSON" | jq -r .name);         REPO_ID=$(echo "$GH_JSON" | jq -r .id)

gcloud iam workload-identity-pools create "$POOL" --project="$P_STATE" \
  --location=global --display-name="GitHub"

# The attribute condition is the "lock": only THIS repo (by immutable numeric
# ID) can use the provider. Forks and renamed/recreated repos do not match.
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
  --project="$P_STATE" --location=global --workload-identity-pool="$POOL" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_id=assertion.repository_id,attribute.repository_owner_id=assertion.repository_owner_id" \
  --attribute-condition="assertion.repository_id=='${REPO_ID}' && assertion.repository_owner_id=='${OWNER_ID}'"

POOL_NAME=$(gcloud iam workload-identity-pools describe "$POOL" \
  --project="$P_STATE" --location=global --format='value(name)')

# One binding per subject (the same four as the Azure lab).
for ctx in "pull_request" "ref:refs/heads/main" "environment:dev" "environment:prod"; do
  gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
    --project="$P_STATE" --role="roles/iam.workloadIdentityUser" \
    --member="principal://iam.googleapis.com/${POOL_NAME}/subject/repo:${OWNER}/${REPO}:${ctx}" \
    --condition=None --quiet >/dev/null
done

echo "6/6 Least-privilege roles"
for p in "$P_DEV" "$P_PROD"; do
  gcloud projects add-iam-policy-binding "$p" \
    --member="serviceAccount:${SA_EMAIL}" --role="roles/storage.admin" \
    --condition=None --quiet >/dev/null
done
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/storage.objectAdmin" >/dev/null

echo
echo "Create these 7 variables in GitHub (Settings > Secrets and variables > Actions > Variables):"
echo "  GCP_WIF_PROVIDER    = ${POOL_NAME}/providers/${PROVIDER}"
echo "  GCP_SERVICE_ACCOUNT = ${SA_EMAIL}"
echo "  GCP_PROJECT_DEV     = ${P_DEV}"
echo "  GCP_PROJECT_PROD    = ${P_PROD}"
echo "  GCP_REGION          = ${REGION}"
echo "  TFSTATE_BUCKET      = ${BUCKET}"
echo "  GCP_PROJECT_STATE   = ${P_STATE}   (only needed for cleanup)"
