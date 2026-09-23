import WidgetKit
import SwiftUI

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
}

// MARK: - Timeline Provider
struct Provider: TimelineProvider {
    private let appGroupId = "group.ru.bmstu.neo"
    private let scheduleKey = "schedule_data"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), schedule: getSampleSchedule())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), schedule: loadSchedule() ?? getSampleSchedule())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let currentSchedule = loadSchedule()
        let currentDate = Date()
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        let entry = SimpleEntry(date: currentDate, schedule: currentSchedule)
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
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
struct ScheduleWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.08, blue: 0.16) // Deep Navy Brand Dark
                .ignoresSafeArea()

            if let sched = entry.schedule {
                switch family {
                case .systemSmall:
                    SmallWidgetView(sched: sched)
                case .systemMedium:
                    MediumWidgetView(sched: sched)
                case .systemLarge:
                    LargeWidgetView(sched: sched)
                default:
                    MediumWidgetView(sched: sched)
                }
            } else {
                EmptyStateView()
            }
        }
    }
}

// MARK: - Small Widget (1x1)
struct SmallWidgetView: View {
    let sched: SchedulePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(sched.groupTitle ?? "МГТУ")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                Spacer()
                Text(sched.weekParity ?? "")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }

            if let headline = sched.statusHeadline, !headline.isEmpty {
                Text(headline)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }

            Divider().background(Color.white.opacity(0.15))

            if let firstLesson = sched.lessons?.first {
                VStack(alignment: .leading, spacing: 3) {
                    Text(firstLesson.disciplineTitle ?? "")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        Text(firstLesson.time ?? "")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                        Spacer()
                        if let room = firstLesson.room, !room.isEmpty {
                            Text(room)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(4)
                                .foregroundColor(.white)
                        }
                    }
                }
            } else {
                Text("Занятий нет")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(12)
    }
}

// MARK: - Medium Widget (2x1)
struct MediumWidgetView: View {
    let sched: SchedulePayload

    var body: some View {
        HStack(spacing: 12) {
            // Left Column: Group & Status
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.82, blue: 1.0))
                        .frame(width: 8, height: 8)
                    Text(sched.groupTitle ?? "МГТУ")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                }

                Text(sched.dayTitle ?? "Сегодня")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                if let headline = sched.statusHeadline {
                    Text(headline)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                if let subline = sched.statusSubline, !subline.isEmpty {
                    Text(subline)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()
                Text(sched.weekParity ?? "")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: 130)

            Divider().background(Color.white.opacity(0.15))

            // Right Column: Upcoming Lessons
            VStack(alignment: .leading, spacing: 6) {
                if let lessons = sched.lessons, !lessons.isEmpty {
                    ForEach(lessons.prefix(2)) { lesson in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(lesson.time ?? "")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                                Spacer()
                                if let room = lesson.room, !room.isEmpty {
                                    Text(room)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(4)
                                        .foregroundColor(.white)
                                }
                            }
                            Text(lesson.disciplineTitle ?? "")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        if lesson.id != lessons.prefix(2).last?.id {
                            Divider().background(Color.white.opacity(0.1))
                        }
                    }
                } else {
                    Spacer()
                    Text("На этот день пар нет")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Large Widget (2x2)
struct LargeWidgetView: View {
    let sched: SchedulePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sched.groupTitle ?? "МГТУ")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                        Text("•  \(sched.weekParity ?? "")")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Text(sched.dayTitle ?? "Сегодня")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                if let headline = sched.statusHeadline {
                    Text(headline)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.0, green: 0.44, blue: 0.95).opacity(0.3))
                        .cornerRadius(6)
                }
            }

            Divider().background(Color.white.opacity(0.2))

            // Schedule List
            if let lessons = sched.lessons, !lessons.isEmpty {
                VStack(spacing: 8) {
                    ForEach(lessons.prefix(5)) { lesson in
                        HStack(alignment: .center, spacing: 8) {
                            Text(lesson.time ?? "")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 0.0, green: 0.82, blue: 1.0))
                                .frame(width: 80, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.disciplineTitle ?? "")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                if let teacher = lesson.teacher, !teacher.isEmpty {
                                    Text(teacher)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(.white.opacity(0.5))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if let room = lesson.room, !room.isEmpty {
                                Text(room)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(4)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
            } else {
                Spacer()
                CenterTextView(text: "Занятий на выбранный день нет")
                Spacer()
            }
            Spacer()
        }
        .padding(16)
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
@main
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
