import Combine
import SwiftUI

struct LiveConversationView: View {
    private enum ScrollAnchor {
        static let bottomSpacer = "conversation_bottom_spacer"
    }

    private enum TranscriptContainerStyle {
        static let topRadius: CGFloat = 24
        static let bottomRadius: CGFloat = 50
    }

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
                .padding(.horizontal, 10)
                .overlay(alignment: .bottom) {
                    bottomControls
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Image(systemName: speakingStateIconName)
                .font(.headline.weight(.bold))
                .foregroundStyle(speakingStateIconColor)
                .symbolEffect(.pulse.byLayer, options: .repeating, value: (viewModel.isAwaitingInitialCoachResponse || viewModel.assistantSpeaking) && !viewModel.isPaused)

            Text(speakingStateTitle)
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

    private var speakingStateIconName: String {
        if viewModel.isPaused {
            return "pause.fill"
        }
        if viewModel.isAwaitingInitialCoachResponse || viewModel.assistantSpeaking {
            return "speaker.wave.2.fill"
        }
        return "mic.fill"
    }

    private var speakingStateIconColor: Color {
        if viewModel.isPaused {
            return SpickingPalette.ink
        }
        if viewModel.isAwaitingInitialCoachResponse || viewModel.assistantSpeaking {
            return SpickingPalette.ocean
        }
        return SpickingPalette.coral
    }

    private var speakingStateTitle: String {
        if viewModel.isPaused {
            return "일시중지중"
        }
        if viewModel.assistantSpeaking {
            return "AI가 말하는 중"
        }
        if viewModel.isAwaitingInitialCoachResponse {
            return "AI가 준비중이에요"
        }
        return "이제 말해보세요"
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            speakingState

            HStack(spacing: 12) {
                pauseButton
                modeControls
                sendButton
            }
        }
    }

    private var pauseButton: some View {
        Button {
            Task {
                await viewModel.togglePause()
            }
        } label: {
            Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(SpickingPalette.ink)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.88), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 18, y: 10)
                )
        }
        .buttonStyle(.plain)
    }

    private var modeControls: some View {
        HStack(spacing: 4) {
            modeSegment(title: "자동 인식", mode: .automatic)
            modeSegment(title: "직접 보내기", mode: .manual)
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.88), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 18, y: 10)
        )
    }

    private var sendButton: some View {
        Button {
            Task {
                await viewModel.sendCurrentTurnManually()
            }
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
        }
        .background(
            Circle()
                .fill(
                    LinearGradient(
                        colors: [SpickingPalette.ocean, SpickingPalette.teal],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.26), lineWidth: 1)
                )
                .shadow(color: SpickingPalette.ocean.opacity(0.24), radius: 18, y: 10)
        )
        .buttonStyle(.plain)
        .disabled(!viewModel.canSendCurrentTurnManually)
        .opacity(viewModel.inputMode == .manual ? (viewModel.canSendCurrentTurnManually ? 1 : 0.55) : 0)
        .allowsHitTesting(viewModel.inputMode == .manual && viewModel.canSendCurrentTurnManually)
    }

    private func modeSegment(title: String, mode: ConversationInputMode) -> some View {
        Button {
            guard viewModel.inputMode != mode else { return }
            viewModel.toggleInputMode()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(viewModel.inputMode == mode ? .white : SpickingPalette.ink)
                .frame(minWidth: 92)
                .frame(height: 48)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            viewModel.inputMode == mode
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [SpickingPalette.ocean, SpickingPalette.teal],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                : AnyShapeStyle(Color.clear)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var transcriptArea: some View {
        ZStack {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: TranscriptContainerStyle.topRadius,
                    bottomLeading: TranscriptContainerStyle.bottomRadius,
                    bottomTrailing: TranscriptContainerStyle.bottomRadius,
                    topTrailing: TranscriptContainerStyle.topRadius
                ),
                style: .continuous
            )
                .fill(Color.white.opacity(0.60))
                .overlay(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: TranscriptContainerStyle.topRadius,
                            bottomLeading: TranscriptContainerStyle.bottomRadius,
                            bottomTrailing: TranscriptContainerStyle.bottomRadius,
                            topTrailing: TranscriptContainerStyle.topRadius
                        ),
                        style: .continuous
                    )
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
                            .frame(height: 180)
                            .allowsHitTesting(false)
                            .id(ScrollAnchor.bottomSpacer)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .scrollIndicators(.hidden)
                .clipShape(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: TranscriptContainerStyle.topRadius,
                            bottomLeading: TranscriptContainerStyle.bottomRadius,
                            bottomTrailing: TranscriptContainerStyle.bottomRadius,
                            topTrailing: TranscriptContainerStyle.topRadius
                        ),
                        style: .continuous
                    )
                )
                .onReceive(
                    viewModel.$liveTranscriptLines
                        .map { lines -> String in
                            guard let last = lines.last else { return "" }
                            return "\(last.id)|\(last.text)|\(last.isFinal)"
                        }
                        .removeDuplicates()
                ) { signature in
                    guard !signature.isEmpty else { return }
                    pendingScrollTask?.cancel()
                    pendingScrollTask = Task {
                        try? await Task.sleep(nanoseconds: 30_000_000)
                        guard Task.isCancelled == false else { return }
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.22)) {
                                proxy.scrollTo(ScrollAnchor.bottomSpacer, anchor: .bottom)
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
        320
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
        Group {
            if isAssistant {
                AssistantSentenceBubbleSequence(line: line, bubbleTextMaxWidth: bubbleTextMaxWidth)
            } else {
                transcriptBubbleBody(text: line.text)
            }
        }
    }

    private func transcriptBubbleBody(text: String) -> some View {
        BubbleTextBlock(
            text: text,
            maxWidth: bubbleTextMaxWidth,
            foregroundColor: isAssistant ? .white : SpickingPalette.ink
        )
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
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 24,
                    bottomLeading: 24,
                    bottomTrailing: 24,
                    topTrailing: 24
                ),
                style: .continuous
            )
                .fill(
                    LinearGradient(
                        colors: [SpickingPalette.ocean, SpickingPalette.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 24,
                    bottomLeading: 24,
                    bottomTrailing: 24,
                    topTrailing: 24
                ),
                style: .continuous
            )
                .fill(Color.white.opacity(0.96))
                .overlay(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 24,
                            bottomLeading: 24,
                            bottomTrailing: 24,
                            topTrailing: 24
                        ),
                        style: .continuous
                    )
                        .stroke(SpickingPalette.outline.opacity(0.9), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.03), radius: 10, y: 6)
        }
    }
}

private struct AssistantSentenceBubbleSequence: View {
    let line: LiveTranscriptLine
    let bubbleTextMaxWidth: CGFloat
    @State private var renderedSegments: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(renderedSegments.enumerated()), id: \.offset) { index, sentence in
                assistantBubble(
                    text: sentence,
                    position: bubblePosition(for: index, totalCount: renderedSegments.count)
                )
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: bubbleTextMaxWidth + 32, alignment: .leading)
        .onAppear {
            applyTranscript(line.text, isFinal: line.isFinal, animated: false)
        }
        .onChange(of: line.text) { _, _ in
            applyTranscript(line.text, isFinal: line.isFinal, animated: true)
        }
        .onChange(of: line.isFinal) { _, _ in
            applyTranscript(line.text, isFinal: line.isFinal, animated: true)
        }
    }

    private func assistantBubble(text: String, position: BubbleStackPosition) -> some View {
        BubbleTextBlock(
            text: text,
            maxWidth: bubbleTextMaxWidth,
            foregroundColor: .white
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bubbleBackground(for: position))
    }

    @ViewBuilder
    private func bubbleBackground(for position: BubbleStackPosition) -> some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: position.topRadius,
                bottomLeading: position.bottomRadius,
                bottomTrailing: 24,
                topTrailing: 24
            ),
            style: .continuous
        )
        .fill(
            LinearGradient(
                colors: [SpickingPalette.ocean, SpickingPalette.teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func bubblePosition(for index: Int, totalCount: Int) -> BubbleStackPosition {
        switch totalCount {
        case 0:
            return .single
        case 1:
            return .single
        default:
            if index == 0 { return .top }
            if index == totalCount - 1 { return .bottom }
            return .middle
        }
    }

    private func applyTranscript(_ text: String, isFinal: Bool, animated: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextSegments = sentenceSegments(from: trimmed, isFinal: isFinal)

        guard nextSegments.isEmpty == false else {
            renderedSegments = []
            return
        }

        guard nextSegments != renderedSegments else {
            return
        }

        let commonPrefixCount = zip(renderedSegments, nextSegments).prefix { $0 == $1 }.count
        let newSegments = Array(nextSegments.dropFirst(commonPrefixCount))

        if animated, commonPrefixCount == renderedSegments.count {
            for segment in newSegments {
                appendNewSegment(segment, animated: true)
            }
        } else {
            renderedSegments = nextSegments
        }
    }

    private func appendNewSegment(_ text: String, animated: Bool) {
        let insertion = {
            renderedSegments.append(text)
        }

        if animated {
            withAnimation(.easeIn(duration: 0.24)) {
                insertion()
            }
        } else {
            insertion()
        }
    }

    private func sentenceSegments(from text: String, isFinal: Bool) -> [String] {
        guard text.isEmpty == false else { return [] }

        let pattern = #"[^.!?]+[.!?]+["')\]]*\s*|[^.!?]+$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return isFinal ? [text] : []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var segments: [String] = []

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let segment = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard segment.isEmpty == false else { continue }

            let lastCharacter = segment.last
            let isCompletedSentence = lastCharacter == "." || lastCharacter == "!" || lastCharacter == "?"
            if isCompletedSentence || isFinal {
                segments.append(segment)
            }
        }

        return segments
    }
}

private enum BubbleStackPosition {
    case single
    case top
    case middle
    case bottom

    var topRadius: CGFloat {
        switch self {
        case .single:
            return 24
        case .top:
            return 24
        case .middle, .bottom:
            return 12
        }
    }

    var bottomRadius: CGFloat {
        switch self {
        case .single:
            return 24
        case .bottom:
            return 24
        case .top, .middle:
            return 12
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

private struct BubbleTextBlock: View {
    let text: String
    let maxWidth: CGFloat
    let foregroundColor: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text)
                .font(.body)
                .foregroundStyle(foregroundColor)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(text)
                .font(.body)
                .foregroundStyle(foregroundColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
    }
}
