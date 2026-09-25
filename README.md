# atak-plugin-pipeline

How we build ATAK plugins and get them through TAK's third-party signing
pipeline, packaged as a [Claude Code](https://claude.com/claude-code) skill.
It covers scaffolding from the SDK template, ATAK-native UI, release builds,
the user manual and its Tool Preferences entry, the tak.gov source-submission
zip, reading what tak.gov sends back, the public plugin repo, and the
`versionCode` rule an MDM needs.

It is a working set of gates, not a write-up. Each script refuses the mistake it
was written for, and every rule in it shipped broken at least once before it
became a rule.

## Why

A plugin is not finished when it works on your phone. It is finished when a
stranger can install the right APK for their ATAK version, open the manual from
inside ATAK, and get the next version pushed to them without uninstalling
anything. Most of what goes wrong between those two points is silent: a
plugin that builds and will not load, a manual nobody can open, a signed APK
that reads as broken on the wrong phone, an update the MDM refuses because
every signed build says `versionCode=1`.

## Install

```bash
git clone https://github.com/takwerx/atak-plugin-pipeline \
    ~/.claude/skills/atak-plugin-pipeline
```

Claude Code picks it up on the next session and uses it when you work on an
ATAK plugin, or on demand with `/atak-plugin-pipeline`. Update with `git pull`
in that directory.

To use the scripts from a shell as well:

```bash
source ~/.claude/skills/atak-plugin-pipeline/scripts/env.sh
```

You can also install it per project: clone it into `<project>/.claude/skills/`
instead. That is the better choice if you want the scripts versioned next to
the plugin.

## The SDK is not here, and never will be

The ATAK-CIV SDK comes from [tak.gov](https://tak.gov) and nowhere else. Its
license lets you build plugins from it and forbids anyone to redistribute it.
So this repository contains no SDK code, resources or binaries, and neither
should yours. Each developer downloads their own SDK and unpacks it at
`~/atak-sdk/ATAK-CIV-<version>/`, one directory per ATAK version they target.
The scripts find whatever versions are there. Nothing here is tied to one ATAK
release.

What this was measured against: ATAK-CIV SDKs **5.6.0.23, 5.7.0.14 and
5.8.0.3** from tak.gov, on physical phones running both official ATAK and the
SDK's developer build, with plugins that have been through the tak.gov
pipeline for all three targets.

The open ATAK-CIV source
([TAK-Product-Center/atak-civ](https://github.com/TAK-Product-Center/atak-civ))
currently goes up to 5.5.1.10. We have not built plugins against it, so nothing
here claims it works.

## One-time setup

1. **The SDK**, as above. `ATAK_SDK_ROOT` overrides the location.
2. **JDK 17** and the **Android SDK** (`platform-tools` for adb, a `build-tools`
   for aapt and apksigner). `scripts/env.sh` finds both, or export `JAVA_HOME` /
   `ANDROID_HOME`.
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

4. **`~/atak-dist/`** (`ATAK_DIST`) for submission zips. Every tak.gov-signed
   APK is filed under `signed/` and every return's scans under `scans/`. Keep
   them: "is this version an update" is measured against that folder.

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

## What is in it

| | |
|---|---|
| [`SKILL.md`](SKILL.md) | the pipeline in order, with the five traps that cost the most |
| [`references/setup.md`](references/setup.md) | SDK, toolchain, build/install, **which device proves what** |
| [`references/scaffold.md`](references/scaffold.md) | naming, scaffolding, build-file invariants, version targeting |
| [`references/licensing.md`](references/licensing.md) | the plugin's own license, and what came from the SDK |
| [`references/ui.md`](references/ui.md) | ATAK-native UI, the context rule, surviving interruptions |
| [`references/release-build.md`](references/release-build.md) | release vs debug, proguard, when to security scan |
| [`references/manual.md`](references/manual.md) | the manual and the Tool Preferences entry that reaches it |
| [`references/submission.md`](references/submission.md) | the tak.gov zip, its gates, per-target builds, POC injection |
| [`references/intake.md`](references/intake.md) | what tak.gov sends back: signed APK, Fortify, Dependency-Check, SBOM |
| [`references/publishing.md`](references/publishing.md) | public repo standard, versionCode/MDM, releases, links |
| [`references/troubleshooting.md`](references/troubleshooting.md) | the logcat table, and what only looks like a regression |
| [`scripts/`](scripts/) | the gates, runnable |
| [`hooks/`](hooks/) | the same gates, wired so they cannot be skipped |
| [`templates/`](templates/) | README skeleton, Tool Preferences plumbing, button style, typst task, license exception |

## Adapt these, deliberately

- **The point-of-contact file** is the only place a real address belongs. Never
  type one into a README, a commit, or any tracked file.
- **The denylist** is yours to fill in. The scrub is only as good as it.
- **The README standard** in `templates/README.md.template` is what tak.gov's
  reviewer reads and what your users land on. Keep the heading order.
- **The version scheme** (`(MAJOR*10000 + MINOR*100 + PATCH) * 10000 +
  ATAK_MAJOR*1000 + ATAK_MINOR*10 + ATAK_PATCH`) is arbitrary but must be
  consistent forever. It only has to rise on every target and differ between
  the targets of one release, and the gate checks it against every signed
  release you have kept.
- **The distribution channel** (step 8 in `SKILL.md`) is the one piece nobody can
  write for you. Whatever your users install from — a market catalog, an MDM, a
  shared folder — updating it is part of the release, with a check.

## Related

[joshuafuller/atak-plugin-skill](https://github.com/joshuafuller/atak-plugin-skill)
is a good companion and installs alongside this one. It goes deeper on reading
ATAK's source and on instrumented tests inside ATAK. Its facts were measured on
one ATAK-CIV 5.8.0.1 emulator; ours on physical phones across 5.6, 5.7 and 5.8.
Where the two disagree, these are the three places, and what we measured:

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

## License and attribution

[MIT](LICENSE). Contributions are welcome under the same terms; see
[CONTRIBUTING.md](CONTRIBUTING.md).

This is an independent project. It is not affiliated with, endorsed by or
approved by the TAK Product Center or any part of the U.S. Government.
[NOTICE.md](NOTICE.md) says what is and is not in this repository.
