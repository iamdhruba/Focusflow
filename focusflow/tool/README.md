# `focusflow/tool/`

Build-time helpers that don't ship with the app.

## `generate_app_icon.py`

Render `focusflow/assets/images/app_icon.png` — the launcher icon source
that `flutter_launcher_icons` repaints into Android's launcher assets.

The script must produce a PNG that visually matches the `BrandLogo` widget
on the Get Started welcome screen:

* `focusflow/lib/shared/widgets/brand_logo.dart`
* `focusflow/lib/core/theme/app_theme.dart` (gradient stops)

### Requirements

* Python 3.10+ with `Pillow` and `fontTools`.
* The Flutter SDK installed at `C:\flutter` for the bundled
  `MaterialIcons-Regular.otf` (used to extract the `Icons.self_improvement_rounded`
  glyph outline). If your SDK lives elsewhere, edit `DEFAULT_FONT_PATH`
  near the top of the script.

### Run

```bash
python focusflow/tool/generate_app_icon.py
```

After it runs:

```bash
dart run flutter_launcher_icons
```

…then rebuild the APK so the launcher icon shows up in `app-release.apk`.

### Why this isn't a Flutter test

`flutter test` does not auto-load `MaterialIcons-Regular.otf`. Painting an
`Icons.self_improvement_rounded` widget in a test would silently emit a
gradient-only PNG with an empty cell where the icon glyph should be. The
Python pipeline reads the glyph outline from the bundled `.otf` directly,
tessellates the TrueType Béziers, and composites it onto a downsampled
gradient — no Flutter runtime required.
