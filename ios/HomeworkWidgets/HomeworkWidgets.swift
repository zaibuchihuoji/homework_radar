import SwiftUI
import WidgetKit
import UIKit

struct RadarEntry: TimelineEntry {
  let date: Date
  let homework: [String: Any]?
  let timetable: [String: Any]?
  let theme: [String: Any]
  let transparent: Bool
  let image: UIImage?

  static func load(at date: Date, preview: Bool = false) -> RadarEntry {
    let defaults = WidgetShared.defaults
    var homework = WidgetData.dictionary(defaults?.string(forKey: "homework_snapshot"))
    if homework?["version"] as? Int != 2 || homework?["items"] as? [[String: Any]] == nil { homework = nil }
    var timetable = WidgetData.dictionary(defaults?.string(forKey: "tt_json"))
    if preview {
      homework = ["items": [["id": "preview", "title": "阅读与写作 · 第四单元", "course": "大学英语", "d": date.addingTimeInterval(7200).timeIntervalSince1970 * 1000]]]
      let weekday = (Calendar.current.component(.weekday, from: date) + 5) % 7 + 1
      timetable = ["days": [String(weekday): [["n": "程序设计实验", "r": "实验楼 402", "s": "14:30", "e": "16:10", "w": []]]]]
    }
    let image = defaults?.string(forKey: "widget_wallpaper").flatMap { name -> UIImage? in
      guard name == "widget-wallpaper.jpg", let path = WidgetShared.container?.appendingPathComponent(name).path else { return nil }
      return UIImage(contentsOfFile: path)
    }
    return RadarEntry(date: date, homework: homework, timetable: timetable,
      theme: WidgetData.dictionary(defaults?.string(forKey: "widget_theme")) ?? [:],
      transparent: defaults?.bool(forKey: "widget_transparent") ?? false, image: image)
  }
}

struct RadarProvider: TimelineProvider {
  func placeholder(in context: Context) -> RadarEntry { .load(at: Date(), preview: true) }
  func getSnapshot(in context: Context, completion: @escaping (RadarEntry) -> Void) {
    completion(.load(at: Date(), preview: context.isPreview))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<RadarEntry>) -> Void) {
    let now = Date(), data = RadarEntry.load(at: Date())
    // Locally prepared dates keep deadlines and class changes correct while
    // WidgetKit budgets refreshes. No extension network or database writes.
    var dates = Set((0...24).map { now.addingTimeInterval(Double($0 * 1800)) })
    let calendar = Calendar.current
    dates.insert(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!)
    if let tasks = data.homework {
      WidgetData.homework(tasks, at: now).compactMap(\.due).filter { $0 > now && $0 < now.addingTimeInterval(86400) }.forEach { dates.insert($0) }
    }
    if let lessons = data.timetable {
      for day in [now, now.addingTimeInterval(86400)] {
        WidgetData.lessons(lessons, at: day).flatMap { [$0.start, $0.end].compactMap { $0 } }.filter { $0 > now && $0 < now.addingTimeInterval(86400) }.forEach { dates.insert($0) }
      }
    }
    let entries = dates.sorted().map { RadarEntry(date: $0, homework: data.homework, timetable: data.timetable, theme: data.theme, transparent: data.transparent, image: data.image) }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800))))
  }
}

struct RadarWidgetView: View {
  let entry: RadarEntry
  let timetable: Bool
  @Environment(\.widgetFamily) private var family
  var body: some View {
    RadarWidgetContent(entry: entry, timetable: timetable, family: family)
  }
}

struct RadarWidgetContent: View {
  let entry: RadarEntry
  let timetable: Bool
  let family: WidgetFamily
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.sizeCategory) private var sizeCategory

  private var style: String { entry.theme["style"] as? String ?? "clean" }
  private var small: Bool { family == .systemSmall }
  private var largeText: Bool { sizeCategory.isAccessibilityCategory }
  private var limit: Int { small || largeText ? 1 : family == .systemLarge ? 4 : 2 }
  private var font: Font.Design {
    ["pixel", "terminal", "receipt"].contains(style) ? .monospaced : ["paper", "editorial", "journal"].contains(style) ? .serif : style == "comic" ? .rounded : .default
  }
  private var colors: [String: Any] {
    let mode = entry.theme["mode"] as? String ?? "system"
    return entry.theme[mode == "dark" || (mode == "system" && colorScheme == .dark) ? "dark" : "light"] as? [String: Any] ?? [:]
  }
  private func color(_ key: String, fallback: UInt32) -> Color {
    let value = (colors[key] as? NSNumber)?.uint32Value ?? fallback
    return Color(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: Double(value >> 24) / 255)
  }
  private var ink: Color { color("ink", fallback: 0xff202428) }
  private var secondary: Color { color("secondary", fallback: 0xff626668) }
  private var accent: Color { color("accent", fallback: 0xffd4a900) }
  private var outline: Color {
    let ink = (colors["ink"] as? NSNumber)?.uint32Value ?? 0xff202428
    let red = Double((ink >> 16) & 255)
    let green = Double((ink >> 8) & 255)
    let blue = Double(ink & 255)
    let lightInk = red * 0.299 + green * 0.587 + blue * 0.114 > 140.0
    return lightInk ? .black.opacity(0.9) : .white.opacity(0.9)
  }
  private var radius: CGFloat { ["pixel", "receipt", "terminal", "editorial"].contains(style) ? 0 : style == "comic" ? 7 : style == "journal" ? 5 : 12 }
  private var tasks: [HomeworkWidgetRow] { entry.homework.map { WidgetData.homework($0, at: entry.date) } ?? [] }
  private var lessons: [LessonWidgetRow] {
    let rows = entry.timetable.map { WidgetData.lessons($0, at: entry.date) } ?? []
    return rows.filter { $0.end == nil || $0.end! > entry.date }
  }
  private var title: String {
    let text = timetable ? "今日课表" : "最近作业"
    return style == "terminal" ? "> " + text : style == "receipt" ? "· " + text + " ·" : text
  }
  private var badge: String {
    if timetable {
      guard let data = entry.timetable, let week = WidgetData.week(data, at: entry.date) else { return "周次未校准" }
      return week < 1 ? "未开学" : "第\(week)周"
    }
    return "\(tasks.count)项"
  }
  private var inset: CGFloat { if #available(iOS 17.0, *) { return 0 }; return 14 }

  var body: some View {
    content
      .font(.system(.subheadline, design: font))
      .foregroundColor(ink)
      .shadow(color: entry.transparent ? outline : .clear, radius: 1)
      .widgetURL(WidgetShared.url(timetable: timetable, id: small && !timetable ? tasks.first?.id : nil))
      .privacySensitive()
      .modifier(RadarBackground(entry: entry, surface: color("surface", fallback: 0xfffffbea)))
  }
  private var content: some View {
    VStack(alignment: .leading, spacing: small ? 7 : 9) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(title).font(.system(.headline, design: font)).fontWeight(style == "comic" || style == "pixel" ? .heavy : .bold).lineLimit(2).layoutPriority(1)
          if !small { Spacer(minLength: 4); badgeView }
        }
        if small { HStack { Spacer(); badgeView } }
      }
      if ["terminal", "receipt", "paper", "editorial", "journal"].contains(style) {
        Rectangle().fill(accent).frame(height: style == "editorial" ? 3 : 1)
      }
      if timetable { timetableBody } else { homeworkBody }
      Spacer(minLength: 0)
      if !small && !largeText {
        HStack {
          Text(style == "terminal" ? "SYNC · 作业通" : style == "receipt" ? "作业通 / 学习清单" : "作业通")
          Spacer()
          let remaining = (timetable ? lessons.count : tasks.count) - limit
          if remaining > 0 { Text("另有\(remaining)项，点开查看") }
        }.font(.caption2).foregroundColor(secondary).lineLimit(1)
      }
    }.padding(inset).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
  private var badgeView: some View {
    Text(badge).font(.system(.caption, design: font).weight(.semibold)).fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 7).padding(.vertical, 4)
      .background(entry.transparent ? Color.clear : color("focus", fallback: 0xffffdf42))
      .foregroundColor(entry.transparent ? ink : color("onFocus", fallback: 0xff202428))
      .clipShape(RoundedRectangle(cornerRadius: radius))
      .overlay(RoundedRectangle(cornerRadius: radius).stroke(style == "comic" || entry.transparent ? accent : .clear, lineWidth: 1))
  }
  @ViewBuilder private var homeworkBody: some View {
    if entry.homework == nil { empty("打开作业通", "同步后在这里查看作业") }
    else if tasks.isEmpty { empty("作业都处理好了", "留一点时间给自己") }
    else {
      ForEach(Array(tasks.prefix(limit))) { item in
        Link(destination: WidgetShared.url(timetable: false, id: item.id)) {
          VStack(alignment: .leading, spacing: 3) {
            Text(item.title).font(.system(.subheadline, design: font).weight(.semibold)).lineLimit(small ? 2 : 3).layoutPriority(2)
            Text(dueText(item.due)).foregroundColor(item.due.map { $0 <= entry.date } == true ? .red : secondary)
              .font(.system(.caption, design: font).weight(.medium)).lineLimit(2).layoutPriority(1)
            if !small || !largeText { Text(item.course).font(.caption).foregroundColor(secondary).lineLimit(small ? 1 : 2) }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        if item.id != tasks.prefix(limit).last?.id { Divider() }
      }
    }
  }
  @ViewBuilder private var timetableBody: some View {
    if entry.timetable == nil { empty("尚未导入课表", "点开作业通导入课程") }
    else if lessons.isEmpty { empty("今天没有待上课程", "留一点时间给自己") }
    else {
      ForEach(Array(lessons.prefix(limit))) { lesson in
        Link(destination: WidgetShared.url(timetable: true)) {
          VStack(alignment: .leading, spacing: 3) {
            Text(lesson.title).font(.system(.subheadline, design: font).weight(.semibold)).lineLimit(small ? 2 : 3)
            Text(lesson.time).font(.system(.caption, design: font).weight(.medium)).lineLimit(2)
            if !small || !largeText { Text(lesson.room).font(.caption).foregroundColor(secondary).lineLimit(1) }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        if lesson.id != lessons.prefix(limit).last?.id { Divider() }
      }
    }
  }
  private func empty(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(.subheadline, design: font).weight(.semibold)).lineLimit(3)
      if !largeText { Text(subtitle).font(.caption).foregroundColor(secondary).lineLimit(2) }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }
  private func dueText(_ due: Date?) -> String {
    guard let due = due else { return "未设截止" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M/d HH:mm"
    return (due <= entry.date ? "已逾期 · " : "截止 ") + formatter.string(from: due)
  }
}

struct RadarBackground: ViewModifier {
  let entry: RadarEntry
  let surface: Color
  @ViewBuilder private var background: some View {
    if entry.transparent, let image = entry.image { Image(uiImage: image).resizable().scaledToFill().clipped() }
    else { entry.transparent ? Color.clear : surface }
  }
  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 17.0, *) { content.containerBackground(for: .widget) { background } }
    else { content.background(background) }
  }
}

struct HomeworkWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "HomeworkWidget", provider: RadarProvider()) { RadarWidgetView(entry: $0, timetable: false) }
      .configurationDisplayName("最近作业").description("查看当前学期未完成作业与准确截止时间。")
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
struct TimetableWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "TimetableWidget", provider: RadarProvider()) { RadarWidgetView(entry: $0, timetable: true) }
      .configurationDisplayName("今日课表").description("随日期与周次变化，查看下一节课和上课地点。")
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
