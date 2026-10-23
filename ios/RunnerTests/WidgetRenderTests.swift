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
          let renderer = ImageRenderer(content: RadarWidgetContent(entry: sample, timetable: timetable, family: .systemSmall).padding(16).frame(width: 172, height: 172).background(Color(red: 1, green: 0.984, blue: 0.918)))
          let image = try XCTUnwrap(renderer.uiImage)
          try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(style)-\(timetable ? "timetable" : "homework")-small.png"))
        }
      }
      for timetable in [false, true] {
        for family in [WidgetFamily.systemSmall, .systemMedium, .systemLarge] {
          let sample = RadarEntry.load(at: Date(), preview: true)
          let renderer = ImageRenderer(content: RadarWidgetContent(entry: sample, timetable: timetable, family: family).environment(\.sizeCategory, .accessibilityLarge)
            .padding(16).frame(width: family == .systemSmall ? 172 : 364, height: family == .systemLarge ? 382 : 172).background(Color(red: 1, green: 0.984, blue: 0.918)))
          try XCTUnwrap(renderer.uiImage?.pngData()).write(to: folder.appendingPathComponent("large-font-\(timetable)-\(family).png"))
        }
        for whiteInk in [false, true] {
          let sample = RadarEntry.load(at: Date(), preview: true)
          let theme: [String: Any] = ["style": whiteInk ? "amoled" : "clean", "mode": "light", "light": ["ink": whiteInk ? 0xffffffff : 0xff111111, "secondary": whiteInk ? 0xffdddddd : 0xff333333]]
          let entry = RadarEntry(date: sample.date, homework: sample.homework, timetable: sample.timetable, theme: theme, transparent: true, image: nil)
          let renderer = ImageRenderer(content: RadarWidgetContent(entry: entry, timetable: timetable, family: .systemSmall).padding(16).frame(width: 172, height: 172)
            .background(whiteInk ? Color.white : Color.black))
          try XCTUnwrap(renderer.uiImage?.pngData()).write(to: folder.appendingPathComponent("transparent-\(whiteInk ? "light-wall" : "dark-wall")-\(timetable).png"))
        }
      }
    }
  }
}
