import SwiftUI

struct LiveConversationView: View {
    @ObservedObject var viewModel: ConversationViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            SpickingBackground()

            VStack(spacing: 14) {
                topBar
                topicBadge
                speakingState
                transcriptArea
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationBarBackButtonHidden()
    }

    private var topBar: some View {
        HStack {
            Button("닫기") {
                viewModel.close()
                onClose()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SpickingPalette.ink)

            Spacer()
        }
    }

    private var topicBadge: some View {
        HStack {
            Text(viewModel.topic)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SpickingPalette.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.86))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(SpickingPalette.outline.opacity(0.9), lineWidth: 1.1)
                        )
                )

            Spacer()
        }
    }

    private var speakingState: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((viewModel.assistantSpeaking ? SpickingPalette.ocean : SpickingPalette.coral).opacity(0.16))
                    .frame(width: 54, height: 54)

                Image(systemName: viewModel.assistantSpeaking ? "speaker.wave.3.fill" : "mic.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(viewModel.assistantSpeaking ? SpickingPalette.ocean : SpickingPalette.coral)
                    .symbolEffect(.pulse.byLayer, options: .repeating, value: viewModel.assistantSpeaking)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.assistantSpeaking ? "AI가 말하는 중" : "이제 말해보세요")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SpickingPalette.ink)
                Text(viewModel.assistantSpeaking ? "중간에 바로 끼어들어도 자연스럽게 이어집니다." : "영어로 편하게 말하면 다음 질문이 이어집니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .glassCard(tint: Color.white.opacity(0.80))
    }

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.liveTranscriptLines) { line in
                        TranscriptBubble(line: line)
                            .id(line.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.60))
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(.white.opacity(0.86), lineWidth: 1)
                    )
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
    }

    private var footer: some View {
        Button {
            Task {
                await viewModel.endSession()
            }
        } label: {
            if viewModel.isEndingSession {
                ProgressView()
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "stop.circle.fill")
                    Text("대화 종료")
                        .font(.headline.weight(.semibold))
                }
            }
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .disabled(viewModel.isEndingSession)
    }
}

private struct TranscriptBubble: View {
    let line: LiveTranscriptLine

    private var isAssistant: Bool {
        line.role == .assistant
    }

    var body: some View {
        HStack {
            if isAssistant {
                bubble
                Spacer(minLength: 46)
            } else {
                Spacer(minLength: 46)
                bubble
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bubble: some View {
        Text(line.text)
            .font(.body)
            .foregroundStyle(isAssistant ? .white : SpickingPalette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if line.wasInterrupted {
                    Text("중간 종료")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isAssistant ? .white.opacity(0.9) : .secondary)
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                }
            }
    }

    @ViewBuilder
    private var background: some View {
        if isAssistant {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [SpickingPalette.ocean, SpickingPalette.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(SpickingPalette.outline.opacity(0.9), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.03), radius: 10, y: 6)
        }
    }
}
