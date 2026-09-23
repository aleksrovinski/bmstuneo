import ActivityKit
import Foundation

@available(iOS 16.1, *)
public struct ScheduleActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var statusHeadline: String
        public var statusSubline: String
        public var currentLesson: String
        public var room: String
        public var teacher: String
        public var timeRange: String
        public var isFinished: Bool

        public init(
            statusHeadline: String,
            statusSubline: String,
            currentLesson: String,
            room: String,
            teacher: String,
            timeRange: String,
            isFinished: Bool = false
        ) {
            self.statusHeadline = statusHeadline
            self.statusSubline = statusSubline
            self.currentLesson = currentLesson
            self.room = room
            self.teacher = teacher
            self.timeRange = timeRange
            self.isFinished = isFinished
        }
    }

    public var groupTitle: String

    public init(groupTitle: String) {
        self.groupTitle = groupTitle
    }
}
