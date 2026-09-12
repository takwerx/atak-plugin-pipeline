#!/usr/bin/env bash
# Scaffold a new ATAK plugin from the SDK's plugintemplate sample.
#
#   new-plugin.sh <PluginName> "Display Name" [destination parent dir]
#
# <PluginName> becomes the directory name, rootProject.name, the proguard
# repackage descriptor, AND the APK name tak.gov produces from a source
# submission. It is the plugin's public identity — pick it deliberately,
# renaming later is disruptive.
#
# Letters and digits only: no dashes or underscores. The release build writes
# "-repackageclasses atakplugin.${rootProject.name}" into proguard, and a dash
# there is an invalid Java package name — debug builds pass, so it only fails at
# release time, which is submission time.
#
# The destination defaults to $ATAK_PLUGINS_ROOT, else ./plugins if it exists,
# else the current directory.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

NAME="${1:-}"
DISPLAY="${2:-}"
PARENT="${3:-}"

if [ -z "$NAME" ] || [ -z "$DISPLAY" ]; then
    echo "usage: $0 <PluginName> \"Display Name\" [destination parent dir]" >&2
    echo "example: $0 UnitTracker \"Unit Tracker\"" >&2
    exit 1
fi

if ! [[ "$NAME" =~ ^[A-Za-z][A-Za-z0-9]*$ ]]; then
    echo "error: name must be letters and digits only (no dashes, underscores or spaces)" >&2
    echo "       got: $NAME" >&2
    exit 1
fi

if [ -z "$PARENT" ]; then
    if [ -n "${ATAK_PLUGINS_ROOT:-}" ]; then PARENT="$ATAK_PLUGINS_ROOT"
    elif [ -d "$(repo_root)/plugins" ]; then PARENT="$(repo_root)/plugins"
    else PARENT="$PWD"; fi
fi

TEMPLATE="$ATAK_SDK/samples/plugintemplate"
DEST="$PARENT/$NAME"

[ -d "$TEMPLATE" ] || { echo "error: template not found at $TEMPLATE (is ATAK_SDK right?)" >&2; exit 1; }
[ -e "$DEST" ] && { echo "error: $DEST already exists" >&2; exit 1; }

# Java package segments are lowercase by convention; the class keeps the casing.
PKG="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')"
CLASS="$(printf '%s' "${NAME:0:1}" | tr '[:lower:]' '[:upper:]')${NAME:1}"

echo "==> copying $TEMPLATE -> $DEST"
mkdir -p "$PARENT"
cp -R "$TEMPLATE" "$DEST"
rm -rf "$DEST/build" "$DEST/app/build" "$DEST/.gradle" "$DEST/.idea" "$DEST/.takdev"
find "$DEST" -name '.DS_Store' -delete

echo "==> renaming package com.atakmap.android.plugintemplate -> com.atakmap.android.$PKG"
for variant in main gov test androidTest; do
    OLD_PKG_DIR="$DEST/app/src/$variant/java/com/atakmap/android/plugintemplate"
    if [ -d "$OLD_PKG_DIR" ]; then
        mv "$OLD_PKG_DIR" "$DEST/app/src/$variant/java/com/atakmap/android/$PKG"
    fi
done

echo "==> rewriting sources"
# Text files only — never touch binaries (icons, fonts, the gradle wrapper jar).
SED_I=(-i ''); sed --version >/dev/null 2>&1 && SED_I=(-i)   # BSD vs GNU sed
find "$DEST" -type f \
    \( -name '*.java' -o -name '*.kt' -o -name '*.xml' -o -name '*.gradle' \
       -o -name '*.properties' -o -name '*.pro' -o -name '*.txt' -o -name '*.md' \) \
    -not -path '*/gradle/wrapper/*' -print0 |
while IFS= read -r -d '' f; do
    sed "${SED_I[@]}" \
        -e "s/com\.atakmap\.android\.plugintemplate/com.atakmap.android.$PKG/g" \
        -e "s/plugintemplate/$PKG/g" \
        -e "s/PluginTemplate/$CLASS/g" \
        "$f"
done

if [ -f "$DEST/app/src/main/java/com/atakmap/android/$PKG/plugin/PluginTemplate.java" ]; then
    mv "$DEST/app/src/main/java/com/atakmap/android/$PKG/plugin/PluginTemplate.java" \
       "$DEST/app/src/main/java/com/atakmap/android/$PKG/plugin/$CLASS.java"
fi

echo "==> versionCode from PLUGIN_VERSION (the SDK's getVersionCode() is 1 in a tak.gov build)"
# tak.gov builds from a zip with no .git, so the template's git-derived
# versionCode falls back to 1 on every signed release — and an MDM decides "is
# this an update" from that integer alone. Two releases both carrying 1 cannot
# be pushed over each other. Derive it from PLUGIN_VERSION instead; the
# submission gate fails the zip when the built APK disagrees.
cat > "$DEST/.version-code.block" <<'BLOCK'
    // Android's integer version. The package manager and every MDM decide "is
    // this an update" from this number alone; versionName is display only. The
    // SDK's getVersionCode() reads the git commit, and tak.gov builds from a
    // zip with no .git — so every signed release would carry versionCode 1 and
    // no MDM could push one release over the last. Derived from PLUGIN_VERSION
    // instead, identical on every machine: 1.3 -> 10300, 1.3.1 -> 10301.
    ext.PLUGIN_VERSION_CODE = { ->
        def p = (PLUGIN_VERSION.tokenize('.') + ['0', '0']).collect { it as int }
        return p[0] * 10000 + p[1] * 100 + p[2]
    }()
BLOCK
sed "${SED_I[@]}" "/^[[:space:]]*ext\.PLUGIN_VERSION[[:space:]]*=/r $DEST/.version-code.block" "$DEST/app/build.gradle"
rm -f "$DEST/.version-code.block"
sed "${SED_I[@]}" 's|^\([[:space:]]*\)defaultConfig.versionCode = getVersionCode()$|\1// Not getVersionCode(): that is 1 at tak.gov. See PLUGIN_VERSION_CODE above.\n\1defaultConfig.versionCode = PLUGIN_VERSION_CODE|' "$DEST/app/build.gradle"
grep -q 'defaultConfig.versionCode = PLUGIN_VERSION_CODE' "$DEST/app/build.gradle" || {
    echo "error: could not rewrite versionCode in $DEST/app/build.gradle" >&2; exit 1; }

echo "==> removing the template's placeholder user manual"
# The template ships a manual titled "Plugin Template 0.1", and tak.gov compiles
# docs/user_manual/ into the APK from the submission zip. Left in place, the
# plugin ships with the template's manual inside it. Write your own when you
# have one; the original stays in the SDK at samples/plugintemplate/docs.
rm -rf "$DEST/docs/user_manual"

echo "==> splitting the icon: a dark tile for Android, the bare glyph for ATAK"
# The template ships ONE icon and wires it to two places: android:icon in the
# manifest, and the toolbar button. It is a white glyph on transparency, which
# is right for the toolbar — ATAK's UI is dark — and INVISIBLE for android:icon,
# which Android draws on LIGHT backgrounds: the app list, Settings, and the file
# browser a user reaches an extracted manual through. It renders as a blank
# square, and it looks perfect in any dark image viewer right up until a user
# sees it. Inverting the one icon only moves the problem onto the toolbar.
DRAWABLE="$DEST/app/src/main/res/drawable"
if [ -f "$DRAWABLE/ic_launcher.png" ]; then
    cp "$DRAWABLE/ic_launcher.png" "$DRAWABLE/ic_toolbar.png"

    JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/java}"
    [ -x "${JAVA_BIN:-}" ] || JAVA_BIN="$(command -v java || true)"
    if [ -n "$JAVA_BIN" ] && [ -x "$JAVA_BIN" ]; then
        MAKE_ICON="$(mktemp -d)/MakeIcon.java"
        cat > "$MAKE_ICON" <<'JAVA'
import javax.imageio.ImageIO; import java.awt.*; import java.awt.geom.RoundRectangle2D;
import java.awt.image.BufferedImage; import java.io.File;
public class MakeIcon { public static void main(String[] a) throws Exception {
  BufferedImage glyph = ImageIO.read(new File(a[0]));
  BufferedImage out = new BufferedImage(256, 256, BufferedImage.TYPE_INT_ARGB);
  Graphics2D g = out.createGraphics();
  g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
  g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
  g.setColor(new Color(0x12, 0x12, 0x12));
  g.fill(new RoundRectangle2D.Float(0, 0, 256, 256, 56, 56));
  g.drawImage(glyph, 30, 30, 196, 196, null);
  g.dispose();
  ImageIO.write(out, "png", new File(a[1]));
}}
JAVA
        "$JAVA_BIN" "$MAKE_ICON" "$DRAWABLE/ic_toolbar.png" "$DRAWABLE/ic_launcher.png" \
            && echo "    ic_launcher.png is now the glyph on a #121212 tile" \
            || echo "    WARN: could not generate the tile; ic_launcher is still the bare glyph"
    else
        echo "    WARN: no java found, so ic_launcher.png is still the bare white glyph."
        echo "          It will be INVISIBLE in Android's app list and file browser."
    fi

    # The manifest keeps ic_launcher (the tile). Every Java reference is
    # ATAK-side and wants the bare glyph.
    find "$DEST/app/src" -name '*.java' -print0 |
        xargs -0 sed "${SED_I[@]}" -e 's/R\.drawable\.ic_launcher/R.drawable.ic_toolbar/g'
fi

echo "==> setting display name and rootProject.name"
cat > "$DEST/app/src/main/res/values/strings.xml" <<STRINGS
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- App -->
    <string name="app_name">$DISPLAY</string>
    <!-- description -->
    <string name="app_desc">$DISPLAY</string>
</resources>
STRINGS

# rootProject.name drives archivesBaseName, the proguard repackage target, and
# the APK name tak.gov builds from a source submission. It must match the
# directory name.
if ! grep -q '^rootProject.name' "$DEST/settings.gradle"; then
    printf "\nrootProject.name = '%s'\n" "$NAME" >> "$DEST/settings.gradle"
fi

# tak.gov requirement: the proguard User Section must keep THIS plugin's own
# package. A keep rule inherited from a copied project protects nothing, and the
# release build then obfuscates classes the plugin loader needs.
cat >> "$DEST/app/proguard-gradle.txt" <<PROGUARD

# Keep this plugin's own classes. A plugin-specific rule is required here — a
# leftover rule from a copied project protects nothing.
-keep class com.atakmap.android.$PKG.** { *; }
PROGUARD

# The release build regenerates this file from rootProject.name, so it only
# exists after a build has run — and the submission gate reads it from the
# source tree. Write it now, so a plugin that has never been built still zips.
printf -- '-repackageclasses atakplugin.%s\n' "$NAME" > "$DEST/app/proguard-gradle-repackage.txt"

echo "==> writing .gitignore"
cat > "$DEST/.gitignore" <<'GITIGNORE'
# ATAK SDK artifacts — never commit (the SDK license forbids redistribution)
main.jar
atak.apk
atak-javadoc.jar
atak-gradle-takdev.jar
android_keystore

# Signing material
*.jks
*.keystore
*.p12
keystore.properties

# Machine-local paths and credentials
local.properties

# Unpacked by the takdev Gradle plugin at build time
.takdev/

# Build output
.gradle/
build/
app/libs/
captures/
.externalNativeBuild/
.cxx/
*.apk
*.aab

# IDE
.idea/
*.iml
*.ipr
*.iws
.DS_Store

# Submission zips
dist/
*.zip
GITIGNORE

echo "==> writing local.properties (gitignored — machine-local paths)"
"$(dirname "${BASH_SOURCE[0]}")/local-properties.sh" "$DEST" "$ATAK_SDK"

sed "${SED_I[@]}" "1s/.*/$DISPLAY/" "$DEST/README.md"

echo
echo "created $DEST"
echo "  entry class: com.atakmap.android.$PKG.plugin.$CLASS"
echo "  APK name on submission: ATAK-Plugin-$NAME-<ver>-<sha>-<atakver>"
echo
echo "next:"
echo "  cd $DEST && ./gradlew assembleCivDebug"
echo "  adb install -r app/build/outputs/apk/civ/debug/ATAK-Plugin-*.apk"
echo "  then rewrite README.md to the submission headings (templates/README.md.template)"
