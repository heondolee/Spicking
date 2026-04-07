import Foundation

struct LiveTranscriptLine: Identifiable, Equatable {
    let id: String
    let role: TranscriptRole
    var text: String
    var isFinal: Bool
    var wasInterrupted: Bool
}

struct ReviewCard: Identifiable, Equatable {
    let id: UUID
    let originalText: String
    let minimalRewrite: String
    let naturalRewrite: String
    let reasonKo: String
    let intentKo: String
    let tags: [String]
    var isSaved: Bool
}

struct RealtimePlaybackSnapshot {
    let itemID: String
    let playedMilliseconds: Int
}

enum ConversationFlowPhase: Equatable {
    case preparing
    case live
    case generatingReview
    case review
    case failed(String)
}

enum RealtimeConnectionState: String {
    case idle
    case connecting
    case connected
    case disconnected
    case failed

    var label: String {
        switch self {
        case .idle:
            return "대기"
        case .connecting:
            return "연결 중"
        case .connected:
            return "연결됨"
        case .disconnected:
            return "연결 종료"
        case .failed:
            return "실패"
        }
    }
}
