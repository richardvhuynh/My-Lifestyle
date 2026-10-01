import SwiftUI

/// A look at another member's fitness: their seven-day step chart and ranged
/// activity graph. Fitness is **friends-only** — the server only returns a member's
/// `FitnessProfile` to their accepted friends, and this screen reflects that by
/// gating the charts behind a friend request flow. Presented when a member is
/// tapped in the Community feed.
struct UserProfileView: View {
    let memberName: String
    /// The member's owner-identity, used to fetch their profile and to grant/record
    /// friendship. Nil for sample authors with no real account.
    let userId: String?

    @Environment(\.dismiss) private var dismiss

    @State private var shared: SharedFitness?
    @State private var relation: FriendshipService.Relation = .none
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var loadFailed = false

    /// Whether the signed-in user is allowed to see this member's fitness.
    private var canViewFitness: Bool {
        relation == .friends || relation == .selfUser
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    header

                    if isLoading {
                        loadingCard
                    } else if userId == nil {
                        emptyCard
                    } else if !canViewFitness {
                        friendGateCard
                    } else if let shared, hasData(shared) {
                        SectionBox(title: "Steps · last 7 days") {
                            StepsWeekChart(data: shared.weeklySteps)
                        }
                        SectionBox(title: "Activity history") {
                            ActivityGraphCard(activities: shared.activities)
                        }
                    } else {
                        emptyCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .task(id: userId) { await load() }
    }

    private func hasData(_ shared: SharedFitness) -> Bool {
        !shared.weeklySteps.isEmpty || !shared.activities.isEmpty
    }

    private func load() async {
        guard let userId else {
            isLoading = false
            return
        }
        isLoading = true
        loadFailed = false
        relation = (try? await FriendshipService.relation(withUsername: memberName)) ?? .none
        if canViewFitness {
            do {
                shared = try await FitnessCloudService.fetch(userId: userId)
            } catch {
                loadFailed = true
            }
        }
        isLoading = false
    }

    /// Sends (or accepts) a friend request by creating an edge toward this member.
    private func addFriend() {
        isWorking = true
        Task {
            try? await FriendshipService.addFriend(username: memberName, toId: userId)
            await load()
            isWorking = false
        }
    }

    private func decline() {
        isWorking = true
        Task {
            try? await FriendshipService.decline(username: memberName)
            await load()
            isWorking = false
        }
    }

    // MARK: - Friend gate

    private var friendGateCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
            Text("\(firstName)'s fitness is friends-only")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
            Text(gateSubtitle)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)

            switch relation {
            case .none:
                Button("Add Friend") { addFriend() }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !isWorking))
                    .frame(maxWidth: 240)
                    .disabled(isWorking)
            case .outgoing:
                Text("Request sent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, 12)
            case .incoming:
                VStack(spacing: 10) {
                    Button("Accept Friend Request") { addFriend() }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: !isWorking))
                        .frame(maxWidth: 240)
                        .disabled(isWorking)
                    Button("Decline") { decline() }
                        .buttonStyle(SecondaryButtonStyle(tint: Theme.secondaryText))
                        .frame(maxWidth: 240)
                        .disabled(isWorking)
                }
            case .friends, .selfUser:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 32)
        .padding(.top, 20)
    }

    private var gateSubtitle: String {
        switch relation {
        case .incoming: return "\(firstName) added you. Accept to see each other's fitness."
        case .outgoing: return "You'll both see each other's fitness once \(firstName) adds you back."
        default: return "Add \(firstName) as a friend to view their steps and activity."
        }
    }

    private var firstName: String {
        memberName.split(separator: " ").first.map(String.init)
            ?? memberName.split(separator: "@").first.map(String.init)
            ?? memberName
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
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

            Circle()
                .fill(Theme.accentSoft)
                .frame(width: 76, height: 76)
                .overlay(
                    Text(initials(for: memberName))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.accentDark)
                )

            VStack(spacing: 3) {
                Text(memberName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                if canViewFitness, let shared, let today = shared.weeklySteps.last {
                    Text("\(today.steps.formatted()) steps today")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(.top, 8)
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading…")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 40)
        .padding(.top, 20)
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: loadFailed ? "wifi.exclamationmark" : "figure.walk.motion")
                .font(.system(size: 40))
                .foregroundStyle(Theme.secondaryText)
            Text(loadFailed
                 ? "Couldn't load this member's fitness data."
                 : "\(memberName) hasn't shared any fitness data yet.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 32)
        .padding(.top, 20)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

#Preview {
    UserProfileView(memberName: "Maya Chen", userId: nil)
}
