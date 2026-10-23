# iOS 小组件与后台同步实施计划

目标：把已有作业、课表小组件和安全同步机制接到 iOS，保留免费 Windows 自签试用路线。不更改业务存储、账号凭据键或 Android 原生代码。本轮本人执行，不使用子代理。

方案：WidgetKit 扩展只读取 App 发布的展示快照，通过 App Group 共享；兼容 AltStore 的 ALTAppGroups 重签标识。沿用现有过滤、主题色、透明/照片设置与导航 URI。采用同一个 FlutterEngine 承载前台和 BGAppRefreshTask，避免并发引擎覆盖本地缓存。系统自行决定后台执行时间，间隔为最早请求时间。

- [ ] Dart 接口测试：iOS kind、重签组初始化、不可用组不假报成功；Android 保持现有调用。
- [ ] 原生共享组与 WidgetKit 数据模型/视图：最近作业、今日课表，小/中/大，跨学期/跨日/周次过滤、主题字体、URL 编码、透明/图片背景。
- [ ] Xcode 扩展目标、共享权限、URL Scheme 与主 App 通道。组件不读取 Cookie 或写业务数据。
- [ ] 单 FlutterEngine、BGAppRefresh 注册/到期/重试/过期完成；设置允许 iOS 调整并解释系统限制。
- [ ] 必要 Dart 回归与静态检查；原生快照/导航/调度测试及云端设备包构建。模拟器验证与实体自签验证分别报告。

已有证据：AltStore ResignAppOperation 会把签名后的共享组数组写入 ALTAppGroups；FetchProvisioningProfilesOperation 为主 App/扩展注册共享组。不能把普通 Xcode Personal Team 的权限限制直接视为 AltStore 无法工作，也不承诺尚未实测的免费账号授权成功。
