import SwiftUI

struct ConversationFlowView: View {
    @ObservedObject var viewModel: ConversationViewModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .preparing, .live:
                    LiveConversationView(viewModel: viewModel, onClose: onClose)
                case .generatingReview:
                    ProgressView("Building your review...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                case .review:
                    SessionReviewView(viewModel: viewModel, onDone: onClose)
                case .failed(let message):
                    FailureStateView(message: message, onClose: onClose)
                }
            }
            .task {
                await viewModel.startIfNeeded()
            }
        }
        .onDisappear {
            viewModel.close()
        }
    }
}

private struct FailureStateView: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Session could not start")
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Close", action: onClose)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}
