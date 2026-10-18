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
- [x] 공개 전 저장소 내용 점검
- [x] 공개 저장소 `clo3olb/toolbelt` (정리된 상태를 커밋 하나로 시작), v0.1.0 게시
- [ ] 앱 이름("Toolbelt") 겹침 확인 (선택)

### 코드 (완료/진행)
- [x] `make release` → `build/Toolbelt-<버전>.zip` (자체 서명 필수, 서명 검증 포함)
- [x] Caps Lock 리매핑·통화 자동 녹음 **기본 꺼짐**
- [x] README 설치 안내
- [x] 첫 실행 안내 화면 (권한 3종, 선택 기능)
- [ ] 전사 언어 선택 (현재 ko-KR 고정)
- [x] 정보(버전)·업데이트 확인·자동 업데이트 — Sparkle (0.2.0)
- [ ] (선택) 영어

### 릴리스 절차 (자동 업데이트 포함)
1. `Info.plist`의 `CFBundleShortVersionString`(예: 0.2.0 → 0.3.0)과 `CFBundleVersion`(정수 +1 — Sparkle은 이 값으로 새 버전을 판단) 올리기
2. 변경 내용을 `docs/releases/<버전>.md`에 쓰기 (## 제목, - 목록, **굵게** 정도의 마크다운)
3. 커밋·push
4. `make publish NOTES=docs/releases/<버전>.md` — 미리 보려면 앞에 `DRY_RUN=1`
   - 빌드·서명 → zip → EdDSA 서명·검증 → `appcast.xml` 생성 → `gh release create`로 zip과 appcast.xml 게시 → 피드 확인
   - 사용자의 앱은 `https://github.com/clo3olb/toolbelt/releases/latest/download/appcast.xml`을 하루 한 번 확인한다

### 자동 업데이트 (Sparkle)
- Sparkle 2.9.x (SwiftPM). `Contents/Frameworks/Sparkle.framework`에 넣고 안쪽 실행 파일부터 같은 인증서로 서명 (`make app`).
- 업데이트 서명 키: EdDSA, 키체인 계정 `clo3olb-toolbelt`. 공개 키는 `Info.plist`의 `SUPublicEDKey`.
- **개인 키를 잃으면 기존 사용자에게 업데이트를 보낼 수 없다** → 백업 필수:
  `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account clo3olb-toolbelt -x <파일>` 로 내보내 안전한 곳에 보관,
  새 Mac에서는 `-f <파일>`로 가져온다.
- appcast에는 최신 버전 하나만 담는다 (`releases/latest`가 항상 최신 릴리스를 가리킴).

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
