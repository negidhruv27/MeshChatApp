import CryptoKit
import Foundation
import Security

/// Persists Curve25519 keys in the iOS Keychain.
/// Replaces: Python's in-memory key generation each run.
struct KeyStore {
    
    private static let identityTag = "com.meshchatapp.identity.key"
    private static let signingTag  = "com.meshchatapp.signing.key"
    
    static func loadOrCreateIdentityKey() -> Curve25519.KeyAgreement.PrivateKey {
        if let data = load(tag: identityTag),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            return key
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        save(data: key.rawRepresentation, tag: identityTag)
        return key
    }
    
    static func loadOrCreateSigningKey() -> Curve25519.Signing.PrivateKey {
        if let data = load(tag: signingTag),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            return key
        }
        let key = Curve25519.Signing.PrivateKey()
        save(data: key.rawRepresentation, tag: signingTag)
        return key
    }
    
    private static func load(tag: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: tag,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }
    
    private static func save(data: Data, tag: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: tag,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
