#!/bin/bash
# release-links-guard: PreToolUse hook for Bash. Before a plugin's tree is pushed
# to its public repo's main, or a GitHub Release is created there, check that
#
#   1. the download block at the top of README.md and docs/USER_GUIDE.md names
#      the version being released and links assets that will exist, and
#   2. the signed APKs are a release an MDM could push as an update: one per
#      target the README links, the right versionCode, the same package name and
#      the same signing certificate as the last release.
#
# Download links name a tag and filenames that do not exist until the release is
# created, so nothing looks wrong until a user clicks one. The version code is
# invisible from everywhere except an MDM's update logic.
#
# The plugin is found by its README's "All releases:" line, which names the
# public repo. A push to a repo no README claims is not a plugin release and is
# left alone.
RL_INPUT="$(cat)" RL_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}" RL_HOOK_DIR="$(cd "$(dirname "$0")" && pwd)" exec python3 <<'PYEOF'
import glob, json, os, re, subprocess, sys

root = os.environ.get("RL_ROOT") or os.getcwd()
hook_dir = os.environ.get("RL_HOOK_DIR") or ""
try:
    data = json.loads(os.environ.get("RL_INPUT") or "{}")
except Exception:
    sys.exit(0)
cmd = (data.get("tool_input") or {}).get("command", "") or ""

slug = None
m = re.search(r'\bgit\b[^|;&]*\bpush\b[^|;&]*github\.com[/:]([A-Za-z0-9._-]+/[A-Za-z0-9._-]+?)(?:\.git)?\s+\S*:(?:refs/heads/)?main\b', cmd)
if m:
    slug = m.group(1)
m2 = re.search(r'\bgh\s+release\s+create\b[^|;&]*--repo\s+([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)', cmd)
if m2:
    slug = m2.group(1)
if not slug:
    sys.exit(0)

readmes = glob.glob(os.path.join(root, "plugins", "*", "README.md")) + [os.path.join(root, "README.md")]
plugin_dir_path = None
for readme in readmes:
    try:
        text = open(readme, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    if re.search(r'^All releases: https://github\.com/' + re.escape(slug) + r'/releases\s*$', text, re.M):
        plugin_dir_path = os.path.dirname(readme)
        break
if not plugin_dir_path:
    sys.exit(0)

# The plugin's name is rootProject.name — the same string the APK and the
# proguard descriptor carry.
plugin = os.path.basename(plugin_dir_path)
settings = os.path.join(plugin_dir_path, "settings.gradle")
if os.path.exists(settings):
    m3 = re.search(r"rootProject\.name\s*=\s*['\"]([^'\"]+)['\"]",
                   open(settings, encoding="utf-8", errors="replace").read())
    if m3:
        plugin = m3.group(1)

def find(script):
    for c in (os.path.join(root, "scripts", script),
              os.path.join(hook_dir, os.pardir, "scripts", script),
              os.path.expanduser("~/.claude/skills/atak-plugin-pipeline/scripts/" + script)):
        if os.path.exists(c):
            return os.path.realpath(c)
    return None

for script, args, why in (
    ("check-download-links.sh", [], "the download links at the top of README.md and docs/USER_GUIDE.md do not "
                                    "match PLUGIN_VERSION. Users would get 404s."),
    ("check-version-code.sh", ["--signed"], "this is not a release an MDM could push as an update "
                                            "(versionCode, a missing target, package or signer)."),
):
    path = find(script)
    if not path:
        sys.stderr.write("release-links-guard: %s not found; refusing to publish a release without it.\n" % script)
        sys.exit(2)
    r = subprocess.run(["bash", path, plugin] + args, capture_output=True, text=True,
                       timeout=240, cwd=plugin_dir_path)
    if r.returncode != 0:
        sys.stderr.write("BLOCKED by release-links-guard: " + why +
                         " Fix the finding and commit it before this push; do not work around this.\n\n"
                         + r.stdout + r.stderr)
        sys.exit(2)
sys.exit(0)
PYEOF
