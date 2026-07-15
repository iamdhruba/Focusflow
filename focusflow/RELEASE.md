# FocusFlow Release Process

This document captures the v1.0.1+ release workflow for FocusFlow's Android
app. Earlier versions are documented in `TEST_DOCUMENTATION.md` and
`REGISTRATION_FIX.md`.

## Pre-release checklist

### 1. Keystore setup (one-time)

Generate a release keystore and store it OUTSIDE source control:

```bash
keytool -genkey -v -keystore upload-keystore.jks -alias upload \
        -keyalg RSA -keysize 2048 -validity 10000
```

Create `android/key.properties` (gitignored) with:

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=../upload-keystore.jks
```

If `key.properties` is missing, the build falls back to **debug signing** —
suitable for local `flutter run --release` only, NOT for Play Store uploads.

### 2. R8 / ProGuard verification (every release)

R8 + resource shrinking are enabled in v1.0.1+ (`isMinifyEnabled = true`,
`isShrinkResources = true`). The keep rules in `app/proguard-rules.pro` are
**defense-in-depth** — they were INERT in v1.0.0 because R8 was disabled
then. Each release build exercises them for the first time and may surface
new keep-rule gaps.

Validate with:

```bash
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/symbols/
```

Look for `R8: missing rules: …` or `Missing class …` warnings in the output.
Any warning = a `-keep class <pkg>.** { *; }` line needs to be added to
`app/proguard-rules.pro`. **Do not ship a release build that emits these
warnings** — they predict runtime crashes from missing classes.

### 3. Drawable preservation

`isShrinkResources = true` is paired with `app/src/main/res/raw/keep.xml`
that whitelists Flutter-side drawables loaded by name at runtime. If you add
new drawable/mipmap/xml resources that are referenced by name, add a
corresponding `<item>` to that file's `tools:keep` list.

### 4. mapping.txt workflow (CRITICAL for crash deobfuscation)

When R8 + `--obfuscate` is on, the build emits a ProGuard mapping file that
maps obfuscated class/method names back to their original names. Without
it, post-release crash reports from Play Console are unreadable.

**Per-release steps:**

1. After a successful release build, locate the mapping file:
   ```bash
   # Default Flutter path
   build/app/outputs/mapping/release/mapping.txt
   ```
2. **Upload to Play Console** (per release):
   - Open Play Console → your app → **App Bundle Explorer**
   - Select the release build
   - Click **"Upload ReTrace mapping file"** (right-hand panel)
   - Upload `mapping.txt` from this release

   **Fallback path** (if your Play Console doesn't show "App Bundle Explorer" in the sidebar): `Release → App signing → Upload ReTrace mapping file`.

   This is a per-release upload; each build has its own mapping file.
3. **Archive `mapping.txt` in source control** (recommended):
   ```bash
   git tag release/v1.0.1
   mkdir -p build/mappings/v1.0.1
   cp build/app/outputs/mapping/release/mapping.txt build/mappings/v1.0.1/
   git add build/mappings/v1.0.1/
   git commit -m "chore: archive R8 mapping.txt for v1.0.1"
   ```
   This gives you a permanent record. If Play Console's upload is ever
   wiped or a historical crash report comes in, you can re-upload the
   archived mapping file.

4. **For local deobfuscation** of a stack trace:
   ```bash
   $ANDROID_HOME/tools/proguard/bin/retrace.sh \
     build/mappings/v1.0.1/mapping.txt crash-stacktrace.txt
   ```

### 5. QUERY_ALL_PACKAGES Play Store declaration

The app declares `android.permission.QUERY_ALL_PACKAGES` for the
app-blocker use case. Google has a documented exemption for digital
wellbeing and parental control apps, but you MUST declare this on the
Play Console submission form:

- Play Console → your app → **App content** → **Permissions**
- Find `QUERY_ALL_PACKAGES` and check the "Digital wellbeing / parental
  control app" exemption box
- Without this declaration, the first submission will be rejected

## Release commands cheat sheet

```bash
# 1. Build the release AAB
flutter clean
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/symbols/

# 2. Inspect the resulting AAB
#    build/app/outputs/bundle/release/app-release.aab

# 3. Upload to Play Console (manual via web UI)

# 4. Archive the mapping file
mkdir -p build/mappings/v$(grep version pubspec.yaml | cut -d' ' -f2 | cut -d'+' -f1)
cp build/app/outputs/mapping/release/mapping.txt \
   build/mappings/v$(grep version pubspec.yaml | cut -d' ' -f2 | cut -d'+' -f1)/
git add build/mappings/
git commit -m "chore: archive R8 mapping.txt for release"
```

## Local-only builds

For `flutter run --release` on a dev device, you do NOT need a real
keystore — the build falls back to debug signing automatically. R8
warnings in this mode are still useful signals (proves the production
build path works), but you can iterate faster with `flutter run` in
debug mode (no R8) for normal development.
