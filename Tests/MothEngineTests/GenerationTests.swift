import XCTest
@testable import MothEngine

final class GenerationTests: XCTestCase {

    private func engine(intake: Intake = Intake(), at date: Date) -> Engine {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let e = Engine(state: MothState(), calendar: cal, clock: { date })
        e.completeOnboarding(intake)
        return e
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal.date(from: DateComponents(year: 2026, month: 9, day: 3,
                                             hour: hour, minute: minute))!
    }

    // MARK: - The grammar produces varied, well-formed output

    func testGeneratorProducesVariedWellFormedTasks() {
        let grammar = Corpus.grammar()
        let ctx = Context(energy: 3, mood: 3, timeBucket: .evening, minutesToBedtime: 120)
        var rng = SeededRNG(seed: 42)
        var seen = Set<String>()

        for i in 0..<600 {
            let archetype = Archetype.allCases[i % Archetype.allCases.count]
            guard let task = grammar.generate(archetype: archetype, context: ctx,
                                              targetEffort: (i % 5) + 1,
                                              now: Date(), rng: &rng) else { continue }
            seen.insert(task.text)
            // No unexpanded placeholders ever reach the user.
            XCTAssertFalse(task.text.contains("{"), "leaked slot: \(task.text)")
            XCTAssertFalse(task.text.contains("}"), "leaked slot: \(task.text)")
            XCTAssertFalse(task.text.contains("  "), "double space: \(task.text)")
            XCTAssertFalse(task.text.hasPrefix(" "))
            XCTAssertTrue((1...5).contains(task.effort))
            XCTAssertGreaterThan(task.estimatedMinutes, 0)
        }
        // The whole premise is "never the same list twice".
        XCTAssertGreaterThan(seen.count, 100, "grammar is not varied enough")
    }

    func testGenerationIsDeterministicForAGivenSeed() {
        let grammar = Corpus.grammar()
        let ctx = Context(energy: 3, mood: 3)
        var a = SeededRNG(seed: 7)
        var b = SeededRNG(seed: 7)
        let first = grammar.generate(archetype: .tend, context: ctx, targetEffort: 2,
                                     now: Date(), rng: &a)
        let second = grammar.generate(archetype: .tend, context: ctx, targetEffort: 2,
                                      now: Date(), rng: &b)
        XCTAssertEqual(first?.text, second?.text)
    }

    // MARK: - Context gating

    func testWindDownWindowOnlyOffersCalmDomains() {
        let e = engine(intake: Intake(bedtimeMinutes: 23 * 60), at: date(22, 45))
        let ctx = e.context(energy: 3, mood: 3)
        XCTAssertTrue(ctx.isWindDownWindow, "15 min before bed should be wind-down")

        for seed in UInt64(0)..<80 {
            guard let task = e.nextTask(context: ctx, seed: seed) else { continue }
            XCTAssertTrue(task.archetype.isWindDownSafe,
                          "offered \(task.archetype) at bedtime: \(task.text)")
            XCTAssertLessThanOrEqual(task.effort, 3,
                                     "too demanding near bed: \(task.text)")
        }
    }

    func testLowEnergyCapsEffortRegardlessOfLadderLevel() {
        var ladder = Ladder(level: 1.5)
        for _ in 0..<40 { ladder.record(completed: true) }
        XCTAssertEqual(ladder.targetEffort, 5, "ladder should have climbed")

        let flattened = Context(energy: 1, mood: 2, minutesToBedtime: 300)
        XCTAssertLessThanOrEqual(ladder.effort(under: flattened), 2,
                                 "a climbed ladder must still yield on an empty day")
    }

    func testRescueTasksAreSmallAndImmediate() {
        let e = engine(at: date(22, 0))
        let ctx = e.context(energy: 2, mood: 2, rescue: true)
        for seed in UInt64(0)..<60 {
            guard let task = e.nextTask(context: ctx, seed: seed) else { continue }
            XCTAssertLessThanOrEqual(task.effort, 2, "rescue too big: \(task.text)")
            XCTAssertNotEqual(task.archetype, .connect,
                              "rescue should not require another person")
        }
    }

    // MARK: - Ladder

    func testLadderDropsFasterThanItClimbs() {
        var up = Ladder(level: 3.0)
        up.record(completed: true)
        var down = Ladder(level: 3.0)
        down.record(completed: false)
        XCTAssertLessThan(3.0 - down.level, 10.0)
        XCTAssertGreaterThan(3.0 - down.level, up.level - 3.0,
                             "a miss must cost more than a hit gains")
    }

    // MARK: - Bandit

    func testBanditLearnsWhichDomainGetsDone() {
        var bandit = ArchetypeBandit()
        var rng = SeededRNG(seed: 3)
        // Simulate somebody who reliably does sensory tasks and never moves.
        for _ in 0..<30 {
            bandit.record(.sense, bucket: "night/lo", completed: true)
            bandit.record(.move, bucket: "night/lo", completed: false)
        }
        var senseWins = 0
        for _ in 0..<200 {
            if bandit.choose(from: [.sense, .move], bucket: "night/lo", rng: &rng) == .sense {
                senseWins += 1
            }
        }
        XCTAssertGreaterThan(senseWins, 170, "bandit failed to exploit the good arm")
    }

    func testBanditDecayForgetsOldEvidence() {
        var bandit = ArchetypeBandit()
        for _ in 0..<20 { bandit.record(.move, bucket: "evening/mid", completed: true) }
        let before = bandit.confidence(.move, bucket: "evening/mid")
        bandit.decay(days: 60)
        XCTAssertLessThan(bandit.confidence(.move, bucket: "evening/mid"), before * 0.4)
    }

    // MARK: - Safety

    func testCrisisLanguageIsCaught() {
        XCTAssertEqual(Safety.screen(text: "I want to die"), .crisis)
        XCTAssertEqual(Safety.screen(text: "thinking about hurting myself"), .crisis)
        XCTAssertEqual(Safety.screen(text: "Wash the dishes"), .none)
        // Precision matters more than recall here.
        XCTAssertEqual(Safety.screen(text: "this deadline is killing me"), .none)
    }

    func testUserTaskWithCrisisLanguageIsRefusedNotStored() {
        let e = engine(at: date(22, 0))
        let result = e.addUserTask(text: "I want to die", archetype: .rest)
        switch result {
        case .success: XCTFail("crisis text must not become a task")
        case .failure(let risk): XCTAssertEqual(risk, .crisis)
        }
        XCTAssertEqual(e.state.journal.record(for: Journal.dayIndex(for: date(22, 0))).tasks.count, 0)
    }

    func testCrisisScreenCanBeAcknowledged() {
        // The view layer cannot assign to engine.state -- it is private(set) --
        // so this has to go through a named operation. Pinning it because the
        // first version of the app tried the assignment and did not compile.
        let e = engine(at: date(20, 0))
        XCTAssertFalse(e.state.acknowledgedCrisisScreen)
        e.acknowledgeCrisisScreen()
        XCTAssertTrue(e.state.acknowledgedCrisisScreen)
    }

    func testSelfHarmIntakeRoutesToCrisis() {
        let intake = Intake(hasSelfHarmThoughts: true)
        XCTAssertEqual(Safety.screen(intake: intake), .crisis)
    }

    // MARK: - Predictor

    func testPredictorCompletesFromPrefix() {
        var p = Predictor.seeded(from: Corpus.grammar())
        p.trainOnUserText("Water the plants on the balcony")
        let completions = p.completions(for: "water the")
        XCTAssertTrue(completions.contains { $0.lowercased().contains("plants") },
                      "got \(completions)")
    }

    func testPredictorOffersStartersOnEmptyInput() {
        let p = Predictor.seeded(from: Corpus.grammar())
        XCTAssertFalse(p.starters().isEmpty)
    }

    // MARK: - Summary

    func testSummaryQuotesRealTasksAndNeverInflates() {
        var day = DayRecord(id: 1)
        day.tasks = [
            MothTask(text: "Clear your desk", archetype: .tend, effort: 3,
                     estimatedMinutes: 5, origin: .engine, offeredAt: Date(), outcome: .done),
            MothTask(text: "Drink a full glass of water", archetype: .nourish, effort: 1,
                     estimatedMinutes: 2, origin: .user, offeredAt: Date(), outcome: .done),
        ]
        var rng = SeededRNG(seed: 1)
        let s = Summarizer.summarize(day: day, streak: 3, bandit: ArchetypeBandit(),
                                     bucket: "night/mid", rng: &rng)
        XCTAssertEqual(s.completedCount, 2)
        XCTAssertEqual(s.minutes, 7)
        XCTAssertTrue(s.highlights.contains("Clear your desk"))
        XCTAssertTrue(s.body.contains("wrote yourself"))
    }

    func testZeroDayIsKindNotPunitive() {
        var day = DayRecord(id: 1)
        day.tasks = [MothTask(text: "Stand up", archetype: .move, effort: 1,
                              estimatedMinutes: 1, origin: .engine,
                              offeredAt: Date(), outcome: .skipped)]
        var rng = SeededRNG(seed: 1)
        let s = Summarizer.summarize(day: day, streak: 0, bandit: ArchetypeBandit(),
                                     bucket: "night/mid", rng: &rng)
        XCTAssertEqual(s.completedCount, 0)
        for word in ["failed", "fail", "missed", "should have", "0 of"] {
            XCTAssertFalse(s.body.lowercased().contains(word), "punitive copy: \(s.body)")
        }
        XCTAssertFalse(s.closing.isEmpty)
    }

    // MARK: - Persistence

    func testStateRoundTripsThroughJSON() throws {
        let e = engine(at: date(20, 0))
        let ctx = e.context(energy: 3, mood: 3)
        if let task = e.nextTask(context: ctx, seed: 11) {
            e.resolve(task, outcome: .done, context: ctx)
        }
        let data = try JSONEncoder().encode(e.state)
        let restored = try JSONDecoder().decode(MothState.self, from: data)
        XCTAssertEqual(restored.journal.lifetimeCompleted, e.state.journal.lifetimeCompleted)
        XCTAssertEqual(restored.ladder.targetEffort, e.state.ladder.targetEffort)
        XCTAssertNotNil(restored.intake)
    }

    // MARK: - Phase progression

    func testGrooveUnlocksAfterFiveOfMothsOwnTasks() {
        let e = engine(at: date(20, 0))
        XCTAssertEqual(Engine.grooveThreshold, 5)
        XCTAssertEqual(e.phase, .guided)
        let ctx = e.context(energy: 4, mood: 4)

        for seed in UInt64(0)..<UInt64(Engine.grooveThreshold - 1) {
            if let task = e.nextTask(context: ctx, seed: seed) {
                e.resolve(task, outcome: .done, context: ctx)
            }
        }
        XCTAssertEqual(e.phase, .guided, "unlocked one task early")

        if let last = e.nextTask(context: ctx, seed: 99) {
            e.resolve(last, outcome: .done, context: ctx)
        }
        XCTAssertEqual(e.phase, .groove)
    }

    func testSkippedTasksDoNotCountTowardTheUnlock() {
        let e = engine(at: date(20, 0))
        let ctx = e.context(energy: 4, mood: 4)
        for seed in UInt64(0)..<20 {
            if let task = e.nextTask(context: ctx, seed: seed) {
                e.resolve(task, outcome: .skipped, context: ctx)
            }
        }
        XCTAssertEqual(e.phase, .guided, "skipping should not earn self-authoring")
    }

    func testUserWrittenTasksDoNotCountTowardTheUnlock() {
        // The threshold means "you have done N of mine", so a user's own tasks
        // must not be what earns them the right to write their own.
        let e = engine(at: date(20, 0))
        let ctx = e.context(energy: 4, mood: 4)
        for _ in 0..<10 {
            if case .success(let task) = e.addUserTask(text: "Water the plants",
                                                       archetype: .tend) {
                e.resolve(task, outcome: .done, context: ctx)
            }
        }
        XCTAssertGreaterThanOrEqual(e.state.journal.lifetimeCompleted, 10)
        XCTAssertEqual(e.state.journal.lifetimeEngineCompleted, 0)
        XCTAssertEqual(e.phase, .guided)
    }

    // MARK: - Output quality regressions

    func testRepeatedSlotInOneFrameResolvesToTheSameValue() {
        // "Clear {surface}. Only {surface}." must name one surface, not two.
        let grammar = Corpus.grammar()
        let ctx = Context(energy: 3, mood: 3, minutesToBedtime: 300)
        var rng = SeededRNG(seed: 21)
        var checked = 0
        for _ in 0..<400 {
            guard let t = grammar.generate(archetype: .tend, context: ctx, targetEffort: 2,
                                           now: Date(), rng: &rng) else { continue }
            guard t.text.lowercased().hasPrefix("clear "),
                  let onlyRange = t.text.lowercased().range(of: "only ") else { continue }
            let first = t.text.lowercased()
                .dropFirst("clear ".count)
                .prefix(while: { $0 != "." })
            let second = t.text.lowercased()[onlyRange.upperBound...]
                .prefix(while: { $0 != " " || true })
                .prefix(while: { $0 != "\u{2014}" })
                .trimmingCharacters(in: .whitespaces)
            XCTAssertTrue(second.hasPrefix(String(first)),
                          "slot disagreement: \(t.text)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "never exercised the repeated-slot frame")
    }

    func testEverySentenceIsCapitalised() {
        let grammar = Corpus.grammar()
        let ctx = Context(energy: 3, mood: 3, minutesToBedtime: 300)
        var rng = SeededRNG(seed: 5)
        for i in 0..<500 {
            let a = Archetype.allCases[i % Archetype.allCases.count]
            guard let t = grammar.generate(archetype: a, context: ctx,
                                           targetEffort: (i % 5) + 1,
                                           now: Date(), rng: &rng) else { continue }
            // Any letter that directly follows ". " must be uppercase.
            let chars = Array(t.text)
            for j in 0..<max(0, chars.count - 2) where chars[j] == "." && chars[j + 1] == " " {
                let next = chars[j + 2]
                if next.isLetter {
                    XCTAssertTrue(next.isUppercase, "lowercase sentence start: \(t.text)")
                }
            }
        }
    }

    func testEngineDoesNotRepeatAFrameBackToBack() {
        let e = engine(at: date(20, 0))
        let ctx = e.context(energy: 3, mood: 3)
        var offered: [Int] = []
        for seed in UInt64(0)..<6 {
            if let t = e.nextTask(context: ctx, seed: seed), let id = t.frameID {
                offered.append(id)
            }
        }
        XCTAssertEqual(Set(offered).count, offered.count,
                       "same frame offered twice in one evening: \(offered)")
    }

    func testEffortNeverDriftsMoreThanOneRungAboveTarget() {
        // The bug this pins: a user reporting low energy with the ladder at its
        // floor was still being offered effort-4 tasks.
        let e = engine(at: date(19, 0))
        let ctx = e.context(energy: 2, mood: 2)
        let target = e.state.ladder.effort(under: ctx)
        for seed in UInt64(0)..<150 {
            guard let t = e.nextTask(context: ctx, seed: seed) else { continue }
            XCTAssertLessThanOrEqual(t.effort, target + 1,
                                     "drifted to e\(t.effort) against target e\(target): \(t.text)")
        }
    }

    func testBedtimeIsAWindowNotEverythingAfterBedtime() {
        // An 11pm bedtime must not still read as "bedtime" at 9am. The signed
        // wrap makes anything more than 12 hours early look late, so without a
        // bounded window the app shows the goodnight summary over breakfast.
        let morning = engine(intake: Intake(bedtimeMinutes: 23 * 60), at: date(9, 0))
        XCTAssertFalse(morning.isBedtime, "9am read as bedtime")

        let noon = engine(intake: Intake(bedtimeMinutes: 23 * 60), at: date(12, 30))
        XCTAssertFalse(noon.isBedtime, "half twelve read as bedtime")

        // The genuine window: at and after bedtime, through the small hours.
        let atBedtime = engine(intake: Intake(bedtimeMinutes: 23 * 60), at: date(23, 0))
        XCTAssertTrue(atBedtime.isBedtime)

        let lateNight = engine(intake: Intake(bedtimeMinutes: 23 * 60), at: date(1, 30))
        XCTAssertTrue(lateNight.isBedtime, "1:30am should still be bedtime")
    }

    func testNoTasksAreOfferedPastBedtime() {
        let e = engine(intake: Intake(bedtimeMinutes: 23 * 60), at: date(23, 30))
        let ctx = e.context(energy: 3, mood: 3)
        for seed in UInt64(0)..<40 {
            XCTAssertNil(e.nextTask(context: ctx, seed: seed),
                         "offered a task after bedtime")
        }
    }

    func testTasksResumeTheNextMorning() {
        let e = engine(intake: Intake(bedtimeMinutes: 23 * 60), at: date(9, 0))
        let ctx = e.context(energy: 3, mood: 3)
        XCTAssertNotNil(e.nextTask(context: ctx, seed: 1),
                        "morning should offer tasks again")
    }

    func testMinutesToBedtimeWrapsPastMidnight() {
        let e = engine(intake: Intake(bedtimeMinutes: 23 * 60), at: date(0, 30))
        // 12:30am against an 11pm bedtime is 90 minutes late.
        XCTAssertEqual(e.minutesToBedtime, -90)
        XCTAssertTrue(e.isBedtime)
    }
}
