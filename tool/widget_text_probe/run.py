"""Measure real RemoteViews from the installed product in a temporary test host.

Requires a dedicated synthetic Android test device, JDK and Android SDK.
Only installs a separate public widget host; never reads or writes target preferences.
"""
from pathlib import Path
import argparse
import json
import os
import subprocess
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--jdk', type=Path, required=True)
    parser.add_argument('--serial', required=True, help='Explicit dedicated test device')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--verify-transparent', action='store_true',
                        help='With no custom image, verify the panel has no broad scrim')
    parser.add_argument('--verify-contrast', action='store_true',
                        help='Verify ambient homework text retains a native contrast halo')
    parser.add_argument('--verify-header', action='store_true', help='Check complete header labels and badge separation')
    parser.add_argument('--position', type=int, default=0)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).resolve().parent
    tools = args.sdk / 'build-tools/36.0.0'
    library = args.sdk / 'platforms/android-36/android.jar'
    env = os.environ.copy()
    env['JAVA_HOME'] = str(args.jdk)

    def run(command):
        result = subprocess.run([str(x) for x in command], env=env,
                                capture_output=True, text=True, encoding='utf-8', errors='replace')
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        return result.stdout

    classes, dex = out / 'classes', out / 'dex'
    classes.mkdir(exist_ok=True)
    dex.mkdir(exist_ok=True)
    run([args.jdk / 'bin/javac.exe', '-encoding', 'UTF-8', '-source', '8', '-target', '8', '-cp', library,
         '-d', classes, *source.glob('*.java')])
    with zipfile.ZipFile(out / 'classes.jar', 'w') as archive:
        for file in classes.rglob('*.class'):
            archive.write(file, file.relative_to(classes))
    run([tools / 'd8.bat', '--min-api', '26', '--lib', library,
         '--output', dex, out / 'classes.jar'])
    run([tools / 'aapt.exe', 'package', '-f', '-M', source / 'AndroidManifest.xml',
         '-I', library, '-F', out / 'unaligned.apk'])
    with zipfile.ZipFile(out / 'unaligned.apk', 'a') as archive:
        archive.write(dex / 'classes.dex', 'classes.dex')
    apk = out / 'widget-text-probe.apk'
    run([tools / 'zipalign.exe', '-f', '4', out / 'unaligned.apk', apk])
    run([tools / 'apksigner.bat', 'sign', '--ks', Path.home() / '.android/debug.keystore',
         '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android',
         '--key-pass', 'pass:android', apk])
    adb = [args.sdk / 'platform-tools/adb.exe', '-s', args.serial]
    run(adb + ['install', '-r', apk])
    run(adb + ['shell', 'am', 'force-stop', 'com.worknote.widgettextprobe'])
    run(adb + ['shell', 'appwidget', 'grantbind', '--package', 'com.worknote.widgettextprobe', '--user', '0'])
    run(adb + ['shell', 'am', 'start', '-W', '-n', 'com.worknote.widgettextprobe/.TextProbeActivity',
               '--ei', 'position', str(args.position)])
    import time
    time.sleep(10)
    run(adb + ['pull', '/sdcard/Android/data/com.worknote.widgettextprobe/files/text-fit', out])
    report = json.loads((out / 'text-fit/report.json').read_text(encoding='utf-8'))
    if args.verify:
        assert len(report) == 7, report
        for item in report:
            if item.get('empty'):
                assert item['emptyFits'], item
                continue
            assert item['ready'] and item['titleInside'] and item['detailFits'], item
            # At the declared 40dp minimum, long titles may ellipsize. They
            # must never be vertically cropped or hide the complete deadline.
            assert item['height'] < 67 or item['titleFits'], item
            if item['type'] == 'homework' and item['height'] < 100:
                assert item['visibleTitleCount'] == 1, item
    if args.verify_header:
        for item in report:
            header = item['header']
            assert header['hostPaddingLeft'] == 0 and header['hostPaddingTop'] == 0, 'Probe padding changed; restart probe after installing product APK'
            if header['visible']:
                assert header['titleFits'] and header['markFits'] and header['gapPx'] > 0, item
    if args.verify_transparent:
        # Theme trim can cross the center, but a broad opaque scrim must not.
        assert all(item['panelCenterAlpha'] <= 0x20 for item in report), report
    if args.verify_contrast:
        assert all(item['haloPreservesMetricsAndColors'] for item in report), report
        assert all(item.get('sdk',29) < 29 or (item['titleHalos'] > 0 and item['detailHalos'] > 0)
                   for item in report if item['ready'] and item['type'] == 'homework'), report
        assert all(item['titleBacking'] == 0 and item['detailBacking'] == 0
                   for item in report if item['ready'] and item['type'] == 'homework'), report
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
