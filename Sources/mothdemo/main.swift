import Foundation
import MothEngine

// `mothdemo --validate` reads a model's JSON summary on stdin and runs it
// through the same harness the app uses. Handy for pointing at a live provider
// and watching what gets caught:
//
//   curl -s ... | swift run mothdemo --validate
if CommandLine.arguments.contains("--validate") {
    let input = FileHandle.standardInput.readDataToEndOfFile()

    struct Probe: Decodable {
        let greeting: String
        let body: String
        let closing: String
        // The facts the request was built from, so grounding can be checked.
        var completedTasks: [String]?
        var completedCount: Int?
        var minutes: Int?
        var streak: Int?
        var selfWrittenCount: Int?
    }

    guard let probe = try? JSONDecoder().decode(Probe.self, from: input) else {
        print("could not parse stdin as a summary candidate")
        exit(2)
    }

    // Rebuild a day whose derived totals match the ones the request carried.
    // Getting this wrong makes the harness compute a different minute count
    // than the model was given and reject correct output -- the scaffold has
    // to reproduce the real request exactly or it tests nothing.
    var day = DayRecord(id: 0)
    let engineTexts = probe.completedTasks ?? []
    let totalCount = max(probe.completedCount ?? engineTexts.count, engineTexts.count)
    let selfWritten = min(probe.selfWrittenCount ?? 0, max(0, totalCount - engineTexts.count))

    var remainingMinutes = probe.minutes ?? 0
    var slotsLeft = totalCount

    func takeMinutes() -> Int {
        guard slotsLeft > 0 else { return 0 }
        let share = remainingMinutes / slotsLeft
        remainingMinutes -= share
        slotsLeft -= 1
        return share
    }

    for text in engineTexts {
        day.tasks.append(MothTask(text: text, archetype: .tend, effort: 2,
                                  estimatedMinutes: takeMinutes(), origin: .engine,
                                  offeredAt: Date(), outcome: .done))
    }
    for _ in 0..<selfWritten {
        day.tasks.append(MothTask(text: "(user written)", archetype: .rest, effort: 1,
                                  estimatedMinutes: takeMinutes(), origin: .user,
                                  offeredAt: Date(), outcome: .done))
    }
    while day.tasks.count < totalCount {
        day.tasks.append(MothTask(text: "(other)", archetype: .rest, effort: 1,
                                  estimatedMinutes: takeMinutes(), origin: .engine,
                                  offeredAt: Date(), outcome: .done))
    }
    // Any rounding remainder lands on the first task so the sum is exact.
    if remainingMinutes > 0, !day.tasks.isEmpty {
        let first = day.tasks[0]
        day.tasks[0] = MothTask(id: first.id, frameID: first.frameID, text: first.text,
                                archetype: first.archetype, effort: first.effort,
                                estimatedMinutes: first.estimatedMinutes + remainingMinutes,
                                origin: first.origin, offeredAt: first.offeredAt,
                                outcome: .done)
    }
    let request = EnrichmentRequest.summary(
        day: day,
        streak: probe.streak ?? 0,
        context: Context(energy: 2, mood: 2, timeBucket: .night, minutesToBedtime: 5)
    )
    let candidate = SummaryCandidate(greeting: probe.greeting, body: probe.body,
                                     closing: probe.closing)

    switch Harness.validate(candidate, against: request) {
    case .success:
        print("\u{001B}[32mACCEPTED\u{001B}[0m")
        print("  \(probe.greeting)")
        print("  \(probe.body)")
        print("  \(probe.closing)")
        exit(0)
    case .failure(let reason):
        print("\u{001B}[31mREJECTED\u{001B}[0m  \(reason.rawValue) -- \(reason.displayName)")
        print("  \(probe.body)")
        exit(1)
    }
}

// A headless driver for the engine. It exists so the generator can be
// inspected and demoed without a simulator -- useful on Linux, and useful for
// showing that the whole thing is deterministic and offline.

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/New_York")!

func at(_ hour: Int, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: hour, minute: minute))!
}

func rule(_ title: String) {
    print("\n\u{001B}[1m\(title)\u{001B}[0m")
    print(String(repeating: "-", count: title.count))
}

// MARK: - A day in the life

// Loud on purpose. Somebody opened Package.swift in Xcode instead of
// Moth.xcodeproj, ran this, and reasonably wondered where the app went.
print("""
\u{001B}[33m┌──────────────────────────────────────────────────────────────┐
│  This is mothdemo -- the HEADLESS engine driver, not the app.│
│  It prints a simulated day so the engine can be inspected     │
│  without a simulator.                                         │
│                                                               │
│  Looking for the iPhone app? Quit this, then:                 │
│      open Moth.xcodeproj      (NOT Package.swift)             │
│  pick the "Moth" scheme and an iPhone simulator, and Run.     │
└──────────────────────────────────────────────────────────────┘\u{001B}[0m
""")

rule("Onboarding")
let intake = Intake(
    lowInterestDays: 2, lowMoodDays: 2, hasSelfHarmThoughts: false,
    baselineMood: 2, caresAbout: [.tend, .sense],
    bedtimeMinutes: 23 * 60, scrollStartMinutes: 22 * 60
)
print("PHQ-2 style screen -> risk: \(Safety.screen(intake: intake).rawValue)")
print("starting ladder level: \(String(format: "%.2f", intake.startingLadderLevel))")

var clockTime = at(19, 0)
let engine = Engine(state: MothState(), calendar: cal, clock: { clockTime })
engine.completeOnboarding(intake)
print("phase: \(engine.phase.rawValue)")

// MARK: - Evening, guided

rule("19:00 - low energy evening, Moth assigns")
clockTime = at(19, 0)
var ctx = engine.context(energy: 2, mood: 2)
print("context: \(ctx.timeBucket.rawValue), \(ctx.minutesToBedtime) min to bed, "
      + "ceiling \(ctx.effortCeiling), bucket \(ctx.banditBucket)")
for i in 0..<4 {
    guard let task = engine.nextTask(context: ctx, seed: UInt64(100 + i)) else { continue }
    // Simulate a user who does sensory and tidying work, and declines the rest.
    let willDo = [Archetype.sense, .tend, .nourish, .rest].contains(task.archetype)
    print("  \(task.archetype.glyph) [e\(task.effort) ~\(task.estimatedMinutes)m] \(task.text)")
    print("      -> \(willDo ? "done" : "skipped")")
    engine.resolve(task, outcome: willDo ? .done : .skipped, context: ctx)
    ctx = engine.context(energy: 2, mood: 2)
}

// MARK: - The rescue

rule("22:10 - user hits 'I'm stuck scrolling'")
clockTime = at(22, 10)
engine.recordRescue()
ctx = engine.context(energy: 2, mood: 2, rescue: true)
print("ceiling under rescue: \(ctx.effortCeiling)")
for i in 0..<3 {
    if let task = engine.nextTask(context: ctx, seed: UInt64(200 + i)) {
        print("  \(task.archetype.glyph) [e\(task.effort) ~\(task.estimatedMinutes)m] \(task.text)")
        engine.resolve(task, outcome: .done, context: ctx)
    }
}

// MARK: - Wind-down gating

rule("22:50 - ten minutes to bedtime")
clockTime = at(22, 50)
ctx = engine.context(energy: 2, mood: 3)
print("wind-down window: \(ctx.isWindDownWindow), ceiling \(ctx.effortCeiling)")
for i in 0..<3 {
    if let task = engine.nextTask(context: ctx, seed: UInt64(300 + i)) {
        print("  \(task.archetype.glyph) [e\(task.effort)] \(task.text)")
        engine.resolve(task, outcome: .done, context: ctx)
    }
}

// MARK: - Typing assist

rule("Predictive input (what the user does NOT have to type)")
for prefix in ["", "wa", "text ", "clear your"] {
    let p = engine.predictions(for: prefix)
    let label = prefix.isEmpty ? "(empty field)" : "\"\(prefix)\""
    print("  \(label)")
    if !p.completions.isEmpty { print("      completions: \(p.completions)") }
    if !p.nextWords.isEmpty { print("      next words:  \(p.nextWords)") }
}

// MARK: - What the bandit learned

rule("What Moth learned about this user today")
let bucket = ctx.banditBucket
for archetype in Archetype.allCases {
    let n = engine.state.bandit.confidence(archetype, bucket: bucket)
    guard n > 0 else { continue }
    let pct = Int(engine.state.bandit.estimate(archetype, bucket: bucket) * 100)
    print("  \(archetype.displayName.padding(toLength: 8, withPad: " ", startingAt: 0)) "
          + "P(does it) \(pct)%  (n=\(String(format: "%.1f", n)))")
}
print("  ladder now at effort \(engine.state.ladder.targetEffort)")
print("  phase: \(engine.phase.rawValue)")

// MARK: - Bedtime

rule("23:00 - bedtime, Moth reads the day back")
clockTime = at(23, 0)
let summary = engine.bedtimeSummary(seed: 5)
print("  \(summary.greeting)\n")
print("  \(summary.body)\n")
for h in summary.highlights { print("    - \(h)") }
print("\n  \(summary.completedCount) done  |  \(summary.minutes) min  |  streak \(summary.streak)")
print("\n  \(summary.closing)")

// MARK: - Safety

rule("Safety gate")
for probe in ["Wash the dishes", "this deadline is killing me", "i want to die"] {
    print("  \"\(probe)\" -> \(Safety.screen(text: probe).rawValue)")
}

// MARK: - Variety

rule("Generator coverage")
let grammar = Corpus.grammar()
var rng = SeededRNG(seed: 99)
var unique = Set<String>()
let contexts = [
    Context(energy: 1, mood: 1, timeBucket: .night, minutesToBedtime: 20),
    Context(energy: 3, mood: 3, timeBucket: .evening, minutesToBedtime: 150),
    Context(energy: 5, mood: 4, timeBucket: .afternoon, minutesToBedtime: 400),
]
for i in 0..<20_000 {
    let c = contexts[i % contexts.count]
    let a = Archetype.allCases[i % Archetype.allCases.count]
    if let t = grammar.generate(archetype: a, context: c, targetEffort: (i % 5) + 1,
                                now: Date(), rng: &rng) {
        unique.insert(t.text)
    }
}
print("  \(unique.count) distinct tasks from \(Corpus.frames.count) frames "
      + "and \(Corpus.slots.count) slots")

let encoded = try! JSONEncoder().encode(engine.state)
print("  full user model on disk: \(encoded.count) bytes")
