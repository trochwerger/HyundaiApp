import SwiftUI

/// Top-of-screen banner showing a command in flight and its result.
/// Tapping a finished result dismisses it.
struct CommandStatusBanner: View {
    let busy: ControlsViewModel.Command?
    let result: ControlsViewModel.Result?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let busy {
                ProgressView()
                Text(busy.inFlightMessage)
            } else if let result {
                switch result {
                case .success(let message):
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(message)
                case .failure(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(tint), in: .capsule)
        .onTapGesture {
            guard busy == nil, result != nil else { return }
            dismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var tint: Color {
        guard busy == nil, let result else { return .clear }
        switch result {
        case .success: return .green.opacity(0.18)
        case .failure: return .red.opacity(0.18)
        }
    }
}
