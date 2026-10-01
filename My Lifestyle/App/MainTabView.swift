import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .diary
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
                // Only pop Recipes to its root when RE-TAPPING the Recipes tab while it's
                // already showing (a normal, expected pop on a visible page). When
                // *leaving* Recipes we must NOT touch its stack: popping a detail that's
                // still mounted makes the recipe list render for a frame — the flash.
                // Switching the tab is instant (no animation) so there's no cross-fade dip.
                let isReTapOnRecipes = newValue == .recipes && selectedTab == .recipes

                var noAnimation = Transaction()
                noAnimation.disablesAnimations = true
                withTransaction(noAnimation) {
                    if isReTapOnRecipes {
                        recipesPath = NavigationPath()
                    }
                    selectedTab = newValue
                }
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
                page(.diary) { DiaryView() }
                page(.recipes) { RecipesView(path: $recipesPath) }
                page(.community) { CommunityView() }
                page(.fitness) { FitnessView() }
                page(.profile) { ProfileView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CustomTabBar(selectedTab: tabSelection)
        }
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(appearance.colorScheme)
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
