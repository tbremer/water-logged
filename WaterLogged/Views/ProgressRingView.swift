import SwiftUI

/// Circular progress toward the daily goal, with the current total in the center.
///
/// Drawn as a custom ring that fills an explicit square frame, so its size is
/// exact and scales cleanly (stroke width and text track the diameter).
struct ProgressRingView: View {
    let total: Double
    let goal: Double

    /// Outer diameter of the ring, in points.
    /// ~150% of the previous `accessoryCircularCapacity` gauge (~68pt).
    var diameter: CGFloat = 102

    private var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(total / goal, 1)
    }

    private var percent: Int { Int((fraction * 100).rounded()) }

    var body: some View {
        let lineWidth = diameter * 0.12

        ZStack {
            Circle()
                .stroke(Color.cyan.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    Color.cyan,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: fraction)

            VStack(spacing: 0) {
                Text("\(Int(total.rounded()))")
                    .font(.system(size: diameter * 0.30, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                Text("/ \(Int(goal.rounded())) oz")
                    .font(.system(size: diameter * 0.13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hydration progress")
        .accessibilityValue("\(Int(total.rounded())) of \(Int(goal.rounded())) ounces, \(percent) percent")
    }
}

#Preview {
    ProgressRingView(total: 48, goal: 96)
}
