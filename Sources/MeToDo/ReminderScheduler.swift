import AppKit
import UserNotifications
import MeToDoCore

/// Keeps macOS's pending notifications in sync with the store and handles the alert buttons (spec §8).
@MainActor @Observable
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    private(set) var remindersOff = false
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let ui: UIState
    @ObservationIgnored private var scheduled: [UUID: PlannedReminder] = [:]
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    private enum Action {
        static let category = "TASK_REMINDER"
        static let complete = "COMPLETE"
        static let snooze10 = "SNOOZE_10"
        static let snooze60 = "SNOOZE_60"
        static let tomorrow = "TOMORROW"
    }

    init(store: Store, ui: UIState) {
        self.store = store
        self.ui = ui
        super.init()
    }

    /// Call from applicationWillFinishLaunching so an action that launched the app is delivered.
    func install() {
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: Action.complete, title: "Complete"),
            UNNotificationAction(identifier: Action.snooze10, title: "Snooze 10 min"),
            UNNotificationAction(identifier: Action.snooze60, title: "Snooze 1 hr"),
            UNNotificationAction(identifier: Action.tomorrow, title: "Tomorrow 9 AM"),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Action.category, actions: actions, intentIdentifiers: []),
        ])
    }

    /// Ask permission, then self-heal: drop every pending request and rebuild from saved data.
    func start() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshAuthorization()
        center.removeAllPendingNotificationRequests()
        scheduled = [:]
        resync()
    }

    func refreshAuthorization() async {
        remindersOff = await center.notificationSettings().authorizationStatus == .denied
    }

    /// Cheap to call often: only changed requests are touched. Called on every store change and every minute.
    func resync() {
        let now = Date()
        let plan = Queries.reminderPlan(store.data, now: now)
        let diff = Queries.reminderDiff(scheduled: scheduled, plan: plan, now: now)
        if !diff.remove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: diff.remove.map(\.uuidString))
        }
        for r in diff.add { center.add(request(for: r)) }
        scheduled = Dictionary(plan.map { ($0.taskID, $0) }, uniquingKeysWith: { first, _ in first })
        clearDeliveredForClosedTasks()
    }

    private func request(for r: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = r.title
        content.subtitle = r.subtitle
        content.sound = .default
        content.categoryIdentifier = Action.category
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: r.date)
        return UNNotificationRequest(identifier: r.taskID.uuidString, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    /// A persistent alert for a task you've since completed or deleted shouldn't linger.
    private func clearDeliveredForClosedTasks() {
        let openIDs = Set(store.data.tasks.filter { !$0.isDone }.map(\.id.uuidString))
        center.getDeliveredNotifications { notes in
            let stale = notes.map(\.request.identifier).filter { !openIDs.contains($0) }
            if !stale.isEmpty { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: stale) }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let id = UUID(uuidString: response.notification.request.identifier)
        Task { @MainActor in
            self.handle(action: action, taskID: id)
            completionHandler()
        }
    }

    private func handle(action: String, taskID: UUID?) {
        guard let taskID, store.task(taskID) != nil else { return }
        switch action {
        case Action.complete: store.complete(taskID)
        case Action.snooze10: store.snooze(taskID, .tenMinutes)
        case Action.snooze60: store.snooze(taskID, .oneHour)
        case Action.tomorrow: store.snooze(taskID, .tomorrowMorning)
        case UNNotificationDefaultActionIdentifier: ui.showTask(taskID)
        default: break
        }
    }
}
