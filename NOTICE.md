# Notice

## What this repository is

Original work by TAKWERX, under the [MIT license](LICENSE): the skill's guidance
(`SKILL.md`, `references/`), the scripts and hooks that enforce it, and the
templates.

## What it is not

**Not affiliated with, endorsed by, sponsored by or approved by** the TAK Product
Center, the U.S. Department of Defense or any other part of the U.S. Government.
ATAK, TAK and tak.gov are named only to describe what this documentation is
about.

**No TAK SDK material.** No SDK code, resources, Gradle scripts or binaries are
in this repository. `main.jar`, `atak.apk`, `atak-gradle-takdev.jar`,
`atak-javadoc.jar` and `android_keystore` come from the SDK each developer
downloads from [tak.gov](https://tak.gov). The SDK's license permits deriving
applications from it and forbids redistributing it. The CI in
`.github/workflows/` refuses binaries and SDK file names, but it cannot prove a
negative. If you find SDK material here, report it as a security issue
([SECURITY.md](SECURITY.md)).

**Where the SDK is referred to**, such as the `plugintemplate` sample, the
`com.atakmap.app.component` activity or the `ATAK_VERSION` property, it is
named so a developer can find it in their own copy, not reproduced.

## Where the facts come from

Measured building, testing and publishing ATAK-CIV plugins against SDKs 5.6,
5.7 and 5.8 from tak.gov, on physical Android phones running both official ATAK
and the SDK's developer build, and through tak.gov's third-party pipeline. The
sources are what we observed: logcat, build output, `aapt` and `apksigner`
readings of APKs, the contents of submission and return zips, and what happened
on devices and in an MDM.

Nothing here is the product of decompiling, disassembling or reverse engineering
ATAK. The TAK license prohibits that, and a contribution that relies on it will
be declined. Where this repository restates something the TAK Product Center
publishes, the TAK Product Center's own documentation is authoritative.

## Contributions

By contributing, you agree that your contribution is licensed under the same MIT
license and that you have the right to submit it.
