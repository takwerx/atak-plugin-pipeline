#!/bin/bash
# publish-guard: PreToolUse hook for Bash. Before anything that publishes — a
# git push, a GitHub release, a tak.gov submission zip — run the publish scrub
# over the tracked tree and BLOCK on findings.
#
# A rule that depends on remembering is not a rule. This is the same scrub you
# would run by hand, wired so it cannot be skipped by momentum.
#
# Install: copy to <project>/.claude/hooks/ and register it in
# <project>/.claude/settings.json (see the skill's README).
PG_INPUT="$(cat)" PG_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}" PG_HOOK_DIR="$(cd "$(dirname "$0")" && pwd)" exec python3 <<'PYEOF'
import json, os, re, subprocess, sys

root = os.environ.get("PG_ROOT") or os.getcwd()
hook_dir = os.environ.get("PG_HOOK_DIR") or ""
try:
    data = json.loads(os.environ.get("PG_INPUT") or "{}")
except Exception:
    sys.exit(0)
cmd = (data.get("tool_input") or {}).get("command", "") or ""

publishing = (
    re.search(r'\bgit\b[^|;&]*\bpush\b', cmd)
    or re.search(r'\bgh\s+release\s+create\b', cmd)
    or re.search(r'submission-zip\.sh', cmd)
)
if not publishing:
    sys.exit(0)

candidates = [
    os.environ.get("ATAK_SCRUB_SCRIPT", ""),
    os.path.join(root, "scripts", "publish-scrub.sh"),
    os.path.join(hook_dir, os.pardir, "scripts", "publish-scrub.sh"),
    os.path.expanduser("~/.claude/skills/atak-plugin-pipeline/scripts/publish-scrub.sh"),
]
scrub = next((os.path.realpath(c) for c in candidates if c and os.path.exists(os.path.expanduser(c))), None)
if not scrub:
    sys.stderr.write("publish-guard: publish-scrub.sh not found — refusing to publish without the scrub.\n")
    sys.exit(2)

r = subprocess.run(["bash", scrub], capture_output=True, text=True, timeout=180, cwd=root)
if r.returncode != 0:
    sys.stderr.write("BLOCKED by publish-guard: the publish scrub found material that must not be "
                     "published. Fix it or move it somewhere private; do not work around this.\n\n"
                     + r.stdout + r.stderr)
    sys.exit(2)
sys.exit(0)
PYEOF
