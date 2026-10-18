# 배포 계획 (일반 공개, GitHub Releases)

## 결정 (2026-10-18)

- Mac App Store는 샌드박스 필수라 **디스플레이 연결 해제(비공개 API)·Caps Lock 리매핑**을 유지할 수 없어 제외.
- Developer ID 인증서(공증 배포)는 지금 발급할 수 없어 보류.
- **공개 GitHub 저장소 + Releases에 자체 서명(`Toolbelt Signing`) zip**으로 배포한다. 각자 빌드 안내는 만들지 않는다.
- 나중에 사용자가 늘면 Developer ID 서명 + 공증만 추가하면 된다 (나머지 구조는 그대로).

## 이 방식의 특징

- 공증이 없어 처음 열 때 macOS가 막는다 → 사용자가 **시스템 설정 → 개인정보 보호 및 보안 → "그래도 열기"** 한 번.
- **같은 자체 서명 인증서로 계속 서명하면** 업데이트해도 사용자 권한(손쉬운 사용·마이크·화면 녹음)이 유지된다.
  ad-hoc 서명은 빌드마다 서명이 바뀌어 업데이트할 때마다 권한이 초기화되므로 쓰지 않는다 (`make release`가 막음).
- `Toolbelt Signing` 인증서를 잃으면 새 인증서로 서명해야 하고, 모든 사용자가 권한을 다시 줘야 한다 → **반드시 .p12로 백업**.

## 할 일

### 지금 (관리자)
- [x] `Toolbelt Signing` 인증서 백업: 키체인 접근 → 로그인 → 내 인증서 → `Toolbelt Signing` 우클릭 → 내보내기 → `.p12`(암호 설정) → 안전한 곳(비밀번호 관리자 등)에 보관
- [x] 라이선스: MIT (`LICENSE`)
- [ ] 공개 전 저장소 내용 점검 — 아래 "공개 전 점검" 참고
- [ ] 저장소 공개 전환 (GitHub → Settings → Change visibility)
- [ ] 앱 이름("Toolbelt") 겹침 확인 (선택)

### 코드 (완료/진행)
- [x] `make release` → `build/Toolbelt-<버전>.zip` (자체 서명 필수, 서명 검증 포함)
- [x] Caps Lock 리매핑·통화 자동 녹음 **기본 꺼짐**
- [x] README 설치 안내
- [ ] 첫 실행 안내 화면 (권한 3종, F19 단축키)
- [ ] 전사 언어 선택 (현재 ko-KR 고정)
- [ ] 정보 화면 (버전), 업데이트 확인 — 처음에는 GitHub Releases 링크, 나중에 Sparkle
- [ ] (선택) 영어

### 릴리스 절차
1. `Info.plist`의 `CFBundleShortVersionString`(예: 0.1.0 → 0.2.0)과 `CFBundleVersion`(정수 +1) 올리기
2. `make release`
3. GitHub → Releases → Draft a new release → 태그 `v0.2.0`, 변경 내용 작성, `build/Toolbelt-0.2.0.zip` 첨부 → Publish
   (`gh release create v0.2.0 build/Toolbelt-0.2.0.zip --notes "..."` 로도 가능)

## 공개 전 점검

저장소를 공개하면 **커밋 기록 전체**와 작성자 정보가 공개된다.
- 공개 저장소에는 개인 정보가 없는 현재 상태만 올린다 (기존 비공개 기록은 올리지 않음).
- 개인 환경·계정 메모는 `CLAUDE.local.md`(gitignore)에 둔다.
- 커밋 작성자 이메일은 GitHub noreply 주소를 쓴다 (`git config user.email <id>+<name>@users.noreply.github.com`).
- 올리기 전 확인: `git grep -n -i -E '<이름>|<회사>|<경로>|password|token|api[_-]?key|PRIVATE KEY'`

## 나중에: Developer ID + 공증으로 올릴 때

1. 이 Mac에서 CSR 생성 (키체인 접근 → 인증서 지원 → 인증 기관에서 인증서 요청 → 디스크에 저장)
2. 개발자 계정 소유자에게 CSR 전달 → Developer ID Application (G2 Sub-CA) 발급 → `.cer`를 받아 이 Mac에서 열기
3. `codesign --options runtime --entitlements`(`com.apple.security.device.audio-input` 포함)로 서명
4. `xcrun notarytool store-credentials` → `notarytool submit --wait` → `stapler staple`
5. 서명 인증서가 바뀌므로 기존 사용자는 권한을 한 번 다시 줘야 한다 (전환 시 안내)
6. Sparkle 자동 업데이트(EdDSA 키, appcast)도 이때 붙이는 것이 좋다
