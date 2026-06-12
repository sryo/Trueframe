// Lunar phase from pure arithmetic. No network, no location.

import Foundation

extension Date {
    private static let synodicMonth = 29.53059
    /// 2000-01-06 18:14 UTC, a new moon.
    private static let referenceNewMoon: TimeInterval = 947_182_440

    /// Days since the last new moon (0 = new, ~14.77 = full).
    var lunarAgeDays: Double {
        let days = (timeIntervalSince1970 - Self.referenceNewMoon) / 86_400
        let age = days.truncatingRemainder(dividingBy: Self.synodicMonth)
        return age < 0 ? age + Self.synodicMonth : age
    }

    /// True within half a day of the mean full moon.
    var isNearFullMoon: Bool {
        abs(lunarAgeDays - Self.synodicMonth / 2) < 0.5
    }
}
