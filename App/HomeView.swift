import SwiftUI

/// The main screen: one task, two answers.
///
/// The screen shows exactly one task at a time. A list would let somebody
/// scan, compare, and pick nothing, which is the same paralysis the feed
/// causes -- and a list of undone tasks is a list of small failures.
struct HomeView: View {
    @EnvironmentObject private var store: Store
    @State private var showingCompose = false
    @State private var showingLearned = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Spacer(minLength: 8)

            MothBuddy(mood: store.buddyMood, size: 132)
                .padding(.bottom, 6)

            speech
                .padding(.horizontal, Theme.gutter)
                .frame(minHeight: 52)

            Spacer(minLength: 8)

            if let completed = store.lastCompleted {
                completionCard(completed)
                    .padding(.horizontal, Theme.gutter)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            } else if let task = store.currentTask {
                taskCard(task)
                    .padding(.horizontal, Theme.gutter)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .id(task.id)
            } else {
                emptyCard
                    .padding(.horizontal, Theme.gutter)
            }

            Spacer(minLength: 12)

            actions
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 20)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.currentTask?.id)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.lastCompleted?.id)
        .sheet(isPresented: $showingCompose) { ComposeView() }
        .sheet(isPresented: $showingLearned) { LearnedView() }
        .onAppear {
            if store.currentTask == nil && store.lastCompleted == nil { store.nextTask() }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.todayCompleted == 0
                     ? "Nothing yet today"
                     : "\(store.todayCompleted) done today")
                    .font(Theme.label)
                    .foregroundStyle(Theme.ink)
                if store.streak > 0 {
                    Text("\(store.streak) day\(store.streak == 1 ? "" : "s") in a row")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkFaint)
                }
            }

            Spacer()

            Button {
                showingLearned = true
            } label: {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }

            bedtimePill
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
    }

    private var bedtimePill: some View {
        let minutes = store.minutesToBedtime
        let label: String
        if minutes <= 0 {
            label = "past bedtime"
        } else if minutes < 60 {
            label = "\(minutes)m to bed"
        } else {
            label = "\(minutes / 60)h to bed"
        }
        return Text(label)
            .font(Theme.caption)
            .foregroundStyle(minutes <= 45 ? Theme.lamp : Theme.inkFaint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(minutes <= 45 ? Theme.lamp.opacity(0.14) : Theme.nightCard)
            )
            .padding(.leading, 10)
    }

    // MARK: Buddy speech

    private var speech: some View {
        Text(speechText)
            .font(Theme.body)
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
            .id(speechText)
    }

    private var speechText: String {
        if store.lastCompleted != nil { return "There it is." }
        if store.minutesToBedtime <= 45 { return "Winding down. Small things only." }
        if store.todayCompleted == 0 { return "Let's start with something small." }
        if store.phase == .groove { return "Want one from me, or one of your own?" }
        return "Here's the next one."
    }

    // MARK: Cards

    private func taskCard(_ task: MothTask) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(task.archetype.glyph).font(.system(size: 15))
                Text(task.archetype.displayName.uppercased())
                    .font(Theme.caption)
                    .tracking(1.1)
                    .foregroundStyle(Theme.tint(for: task.archetype))
                Spacer()
                Text("~\(task.estimatedMinutes) min")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkFaint)
                if task.origin == .user {
                    Text("YOURS")
                        .font(Theme.caption)
                        .tracking(1.1)
                        .foregroundStyle(Theme.lamp)
                }
            }

            Text(task.text)
                .font(Theme.task)
                .foregroundStyle(Theme.ink)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.nightCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Theme.tint(for: task.archetype).opacity(0.28), lineWidth: 1)
        )
    }

    private func completionCard(_ task: MothTask) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.done)
            Text(task.text)
                .font(Theme.body)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.done.opacity(0.10))
        )
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Text("Nothing left that fits right now.")
                .font(Theme.body)
                .foregroundStyle(Theme.inkSoft)
            Text("That's allowed.")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        if store.lastCompleted != nil {
            // Nothing to press while the completion is on screen. The pause is
            // the point.
            Color.clear.frame(height: 108)
        } else if store.currentTask != nil {
            VStack(spacing: 10) {
                Button("Done") {
                    if let task = store.currentTask { store.complete(task) }
                }
                .buttonStyle(LampButtonStyle())

                HStack(spacing: 10) {
                    Button("Not this one") {
                        if let task = store.currentTask { store.skip(task) }
                    }
                    .buttonStyle(LampButtonStyle(prominent: false))

                    if store.phase == .groove {
                        Button("Write my own") { showingCompose = true }
                            .buttonStyle(LampButtonStyle(prominent: false))
                    }
                }

                rescueButton
            }
        } else {
            Button("Ask Moth for something") { store.nextTask() }
                .buttonStyle(LampButtonStyle())
        }
    }

    private var rescueButton: some View {
        Button {
            store.rescue()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.uturn.down")
                    .font(.system(size: 12, weight: .semibold))
                Text("I'm stuck scrolling")
            }
            .font(Theme.label)
            .foregroundStyle(Theme.lamp)
        }
        .padding(.top, 4)
    }
}

/// Shows the user their own model back to them.
///
/// This is the transparency half of "responsible AI": the app personalises,
/// so the user gets to see precisely what it inferred and how sure it is.
struct LearnedView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingErase = false

    var body: some View {
        ZStack {
            NightBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("What Moth has figured out")
                        .font(Theme.title)
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 34)

                    Text("Right now, around this time of day. It updates every time you answer, and it slowly forgets old evidence.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)

                    if store.learned.isEmpty {
                        Text("Not enough yet. Answer a few tasks and this fills in.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 14) {
                            ForEach(store.learned) { entry in
                                row(entry.archetype, rate: entry.rate,
                                    evidence: entry.evidence)
                            }
                        }
                    }

                    Divider().background(Theme.inkFaint.opacity(0.3))

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Nothing leaves this phone", systemImage: "lock.fill")
                            .font(Theme.label)
                            .foregroundStyle(Theme.done)
                        Text("Moth has no network code in it at all. Your answers, your tasks and this model live in one file in the app's own storage.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Delete everything") { confirmingErase = true }
                        .buttonStyle(LampButtonStyle(prominent: false))

                    Button("Close") { dismiss() }
                        .font(Theme.label)
                        .foregroundStyle(Theme.inkFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
        .alert("Delete everything?", isPresented: $confirmingErase) {
            Button("Delete", role: .destructive) {
                store.eraseAllData()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your history, your streak and everything Moth learned. This can't be undone.")
        }
    }

    private func row(_ archetype: Archetype, rate: Double, evidence: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(archetype.glyph)
                Text(archetype.displayName)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int(rate * 100))%")
                    .font(Theme.label)
                    .foregroundStyle(Theme.tint(for: archetype))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.nightCard)
                    Capsule()
                        .fill(Theme.tint(for: archetype).opacity(0.75))
                        .frame(width: geo.size.width * rate)
                }
            }
            .frame(height: 6)
            Text("based on \(Int(evidence.rounded())) answer\(evidence < 1.5 ? "" : "s")")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkFaint)
        }
    }
}
