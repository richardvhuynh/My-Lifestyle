import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .diary

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
                page(.recipes) { RecipesView() }
                page(.pantry) { PantryView() }
                page(.profile) { ProfileView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.28), value: selectedTab)

            CustomTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
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
}
