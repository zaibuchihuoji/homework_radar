# iOS 小组件与后台同步实施计划

目标：把已有作业、课表小组件和安全同步机制接到 iOS，保留免费 Windows 自签试用路线。不更改业务存储、账号凭据键或 Android 原生代码。本轮本人执行，不使用子代理。

方案：WidgetKit 扩展只读取 App 发布的展示快照，通过 App Group 共享；兼容 AltStore 的 ALTAppGroups 重签标识。沿用现有过滤、主题色、透明/照片设置与导航 URI。采用同一个 FlutterEngine 承载前台和 BGAppRefreshTask，避免并发引擎覆盖本地缓存。系统自行决定后台执行时间，间隔为最早请求时间。

- [x] Dart 接口测试：iOS kind、重签组初始化、不可用组不假报成功；Android 保持现有调用。
- [x] 原生共享组与 WidgetKit 数据模型/视图：最近作业、今日课表，小/中/大，跨学期/跨日/周次过滤、主题字体、URL 编码、透明/图片背景。
- [x] Xcode 扩展目标、共享权限、URL Scheme 与主 App 通道。组件不读取 Cookie 或写业务数据。
- [x] 单 FlutterEngine、BGAppRefresh 注册/到期/重试/过期完成；设置允许 iOS 调整并解释系统限制。
- [x] 必要 Dart 回归、静态检查、原生快照/导航/调度测试及云端设备包构建通过；单独记录桌面自动化失败与实体机待验证项目。

已有证据：AltStore ResignAppOperation 会把签名后的共享组数组写入 ALTAppGroups；FetchProvisioningProfilesOperation 为主 App/扩展注册共享组。不能把普通 Xcode Personal Team 的权限限制直接视为 AltStore 无法工作，也不承诺尚未实测的免费账号授权成功。

2026-10-23 验证结果：

- Dart 必要回归 32 项与针对性静态检查通过。覆盖快照发布、隐藏/恢复/删除/状态变更、旧备注/课程/隐藏记录保护、账号切换时的导出顺序、精确 ID 冷/热启动导航、主题绑定，以及后台调度/失败重试/提醒更新联动；这是自动化回归，不等同于真实账号逐个平台手动登录验证。
- 最终产品源码 d581a2b 的云端构建 39942878582 通过 8 项原生测试：同一 FlutterEngine 到 Dart 的刷新、Keychain 写入/读取/替换/删除、中文 ML Kit OCR、调度策略、AltStore 共享组解析、历史学期过滤/无截止作业保留/导航编码、周次计算及主题/尺寸/大字体布局渲染。已检查生成的布局截图。
- 同次构建产出 arm64 iPhoneOS Release IPA，主 App 和组件扩展的临时签名及 App Group 权限校验通过；Windows 上重新验证 ZIP CRC、设备架构、扩展/版本元数据，并核对云端 SHA256。文件为 homework-radar-1.2.1-ios-self-sign.ipa，SHA256 为 710ab2d1522f908ad941aacc5d9533389874d43782a11f2e236697d54d7df494。
- 上述构建中的桌面自动化已进入系统“作业通”组件选择器，未完成添加与点击；失败证据是系统 Add Widget 按钮标签带前导空格。0e0f73d 仅调整 UI 测试和流水线，产品源码未变；随后单独执行的 39946678140 编译成功，但 RunnerUITests-Runner 在开始执行测试前被 signal kill 终止（Early unexpected exit, operation never finished bootstrapping）。已保存日志与最终模拟器截图，不把它算作通过，也不据此推断 App 故障。未继续重复耗时构建；桌面添加与点击仍需实机确认。
- 尚未完成实体机免费账号自签、实际系统后台唤醒、真机定时提醒、真实平台逐个登录同步或完整相册操作；不得报告为通过。Android 原生代码、业务数据模型和本地业务存储未改动。
