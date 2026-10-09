#!/usr/bin/env bash
#
# One-command installer for a Flutter + Android build environment (macOS).
# Targets Intel Macs and Apple Silicon Macs.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-android-macos.sh)
#   or locally:
#   bash install-android-macos.sh [OPTIONS]
#
# Options:
#   -y, --non-interactive   Run without prompts; use defaults and skip confirmation.
#       --sdk <version>     Android SDK version (default: 33).
#       --ndk <version>     Android NDK version (default: 28.2.13676358).
#       --flutter <version> Flutter version tag, e.g. 3.24.0 (default: latest stable).
#   -h, --help              Show help and exit.
#
# Installs:
#   - Homebrew (if not already installed; pinned to 6.0.22 + a fixed homebrew-core
#     snapshot on Intel Macs)
#   - JDK 17 (openjdk@17)
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
FLUTTER_CHANNEL="stable"
FLUTTER_REPO="https://github.com/flutter/flutter.git"

# Homebrew is pinned to this release on Intel Macs, the last one this script
# supports there. Apple Silicon Macs keep the latest Homebrew.
HOMEBREW_INTEL_VERSION="6.0.22"
# homebrew-core is pinned too on Intel Macs: newer formula revisions are only
# bottled for Apple Silicon (ruby 4.0.7 and openssl@3 3.6.3+ among them), so
# Intel would build ruby -> rust -> llvm from source. This commit (2026-08-25)
# is the last one where every formula the scripts install has an Intel bottle.
HOMEBREW_CORE_INTEL_COMMIT="727fea0a56b12a6a5fa1e57ac92e1c60d98379ad"
# The official installer dropped Intel support in Homebrew/install@e078684 and
# now aborts on x86_64, so Intel Macs use the last commit before that change.
HOMEBREW_INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
HOMEBREW_INTEL_INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/7a133dcc74051ee4efc79467ed215dfedf45aea2/install.sh"

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

# ============================================================================
# Command-line arguments
# ============================================================================

usage() {
    cat <<'EOF'
Usage: bash install-android-macos.sh [OPTIONS]

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
  bash install-android-macos.sh
  bash install-android-macos.sh --non-interactive
  bash install-android-macos.sh -y --sdk 34 --ndk 27.0.12077973
  bash install-android-macos.sh -y --flutter 3.24.0
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
# macOS detection
# ============================================================================

detect_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        die "This script only supports macOS. Linux users: use install-android-linux.sh"
    fi

    ARCH="$(uname -m)"

    # A shell running under Rosetta 2 reports x86_64 even on Apple Silicon.
    # Check the real chip so Apple Silicon is never treated as Intel (wrong
    # Homebrew prefix, needless version pin).
    if [[ "$ARCH" == "x86_64" ]] && [[ "$(sysctl -in hw.optional.arm64 2>/dev/null)" == "1" ]]; then
        die "This shell is running under Rosetta 2 on Apple Silicon. Re-run the script from a native (arm64) terminal"
    fi

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
        pin_homebrew
        return
    fi

    local installer_url="$HOMEBREW_INSTALLER_URL"
    [[ "$MAC_TYPE" == "Intel" ]] && installer_url="$HOMEBREW_INTEL_INSTALLER_URL"

    info "Homebrew not found, installing..."
    info "Enter your password if prompted for sudo"
    local installer
    installer=$(curl -fsSL "$installer_url") || die "Failed to download the Homebrew installer from $installer_url"
    if [[ "$NON_INTERACTIVE" == true ]]; then
        # NONINTERACTIVE=1 stops the Homebrew installer from waiting on RETURN
        NONINTERACTIVE=1 /bin/bash -c "$installer"
    else
        /bin/bash -c "$installer"
    fi

    # Add brew to PATH for the current session
    if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
        eval "$($BREW_PREFIX/bin/brew shellenv)"
    else
        die "brew command not found after Homebrew installation"
    fi

    ok "Homebrew installed"
    pin_homebrew
}

# On Intel Macs, check out the pinned Homebrew release and homebrew-core
# snapshot, and stop brew from auto-updating past them. Does nothing on Apple
# Silicon.
pin_homebrew() {
    [[ "$MAC_TYPE" == "Intel" ]] || return 0

    # `brew install` would otherwise run `brew update` and move off the pin
    export HOMEBREW_NO_AUTO_UPDATE=1
    # Read formulae from the pinned homebrew-core checkout instead of the live
    # formulae.brew.sh API, whose latest versions often lack Intel bottles
    export HOMEBREW_NO_INSTALL_FROM_API=1

    local repo current
    repo=$(brew --repo)
    current=$(git -C "$repo" describe --tags --exact-match HEAD 2>/dev/null || true)
    if [[ "$current" == "$HOMEBREW_INTEL_VERSION" ]]; then
        ok "Homebrew pinned to $HOMEBREW_INTEL_VERSION (Intel Mac)"
    else
        info "Intel Mac detected, pinning Homebrew to $HOMEBREW_INTEL_VERSION (currently ${current:-$(brew --version | head -1)})..."
        git -C "$repo" fetch --quiet --force origin "refs/tags/$HOMEBREW_INTEL_VERSION:refs/tags/$HOMEBREW_INTEL_VERSION" \
            || die "Failed to fetch Homebrew $HOMEBREW_INTEL_VERSION"
        git -C "$repo" checkout --quiet "$HOMEBREW_INTEL_VERSION" \
            || die "Failed to check out Homebrew $HOMEBREW_INTEL_VERSION (local changes in $repo?)"
        ok "Homebrew pinned to $HOMEBREW_INTEL_VERSION (Intel Mac)"
    fi

    pin_homebrew_core
    warn "Auto-update is disabled; running 'brew update' manually will move Homebrew and homebrew-core off the pin"
}

# Check out homebrew-core at HOMEBREW_CORE_INTEL_COMMIT. A fresh tap is a
# shallow fetch of just that commit, so the full history is never downloaded.
pin_homebrew_core() {
    local core_repo short_sha remote
    core_repo="$(brew --repo)/Library/Taps/homebrew/homebrew-core"
    short_sha="${HOMEBREW_CORE_INTEL_COMMIT:0:7}"
    remote="${HOMEBREW_CORE_GIT_REMOTE:-https://github.com/Homebrew/homebrew-core}"

    if [[ "$(git -C "$core_repo" rev-parse HEAD 2>/dev/null)" == "$HOMEBREW_CORE_INTEL_COMMIT" ]]; then
        ok "homebrew-core pinned to $short_sha (Intel Mac)"
        return
    fi

    info "Pinning homebrew-core to $short_sha (formula versions that still ship Intel bottles)..."
    if [[ ! -d "$core_repo/.git" ]]; then
        mkdir -p "$core_repo"
        git -C "$core_repo" init --quiet
        git -C "$core_repo" remote add origin "$remote"
    fi
    if ! git -C "$core_repo" cat-file -e "$HOMEBREW_CORE_INTEL_COMMIT^{commit}" 2>/dev/null; then
        # Keep a full clone full; only a new or already-shallow tap gets --depth
        local depth=""
        if ! git -C "$core_repo" rev-parse --verify --quiet HEAD >/dev/null \
            || [[ "$(git -C "$core_repo" rev-parse --is-shallow-repository)" == "true" ]]; then
            depth="--depth=1"
        fi
        # $depth is unquoted on purpose: it must vanish when empty
        git -C "$core_repo" fetch --quiet $depth origin "$HOMEBREW_CORE_INTEL_COMMIT" \
            || die "Failed to fetch homebrew-core $short_sha from $remote"
    fi
    git -C "$core_repo" checkout --quiet --force --detach "$HOMEBREW_CORE_INTEL_COMMIT" \
        || die "Failed to check out homebrew-core $short_sha"

    ok "homebrew-core pinned to $short_sha (Intel Mac)"
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

    # Build the package list, skipping any version that is already installed.
    # SDK Platform and Build Tools are version-keyed, so several versions can
    # coexist; only install the requested version if it is missing.
    local sdk_packages=("platform-tools")

    if [[ -d "$ANDROID_HOME/platforms/android-${SDK_VERSION}" ]]; then
        info "SDK Platform ${SDK_VERSION} already installed, skipping"
    else
        sdk_packages+=("platforms;android-${SDK_VERSION}")
    fi

    if [[ -d "$ANDROID_HOME/build-tools/${SDK_VERSION}.0.0" ]]; then
        info "Build Tools ${SDK_VERSION}.0.0 already installed, skipping"
    else
        sdk_packages+=("build-tools;${SDK_VERSION}.0.0")
    fi

    info "Installing: ${sdk_packages[*]}..."
    sdkmanager "${sdk_packages[@]}"

    ok "Android SDK Platform ${SDK_VERSION} ready"
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

    local flutter_ref="$FLUTTER_CHANNEL"
    local flutter_desc="$FLUTTER_CHANNEL channel (latest)"
    if [[ -n "$FLUTTER_VERSION" ]]; then
        flutter_ref="$FLUTTER_VERSION"
        flutter_desc="version $FLUTTER_VERSION"
    fi

    if [[ -d "$FLUTTER_HOME" ]]; then
        # Work out which version is currently installed
        local installed_version
        installed_version="$(git -C "$FLUTTER_HOME" describe --tags 2>/dev/null || true)"
        if [[ -z "$installed_version" && -f "$FLUTTER_HOME/version" ]]; then
            installed_version="$(head -1 "$FLUTTER_HOME/version" 2>/dev/null)"
        fi

        if [[ -z "$FLUTTER_VERSION" ]]; then
            # No specific version requested: keep whatever is already there
            info "Flutter already installed (${installed_version:-unknown version}), skipping clone"
        elif [[ "$installed_version" == "$FLUTTER_VERSION" ]]; then
            info "Flutter $FLUTTER_VERSION already installed, skipping clone"
        else
            warn "Installed Flutter is ${installed_version:-an unknown version}, but $FLUTTER_VERSION was requested"
            local reinstall
            reinstall=$(prompt "Reinstall Flutter as $FLUTTER_VERSION? This replaces $FLUTTER_HOME (y/N)" "n")
            if [[ "$reinstall" =~ ^[Yy] ]]; then
                info "Removing existing Flutter at $FLUTTER_HOME..."
                rm -rf "$FLUTTER_HOME"
                info "Cloning Flutter $flutter_desc..."
                git clone --depth 1 -b "$flutter_ref" "$FLUTTER_REPO" "$FLUTTER_HOME"
            else
                info "Keeping the existing Flutter (${installed_version:-unknown version})"
            fi
        fi
    else
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

    # Keep later `brew` runs from auto-updating past the Intel pin
    local brew_pin_line=""
    [[ "$MAC_TYPE" == "Intel" ]] && brew_pin_line="export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1"

    cat >> "$RCFILE" <<EOF
$marker_begin
${brew_pin_line}
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
    printf '%sNext steps:%s\n' "$BOLD" "$NC"
    printf '  1. Run %ssource %s%s or open a new terminal\n' "$GREEN" "$RCFILE" "$NC"
    printf '  2. In your Flutter project directory, run %sflutter pub get && flutter build apk --debug%s\n' "$GREEN" "$NC"
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
    echo "  - Homebrew (if not already installed; pinned to $HOMEBREW_INTEL_VERSION on Intel)"
    echo "  - JDK 17 (openjdk@17 via Homebrew)"
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
