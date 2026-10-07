# gitops-repo (desired state)

This folder plays the role of the GitOps repository. Everything under `apps/`
is the **desired state** of the cluster. Nobody runs `kubectl apply` on these
files by hand; Argo CD watches this path in Git and applies it.

```text
gitops-repo/
└── apps/
    └── demo-app/
        ├── kustomization.yaml   <- Argo CD detects this and renders with kustomize
        ├── namespace.yaml
        ├── deployment.yaml      <- nginx:alpine, replicas: 2
        └── service.yaml
```

The Argo CD `Application` object that points here lives one level up in
`../argocd/application.yaml` on purpose: it is applied once by an admin and
must not be rendered as part of the workload manifests.
