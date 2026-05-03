import Foundation
import Combine

/// Tracks how many drinks the user has logged today (UTC day boundary)
/// to power the in-app safety reminders. Stored locally — this is a
/// nudge, not a server-enforced rule, so each device tracks its own count.
@MainActor
final class DrinkLimitStore: ObservableObject {
    static let shared = DrinkLimitStore()

    private let countKey = "drinkLimit.count"
    private let dayKey = "drinkLimit.day"

    static let softReminderThreshold = 5
    static let strongWarningThreshold = 8
    static let hardLimitThreshold = 15

    enum WarningLevel {
        case none
        case softReminder
        case strongWarning
        case hardLimit
    }

    private init() {}

    private var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }

    private func currentCount() -> Int {
        let stored = UserDefaults.standard.string(forKey: dayKey)
        if stored != todayKey {
            UserDefaults.standard.set(todayKey, forKey: dayKey)
            UserDefaults.standard.set(0, forKey: countKey)
            return 0
        }
        return UserDefaults.standard.integer(forKey: countKey)
    }

    /// The count *if* the user logs one more drink right now.
    var nextCount: Int { currentCount() + 1 }

    /// Whether the user has hit the hard cap and should be blocked.
    var isAtHardLimit: Bool { currentCount() >= Self.hardLimitThreshold }

    /// Returns the warning level the UI should show *before* a submission
    /// at the proposed next count. The UI calls this, shows the matching
    /// dialog, and if the user proceeds, calls `recordSubmission()`.
    func warningLevelForNextDrink() -> WarningLevel {
        let next = nextCount
        if next > Self.hardLimitThreshold { return .hardLimit }
        if next >= Self.strongWarningThreshold { return .strongWarning }
        if next >= Self.softReminderThreshold { return .softReminder }
        return .none
    }

    func recordSubmission() {
        let next = currentCount() + 1
        UserDefaults.standard.set(next, forKey: countKey)
        UserDefaults.standard.set(todayKey, forKey: dayKey)
    }
}
