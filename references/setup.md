# Setup — the SDK, the toolchain, and which device proves what

## The SDK lives outside every repo, and stays there

Download the ATAK-CIV SDK from tak.gov and unpack it at `~/atak-sdk/ATAK-CIV-<version>/`.
Keep every version you target side by side — you will build against all of them.

It contains:

| File | What it is |
|---|---|
| `main.jar` | the ATAK API you compile against |
| `atak-gradle-takdev.jar` | the Gradle plugin that wires it up |
| `android_keystore` | the shared dev signing key (`tnttnt` / `wintec_mapping`) |
| `atak.apk` | the matching **developer build** of ATAK, to sideload |
| `ATAK_Plugin_Development_Guide.pdf` | read it once |
| `samples/` | ~28 worked examples |

**Read the sample before inventing an approach.** `plugintemplate` is the
skeleton every plugin starts from; `helloworld` is a broad API tour; then the
targeted ones — `cotinjector`, `importexportexample`, `videooverlay`,
`radialmenudemo`, `dsmmanager` (the Tool Preferences / manual reference),
`hellojni`, `sensortester`, `customtiles`, `selfmarkerdata`.

**Never commit SDK artifacts.** The CIV SDK license forbids copying, publishing
or distributing the SDK. `main.jar`, `atak.apk`, `atak-gradle-takdev.jar`,
`atak-javadoc.jar` and `android_keystore` are gitignored and must stay that way,
in public *and* private repos. Each plugin reaches the SDK through `sdk.path` in
its gitignored `local.properties`.

The line is **SDK binaries vs. derivative work**: the same license grants the
right "to use the TAK-SDK and to derive new works or applications based on the
TAK-SDK", so plugin code scaffolded from `samples/plugintemplate` is yours to
commit and publish. The SDK's own distributable artifacts are not.

Consequence: **GitHub Actions cannot build these plugins** unless you have a
tak.gov Artifactory account (`takrepo.url` / `takrepo.user` / `takrepo.password`
as repo secrets). Do not "solve" CI by committing the SDK.

## Toolchain

- **JDK 17.** Not 21.
- **Android SDK** with `platform-tools` (adb) and a `build-tools` (the gate reads
  `aapt` from there), plus the platform the template targets.
- Gradle comes from each project's own wrapper (`./gradlew`) — never install one.

`scripts/env.sh` finds all of it and exports `ATAK_SDK`, `ATAK_DIST` and the
helpers the other scripts use. Source it if a shell is missing anything.

## Machine-local config, outside every repo

`~/.config/atak-plugins/` (override with `ATAK_CONFIG_DIR`):

- `submission-poc.txt` — one line: the real point-of-contact address tak.gov
  requires in the submission README. The submission gate injects it into the
  README **inside the zip**, so it never enters the tracked tree. See
  [submission.md](submission.md).
- `publish-scrub.denylist` — literals that must never be published: your own
  addresses, device serials, customer or site names. One per line, `#` comments.
  The scrub is mechanical about these so you do not have to be.

`~/atak-dist/` (override with `ATAK_DIST`) holds every submission zip, and every
tak.gov-signed APK under `signed/`. Keep the signed APKs: "is this version an
update" is measured against them, and a release is reconstructed from them.

## Build and install

```bash
cd <plugin>
./gradlew assembleCivDebug        # civ = the CIV flavor; also mil/gov/xyz
adb install -r app/build/outputs/apk/civ/debug/ATAK-Plugin-*.apk
```

ATAK must already be installed and be the **same version** the plugin targets.
Load the plugin from ATAK's Plugins manager. `~/atak-sdk/<version>/atak.apk` is
the matching ATAK build.

In Android Studio, set Build → Select Build Variants explicitly: it defaults to
the alphabetically-first flavor, which is not `civ` once other flavors exist.

Two things that read as code regressions and are not:

- **Reinstalling a plugin unloads it.** Re-enable it in ATAK's plugin manager or
  it sits there inert.
- **Resource changes need an ATAK restart.** Code reloads on install; layouts,
  drawables and strings do not. On official ATAK even code can keep running old
  classes after a replace — quit ATAK, then confirm from a log line that only
  the new build prints.

## Which device proves what — the rule that is not optional

**A tak.gov-signed APK cannot load on the SDK's developer ATAK, and a locally
built one cannot load on official ATAK.** They are mirror images and neither is
broken. Official ATAK is obfuscated, so `gov.tak.api.plugin.IServiceController`
is `gov.tak.api.plugin.a` there, and tak.gov builds plugins to match it. The
SDK's `atak.apk` is a dev build with the real names, so a signed plugin fails on
it with `ClassNotFoundException: Didn't find class "gov.tak.api.plugin.a"` and
`failed to load extension`. That reads exactly like a broken release and is not
one.

- **Locally built APKs** (debug or `assembleCivRelease`) — test on a device
  running the SDK's `atak.apk`. That is where proguard breakage shows up.
- **tak.gov-signed APKs** — test ONLY on a device running **official** ATAK from
  tak.gov or the Play Store. A dev-build device can never validate one.

**Check the signature, not the version string.** The hash in `versionName` is the
source commit, and tak.gov's official build and the SDK's dev build of the same
release share it — a phone on official 5.7.0.14 reports exactly what the SDK's
`atak.apk` reports. What differs is who signed it:

```bash
adb shell dumpsys package com.atakmap.app.civ | grep -E "signatures=|pkgFlags"
# dev (SDK) build:  signatures:[...] ... pkgFlags=[ DEBUGGABLE HAS_CODE ... ]
# official build:   signatures:[...] ... pkgFlags=[ HAS_CODE ... ]   (no DEBUGGABLE)
```

The SDK build is signed with the shared dev keystore and is `DEBUGGABLE`;
official ATAK is signed by tak.gov and is not. The on-screen `DEVELOPER BUILD`
watermark is the same fact seen from the phone.

Keep at least one phone on each, and say out loud which one a result came from.
