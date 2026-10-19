"""Render installed widget XML and exercise the legacy previewImage API.

Requires a dedicated Android test device, JDK and Android SDK. Only installs
the separate com.worknote.widgetpreview helper; never reads target app data.
"""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--jdk', type=Path, required=True)
    parser.add_argument('--serial', required=True, help='Explicit dedicated test device')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--write-assets', action='store_true')
    parser.add_argument('--legacy', action='store_true')
    parser.add_argument('--verify', action='store_true')
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
    run([args.jdk / 'bin/javac.exe', '-source', '8', '-target', '8', '-cp', library,
         '-d', classes, source / 'PreviewActivity.java'])
    with zipfile.ZipFile(out / 'classes.jar', 'w') as archive:
        for file in classes.rglob('*.class'):
            archive.write(file, file.relative_to(classes))
    run([tools / 'd8.bat', '--min-api', '26', '--lib', library,
         '--output', dex, out / 'classes.jar'])
    run([tools / 'aapt.exe', 'package', '-f', '-M', source / 'AndroidManifest.xml',
         '-I', library, '-F', out / 'unaligned.apk'])
    with zipfile.ZipFile(out / 'unaligned.apk', 'a') as archive:
        archive.write(dex / 'classes.dex', 'classes.dex')
    apk = out / 'preview-probe.apk'
    run([tools / 'zipalign.exe', '-f', '4', out / 'unaligned.apk', apk])
    run([tools / 'apksigner.bat', 'sign', '--ks', Path.home() / '.android/debug.keystore',
         '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android',
         '--key-pass', 'pass:android', apk])
    adb = [args.sdk / 'platform-tools/adb.exe', '-s', args.serial]
    run(adb + ['install', '-r', apk])
    run(adb + ['shell', 'am', 'force-stop', 'com.worknote.widgetpreview'])
    run(adb + ['shell', 'am', 'start', '-W', '-n', 'com.worknote.widgetpreview/.PreviewActivity',
               '--ez', 'legacy', str(args.legacy).lower()])
    run(adb + ['pull', '/sdcard/Android/data/com.worknote.widgetpreview/files/previews', out])
    report = json.loads((out / 'previews/report.json').read_text(encoding='utf-8'))
    if args.verify:
        assert len(report) == 2
        assert all(x['legacyLoaded'] and x['previewImage'] and x['previewLayout'] for x in report), report
    if args.write_assets:
        # These are density-independent launcher thumbnails, not widget business data.
        target = source.parents[1] / 'android/app/src/main/res/drawable-nodpi'
        target.mkdir(exist_ok=True)
        for item in report:
            name = item['type']
            shutil.copyfile(out / f'previews/{name}.png', target / f'{name}_widget_preview.png')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
