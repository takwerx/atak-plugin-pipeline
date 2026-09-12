---
name: atak-plugin-pipeline
description: End-to-end pipeline for building and publishing ATAK (Android Team Awareness Kit) plugins through TAK's third-party signing process — scaffolding from the SDK template, ATAK-native UI, release vs debug builds, which device proves what, the user manual and its Tool Preferences entry, the tak.gov source-submission zip and its gates, the public plugin repo, and the versionCode rule an MDM needs. Use when creating, building, testing, submitting or releasing an ATAK plugin, or when one will not load, a submission is rejected, some ATAK targets fail at tak.gov, or an update will not push to a fleet.
---

# ATAK plugin pipeline

A plugin is not finished when it works on your phone. It is finished when a
stranger can install the right APK for their ATAK version, open the manual from
inside ATAK, and get the next version pushed to them without uninstalling
anything. Everything below is what stands between those two points, in the order
it happens.

Every rule here is written because it shipped broken once. Where a rule names a
failure, that failure is the reason the rule exists — not an illustration.

## The five that cost the most

1. **A dialog built on the plugin context kills ATAK.** `BadTokenException`, no
   warning. MapView context for anything that opens a window, plugin context for
   resources. And never a `Spinner`. → [references/ui.md](references/ui.md)
2. **Signed and locally-built APKs run on different ATAKs.** Official ATAK is
   obfuscated; the SDK's `atak.apk` is not. A tak.gov-signed plugin on a dev
   phone fails with `ClassNotFoundException: gov.tak.api.plugin.a` and nothing is
   wrong. Check the signature, not the version string.
   → [references/setup.md](references/setup.md)
3. **tak.gov builds have no `.git`, so the SDK's `versionCode` is 1 on every
   signed release** — and an MDM decides "is this an update" from that integer
   alone. Derive it from `PLUGIN_VERSION`.
   → [references/publishing.md](references/publishing.md)
4. **A manual in `assets/` is unreachable.** Building the PDF is half the job;
   ATAK opens documentation from the plugin's Tool Preferences entry, and a
   plugin without one ships a manual nobody can open — with every build gate
   passing. → [references/manual.md](references/manual.md)
5. **Release builds break where debug builds do not** (lambdas under proguard,
   reflection, resource-by-name). Test `assembleCivRelease` locally *before*
   submitting; a signed APK is not where bugs get found.
   → [references/release-build.md](references/release-build.md)

## The pipeline

Each step has a gate. Run the gate; do not work around one that fails.

**0. Set up once.** SDK unpacked at `~/atak-sdk/ATAK-CIV-<version>/` (never
committed — the license forbids redistribution), JDK 17, Android SDK,
machine-local config in `~/.config/atak-plugins/`, signed APKs kept in
`~/atak-dist/signed/`. → [references/setup.md](references/setup.md)

**1. Name it, then scaffold it.** The name is the directory, `rootProject.name`,
the proguard descriptor and the APK name tak.gov produces — letters and digits
only, or the *release* build fails at submission time.

```bash
scripts/new-plugin.sh <PluginName> "<Display Name>"
```

→ [references/scaffold.md](references/scaffold.md)

**2. Build it like ATAK.** ATAK's own button drawables and one button style, host
context for windows, no Spinner, no ListView inside a ScrollView, distances in
the operator's configured units. Anything that must outlive a tap — a recording,
a feed, a download — lives in a component, never inside a `Tool`.
→ [references/ui.md](references/ui.md)

**3. Test the release build, on the right phone.**

```bash
./gradlew assembleCivRelease -PbuildManual
adb install -r app/build/outputs/apk/civ/release/ATAK-Plugin-*.apk
```

Run a security review in the session that writes the code — network fetches, file
writes and deletes, paths built from external input, parsing what a server sent.
→ [references/release-build.md](references/release-build.md)

**4. Write the manual, and give it a door.** `docs/user_manual/` compiled by
tak.gov, plus `res/xml/preferences.xml`, a `PluginPreferenceFragment` and
`ToolsPreferenceFragment.register(...)`. Check it on a device via Settings → Tool
Preferences. The build the screenshots come from never ships — the next one
carries the manual. → [references/manual.md](references/manual.md)

**5. Bump the version and build a zip per ATAK target.**

```bash
scripts/submission-zip.sh <PluginName>     # one per ext.ATAK_VERSION, retarget sdk.path too
```

A resubmission after a failure is a **new version**. The gate refuses a version
already signed for that target, verifies the zip's contents, scrubs it, then
extracts it to a clean directory and builds it with `ATAK_CI=1` — a zip that
fails there fails at tak.gov. → [references/submission.md](references/submission.md)

**6. Publish the release.** Signed APKs land in `~/atak-dist/signed/`. One public
repo per plugin, README to the standard, download block re-stamped to this
version, a GitHub Release per version with every target attached.

```bash
scripts/check-version-code.sh <Plugin> --signed --live
scripts/check-download-links.sh <Plugin> --live
```

→ [references/publishing.md](references/publishing.md)

**7. Update the channel your users install from.** A GitHub Release is where a
person downloads; a fleet gets what its market catalog or MDM offers, and nothing
updates that on its own. A release is not shipped until that channel offers the
new version on every target it was built for.

## Scripts

Run them from the repo holding the plugin. They work with one repo per plugin or
a monorepo of `plugins/<Name>/`; layout is resolved by `plugin_dir` in `env.sh`.

| Script | What it does |
|---|---|
| `scripts/env.sh` | toolchain, `ATAK_SDK`, `ATAK_DIST`, and the layout helpers — source it |
| `scripts/new-plugin.sh` | scaffold from `samples/plugintemplate`, with every fix pre-applied |
| `scripts/local-properties.sh` | write the gitignored `local.properties` for a plugin |
| `scripts/submission-zip.sh` | build and verify a tak.gov source zip (the big gate) |
| `scripts/check-version-code.sh` | is this release an update an MDM can push |
| `scripts/check-download-links.sh` | do the README/guide links name this version, and resolve |
| `scripts/publish-scrub.sh` | last look before anything leaves the machine |
| `hooks/*.sh` | the same checks, wired so they cannot be skipped |

`templates/` holds the README skeleton tak.gov expects, the Tool Preferences
plumbing, the button style, and a hardened typst download task.

## Not negotiable

- **Never commit SDK artifacts** — `main.jar`, `atak.apk`, `atak-gradle-takdev.jar`,
  `android_keystore`. The license forbids redistribution, in public *and* private
  repos. Do not "solve" CI by committing them.
- **Never submit a built APK.** tak.gov builds from source.
- **Never ship a plugin only run as `civDebug`.**
- **Never publish without the scrub**, and never widen the point-of-contact
  exception by hand.
- **Screenshots are reviewed by eye** — no scrub reads a picture.
- Prefer stable `gov.tak.api.*` classes over `com.atakmap.android.*` internals:
  the stable API is not obfuscated and survives ATAK upgrades.

## When it does not work

Read the logcat line, not the dialog: the plugin manager's "Incompatible" almost
always means a signature, and the two most alarming failures
(`ClassNotFoundException` on a signed build, targets failing at tak.gov for no
stated reason) are usually not bugs in the plugin at all.
→ [references/troubleshooting.md](references/troubleshooting.md)
