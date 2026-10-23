import XCTest
import SwiftUI
import WidgetKit

final class WidgetRenderTests: XCTestCase {
  @MainActor func testWidgetLayoutsAcrossThemesAndSizes() throws {
    if #available(iOS 16.0, *) {
      let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("widget-snapshots")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let styles = ["clean", "green", "morandi", "pixel", "amoled", "paper", "comic", "receipt", "editorial", "terminal", "journal"]
      for style in styles {
        for timetable in [false, true] {
          var sample = RadarEntry.load(at: Date(), preview: true)
          sample = RadarEntry(date: sample.date, homework: sample.homework, timetable: sample.timetable,
            theme: ["style": style], transparent: false, image: nil)
          let renderer = ImageRenderer(content: RadarWidgetView(entry: sample, timetable: timetable)
            .environment(\.widgetFamily, .systemSmall).frame(width: 160, height: 160))
          let image = try XCTUnwrap(renderer.uiImage)
          try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(style)-\(timetable ? "timetable" : "homework")-small.png"))
        }
      }
      for timetable in [false, true] {
        for family in [WidgetFamily.systemMedium, .systemLarge] {
          let sample = RadarEntry.load(at: Date(), preview: true)
          let renderer = ImageRenderer(content: RadarWidgetView(entry: sample, timetable: timetable)
            .environment(\.widgetFamily, family).environment(\.sizeCategory, .accessibilityLarge)
            .frame(width: 340, height: family == .systemLarge ? 350 : 160))
          try XCTUnwrap(renderer.uiImage?.pngData()).write(to: folder.appendingPathComponent("large-font-\(timetable)-\(family).png"))
        }
      }
    }
  }
}
