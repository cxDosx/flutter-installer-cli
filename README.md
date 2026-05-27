# Flutter Installer CLI

[![Shell](https://img.shields.io/badge/shell-bash-4eaa25)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A CLI that sets up a complete **Flutter development environment** in a single command. It installs Flutter together with the full toolchain needed to build real apps — the Android toolchain on Linux or macOS, the iOS toolchain on macOS — and wires up your `PATH` and environment variables automatically. No manual SDK downloads, no version juggling.

Great for bootstrapping a fresh machine, cloud CI servers, and remote development environments (GCP / AWS / Alibaba Cloud ECS).

This repository provides three installer scripts:

| Script | Runs on | Builds for |
|---|---|---|
| `install-android-linux.sh` | Linux | Android |
| `install-android-macos.sh` | macOS | Android |
| `install-ios-macos.sh` | macOS | iOS |

You can run `install-android-macos.sh` and `install-ios-macos.sh` on the same Mac to build for both platforms.

---

## Quick Start

### Android on Linux (Debian / Ubuntu / CentOS / RHEL / Rocky / AlmaLinux / Fedora)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-android-linux.sh)
```

### Android on macOS (Intel / Apple Silicon)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-android-macos.sh)
```

### iOS on macOS (Intel / Apple Silicon)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-ios-macos.sh)
```

> Prefer the `bash <(...)` form over `curl ... | bash`. The former supports interactive input; the latter cannot read the keyboard in some shells.

The two Android scripts prompt you for the SDK / NDK versions:

```
Enter the Android SDK version to install [33]:
Enter the Android NDK version to install [28.2.13676358]:
```

Press Enter to accept the defaults. The iOS script has no version prompts. The whole process takes about 10-15 minutes (depending on your network).

---

## What It Does

### Android (`install-android-linux.sh`, `install-android-macos.sh`)

| Component | Version | Linux source | macOS source |
|---|---|---|---|
| JDK | 17 | apt / dnf | Homebrew |
| Android command-line tools | latest | Google official (linux package) | Google official (mac package) |
| Android SDK Platform | user-specified (default 33) | sdkmanager | sdkmanager |
| Android Build Tools | matches the SDK version | sdkmanager | sdkmanager |
| Android NDK | user-specified (default 28.2.13676358) | sdkmanager | sdkmanager |
| Flutter | stable channel | git | git |

### iOS (`install-ios-macos.sh`)

| Component | Version | Source |
|---|---|---|
| Homebrew | latest | official installer (if missing) |
| Rosetta 2 | — | `softwareupdate` (Apple Silicon only) |
| Xcode | whatever you installed | **Mac App Store (manual)** |
| CocoaPods | latest | Homebrew |
| Flutter | stable channel | git |

The iOS script accepts the Xcode license, runs Xcode's first-launch component install, and precaches the Flutter iOS toolchain. **It does not install Xcode itself** — the full Xcode app can only come from the App Store. The script checks for it and, if it is missing, points you to the App Store and exits so you can install it and re-run.

All scripts also configure the `PATH`, `JAVA_HOME`, `ANDROID_HOME` and related environment variables automatically.

---

## Supported Systems

### Android on Linux (`install-android-linux.sh`)

Detected automatically via `/etc/os-release`. The following distributions are verified:

- ✅ Debian 11 / 12
- ✅ Ubuntu 20.04 / 22.04 / 24.04
- ✅ CentOS Stream 9
- ✅ RHEL 8 / 9
- ✅ Rocky Linux 8 / 9
- ✅ AlmaLinux 8 / 9
- ✅ Fedora

The package manager is selected automatically (`apt` / `dnf` / `yum`).

### Android on macOS (`install-android-macos.sh`)

- ✅ macOS 12+ (Monterey and later)
- ✅ Apple Silicon (M1 / M2 / M3 / M4)
- ✅ Intel Mac

Requires [Homebrew](https://brew.sh/); the script installs it automatically if it is missing.

### iOS on macOS (`install-ios-macos.sh`)

- ✅ macOS 12+ (Monterey and later)
- ✅ Apple Silicon (M1 / M2 / M3 / M4)
- ✅ Intel Mac

Requires the full **Xcode** app — install it from the Mac App Store beforehand, or let the script point you there. Also requires [Homebrew](https://brew.sh/), which is installed automatically if missing.

---

## Which Script to Use

| Your goal | Use this |
|---|---|
| Build Flutter **Android** apps on a remote Linux server (GCP / AWS / Alibaba Cloud, etc.) | `install-android-linux.sh` |
| Build Flutter **Android** apps on local macOS | `install-android-macos.sh` |
| Build Flutter **iOS** apps on macOS | `install-ios-macos.sh` |
| Build on Windows | **Not supported** — use WSL2 + `install-android-linux.sh` for Android |

---

## Usage

### Option 1: Run online (recommended)

```bash
# Android on Linux
bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-android-linux.sh)

# Android on macOS
bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-android-macos.sh)

# iOS on macOS
bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-ios-macos.sh)
```

### Option 2: Download, then run

```bash
# Example: the iOS script (the same pattern works for the others)
curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-ios-macos.sh -o install-ios-macos.sh
chmod +x install-ios-macos.sh
./install-ios-macos.sh
```

### Option 3: Clone the repository

```bash
git clone https://github.com/cxDosx/flutter-installer-cli.git
cd flutter-installer-cli

# Pick the script for your goal
bash install-android-linux.sh   # Android on Linux
bash install-android-macos.sh             # Android on macOS
bash install-ios-macos.sh         # iOS on macOS
```

---

## Input Parameters

The two **Android** scripts take identical input:

| Parameter | Default | Validation rule |
|---|---|---|
| Android SDK version | `33` | Integer, between 21 and 99 |
| Android NDK version | `28.2.13676358` | Must be three numeric segments `X.Y.Z` |

**The script exits immediately on invalid input** and will not install a wrong version. For example:

```
$ bash install-android-linux.sh
Enter the Android SDK version to install [33]: abc
[ERROR] SDK version must be an integer, but got: 'abc'
```

The **iOS** script (`install-ios-macos.sh`) has no version parameters — it just needs a confirmation.

---

## Non-Interactive Mode

By default the scripts are interactive: the Android scripts prompt for the SDK / NDK versions, and all scripts ask for a final confirmation. You can run them fully unattended with command-line flags — useful for CI pipelines, provisioning scripts, and automation.

| Flag | Description | Available in |
|---|---|---|
| `-y`, `--non-interactive` | Skip all prompts and the confirmation step. | all scripts |
| `--sdk <version>` | Android SDK version to install (default: `33`). | Android scripts only |
| `--ndk <version>` | Android NDK version to install (default: `28.2.13676358`). | Android scripts only |
| `-h`, `--help` | Show usage help and exit. | all scripts |

```bash
# Android, all defaults, no prompts
bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-android-linux.sh) -y

# Android with explicit versions
bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-android-macos.sh) --non-interactive --sdk 34 --ndk 27.0.12077973

# iOS, no prompts
bash <(curl -fsSL https://raw.githubusercontent.com/cxDosx/flutter-installer-cli/main/install-ios-macos.sh) -y
```

A few details:

- `--sdk` / `--ndk` can be passed **without** `--non-interactive`. The value is then shown as the default in the interactive prompt, so you can still review or change it.
- In an environment with **no TTY at all** (such as a CI job), the scripts detect this and behave as if `--non-interactive` was passed, even without the flag.
- Non-interactive mode only removes the script's *own* prompts. It cannot suppress a `sudo` password prompt (Linux / macOS) or a password prompt from the Homebrew installer (macOS). For a truly unattended run, use `root` / passwordless `sudo`, and on macOS pre-install Homebrew. When `--non-interactive` is set, the macOS scripts also pass `NONINTERACTIVE=1` to the Homebrew installer to skip its "press RETURN" step.
- The iOS script cannot install Xcode for you in any mode. If Xcode is missing, install it from the App Store first (see [iOS notes](#ios-on-macos-install-ios-macossh)).

---

## Install Locations

| Item | Path |
|---|---|
| Android SDK (Android scripts) | `~/android-sdk` |
| Flutter (all scripts) | `~/flutter` |
| Environment variables (Linux bash) | `~/.bashrc` |
| Environment variables (Linux zsh) | `~/.zshrc` |
| Environment variables (macOS, default zsh) | `~/.zshrc` |
| Environment variables (macOS legacy bash) | `~/.bash_profile` |

The environment variables are written inside a marked block: the Android scripts use a `flutter-android-env` block, the iOS script uses a `flutter-ios-env` block. After installation, open a new terminal or `source` the relevant file to apply them.

---

## Verify the Installation

```bash
# Linux
source ~/.bashrc

# macOS
source ~/.zshrc

flutter doctor
```

For **Android**, look at these two lines:

```
[✓] Flutter
[✓] Android toolchain
```

For **iOS**, look at these two lines:

```
[✓] Flutter
[✓] Xcode - develop for iOS and macOS
```

As long as the relevant lines show ✓, you can build for that platform. The other items (Chrome, Linux desktop, Android Studio) are irrelevant to command-line builds and can be ignored.

---

## Build Your Project

```bash
cd ~/your-flutter-project
flutter pub get
```

### Android

```bash
# Debug APK (fast, unsigned)
flutter build apk --debug

# Release APK (split per ABI)
flutter build apk --release --split-per-abi

# AAB (the format required for Google Play)
flutter build appbundle --release
```

Output locations:

- `build/app/outputs/flutter-apk/*.apk`
- `build/app/outputs/bundle/release/*.aab`

### iOS

```bash
# App for the iOS Simulator (no code signing required)
flutter build ios --simulator

# IPA for distribution (requires an Apple Developer account set up in Xcode)
flutter build ipa --release
```

Output locations:

- `build/ios/iphonesimulator/Runner.app`
- `build/ios/ipa/*.ipa`

---

## Idempotency

The scripts are **idempotent** — running them again will not reinstall things:

- Existing cmdline-tools / Flutter directories are skipped
- An NDK that is already fully installed is skipped
- An incomplete leftover NDK directory (missing `source.properties`) is cleaned up and reinstalled
- Already-installed Homebrew, Rosetta 2, Xcode and CocoaPods are detected and skipped
- The environment-variable block is wrapped in markers, so re-runs replace it instead of appending duplicates

---

## FAQ

### Q: Interactive input does not work when run via `curl ... | bash`

That is expected. Use the `bash <(curl ...)` form instead, or download the script locally and run it.

### Q: Installation fails with "NDK installation failed"

This is usually caused by a network interruption that left the download incomplete, or by a version number that does not exist in the Google repository.

The NDK version number must be **exact** (including the long trailing digits). Check available versions in the [Android NDK Revision History](https://developer.android.com/ndk/downloads/revision_history).

### Q: Installation fails with "could not find `build-tools;XX.0.0`"

By default the Android scripts install Build Tools version `<SDK version>.0.0`. Almost every modern SDK version has a matching `.0.0` Build Tools, but a few do not. If you hit this, look up an existing version in the [Android SDK Build Tools list](https://developer.android.com/tools/releases/build-tools) and re-run the script with the corresponding SDK version.

### Q: `Flutter requires Android SDK XX and Build Tools XX.X.X`

A Flutter SDK upgrade may require a newer Android SDK. Just re-run the script and enter the new SDK version number. Multiple SDK versions can coexist.

### Q: The iOS script says "The full Xcode app is not installed"

iOS builds require the full Xcode app, which can only be installed from the Mac App Store (a free Apple ID is enough) — it cannot be installed by a script. Install Xcode, open it once so it can finish its first-time setup, then re-run `install-ios-macos.sh`. The script will then accept the license and install the remaining components for you.

### Q: iOS build fails with CocoaPods errors

Make sure `pod` is on your `PATH` (`source ~/.zshrc` or open a new terminal). Inside your project, `cd ios && pod install` can surface more detailed errors. On Apple Silicon, the iOS script installs Rosetta 2 because some older pods still need it.

### Q: Homebrew installs slowly on macOS

You can configure a faster regional mirror before running the script. See [Homebrew mirror help — TUNA mirror](https://mirrors.tuna.tsinghua.edu.cn/help/homebrew/).

### Q: macOS says `java_home cannot find 17`

This usually happens when Homebrew installs the JDK but does not link it into the system directory. The Android macOS script handles this step automatically (`ln -sfn` into `/Library/Java/JavaVirtualMachines`), which requires your `sudo` password.

### Q: Can it run non-interactively (all defaults)?

Yes. Pass the `-y` / `--non-interactive` flag, optionally with `--sdk` / `--ndk` (Android only) to choose versions — see [Non-Interactive Mode](#non-interactive-mode) for details and examples. In an environment with no TTY at all (such as CI), the scripts switch to non-interactive behavior automatically, even without the flag.

---

## Uninstall

### Android on Linux

```bash
rm -rf ~/android-sdk ~/flutter
# Then manually edit ~/.bashrc / ~/.zshrc and remove the block wrapped
# by the flutter-android-env markers
```

### Android on macOS

```bash
rm -rf ~/android-sdk ~/flutter

# Uninstall the JDK (optional)
brew uninstall openjdk@17
sudo rm -f /Library/Java/JavaVirtualMachines/openjdk-17.jdk

# Then manually edit ~/.zshrc and remove the block wrapped
# by the flutter-android-env markers
```

### iOS on macOS

```bash
rm -rf ~/flutter

# Uninstall CocoaPods (optional)
brew uninstall cocoapods

# Then manually edit ~/.zshrc and remove the block wrapped
# by the flutter-ios-env markers
```

> Xcode and Rosetta 2 are left in place — remove Xcode from the Applications folder yourself if you no longer need it.

---

## License

[MIT](LICENSE)
