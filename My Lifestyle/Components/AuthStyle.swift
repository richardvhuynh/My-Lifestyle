import SwiftUI

/// Shared visual language for the splash + auth screens: a warm sunset-to-green
/// mesh gradient backdrop, the brand wordmark, animated loading dots, and a glassy
/// icon-led text field. Gives the onboarding a modern food-app feel.

/// Full-bleed organic gradient (warm at the top melting into the brand green),
/// used behind both the splash and the sign-in screen.
struct AuthBackground: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                Color(red: 1.00, green: 0.72, blue: 0.42), Color(red: 1.00, green: 0.56, blue: 0.40), Color(red: 0.98, green: 0.78, blue: 0.50),
                Color(red: 0.86, green: 0.55, blue: 0.40), Color(red: 0.32, green: 0.63, blue: 0.50), Color(red: 0.16, green: 0.68, blue: 0.55),
                Color(red: 0.10, green: 0.50, blue: 0.40), Color(red: 0.09, green: 0.54, blue: 0.36), Color(red: 0.07, green: 0.42, blue: 0.40)
            ]
        )
        .overlay(
            // Slight darkening toward the bottom keeps white text legible over the
            // lighter warm tones.
            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea()
    }
}

/// Stacked heart badge + wordmark, shown at the top of the onboarding screens.
struct BrandMark: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: compact ? 24 : 30, weight: .semibold))
                .foregroundStyle(Color(red: 1.00, green: 0.55, blue: 0.20))
                .frame(width: compact ? 52 : 68, height: compact ? 52 : 68)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                )
            Text("My Lifestyle")
                .font(.system(size: compact ? 22 : 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .tracking(1)
        }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

/// Three dots that pulse in sequence, for the splash "loading" affordance. Driven by
/// an async loop (no Combine timer, per the project's concurrency preference).
struct LoadingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .opacity(phase == index ? 1 : 0.35)
                    .scaleEffect(phase == index ? 1.2 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                phase = (phase + 1) % 3
            }
        }
    }
}

/// Recessed, icon-led field used on the auth card. Supports a secure mode with a
/// show/hide toggle.
struct AuthField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var isEmail = false

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)

            Group {
                if isSecure && !revealed {
                    SecureField(placeholder, text: $text)
                        .textContentType(.password)
                } else {
                    TextField(placeholder, text: $text)
                        .textContentType(isEmail ? .emailAddress : (isSecure ? .password : .none))
                        .keyboardType(isEmail ? .emailAddress : .default)
                        .textInputAutocapitalization(isEmail ? .never : .sentences)
                        .autocorrectionDisabled(isEmail)
                }
            }
            .font(.system(size: 16))
            .foregroundStyle(Theme.primaryText)
            .tint(Theme.accent)
            .focused($focused)

            if isSecure {
                Button { revealed.toggle() } label: {
                    Image(systemName: revealed ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .fill(Theme.surfaceAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .strokeBorder(focused ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5)
                )
        )
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// Full-width outlined button used for third-party sign-in (Apple / Google) on the
/// auth card. Takes an arbitrary label so each provider can supply its own glyph.
struct SocialLoginButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(Theme.surfaceAlt)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// Splash composition preview (mirrors RootView's splash).
#Preview {
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
            Spacer()
            LoadingDots()
                .padding(.bottom, 60)
        }
    }
}
