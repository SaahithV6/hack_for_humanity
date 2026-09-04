import Foundation

// MARK: - What we are allowed to send

/// The *only* shape that can leave the device.
///
/// Privacy here is enforced by the type system rather than by discipline.
/// There is no field on this struct for the journal, the mood history, the
/// bandit posteriors, or anything the user typed -- so no future edit to the
/// networking layer can accidentally send them. If something needs to go, it
/// has to be added here first, deliberately, in a diff someone reviews.
public struct EnrichmentRequest: Codable, Equatable, Sendable {

    public enum Kind: String, Codable, Sendable {
        case task
        case summary
    }

    public let kind: Kind

    // Coarse context only. All of this is derivable from a clock and a slider;
    // none of it identifies anybody.
    public let timeBucket: TimeBucket
    public let minutesToBedtime: Int
    public let energy: Int
    public let mood: Int

    // For task generation.
    public let archetype: Archetype?
    public let targetEffort: Int?
    public let effortCeiling: Int?
    /// The grammar's own output, sent as a worked example of house style. The
    /// model is asked to specialise it, not to invent from nothing.
    public let seedTask: String?

    // For the summary.
    public let completedTasks: [String]?
    public let completedCount: Int?
    public let minutes: Int?
    public let streak: Int?
    /// Tasks the user wrote themselves are counted but never quoted -- their
    /// own words are the most personal text in the app.
    public let selfWrittenCount: Int?

    private init(
        kind: Kind, timeBucket: TimeBucket, minutesToBedtime: Int, energy: Int, mood: Int,
        archetype: Archetype? = nil, targetEffort: Int? = nil, effortCeiling: Int? = nil,
        seedTask: String? = nil, completedTasks: [String]? = nil, completedCount: Int? = nil,
        minutes: Int? = nil, streak: Int? = nil, selfWrittenCount: Int? = nil
    ) {
        self.kind = kind
        self.timeBucket = timeBucket
        self.minutesToBedtime = minutesToBedtime
        self.energy = energy
        self.mood = mood
        self.archetype = archetype
        self.targetEffort = targetEffort
        self.effortCeiling = effortCeiling
        self.seedTask = seedTask
        self.completedTasks = completedTasks
        self.completedCount = completedCount
        self.minutes = minutes
        self.streak = streak
        self.selfWrittenCount = selfWrittenCount
    }

    public static func task(seed: MothTask, context ctx: Context, targetEffort: Int)
        -> EnrichmentRequest
    {
        EnrichmentRequest(
            kind: .task,
            timeBucket: ctx.timeBucket,
            minutesToBedtime: ctx.minutesToBedtime,
            energy: ctx.energy,
            mood: ctx.mood,
            archetype: seed.archetype,
            targetEffort: targetEffort,
            effortCeiling: ctx.effortCeiling,
            seedTask: seed.text
        )
    }

    /// Only engine-authored task text is included. Anything the user wrote is
    /// reduced to a count before it ever reaches this struct.
    public static func summary(day: DayRecord, streak: Int, context ctx: Context)
        -> EnrichmentRequest
    {
        let engineAuthored = day.completed
            .filter { $0.origin == .engine }
            .map(\.text)
        return EnrichmentRequest(
            kind: .summary,
            timeBucket: ctx.timeBucket,
            minutesToBedtime: ctx.minutesToBedtime,
            energy: ctx.energy,
            mood: ctx.mood,
            completedTasks: engineAuthored,
            completedCount: day.completedCount,
            minutes: day.minutesInvested,
            streak: streak,
            selfWrittenCount: day.selfWritten.count
        )
    }
}

// MARK: - What can come back

public struct TaskCandidate: Codable, Equatable, Sendable {
    public let text: String
    public let effort: Int
    public let estimatedMinutes: Int

    public init(text: String, effort: Int, estimatedMinutes: Int) {
        self.text = text
        self.effort = effort
        self.estimatedMinutes = estimatedMinutes
    }
}

public struct SummaryCandidate: Codable, Equatable, Sendable {
    public let greeting: String
    public let body: String
    public let closing: String

    public init(greeting: String, body: String, closing: String) {
        self.greeting = greeting
        self.body = body
        self.closing = closing
    }
}

// MARK: - Rejection reasons

/// Why a model's output was thrown away. Surfaced in a debug view and counted,
/// because a harness whose rejection rate nobody watches is not a harness.
public enum RejectionReason: String, Codable, Sendable, CaseIterable, Error {
    case empty
    case tooLong
    case tooShort
    case leakedPlaceholder
    case containsURL
    case askedAQuestion
    case notAnInstruction
    case bannedTopic
    case crisisLanguage
    case effortOutOfRange
    case durationImplausible
    case fabricatedNumber
    case fabricatedQuote
    case inflatedPraise
    case gaveAdvice
    case assignedMoreWork

    /// Plain-language version, shown to the user. They are the ones the
    /// guardrail is for, so they get to read what it caught in words rather
    /// than in enum cases.
    public var displayName: String {
        switch self {
        case .empty: return "came back empty"
        case .tooLong: return "rambled"
        case .tooShort: return "said nothing"
        case .leakedPlaceholder: return "leaked template syntax"
        case .containsURL: return "tried to link somewhere"
        case .askedAQuestion: return "asked a question"
        case .notAnInstruction: return "wasn't an instruction"
        case .bannedTopic: return "went somewhere it shouldn't"
        case .crisisLanguage: return "used crisis language"
        case .effortOutOfRange: return "asked for too much"
        case .durationImplausible: return "misjudged how long it takes"
        case .fabricatedNumber: return "made up a number"
        case .fabricatedQuote: return "invented something you did"
        case .inflatedPraise: return "laid the praise on too thick"
        case .gaveAdvice: return "gave advice at bedtime"
        case .assignedMoreWork: return "assigned you more work"
        }
    }
}

// MARK: - The harness

/// Validates model output before any of it reaches a user.
///
/// The operating assumption is that the model is an unreliable narrator: it may
/// be wrong, off-tone, unsafe, or quietly making things up, and it is never
/// given the benefit of the doubt. Anything that fails any check is discarded
/// whole and the on-device output is used instead. There is no repair step and
/// no partial acceptance -- a half-trusted summary is worse than a template.
public enum Harness {

    // MARK: Task validation

    public static func validate(
        _ candidate: TaskCandidate,
        against request: EnrichmentRequest
    ) -> Result<TaskCandidate, RejectionReason> {

        let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty { return .failure(.empty) }
        if text.count < 8 { return .failure(.tooShort) }
        if text.count > 140 { return .failure(.tooLong) }
        if text.contains("{") || text.contains("}") { return .failure(.leakedPlaceholder) }
        if containsURL(text) { return .failure(.containsURL) }
        if text.contains("?") { return .failure(.askedAQuestion) }
        if Safety.screen(text: text) == .crisis { return .failure(.crisisLanguage) }
        if let reason = topicViolation(text) { return .failure(reason) }
        if !readsAsInstruction(text) { return .failure(.notAnInstruction) }

        // The ceiling is the same one the grammar obeys. A model that returns
        // a fifteen-minute task for somebody forty minutes from bed is wrong
        // in exactly the way the local engine is built not to be.
        let ceiling = request.effortCeiling ?? 5
        guard (1...ceiling).contains(candidate.effort) else {
            return .failure(.effortOutOfRange)
        }
        // Duration has to be consistent with the claimed effort, or the model
        // can smuggle a big task in under a small number.
        guard candidate.estimatedMinutes >= 1,
              candidate.estimatedMinutes <= plausibleMinutes(forEffort: candidate.effort) else {
            return .failure(.durationImplausible)
        }

        return .success(TaskCandidate(
            text: text,
            effort: candidate.effort,
            estimatedMinutes: candidate.estimatedMinutes
        ))
    }

    /// Effort 1 is a minute; effort 5 is half an hour. Anything past this for a
    /// given rung means the model has mislabelled how big its own task is.
    private static func plausibleMinutes(forEffort effort: Int) -> Int {
        switch effort {
        case 1: return 4
        case 2: return 9
        case 3: return 16
        case 4: return 25
        default: return 40
        }
    }

    // MARK: Summary validation

    /// The strictest of the two, because the summary is the one place the app
    /// makes factual claims about the user's own day. Being warmly wrong about
    /// what somebody did is worse than being flatly right.
    public static func validate(
        _ candidate: SummaryCandidate,
        against request: EnrichmentRequest
    ) -> Result<SummaryCandidate, RejectionReason> {

        let greeting = candidate.greeting.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = candidate.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let closing = candidate.closing.trimmingCharacters(in: .whitespacesAndNewlines)

        if body.isEmpty || greeting.isEmpty || closing.isEmpty { return .failure(.empty) }
        if body.count < 20 { return .failure(.tooShort) }
        if body.count > 600 { return .failure(.tooLong) }
        if greeting.count > 80 || closing.count > 120 { return .failure(.tooLong) }

        let whole = [greeting, body, closing].joined(separator: " ")
        if whole.contains("{") || whole.contains("}") { return .failure(.leakedPlaceholder) }
        if containsURL(whole) { return .failure(.containsURL) }
        if Safety.screen(text: whole) == .crisis { return .failure(.crisisLanguage) }
        if let reason = topicViolation(whole) { return .failure(reason) }

        // Bedtime is not the moment to be handed a plan, a technique, or
        // tomorrow's list. The screen exists to end the day, not extend it.
        if containsAny(whole, adviceMarkers) { return .failure(.gaveAdvice) }
        if containsAny(whole, assignmentMarkers) { return .failure(.assignedMoreWork) }

        // Tone: this app does not do "amazing", "crushed it", or exclamation
        // marks. Inflated praise for a two-minute task makes every other thing
        // the app says untrustworthy.
        if whole.contains("!") { return .failure(.inflatedPraise) }
        if containsAny(whole, inflationMarkers) { return .failure(.inflatedPraise) }

        // Grounding check 1: every number the model states must be a number we
        // actually gave it. This is the anti-hallucination gate, and it is the
        // reason a cloud summary can be trusted at all.
        if let bad = ungroundedNumber(in: whole, request: request) {
            _ = bad
            return .failure(.fabricatedNumber)
        }

        // Grounding check 2: anything in quotation marks must be a task that
        // really happened. A model inventing a plausible-sounding accomplishment
        // is the single worst failure this app could have.
        if !quotesAreGrounded(whole, tasks: request.completedTasks ?? []) {
            return .failure(.fabricatedQuote)
        }

        return .success(SummaryCandidate(greeting: greeting, body: body, closing: closing))
    }

    // MARK: Grounding

    /// Integers the model is allowed to use: the ones we sent, plus small
    /// numbers that are almost always words about quantity rather than claims
    /// ("one thing", "a couple"). Anything else is a fabrication.
    private static func ungroundedNumber(in text: String, request: EnrichmentRequest) -> Int? {
        var allowed = Set<Int>([0, 1, 2])
        if let n = request.completedCount { allowed.insert(n) }
        if let n = request.minutes { allowed.insert(n) }
        if let n = request.streak { allowed.insert(n) }
        if let n = request.selfWrittenCount { allowed.insert(n) }
        if let n = request.completedTasks?.count { allowed.insert(n) }

        for token in text.split(whereSeparator: { !$0.isNumber }) {
            guard let value = Int(token) else { continue }
            if !allowed.contains(value) { return value }
        }
        return nil
    }

    /// Every quoted span must match a real task. Matching is loose on
    /// punctuation and case, because a model will reasonably re-capitalise or
    /// drop a trailing full stop when it quotes.
    private static func quotesAreGrounded(_ text: String, tasks: [String]) -> Bool {
        let normalisedTasks = tasks.map(normalise)
        for quoted in quotedSpans(in: text) {
            let needle = normalise(quoted)
            // Ignore very short quotes -- a model quoting one word is not
            // making a factual claim about what happened.
            guard needle.count >= 8 else { continue }
            let grounded = normalisedTasks.contains { task in
                task.contains(needle) || needle.contains(task)
            }
            if !grounded { return false }
        }
        return true
    }

    /// Pulls out spans in straight or curly double quotes.
    private static func quotedSpans(in text: String) -> [String] {
        var spans: [String] = []
        var current: String?
        for ch in text {
            let isOpen = (ch == "\u{201C}")
            let isClose = (ch == "\u{201D}")
            let isStraight = (ch == "\"")
            if isOpen || (isStraight && current == nil) {
                current = ""
            } else if isClose || (isStraight && current != nil) {
                if let span = current { spans.append(span) }
                current = nil
            } else if current != nil {
                current?.append(ch)
            }
        }
        return spans
    }

    private static func normalise(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Content rules

    private static let bannedTopics: [String] = [
        // Anything clinical. Moth is not qualified and must not sound it.
        "medication", "meds dose", "dosage", "prescri", "diagnos", "therapy session",
        "antidepressant", "your doctor", "symptom",
        // Substances.
        "alcohol", "drink a beer", "wine", "weed", "smoke a", "vape",
        // Anything that spends money or opens another feed -- both are the
        // behaviour we are trying to interrupt.
        "buy ", "purchase", "order online", "add to cart", "subscribe",
        "instagram", "tiktok", "twitter", "reddit", "youtube", "facebook",
        "scroll through", "check your feed",
        // Intensity that could hurt somebody who is not well.
        "run a mile", "push-ups until", "as many as you can", "push yourself hard",
        "fast for", "skip a meal",
    ]

    private static let adviceMarkers: [String] = [
        "you should", "try to", "remember to", "make sure", "next time",
        "it's important to", "consider ", "i suggest", "i recommend", "tip:",
    ]

    private static let assignmentMarkers: [String] = [
        "tomorrow you", "tomorrow, ", "your next task", "here's what", "goal for",
        "plan to", "aim to",
    ]

    private static let inflationMarkers: [String] = [
        "amazing", "incredible", "crushed", "crushing it", "smashed", "proud of you",
        "you're a star", "well done!", "fantastic", "awesome", "superstar",
        "keep it up", "you rock", "way to go",
    ]

    private static func topicViolation(_ text: String) -> RejectionReason? {
        let lower = text.lowercased()
        for banned in bannedTopics where lower.contains(banned) {
            return .bannedTopic
        }
        return nil
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        let lower = text.lowercased()
        return needles.contains { lower.contains($0) }
    }

    private static func containsURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("http://") || lower.contains("https://")
            || lower.contains("www.") || lower.contains(".com")
    }

    /// A task has to read as something to do. Rejects first-person narration
    /// ("I think you could..."), hedging, and meta-commentary about the request.
    private static func readsAsInstruction(_ text: String) -> Bool {
        let lower = text.lowercased()
        let badOpenings = ["i ", "i'", "as an", "sure,", "here'", "certainly",
                           "of course", "okay,", "ok,", "let me", "how about",
                           "maybe you", "perhaps"]
        for opening in badOpenings where lower.hasPrefix(opening) { return false }
        if lower.contains("as an ai") || lower.contains("language model") { return false }
        return true
    }
}
