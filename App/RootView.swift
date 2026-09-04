import SwiftUI

/// Routes between the four states the app can be in. Crisis outranks
/// everything: if the intake or a typed task tripped the gate, that screen
/// comes first and the rest of the app waits.
struct RootView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            NightBackground()

            switch store.phase {
            case .onboarding:
                OnboardingView()
                    .transition(.opacity)
            case .guided, .groove:
                HomeView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.phase)
        .sheet(isPresented: $store.showingCrisis) {
            CrisisView()
                .interactiveDismissDisabled(true)
        }
        .fullScreenCover(isPresented: $store.showingBedtime) {
            BedtimeView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Coming back to the app after bedtime has passed is exactly the
            // moment to interrupt -- they have almost certainly just been
            // somewhere else on the phone.
            if newPhase == .active, store.isBedtime, store.phase != .onboarding {
                store.showingBedtime = true
            }
        }
    }
}
