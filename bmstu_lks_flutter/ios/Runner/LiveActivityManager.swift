import ActivityKit
import Foundation

@available(iOS 16.1, *)
class LiveActivityManager {
    static let shared = LiveActivityManager()
    private let appGroupId = "group.ru.bmstu.neo"
    private let enabledKey = "live_notification_enabled"

    func isEnabled() -> Bool {
        return UserDefaults(suiteName: appGroupId)?.object(forKey: enabledKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults(suiteName: appGroupId)?.set(enabled, forKey: enabledKey)
        if !enabled {
            endAllActivities()
        }
    }

    func updateLiveActivity(scheduleJson: String, enabled: Bool) {
        guard enabled, isEnabled() else {
            endAllActivities()
            return
        }

        guard let data = scheduleJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            endAllActivities()
            return
        }

        let isTomorrow = json["isTomorrow"] as? Bool ?? false
        let lessons = json["lessons"] as? [[String: Any]] ?? []

        // If today has finished or no lessons today, end Live Activity
        if isTomorrow || lessons.isEmpty {
            endAllActivities()
            return
        }

        let groupTitle = json["groupTitle"] as? String ?? "МГТУ"
        let statusHeadline = json["statusHeadline"] as? String ?? "Занятия"
        let statusSubline = json["statusSubline"] as? String ?? ""

        var currentLessonTitle = "Занятия"
        var room = ""
        var teacher = ""
        var timeRange = ""

        if let firstLesson = lessons.first {
            currentLessonTitle = firstLesson["disciplineTitle"] as? String ?? "Занятие"
            room = firstLesson["room"] as? String ?? ""
            teacher = firstLesson["teacher"] as? String ?? ""
            timeRange = firstLesson["time"] as? String ?? ""
        }

        let contentState = ScheduleActivityAttributes.ContentState(
            statusHeadline: statusHeadline,
            statusSubline: statusSubline,
            currentLesson: currentLessonTitle,
            room: room,
            teacher: teacher,
            timeRange: timeRange,
            isFinished: false
        )

        // Check if an existing live activity is running
        if let currentActivity = Activity<ScheduleActivityAttributes>.activities.first {
            Task {
                await currentActivity.update(using: contentState)
            }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                print("[LiveActivityManager] Live Activities are not enabled in system settings")
                return
            }
            // Request a new Live Activity
            let attributes = ScheduleActivityAttributes(groupTitle: groupTitle)
            do {
                _ = try Activity<ScheduleActivityAttributes>.request(
                    attributes: attributes,
                    contentState: contentState,
                    pushType: nil
                )
            } catch {
                print("[LiveActivityManager] Error starting Live Activity: \(error)")
            }
        }
    }

    func endAllActivities() {
        Task {
            for activity in Activity<ScheduleActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}
