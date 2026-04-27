import SwiftData
import Foundation
import CryptoKit

/// Central SwiftData stack — replaces JSONDatabaseManager.
@MainActor
final class PersistenceManager {
    
    static let shared = PersistenceManager()
    
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    
    private init() {
        let schema = Schema([Peer.self, Chat.self, Message.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }
    
    // MARK: - Peer
    // Replaces: db.add_peer(uuid, public_key) and db.get_peer_pub_key(uuid)
    
    func upsertPeer(from handshake: HandshakePayload, myUUID: String) {  // ✅ added myUUID
        let descriptor = FetchDescriptor<Peer>(
            predicate: #Predicate { $0.id == handshake.peerId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.displayName = handshake.displayName
            existing.publicKeyData = handshake.identityPublicKey
            existing.lastSeen = .now
            existing.isConnected = true
        } else {
            let newPeer = Peer(
                id: handshake.peerId,
                displayName: handshake.displayName,
                publicKeyData: handshake.identityPublicKey
            )
            context.insert(newPeer)
            createChatIfNeeded(for: newPeer, myUUID: myUUID)  // ✅ now uses local UUID
        }
        try? context.save()
    }
    func peer(byId id: String) -> Peer? {
        let descriptor = FetchDescriptor<Peer>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
    
    // MARK: - Chat
    // Replaces: db.create_chat(chat_id, peer_uuid)
    // Chat ID formula is identical to Python: SHA256(sorted UUIDs)[:16]
    
    func createChatIfNeeded(for peer: Peer, myUUID: String) {
        let chatId = Self.chatId(myUUID: myUUID, peerUUID: peer.id)
        let descriptor = FetchDescriptor<Chat>(predicate: #Predicate { $0.id == chatId })
        guard (try? context.fetch(descriptor).first) == nil else { return }
        let chat = Chat(id: chatId, peer: peer)
        context.insert(chat)
        try? context.save()
    }
    
    func chat(withId id: String) -> Chat? {
        let descriptor = FetchDescriptor<Chat>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
    
    // MARK: - Message
    // Replaces: db.save_message(...) and db.update_message_status(...)
    
    func saveMessage(_ inner: InnerMessage, direction: MessageDirection) {
        guard let chat = chat(withId: inner.chatId) else { return }
        
        let msg = Message(
            id: inner.messageId,
            text: inner.text ?? "",
            direction: direction,
            senderPeerId: inner.senderId,
            replyToId: inner.replyToId
        )
        msg.timestamp = Date(timeIntervalSince1970: inner.timestamp)
        msg.chat = chat
        chat.lastMessageAt = msg.timestamp
        context.insert(msg)
        try? context.save()
    }
    
    func updateMessageStatus(id: String, status: MessageStatus) {
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.id == id })
        if let msg = try? context.fetch(descriptor).first {
            msg.status = status
            try? context.save()
        }
    }
    
    // MARK: - Utilities
    
    static func chatId(myUUID: String, peerUUID: String) -> String {
        // Same formula as Python: hashlib.sha256("".join(sorted([uuid1, uuid2]))).hexdigest()[:16]
        let sorted = [myUUID, peerUUID].sorted().joined()
        let digest = SHA256.hash(data: Data(sorted.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}
