//
//  FramwiseDesignSystem.swift
//  Framwise
//
//  Design tokens, color extensions, typography, and shared UI components.
//  Extracted from ContentView to serve as a single dependency for all layers.
//

import SwiftUI

// MARK: - Theme Tokens

enum FramwiseTheme {
    static let background = Color(hex: "0D0F12")
    static let backgroundElevated = Color(hex: "11141B")
    static let surface = Color(hex: "151922")
    static let surfaceRaised = Color(hex: "1D2330")
    static let line = Color(hex: "2A3142")
    static let textPrimary = Color(hex: "E7ECF3")
    static let textMuted = Color(hex: "9AA6B8")
    static let accent = Color(hex: "8C7CFF")
    static let accentSoft = Color(hex: "8C7CFF").opacity(0.16)
    static let success = Color(hex: "4DE2C5")
    static let warning = Color(hex: "FFB84D")
    static let danger = Color(hex: "FF6B6B")
    static let info = Color(hex: "7FB3FF")
    static let warm = Color(hex: "F3D2A7")

    static let tagPink = Color(hex: "E58ACF")
    static let tagGray = Color(hex: "6E778A")

    static let appGradient = LinearGradient(
        colors: [
            background,
            Color(hex: "10131A"),
            background
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleHighlight = LinearGradient(
        colors: [
            warm.opacity(0.18),
            accent.opacity(0.06),
            .clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let monitorGradient = LinearGradient(
        colors: [
            Color.black.opacity(0.0),
            Color.black.opacity(0.55),
            Color.black.opacity(0.84)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Color Hex Init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            assertionFailure("Invalid hex color string: \(hex)")
            (a, r, g, b) = (255, 255, 0, 255) // magenta — visible debug sentinel
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography

extension Font {
    static func framwiseDisplay(_ size: CGFloat, weight: Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func framwiseUI(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func framwiseMono(_ size: CGFloat, weight: Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Panel Modifier

struct FramwisePanelModifier: ViewModifier {
    var background: Color = FramwiseTheme.surface
    var radius: CGFloat = 18
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(FramwiseTheme.line.opacity(0.9), lineWidth: 1)
            )
    }
}

extension View {
    func framwisePanel(
        background: Color = FramwiseTheme.surface,
        radius: CGFloat = 18,
        padding: CGFloat = 0
    ) -> some View {
        modifier(FramwisePanelModifier(background: background, radius: radius, padding: padding))
    }
}

// MARK: - Button Styles

struct FramwisePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.framwiseUI(13, weight: .semibold))
            .foregroundStyle(FramwiseTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                FramwiseTheme.accent.opacity(configuration.isPressed ? 0.55 : 0.78),
                                FramwiseTheme.warm.opacity(configuration.isPressed ? 0.18 : 0.26)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(FramwiseTheme.accent.opacity(0.55), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FramwiseGhostButtonStyle: ButtonStyle {
    var fill: Color = FramwiseTheme.surfaceRaised
    var border: Color = FramwiseTheme.line.opacity(0.9)
    var foreground: Color = FramwiseTheme.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.framwiseUI(13, weight: .medium))
            .foregroundStyle(foreground.opacity(configuration.isPressed ? 0.92 : 1))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.9 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Shared Components

struct FramwiseMetricBadge: View {
    let title: String
    let value: String
    var color: Color = FramwiseTheme.textMuted

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.framwiseMono(10))
                .foregroundStyle(FramwiseTheme.textMuted)
            Text(value)
                .font(.framwiseDisplay(18, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 14)
    }
}

struct FramwiseLinearProgress: View {
    let value: Double
    var tint: Color = FramwiseTheme.accent

    private var clampedValue: Double {
        max(0, min(1, value))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(FramwiseTheme.surfaceRaised)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, FramwiseTheme.warm.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geometry.size.width * clampedValue))
            }
            .overlay(
                Capsule(style: .continuous)
                    .stroke(FramwiseTheme.line.opacity(0.6), lineWidth: 1)
            )
        }
        .frame(height: 10)
    }
}

struct FramwiseLoadingIndicator: View {
    var tint: Color = FramwiseTheme.accent
    var diameter: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .stroke(FramwiseTheme.line.opacity(0.35), lineWidth: 2)

            Circle()
                .trim(from: 0.12, to: 0.78)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}
