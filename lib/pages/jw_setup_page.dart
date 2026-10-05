/// 教务平台设置页：手输学校名与教务系统网址（超级课程表式导入第一步）。
/// 网址可以是首页（http://jw.xxx.edu.cn）或任意教务页面地址，
/// 登录与导航都在后续 WebView 里完成，这里只负责把入口记下来。
library;

import 'package:flutter/material.dart';

import '../services/jw_config.dart';
import '../ui/adaptive.dart';

class JwSetupPage extends StatefulWidget {
  const JwSetupPage({super.key, this.initial});

  /// 传入已有配置 = 编辑模式（可删除）。
  final JwConfig? initial;

  @override
  State<JwSetupPage> createState() => _JwSetupPageState();
}

class _JwSetupPageState extends State<JwSetupPage> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  String? _error;

  /// 防重入：按钮和键盘回车都能触发 _save，第一次 pop 后退场动画期间
  /// 仍可再点，两次完成会连弹两层（把底下的页面也弹掉）
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _url = TextEditingController(text: widget.initial?.url ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final url = JwStore.normalizeUrl(_url.text);
    if (url == null) {
      setState(() => _error = '网址看起来不对：需要能解析出域名，如 jw.xxx.edu.cn');
      return;
    }
    _saving = true;
    final name = _name.text.trim();
    final cfg = JwConfig(
      name: name.isEmpty ? Uri.parse(url).host : name,
      url: url,
    );
    await JwStore.save(cfg);
    if (mounted) Navigator.of(context).pop(cfg);
  }

  Future<void> _delete() async {
    if (_deleting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除教务配置'),
        content: const Text('只删除教务平台地址配置，不影响已导入的课表与账号登录态。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    _deleting = true;
    await JwStore.clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '更换教务平台' : '添加教务平台'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(
            '输入学校教务系统的网址，登录和进入课表页在下一步的浏览器里完成。\n'
            '教务系统通常仅校园网或学校 VPN 可达。',
            style: TextStyle(fontSize: 13, height: 1.7, color: textSecondary(context)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: '学校名 / 备注（选填）',
              hintText: '如：郑州轻工业大学',
              border: const OutlineInputBorder(),
              suffixIcon: _name.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _name.clear();
                        setState(() {});
                      },
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autofocus: !editing,
            decoration: InputDecoration(
              labelText: '教务系统网址',
              hintText: 'jw.xxx.edu.cn 或 http://jw.xxx.edu.cn',
              border: const OutlineInputBorder(),
              errorText: _error,
              suffixIcon: _url.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _url.clear();
                        setState(() => _error = null);
                      },
                    ),
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Text(
            '常见教务系统都支持：金智青果、正方、强智、URP 等；'
            '识别不了的表格格式可用「粘贴文本导入」或「截图导入」兑底。',
            style: TextStyle(fontSize: 12, height: 1.6, color: textFaint(context)),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            // 只看网址：只填了学校名、网址为空时点保存必然触发网址校验报错，
            // 入口与校验逻辑此前自相矛盾
            onPressed: _url.text.trim().isNotEmpty ? _save : null,
            icon: const Icon(Icons.login_rounded),
            label: Text(editing ? '保存并进入抓取' : '下一步：登录教务'),
          ),
          if (editing) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('删除该教务配置'),
            ),
          ],
        ],
      ),
    );
  }
}
