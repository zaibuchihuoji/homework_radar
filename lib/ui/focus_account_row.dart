import 'package:flutter/material.dart';

import '../app_state.dart';
import 'account_platform_icon.dart';
import 'adaptive.dart';
import 'focus_parts.dart';
import 'theme_forms.dart';
import 'tokens.dart';

class FocusAccountRow extends StatelessWidget {
  const FocusAccountRow({
    super.key,
    required this.index,
    required this.title,
    required this.state,
    required this.label,
    this.extra,
    required this.onLogin,
    required this.onLogout,
  });
  final int index;
  final String title, label;
  final String? extra;
  final AccountState state;
  final VoidCallback onLogin, onLogout;

  void _details(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dc) => ThemedDialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 650),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AccountPlatformIcon(index: index, size: 44),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭账号详情',
                      onPressed: () => Navigator.of(dc).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 25,
                    height: 1.4,
                    fontFamily: paletteOf(dc).clay ? 'StudySerif' : null,
                    fontWeight: paletteOf(dc).clay
                        ? FontWeight.w400
                        : FontWeight.w600,
                    color: textPrimary(dc),
                  ),
                ),
                const SizedBox(height: 20),
                FocusSummary(
                  eyebrow: '连接状态',
                  title: state == AccountState.ok
                      ? '已连接'
                      : state == AccountState.needRelogin
                      ? '需要重新登录'
                      : '尚未连接',
                  detail: state == AccountState.needRelogin
                      ? '重新登录后继续同步，原有作业不会在此删除。'
                      : '通过平台官方页面登录，登录信息保存在本机。',
                ),
                if (extra != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: SelectableText(
                      extra!,
                      style: TextStyle(fontSize: 13, color: textSecondary(dc)),
                    ),
                  ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dc).pop();
                    onLogin();
                  },
                  child: Text(
                    state == AccountState.notLoggedIn ? '登录$title' : '重新登录',
                  ),
                ),
                if (state != AccountState.notLoggedIn)
                  TextButton(
                    onPressed: () {
                      Navigator.of(dc).pop();
                      onLogout();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(dc).colorScheme.error,
                    ),
                    child: const Text('退出账号'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    return InkWell(
      onTap: () => _details(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.hairline, width: .6)),
        ),
        child: Row(
          children: [
            AccountPlatformIcon(index: index, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: state == AccountState.needRelogin
                          ? Theme.of(context).colorScheme.error
                          : p.ink2,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '$title账号详情',
              onPressed: () => _details(context),
              icon: Icon(Icons.chevron_right_rounded, size: 21, color: p.ink2),
            ),
          ],
        ),
      ),
    );
  }
}
