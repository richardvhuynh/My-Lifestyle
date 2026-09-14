import Foundation
import Amplify

/// Observable wrapper around Amplify Auth (Cognito) for a simple
/// email + password sign-up / confirm / sign-in flow.
@MainActor
@Observable
final class SessionModel {

    enum AuthState: Equatable {
        case unknown
        case signedOut
        /// Sign-up succeeded but the email still needs a confirmation code.
        case confirming(email: String)
        case signedIn(email: String)
    }

    var state: AuthState = .unknown
    var errorMessage: String?
    var isWorking = false

    /// Resolves the current session on launch so the UI shows the right state.
    func refresh() async {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            if session.isSignedIn {
                let user = try? await Amplify.Auth.getCurrentUser()
                state = .signedIn(email: user?.username ?? "Signed in")
            } else {
                state = .signedOut
            }
        } catch {
            state = .signedOut
        }
    }

    func signUp(email: String, password: String) async {
        await perform {
            let result = try await Amplify.Auth.signUp(
                username: email,
                password: password,
                options: .init(userAttributes: [AuthUserAttribute(.email, value: email)])
            )
            if case .confirmUser = result.nextStep {
                self.state = .confirming(email: email)
            } else {
                await self.refresh()
            }
        }
    }

    func confirmSignUp(email: String, code: String, password: String) async {
        await perform {
            _ = try await Amplify.Auth.confirmSignUp(for: email, confirmationCode: code)
            await self.signIn(email: email, password: password)
        }
    }

    func signIn(email: String, password: String) async {
        await perform {
            let result = try await Amplify.Auth.signIn(username: email, password: password)
            if result.isSignedIn {
                self.state = .signedIn(email: email)
            } else {
                self.errorMessage = "Additional step required: \(result.nextStep)"
            }
        }
    }

    func signOut() async {
        _ = await Amplify.Auth.signOut()
        state = .signedOut
    }

    /// Runs an async auth call with shared loading + error handling.
    private func perform(_ work: @escaping () async throws -> Void) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
        }
    }
}
