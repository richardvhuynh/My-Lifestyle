import SwiftUI

/// Email + password sign-up / confirm / sign-in screen backed by `SessionModel`.
struct AuthView: View {
    @Bindable var session: SessionModel
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
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Account")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Theme.surface))
                        }
                        .buttonStyle(.plain)
                    }

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
                                    .fill(Theme.danger.opacity(0.1))
                            )
                    }
                }
                .padding(20)
            }
            .disabled(session.isWorking)

            if session.isWorking {
                ProgressView()
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.surface)
                            .shadow(color: Theme.shadow, radius: 12, y: 6)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var credentialsSection: some View {
        SegmentedSelector(
            options: Mode.allCases.map { (value: $0, label: $0.rawValue) },
            selection: $mode
        )

        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textFieldStyle(RoundedFieldStyle())
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedFieldStyle())
                .textContentType(mode == .signUp ? .newPassword : .password)

            if mode == .signUp {
                Text("Password needs 8+ characters with upper, lower, number, and symbol.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        Button(mode.rawValue) {
            Task {
                switch mode {
                case .signIn: await session.signIn(email: email, password: password)
                case .signUp: await session.signUp(email: email, password: password)
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: !(email.isEmpty || password.isEmpty)))
        .disabled(email.isEmpty || password.isEmpty)
    }

    @ViewBuilder
    private func confirmationSection(email: String) -> some View {
        Text("We sent a confirmation code to \(email).")
            .font(.system(size: 15))
            .foregroundStyle(Theme.primaryText)

        TextField("Confirmation code", text: $confirmationCode)
            .textFieldStyle(RoundedFieldStyle())
            .keyboardType(.numberPad)

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
}
