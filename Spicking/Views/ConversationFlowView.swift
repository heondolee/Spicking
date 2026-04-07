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
                    ProgressView("리뷰를 만드는 중이에요…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(SpickingBackground())
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
        ZStack {
            SpickingBackground()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(SpickingPalette.coral)
                Text("세션을 시작하지 못했어요")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("닫기", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .tint(SpickingPalette.ink)
            }
            .glassCard(tint: Color.white.opacity(0.84))
            .padding(24)
        }
    }
}
