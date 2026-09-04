import Foundation

/// Thompson sampling over archetypes, partitioned by context bucket.
///
/// The problem this solves: we do not know what will actually get this
/// particular person off their phone. Asking them is unreliable -- depressed
/// people routinely mispredict what will help. So we treat each archetype as
/// an arm with an unknown completion probability, keep a Beta posterior over
/// it, and sample. Arms we have never tried stay optimistic and get explored;
/// arms that keep getting skipped quietly recede.
///
/// Beta-Bernoulli is the right conjugate pair here because the reward is
/// binary (the task got done or it didn't), and it needs two Doubles per arm,
/// which matters when the whole model has to sit in a few hundred kilobytes.
public struct ArchetypeBandit: Codable, Sendable {
    /// Posterior counts keyed by "bucket|archetype".
    private var successes: [String: Double] = [:]
    private var failures: [String: Double] = [:]

    /// Beta(1,1) is uniform -- we start out knowing nothing, which is true.
    private let priorAlpha: Double
    private let priorBeta: Double

    /// Multiplied into every count on a day boundary so that who someone was
    /// three months ago stops outvoting who they are now. 0.98 gives a
    /// half-life of about five weeks.
    private let dailyDecay: Double

    public init(priorAlpha: Double = 1.0, priorBeta: Double = 1.0, dailyDecay: Double = 0.98) {
        self.priorAlpha = priorAlpha
        self.priorBeta = priorBeta
        self.dailyDecay = dailyDecay
    }

    private func key(_ bucket: String, _ archetype: Archetype) -> String {
        "\(bucket)|\(archetype.rawValue)"
    }

    /// Posterior mean for an arm -- what we currently believe the completion
    /// rate to be. Used for display and for the summary, not for selection.
    public func estimate(_ archetype: Archetype, bucket: String) -> Double {
        let k = key(bucket, archetype)
        let a = priorAlpha + (successes[k] ?? 0)
        let b = priorBeta + (failures[k] ?? 0)
        return a / (a + b)
    }

    /// How much evidence we have for an arm, in effective observations.
    public func confidence(_ archetype: Archetype, bucket: String) -> Double {
        let k = key(bucket, archetype)
        return (successes[k] ?? 0) + (failures[k] ?? 0)
    }

    public mutating func record(_ archetype: Archetype, bucket: String, completed: Bool) {
        let k = key(bucket, archetype)
        if completed {
            successes[k, default: 0] += 1
        } else {
            failures[k, default: 0] += 1
        }
    }

    /// Applies one day's forgetting. Called once per calendar day, not per launch.
    public mutating func decay(days: Int = 1) {
        guard days > 0 else { return }
        let factor = Foundation.pow(dailyDecay, Double(days))
        for k in successes.keys { successes[k]! *= factor }
        for k in failures.keys { failures[k]! *= factor }
    }

    /// Draws one sample from each arm's posterior and returns the argmax.
    ///
    /// `bias` nudges arms up or down before the comparison -- the caller uses
    /// it to express preferences the bandit cannot learn on its own, like
    /// "the user told us they care about movement" or "we just offered this
    /// one, don't repeat".
    public mutating func choose(
        from candidates: Set<Archetype>,
        bucket: String,
        bias: [Archetype: Double] = [:],
        rng: inout SeededRNG
    ) -> Archetype? {
        guard !candidates.isEmpty else { return nil }
        var best: Archetype?
        var bestScore = -Double.infinity
        // Iterate over allCases rather than the set so the draw order is
        // deterministic for a given seed; Set iteration order is not stable.
        for archetype in Archetype.allCases where candidates.contains(archetype) {
            let k = key(bucket, archetype)
            let a = priorAlpha + (successes[k] ?? 0)
            let b = priorBeta + (failures[k] ?? 0)
            let score = rng.beta(a, b) + (bias[archetype] ?? 0)
            if score > bestScore {
                bestScore = score
                best = archetype
            }
        }
        return best
    }
}
