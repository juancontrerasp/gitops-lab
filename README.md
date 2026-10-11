# Laboratorio 6: GitOps con GitHub, Terraform y Google Cloud

Repositorio plantilla del laboratorio (PEMU 2026, Escuela Colombiana de
Ingeniería Julio Garavito). Versión para Google Cloud. Siga la guía del
laboratorio; no suba secretos ni claves JSON.

- `modules/static_site/`  módulo: bucket de Cloud Storage con sitio web estático
- `envs/dev`, `envs/prod` un entorno por carpeta, cada uno con su propio estado
- `site/index.html`       la página que se publica
- `.github/workflows/`    terraform-plan, terraform-apply, drift y destroy
- `bootstrap/bootstrap.sh` preparación de Google Cloud (se ejecuta una vez, a mano)
