# Native widget text regression probe

Run against a dedicated Android test device with synthetic data and the current
product APK already installed. The probe installs a separate public AppWidgetHost;
it does not read or modify the product's preferences or database.

```powershell
python tool/widget_text_probe/run.py --sdk <Android-SDK> --jdk <JDK> --serial <device-serial> --output <artifact-directory> --verify
```

Requires Android SDK platform/build-tools 36 and an existing standard Android
debug keystore. Use `--position 1` to inspect the second list item. Set the test
device's font scale and the product's theme/background through their normal
settings before running each profile.

Use `--verify-transparent` with transparent mode enabled and no custom image to
check that the native panel bitmap has no broad opaque scrim. It reports the
center alpha separately from the native text, row backgrounds and theme trim.

`--verify-contrast` checks that ambient homework labels have no rectangular glyph
backing and retain (on Android 10+) shadow spans across the RemoteViews parcel boundary.
The report includes text colors, glyph backing colors, actual row tint and panel
pixels for comparison with native screenshots. Shadows must not override font metrics or
semantic text colors. Focus course cards and count badges keep their own styles.

The optional `WallpaperProbeActivity` changes only the dedicated test device's
wallpaper. Launch it with `--es wallpaper dark`, `light`, `gray`, `dim` or `mixed`.
`default` restores the factory wallpaper, **not an arbitrary prior user image**;
use this only on a disposable emulator whose wallpaper can be restored. Existing
host views are retained across Android's wallpaper-induced activity recreation.
Launching `TextProbeActivity --ez capture true` captures those same widget IDs
without rebinding or opening the product. On recent Android, a frozen product
process may receive wallpaper notifications late: the text halo softens glyph edges while old colors are cached; visual QA must
check mixed wallpapers, without claiming a guaranteed 4.5:1 ratio on every photo.

The seven samples cover homework at 124x67, 124x151, 260x318, 124x40 and
110x40 dp, and timetable at 124x151 and 110x110 dp. The JSON report checks native
TextView layouts, ellipsis counts, viewport bounds, adapter counts and whether a
partial second title appears in a physically compact homework panel. Complete
deadlines and times must fit. Long titles may ellipsize at the declared 40dp
minimum; larger samples must show the supplied regression titles completely.

After testing, delete the probe's own widget host before uninstalling it:

```powershell
adb -s <device-serial> shell am start -W -n com.worknote.widgettextprobe/.TextProbeActivity --ez cleanup true
adb -s <device-serial> uninstall com.worknote.widgettextprobe
```

Use `--verify-header` to check visible header titles and badges for ellipsis,
vertical clipping and missing separation. Headers may wrap to two lines; list
row title/deadline checks still run with `--verify`.

After replacing the product APK, restart the probe before a layout matrix.
Android package replacement may restore AppWidgetHostView system padding,
invalidating the probe's declared padding-free content dimensions. Retained
host captures are intended for theme/wallpaper changes within one product build.
