import SwiftUI

struct LiveConversationView: View {
    @ObservedObject var viewModel: ConversationViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            SpickingBackground()

            VStack(spacing: 14) {
                header

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(viewModel.liveTranscriptLines) { line in
                                TranscriptBubble(line: line)
                                    .id(line.id)
                            }
                        }
                        .padding(18)
                    }
                    .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(.white.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 22, y: 12)
                    .onChange(of: viewModel.liveTranscriptLines) { _, lines in
                        if let last = lines.last?.id {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }

                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("닫기") {
                    viewModel.close()
                    onClose()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("실전 영어 대화")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SpickingPalette.ocean)

            Text(viewModel.topic)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(SpickingPalette.ink)

            HStack(spacing: 12) {
                StatusPill(title: "연결 상태", value: viewModel.connectionState.label, tint: connectionTint)
                StatusPill(title: "AI 상태", value: viewModel.assistantSpeaking ? "말하는 중" : "듣는 중", tint: viewModel.assistantSpeaking ? SpickingPalette.coral : SpickingPalette.teal)
            }

            Text(viewModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Color.white.opacity(0.8))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Text("대화는 영어로만 진행됩니다. AI가 말하는 중에도 자연스럽게 끼어들 수 있어요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.endSession()
                }
            } label: {
                if viewModel.isEndingSession {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("세션 종료하고 리뷰 보기", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(SpickingPalette.ink)
            .disabled(viewModel.isEndingSession)
        }
        .glassCard(tint: Color.white.opacity(0.84))
    }

    private var connectionTint: Color {
        switch viewModel.connectionState {
        case .connected:
            return SpickingPalette.teal
        case .connecting:
            return SpickingPalette.coral
        case .failed:
            return .red
        case .disconnected:
            return .gray
        case .idle:
            return .secondary
        }
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TranscriptBubble: View {
    let line: LiveTranscriptLine

    private var bubbleStyle: AnyShapeStyle {
        if line.role == .user {
            AnyShapeStyle(
                LinearGradient(
                    colors: [SpickingPalette.ocean, SpickingPalette.teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.96), Color.white.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    var body: some View {
        VStack(alignment: line.role == .user ? .trailing : .leading, spacing: 8) {
            Text(line.role == .user ? "나" : "코치")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(line.text)
                .foregroundStyle(line.role == .user ? .white : .primary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: line.role == .user ? .trailing : .leading)
                .background(bubbleStyle, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 6) {
                if !line.isFinal {
                    Text("받아쓰는 중…")
                }
                if line.wasInterrupted {
                    Text("중간 끊기")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
