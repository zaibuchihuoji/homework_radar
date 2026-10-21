# Windows 自签试用 iOS 版

需要 iOS 15.5 或更新版本。本 IPA 是 arm64 真机 Release 构建，未使用开发者证书签名，不能直接点开安装，也不是模拟器包。

1. 从云构建附件 `ios-self-sign-ipa` 解压出 `.ipa`。Windows 上可用 `certutil -hashfile 文件名.ipa SHA256` 对照 `SHA256SUMS`。
2. 按 [AltStore Classic 的 Windows 官方步骤](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) 安装 AltServer/AltStore，连接 iPhone 并信任电脑。Apple 账号只在工具中自行输入，不需要提供给项目或聊天。
3. 将 IPA 导入 AltStore，完成自己的 Apple 账号签名后安装。iOS 16 或更新版本若提示开发者模式，按系统提示启用并重启。
4. 免费账号的签名通常 7 天有效，需要通过 AltStore 刷新；安装后根据需要授权通知和相册。

更新或重签时使用同一 Apple 账号和相同的最终 Bundle ID，覆盖更新，不要先卸载；卸载会清除本机应用数据。试用数据建议使用 App 内的导出备份。

本次只打通 iOS 试用构建，不修改 Android 安装包和数据格式。目前 iOS 尚无本项目的原生定时后台同步及 WidgetKit 桌面小组件；iOS 更新使用新 IPA 自签覆盖，不使用 Android APK 下载。前台使用、作业/课表编辑、截图识别和已有本地提醒供本轮试用验证。
