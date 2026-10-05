// 学期文本相似判定：换学期整表替换不能被一次 OCR 误读触发（#47）。
import 'package:flutter_test/flutter_test.dart';
import 'package:homework_radar/app_state.dart';

void main() {
  test('完全一致（含仅空白/大小写差异）视为同一学期', () {
    expect(AppState.sameSemesterText('2025-2026学年第2学期', '2025-2026学年第2学期'),
        isTrue);
    expect(AppState.sameSemesterText('2025-2026 学年第 2 学期', '2025-2026学年第2学期'),
        isTrue);
  });

  test('OCR 误读一两个字符仍视为同一学期（宁少替换不误清课表）', () {
    expect(AppState.sameSemesterText('2025-2026学年第3学期', '2025-2026学年第2学期'),
        isTrue,
        reason: '「第2/第3」一字之差是典型 OCR 噪声');
    expect(AppState.sameSemesterText('第二学期', '第三学期'), isTrue);
    expect(AppState.sameSemesterText('2025-2O26学年第2学期', '2025-2026学年第2学期'),
        isTrue,
        reason: '数字 0 误读为字母 O');
  });

  test('真正换学期（学年+学期都变）判定为不同', () {
    expect(AppState.sameSemesterText('2024-2025学年第2学期', '2025-2026学年第1学期'),
        isFalse);
    expect(AppState.sameSemesterText('2025-2026学年第1学期', '2026-2027学年第2学期'),
        isFalse);
  });

  test('任一侧为空不参与相似度（由调用方按空值分支处理）', () {
    expect(AppState.sameSemesterText('', '2025-2026学年第2学期'), isFalse);
    expect(AppState.sameSemesterText('2025-2026学年第2学期', ''), isFalse);
  });
}
