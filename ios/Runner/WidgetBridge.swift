import Flutter
import UIKit
import ImageIO

final class WidgetBridge {
  private let channel: FlutterMethodChannel
  private var initialURL: String?
  private var navigationReady = false
  private var assetToken: String?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "homework_radar/widgets", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "group": result(["groupId": WidgetShared.groupID(), "available": WidgetShared.container != nil])
      case "prepareAssets": result(self.prepareAssets())
      case "initialUrl":
        self.navigationReady = true
        let value = self.initialURL
        self.initialURL = nil
        result(value)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  func open(_ url: URL) {
    guard url.scheme == "homework-radar", url.host == "widget",
          ["/homework", "/timetable"].contains(url.path) else { return }
    if navigationReady { channel.invokeMethod("openURL", arguments: url.absoluteString) }
    else { initialURL = url.absoluteString }
  }
  private func prepareAssets() -> Bool {
    guard let container = WidgetShared.container, let defaults = WidgetShared.defaults else { return false }
    let target = container.appendingPathComponent("widget-wallpaper.jpg")
    guard let path = defaults.string(forKey: "glass_bg_path"), !path.isEmpty else {
      defaults.removeObject(forKey: "widget_wallpaper")
      assetToken = nil
      return defaults.synchronize()
    }
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    let token = "\(path)|\(attributes?[.modificationDate] ?? "")|\(attributes?[.size] ?? "")"
    if assetToken == token, FileManager.default.fileExists(atPath: target.path) { return defaults.synchronize() }
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
          ] as CFDictionary), let data = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else { return false }
    do {
      // Only export the selected presentation image, never a business database.
      if (try? Data(contentsOf: target)) != data { try data.write(to: target, options: .atomic) }
      defaults.set(target.lastPathComponent, forKey: "widget_wallpaper")
      assetToken = token
      return defaults.synchronize()
    } catch { return false }
  }
}
