import Foundation

/// Word-level n-gram model with stupid-backoff, plus whole-phrase recall.
///
/// This is the half of the engine that runs once somebody has found their
/// groove and starts writing their own tasks. Typing on a phone at 11pm is
/// exactly the friction that sends people back to the feed, so the goal is
/// that writing a task takes three taps and no keyboard.
///
/// It trains on two sources: the shipped corpus (so it is useful on day one)
/// and everything the user has written or completed (so it converges on their
/// own vocabulary within a week). Order 3 with backoff is the sweet spot --
/// order 4 overfits on the tiny amount of personal text we ever see.
public struct Predictor: Codable, Sendable {

    /// counts[context][nextWord] -> weight. Context is "" for unigrams,
    /// "w" for bigrams, "w1 w2" for trigrams.
    private var counts: [String: [String: Double]] = [:]
    /// Whole phrases we have seen, for prefix completion.
    private var phrases: [String: Double] = [:]

    private static let maxOrder = 3
    /// User text counts for more than shipped corpus text -- it is evidence
    /// about this person rather than about people in general.
    private static let userWeight = 6.0

    public init() {}

    // MARK: - Training

    public mutating func train(phrase raw: String, weight: Double = 1.0) {
        let tokens = Predictor.tokenize(raw)
        guard !tokens.isEmpty else { return }

        let normalised = tokens.joined(separator: " ")
        phrases[normalised, default: 0] += weight

        // Sentinel start token so we can predict the *first* word too.
        let padded = ["\u{2}"] + tokens
        for i in 1..<padded.count {
            let next = padded[i]
            for order in 0..<Predictor.maxOrder {
                let start = i - order - 1
                guard start >= 0 else { break }
                let context = padded[start..<i].joined(separator: " ")
                counts[context, default: [:]][next, default: 0] += weight
            }
            // Unconditional unigram counts.
            counts["", default: [:]][next, default: 0] += weight
        }
    }

    public mutating func trainOnUserText(_ raw: String) {
        train(phrase: raw, weight: Predictor.userWeight)
    }

    /// Seeds the model from the shipped grammar so predictions are useful
    /// before the user has written anything at all.
    public static func seeded(from grammar: TaskGrammar, samples: Int = 400) -> Predictor {
        var predictor = Predictor()
        var rng = SeededRNG(seed: 0xB0DE_5EED_C0DE)
        let now = Date(timeIntervalSince1970: 0)
        // Sample across a spread of contexts so gated frames get represented.
        let contexts = [
            Context(energy: 1, mood: 2, timeBucket: .night, minutesToBedtime: 30),
            Context(energy: 3, mood: 3, timeBucket: .evening, minutesToBedtime: 120),
            Context(energy: 5, mood: 4, timeBucket: .afternoon, minutesToBedtime: 400),
            Context(energy: 2, mood: 2, timeBucket: .evening, minutesToBedtime: 90,
                    isDoomscrollRescue: true),
        ]
        for i in 0..<samples {
            let ctx = contexts[i % contexts.count]
            let archetype = Archetype.allCases[i % Archetype.allCases.count]
            let effort = (i % 5) + 1
            if let task = grammar.generate(archetype: archetype, context: ctx,
                                           targetEffort: effort, now: now, rng: &rng) {
                predictor.train(phrase: task.text, weight: 1.0)
            }
        }
        return predictor
    }

    // MARK: - Prediction

    /// The most likely next words given what has been typed so far.
    ///
    /// Stupid-backoff: try the longest context we have evidence for, and fall
    /// back a word at a time. Cheap, and it degrades gracefully, which matters
    /// more here than calibrated probabilities.
    public func nextWords(after typed: String, limit: Int = 3) -> [String] {
        let tokens = Predictor.tokenize(typed)
        let padded = ["\u{2}"] + tokens

        for order in stride(from: Predictor.maxOrder, through: 1, by: -1) {
            let start = padded.count - order
            guard start >= 0 else { continue }
            let context = padded[start...].joined(separator: " ")
            if let table = counts[context], table.count >= 2 {
                return Predictor.top(table, limit: limit)
            }
        }
        return Predictor.top(counts[""] ?? [:], limit: limit)
    }

    /// Whole remembered phrases that start with what has been typed. This is
    /// what turns "wa" into "walk around the block" in one tap.
    public func completions(for typed: String, limit: Int = 3) -> [String] {
        let prefix = Predictor.tokenize(typed).joined(separator: " ")
        guard !prefix.isEmpty else { return [] }
        let matches = phrases
            .filter { $0.key.hasPrefix(prefix) && $0.key != prefix }
            .sorted { lhs, rhs in
                // Prefer stronger evidence, then shorter completions -- a
                // short finish is likelier to be what they meant.
                lhs.value == rhs.value ? lhs.key.count < rhs.key.count : lhs.value > rhs.value
            }
        return matches.prefix(limit).map { Predictor.present($0.key) }
    }

    /// Openings offered when the field is still empty, so there is something
    /// to tap rather than a blank box and a blinking cursor.
    public func starters(limit: Int = 4) -> [String] {
        Predictor.top(counts["\u{2}"] ?? [:], limit: limit)
    }

    // MARK: - Helpers

    private static func top(_ table: [String: Double], limit: Int) -> [String] {
        table.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        .prefix(limit)
        .map(\.key)
    }

    static func tokenize(_ raw: String) -> [String] {
        raw.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func present(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
}
