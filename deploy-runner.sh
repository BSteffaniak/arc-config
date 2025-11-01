#!/bin/bash

set -e

# Script to deploy or upgrade GitHub Actions Runner Controller (ARC) runners
# Handles Linux, macOS, and Windows (Git Bash/MSYS) environments

# Variables - all start as empty
RELEASE_NAME=""
MODE="install"
GITHUB_URL=""
REPO_OWNER=""
REPO_NAME=""
CARGO_CACHE_PATH=""
GIT_CACHE_PATH=""
MIN_RUNNERS=""
MAX_RUNNERS=""
NAMESPACE="arc-runners"
DRY_RUN="false"
FORCE_MODE="false"

# Track what was explicitly provided
PROVIDED_GITHUB_URL=false
PROVIDED_REPO_OWNER=false
PROVIDED_REPO_NAME=false
PROVIDED_CARGO_CACHE=false
PROVIDED_GIT_CACHE=false
PROVIDED_MIN_RUNNERS=false
PROVIDED_MAX_RUNNERS=false

# OS Detection
OS=""
CHART_DIR=""
DEFAULT_CARGO_CACHE=""
DEFAULT_GIT_CACHE=""

detect_os() {
  case "$(uname -s)" in
    Linux*)
      OS="linux"
      DEFAULT_CARGO_CACHE="/home/$(whoami)/.cargo-cache"
      DEFAULT_GIT_CACHE="/var/lib/arc-runner/git-cache"
      CHART_DIR="arc-chart"
      ;;
    Darwin*)
      OS="macos"
      DEFAULT_CARGO_CACHE="/Users/$(whoami)/.cargo-cache"
      DEFAULT_GIT_CACHE="/Users/$(whoami)/.git-cache"
      CHART_DIR="arc-chart"
      ;;
    CYGWIN*|MINGW*|MSYS*)
      OS="windows"
      DEFAULT_CARGO_CACHE="C:\\cargo-cache"
      DEFAULT_GIT_CACHE="C:\\arc-runner\\git-cache"
      CHART_DIR="arc-chart-windows"
      ;;
    *)
      echo "❌ Error: Unsupported operating system: $(uname -s)"
      exit 1
      ;;
  esac
}

detect_os_name() {
  echo "$OS"
}

show_help() {
  cat << EOF
🚀 ARC Runner Deployment Script

Usage: 
  $0 <release-name> [--upgrade] [options]

INSTALL MODE (default):
  Required:
    <release-name>              Helm release name (e.g., mac-mini-runners)
    --github-url URL            GitHub repository URL
    --repo-owner OWNER          GitHub repository owner
    --repo-name NAME            GitHub repository name
  
  Optional:
    --cargo-cache-path PATH     Cargo cache path (default: OS-specific)
    --git-cache-path PATH       Git cache path (default: OS-specific)
    --min-runners NUM           Minimum runners always running (default: 0)
    --max-runners NUM           Maximum concurrent runners (default: unlimited)
    --force                     Force reinstall (uninstall + install)
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
    --min-runners NUM           Update minimum runners
    --max-runners NUM           Update maximum runners
    --force                     Force reset all values (requires all config)
    --namespace NS              Kubernetes namespace (default: arc-runners)
    --dry-run                   Show command without executing

Detected OS: $OS
Default cargo cache: $DEFAULT_CARGO_CACHE
Default git cache: $DEFAULT_GIT_CACHE

Examples:
  # Install new runner (all required args)
  $0 mac-mini-runners \\
    --github-url https://github.com/MoosicBox/MoosicBox \\
    --repo-owner MoosicBox \\
    --repo-name MoosicBox

  # Install with custom cache paths
  $0 ubuntu-runners \\
    --github-url https://github.com/MoosicBox/MoosicBox \\
    --repo-owner MoosicBox \\
    --repo-name MoosicBox \\
    --cargo-cache-path /mnt/ssd/cargo \\
    --git-cache-path /mnt/ssd/git

  # Upgrade existing (no args = no changes)
  $0 mac-mini-runners --upgrade

  # Install with min/max runners
  $0 mac-mini-runners \\
    --github-url https://github.com/MoosicBox/MoosicBox \\
    --repo-owner MoosicBox \\
    --repo-name MoosicBox \\
    --min-runners 1 \\
    --max-runners 5

  # Upgrade and change cache paths only
  $0 mac-mini-runners --upgrade \\
    --cargo-cache-path /new/cargo/path \\
    --git-cache-path /new/git/path

  # Upgrade and change repo
  $0 mac-mini-runners --upgrade \\
    --repo-owner NewOrg \\
    --repo-name NewRepo

  # Upgrade and set min runners
  $0 mac-mini-runners --upgrade \\
    --min-runners 2

  # Force reinstall (uninstall + install)
  $0 mac-mini-runners --force \\
    --github-url https://github.com/MoosicBox/MoosicBox \\
    --repo-owner MoosicBox \\
    --repo-name MoosicBox \\
    --min-runners 1

  # Force upgrade (reset all values)
  $0 mac-mini-runners --upgrade --force \\
    --github-url https://github.com/MoosicBox/MoosicBox \\
    --repo-owner MoosicBox \\
    --repo-name MoosicBox \\
    --min-runners 1

  # Dry run to see what would happen
  $0 mac-mini-runners --upgrade --dry-run

EOF
}

parse_arguments() {
  if [ $# -eq 0 ]; then
    show_help
    exit 1
  fi
  
  # Check for help first before processing positional args
  for arg in "$@"; do
    if [ "$arg" = "--help" ] || [ "$arg" = "-h" ]; then
      show_help
      exit 0
    fi
  done
  
  # First positional arg is release name
  RELEASE_NAME="$1"
  shift
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      --upgrade)
        MODE="upgrade"
        shift
        ;;
      --github-url)
        if [ -z "$2" ]; then
          echo "❌ Error: --github-url requires a value"
          exit 1
        fi
        GITHUB_URL="$2"
        PROVIDED_GITHUB_URL=true
        shift 2
        ;;
      --repo-owner)
        if [ -z "$2" ]; then
          echo "❌ Error: --repo-owner requires a value"
          exit 1
        fi
        REPO_OWNER="$2"
        PROVIDED_REPO_OWNER=true
        shift 2
        ;;
      --repo-name)
        if [ -z "$2" ]; then
          echo "❌ Error: --repo-name requires a value"
          exit 1
        fi
        REPO_NAME="$2"
        PROVIDED_REPO_NAME=true
        shift 2
        ;;
      --cargo-cache-path)
        if [ -z "$2" ]; then
          echo "❌ Error: --cargo-cache-path requires a value"
          exit 1
        fi
        CARGO_CACHE_PATH="$2"
        PROVIDED_CARGO_CACHE=true
        shift 2
        ;;
      --git-cache-path)
        if [ -z "$2" ]; then
          echo "❌ Error: --git-cache-path requires a value"
          exit 1
        fi
        GIT_CACHE_PATH="$2"
        PROVIDED_GIT_CACHE=true
        shift 2
        ;;
      --min-runners)
        if [ -z "$2" ]; then
          echo "❌ Error: --min-runners requires a value"
          exit 1
        fi
        MIN_RUNNERS="$2"
        PROVIDED_MIN_RUNNERS=true
        shift 2
        ;;
      --max-runners)
        if [ -z "$2" ]; then
          echo "❌ Error: --max-runners requires a value"
          exit 1
        fi
        MAX_RUNNERS="$2"
        PROVIDED_MAX_RUNNERS=true
        shift 2
        ;;
      --namespace)
        if [ -z "$2" ]; then
          echo "❌ Error: --namespace requires a value"
          exit 1
        fi
        NAMESPACE="$2"
        shift 2
        ;;
      --force)
        FORCE_MODE="true"
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        echo "❌ Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

validate_arguments() {
  if [ -z "$RELEASE_NAME" ]; then
    echo "❌ Error: Release name is required"
    exit 1
  fi
  
  if [ "$MODE" = "install" ]; then
    # Install requires repo configuration
    if [ "$PROVIDED_GITHUB_URL" = "false" ]; then
      echo "❌ Error: --github-url is required for install mode"
      echo "   Example: --github-url https://github.com/MoosicBox/MoosicBox"
      exit 1
    fi
    
    if [ "$PROVIDED_REPO_OWNER" = "false" ]; then
      echo "❌ Error: --repo-owner is required for install mode"
      echo "   Example: --repo-owner MoosicBox"
      exit 1
    fi
    
    if [ "$PROVIDED_REPO_NAME" = "false" ]; then
      echo "❌ Error: --repo-name is required for install mode"
      echo "   Example: --repo-name MoosicBox"
      exit 1
    fi
    
    # Set cache path defaults if not provided
    if [ "$PROVIDED_CARGO_CACHE" = "false" ]; then
      CARGO_CACHE_PATH="$DEFAULT_CARGO_CACHE"
      PROVIDED_CARGO_CACHE=true
      echo "ℹ️  Using default cargo cache: $CARGO_CACHE_PATH"
    fi
    
    if [ "$PROVIDED_GIT_CACHE" = "false" ]; then
      GIT_CACHE_PATH="$DEFAULT_GIT_CACHE"
      PROVIDED_GIT_CACHE=true
      echo "ℹ️  Using default git cache: $GIT_CACHE_PATH"
    fi
  fi
  
  # For upgrade mode, all repo/cache args are optional
  # Only validate they're provided together if any are provided
  if [ "$MODE" = "upgrade" ]; then
    # Force mode with upgrade requires all config (like install mode)
    if [ "$FORCE_MODE" = "true" ]; then
      echo "ℹ️  Force mode: All values will be reset!"
      echo "   You must provide all required configuration."
      echo ""
      
      if [ "$PROVIDED_GITHUB_URL" = "false" ]; then
        echo "❌ Error: --github-url is required when using --force --upgrade"
        echo "   Force upgrade resets all values, so all config must be provided."
        exit 1
      fi
      
      if [ "$PROVIDED_REPO_OWNER" = "false" ]; then
        echo "❌ Error: --repo-owner is required when using --force --upgrade"
        exit 1
      fi
      
      if [ "$PROVIDED_REPO_NAME" = "false" ]; then
        echo "❌ Error: --repo-name is required when using --force --upgrade"
        exit 1
      fi
      
      # Set cache path defaults if not provided
      if [ "$PROVIDED_CARGO_CACHE" = "false" ]; then
        CARGO_CACHE_PATH="$DEFAULT_CARGO_CACHE"
        PROVIDED_CARGO_CACHE=true
        echo "ℹ️  Using default cargo cache: $CARGO_CACHE_PATH"
      fi
      
      if [ "$PROVIDED_GIT_CACHE" = "false" ]; then
        GIT_CACHE_PATH="$DEFAULT_GIT_CACHE"
        PROVIDED_GIT_CACHE=true
        echo "ℹ️  Using default git cache: $GIT_CACHE_PATH"
      fi
    else
      # Normal upgrade mode - partial updates allowed
      if [ "$PROVIDED_REPO_OWNER" = "true" ] && [ "$PROVIDED_REPO_NAME" = "false" ]; then
        echo "❌ Error: --repo-name is required when --repo-owner is provided"
        exit 1
      fi
      
      if [ "$PROVIDED_REPO_NAME" = "true" ] && [ "$PROVIDED_REPO_OWNER" = "false" ]; then
        echo "❌ Error: --repo-owner is required when --repo-name is provided"
        exit 1
      fi
      
      # Auto-construct github-url if owner and name provided but not url
      if [ "$PROVIDED_REPO_OWNER" = "true" ] && [ "$PROVIDED_REPO_NAME" = "true" ] && [ "$PROVIDED_GITHUB_URL" = "false" ]; then
        GITHUB_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}"
        PROVIDED_GITHUB_URL=true
        echo "ℹ️  Auto-constructed GitHub URL: $GITHUB_URL"
      fi
    fi
  fi
}

validate_environment() {
  # Check helm
  if ! command -v helm &> /dev/null; then
    echo "❌ Error: helm not found. Install: https://helm.sh/docs/intro/install/"
    exit 1
  fi
  
  # Check kubectl
  if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl not found. Install: https://kubernetes.io/docs/tasks/tools/"
    exit 1
  fi
  
  # Check namespace exists
  if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "❌ Error: Namespace '$NAMESPACE' not found"
    echo "   Create it with: kubectl create namespace $NAMESPACE"
    exit 1
  fi
  
  # Check chart directory exists
  if [ ! -d "$CHART_DIR" ]; then
    echo "❌ Error: Chart directory '$CHART_DIR' not found"
    echo "   Are you running this script from the correct directory?"
    exit 1
  fi
  
  # Check chart dependencies
  if [ ! -d "$CHART_DIR/charts" ]; then
    echo "⚠️  Chart dependencies not found. Running 'helm dependency update'..."
    (cd "$CHART_DIR" && helm dependency update)
    if [ $? -ne 0 ]; then
      echo "❌ Error: Failed to update chart dependencies"
      exit 1
    fi
  fi
  
  # Check if release exists for upgrade mode
  if [ "$MODE" = "upgrade" ]; then
    if ! helm list -n "$NAMESPACE" | grep -q "^$RELEASE_NAME"; then
      echo "❌ Error: Release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
      echo "   Use install mode instead (remove --upgrade flag)"
      exit 1
    fi
  fi
  
  # Check if release exists for install mode
  if [ "$MODE" = "install" ]; then
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "^$RELEASE_NAME"; then
      if [ "$FORCE_MODE" = "true" ]; then
        # Force mode: uninstall existing release
        echo ""
        echo "⚠️  WARNING: Release '$RELEASE_NAME' already exists and will be DELETED"
        echo "   This is a destructive operation that will:"
        echo "   - Uninstall the existing Helm release"
        echo "   - Delete all runner pods"
        echo "   - Remove all associated resources"
        echo ""
        
        if [ "$DRY_RUN" = "true" ]; then
          echo "🔍 Dry-run mode: Would uninstall '$RELEASE_NAME' here"
        else
          read -p "Type 'yes' to confirm uninstall and reinstall: " -r
          echo
          if [[ ! $REPLY = "yes" ]]; then
            echo "Aborted. You must type 'yes' exactly to proceed with force mode."
            exit 1
          fi
          
          echo "🗑️  Uninstalling existing release..."
          if ! helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"; then
            echo "❌ Error: Failed to uninstall release"
            echo "   You may need to manually cleanup: kubectl get all -n $NAMESPACE"
            exit 1
          fi
          
          echo "⏳ Waiting for cleanup (10 seconds)..."
          sleep 10
          
          # Check if resources still exist
          if kubectl get autoscalingrunnerset "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null; then
            echo "⚠️  Warning: AutoScalingRunnerSet still exists. Waiting longer..."
            sleep 10
          fi
          
          echo "✅ Cleanup complete. Proceeding with fresh install..."
          echo ""
        fi
      else
        echo "❌ Error: Release '$RELEASE_NAME' already exists in namespace '$NAMESPACE'"
        echo "   Use --upgrade to update it, --force to reinstall, or choose a different release name"
        exit 1
      fi
    fi
  fi
}

generate_override_values() {
  local override_file=$(mktemp)
  
  if [ "$OS" = "windows" ]; then
    # Windows-specific configuration
    cat > "$override_file" << 'EOF'
githubRepoOwner: "$REPO_OWNER"
githubRepoName: "$REPO_NAME"

gha-runner-scale-set:
  githubConfigUrl: "$GITHUB_URL"
  githubConfigSecret: github-secret
  minRunners: ${MIN_RUNNERS:-0}
  maxRunners: ${MAX_RUNNERS:-0}
  template:
    spec:
      nodeSelector:
        kubernetes.io/os: windows
      
      initContainers:
      - name: setup-git-cache
        image: mcr.microsoft.com/windows/servercore:ltsc2022
        command:
        - powershell.exe
        - -Command
        - |
          $ErrorActionPreference = "Stop"
          $repoCache = "C:\git-cache\$env:GITHUB_REPO_OWNER\$env:GITHUB_REPO_NAME.git"
          
          New-Item -ItemType Directory -Force -Path (Split-Path $repoCache) | Out-Null
          
          if (Test-Path $repoCache) {
            Push-Location $repoCache
            try {
              git fetch --force --prune origin "+refs/heads/*:refs/heads/*" "+refs/tags/*:refs/tags/*"
            } catch {
              Pop-Location
              Remove-Item -Recurse -Force $repoCache
              git clone --mirror "https://github.com/$env:GITHUB_REPO_OWNER/$env:GITHUB_REPO_NAME.git" $repoCache
            }
            Pop-Location
          } else {
            git clone --mirror "https://github.com/$env:GITHUB_REPO_OWNER/$env:GITHUB_REPO_NAME.git" $repoCache
          }
        env:
        - name: GITHUB_REPO_OWNER
          value: "$REPO_OWNER"
        - name: GITHUB_REPO_NAME
          value: "$REPO_NAME"
        volumeMounts:
        - name: git-cache
          mountPath: C:\git-cache
      
      containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        command: ["C:\\actions-runner\\run.cmd"]
        volumeMounts:
        - name: cargo-cache
          mountPath: C:\Users\ContainerAdministrator\.cargo\registry
        - name: git-cache
          mountPath: C:\git-cache
          readOnly: true
      
      volumes:
      - name: cargo-cache
        hostPath:
          path: "$CARGO_CACHE_PATH"
          type: DirectoryOrCreate
      - name: git-cache
        hostPath:
          path: "$GIT_CACHE_PATH"
          type: DirectoryOrCreate
EOF
  else
    # Linux/macOS configuration
    cat > "$override_file" << 'EOF'
githubRepoOwner: "$REPO_OWNER"
githubRepoName: "$REPO_NAME"

gha-runner-scale-set:
  githubConfigUrl: "$GITHUB_URL"
  githubConfigSecret: github-secret
  minRunners: ${MIN_RUNNERS:-0}
  maxRunners: ${MAX_RUNNERS:-0}
  template:
    spec:
      initContainers:
      - name: setup-git-cache
        image: alpine/git:latest
        command:
        - sh
        - -c
        - |
          REPO_CACHE="/git-cache/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}.git"
          mkdir -p $(dirname $REPO_CACHE)
          
          if [ -d "$REPO_CACHE" ]; then
            cd $REPO_CACHE
            git fetch --force --prune origin "+refs/heads/*:refs/heads/*" "+refs/tags/*:refs/tags/*" || {
              cd / && rm -rf $REPO_CACHE
              git clone --mirror https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}.git $REPO_CACHE
            }
          else
            git clone --mirror https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}.git $REPO_CACHE
          fi
        env:
        - name: GITHUB_REPO_OWNER
          value: "$REPO_OWNER"
        - name: GITHUB_REPO_NAME
          value: "$REPO_NAME"
        volumeMounts:
        - name: git-cache
          mountPath: /git-cache
      
      containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        command: ["/home/runner/run.sh"]
        volumeMounts:
        - name: git-cache
          mountPath: /git-cache
          readOnly: true
        - name: cargo-cache
          mountPath: /cargo-cache
      
      volumes:
      - name: cargo-cache
        hostPath:
          path: "$CARGO_CACHE_PATH"
          type: DirectoryOrCreate
      - name: git-cache
        hostPath:
          path: "$GIT_CACHE_PATH"
          type: DirectoryOrCreate
EOF
  fi
  
  # Now substitute variables in the file
  # Escape backslashes for Windows paths in sed
  local cargo_cache_escaped=$(echo "$CARGO_CACHE_PATH" | sed 's/\\/\\\\/g')
  local git_cache_escaped=$(echo "$GIT_CACHE_PATH" | sed 's/\\/\\\\/g')
  
  sed -i.bak \
    -e "s|\$REPO_OWNER|$REPO_OWNER|g" \
    -e "s|\$REPO_NAME|$REPO_NAME|g" \
    -e "s|\$GITHUB_URL|$GITHUB_URL|g" \
    -e "s|\${MIN_RUNNERS:-0}|${MIN_RUNNERS:-0}|g" \
    -e "s|\${MAX_RUNNERS:-0}|${MAX_RUNNERS:-0}|g" \
    -e "s|\$CARGO_CACHE_PATH|$cargo_cache_escaped|g" \
    -e "s|\$GIT_CACHE_PATH|$git_cache_escaped|g" \
    "$override_file"
  
  rm -f "${override_file}.bak"
  
  echo "$override_file"
}

build_helm_command() {
  local override_file=$(generate_override_values)
  local cmd="helm $MODE $RELEASE_NAME ./$CHART_DIR"
  cmd="$cmd --namespace $NAMESPACE"
  cmd="$cmd -f $override_file"
  
  if [ "$MODE" = "upgrade" ]; then
    if [ "$FORCE_MODE" = "true" ]; then
      cmd="$cmd --reset-values"
    else
      cmd="$cmd --reuse-values"
    fi
  fi
  
  # Return both command and override file path (separated by |)
  echo "$cmd|$override_file"
}

main() {
  echo "🚀 ARC Runner Deployment Script"
  echo "================================"
  echo ""
  
  detect_os
  echo "Detected OS: $OS"
  echo ""
  
  parse_arguments "$@"
  validate_arguments
  validate_environment
  
  echo ""
  echo "📋 Configuration:"
  echo "  Release name: $RELEASE_NAME"
  if [ "$FORCE_MODE" = "true" ]; then
    if [ "$MODE" = "install" ]; then
      echo "  Mode: $MODE (forced - will uninstall if exists)"
    else
      echo "  Mode: $MODE (forced - resetting all values)"
    fi
  else
    echo "  Mode: $MODE"
  fi
  echo "  Namespace: $NAMESPACE"
  echo "  Chart: $CHART_DIR"
  
  if [ "$PROVIDED_GITHUB_URL" = "true" ]; then
    echo "  GitHub URL: $GITHUB_URL"
  fi
  
  if [ "$PROVIDED_REPO_OWNER" = "true" ]; then
    echo "  Repo owner: $REPO_OWNER"
  fi
  
  if [ "$PROVIDED_REPO_NAME" = "true" ]; then
    echo "  Repo name: $REPO_NAME"
  fi
  
  if [ "$PROVIDED_CARGO_CACHE" = "true" ]; then
    echo "  Cargo cache: $CARGO_CACHE_PATH"
  fi
  
  if [ "$PROVIDED_GIT_CACHE" = "true" ]; then
    echo "  Git cache: $GIT_CACHE_PATH"
  fi
  
  if [ "$PROVIDED_MIN_RUNNERS" = "true" ]; then
    echo "  Min runners: $MIN_RUNNERS"
  fi
  
  if [ "$PROVIDED_MAX_RUNNERS" = "true" ]; then
    echo "  Max runners: $MAX_RUNNERS"
  fi
  
  echo ""
  
  # Build helm command and get override file path
  HELM_CMD_AND_FILE=$(build_helm_command)
  HELM_CMD="${HELM_CMD_AND_FILE%|*}"
  OVERRIDE_FILE="${HELM_CMD_AND_FILE#*|}"
  
  # Setup cleanup trap to ensure temp file is deleted
  trap "rm -f '$OVERRIDE_FILE'" EXIT INT TERM
  
  echo "📦 Helm command:"
  echo "$HELM_CMD"
  echo ""
  
  if [ "$DRY_RUN" = "true" ]; then
    echo "🔍 Dry-run mode - not executing"
    echo ""
    echo "📄 Generated override file content:"
    cat "$OVERRIDE_FILE"
    rm -f "$OVERRIDE_FILE"
    exit 0
  fi
  
  read -p "Execute this command? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    rm -f "$OVERRIDE_FILE"
    exit 0
  fi
  
  echo "⚙️  Executing..."
  eval "$HELM_CMD"
  
  if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Success! Runner deployed."
    echo ""
    echo "📊 Check status:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo ""
    echo "📝 View logs:"
    echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=runner-scale-set-listener"
    echo ""
    echo "🔍 View runner in GitHub:"
    echo "  Go to repo → Settings → Actions → Runners"
  else
    echo ""
    echo "❌ Deployment failed. Check output above for errors."
    rm -f "$OVERRIDE_FILE"
    exit 1
  fi
  
  # Cleanup (also handled by trap)
  rm -f "$OVERRIDE_FILE"
}

main "$@"
