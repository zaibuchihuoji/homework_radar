import Flutter
import UIKit
import WebKit
import Security
import UserNotifications
import BackgroundTasks

// 凭据存 Keychain（service 固定，account 为键名）
enum SecureBox {
  static func baseQuery(_ key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "homework_radar",
      kSecAttrAccount as String: key,
    ]
  }

  static func read(_ key: String) throws -> String? {
    var item: CFTypeRef?
    var query = baseQuery(key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data,
          let value = String(data: data, encoding: .utf8) else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status == errSecSuccess ? errSecDecode : status))
    }
    return value
  }

  @discardableResult static func write(_ key: String, _ value: String) -> Bool {
    let changes: [String: Any] = [
      kSecValueData as String: value.data(using: .utf8) ?? Data(),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let status = SecItemUpdate(baseQuery(key) as CFDictionary, changes as CFDictionary)
    if status == errSecSuccess { return true }
    if status != errSecItemNotFound { return false }
    let attrs = baseQuery(key).merging(changes) { _, new in new }
    return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
  }

  @discardableResult static func delete(_ key: String) -> Bool {
    let status = SecItemDelete(baseQuery(key) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let reminderRefreshIdentifier = "com.worknote.homeworkRadar.reminderRefresh"
  private var reminderChannel: FlutterMethodChannel?
  private var appIsForeground = false
  private var reminderTaskRegistered = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self, selector: #selector(appDidBecomeActive(_:)),
      name: UIApplication.didBecomeActiveNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(appDidEnterBackground(_:)),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    reminderTaskRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: reminderRefreshIdentifier, using: nil) { [weak self] task in
      guard let refresh = task as? BGAppRefreshTask, let self = self else {
        task.setTaskCompleted(success: false)
        return
      }
      self.handleReminderRefresh(refresh)
    }
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc private func appDidBecomeActive(_ notification: Notification) {
    appIsForeground = true
    reminderChannel?.invokeMethod("foreground", arguments: true)
  }

  @objc private func appDidEnterBackground(_ notification: Notification) {
    appIsForeground = false
    reminderChannel?.invokeMethod("foreground", arguments: false)
  }

  private func scheduleReminderRefresh() throws {
    guard reminderTaskRegistered else {
      throw NSError(domain: "homework_radar.reminder", code: 1, userInfo: nil)
    }
    let request = BGAppRefreshTaskRequest(identifier: reminderRefreshIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
    try BGTaskScheduler.shared.submit(request)
  }

  private func handleReminderRefresh(_ task: BGAppRefreshTask) {
    do { try scheduleReminderRefresh() }
    catch { NSLog("Reminder background refresh could not be scheduled") }

    // Never start a second Dart engine: it could race the UI's local writes.
    // If iOS launched a cold process with no existing engine, fail safely and
    // rely on the next foreground launch and the scheduled reopen reminder.
    var completed = false
    let finish: (Bool) -> Void = { success in
      DispatchQueue.main.async {
        guard !completed else { return }
        completed = true
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
      }
    }
    task.expirationHandler = { finish(false) }
    DispatchQueue.main.async { [weak self] in
      guard let channel = self?.reminderChannel else {
        finish(false)
        return
      }
      channel.invokeMethod("run", arguments: "ios_reminders") { value in
        finish(value as? Bool == true)
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
      let background = FlutterMethodChannel(
        name: "homework_radar/background_sync",
        binaryMessenger: engineBridge.applicationRegistrar.messenger())
      reminderChannel = background
      background.setMethodCallHandler { [weak self] (call, result) in
        switch call.method {
        case "ready":
          result(self?.appIsForeground == true)
        case "configure":
          if (call.arguments as? [String: Any])?["scheduleLocalReminders"] as? Bool == false {
            result(true)
            return
          }
          guard let self = self else {
            result(FlutterError(code: "schedule", message: "无法安排后台提醒更新", details: nil))
            return
          }
          do {
            try self.scheduleReminderRefresh()
            result(true)
          } catch {
            result(FlutterError(code: "schedule", message: "无法安排后台提醒更新", details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      let channel = FlutterMethodChannel(
        name: "homework_radar/platform",
        binaryMessenger: engineBridge.applicationRegistrar.messenger())
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
          WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeCookies],
              modifiedSince: .distantPast) {
            result(true)
          }
        case "clearDomainCookies":
          let domains = (call.arguments as? [String: Any])?["domains"] as? [String] ?? []
          let store = WKWebsiteDataStore.default().httpCookieStore
          store.getAllCookies { cookies in
            let selected = cookies.filter { cookie in
              let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
              return domains.contains { root in
                domain == root || domain.hasSuffix("." + root) || root.hasSuffix("." + domain)
              }
            }
            let group = DispatchGroup()
            for cookie in selected {
              group.enter()
              store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) { result(true) }
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
          do { result(try SecureBox.read(key)) }
          catch { result(FlutterError(code: "secure", message: "Keychain read failed", details: nil)) }
        case "secureWrite":
          let args = call.arguments as? [String: Any]
          if SecureBox.write(args?["key"] as? String ?? "", args?["value"] as? String ?? "") {
            result(true)
          } else {
            result(FlutterError(code: "secure", message: "Keychain write failed", details: nil))
          }
        case "secureDelete":
          let key = (call.arguments as? [String: Any])?["key"] as? String ?? ""
          if SecureBox.delete(key) { result(true) }
          else { result(FlutterError(code: "secure", message: "Keychain delete failed", details: nil)) }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }
}
