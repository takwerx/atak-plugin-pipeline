# Licensing — the plugin's own license, and what came from the SDK

## A repository with no license is not open

A public repository with no license is **all rights reserved**, not
permissive. A careful contributor reads it that way and leaves. We had people
offering data and fixes who could not open a pull request, because there was
nothing to contribute under. Give every plugin a license in its first commit.

Which license is your call. Two things are specific to ATAK plugins either way.

## 1. A copyleft license needs an exception for ATAK

A plugin's classes load into **ATAK's own process** and call its API directly.
With a permissive license (MIT, Apache-2.0) that raises no question. With a
copyleft one (GPL, AGPL), it is not obvious whether the license reaches into
ATAK, so grant the answer explicitly. Use an additional permission under
GPL/AGPL §7 that lets the plugin be combined with, and distributed together
with, the TAK Software: ATAK-CIV, ATAK-GOV, ATAK-MIL and the TAK SDK, under
the TAK Software License Agreement.

That permission comes from **you**, as the copyright holder. It removes a
restriction your own license would otherwise impose. It does not change the TAK
license, and it cannot.

`templates/LICENSE-EXCEPTION.md.template` has the wording.

## 2. Say which files you did not write

A plugin scaffolded from the SDK's `plugintemplate` carries files that came from
the TAK Product Center: the Gradle files, the manifest's discovery activity,
`PluginNativeLoader.java`, and the lifecycle and tool classes you then rewrote.
The SDK license grants you the right **to derive new works**. It does not grant
you the right to relicense the SDK's own code. So list those files as the TAK
Product Center's, under the TAK Software License Agreement, with your license
covering your changes.

Generate the list from what is on disk. Do not guess it from the plugin name.
Class names drift: one plugin's preference fragment is `PlssPreferenceFragment`,
another has none at all. A provenance statement that names files that do not
exist is worse than none.

```bash
ls app/src/main/java/com/atakmap/android/*/plugin/*.java
```

## What is never in the repository

The SDK itself. `main.jar`, `atak.apk`, `atak-gradle-takdev.jar`,
`atak-javadoc.jar` and `android_keystore` come from the SDK each developer
downloads from tak.gov. The same license clause that lets you publish a plugin
forbids you to publish those. See [setup.md](setup.md).
