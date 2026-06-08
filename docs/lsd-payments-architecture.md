# LSD Payments — AWS Architecture

**Region:** us-east-2 · **Author:** adkinsdevon001 · **Date:** 2026-06-08 · **Version:** v1.0

Diagram source: [lsd-payments-architecture.drawio](lsd-payments-architecture.drawio) (open in [draw.io](https://app.diagrams.net) or the VS Code Draw.io extension).

## Request Flow (runtime)

1. **Users (Internet)** reach the platform over **HTTPS**.
2. Traffic enters the VPC through the **Internet Gateway** and hits the **internet-facing ALB** sitting in the **3 public subnets**.
3. The ALB routes `/` to the **lsd-frontend** Deployment (React/nginx, 2 replicas) and `/api` to the **lsd-backend** Deployment (Node.js, 2 replicas), both running on EKS worker nodes in the **3 private subnets**.
4. The frontend calls the backend over the internal **REST API**.
5. The backend connects to **RDS PostgreSQL 15** (db.t3.micro) on port **5432** in the private subnets.
6. Outbound traffic from private nodes egresses through the single **NAT Gateway** → Internet Gateway.

## CI/CD Flow (GitOps)

1. **Developer** pushes to the **GitHub repo** (`lsd-payments`).
2. **GitHub Actions** builds Docker images and pushes them to **ECR** (`lsd-frontend`, `lsd-backend`), then commits an updated `kustomization.yaml` back to the repo. Terraform state is stored in **S3** and locked via **DynamoDB**.
3. **ArgoCD** (running in EKS) watches the repo and reconciles desired state, deploying the updated Deployments.
4. EKS pulls the new images from **ECR**.

## Services & Purpose

| Component | Purpose |
|-----------|---------|
| VPC (10.0.0.0/16) | Network isolation; 3 public + 3 private subnets across us-east-2a/2b/2c |
| Internet Gateway | Inbound/outbound internet access for public subnets |
| NAT Gateway (×1) | Outbound internet access for private subnets |
| ALB (internet-facing) | L7 ingress in public subnets; routes to EKS services |
| EKS Cluster `lsd-payments-dev` | Kubernetes control plane + 2× t3.medium worker nodes (private subnets) |
| ALB Controller | Provisions/manages the ALB from Kubernetes Ingress (uses IRSA) |
| OPA Gatekeeper | Admission-control policy enforcement |
| External Secrets Operator | Syncs Secrets Manager values into Kubernetes Secrets (uses IRSA) |
| ArgoCD | GitOps continuous delivery; reconciles repo → cluster |
| Dynatrace Operator + OneAgent DaemonSet | Observability; OneAgent ships telemetry to Dynatrace SaaS |
| lsd-frontend Deployment | React app served by nginx, 2 replicas |
| lsd-backend Deployment | Node.js API, 2 replicas |
| RDS PostgreSQL 15 (db.t3.micro) | Application database in private subnets |
| ECR (lsd-frontend, lsd-backend) | Container image registry |
| Secrets Manager (rds-v2, dynatrace) | RDS credentials and Dynatrace token |
| IAM Roles (IRSA) | `alb-controller`, `external-secrets` pod-level AWS access |
| S3 | Terraform remote state |
| DynamoDB | Terraform state locking |

## Key Design Decisions

- **Single NAT Gateway** for the dev environment to reduce cost (vs. one per AZ in prod).
- **IRSA** grants least-privilege AWS access to specific service accounts (ALB Controller, External Secrets) instead of node-wide IAM roles.
- **Secrets never live in Git** — External Secrets Operator pulls from Secrets Manager at runtime.
- **GitOps with ArgoCD** — the GitHub repo is the single source of truth; GitHub Actions only builds/pushes images and bumps the image tag.
- **Private workloads** — all compute (EKS nodes, RDS) is in private subnets; only the ALB is internet-facing.
