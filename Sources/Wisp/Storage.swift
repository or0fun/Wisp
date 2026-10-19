import Foundation
import Security

final class DiskStore {
    let directory: URL
    let images: URL
    init(directory: URL? = nil) throws {
        // Keep the original location so renaming the app preserves existing data.
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PersonalAI", isDirectory: true)
        images = self.directory.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.directory.path)
    }
    func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do { return try JSONDecoder().decode(type, from: data) }
        catch {
            let backup = directory.appendingPathComponent("\(name).corrupt-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: url, to: backup)
            throw AppError.message("\(name) 读取失败，原始文件已备份。\(error.localizedDescription)")
        }
    }
    func save<T: Encodable>(_ value: T, to name: String) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(encoder.encode(value), to: directory.appendingPathComponent(name))
    }
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum Keychain {
    // This stable service identifier preserves access to existing API keys.
    private static let service = "com.fangjun.personalai"
    static func read(account: String = "doubao-api-key") throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else { throw AppError.message("无法读取钥匙串密钥（\(status)）。") }
        return value
    }
    static func save(_ value: String, account: String = "doubao-api-key") throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError.message("无法删除钥匙串密钥（\(status)）。") }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var new = query; attributes.forEach { new[$0.key] = $0.value }
            let added = SecItemAdd(new as CFDictionary, nil)
            guard added == errSecSuccess else { throw AppError.message("无法保存钥匙串密钥（\(added)）。") }
        } else if status != errSecSuccess { throw AppError.message("无法更新钥匙串密钥（\(status)）。") }
    }
}
