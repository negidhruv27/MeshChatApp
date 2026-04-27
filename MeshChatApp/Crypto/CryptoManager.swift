import CryptoKit
import Foundation

actor CryptoManager {
    
    private let identityKey: Curve25519.KeyAgreement.PrivateKey
    private let signingKey: Curve25519.Signing.PrivateKey
    
    init() {
        self.identityKey = KeyStore.loadOrCreateIdentityKey()
        self.signingKey = KeyStore.loadOrCreateSigningKey()
    }
    
    func myPublicKeyData() -> Data {
        identityKey.publicKey.rawRepresentation
    }
    
    func mySigningPublicKeyData() -> Data {
        signingKey.publicKey.rawRepresentation
    }
    
    func encryptAndSign(
        _ payload: [String: Any],
        for peerPublicKeyData: Data
    ) throws -> String {
        
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        
        let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: peerPublicKeyData
        )
        
        let ephemeralPrivate = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublic = ephemeralPrivate.publicKey
        
        let sharedSecret = try ephemeralPrivate.sharedSecretFromKeyAgreement(
            with: peerPublicKey
        )
        
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephemeralPublic.rawRepresentation,
            sharedInfo: Data("meshchatapp-v1".utf8),
            outputByteCount: 32
        )
        
        let sealedBox = try AES.GCM.seal(
            payloadData,
            using: symmetricKey
        )
        
        guard let combined = sealedBox.combined else {
            throw CryptoError.sealingFailed
        }
        
        let signature = try signingKey.signature(for: combined)
        
        var blob = Data()
        blob.append(signature)
        blob.append(ephemeralPublic.rawRepresentation)
        blob.append(combined)
        
        return blob.base64EncodedString()
    }
    
    func decryptAndVerify(
        _ base64Blob: String,
        senderSigningKeyData: Data
    ) throws -> [String: Any] {
        
        guard let blob = Data(base64Encoded: base64Blob) else {
            throw CryptoError.invalidBase64
        }
        
        guard blob.count > 96 else {
            throw CryptoError.malformedPayload
        }
        
        let signatureData = Data(blob.prefix(64))
        let ephemeralPubData = Data(blob[64..<96])
        let combined = Data(blob.suffix(from: 96))
        
        let senderSigningKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: senderSigningKeyData
        )

        guard senderSigningKey.isValidSignature(
            signatureData,
            for: combined
        ) else {
            throw CryptoError.invalidSignature
        }
        
        let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: ephemeralPubData
        )
        
        let sharedSecret = try identityKey.sharedSecretFromKeyAgreement(
            with: ephemeralPublicKey
        )
        
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephemeralPubData,
            sharedInfo: Data("meshchatapp-v1".utf8),
            outputByteCount: 32
        )
        
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        
        let plaintext = try AES.GCM.open(
            sealedBox,
            using: symmetricKey
        )
        
        guard let dict = try JSONSerialization.jsonObject(
            with: plaintext
        ) as? [String: Any] else {
            throw CryptoError.invalidPayload
        }
        
        return dict
    }
}

enum CryptoError: LocalizedError {
    case sealingFailed
    case invalidBase64
    case malformedPayload
    case invalidSignature
    case invalidPayload
    
    var errorDescription: String? {
        switch self {
        case .sealingFailed:
            return "Failed to encrypt message."
            
        case .invalidBase64:
            return "Invalid Base64 payload."
            
        case .malformedPayload:
            return "Malformed encrypted payload."
            
        case .invalidSignature:
            return "Message signature verification failed."
            
        case .invalidPayload:
            return "Invalid decrypted payload."
        }
    }
}
