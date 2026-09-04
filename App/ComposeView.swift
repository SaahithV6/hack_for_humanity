import SwiftUI

/// Writing your own task, with the keyboard doing as little work as possible.
///
/// This screen only exists once somebody has completed enough tasks to have
/// found a rhythm. The point of behavioural activation is that the person
/// eventually schedules their own activity -- but typing a sentence on a phone
/// at 11pm is real friction, so the predictor turns it into taps: a phrase
/// from the model's memory, then next-word chips until the sentence is done.
struct ComposeView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var archetype: Archetype = .tend
    @FocusState private var focused: Bool

    private var predictions: (completions: [String], nextWords: [String]) {
        store.predictions(for: text)
    }

    var body: some View {
        ZStack {
            NightBackground()

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Your own")
                        .font(Theme.title)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .font(Theme.label)
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.top, 28)

                field
                suggestions
                domainPicker

                Spacer()

                Button("Give it to me") { submit() }
                    .buttonStyle(LampButtonStyle())
                    .disabled(text.trimmingCharacters(in: .whitespaces).count < 3)
                    .opacity(text.trimmingCharacters(in: .whitespaces).count < 3 ? 0.4 : 1)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, Theme.gutter)
        }
        .onAppear { focused = true }
    }

    private var field: some View {
        TextField("", text: $text, axis: .vertical)
            .focused($focused)
            .font(Theme.task)
            .foregroundStyle(Theme.ink)
            .tint(Theme.lamp)
            .lineLimit(1...4)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.nightCard)
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("What's one small thing?")
                        .font(Theme.task)
                        .foregroundStyle(Theme.inkFaint)
                        .padding(18)
                        .allowsHitTesting(false)
                }
            }
    }

    /// Whole-phrase completions first, then next-word chips. The phrase row is
    /// what usually finishes the job in one tap.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            let p = predictions

            if !p.completions.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(text.isEmpty ? "START WITH" : "FINISH IT")
                        .font(Theme.caption)
                        .tracking(1.1)
                        .foregroundStyle(Theme.inkFaint)
                    ForEach(p.completions.prefix(3), id: \.self) { completion in
                        Button {
                            // An empty field offers single starter words; a
                            // non-empty one offers the whole finished sentence.
                            text = text.isEmpty ? completion + " " : completion
                        } label: {
                            HStack {
                                Text(completion)
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.lamp)
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Theme.lamp.opacity(0.10))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !p.nextWords.isEmpty {
                HStack(spacing: 8) {
                    ForEach(p.nextWords.prefix(3), id: \.self) { word in
                        Button {
                            let needsSpace = !text.isEmpty && !text.hasSuffix(" ")
                            text += (needsSpace ? " " : "") + word + " "
                        } label: {
                            Text(word)
                                .font(Theme.label)
                                .foregroundStyle(Theme.inkSoft)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Theme.nightCard))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: text)
    }

    private var domainPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KIND")
                .font(Theme.caption)
                .tracking(1.1)
                .foregroundStyle(Theme.inkFaint)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Archetype.allCases, id: \.self) { option in
                        Button { archetype = option } label: {
                            HStack(spacing: 5) {
                                Text(option.glyph).font(.system(size: 13))
                                Text(option.displayName).font(Theme.caption)
                            }
                            .foregroundStyle(archetype == option
                                             ? Theme.tint(for: option) : Theme.inkSoft)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(archetype == option
                                               ? Theme.tint(for: option).opacity(0.18)
                                               : Theme.nightCard)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func submit() {
        // A nil result means it was accepted; a non-nil risk means the safety
        // gate caught something and the store has already surfaced resources.
        if store.addUserTask(text: text, archetype: archetype) == nil {
            dismiss()
        } else {
            dismiss()
        }
    }
}

#Preview {
    ComposeView().environmentObject(Store.preview(.groove))
}
