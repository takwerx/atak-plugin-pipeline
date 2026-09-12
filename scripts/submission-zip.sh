#!/usr/bin/env bash
# Build a tak.gov source-submission zip for a plugin, then verify it.
#
#   submission-zip.sh <PluginName> [--no-build]
#
# tak.gov builds the plugin FROM SOURCE: you submit a zip of the source tree and
# their pipeline runs ./gradlew itself and signs the APK. Do not submit a built
# APK. Every rule encoded here is a rejected or silently-broken submission:
#
#   - every path inside the zip sits under a single "<PluginName>/" root, and
#     that root name becomes the APK name
#   - gradle/wrapper/gradle-wrapper.jar MUST be included, or their ./gradlew
#     cannot bootstrap (Could not find or load main class GradleWrapperMain)
#   - .takdev/, app/libs/ (the ~30 MB SDK main.jar), build output,
#     local.properties and any keystore must NOT be included; tak.gov resolves
#     the SDK itself, and the SDK license forbids you to ship it
#   - docs/user_manual/ IS included when present — tak.gov compiles the PDF from
#     it, so it needs the source, not a built PDF. The rest of docs/ stays out.
#
# By default the zip is extracted to a temp dir and built, because a zip that
# does not build from a clean extract will not build on tak.gov either.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/env.sh"

NAME="${1:-}"
DO_BUILD=1
[ "${2:-}" = "--no-build" ] && DO_BUILD=0
[ -n "$NAME" ] || { echo "usage: $0 <PluginName> [--no-build]" >&2; exit 1; }

PROJECT="$(plugin_dir "$NAME")" || exit 1
DIST="$ATAK_DIST"

# Naming: <Name>-<PLUGIN_VERSION>-<ATAK_VERSION>.zip, both read from the tree
# being zipped, so the filename always says what is inside. One zip per ATAK
# target: retarget ext.ATAK_VERSION (and local.properties' sdk.path), re-run,
# restore.
PLUGIN_VERSION="$(gradle_prop "$PROJECT/app/build.gradle" PLUGIN_VERSION)"
ATAK_VERSION="$(gradle_prop "$PROJECT/app/build.gradle" ATAK_VERSION)"
[ -n "$PLUGIN_VERSION" ] && [ -n "$ATAK_VERSION" ] || {
    echo "error: could not read PLUGIN_VERSION/ATAK_VERSION from $PROJECT/app/build.gradle" >&2; exit 1; }
OUT="$DIST/$NAME-$PLUGIN_VERSION-$ATAK_VERSION.zip"

# A release must be an update the fleet's MDM can push: above every release
# already signed, and never the same version twice for one target.
echo "==> version code (the MDM must see this as an update)"
"$HERE/check-version-code.sh" "$NAME" --target "$ATAK_VERSION" || {
    echo "error: not zipping a version an MDM could not push as an update — bump PLUGIN_VERSION" >&2; exit 1; }

mkdir -p "$DIST"
rm -f "$OUT"

# The zip's single root directory must be named for the plugin. Rather than
# requiring the project directory to be called that (it is, in a monorepo; it
# may not be if the plugin has its own repo), stage the include list into
# <tmp>/<PluginName>/ and zip from there. Same zip either way.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ROOT="$STAGE/$NAME"
mkdir -p "$ROOT"

CANDIDATES=(
    "app/build.gradle"
    "app/proguard-gradle.txt"
    "app/proguard-gradle-repackage.txt"
    "app/src/test"
    "app/src/main/AndroidManifest.xml"
    "app/src/main/assets"
    "app/src/main/res"
    "app/src/main/java"
    "app/src/gov"
    "template.local.properties"
    "README.md"
    "docs/user_manual"
    "gradle"
    "gradlew"
    "gradlew.bat"
    "build.gradle"
    "gradle.properties"
    "settings.gradle"
)
for path in "${CANDIDATES[@]}"; do
    if [ -e "$PROJECT/$path" ]; then
        mkdir -p "$ROOT/$(dirname "$path")"
        cp -R "$PROJECT/$path" "$ROOT/$path"
    else
        echo "    (skipping absent $path)"
    fi
done

# usermanual.pdf is BUILD OUTPUT that lands in the source tree: a local
# -PbuildManual run writes it into app/src/main/assets/. tak.gov compiles the
# manual from docs/user_manual/ itself, so a stale local PDF riding along would
# be both wrong and megabytes of it.
rm -f "$ROOT/app/src/main/assets/usermanual.pdf"
find "$ROOT" -name '.DS_Store' -delete
rm -rf "$ROOT/.gradle" "$ROOT/build" "$ROOT/app/build" "$ROOT/.takdev"

echo "==> zipping $NAME/ -> $OUT"
( cd "$STAGE" && zip -rq "$OUT" "$NAME" )

# --- point of contact ---------------------------------------------------------
# tak.gov requires a contact address in the submission README. A public repo must
# never carry one — the scrub blocks email addresses, and the same README is what
# users read. Those two requirements are only compatible if the address never
# enters the tracked tree at all: keep it in one machine-local file and inject it
# into the README *inside the zip*, after the tracked tree has been zipped.
POC_FILE="${ATAK_POC_FILE:-$ATAK_CONFIG_DIR/submission-poc.txt}"
POC_LINE=""
if [ -f "$POC_FILE" ]; then
    # A file of comments only is the normal state, and grep matching nothing
    # exits 1 — which under `set -e` would abort after the zip was written.
    POC_LINE="$(grep -v '^[[:space:]]*#' "$POC_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d' | head -1 || true)"
fi
if [ -n "$POC_LINE" ]; then
    POC_TMP="$(mktemp -d)"
    ( cd "$POC_TMP" && unzip -q "$OUT" "$NAME/README.md" )
    # Insert directly beneath the existing contact block, keeping the heading.
    awk -v poc="$POC_LINE" '
        /^POINT OF CONTACTS$/ { inpoc = 1 }
        inpoc && /^https:\/\// { print; print poc; inpoc = 0; next }
        { print }
    ' "$POC_TMP/$NAME/README.md" > "$POC_TMP/README.new"
    if ! grep -qF "$POC_LINE" "$POC_TMP/README.new"; then
        echo "error: could not place the point of contact in README.md" >&2
        rm -rf "$POC_TMP"; exit 1
    fi
    mv "$POC_TMP/README.new" "$POC_TMP/$NAME/README.md"
    ( cd "$POC_TMP" && zip -q "$OUT" "$NAME/README.md" )
    rm -rf "$POC_TMP"
    echo "==> point of contact injected into the zip's README (not the tracked one)"
elif [ -f "$POC_FILE" ]; then
    echo "==> $POC_FILE holds no address — zip README carries the public contact line only"
else
    echo "==> no $POC_FILE — zip README carries the public contact line only"
    echo "    (tak.gov wants a real address in POINT OF CONTACTS; put one line in that file)"
fi

echo
echo "==> verifying $OUT"
FAIL=0
check() { # description, offending-lines
    if [ -z "$2" ]; then
        echo "  PASS  $1"
    else
        echo "  FAIL  $1"
        printf '        %s\n' $2
        FAIL=1
    fi
}

SIZE_BYTES=$(wc -c < "$OUT" | tr -d ' ')
SIZE_HUMAN=$(du -h "$OUT" | cut -f1 | tr -d ' ')
# Without a manual a submission is a few hundred KB, and anything larger means
# the SDK jar or build output crept in. A manual legitimately carries its own
# fonts, title art and screenshots, so the ceiling moves — but it is still a
# ceiling, well under the ~30 MB that main.jar alone would add.
if [ -d "$PROJECT/docs/user_manual" ]; then
    SIZE_LIMIT=12000000
    SIZE_NOTE="with the user manual"
else
    SIZE_LIMIT=2000000
    SIZE_NOTE="expected KB, not MB"
fi
if [ "$SIZE_BYTES" -lt "$SIZE_LIMIT" ]; then
    echo "  PASS  size is $SIZE_HUMAN ($SIZE_NOTE)"
else
    echo "  FAIL  size is $SIZE_HUMAN — something large is in the zip"
    FAIL=1
fi

check "every path is under $NAME/"        "$(zipinfo -1 "$OUT" | grep -v "^$NAME/" || true)"
check "no app/libs/ or .takdev/"          "$(zipinfo -1 "$OUT" | grep -E "(libs/|takdev)" || true)"
check "no docs/ beyond user_manual"       "$(zipinfo -1 "$OUT" | grep -E "^$NAME/docs/" | grep -v "^$NAME/docs/user_manual/" || true)"
check "no build output"                   "$(zipinfo -1 "$OUT" | grep -E "(/build/|^$NAME/\.gradle/)" || true)"
check "no built manual in assets"         "$(zipinfo -1 "$OUT" | grep -E "^$NAME/app/src/main/assets/usermanual\.pdf$" || true)"
check "only gradle-wrapper.jar as binary" "$(zipinfo -1 "$OUT" | grep -E '\.(jar|aar)$' | grep -v 'gradle-wrapper\.jar' || true)"
check "no real local.properties/keystore" "$(zipinfo -1 "$OUT" | grep -E "local\.properties|keystore" | grep -v 'template\.local\.properties' || true)"

# Capture rather than `grep -q`: under `set -o pipefail`, grep -q exits early,
# zipinfo takes SIGPIPE, and the pipeline reports failure even when the match was
# found. This trap catches every "the thing IS there but reads as missing" bug in
# this file.
WRAPPER_JAR="$(zipinfo -1 "$OUT" | grep 'gradle/wrapper/gradle-wrapper.jar' || true)"
if [ -n "$WRAPPER_JAR" ]; then
    echo "  PASS  gradle-wrapper.jar is included"
else
    echo "  FAIL  gradle-wrapper.jar is MISSING — tak.gov's ./gradlew cannot bootstrap"
    FAIL=1
fi

if grep -q "atakplugin\.$NAME" "$PROJECT/app/proguard-gradle-repackage.txt" 2>/dev/null; then
    echo "  PASS  proguard repackage descriptor is atakplugin.$NAME"
else
    echo "  FAIL  proguard-gradle-repackage.txt is not plugin-specific"
    FAIL=1
fi

if [ "$DO_BUILD" = 1 ]; then
    echo
    echo "==> publish scrub of the zip contents (PII, credentials, forbidden files)"
    SCRUB_DIR="$(mktemp -d)"
    ( cd "$SCRUB_DIR" && unzip -q "$OUT" )
    if POC_ALLOW="$POC_LINE" "$HERE/publish-scrub.sh" "$SCRUB_DIR"; then
        echo "  PASS  publish scrub"
    else
        echo "  FAIL  publish scrub — see findings above"; FAIL=1
    fi
    rm -rf "$SCRUB_DIR"

    echo "==> clean-extract build test (a zip that fails here fails on tak.gov)"
    TMP="$(mktemp -d)"
    unzip -q "$OUT" -d "$TMP"
    # Build against the SDK this plugin TARGETS, not whatever ATAK_SDK defaults
    # to. A plugin tested against the wrong API either fails for reasons tak.gov
    # will not see, or passes while hiding a real incompatibility — classes come
    # and go between ATAK releases.
    WANT="$(gradle_prop "$TMP/$NAME/app/build.gradle" ATAK_VERSION)"
    BUILD_SDK="$ATAK_SDK"
    if [ -n "$WANT" ]; then
        MATCH="$(sdk_for "$WANT")"
        if [ -n "$MATCH" ]; then BUILD_SDK="$MATCH"
        else echo "  WARN  no SDK found for ATAK_VERSION $WANT; using $ATAK_SDK"; fi
    fi
    echo "  ..    building against $(basename "$BUILD_SDK") (plugin targets $WANT)"
    cat > "$TMP/$NAME/local.properties" <<PROPS
sdk.dir=$ANDROID_HOME
sdk.path=$BUILD_SDK
takdev.plugin=$BUILD_SDK/atak-gradle-takdev.jar
PROPS

    # ATAK_CI=1, which is the whole point: without it gradle/typst.gradle never
    # runs, so this build proves the CODE compiles and says NOTHING about the
    # manual — while tak.gov builds WITH it. And typst.gradle degrades to a
    # warning when the manual cannot be built, so that failure is silent end to
    # end: every local gate passes, tak.gov produces an APK with no manual in it,
    # and nothing anywhere reports an error.
    #
    # typst.gradle downloads a linux-musl binary it cannot run here but prefers a
    # ./typst in the project root, so a local typst is linked in when available.
    # Without one the manual check is SKIPPED and says so rather than passing
    # quietly.
    LOCAL_TYPST="$(command -v typst || true)"
    [ -n "$LOCAL_TYPST" ] && ln -sf "$LOCAL_TYPST" "$TMP/$NAME/typst"

    if ( cd "$TMP/$NAME" && ATAK_CI=1 ./gradlew assembleCivDebug -q >/dev/null 2>&1 ); then
        echo "  PASS  extracted zip builds assembleCivDebug (with ATAK_CI=1)"
        BUILT_APK="$(ls "$TMP/$NAME"/app/build/outputs/apk/civ/debug/*.apk 2>/dev/null | head -1)"

        # The versionCode this APK carries is the one tak.gov's will carry: this
        # build has no .git either. The SDK's getVersionCode() returns 1 here, and
        # a versionCode-1 release is not an update to any MDM.
        AAPT="$(aapt_bin)"
        EXPECT_CODE="$(version_code "$PLUGIN_VERSION")"
        GOT_CODE=""
        if [ -n "$AAPT" ] && [ -n "$BUILT_APK" ]; then
            GOT_CODE="$("$AAPT" dump badging "$BUILT_APK" 2>/dev/null \
                | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")"
        fi
        if [ -z "$GOT_CODE" ]; then
            echo "  FAIL  could not read versionCode from the built APK (aapt: ${AAPT:-none})"
            FAIL=1
        elif [ "$GOT_CODE" = "$EXPECT_CODE" ] && [ "$GOT_CODE" -gt 1 ]; then
            echo "  PASS  versionCode=$GOT_CODE from PLUGIN_VERSION $PLUGIN_VERSION (no .git needed)"
        else
            echo "  FAIL  versionCode=$GOT_CODE, expected $EXPECT_CODE from PLUGIN_VERSION $PLUGIN_VERSION."
            echo "        A signed release with versionCode 1 cannot be pushed as an update by"
            echo "        any MDM. app/build.gradle must set versionCode = PLUGIN_VERSION_CODE,"
            echo "        not getVersionCode()."
            FAIL=1
        fi

        if [ -d "$TMP/$NAME/docs/user_manual" ]; then
            if [ -z "$LOCAL_TYPST" ]; then
                echo "  SKIP  manual not checked — no typst on PATH (install it: the"
                echo "        plugin has docs/user_manual/, so tak.gov WILL build one)"
            elif MANUAL_LINE="$(unzip -l "$BUILT_APK" 2>/dev/null || true)" &&
                    case "$MANUAL_LINE" in *assets/usermanual.pdf*) true ;;
                                           *) false ;; esac; then
                MANUAL_BYTES="$(printf '%s\n' "$MANUAL_LINE" | awk '/assets\/usermanual.pdf/{print $1}')"
                echo "  PASS  manual built into the APK ($MANUAL_BYTES bytes)"
            else
                echo "  FAIL  docs/user_manual/ exists but NO assets/usermanual.pdf"
                echo "        landed in the APK. tak.gov will sign a plugin whose"
                echo "        manual cannot be opened, and will not tell you."
                FAIL=1
            fi
        fi
    else
        echo "  FAIL  extracted zip does NOT build — rerun by hand for the error:"
        echo "        unzip $OUT -d /tmp/x && cd /tmp/x/$NAME && ATAK_CI=1 ./gradlew assembleCivDebug"
        FAIL=1
    fi
    rm -rf "$TMP"
fi

echo
if [ "$FAIL" = 0 ]; then
    echo "$OUT ($SIZE_HUMAN) — ready to submit"
else
    echo "$OUT — FIX THE FAILURES ABOVE BEFORE SUBMITTING"
    exit 1
fi
