import Foundation
import SwiftData
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    
    @Published var messages: [Message] = []
    @Published var draftText: String = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    
    private let chat: Chat
    private let mesh: MeshService
    private let persistence: PersistenceManager
    private let myUUID: String
    private var cancellables = Set<AnyCancellable>()
    
    init(chat: Chat, mesh: MeshService, persistence: PersistenceManager, myUUID: String) {
        self.chat = chat
        self.mesh = mesh
        self.persistence = persistence
        self.myUUID = myUUID
        loadMessages()
        
        // React to incoming messages
        // Replace the two NotificationCenter subscriptions in init() with these:

        NotificationCenter.default.publisher(for: .meshMessagePersisted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.loadMessages()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .meshAckPersisted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.loadMessages()
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadMessages() {
        messages = (chat.messages).sorted { $0.timestamp < $1.timestamp }
    }
    
    func sendMessage() {
        guard !draftText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let peer = chat.peer else { return }
        
        let text = draftText
        let msgId = UUID().uuidString
        draftText = ""
        isSending = true
        
        // Save locally first (optimistic update)
        let localMsg = InnerMessage(
            kind: .chat,
            messageId: msgId,
            senderId: myUUID,
            chatId: chat.id,
            text: text,
            timestamp: Date().timeIntervalSince1970,
            replyToId: nil
        )
        persistence.saveMessage(localMsg, direction: .outgoing)
        loadMessages()
        
        Task {
            do {
                try await mesh.sendMessage(
                    text: text,
                    to: peer.id,
                    chatId: chat.id,
                    messageId: msgId
                )
                persistence.updateMessageStatus(id: msgId, status: .sent)
            } catch {
                errorMessage = error.localizedDescription
                persistence.updateMessageStatus(id: msgId, status: .failed)
            }
            isSending = false
            loadMessages()
        }
    }
}
