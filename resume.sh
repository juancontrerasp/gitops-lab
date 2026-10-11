#!/usr/bin/env bash
set -euo pipefail

GH_USER=$(grep '^GH_USER=' bootstrap/bootstrap.sh | cut -d'"' -f2)
GH_REPO=$(grep '^GH_REPO=' bootstrap/bootstrap.sh | cut -d'"' -f2)

SUFFIX="53d92c"
REGION="us-central1"
P_STATE="gitops-state-${SUFFIX}"
P_DEV="gitops-dev-${SUFFIX}"
P_PROD="gitops-prod-${SUFFIX}"
BUCKET="tfstate-${P_STATE}"
SA_NAME="sa-gitops-github"
SA_EMAIL="${SA_NAME}@${P_STATE}.iam.gserviceaccount.com"
POOL="github-pool"
PROVIDER="github-provider"

echo "5/6 Workload Identity Federation for GitHub"
GH_JSON=$(curl -fsS "https://api.github.com/repos/${GH_USER}/${GH_REPO}")
OWNER=$(echo "$GH_JSON" | jq -r .owner.login); OWNER_ID=$(echo "$GH_JSON" | jq -r .owner.id)
REPO=$(echo "$GH_JSON" | jq -r .name);         REPO_ID=$(echo "$GH_JSON" | jq -r .id)

gcloud iam workload-identity-pools create "$POOL" --project="$P_STATE" \
  --location=global --display-name="GitHub"

gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
  --project="$P_STATE" --location=global --workload-identity-pool="$POOL" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_id=assertion.repository_id,attribute.repository_owner_id=assertion.repository_owner_id" \
  --attribute-condition="assertion.repository_id=='${REPO_ID}' && assertion.repository_owner_id=='${OWNER_ID}'"

POOL_NAME=$(gcloud iam workload-identity-pools describe "$POOL" \
  --project="$P_STATE" --location=global --format='value(name)')

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
echo "Create these 7 variables in GitHub:"
echo "  GCP_WIF_PROVIDER    = ${POOL_NAME}/providers/${PROVIDER}"
echo "  GCP_SERVICE_ACCOUNT = ${SA_EMAIL}"
echo "  GCP_PROJECT_DEV     = ${P_DEV}"
echo "  GCP_PROJECT_PROD    = ${P_PROD}"
echo "  GCP_REGION          = ${REGION}"
echo "  TFSTATE_BUCKET      = ${BUCKET}"
echo "  GCP_PROJECT_STATE   = ${P_STATE}"
