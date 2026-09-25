import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Models
struct SchedulePayload: Codable {
    let groupTitle: String?
    let dayTitle: String?
    let isTomorrow: Bool?
    let weekParity: String?
    let statusHeadline: String?
    let statusSubline: String?
    let lessons: [LessonPayload]?
}

struct LessonPayload: Codable, Identifiable {
    var id: String { "\(startTime ?? "")_\(disciplineTitle ?? "")" }
    let time: String?
    let startTime: String?
    let endTime: String?
    let disciplineTitle: String?
    let type: String?
    let room: String?
    let teacher: String?
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let schedule: SchedulePayload?
    let activeLesson: LessonPayload?
    let nextLesson: LessonPayload?
    let targetCountdownDate: Date?
    let isLessonActive: Bool
    let statusBadgeText: String
}

// MARK: - Helper Functions
func parseTimeToMinutes(_ timeStr: String) -> Int? {
    let parts = timeStr.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
    guard parts.count >= 2,
          let h = Int(parts[0]),
          let m = Int(parts[1]) else { return nil }
    return h * 60 + m
}

func typeColor(_ type: String) -> Color {
    let t = type.lowercased()
    if t.contains("лек") {
        return Color(red: 0.0, green: 0.82, blue: 1.0)
    } else if t.contains("лаб") {
        return Color(red: 1.0, green: 0.58, blue: 0.0)
    } else if t.contains("сем") || t.contains("прак") {
        return Color(red: 0.35, green: 0.85, blue: 0.45)
    }
    return Color(red: 0.0, green: 0.82, blue: 1.0)
}

func displayLessons(allLessons: [LessonPayload], activeLesson: LessonPayload?, currentMinutes: Int, maxCount: Int = 2) -> [LessonPayload] {
    if let active = activeLesson, let activeIdx = allLessons.firstIndex(where: { $0.id == active.id }) {
        return Array(allLessons.dropFirst(activeIdx).prefix(maxCount))
    }
    
    let upcoming = allLessons.filter { lesson in
        guard let eStr = lesson.endTime, let eMin = parseTimeToMinutes(eStr) else { return true }
        return eMin > currentMinutes
    }
    
    if !upcoming.isEmpty {
        return Array(upcoming.prefix(maxCount))
    }
    
    return Array(allLessons.suffix(maxCount))
}

// MARK: - Timeline Provider
struct Provider: TimelineProvider {
    private let appGroupId = "group.ru.bmstu.neo"
    private let scheduleKey = "schedule_data"

    func placeholder(in context: Context) -> SimpleEntry {
        let sample = getSampleSchedule()
        return SimpleEntry(
            date: Date(),
            schedule: sample,
            activeLesson: sample.lessons?.first,
            nextLesson: sample.lessons?.last,
            targetCountdownDate: Calendar.current.date(byAdding: .minute, value: 35, to: Date()),
            isLessonActive: true,
            statusBadgeText: "Идёт пара"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let sched = loadSchedule() ?? getSampleSchedule()
        let entry = buildEntry(date: Date(), schedule: sched)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let currentSchedule = loadSchedule()
        let currentDate = Date()
        var entries: [SimpleEntry] = []

        // Current entry
        entries.append(buildEntry(date: currentDate, schedule: currentSchedule))

        if let schedule = currentSchedule,
           let lessons = schedule.lessons,
           !lessons.isEmpty,
           schedule.isTomorrow != true {
            let cal = Calendar.current
            var boundaryMinutes: Set<Int> = []

            for lesson in lessons {
                if let sStr = lesson.startTime, let sMin = parseTimeToMinutes(sStr) {
                    boundaryMinutes.insert(sMin)
                }
                if let eStr = lesson.endTime, let eMin = parseTimeToMinutes(eStr) {
                    boundaryMinutes.insert(eMin)
                }
            }

            let sortedMinutes = boundaryMinutes.sorted()
            let curH = cal.component(.hour, from: currentDate)
            let curM = cal.component(.minute, from: currentDate)
            let currentTotalM = curH * 60 + curM

            for m in sortedMinutes where m > currentTotalM {
                if let tDate = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: currentDate) {
                    entries.append(buildEntry(date: tDate, schedule: currentSchedule))
                }
            }
        }

        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        let timeline = Timeline(entries: entries, policy: .after(refreshDate))
        completion(timeline)
    }

    private func buildEntry(date: Date, schedule: SchedulePayload?) -> SimpleEntry {
        guard let schedule = schedule,
              let lessons = schedule.lessons,
              !lessons.isEmpty,
              schedule.isTomorrow != true else {
            let isTom = schedule?.isTomorrow ?? false
            let badge = isTom ? "Завтра" : (schedule?.lessons?.isEmpty == false ? "Расписание" : "Пар нет")
            return SimpleEntry(
                date: date,
                schedule: schedule,
                activeLesson: nil,
                nextLesson: schedule?.lessons?.first,
                targetCountdownDate: nil,
                isLessonActive: false,
                statusBadgeText: badge
            )
        }

        let cal = Calendar.current
        let curH = cal.component(.hour, from: date)
        let curM = cal.component(.minute, from: date)
        let currentMinutes = curH * 60 + curM

        var activeLesson: LessonPayload? = nil
        var nextLesson: LessonPayload? = nil
        var activeEndTime: Date? = nil
        var nextStartTime: Date? = nil

        for lesson in lessons {
            guard let sStr = lesson.startTime, let eStr = lesson.endTime,
                  let sMin = parseTimeToMinutes(sStr),
                  let eMin = parseTimeToMinutes(eStr) else { continue }

            let sDate = cal.date(bySettingHour: sMin / 60, minute: sMin % 60, second: 0, of: date)
            let eDate = cal.date(bySettingHour: eMin / 60, minute: eMin % 60, second: 0, of: date)

            if currentMinutes >= sMin && currentMinutes < eMin {
                activeLesson = lesson
                activeEndTime = eDate
                break
            } else if currentMinutes < sMin && nextLesson == nil {
                nextLesson = lesson
                nextStartTime = sDate
            }
        }

        if let active = activeLesson {
            return SimpleEntry(
                date: date,
                schedule: schedule,
                activeLesson: active,
                nextLesson: nextLesson,
                targetCountdownDate: activeEndTime,
                isLessonActive: true,
                statusBadgeText: "Идёт пара"
            )
        } else if let next = nextLesson {
            let firstSMin = parseTimeToMinutes(lessons.first?.startTime ?? "") ?? 0
            let isBreak = currentMinutes >= firstSMin
            return SimpleEntry(
                date: date,
                schedule: schedule,
                activeLesson: nil,
                nextLesson: next,
                targetCountdownDate: nextStartTime,
                isLessonActive: false,
                statusBadgeText: isBreak ? "Перемена" : "До начала"
            )
        } else {
            return SimpleEntry(
                date: date,
                schedule: schedule,
                activeLesson: nil,
                nextLesson: nil,
                targetCountdownDate: nil,
                isLessonActive: false,
                statusBadgeText: "Пары завершены"
            )
        }
    }

    private func loadSchedule() -> SchedulePayload? {
        guard let userDefaults = UserDefaults(suiteName: appGroupId),
              let jsonString = userDefaults.string(forKey: scheduleKey),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(SchedulePayload.self, from: data)
    }

    private func getSampleSchedule() -> SchedulePayload {
        SchedulePayload(
            groupTitle: "ИУ7-43Б",
            dayTitle: "Сегодня (Среда)",
            isTomorrow: false,
            weekParity: "Числитель",
            statusHeadline: "Идет 2 пара • 10:15 - 11:50",
            statusSubline: "До конца пары 35 мин",
            lessons: [
                LessonPayload(
                    time: "10:15 - 11:50",
                    startTime: "10:15",
                    endTime: "11:50",
                    disciplineTitle: "Базы данных",
                    type: "Лек",
                    room: "502л",
                    teacher: "Иванов И.И."
                ),
                LessonPayload(
                    time: "12:00 - 13:35",
                    startTime: "12:00",
                    endTime: "13:35",
                    disciplineTitle: "Операционные системы",
                    type: "Лаб",
                    room: "395ю",
                    teacher: "Петров П.П."
                )
            ]
        )
    }
}

// MARK: - Widget Views
extension View {
    @ViewBuilder
    func applyWidgetBackground() -> some View {
        let bg = Color(red: 0.04, green: 0.08, blue: 0.16)
        if #available(iOS 17.0, *) {
            self.containerBackground(bg, for: .widget)
        } else {
            self.background(bg)
        }
    }
}

struct ScheduleWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if let sched = entry.schedule {
                switch family {
                case .systemSmall:
                    SmallWidgetView(entry: entry, sched: sched)
                case .systemMedium:
                    MediumWidgetView(entry: entry, sched: sched)
                case .systemLarge:
                    LargeWidgetView(entry: entry, sched: sched)
                default:
                    MediumWidgetView(entry: entry, sched: sched)
                }
            } else {
                EmptyStateView()
            }
        }
        .applyWidgetBackground()
    }
}

// MARK: - Small Widget (1x1)
struct SmallWidgetView: View {
    let entry: SimpleEntry
    let sched: SchedulePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(sched.groupTitle ?? "МГТУ")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                Spacer()
                if let parity = sched.weekParity, !parity.isEmpty {
                    Text(parity.prefix(4))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            HStack(spacing: 3) {
                Circle()
                    .fill(entry.isLessonActive ? Color.green : Color(red: 0.0, green: 0.82, blue: 1.0))
                    .frame(width: 5, height: 5)
                Text(entry.statusBadgeText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                if let target = entry.targetCountdownDate {
                    Text(target, style: .relative)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                }
            }

            Divider().background(Color.white.opacity(0.15))

            let displayLesson = entry.activeLesson ?? entry.nextLesson ?? sched.lessons?.first
            if let lesson = displayLesson {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(lesson.time ?? "")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                        Spacer()
                        if let room = lesson.room, !room.isEmpty && room != "—" {
                            Text(room)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(4)
                                .foregroundColor(.white)
                        }
                    }

                    Text(lesson.disciplineTitle ?? "")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let type = lesson.type, !type.isEmpty {
                        Text(type)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(typeColor(type).opacity(0.2))
                            .foregroundColor(typeColor(type))
                            .cornerRadius(3)
                    }
                }
            } else {
                Spacer()
                Text(sched.isTomorrow == true ? "На завтра пар нет ✨" : "На сегодня пар нет ✨")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
            Spacer()
        }
        .padding(11)
    }
}

// MARK: - Medium Widget (2x1) - Compact High Density
struct MediumWidgetView: View {
    let entry: SimpleEntry
    let sched: SchedulePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row: Single compact horizontal line
            HStack(alignment: .center) {
                HStack(spacing: 5) {
                    Text(sched.groupTitle ?? "МГТУ")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))

                    Text("•")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))

                    Text(sched.dayTitle ?? "Сегодня")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))

                    if let parity = sched.weekParity, !parity.isEmpty {
                        Text("(\(parity.prefix(4)))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                Spacer()

                // Compact Status Badge with Live Countdown
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.isLessonActive ? Color.green : Color(red: 0.0, green: 0.82, blue: 1.0))
                        .frame(width: 6, height: 6)

                    Text(entry.statusBadgeText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)

                    if let target = entry.targetCountdownDate {
                        Text(target, style: .relative)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(5)
            }

            Divider().background(Color.white.opacity(0.12))

            // Full-width Lessons List
            if let lessons = sched.lessons, !lessons.isEmpty {
                let cal = Calendar.current
                let curM = cal.component(.hour, from: entry.date) * 60 + cal.component(.minute, from: entry.date)
                let visibleLessons = sched.isTomorrow == true
                    ? Array(lessons.prefix(2))
                    : displayLessons(allLessons: lessons, activeLesson: entry.activeLesson, currentMinutes: curM, maxCount: 2)

                VStack(spacing: 5) {
                    ForEach(Array(visibleLessons.enumerated()), id: \.offset) { index, lesson in
                        let isActive = entry.isLessonActive && entry.activeLesson?.id == lesson.id
                        MediumLessonRow(lesson: lesson, isActive: isActive)

                        if index == 0 && visibleLessons.count > 1 {
                            Divider().background(Color.white.opacity(0.06))
                        }
                    }
                }
            } else {
                Spacer()
                CenterTextView(text: sched.isTomorrow == true ? "На завтра пар нет ✨" : "На сегодня пар нет ✨")
                Spacer()
            }
        }
        .padding(12)
    }
}

// MARK: - Medium Lesson Row
struct MediumLessonRow: View {
    let lesson: LessonPayload
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isActive ? Color(red: 0.0, green: 0.82, blue: 1.0) : Color.white.opacity(0.15))
                .frame(width: 3, height: 26)

            Text(lesson.time ?? "")
                .font(.system(size: 11, weight: isActive ? .bold : .medium))
                .foregroundColor(isActive ? Color(red: 0.0, green: 0.82, blue: 1.0) : .white.opacity(0.85))
                .frame(width: 78, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(lesson.disciplineTitle ?? "")
                        .font(.system(size: 12, weight: isActive ? .bold : .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let type = lesson.type, !type.isEmpty {
                        Text(type)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(typeColor(type).opacity(0.2))
                            .foregroundColor(typeColor(type))
                            .cornerRadius(3)
                    }
                }

                if let teacher = lesson.teacher, !teacher.isEmpty && teacher != "Кафедра" {
                    Text(teacher)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let room = lesson.room, !room.isEmpty && room != "—" {
                Text(room)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isActive ? Color(red: 0.0, green: 0.44, blue: 0.95).opacity(0.6) : Color.white.opacity(0.12))
                    .foregroundColor(isActive ? .white : .white.opacity(0.9))
                    .cornerRadius(6)
            }
        }
    }
}

// MARK: - Large Widget (2x2)
struct LargeWidgetView: View {
    let entry: SimpleEntry
    let sched: SchedulePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sched.groupTitle ?? "МГТУ")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                        if let parity = sched.weekParity, !parity.isEmpty {
                            Text("•  \(parity)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    Text(sched.dayTitle ?? "Сегодня")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.isLessonActive ? Color.green : Color(red: 0.0, green: 0.82, blue: 1.0))
                        .frame(width: 6, height: 6)
                    Text(entry.statusBadgeText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    if let target = entry.targetCountdownDate {
                        Text(target, style: .relative)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
            }

            Divider().background(Color.white.opacity(0.15))

            if let lessons = sched.lessons, !lessons.isEmpty {
                let cal = Calendar.current
                let curM = cal.component(.hour, from: entry.date) * 60 + cal.component(.minute, from: entry.date)
                let visibleLessons = sched.isTomorrow == true
                    ? Array(lessons.prefix(5))
                    : displayLessons(allLessons: lessons, activeLesson: entry.activeLesson, currentMinutes: curM, maxCount: 5)

                VStack(spacing: 7) {
                    ForEach(visibleLessons) { lesson in
                        let isActive = entry.isLessonActive && entry.activeLesson?.id == lesson.id
                        MediumLessonRow(lesson: lesson, isActive: isActive)
                    }
                }
            } else {
                Spacer()
                CenterTextView(text: sched.isTomorrow == true ? "На завтра пар нет ✨" : "На сегодня пар нет ✨")
                Spacer()
            }
            Spacer()
        }
        .padding(14)
    }
}

struct CenterTextView: View {
    let text: String
    var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 28))
                .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
            Text("BMSTU neo")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            Text("Откройте приложение для синхронизации расписания")
                .font(.system(size: 10, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 16)
        }
        .padding()
    }
}

// MARK: - Widget Configuration
struct ScheduleWidget: Widget {
    let kind: String = "ScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ScheduleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Расписание пар МГТУ")
        .description("Текущая пара, аудитория и расписание занятий BMSTU neo.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Live Activity Widget
@available(iOS 16.1, *)
struct ScheduleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleActivityAttributes.self) { context in
            // Lock Screen Banner
            VStack(alignment: .leading, spacing: 6) {
                // Header row: Group • Status • Live Countdown
                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(context.state.isBreak ? Color.orange : Color(red: 0.0, green: 0.82, blue: 1.0))
                            .frame(width: 7, height: 7)
                        Text(context.attributes.groupTitle)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                        Text("•")
                            .foregroundColor(.white.opacity(0.4))
                        Text(context.state.statusBadge)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    let targetDate = Date(timeIntervalSince1970: context.state.targetTimestamp)
                    if context.state.targetTimestamp > Date().timeIntervalSince1970 {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                                .font(.system(size: 10, weight: .bold))
                            Text(targetDate, style: .timer)
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        }
                        .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

                // Main lesson row
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(context.state.disciplineTitle)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if !context.state.lessonType.isEmpty {
                                Text(context.state.lessonType)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.cyan.opacity(0.2))
                                    .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                                    .cornerRadius(4)
                            }
                        }

                        HStack(spacing: 6) {
                            if !context.state.timeRange.isEmpty {
                                Text(context.state.timeRange)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            if !context.state.teacher.isEmpty && context.state.teacher != "Кафедра" {
                                Text("•  \(context.state.teacher)")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    if !context.state.room.isEmpty && context.state.room != "—" {
                        Text(context.state.room)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.0, green: 0.44, blue: 0.95))
                            .cornerRadius(8)
                    }
                }

                // Next lesson preview
                if !context.state.nextLessonPreview.isEmpty {
                    Divider().background(Color.white.opacity(0.1))
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                        Text(context.state.nextLessonPreview)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .background(Color(red: 0.04, green: 0.08, blue: 0.16))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.groupTitle)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                        Text(context.state.statusBadge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if !context.state.room.isEmpty && context.state.room != "—" {
                            Text(context.state.room)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.0, green: 0.44, blue: 0.95))
                                .cornerRadius(5)
                        }
                        let targetDate = Date(timeIntervalSince1970: context.state.targetTimestamp)
                        if context.state.targetTimestamp > Date().timeIntervalSince1970 {
                            Text(targetDate, style: .timer)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                        }
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(context.state.disciplineTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if !context.state.lessonType.isEmpty {
                                Text(context.state.lessonType)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        if !context.state.nextLessonPreview.isEmpty {
                            Text(context.state.nextLessonPreview)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(context.state.isBreak ? Color.orange : Color(red: 0.0, green: 0.82, blue: 1.0))
                        .frame(width: 5, height: 5)
                    Text(context.state.room.isEmpty || context.state.room == "—" ? context.attributes.groupTitle : context.state.room)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                }
            } compactTrailing: {
                let targetDate = Date(timeIntervalSince1970: context.state.targetTimestamp)
                if context.state.targetTimestamp > Date().timeIntervalSince1970 {
                    Text(targetDate, style: .timer)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                } else {
                    Text(context.state.timeRange.components(separatedBy: " – ").last ?? "")
                        .font(.system(size: 11, weight: .semibold))
                }
            } minimal: {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
            }
        }
    }
}

// MARK: - Widget Bundle
@main
struct ScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        if #available(iOS 16.1, *) {
            ScheduleLiveActivity()
        }
    }
}
