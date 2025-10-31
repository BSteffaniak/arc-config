# Actions Runner Controller (ARC) Setup Guide

This directory contains configuration for running GitHub Actions self-hosted runners using Actions Runner Controller (ARC) on Kubernetes.

## Prerequisites

- Docker Desktop (or Docker Engine on Linux)
- kind (Kubernetes in Docker)
- helm
- kubectl
- GitHub App credentials (App ID, Installation ID, Private Key)

## Initial Setup

### 1. Create GitHub App

1. Go to Settings → Developer settings → GitHub Apps → "New GitHub App"
2. Fill in:
   - **Name**: "ARC Runners" (or any name)
   - **Homepage URL**: `https://github.com`
   - **Webhook**: Uncheck "Active"
3. **Repository permissions**:
   - Actions: Read & write
   - Administration: Read & write
   - Checks: Read & write
4. Click "Create GitHub App"
5. **Generate private key**: Scroll down → "Generate a private key" → saves `.pem` file
6. **Install app**: "Install App" (left sidebar) → Install → Select repositories
7. **Note these values**:
   - **App ID**: shown on app settings page
   - **Installation ID**: in URL after install (`https://github.com/settings/installations/XXXXX`)
   - **Private key**: the `.pem` file downloaded

### 2. Create kind Cluster

```bash
kind create cluster --name arc
```

### 3. Install ARC Controller

```bash
helm install arc \
  --namespace arc-systems \
  --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
```

### 4. Create Kubernetes Secret

```bash
kubectl create namespace arc-runners

kubectl create secret generic github-secret \
  --namespace arc-runners \
  --from-literal=github_app_id='YOUR_APP_ID' \
  --from-literal=github_app_installation_id='YOUR_INSTALLATION_ID' \
  --from-file=github_app_private_key=/path/to/your-private-key.pem
```

## Installing Runner Scale Sets

### macOS

```bash
helm install mac-mini-runners \
  --namespace arc-runners \
  -f arc-values.yaml \
  --set githubConfigUrl="https://github.com/YOUR_USER/YOUR_REPO" \
  --set githubConfigSecret=github-secret \
  --set cargoCachePath=/Users/USERNAME/.cargo-cache \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

**Recommended cache path**: `/Users/USERNAME/.cargo-cache`

### Ubuntu/Linux

```bash
helm install ubuntu-runners \
  --namespace arc-runners \
  -f arc-values.yaml \
  --set githubConfigUrl="https://github.com/YOUR_USER/YOUR_REPO" \
  --set githubConfigSecret=github-secret \
  --set cargoCachePath=/home/USERNAME/.cargo-cache \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

**Recommended cache path**: `/home/USERNAME/.cargo-cache`

### Windows (Future Use)

```bash
helm install windows-runners \
  --namespace arc-runners \
  -f arc-values-windows.yaml \
  --set githubConfigUrl="https://github.com/YOUR_USER/YOUR_REPO" \
  --set githubConfigSecret=github-secret \
  --set cargoCachePath=C:\cargo-cache \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

**Note**: Windows runners in kind require additional setup and may be better run directly on Windows hosts.

## Configuring Runner Scale Settings

You can configure min/max runners when installing or upgrading:

```bash
helm upgrade mac-mini-runners \
  --namespace arc-runners \
  --reuse-values \
  --set minRunners=1 \
  --set maxRunners=5 \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

- `minRunners`: Minimum runners always running (default: 0)
- `maxRunners`: Maximum concurrent runners (default: unlimited)

## Using Runners in Workflows

Reference the runner by its helm release name:

```yaml
jobs:
  build-mac:
    runs-on: mac-mini-runners
    steps:
      - uses: actions/checkout@v4
      - run: cargo build

  build-ubuntu:
    runs-on: ubuntu-runners
    steps:
      - uses: actions/checkout@v4
      - run: cargo build
```

## Verification

Check that runners are registered:

```bash
# Check controller is running
kubectl get pods -n arc-systems

# Check listener pod is running
kubectl get pods -n arc-runners

# View controller logs
kubectl logs -n arc-systems -l app.kubernetes.io/name=gha-runner-scale-set-controller

# View listener logs
kubectl logs -n arc-runners -l app.kubernetes.io/component=runner-scale-set-listener
```

Verify in GitHub:
- Go to repo → Settings → Actions → Runners
- You should see your runner scale sets listed

## Cargo Cache Configuration

The configuration templates (`arc-values.yaml` and `arc-values-windows.yaml`) include shared Cargo registry cache setup. This prevents redundant dependency downloads across runner pods on the same machine.

### How it works:

- A directory on your host machine is mounted into each runner pod
- Cargo downloads dependencies to this shared location
- All runner pods on the same machine reuse the same cache
- Cache persists across runner pod restarts

### Cache locations:

The `cargoCachePath` parameter should point to a persistent directory on your host:
- **macOS**: `/Users/USERNAME/.cargo-cache`
- **Linux**: `/home/USERNAME/.cargo-cache`
- **Windows**: `C:\cargo-cache`

## Troubleshooting

### No listener pod appearing

Check controller logs:
```bash
kubectl logs -n arc-systems -l app.kubernetes.io/name=gha-runner-scale-set-controller
```

### Runner not appearing in GitHub

1. Verify githubConfigUrl is correct (must match exact repo URL)
2. Check GitHub App has correct permissions and is installed on the repo
3. Check listener pod logs for authentication errors

### Runners not scaling up

1. Check that jobs are using the correct `runs-on` label
2. Verify `maxRunners` isn't set too low
3. Check listener pod logs for errors

## Updating Configuration

To update an existing runner scale set:

```bash
helm upgrade mac-mini-runners \
  --namespace arc-runners \
  --reuse-values \
  -f arc-values.yaml \
  --set cargoCachePath=/Users/USERNAME/.cargo-cache \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

## Cleanup

To remove a runner scale set:

```bash
helm uninstall mac-mini-runners --namespace arc-runners
```

To remove the entire ARC installation:

```bash
helm uninstall arc --namespace arc-systems
kubectl delete namespace arc-systems
kubectl delete namespace arc-runners
kind delete cluster --name arc
```
