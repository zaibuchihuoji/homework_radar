# Windows 自签试用 iOS 版

需要 iOS 15.5 或更新版本。本 IPA 是 arm64 真机 Release 构建，未使用开发者证书签名，不能直接点开安装，也不是模拟器包。包内带最近作业、今日课表扩展；仅用无证书临时签名保存 App Group 权限，供 AltStore 等工具重新签名时识别，仍须用你的 Apple 账号完成设备授权。

1. 从云构建附件 `ios-self-sign-ipa` 解压出 `.ipa`。Windows 上可用 `certutil -hashfile 文件名.ipa SHA256` 对照 `SHA256SUMS`。
2. 按 [AltStore Classic 的 Windows 官方步骤](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) 安装 AltServer/AltStore，连接 iPhone 并信任电脑。Apple 账号只在工具中自行输入，不需要提供给项目或聊天。
3. 将 IPA 导入 AltStore，保留小组件扩展，完成自己的 Apple 账号签名后安装。主 App 与扩展会分别占用 App ID 名额；若工具移除了扩展，桌面上不会出现小组件。iOS 16 或更新版本若提示开发者模式，按系统提示启用并重启。
4. 免费账号的签名通常 7 天有效，需要通过 AltStore 刷新；安装后根据需要授权通知和相册。

首次打开 App 后，长按 iPhone 桌面空白处，依次进入编辑、添加小组件，搜索“作业通”，选择“最近作业”或“今日课表”及尺寸。组件跟随 App 主题；隐藏、删除、完成和账号切换会发布新的展示快照。iOS 决定组件实际刷新的时机，不能保证每次操作后立即重绘。若搜索不到组件，先确认自签安装时保留了扩展，再打开一次 App。

更新或重签时使用同一 Apple 账号和相同的最终 Bundle ID，覆盖更新，不要先卸载；卸载会清除本机应用数据。试用数据建议使用 App 内的导出备份。

本次只打通 iOS 试用构建，不修改 Android 安装包和数据格式。iOS 已接入 WidgetKit 与 BGAppRefreshTask。后台由系统根据使用情况、电量和网络安排，所选间隔是最早请求时间，不能保证准点；请打开系统后台 App 刷新，不要手动划掉 App。小组件共享组支持 AltStore 的 ALTAppGroups 重签标识，但免费账号的实际授权仍须实体机自签验证；共享不可用时不会清除旧作业。iOS 不允许任意读取桌面壁纸，透明效果可结合所选壁纸图片；iOS 更新使用新 IPA 自签覆盖，不使用 Android APK 下载。前台使用、作业/课表编辑、截图识别和已有本地提醒供本轮试用验证。
