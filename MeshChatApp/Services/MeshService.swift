import MultipeerConnectivity
import CryptoKit
import Foundation
import Combine

/// The service type identifier — must match NSBonjourServices in Info.plist.
/// Replaces: UDP port 8082 discovery + TCP port 8081 messaging.
private let kServiceType = "meshchatapp"

// MARK: - Handshake Payload (sent immediately on connection)
// Replaces: {"type": "handshake", "uuid": ..., "public_key": ...}

struct HandshakePayload: Codable {
    let type: String            // "handshake"
    let peerId: String          // sender UUID
    let identityPublicKey: Data // Curve25519.KeyAgreement public key
    let signingPublicKey: Data  // Curve25519.Signing public key
    let displayName: String
}

// MARK: - Outer Mesh Packet
// Replaces: {"receiver_id": ..., "message": "encrypted_blob"}

struct MeshPacket: Codable {
    let packetId: String        // UUID for dedup (replaces payload_hash)
    let receiverId: String      // target peer UUID, or "*" for broadcast
    let encryptedBlob: String   // base64 blob from CryptoManager
    let senderMCPeerId: String  // for mesh relaying
}

// MARK: - Inner Decrypted Message
// Replaces: inner_payload dict

struct InnerMessage: Codable {
    enum Kind: String, Codable {
        case chat        // replaces message_text
        case ack         // replaces acknowledgement
    }
    let kind: Kind
    let messageId: String
    let senderId: String
    let chatId: String
    let text: String?       // non-nil for .chat
    let timestamp: Double   // Unix timestamp
    let replyToId: String?
}

// MARK: - MeshService

/// Observable service — ViewModels subscribe to this via Combine.
/// Replaces: BluetoothMeshNode + ChatApp combined.
@MainActor
final class MeshService: NSObject, ObservableObject {
    
    // MARK: Published State
    
    @Published var nearbyPeers: [MCPeerID] = []           // browsed but not yet connected
    @Published var connectedPeers: [MCPeerID] = []        // active MCSession peers
    @Published var receivedMessages: [InnerMessage] = []  // incoming decrypted messages
    @Published var ackReceived: [String: Date] = [:]      // messageId → ACK timestamp
    @Published var connectionState: ConnectionState = .idle
    
    enum ConnectionState {
        case idle, advertising, browsing, connecting, connected
    }
    
    // MARK: Private State
    
    let myPeerId: MCPeerID
    let myUUID: String
    
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let crypto: CryptoManager
    
    // Dedup set — replaces: self.seen_messages in BluetoothMeshNode
    private var seenPacketIds = Set<String>()
    private var pendingInvites = Set<String>()
    
    // Peer metadata keyed by UUID
    private var peerMetadata: [String: HandshakePayload] = [:]
    
    // MARK: - Init
    
    init(crypto: CryptoManager, myUUID: String, displayName: String) {
        self.crypto = crypto
        self.myUUID = myUUID
        
        // MCPeerID = your identity on the mesh
        // displayName is shown during peer discovery
        self.myPeerId = MCPeerID(displayName: displayName)
        
        // MCSession: the connection manager
        // encryptionPreference .required adds TLS — extra layer on top of our CryptoKit
        self.session = MCSession(
            peer: myPeerId,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        
        // Advertiser: "I'm here, come find me"
        // Replaces: UDP MESH_ACK responder thread
        self.advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerId,
            discoveryInfo: ["uuid": myUUID],
            serviceType: kServiceType
        )
        
        // Browser: "Who's nearby?"
        // Replaces: UDP MESH_DISCOVER sender
        self.browser = MCNearbyServiceBrowser(
            peer: myPeerId,
            serviceType: kServiceType
        )
        
        super.init()
        
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }
    
    // MARK: - Start / Stop
    // Replaces: BluetoothMeshNode.__init__ which starts threads
    
    func startMesh() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        connectionState = .advertising
    }
    
    func stopMesh() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        nearbyPeers.removeAll()
        connectedPeers.removeAll()
        pendingInvites.removeAll()
        connectionState = .idle
    }
    
    // MARK: - Connect to Peer
    // Replaces: node.connect_to_peer(address_string)
    // In MultipeerConnectivity, we invite instead of TCP-connect.
    
    func invitePeer(_ peerID: MCPeerID) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        connectionState = .connecting
    }
    
    // MARK: - Send Encrypted Message
    // Replaces: app.send_message(receiver_id, chat_id, text)
    
    func sendMessage(
        text: String,
        to receiverId: String,
        chatId: String,
        messageId: String = UUID().uuidString,
        replyToId: String? = nil
    ) async throws {
        guard let peerMeta = peerMetadata[receiverId] else {
            throw MeshError.peerNotFound
        }
        
        // Build inner payload (same fields as Python's inner_payload dict)
        let inner = InnerMessage(
            kind: .chat,
            messageId: messageId,
            senderId: myUUID,
            chatId: chatId,
            text: text,
            timestamp: Date().timeIntervalSince1970,
            replyToId: replyToId
        )
        let innerData = try JSONEncoder().encode(inner)
        let innerDict = try JSONSerialization.jsonObject(with: innerData) as! [String: Any]
        
        // Encrypt + sign using CryptoManager
        let encryptedBlob = try await crypto.encryptAndSign(
            innerDict,
            for: peerMeta.identityPublicKey
        )
        
        // Wrap in outer mesh packet
        let packet = MeshPacket(
            packetId: UUID().uuidString,
            receiverId: receiverId,
            encryptedBlob: encryptedBlob,
            senderMCPeerId: myPeerId.displayName
        )
        
        try broadcastPacket(packet)
    }
    
    // MARK: - Broadcast Packet (Gossip)
    // Replaces: node.broadcast(payload) which sends to all peers
    
    private func broadcastPacket(_ packet: MeshPacket, markSeen: Bool = true) throws {
        if markSeen {
            guard !seenPacketIds.contains(packet.packetId) else { return }
            seenPacketIds.insert(packet.packetId)
        }
        
        let data = try JSONEncoder().encode(packet)
        let peers = session.connectedPeers.filter { $0.displayName != packet.senderMCPeerId }
        guard !peers.isEmpty else { throw MeshError.noPeersConnected }
        
        // .reliable = TCP-like delivery guarantee
        try session.send(data, toPeers: peers, with: .reliable)
    }
    
    // MARK: - Send Handshake
    // Replaces: perform_handshake() + return handshake logic
    
    private func sendHandshake(to peerID: MCPeerID) async throws {
        let handshake = HandshakePayload(
            type: "handshake",
            peerId: myUUID,
            identityPublicKey: await crypto.myPublicKeyData(),
            signingPublicKey: await crypto.mySigningPublicKeyData(),
            displayName: myPeerId.displayName
        )
        let data = try JSONEncoder().encode(handshake)
        try session.send(data, toPeers: [peerID], with: .reliable)
    }
    
    // MARK: - Send ACK
    // Replaces: _send_acknowledgement()
    
    private func sendAck(
        for messageId: String,
        chatId: String,
        to receiverId: String
    ) async throws {
        guard let peerMeta = peerMetadata[receiverId] else { return }
        
        let ack = InnerMessage(
            kind: .ack,
            messageId: messageId,
            senderId: myUUID,
            chatId: chatId,
            text: nil,
            timestamp: Date().timeIntervalSince1970,
            replyToId: nil
        )
        let ackData = try JSONEncoder().encode(ack)
        let ackDict = try JSONSerialization.jsonObject(with: ackData) as! [String: Any]
        
        let encryptedBlob = try await crypto.encryptAndSign(
            ackDict,
            for: peerMeta.identityPublicKey
        )
        let packet = MeshPacket(
            packetId: UUID().uuidString,
            receiverId: receiverId,
            encryptedBlob: encryptedBlob,
            senderMCPeerId: myPeerId.displayName
        )
        try broadcastPacket(packet)
    }
    
    // MARK: - Process Incoming Packet
    // Replaces: _handle_incoming_mesh_data() + _process_raw_payload()
    
    private func processIncomingData(_ data: Data, from peerID: MCPeerID) {
        Task {
            // Try to decode as handshake first
            if let handshake = try? JSONDecoder().decode(HandshakePayload.self, from: data) {
                await handleHandshake(handshake, from: peerID)
                return
            }
            
            // Try to decode as mesh packet
            guard let packet = try? JSONDecoder().decode(MeshPacket.self, from: data) else { return }
            
            // Dedup — replaces: if payload_hash in self.seen_messages
            guard !seenPacketIds.contains(packet.packetId) else { return }
            seenPacketIds.insert(packet.packetId)
            
            if packet.receiverId == myUUID {
                // This packet is for us — decrypt it
                await handleOwnPacket(packet)
            } else {
                // Not for us — relay it (gossip)
                // Replaces: if not is_for_us: self.broadcast(payload, origin_sock=source_sock)
                try? broadcastPacket(packet, markSeen: false)
            }
        }
    }
    
    // MARK: - Handle Handshake
    // Replaces: the "handshake" branch in _handle_incoming_mesh_data
    
    private func handleHandshake(_ handshake: HandshakePayload, from peerID: MCPeerID) async {
        let isNew = peerMetadata[handshake.peerId] == nil
        peerMetadata[handshake.peerId] = handshake
        
        // Return our handshake if this is the first time (mutual exchange)
        // Replaces: if is_new_peer and source_sock: send reply_payload
        if isNew {
            try? await sendHandshake(to: peerID)
        }
        
        // Notify persistence layer via NotificationCenter
        NotificationCenter.default.post(
            name: .meshPeerHandshaked,
            object: handshake
        )
    }
    
    // MARK: - Handle Own Packet
    // Replaces: _process_received_message() + _process_received_ack()
    
    private func handleOwnPacket(_ packet: MeshPacket) async {
        // Find sender's signing key for verification

        
        // Try each known peer's signing key (same fallback as Python's loop over peers)
        for (_, meta) in peerMetadata {
            do {
                let innerDict = try await crypto.decryptAndVerify(
                    packet.encryptedBlob,
                    senderSigningKeyData: meta.signingPublicKey
                )
                let innerData = try JSONSerialization.data(withJSONObject: innerDict)
                let inner = try JSONDecoder().decode(InnerMessage.self, from: innerData)
                
                switch inner.kind {
                case .chat:
                    receivedMessages.append(inner)
                    // Auto-send ACK
                    try? await sendAck(
                        for: inner.messageId,
                        chatId: inner.chatId,
                        to: inner.senderId
                    )
                    NotificationCenter.default.post(name: .meshMessageReceived, object: inner)
                    
                case .ack:
                    ackReceived[inner.messageId] = Date(timeIntervalSince1970: inner.timestamp)
                    NotificationCenter.default.post(name: .meshAckReceived, object: inner)
                }
                break
            } catch {
                continue
            }
        }
    }
}

// MARK: - MCSessionDelegate
// Replaces: _handle_client thread + connection/disconnection logic

extension MeshService: MCSessionDelegate {
    
    nonisolated func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        Task { @MainActor in
            switch state {
            case .connected:
                pendingInvites.remove(peerID.displayName)
                if !connectedPeers.contains(peerID) {
                    connectedPeers.append(peerID)
                }
                nearbyPeers.removeAll { $0 == peerID }
                connectionState = .connected
                // Send handshake immediately on connect
                // Replaces: sock.sendall(json.dumps(handshake_payload))
                try? await sendHandshake(to: peerID)
                
            case .notConnected:
                pendingInvites.remove(peerID.displayName)
                connectedPeers.removeAll { $0 == peerID }
                if !nearbyPeers.contains(peerID) {
                    nearbyPeers.append(peerID)
                }
                connectionState = connectedPeers.isEmpty ? .browsing : .connected
                
            case .connecting:
                connectionState = .connecting
                
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        // Replaces: _handle_client() which calls _process_raw_payload()
        Task { @MainActor in
            processIncomingData(data, from: peerID)
        }
    }
    
    // Required stubs (stream/resource sending not used yet)
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
// Replaces: _listen_for_discovery() which responds to MESH_DISCOVER pings

extension MeshService: MCNearbyServiceAdvertiserDelegate {
    
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Auto-accept all invitations (can add UI prompt here for production)
        Task { @MainActor in
            pendingInvites.remove(peerID.displayName)
            invitationHandler(true, session)
        }
    }
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Advertising error: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
// Replaces: UDP scan_network() which collected discovered device IPs

extension MeshService: MCNearbyServiceBrowserDelegate {
    
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            if !nearbyPeers.contains(peerID) && !connectedPeers.contains(peerID) {
                nearbyPeers.append(peerID)
            }

            // Make testing on two devices less fragile: only the lexicographically
            // lower stable peer name sends the invite, avoiding crossed invites.
            if myPeerId.displayName < peerID.displayName,
               !pendingInvites.contains(peerID.displayName),
               !connectedPeers.contains(peerID) {
                pendingInvites.insert(peerID.displayName)
                invitePeer(peerID)
            }
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            nearbyPeers.removeAll { $0 == peerID }
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Browsing error: \(error)")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let meshPeerHandshaked  = Notification.Name("meshPeerHandshaked")
    static let meshMessageReceived = Notification.Name("meshMessageReceived")
    static let meshAckReceived     = Notification.Name("meshAckReceived")
    static let meshMessagePersisted = Notification.Name("meshMessagePersisted")
    static let meshAckPersisted     = Notification.Name("meshAckPersisted")
}

// MARK: - Errors

enum MeshError: LocalizedError {
    case peerNotFound
    case noPeersConnected
    case encryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .peerNotFound:      return "Peer not found. Exchange handshake first."
        case .noPeersConnected:  return "No peers currently connected."
        case .encryptionFailed:  return "Failed to encrypt message."
        }
    }
}
