import Foundation
import Security
import NoTypeCore

enum CloudCredentialStore {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.notype.speech-api", kSecAttrAccount as String: account]
    }
    static func read(account: String) throws -> String {
        var request = query(account)
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw CloudSpeechError("无法读取语音 API 钥匙串条目（\(status)）。请检查钥匙串授权。")
        }
        return key
    }
    static func save(_ key: String, account: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: { $0.isNewline }) else { throw CloudSpeechError("API Key 不能为空或包含换行。") }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let update = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw CloudSpeechError("保存语音 API Key 失败（\(update)）。") }
        var request = query(account)
        request[kSecValueData as String] = Data(value.utf8)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        guard status == errSecSuccess else { throw CloudSpeechError("保存语音 API Key 失败（\(status)）。") }
    }
    static func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CloudSpeechError("删除语音 API Key 失败（\(status)）。") }
    }
}
