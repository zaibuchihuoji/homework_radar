import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/update_service.dart';

void main() {
  Map<String, dynamic> asset(String name, {String? url}) => {
    'name': name,
    'size': 44000000,
    'state': 'uploaded',
    'browser_download_url':
        url ?? 'https://github.com/$kGithubRepo/releases/download/v1.2.0/$name',
    'digest': 'sha256:${'a' * 64}',
  };
  Map<String, dynamic> release(List<Map<String, dynamic>> assets) => {
    'tag_name': 'v1.2.0',
    'body': '更新说明',
    'assets': assets,
    'html_url': 'https://github.com/$kGithubRepo/releases/tag/v1.2.0',
  };

  test('device ABI outranks release asset order; digest and size travel with selected file', () {
    final info = parseGithubRelease(
      release([
        asset('app-armeabi-v7a-release.apk'),
        asset('app-release.apk'),
        asset('app-x86_64-release.apk'),
        asset('app-arm64-v8a-release.apk'),
      ]),
      supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
    )!;
    expect(info.apkName, 'app-arm64-v8a-release.apk');
    expect(info.apkSize, 44000000);
    expect(info.apkSha256, 'a' * 64);
    expect(info.isNewerThan('1.1.1'), true);
  });
  test(
    'old universal releases work; another architecture is never guessed',
    () {
      final legacy = asset('app-release.apk')..remove('digest');
      expect(
        parseGithubRelease(
          release([legacy]),
          supportedAbis: ['arm64-v8a'],
        )!.apkSha256,
        isNull,
      );
      expect(
        parseGithubRelease(
          release([asset('app-release.apk')]),
          supportedAbis: ['arm64-v8a'],
        )!.apkName,
        'app-release.apk',
      );
      expect(
        parseGithubRelease(
          release([asset('app-armeabi-v7a-release.apk')]),
          supportedAbis: ['x86_64'],
        )!.apkUrl,
        isEmpty,
      );
    },
  );
  test('reject foreign repository, insecure URL, malformed digest and drafts', () {
    for (final url in [
      'http://github.com/$kGithubRepo/releases/download/v1/app-release.apk',
      'https://github.com/other/repo/releases/download/v1/app-release.apk',
      'https://github.com.evil.example/$kGithubRepo/releases/download/v1/app-release.apk',
    ]) {
      expect(
        parseGithubRelease(
          release([asset('app-release.apk', url: url)]),
          supportedAbis: ['arm64-v8a'],
        )!.apkUrl,
        isEmpty,
      );
    }
    expect(
      parseGithubRelease({...release([]), 'draft': true}, supportedAbis: []),
      isNull,
    );
    final bad = asset('app-release.apk')..['digest'] = 'sha256:bad';
    expect(
      parseGithubRelease(release([bad]), supportedAbis: ['arm64-v8a'])!.apkUrl,
      isEmpty,
    );
  });
}
