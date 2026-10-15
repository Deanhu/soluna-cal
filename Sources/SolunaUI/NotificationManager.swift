import Foundation
import UserNotifications

/// 通知调度：读取偏好 → NotificationPlanner 出计划 → 全量重排（幂等）
public enum NotificationManager {
    /// 偏好读写（UserDefaults 键集中在这里）
    public static var prefs: NotifyPrefs {
        get {
            let ud = UserDefaults.standard
            var p = NotifyPrefs()
            p.holidayEve = ud.bool(forKey: "notify.holidayEve")
            p.festival = ud.bool(forKey: "notify.festival")
            p.birthday = ud.bool(forKey: "notify.birthday")
            p.dndEnabled = ud.bool(forKey: "notify.dndEnabled")
            if ud.object(forKey: "notify.dndStart") != nil { p.dndStartMin = ud.integer(forKey: "notify.dndStart") }
            if ud.object(forKey: "notify.dndEnd") != nil { p.dndEndMin = ud.integer(forKey: "notify.dndEnd") }
            return p
        }
    }

    /// 全量重排未来 60 天通知。无任何开关开启时清空并跳过授权请求。
    public static func reschedule(store: BirthdayStore, now: Date = Date()) {
        let plans = NotificationPlanner.plan(now: now, prefs: prefs, store: store)
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard !plans.isEmpty else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for p in plans {
                let c = Calendar(identifier: .gregorian)
                let comps = c.dateComponents([.year, .month, .day, .hour, .minute], from: p.fireDate)
                let content = UNMutableNotificationContent()
                content.title = p.title
                content.body = p.body
                content.sound = .default
                let req = UNNotificationRequest(
                    identifier: p.id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                center.add(req)
            }
        }
    }
}
