import Foundation
import MothEngine

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
