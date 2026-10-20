import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/update_service.dart';

import 'support/synthetic_http.dart';

void main() {
  final network = SyntheticHttp();
  final requested = <Uri>[];
  const name = 'app-arm64-v8a-release.apk';
  const primary = 'https://gitee.com/zaibuchihuoji/homework_radar';
  const backup = 'https://github.com/zaibuchihuoji/homework_radar';
  final hash = 'a' * 64;

  Map<String, dynamic> release(
    String origin, {
    String tag = 'v1.2.0',
    String file = name,
  }) => {
    'tag_name': tag,
    'prerelease': false,
    'body': '发布说明',
    'assets': [
      {
        'name': file,
        'browser_download_url': '$origin/releases/download/$tag/$file',
        if (origin == backup) 'digest': 'sha256:$hash',
        if (origin == backup) 'size': 44000000,
      },
      if (origin == primary)
        {
          'name': 'SHA256SUMS',
          'browser_download_url': '$origin/releases/download/$tag/SHA256SUMS',
        },
    ],
  };
  late SyntheticResponse Function(Uri) response;
  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);
  setUp(() {
    requested.clear();
    response = (uri) {
      if (uri.path.endsWith('/latest')) {
        return SyntheticResponse(
          jsonEncode(release(uri.host == 'gitee.com' ? primary : backup)),
        );
      }
      if (uri.path.endsWith('/SHA256SUMS')) {
        return SyntheticResponse('$hash  $name\n');
      }
      return SyntheticResponse('unexpected', 500);
    };
    network.handler = (_, uri, _) {
      requested.add(uri);
      return response(uri);
    };
  });

  test('Gitee checksum redirects work and selected ABI has same-version GitHub backup', () async {
    final normal = response;
    response = (uri) => uri.path.endsWith('/SHA256SUMS')
        ? SyntheticResponse('', 302, {
            'location': 'https://foruda.gitee.com/attach_file/sums',
          })
        : uri.host == 'foruda.gitee.com'
        ? SyntheticResponse('$hash  $name\n')
        : normal(uri);
    final info = (await fetchLatestRelease(supportedAbis: ['arm64-v8a']))!;
    expect(info.apkUrl, '$primary/releases/download/v1.2.0/$name');
    expect(info.apkSha256, hash);
    expect(info.source, 'Gitee');
    expect(info.fallbackApkUrl, '$backup/releases/download/v1.2.0/$name');
    expect(requested.map((u) => u.host), [
      'gitee.com',
      'gitee.com',
      'foruda.gitee.com',
    ]);
  });

  for (final failure in [
    'unavailable',
    'login html',
    'missing checksum',
    'bad checksum',
    'conflicting checksum',
    'wrong architecture',
    'foreign URL',
  ]) {
    test(
      '$failure on Gitee falls back to GitHub without guessing an APK',
      () async {
        final normal = response;
        response = (uri) {
          if (uri.host != 'gitee.com') return normal(uri);
          if (failure == 'unavailable') throw const SocketException('offline');
          if (failure == 'login html') {
            return SyntheticResponse('<html>请登录</html>');
          }
          if (uri.path.endsWith('SHA256SUMS')) {
            return switch (failure) {
              'missing checksum' => SyntheticResponse('', 404),
              'bad checksum' => SyntheticResponse('not-a-hash  $name'),
              'conflicting checksum' => SyntheticResponse(
                '$hash  $name\n${'b' * 64}  $name',
              ),
              _ => normal(uri),
            };
          }
          final data = release(
            primary,
            file: failure == 'wrong architecture'
                ? 'app-x86_64-release.apk'
                : name,
          );
          if (failure == 'foreign URL') {
            (data['assets'] as List).first['browser_download_url'] =
                'https://gitee.com/other/repo/releases/download/v1.2.0/$name';
          }
          return SyntheticResponse(jsonEncode(data));
        };
        final info = (await fetchLatestRelease(supportedAbis: ['arm64-v8a']))!;
        expect(info.apkUrl, '$backup/releases/download/v1.2.0/$name');
        expect(info.source, 'GitHub');
        expect(info.fallbackApkUrl, isEmpty);
        expect(requested.last.host, 'api.github.com');
      },
    );
  }

  test('a stale mirror cannot hide a newer GitHub release', () async {
    final normal = response;
    response = (uri) => uri.host == 'api.github.com'
        ? SyntheticResponse(jsonEncode(release(backup, tag: 'v1.2.1')))
        : normal(uri);
    final info = (await fetchLatestRelease(
      supportedAbis: ['arm64-v8a'],
      localVersion: '1.2.0',
    ))!;
    expect(info.version, '1.2.1');
    expect(info.apkUrl, '$backup/releases/download/v1.2.1/$name');
  });

  test('up-to-date Gitee still answers when GitHub is unavailable', () async {
    final normal = response;
    response = (uri) =>
        uri.host == 'api.github.com' ? SyntheticResponse('', 503) : normal(uri);
    final info = (await fetchLatestRelease(
      supportedAbis: ['arm64-v8a'],
      localVersion: '1.2.0',
    ))!;
    expect(info.version, '1.2.0');
    expect(info.source, 'Gitee');
  });

  test(
    'both sources unavailable returns a retryable check failure, not latest',
    () async {
      response = (_) => SyntheticResponse('', 503);
      expect(await fetchLatestRelease(supportedAbis: ['arm64-v8a']), isNull);
      expect(requested.map((u) => u.host), ['gitee.com', 'api.github.com']);
    },
  );
}
