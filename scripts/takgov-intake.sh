#!/bin/bash
# Take in what tak.gov sends back, file it, and read the scans before anyone publishes.
#
# tak.gov returns one zip per build: the signed APK and AAB, a Fortify static
# analysis of your source, an OWASP Dependency-Check report, a CycloneDX SBOM and
# the build log. Every file in it has the same name whatever the ATAK target, so
# two targets unpacked into one folder overwrite each other, and the scans are
# read only when somebody remembers to.
#
# So: drop every return zip in $ATAK_DIST/inbox and run this. It reads the
# plugin, the version and the ATAK target off the APK name inside, files
# everything where it belongs, and then checks what decides whether a build is
# fit to publish. It is a gate, not a report: a real finding exits non-zero.
#
#   scripts/takgov-intake.sh              # everything in the inbox
#   scripts/takgov-intake.sh <zip>...     # named zips
#   scripts/takgov-intake.sh --keep       # leave the zips in the inbox
#
# What it files:
#   $ATAK_DIST/signed/<apk>, <aab>
#   $ATAK_DIST/scans/<Plugin>/<version>/<target>/{build.log,fortify_*,dependency-check-report.html,sbom/,...}
#
# What it checks, and why each one is here:
#   signer          a build signed by anything but the TAK Product Center is not
#                   the artifact you asked for
#   versionCode     (MAJOR*10000+MINOR*100+PATCH)*10000 + ATAK major*1000+minor*10
#                   +patch, one code per target, or no MDM can push it as an
#                   update -- the same rule submission-zip.sh enforces going out
#   version match   the APK inside says the version its name claims
#   package         the same package id as the last signed release, or it
#                   installs alongside the old one instead of over it
#   certificate     the same signing certificate as the last signed release, for
#                   the same reason
#   Fortify         "Rendering N results": any N above zero is a finding in your
#                   own source and stops the gate, unless you have accepted that
#                   exact finding (plugin, category and file) in
#                   $ATAK_CONFIG_DIR/fortify-accepted.txt; those print as ACCEPTED
#   Dependency-Check  every CVE is listed with the artifact it attached to. These
#                   are frequently false positives -- the scanner opens an Android
#                   asset renamed to .jar and fuzzy-matches it against a library
#                   -- so the SBOM is checked for the named product before the
#                   gate fails on it
#
# fortify-accepted.txt, one line per accepted finding, # comments:
#   <Plugin>|<Category as Fortify names it>|<file path suffix>|<where the decision is recorded>
# Add a line only when you have decided the finding describes the design and
# cannot be cleared, and have written down why and what would reopen it.
set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "$HERE/env.sh" >/dev/null 2>&1
DIST="${ATAK_DIST:-$HOME/atak-dist}"
INBOX="$DIST/inbox"
ACCEPTED_LIST="${ATAK_CONFIG_DIR:-$HOME/.config/atak-plugins}/fortify-accepted.txt"
KEEP=0
ZIPS=()
for a in "$@"; do
    case "$a" in
        --keep) KEEP=1 ;;
        -h|--help) sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) ZIPS+=("$a") ;;
    esac
done
[ ${#ZIPS[@]} -eq 0 ] && { shopt -s nullglob; ZIPS=("$INBOX"/*.zip); shopt -u nullglob; }
[ ${#ZIPS[@]} -eq 0 ] && { echo "nothing to take in: $INBOX is empty"; exit 0; }

command -v unzip >/dev/null || { echo "error: unzip not on PATH" >&2; exit 1; }
AAPT="$(aapt_bin)"
APKSIGNER="${AAPT%/aapt}/apksigner"
[ -x "$AAPT" ] || { echo "error: aapt not found under \$ANDROID_HOME/build-tools" >&2; exit 1; }
[ -x "$APKSIGNER" ] || { echo "error: apksigner not found beside $AAPT" >&2; exit 1; }

FAIL=0
NOTE=0
ok()   { echo "  PASS  $*"; }
bad()  { echo "  FAIL  $*"; FAIL=1; }
note() { echo "  ..    $*"; NOTE=1; }

# One line per Fortify finding, read from the scan's own results (audit.fvdl
# inside scan_results.fpr), each marked ACCEPTED when the accepted list has a
# matching plugin, category and file. Prints nothing when the results cannot be
# read, and the caller then fails on the count alone.
fortify_findings() {
    local fpr="$1" plugin="$2" list="$3" tmp
    [ -f "$fpr" ] && command -v python3 >/dev/null 2>&1 || return 0
    tmp="$(mktemp)"
    unzip -p "$fpr" audit.fvdl > "$tmp" 2>/dev/null
    python3 - "$plugin" "$list" "$tmp" <<'PY'
import sys, re
plugin, listing, xml = sys.argv[1], sys.argv[2], sys.argv[3]
accepted = []
try:
    for raw in open(listing, encoding="utf-8"):
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        parts = [f.strip() for f in raw.split("|")]
        if len(parts) >= 4 and parts[0] == plugin:
            accepted.append((parts[1].lower(), parts[2], parts[3]))
except OSError:
    pass
x = open(xml, encoding="utf-8", errors="replace").read()
for v in re.findall(r"<Vulnerability>.*?</Vulnerability>", x, re.S):
    t = re.search(r"<Type>(.*?)</Type>", v)
    st = re.search(r"<Subtype>(.*?)</Subtype>", v)
    cat = (t.group(1) if t else "?") + ((": " + st.group(1)) if st and st.group(1) else "")
    locs = re.findall(r'<SourceLocation[^>]*path="([^"]+)"[^>]*line="(\d+)"', v)
    path, line = (locs[-1] if locs else ("?", "?"))
    hit = None
    for acat, afile, rec in accepted:
        if acat == cat.lower() and any(p.endswith(afile) or afile.endswith(p) for p, _ in locs):
            hit = rec
            break
    if hit:
        print("ACCEPTED %s at %s:%s -- %s" % (cat, path, line, hit))
    else:
        print("%s at %s:%s (not accepted)" % (cat, path, line))
PY
    rm -f "$tmp"
}

# The newest signed release of this plugin other than the one in hand, so a
# change of package or key is caught the moment it happens.
prev_signed() {
    local plugin="$1" skip="$2" f
    while IFS= read -r f; do
        [ "$(basename "$f")" = "$skip" ] && continue
        echo "$f"
        return 0
    done < <(ls -t "$DIST"/signed/ATAK-Plugin-"$plugin"-*.apk 2>/dev/null)
    return 1
}

cert_of() { "$APKSIGNER" verify --print-certs "$1" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: \(.*\)/\1/p' | head -1; }
pkg_of()  { "$AAPT" dump badging "$1" 2>/dev/null | sed -n "s/package: name='\([^']*\)'.*/\1/p" | head -1; }

for Z in "${ZIPS[@]}"; do
    [ -f "$Z" ] || { echo "no such zip: $Z" >&2; FAIL=1; continue; }
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    unzip -q "$Z" -d "$TMP" || { echo "could not unzip $Z" >&2; FAIL=1; rm -rf "$TMP"; continue; }

    APK="$(ls "$TMP"/ATAK-Plugin-*.apk 2>/dev/null | head -1)"
    [ -n "$APK" ] || { echo "no ATAK-Plugin-*.apk inside $(basename "$Z") -- is this a tak.gov return zip?" >&2; FAIL=1; rm -rf "$TMP"; continue; }
    BASE="$(basename "$APK")"
    PLUGIN="$(echo "$BASE" | sed -E 's/^ATAK-Plugin-([A-Za-z0-9]+)-.*/\1/')"
    VERSION="$(echo "$BASE" | sed -E 's/^ATAK-Plugin-[A-Za-z0-9]+-([0-9][0-9.]*)--.*/\1/')"
    TARGET="$(echo "$BASE" | sed -E 's/.*--([0-9][0-9.]*)-civ-release\.apk$/\1/')"
    echo
    echo "==> $PLUGIN $VERSION for ATAK $TARGET   ($(basename "$Z"))"

    DEST="$DIST/scans/$PLUGIN/$VERSION/$TARGET"
    mkdir -p "$DEST" "$DIST/signed"
    for f in build.log civRelease-app-mapping.txt dependency-check-report.html \
             fortify_analyze.log fortify_analyze_FortifySupport.log fortify_scan.txt \
             fortify_scan_FortifySupport.txt fortify_scan_results.pdf scan_results.fpr; do
        [ -f "$TMP/$f" ] && cp "$TMP/$f" "$DEST/"
    done
    [ -d "$TMP/sbom" ] && { mkdir -p "$DEST/sbom"; cp "$TMP"/sbom/* "$DEST/sbom/" 2>/dev/null; }
    cp "$APK" "$DIST/signed/"
    for b in "$TMP"/ATAK-Plugin-*.aab; do [ -f "$b" ] && cp "$b" "$DIST/signed/"; done
    ok "filed: signed/$BASE and scans/$PLUGIN/$VERSION/$TARGET/"

    # ---- the APK is what it claims to be ------------------------------------
    SIGNER="$("$APKSIGNER" verify --print-certs "$APK" 2>/dev/null | sed -n 's/.*certificate DN: CN=\([^,]*\).*/\1/p' | head -1)"
    case "$SIGNER" in
        *"TAK Product Center"*) ok "signed by $SIGNER" ;;
        "") bad "no signature could be read from the APK" ;;
        *)  bad "signed by '$SIGNER', not the TAK Product Center" ;;
    esac

    BADGING="$("$AAPT" dump badging "$APK" 2>/dev/null | head -1)"
    GOT_CODE="$(echo "$BADGING" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")"
    GOT_NAME="$(echo "$BADGING" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")"
    WANT_CODE="$(target_version_code "$VERSION" "$TARGET")"
    if [ -n "$WANT_CODE" ] && [ "$GOT_CODE" = "$WANT_CODE" ]; then
        ok "versionCode $GOT_CODE, derived from $VERSION on ATAK $TARGET as an MDM needs"
    else
        bad "versionCode $GOT_CODE, expected ${WANT_CODE:-?} from version $VERSION on ATAK $TARGET -- no MDM can push this as an update"
    fi
    case "$GOT_NAME" in
        "$VERSION"*) ok "versionName '$GOT_NAME' agrees with the file name" ;;
        *) bad "versionName '$GOT_NAME' does not start with $VERSION" ;;
    esac

    PKG="$(pkg_of "$APK")"
    if PREV="$(prev_signed "$PLUGIN" "$BASE")"; then
        if [ "$(pkg_of "$PREV")" = "$PKG" ]; then
            ok "package $PKG, same as $(basename "$PREV")"
        else
            bad "package $PKG differs from $(basename "$PREV") ($(pkg_of "$PREV")) -- it would install alongside, not over"
        fi
        if [ "$(cert_of "$PREV")" = "$(cert_of "$APK")" ]; then
            ok "same signing certificate as the last signed release"
        else
            bad "signing certificate CHANGED since $(basename "$PREV") -- Android will refuse the update"
        fi
    else
        note "no earlier signed release to compare package and certificate against"
    fi

    # ---- Fortify: your own source --------------------------------------------
    if [ -f "$DEST/fortify_scan.txt" ]; then
        N="$(sed -n 's/.*Rendering \([0-9]*\) results.*/\1/p' "$DEST/fortify_scan.txt" | tail -1)"
        if [ -z "$N" ]; then
            bad "Fortify did not report a result count -- read $DEST/fortify_scan.txt by hand"
        elif [ "$N" -eq 0 ]; then
            ok "Fortify: 0 findings"
        else
            VERDICT="$(fortify_findings "$DEST/scan_results.fpr" "$PLUGIN" "$ACCEPTED_LIST")"
            if [ -z "$VERDICT" ]; then
                bad "Fortify: $N finding(s) in your own source -- open $DEST/fortify_scan_results.pdf"
            else
                unaccepted=0
                while IFS= read -r line; do
                    case "$line" in
                        ACCEPTED*) note "Fortify: $line" ;;
                        *) bad "Fortify: $line -- open $DEST/fortify_scan_results.pdf"; unaccepted=1 ;;
                    esac
                done <<< "$VERDICT"
                [ "$unaccepted" -eq 0 ] && note "Fortify: $N finding(s), every one in fortify-accepted.txt; read the records before publishing"
            fi
        fi
    else
        note "no Fortify report in this zip"
    fi

    # ---- Dependency-Check: libraries, and its habit of guessing --------------
    DC="$DEST/dependency-check-report.html"
    if [ -f "$DC" ]; then
        CVES="$(grep -oE 'CVE-[0-9]{4}-[0-9]+' "$DC" | sort -u)"
        if [ -z "$CVES" ]; then
            ok "Dependency-Check: no CVEs"
        else
            for CVE in $CVES; do
                # The product the scanner thinks is vulnerable, and whether the
                # SBOM has ever heard of it. A CVE against something you do not
                # ship is the scanner matching an Android asset to a library.
                PROD="$(python3 - "$DC" "$CVE" <<'PY' 2>/dev/null
import re, sys, html
# The product a CVE is actually against is the one under "Vulnerable Software &
# Versions" after the identifier, not whichever CPE the scanner guessed at last
# while listing candidates for the file.
s = open(sys.argv[1], encoding='utf-8', errors='replace').read()
i = s.find(sys.argv[2])
after = html.unescape(re.sub(r'<[^>]+>', ' ', s[i:i + 9000]))
m = re.search(r'Vulnerable Software[^:]*:\s*cpe:2\.3:a:[a-z0-9_\-]+:([a-z0-9_\-]+):', after)
if not m:
    m = re.search(r'cpe:2\.3:a:[a-z0-9_\-]+:([a-z0-9_\-]+):', after)
print(m.group(1) if m else '')
PY
)"
                SB="$DEST/sbom/bom.json"
                if [ -n "$PROD" ] && [ -f "$SB" ] && ! grep -qi "\"$PROD\"" "$SB"; then
                    note "$CVE claims '$PROD', which the SBOM does not list -- a misidentified artifact, not a dependency"
                elif [ -n "$PROD" ]; then
                    bad "$CVE against '$PROD', which IS in the SBOM -- this one is real, update it"
                else
                    bad "$CVE reported and its product could not be read -- open $DC"
                fi
            done
        fi
    else
        note "no Dependency-Check report in this zip"
    fi

    [ "$KEEP" -eq 1 ] || { mkdir -p "$INBOX/done"; mv "$Z" "$INBOX/done/"; }
    rm -rf "$TMP"
    trap - EXIT
done

echo
if [ "$FAIL" -eq 0 ]; then
    [ "$NOTE" -eq 1 ] && echo "takgov-intake: PASS with notes above -- read them before publishing"
    [ "$NOTE" -eq 0 ] && echo "takgov-intake: PASS"
    exit 0
fi
echo "takgov-intake: FAIL -- do not publish until the findings above are answered"
exit 1
