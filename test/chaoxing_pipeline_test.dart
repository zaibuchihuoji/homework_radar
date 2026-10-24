import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/chaoxing_service.dart';

import 'support/synthetic_http.dart';

void main() {
  final network = SyntheticHttp();
  setUpAll(() => HttpOverrides.global = network);
  tearDownAll(() => HttpOverrides.global = null);
  test('exam request can overlap slow homework without exceeding two HTTP requests', () async {
    final workHeld = Completer<void>();
    final workStarted = Completer<void>();
    final examStarted = Completer<void>();
    var active = 0, maximum = 0;
    SyntheticResponse html(String body) => SyntheticResponse(body, 200, {
      'content-type': 'text/html; charset=utf-8',
    });
    network.handler = (_, uri, _) async {
      active++;
      if (active > maximum) maximum = active;
      try {
        if (uri.path.endsWith('/courses/list')) {
          return html(
            '<li class="course"><a href="https://mooc1.chaoxing.com/course"><span class="course-name">课程</span></a></li>',
          );
        }
        if (uri.path == '/course') {
          return html(
            '<input id="courseid" value="1"><input id="clazzid" value="2"><input id="oldenc" value="synthetic"><input id="enc" value="synthetic"><input id="t" value="123">',
          );
        }
        if (uri.path.contains('getAllWork')) {
          workStarted.complete();
          await workHeld.future;
          return html(
            '<div class="ulDiv"><li><div class="titTxt"><a data="8">保留作业</a></div></li></div>',
          );
        }
        if (!examStarted.isCompleted) examStarted.complete();
        return html(
          '<html><title>考试列表</title><div class="main task-list"><div class="has-content"><div class="null-data">暂无考试</div></div></div></html>',
        );
      } finally {
        active--;
      }
    };
    final service = ChaoxingService(cookie: 'synthetic');
    final pending = service.allHomework();
    await workStarted.future;
    var overlapping = false;
    try {
      overlapping = await examStarted.future
          .then((_) => true)
          .timeout(const Duration(milliseconds: 650), onTimeout: () => false);
    } finally {
      workHeld.complete();
    }
    final items = await pending;
    expect(overlapping, isTrue);
    expect(maximum, lessThanOrEqualTo(2));
    expect(items.single.title, '保留作业');
    expect(service.failedCount, 0);
  });

  test('multiple course pipelines retain every work item and cap HTTP concurrency', () async {
    var active = 0, maximum = 0;
    SyntheticResponse html(String body) => SyntheticResponse(body, 200, {
      'content-type': 'text/html; charset=utf-8',
    });
    network.handler = (_, uri, _) async {
      active++;
      if (active > maximum) maximum = active;
      try {
        if (uri.path.endsWith('/courses/list')) {
          return html(
            [
              for (var i = 0; i < 4; i++)
                '<li class="course"><a href="https://mooc1.chaoxing.com/course?i=$i"><span class="course-name">Course $i</span></a></li>',
            ].join(),
          );
        }
        if (uri.path == '/course') {
          return html(
            '<input id="courseid" value="${int.parse(uri.queryParameters['i']!) + 1}"><input id="clazzid" value="2"><input id="oldenc" value="synthetic"><input id="enc" value="synthetic"><input id="t" value="123">',
          );
        }
        if (uri.path.contains('getAllWork')) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
          return html(
            '<div class="ulDiv"><li><div class="titTxt"><a data="8">Work ${uri.queryParameters['courseId']}</a></div></li></div>',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 70));
        return html(
          '<html><title>考试列表</title><div class="main task-list"><div class="has-content"><div class="null-data">暂无考试</div></div></div></html>',
        );
      } finally {
        active--;
      }
    };
    final service = ChaoxingService(cookie: 'synthetic');
    final items = await service.allHomework();
    expect(maximum, 2);
    expect(service.failedCount, 0);
    expect(service.listFailed, isFalse);
    expect(items.map((h) => h.title).toSet(), {
      'Work 1',
      'Work 2',
      'Work 3',
      'Work 4',
    });
  });
}
