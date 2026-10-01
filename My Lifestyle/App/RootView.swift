import SwiftUI

/// Authentication gate for the whole app. Until the user is signed in, the only
/// thing they can reach is the full-screen `AuthView`; the tabbed app appears once
/// `SessionModel` reports a signed-in state. Uses the shared session from the
/// environment so signing out (from Profile) returns here.
struct RootView: View {
    @Environment(SessionModel.self) private var session
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        Group {
            switch session.state {
            case .signedIn:
                MainTabView()
            case .unknown:
                splash
            case .signedOut, .confirming:
                AuthView(session: session, isModal: false)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task { await session.refresh() }
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
