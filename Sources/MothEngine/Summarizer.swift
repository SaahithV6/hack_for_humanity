import Foundation

/// What Moth says at bedtime.
///
/// This is the payload the whole app exists to deliver. The bet is that the
/// reason people scroll until 2am is that going to bed means sitting with an
/// unnarrated day, and an unnarrated day defaults to "I did nothing." So Moth
/// narrates it: specifically, in the user's own terms, using things that
/// actually happened.
///
/// Design rules, learned the hard way from how this copy reads out loud:
///   - Quote the user's actual tasks. Generic praise reads as a machine.
///   - Never inflate. If they did one thing, say one thing; a two-minute task
///     described as "crushing it" makes the whole app untrustworthy.
///   - A zero day is not a failure state and must never be written as one.
public struct Summary: Sendable, Equatable {
    public let greeting: String
    /// Two to four sentences, the main body.
    public let body: String
    /// Verbatim task texts to show as a list.
    public let highlights: [String]
    public let completedCount: Int
    public let minutes: Int
    public let streak: Int
    /// The last line, shown just above the "goodnight" button.
    public let closing: String

    public init(greeting: String, body: String, highlights: [String],
                completedCount: Int, minutes: Int, streak: Int, closing: String) {
        self.greeting = greeting
        self.body = body
        self.highlights = highlights
        self.completedCount = completedCount
        self.minutes = minutes
        self.streak = streak
        self.closing = closing
    }
}

public enum Summarizer {

    public static func summarize(
        day: DayRecord,
        streak: Int,
        bandit: ArchetypeBandit,
        bucket: String,
        rng: inout SeededRNG
    ) -> Summary {
        let done = day.completed
        guard !done.isEmpty else {
            return zeroDay(day: day, streak: streak, rng: &rng)
        }

        let highlights = pickHighlights(from: done, bandit: bandit, bucket: bucket)
        let minutes = day.minutesInvested

        let greeting = pick([
            "Here's your day.",
            "Before you go under.",
            "Let's close this out.",
            "Day's done. Here's what was in it.",
        ], &rng)

        var sentences: [String] = []

        // Lead with the count, stated plainly.
        sentences.append(countSentence(done.count, minutes: minutes, rng: &rng))

        // Name the thing that took the most out of them.
        if let hardest = done.max(by: { $0.effort < $1.effort }), hardest.effort >= 3 {
            sentences.append(pick([
                "\(quoted(hardest.text)) was the one with weight in it.",
                "The real one was \(quoted(hardest.text)).",
                "\(quoted(hardest.text)) took something, and you did it anyway.",
            ], &rng))
        }

        // Call out a domain they usually avoid. This is the observation the
        // user could not have made about themselves, and it is the moment the
        // summary stops sounding like a template.
        if let surprise = surprising(done, bandit: bandit, bucket: bucket) {
            sentences.append(pick([
                "\(surprise.archetype.displayName.lowercased()) is usually the one you skip. Not tonight.",
                "You don't normally go for \(surprise.archetype.displayName.lowercased()). You did today.",
            ], &rng))
        }

        // Their own tasks are the milestone the whole design is aimed at.
        let own = day.selfWritten
        if !own.isEmpty {
            sentences.append(own.count == 1
                ? "One of those you wrote yourself."
                : "\(own.count) of those you wrote yourself.")
        }

        if streak >= 2 {
            sentences.append(streakSentence(streak, rng: &rng))
        }

        let closing = pick([
            "That's enough. Put it down.",
            "Nothing left to do tonight.",
            "The rest of it can be tomorrow's.",
            "You're done. Go to sleep.",
        ], &rng)

        return Summary(
            greeting: greeting,
            body: sentences.joined(separator: " "),
            highlights: highlights.map(\.text),
            completedCount: done.count,
            minutes: minutes,
            streak: streak,
            closing: closing
        )
    }

    // MARK: - Zero days

    /// A day with nothing completed still gets a summary, because the
    /// alternative -- silence, or a red zero -- is precisely the input that
    /// starts the next doomscroll.
    private static func zeroDay(day: DayRecord, streak: Int, rng: inout SeededRNG) -> Summary {
        var sentences: [String] = []

        if day.rescues > 0 {
            sentences.append(day.rescues == 1
                ? "You opened Moth once today to get out of a scroll. That was the hard part."
                : "You reached for this \(day.rescues) times today instead of the feed.")
        } else {
            sentences.append(pick([
                "Nothing got done today, and that's a real thing that happens.",
                "Today didn't have much in it. Some don't.",
            ], &rng))
        }

        sentences.append(pick([
            "Tomorrow starts at one small thing, same as always.",
            "The list resets overnight. It always does.",
            "You don't owe today anything.",
        ], &rng))

        return Summary(
            greeting: pick(["Before you go under.", "Let's close this out."], &rng),
            body: sentences.joined(separator: " "),
            highlights: [],
            completedCount: 0,
            minutes: 0,
            streak: streak,
            closing: "Go to sleep. That counts too."
        )
    }

    // MARK: - Selection

    /// At most three, weighted toward effort, with domain variety so the list
    /// does not read as three versions of the same act.
    private static func pickHighlights(
        from done: [MothTask],
        bandit: ArchetypeBandit,
        bucket: String
    ) -> [MothTask] {
        let ranked = done.sorted { lhs, rhs in
            let lScore = Double(lhs.effort) + (lhs.origin == .user ? 1.5 : 0)
                + (1.0 - bandit.estimate(lhs.archetype, bucket: bucket))
            let rScore = Double(rhs.effort) + (rhs.origin == .user ? 1.5 : 0)
                + (1.0 - bandit.estimate(rhs.archetype, bucket: bucket))
            return lScore > rScore
        }

        var chosen: [MothTask] = []
        var seen: Set<Archetype> = []
        for task in ranked where !seen.contains(task.archetype) {
            chosen.append(task)
            seen.insert(task.archetype)
            if chosen.count == 3 { break }
        }
        // Backfill if they did three things in one domain.
        if chosen.count < 3 {
            for task in ranked where !chosen.contains(where: { $0.id == task.id }) {
                chosen.append(task)
                if chosen.count == 3 { break }
            }
        }
        return chosen
    }

    /// A completed task in a domain this user's posterior says they usually
    /// decline. Requires real evidence, otherwise every domain looks
    /// surprising on day one.
    private static func surprising(
        _ done: [MothTask],
        bandit: ArchetypeBandit,
        bucket: String
    ) -> MothTask? {
        done.first { task in
            bandit.confidence(task.archetype, bucket: bucket) >= 4
                && bandit.estimate(task.archetype, bucket: bucket) < 0.35
        }
    }

    // MARK: - Phrasing

    private static func countSentence(_ count: Int, minutes: Int, rng: inout SeededRNG) -> String {
        switch count {
        case 1:
            return pick([
                "One thing, done.",
                "You did one thing today. It's on the board.",
            ], &rng)
        case 2...3:
            return "\(count) things, about \(minutes) minutes total."
        default:
            return pick([
                "\(count) things today -- roughly \(minutes) minutes of actually being here.",
                "\(count) done. That's \(minutes) minutes you spent outside the feed.",
            ], &rng)
        }
    }

    private static func streakSentence(_ streak: Int, rng: inout SeededRNG) -> String {
        if streak >= 7 {
            return "\(streak) days running now. That's a habit, not a fluke."
        }
        return pick([
            "\(streak) days in a row.",
            "That's \(streak) days now.",
        ], &rng)
    }

    private static func quoted(_ text: String) -> String {
        var t = text
        if t.hasSuffix(".") { t.removeLast() }
        return "\u{201C}" + t + "\u{201D}"
    }

    private static func pick(_ options: [String], _ rng: inout SeededRNG) -> String {
        guard let idx = rng.weightedIndex(Array(repeating: 1.0, count: options.count)) else {
            return options.first ?? ""
        }
        return options[idx]
    }
}
