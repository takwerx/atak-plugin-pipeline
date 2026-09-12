# Publishing — the page users land on, and the update their fleet can install

## One public repo per plugin

Users get a plugin from **its own public repository**, whose front page *is* the
plugin: download links at the top of the README, the user guide with screenshots
under `docs/`, its own Releases (`vX.Y`, signed APKs attached) and its own Issues.
GitHub Releases and Issues are per repository, so sharing them across plugins in
one repo is confusing to hand out.

If you develop several plugins in one workspace, a plugin reaches its public repo
by subtree push, history preserved:

```bash
git subtree split --prefix=plugins/<Name> -b <name>-export
git push https://github.com/<owner>/<plugin-repo>.git <name>-export:refs/heads/main
```

### The plugin page standard

**README.md** — in this exact order, nothing between them
(`templates/README.md.template`):

1. Title line `ATAK Plugin — <Display Name>`
2. `**Download <Display Name> <ver>**` … then one bullet per ATAK target,
   ascending, then `All releases: <releases URL>`
3. `**User guide with screenshots: [docs/USER_GUIDE.md](docs/USER_GUIDE.md)**`
   with the absolute URL beneath it
4. The SDK template headings, unchanged and in template order: PURPOSE AND
   CAPABILITIES, STATUS, POINT OF CONTACTS, PORTS REQUIRED, EQUIPMENT REQUIRED,
   EQUIPMENT SUPPORTED, COMPILATION, DEVELOPER NOTES

PORTS REQUIRED is read for ATO and security review. Answer it properly: outbound
ports and what triggers them, inbound (usually none), whether it talks to the TAK
server, whether it works in airplane mode.

**GitHub repo metadata** — set with `gh repo edit`; it is what the repo list and
search show, and it is invisible from inside the README:

- description: `ATAK Plugin: <Display Name> — <what it does>. Downloads, guide and issues here.`
- website: the user guide's absolute URL
- topics: `atak`, `atak-plugin`, `tak`, plus one or two domain topics
- Issues enabled

**docs/USER_GUIDE.md** — the same download block at the top, and a "Before you
start" note listing which ATAK versions have published builds.

Anything that lives beside your plugins but is not one (a data repo, say) says so
in the first words of its description, so the repo list does not read as if it
were something to install.

## versionCode — the release rule nobody sees until an MDM refuses

Think like the package manager and the MDM, not only the plugin loader. A release
that sideloads fine but cannot be pushed as an update is a broken release:
**same package name, same signer, a `versionCode` higher than the last release,
and one APK per ATAK target your users run.**

**tak.gov builds have no git, so `versionCode` must come from `PLUGIN_VERSION`.**
The SDK's `getVersionCode()` and `getVersionName()` both read the git revision,
and the submission is a zip with no `.git`. Measured on the same zip:

```
with .git : versionCode=1788195463  versionName='1.2 (4391c747) - [5.8.0]'
no .git   : versionCode=1           versionName='1.2 () - [5.8.0]'
```

So every signed release carries `versionCode=1`, and that is the number an MDM
keys updates on; `versionName` is a display string. A fleet MDM will refuse 1.2
as an update to 1.1 because both are version 1 to it, and nothing in sideloading
or the on-device market ever shows the problem, because the system installer
happily replaces a same-code package.

`app/build.gradle` therefore sets `versionCode = PLUGIN_VERSION_CODE`, computed
as `MAJOR*10000 + MINOR*100 + PATCH` (1.3 → 10300), identical on every machine.
`new-plugin.sh` writes it; `submission-zip.sh` reads the clean-extract APK with
`aapt` and fails the zip when the code is not that number.

Consequences worth knowing:

- `versionName` still carries a blank hash in signed builds. Expected, not broken.
- A rising code means Android refuses a downgrade, so **every release ships every
  target** — a device on 1.4 for ATAK 5.7 cannot be moved to 1.3 for 5.8.
- On a dev phone, the first install over a build from before the change fails
  with `INSTALL_FAILED_VERSION_DOWNGRADE` (the git-derived code was a timestamp).
  Uninstall the plugin first. Devices that only ever had code 1 upgrade normally.

`scripts/check-version-code.sh <Plugin> --signed --live` holds the whole rule:
above every signed release, one APK per target the README links, each with that
code, the same package and the same signing certificate as last time.

## The download links are part of the release

They name a tag and asset filenames that **do not exist until the GitHub Release
is created**, so nothing on the page looks wrong until a user clicks one. When a
version is skipped or folded into the next one, re-stamp the block in the same
commit that bumps `PLUGIN_VERSION`.

```bash
scripts/check-download-links.sh <Plugin>          # text check, before the release exists
scripts/check-download-links.sh <Plugin> --live   # after gh release create: each link 200
```

Wire `hooks/release-links-guard.sh` in and it blocks the subtree push and
`gh release create` on a failure, which is the only version of this rule that
holds.

## Whatever your users install from is part of the release

A GitHub Release is where a person downloads. A fleet does not download; it gets
what its channel offers — an on-device market catalog, an MDM, a shared folder.
**Nothing updates that channel on its own.** A release is not shipped until the
channel a user actually installs from offers it, on every ATAK target it was
built for; until then "the market is broken" is what your users will report, and
they will be describing your release process accurately.

Make it a step with a check, not a memory: publish the catalog from the GitHub
Releases, verify the live catalog names the new version for every target, and run
the same publisher on a schedule so a missed step self-heals.

## Signing, for anything you distribute yourself

- **Debug/dev:** the SDK's shared `android_keystore`. It is public, in every SDK
  download, and must never sign a public release.
- **Officially published plugins are built and signed by tak.gov** from the
  source zip, so no key of yours is involved in that path.
- **Your own release keystore** is only needed for APKs you distribute yourself
  (direct sideload, MDM push). Android requires every update to be signed by the
  same key as the installed version: generate it once, back it up, and keep
  custody of it outside the repo. Record where it lives somewhere private — never
  the key itself.

## The scrub, before anything leaves the machine

```bash
scripts/publish-scrub.sh                 # the tracked tree (what a push publishes)
scripts/publish-scrub.sh <dir>           # an extracted zip or a docs tree
scripts/publish-scrub.sh --file <path>   # one file
```

It fails on personal identifiers, machine-local paths, real-looking IPs,
credentials and keys, SDK binaries and signing material, and every literal in
your machine-local denylist. Wire `hooks/publish-guard.sh` in so it runs before
every push, release and submission zip.

It cannot read a screenshot. That check is yours, every time.
