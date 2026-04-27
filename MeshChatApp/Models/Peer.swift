import SwiftData
import Foundation

/// Replaces: db.data["peers"][uuid] = public_key
@Model
final class Peer {
    @Attribute(.unique) var id: String          // peer's UUID string
    var displayName: String                      // MCPeerID.displayName
    var publicKeyData: Data                      // Curve25519 raw public key bytes
    var firstSeen: Date
    var lastSeen: Date
    var isConnected: Bool
    
    // Relationship to chats
    @Relationship(deleteRule: .cascade) var chats: [Chat] = []
    
    init(id: String, displayName: String, publicKeyData: Data) {
        self.id = id
        self.displayName = displayName
        self.publicKeyData = publicKeyData
        self.firstSeen = .now
        self.lastSeen = .now
        self.isConnected = false
    }
}
