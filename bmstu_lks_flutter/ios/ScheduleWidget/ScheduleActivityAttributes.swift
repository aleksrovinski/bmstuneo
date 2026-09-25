import ActivityKit
import Foundation

@available(iOS 16.1, *)
public struct ScheduleActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var statusBadge: String         // e.g. "Идёт 2-я пара" / "Перемена" / "Скоро начало"
        public var disciplineTitle: String     // e.g. "Базы данных"
        public var lessonType: String          // e.g. "Лекция"
        public var room: String                // e.g. "502л"
        public var teacher: String             // e.g. "Иванов И.И."
        public var timeRange: String           // e.g. "10:15 – 11:50"
        public var nextLessonPreview: String   // e.g. "Далее: 3-я пара • ОС (395ю)"
        public var targetTimestamp: Double     // Unix timestamp for live countdown
        public var isBreak: Bool
        public var isFinished: Bool

        public init(
            statusBadge: String,
            disciplineTitle: String,
            lessonType: String,
            room: String,
            teacher: String,
            timeRange: String,
            nextLessonPreview: String,
            targetTimestamp: Double,
            isBreak: Bool = false,
            isFinished: Bool = false
        ) {
            self.statusBadge = statusBadge
            self.disciplineTitle = disciplineTitle
            self.lessonType = lessonType
            self.room = room
            self.teacher = teacher
            self.timeRange = timeRange
            self.nextLessonPreview = nextLessonPreview
            self.targetTimestamp = targetTimestamp
            self.isBreak = isBreak
            self.isFinished = isFinished
        }
    }

    public var groupTitle: String

    public init(groupTitle: String) {
        self.groupTitle = groupTitle
    }
}
