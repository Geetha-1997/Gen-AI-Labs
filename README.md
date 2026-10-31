# Gen-AI-Labs

A ChatGPT-style AI workspace built with React + TypeScript, FastAPI, PostgreSQL and Groq inference. Designed for Docker and Amazon EKS deployment.

> **Provider clarification:** Groq and xAI are different providers with different API keys and endpoints. This implementation uses the Groq API as the configured primary provider. The xAI key setting is reserved for a future provider adapter; it is not used by the Groq client. Do not put either key in browser code.

## Capabilities

- Email/password registration and login; JWT-protected API routes.
- Per-user conversation history and persisted user/assistant messages.
- Multi-turn context (most recent 30 messages supplied to the model).
- Groq Chat Completions API with server-sent event streaming.
- PostgreSQL persistence and Alembic schema migrations.
- Responsive dark React chat interface, conversation creation/deletion, streaming composer.
- Docker Compose local environment; non-root frontend/backend images.
- Kubernetes Deployment/Service/Ingress/HPA/PDB manifests; AWS ALB HTTPS ingress.
- GitHub Actions tests, ECR image publishing and EKS rollout using GitHub OIDC.

## Architecture

```mermaid
flowchart TB
  U[Browser] --> R53[Route 53 DNS]
  R53 --> ALB[ALB + ACM HTTPS]
  ALB --> WEB[React / Nginx on EKS]
  ALB --> API[FastAPI on EKS]
  WEB -->|/api same-origin| API
  API --> DB[(PostgreSQL / Amazon RDS)]
  API --> GROQ[Groq Chat Completions API]
  GH[GitHub Actions] -->|OIDC short-lived role| AWS[AWS IAM]
  GH --> ECR[ECR repositories]
  ECR --> EKS[EKS deployments]
  EKS --> CW[CloudWatch Container Insights]
```

## Local development

### Prerequisites

- Docker Engine + Docker Compose v2
- A Groq API key from [Groq Console](https://console.groq.com/keys)

### Start

```bash
cp .env.example .env
# Edit .env: set GROQ_API_KEY and a unique JWT_SECRET (32+ random bytes)
docker compose up --build -d
```

Open:
- Web app: http://localhost:8080
- API OpenAPI docs: http://localhost:8000/docs
- Liveness: http://localhost:8000/health/live
- Readiness: http://localhost:8000/health/ready

The first backend boot does not create tables. Run the migration once after PostgreSQL is healthy:

```bash
docker compose exec backend alembic upgrade head
```

Then register an account in the UI. To inspect logs: `docker compose logs -f backend`.

### Run without Docker

```bash
# PostgreSQL must be running and DATABASE_URL configured.
cd backend
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --reload --port 8000
```

In another terminal:

```bash
cd frontend
npm install
# VITE_API_URL defaults to same-origin. For Vite dev server use:
# Windows PowerShell: $env:VITE_API_URL='http://localhost:8000'
# macOS/Linux: VITE_API_URL=http://localhost:8000 npm run dev
npm run dev
```

## Configuration

| Variable | Required | Description |
|---|---:|---|
| `GROQ_API_KEY` | Yes | Groq API secret; backend only |
| `GROQ_MODEL` | No | Defaults to `openai/gpt-oss-120b`; verify model availability in Groq Console |
| `DATABASE_URL` | Yes | SQLAlchemy PostgreSQL URL using psycopg driver |
| `JWT_SECRET` | Yes | Random signing secret; use Secrets Manager in production |
| `JWT_ALGORITHM` | No | Defaults to HS256 |
| `ACCESS_TOKEN_MINUTES` | No | Defaults to 60 |
| `CORS_ORIGINS` | No | Comma-separated trusted browser origins |
| `XAI_API_KEY` | No | Reserved for separate xAI adapter; currently unused |
| `VITE_API_URL` | No | Frontend API origin; blank for same-origin ALB routing |

Never use the sample local JWT secret in a deployed environment. Never prefix a secret with `VITE_`: Vite variables are bundled into public browser assets.

## Tests and validation

```bash
cd backend
pip install -r requirements.txt
python -m compileall -q app
python -m pytest -q
cd ../frontend
npm ci
npm run build
```

The backend tests currently cover password hashing/verification and JWT subject encoding. Add integration tests against an ephemeral PostgreSQL instance and mocked Groq transport before production sign-off. CI runs backend unit tests and frontend production compilation before publishing images.

## AWS deployment (operator-run)

The AWS account, region, domain, EKS cluster, ACM certificate and GitHub repository are environment-specific. No AWS account credentials were supplied to this build, so **no AWS resources have been created and no deployment is claimed**.

### 1. Provision AWS foundation

Use an approved IaC baseline (Terraform or AWS CDK) to create:

- VPC across at least two Availability Zones, public/private subnets, route tables and security groups.
- EKS cluster and managed node group(s) in private subnets. Use supported Kubernetes/EKS versions and a supported node AMI.
- ECR repositories `gen-ai-labs-api` and `gen-ai-labs-web`, with image scanning, immutable release tags and lifecycle retention.
- Amazon RDS for PostgreSQL in private subnets, encryption at rest, automated backups and deletion protection. Do not run production PostgreSQL as a single pod.
- ACM public certificate for `app.example.com` in the ALB region.
- Route 53 hosted zone and DNS alias to the ALB after Ingress provisions it.
- CloudWatch Container Insights/log groups, alarms, retention and SNS notifications.

### 2. Configure EKS add-ons

Install/configure the AWS Load Balancer Controller with its own least-privilege IRSA role and service account. Follow the official AWS procedure; do not reuse the application's IAM role. Install Metrics Server for HPA. Configure node autoscaling using **Karpenter (recommended for new deployments)** or Cluster Autoscaler; provision its own IAM permissions and interruption handling. `infra/k8s/karpenter-nodepool.yaml` provides a starting EC2NodeClass/NodePool template; replace the cluster tags and node role, and validate against the installed Karpenter CRDs before applying. The included HPA will not scale without resource metrics.

Official references:
- [EKS AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)
- [Install Load Balancer Controller with Helm](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)
- [EKS security best practices](https://docs.aws.amazon.com/eks/latest/best-practices/security.html)
- [EKS cluster autoscaling best practices](https://docs.aws.amazon.com/eks/latest/best-practices/cluster-autoscaling/)

### 3. Create secrets

Recommended: AWS Secrets Manager + External Secrets Operator (ESO) with IRSA. Store `database-url`, `jwt-secret`, and `groq-api-key` in Secrets Manager and configure an ESO `SecretStore`/`ExternalSecret` to materialize Kubernetes Secret `gen-ai-labs-secrets` in namespace `gen-ai-labs`.

For a short-lived test only, create the Kubernetes secret interactively (avoid shell history and CI logs):

```bash
kubectl create namespace gen-ai-labs
kubectl -n gen-ai-labs create secret generic gen-ai-labs-secrets \
  --from-literal=database-url='postgresql+psycopg://USER:PASSWORD@RDS_ENDPOINT:5432/genai' \
  --from-literal=jwt-secret='GENERATE_A_LONG_RANDOM_VALUE' \
  --from-literal=groq-api-key='GROQ_SECRET'
```

Do not commit `secrets.template.yaml` with real values or pass credentials as command-line arguments in shared environments.

### 4. Build and push images

```bash
export AWS_REGION=ap-south-1
export AWS_ACCOUNT_ID=123456789012
export REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
aws ecr create-repository --repository-name gen-ai-labs-api --region "$AWS_REGION"
aws ecr create-repository --repository-name gen-ai-labs-web --region "$AWS_REGION"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"
docker build -t "$REGISTRY/gen-ai-labs-api:initial" ./backend
docker build --build-arg VITE_API_URL= --build-arg VITE_MODEL_NAME=Llama -t "$REGISTRY/gen-ai-labs-web:initial" ./frontend
docker push "$REGISTRY/gen-ai-labs-api:initial"
docker push "$REGISTRY/gen-ai-labs-web:initial"
```

### 5. Configure GitHub OIDC

Create the GitHub OIDC provider `token.actions.githubusercontent.com` if absent. Create a deploy role using `infra/aws/oidc-trust-policy.json`, replacing account and repository placeholders. Restrict `sub` to the exact repository and protected deployment branch/environment. Attach a least-privilege policy based on `infra/aws/github-deploy-policy.json`; scope ECR to the two repositories and EKS to the target cluster. Configure the EKS access entry/RBAC mapping so the role can update only the intended namespace/deployments.

Set GitHub repository/environment configuration:

- Variable `AWS_REGION`
- Variable `EKS_CLUSTER_NAME`
- Secret `AWS_DEPLOY_ROLE_ARN`
- Protect the `production` environment with required reviewers and branch restrictions.

The workflow uses OIDC and does not require long-lived AWS access keys. Its trust-policy subject must match the `production` GitHub Environment configured in the workflow. The workflow runs the migration Job before updating the application Deployments; use backward-compatible expand/contract migrations.

### 6. Deploy manifests and migrate database

Replace all placeholders in `infra/k8s/*.yaml`: account ID, region, ACM certificate ARN, hostname and image references. Ensure `CORS_ORIGINS` matches the real HTTPS site. Apply in order:

```bash
aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"
kubectl apply -f infra/k8s/namespace.yaml
kubectl apply -f infra/k8s/backend.yaml
kubectl apply -f infra/k8s/frontend.yaml
kubectl apply -f infra/k8s/autoscaling.yaml
# After Karpenter is installed and cluster-specific tags/role are set:
# kubectl apply -f infra/k8s/karpenter-nodepool.yaml
kubectl apply -f infra/k8s/ingress.yaml
```

Run the migration Job template after replacing the image placeholder with the exact backend image tag:

```bash
sed "s|AWS_ACCOUNT_ID.dkr.ecr.AWS_REGION.amazonaws.com/gen-ai-labs-api:latest|$REGISTRY/gen-ai-labs-api:initial|" infra/k8s/migration-job.yaml > /tmp/gen-ai-labs-migration.yaml
kubectl -n gen-ai-labs delete job gen-ai-labs-migrate --ignore-not-found=true
kubectl apply -f /tmp/gen-ai-labs-migration.yaml
kubectl -n gen-ai-labs wait --for=condition=complete job/gen-ai-labs-migrate --timeout=300s
```

Then verify:

```bash
kubectl -n gen-ai-labs get pods,svc,ingress,hpa,pdb
kubectl -n gen-ai-labs rollout status deploy/gen-ai-labs-api
kubectl -n gen-ai-labs rollout status deploy/gen-ai-labs-web
kubectl -n gen-ai-labs get ingress gen-ai-labs -o wide
```

Create a Route 53 A/AAAA alias to the ALB DNS name/hosted zone ID once provisioned. Test HTTPS, DNS, certificate chain, auth, persistence, streaming and cross-user access isolation.


### 7. CI/CD behavior

Pull requests run Python tests and frontend build. A push to `main` after tests assumes the configured GitHub OIDC role, builds and pushes immutable SHA tags to ECR, runs the checked-in migration Job, updates both Deployments and waits for rollout. Protect the `production` environment with reviewer approval and branch restrictions. Use backward-compatible expand/contract migrations.

## Security and operational controls

- API keys remain server-side in environment variables/Secrets Manager; never expose them to Vite/browser code.
- HTTPS termination at ALB/ACM; restrict ingress and database security groups. RDS accepts PostgreSQL only from application/node security groups.
- JWT expiry, bcrypt password hashes, ownership-scoped conversation queries, input length bounds, non-root images, read-only root filesystems and dropped Linux capabilities.
- Kubernetes resource requests/limits, readiness/liveness probes, HPA and PDB.
- Enable ECR image scanning, dependency scanning, branch protection, secret scanning and signed/provenance-attested builds as an operational hardening step.
- Configure API rate limiting/WAF, account lockout or throttling, email verification, password reset, refresh-token rotation and HttpOnly Secure SameSite cookies before public launch. The current demo stores the access token in browser localStorage; this is not the preferred production session design.
- Add audit events with request IDs; do not log prompts, passwords, tokens, API keys or database URLs. Configure CloudWatch retention and alarms for 5xx, latency, pod restarts, CPU/memory, RDS storage/connections and ALB target health.
- Enable RDS automated backups (e.g. 7–35 day retention per policy), point-in-time recovery, encryption with KMS, snapshots before schema changes and periodic restore drills. Define RPO/RTO with the service owner.
- Use a database connection pool budget aligned to maximum API replicas and RDS connection limits. Consider PgBouncer/RDS Proxy at scale.

## Monitoring, backup and rollback

```bash
kubectl -n gen-ai-labs logs deploy/gen-ai-labs-api --since=30m
kubectl -n gen-ai-labs describe pods
kubectl -n gen-ai-labs get hpa
kubectl -n gen-ai-labs rollout history deploy/gen-ai-labs-api
./scripts/rollback.sh
```

Rollback reverts application Deployments to the previous ReplicaSet. It does **not** reverse database migrations. Use backward-compatible migrations; restore from a verified RDS snapshot/PITR only under an approved incident procedure. Keep the last known-good ECR image tag and deployment manifest revision.

## Troubleshooting

| Symptom | Check |
|---|---|
| `GROQ_API_KEY is not configured` | Secret name/key, pod env, ESO sync status; restart deployment after secret rotation |
| Groq 401/429/5xx | Key validity, model availability, quota/rate limits, provider status; inspect sanitized API error logs |
| API readiness 503 | `DATABASE_URL`, RDS SG/NACL/routes, TLS mode, DB credentials, migrations |
| HPA `<unknown>` | Metrics Server, resource requests, `kubectl top pods` |
| Ingress pending | AWS Load Balancer Controller logs, subnet tags, IAM/IRSA, ACM region and security groups |
| HTTPS/DNS failure | ACM domain validation, Ingress certificate ARN, Route 53 alias, ALB listener/target health |
| Streaming appears buffered | ALB idle timeout, proxy buffering, client network; response includes `X-Accel-Buffering: no` |
| Pods crash with permission errors | Container UID, writable Nginx runtime mounts, Kubernetes security context |

## Cost planning (indicative, not a quote)

Illustrative small production footprint in a common AWS commercial region, 730 hours/month, two modest worker nodes, one ALB, managed PostgreSQL, modest logs/egress. Actual prices depend materially on region, instance family, storage, NAT traffic, requests, HA and support. Validate with the [AWS Pricing Calculator](https://calculator.aws/).

| Component | Rough monthly planning range (USD) |
|---|---:|
| EKS control plane | $73 |
| 2 worker nodes | $60–$180 |
| ALB + LCU usage | $20–$60 |
| NAT gateways / data processing | $35–$120+ |
| RDS PostgreSQL | $40–$180+ |
| EBS, snapshots, S3 backups | $10–$40 |
| CloudWatch logs/metrics/alarms | $10–$50+ |
| Route 53 hosted zone/queries | $1–$5+ |
| **Indicative AWS total** | **$249–$708+ / month** |

Groq inference is separate and usage-based according to selected model/input/output tokens and current plan/rates. Consult [Groq pricing](https://groq.com/pricing/) before launch; do not assume a free tier or fixed token rate. xAI charges separately if enabled later; see [xAI API pricing](https://docs.x.ai/docs). Add WAF, multi-AZ NAT, production HA, support, backups and higher throughput to a full production estimate. Cost estimate excludes engineering and taxes.

## Project status

See [`STATUS.md`](STATUS.md) for generated files, validation evidence, environment blockers and the operator checklist. No AWS deployment is performed automatically by this repository generation.
