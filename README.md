# atak-plugin-pipeline — a Claude Code skill

The whole pipeline for building an ATAK plugin and publishing it through TAK's
third-party signing process: scaffold, ATAK-native UI, release builds, the user
manual and its Tool Preferences entry, the tak.gov source-submission zip, the
public plugin repo, and the `versionCode` rule an MDM needs.

It is a working set of gates, not a write-up. Each script refuses the mistake it
was written for.

## Install

```bash
cp -R atak-plugin-pipeline ~/.claude/skills/
```

That is it — Claude Code picks it up on the next session and invokes it when you
work on an ATAK plugin. To use the scripts from a shell as well:

```bash
chmod +x ~/.claude/skills/atak-plugin-pipeline/scripts/*.sh
source ~/.claude/skills/atak-plugin-pipeline/scripts/env.sh
```

Per-project install works too — drop it in `<project>/.claude/skills/` instead —
and is the better choice if you want the scripts committed next to the plugin.

## One-time setup

1. **The SDK.** Download the ATAK-CIV SDK from tak.gov and unpack it at
   `~/atak-sdk/ATAK-CIV-<version>/`, one directory per version you target. Never
   commit any of it. (`ATAK_SDK_ROOT` overrides the location.)
2. **JDK 17** and the **Android SDK** (`platform-tools` for adb, a `build-tools`
   for aapt). `scripts/env.sh` finds both, or export `JAVA_HOME` / `ANDROID_HOME`.
3. **Machine-local config** in `~/.config/atak-plugins/` (`ATAK_CONFIG_DIR`):

   ```bash
   mkdir -p ~/.config/atak-plugins
   # tak.gov requires a contact address in the submission README; this keeps it
   # out of the tracked tree. One line, injected into the README inside the zip.
   echo "Your Name, your org, your-address" > ~/.config/atak-plugins/submission-poc.txt
   # literals that must never be published: your addresses, device serials,
   # customer or site names. One per line, # comments.
   touch ~/.config/atak-plugins/publish-scrub.denylist
   ```

4. **`~/atak-dist/`** (`ATAK_DIST`) for submission zips, with every tak.gov-signed
   APK filed under `signed/`. Keep them: "is this version an update" is measured
   against that folder.

## Wire the gates in (recommended)

The checks only hold if they cannot be skipped. Copy the hooks into the project
and register them:

```bash
mkdir -p <project>/.claude/hooks
cp ~/.claude/skills/atak-plugin-pipeline/hooks/*.sh <project>/.claude/hooks/
```

`<project>/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/publish-guard.sh" },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/release-links-guard.sh" }
        ]
      }
    ]
  }
}
```

- **publish-guard** runs the publish scrub before any `git push`, `gh release
  create` or submission zip, and blocks on findings.
- **release-links-guard** runs the download-link and version-code checks before a
  push to a plugin's public repo or a `gh release create` there.

Both find their scripts in the project first (`<project>/scripts/`), then in this
skill, so a project that vendors its own copies uses those.

## Layout

The scripts do not care whether you keep one repo per plugin or a monorepo:

```
one repo per plugin              a monorepo
  <repo>/                          <repo>/
    app/build.gradle                 plugins/<Name>/app/build.gradle
    settings.gradle                  plugins/<Other>/...
    docs/user_manual/                scripts/   (if you vendor these)
```

Run them from the repo holding the plugin. `ATAK_PLUGINS_ROOT` overrides the
search if your plugins live somewhere else entirely.

## What each piece is

| | |
|---|---|
| `SKILL.md` | the pipeline in order, with the five traps that cost the most |
| `references/setup.md` | SDK, toolchain, build/install, **which device proves what** |
| `references/scaffold.md` | naming, scaffolding, build-file invariants, version targeting |
| `references/ui.md` | ATAK-native UI, the context rule, surviving interruptions |
| `references/release-build.md` | release vs debug, proguard, when to security scan |
| `references/manual.md` | the manual and the Tool Preferences entry that reaches it |
| `references/submission.md` | the tak.gov zip, its gates, per-target builds, POC injection |
| `references/publishing.md` | public repo standard, versionCode/MDM, releases, links |
| `references/troubleshooting.md` | the logcat table, and what only looks like a regression |
| `scripts/` | the gates, runnable |
| `templates/` | README skeleton, preferences plumbing, button style, typst task |

## Adapt these, deliberately

- **The point-of-contact file** is the only place a real address belongs. Never
  type one into a README, a commit, or any tracked file.
- **The denylist** is yours to fill in. The scrub is only as good as it.
- **The README standard** in `templates/README.md.template` is what tak.gov's
  reviewer reads and what your users land on. Keep the heading order.
- **The version scheme** (`MAJOR*10000 + MINOR*100 + PATCH`) is arbitrary but must
  be consistent forever — it only has to rise, and the gate checks it against
  every signed release you have kept.
- **The distribution channel** (step 7 in `SKILL.md`) is the one piece nobody can
  write for you. Whatever your users install from — a market catalog, an MDM, a
  shared folder — updating it is part of the release, with a check.

## Prior art

`joshuafuller/atak-plugin` is a good companion skill and can be installed
alongside this one; it goes deeper on reading ATAK's source and on instrumented
testing. Where the two disagree, three specific things measured here across ATAK
5.6, 5.7 and 5.8 on real hardware:

- **Do not gitignore template-derived files.** That would exclude
  `gradle-wrapper.jar`, `app/build.gradle` and the proguard files — exactly what
  the submission zip requires — and make a tak.gov submission impossible.
- **"Incompatible" is not always a dev-vs-release signature problem.** The
  obfuscation failure (a signed APK on a developer ATAK) looks identical, and the
  usual fix for the first — install the SDK's `atak.apk` — wipes the only device
  that can validate a signed build.
- **`adb install -r` plus loading from the plugin manager is the whole flow** on
  real phones; no copy into `/sdcard/atak/support/apks/sideloaded/` and no sync
  is needed.
