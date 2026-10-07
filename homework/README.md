# DevOps Course Homework

Student: Om Malviya | Enrollment No: 24BCS10448

This folder contains my submissions for all 21 session assignments from the
[DevOps HomeWork document](https://docs.google.com/document/d/1cjXFYf2Thm8cBEN-0C48B-v02cj3jGLd47lcO18prHE/edit?usp=sharing).
Each session has its own folder with a README.md that restates the tasks, shows the
commands I ran, the output, and my explanation. Terminal output blocks stand in for
screenshots; every output block says whether it was captured on my machine or is the
expected output for an environment I could not run (AWS, GitHub-hosted runners).

| # | Session | Folder | Main deliverables |
|---|---------|--------|-------------------|
| 1 | DevOps Engineer Roadmap | [session01-devops-roadmap](session01-devops-roadmap/) | Study notes |
| 2 | Linux | [session02-linux](session02-linux/) | Soft/hard links, adduser vs useradd, journalctl, cheat sheet practice |
| 3 | Shell Scripting | [session03-shell-scripting](session03-shell-scripting/) | `system-info.sh`, `practice.sh`, captured output |
| 4 | Networking | [session04-networking](session04-networking/) | Subnetting notes, networking command outputs |
| 5 | Git & GitHub | [session05-git-github](session05-git-github/) | `git commit -a` vs `-m`, cherry-pick walkthrough, cheat sheet |
| 6 | Docker – Hello World apps | [session06-docker-hello-world](session06-docker-hello-world/) | nodejs-app, python-app, java-app, Apache-app, React-app, nginx-app |
| 7 | Docker – Multi-stage build | [session07-docker-multistage](session07-docker-multistage/) | Multi-stage app on 8080, 3 app deployments |
| 8 | Docker – Networking & Volumes | [session08-docker-networking-volume](session08-docker-networking-volume/) | 3 networks, host network, bind mount, overlay research |
| 9 | Kubernetes Fundamentals | [session09-kubernetes-fundamentals](session09-kubernetes-fundamentals/) | Minikube setup, architecture notes, basics tutorial |
| 10 | Pods, ReplicaSets & Deployments | [session10-k8s-core-objects](session10-k8s-core-objects/) | 4 deployment strategies, pod lifecycle |
| 11 | Networking & Services | [session11-k8s-services](session11-k8s-services/) | 5 service types, object comparison, fqdn/, coredns/ |
| 12 | Ingress, ConfigMaps & Secrets | [session12-ingress-configmaps-secrets](session12-ingress-configmaps-secrets/) | ConfigMap, Secret, Ingress demos, troubleshooting |
| 13 | Storage, HPA & Probes | [session13-storage-hpa-probes](session13-storage-hpa-probes/) | Volumes doc, HPA hands-on, mini project |
| 14 | Kubernetes Troubleshooting | [session14-k8s-troubleshooting](session14-k8s-troubleshooting/) | Commands, 9 issue scenarios, mini project |
| 15 | Helm | [session15-helm](session15-helm/) | Helm commands, rollback workflow, mini project |
| 16 | CI/CD & GitHub Actions | [session16-cicd-github-actions](session16-cicd-github-actions/) | App, Dockerfile, CI + CD workflow |
| 17 | CI/CD & DevSecOps | [session17-devsecops](session17-devsecops/) | SAST, SCA, secret scan, image scan, security gate pipeline |
| 18 | Terraform & IaC | [session18-terraform-iac](session18-terraform-iac/) | terraform-s3-demo/, aws-services/ research |
| 19 | Cloud & Terraform in Action | [session19-cloud-terraform](session19-cloud-terraform/) | VPC + Subnet + SG + EC2 + S3 project |
| 20 | Monitoring, Observability & GitOps | [session20-monitoring-observability-gitops](session20-monitoring-observability-gitops/) | Prometheus/Grafana stack, observability doc, Argo CD demo |
| 21 | Final DevOps Project | [session21-final-devops-project](session21-final-devops-project/) | End-to-end project with troubleshooting challenge |

## GitHub Actions workflows

GitHub only runs workflows from the repository root, so the pipelines for sessions
16, 17 and 21 are also registered in [.github/workflows/](../.github/workflows/) with
path filters that trigger them only when the matching session folder changes.

## Local tooling used

- macOS (Apple Silicon), zsh/bash
- Docker and Kubernetes (k3s) via Colima, kubectl, Helm, kind
- Terraform 1.16 (validate/plan only; no AWS account was used)
- Python 3.12, Node 22, Java 21
