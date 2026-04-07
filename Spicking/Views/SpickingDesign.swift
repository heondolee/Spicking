import SwiftUI

enum SpickingPalette {
    static let ink = Color(red: 0.09, green: 0.11, blue: 0.18)
    static let ocean = Color(red: 0.14, green: 0.45, blue: 0.98)
    static let teal = Color(red: 0.10, green: 0.74, blue: 0.73)
    static let coral = Color(red: 0.98, green: 0.54, blue: 0.35)
    static let graphite = Color(red: 0.42, green: 0.46, blue: 0.54)
    static let mist = Color(red: 0.93, green: 0.96, blue: 1.00)
    static let sand = Color(red: 0.99, green: 0.93, blue: 0.85)
    static let paper = Color(red: 0.98, green: 0.99, blue: 1.00)
    static let outline = Color(red: 0.72, green: 0.81, blue: 0.96)
    static let neutralOutline = Color(red: 0.78, green: 0.80, blue: 0.84)
}

struct SpickingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.90, green: 0.95, blue: 1.00),
                    SpickingPalette.paper,
                    SpickingPalette.sand.opacity(0.95),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(SpickingPalette.ocean.opacity(0.16))
                .frame(width: 300, height: 300)
                .blur(radius: 24)
                .offset(x: 140, y: -270)

            Circle()
                .fill(SpickingPalette.coral.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 24)
                .offset(x: -140, y: 210)
        }
        .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    var tint: Color = .white

    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(tint.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.88), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 22, y: 12)
            )
    }
}

extension View {
    func glassCard(tint: Color = .white) -> some View {
        modifier(GlassCardModifier(tint: tint))
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(SpickingPalette.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BrandMark: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SpickingPalette.ocean, SpickingPalette.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Spicking")
                    .font(.system(size: 28, weight: .black, design: .default))
                    .foregroundStyle(SpickingPalette.ink)
                Text("Speak naturally. Pick what you'll use.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SpickingPalette.graphite.opacity(0.92))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PromptChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? SpickingPalette.ocean : SpickingPalette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [Color(red: 0.88, green: 0.94, blue: 1.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.82), Color.white.opacity(0.68)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                isSelected ? SpickingPalette.ocean.opacity(0.22) : SpickingPalette.outline.opacity(0.95),
                                lineWidth: 1.2
                            )
                    )
            )
    }
}

struct MetricChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [SpickingPalette.ocean, SpickingPalette.teal],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: SpickingPalette.ocean.opacity(0.24), radius: 18, y: 10)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct CompactPrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                LinearGradient(
                    colors: [SpickingPalette.ocean, SpickingPalette.teal],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.26), lineWidth: 1)
            )
            .shadow(color: SpickingPalette.ocean.opacity(0.24), radius: 18, y: 10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
