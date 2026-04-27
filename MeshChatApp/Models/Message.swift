import SwiftData
import Foundation

enum MessageStatus: String, Codable {
    case sending       // just queued
    case sent          // broadcast succeeded
    case delivered     // ACK received (replaces "received" status)
    case failed
}

enum MessageDirection: String, Codable {
    case outgoing
    case incoming
}

/// Replaces: db.data["messages"][msg_id]
@Model
final class Message {
    @Attribute(.unique) var id: String
    var text: String
    var timestamp: Date
    var status: MessageStatus
    var direction: MessageDirection
    var replyToId: String?
    var senderPeerId: String           // UUID of sender
    var chat: Chat?
    
    init(
        id: String = UUID().uuidString,
        text: String,
        direction: MessageDirection,
        senderPeerId: String,
        replyToId: String? = nil
    ) {
        self.id = id
        self.text = text
        self.timestamp = .now
        self.status = direction == .outgoing ? .sending : .delivered
        self.direction = direction
        self.senderPeerId = senderPeerId
        self.replyToId = replyToId
    }
}
