import Combine
import SwiftUI
import UIKit

struct LiveConversationView: View {
    @ObservedObject var viewModel: ConversationViewModel
    let onClose: () -> Void
    @State private var showCancelAlert = false
    @State private var pendingScrollTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            SpickingBackground()
                .ignoresSafeArea()

            transcriptArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 20)
                .overlay(alignment: .bottom) {
                    speakingState
                        .padding(20)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
				.padding(.bottom, 20)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .alert("대화를 취소할까요?", isPresented: $showCancelAlert) {
            Button("계속 대화하기", role: .cancel) {}
            Button("취소하고 나가기", role: .destructive) {
                viewModel.close()
                onClose()
            }
        } message: {
            Text("지금 나가면 진행 중인 대화가 저장되지 않을 수 있어요.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showCancelAlert = true
                } label: {
                    Image(systemName: "chevron.left")
                }
            }

            ToolbarItem(placement: .principal) {
                topicBadge
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.endSession()
                    }
                } label: {
                    Text("대화 종료")
                }
                .disabled(viewModel.isEndingSession)
            }
        }
        .tint(.black)
    }

    private var topicBadge: some View {
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
    }

    private var speakingState: some View {
        HStack(spacing: 10) {
            Image(systemName: (viewModel.isAwaitingInitialCoachResponse || viewModel.assistantSpeaking) ? "speaker.wave.2.fill" : "mic.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle((viewModel.isAwaitingInitialCoachResponse || viewModel.assistantSpeaking) ? SpickingPalette.ocean : SpickingPalette.coral)
                .symbolEffect(.pulse.byLayer, options: .repeating, value: viewModel.isAwaitingInitialCoachResponse || viewModel.assistantSpeaking)

            Text(
                viewModel.assistantSpeaking
                    ? "AI가 말하는 중"
                    : (viewModel.isAwaitingInitialCoachResponse ? "AI가 준비중이에요" : "이제 말해보세요")
            )
                .font(.headline.weight(.bold))
                .foregroundStyle(SpickingPalette.ink)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.07), radius: 20, y: 12)
        )
    }

    private var transcriptArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(Color.white.opacity(0.60))
                .overlay(
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(.white.opacity(0.86), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 22, y: 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if viewModel.isAwaitingInitialCoachResponse {
                            InitialCoachLoadingBubble()
                        }
                        ForEach(viewModel.liveTranscriptLines) { line in
                            TranscriptBubble(line: line)
                                .id(line.id)
                        }
                        Color.clear
                            .frame(height: 74)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .scrollIndicators(.hidden)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .onReceive(viewModel.$liveTranscriptLines.map(\.last?.id).removeDuplicates()) { lastID in
                    guard let lastID else { return }
                    pendingScrollTask?.cancel()
                    pendingScrollTask = Task {
                        try? await Task.sleep(nanoseconds: 30_000_000)
                        guard Task.isCancelled == false else { return }
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.22)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }
                .onDisappear {
                    pendingScrollTask?.cancel()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct InitialCoachLoadingBubble: View {
    var body: some View {
        HStack {
            LoadingEllipsisText()
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [SpickingPalette.ocean, SpickingPalette.teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            Spacer(minLength: 46)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }
}

private struct TranscriptBubble: View {
    let line: LiveTranscriptLine

    private var bubbleTextMaxWidth: CGFloat {
        250
    }

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
        StreamingTranscriptLabel(
            text: line.text,
            tokenRevealDelay: isAssistant ? 55_000_000 : 35_000_000,
            textColor: UIColor(isAssistant ? .white : SpickingPalette.ink)
        )
            .frame(maxWidth: bubbleTextMaxWidth, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(background)
            .overlay(alignment: .bottomTrailing) {
                if line.wasInterrupted && !isAssistant {
                    Text("중간 종료")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                }
            }
            .transition(.asymmetric(insertion: .move(edge: isAssistant ? .leading : .trailing).combined(with: .opacity), removal: .opacity))
    }

    @ViewBuilder
    private var background: some View {
        if isAssistant {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [SpickingPalette.ocean, SpickingPalette.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(SpickingPalette.outline.opacity(0.9), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.03), radius: 10, y: 6)
        }
    }
}

private struct LoadingEllipsisText: View {
    @State private var dotCount = 1

    var body: some View {
        Text(String(repeating: ".", count: dotCount))
            .monospacedDigit()
            .onAppear {
                dotCount = 1
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    dotCount = dotCount % 3 + 1
                }
            }
    }
}

private struct StreamingTranscriptLabel: UIViewRepresentable {
    let text: String
    let tokenRevealDelay: UInt64
    let textColor: UIColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UILabel {
        let label = WrappingLabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .left
        label.textColor = textColor
        label.alpha = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        context.coordinator.attach(to: label)
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.textColor = textColor
        context.coordinator.update(text: text, tokenRevealDelay: tokenRevealDelay)
    }

    static func dismantleUIView(_ uiView: UILabel, coordinator: Coordinator) {
        coordinator.cancel()
    }

    final class WrappingLabel: UILabel {
        override func layoutSubviews() {
            super.layoutSubviews()
            preferredMaxLayoutWidth = bounds.width
        }
    }

    final class Coordinator {
        private weak var label: UILabel?
        private var displayedText = ""
        private var revealTask: Task<Void, Never>?
        private var hasAnimatedIn = false

        func attach(to label: UILabel) {
            self.label = label
        }

        func update(text newValue: String, tokenRevealDelay: UInt64) {
            guard let label else { return }
            let oldTokens = tokenize(displayedText)
            let newTokens = tokenize(newValue)

            if hasAnimatedIn == false {
                hasAnimatedIn = true
                label.alpha = 0
                UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
                    label.alpha = 1
                }
            }

            revealTask?.cancel()

            guard newTokens.count > oldTokens.count,
                  Array(newTokens.prefix(oldTokens.count)) == oldTokens else {
                displayedText = newValue
                label.text = newValue
                return
            }

            let additionalTokens = Array(newTokens.dropFirst(oldTokens.count))

            revealTask = Task { [weak self] in
                guard let self else { return }
                for token in additionalTokens {
                    if Task.isCancelled { return }
                    try? await Task.sleep(nanoseconds: tokenRevealDelay)
                    await MainActor.run {
                        self.displayedText += token
                        self.label?.text = self.displayedText
                    }
                }
            }
        }

        func cancel() {
            revealTask?.cancel()
        }

        private func tokenize(_ text: String) -> [String] {
            let nsText = text as NSString
            let pattern = #"\S+\s*"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return text.isEmpty ? [] : [text]
            }

            return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap {
                Range($0.range, in: text).map { String(text[$0]) }
            }
        }
    }
}
