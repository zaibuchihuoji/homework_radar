import BackgroundTasks
import Flutter
import UIKit

enum BackgroundRefreshPolicy {
  static func nextDate(enabled: Bool, minutes: Int, retryAt: Double?, now: Date) -> Date? {
    guard enabled else { return nil }
    let interval = [15, 30, 60, 120].contains(minutes) ? minutes : 30
    let regular = now.addingTimeInterval(Double(interval * 60))
    guard let retry = retryAt, retry.isFinite else { return regular }
    return min(regular, max(now.addingTimeInterval(60), Date(timeIntervalSince1970: retry / 1000)))
  }
}

/// Uses the exact same engine/state/transaction queue as the foreground app.
final class BackgroundRefresh {
  static let identifier = "com.worknote.homeworkRadar.refresh"
  private let channel: FlutterMethodChannel
  private var ready = false
  private var running = false
  private var pending = [(Bool) -> Void]()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "homework_radar/background_sync", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(false); return }
      switch call.method {
      case "ready":
        self.ready = true
        result(UIApplication.shared.applicationState != .background)
        self.flush()
      case "configure":
        let options = call.arguments as? [String: Any] ?? [:]
        var stored: [String: Any] = ["enabled": options["enabled"] as? Bool == true, "minutes": options["minutes"] as? Int ?? 30]
        if let retry = options["retryAt"] as? NSNumber, retry.doubleValue.isFinite { stored["retryAt"] = retry }
        UserDefaults.standard.set(stored, forKey: "ios_background_sync")
        do { try self.schedule(); result(true) }
        catch { result(FlutterError(code: "background", message: "后台刷新安排失败，请检查系统后台 App 刷新设置", details: nil)) }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  func register() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { [weak self] task in
      guard let self = self else { task.setTaskCompleted(success: false); return }
      // Queue a successor before doing any network work, including cold launches.
      try? self.schedule()
      var finished = false
      let complete: (Bool) -> Void = { success in
        guard !finished else { return }
        finished = true
        task.setTaskCompleted(success: success)
      }
      task.expirationHandler = {
        DispatchQueue.main.async {
          // Do not destroy the engine or interrupt a storage commit on expiry.
          complete(false)
        }
      }
      self.run(completion: complete)
    }
  }
  func foreground(_ active: Bool) {
    guard ready else { return }
    channel.invokeMethod("foreground", arguments: active)
  }
  func run(completion: @escaping (Bool) -> Void) {
    pending.append(completion)
    flush()
  }
  private func flush() {
    guard ready, !running, !pending.isEmpty else { return }
    running = true
    channel.invokeMethod("run", arguments: "periodic") { [weak self] result in
      guard let self = self else { return }
      self.running = false
      let callbacks = self.pending
      self.pending.removeAll()
      callbacks.forEach { $0(result as? Bool == true) }
    }
  }
  private func schedule() throws {
    let options = UserDefaults.standard.dictionary(forKey: "ios_background_sync") ?? [:]
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
    guard let next = BackgroundRefreshPolicy.nextDate(
      enabled: options["enabled"] as? Bool == true,
      minutes: options["minutes"] as? Int ?? 30,
      retryAt: (options["retryAt"] as? NSNumber)?.doubleValue, now: Date()) else { return }
    let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
    request.earliestBeginDate = next
    try BGTaskScheduler.shared.submit(request)
  }
}
