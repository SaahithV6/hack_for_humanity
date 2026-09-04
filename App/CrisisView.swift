import SwiftUI

/// Shown when the intake screen or a typed task indicates crisis.
///
/// Deliberately the plainest screen in the app: no buddy, no animation, no
/// streak, no gamification of any kind. Three phone numbers and a way out.
struct CrisisView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Hey.")
                        .font(Theme.title)
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 40)

                    Text(Safety.crisisMessage)
                        .font(Theme.body)
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 12) {
                        ForEach(Safety.resources) { resource in
                            resourceCard(resource)
                        }
                    }

                    Button("I'm okay for now") {
                        store.acknowledgeCrisis()
                    }
                    .buttonStyle(LampButtonStyle(prominent: false))
                    .padding(.top, 8)

                    Text("Moth isn't a crisis service and doesn't replace one. Nothing you type here is sent anywhere.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkFaint)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private func resourceCard(_ resource: SafetyResource) -> some View {
        Button {
            if let url = URL(string: resource.action) { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(resource.name)
                    .font(Theme.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(resource.detail)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(resource.actionLabel)
                    .font(Theme.label)
                    .foregroundStyle(Theme.lamp)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.nightCard)
            )
        }
        .buttonStyle(.plain)
    }
}
