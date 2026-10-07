# Session 01 – DevOps Engineer Roadmap
Student: Om Malviya | Enrollment No: 24BCS10448

Session 1 has no formal homework task in the spec. The course folder
(`session1-devops-engineer-roadmap/`) contains `session1.md` (a title line) and
`devops1-83.pdf`, which is a 13-page set of handwritten whiteboard slides. These are my
study notes from those slides, expanded with what I read in the official roadmaps.

## Task 1: Notes from the session slides

The whiteboard slides covered, in order:

1. **Monolithic vs Microservice architecture**
2. **DevOps = Dev + Ops**
3. **Tools in DevOps** (13 items, numbered on the board)
4. **DevOps lifecycle** (Plan → Code → Build → Test → Release → Deploy → Operate → Monitor)
5. **Job roles** (DevOps, DevSecOps, Platform, SRE, Cloud, Solution Architect, AIOps, MLOps, AI Cloud Engineer)
6. **AI ⊃ ML ⊃ DL** diagram
7. A quiz: *"To build a College Placement Application, which architecture will you use?"* — answer circled: **Microservice**.

### Monolith vs Microservice (slide 2)

| Monolith | Microservice |
|---|---|
| Simple to start | More operational complexity |
| Complex, delayed deployment (one big release) | Easily deployable (each service ships on its own) |
| One common codebase | Micro-components, one per feature |
| Tightly coupled | Loosely coupled |

My take: a monolith is the right first choice for a tiny app or a prototype. As soon as several
teams work on the same product, or parts of it need to scale independently (e.g. the placement
portal's "notifications" service vs its "student profile" service), microservices pay off even
though they need more DevOps work (containers, orchestration, CI/CD per service, observability).
That is exactly why the session ties the architecture discussion to DevOps.

## Task 2: What is DevOps?

DevOps is **Development + Operations**: a culture and a set of practices that remove the wall
between the people who write software and the people who run it. Instead of "dev throws a
release over the wall and ops keeps it alive", one pipeline takes code from a commit to
production, with automation, shared ownership and fast feedback.

Key ideas I noted:

- **Culture**: shared responsibility, blameless post-mortems, "you build it, you run it".
- **Automation**: everything repeatable is scripted (builds, tests, deployments, infrastructure).
- **Lean / small batches**: ship small changes often; small changes are easy to debug and roll back.
- **Measurement**: metrics, logs and traces tell us whether a change helped or hurt.
- **Sharing**: Git as the single source of truth for code *and* infrastructure.

CI vs CD as drawn on the slide:

- **CI – Continuous Integration**: every push is built and tested automatically.
- **CD – Continuous Delivery**: every good build is *ready* to deploy; a human gives a manual approval.
- **CD – Continuous Deployment**: every good build *is* deployed automatically, no manual gate.

## Task 3: DevOps lifecycle

```text
          ┌────────┐   ┌──────┐   ┌───────┐   ┌──────┐
   ┌─────▶│  Plan  ├──▶│ Code ├──▶│ Build ├──▶│ Test ├─────┐
   │      └────────┘   └──────┘   └───────┘   └──────┘     │
   │                                                       ▼
┌──┴──────┐   ┌─────────┐   ┌────────┐   ┌─────────┐
│ Monitor │◀──┤ Operate │◀──┤ Deploy │◀──┤ Release │
└─────────┘   └─────────┘   └────────┘   └─────────┘
   (feedback from Monitor flows back into Plan – the "infinity loop")
```

| Phase | What happens | Typical tools |
|---|---|---|
| Plan | Requirements, backlog, sprint planning | Jira, GitHub Issues/Projects |
| Code | Write code, review via pull requests | Git, GitHub/GitLab, VS Code |
| Build | Compile, package, build container image | Maven/Gradle, npm, Docker |
| Test | Unit, integration, security scans | JUnit, pytest, SonarQube, Trivy |
| Release | Version, tag, store artefact | GitHub Releases, Docker Hub/ECR, Helm charts |
| Deploy | Roll out to environments | Kubernetes, Helm, Argo CD, Terraform |
| Operate | Keep it running, scale, patch | Kubernetes, Ansible, cloud consoles |
| Monitor | Metrics, logs, alerts, traces | Prometheus, Grafana, Loki/ELK, Jaeger |

## Task 4: DevOps engineer roadmap

The order below is the order the course follows (session folders in brackets).

| # | Stage | Why it matters | Key tools / topics | Course |
|---|---|---|---|---|
| 1 | **Linux** – "heart of DevOps" (slide) | Almost every server, container and CI runner is Linux | shell, files/permissions, users, processes, systemd, journalctl, package managers | session2 |
| 2 | **Scripting** | Automate the boring parts; glue tools together | Bash (variables, loops, `read -p`, redirection), Python (slide: Python → Go next) | session3, session21 |
| 3 | **Networking** | Everything talks over the network: pods, services, load balancers | TCP/UDP, OSI layers, IP/subnetting/CIDR, DNS, HTTP, `ping`, `dig`, `curl`, `ss` | session4 |
| 4 | **Git & GitHub** | Version control is the source of truth for code and infra | clone, branch, commit, merge, rebase, cherry-pick, pull requests | session5 |
| 5 | **Docker** | Package the app with its dependencies once, run anywhere | Dockerfile, images, containers, multi-stage builds, networks, volumes | session6-7, session8 |
| 6 | **Kubernetes** | Run containers at scale with self-healing and rolling updates | Pod, ReplicaSet, Deployment, StatefulSet, Service, Ingress, ConfigMap/Secret, Volume, HPA, probes, Helm | session9–15 |
| 7 | **CI/CD** | Automate build → test → deploy on every commit | GitHub Actions (workflows, jobs, steps, runners, secrets, artefacts), Jenkins | session16, session17 |
| 8 | **IaC** | Infrastructure described in code is reviewable, repeatable and versioned | Terraform (providers, resources, variables, state), Ansible (config management) | session18, session19 |
| 9 | **Cloud** | Where the infrastructure actually runs | AWS (IAM, EC2, S3, VPC, RDS/DynamoDB), Azure, GCP, Oracle Cloud | session18, session19 |
| 10 | **Monitoring & observability** | Know the system is healthy before users complain | Prometheus (metrics), Grafana (dashboards), Loki/ELK (logs), Jaeger/Tempo (traces), alerting | session20 |
| 11 | **GitOps** | Git is the desired state; a controller reconciles the cluster to it | Argo CD, Flux | session20 |
| + | **DevSecOps** (slide item 13) | Shift security left into the pipeline | SonarQube (SAST), OWASP ZAP (DAST), Trivy (scan Docker images / SCA), secret scanning, security gates | session17 |

### Tools listed on the whiteboard (slide numbering)

1. Git & GitHub · 2. Docker · 3. Python (→ Go later) · 4. Linux – heart of DevOps ·
5. Networking – TCP/UDP, OSI layers · 6. CI/CD – CI, Continuous Deployment vs Continuous Delivery (manual approval) ·
7. Cloud – AWS, Azure, Oracle, GCP · 8. Kubernetes (K8s) – Pod, ReplicaSet, StatefulSet, Volume ·
9. Terraform – infra provisioner · 10. Ansible · 11. Monitoring – Grafana (dashboard), Prometheus ·
12. GitOps · 13. SecOps / DevSecOps – SonarQube (SAST), DAST, OWASP, Trivy (scan the Docker image).

### Job roles (slides 10–11)

DevOps Engineer · DevSecOps Engineer · Platform Engineer · SRE (Site Reliability Engineer, ~4 YOE) ·
Cloud Engineer · Solution Architect (~5 YOE) · AIOps Engineer · MLOps Engineer · AI Cloud Engineer.
The AI ⊃ ML ⊃ DL rings on slide 12 were drawn to explain where the AIOps/MLOps roles sit.

## Task 5: What I learned

- DevOps is not a tool or a job title first; it is a way of working. The tools (Docker, Kubernetes,
  Terraform, GitHub Actions) exist to automate the lifecycle loop above.
- Linux and networking are the foundation; every later stage (containers, clusters, cloud) is
  "Linux boxes talking over IP", so I should be comfortable in a shell before touching Kubernetes.
- CI and CD are different: CI is about integrating and testing often; CD is about being able to
  (delivery) or actually (deployment) ship every green build.
- The monolith → microservice shift is what makes containers and orchestration necessary; the
  placement-portal quiz made that concrete for me.
- Security is part of the pipeline (DevSecOps), not a review at the end: SAST on code, scanning
  on images, gates that fail the build.
- The roadmap is cumulative. My plan for the course is Linux → Bash → networking → Git → Docker →
  Kubernetes → GitHub Actions → Terraform/AWS → Prometheus/Grafana → Argo CD, which matches the
  session order of this repository.

## Screenshots

No commands were required for this session, so there are no terminal outputs standing in for
screenshots. The slide content summarised above was read from
`session1-devops-engineer-roadmap/devops1-83.pdf` (13 pages).

## Deliverables

- `homework/session01-devops-roadmap/README.md` – study notes: what DevOps is, lifecycle, roadmap with tools per stage, job roles, and what I learned.
