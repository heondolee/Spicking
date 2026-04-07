import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConversationSession.startedAt, order: .reverse) private var sessions: [ConversationSession]
    @ObservedObject var appViewModel: AppViewModel
    @State private var topic = "daily life and small talk"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SetupCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today's Topic")
                            .font(.headline)
                        TextField("Topic", text: $topic, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            appViewModel.startConversation(topic: topic, modelContext: modelContext)
                        } label: {
                            Label("Start Conversation", systemImage: "mic.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Sessions")
                            .font(.headline)
                        if sessions.isEmpty {
                            Text("Your first speaking session will show up here.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(sessions.prefix(3))) { session in
                                RecentSessionRow(session: session)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Spicking")
        }
    }
}

private struct SetupCard: View {
    private var isConfigured: Bool {
        (try? AppConfigurationLoader.load()) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isConfigured ? "Configuration Ready" : "Setup Needed", systemImage: isConfigured ? "checkmark.seal.fill" : "gearshape.2.fill")
                .font(.headline)
                .foregroundStyle(isConfigured ? .green : .primary)
            Text(isConfigured
                 ? "The app found your Worker URL and shared secret in SpickingConfig.plist."
                 : "Add your Cloudflare Worker URL and shared secret to SpickingConfig.plist before you start the live conversation feature.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct RecentSessionRow: View {
    let session: ConversationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.topic)
                    .font(.headline)
                Spacer()
                Text(session.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15), in: Capsule())
            }

            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if session.durationSeconds > 0 {
                Text("\(session.durationSeconds / 60)m \(session.durationSeconds % 60)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusColor: Color {
        switch session.status {
        case .completed:
            return .green
        case .reviewing, .live:
            return .blue
        case .failed:
            return .red
        case .preparing:
            return .orange
        }
    }
}
