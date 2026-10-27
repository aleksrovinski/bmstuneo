import ActivityKit
import Foundation

@available(iOS 16.1, *)
class LiveActivityManager {
    static let shared = LiveActivityManager()
    private let appGroupId = "group.ru.bmstu.neo"
    private let enabledKey = "live_notification_enabled"

    private struct LessonItem {
        let pairNumber: Int
        let startTime: String
        let endTime: String
        let startMin: Int
        let endMin: Int
        let title: String
        let type: String
        let room: String
        let teacher: String
    }

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
        let lessonsRaw = json["lessons"] as? [[String: Any]] ?? []

        // If today has finished or no lessons today, end Live Activity
        if isTomorrow || lessonsRaw.isEmpty {
            endAllActivities()
            return
        }

        let groupTitle = json["groupTitle"] as? String ?? "МГТУ"

        // Parse lesson items
        var lessonList: [LessonItem] = []
        for (index, dict) in lessonsRaw.enumerated() {
            let startTime = (dict["startTime"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let endTime = (dict["endTime"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard let sMin = parseMinutes(startTime), let eMin = parseMinutes(endTime) else { continue }

            let pairNum = dict["pairNumber"] as? Int ?? (index + 1)
            let title = dict["disciplineTitle"] as? String ?? "Занятие"
            let type = dict["type"] as? String ?? (dict["actTypeTitle"] as? String ?? "")
            let room = dict["room"] as? String ?? (dict["audiencesFormatted"] as? String ?? "")
            let teacher = dict["teacher"] as? String ?? (dict["teachersFormatted"] as? String ?? "")

            lessonList.append(
                LessonItem(
                    pairNumber: pairNum > 0 ? pairNum : (index + 1),
                    startTime: startTime,
                    endTime: endTime,
                    startMin: sMin,
                    endMin: eMin,
                    title: title,
                    type: type,
                    room: room,
                    teacher: teacher == "Кафедра" ? "" : teacher
                )
            )
        }

        if lessonList.isEmpty {
            endAllActivities()
            return
        }

        lessonList.sort { $0.startMin < $1.startMin }

        let now = Date()
        let cal = Calendar.current
        let currentMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        guard let firstLesson = lessonList.first, let lastLesson = lessonList.last else {
            endAllActivities()
            return
        }

        // If all lessons for today have finished, dismiss Live Activity
        if currentMinutes > lastLesson.endMin {
            endAllActivities()
            return
        }

        var currentLesson: LessonItem? = nil
        var nextLesson: LessonItem? = nil

        for l in lessonList {
            if currentMinutes >= l.startMin && currentMinutes <= l.endMin {
                currentLesson = l
            } else if currentMinutes < l.startMin && nextLesson == nil {
                nextLesson = l
            }
        }

        let contentState: ScheduleActivityAttributes.ContentState

        if let active = currentLesson {
            let targetDt = dateFromMinutes(active.endMin, baseDate: now)
            let nextPreview: String
            if let next = nextLesson {
                let roomPart = next.room.isEmpty ? "" : ", ауд. \(next.room)"
                nextPreview = "Далее: \(next.pairNumber) пара • \(next.title)\(roomPart)"
            } else {
                nextPreview = "Последняя пара на сегодня 🎉"
            }

            contentState = ScheduleActivityAttributes.ContentState(
                statusBadge: "Идёт \(active.pairNumber) пара",
                disciplineTitle: active.title,
                lessonType: active.type,
                room: active.room,
                teacher: active.teacher,
                timeRange: "\(active.startTime) – \(active.endTime)",
                nextLessonPreview: nextPreview,
                targetTimestamp: targetDt.timeIntervalSince1970,
                isBreak: false,
                isFinished: false
            )
        } else if let upcoming = nextLesson {
            let isBreak = currentMinutes >= firstLesson.startMin
            let targetDt = dateFromMinutes(upcoming.startMin, baseDate: now)
            let badge = isBreak ? "Перемена" : "Скоро начало"
            let preview = "Всего \(lessonList.count) пар на сегодня"

            contentState = ScheduleActivityAttributes.ContentState(
                statusBadge: badge,
                disciplineTitle: upcoming.title,
                lessonType: upcoming.type,
                room: upcoming.room,
                teacher: upcoming.teacher,
                timeRange: "\(upcoming.startTime) – \(upcoming.endTime)",
                nextLessonPreview: preview,
                targetTimestamp: targetDt.timeIntervalSince1970,
                isBreak: isBreak,
                isFinished: false
            )
        } else {
            endAllActivities()
            return
        }

        // Update or request activity
        if let currentActivity = Activity<ScheduleActivityAttributes>.activities.first {
            Task {
                await currentActivity.update(using: contentState)
            }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                print("[LiveActivityManager] Live Activities are not enabled in system settings")
                return
            }
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

    private func parseMinutes(_ timeStr: String) -> Int? {
        let parts = timeStr.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    private func dateFromMinutes(_ minutes: Int, baseDate: Date = Date()) -> Date {
        let cal = Calendar.current
        var comp = cal.dateComponents([.year, .month, .day], from: baseDate)
        comp.hour = minutes / 60
        comp.minute = minutes % 60
        comp.second = 0
        return cal.date(from: comp) ?? baseDate
    }
}
