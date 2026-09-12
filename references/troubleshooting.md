# When it does not work — read the log line, not the dialog

```bash
adb logcat | grep -E "AtakPluginRegistry|PluginValidator|AndroidRuntime"
```

| What you see | What it means | What to do |
|---|---|---|
| nothing in logcat for your package | not discovered | the `com.atakmap.app.component` activity or the `plugin-api` meta-data is missing from the manifest |
| `signature mismatch` then `will NOT load` | the plugin's cert does not match this ATAK's | you built locally and the phone runs **official** ATAK (or the reverse). See below |
| `ClassNotFoundException: gov.tak.api.plugin.a`, `failed to load extension` | a **tak.gov-signed** APK on a **developer** ATAK | test signed APKs only on official ATAK. Nothing is broken |
| `api matches` but `will NOT load` / `!should load` | discovered and compatible, not enabled | load it from the plugin manager |
| `SDK skipping signature check` | you are on the developer build | expected, the good path |
| plugin manager says **Incompatible** | almost always the signature, not the API version | check which ATAK build the phone has |
| the plugin loads but the UI is stale | resources do not hot-reload | quit ATAK fully and relaunch |
| the plugin is installed but inert | a reinstall unloads it | re-enable it in the plugin manager |
| release APK crashes where debug did not | proguard | lambdas, reflection, resource-by-name; see [release-build.md](release-build.md) |
| native `SIGSEGV`, no Java stack | a View or map item touched from the GL thread | move it off `onMapMoved` |
| `BadTokenException`, ATAK dies | a dialog built on the plugin context | use the MapView context |
| ATAK hangs, no crash | an ANR | `adb shell dumpsys dropbox --print` for the stack (`/data/anr` needs root) |
| `INSTALL_FAILED_VERSION_DOWNGRADE` | the installed build has a higher versionCode | uninstall the plugin first; see [publishing.md](publishing.md) |
| some ATAK targets build at tak.gov, others fail with no reason | usually the typst download, not compatibility | diff the zips; see [submission.md](submission.md) |
| the manual is in the APK but nobody can open it | no Tool Preferences entry | [manual.md](manual.md) |

**Before drawing any conclusion, check which ATAK the phone is running — by
signature, not by version string.** The version hash is shared by the dev build
and the official build of the same release. See "Which device proves what" in
[setup.md](setup.md).

## Things that look like regressions and are not

- A reinstall unloads the plugin.
- Resource changes need a full ATAK restart; on official ATAK even code can keep
  running old classes after a replace. Confirm from a log line only the new build
  prints.
- A handoff note describing an old bug is a lead, not a fact. Reproduce it on the
  current build before reporting it — a "crash" recorded months ago can be a
  silent no-op today.

## Claims about ATAK: check the source before asserting one

ATAK-CIV is published under GPL-3.0 (tak.gov, or the delayed public mirror). The
SDK carries the javadoc, the broadcast list and 28 samples. Between them, most
"can ATAK do X" questions are answered by reading rather than by experiment —
and an answer from bytecode alone is not proof. Read the source, the samples and
ATAK's own assets first, then measure on a device, then assert.

## A short list of measured facts that save days

- `AtakMapController.zoomTo(double)` takes map **scale**, not resolution. A
  plausible "30 meters per pixel" asks for something extremely zoomed in: every
  tile request misses and the map renders blank, with no error anywhere.
  `AtakMapView.mapResolutionAsMapScale()` converts.
- ATAK's video player (`ConnectionEntry` protocol `RAW`) plays anything. A camera
  that will not play has a bad URL, not the wrong protocol.
- `curl` negotiating HTTP/2 can pass a URL that libVLC — HTTP/1.1 only — fails.
  Test the route the phone will actually use.
- Instrumented tests inside ATAK ship in `$ATAK_SDK/espresso/`. The trap:
  `assembleCivDebugAndroidTest` does **not** run
  `packageCivDebugAndroidTest_modApk` — only `connectedCivDebugAndroidTest` does
  — and without it every test dies at startup in `ATAKStarter`. `am instrument`
  also exits 0 when tests fail, so a wrapper must parse the output. And the
  harness permanently rewrites ATAK's `nav_orientation_right`, so a device used
  for instrumented tests is no longer in a user's configuration.
