"""Validate a device IPA without Xcode; also usable on Windows after download."""
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path


def verify(path):
    path = Path(path)
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, 'Corrupted IPA archive'
        names = archive.namelist()
        assert all(n.startswith('Payload/') for n in names), 'IPA must contain Payload only'
        info = plistlib.loads(archive.read('Payload/Runner.app/Info.plist'))
        assert info['CFBundleIdentifier'] == 'com.worknote.homeworkRadar'
        assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
        assert info['NSPhotoLibraryUsageDescription'].strip()
        assert tuple(map(int, info['MinimumOSVersion'].split('.'))) >= (15, 5)
        assert not any(n.endswith('/embedded.mobileprovision') for n in names)
        # CPU_TYPE_ARM64 in a little-endian 64-bit Mach-O executable.
        binary = archive.read('Payload/Runner.app/' + info['CFBundleExecutable'])
        magic, cpu = struct.unpack_from('<II', binary)
        assert magic == 0xFEEDFACF and cpu == 0x0100000C, 'Not an arm64 device executable'
        assert 'Payload/Runner.app/Frameworks/App.framework/App' in names
        assert 'Payload/Runner.app/Frameworks/Flutter.framework/Flutter' in names
        extension = 'Payload/Runner.app/PlugIns/HomeworkWidgets.appex/'
        widget_info = plistlib.loads(archive.read(extension + 'Info.plist'))
        assert widget_info['CFBundleIdentifier'] == info['CFBundleIdentifier'] + '.HomeworkWidgets'
        assert widget_info['CFBundleVersion'] == info['CFBundleVersion']
        assert widget_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
        assert widget_info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
        widget_binary = archive.read(extension + widget_info['CFBundleExecutable'])
        assert struct.unpack_from('<II', widget_binary) == (0xFEEDFACF, 0x0100000C)

    result = {
        'file': path.name, 'version': info['CFBundleShortVersionString'],
        'build': info['CFBundleVersion'], 'bundleId': info['CFBundleIdentifier'],
        'minimumIOS': info['MinimumOSVersion'], 'architecture': 'arm64',
        'requiresSelfSigning': True, 'temporaryAdHocSignature': True,
        'widgetExtension': widget_info['CFBundleIdentifier'], 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
    }
    return result


if __name__ == '__main__':
    output = verify(sys.argv[1])
    Path(sys.argv[1]).with_name('build-info.json').write_text(
        json.dumps(output, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(output, ensure_ascii=False, indent=2))
