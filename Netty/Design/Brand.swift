import SwiftUI

/// Netty's visual language, shared with JUMP: graphite, hairline borders and
/// soft top-lit cards.
enum Brand {
    static let cardRadius: CGFloat = 14
    static let tileRadius: CGFloat = 12
    static let buttonRadius: CGFloat = 8

    /// Thin border around cards and buttons.
    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.09)
    }

    /// A soft top-lit wash for cards.
    static func cardWash(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [.white.opacity(0.06), .white.opacity(0.03)]
                : [.black.opacity(0.025), .black.opacity(0.035)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// A top-lit surface with a hairline border.
struct CardBackground: ViewModifier {
    var radius = Brand.cardRadius
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(Brand.cardWash(scheme), in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Brand.hairline(scheme)))
    }
}

/// Netty's flat button: the cards' wash and hairline, so it sits on the
/// popover's translucent material instead of standing out from it.
struct PlainCardButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Brand.cardWash(scheme), in: .rect(cornerRadius: Brand.buttonRadius))
            .background(.primary.opacity(configuration.isPressed ? 0.08 : 0), in: .rect(cornerRadius: Brand.buttonRadius))
            .overlay(RoundedRectangle(cornerRadius: Brand.buttonRadius).strokeBorder(Brand.hairline(scheme)))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.rect)
    }
}

extension View {
    func card(radius: CGFloat = Brand.cardRadius) -> some View {
        modifier(CardBackground(radius: radius))
    }
}
