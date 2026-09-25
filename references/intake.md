# Intake — what comes back from tak.gov, and reading it before you publish

tak.gov returns one zip per build, and the APK is the least interesting thing in
it. The zip also carries:

| File | What it is |
|---|---|
| `ATAK-Plugin-<Name>-<ver>--<atak>-civ-release.apk` / `.aab` | the signed build |
| `fortify_scan.txt`, `fortify_scan_results.pdf`, `scan_results.fpr` | a Fortify static analysis of **your own source** |
| `dependency-check-report.html` | an OWASP Dependency-Check of every archive in the build |
| `sbom/bom.json` | a CycloneDX SBOM |
| `build.log`, `civRelease-app-mapping.txt` | the build log and the proguard mapping |

Every file has the same name whatever the ATAK target, so two targets unpacked
into one folder overwrite each other. And a scan nobody opens has not been read.

## One command, every return zip

Drop each return zip in `~/atak-dist/inbox/` and run:

```bash
scripts/takgov-intake.sh            # everything in the inbox
scripts/takgov-intake.sh <zip>...   # named zips
```

It reads the plugin, version and ATAK target off the APK name inside, files the
APK and AAB under `~/atak-dist/signed/` and the scans under
`~/atak-dist/scans/<Plugin>/<version>/<target>/`, moves the zip to
`inbox/done/`, and then gates on what decides whether a build is fit to publish:

- **Signer** is the TAK Product Center.
- **versionCode** is the one `PLUGIN_VERSION` and the ATAK target derive — see
  [publishing.md](publishing.md). A build that fails this cannot be pushed by
  an MDM as an update, whatever else is right about it.
- **versionName** agrees with the file name.
- **Package id and signing certificate** match the last signed release of the
  same plugin. Either one changing means Android installs it alongside the old
  one, or refuses it.
- **Fortify rendered zero results.**

It exits non-zero on a real finding. Do not publish past a FAIL.

`inbox/done/` is not "filed". A zip that failed the gate still moves there.
Before you call a release complete, check that `~/atak-dist/signed/` holds one
APK per target.

## Fortify — findings in your code

Any Fortify result is a finding in your own source. Most are real and cheap to
fix: a path built from server data without a check, a digest updated outside a
loop, a word like `password` in a comment. Fix them and submit a new version.

Some findings cannot be cleared because they describe the design. A plugin that
fetches what its catalog names will always trip Fortify's SSRF rule, because
the rule follows the data to the connection whatever you check on the way. In
that case, **record the decision instead of working around it**:

```
# ~/.config/atak-plugins/fortify-accepted.txt
<Plugin>|<Category as Fortify names it>|<file path suffix>|<where the record is>
```

The record says what the finding is, why it cannot be cleared, what protects
the code instead, and what would reopen it. The intake matches a finding on
plugin, category *and* file. It reads them from the scan's own results
(`audit.fvdl` inside `scan_results.fpr`), prints a match as ACCEPTED and passes.
Any other finding still fails. Never add a line without the decision and the
record behind it.

## Dependency-Check — needs a human's eye, and the script gives it one

The scanner opens every archive in the build, including Android assets that
the packager renamed with a `.jar` suffix, and fuzzy-matches them against the
CVE database. It has reported an XSS in Apache SkyWalking against a plugin's own
`catalog.json` asset. So each CVE is checked against the SBOM:

- a product the SBOM **does not** list → reported as a misidentified artifact,
  and it does not fail the gate
- a product the SBOM **does** list → fails the gate. It is real; update the
  dependency.

Keep the scans on disk. They are the record of what was checked before you
published.
