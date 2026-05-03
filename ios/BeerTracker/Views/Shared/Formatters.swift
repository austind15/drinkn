import Foundation

enum Format {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static let dayOfWeek: [String] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func dayOfWeekName(_ index: Int) -> String {
        guard index >= 0 && index < dayOfWeek.count else { return "—" }
        return dayOfWeek[index]
    }

    static func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        if normalized == 0 { return "12am" }
        if normalized == 12 { return "12pm" }
        if normalized < 12 { return "\(normalized)am" }
        return "\(normalized - 12)pm"
    }

    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
