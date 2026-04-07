import Foundation
import SwiftData

enum ConversationSessionStatus: String, Codable, CaseIterable {
    case preparing
    case live
    case reviewing
    case completed
    case failed
}

enum TranscriptRole: String, Codable, CaseIterable {
    case user
    case assistant
}

@Model
final class ConversationSession {
    @Attribute(.unique) var id: UUID
    var topic: String
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var durationSeconds: Int

    init(
        id: UUID = UUID(),
        topic: String,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        status: ConversationSessionStatus = .preparing,
        durationSeconds: Int = 0
    ) {
        self.id = id
        self.topic = topic
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.statusRaw = status.rawValue
        self.durationSeconds = durationSeconds
    }

    var status: ConversationSessionStatus {
        get { ConversationSessionStatus(rawValue: statusRaw) ?? .preparing }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class TranscriptEntry {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var remoteItemID: String
    var roleRaw: String
    var sequence: Int
    var text: String
    var startedAt: Date
    var endedAt: Date?
    var wasInterrupted: Bool
    var isFinal: Bool

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        remoteItemID: String,
        role: TranscriptRole,
        sequence: Int,
        text: String,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        wasInterrupted: Bool = false,
        isFinal: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.remoteItemID = remoteItemID
        self.roleRaw = role.rawValue
        self.sequence = sequence
        self.text = text
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.wasInterrupted = wasInterrupted
        self.isFinal = isFinal
    }

    var role: TranscriptRole {
        get { TranscriptRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }
}

@Model
final class ReviewSuggestion {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var originalText: String
    var minimalRewrite: String
    var naturalRewrite: String
    var reasonKo: String
    var intentKo: String
    var tagsRaw: String
    var isSaved: Bool

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        originalText: String,
        minimalRewrite: String,
        naturalRewrite: String,
        reasonKo: String,
        intentKo: String,
        tags: [String],
        isSaved: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.originalText = originalText
        self.minimalRewrite = minimalRewrite
        self.naturalRewrite = naturalRewrite
        self.reasonKo = reasonKo
        self.intentKo = intentKo
        self.tagsRaw = tags.joined(separator: ",")
        self.isSaved = isSaved
    }

    var tags: [String] {
        get {
            tagsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsRaw = newValue.joined(separator: ",")
        }
    }
}

@Model
final class PhraseCard {
    @Attribute(.unique) var id: UUID
    var intentKo: String
    var expressionEn: String
    var sourceOriginalText: String
    var naturalRewrite: String
    var usageNoteKo: String
    var tagsRaw: String
    var createdAt: Date
    var sourceSessionID: UUID

    init(
        id: UUID = UUID(),
        intentKo: String,
        expressionEn: String,
        sourceOriginalText: String,
        naturalRewrite: String,
        usageNoteKo: String,
        tags: [String],
        createdAt: Date = .now,
        sourceSessionID: UUID
    ) {
        self.id = id
        self.intentKo = intentKo
        self.expressionEn = expressionEn
        self.sourceOriginalText = sourceOriginalText
        self.naturalRewrite = naturalRewrite
        self.usageNoteKo = usageNoteKo
        self.tagsRaw = tags.joined(separator: ",")
        self.createdAt = createdAt
        self.sourceSessionID = sourceSessionID
    }

    var tags: [String] {
        get {
            tagsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsRaw = newValue.joined(separator: ",")
        }
    }
}
