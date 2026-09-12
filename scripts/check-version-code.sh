#!/usr/bin/env bash
# check-version-code: a plugin release has to be a real Android upgrade, or the
# MDM that pushes it to a fleet will refuse it over the build already installed.
#
# The trap: tak.gov builds from a source zip with no .git in it, so the SDK
# template's git-derived versionCode falls back to 1 — on EVERY signed release.
# Android and every MDM decide "is this an update" from that integer alone
# (versionName is a display string), so two releases both carrying 1 are the same
# build as far as the fleet is concerned, and the second one is never pushed.
# Sideloading hides it completely: the system installer happily replaces a
# same-code package.
#
# What "an update" needs, checked here:
#   - app/build.gradle derives versionCode from PLUGIN_VERSION
#     (MAJOR*10000 + MINOR*100 + PATCH), never from git
#   - the version is above every release already signed ($ATAK_DIST/signed keeps
#     every signed APK), so a resubmission is a NEW version, not the same one
#     again. --target narrows "already signed" to one ATAK target: a target that
#     failed at tak.gov may be resubmitted under the same version while no signed
#     APK exists for it
#   - --signed: this version's signed APKs are all present, one per target the
#     README links (a missing target strands every device on that ATAK), each
#     carries that code, the same package name and the same signing certificate
#     as the last signed release
#   - --live: no release on the plugin's public repo is this version or newer
#
#   check-version-code.sh <Plugin>                    # tree + signed dir, no network
#   check-version-code.sh <Plugin> --target 5.7.0     # what the submission gate runs
#   check-version-code.sh <Plugin> --signed [--live]  # before publishing a release
#
# Exit 1 on any finding, 2 on usage.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

PLUGIN="${1:-}"; [ $# -gt 0 ] && shift
SIGNED=0; LIVE=0; TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --signed) SIGNED=1 ;;
    --live)   LIVE=1 ;;
    --target) TARGET="${2:-}"; shift ;;
    *) echo "usage: $0 <Plugin> [--target <atak>] [--signed] [--live]" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$PLUGIN" ] || { echo "usage: $0 <Plugin> [--target <atak>] [--signed] [--live]" >&2; exit 2; }
DIR="$(plugin_dir "$PLUGIN")" || exit 2
GRADLE="$DIR/app/build.gradle"

VER="$(gradle_prop "$GRADLE" PLUGIN_VERSION)"
[ -n "$VER" ] || { echo "check-version-code: PLUGIN_VERSION not found in $GRADLE" >&2; exit 2; }

EXPECT="$(version_code "$VER")" || EXPECT=""
if [ -z "$EXPECT" ] || [ "$EXPECT" -le 1 ]; then
  echo "check-version-code: FAIL ($PLUGIN): PLUGIN_VERSION '$VER' is not MAJOR.MINOR[.PATCH] digits" >&2; exit 1
fi

fail=0
finding() { echo "  FAIL: $*"; fail=1; }

# 1. The tree derives the code from PLUGIN_VERSION. The submission gate proves
#    the built APK agrees; this catches a plugin that never got the change.
grep -qE '^[[:space:]]*defaultConfig\.versionCode[[:space:]]*=[[:space:]]*PLUGIN_VERSION_CODE\b' "$GRADLE" \
  || finding "app/build.gradle does not set defaultConfig.versionCode = PLUGIN_VERSION_CODE (the SDK's getVersionCode() is 1 at tak.gov)"
grep -qE '^[[:space:]]*ext\.PLUGIN_VERSION_CODE[[:space:]]*=' "$GRADLE" \
  || finding "app/build.gradle does not define ext.PLUGIN_VERSION_CODE"

# 2. Above every release already signed. The version in the file name is the
#    truth for builds from before the fix: they all read versionCode 1.
SIGNED_DIR="${ATAK_SIGNED_DIR:-$ATAK_DIST/signed}"
if [ ! -d "$SIGNED_DIR" ]; then
  # No folder at all is the normal state for a first plugin, and refusing there
  # would block the first submission anyone ever builds. It is only a finding
  # when an actual release is being validated (--signed), where the APKs have to
  # exist. Otherwise say plainly what is not being checked.
  if [ "$SIGNED" = 1 ]; then
    finding "no signed-release folder at $SIGNED_DIR (set ATAK_SIGNED_DIR); this release's APKs cannot be checked"
  else
    echo "  note  no signed-release folder at $SIGNED_DIR yet — keep every signed APK there,"
    echo "        or nothing can tell whether a version is an update to what shipped"
  fi
fi
seen=0
prev_max=0; prev_ver=""; prev_apk=""
for a in "$SIGNED_DIR"/ATAK-Plugin-"$PLUGIN"-*--*-civ-release.apk; do
  [ -f "$a" ] || continue
  b="$(basename "$a")"
  v="$(printf '%s' "$b" | sed -nE "s/^ATAK-Plugin-$PLUGIN-([0-9.]+)--([0-9.]+)-civ-release\.apk$/\1/p")"
  t="$(printf '%s' "$b" | sed -nE "s/^ATAK-Plugin-$PLUGIN-([0-9.]+)--([0-9.]+)-civ-release\.apk$/\2/p")"
  [ -n "$v" ] || continue
  c="$(version_code "$v")" || c=""
  [ -n "$c" ] || continue
  seen=$((seen + 1))
  if [ "$v" = "$VER" ]; then
    if [ "$SIGNED" = 0 ] && { [ -z "$TARGET" ] || [ "$t" = "$TARGET" ]; }; then
      finding "$VER is already signed for ATAK $t ($b): a resubmission is a NEW version, bump PLUGIN_VERSION"
    fi
    continue
  fi
  if [ "$c" -ge "$EXPECT" ]; then
    finding "$VER (code $EXPECT) is not above the signed $v (code $c, $b): no MDM would see an update"
  fi
  if [ "$c" -gt "$prev_max" ]; then prev_max=$c; prev_ver=$v; prev_apk=$a; fi
done
if [ "$seen" = 0 ]; then
  echo "  note  no signed $PLUGIN release under $SIGNED_DIR: treating $VER as the first release"
else
  echo "  ok    $seen signed $PLUGIN APK(s) under $SIGNED_DIR, newest other version ${prev_ver:-none}"
fi

# 3. --signed: this version's signed APKs, one per target, right code, same
#    package and same certificate as the last signed release.
AAPT="$(aapt_bin)"; AAPT="${AAPT:-/nonexistent}"
KEYTOOL="$(keytool_bin)"; KEYTOOL="${KEYTOOL:-/nonexistent}"
pkg_of()  { "$AAPT" dump badging "$1" 2>/dev/null | sed -n "s/^package: name='\([^']*\)'.*/\1/p"; }
code_in() { "$AAPT" dump badging "$1" 2>/dev/null | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p"; }
cert_of() { "$KEYTOOL" -printcert -jarfile "$1" 2>/dev/null | sed -n 's/^[[:space:]]*SHA256: //p' | head -1; }

if [ "$SIGNED" = 1 ]; then
  [ -x "$AAPT" ] || finding "no aapt under \$ANDROID_HOME/build-tools; cannot read the signed APKs"
  [ -x "$KEYTOOL" ] || finding "no keytool at $KEYTOOL; cannot compare signing certificates"
  targets="$(grep -oE "/releases/download/v$VER/ATAK-Plugin-$PLUGIN-$VER--[0-9.]+-civ-release\.apk" "$DIR/README.md" 2>/dev/null \
             | sed -E 's/.*--([0-9.]+)-civ.*/\1/' | sort -u)"
  [ -n "$targets" ] || finding "README.md links no v$VER assets; nothing says which targets this release ships"
  prev_pkg=""; prev_cert=""
  if [ -n "$prev_apk" ] && [ -x "$AAPT" ]; then
    prev_pkg="$(pkg_of "$prev_apk")"
    [ -x "$KEYTOOL" ] && prev_cert="$(cert_of "$prev_apk")"
  fi
  certs=""
  for t in $targets; do
    a="$SIGNED_DIR/ATAK-Plugin-$PLUGIN-$VER--$t-civ-release.apk"
    if [ ! -f "$a" ]; then
      finding "no signed APK for ATAK $t ($(basename "$a")): every target ships, or devices on that ATAK can never be updated"
      continue
    fi
    [ -x "$AAPT" ] || continue
    before=$fail
    c="$(code_in "$a")"
    [ "$c" = "$EXPECT" ] || finding "$(basename "$a") carries versionCode '${c:-?}', expected $EXPECT"
    p="$(pkg_of "$a")"
    if [ -n "$prev_pkg" ] && [ "$p" != "$prev_pkg" ]; then
      finding "$(basename "$a") is package $p but the last signed release ($prev_ver) was $prev_pkg: a different app, not an update"
    fi
    s=""
    if [ -x "$KEYTOOL" ]; then
      s="$(cert_of "$a")"
      [ -n "$s" ] || finding "$(basename "$a"): could not read the signing certificate"
      if [ -n "$prev_cert" ] && [ -n "$s" ] && [ "$s" != "$prev_cert" ]; then
        finding "$(basename "$a") is signed by a different certificate than $prev_ver: Android refuses the update"
      fi
      case "$certs" in *"$s"*) ;; *) certs="$certs $s" ;; esac
    fi
    [ "$fail" = "$before" ] && echo "  ok    $(basename "$a"): versionCode $c, $p"
  done
  [ "$(printf '%s' "$certs" | wc -w)" -le 1 ] || finding "this version's APKs are not all signed by one certificate"
  if [ -n "$prev_ver" ] && [ "$fail" = 0 ]; then
    echo "  ok    an update over the last signed release, $prev_ver: same package, same signing certificate"
  fi
fi

# 4. --live: nothing on the public repo is this version or newer.
if [ "$LIVE" = 1 ]; then
  slug="$(sed -nE 's#^All releases: https://github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/releases[[:space:]]*$#\1#p' "$DIR/README.md" 2>/dev/null | head -1)"
  if [ -z "$slug" ]; then
    finding "README.md has no 'All releases: https://github.com/<owner>/<repo>/releases' line naming the public repo"
  elif ! command -v gh >/dev/null 2>&1; then
    finding "gh is not installed; cannot compare against the live releases"
  else
    if tags="$(gh api "repos/$slug/releases?per_page=100" --jq '.[].tag_name' 2>&1)"; then
      [ -n "$tags" ] || echo "  note  $slug has no releases yet (first release)"
      for tg in $tags; do
        tc="$(version_code "${tg#v}")" || tc=""
        [ -n "$tc" ] || continue
        [ "$tc" -lt "$EXPECT" ] || finding "$slug already has release $tg (code $tc); $VER (code $EXPECT) is not newer"
      done
      [ "$fail" = 0 ] && echo "  ok    $slug: every existing release is older than $VER"
    else
      finding "gh api repos/$slug/releases failed: $tags"
    fi
  fi
fi

if [ "$fail" = 0 ]; then
  echo "check-version-code: PASS ($PLUGIN $VER -> versionCode $EXPECT, an update over every signed release)"
  exit 0
fi
echo "check-version-code: FAIL ($PLUGIN $VER): an MDM could not push this as an update; fix the findings above, do not work around them" >&2
exit 1
