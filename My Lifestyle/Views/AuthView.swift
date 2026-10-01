import SwiftUI
import Amplify

/// Email + password sign-up / confirm / sign-in screen backed by `SessionModel`,
/// styled as a modern food-app onboarding: a warm mesh-gradient hero with the brand
/// mark, over a frosted form card.
struct AuthView: View {
    @Bindable var session: SessionModel
    /// When true (the default) the view is a dismissible sheet and shows a close
    /// button. As the launch gate (`isModal: false`) it fills the screen with no way
    /// to dismiss — the user must sign in to proceed.
    var isModal: Bool = true
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable {
        case signIn = "Sign In"
        case signUp = "Sign Up"
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmationCode = ""

    var body: some View {
        ZStack(alignment: .top) {
            AuthBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    hero
                    formCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(session.isWorking)

            if isModal {
                closeButton
            }

            if session.isWorking {
                loadingOverlay
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            BrandMark()
                .padding(.top, isModal ? 24 : 64)

            VStack(spacing: 6) {
                Text(mode == .signUp ? "Create your account" : "Welcome back")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Eat well, move more, feel great.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    // MARK: - Form card

    private var formCard: some View {
        VStack(spacing: 18) {
            if case .confirming(let email) = session.state {
                confirmationSection(email: email)
            } else {
                credentialsSection
            }

            if let error = session.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.danger.opacity(0.12))
                    )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        )
    }

    @ViewBuilder
    private var credentialsSection: some View {
        SegmentedSelector(
            options: Mode.allCases.map { (value: $0, label: $0.rawValue) },
            selection: $mode
        )

        VStack(spacing: 12) {
            AuthField(icon: "envelope.fill", placeholder: "Email", text: $email, isEmail: true)
            AuthField(icon: "lock.fill", placeholder: "Password", text: $password, isSecure: true)

            if mode == .signUp {
                Text("Password needs 8+ characters with upper, lower, number, and symbol.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        Button(mode == .signUp ? "Create Account" : "Sign In") {
            Task {
                switch mode {
                case .signIn: await session.signIn(email: email, password: password)
                case .signUp: await session.signUp(email: email, password: password)
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: !(email.isEmpty || password.isEmpty)))
        .disabled(email.isEmpty || password.isEmpty)

        socialSection
    }

    @ViewBuilder
    private var socialSection: some View {
        HStack(spacing: 10) {
            divider
            Text("or continue with")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize()
            divider
        }

        HStack(spacing: 12) {
            SocialLoginButton {
                Task { await session.signInWithSocial(.apple) }
            } label: {
                Image(systemName: "applelogo")
                    .font(.system(size: 16, weight: .semibold))
                Text("Apple")
            }

            SocialLoginButton {
                Task { await session.signInWithSocial(.google) }
            } label: {
                Text("G")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                Text("Google")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.secondaryText.opacity(0.25))
            .frame(height: 1)
    }

    @ViewBuilder
    private func confirmationSection(email: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.accent)
            Text("Check your email")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            Text("We sent a confirmation code to \(email).")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)

        AuthField(icon: "number", placeholder: "Confirmation code", text: $confirmationCode)

        Button("Confirm & Sign In") {
            Task {
                await session.confirmSignUp(
                    email: email,
                    code: confirmationCode,
                    password: password
                )
            }
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: !confirmationCode.isEmpty))
        .disabled(confirmationCode.isEmpty)
    }

    // MARK: - Overlays

    private var closeButton: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var loadingOverlay: some View {
        ProgressView()
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AuthView(session: SessionModel(), isModal: false)
}
