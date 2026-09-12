# Release builds differ from debug builds

`release` enables minify + proguard. **Never submit or field a plugin that has
only been run as `civDebug`** — these break in release and nowhere else:

- **Lambdas break under release proguard** (documented in the SDK README).
  Prefer anonymous classes in code paths that ship.
- Reflection, `Class.forName` and resource-by-name lookups need keep rules in
  `app/proguard-gradle.txt` (the SDK's `proguard-release-keep.txt` is the
  reference).
- The proguard **User Section** must keep this plugin's own package:
  `-keep class com.atakmap.android.<pkg>.** { *; }`. A rule inherited from a
  copied project protects nothing, and the release build then obfuscates classes
  the plugin loader needs.
- `proguard-gradle-repackage.txt` must carry a plugin-specific descriptor:
  `-repackageclasses atakplugin.<PluginName>`.

## Test the release build BEFORE submitting, not after

Waiting for tak.gov to sign an APK to find out whether the plugin works turns
every bug into a full round trip — and a signed release you then throw away is
also a version number you can never reuse.

You do not need tak.gov to test any of this. `assembleCivRelease` runs the same
minify and proguard locally, signed with the SDK's shared dev keystore:

```bash
./gradlew assembleCivRelease -PbuildManual        # same proguard, manual included
adb install -r app/build/outputs/apk/civ/release/ATAK-Plugin-*.apk
```

`-PbuildManual` compiles `docs/user_manual/` with a local typst so the manual is
in the APK and can be **opened on the device** — the only way to catch a manual
with no preferences entry to reach it. The signed build differs only in who
signed it, so what passes here passes there.

The local PDF lands in `app/src/main/assets/usermanual.pdf`, which is gitignored
and excluded from the submission zip. tak.gov builds its own.

## The signed APK still gets a load check

When the signed APKs come back, install each one on a device running **official**
ATAK of that target version and load it. That is a smoke test, not the place bugs
are discovered. See "Which device proves what" in [setup.md](setup.md) — a signed
APK on a dev-build phone fails with a `ClassNotFoundException` that means nothing
except that you used the wrong phone.

## Security scan when the code lands, not at ship

Run a security review **in the session that writes the code**, before the commit,
whenever a change touches: network fetch, file writes or deletes, path
construction from external input, parsing anything a server sent, or a version
bump of vendored third-party code.

Ship-time scanning is how a path traversal in a removal path gets found at the
ship prompt, with signed APKs already verified on hardware. The scan is cheap and
the round trip is not. Record the date, commit and result somewhere you can cite
later.

One rule that keeps coming back: **a negative cache must not outlive a positive
one.** Caching a 404 for a path that can become a 200 is poisoning your own
plugin; only durable absence is cacheable.
