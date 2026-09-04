import SwiftUI

/// The bedtime read-back. This is the screen the whole app is pointed at.
///
/// It has exactly one button and it says goodnight. There is nothing to browse,
/// nothing to tap into, no tomorrow-view, no settings. An app that interrupts a
/// doomscroll and then offers somewhere else to go has not helped.
struct BedtimeView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var revealed = 0
    @State private var summary: Summary?

    var body: some View {
        ZStack {
            NightBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 30)

                MothBuddy(mood: store.buddyMood == .sleepy ? .sleepy : .pleased, size: 118)

                if let summary {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            Text(summary.greeting)
                                .font(Theme.title)
                                .foregroundStyle(Theme.ink)
                                .opacity(revealed >= 1 ? 1 : 0)
                                .offset(y: revealed >= 1 ? 0 : 8)

                            Text(summary.body)
                                .font(Theme.body)
                                .foregroundStyle(Theme.inkSoft)
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                                .opacity(revealed >= 2 ? 1 : 0)
                                .offset(y: revealed >= 2 ? 0 : 8)

                            if !summary.highlights.isEmpty {
                                VStack(alignment: .leading, spacing: 11) {
                                    ForEach(Array(summary.highlights.enumerated()),
                                            id: \.offset) { index, highlight in
                                        HStack(alignment: .top, spacing: 11) {
                                            Circle()
                                                .fill(Theme.lamp.opacity(0.8))
                                                .frame(width: 5, height: 5)
                                                .padding(.top, 8)
                                            Text(highlight)
                                                .font(Theme.body)
                                                .foregroundStyle(Theme.ink)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .opacity(revealed >= 3 + index ? 1 : 0)
                                        .offset(y: revealed >= 3 + index ? 0 : 8)
                                    }
                                }
                                .padding(.leading, 2)
                            }

                            stats(summary)
                                .opacity(revealed >= 6 ? 1 : 0)

                            Text(summary.closing)
                                .font(Theme.body.weight(.medium))
                                .foregroundStyle(Theme.lamp)
                                .opacity(revealed >= 7 ? 1 : 0)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 26)
                    }
                }

                Spacer(minLength: 12)

                Button("Goodnight") {
                    store.finishDay()
                    dismiss()
                }
                .buttonStyle(LampButtonStyle())
                .opacity(revealed >= 7 ? 1 : 0)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 30)
            }
        }
        .task {
            let local = store.bedtimeSummary()
            summary = local
            reveal()
            // Runs only if the user opted in. The local summary is already on
            // screen and already revealing; if a better-written one arrives
            // before the reveal finishes, it cross-fades in. If it doesn't,
            // nothing happens and nobody is told.
            if let better = await store.enrichedSummary(upgrading: local) {
                withAnimation(.easeInOut(duration: 0.45)) { summary = better }
            }
        }
    }

    private func stats(_ summary: Summary) -> some View {
        HStack(spacing: 0) {
            stat("\(summary.completedCount)", "done")
            divider
            stat("\(summary.minutes)", "minutes")
            if summary.streak > 0 {
                divider
                stat("\(summary.streak)", "day streak")
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.nightRaised)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.inkFaint.opacity(0.25))
            .frame(width: 1, height: 26)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }

    /// Reveals the summary a line at a time.
    ///
    /// This is the one place the app is deliberately slow. Dumping the whole
    /// summary at once makes it a receipt; letting it arrive line by line makes
    /// it feel like somebody telling you about your day, and gives the reader
    /// time to actually take in what they did.
    private func reveal() {
        for step in 1...7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.42) {
                withAnimation(.easeOut(duration: 0.5)) { revealed = step }
            }
        }
    }
}
