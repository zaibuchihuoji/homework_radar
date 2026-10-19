import '../models/homework.dart';

class HomeworkDuplicates {
  static String normalize(String value) {
    final ascii = String.fromCharCodes(
      value.runes.map((c) => c >= 0xff01 && c <= 0xff5e ? c - 0xfee0 : c),
    );
    return ascii.toLowerCase().replaceAll(
      RegExp(r'[\s，,。．.：:；;！!？?、·\-—_（）()\[\]【】]'),
      '',
    );
  }

  static bool same(
    String course,
    String title,
    String otherCourse,
    String otherTitle,
  ) {
    final a = normalize(title), b = normalize(otherTitle);
    if (a.isEmpty || a != b) return false;
    final c = normalize(course), d = normalize(otherCourse);
    return c.isEmpty || d.isEmpty || c == d;
  }

  static bool matches(String course, String title, HomeworkItem existing) =>
      same(course, title, existing.course, existing.title);
}
