import SwiftUI

enum SpickingPalette {
    static let ink = Color(red: 0.10, green: 0.12, blue: 0.18)
    static let ocean = Color(red: 0.18, green: 0.49, blue: 0.96)
    static let teal = Color(red: 0.16, green: 0.72, blue: 0.71)
    static let coral = Color(red: 0.98, green: 0.53, blue: 0.32)
    static let mist = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let sand = Color(red: 1.00, green: 0.95, blue: 0.89)
}

struct SpickingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SpickingPalette.mist,
                    Color.white,
                    SpickingPalette.sand.opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(SpickingPalette.teal.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 16)
                .offset(x: 130, y: -260)

            Circle()
                .fill(SpickingPalette.ocean.opacity(0.14))
                .frame(width: 240, height: 240)
                .blur(radius: 20)
                .offset(x: -140, y: 140)
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
                            .stroke(.white.opacity(0.72), lineWidth: 1)
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
