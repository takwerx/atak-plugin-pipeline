#!/usr/bin/env bash
# publish-scrub: the last look before anything leaves this machine for a public
# place — a push to a public repo, a tak.gov submission zip, a published guide or
# artifact, a GitHub release. Greps for what must never be published: personal
# identifiers, credentials, machine-local paths, SDK binaries and signing
# material. Exit 0 = PASS, exit 1 = FAIL with a findings list.
#
#   publish-scrub.sh                 # tracked + untracked (non-ignored) files in this repo
#   publish-scrub.sh <dir>           # every text file under a directory (e.g. an extracted zip)
#   publish-scrub.sh --file <path>   # one file
#
# Sensitive literals that must not appear anywhere — your own address, device
# serials, a customer name, a site — cannot live in a public denylist, so they
# are read from a machine-local file if present:
#
#   $ATAK_CONFIG_DIR/publish-scrub.denylist   (one literal per line, # comments)
#
# What it cannot do: read a screenshot. Pictures must be eyeballed for callsigns,
# coordinates, names, faces, plates and server addresses before they are
# committed. That check is yours, every time.

set -uo pipefail

CONFIG_DIR="${ATAK_CONFIG_DIR:-$HOME/.config/atak-plugins}"
DENYLIST="${ATAK_SCRUB_DENYLIST:-$CONFIG_DIR/publish-scrub.denylist}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

MODE="repo"; TARGET=""
case "${1:-}" in
    "") ;;
    --file) MODE="file"; TARGET="${2:-}"; [ -n "$TARGET" ] || { echo "usage: $0 --file <path>" >&2; exit 2; } ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) MODE="dir"; TARGET="$1" ;;
esac

# ---- file list --------------------------------------------------------------
list_files() {
    case "$MODE" in
        # tracked AND untracked-but-not-ignored: what a push publishes, plus what
        # the next commit would add. (A new file checked before `git add` once
        # slipped through on tracked-only.)
        repo) git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard | tr '\0' '\n' | sed "s|^|$REPO_ROOT/|" ;;
        dir)  find "$TARGET" -type f -not -path '*/.git/*' ;;
        file) echo "$TARGET" ;;
    esac
}

is_text() {
    case "$1" in
        *.png|*.jpg|*.jpeg|*.gif|*.webp|*.svg|*.ico|*.zip|*.jar|*.apk|*.aab|*.sqlite|*.db|*.ttf|*.otf|*.woff|*.woff2|*.pdf|*.so) return 1 ;;
    esac
    return 0
}

# One sink for every category. Two sinks is how a forbidden main.jar once printed
# a findings block while the script still exited 0, and both callers (the hook and
# the submission gate) read only the exit code.
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
finding() { printf '  [%s] %s\n' "$1" "$2" >> "$TMP"; }

# ---- 1. forbidden files (by name/extension) ---------------------------------
while IFS= read -r f; do
    base="$(basename "$f")"
    rel="${f#$REPO_ROOT/}"
    case "$base" in
        main.jar|atak.apk|atak-javadoc.jar|atak-gradle-takdev.jar|android_keystore|local.properties|keystore.properties)
            finding "forbidden-file" "$rel" ;;
        *.jks|*.keystore|*.p12|*.pem|*.key|*.apk|*.aab|*.sqlite)
            finding "forbidden-file" "$rel" ;;
    esac
    case "$rel" in
        *.takdev/*|*/app/libs/*|*/build/*) finding "forbidden-path" "$rel" ;;
    esac
done < <(list_files)

# ---- 2. content patterns ----------------------------------------------------
# Allowlisted on purpose, because each is genuinely public:
#   - the SDK's shared dev keystore password/alias (tnttnt / wintec_mapping): it
#     ships in every SDK download and is not a secret. It must never sign a
#     public release, which is a different rule.
#   - ATAK's plugin-api literal com.atakmap.app@<x.y.z>.<FLAVOR> — not an address
#   - schema/xmlns URLs, example.com, loopback addresses
#   - the placeholder credential keys in template.local.properties
ALLOW='com\.atakmap\.app@[0-9]+\.[0-9]+\.[0-9]+\.[A-Z]+|example\.com|schemas\.android\.com|w3\.org|0\.0\.0\.0|127\.0\.0\.1|localhost|tnttnt|wintec_mapping|takrepoUser|takrepoPassword|storePassword|keyPassword'

# The tak.gov submission README must carry a point-of-contact address, and the
# generic email scan would otherwise block the very zip that needs it. This is
# the one sanctioned exception: submission-zip.sh exports POC_ALLOW with the
# single address it just injected (read from outside the repo, never from the
# tracked tree), and only that literal is allowed. Unset in every other run, so a
# stray address in the repo still fails. Never widen this by hand.
if [ -n "${POC_ALLOW:-}" ]; then
    ALLOW="$ALLOW|$(printf '%s' "$POC_ALLOW" | sed 's/[^A-Za-z0-9_-]/\\&/g')"
fi

scan() { # category, regex
    local cat="$1" re="$2"
    while IFS= read -r f; do
        is_text "$f" || continue
        [ -f "$f" ] || continue
        # Exempt the allowlisted TOKEN, not the whole line: dropping any line that
        # contains an allowed literal is much broader than it looks. Strip the
        # allowed literals, re-test what is left, report the ORIGINAL line.
        # "#" is the sed delimiter, so no allowlist entry may contain one.
        grep -nHIE "$re" "$f" 2>/dev/null | while IFS= read -r line; do
            content="${line#*:}"; content="${content#*:}"
            printf '%s' "$content" | sed -E "s#($ALLOW)##g" | grep -qE "$re" || continue
            finding "$cat" "${line#$REPO_ROOT/}"
        done
    done < <(list_files)
}

scan "email"        '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
scan "phone"        '(^|[^0-9A-Za-z])\(?[0-9]{3}\)?[-. ][0-9]{3}[-. ][0-9]{4}([^0-9]|$)'
scan "home-path"    '(/Users/[A-Za-z]|/home/[a-z][a-z0-9_-]*/|C:\\Users\\)'
# IPv4 that looks like a real address rather than a 4-part version: private
# ranges, or any octet >= 100. (ATAK versions like 5.8.0.3 do not trip this.)
scan "ip-address"   '(^|[^0-9.])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|([0-9]{1,3}\.){3}(1[0-9]{2}|2[0-5][0-9])|(1[0-9]{2}|2[0-5][0-9])(\.[0-9]{1,3}){3})([^0-9.]|$)'
scan "secret"       '(password|passwd|secret|api[_-]?key|access[_-]?key|auth[_-]?token|bearer)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{4,}["'"'"']'
scan "secret"       'BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY'
scan "secret"       '(AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|xox[bpa]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,})'
# Excludes the <angle bracket> placeholder form: template.local.properties carries
# takrepo.user=<username> uncommented, is required in the submission zip, and is a
# placeholder rather than a credential.
scan "takrepo-cred" '^[[:space:]]*takrepo\.(user|password)[[:space:]]*=[[:space:]]*[^[:space:]#<]'

# ---- 3. private denylist (machine-local literals) ---------------------------
if [ -f "$DENYLIST" ]; then
    while IFS= read -r lit; do
        lit="${lit%%#*}"; lit="$(echo "$lit" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -n "$lit" ] || continue
        while IFS= read -r f; do
            is_text "$f" || continue
            [ -f "$f" ] || continue
            grep -nHIF -- "$lit" "$f" 2>/dev/null | while IFS= read -r line; do
                finding "denylist" "${line#$REPO_ROOT/}"
            done
        done < <(list_files)
    done < "$DENYLIST"
else
    echo "  note: no private denylist at $DENYLIST (your own literals are not checked)"
fi

# ---- report ------------------------------------------------------------------
if [ -s "$TMP" ]; then
    echo "publish-scrub: FAIL ($MODE${TARGET:+ $TARGET})"
    echo "FINDINGS:"
    sort -u "$TMP"
    echo
    echo "Fix it or move it somewhere private, then re-run. Nothing ships with findings."
    exit 1
fi
echo "publish-scrub: PASS ($MODE${TARGET:+ $TARGET}) — no PII, credentials, machine paths or forbidden files"
exit 0
