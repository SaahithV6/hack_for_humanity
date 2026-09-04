import XCTest
@testable import MothEngine

/// The harness is the only thing standing between a remote model and somebody
/// who is not doing well at 11pm, so it gets tested the way you would test a
/// parser on hostile input: with the outputs a model actually produces when it
/// goes wrong, not with the ones it produces when it goes right.
final class HarnessTests: XCTestCase {

    // MARK: - Fixtures

    private let ctx = Context(energy: 2, mood: 2, timeBucket: .night,
                              minutesToBedtime: 40)

    private var taskRequest: EnrichmentRequest {
        let seed = MothTask(text: "Clear your desk", archetype: .tend, effort: 2,
                            estimatedMinutes: 5, origin: .engine, offeredAt: Date())
        return .task(seed: seed, context: ctx, targetEffort: 2)
    }

    private var summaryRequest: EnrichmentRequest {
        var day = DayRecord(id: 1)
        day.tasks = [
            MothTask(text: "Clear your desk", archetype: .tend, effort: 2,
                     estimatedMinutes: 5, origin: .engine, offeredAt: Date(), outcome: .done),
            MothTask(text: "Drink a full glass of water", archetype: .nourish, effort: 1,
                     estimatedMinutes: 2, origin: .engine, offeredAt: Date(), outcome: .done),
            MothTask(text: "Text my sister back", archetype: .connect, effort: 2,
                     estimatedMinutes: 3, origin: .user, offeredAt: Date(), outcome: .done),
        ]
        return .summary(day: day, streak: 3, context: ctx)
    }

    private func expectTaskRejected(
        _ text: String, effort: Int = 2, minutes: Int = 5,
        _ reason: RejectionReason, file: StaticString = #filePath, line: UInt = #line
    ) {
        let candidate = TaskCandidate(text: text, effort: effort, estimatedMinutes: minutes)
        switch Harness.validate(candidate, against: taskRequest) {
        case .success:
            XCTFail("harness accepted: \(text)", file: file, line: line)
        case .failure(let got):
            XCTAssertEqual(got, reason, "wrong reason for: \(text)", file: file, line: line)
        }
    }

    private func expectSummaryRejected(
        greeting: String = "Here's your day.",
        body: String,
        closing: String = "Go to sleep.",
        _ reason: RejectionReason, file: StaticString = #filePath, line: UInt = #line
    ) {
        let candidate = SummaryCandidate(greeting: greeting, body: body, closing: closing)
        switch Harness.validate(candidate, against: summaryRequest) {
        case .success:
            XCTFail("harness accepted: \(body)", file: file, line: line)
        case .failure(let got):
            XCTAssertEqual(got, reason, "wrong reason for: \(body)", file: file, line: line)
        }
    }

    // MARK: - Privacy is structural

    func testRequestCannotCarryUserWrittenTaskText() {
        // The user wrote "Text my sister back". It must be counted, never quoted.
        let request = summaryRequest
        XCTAssertEqual(request.selfWrittenCount, 1)
        XCTAssertEqual(request.completedTasks, ["Clear your desk", "Drink a full glass of water"])
        let encoded = try! JSONEncoder().encode(request)
        let json = String(data: encoded, encoding: .utf8)!
        XCTAssertFalse(json.contains("sister"),
                       "user-authored text reached the wire: \(json)")
    }

    func testRequestCarriesNoJournalOrModelState() {
        // Everything on the wire should be derivable from a clock and two
        // sliders. If this ever fails, someone widened the request type.
        let json = String(data: try! JSONEncoder().encode(summaryRequest), encoding: .utf8)!
        for forbidden in ["bandit", "posterior", "ladder", "journal", "intake",
                          "phq", "selfHarm", "successes", "failures"] {
            XCTAssertFalse(json.lowercased().contains(forbidden.lowercased()),
                           "leaked \(forbidden): \(json)")
        }
    }

    // MARK: - Task: the good case still passes

    func testAWellFormedTaskIsAccepted() {
        let candidate = TaskCandidate(text: "Put the three closest things back where they live.",
                                      effort: 2, estimatedMinutes: 4)
        guard case .success = Harness.validate(candidate, against: taskRequest) else {
            return XCTFail("harness rejected a good task")
        }
    }

    // MARK: - Task: model failure modes

    func testRejectsAssistantPreamble() {
        expectTaskRejected("Sure, here's a small task for you: clear one shelf.",
                           .notAnInstruction)
        expectTaskRejected("Of course. Wipe down the counter.", .notAnInstruction)
        expectTaskRejected("As an AI, I'd suggest tidying one surface.", .notAnInstruction)
    }

    func testRejectsLeakedTemplateSyntax() {
        expectTaskRejected("Clear {surface} before bed.", .leakedPlaceholder)
    }

    func testRejectsQuestions() {
        expectTaskRejected("Why not clear your desk before bed?", .askedAQuestion)
    }

    func testRejectsClinicalContent() {
        expectTaskRejected("Take your medication dosage as prescribed.", .bannedTopic)
        expectTaskRejected("Write down every symptom you noticed today.", .bannedTopic)
    }

    func testRejectsSubstancesAndSpending() {
        expectTaskRejected("Pour a glass of wine and relax.", .bannedTopic)
        expectTaskRejected("Buy a nice candle for your room.", .bannedTopic)
    }

    func testRejectsSendingTheUserBackToAFeed() {
        // The single worst possible suggestion this app could make.
        expectTaskRejected("Scroll through Instagram for five minutes guilt-free.",
                           .bannedTopic)
        expectTaskRejected("Post about your day on twitter.", .bannedTopic)
    }

    func testRejectsIntensityThatCouldHurtSomeone() {
        expectTaskRejected("Do push-ups until failure.", .bannedTopic)
        expectTaskRejected("Go run a mile right now.", .bannedTopic)
    }

    func testRejectsEffortAboveTheContextCeiling() {
        // Forty minutes to bedtime means the ceiling is 3.
        XCTAssertEqual(ctx.effortCeiling, 3)
        expectTaskRejected("Reorganise the whole kitchen tonight.", effort: 5, minutes: 30,
                           .effortOutOfRange)
    }

    func testRejectsDurationInconsistentWithClaimedEffort() {
        // A model smuggling a big task in under a small effort number.
        expectTaskRejected("Tidy one shelf.", effort: 1, minutes: 25, .durationImplausible)
    }

    func testRejectsCrisisLanguageInGeneratedText() {
        expectTaskRejected("Write about why you want to die.", .crisisLanguage)
    }

    func testRejectsLinks() {
        expectTaskRejected("Read this: https://example.com/calm", .containsURL)
    }

    // MARK: - Summary: the good case still passes

    func testAWellFormedSummaryIsAccepted() {
        let candidate = SummaryCandidate(
            greeting: "Here's your day.",
            body: "3 things, about 10 minutes. \u{201C}Clear your desk\u{201D} was the one with weight in it. One of those you wrote yourself. That's 3 days in a row now.",
            closing: "That's enough. Put it down."
        )
        guard case .success = Harness.validate(candidate, against: summaryRequest) else {
            return XCTFail("harness rejected a good summary")
        }
    }

    // MARK: - Summary: grounding

    func testRejectsFabricatedNumbers() {
        // The user did 3 things in 10 minutes with a 3-day streak. 47 is invented.
        expectSummaryRejected(
            body: "You did 47 things today, which is a lot for anyone.",
            .fabricatedNumber
        )
    }

    func testRejectsInflatedCountsEvenWhenPlausible() {
        expectSummaryRejected(
            body: "8 things today, and that took real effort on a hard evening.",
            .fabricatedNumber
        )
    }

    func testAcceptsNumbersWeActuallySupplied() {
        let candidate = SummaryCandidate(
            greeting: "Day's done.",
            body: "3 things, 10 minutes, and a 3 day streak behind it.",
            closing: "Sleep."
        )
        guard case .success = Harness.validate(candidate, against: summaryRequest) else {
            return XCTFail("harness rejected grounded numbers")
        }
    }

    func testRejectsFabricatedAccomplishments() {
        // The worst failure available to this app: inventing something warm
        // and specific that never happened.
        expectSummaryRejected(
            body: "\u{201C}You called your mum back after all this time\u{201D} was the big one today.",
            .fabricatedQuote
        )
    }

    func testAcceptsQuotesOfRealTasks() {
        let candidate = SummaryCandidate(
            greeting: "Here's your day.",
            body: "\u{201C}Drink a full glass of water\u{201D} sounds like nothing and wasn't.",
            closing: "Goodnight."
        )
        guard case .success = Harness.validate(candidate, against: summaryRequest) else {
            return XCTFail("harness rejected a grounded quote")
        }
    }

    func testRejectsQuotingTheUsersOwnPrivateTask() {
        // "Text my sister back" was never sent, so a model quoting it back
        // would mean something has gone very wrong upstream.
        expectSummaryRejected(
            body: "\u{201C}Text my sister back\u{201D} was the brave one tonight.",
            .fabricatedQuote
        )
    }

    // MARK: - Summary: tone

    func testRejectsInflatedPraise() {
        expectSummaryRejected(body: "You absolutely crushed it today, superstar.",
                              .inflatedPraise)
        expectSummaryRejected(body: "3 things done. Amazing work today.", .inflatedPraise)
    }

    func testRejectsExclamationMarks() {
        expectSummaryRejected(body: "3 things today, and that counts!", .inflatedPraise)
    }

    func testRejectsAdviceAtBedtime() {
        expectSummaryRejected(
            body: "3 things today. Next time, try to start a little earlier in the evening.",
            .gaveAdvice
        )
    }

    func testRejectsAssigningTomorrowsWork() {
        expectSummaryRejected(
            body: "3 things today. Tomorrow you can build on this and do a few more.",
            .assignedMoreWork
        )
    }

    func testRejectsRamblingSummaries() {
        expectSummaryRejected(body: String(repeating: "Some words about the day. ", count: 40),
                              .tooLong)
    }

    // MARK: - Merging a validated candidate

    func testAcceptedSummaryKeepsLocalFactsAndOnlyTakesProse() {
        let engine = Engine(state: MothState())
        engine.completeOnboarding(Intake())
        let local = Summary(greeting: "Local greeting.", body: "Local body.",
                            highlights: ["Clear your desk"], completedCount: 3,
                            minutes: 10, streak: 3, closing: "Local closing.")
        let candidate = SummaryCandidate(
            greeting: "Here's your day.",
            body: "3 things, about 10 minutes. That's 3 days in a row now.",
            closing: "Put it down."
        )
        let merged = engine.accept(candidate, request: summaryRequest, localFallback: local)
        let result = try! XCTUnwrap(merged)
        // Prose comes from the model.
        XCTAssertEqual(result.body, candidate.body)
        XCTAssertEqual(result.closing, "Put it down.")
        // Every fact stays local. The model never gets to say what happened.
        XCTAssertEqual(result.completedCount, 3)
        XCTAssertEqual(result.minutes, 10)
        XCTAssertEqual(result.streak, 3)
        XCTAssertEqual(result.highlights, ["Clear your desk"])
        XCTAssertEqual(engine.state.enrichmentAccepted, 1)
        XCTAssertEqual(engine.state.enrichmentRejected, 0)
    }

    func testRejectedSummaryReturnsNilAndIsCounted() {
        let engine = Engine(state: MothState())
        engine.completeOnboarding(Intake())
        let local = Summary(greeting: "g", body: "b", highlights: [], completedCount: 3,
                            minutes: 10, streak: 3, closing: "c")
        let bad = SummaryCandidate(greeting: "Hey.",
                                   body: "You did 47 things today, which took real effort.",
                                   closing: "Night.")
        XCTAssertNil(engine.accept(bad, request: summaryRequest, localFallback: local))
        XCTAssertEqual(engine.state.enrichmentRejected, 1)
        XCTAssertEqual(engine.state.lastRejection, .fabricatedNumber)
    }

    // MARK: - Forward compatibility of the saved state

    func testStateSavedByAnOlderBuildStillLoads() {
        // A state file written before cloud enrichment existed. Decoding this
        // must not throw -- if it does, every user loses their streak and
        // everything the bandit learned on the next update.
        let legacy = """
        {"lastDecayDay":20334,"acknowledgedCrisisScreen":false,
         "ladder":{"level":2.4,"ascent":0.22,"descent":0.55,"floor":1.0,"ceiling":5.0},
         "journal":{"days":{}},"bandit":{"successes":{},"failures":{},
         "priorAlpha":1.0,"priorBeta":1.0,"dailyDecay":0.98},
         "predictor":{"counts":{},"phrases":{}}}
        """
        let data = legacy.data(using: .utf8)!
        let restored = try? JSONDecoder().decode(MothState.self, from: data)
        let state = try! XCTUnwrap(restored, "legacy state failed to decode")
        XCTAssertEqual(state.lastDecayDay, 20334)
        XCTAssertEqual(state.ladder.targetEffort, 2)
        // New fields land on their defaults.
        XCTAssertFalse(state.cloudEnrichmentEnabled)
        XCTAssertEqual(state.enrichmentAccepted, 0)
        XCTAssertNil(state.lastRejection)
    }

    func testCloudEnrichmentIsOffByDefault() {
        XCTAssertFalse(MothState().cloudEnrichmentEnabled)
    }

    // MARK: - Fallback contract

    func testEveryRejectionReasonIsDistinguishable() {
        // The debug view counts these, so they must not collapse.
        XCTAssertEqual(Set(RejectionReason.allCases.map(\.rawValue)).count,
                       RejectionReason.allCases.count)
    }
}
