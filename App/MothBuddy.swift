import SwiftUI

/// Moth's moods. The buddy is the app's whole personality, and its job is to
/// make the summary at the end feel like it came from someone.
enum MothMood {
    case idle
    case pleased
    case sleepy
    case listening
}

/// The buddy, drawn entirely in vectors.
///
/// No image assets on purpose: it scales to any screen, costs nothing in the
/// bundle, and can be animated per-part. The wings drift on a slow sine so it
/// reads as breathing rather than looping.
struct MothBuddy: View {
    var mood: MothMood = .idle
    var size: CGFloat = 160

    @State private var flutter: CGFloat = 0
    @State private var blink: Bool = false
    @State private var bob: CGFloat = 0

    private var wingSpread: CGFloat {
        switch mood {
        case .idle: return 1.0
        case .pleased: return 1.14
        case .sleepy: return 0.82
        case .listening: return 0.95
        }
    }

    var body: some View {
        ZStack {
            // Lamplight halo. Brightest when pleased, almost out when sleepy.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.lamp.opacity(mood == .sleepy ? 0.10 : 0.22),
                                 Theme.lamp.opacity(0)],
                        center: .center, startRadius: 0, endRadius: size * 0.72
                    )
                )
                .frame(width: size * 1.6, height: size * 1.6)

            wing(side: -1)
            wing(side: 1)
            body_
            antennae
            face
        }
        .frame(width: size, height: size)
        .offset(y: bob)
        .onAppear { startAnimating() }
    }

    // MARK: Parts

    private func wing(side: CGFloat) -> some View {
        // Two overlapping ellipses per side: a big upper wing and a smaller
        // lower one, which is roughly how a real moth reads in silhouette.
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Theme.lamp.opacity(0.55), Theme.lampDim.opacity(0.30)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: size * 0.46, height: size * 0.62)
                .offset(x: side * size * 0.20, y: -size * 0.04)
            Ellipse()
                .fill(Theme.lampDim.opacity(0.34))
                .frame(width: size * 0.34, height: size * 0.40)
                .offset(x: side * size * 0.19, y: size * 0.17)
        }
        .rotationEffect(.degrees(Double(side) * (18 + flutter * 12) * Double(wingSpread)),
                        anchor: .center)
        .scaleEffect(x: wingSpread, y: 1, anchor: .center)
        .animation(.easeInOut(duration: 0.5), value: mood)
    }

    private var body_: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Theme.ink.opacity(0.92), Theme.ink.opacity(0.74)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: size * 0.21, height: size * 0.50)
    }

    private var antennae: some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                Path { p in
                    let origin = CGPoint(x: size * 0.5, y: size * 0.32)
                    p.move(to: origin)
                    p.addQuadCurve(
                        to: CGPoint(x: size * 0.5 + side * size * 0.20, y: size * 0.10),
                        control: CGPoint(x: size * 0.5 + side * size * 0.05, y: size * 0.14)
                    )
                }
                .stroke(Theme.ink.opacity(0.78), style: .init(lineWidth: size * 0.018,
                                                              lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(side * flutter * 3), anchor: .center)
            }
        }
    }

    private var face: some View {
        VStack(spacing: size * 0.045) {
            HStack(spacing: size * 0.075) {
                eye
                eye
            }
            mouth
        }
        .offset(y: -size * 0.035)
    }

    private var eye: some View {
        Group {
            if mood == .sleepy || blink {
                // A closed eye is a short arc, not a line -- a flat line reads
                // as dead rather than asleep.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size * 0.018))
                    p.addQuadCurve(to: CGPoint(x: size * 0.055, y: size * 0.018),
                                   control: CGPoint(x: size * 0.0275, y: -size * 0.012))
                }
                .stroke(Theme.night, style: .init(lineWidth: size * 0.016, lineCap: .round))
                .frame(width: size * 0.055, height: size * 0.045)
            } else {
                Circle()
                    .fill(Theme.night)
                    .frame(width: size * 0.05, height: size * 0.05)
            }
        }
    }

    private var mouth: some View {
        Group {
            switch mood {
            case .pleased:
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addQuadCurve(to: CGPoint(x: size * 0.07, y: 0),
                                   control: CGPoint(x: size * 0.035, y: size * 0.035))
                }
                .stroke(Theme.night.opacity(0.8),
                        style: .init(lineWidth: size * 0.014, lineCap: .round))
                .frame(width: size * 0.07, height: size * 0.03)
            case .sleepy:
                Circle()
                    .fill(Theme.night.opacity(0.55))
                    .frame(width: size * 0.022, height: size * 0.022)
            default:
                Capsule()
                    .fill(Theme.night.opacity(0.5))
                    .frame(width: size * 0.04, height: size * 0.012)
            }
        }
        .animation(.easeOut(duration: 0.25), value: mood)
    }

    // MARK: Animation

    private func startAnimating() {
        withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
            flutter = 1
        }
        withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
            bob = -6
        }
        scheduleBlink()
    }

    /// Irregular blink interval. A metronomic blink is uncanny; a random one
    /// reads as alive.
    private func scheduleBlink() {
        let delay = Double.random(in: 2.4...6.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard mood != .sleepy else { scheduleBlink(); return }
            withAnimation(.easeInOut(duration: 0.09)) { blink = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.easeInOut(duration: 0.09)) { blink = false }
                scheduleBlink()
            }
        }
    }
}

#Preview("Moods") {
    ZStack {
        NightBackground()
        VStack(spacing: 36) {
            MothBuddy(mood: .idle, size: 130)
            HStack(spacing: 30) {
                MothBuddy(mood: .pleased, size: 100)
                MothBuddy(mood: .sleepy, size: 100)
                MothBuddy(mood: .listening, size: 100)
            }
        }
    }
}
