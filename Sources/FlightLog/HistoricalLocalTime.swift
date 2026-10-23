import Foundation

enum LocalWallClockOccurrence: String, Codable, CaseIterable, Sendable {
    case first
    case second

    var title: String {
        switch self {
        case .first:
            "第一次"
        case .second:
            "第二次"
        }
    }
}

struct LocalWallClockCandidate: Equatable, Sendable {
    let occurrence: LocalWallClockOccurrence
    let absoluteDate: Date
    let utcOffsetSeconds: Int
}

struct LocalWallClockResolution: Equatable, Sendable {
    let localDateTime: String
    let candidates: [LocalWallClockCandidate]

    var isAmbiguous: Bool {
        candidates.count == 2
    }

    func candidate(
        for occurrence: LocalWallClockOccurrence
    ) -> LocalWallClockCandidate {
        guard candidates.count > 1 else {
            return candidates[0]
        }
        return occurrence == .second ? candidates[1] : candidates[0]
    }
}

enum LocalWallClockResolver {
    static func resolve(
        _ wallClockDate: Date,
        timeZoneID: String
    ) throws -> LocalWallClockResolution {
        guard let timeZone = TimeZone(identifier: timeZoneID) else {
            throw LocalDateTimeConversionError.invalidTimeZone
        }

        let components = utcCalendar.dateComponents(
            componentSet,
            from: wallClockDate
        )
        guard let referenceDate = utcCalendar.date(from: components) else {
            throw LocalDateTimeConversionError.nonexistentLocalTime
        }
        let calendar = localCalendar(timeZone: timeZone)
        let nearbyOffsets = Set(
            stride(
                from: -259_200.0,
                through: 259_200.0,
                by: 21_600.0
            ).map {
                timeZone.secondsFromGMT(
                    for: referenceDate.addingTimeInterval($0)
                )
            }
        )
        let dates = nearbyOffsets
            .map {
                referenceDate.addingTimeInterval(-Double($0))
            }
            .filter {
                timeZone.secondsFromGMT(for: $0)
                    == Int(referenceDate.timeIntervalSince($0))
            }
            .filter {
                matches(
                    components,
                    calendar.dateComponents(componentSet, from: $0)
                )
            }
            .reduce(into: [Date]()) { unique, date in
                if !unique.contains(date) {
                    unique.append(date)
                }
            }
            .sorted()
        guard !dates.isEmpty else {
            throw LocalDateTimeConversionError.nonexistentLocalTime
        }

        let candidates = dates.enumerated().map { index, date in
            LocalWallClockCandidate(
                occurrence: index == 0 ? .first : .second,
                absoluteDate: date,
                utcOffsetSeconds: timeZone.secondsFromGMT(for: date)
            )
        }
        return LocalWallClockResolution(
            localDateTime: stableString(from: wallClockDate),
            candidates: candidates
        )
    }

    static func stableString(from wallClockDate: Date) -> String {
        let components = utcCalendar.dateComponents(
            componentSet,
            from: wallClockDate
        )
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    static func wallClockDate(from stableString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.isLenient = false
        guard
            let date = formatter.date(from: stableString),
            formatter.string(from: date) == stableString
        else {
            return nil
        }
        return date
    }

    static func wallClockDate(
        from absoluteDate: Date,
        timeZoneID: String
    ) throws -> Date {
        guard let timeZone = TimeZone(identifier: timeZoneID) else {
            throw LocalDateTimeConversionError.invalidTimeZone
        }
        let components = localCalendar(timeZone: timeZone).dateComponents(
            componentSet,
            from: absoluteDate
        )
        guard let wallClockDate = utcCalendar.date(from: components) else {
            throw LocalDateTimeConversionError.nonexistentLocalTime
        }
        return wallClockDate
    }

    private static let componentSet: Set<Calendar.Component> = [
        .year,
        .month,
        .day,
        .hour,
        .minute,
        .second,
    ]

    private static var utcCalendar: Calendar {
        localCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    private static func localCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    private static func matches(
        _ lhs: DateComponents,
        _ rhs: DateComponents
    ) -> Bool {
        lhs.year == rhs.year
            && lhs.month == rhs.month
            && lhs.day == rhs.day
            && lhs.hour == rhs.hour
            && lhs.minute == rhs.minute
            && lhs.second == rhs.second
    }
}

enum HistoricalLocalTime {
    static func localDateTime(
        snapshot: String?,
        absoluteDate: Date,
        timeZoneID: String
    ) -> String {
        if
            let snapshot,
            LocalWallClockResolver.wallClockDate(from: snapshot) != nil
        {
            return snapshot
        }
        guard
            let wallClockDate = try? LocalWallClockResolver.wallClockDate(
                from: absoluteDate,
                timeZoneID: timeZoneID
            )
        else {
            return LocalWallClockResolver.stableString(from: absoluteDate)
        }
        return LocalWallClockResolver.stableString(from: wallClockDate)
    }

    static func wallClockDate(
        snapshot: String?,
        absoluteDate: Date,
        timeZoneID: String
    ) -> Date {
        if
            let snapshot,
            let date = LocalWallClockResolver.wallClockDate(from: snapshot)
        {
            return date
        }
        return (
            try? LocalWallClockResolver.wallClockDate(
                from: absoluteDate,
                timeZoneID: timeZoneID
            )
        ) ?? absoluteDate
    }

    static func csvText(
        snapshot: String?,
        absoluteDate: Date,
        timeZoneID: String
    ) -> String {
        let stable = localDateTime(
            snapshot: snapshot,
            absoluteDate: absoluteDate,
            timeZoneID: timeZoneID
        )
        guard let date = LocalWallClockResolver.wallClockDate(from: stable) else {
            return stable
        }
        return formatter(
            format: "yyyy-MM-dd HH:mm",
            locale: Locale(identifier: "en_US_POSIX")
        ).string(from: date)
    }

    static func displayText(
        snapshot: String?,
        absoluteDate: Date,
        timeZoneID: String,
        utcOffsetSeconds: Int?
    ) -> String {
        let stable = localDateTime(
            snapshot: snapshot,
            absoluteDate: absoluteDate,
            timeZoneID: timeZoneID
        )
        guard let date = LocalWallClockResolver.wallClockDate(from: stable) else {
            return stable
        }
        let localText = formatter(
            format: "yyyy年M月d日 HH:mm",
            locale: Locale(identifier: "zh_CN")
        ).string(from: date)
        let offset = utcOffsetSeconds
            ?? TimeZone(identifier: timeZoneID)?.secondsFromGMT(for: absoluteDate)
        guard let offset else {
            return localText
        }
        return "\(localText)（\(offsetText(offset))）"
    }

    private static func formatter(
        format: String,
        locale: Locale
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    private static func offsetText(_ seconds: Int) -> String {
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        let hours = absolute / 3_600
        let minutes = absolute % 3_600 / 60
        let remainingSeconds = absolute % 60
        if remainingSeconds == 0 {
            return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
        }
        return String(
            format: "UTC%@%02d:%02d:%02d",
            sign,
            hours,
            minutes,
            remainingSeconds
        )
    }
}
