#!/usr/bin/env bash
#
# One-command installer for a Flutter + Android build environment (macOS).
# Targets Intel Macs and Apple Silicon Macs.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-macos.sh)
#   or locally:
#   bash install-macos.sh [OPTIONS]
#
# Options:
#   -y, --non-interactive   Run without prompts; use defaults and skip confirmation.
#       --sdk <version>     Android SDK version (default: 33).
#       --ndk <version>     Android NDK version (default: 28.2.13676358).
#   -h, --help              Show help and exit.
#
# Installs:
#   - Homebrew (if not already installed)
#   - JDK 17 (openjdk@17)
#   - Android command-line tools
#   - Android SDK Platform (user-specified version, default 33)
#   - Android Build Tools (matching the SDK version)
#   - Android NDK (user-specified version, default 28.2.13676358)
#   - Flutter (stable channel)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

DEFAULT_SDK_VERSION="33"
DEFAULT_NDK_VERSION="28.2.13676358"
FLUTTER_CHANNEL="stable"
FLUTTER_REPO="https://github.com/flutter/flutter.git"

ANDROID_HOME="${HOME}/android-sdk"
FLUTTER_HOME="${HOME}/flutter"

# Runtime state (may be overridden by command-line flags)
NON_INTERACTIVE=false
SDK_VERSION_ARG=""
NDK_VERSION_ARG=""

# ============================================================================
# Helper functions
# ============================================================================

# Colored output (only when stdout is a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
title() { echo -e "\n${BOLD}━━━ $* ━━━${NC}\n"; }

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

    echo -en "${BOLD}${message}${NC} [${GREEN}${default}${NC}]: " > /dev/tty
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

# ============================================================================
# Command-line arguments
# ============================================================================

usage() {
    cat <<'EOF'
Usage: bash install-macos.sh [OPTIONS]

Options:
  -y, --non-interactive   Run without prompts: use the default versions
                          (or the values from --sdk / --ndk) and skip the
                          confirmation step.
      --sdk <version>     Android SDK version to install (default: 33).
      --ndk <version>     Android NDK version to install
                          (default: 28.2.13676358).
  -h, --help              Show this help and exit.

Examples:
  bash install-macos.sh
  bash install-macos.sh --non-interactive
  bash install-macos.sh -y --sdk 34 --ndk 27.0.12077973
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
# macOS detection
# ============================================================================

detect_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        die "This script only supports macOS. Linux users: use install-flutter-android.sh"
    fi

    ARCH="$(uname -m)"
    case "$ARCH" in
        arm64)
            MAC_TYPE="Apple Silicon"
            BREW_PREFIX="/opt/homebrew"
            ;;
        x86_64)
            MAC_TYPE="Intel"
            BREW_PREFIX="/usr/local"
            ;;
        *)
            die "Unknown macOS architecture: $ARCH"
            ;;
    esac

    local macos_version
    macos_version=$(sw_vers -productVersion)
    info "macOS $macos_version ($MAC_TYPE, $ARCH)"
}

# ============================================================================
# Install Homebrew
# ============================================================================

install_homebrew() {
    title "Checking Homebrew"

    if has brew; then
        ok "Homebrew already installed ($(brew --version | head -1))"
        return
    fi

    info "Homebrew not found, installing..."
    info "Enter your password if prompted for sudo"
    if [[ "$NON_INTERACTIVE" == true ]]; then
        # NONINTERACTIVE=1 stops the Homebrew installer from waiting on RETURN
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Add brew to PATH for the current session
    if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
        eval "$($BREW_PREFIX/bin/brew shellenv)"
    else
        die "brew command not found after Homebrew installation"
    fi

    ok "Homebrew installed"
}

# ============================================================================
# Install JDK 17
# ============================================================================

install_jdk() {
    title "Installing JDK 17"

    if /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
        local current_java_home
        current_java_home=$(/usr/libexec/java_home -v 17)
        ok "JDK 17 already installed: $current_java_home"
        JAVA_HOME_DETECTED="$current_java_home"
        return
    fi

    info "Installing openjdk@17 via Homebrew..."
    brew install openjdk@17

    # macOS needs a manual symlink into the system Java directory so that
    # /usr/libexec/java_home can discover it
    local jdk_path="$BREW_PREFIX/opt/openjdk@17/libexec/openjdk.jdk"
    local system_jdk_dir="/Library/Java/JavaVirtualMachines"

    if [[ -d "$jdk_path" ]] && [[ ! -L "$system_jdk_dir/openjdk-17.jdk" ]]; then
        info "Linking openjdk@17 into the system Java directory (requires sudo)..."
        sudo ln -sfn "$jdk_path" "$system_jdk_dir/openjdk-17.jdk"
    fi

    if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
        die "JDK 17 installed but not recognized by /usr/libexec/java_home"
    fi

    JAVA_HOME_DETECTED=$(/usr/libexec/java_home -v 17)
    ok "JDK 17 installed: $JAVA_HOME_DETECTED"
}

# ============================================================================
# Install other base tools
# ============================================================================

install_basic_tools() {
    title "Installing base tools"

    local tools=("git" "unzip")
    for tool in "${tools[@]}"; do
        if has "$tool"; then
            info "$tool already present, skipping"
        else
            info "Installing $tool..."
            brew install "$tool"
        fi
    done

    ok "Base tools ready"
}

# ============================================================================
# Install Android SDK
# ============================================================================

install_android_sdk() {
    title "Installing Android SDK"

    if [[ -d "$ANDROID_HOME/cmdline-tools/latest" ]]; then
        info "Android cmdline-tools already present, skipping download"
    else
        info "Downloading Android command-line tools (macOS build)..."
        mkdir -p "$ANDROID_HOME/cmdline-tools"
        cd "$ANDROID_HOME/cmdline-tools"

        local tmpzip="cmdline-tools.zip"
        # Use the macOS build of the command-line tools
        local cmdline_url="https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip"
        curl -fsSL -o "$tmpzip" "$cmdline_url"

        unzip -qo "$tmpzip"
        mv cmdline-tools latest
        rm -f "$tmpzip"
        ok "command-line tools installed to $ANDROID_HOME/cmdline-tools/latest"
    fi

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
        info "Cloning Flutter $FLUTTER_CHANNEL..."
        git clone --depth 1 -b "$FLUTTER_CHANNEL" "$FLUTTER_REPO" "$FLUTTER_HOME"
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

    # macOS defaults to zsh (since Catalina); older versions may use bash
    case "$(basename "${SHELL:-/bin/zsh}")" in
        zsh)  RCFILE="$HOME/.zshrc" ;;
        bash) RCFILE="$HOME/.bash_profile" ;;
        *)    RCFILE="$HOME/.profile" ;;
    esac

    touch "$RCFILE"

    local marker_begin="# >>> flutter-android-env (managed by install script) >>>"
    local marker_end="# <<< flutter-android-env <<<"

    # Remove any previous block (macOS sed differs slightly from GNU sed,
    # so perl is more reliable here)
    if grep -q "$marker_begin" "$RCFILE"; then
        info "Existing config block detected, replacing it..."
        # Replace the content between the two markers (macOS-compatible),
        # then drop the temporary backup
        perl -i.bak -ne "print unless /\Q$marker_begin\E/ .. /\Q$marker_end\E/" "$RCFILE"
        rm -f "$RCFILE.bak"
    fi

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
    info "Open a new terminal or run 'source $RCFILE' to apply them"
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
    echo -e "${BOLD}Next steps:${NC}"
    echo "  1. Run ${GREEN}source $RCFILE${NC} or open a new terminal"
    echo "  2. In your Flutter project directory, run ${GREEN}flutter pub get && flutter build apk --debug${NC}"
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_args "$@"

    title "Flutter + Android build environment installer (macOS)"

    detect_macos

    if [[ "$NON_INTERACTIVE" == true ]]; then
        info "Running in non-interactive mode (prompts skipped, defaults used)"
    fi

    SDK_VERSION=$(prompt "Enter the Android SDK version to install" "${SDK_VERSION_ARG:-$DEFAULT_SDK_VERSION}")
    validate_sdk_version "$SDK_VERSION"
    ok "SDK version: $SDK_VERSION"

    NDK_VERSION=$(prompt "Enter the Android NDK version to install" "${NDK_VERSION_ARG:-$DEFAULT_NDK_VERSION}")
    validate_ndk_version "$NDK_VERSION"
    ok "NDK version: $NDK_VERSION"

    echo
    info "About to install the following components:"
    echo "  - Homebrew (if not already installed)"
    echo "  - JDK 17 (openjdk@17 via Homebrew)"
    echo "  - Android SDK Platform $SDK_VERSION"
    echo "  - Android Build Tools $SDK_VERSION.0.0"
    echo "  - Android NDK $NDK_VERSION"
    echo "  - Flutter ($FLUTTER_CHANNEL channel)"
    echo "  - Install directories: $ANDROID_HOME, $FLUTTER_HOME"
    echo

    local confirm
    confirm=$(prompt "Continue? (Y/n)" "y")
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        info "Cancelled"
        exit 0
    fi

    install_homebrew
    install_basic_tools
    install_jdk
    install_android_sdk
    install_ndk
    install_flutter
    setup_shell_env
    verify
}

main "$@"
