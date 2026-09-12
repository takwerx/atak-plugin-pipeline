# Submission — tak.gov builds from SOURCE, not from your APK

The submission is a **zip of the source tree**. tak.gov runs `./gradlew` itself
and produces a signed APK. Do not submit a built APK.

```bash
scripts/submission-zip.sh <PluginName>      # builds ~/atak-dist/<Name>-<ver>-<atak>.zip and verifies it
```

The script encodes the pipeline's requirements and checks each one, because every
one of them is a rejected or silently-broken submission:

- Every path lives under a single `<PluginName>/` root.
- `gradle/wrapper/gradle-wrapper.jar` **must** be included — without it tak.gov's
  `./gradlew` cannot bootstrap (`Could not find or load main class
  …GradleWrapperMain`).
- `.takdev/`, `app/libs/` (the ~30 MB SDK `main.jar`), build output,
  `local.properties` and any keystore **must not** be included. tak.gov resolves
  the SDK itself, and the license forbids you to ship it. Without a manual the
  zip is ~100–300 KB; megabytes means something is wrong.
- `docs/user_manual/` **is** included — it is the one exception to the docs rule,
  because tak.gov compiles the PDF from the source. Everything else under
  `docs/` stays out.
- `template.local.properties` (placeholders only) is included; the real
  `local.properties` never is.
- `proguard-gradle-repackage.txt` carries `-repackageclasses
  atakplugin.<PluginName>`, and the proguard User Section keeps this plugin's own
  package.
- `assembleCivRelease` must be a defined target, and the
  `com.atakmap.app.component` discovery activity must be in the manifest.
- The built APK's `versionCode` must be the one derived from `PLUGIN_VERSION` —
  see [publishing.md](publishing.md).

The last check extracts the zip to a clean directory and builds it with
`ATAK_CI=1`: a zip that does not build from a clean extract will not build at
tak.gov, and building **with** `ATAK_CI=1` is the only way the manual is exercised
at all.

## One zip per ATAK target, built against that target's SDK

Retarget `ext.ATAK_VERSION` **and** `sdk.path` in `local.properties` together, so
the clean-extract test validates that target rather than testing one SDK three
times. Classes come and go between ATAK releases, and dead code that references a
5.8-only class fails the 5.6 and 5.7 builds.

Read the build log per target. When one fails, rerun the extracted zip by hand
and read javac.

## Point of contact — recorded once, injected automatically

tak.gov requires a contact address in the submission README. A public repo must
never carry one. Both hold only because the address never enters the tracked tree:

- it lives in one machine-local file, `~/.config/atak-plugins/submission-poc.txt`
- `submission-zip.sh` reads it and rewrites the README **inside the zip**, after
  the tracked tree has been zipped, then passes it to the scrub as `POC_ALLOW` so
  the zip's own scrub does not fail on the address it was just told to add
- `POC_ALLOW` allows that one literal, escaped, in that one run. Every other
  address and every other scrub category still fails. Never widen it, and never
  set it by hand to get a scrub to pass.

Do not type the address into a README, a commit, or any file in the repo.

## When some ATAK targets build at tak.gov and others do not

tak.gov reports no failure reason, so this reads like a version-compatibility
problem. It usually is not. **Diff the zips before suspecting the plugin** — the
zips for one release differ in exactly one character, `ext.ATAK_VERSION`:

```bash
for v in 5.6.0 5.7.0 5.8.0; do unzip -q ~/atak-dist/<Name>-<ver>-$v.zip -d /tmp/z/$v; done
diff -rq /tmp/z/5.6.0 /tmp/z/5.7.0        # expect: app/build.gradle only
```

Identical source with different outcomes means the cause is not what you
submitted. The known culprit is `gradle/typst.gradle`, which downloads a 30 MB
typst binary from GitHub once per target; the stock task uses `curl -L` without
`-f`, so an HTTP error body is written into the tarball and the build dies at
`tar` with "Extraction failed", naming neither the network nor the URL. Harden it
with `templates/typst-setup-task.gradle`. **Resubmitting the failed targets is
the correct response** to this failure.

Note that the clean-extract build does not run typst locally unless a `typst` is
on `PATH` (it downloads a linux-musl binary it cannot run on a Mac), so the gate
reports SKIP rather than passing quietly. Install typst if the plugin has a
manual.

## Bump `PLUGIN_VERSION` before building zips, every time

**A resubmission after a failure is a new version, not the same one again.** A
same-version build carries the same `versionCode`, so no MDM would push it, and
`submission-zip.sh` refuses a version already signed for that target.

Re-stamp the download block in the same commit that bumps the version — see
[publishing.md](publishing.md).
