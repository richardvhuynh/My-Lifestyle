import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .diary
    @State private var showingProfile = false
    @State private var recipesPath = NavigationPath()
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    /// Wraps the tab selection so any tab tap (switching or re-tapping the
    /// current tab) returns sections with pushed detail views to their root.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                recipesPath = NavigationPath()
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Constant backdrop so the background stays solid while pages cross-fade.
            Theme.background.ignoresSafeArea()

            // All pages stay mounted and cross-fade via opacity. A `.transition`
            // on a swapped view is ignored by NavigationStack (Recipes/Profile),
            // which made them snap in; animating a persistent view's opacity fades
            // every page smoothly and also preserves each tab's state.
            ZStack {
                page(.diary) { DiaryView(onOpenProfile: { showingProfile = true }) }
                page(.recipes) { RecipesView(path: $recipesPath) }
                page(.pantry) { PantryView() }
                page(.community) { CommunityView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.28), value: selectedTab)

            CustomTabBar(selectedTab: tabSelection)
        }
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(appearance.colorScheme)
        // Profile is reached from the Diary header now that its tab slot is Community.
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
    }

    /// Wraps a page so only the selected one is visible and interactive.
    @ViewBuilder
    private func page<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let isSelected = selectedTab == tab
        content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}

#Preview {
    MainTabView()
        .environment(PantryStore())
}
