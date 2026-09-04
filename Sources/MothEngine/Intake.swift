import Foundation

/// The onboarding questionnaire.
///
/// Six questions, hard cap. Every extra question is a place somebody closes
/// the app, and the population we are building for has the least patience for
/// forms. Everything else the engine needs, it learns by watching.
public struct Intake: Codable, Equatable, Sendable {

    // MARK: PHQ-2 style screen (frequency over the last two weeks, 0...3)
    /// "Little interest or pleasure in doing things."
    public var lowInterestDays: Int
    /// "Feeling down, hopeless."
    public var lowMoodDays: Int
    /// Asked plainly, with the resources one tap away regardless of answer.
    public var hasSelfHarmThoughts: Bool

    // MARK: Calibration
    /// Typical mood, 1...5. Sets the ladder's starting rung.
    public var baselineMood: Int
    /// Domains the user says matter to them. Seeds the bandit's bias, not its
    /// posteriors -- what people say they want and what they actually do
    /// diverge, so this is a starting hint the engine is free to override.
    public var caresAbout: Set<Archetype>
    /// Minutes past midnight. The whole app points at this moment.
    public var bedtimeMinutes: Int
    /// When the scroll usually starts, so we can offer the rescue before it.
    public var scrollStartMinutes: Int

    public init(
        lowInterestDays: Int = 0,
        lowMoodDays: Int = 0,
        hasSelfHarmThoughts: Bool = false,
        baselineMood: Int = 3,
        caresAbout: Set<Archetype> = [],
        bedtimeMinutes: Int = 23 * 60,
        scrollStartMinutes: Int = 22 * 60
    ) {
        self.lowInterestDays = lowInterestDays
        self.lowMoodDays = lowMoodDays
        self.hasSelfHarmThoughts = hasSelfHarmThoughts
        self.baselineMood = Swift.min(Swift.max(baselineMood, 1), 5)
        self.caresAbout = caresAbout
        self.bedtimeMinutes = bedtimeMinutes
        self.scrollStartMinutes = scrollStartMinutes
    }

    /// Where the ladder starts. Somebody reporting a flat two weeks should be
    /// met with a one-minute task, not a fifteen-minute one.
    public var startingLadderLevel: Double {
        let severity = Double(lowInterestDays + lowMoodDays)  // 0...6
        let base = 1.0 + Double(baselineMood - 1) * 0.45      // 1.0 ... 2.8
        return Swift.max(1.0, base - severity * 0.2)
    }
}
