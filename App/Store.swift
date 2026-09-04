import Foundation
import SwiftUI
import UserNotifications

/// The bridge between the pure-Swift engine and SwiftUI.
///
/// The engine deliberately knows nothing about Apple frameworks, so everything
/// platform-shaped lives here: persistence, notifications, and the small
/// amount of view state that outlives a single screen.
@MainActor
final class Store: ObservableObject {

    @Published private(set) var currentTask: MothTask?
    @Published private(set) var phase: Phase = .onboarding
    @Published private(set) var todayCompleted: Int = 0
    @Published private(set) var streak: Int = 0
    @Published var mood: Int = 3
    @Published var energy: Int = 3
    @Published var showingBedtime = false
    @Published var showingCrisis = false
    @Published var buddyMood: MothMood = .idle
    /// Set briefly after a completion so the UI can celebrate without the
    /// engine having to model "celebration".
    @Published var lastCompleted: MothTask?

    private var engine: Engine
    private let storeURL: URL
    private let enrichment = EnrichmentClient()
    /// False in Xcode previews, so the canvas never reads or writes the real
    /// state file. Without this, editing a preview would quietly mutate the
    /// history of whatever was last run in the simulator.
    private let persists: Bool

    // MARK: - Lifecycle

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeURL = dir.appendingPathComponent("moth-state.json")
        persists = true

        let loaded: MothState
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode(MothState.self, from: data) {
            loaded = decoded
        } else {
            loaded = MothState()
        }
        engine = Engine(state: loaded)
        refresh()
    }

    /// In-memory store for previews and tests. Touches no disk.
    init(previewState: MothState) {
        storeURL = URL(fileURLWithPath: "/dev/null")
        persists = false
        engine = Engine(state: previewState)
        refresh()
    }

    private func save() {
        guard persists else { return }
        // Atomic so an interrupted write cannot leave a half-file that fails
        // to decode and silently resets somebody's history.
        guard let data = try? JSONEncoder().encode(engine.state) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func refresh() {
        phase = engine.phase
        let today = Journal.dayIndex(for: Date())
        todayCompleted = engine.state.journal.record(for: today).completedCount
        streak = engine.state.journal.streak(endingAt: today)
    }

    // MARK: - Derived state

    var context: Context { engine.context(energy: energy, mood: mood) }
    var isBedtime: Bool { engine.isBedtime }
    var minutesToBedtime: Int { engine.minutesToBedtime }
    var riskLevel: RiskLevel { engine.riskLevel }
    var intake: Intake? { engine.state.intake }
    var hasAcknowledgedCrisis: Bool { engine.state.acknowledgedCrisisScreen }
    var lifetimeCompleted: Int { engine.state.journal.lifetimeCompleted }
    var engineCompleted: Int { engine.state.journal.lifetimeEngineCompleted }
    var cloudEnabled: Bool { engine.state.cloudEnrichmentEnabled }
    var enrichmentAccepted: Int { engine.state.enrichmentAccepted }
    var enrichmentRejected: Int { engine.state.enrichmentRejected }
    var lastRejection: RejectionReason? { engine.state.lastRejection }
    /// How many more of Moth's tasks before writing your own unlocks.
    var grooveRemaining: Int {
        max(0, Engine.grooveThreshold - engine.state.journal.lifetimeEngineCompleted)
    }

    /// One row of "what Moth has figured out". A named type rather than a
    /// tuple because SwiftUI's ForEach needs something identifiable.
    struct LearnedRow: Identifiable {
        let archetype: Archetype
        /// Posterior mean: how likely this person is to actually do it.
        let rate: Double
        /// Effective observations behind that estimate.
        let evidence: Double
        var id: Archetype { archetype }
    }

    /// What Moth currently believes about this person, for the "what I've
    /// learned" screen. Showing the model back to the user is the honest
    /// version of personalisation -- they can see exactly what it inferred.
    var learned: [LearnedRow] {
        let bucket = context.banditBucket
        return Archetype.allCases.compactMap { archetype -> LearnedRow? in
            let n = engine.state.bandit.confidence(archetype, bucket: bucket)
            guard n > 0.5 else { return nil }
            return LearnedRow(
                archetype: archetype,
                rate: engine.state.bandit.estimate(archetype, bucket: bucket),
                evidence: n
            )
        }
        .sorted { $0.rate > $1.rate }
    }

    // MARK: - Onboarding

    func completeOnboarding(_ intake: Intake) {
        engine.completeOnboarding(intake)
        energy = intake.baselineMood
        mood = intake.baselineMood
        if Safety.screen(intake: intake) == .crisis {
            showingCrisis = true
        }
        scheduleBedtimeNotification()
        save()
        refresh()
        nextTask()
    }

    func acknowledgeCrisis() {
        engine.state.acknowledgedCrisisScreen = true
        showingCrisis = false
        save()
    }

    // MARK: - Tasks

    func nextTask(rescue: Bool = false) {
        let ctx = engine.context(energy: energy, mood: mood, rescue: rescue)
        currentTask = engine.nextTask(context: ctx)
        buddyMood = .idle
        save()
    }

    func complete(_ task: MothTask) {
        engine.resolve(task, outcome: .done, context: context)
        lastCompleted = task
        buddyMood = .pleased
        save()
        refresh()
        // Let the celebration land before the next task slides in. Immediately
        // replacing it makes the app feel like a conveyor belt, which is the
        // same feeling as a feed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { [weak self] in
            guard let self else { return }
            self.lastCompleted = nil
            self.nextTask()
        }
    }

    func skip(_ task: MothTask) {
        engine.resolve(task, outcome: .skipped, context: context)
        save()
        refresh()
        nextTask()
    }

    func rescue() {
        engine.recordRescue()
        nextTask(rescue: true)
    }

    /// Returns nil on success, or the risk level that blocked it.
    func addUserTask(text: String, archetype: Archetype) -> RiskLevel? {
        switch engine.addUserTask(text: text, archetype: archetype) {
        case .success(let task):
            currentTask = task
            save()
            return nil
        case .failure(let risk):
            showingCrisis = true
            return risk
        }
    }

    func predictions(for typed: String) -> (completions: [String], nextWords: [String]) {
        engine.predictions(for: typed)
    }

    // MARK: - Bedtime

    func bedtimeSummary() -> Summary { engine.bedtimeSummary() }

    func setCloudEnrichment(_ enabled: Bool) {
        engine.setCloudEnrichment(enabled)
        save()
        objectWillChange.send()
    }

    /// Tries to upgrade the prose of an already-displayed summary.
    ///
    /// Returns nil for every failure -- disabled, offline, slow, refused, or
    /// rejected by the harness -- and the caller simply keeps what is already
    /// on screen. There is no error path to the user because from their side
    /// nothing has gone wrong.
    func enrichedSummary(upgrading local: Summary) async -> Summary? {
        guard engine.state.cloudEnrichmentEnabled else { return nil }
        let request = engine.enrichmentRequest(energy: energy, mood: mood)
        guard let candidate = try? await enrichment.summary(for: request) else { return nil }
        let merged = engine.accept(candidate, request: request, localFallback: local)
        save()
        return merged
    }

    func finishDay() {
        engine.completeWindDown()
        buddyMood = .sleepy
        save()
        refresh()
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// One notification a day, at bedtime. Not a re-engagement nudge -- this
    /// is the app asking the user to stop, which is the only kind of push
    /// notification it will ever send.
    func scheduleBedtimeNotification() {
        guard let bedtime = engine.state.intake?.bedtimeMinutes else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["moth.bedtime"])

        let content = UNMutableNotificationContent()
        content.title = "Moth"
        content.body = "It's time. Come see how your day went."
        content.sound = .default

        var components = DateComponents()
        components.hour = bedtime / 60
        components.minute = bedtime % 60

        let request = UNNotificationRequest(
            identifier: "moth.bedtime",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        center.add(request)
    }

    // MARK: - Privacy

    /// Everything lives in one JSON file, so "delete everything" is one unlink
    /// and it is genuinely complete.
    func eraseAllData() {
        try? FileManager.default.removeItem(at: storeURL)
        engine = Engine(state: MothState())
        currentTask = nil
        lastCompleted = nil
        refresh()
    }
}


// MARK: - Preview fixtures

// Deliberately not behind `#if DEBUG`: the `#Preview` macro expands into
// code that is compiled in Release too, so guarding these fixtures would break
// the Release build with "no member 'preview'".
extension Store {

    /// The states worth looking at in the canvas. Building these by hand beats
    /// clicking through onboarding every time a colour changes.
    enum Scenario {
        /// Fresh install, no intake yet.
        case onboarding
        /// Moth is assigning; a task is on screen.
        case guided
        /// Enough completions that self-authoring has unlocked.
        case groove
        /// A day with history behind it, for the bedtime read-back.
        case endOfDay
        /// Intake tripped the safety gate.
        case crisis
    }

    static func preview(_ scenario: Scenario) -> Store {
        var state = MothState()

        switch scenario {
        case .onboarding:
            return Store(previewState: state)

        case .crisis:
            state.intake = Intake(lowInterestDays: 3, lowMoodDays: 3,
                                  hasSelfHarmThoughts: true, baselineMood: 1)
            return Store(previewState: state)

        case .guided:
            state.intake = Intake(baselineMood: 3, caresAbout: [.tend, .sense])
            let store = Store(previewState: state)
            store.nextTask()
            return store

        case .groove, .endOfDay:
            state.intake = Intake(baselineMood: 3, caresAbout: [.tend, .sense],
                                  bedtimeMinutes: 23 * 60)
            state.ladder = Ladder(level: 2.4)

            let today = Journal.dayIndex(for: Date())
            var day = DayRecord(id: today)
            day.tasks = [
                MothTask(text: "Clear your desk. Only your desk \u{2014} stop when it's done.",
                         archetype: .tend, effort: 2, estimatedMinutes: 5,
                         origin: .engine, offeredAt: Date(), outcome: .done),
                MothTask(text: "Drink a full glass of water.", archetype: .nourish,
                         effort: 1, estimatedMinutes: 2, origin: .engine,
                         offeredAt: Date(), outcome: .done),
                MothTask(text: "Name five things you can see.", archetype: .sense,
                         effort: 1, estimatedMinutes: 2, origin: .engine,
                         offeredAt: Date(), outcome: .done),
                MothTask(text: "Text my sister back", archetype: .connect, effort: 2,
                         estimatedMinutes: 4, origin: .user, offeredAt: Date(),
                         outcome: .done),
            ]
            state.journal.update(day)

            // A few days behind it, so the streak and the bandit have something
            // to say.
            for offset in 1...3 {
                var past = DayRecord(id: today - offset)
                past.tasks = [
                    MothTask(text: "Stand up. That's the whole task.", archetype: .move,
                             effort: 1, estimatedMinutes: 1, origin: .engine,
                             offeredAt: Date(), outcome: .done),
                    MothTask(text: "Put one mug in the sink.", archetype: .tend,
                             effort: 1, estimatedMinutes: 2, origin: .engine,
                             offeredAt: Date(), outcome: .done),
                ]
                state.journal.update(past)
            }

            for _ in 0..<6 { state.bandit.record(.tend, bucket: "night/mid", completed: true) }
            for _ in 0..<4 { state.bandit.record(.sense, bucket: "night/mid", completed: true) }
            for _ in 0..<5 { state.bandit.record(.move, bucket: "night/mid", completed: false) }

            let store = Store(previewState: state)
            if scenario == .groove { store.nextTask() }
            return store
        }
    }
}
