# Gen-AI-Labs build status

**Build state:** Source package cleaned and deployment scaffold updated. Static source/configuration checks are recorded below. This package has not been deployed to AWS and is not certified production-ready.

## Included

- [x] React + TypeScript chat frontend, sign-in and registration screens.
- [x] FastAPI API, JWT authentication, bcrypt password hashing and user-owned conversations.
- [x] PostgreSQL SQLAlchemy models and Alembic migration source (`backend/alembic`).
- [x] Groq Chat Completions streaming adapter; API key remains backend-side.
- [x] Dockerfiles, Docker Compose and `.env.example`.
- [x] Dedicated `database/` operational folder with local backup/restore helpers.
- [x] Terraform EC2 architecture: dedicated two-AZ VPC, ALBs, web/app Auto Scaling Groups, SSM-only Bastion, ECR, encrypted Multi-AZ RDS, Secrets Manager, least-privilege EC2 roles, CloudWatch logs/alarms, optional Route 53/ACM and optional SNS email notifications.
- [x] GitHub Actions CI workflow: backend pytest/coverage, frontend Vitest/build, Trivy filesystem vulnerability/misconfiguration/secret scan, Docker builds and Trivy image scans.
- [x] SonarQube project configuration and optional CI scan (requires `SONAR_TOKEN` secret and `SONAR_HOST_URL` repository variable).
- [x] Optional local SonarQube Community service behind Docker Compose `quality` profile.
- [x] Optional Kubernetes manifest examples under `infra/k8s/`; these are not deployed by the EC2 Terraform stack.
- [x] PowerShell image bootstrap and SSM rollout scripts.
- [x] Documentation for architecture, cost review, deployment and operational limitations.

## Checks completed in this workspace

- [x] Python source syntax compilation (`compileall`).
- [x] AWS IAM JSON files parsed.
- [x] GitHub Actions and Docker Compose YAML parsed; Kubernetes multi-document YAML is retained as supplied.
- [x] Shell syntax checked for GitHub Actions run steps and local shell scripts.
- [x] Terraform variable references checked against declarations; HCL delimiter/string scans passed.

## Checks not completed

- [ ] Backend pytest/coverage: run in CI or a dependency-enabled environment; not executed as part of this modification.
- [ ] Frontend Vitest tests and Vite build: run in CI or a dependency-enabled environment; not executed as part of this modification.
- [ ] Trivy filesystem/image scans and Docker image builds: run in GitHub Actions; not executed in this workspace.
- [ ] SonarQube analysis: configure `SONAR_TOKEN` and `SONAR_HOST_URL`; scan is skipped until configured.
- [ ] Terraform `fmt`, `validate` and `plan`: run these locally before any apply.
- [ ] PowerShell deployment scripts: PowerShell runtime unavailable here; review/run in Windows PowerShell 7.
- [ ] Groq live API, AWS deployment, ALB health, RDS failover/restore, autoscaling and SNS delivery have not been tested.

## Production sign-off still required

1. Run dependency-backed backend/frontend/Docker checks and Terraform `fmt`, `validate`, and `plan` in the target environment.
2. Review current AWS costs. Two NAT Gateways, two ALBs, four baseline EC2 instances, Bastion and Multi-AZ RDS incur ongoing charges.
3. Configure encrypted/versioned remote Terraform state and restrict access; local state is only a starter.
4. Add HttpOnly Secure SameSite sessions, CSRF protections, rate limiting/WAF, account recovery, email verification, audit controls and dependency/image scanning.
5. Fix any Trivy HIGH/CRITICAL findings and SonarQube quality-gate issues.
6. Deploy to staging, test migrations and authorization isolation, load test, verify alarms, test RDS restore/failover, and rehearse rollback.

**No AWS resources were created, no AWS deployment was performed, and no end-to-end production test is claimed.**
