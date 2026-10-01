import SwiftUI

/// Authentication gate for the whole app. Until the user is signed in, the only
/// thing they can reach is the full-screen `AuthView`; the tabbed app appears once
/// `SessionModel` reports a signed-in state. Uses the shared session from the
/// environment so signing out (from Profile) returns here.
struct RootView: View {
    @Environment(SessionModel.self) private var session
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    /// Drives the splash overlay: it stays up until the session is resolved AND a
    /// minimum display time has passed, then fades away.
    @State private var splashVisible = true
    @State private var minimumTimeElapsed = false

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    /// True once the launch auth check has produced a definite state.
    private var sessionResolved: Bool {
        if case .unknown = session.state { return false }
        return true
    }

    var body: some View {
        ZStack {
            Group {
                switch session.state {
                case .signedIn:
                    MainTabView()
                case .signedOut, .confirming:
                    AuthView(session: session, isModal: false)
                case .unknown:
                    // Covered by the splash until the session resolves.
                    AuthBackground()
                }
            }

            // Kept mounted and faded via opacity so the dismissal is a smooth
            // animation rather than an abrupt removal.
            splash
                .opacity(splashVisible ? 1 : 0)
                .allowsHitTesting(splashVisible)
        }
        .preferredColorScheme(appearance.colorScheme)
        .task { await session.refresh() }
        .task {
            // Guarantee the brand splash is shown for at least two seconds.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            minimumTimeElapsed = true
            updateSplashVisibility()
        }
        .onChange(of: session.state) { updateSplashVisibility() }
    }

    /// Fades the splash out once the session is known and the minimum time has
    /// elapsed, so it never flashes away abruptly on a fast launch.
    private func updateSplashVisibility() {
        guard splashVisible, sessionResolved, minimumTimeElapsed else { return }
        withAnimation(.easeInOut(duration: 0.8)) {
            splashVisible = false
        }
    }

    /// Brief branded loading state while the existing session is resolved on launch —
    /// styled to match the sign-in onboarding.
    private var splash: some View {
        ZStack {
            AuthBackground()

            VStack(spacing: 0) {
                Spacer()
                BrandMark()
                Spacer().frame(height: 28)
                VStack(spacing: 8) {
                    Text("Welcome to My Lifestyle")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Elevate your well-being, find balance, and embrace joy.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                Spacer()
                LoadingDots()
                    .padding(.bottom, 60)
            }
        }
    }
}
