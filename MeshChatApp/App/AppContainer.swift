import Foundation
import Combine
import UIKit
@MainActor
final class AppContainer: ObservableObject {
    
    static let placeholder = AppContainer()
    let myUUID: String
    let crypto: CryptoManager
    let meshService: MeshService
    let persistence: PersistenceManager
    
    init() {
        if let stored = UserDefaults.standard.string(forKey: "myUUID") {
            self.myUUID = stored
        } else {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: "myUUID")
            self.myUUID = new
        }
        
        let displayName = Self.meshDisplayName(
            deviceName: UIDevice.current.name,
            uuid: myUUID
        )
        
        self.crypto = CryptoManager()
        
        self.meshService = MeshService(
            crypto: crypto,
            myUUID: myUUID,
            displayName: displayName
        )
        
        self.persistence = .shared
        
        NotificationCenter.default.addObserver(
            forName: .meshPeerHandshaked,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let handshake = notification.object as? HandshakePayload else { return }
            Task { @MainActor in
                self.persistence.upsertPeer(from: handshake, myUUID: self.myUUID)  // ✅ pass local UUID
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .meshMessageReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let inner = notification.object as? InnerMessage else { return }
            
            Task { @MainActor in
                self?.persistence.saveMessage(inner, direction: .incoming)
                NotificationCenter.default.post(name: .meshMessagePersisted, object: inner)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .meshAckReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let inner = notification.object as? InnerMessage else { return }
            
            Task { @MainActor in
                self?.persistence.updateMessageStatus(
                    id: inner.messageId,
                    status: .delivered
                )
                NotificationCenter.default.post(name: .meshAckPersisted, object: inner)
            }
        }
    }
    
    func start() {
        meshService.startMesh()
    }

    private static func meshDisplayName(deviceName: String, uuid: String) -> String {
        let suffix = String(uuid.prefix(4))
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = name.isEmpty ? "Device" : name
        return "\(base.prefix(58))-\(suffix)"
    }
}
