import SwiftUI

extension Color {
    /// A color that resolves differently in light and dark appearance.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

/// User-selectable appearance, persisted via `@AppStorage("appearance")`.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The SwiftUI color scheme to force, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Central design tokens for the app. Everything visual (colors, radii, shadows)
/// is defined here so the whole UI is hand-built rather than relying on stock
/// iOS materials / system backgrounds.
enum Theme {
    // MARK: Palette
    //
    // Neutral tokens are dynamic so the app supports light and dark mode; brand
    // and macro accents stay constant across both.

    /// Warm off-white app background (near-black in dark mode).
    static let background = Color.dynamic(
        light: Color(red: 0.96, green: 0.97, blue: 0.95),
        dark: Color(red: 0.07, green: 0.08, blue: 0.08))
    /// Card / raised surface color.
    static let surface = Color.dynamic(
        light: .white,
        dark: Color(red: 0.13, green: 0.14, blue: 0.14))
    /// Recessed surface (fields, inline tiles).
    static let surfaceAlt = Color.dynamic(
        light: Color(red: 0.94, green: 0.95, blue: 0.93),
        dark: Color(red: 0.19, green: 0.20, blue: 0.20))

    static let primaryText = Color.dynamic(
        light: Color(red: 0.11, green: 0.14, blue: 0.13),
        dark: Color(red: 0.95, green: 0.96, blue: 0.95))
    static let secondaryText = Color.dynamic(
        light: Color(red: 0.46, green: 0.49, blue: 0.47),
        dark: Color(red: 0.64, green: 0.66, blue: 0.64))

    /// Fresh green brand accent.
    static let accent = Color(red: 0.16, green: 0.68, blue: 0.45)
    static let accentDark = Color(red: 0.10, green: 0.55, blue: 0.36)
    static let accentSoft = Color.dynamic(
        light: Color(red: 0.85, green: 0.94, blue: 0.88),
        dark: Color(red: 0.16, green: 0.28, blue: 0.22))

    static let carb = Color(red: 0.96, green: 0.62, blue: 0.24)
    static let protein = Color(red: 0.93, green: 0.36, blue: 0.55)
    static let fat = Color(red: 0.56, green: 0.46, blue: 0.86)
    static let danger = Color(red: 0.90, green: 0.31, blue: 0.31)

    // MARK: Metrics
    static let cardRadius: CGFloat = 22
    static let fieldRadius: CGFloat = 14
    static let shadow = Color.dynamic(
        light: Color.black.opacity(0.06),
        dark: Color.black.opacity(0.4))

    /// Signature accent gradient used on primary actions and rings.
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Card surface

private struct CardStyle: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: Theme.shadow, radius: 14, x: 0, y: 8)
    }
}

extension View {
    /// Wraps the content in a hand-built raised card surface.
    func card(padding: CGFloat = 16, radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(CardStyle(padding: padding, radius: radius))
    }
}

// MARK: - Section box

/// A titled, card-backed container that replaces the system `Section`/`List` look.
struct SectionBox<Content: View>: View {
    var title: String?
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 6)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .card(padding: padding)
        }
    }
}

/// Thin inset divider for use between rows inside a `SectionBox`.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

// MARK: - Buttons

/// Filled pill primary action.
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.accent)
                    .opacity(isEnabled ? 1 : 0.4)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Outlined secondary action.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.5), lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Small circular icon button (e.g. the "add food" plus).
struct IconButton: View {
    var systemName: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.accent))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Text field

/// Recessed, rounded field to replace bare system `TextField`s.
struct RoundedFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 16))
            .foregroundStyle(Theme.primaryText)
            .tint(Theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(Theme.surfaceAlt)
            )
    }
}

// MARK: - Header

/// Custom top bar replacing the system navigation title.
struct AppHeader: View {
    var title: String
    var subtitle: String?
    var trailingIcon: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            if let trailingIcon {
                Button { trailingAction?() } label: {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Theme.surface))
                        .overlay(Circle().stroke(Color.black.opacity(0.04), lineWidth: 1))
                        .shadow(color: Theme.shadow, radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Segmented control

/// Hand-built two-plus option selector to replace the system segmented `Picker`.
struct SegmentedSelector<T: Hashable>: View {
    var options: [(value: T, label: String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Theme.accent)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Theme.surfaceAlt)
        )
    }
}
