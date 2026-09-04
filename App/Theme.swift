import SwiftUI

/// Palette and type.
///
/// The app is used in the dark, in bed, by somebody whose eyes are already
/// tired and already overstimulated. So: no pure white, no saturated blue, no
/// high-frequency contrast. The one warm accent is the lamp the moth circles,
/// and it is the only thing on screen allowed to be bright.
enum Theme {

    // MARK: Colour

    /// Deep, slightly warm night. Not pure black -- OLED black next to a light
    /// accent is the exact high-contrast edge we are trying to avoid.
    static let night = Color(red: 0.055, green: 0.055, blue: 0.086)
    static let nightRaised = Color(red: 0.094, green: 0.094, blue: 0.137)
    static let nightCard = Color(red: 0.129, green: 0.129, blue: 0.180)

    /// The lamp. Warm amber, used sparingly and never for large areas.
    static let lamp = Color(red: 1.0, green: 0.749, blue: 0.361)
    static let lampDim = Color(red: 0.788, green: 0.573, blue: 0.259)

    /// Text. Cream rather than white, which reads softer at 1am.
    static let ink = Color(red: 0.945, green: 0.933, blue: 0.898)
    static let inkSoft = Color(red: 0.945, green: 0.933, blue: 0.898).opacity(0.62)
    static let inkFaint = Color(red: 0.945, green: 0.933, blue: 0.898).opacity(0.34)

    /// Muted, desaturated success. A bright green "done" flash is a slot
    /// machine tell, and this app is explicitly not that.
    static let done = Color(red: 0.478, green: 0.741, blue: 0.596)
    static let alarm = Color(red: 0.902, green: 0.494, blue: 0.443)

    static func tint(for archetype: Archetype) -> Color {
        switch archetype {
        case .move:    return Color(red: 0.596, green: 0.729, blue: 0.941)
        case .tend:    return Color(red: 0.647, green: 0.788, blue: 0.706)
        case .connect: return Color(red: 0.937, green: 0.663, blue: 0.647)
        case .create:  return Color(red: 0.816, green: 0.706, blue: 0.941)
        case .sense:   return Color(red: 0.596, green: 0.855, blue: 0.769)
        case .nourish: return Color(red: 0.949, green: 0.796, blue: 0.588)
        case .rest:    return Color(red: 0.706, green: 0.706, blue: 0.902)
        }
    }

    // MARK: Type

    static let display = Font.system(size: 34, weight: .semibold, design: .serif)
    static let title = Font.system(size: 26, weight: .semibold, design: .serif)
    /// Tasks are set in serif at a generous size. They are the one thing on
    /// screen meant to be read slowly.
    static let task = Font.system(size: 25, weight: .regular, design: .serif)
    static let body = Font.system(size: 17, weight: .regular)
    static let label = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 12, weight: .medium)

    // MARK: Layout

    static let corner: CGFloat = 22
    static let gutter: CGFloat = 24
}

/// The background used on every screen.
struct NightBackground: View {
    var body: some View {
        ZStack {
            Theme.night
            // A single soft pool of lamplight behind the buddy, so the screen
            // has a focal point without needing a bright element.
            RadialGradient(
                colors: [Theme.lamp.opacity(0.13), Theme.lamp.opacity(0.0)],
                center: .init(x: 0.5, y: 0.28),
                startRadius: 8,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

/// The app's one button style. Amber for the single primary action on a
/// screen, outlined for everything else.
struct LampButtonStyle: ButtonStyle {
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body.weight(.semibold))
            .foregroundStyle(prominent ? Theme.night : Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent ? Theme.lamp : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Theme.inkFaint, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
