#!/usr/bin/env bash
# Source this to get the ATAK plugin build environment plus the helpers every
# other script here uses:
#
#   source "$(dirname "$0")/env.sh"
#
# Nothing in this file is a secret. Every value can be overridden by exporting it
# first; the defaults are what a stock install looks like.
#
#   JAVA_HOME           JDK 17. ATAK plugins do not build on 21.
#   ANDROID_HOME        Android SDK (needs platform-tools and build-tools for aapt)
#   ATAK_SDK_ROOT       where unpacked ATAK CIV SDKs live (default ~/atak-sdk)
#   ATAK_SDK            one SDK, e.g. $ATAK_SDK_ROOT/ATAK-CIV-5.8.0.3
#   ATAK_DIST           submission zips, and every signed APK under signed/
#   ATAK_PLUGINS_ROOT   parent directory of plugin projects, if you keep a monorepo
#   ATAK_CONFIG_DIR     machine-local config that must never enter a repo
#                       (default ~/.config/atak-plugins)

# --- toolchain --------------------------------------------------------------
if [ -z "${JAVA_HOME:-}" ]; then
    if [ -x /usr/libexec/java_home ]; then
        JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
    fi
    if [ -z "${JAVA_HOME:-}" ]; then
        for c in /opt/homebrew/opt/openjdk@17 /usr/local/opt/openjdk@17 \
                 /usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/jvm/java-17-openjdk; do
            [ -x "$c/bin/javac" ] && { JAVA_HOME="$c"; break; }
        done
    fi
fi
export JAVA_HOME="${JAVA_HOME:-}"

if [ -z "${ANDROID_HOME:-}" ]; then
    for c in "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk" \
             /opt/homebrew/share/android-commandlinetools /usr/local/share/android-commandlinetools; do
        [ -n "$c" ] && [ -d "$c" ] && { ANDROID_HOME="$c"; break; }
    done
fi
export ANDROID_HOME="${ANDROID_HOME:-}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}${ANDROID_HOME:+$ANDROID_HOME/platform-tools:}$PATH"

# --- the ATAK SDK, which lives OUTSIDE every repo ---------------------------
# Its license forbids redistribution: main.jar, atak.apk, atak-gradle-takdev.jar
# and android_keystore are never committed, in a public or a private repo. Each
# plugin reaches the SDK through sdk.path in its gitignored local.properties.
export ATAK_SDK_ROOT="${ATAK_SDK_ROOT:-$HOME/atak-sdk}"
if [ -z "${ATAK_SDK:-}" ]; then
    ATAK_SDK="$(ls -d "$ATAK_SDK_ROOT"/ATAK-CIV-* 2>/dev/null | sort -V | tail -1)"
fi
export ATAK_SDK="${ATAK_SDK:-}"

# Build artifacts live outside every checkout, in one place: a zip written into
# one checkout is invisible from another. Signed APKs returned by tak.gov are
# filed under $ATAK_DIST/signed and are what "is this version an update" is
# measured against.
export ATAK_DIST="${ATAK_DIST:-$HOME/atak-dist}"
export ATAK_CONFIG_DIR="${ATAK_CONFIG_DIR:-$HOME/.config/atak-plugins}"

# --- layout helpers ---------------------------------------------------------
# These scripts do not care whether you keep one repo per plugin or a monorepo
# with plugins/<Name>/. Everything resolves through plugin_dir.

repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

# plugin_dir <Name> -> the directory holding app/build.gradle, or empty + status 1
plugin_dir() {
    local name="$1" root cand
    root="$(repo_root)"
    for cand in "${ATAK_PLUGINS_ROOT:+$ATAK_PLUGINS_ROOT/$name}" \
                "$root/plugins/$name" "$root/$name" "$root"; do
        [ -n "$cand" ] || continue
        [ -f "$cand/app/build.gradle" ] || continue
        # The last two candidates are only right if the project really is this
        # plugin: rootProject.name is the plugin's identity everywhere else
        # (the APK name, the proguard descriptor), so it decides here too.
        case "$cand" in
            "$root"|"$root/$name")
                grep -q "rootProject.name *= *['\"]$name['\"]" "$cand/settings.gradle" 2>/dev/null || continue ;;
        esac
        printf '%s\n' "$cand"
        return 0
    done
    echo "error: no plugin '$name' found. Looked in ${ATAK_PLUGINS_ROOT:+$ATAK_PLUGINS_ROOT/$name, }$root/plugins/$name, $root/$name, $root." >&2
    echo "       Run this from the repo holding the plugin, or export ATAK_PLUGINS_ROOT." >&2
    return 1
}

# gradle_prop <build.gradle> <ext property>  e.g. gradle_prop app/build.gradle PLUGIN_VERSION
gradle_prop() {
    sed -nE "s/^[[:space:]]*ext\.$2[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"'].*/\1/p" "$1" | head -1
}

# version_code <1.3> -> 10300. The same arithmetic as PLUGIN_VERSION_CODE in
# app/build.gradle. Empty + status 1 if the version is not MAJOR.MINOR[.PATCH].
version_code() {
    printf '%s' "$1" | awk -F. '{
        if ($1 !~ /^[0-9]+$/ || ($2 != "" && $2 !~ /^[0-9]+$/) ||
            ($3 != "" && $3 !~ /^[0-9]+$/) || NF > 3) exit 1
        printf "%d", $1*10000 + $2*100 + $3 }'
}

# sdk_for <5.8.0> -> the newest unpacked SDK matching that ATAK version
sdk_for() {
    ls -d "$ATAK_SDK_ROOT"/ATAK-CIV-"$1"* 2>/dev/null | sort -V | tail -1
}

# aapt / keytool, wherever this machine keeps them
aapt_bin()    { ls "$ANDROID_HOME"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1; }
keytool_bin() { echo "${JAVA_HOME:+$JAVA_HOME/bin/keytool}"; }

if [ ! -d "${ATAK_SDK:-/nonexistent}" ]; then
    echo "warning: no ATAK SDK found under $ATAK_SDK_ROOT — download one from tak.gov and unpack it there" >&2
fi
