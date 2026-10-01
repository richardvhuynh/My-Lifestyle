import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Environment(SessionModel.self) private var session
    @State private var showingAuth = false
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    // User-editable profile. Stored locally so the Diary and Profile screens
    // share the same values.
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("profileImageData") private var profileImageData: Data?

    // Daily goals — shared with DiaryView via the same AppStorage keys.
    @AppStorage("goalCalories") private var calorieGoal = 2000
    @AppStorage("goalProtein") private var proteinGoal = 100.0
    @AppStorage("goalCarbs") private var carbGoal = 250.0
    @AppStorage("goalFat") private var fatGoal = 67.0

    // Editing state for the name and the profile photo.
    @State private var photoItem: PhotosPickerItem?
    @State private var editingName = false
    @State private var nameDraft = ""

    // Editing state for a single goal via an alert.
    @State private var editingGoal: GoalField?
    @State private var goalDraft = ""

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

                        identityCard

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
                                goalRow(.calories)
                                RowDivider()
                                goalRow(.protein)
                                RowDivider()
                                goalRow(.carbs)
                                RowDivider()
                                goalRow(.fat)
                            }
                        }

                        // Social
                        SectionBox(title: "Social") {
                            NavigationLink {
                                FriendsView()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 24)
                                    Text("Friends")
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
        .onChange(of: photoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    profileImageData = data
                }
            }
        }
        .alert("Display Name", isPresented: $editingName) {
            TextField("Name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                profileName = nameDraft.trimmingCharacters(in: .whitespaces)
            }
        } message: {
            Text("Enter the name shown on your profile.")
        }
        .alert(editingGoal?.title ?? "Goal", isPresented: goalAlertPresented) {
            TextField("Value", text: $goalDraft)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveGoal() }
        } message: {
            if let unit = editingGoal?.unit {
                Text("Enter your daily goal in \(unit).")
            }
        }
    }

    // MARK: - Identity

    private var identityCard: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                avatar
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.accent))
                            .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                Text(statusText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button {
                nameDraft = profileName
                editingName = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.accentSoft))
            }
            .buttonStyle(.plain)
        }
        .card(padding: 18)
    }

    @ViewBuilder
    private var avatar: some View {
        if let data = profileImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 62, height: 62)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Theme.accentSoft)
                .frame(width: 62, height: 62)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.accentDark)
                )
        }
    }

    // MARK: - Goals

    private enum GoalField: Identifiable {
        case calories, protein, carbs, fat
        var id: Self { self }

        var title: String {
            switch self {
            case .calories: return "Daily calorie goal"
            case .protein: return "Protein goal"
            case .carbs: return "Carb goal"
            case .fat: return "Fat goal"
            }
        }

        var unit: String {
            switch self {
            case .calories: return "kcal"
            default: return "grams"
            }
        }
    }

    private var goalAlertPresented: Binding<Bool> {
        Binding(
            get: { editingGoal != nil },
            set: { if !$0 { editingGoal = nil } }
        )
    }

    private func goalValueString(_ field: GoalField) -> String {
        switch field {
        case .calories: return "\(calorieGoal) kcal"
        case .protein: return "\(Int(proteinGoal)) g"
        case .carbs: return "\(Int(carbGoal)) g"
        case .fat: return "\(Int(fatGoal)) g"
        }
    }

    private func goalDraftValue(_ field: GoalField) -> String {
        switch field {
        case .calories: return "\(calorieGoal)"
        case .protein: return "\(Int(proteinGoal))"
        case .carbs: return "\(Int(carbGoal))"
        case .fat: return "\(Int(fatGoal))"
        }
    }

    private func saveGoal() {
        guard let field = editingGoal else { return }
        switch field {
        case .calories: calorieGoal = Int(goalDraft) ?? calorieGoal
        case .protein: proteinGoal = Double(goalDraft) ?? proteinGoal
        case .carbs: carbGoal = Double(goalDraft) ?? carbGoal
        case .fat: fatGoal = Double(goalDraft) ?? fatGoal
        }
        editingGoal = nil
    }

    private func goalRow(_ field: GoalField) -> some View {
        Button {
            goalDraft = goalDraftValue(field)
            editingGoal = field
        } label: {
            HStack {
                Text(field.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text(goalValueString(field))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.6))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayName: String {
        let trimmed = profileName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
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
        .environment(SessionModel())
}
