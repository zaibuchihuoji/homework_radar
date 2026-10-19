// 学习通考试列表解析（exam-ans/exam/test-list HTML）——行形状未真机校准，
// 宽松行扫描：行内带日期时间才算考试行，截止取行内最晚时间。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/models/homework.dart';
import 'package:homework_radar/services/chaoxing_service.dart';

void main() {
  group('parseExamListHtml 考试列表解析', () {
    test('真机形状 .bottomList ul li：data 挂 URL，最晚时间为截止，已结束=done', () {
      const html = '''
      <html><body><div class="bottomList"><ul>
      <li data="/exam-ans/mooc2/exam/preview?examId=123&courseid=201">
        <div class="left-content">
          <h3>期末考试</h3>
          <p>考试时间：2026-09-10 08:00 ~ 2026-09-10 10:00</p>
        </div>
        <div class="right-content"><p>已结束</p><p class="status">90分</p></div>
      </li>
      </ul></div></body></html>
      ''';
      final items = ChaoxingService.parseExamListHtml(
        html,
        courseName: '线性代数',
        courseId: '201',
        clazzId: '305',
      );
      expect(items.length, 1);
      expect(items[0].title, '期末考试');
      expect(items[0].dueAt, DateTime(2026, 9, 10, 10, 0),
          reason: '开始/结束两列取结束时间');
      expect(items[0].status, HwStatus.done);
      expect(items[0].platform, PlatformKind.chaoxing);
      expect(items[0].id, 'cxe_201_305_123');
    });

    test('表格行 tr 也兼容：取行内最晚时间，examId 入 id', () {
      const html = '''
      <html><body><table>
      <tr><th>考试名称</th><th>时间</th><th>状态</th></tr>
      <tr>
        <td><a title="补考" href="/exam-ans/exam/Do?examId=77">补考</a></td>
        <td>2026-09-10 08:00 ~ 2026-09-10 10:00</td>
        <td>已结束</td>
      </tr>
      </table></body></html>
      ''';
      final items = ChaoxingService.parseExamListHtml(
        html,
        courseName: '线性代数',
        courseId: '201',
        clazzId: '305',
      );
      expect(items.length, 1);
      expect(items[0].title, '补考');
      expect(items[0].dueAt, DateTime(2026, 9, 10, 10, 0));
      expect(items[0].status, HwStatus.done);
      expect(items[0].id, 'cxe_201_305_77');
    });

    test('行内无 examId 用标题哈希兜底；未开始=todo', () {
      const html = '''
      <html><body><div class="bottomList"><ul>
      <li>
        <div class="left-content"><h3>期中测验</h3>
        <p>2026-10-20 09:00 ~ 2026-10-20 11:00</p></div>
        <div class="right-content"><p>未开始</p></div>
      </li>
      </ul></div></body></html>
      ''';
      final items = ChaoxingService.parseExamListHtml(
        html,
        courseName: '课',
        courseId: '1',
        clazzId: '2',
      );
      expect(items.length, 1);
      expect(items[0].title, '期中测验');
      expect(items[0].status, HwStatus.todo);
      expect(items[0].id, startsWith('cxe_1_2_'));
      expect(items[0].id, isNot(contains('exam')));
    });

    test('真实空列表页（模板脚本但无条目）= 空列表', () {
      const html = '''
      <html><body><div class="bottomList"><ul></ul></div>
      <script>function goTask(obj) { var url = \$(obj).attr("data"); }</script>
      </body></html>
      ''';
      final items = ChaoxingService.parseExamListHtml(
        html,
        courseName: '课',
        courseId: '1',
        clazzId: '2',
      );
      expect(items, isEmpty);
    });

    test('中文日期时间形态（2026年9月10日 8:00）可解析', () {
      const html = '''
      <html><body><div class="bottomList"><ul>
      <li><h3>补考</h3><p>2026年9月10日 08:00 到 2026年9月10日 09:30</p></li>
      </ul></div></body></html>
      ''';
      final items = ChaoxingService.parseExamListHtml(
        html,
        courseName: '课',
        courseId: '1',
        clazzId: '2',
      );
      expect(items.single.dueAt, DateTime(2026, 9, 10, 9, 30));
    });
  });
}
