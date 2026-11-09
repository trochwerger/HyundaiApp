import SwiftUI

/// Circular EV battery gauge.
struct BatteryRing: View {
    let fraction: Double?
    let percentText: String
    let rangeText: String
    let isCharging: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 132
    @ScaledMetric(relativeTo: .largeTitle) private var lineWidth: CGFloat = 13

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(
                    // Gradient spans only the filled arc so there is no seam at the start.
                    AngularGradient(
                        colors: [.teal, .green],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(fraction ?? 0, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: fraction)

            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                    }
                    Text(percentText)
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text(rangeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("EV")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .minimumScaleFactor(0.6)
            .padding(lineWidth * 1.5)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("EV battery \(percentText), range \(rangeText)\(isCharging ? ", charging" : "")")
    }
}

/// Labelled horizontal level bar (used for fuel).
struct LevelBar: View {
    let title: String
    let symbol: String
    let fraction: Double?
    let valueText: String
    let detailText: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: proxy.size.width * (fraction ?? 0))
                        .animation(.easeOut(duration: 0.6), value: fraction)
                }
            }
            .frame(height: 8)

            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(valueText), \(detailText)")
    }
}

/// Small status capsule such as "Locked" or "Charging".
struct StatusPill: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular.tint(tint.opacity(0.15)), in: .capsule)
    }
}

/// Large square-ish quick action button.
struct QuickActionTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let isBusy: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .title2) private var minHeight: CGFloat = 86

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if isBusy {
                        ProgressView()
                    } else {
                        Image(systemName: symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(tint)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .frame(height: 30)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 22))
    }
}
