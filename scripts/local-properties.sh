#!/usr/bin/env bash
# Write a plugin's gitignored local.properties: the machine-local paths to the
# Android SDK and the ATAK SDK. A plugin without this file does not build, and
# git does not carry it (it is gitignored on purpose — it holds real paths and,
# optionally, Artifactory credentials).
#
#   local-properties.sh <plugin dir> [<ATAK SDK dir>]
#
# The SDK defaults to the newest unpacked one matching the plugin's own
# ext.ATAK_VERSION, else $ATAK_SDK. An existing file is kept: it may have been
# retargeted on purpose.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

DIR="${1:-}"; SDK="${2:-}"
[ -n "$DIR" ] && [ -f "$DIR/app/build.gradle" ] || { echo "usage: $0 <plugin dir> [<ATAK SDK dir>]" >&2; exit 2; }
OUT="$DIR/local.properties"
if [ -e "$OUT" ]; then
    echo "    keeping existing $OUT"; exit 0
fi
if [ -z "$SDK" ]; then
    WANT="$(gradle_prop "$DIR/app/build.gradle" ATAK_VERSION)"
    [ -n "$WANT" ] && SDK="$(sdk_for "$WANT")" || true
    [ -n "$SDK" ] || SDK="$ATAK_SDK"
fi
[ -d "${SDK:-/nonexistent}" ] || { echo "error: no ATAK SDK at '${SDK:-}'" >&2; exit 1; }
cat > "$OUT" <<PROPS
# Machine-local. Gitignored: never commit real paths or credentials.
# Offline build against the SDK unpacked outside the repo.
sdk.dir=$ANDROID_HOME
sdk.path=$SDK
takdev.plugin=$SDK/atak-gradle-takdev.jar

# Artifactory build (alternative to offline) — uncomment and fill in if you have
# a tak.gov Artifactory account. Setting takrepo.url switches takdev out of
# offline mode, and is the only way a CI runner can build without the SDK, which
# the license forbids you to commit.
#takrepo.url=https://artifacts.tak.gov/artifactory/maven
#takrepo.user=
#takrepo.password=
PROPS
echo "    wrote $OUT (sdk.path=$SDK)"
