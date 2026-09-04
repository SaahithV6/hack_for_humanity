import Foundation

// MARK: - Gates

/// A predicate over `Context` that decides whether a frame or a vocabulary
/// option is admissible right now.
///
/// Gates are what make this a *conditional* grammar rather than a bag of
/// canned strings: "step outside and look at the sky" is a fine suggestion at
/// 6pm and a bad one at 1am, and the grammar knows the difference.
public struct Gate: Codable, Equatable, Sendable {
    public var minEnergy: Int = 1
    public var maxEnergy: Int = 5
    public var minMood: Int = 1
    public var maxMood: Int = 5
    /// Don't offer this if bedtime is closer than this many minutes.
    public var minMinutesToBedtime: Int = 0
    /// Time buckets this is allowed in. Empty means "any".
    public var buckets: Set<TimeBucket> = []
    /// If true, only offered when the user hit the "rescue me" button.
    public var rescueOnly: Bool = false

    public init(
        minEnergy: Int = 1,
        maxEnergy: Int = 5,
        minMood: Int = 1,
        maxMood: Int = 5,
        minMinutesToBedtime: Int = 0,
        buckets: Set<TimeBucket> = [],
        rescueOnly: Bool = false
    ) {
        self.minEnergy = minEnergy
        self.maxEnergy = maxEnergy
        self.minMood = minMood
        self.maxMood = maxMood
        self.minMinutesToBedtime = minMinutesToBedtime
        self.buckets = buckets
        self.rescueOnly = rescueOnly
    }

    public func admits(_ ctx: Context) -> Bool {
        guard ctx.energy >= minEnergy, ctx.energy <= maxEnergy else { return false }
        guard ctx.mood >= minMood, ctx.mood <= maxMood else { return false }
        guard ctx.minutesToBedtime >= minMinutesToBedtime else { return false }
        if !buckets.isEmpty && !buckets.contains(ctx.timeBucket) { return false }
        if rescueOnly && !ctx.isDoomscrollRescue { return false }
        return true
    }
}

// MARK: - Vocabulary

/// One expansion of a non-terminal.
public struct Option: Sendable {
    public let text: String
    /// Relative likelihood before context weighting.
    public let weight: Double
    /// Shifts the finished task's effort. Lets one frame span several rungs of
    /// the ladder: "text {someone}" is easier for a sibling than for a friend
    /// you have been avoiding.
    public let effortDelta: Int
    public let gate: Gate

    public init(_ text: String, weight: Double = 1.0, effortDelta: Int = 0, gate: Gate = Gate()) {
        self.text = text
        self.weight = weight
        self.effortDelta = effortDelta
        self.gate = gate
    }
}

/// A named non-terminal: `{place}`, `{someone}`, `{small_object}` and so on.
public struct Slot: Sendable {
    public let name: String
    public let options: [Option]

    public init(_ name: String, _ options: [Option]) {
        self.name = name
        self.options = options
    }
}

// MARK: - Frames

/// A sentence template. `{slot}` placeholders are expanded against the
/// vocabulary; everything else is emitted verbatim.
public struct Frame: Sendable {
    /// Assigned by `TaskGrammar` from the frame's position in the ruleset.
    /// The engine uses it to avoid handing somebody the same sentence twice in
    /// an evening, which reads as broken however good the sentence is.
    public internal(set) var id: Int = -1
    public let template: String
    public let archetype: Archetype
    /// Effort before any slot deltas are applied.
    public let baseEffort: Int
    public let minutes: Int
    public let weight: Double
    public let gate: Gate

    public init(
        _ template: String,
        _ archetype: Archetype,
        effort: Int,
        minutes: Int,
        weight: Double = 1.0,
        gate: Gate = Gate()
    ) {
        self.template = template
        self.archetype = archetype
        self.baseEffort = effort
        self.minutes = minutes
        self.weight = weight
        self.gate = gate
    }
}

// MARK: - Grammar

/// The generative core. Given an archetype, a context and a target effort, it
/// samples a frame and expands its slots to produce a concrete task.
///
/// The whole thing is a few hundred rules that combine into the high tens of
/// thousands of distinct, sensible sentences -- which is what buys us
/// "never the same list twice" without shipping a language model.
public struct TaskGrammar: Sendable {
    private let frames: [Frame]
    private let slots: [String: Slot]

    public init(frames: [Frame], slots: [Slot]) {
        self.frames = frames.enumerated().map { index, frame in
            var copy = frame
            copy.id = index
            return copy
        }
        self.slots = Dictionary(uniqueKeysWithValues: slots.map { ($0.name, $0) })
    }

    /// Every archetype that has at least one frame admissible in this context.
    public func availableArchetypes(for ctx: Context) -> Set<Archetype> {
        var found: Set<Archetype> = []
        for frame in frames where frame.gate.admits(ctx) {
            found.insert(frame.archetype)
        }
        return found
    }

    /// Samples one task. Returns nil only if no frame of that archetype is
    /// admissible, which the caller handles by falling back to another domain.
    /// - Parameters:
    ///   - targetEffort: what the ladder would like. A soft preference.
    ///   - maxEffort: a hard ceiling the result may not exceed, applied to
    ///     both frame selection and slot expansion. Defaults to the context's
    ///     own ceiling.
    ///   - excluding: frame ids offered recently. Skipped if that would leave
    ///     nothing at all -- a repeat beats an empty screen.
    public func generate(
        archetype: Archetype,
        context ctx: Context,
        targetEffort: Int,
        maxEffort: Int? = nil,
        excluding recent: Set<Int> = [],
        now: Date,
        rng: inout SeededRNG
    ) -> MothTask? {
        let ceiling = Swift.min(maxEffort ?? ctx.effortCeiling, 5)
        let admissible = frames.filter {
            $0.archetype == archetype && $0.gate.admits(ctx) && $0.baseEffort <= ceiling
        }
        guard !admissible.isEmpty else { return nil }
        let fresh = admissible.filter { !recent.contains($0.id) }
        let candidates = fresh.isEmpty ? admissible : fresh

        // Weight each frame by how close its base effort sits to what the
        // ladder asked for. Exact matches dominate but neighbours stay live,
        // which keeps the output from collapsing onto a handful of sentences.
        let weights = candidates.map { frame -> Double in
            let distance = Double(abs(frame.baseEffort - targetEffort))
            return frame.weight * Foundation.exp(-0.9 * distance)
        }
        guard let pick = rng.weightedIndex(weights) else { return nil }
        let frame = candidates[pick]

        // Slot options can add effort, so the expansion gets whatever headroom
        // is left under the ceiling and refuses options that would breach it.
        let budget = ceiling - frame.baseEffort
        let (text, effortDelta) = expand(frame.template, context: ctx, budget: budget, rng: &rng)
        let effort = Swift.min(Swift.max(frame.baseEffort + effortDelta, 1), ceiling)

        // Scale the time estimate with the realised effort so a harder variant
        // of a frame doesn't claim the easy variant's two minutes.
        let minutes = Swift.max(1, Int((Double(frame.minutes) * (0.75 + 0.25 * Double(effort))).rounded()))

        return MothTask(
            frameID: frame.id,
            text: sentenceCase(text),
            archetype: archetype,
            effort: effort,
            estimatedMinutes: minutes,
            origin: .engine,
            offeredAt: now
        )
    }

    /// Walks the template, replacing `{slot}` with a sampled option and
    /// accumulating the effort deltas those options carry.
    private func expand(
        _ template: String,
        context ctx: Context,
        budget: Int,
        rng: inout SeededRNG
    ) -> (String, Int) {
        var out = ""
        var totalDelta = 0
        var remaining = budget
        // A slot name that appears twice in one frame refers to the same
        // thing. "Clear {surface}. Only {surface}." has to name one surface,
        // or the instruction is nonsense. Suffixing a name with "!" opts out
        // and forces an independent draw.
        var bound: [String: String] = [:]
        var rest = Substring(template)

        while let open = rest.firstIndex(of: "{") {
            out += rest[rest.startIndex..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else {
                // Unbalanced brace: emit the remainder literally rather than
                // dropping text on the floor.
                out += rest[open...]
                return (out, totalDelta)
            }
            let raw = String(rest[afterOpen..<close])
            let forceFresh = raw.hasSuffix("!")
            let name = forceFresh ? String(raw.dropLast()) : raw
            if !forceFresh, let previous = bound[name] {
                out += previous
            } else if let (text, delta) = sample(slot: name, context: ctx,
                                                 budget: remaining, rng: &rng) {
                out += text
                totalDelta += delta
                remaining -= delta
                if !forceFresh { bound[name] = text }
            } else {
                // No admissible option. Leaving the placeholder in would show
                // the user raw braces, so emit nothing and let the sentence
                // read a little shorter.
                out += ""
            }
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return (tidy(out), totalDelta)
    }

    private func sample(
        slot name: String,
        context ctx: Context,
        budget: Int,
        rng: inout SeededRNG
    ) -> (String, Int)? {
        guard let slot = slots[name] else { return nil }
        let admissible = slot.options.filter { $0.gate.admits(ctx) && $0.effortDelta <= budget }
        guard !admissible.isEmpty else { return nil }
        guard let idx = rng.weightedIndex(admissible.map(\.weight)) else { return nil }
        let option = admissible[idx]
        return (option.text, option.effortDelta)
    }

    /// Collapses the double spaces and stray leading spaces that dropping an
    /// unfillable slot can leave behind.
    private func tidy(_ s: String) -> String {
        var out = s
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        out = out.replacingOccurrences(of: " ,", with: ",")
        out = out.replacingOccurrences(of: " .", with: ".")
        // The corpus writes "--" for readability in source; users get a real
        // em dash.
        out = out.replacingOccurrences(of: " -- ", with: "\u{2009}\u{2014}\u{2009}")
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Capitalises the start of every sentence.
    ///
    /// The corpus is written in lowercase so that frames compose without the
    /// author having to think about position, which means casing is applied
    /// here, once, at the end.
    private func sentenceCase(_ s: String) -> String {
        var out = ""
        var capitaliseNext = true
        for ch in s {
            if capitaliseNext, ch.isLetter {
                out.append(Character(ch.uppercased()))
                capitaliseNext = false
            } else {
                out.append(ch)
                if ch == "." || ch == "?" || ch == "!" { capitaliseNext = true }
            }
        }
        return out
    }
}
