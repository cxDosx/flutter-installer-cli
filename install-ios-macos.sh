#!/usr/bin/env bash
#
# One-command installer for a Flutter iOS build environment (macOS only).
# Targets Intel Macs and Apple Silicon Macs.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-ios-macos.sh)
#   or locally:
#   bash install-ios-macos.sh [OPTIONS]
#
# Options:
#   -y, --non-interactive   Run without prompts; skip confirmation.
#       --flutter <version> Flutter version tag, e.g. 3.24.0 (default: latest stable).
#   -h, --help              Show help and exit.
#
# Installs / configures:
#   - Homebrew (if not already installed)
#   - Rosetta 2 (Apple Silicon only)
#   - Xcode license acceptance + first-launch components
#   - CocoaPods (via Homebrew)
#   - Flutter (user-specified version, or latest stable if unspecified) with iOS
#     artifacts precached
#
# Note: the full Xcode app cannot be installed non-interactively. It must come
# from the Mac App Store. If it is missing, this script guides you there and
# then exits; install Xcode and re-run the script.

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

FLUTTER_CHANNEL="stable"
FLUTTER_REPO="https://github.com/flutter/flutter.git"
FLUTTER_HOME="${HOME}/flutter"

XCODE_APP_STORE_URL="macappstore://apps.apple.com/app/xcode/id497799835"
XCODE_WEB_URL="https://apps.apple.com/app/xcode/id497799835"

# Runtime state (may be overridden by command-line flags)
NON_INTERACTIVE=false
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

# Validate: Flutter version must look like X.Y.Z (pre-release suffix like
# '-1.0.pre' allowed) AND must exist as a tag in the official Flutter repo.
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

    printf '%s%s%s [%s%s%s]: ' "$BOLD" "$message" "$NC" "$GREEN" "$default" "$NC" > /dev/tty
    read -r var < /dev/tty || var=""

    if [[ -z "$var" ]]; then
        echo "$default"
    else
        echo "$var"
    fi
}

# ============================================================================
# Command-line arguments
# ============================================================================

usage() {
    cat <<'EOF'
Usage: bash install-ios-macos.sh [OPTIONS]

Options:
  -y, --non-interactive   Run without prompts and skip the confirmation step.
      --flutter <version> Flutter version tag to install, e.g. 3.24.0.
                          If omitted, the latest stable release is used.
  -h, --help              Show this help and exit.

Examples:
  bash install-ios-macos.sh
  bash install-ios-macos.sh --non-interactive
  bash install-ios-macos.sh -y --flutter 3.24.0
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
# macOS detection
# ============================================================================

detect_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        die "iOS development is only possible on macOS; this script cannot run here"
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
# Xcode
# ============================================================================

# Locate a full Xcode.app installation; sets XCODE_APP on success
XCODE_APP=""
find_xcode() {
    local dev_dir
    dev_dir=$(xcode-select -p 2>/dev/null || true)

    # xcode-select may already point at a full Xcode (not just command-line tools)
    if [[ "$dev_dir" == *".app/Contents/Developer" ]]; then
        local candidate="${dev_dir%/Contents/Developer}"
        if [[ -d "$candidate" ]]; then
            XCODE_APP="$candidate"
            return 0
        fi
    fi

    # Default install location
    if [[ -d "/Applications/Xcode.app" ]]; then
        XCODE_APP="/Applications/Xcode.app"
        return 0
    fi

    # Last resort: ask Spotlight
    local found
    found=$(mdfind 'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"' 2>/dev/null | head -1 || true)
    if [[ -n "$found" ]] && [[ -d "$found" ]]; then
        XCODE_APP="$found"
        return 0
    fi

    return 1
}

# Verify Xcode is present, or guide the user to install it and exit
ensure_xcode() {
    title "Checking Xcode"

    if find_xcode; then
        ok "Xcode found: $XCODE_APP"
        return
    fi

    err "The full Xcode app is not installed."
    echo
    echo "iOS builds require the full Xcode app. It cannot be installed"
    echo "non-interactively; get it from the Mac App Store (a free Apple ID"
    echo "is enough), then re-run this script:"
    echo
    echo "  1. Install Xcode from the App Store:"
    echo "     $XCODE_WEB_URL"
    echo "  2. Open Xcode once so it can finish its first-time setup."
    echo "  3. Re-run this script."
    echo

    if [[ "$NON_INTERACTIVE" != true ]]; then
        local open_now
        open_now=$(prompt "Open the App Store Xcode page now? (Y/n)" "y")
        if [[ "$open_now" =~ ^[Yy] ]]; then
            open "$XCODE_APP_STORE_URL" 2>/dev/null \
                || open "$XCODE_WEB_URL" 2>/dev/null \
                || true
        fi
    fi

    die "Xcode is required. Install it, then run this script again."
}

# Select the full Xcode, accept its license, and install required components
configure_xcode() {
    title "Configuring Xcode"

    local dev_dir="$XCODE_APP/Contents/Developer"

    # Point the active developer directory at the full Xcode
    if [[ "$(xcode-select -p 2>/dev/null || true)" != "$dev_dir" ]]; then
        info "Selecting $XCODE_APP as the active developer directory (requires sudo)..."
        sudo xcode-select -s "$dev_dir"
    else
        info "Active developer directory already points at Xcode"
    fi

    # Accept the Xcode license (idempotent)
    info "Accepting the Xcode license (requires sudo)..."
    sudo xcodebuild -license accept

    # Install additional required components (idempotent)
    info "Running Xcode first-launch setup (requires sudo)..."
    sudo xcodebuild -runFirstLaunch

    local xcode_version
    xcode_version=$(xcodebuild -version 2>/dev/null | head -1 || echo "Xcode")
    ok "$xcode_version configured"
}

# ============================================================================
# Rosetta 2 (Apple Silicon only)
# ============================================================================

install_rosetta() {
    # Rosetta 2 only applies to Apple Silicon
    [[ "$ARCH" == "arm64" ]] || return 0

    title "Checking Rosetta 2"

    if pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
        ok "Rosetta 2 already installed"
        return
    fi

    info "Installing Rosetta 2 (recommended for some iOS tooling on Apple Silicon)..."
    if softwareupdate --install-rosetta --agree-to-license; then
        ok "Rosetta 2 installed"
    else
        warn "Rosetta 2 installation failed; continuing anyway (modern Flutter iOS builds usually work without it)"
    fi
}

# ============================================================================
# Homebrew
# ============================================================================

install_homebrew() {
    title "Checking Homebrew"

    # Homebrew may be installed but not yet on PATH in this shell
    if ! has brew && [[ -x "$BREW_PREFIX/bin/brew" ]]; then
        eval "$($BREW_PREFIX/bin/brew shellenv)"
    fi

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
# CocoaPods
# ============================================================================

install_cocoapods() {
    title "Installing CocoaPods"

    if has pod; then
        ok "CocoaPods already installed ($(pod --version 2>/dev/null || echo 'version unknown'))"
        return
    fi

    info "Installing CocoaPods via Homebrew..."
    brew install cocoapods

    has pod || die "CocoaPods installed but the 'pod' command is unavailable"
    ok "CocoaPods installed ($(pod --version))"
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

    info "Precaching the iOS toolchain..."
    flutter precache --ios

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

    local marker_begin="# >>> flutter-ios-env (managed by install script) >>>"
    local marker_end="# <<< flutter-ios-env <<<"

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
eval "\$($BREW_PREFIX/bin/brew shellenv)"
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
    info "Running flutter doctor (focus on Flutter / Xcode):"
    flutter doctor || true

    echo
    ok "Installation complete 🎉"
    echo
    printf '%sNext steps:%s\n' "$BOLD" "$NC"
    printf '  1. Run %ssource %s%s or open a new terminal\n' "$GREEN" "$RCFILE" "$NC"
    printf '  2. In your Flutter project directory, run %sflutter pub get%s\n' "$GREEN" "$NC"
    printf '  3. Build for the simulator: %sflutter build ios --simulator%s\n' "$GREEN" "$NC"
    echo "     (a signed device build or IPA additionally needs an Apple"
    echo "      Developer account configured in Xcode)"
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_args "$@"

    title "Flutter iOS build environment installer (macOS)"

    detect_macos

    if [[ "$NON_INTERACTIVE" == true ]]; then
        info "Running in non-interactive mode (prompts skipped, defaults used)"
    fi

    # Fail fast if Xcode is missing — it needs a manual App Store install
    ensure_xcode

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
    info "About to install / configure the following:"
    echo "  - Homebrew (if not already installed)"
    echo "  - Rosetta 2 (Apple Silicon only)"
    echo "  - Xcode: $XCODE_APP (accept license + first-launch setup)"
    echo "  - CocoaPods (via Homebrew)"
    echo "  - Flutter ($flutter_label) with iOS artifacts"
    echo "  - Install directory: $FLUTTER_HOME"
    echo

    local confirm
    confirm=$(prompt "Continue? (Y/n)" "y")
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        info "Cancelled"
        exit 0
    fi

    install_homebrew
    install_rosetta
    configure_xcode
    install_cocoapods
    install_flutter
    setup_shell_env
    verify
}

main "$@"
