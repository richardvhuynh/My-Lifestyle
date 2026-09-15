import SwiftUI

struct ProfileView: View {
    @State private var session = SessionModel()
    @State private var showingAuth = false
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        AppHeader(title: "Profile")

                        // Identity card
                        HStack(spacing: 14) {
                            Circle()
                                .fill(Theme.accentSoft)
                                .frame(width: 62, height: 62)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 26))
                                        .foregroundStyle(Theme.accentDark)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(displayName)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Theme.primaryText)
                                Text(statusText)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                        }
                        .card(padding: 18)

                        // Appearance
                        SectionBox(title: "Appearance") {
                            Picker("Appearance", selection: appearanceBinding) {
                                ForEach(AppAppearance.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // Goals
                        SectionBox(title: "Goals") {
                            VStack(spacing: 0) {
                                goalRow("Daily calorie goal", "2000 kcal")
                                RowDivider()
                                goalRow("Protein goal", "100 g")
                                RowDivider()
                                goalRow("Carb goal", "250 g")
                                RowDivider()
                                goalRow("Fat goal", "67 g")
                            }
                        }

                        // Backend
                        SectionBox(title: "Backend") {
                            NavigationLink {
                                TodoDemoView()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "cloud")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 24)
                                    Text("Cloud Todos (Amplify demo)")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        // Account
                        if case .signedIn = session.state {
                            Button("Sign Out") {
                                Task { await session.signOut() }
                            }
                            .buttonStyle(SecondaryButtonStyle(tint: Theme.danger))
                        } else {
                            Button("Sign In / Sign Up") {
                                showingAuth = true
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await session.refresh() }
        .sheet(isPresented: $showingAuth) {
            AuthView(session: session)
        }
        .onChange(of: session.state) {
            if case .signedIn = session.state { showingAuth = false }
        }
    }

    private func goalRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 8)
    }

    private var displayName: String {
        if case .signedIn(let email) = session.state {
            return email
        }
        return "Guest"
    }

    private var statusText: String {
        switch session.state {
        case .signedIn: return "Signed in"
        case .confirming: return "Confirmation pending"
        case .signedOut: return "Not signed in"
        case .unknown: return "Checking…"
        }
    }
}

#Preview {
    ProfileView()
}
