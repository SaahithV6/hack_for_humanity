import Foundation

/// Tracks how hard the next task should be.
///
/// The failure mode we are designing against is the one that makes to-do apps
/// useless for depressed people: the app asks for more than the person has,
/// they don't do it, and now they have evidence they are failing. So the
/// ladder is deliberately asymmetric -- it climbs slowly on success and drops
/// fast on a skip. Getting the difficulty wrong downward costs one easy task;
/// getting it wrong upward costs the user's belief that this works.
public struct Ladder: Codable, Sendable {
    /// Continuous difficulty, 1.0 ... 5.0. Quantised to an Int for the grammar.
    public private(set) var level: Double

    private let ascent: Double
    private let descent: Double
    private let floor: Double
    private let ceiling: Double

    public init(level: Double = 1.5, ascent: Double = 0.22, descent: Double = 0.55) {
        self.level = level
        self.ascent = ascent
        self.descent = descent
        self.floor = 1.0
        self.ceiling = 5.0
    }

    public var targetEffort: Int {
        Swift.min(Swift.max(Int(level.rounded()), 1), 5)
    }

    public mutating func record(completed: Bool) {
        if completed {
            level = Swift.min(level + ascent, ceiling)
        } else {
            level = Swift.max(level - descent, floor)
        }
    }

    /// A skipped task should not be punished as hard as an ignored one -- the
    /// user engaged, they just said no to this particular thing.
    public mutating func recordSkip() {
        level = Swift.max(level - descent * 0.5, floor)
    }

    /// Low energy caps how high we are willing to reach regardless of history.
    /// Somebody who has climbed to level 4 over a good week should still get a
    /// level-2 task on the evening they report running on empty.
    public func effort(under ctx: Context) -> Int {
        let energyCap: Double
        switch ctx.energy {
        case 1: energyCap = 1.6
        case 2: energyCap = 2.6
        case 3: energyCap = 3.6
        case 4: energyCap = 4.4
        default: energyCap = 5.0
        }
        // In the last stretch before bed, nothing ambitious.
        let bedtimeCap = ctx.isWindDownWindow ? 2.2 : 5.0
        // A rescue is an emergency exit from a scroll: it has to be something
        // the user can start in the next ten seconds, or they won't.
        let rescueCap = ctx.isDoomscrollRescue ? 2.0 : 5.0
        let capped = Swift.min(level, energyCap, bedtimeCap, rescueCap)
        return Swift.min(Swift.max(Int(capped.rounded()), 1), 5)
    }
}
