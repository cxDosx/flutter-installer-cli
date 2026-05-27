#!/usr/bin/env bash
#
# One-command installer for a Flutter + Android build environment.
# Targets Debian / Ubuntu / CentOS / RHEL / Rocky / AlmaLinux / Fedora.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-flutter-android.sh)
#   or locally:
#   bash install-flutter-android.sh [OPTIONS]
#
# Options:
#   -y, --non-interactive   Run without prompts; use defaults and skip confirmation.
#       --sdk <version>     Android SDK version (default: 33).
#       --ndk <version>     Android NDK version (default: 28.2.13676358).
#       --flutter <version> Flutter version tag, e.g. 3.24.0 (default: latest stable).
#   -h, --help              Show help and exit.
#
# Installs:
#   - JDK 17
#   - Android command-line tools
#   - Android SDK Platform (user-specified version, default 33)
#   - Android Build Tools (matching the SDK version)
#   - Android NDK (user-specified version, default 28.2.13676358)
#   - Flutter (user-specified version, or latest stable if unspecified)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

DEFAULT_SDK_VERSION="33"
DEFAULT_NDK_VERSION="28.2.13676358"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
FLUTTER_CHANNEL="stable"
FLUTTER_REPO="https://github.com/flutter/flutter.git"

ANDROID_HOME="${HOME}/android-sdk"
FLUTTER_HOME="${HOME}/flutter"

# Runtime state (may be overridden by command-line flags)
NON_INTERACTIVE=false
SDK_VERSION_ARG=""
NDK_VERSION_ARG=""
FLUTTER_VERSION_ARG=""

# ============================================================================
# Helper functions
# ============================================================================

# Colored output (only when stdout is a terminal). Use ANSI-C quoting ($'...')
# so the variables hold the real ESC byte; this lets us use plain `echo` (which
# is portable) instead of relying on `echo -e` to interpret backslash escapes.
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    BOLD=$'\033[1m'
    NC=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

info()  { printf '%s[INFO]%s  %s\n' "$BLUE" "$NC" "$*"; }
ok()    { printf '%s[OK]%s    %s\n' "$GREEN" "$NC" "$*"; }
warn()  { printf '%s[WARN]%s  %s\n' "$YELLOW" "$NC" "$*"; }
err()   { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; }
title() { printf '\n%s━━━ %s ━━━%s\n\n' "$BOLD" "$*" "$NC"; }

die() {
    err "$*"
    exit 1
}

# Check whether a command exists
has() { command -v "$1" >/dev/null 2>&1; }

# Read user input from /dev/tty (works even under `curl | bash`)
prompt() {
    local message="$1"
    local default="$2"
    local var

    # Non-interactive: forced via --non-interactive, or no TTY at all (e.g. CI).
    # In both cases fall back to the default.
    if [[ "$NON_INTERACTIVE" == true ]] || { [[ ! -t 0 ]] && [[ ! -e /dev/tty ]]; }; then
        echo "$default"
        return
    fi

    # Read from /dev/tty so a piped stdin does not block input
    printf '%s%s%s [%s%s%s]: ' "$BOLD" "$message" "$NC" "$GREEN" "$default" "$NC" > /dev/tty
    read -r var < /dev/tty || var=""

    if [[ -z "$var" ]]; then
        echo "$default"
    else
        echo "$var"
    fi
}

# Validate: integer only, range 21-99 (covers realistic Android SDK versions)
validate_sdk_version() {
    local v="$1"
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
        die "SDK version must be an integer, but got: '$v'"
    fi
    if (( v < 21 || v > 99 )); then
        die "SDK version out of reasonable range (21-99), but got: '$v'"
    fi
}

# Validate: NDK version must look like X.Y.ZZZZZZZZ
validate_ndk_version() {
    local v="$1"
    if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "Invalid NDK version format, expected 'X.Y.Z', but got: '$v'"
    fi
}

# Validate: Flutter version must look like X.Y.Z (optional 'v' prefix and
# pre-release suffix like '-1.0.pre' allowed) AND must exist as a tag in the
# official Flutter repository.
validate_flutter_version() {
    local v="$1"
    if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.\-]+)?$ ]]; then
        die "Invalid Flutter version format, expected 'X.Y.Z' (e.g. 3.24.0), but got: '$v'"
    fi
    info "Checking that Flutter $v exists in the official repository..."
    if ! git ls-remote --tags --exit-code "$FLUTTER_REPO" "refs/tags/$v" >/dev/null 2>&1; then
        die "Flutter version '$v' was not found in the official repository. See https://docs.flutter.dev/release/archive for the list of valid versions."
    fi
}

# ============================================================================
# Command-line arguments
# ============================================================================

usage() {
    cat <<'EOF'
Usage: bash install-flutter-android.sh [OPTIONS]

Options:
  -y, --non-interactive   Run without prompts: use the default versions
                          (or the values from --sdk / --ndk / --flutter)
                          and skip the confirmation step.
      --sdk <version>     Android SDK version to install (default: 33).
      --ndk <version>     Android NDK version to install
                          (default: 28.2.13676358).
      --flutter <version> Flutter version tag to install, e.g. 3.24.0.
                          If omitted, the latest stable release is used.
  -h, --help              Show this help and exit.

Examples:
  bash install-flutter-android.sh
  bash install-flutter-android.sh --non-interactive
  bash install-flutter-android.sh -y --sdk 34 --ndk 27.0.12077973
  bash install-flutter-android.sh -y --flutter 3.24.0
EOF
}

# Parse command-line flags into the runtime-state globals
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--non-interactive|--yes)
                NON_INTERACTIVE=true
                shift
                ;;
            --sdk)
                [[ $# -ge 2 ]] || die "--sdk requires a value"
                SDK_VERSION_ARG="$2"
                shift 2
                ;;
            --sdk=*)
                SDK_VERSION_ARG="${1#*=}"
                shift
                ;;
            --ndk)
                [[ $# -ge 2 ]] || die "--ndk requires a value"
                NDK_VERSION_ARG="$2"
                shift 2
                ;;
            --ndk=*)
                NDK_VERSION_ARG="${1#*=}"
                shift
                ;;
            --flutter|--flutter-version)
                [[ $# -ge 2 ]] || die "$1 requires a value"
                FLUTTER_VERSION_ARG="$2"
                shift 2
                ;;
            --flutter=*|--flutter-version=*)
                FLUTTER_VERSION_ARG="${1#*=}"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1 (run with --help to see available options)"
                ;;
        esac
    done
}

# ============================================================================
# OS detection
# ============================================================================

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        die "Unable to identify the system (/etc/os-release not found)"
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    OS_ID="${ID:-unknown}"
    OS_ID_LIKE="${ID_LIKE:-}"

    case "$OS_ID" in
        debian|ubuntu)
            PKG_MANAGER="apt"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            PKG_MANAGER="dnf"
            has dnf || PKG_MANAGER="yum"
            ;;
        *)
            # Fallback: inspect ID_LIKE
            if [[ "$OS_ID_LIKE" == *"debian"* ]]; then
                PKG_MANAGER="apt"
            elif [[ "$OS_ID_LIKE" == *"rhel"* ]] || [[ "$OS_ID_LIKE" == *"fedora"* ]]; then
                PKG_MANAGER="dnf"
                has dnf || PKG_MANAGER="yum"
            else
                die "Unsupported system: $OS_ID (supports Debian/Ubuntu/CentOS/RHEL/Rocky/AlmaLinux/Fedora)"
            fi
            ;;
    esac

    info "Detected system: ${OS_ID} (using ${PKG_MANAGER})"
}

# Use sudo unless already running as root
SUDO=""
need_sudo() {
    if [[ "$EUID" -ne 0 ]]; then
        has sudo || die "sudo is required but not installed"
        SUDO="sudo"
    fi
}

# ============================================================================
# Install system dependencies
# ============================================================================

install_system_deps() {
    title "Installing system dependencies"

    case "$PKG_MANAGER" in
        apt)
            info "Updating apt index..."
            $SUDO apt update -y
            info "Installing base tools and JDK 17..."
            $SUDO apt install -y \
                curl git unzip wget xz-utils zip ca-certificates \
                openjdk-17-jdk libglu1-mesa
            ;;
        dnf|yum)
            info "Installing base tools and JDK 17..."
            $SUDO "$PKG_MANAGER" install -y \
                curl git unzip wget xz tar zip ca-certificates \
                java-17-openjdk-devel mesa-libGLU || \
                $SUDO "$PKG_MANAGER" install -y \
                    curl git unzip wget xz tar zip ca-certificates \
                    java-17-openjdk-devel
            ;;
    esac

    # Verify Java
    if ! has java; then
        die "JDK installation failed: the 'java' command is unavailable"
    fi

    local java_version
    java_version=$(java -version 2>&1 | head -1)
    ok "Java installed: $java_version"
}

# Determine JAVA_HOME
detect_java_home() {
    local java_bin
    java_bin=$(readlink -f "$(command -v java)")
    # java_bin looks like /usr/lib/jvm/java-17-openjdk-amd64/bin/java
    JAVA_HOME_DETECTED="${java_bin%/bin/java}"
    info "Detected JAVA_HOME: $JAVA_HOME_DETECTED"
}

# ============================================================================
# Install Android SDK
# ============================================================================

install_android_sdk() {
    title "Installing Android SDK"

    if [[ -d "$ANDROID_HOME/cmdline-tools/latest" ]]; then
        info "Android cmdline-tools already present, skipping download"
    else
        info "Downloading Android command-line tools..."
        mkdir -p "$ANDROID_HOME/cmdline-tools"
        cd "$ANDROID_HOME/cmdline-tools"

        local tmpzip="cmdline-tools.zip"
        wget -q --show-progress -O "$tmpzip" "$CMDLINE_TOOLS_URL"

        unzip -qo "$tmpzip"
        mv cmdline-tools latest
        rm -f "$tmpzip"
        ok "command-line tools installed to $ANDROID_HOME/cmdline-tools/latest"
    fi

    # Add sdkmanager to PATH for the duration of this script run
    export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
    export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME"
    export JAVA_HOME="$JAVA_HOME_DETECTED"

    info "Accepting Android SDK licenses..."
    yes 2>/dev/null | sdkmanager --licenses > /dev/null || true

    info "Installing platform-tools, SDK Platform ${SDK_VERSION}, Build Tools ${SDK_VERSION}.0.0..."
    sdkmanager \
        "platform-tools" \
        "platforms;android-${SDK_VERSION}" \
        "build-tools;${SDK_VERSION}.0.0"

    ok "Android SDK Platform ${SDK_VERSION} installed"
}

# ============================================================================
# Install NDK
# ============================================================================

install_ndk() {
    title "Installing Android NDK ${NDK_VERSION}"

    local ndk_dir="$ANDROID_HOME/ndk/$NDK_VERSION"

    # If the directory exists but is incomplete, remove it and reinstall
    if [[ -d "$ndk_dir" ]] && [[ ! -f "$ndk_dir/source.properties" ]]; then
        warn "Incomplete NDK directory detected (no source.properties), cleaning up..."
        rm -rf "$ndk_dir"
    fi

    if [[ -f "$ndk_dir/source.properties" ]]; then
        info "NDK $NDK_VERSION already installed and complete, skipping"
        return
    fi

    info "Downloading and installing NDK $NDK_VERSION..."
    sdkmanager --install "ndk;$NDK_VERSION"

    # Re-verify after installation
    if [[ ! -f "$ndk_dir/source.properties" ]]; then
        die "NDK installation failed: $ndk_dir/source.properties not found. Make sure version '$NDK_VERSION' is available in the Google repository"
    fi

    ok "NDK $NDK_VERSION installed"
}

# ============================================================================
# Install Flutter
# ============================================================================

install_flutter() {
    title "Installing Flutter"

    if [[ -d "$FLUTTER_HOME" ]]; then
        info "Flutter directory already exists, skipping clone"
    else
        local flutter_ref="$FLUTTER_CHANNEL"
        local flutter_desc="$FLUTTER_CHANNEL channel (latest)"
        if [[ -n "$FLUTTER_VERSION" ]]; then
            flutter_ref="$FLUTTER_VERSION"
            flutter_desc="version $FLUTTER_VERSION"
        fi
        info "Cloning Flutter $flutter_desc..."
        git clone --depth 1 -b "$flutter_ref" "$FLUTTER_REPO" "$FLUTTER_HOME"
    fi

    export PATH="$FLUTTER_HOME/bin:$PATH"

    info "Precaching the Android toolchain..."
    flutter precache --android

    info "Accepting Android licenses (via Flutter)..."
    yes 2>/dev/null | flutter doctor --android-licenses > /dev/null || true

    ok "Flutter installed to $FLUTTER_HOME"
}

# ============================================================================
# Configure shell environment variables
# ============================================================================

setup_shell_env() {
    title "Configuring shell environment variables"

    case "$(basename "${SHELL:-/bin/bash}")" in
        zsh)  RCFILE="$HOME/.zshrc" ;;
        bash) RCFILE="$HOME/.bashrc" ;;
        *)    RCFILE="$HOME/.profile" ;;
    esac

    touch "$RCFILE"

    local marker_begin="# >>> flutter-android-env (managed by install script) >>>"
    local marker_end="# <<< flutter-android-env <<<"

    # Remove any previous block
    if grep -q "$marker_begin" "$RCFILE"; then
        info "Existing config block detected, replacing it..."
        # Delete the old block with sed, then drop the temporary backup
        sed -i.bak "/$marker_begin/,/$marker_end/d" "$RCFILE"
        rm -f "$RCFILE.bak"
    fi

    # Append the new block
    cat >> "$RCFILE" <<EOF
$marker_begin
export JAVA_HOME="$JAVA_HOME_DETECTED"
export ANDROID_HOME="$ANDROID_HOME"
export ANDROID_SDK_ROOT="\$ANDROID_HOME"
export PATH="\$PATH:\$ANDROID_HOME/cmdline-tools/latest/bin"
export PATH="\$PATH:\$ANDROID_HOME/platform-tools"
export PATH="\$PATH:\$ANDROID_HOME/build-tools/${SDK_VERSION}.0.0"
export PATH="\$PATH:$FLUTTER_HOME/bin"
$marker_end
EOF

    ok "Environment variables written to $RCFILE"
    info "Log in again or run 'source $RCFILE' to apply them"
}

# ============================================================================
# Verify
# ============================================================================

verify() {
    title "Verifying the installation"

    info "Flutter version:"
    flutter --version || die "Flutter verification failed"

    echo
    info "Running flutter doctor (focus on Flutter / Android toolchain):"
    flutter doctor || true

    echo
    ok "Installation complete 🎉"
    echo
    printf '%sNext steps:%s\n' "$BOLD" "$NC"
    printf '  1. Run %ssource %s%s or log in again\n' "$GREEN" "$RCFILE" "$NC"
    printf '  2. In your Flutter project directory, run %sflutter pub get && flutter build apk --debug%s\n' "$GREEN" "$NC"
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_args "$@"

    title "Flutter + Android build environment installer"

    detect_os
    need_sudo

    if [[ "$NON_INTERACTIVE" == true ]]; then
        info "Running in non-interactive mode (prompts skipped, defaults used)"
    fi

    # Parameter input (prompts are skipped in non-interactive mode)
    SDK_VERSION=$(prompt "Enter the Android SDK version to install" "${SDK_VERSION_ARG:-$DEFAULT_SDK_VERSION}")
    validate_sdk_version "$SDK_VERSION"
    ok "SDK version: $SDK_VERSION"

    NDK_VERSION=$(prompt "Enter the Android NDK version to install" "${NDK_VERSION_ARG:-$DEFAULT_NDK_VERSION}")
    validate_ndk_version "$NDK_VERSION"
    ok "NDK version: $NDK_VERSION"

    local flutter_input
    flutter_input=$(prompt "Enter the Flutter version (or 'latest')" "${FLUTTER_VERSION_ARG:-latest}")
    flutter_input="${flutter_input#v}"
    if [[ -z "$flutter_input" || "$flutter_input" == "latest" ]]; then
        FLUTTER_VERSION=""
        ok "Flutter: latest ($FLUTTER_CHANNEL channel)"
    else
        validate_flutter_version "$flutter_input"
        FLUTTER_VERSION="$flutter_input"
        ok "Flutter version: $FLUTTER_VERSION"
    fi

    local flutter_label="$FLUTTER_CHANNEL channel (latest)"
    [[ -n "$FLUTTER_VERSION" ]] && flutter_label="version $FLUTTER_VERSION"

    echo
    info "About to install the following components:"
    echo "  - JDK 17"
    echo "  - Android SDK Platform $SDK_VERSION"
    echo "  - Android Build Tools $SDK_VERSION.0.0"
    echo "  - Android NDK $NDK_VERSION"
    echo "  - Flutter ($flutter_label)"
    echo "  - Install directories: $ANDROID_HOME, $FLUTTER_HOME"
    echo

    local confirm
    confirm=$(prompt "Continue? (Y/n)" "y")
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        info "Cancelled"
        exit 0
    fi

    install_system_deps
    detect_java_home
    install_android_sdk
    install_ndk
    install_flutter
    setup_shell_env
    verify
}

main "$@"
