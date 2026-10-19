import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// 클립보드 기록 항목. 비밀 항목은 값을 키체인에만 두고 여기에는 가린 미리보기만 둔다.
struct ClipItem: Codable, Identifiable, Equatable {
    let id: UUID
    var date: Date
    var isSecret: Bool
    /// 일반 항목의 원문 (비밀 항목은 nil)
    var text: String?
    /// 목록에 보여줄 한 줄 (비밀 항목은 가린 값)
    var preview: String
    /// 비밀 종류 (예: "API 키") 또는 nil
    var label: String?
    /// 복사한 앱 이름
    var source: String?
}

/// 기록 파일에 담는 내용: 항목 + 비밀로 기억한 값의 지문
struct ClipboardData: Codable {
    var items: [ClipItem]
    /// "비밀로 바꾸기"한 값의 HMAC 지문 — 같은 값을 다시 복사하면 처음부터 비밀로 저장한다
    var rememberedSecrets: Set<String>
}

/// 기록 파일(AES-GCM 암호화, 키는 키체인)과 비밀 값(키체인) 저장.
///   ~/Library/Application Support/Toolbelt/clipboard.dat
enum ClipboardStore {
    private static let service = "kr.clo3olb.toolbelt"
    private static let historyKeyAccount = "clipboard-history-key"
    private static let fingerprintKeyAccount = "clipboard-fingerprint-key"
    private static let secretPrefix = "clipboard-secret-"

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Toolbelt/clipboard.dat")
    }

    // MARK: - 기록 파일

    static func load() -> ClipboardData {
        let empty = ClipboardData(items: [], rememberedSecrets: [])
        guard let sealed = try? Data(contentsOf: fileURL),
              let key = historyKey(create: false),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: key) else { return empty }
        if let decoded = try? JSONDecoder().decode(ClipboardData.self, from: data) { return decoded }
        // 예전 형식: 항목 배열만
        return ClipboardData(items: (try? JSONDecoder().decode([ClipItem].self, from: data)) ?? [], rememberedSecrets: [])
    }

    static func save(_ contents: ClipboardData) {
        guard let key = historyKey(create: true) else { return }
        guard let data = try? JSONEncoder().encode(contents),
              let sealed = try? AES.GCM.seal(data, using: key).combined else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? sealed.write(to: fileURL, options: .atomic)
    }

    static func deleteFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 기록 파일 암호화 키 (처음이면 만들어 키체인에 저장)
    private static func historyKey(create: Bool) -> SymmetricKey? {
        if let data = readKeychain(account: historyKeyAccount) { return SymmetricKey(data: data) }
        guard create else { return nil }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        return writeKeychain(data, account: historyKeyAccount) ? key : nil
    }

    // MARK: - 지문 (HMAC-SHA256, 키는 키체인)

    /// 원래 값으로 되돌릴 수 없고, 키 없이는 짧은 비밀번호를 대입해 맞춰 볼 수도 없다.
    static func fingerprint(_ text: String) -> String? {
        guard let key = fingerprintKey() else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(normalized.utf8), using: key)
        return Data(mac).base64EncodedString()
    }

    private static func fingerprintKey() -> SymmetricKey? {
        if let data = readKeychain(account: fingerprintKeyAccount) { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        return writeKeychain(key.withUnsafeBytes { Data($0) }, account: fingerprintKeyAccount) ? key : nil
    }

    // MARK: - 비밀 값

    @discardableResult
    static func saveSecret(_ text: String, id: UUID) -> Bool {
        writeKeychain(Data(text.utf8), account: secretPrefix + id.uuidString)
    }

    static func deleteSecret(id: UUID) {
        deleteKeychain(account: secretPrefix + id.uuidString)
    }

    /// Touch ID 또는 Mac 암호로 확인한 뒤 비밀 값을 돌려준다.
    static func readSecretAuthenticated(id: UUID, reason: String) async -> String? {
        let context = LAContext()
        guard (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true,
              let data = readKeychain(account: secretPrefix + id.uuidString) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 키체인 (일반 암호 항목)

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func readKeychain(account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    private static func writeKeychain(_ data: Data, account: String) -> Bool {
        deleteKeychain(account: account)
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrLabel as String] = "Toolbelt 클립보드"
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { NSLog("Toolbelt: 키체인 저장 실패 (\(status))") }
        return status == errSecSuccess
    }

    private static func deleteKeychain(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
