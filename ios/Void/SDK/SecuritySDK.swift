import Foundation
import CryptoKit
import LocalAuthentication
import Security

@MainActor
final class SecuritySDK: SDKModule {
    private func keychainQuery(_ name: String, _ project: UUID, crypto: Bool) throws -> [String: Any] {
        guard !name.isEmpty else { throw SDKFailure.invalid("key") }
        return [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"app.chkf.void." + project.uuidString + (crypto ? ".keys" : ".secrets"), kSecAttrAccount as String:name]
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw SDKFailure("KEYCHAIN_ERROR", (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain \(status)") }
    }
    private func read(_ q: [String: Any]) throws -> Data? {
        var query = q, value: CFTypeRef?
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return value as? Data
    }
    private func put(_ bytes: Data, _ query: [String: Any]) throws {
        let attrs: [String: Any] = [kSecValueData as String: bytes, kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { try check(SecItemAdd(query.merging(attrs) { _, b in b } as CFDictionary, nil)) }
        else { try check(status) }
    }
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        switch method {
        case "hash": return SHA256.hash(data: try a.data("data")).map { String(format: "%02x", $0) }.joined()
        case "random":
            var bytes = [UInt8](repeating: 0, count: try a.int("length", range: 1...65536))
            try check(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes))
            return Data(bytes).base64EncodedString()
        case "setSecret", "getSecret", "deleteSecret":
            let q = try keychainQuery(a.string("key"), s.record.id, crypto: false)
            if method == "setSecret" { try put(Data(try a.string("value").utf8), q) }
            else if method == "getSecret" { return try read(q).flatMap { String(data: $0, encoding: .utf8) } as Any? ?? NSNull() }
            else { let result = SecItemDelete(q as CFDictionary); if result != errSecItemNotFound { try check(result) } }
        case "encrypt", "decrypt":
            let q = try keychainQuery(a.string("key"), s.record.id, crypto: true)
            let key: SymmetricKey
            if let bytes = try read(q) { key = SymmetricKey(data: bytes) }
            else if method == "encrypt" {
                key = SymmetricKey(size: .bits256)
                try key.withUnsafeBytes { try put(Data($0), q) }
            } else { throw SDKFailure("NOT_FOUND", "该项目没有对应密钥") }
            let data = try a.data("data")
            if method == "encrypt" {
                guard let sealed = try AES.GCM.seal(data, using: key).combined else { throw SDKFailure("ENCRYPTION_FAILED", "无法生成密文") }
                return sealed.base64EncodedString()
            }
            return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key).base64EncodedString()
        case "biometricType", "authenticate":
            let context = LAContext()
            var error: NSError?
            let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            if method == "biometricType" {
                return available ? (context.biometryType == .faceID ? "faceID" : (context.biometryType == .touchID ? "touchID" : "other")) : "none"
            }
            guard available else { throw SDKFailure.unavailable(error?.localizedDescription ?? "生物识别不可用") }
            let reason = try a.string("reason", "验证当前项目的操作")
            guard !reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw SDKFailure.invalid("reason") }
            return try await withTaskCancellationHandler {
                try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            } onCancel: { context.invalidate() }
        default: throw SDKFailure("UNKNOWN_METHOD", method)
        }
        return NSNull()
    }
}
