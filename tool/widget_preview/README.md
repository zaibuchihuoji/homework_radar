# Android widget preview compatibility

Keep both `previewLayout` and `previewImage` in the provider metadata. Hosts that
do not support Android 12's layout previews use the PNG fallback; without it
Android substitutes the app icon. The PNGs are rendered from the actual preview
XML with Android's `RemoteViews`, including the 6 dp header gap. Sample content
is fictional and does not read a user's homework or timetable.

On a dedicated Android test device with the current app installed:

```powershell
python tool/widget_preview/render.py `
  --sdk $env:ANDROID_SDK_ROOT --jdk $env:JAVA_HOME `
  --serial emulator-5580 --output <absolute-artifact-directory> --legacy --verify
```

The separate development helper calls `AppWidgetProviderInfo.loadPreviewImage`
directly, even on a host that supports `previewLayout`. `report.json` must show
two nonzero image/layout IDs and `legacyLoaded: true`. The helper displays those
legacy images for visual verification. It is never included in the product APK.

When changing preview XML, run with `--write-assets` to regenerate the two PNGs,
inspect them, then rebuild the app and repeat `--legacy --verify`. The command
requires Windows SDK build tools 36.0.0, platform 36, JDK and a local Android
debug keystore. Default font size and a 2x-density test device give the checked-in
640×320 and 360×360 images. The tool only stops/reinstalls its own helper package.
