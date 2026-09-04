import Foundation

/// Deterministic, seedable PRNG (SplitMix64).
///
/// Every stochastic part of the engine draws from this rather than the system
/// RNG so that a given (seed, context) pair always produces the same task.
/// That makes the whole generator unit-testable and lets us reproduce exactly
/// what a user saw when they report something odd.
public struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        // Avoid the all-zero state, which SplitMix64 handles fine but which
        // makes the first few draws look suspiciously patterned.
        self.state = seed &+ 0x9E3779B97F4A7C15
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func uniform() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Standard normal via Box-Muller. Used by the bandit's posterior sampling.
    public mutating func normal() -> Double {
        // Clamp away from zero so log() stays finite.
        let u1 = Swift.max(uniform(), 1e-12)
        let u2 = uniform()
        return (-2.0 * Foundation.log(u1)).squareRoot() * Foundation.cos(2.0 * Double.pi * u2)
    }

    /// Gamma(shape, 1) via Marsaglia-Tsang. Building block for Beta sampling.
    public mutating func gamma(shape: Double) -> Double {
        guard shape > 0 else { return 0 }
        if shape < 1 {
            // Boost a sub-unit shape into the valid range, then scale back.
            let g = gamma(shape: shape + 1)
            return g * Foundation.pow(Swift.max(uniform(), 1e-12), 1.0 / shape)
        }
        let d = shape - 1.0 / 3.0
        let c = 1.0 / (9.0 * d).squareRoot()
        while true {
            let x = normal()
            let v = 1.0 + c * x
            guard v > 0 else { continue }
            let v3 = v * v * v
            let u = Swift.max(uniform(), 1e-12)
            if Foundation.log(u) < 0.5 * x * x + d - d * v3 + d * Foundation.log(v3) {
                return d * v3
            }
        }
    }

    /// Beta(a, b) as the normalised ratio of two Gamma draws.
    public mutating func beta(_ a: Double, _ b: Double) -> Double {
        let x = gamma(shape: a)
        let y = gamma(shape: b)
        let total = x + y
        return total > 0 ? x / total : 0.5
    }

    /// Picks an index with probability proportional to its weight.
    /// Returns nil only for an empty or entirely non-positive weight vector.
    public mutating func weightedIndex(_ weights: [Double]) -> Int? {
        let total = weights.reduce(0) { $0 + Swift.max($1, 0) }
        guard total > 0 else { return nil }
        var target = uniform() * total
        for (i, w) in weights.enumerated() {
            target -= Swift.max(w, 0)
            if target <= 0 { return i }
        }
        return weights.indices.last
    }
}
