import Foundation

/// Everything that persists. One Codable value, written as a single JSON file,
/// which is also what makes "delete everything" honest and instant.
public struct MothState: Codable, Sendable {
    public var intake: Intake?
    public var bandit: ArchetypeBandit
    public var ladder: Ladder
    public var journal: Journal
    public var predictor: Predictor
    /// Last day we applied the bandit's forgetting factor, so relaunching the
    /// app six times in an evening doesn't decay six days' worth.
    public var lastDecayDay: Int
    /// Set once the user has dismissed the crisis screen, so we don't trap
    /// them behind it on every launch.
    public var acknowledgedCrisisScreen: Bool

    // MARK: Optional cloud enrichment
    /// Off unless the user turns it on, and the app is fully functional
    /// without it.
    public var cloudEnrichmentEnabled: Bool
    /// How often the harness has let a model's writing through, and how often
    /// it has thrown it away. Surfaced in the app: a guardrail whose hit rate
    /// nobody looks at is decoration.
    public var enrichmentAccepted: Int
    public var enrichmentRejected: Int
    public var lastRejection: RejectionReason?

    public init(
        intake: Intake? = nil,
        bandit: ArchetypeBandit = ArchetypeBandit(),
        ladder: Ladder = Ladder(),
        journal: Journal = Journal(),
        predictor: Predictor = Predictor(),
        lastDecayDay: Int = 0,
        acknowledgedCrisisScreen: Bool = false,
        cloudEnrichmentEnabled: Bool = false,
        enrichmentAccepted: Int = 0,
        enrichmentRejected: Int = 0,
        lastRejection: RejectionReason? = nil
    ) {
        self.intake = intake
        self.bandit = bandit
        self.ladder = ladder
        self.journal = journal
        self.predictor = predictor
        self.lastDecayDay = lastDecayDay
        self.acknowledgedCrisisScreen = acknowledgedCrisisScreen
        self.cloudEnrichmentEnabled = cloudEnrichmentEnabled
        self.enrichmentAccepted = enrichmentAccepted
        self.enrichmentRejected = enrichmentRejected
        self.lastRejection = lastRejection
    }

    /// Hand-written so that a state file saved by an older build still loads.
    ///
    /// The synthesised decoder throws on any missing key, which would silently
    /// wipe somebody's streak and everything the bandit learned the first time
    /// we shipped a new field. Every field here is optional-with-default on the
    /// way in, and new fields must be added the same way.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intake = try c.decodeIfPresent(Intake.self, forKey: .intake)
        bandit = try c.decodeIfPresent(ArchetypeBandit.self, forKey: .bandit) ?? ArchetypeBandit()
        ladder = try c.decodeIfPresent(Ladder.self, forKey: .ladder) ?? Ladder()
        journal = try c.decodeIfPresent(Journal.self, forKey: .journal) ?? Journal()
        predictor = try c.decodeIfPresent(Predictor.self, forKey: .predictor) ?? Predictor()
        lastDecayDay = try c.decodeIfPresent(Int.self, forKey: .lastDecayDay) ?? 0
        acknowledgedCrisisScreen =
            try c.decodeIfPresent(Bool.self, forKey: .acknowledgedCrisisScreen) ?? false
        cloudEnrichmentEnabled =
            try c.decodeIfPresent(Bool.self, forKey: .cloudEnrichmentEnabled) ?? false
        enrichmentAccepted = try c.decodeIfPresent(Int.self, forKey: .enrichmentAccepted) ?? 0
        enrichmentRejected = try c.decodeIfPresent(Int.self, forKey: .enrichmentRejected) ?? 0
        lastRejection = try c.decodeIfPresent(RejectionReason.self, forKey: .lastRejection)
    }
}

/// Which mode the app is in. The progression from "Moth hands you tasks" to
/// "you write your own" is the actual therapeutic arc -- behavioural
/// activation works when the person takes over the scheduling, and the app is
/// scaffolding that should get out of the way.
public enum Phase: String, Sendable {
    case onboarding
    /// Moth assigns everything.
    case guided
    /// The user can write their own; Moth still offers, and the predictor
    /// means writing one costs a few taps.
    case groove
}

/// The engine's public surface. Deliberately synchronous and value-typed --
/// every operation is microseconds, so there is no reason for the view layer
/// to deal with concurrency.
public final class Engine {

    public private(set) var state: MothState
    private let grammar: TaskGrammar
    private let calendar: Calendar
    /// Injected so tests can pin it; the app passes Date.init.
    private let clock: () -> Date

    /// Completed tasks required before self-authoring unlocks. Eight is about
    /// a week of light use -- long enough that the habit has some traction,
    /// short enough that motivated users aren't held back.
    public static let grooveThreshold = 8

    public init(
        state: MothState = MothState(),
        grammar: TaskGrammar = Corpus.grammar(),
        calendar: Calendar = .current,
        clock: @escaping () -> Date = Date.init
    ) {
        self.state = state
        self.grammar = grammar
        self.calendar = calendar
        self.clock = clock
        if self.state.predictor.starters().isEmpty {
            self.state.predictor = Predictor.seeded(from: grammar)
        }
    }

    // MARK: - Phase and risk

    public var phase: Phase {
        guard state.intake != nil else { return .onboarding }
        return state.journal.lifetimeCompleted >= Engine.grooveThreshold ? .groove : .guided
    }

    public var riskLevel: RiskLevel {
        guard let intake = state.intake else { return .none }
        return Safety.screen(intake: intake)
    }

    public func completeOnboarding(_ intake: Intake) {
        state.intake = intake
        state.ladder = Ladder(level: intake.startingLadderLevel)
        state.lastDecayDay = today
    }

    // MARK: - Time

    private var now: Date { clock() }
    private var today: Int { Journal.dayIndex(for: now, calendar: calendar) }

    private var minutesNow: Int {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Minutes until bedtime, wrapping past midnight so a 12:30am check-in
    /// against an 11pm bedtime reads as 90 minutes late, not 22 hours early.
    public var minutesToBedtime: Int {
        guard let bedtime = state.intake?.bedtimeMinutes else { return 240 }
        var delta = bedtime - minutesNow
        if delta < -720 { delta += 1440 }
        if delta > 720 { delta -= 1440 }
        return delta
    }

    public var isBedtime: Bool { minutesToBedtime <= 0 }

    // MARK: - Context

    public func context(energy: Int, mood: Int, rescue: Bool = false) -> Context {
        let parts = calendar.dateComponents([.hour], from: now)
        let day = today
        return Context(
            energy: energy,
            mood: mood,
            timeBucket: TimeBucket.from(hour: parts.hour ?? 20),
            minutesToBedtime: minutesToBedtime,
            recentCompletionRate: state.journal.recentCompletionRate(endingAt: day),
            streakDays: state.journal.streak(endingAt: day),
            recentArchetypes: recentArchetypes(),
            preferredArchetypes: state.intake?.caresAbout ?? [],
            isDoomscrollRescue: rescue
        )
    }

    private func recentArchetypes(limit: Int = 3) -> [Archetype] {
        return state.journal.record(for: today).tasks
            .sorted { $0.offeredAt > $1.offeredAt }
            .prefix(limit)
            .map(\.archetype)
    }

    /// Frames offered recently, so the grammar can avoid handing back a
    /// sentence the user just saw. Six is roughly an evening's worth.
    private func recentFrameIDs(limit: Int = 6) -> Set<Int> {
        Set(state.journal.record(for: today).tasks
            .sorted { $0.offeredAt > $1.offeredAt }
            .prefix(limit)
            .compactMap(\.frameID))
    }

    // MARK: - Task generation

    /// The main entry point. Picks a domain with the bandit, asks the grammar
    /// for a sentence, records it as offered, and hands it back.
    public func nextTask(context ctx: Context, seed: UInt64? = nil) -> MothTask? {
        applyPendingDecay()

        var rng = SeededRNG(seed: seed ?? UInt64(now.timeIntervalSince1970 * 1000).byteSwapped)

        var candidates = grammar.availableArchetypes(for: ctx)
        // Close to bed, drop anything that would wake them back up.
        if ctx.isWindDownWindow {
            candidates = candidates.filter(\.isWindDownSafe)
        }
        guard !candidates.isEmpty else { return nil }

        let effort = state.ladder.effort(under: ctx)
        // The grammar is allowed to drift one rung above target to keep its
        // output varied, but no further: asking somebody who just told us they
        // are running on empty for a fifteen-minute task is exactly the miss
        // that makes people delete the app.
        let ceiling = Swift.min(ctx.effortCeiling, effort + 1)

        guard let archetype = state.bandit.choose(
            from: candidates,
            bucket: ctx.banditBucket,
            bias: bias(for: ctx),
            rng: &rng
        ) else { return nil }

        // The bandit picked a domain the grammar might not be able to fill at
        // this effort; fall back through the other candidates rather than
        // handing the user an empty screen.
        var ordered = [archetype] + Archetype.allCases.filter {
            candidates.contains($0) && $0 != archetype
        }
        let recent = recentFrameIDs()
        for option in ordered {
            if let task = grammar.generate(archetype: option, context: ctx,
                                           targetEffort: effort,
                                           maxEffort: ceiling,
                                           excluding: recent,
                                           now: now, rng: &rng) {
                offer(task)
                return task
            }
        }
        ordered.removeAll()
        return nil
    }

    /// Nudges the bandit without touching its learned posteriors.
    private func bias(for ctx: Context) -> [Archetype: Double] {
        var bias: [Archetype: Double] = [:]
        for archetype in ctx.preferredArchetypes {
            bias[archetype, default: 0] += 0.08
        }
        // Strong penalty for whatever we just offered, weaker for the one
        // before it -- variety matters, but not more than fit.
        for (i, archetype) in ctx.recentArchetypes.prefix(2).enumerated() {
            bias[archetype, default: 0] -= (i == 0 ? 0.35 : 0.15)
        }
        if ctx.isDoomscrollRescue {
            // A rescue needs to land in seconds: sensory and rest work, a
            // phone call does not.
            bias[.sense, default: 0] += 0.25
            bias[.rest, default: 0] += 0.20
            bias[.move, default: 0] += 0.10
            bias[.connect, default: 0] -= 0.30
            bias[.create, default: 0] -= 0.20
        }
        return bias
    }

    // MARK: - Recording outcomes

    private func offer(_ task: MothTask) {
        var record = state.journal.record(for: today)
        record.tasks.append(task)
        state.journal.update(record)
    }

    public func resolve(_ task: MothTask, outcome: TaskOutcome, context ctx: Context) {
        var record = state.journal.record(for: today)
        guard let idx = record.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        record.tasks[idx].outcome = outcome
        record.tasks[idx].resolvedAt = now
        state.journal.update(record)

        switch outcome {
        case .done:
            state.bandit.record(task.archetype, bucket: ctx.banditBucket, completed: true)
            state.ladder.record(completed: true)
            state.predictor.trainOnUserText(task.text)
        case .skipped:
            state.bandit.record(task.archetype, bucket: ctx.banditBucket, completed: false)
            state.ladder.recordSkip()
        case .expired:
            state.bandit.record(task.archetype, bucket: ctx.banditBucket, completed: false)
        case .pending:
            break
        }
    }

    /// A task the user typed. Screened before it is stored, because the text
    /// field is the one place somebody can tell us they are in trouble.
    public func addUserTask(text: String, archetype: Archetype, estimatedMinutes: Int = 5)
        -> Result<MothTask, RiskLevel>
    {
        let risk = Safety.screen(text: text)
        guard risk != .crisis else { return .failure(.crisis) }

        let task = MothTask(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            archetype: archetype,
            effort: state.ladder.targetEffort,
            estimatedMinutes: estimatedMinutes,
            origin: .user,
            offeredAt: now
        )
        offer(task)
        state.predictor.trainOnUserText(task.text)
        return .success(task)
    }

    public func recordRescue() {
        var record = state.journal.record(for: today)
        record.rescues += 1
        state.journal.update(record)
    }

    // MARK: - Bedtime

    public func bedtimeSummary(seed: UInt64? = nil) -> Summary {
        var rng = SeededRNG(seed: seed ?? UInt64(today))
        let record = state.journal.record(for: today)
        let parts = calendar.dateComponents([.hour], from: now)
        let bucket = Context(timeBucket: TimeBucket.from(hour: parts.hour ?? 22)).banditBucket
        return Summarizer.summarize(
            day: record,
            streak: state.journal.streak(endingAt: today),
            bandit: state.bandit,
            bucket: bucket,
            rng: &rng
        )
    }

    // MARK: - Enrichment

    /// Builds the narrow request the proxy is allowed to see. Nothing else in
    /// the app may construct one.
    public func enrichmentRequest(energy: Int, mood: Int) -> EnrichmentRequest {
        let ctx = context(energy: energy, mood: mood)
        return .summary(
            day: state.journal.record(for: today),
            streak: state.journal.streak(endingAt: today),
            context: ctx
        )
    }

    /// Runs a model's summary through the harness and, only if it survives,
    /// merges it onto the locally computed one.
    ///
    /// The counts, the minutes, the streak and the highlight list are always
    /// the local engine's -- the model is allowed to write the prose and
    /// nothing else. Even a fully validated candidate never gets to tell the
    /// user what they did.
    public func accept(
        _ candidate: SummaryCandidate,
        request: EnrichmentRequest,
        localFallback local: Summary
    ) -> Summary? {
        switch Harness.validate(candidate, against: request) {
        case .failure(let reason):
            state.enrichmentRejected += 1
            state.lastRejection = reason
            return nil
        case .success(let safe):
            state.enrichmentAccepted += 1
            state.lastRejection = nil
            return Summary(
                greeting: safe.greeting,
                body: safe.body,
                highlights: local.highlights,
                completedCount: local.completedCount,
                minutes: local.minutes,
                streak: local.streak,
                closing: safe.closing
            )
        }
    }

    public func setCloudEnrichment(_ enabled: Bool) {
        state.cloudEnrichmentEnabled = enabled
    }

    public func completeWindDown() {
        var record = state.journal.record(for: today)
        record.windDownCompleted = true
        // Anything still open when the day closes counts as expired, not as a
        // pending guilt object waiting for them tomorrow morning.
        for i in record.tasks.indices where record.tasks[i].outcome == .pending {
            record.tasks[i].outcome = .expired
        }
        state.journal.update(record)
    }

    // MARK: - Maintenance

    /// Applies one decay step per elapsed calendar day.
    private func applyPendingDecay() {
        let day = today
        guard day > state.lastDecayDay else { return }
        state.bandit.decay(days: day - state.lastDecayDay)
        state.lastDecayDay = day
    }

    // MARK: - Prediction passthrough

    public func predictions(for typed: String) -> (completions: [String], nextWords: [String]) {
        if typed.trimmingCharacters(in: .whitespaces).isEmpty {
            return (state.predictor.starters(), [])
        }
        return (state.predictor.completions(for: typed), state.predictor.nextWords(after: typed))
    }
}
