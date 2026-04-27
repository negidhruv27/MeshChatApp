import SwiftData
import Foundation

/// Replaces: db.data["chats"][chat_id] = peer_uuid
@Model
final class Chat {
    @Attribute(.unique) var id: String           // SHA256(sorted UUIDs)[:16]
    var createdAt: Date
    var lastMessageAt: Date
    var peer: Peer?
    
    @Relationship(deleteRule: .cascade) var messages: [Message] = []
    
    /// Computed: last message preview for the chat list
    var lastMessagePreview: String {
        messages.sorted { $0.timestamp > $1.timestamp }.first?.text ?? ""
    }
    
    init(id: String, peer: Peer) {
        self.id = id
        self.createdAt = .now
        self.lastMessageAt = .now
        self.peer = peer
    }
}
