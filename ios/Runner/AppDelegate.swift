import Flutter
import UIKit
import WebKit

// 凭据存 Keychain（service 固定，account 为键名）
enum SecureBox {
  static func baseQuery(_ key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "homework_radar",
      kSecAttrAccount as String: key,
    ]
  }

  static func read(_ key: String) -> String? {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(baseQuery(key) as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func write(_ key: String, _ value: String) {
    var attrs = baseQuery(key)
    attrs[kSecValueData as String] = value.data(using: .utf8) ?? Data()
    attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemDelete(baseQuery(key) as CFDictionary)
    SecItemAdd(attrs as CFDictionary, nil)
  }

  static func delete(_ key: String) {
    SecItemDelete(baseQuery(key) as CFDictionary)
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "homework_radar/platform",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "getCookie":
          let url = (call.arguments as? [String: Any])?["url"] as? String ?? ""
          guard let host = URL(string: url)?.host else {
            result(nil)
            return
          }
          WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let parts = cookies.filter { cookie in
              var domain = cookie.domain
              if domain.hasPrefix(".") { domain.removeFirst() }
              return host == domain || host.hasSuffix("." + domain)
            }
            .map { "\($0.name)=\($0.value)" }
            result(parts.isEmpty ? nil : parts.joined(separator: "; "))
          }
        case "clearCookies":
          WKWebsiteDataStore.default().removeAllCookies { _ in
            result(true)
          }
        case "setCookie":
          // 与 Android 端 setCookie 对齐：退出任一平台时把其它平台的会话
          // 备份装回，避免「全清」连坐销毁别的平台登录态。
          // iOS 侧没有 CookieManager，罐子与 getCookie 同源
          // （WKWebsiteDataStore.httpCookieStore），写入完成即持久，
          // 不需要 Android 的 flush
          let args = call.arguments as? [String: Any]
          let url = args?["url"] as? String ?? ""
          let pair = args?["cookie"] as? String ?? ""
          let kv = pair.split(separator: "=", maxSplits: 1,
                              omittingEmptySubsequences: false)
          if let host = URL(string: url)?.host, kv.count == 2,
             let cookie = HTTPCookie(properties: [
               .domain: host,
               .name: String(kv[0]),
               .path: "/",
               .value: String(kv[1]),
             ]) {
            WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) {
              result(true)
            }
          } else {
            result(true)
          }
        case "secureRead":
          let key = (call.arguments as? [String: Any])?["key"] as? String ?? ""
          result(SecureBox.read(key))
        case "secureWrite":
          let args = call.arguments as? [String: Any]
          SecureBox.write(args?["key"] as? String ?? "", args?["value"] as? String ?? "")
          result(true)
        case "secureDelete":
          let key = (call.arguments as? [String: Any])?["key"] as? String ?? ""
          SecureBox.delete(key)
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
