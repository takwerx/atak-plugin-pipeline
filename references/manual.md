# The user manual, and why it is usually unreachable

tak.gov compiles `docs/user_manual/` into the plugin at build time
(`gradle/typst.gradle`, when `ATAK_CI=1`), producing
`app/src/main/assets/usermanual.pdf`. That is half the job.

## A manual in `assets/` is unreachable

ATAK surfaces a plugin's documentation through its **Tool Preferences** entry, so
a plugin without one ships the manual inside the APK with **no way for anyone to
open it**. This ships undetected easily, because the PDF genuinely is in the APK
and every build gate passes.

Three pieces, all required (`samples/dsmmanager` is the SDK's reference, and
`templates/` here has both files):

1. `res/xml/preferences.xml` with a `com.atakmap.android.gui.PanPreference`
   keyed `manual`
2. a fragment extending `com.atakmap.android.preference.PluginPreferenceFragment`
   whose click handler calls `PdfHelper.extractAndShow(pluginContext,
   getActivity(), "usermanual.pdf", <extract path>, true)`
3. `ToolsPreferenceFragment.register(new ToolPreference(title, summary, key,
   icon, fragment))` on plugin start, and `unregister(key)` on stop

**Check it on a device by opening Settings → Tool Preferences.** Unzipping the
APK proves nothing: the PDF is in there either way.

`PdfHelper` re-extracts the PDF when the version it recorded changes, so with a
`versionCode` derived from `PLUGIN_VERSION` (see [publishing.md](publishing.md))
the manual updates by itself. With the SDK's git-derived code — 1 on every signed
build — it never does: the first manual a user opens is the one they keep, the
plugin manager says 0.8 while the manual says 0.5, and nothing on the device can
fix it.

## Verify the manual from the zip, not from your working tree

`app/src/main/assets/usermanual.pdf` is gitignored and only regenerated when
typst runs, so a local build packages whatever is lying there — which can be
months old. Build the zip the way tak.gov does and look at what lands in the APK:

```bash
unzip -q ~/atak-dist/<Name>-<ver>-<atak>.zip -d /tmp/ci && cd /tmp/ci/<Name>
cp <a local.properties pointing sdk.path at the SDK that zip targets> .
ATAK_CI=1 ./gradlew assembleCivDebug
unzip -p app/build/outputs/apk/civ/debug/*.apk assets/usermanual.pdf > /tmp/m.pdf
pdfinfo /tmp/m.pdf | grep Pages && pdftotext -f 1 -l 1 /tmp/m.pdf - | head -5
```

The title page must show the version you are shipping. `runTypst` rewrites
`plugin-version` in `usermanual.typ` **in place** during the build, so that
tracked file drifts under you and a zip can carry a stale stamp. Commit the value
so the tree, the zip and the PDF agree.

Verify against **tak.gov's pinned typst version** (0.13.1 in `typst.gradle`), not
whatever is installed locally, and harden the download task —
`templates/typst-setup-task.gradle` explains the failure it prevents.

## How a guide gets built — shot list first

The user guide and the manual are written around screenshots, and the
screenshots come from a **signed build on a phone running official ATAK** (a dev
build watermarks every frame). The order is fixed, and it costs one extra
release:

1. Write the shot list before taking any shots: framing rules, then a numbered
   table of shots (section, what it shows, crop).
2. Stage each screen and pull it with `adb exec-out screencap -p`.
3. Crop tightly (pane, dialog, toolbar strip, or the map when the map is the
   point), review every frame by eye, name them `<n>_<what>.png` under
   `docs/screenshots/`, and copy the manual's set into `docs/user_manual/` as
   `<n>.png`.
4. Write `docs/USER_GUIDE.md` and `usermanual.typ` around them, add the Tool
   Preferences entry if the plugin has none, and **submit the next version**.

That last point is the part people get wrong: **the build the pictures come from
never ships.** The version after it carries the manual. So plan for it —
"pictures" is not a step before shipping, it is a release of its own.

`sips --cropOffset 0 0` is ignored and crops the **center** of the image; use a
tool that does exact crops.
