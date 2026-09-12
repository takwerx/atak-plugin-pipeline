# Scaffolding a plugin, and the build config you must not clean up

## The name is the hardest thing to change later

`<PluginName>` is the directory, `rootProject.name`, the proguard repackage
descriptor, **and the APK name tak.gov produces from a source submission**. It is
the plugin's public identity.

- **Letters and digits only.** No dash, no underscore, no space. Capitals are
  fine (`UnitTracker`, `CamDepot`). The release build emits
  `-repackageclasses atakplugin.${rootProject.name}` into proguard, and a dash
  there is an invalid Java package: **debug builds pass**, so it only fails at
  release time, which is submission time.
- The Display Name is separate and may have spaces (`"Cam Depot"`).
- The public repo is kebab-case of the display name (`<owner>/cam-depot`).

Decide all three before running anything.

## Scaffold

```bash
scripts/new-plugin.sh <PluginName> "<Display Name>" [parent dir]
```

It copies `samples/plugintemplate` out of the SDK and then does the things that
are easy to forget and expensive to discover:

- renames the package, the class and the descriptor, sets `rootProject.name`
- **derives `versionCode` from `PLUGIN_VERSION`** instead of git — see
  [publishing.md](publishing.md); this one is not optional if anyone will ever
  push an update through an MDM
- **deletes the template's placeholder user manual.** The template ships a manual
  titled "Plugin Template 0.1" and tak.gov compiles `docs/user_manual/` into the
  APK, so left in place your plugin ships with the template's manual inside it
- **splits the icon in two** — see below
- adds the plugin-specific proguard keep rule tak.gov requires
- writes a `.gitignore` that is safe as a standalone repo root, and a gitignored
  `local.properties`

Then rewrite `README.md` to the submission headings
(`templates/README.md.template`) — it is part of the zip and part of the public
page, and it is read by a human reviewer at tak.gov.

## Two icons, not one

`android:icon` is what **Android** shows on **light** backgrounds — the app list,
Settings, and the file browser a user reaches an extracted manual through. ATAK
shows toolbar and Tool Preferences icons on **dark**. The SDK template ships one
white-on-transparent glyph wired to both, which is invisible in the file manager
and looks like a missing image.

- `ic_launcher.png` — the glyph on a solid dark tile (`#121212`, rounded), used
  by `android:icon` only.
- `ic_toolbar.png` — the bare white glyph, used by `ToolbarItem` and
  `ToolsPreferenceFragment.register`.

Both are 256×256. In `ic_toolbar.png` the glyph's longer side spans the full 256
with **no margin**: ATAK draws every toolbar icon in the same square, so a glyph
with padding reads smaller than its neighbors. In `ic_launcher.png` the glyph
sits at about 196 of 256 on the tile. Start from square artwork — a tall or wide
glyph leaves empty sides no scaling can fix.

Check the launcher icon by compositing it on **white**, not by opening it in a
dark image editor where a white glyph looks fine right up until a user sees it.

ATAK's toolbar and Tools-list glyphs are **alpha masks**: color is discarded, so
punch inner marks through the alpha rather than drawing them in another color.
Marker icons are not masks and keep their color.

## Build-file invariants — do not "clean these up"

The template's `app/build.gradle` and manifest carry load-bearing config.
Removing any of it produces a plugin that builds fine and then refuses to load:

- `bundle { storeArchive { enable = false } }` — required, or TAK's inner
  signing check fails.
- `packagingOptions { jniLibs.useLegacyPackaging true }` — required for native
  libraries.
- The `com.atakmap.app.component` activity in `AndroidManifest.xml` — ATAK
  ≥ 4.6.0.2 uses it for plugin discovery. Delete it and the plugin is invisible,
  with no error anywhere.
- `<meta-data android:name="plugin-api" android:value="${atakApiVersion}"/>` —
  resolves to `com.atakmap.app@<ATAK_VERSION>.<FLAVOR>`. It must match the target
  ATAK build or ATAK will not load the plugin.
- `archivesBaseName` / `getVersionName()` — the SDK asks developers not to change
  these, and the publication pipeline expects
  `ATAK-Plugin-<name>-<ver>-<gitsha>-<atakver>.apk`. The one deliberate
  departure is `versionCode`.

## ATAK version targeting — the silent-failure trap

Officially built plugins are **version-matched to the ATAK release they were
built against**. ATAK's obfuscation mapping changes between releases, so a plugin
built for 5.6 can fail on official 5.7 while working fine against dev/SDK builds
— and the failure does not look like a version problem.

- `ext.ATAK_VERSION` in `app/build.gradle` sets the target.
- Request a build artifact for **every** ATAK version your users run. One APK is
  not enough once they are on mixed versions.
- **Prefer the stable `gov.tak.api.*` classes over `com.atakmap.android.*`
  internals** wherever an equivalent exists. The stable API is not obfuscated and
  survives version changes. This is a design rule, not a preference: it decides
  whether a plugin survives an ATAK upgrade.
- **Compile against every target SDK before zipping.** Classes come and go
  between releases: `QueryUserTracksRequest2`, `HTTPRequestManager2` and
  `com.atakmap.comms.datadroidlite` exist only in 5.8, and a plugin that touches
  them — even in dead code — fails the 5.6 and 5.7 builds.

## Java or Kotlin

The template is Java. ATAK ships Kotlin and much of its own newer API surface is
Kotlin, so choose on merits. One trap: the SDK forces `-Xsam-conversions=class`
on *release* builds, because Kotlin's default `indy` form fails only after
release.

## Plan before code, for anything past a hot fix

Write down what it does, for whom in the field, where the data comes from, which
ATAK targets it ships for, and — always — **what happens when it is interrupted**
(see [ui.md](ui.md)). "Not applicable" is an answer; silence is not.

**If the plugin downloads from a catalog, verify the catalog against the servers
before shipping.** Reading a catalog is not the same as asking whether anything
will serve it, and the interesting failures are silent: an agency endpoint that
answers `204 No Content` for a map it does not hold looks like a generic download
failure from inside ATAK. Build each URL the way the plugin builds it and ask for
one byte. A verifier that constructs URLs differently proves nothing about what
users get.
