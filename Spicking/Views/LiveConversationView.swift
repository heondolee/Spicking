import SwiftUI

struct LiveConversationView: View {
    @ObservedObject var viewModel: ConversationViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.liveTranscriptLines) { line in
                            TranscriptBubble(line: line)
                                .id(line.id)
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .onChange(of: viewModel.liveTranscriptLines) { _, lines in
                    if let last = lines.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            footer
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") {
                    viewModel.close()
                    onClose()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.topic)
                .font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                StatusPill(title: "Connection", value: viewModel.connectionState.label, tint: connectionTint)
                StatusPill(title: "Assistant", value: viewModel.assistantSpeaking ? "Speaking" : "Listening", tint: viewModel.assistantSpeaking ? .orange : .green)
            }
            Text(viewModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Text("You can interrupt the assistant naturally. Your speaking is being transcribed live.")
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
                    Label("End Session", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isEndingSession)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var connectionTint: Color {
        switch viewModel.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TranscriptBubble: View {
    let line: LiveTranscriptLine

    var body: some View {
        VStack(alignment: line.role == .user ? .trailing : .leading, spacing: 6) {
            Text(line.role == .user ? "You" : "Coach")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(line.text)
                .foregroundStyle(line.role == .user ? .white : .primary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: line.role == .user ? .trailing : .leading)
                .background(
                    line.role == .user ? Color.accentColor : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )

            HStack(spacing: 6) {
                if !line.isFinal {
                    Text("Listening…")
                }
                if line.wasInterrupted {
                    Text("Interrupted")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
