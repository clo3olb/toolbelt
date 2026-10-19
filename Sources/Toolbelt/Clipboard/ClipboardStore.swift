import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// 클립보드 기록 항목. 비밀 항목은 원문 대신 보안 칩 키로 암호화한 값(sealedSecret)과 가린 미리보기만 둔다.
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
    /// 비밀 항목의 값 — Touch ID/암호가 있어야 쓸 수 있는 보안 칩 키로 암호화 (임시 공개키 65바이트 + AES-GCM)
    var sealedSecret: Data? = nil
}

/// 기록 파일에 담는 내용: 항목 + 비밀로 기억한 값의 지문
struct ClipboardData: Codable {
    var items: [ClipItem]
    /// "비밀로 바꾸기"한 값의 HMAC 지문 — 같은 값을 다시 복사하면 처음부터 비밀로 저장한다
    var rememberedSecrets: Set<String>
}

/// 클립보드 기록 저장. 키체인을 쓰지 않고 **보안 칩(Secure Enclave)** 키를 쓴다.
///
/// 자체 서명 앱은 팀 ID가 없어 키체인 항목이 빌드별 cdhash에 묶이고, 다시 빌드·업데이트할 때마다
/// 로그인 암호 창이 뜬다. 보안 칩 키는 앱 서명과 무관하고 이 Mac 밖에서는 쓸 수 없다.
///   ~/Library/Application Support/Toolbelt/clipboard-keys.json — 보안 칩 키 묶음(이 Mac에서만 의미 있음)
///   ~/Library/Application Support/Toolbelt/clipboard-v2.dat     — 기록 (AES-GCM)
enum ClipboardStore {
    private struct Keys: Codable {
        /// 인증 없이 쓰는 보안 칩 키 → 기록 파일 키·지문 키를 만든다
        var openKey: Data
        /// 키 합의에 쓰는 고정 상대 공개키
        var peer: Data
        /// Touch ID/암호가 있어야 쓰는 보안 칩 키 → 비밀 항목 복호화
        var guardedKey: Data
        var guardedPublic: Data
    }

    enum StoreError: LocalizedError {
        case secureEnclaveUnavailable
        var errorDescription: String? { "이 Mac에서는 보안 칩(Secure Enclave)을 쓸 수 없어 클립보드 기록을 암호화할 수 없습니다." }
    }

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Toolbelt")
    }
    static var fileURL: URL { folder.appendingPathComponent("clipboard-v2.dat") }
    private static var keysURL: URL { folder.appendingPathComponent("clipboard-keys.json") }
    /// 예전 형식 (키체인 키로 암호화) — 읽으려면 로그인 암호 창이 뜨므로 버린다
    private static var legacyURL: URL { folder.appendingPathComponent("clipboard.dat") }

    nonisolated(unsafe) private static var cachedKeys: Keys?
    nonisolated(unsafe) private static var cachedHistoryKey: SymmetricKey?
    nonisolated(unsafe) private static var cachedFingerprintKey: SymmetricKey?

    // MARK: - 키

    private static func keys() throws -> Keys {
        if let cachedKeys { return cachedKeys }
        guard SecureEnclave.isAvailable else { throw StoreError.secureEnclaveUnavailable }
        if let data = try? Data(contentsOf: keysURL), let keys = try? JSONDecoder().decode(Keys.self, from: data) {
            cachedKeys = keys
            return keys
        }
        // 처음: 보안 칩 키 두 개를 만든다
        let open = try SecureEnclave.P256.KeyAgreement.PrivateKey()
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           [.privateKeyUsage, .userPresence], &error) else {
            throw error!.takeRetainedValue() as Error
        }
        let guarded = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        let keys = Keys(openKey: open.dataRepresentation,
                        peer: P256.KeyAgreement.PrivateKey().publicKey.x963Representation,
                        guardedKey: guarded.dataRepresentation,
                        guardedPublic: guarded.publicKey.x963Representation)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(keys).write(to: keysURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keysURL.path)
        cachedKeys = keys
        return keys
    }

    /// 인증 없는 보안 칩 키 + 고정 상대 공개키로 용도별 대칭 키를 만든다 (실행할 때마다 같은 값)
    private static func derivedKey(_ purpose: String) throws -> SymmetricKey {
        let keys = try keys()
        let open = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: keys.openKey)
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: keys.peer)
        return try open.sharedSecretFromKeyAgreement(with: peer)
            .hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("toolbelt-clipboard".utf8),
                                     sharedInfo: Data(purpose.utf8), outputByteCount: 32)
    }

    private static func historyKey() throws -> SymmetricKey {
        if let cachedHistoryKey { return cachedHistoryKey }
        let key = try derivedKey("history")
        cachedHistoryKey = key
        return key
    }

    // MARK: - 기록 파일

    static func load() -> ClipboardData {
        try? FileManager.default.removeItem(at: legacyURL)
        let empty = ClipboardData(items: [], rememberedSecrets: [])
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let sealed = try? Data(contentsOf: fileURL),
              let key = try? historyKey(),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: key) else { return empty }
        return (try? JSONDecoder().decode(ClipboardData.self, from: data)) ?? empty
    }

    static func save(_ contents: ClipboardData) {
        guard let key = try? historyKey(),
              let data = try? JSONEncoder().encode(contents),
              let sealed = try? AES.GCM.seal(data, using: key).combined else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? sealed.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    // MARK: - 지문 (HMAC-SHA256)

    /// 원래 값으로 되돌릴 수 없고, 보안 칩 키 없이는 짧은 비밀번호를 대입해 맞춰 볼 수도 없다.
    static func fingerprint(_ text: String) -> String? {
        if cachedFingerprintKey == nil { cachedFingerprintKey = try? derivedKey("fingerprint") }
        guard let key = cachedFingerprintKey else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(HMAC<SHA256>.authenticationCode(for: Data(normalized.utf8), using: key)).base64EncodedString()
    }

    // MARK: - 비밀 값

    /// 공개키로만 암호화하므로 인증 창이 뜨지 않는다
    static func sealSecret(_ text: String) -> Data? {
        guard let keys = try? keys(),
              let guardedPublic = try? P256.KeyAgreement.PublicKey(x963Representation: keys.guardedPublic) else { return nil }
        let ephemeral = P256.KeyAgreement.PrivateKey()
        guard let shared = try? ephemeral.sharedSecretFromKeyAgreement(with: guardedPublic) else { return nil }
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("toolbelt-secret".utf8),
                                                 sharedInfo: Data(), outputByteCount: 32)
        guard let sealed = try? AES.GCM.seal(Data(text.utf8), using: key).combined else { return nil }
        return ephemeral.publicKey.x963Representation + sealed
    }

    /// Touch ID 또는 Mac 암호로 확인한 뒤 비밀 값을 푼다 (보안 칩이 확인을 강제한다)
    static func openSecret(_ sealedSecret: Data, reason: String) async -> String? {
        guard sealedSecret.count > 65, let keys = try? keys() else { return nil }
        let context = LAContext()
        guard (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true,
              let guarded = try? SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: keys.guardedKey,
                                                                            authenticationContext: context),
              let ephemeral = try? P256.KeyAgreement.PublicKey(x963Representation: sealedSecret.prefix(65)),
              let shared = try? guarded.sharedSecretFromKeyAgreement(with: ephemeral) else { return nil }
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("toolbelt-secret".utf8),
                                                 sharedInfo: Data(), outputByteCount: 32)
        guard let box = try? AES.GCM.SealedBox(combined: sealedSecret.dropFirst(65)),
              let data = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
