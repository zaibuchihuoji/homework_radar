import Foundation

enum WidgetShared {
  static let baseGroup = "group.com.worknote.homeworkRadar"
  static func groupID(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
    // AltStore rewrites the group entitlement and records the signed IDs here.
    let groups = info["ALTAppGroups"] as? [String] ?? []
    return groups.first { $0 == baseGroup || $0.hasPrefix(baseGroup + ".") } ?? baseGroup
  }
  static var container: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID())
  }
  static var defaults: UserDefaults? {
    guard container != nil else { return nil }
    return UserDefaults(suiteName: groupID())
  }
  static func url(timetable: Bool, id: String? = nil) -> URL {
    var value = URLComponents()
    value.scheme = "homework-radar"
    value.host = "widget"
    value.path = timetable ? "/timetable" : "/homework"
    value.queryItems = [URLQueryItem(name: "homeWidget", value: "1")]
    if let id = id { value.queryItems?.append(URLQueryItem(name: "id", value: id)) }
    return value.url!
  }
}

struct HomeworkWidgetRow: Identifiable {
  let id: String
  let title: String
  let course: String
  let due: Date?
}

struct LessonWidgetRow: Identifiable {
  let id: String
  let title: String
  let room: String
  let start: Date?
  let end: Date?
  let time: String
}

enum WidgetData {
  static func dictionary(_ value: String?) -> [String: Any]? {
    guard let data = value?.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
  static func date(_ value: Any?) -> Date? {
    guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
    return Date(timeIntervalSince1970: number.doubleValue / 1000)
  }
  static func homework(_ json: [String: Any], at now: Date) -> [HomeworkWidgetRow] {
    let calendar = Calendar.current
    let month = calendar.component(.month, from: now)
    let year = calendar.component(.year, from: now)
    let start = calendar.date(from: DateComponents(year: month == 1 ? year - 1 : year, month: month == 1 || month >= 8 ? 8 : 2))!
    let end = calendar.date(byAdding: .month, value: 6, to: start)!
    // Only the authoritative, already-hidden/account-filtered snapshot is read.
    // Never fall back to old legacy lists when a snapshot is missing or invalid.
    return (json["items"] as? [[String: Any]] ?? []).compactMap { item in
      guard let id = item["id"] as? String, let title = item["title"] as? String,
            item["status"] as? String != "done", item["status"] as? String != "submitted" else { return nil }
      let due = date(item["d"])
      if let due = due, due < start || due >= end { return nil }
      return HomeworkWidgetRow(id: id, title: title, course: item["course"] as? String ?? "", due: due)
    }.sorted { a, b in
      if a.due == b.due { return a.id < b.id }
      return (a.due ?? .distantFuture) < (b.due ?? .distantFuture)
    }
  }
  static func week(_ json: [String: Any], at now: Date) -> Int? {
    guard let start = date(json["start"]) else { return nil }
    var calendar = Calendar.current
    calendar.firstWeekday = 2
    guard let a = calendar.dateInterval(of: .weekOfYear, for: start)?.start,
          let b = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
          let days = calendar.dateComponents([.day], from: a, to: b).day else { return nil }
    return Int(floor(Double(days) / 7)) + 1
  }
  static func lessons(_ json: [String: Any], at now: Date) -> [LessonWidgetRow] {
    let calendar = Calendar.current
    let weekday = (calendar.component(.weekday, from: now) + 5) % 7 + 1
    let currentWeek = week(json, at: now)
    if let week = currentWeek, week < 1 { return [] }
    let days = json["days"] as? [String: Any] ?? [:]
    func time(_ value: String) -> Date? {
      let parts = value.split(separator: ":").compactMap { Int($0) }
      guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
      return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now)
    }
    return (days[String(weekday)] as? [[String: Any]] ?? []).enumerated().compactMap { index, item in
      let weeks = item["w"] as? [Int] ?? []
      if let week = currentWeek, !weeks.isEmpty && !weeks.contains(week) { return nil }
      guard let title = item["n"] as? String else { return nil }
      let start = item["s"] as? String ?? "", end = item["e"] as? String ?? ""
      return LessonWidgetRow(id: String(index), title: title, room: item["r"] as? String ?? "", start: time(start), end: time(end), time: start.isEmpty || end.isEmpty ? "时间待补全" : "\(start)–\(end)")
    }
  }
}
