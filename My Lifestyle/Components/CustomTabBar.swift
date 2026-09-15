import SwiftUI
import UIKit

enum AppTab: String, CaseIterable {
    case diary = "Diary"
    case recipes = "Recipes"
    case pantry = "Pantry"
    case community = "Community"

    var icon: String {
        switch self {
        case .diary: return "book.closed.fill"
        case .recipes: return "fork.knife"
        case .pantry: return "cabinet.fill"
        case .community: return "person.2.fill"
        }
    }

    /// Each tab lights up in its own color when active — matching the Akashic bar.
    var selectedColor: Color {
        switch self {
        case .diary:     return Color(red: 0.15, green: 0.72, blue: 0.54)
        case .recipes:   return Color(red: 1.0,  green: 0.58, blue: 0.12)
        case .pantry:    return Color(red: 0.28, green: 0.52, blue: 1.0)
        case .community: return Color(red: 0.9,  green: 0.3,  blue: 0.72)
        }
    }
}

/// Floating capsule tab bar styled after Akashic Records: icons only, the active
/// tab shows as a filled colored circle, and a press-and-slide gesture lets you
/// drag across the icons and release on the one you want (with light haptics).
struct CustomTabBar: View {
    @Binding var selectedTab: AppTab

    // Tracks a press-and-slide gesture: the icon under the finger is highlighted
    // and, on release, becomes the active tab. A plain tap behaves like a normal press.
    @State private var draggedTab: AppTab?
    @State private var tabFrames: [AppTab: CGRect] = [:]
    @State private var isDragging = false

    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    /// Maps a point in the bar's coordinate space to the tab under it: a direct hit
    /// when inside an icon, otherwise the horizontally-nearest icon so the finger
    /// stays "locked" to a tab while sliding through the gaps between them.
    private func tab(at point: CGPoint) -> AppTab? {
        if let hit = tabFrames.first(where: { $0.value.contains(point) })?.key {
            return hit
        }
        return tabFrames.min {
            abs($0.value.midX - point.x) < abs($1.value.midX - point.x)
        }?.key
    }

    private var slideGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("lifestyleTabBar"))
            .onChanged { value in
                isDragging = true
                guard let tab = tab(at: value.location) else { return }
                if draggedTab != tab {
                    draggedTab = tab
                    hapticGenerator.impactOccurred()
                }
            }
            .onEnded { value in
                let target = tab(at: value.location) ?? draggedTab
                isDragging = false
                // Clear the drag highlight and commit the selection in a single
                // animated transaction. Doing them separately would briefly leave
                // draggedTab == nil while selectedTab is still the old tab, which
                // snaps the previous tab's circle to filled for one frame (a flash).
                withAnimation(.easeInOut(duration: 0.2)) {
                    if let target { selectedTab = target }
                    draggedTab = nil
                }
            }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(6)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(Theme.surface.opacity(0.6))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
        .contentShape(Capsule(style: .continuous))
        .coordinateSpace(name: "lifestyleTabBar")
        .onPreferenceChange(TabFramePreferenceKey.self) { tabFrames = $0 }
        .gesture(slideGesture)
        .onAppear { hapticGenerator.prepare() }
        .padding(.horizontal, 44)
        .padding(.bottom, 6)
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        let isHighlighted = draggedTab == tab
        // While sliding, only the icon under the finger is filled; otherwise the
        // active tab is. This avoids showing two filled icons at once.
        let filled = draggedTab != nil ? isHighlighted : isSelected

        return Image(systemName: tab.icon)
            .font(.system(size: 20, weight: filled ? .semibold : .regular))
            .foregroundStyle(filled ? .white : Theme.secondaryText)
            .frame(width: 46, height: 46)
            .background {
                Circle().fill(filled ? tab.selectedColor : Color.clear)
            }
            .scaleEffect(isHighlighted ? 1.12 : 1)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: TabFramePreferenceKey.self,
                        value: [tab: geo.frame(in: .named("lifestyleTabBar"))]
                    )
                }
            }
            .contentShape(Circle())
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: draggedTab)
            .accessibilityLabel(tab.rawValue)
    }
}

private struct TabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [AppTab: CGRect] = [:]

    static func reduce(value: inout [AppTab: CGRect], nextValue: () -> [AppTab: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        Theme.background.ignoresSafeArea()
        CustomTabBar(selectedTab: .constant(.diary))
    }
}
