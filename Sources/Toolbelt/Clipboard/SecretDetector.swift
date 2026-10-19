import Foundation

/// 복사한 텍스트가 비밀 값(API 키·토큰·개인 키 등)처럼 보이는지 판단한다.
/// 평범한 문장 속 비밀번호는 구별할 수 없으므로, 사용자가 기록에서 "비밀로 바꾸기"로 보완한다.
enum SecretDetector {
    /// 알려진 형식 → 표시 이름
    private static let patterns: [(regex: String, label: String)] = [
        (#"-----BEGIN [A-Z ]*PRIVATE KEY-----"#, "개인 키"),
        (#"^sk-(proj-|ant-)?[A-Za-z0-9_\-]{20,}$"#, "API 키"),
        (#"^(ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}$"#, "GitHub 토큰"),
        (#"^(AKIA|ASIA)[0-9A-Z]{16}$"#, "AWS 키"),
        (#"^xox[abposr]-[A-Za-z0-9\-]{10,}$"#, "Slack 토큰"),
        (#"^AIza[0-9A-Za-z_\-]{35}$"#, "Google API 키"),
        (#"^(sk|rk|pk)_(live|test)_[0-9A-Za-z]{16,}$"#, "Stripe 키"),
        (#"^eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}$"#, "토큰(JWT)"),
        (#"^[a-z][a-z0-9+.\-]*://[^\s:/]+:[^\s@/]+@"#, "비밀번호 포함 주소"),
    ]

    /// 비밀처럼 보이면 표시 이름, 아니면 nil
    static func detect(_ text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (regex, label) in patterns where s.range(of: regex, options: .regularExpression) != nil {
            return label
        }
        return looksRandom(s) ? "비밀 값" : nil
    }

    /// 공백 없는 긴 문자열이면서 글자 종류가 섞이고 무작위성이 높으면 키·토큰으로 본다.
    /// (주소·경로·일반 단어는 제외)
    private static func looksRandom(_ s: String) -> Bool {
        guard s.count >= 24, s.count <= 512, !s.contains(where: \.isWhitespace) else { return false }
        if s.contains("://") || s.hasPrefix("/") || s.hasPrefix("~") || s.contains("@") && s.contains(".") { return false }
        var classes = 0
        if s.contains(where: \.isLowercase) { classes += 1 }
        if s.contains(where: \.isUppercase) { classes += 1 }
        if s.contains(where: \.isNumber) { classes += 1 }
        guard classes >= 3 else { return false }
        // 문자당 섀넌 엔트로피 (무작위 base64 ≈ 5~6비트, 일반 단어 조합 ≈ 3~4비트)
        var counts: [Character: Int] = [:]
        for c in s { counts[c, default: 0] += 1 }
        let n = Double(s.count)
        let entropy = counts.values.reduce(0.0) { acc, c in
            let p = Double(c) / n
            return acc - p * log2(p)
        }
        return entropy >= 4.0
    }

    /// 기록에 보여줄 가린 미리보기 (예: "sk-p••••••7Q2a")
    static func mask(_ text: String) -> String {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("-----BEGIN") { return "-----BEGIN ••••••" }
        guard s.count >= 16 else { return "••••••••" }
        return "\(s.prefix(4))••••••\(s.suffix(4))"
    }
}
