import SwiftUI

/// The three quick-add buttons (8 / 16 / 24 oz).
struct LogButtonsView: View {
    var onLog: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DrinkSize.allCases) { size in
                Button {
                    onLog(size.ounces)
                } label: {
                    Text(size.label)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .tint(.blue)
                .accessibilityLabel("Log \(size.label)")
            }
        }
    }
}

#Preview {
    LogButtonsView { _ in }
}
