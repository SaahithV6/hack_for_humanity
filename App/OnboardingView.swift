import SwiftUI

/// Six questions, one per screen.
///
/// One question per screen rather than a scrolling form: a form of six
/// questions looks like work, and the population this is built for closes
/// anything that looks like work. A single question with a lot of space
/// around it reads as a conversation.
struct OnboardingView: View {
    @EnvironmentObject private var store: Store

    @State private var step = 0
    @State private var lowInterest = 0
    @State private var lowMood = 0
    @State private var selfHarm: Bool?
    @State private var baselineMood = 3
    @State private var cares: Set<Archetype> = []
    @State private var bedtime = Calendar.current.date(
        from: DateComponents(hour: 23, minute: 0)) ?? Date()

    private let lastStep = 6

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $step) {
                welcome.tag(0)
                frequency(
                    title: "Over the last two weeks, how often have you had little interest or pleasure in doing things?",
                    value: $lowInterest
                ).tag(1)
                frequency(
                    title: "And how often have you felt down, hopeless, or flat?",
                    value: $lowMood
                ).tag(2)
                selfHarmStep.tag(3)
                moodStep.tag(4)
                caresStep.tag(5)
                bedtimeStep.tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: step)

            footer
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(0...lastStep, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Theme.lamp : Theme.inkFaint.opacity(0.3))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
        .animation(.easeOut(duration: 0.25), value: step)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button(step == lastStep ? "Start" : "Next") {
                if step == lastStep {
                    finish()
                } else {
                    withAnimation { step += 1 }
                }
            }
            .buttonStyle(LampButtonStyle())
            .disabled(!canAdvance)
            .opacity(canAdvance ? 1 : 0.4)

            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 28)
    }

    private var canAdvance: Bool {
        switch step {
        case 3: return selfHarm != nil
        case 5: return !cares.isEmpty
        default: return true
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 26) {
            Spacer()
            MothBuddy(mood: .idle, size: 150)
            Text("This is Moth.")
                .font(Theme.display)
                .foregroundStyle(Theme.ink)
            Text("""
                 It gives you one small thing to do at a time, and at bedtime it tells you what you did.

                 Six questions first. Everything you answer stays on this phone.
                 """)
                .font(Theme.body)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 8)
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func frequency(title: String, value: Binding<Int>) -> some View {
        stepScaffold(title: title) {
            VStack(spacing: 10) {
                ForEach(Array(["Not at all", "Several days",
                               "More than half the days", "Nearly every day"].enumerated()),
                        id: \.offset) { index, label in
                    choice(label, selected: value.wrappedValue == index) {
                        value.wrappedValue = index
                    }
                }
            }
        }
    }

    private var selfHarmStep: some View {
        stepScaffold(
            title: "In the last two weeks, have you had thoughts of hurting yourself?",
            note: "There's no wrong answer, and this doesn't lock you out of anything."
        ) {
            VStack(spacing: 10) {
                choice("No", selected: selfHarm == false) { selfHarm = false }
                choice("Yes", selected: selfHarm == true) { selfHarm = true }
            }
        }
    }

    private var moodStep: some View {
        stepScaffold(title: "On an ordinary day lately, where are you?") {
            VStack(spacing: 10) {
                ForEach(Array(["Flattened", "Low", "Okay", "Decent", "Good"].enumerated()),
                        id: \.offset) { index, label in
                    choice(label, selected: baselineMood == index + 1) {
                        baselineMood = index + 1
                    }
                }
            }
        }
    }

    private var caresStep: some View {
        stepScaffold(
            title: "What's worth doing, on a good day?",
            note: "Pick any. Moth uses this as a starting guess and corrects itself from there."
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Archetype.allCases, id: \.self) { archetype in
                    Button {
                        if cares.contains(archetype) { cares.remove(archetype) }
                        else { cares.insert(archetype) }
                    } label: {
                        VStack(spacing: 6) {
                            Text(archetype.glyph).font(.system(size: 26))
                            Text(archetype.displayName)
                                .font(Theme.label)
                                .foregroundStyle(Theme.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(cares.contains(archetype)
                                      ? Theme.tint(for: archetype).opacity(0.22)
                                      : Theme.nightCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(cares.contains(archetype)
                                              ? Theme.tint(for: archetype).opacity(0.7)
                                              : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var bedtimeStep: some View {
        stepScaffold(
            title: "When do you want to be asleep?",
            note: "Moth will interrupt you then, whatever you're in the middle of."
        ) {
            DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorInvert()
                .colorMultiply(Theme.ink)
        }
    }

    // MARK: Building blocks

    private func stepScaffold<Content: View>(
        title: String,
        note: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(title)
                    .font(Theme.title)
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 44)

                if let note {
                    Text(note)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content()
                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
        }
    }

    private func choice(_ label: String, selected: Bool, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if selected {
                    Circle().fill(Theme.lamp).frame(width: 9, height: 9)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Theme.lamp.opacity(0.14) : Theme.nightCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.lamp.opacity(0.6) : Color.clear,
                                  lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func finish() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
        let bedtimeMinutes = (components.hour ?? 23) * 60 + (components.minute ?? 0)
        let intake = Intake(
            lowInterestDays: lowInterest,
            lowMoodDays: lowMood,
            hasSelfHarmThoughts: selfHarm ?? false,
            baselineMood: baselineMood,
            caresAbout: cares,
            bedtimeMinutes: bedtimeMinutes,
            // Assume the scroll starts about an hour before they mean to sleep.
            scrollStartMinutes: max(0, bedtimeMinutes - 60)
        )
        store.requestNotificationPermission()
        store.completeOnboarding(intake)
    }
}

#Preview {
    OnboardingView().environmentObject(Store.preview(.onboarding))
        .background(NightBackground())
}
