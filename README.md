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

### 5. Download Chart Dependencies

Before installing runner scale sets, download the chart dependencies:

**For Linux/macOS runners:**
```bash
cd arc-chart
helm dependency update
cd ..
```

**For Windows runners (future use):**
```bash
cd arc-chart-windows
helm dependency update
cd ..
```

## Installing Runner Scale Sets

This setup uses Helm wrapper charts that allow parameterized cargo cache paths while keeping configuration in version control.

### macOS

**First time installation:**
```bash
helm install mac-mini-runners ./arc-chart \
  --namespace arc-runners \
  --set gha-runner-scale-set.githubConfigUrl="https://github.com/YOUR_USER/YOUR_REPO" \
  --set gha-runner-scale-set.githubConfigSecret=github-secret \
  --set cargoCachePath=/Users/$(whoami)/.cargo-cache
```

**Updating existing installation:**
```bash
helm upgrade mac-mini-runners ./arc-chart \
  --namespace arc-runners \
  --reuse-values \
  --set cargoCachePath=/Users/$(whoami)/.cargo-cache
```

**Recommended cache path**: `/Users/USERNAME/.cargo-cache`

### Ubuntu/Linux

**First time installation:**
```bash
helm install ubuntu-runners ./arc-chart \
  --namespace arc-runners \
  --set gha-runner-scale-set.githubConfigUrl="https://github.com/YOUR_USER/YOUR_REPO" \
  --set gha-runner-scale-set.githubConfigSecret=github-secret \
  --set cargoCachePath=/home/$(whoami)/.cargo-cache
```

**Updating existing installation:**
```bash
helm upgrade ubuntu-runners ./arc-chart \
  --namespace arc-runners \
  --reuse-values \
  --set cargoCachePath=/home/$(whoami)/.cargo-cache
```

**Recommended cache path**: `/home/USERNAME/.cargo-cache`

### Windows (Future Use)

**First time installation:**
```bash
helm install windows-runners ./arc-chart-windows \
  --namespace arc-runners \
  --set gha-runner-scale-set.githubConfigUrl="https://github.com/YOUR_USER/YOUR_REPO" \
  --set gha-runner-scale-set.githubConfigSecret=github-secret \
  --set cargoCachePath=C:\cargo-cache
```

**Updating existing installation:**
```bash
helm upgrade windows-runners ./arc-chart-windows \
  --namespace arc-runners \
  --reuse-values \
  --set cargoCachePath=C:\cargo-cache
```

**Note**: Windows runners in kind require additional setup and may be better run directly on Windows hosts.

## Chart Structure

This setup uses wrapper Helm charts to enable templated configuration:

```
act/
├── arc-chart/              # Linux/macOS runner chart
│   ├── Chart.yaml         # Defines dependency on ARC
│   ├── values.yaml        # Default values with cargo cache config
│   └── templates/
│       └── _helpers.tpl   # Template helpers
├── arc-chart-windows/     # Windows runner chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       └── _helpers.tpl
└── README.md
```

The wrapper charts:
- Reference the official ARC chart as a dependency
- Allow parameterized `cargoCachePath` via `--set`
- Keep machine-specific paths out of version control
- Share configuration across Linux/macOS or Windows

## Configuring Runner Scale Settings

You can configure min/max runners when installing or upgrading:

```bash
helm upgrade mac-mini-runners ./arc-chart \
  --namespace arc-runners \
  --reuse-values \
  --set gha-runner-scale-set.minRunners=1 \
  --set gha-runner-scale-set.maxRunners=5
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

The wrapper charts include shared Cargo registry cache setup. This prevents redundant dependency downloads across runner pods on the same machine.

### How it works:

- A directory on your host machine is mounted into each runner pod at `/usr/local/cargo/registry`
- Cargo downloads dependencies to this shared location
- All runner pods on the same machine reuse the same cache
- Cache persists across runner pod restarts

### Cache locations:

The `cargoCachePath` parameter should point to a persistent directory on your host:
- **macOS**: `/Users/USERNAME/.cargo-cache`
- **Linux**: `/home/USERNAME/.cargo-cache`
- **Windows**: `C:\cargo-cache`

### Why use wrapper charts?

This approach allows you to:
1. Keep chart configuration in git (the `arc-chart/` directories)
2. Parameterize machine-specific paths (via `--set cargoCachePath=...`)
3. Share the same chart template across multiple machines
4. Use proper Helm templating syntax

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

### Chart dependency errors

If you see errors about missing dependencies, run:
```bash
cd arc-chart
helm dependency update
```

## Updating Configuration

To update an existing runner scale set with new settings:

```bash
helm upgrade mac-mini-runners ./arc-chart \
  --namespace arc-runners \
  --reuse-values \
  --set cargoCachePath=/Users/USERNAME/.cargo-cache \
  --set gha-runner-scale-set.minRunners=2
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
