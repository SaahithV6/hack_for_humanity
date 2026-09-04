import Foundation

/// One day's record. The unit the summary is written from and the unit the
/// streak counts.
public struct DayRecord: Codable, Identifiable, Sendable {
    /// Days since the reference date, so a day is comparable and Codable
    /// without dragging a Calendar into the model layer.
    public var id: Int
    public var tasks: [MothTask]
    /// Mood check-ins through the day, in order.
    public var moodChecks: [Int]
    /// How many times the user hit the rescue button.
    public var rescues: Int
    /// Whether the wind-down ritual was completed.
    public var windDownCompleted: Bool

    public init(id: Int, tasks: [MothTask] = [], moodChecks: [Int] = [],
                rescues: Int = 0, windDownCompleted: Bool = false) {
        self.id = id
        self.tasks = tasks
        self.moodChecks = moodChecks
        self.rescues = rescues
        self.windDownCompleted = windDownCompleted
    }

    public var completed: [MothTask] { tasks.filter { $0.outcome == .done } }
    public var completedCount: Int { completed.count }
    public var offeredCount: Int { tasks.count }
    public var minutesInvested: Int { completed.reduce(0) { $0 + $1.estimatedMinutes } }
    public var selfWritten: [MothTask] { completed.filter { $0.origin == .user } }

    public var completionRate: Double {
        let resolved = tasks.filter { $0.outcome != .pending }
        guard !resolved.isEmpty else { return 0 }
        return Double(completed.count) / Double(resolved.count)
    }
}

/// Rolling history. Bounded on purpose -- we keep eight weeks, which is enough
/// for the bandit to be well-calibrated and short enough that the whole store
/// stays a small JSON file that can be deleted in one tap.
public struct Journal: Codable, Sendable {
    public private(set) var days: [Int: DayRecord] = [:]
    private let retentionDays = 56

    public init() {}

    public static func dayIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        return Int(start.timeIntervalSince1970 / 86_400)
    }

    public func record(for day: Int) -> DayRecord {
        days[day] ?? DayRecord(id: day)
    }

    public mutating func update(_ record: DayRecord) {
        days[record.id] = record
        prune(newest: record.id)
    }

    private mutating func prune(newest: Int) {
        let cutoff = newest - retentionDays
        days = days.filter { $0.key > cutoff }
    }

    /// Consecutive days ending today (or yesterday, if today is not done yet)
    /// with at least one completed task.
    ///
    /// The "or yesterday" clause is the forgiving part: a streak that breaks
    /// the moment the clock passes midnight punishes exactly the person who
    /// went to bed on time, which is the behaviour we are trying to cause.
    public func streak(endingAt today: Int) -> Int {
        var count = 0
        var cursor = today
        if (days[today]?.completedCount ?? 0) == 0 {
            cursor = today - 1
        }
        while (days[cursor]?.completedCount ?? 0) > 0 {
            count += 1
            cursor -= 1
        }
        return count
    }

    /// Completion rate over the trailing window. Feeds the context vector.
    public func recentCompletionRate(endingAt today: Int, window: Int = 7) -> Double {
        var done = 0
        var resolved = 0
        for day in (today - window + 1)...today {
            guard let record = days[day] else { continue }
            done += record.completed.count
            resolved += record.tasks.filter { $0.outcome != .pending }.count
        }
        guard resolved > 0 else { return 0.5 }
        return Double(done) / Double(resolved)
    }

    /// Total completed tasks ever. Drives the "groove" threshold at which the
    /// app starts inviting the user to write their own.
    public var lifetimeCompleted: Int {
        days.values.reduce(0) { $0 + $1.completedCount }
    }

    public var lifetimeSelfWritten: Int {
        days.values.reduce(0) { $0 + $1.selfWritten.count }
    }
}
