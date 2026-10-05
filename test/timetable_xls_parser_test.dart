// Excel/CSV 课表导入解析测试：内存构造工作簿，走真实解析链。
import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/services/timetable_xls_parser.dart';

const _header = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

// 与 timetable_parser_test 的基准页同源的课表网格（上午/一 为行头，课格内换行分段）
List<List<String>> get _grid => [
      _header,
      [
        '上午',
        '一',
        '网络系统管理A\n陆文静\n1-5,8-19[1-2]\n三教107',
        '',
        '计算机组成原理\n胡伟华\n1-5,8-10[1-2]\n三教404',
        '毛泽东思想概论\n涂海燕\n1-5,8,14双[1-2]\n三教407\n软件工程B\n全雪松\n1-5,8-15单[1-2]\n三教407',
        '画法设计与分析A\n翁修焓\n1-5,8-19[1-2]\n三教109',
        '',
        '',
      ],
      [
        '',
        '二',
        '软件工程A\n宋卫卫\n1-5,8-15[3-4]\n三教409',
        '计算机网络A\n李世奇\n黄连树\n1-5,8-16[3-4]\n二教815',
        '形势与政策5\n王淑敏\n11-14[3-4]\n三教103',
        '',
        '大学语文\n边加强\n1-5,8-10[3-4]\n三教409',
        '',
        '',
      ],
      [
        '下午',
        '三',
        '数字图像处理导论\n徐修如\n1-5,8-15[5-6]\n三教202',
        '科技文献检索\n兰张奇\n1-5,8-10[5-6]\n三教106',
        '算法设计与分析A\n苏牧\n1-5,8-13双[5-6]\n三教407\n网络系统管理A\n陆文静\n1-5,8-13双[5-6]\n三教407',
        '',
        '计算机组成原理\n鲍军生\n1-5,8-10[5-6]\n三教404',
        '',
        '',
      ],
      ['', '四', '', '毛泽东思想概论\n徐静娴\n1-5,8,14[7-8]\n三教405', '', '', '', '', ''],
      ['晚上', '五', '', '', '', '', '', '', ''],
    ];

void main() {
  test('xlsx：内存构造工作簿 → 解析出 15 门课', () {
    final excel = Excel.createExcel();
    final sheet = excel['个人课表'];
    for (final row in _grid) {
      sheet.appendRow([for (final c in row) TextCellValue(c)]);
    }
    final bytes = excel.encode()!;
    final courses = TimetableXlsParser.parse(bytes);
    expect(courses, hasLength(15));

    final net = courses.firstWhere(
        (c) => c.name == '网络系统管理A' && c.weekday == 1 && c.startSection == 1);
    expect(net.teacher, '陆文静');
    expect(net.room, '三教107');
    expect(net.weeks.length, 17); // 1-5 + 8-19

    // 周四上午叠课两门都在
    expect(
        courses
            .where((c) => c.weekday == 4 && c.startSection == 1)
            .map((c) => c.name),
        containsAll(['毛泽东思想概论', '软件工程B']));
  });

  test('CSV：带引号字段（单元格内含逗号）', () {
    final csv = StringBuffer();
    for (final row in _grid) {
      csv.writeln(row.map((c) => '"${c.replaceAll('"', '""')}"').join(','));
    }
    final courses = TimetableXlsParser.parse(utf8.encode(csv.toString()));
    expect(courses, hasLength(15));
    final nw = courses.firstWhere((c) =>
        c.name == '计算机网络A' && c.weekday == 2 && c.startSection == 3);
    expect(nw.teacher, '李世奇,黄连树');
    expect(nw.room, '二教815');
  });

  test('TSV：带引号字段（单元格内含换行的多行内容）', () {
    // Excel「文本(制表符分隔)」导出的标准行为：多行单元格用引号包裹，
    // 引号内既有换行又可能含制表符，逐行 split 会拦腰切断
    final tsv = StringBuffer();
    for (final row in _grid) {
      tsv.writeln(row.map((c) => '"${c.replaceAll('"', '""')}"').join('\t'));
    }
    final courses = TimetableXlsParser.parse(utf8.encode(tsv.toString()));
    expect(courses, hasLength(15));
    final nw = courses.firstWhere((c) =>
        c.name == '计算机网络A' && c.weekday == 2 && c.startSection == 3);
    expect(nw.teacher, '李世奇,黄连树');
    expect(nw.room, '二教815');
  });

  test('SpreadsheetML（Excel 2003 XML）：识别 + ss:Index 跳列 + 多行 Data', () {
    // progid 声明在 64 字节之外（前面还有 encoding 声明），探测窗口必须放宽；
    // ss:Index="5" 表示该格在第 5 列，中间缺的列要补空，否则整行列错位
    const xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<?mso-application progid="Excel.Sheet"?>\n'
        '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"'
        ' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">\n'
        ' <Worksheet ss:Name="Sheet1"><Table>\n'
        '  <Row><Cell><Data ss:Type="String">节次</Data></Cell>'
        '<Cell><Data ss:Type="String">星期一</Data></Cell>'
        '<Cell><Data ss:Type="String">星期二</Data></Cell>'
        '<Cell><Data ss:Type="String">星期三</Data></Cell>'
        '<Cell><Data ss:Type="String">星期四</Data></Cell>'
        '<Cell><Data ss:Type="String">星期五</Data></Cell></Row>\n'
        '  <Row><Cell><Data ss:Type="String">1</Data></Cell>'
        '<Cell><Data ss:Type="String">高等数学&#10;王一&#10;1-16周&#10;教A301</Data></Cell>'
        '<Cell ss:Index="5"><Data ss:Type="String">大学英语&#10;李四&#10;2-9周&#10;外语楼201</Data></Cell></Row>\n'
        ' </Table></Worksheet>\n'
        '</Workbook>';
    final courses = TimetableXlsParser.parse(utf8.encode(xml));
    expect(courses, hasLength(2));

    final math = courses.firstWhere((c) => c.name == '高等数学');
    expect(math.weekday, 1);
    expect(math.teacher, '王一');
    expect(math.weeks.length, 16);
    expect(math.room, '教A301');
    expect(math.startSection, 1);
    expect(math.endSection, 2);

    final eng = courses.firstWhere((c) => c.name == '大学英语');
    expect(eng.weekday, 4, reason: 'ss:Index=5 → 第 5 列 → 星期四');
    expect(eng.weeks.length, 8);
    expect(eng.room, '外语楼201');
  });

  test('GBK 文本含解不出的字节序列：不抛异常且仍能认出课表', () {
    // 0x81,0x30,0x81,0x30 是 GB18030 四字节字符的编码，GBK 单字节流解不出；
    // 旧行为 gbk.decode 抛异常 → 退回整篇 UTF-8 乱码 → 报「缺星期表头」
    final text = '星期一,星期二,星期三,星期四,星期五,星期六,星期日\n'
        '"高等数学\n王一\n1-16周\n教A-301",,,,,,\n';
    final bytes = <int>[
      ...gbk.encode(text),
      0x81, 0x30, 0x81, 0x30, //
    ];
    final courses = TimetableXlsParser.parse(bytes);
    expect(courses, hasLength(1));
    expect(courses.first.name, '高等数学');
    expect(courses.first.teacher, '王一');
    expect(courses.first.weeks.length, 16);
  });

  test('伪装成 xls 的 HTML 表格', () {
    final html = '''<html><body><table>
<tr><td>星期一</td><td>星期二</td><td>星期三</td><td>星期四</td><td>星期五</td><td>星期六</td><td>星期日</td></tr>
<tr><td>高等数学<br>王一<br>1-16周<br>教A301</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
</table></body></html>''';
    final courses = TimetableXlsParser.parse(utf8.encode(html));
    expect(courses, hasLength(1));
    expect(courses.first.name, '高等数学');
    expect(courses.first.weeks.length, 16);
  });

  test('老版二进制 xls：给明确提示而非崩溃', () {
    final biff = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    expect(() => TimetableXlsParser.parse(biff),
        throwsA(isA<FormatException>()));
  });
}
