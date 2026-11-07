#!/data/data/com.termux/files/usr/bin/bash
# Sets up Termux to build, install and debug Android apps on the same phone.
#   bash install.sh
# Safe to re-run. Override versions with SDK_PLATFORM=36 BUILD_TOOLS=36.0.0 bash install.sh
set -eu  # no pipefail: `yes | pkg` would fail on SIGPIPE

HERE="$(cd "$(dirname "$0")" && pwd)"
BASHRC="$HOME/.bashrc"
SDK="$HOME/android-sdk"
SDK_PLATFORM="${SDK_PLATFORM:-36}"
BUILD_TOOLS="${BUILD_TOOLS:-36.0.0}"
GRADLE_PROPS="$HOME/.gradle/gradle.properties"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

[ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ] || { warn "Run this inside Termux."; exit 1; }
[ "$(uname -m)" = aarch64 ] || warn "Only tested on aarch64; continuing anyway."

info "Installing packages (JDK, Gradle, Kotlin, aapt2, adb, apksigner, d8)"
yes | pkg update -y >/dev/null 2>&1 || true
yes | DEBIAN_FRONTEND=noninteractive pkg install -y -o Dpkg::Options::=--force-confnew \
  openjdk-21 gradle kotlin aapt2 android-tools apksigner d8 wget unzip termux-exec >/dev/null

info "Adding Android environment to $BASHRC"
touch "$BASHRC"
snippet="$HERE/config/bashrc.d/android-env.sh"
# Replace any previous copy of the block so re-running applies updates.
sed -i '/^# >>> termux-android-dev >>>$/,/^# <<< termux-android-dev <<<$/d' "$BASHRC"
cat "$snippet" >> "$BASHRC"
# shellcheck source=config/bashrc.d/android-env.sh
. "$snippet"

if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  info "Downloading Android SDK command-line tools"
  zip_name="$(curl -fsSL https://developer.android.com/studio \
    | grep -oE 'commandlinetools-linux-[0-9]+_latest\.zip' | head -1)"
  [ -n "$zip_name" ] || { warn "Could not find the command-line tools download link."; exit 1; }
  tmp="$(mktemp -d)"
  wget -q "https://dl.google.com/android/repository/$zip_name" -O "$tmp/clt.zip"
  mkdir -p "$SDK/cmdline-tools"
  unzip -q "$tmp/clt.zip" -d "$tmp"
  rm -rf "$SDK/cmdline-tools/latest"
  mv "$tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
  rm -rf "$tmp"
fi
# Termux has no /usr/bin/env, which the SDK scripts' shebangs use.
sed -i "1s|^#!/usr/bin/env sh|#!$PREFIX/bin/sh|" "$SDK"/cmdline-tools/latest/bin/*

info "Installing SDK platform $SDK_PLATFORM, build-tools $BUILD_TOOLS, platform-tools"
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager "platforms;android-$SDK_PLATFORM" "build-tools;$BUILD_TOOLS" platform-tools >/dev/null

# Google ships x86_64 binaries; replace them with Termux's native builds.
info "Linking native aapt2/adb/fastboot into the SDK"
for bt in "$SDK"/build-tools/*/; do
  ln -sf "$PREFIX/bin/aapt2" "$bt/aapt2"
done
for b in adb fastboot; do
  ln -sf "$PREFIX/bin/$b" "$SDK/platform-tools/$b"
done

info "Pointing Gradle at the native aapt2 ($GRADLE_PROPS)"
mkdir -p "$(dirname "$GRADLE_PROPS")"; touch "$GRADLE_PROPS"
grep -q '^android.aapt2FromMavenOverride=' "$GRADLE_PROPS" \
  || echo "android.aapt2FromMavenOverride=$PREFIX/bin/aapt2" >> "$GRADLE_PROPS"
grep -q '^org.gradle.jvmargs=' "$GRADLE_PROPS" \
  || echo "org.gradle.jvmargs=-Xmx2g" >> "$GRADLE_PROPS"

info "Installing helper commands: adb-local, adb-debug"
for f in "$HERE"/bin/*; do
  install -m 755 "$f" "$PREFIX/bin/$(basename "$f")"
done

info "Done. Open a new Termux session (or run: source ~/.bashrc)."
cat <<'EOF'
Next:
  1. Build the sample:  cd sample/HelloAndroid && ./gradlew assembleDebug
  2. Connect adb:       adb-local      (see README for first-time pairing)
  3. Install & debug:   ./gradlew installDebug && adb-debug com.example.hello
EOF
