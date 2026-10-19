# 2026-10-16 当前源码审查统一修复计划

授权：用户要求修复本轮已确认问题，数据安全和账号隔离优先；补回归并全面验证。未确认的风险先核实，不猜改。既有未提交改动全部保留，原副本位于 ../audit-artifacts/20261016-before-fix。当前目录分支隔离修复，不提交或发布。

## 设计与全局约束
- 账号/备份改变递增数据世代，旧同步不得提交；本地编辑与抓取做三方合并，返回界面时从最新持久层加载。
- 已知相同账号凭据或验证过的用户ID保留关联；无法证明同一账号时先留无凭据业务归档，再清活动平台数据，禁止猜测Cookie身份。
- 隐藏恢复先验证并写回本体再移除隐藏副本；凭据写删必须确认成功，失败向调用者传播。
- 备份恢复先解析验证，保留节次索引，默认值明确恢复；持久化恢复日志保证异常/重启可回滚。
- 默认导入为合并；明确整表替换时给删除影响预览；学校/真实学期变化不能套用旧修正。
- 不完整抓取保留旧数据，分页、局部错误、限额必须传递完整性；用户可见部分同步状态。
- 不因本轮修复直接迁移任务ID；先验证稳定身份方案及旧备注/隐藏迁移，证据不足则保留并记录。
- 所有行为变更先写失败回归再修复。禁止访问真实账号、覆盖用户设备数据或输出凭据。

## 任务与文件所有权
1. 数据安全（主代理）：app_state.dart、storage.dart、backup_service.dart、secure_store.dart、sync_service.dart及相应新回归。覆盖审查01-14、27、41，并提供账号归档读接口。
2. 平台抓取：五个平台service、safe_http.dart、webview_login_page.dart及其测试。覆盖15-26、40和平台待确认项；SyncService由主代理集成完整性和警告信号。
3. 课表解析：course.dart、timetable解析器、jw相关页面、zf_login_page.dart、course_edit_sheet.dart、section_times_page.dart及测试。覆盖28-39、导入确认和学校/周次归属；app_state由主代理实现合并。不要修改timetable_page.dart，向主代理交具体必要修改。
4. 原生与UI：main.dart、notification_service.dart、timetable_widget.dart、platform_cookie.dart、home/calendar/detail/settings/accounts页面、Android/iOS与CI。覆盖42-52及原生待确认项。不要修改app_state，向主代理交所需状态API。
5. 全面验证与独立复审：完整flutter analyze/test；Android debug与release构建；可用模拟器只使用合成账号/课表数据；iOS无Xcode时明确未编译，验证API与配置，不谎报双端通过。

## 接口协调
- 主代理新增 AppState.setHomeworkStatus(String id, HwStatus status)。UI任务可调用。
- 主代理新增 Storage.accountArchives() -> List<Map<String,dynamic>>（无凭据，含createdAt/platform/homework/hiddenItems）；设置页提供只读查看/导出，禁止隐式恢复到其他账号。
- 平台任务沿用 listFailed/failedCount 但任何分页/局部失败置不完整，额外待确认方案先回报。
- 课表解析任务修改Course身份键时兼容旧id，不做存量ID无迁移替换。

## 执行/验证记录
- 基线：flutter analyze --no-pub无问题；flutter test --no-pub 187通过。
- 已有项目外25个错误行为复现，在新回归中改为正确结果断言并先确认失败。
- 各代理分域所有权，同目录协作；禁止git add/commit/reset、覆盖他人文件或取消他人进程。
- 未决风险逐项记录：真实平台响应、OEM、iOS Xcode/真机、通知点击与跨天刷新不得用合成测试替代。

## 本轮修复核对（以当前源码和回归为证据）

| 原审查编号 | 处理结果 | 回归入口 |
|---|---|---|
| 01–03 隐藏恢复/备份导入/退出与在途同步相撞 | 数据世代校验；同步等待事务，事务结束再次失效；提交和收尾使用最新本地可见数据 | data_safety_regression_test、data_ownership_test |
| 04 账号之间混入备注、完成和隐藏记录 | 换号先保存无凭据归档并清活动平台记录；仅同Cookie或已核验的学习通UID保留；其他平台无法证明同一人时保守归档 | data_ownership_test、account_archive_ui_test |
| 05 同步尾部覆盖新界面状态 | 以最新持久层回填，旧世代不更新账号状态/成功时间；提醒与组件取最新可见集 | data_safety_regression_test |
| 06 恢复损坏隐藏作业删除唯一副本 | 先解析和保存本体，再移除隐藏；失败保留原文 | data_safety_regression_test |
| 07 凭据写删虚报成功 | 单个加密集合原子提交Cookie/UID/CSRF；回读确认；清旧原生键失败恢复旧集合并报错；Android后台commit检查结果 | data_ownership_test、data_safety_regression_test、DurablePreferencesTest |
| 08 作息坏条目造成索引前移 | 保留原索引，默认节次原位占位；无默认值的坏晚课拒绝导入 | data_safety_regression_test |
| 09 备份默认字段不覆盖目标自定义 | 明确清除空作息、空学期文本、null开学日期；合法空列表恢复为空 | data_safety_regression_test、data_ownership_test |
| 10–11 双胞胎人工修正折叠/本次预览被旧修正覆盖 | 按ID与周次保留多条修正，本次已编辑结果优先；过期编辑/删除不猜测同ID其他周次 | course_index_test、merge_edited_test、data_ownership_test |
| 12 局部导入默认整表替换 | 五个入口统一确认，默认补充；明确整表替换展示移除课程并先归档；备份坏条目整份拒绝 | timetable_import_confirmation_test、data_ownership_test |
| 13–14 相邻学期/不同学校沿用旧修正 | 不用编辑距离混淆学期数字；来源保存学校与已知学号；更换归属需明确替换，旧校准失效 | semester_text_test、data_ownership_test |
| 15 雨课堂按过滤后数量提前停页 | 分页使用原始列表数量 | platform_integrity_regression_test |
| 16–17 学堂课程后续页/部分章节失败未传递完整性 | listFailed/failedCount覆盖失败路径，保留已取到的条目与旧记录 | platform_integrity_regression_test |
| 18 学习通200错误HTML当空结果 | 识别作业/考试列表容器，陌生或错误页标失败 | platform_integrity_regression_test |
| 19 智慧树/雨课堂部分解析失败当完整 | 解析错误传递失败信号，禁止破坏性清理 | platform_integrity_regression_test |
| 20 智慧树只取前50条 | 完整分页；异常/重复页标不完整 | platform_integrity_regression_test |
| 21 各平台达到安全上限仍报完整 | 达限/循环均置不完整，并显示部分同步提示 | platform_integrity_regression_test |
| 22 MOOC考试游标错误 | 用考试内容的正确游标继续取数 | platform_integrity_regression_test |
| 23 MOOC旧Cookie自动假重登 | 真实会话探测成功后才捕获，保存完成后再退出登录页 | platform_integrity_regression_test、webview_login_commit_test |
| 24 雨课堂www拒绝阻断pro | 主站401/403继续候选域，优先有效origin | platform_integrity_regression_test |
| 25 智慧树否定词误判完成 | unfinished/incomplete不再匹配done | platform_integrity_regression_test |
| 26 可变课程名参与任务ID | 保持旧ID兼容，新增真实课程/任务sourceKey作关联；歧义不删旧候选；首次升级前已改名的旧备注记录保留而不猜匹配 | data_ownership_test |
| 27 部分失败显示近期成功同步 | 部分结果提示失败平台，完整成功才更新lastSync | platform_integrity_regression_test、sync_service |
| 28–31 星期表头、无第字节次、尾部教师、多词课名 | 按真实表头映射；修正文法与块边界，避免吞课 | audit_timetable_regression_test、timetable_parser_test、timetable_text_parser_test |
| 32 Excel合并跨度丢失 | XLSX/SpreadsheetML保留合并元数据 | audit_timetable_regression_test、timetable_xls_parser_test |
| 33–34 OCR无标尺假精确/末端缺列 | 不确定节次标待确认；补齐左右末端缺失星期锚点 | audit_timetable_regression_test、timetable_ocr_test |
| 35–36 无周次、0周、99节保存 | 预览/编辑统一验证，不能勾选或导入无效条目 | audit_timetable_regression_test |
| 37 公告任意第N周校准 | JS只采明确当前周上下文 | audit_timetable_regression_test |
| 38 窄屏重叠块只覆盖代表课程 | 使用整个重叠簇的起止范围 | timetable_page_safety_test |
| 39 引号内Tab误判TSV | 只看引号外的分隔符 | audit_timetable_regression_test |
| 40 请求头阶段不受超时保护 | 发送、收头、读body及整个重定向链共享整体30秒超时 | platform_integrity_regression_test |
| 41 URL/JSON敏感短值漏脱敏 | 扩展敏感键；先脱敏后截断，支持截断中的JSON字符串 | data_safety_regression_test、section_times_test |
| 42 全清再种Cookie破坏其他平台 | 定向清理目标平台；iOS枚举原Cookie对象删除，Android仅过期目标可见Cookie并等待回调 | platform_cookie_scope_test、zf_login_regression_test |
| 43–44 无账号手工作业不可用/无完成入口 | 首页无账号仍管理手工作业，长按和详情支持完成/撤销并持久化 | native_ui_regression_test |
| 45、47 提醒超过预算/iOS64限制 | 按真实触发时间全局排序，严格100作业、400课程、Android500总量/iOS64总量 | native_ui_regression_test |
| 46 未开学组件误显示第一周 | 日历日期差向下取整，负周次不显示；覆盖DST | TimetableWeekTest、TimetableWidgetDataTest |
| 48–51 iOS Cookie API/Scene通道/Keychain返回/通知delegate | 改为存在的API与引擎注册回调；Keychain区分不存在与错误；设置delegate；补真实Keychain XCTest | RunnerTests.swift；本机无Xcode，未运行 |
| 52 iOS仅HTTP学校不可用 | 仅允许WebView非TLS内容 | Info.plist；未做iOS实机兼容声明 |

## 补充复审与待确认项

- 已复现并修复：非Map备份条目清空目标；备份恢复把A账号数据关联到已登录B账号（现在仅进只读归档）；凭据与业务两份存储回滚不一致；同步复活事务中间快照；提交前回填课表；日志删除和回滚同时失败后错误放行。用加密凭据恢复日志与独立recoveryPending保护，日志中不含明文凭据。
- 已复现并修复：五平台登录持久保存之前提前pop成功（10条真实路由回归）；Android apply只确认内存（改commit）；课表校准后/跨周标题与PageView不同步；换学校仍沿用Cookie罐。
- 已复现并修复：HTTP自动重定向绕过白名单，可请求外部域/localhost；自定义CSRF/Referer跨源泄露。真实Dart HttpClient只连loopback验证18条。SDK原本会剥跨源Cookie/Authorization，不能泛称它默认泄露这两项。现在逐跳验证、拒绝HTTPS降级/外部域、跨源剥调用方头、不重放POST。
- 收尾再复现并修复：学习通手动重定向会重新加Cookie，课程href/考试data-url还能直接使用全局其他平台域名。新增12条真实本地socket回归（先9红3绿），全部CX请求现只允许HTTPS超星域及其子域，每一跳单独验证；合法超星子域继续携带会话，整链共30秒预算，拒绝路径按同步失败保留旧数据。
- 已复现并保守处理：HTML含多张独立可解析课表时原先只取一张。现在保留候选并拒绝自动判定，提示切到单张课表或文本导入；不猜不同学期，也不自动合并重复视图。
- 已核实24:00的真实widget：没有复现崩溃；确认传给picker的hour=24违反其约定，现映射为00:00并将课程结束时间还原1440。撤销“已确认崩溃”的表述。
- 仍需脱敏真实成功响应：MOOC RPC服务端JSON结构（本地公开JS的mocTermDto是客户端包装，不能当响应样本）；学堂章节score_deadline是否还需传播到无日期leaf；学习通考试结束/完成与真正截止时间语义及transfer参数t/stuenc；智慧树是否返回数值字符串时间戳。本轮未据此猜改字段语义。
- Android CookieManager无法完整枚举未知路径Cookie。本轮保证不再全清或重种其他平台；不能声称服务器会话已注销或未知路径Cookie全部清除。
- iOS真机、Xcode编译/XCTest、OEM后台通知限制、真实平台登录与真实学校页面仍需相应环境验证。CI新增原生构建/XCTest门禁，未把未运行的检查写成通过。
- 回归和网络测试仅用合成数据/本地HTTP，无真实账号请求。未安装到已有用户设备，未发布、推送或提交。

## 最终本机验证记录

| 检查 | 结果 | 证据（项目外，保留原始日志） |
|---|---|---|
| 完整Flutter回归 | 334通过，0失败；基线187，新增147项覆盖 | `D:/opencode-sessions/work-note/audit-artifacts/full-regression-final.log` |
| flutter analyze --no-pub | No issues found | `D:/opencode-sessions/work-note/audit-artifacts/final-analyze.log` |
| git diff --check | 退出0，无空白错误 | 当前工作树 |
| 真实Gradle :app:testDebugUnitTest | 6 tests，0 failures，0 errors | `D:/opencode-sessions/work-note/audit-artifacts/gradle-real-jvm-tests-local-artifact2.log` |
| :app:assembleDebug | 最后CX补丁后退出0；重新执行Flutter编译/打包 | `D:/opencode-sessions/work-note/audit-artifacts/gradle-cx-final-debug.log` |
| :app:assembleRelease | 最后CX补丁后退出0；重新执行Flutter编译/打包 | `D:/opencode-sessions/work-note/audit-artifacts/gradle-cx-final-release.log` |
| aapt/apksigner | 两包均1.0.1(code3)、签名验证退出0；Release非debug证书、debuggable=false | `D:/opencode-sessions/work-note/audit-artifacts/apk-final-verification.json` |

- Debug：`build/app/outputs/flutter-apk/app-debug.apk`；SHA256 `DC467057A8C3F92305311B54253E6162EBD5C128B251BF7C29EECCC7DCC73855`。
- Release：`build/app/outputs/flutter-apk/app-release.apk`；SHA256 `075E65C7AB69143CE0D5CA010A1E1C6E81CB0C5B688C3FD12613986B773F2C06`。
- 本机Gradle启动存在AF_UNIX默认TEMP路径连接失败。只在任务终端设 `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=D:/opencode-sessions/work-note/audit-artifacts/jvm-sockets` 后通过，未改全局环境/网络。单测还用项目外临时init脚本复用已核SHA的Hamcrest缓存，绕过Aliyun TLS握手故障；APK构建未使用该脚本。
- 已有改动基线副本保留在 `D:/opencode-sessions/work-note/audit-artifacts/20261016-before-fix`；原有未跟踪 `chaoxing_exam_test.dart` 哈希与副本一致。分支 `fix/audit-data-safety-20261016`，未提交。
- Release模拟器实测使用D盘全新一次性API36 AVD `emulator-5580`；不复用已有AVD或其用户数据。真实创建手工作业并标记完成，force-stop后COLD启动仍保留；再安装最后CX补丁的Release升级，设备base.apk哈希与最终产物一致，冷启动及原记录/完成状态再次保留。最后冷启动5470ms、前台MainActivity，记录中AndroidRuntime/Flutter错误0行。备注输入误追加到合成标题，未把它宣称为独立备注持久化验收。
- 设备证据：`D:/opencode-sessions/work-note/audit-artifacts/android-avd-disposable-20261016` 下的 runtime-smoke-result.json、final-upgrade-install.log、final-upgrade-cold-start.log、final-upgrade-runtime-errors.log、ui-final-upgrade-detail.xml/png。一次性AVD测试后关闭，独立数据与证据保留。
