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

The deployment script will automatically download chart dependencies if needed, but you can do it manually:

```bash
cd arc-chart
helm dependency update
cd ..

# For Windows (if needed)
cd arc-chart-windows
helm dependency update
cd ..
```

## Deploying Runners

This repository includes a unified deployment script (`deploy-runner.sh`) that handles all the complexity of deploying runners across Linux, macOS, and Windows environments.

### Features

✅ **Auto OS detection** - Detects Linux, macOS, or Windows (Git Bash/MSYS)
✅ **Platform-specific configs** - Automatically generates correct YAML for each OS
✅ **Smart defaults** - OS-specific cache paths and runner configurations
✅ **Install or upgrade** - Single script handles both modes
✅ **Validation** - Pre-flight checks before execution
✅ **Conditional arguments** - Only updates values you explicitly provide
✅ **Interactive confirmation** - Shows command before executing
✅ **Dry-run mode** - See what would happen without executing

### Quick Start

#### Install a new runner:

```bash
./deploy-runner.sh mac-mini-runners \
  --github-url https://github.com/MoosicBox/MoosicBox \
  --repo-owner MoosicBox \
  --repo-name MoosicBox
```

This will:
- Use OS-appropriate default cache paths
- Create a new Helm release named `mac-mini-runners`
- Configure Git repository caching for faster checkouts
- Configure Cargo dependency caching

#### Upgrade an existing runner:

```bash
# Upgrade without changing anything
./deploy-runner.sh mac-mini-runners --upgrade

# Upgrade and change cache paths
./deploy-runner.sh mac-mini-runners --upgrade \
  --cargo-cache-path /new/path/cargo \
  --git-cache-path /new/path/git

# Upgrade and change repository
./deploy-runner.sh mac-mini-runners --upgrade \
  --repo-owner NewOrg \
  --repo-name NewRepo
```

### Script Usage

```
Usage: 
  ./deploy-runner.sh <release-name> [--upgrade] [options]

INSTALL MODE (default):
  Required:
    <release-name>              Helm release name (e.g., mac-mini-runners)
    --github-url URL            GitHub repository URL
    --repo-owner OWNER          GitHub repository owner
    --repo-name NAME            GitHub repository name
  
  Optional:
    --cargo-cache-path PATH     Cargo cache path (default: OS-specific)
    --git-cache-path PATH       Git cache path (default: OS-specific)
    --namespace NS              Kubernetes namespace (default: arc-runners)
    --dry-run                   Show command without executing

UPGRADE MODE:
  Required:
    <release-name>              Helm release name to upgrade
    --upgrade                   Enable upgrade mode
  
  Optional:
    --github-url URL            Update GitHub repository URL
    --repo-owner OWNER          Update repository owner
    --repo-name NAME            Update repository name
    --cargo-cache-path PATH     Update cargo cache path
    --git-cache-path PATH       Update git cache path
    --namespace NS              Kubernetes namespace (default: arc-runners)
    --dry-run                   Show command without executing
```

### Default Cache Paths

The script automatically sets appropriate default cache paths based on your OS:

- **macOS**: 
  - Cargo: `/Users/USERNAME/.cargo-cache`
  - Git: `/Users/USERNAME/.git-cache`
- **Linux**: 
  - Cargo: `/home/USERNAME/.cargo-cache`
  - Git: `/var/lib/arc-runner/git-cache`
- **Windows** (Git Bash/MSYS): 
  - Cargo: `C:\cargo-cache`
  - Git: `C:\arc-runner\git-cache`

### Examples

**Install on macOS with defaults:**
```bash
./deploy-runner.sh mac-mini-runners \
  --github-url https://github.com/MoosicBox/MoosicBox \
  --repo-owner MoosicBox \
  --repo-name MoosicBox
```

**Install on Ubuntu with custom paths:**
```bash
./deploy-runner.sh ubuntu-runners \
  --github-url https://github.com/MoosicBox/MoosicBox \
  --repo-owner MoosicBox \
  --repo-name MoosicBox \
  --cargo-cache-path /mnt/ssd/cargo-cache \
  --git-cache-path /mnt/ssd/git-cache
```

**Install on Windows:**
```bash
# From Git Bash or MSYS terminal
./deploy-runner.sh windows-runners \
  --github-url https://github.com/MoosicBox/MoosicBox \
  --repo-owner MoosicBox \
  --repo-name MoosicBox

# With custom paths
./deploy-runner.sh windows-runners \
  --github-url https://github.com/MoosicBox/MoosicBox \
  --repo-owner MoosicBox \
  --repo-name MoosicBox \
  --cargo-cache-path "C:\\my-caches\\cargo" \
  --git-cache-path "C:\\my-caches\\git"
```

**Note for Windows:** The script automatically:
- Uses Windows Server Core container for initContainer
- Uses PowerShell scripts instead of bash
- Configures Windows paths (`C:\...`) 
- Adds `nodeSelector` for Windows nodes
- Uses correct runner command (`C:\actions-runner\run.cmd`)

**Upgrade existing runner (no changes):**
```bash
./deploy-runner.sh mac-mini-runners --upgrade
```

**Upgrade and update cache paths:**
```bash
./deploy-runner.sh mac-mini-runners --upgrade \
  --cargo-cache-path /new/cargo/path
```

**Dry-run to preview changes:**
```bash
./deploy-runner.sh mac-mini-runners --upgrade \
  --cargo-cache-path /new/path \
  --dry-run
```

## Chart Structure

```
.
├── arc-chart/              # Linux/macOS runner chart
│   ├── Chart.yaml         # Chart metadata and dependencies
│   ├── values.yaml        # Default configuration values
│   └── charts/            # Downloaded dependencies
├── arc-chart-windows/     # Windows runner chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── charts/
├── deploy-runner.sh       # Unified deployment script
└── README.md
```

The charts are wrapper charts that:
- Reference the official ARC chart as a dependency
- Provide sensible defaults for cache paths
- Include initContainers for Git repository caching
- Support both Linux/macOS and Windows environments

## Configuring Runner Scale Settings

You can configure min/max runners by directly editing the `values.yaml` file or by using helm's `--set` flag:

```bash
# Edit values.yaml
vim arc-chart/values.yaml
# Change minRunners and maxRunners values

# Or override during install/upgrade
./deploy-runner.sh mac-mini-runners --upgrade
# Then manually add --set if needed:
helm upgrade mac-mini-runners ./arc-chart \
  --namespace arc-runners \
  --reuse-values \
  --set gha-runner-scale-set.minRunners=1 \
  --set gha-runner-scale-set.maxRunners=5
```

- `minRunners`: Minimum runners always running (default: 0)
- `maxRunners`: Maximum concurrent runners (default: unlimited)

## Using Runners in Workflows

Reference the runner by its Helm release name:

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

## Cache Configuration

### Cargo Cache

The wrapper charts include shared Cargo registry cache setup to prevent redundant dependency downloads:

- A directory on your host machine is mounted into each runner pod at `/usr/local/cargo/registry`
- Cargo downloads dependencies to this shared location
- All runner pods on the same machine reuse the same cache
- Cache persists across runner pod restarts

### Git Repository Cache

The wrapper charts include Git repository caching to dramatically speed up checkout:

**How it works:**
- Before each runner starts, an initContainer updates a Git mirror cache on the host
- The mirror cache uses `git fetch --force --prune` to handle force pushes gracefully
- The cache is mounted read-only into runner containers
- `actions/checkout@v4` automatically detects and uses the cache via Git's `--reference-if-able`
- Only new/changed Git objects are downloaded
- Full repository history is still available to workflows
- Cache is shared across all runners on the same host

**Platform-specific implementation:**
- **Linux/macOS**: Uses `alpine/git:latest` with bash scripts
- **Windows**: Uses `mcr.microsoft.com/windows/servercore:ltsc2022` with PowerShell scripts
- Both achieve the same result with platform-appropriate tooling

**Benefits:**
- **Faster checkouts**: Only fetch new commits and changed files
- **Reduced bandwidth**: Reuse Git objects (commits, trees, blobs) already cached
- **Force-push safe**: Handles repository force pushes without corruption
- **Pure builds**: Workflows still get full history and clean checkouts
- **Transparent**: No workflow changes needed
- **Cross-platform**: Works on Linux, macOS, and Windows runners

## Troubleshooting

### Script reports missing required arguments

Make sure you provide all required arguments for install mode:
```bash
./deploy-runner.sh my-runner \
  --github-url https://github.com/Owner/Repo \
  --repo-owner Owner \
  --repo-name Repo
```

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

### Git cache not working

1. Check that `githubRepoOwner` and `githubRepoName` are set correctly
2. Verify the initContainer completed successfully: `kubectl get pods -n arc-runners`
3. Check initContainer logs: `kubectl logs -n arc-runners <pod-name> -c setup-git-cache`
4. Ensure the host path for git cache is writable by the runner pods

### Chart dependency errors

The deploy script will automatically update dependencies, but you can manually update:
```bash
cd arc-chart
helm dependency update
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

## Advanced: Direct Helm Usage

If you prefer to use Helm directly instead of the deploy script, you can:

```bash
# Install
helm install mac-mini-runners ./arc-chart \
  --namespace arc-runners \
  --set gha-runner-scale-set.githubConfigUrl="https://github.com/MoosicBox/MoosicBox" \
  --set githubRepoOwner=MoosicBox \
  --set githubRepoName=MoosicBox \
  --set gha-runner-scale-set.template.spec.initContainers[0].env[0].value=MoosicBox \
  --set gha-runner-scale-set.template.spec.initContainers[0].env[1].value=MoosicBox \
  --set gha-runner-scale-set.template.spec.volumes[0].hostPath.path=/Users/me/.cargo-cache \
  --set gha-runner-scale-set.template.spec.volumes[1].hostPath.path=/Users/me/.git-cache

# Upgrade
helm upgrade mac-mini-runners ./arc-chart \
  --namespace arc-runners \
  --reuse-values \
  --set gha-runner-scale-set.template.spec.volumes[0].hostPath.path=/new/path
```

However, the `deploy-runner.sh` script is recommended as it handles all this complexity for you.
