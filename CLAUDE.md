# CLAUDE.md

macOS 메뉴바 유틸리티 앱 **Toolbelt**. 여러 기능을 계속 추가해 나가는 "도구 모음" 앱이다.
사용법·단축키·안전장치 상세는 `README.md`, 배포는 `docs/DISTRIBUTION.md` 참고.

이 파일은 저장소에 공개된다. 개인 환경·계정·작업 메모는 `CLAUDE.local.md`(gitignore됨)에 둔다.

## 빌드 / 설치

- 최소 macOS 26 (`Package.swift` `.macOS("26.0")`, `LSMinimumSystemVersion`) — SpeechAnalyzer 때문.
- Xcode 없이 **Command Line Tools + Swift Package Manager**로 빌드한다 (`swift build`).
- `make install` → `.build/` 빌드 → `build/Toolbelt.app` 번들링 → `Toolbelt Signing` 인증서로 서명 → `/Applications/Toolbelt.app` 설치 → 실행.
  설치 전 기존 앱은 `make quit`(osascript 정상 종료 → 녹음 중이면 파일 마무리, 10초 뒤 pkill)으로 끈다. `pkill`만 쓰면 녹음 파일이 마무리되지 않는다.
- `make release` → 배포용 `build/Toolbelt-<버전>.zip`. **항상 `Toolbelt Signing`으로 서명**해야 사용자 권한이 업데이트 후에도 유지된다 (ad-hoc 금지).
- 앱 아이콘: `Scripts/make-icon.swift`가 원본을 그리고 `make icon`이 `Resources/AppIcon.icns`를 만든다(커밋됨).
- 메인 창에서 ⌘C·⌘A·⌘W가 동작하도록 `main.swift`에서 최소 `NSApp.mainMenu`를 만든다 (LSUIElement라 메뉴바는 안 보임).
- `Info.plist`는 루트에 있고 Makefile이 번들에 복사한다. `LSUIElement`(Dock 아이콘 없음), 번들 ID `kr.clo3olb.toolbelt`.
  번들 ID를 바꾸면 모든 사용자의 권한·설정(UserDefaults)이 초기화된다.

### 권한·서명 주의

- 창 배치·브라우저 회의 감지는 **손쉬운 사용**, 녹음은 **마이크**와 **화면 및 시스템 오디오 녹음** 권한이 필요하다. 사용자가 직접 켜야 한다.
- 자체 서명 인증서 `Toolbelt Signing`은 `security find-identity`에 `CSSMERR_TP_NOT_TRUSTED`로 나오지만 정상이다.
- 인증서를 다시 만들거나 ad-hoc(`SIGN_ID=-`)으로 빌드하면 권한이 풀린다 → "설정에서 Toolbelt를 지우고 다시 추가" 안내.
- 다른 사람에게 영향이 큰 기능은 **기본 꺼짐**: Caps Lock 리매핑, 통화 자동 녹음.

## 구조

```
Sources/Toolbelt/
├── main.swift                 # AppDelegate: 상태 아이템, PanelController, 단축키 등록, 메인 메뉴
├── Panel/                     # 메뉴바 아이콘 클릭 시 SwiftUI 팝오버 (텍스트 메뉴 없음)
│   ├── PanelController.swift  # NSPopover, 열기 직전 앞 앱 기억 → 창 배치는 그 앱으로 돌아가 실행, 녹음 상태 아이콘
│   ├── PanelLayout.swift      # FeatureID(기능 목록), PanelLayout(팝오버 표시·순서, UserDefaults), LastAppTracker
│   ├── PanelModel.swift       # @MainActor 상태·동작 (팝오버와 메인 창이 각자 인스턴스), 열려 있을 때만 2초 갱신
│   └── PanelView.swift        # 팝오버 + 공용 부품(PanelSection, RingGauge, UsageBar, VolumeRow, DisplayRow, 기능별 섹션)
├── MainWindow/                # 메인 창 (사이드바: 기능별 상세 페이지 + 설정)
│   ├── MainWindowController.swift  # MainPage, 창 생성·표시, 창 배치는 LastAppTracker 앱에 적용
│   └── MainPages.swift        # 시스템/저장 장치/창 배치/디스플레이/키보드/설정 페이지
├── Onboarding/                # 첫 실행 안내 창 (권한·선택 기능)
├── Core/HotKeys.swift         # HotKey(Codable, display), Command, HotKeyCenter (Carbon, replaceGroup/removeGroup)
├── WindowSnap/                # 창 배치
│   ├── SnapAction.swift       # 40가지 배치(Rectangle 목록): 분류·이름·영역(unitRect)·기본 단축키·목표 프레임
│   ├── WindowMover.swift      # AX API로 포커스 창 이동, 원래대로(restoreFrames), 다음/이전 디스플레이, 옆 모니터 넘기기
│   ├── WindowSnapSettings.swift  # 종류별 켜기/끄기·단축키 저장(snapEnabled/snapHotKeys), 전역 단축키 재등록(group "windowSnap")
│   └── SnapViews.swift        # SnapGlyph(영역 아이콘), SnapTile(팝오버), ShortcutField(단축키 기록, 기록 중 단축키 해제)
├── Storage/StorageDevices.swift  # 마운트된 로컬 볼륨 용량, 꺼내기
├── Display/                   # 디스플레이
│   ├── DisplayManager.swift   # 연결 해제/재연결(비공개 API), 주 디스플레이 변경, 확인 다이얼로그
│   └── DisplayCommands.swift  # ⌃⌥⌘R 비상 복구
├── InputSwitch/CapsLockSwitch.swift  # Caps Lock→F19 리매핑 (macOS '이전 입력 소스 선택' 단축키를 F19로)
├── Recorder/                  # 녹음·전사
│   ├── CallDetector.swift     # 통화 감지: Core Audio 프로세스별 마이크 사용(2초 폴링) + CallApps 대상 목록, 브라우저는 AX 창 제목
│   ├── AudioRecorder.swift    # SCStream(.microphone / .audio)을 mic.m4a / system.m4a로 따로 기록, 트랙 시작 offset 계산
│   ├── RecordingStore.swift   # ~/Library/Application Support/Toolbelt/Recordings/<날짜>/, meta.json(길이·offset·제목, 녹음 시작 시 생성)
│   ├── RecordingController.swift  # @MainActor 싱글턴: 녹음 상태·권한, 자동 전사 대기열(하나씩, 실패는 수동 재시도), 통화 감지 연결
│   ├── RecordingPlayer.swift  # 두 트랙을 offset 맞춰 AVAudioPlayer 2개로 동시 재생
│   ├── RecordingsBrowser.swift # 메인 창 '녹음' 페이지 (HSplitView: 녹음 막대+목록 / 재생·대화·텍스트·복사·휴지통)
│   └── RecordingTranscriber.swift # SpeechAnalyzer로 트랙별 전사 → 시간순 "나/상대" transcript.txt + transcript-apple.json(구간·단어 시간·신뢰도)
├── LoginItem/LoginItem.swift  # 로그인 시 자동 실행 (SMAppService.mainApp)
└── SystemStats/SystemStats.swift  # CPU·메모리·저장 공간 측정(host_statistics(64), 볼륨 용량), 활성 상태 보기 열기
```

### 새 기능 추가 규칙

1. `Sources/Toolbelt/<기능>/` 폴더를 만든다.
2. 고정 단축키는 `Command`로 정의해 `HotKeyCenter.register(...)`, 사용자가 바꾸는 단축키는 `HotKeyCenter.replaceGroup(...)`으로 등록한다.
3. `FeatureID`에 case를 추가하고(팝오버 순서·표시는 자동으로 설정에 나타남), `PanelView.swift`의 `FeatureSection`에 팝오버 섹션,
   `MainWindowView`/`MainPages.swift`에 메인 창 페이지를 추가한다 (상태는 `PanelModel`, 팝오버 밖 다이얼로그는 `dismiss()` 후 실행).
   렌더링 확인: 팝오버·페이지 뷰를 화면 밖 NSHostingView로 그려 PNG로 볼 수 있다 (main.swift 제외 소스 + 렌더 main을 swiftc로 빌드).
   NavigationSplitView 창 전체·사이드바는 이 방식으로 그려지지 않으니 페이지 뷰를 따로 그린다.
4. `README.md`의 기능 섹션을 갱신한다.

## 단축키

| 기능 | 단축키 |
| --- | --- |
| 창 배치 (기본 21개, 메인 창에서 변경 가능) | ⌃⌥ + ←→↑↓ U I J K D F G E T ↩ = - C ⌫, ⌃⌥⇧↑, ⌃⌥⌘←/→ |
| 모든 디스플레이 다시 연결 (비상 복구) | ⌃⌥⌘R (창 배치에 지정 불가) |
| 한/영 전환 | Caps Lock (→ F19 리매핑, F19는 다른 용도로 쓰지 말 것) |

디스플레이 연결 해제·주 디스플레이 변경은 팝오버·메인 창으로만 가능하다 (단축키 없음).

## 디스플레이 기능 — 반드시 지킬 안전장치

`CGSConfigureDisplayEnabled`는 **비공개 API**다 (`@_silgen_name`으로 선언, CoreGraphics가 재export). macOS 업데이트로 깨질 수 있다.
이 기능을 수정할 때 아래 안전장치를 절대 제거하지 않는다.

1. 마지막 남은 활성 디스플레이는 연결 해제 불가 (버튼 비활성 + 코드 가드).
2. 연결 해제 후 15초 확인 다이얼로그 — 응답 없으면 자동 재연결.
3. 연결 해제는 `.forSession`으로 적용 — 로그아웃/재부팅 시 원복. (주 디스플레이 변경은 `.permanently`)
4. 해제한 디스플레이 ID/이름을 UserDefaults(`disabledDisplays`)에 저장 → 앱 재시작 후에도 팝오버/⌃⌥⌘R로 재연결 가능.
5. ⌃⌥⌘R 비상 복구 단축키는 항상 등록.

## 설계 결정·알려진 동작

- **Caps Lock**: F19로 단순 리매핑만 한다. 대문자 고정(길게 누르기)은 지원하지 않는다.
  중간 키(F18) + 길게 누르기 판정 방식은 쓰지 않는다 — 시스템 설정의 단축키 기록 칸이 기록 중 전역 단축키를 꺼서 F18이 기록되는 문제가 있었다.
- **통화 감지**: Core Audio `kAudioProcessPropertyIsRunningInput`으로 앱별 마이크 사용을 본다. 시작 3초·정지 5초 판정.
  카카오톡은 통화 종료 즉시 마이크를 놓는다. 우리 녹음 중에는 `com.apple.replayd`(ScreenCaptureKit)가 마이크 사용자로 보인다(대상 아님).
  Chrome·Slack은 `.helper` 프로세스, Safari는 `com.apple.WebKit.GPU`가 마이크를 쓴다. 전화·FaceTime은 시스템 데몬일 수 있어 실제 번들 ID를
  로그("마이크 사용 중인 프로세스")로 확인해 `CallApps`를 보정한다. 브라우저는 창 제목에 회의 서비스 이름이 있을 때만. AI 음성 대화 앱은 대상이 아니다.
  자동 녹음 제목: "<앱> 통화 녹음 · HH:mm". 직접 시작한 녹음은 통화가 끝나도 멈추지 않는다.
- **전사**: Apple 기기 내 엔진(SpeechAnalyzer). 원본 오디오와 시간 데이터(`transcript-apple.json`)를 함께 보관해 다른 엔진 결과를
  `transcript-<엔진>.json`으로 나란히 둘 수 있게 한다. Claude API에는 음성 전사 기능이 없다.
- **재생**: `RecordingPlayer.updatePosition()`은 `pause()`에서도 부르므로 그 안에서 `pause()`를 부르면 무한 재귀(크래시)가 난다.
- **창 배치**: 가상 키 입력으로 보낸 단축키에서 크기만 바뀌고 위치가 그대로인 경우가 관찰됐다(실사용에서는 문제없음).
  재발하면 `WindowMover.perform`의 AX 에러 코드를 로그로 남기고 위치→크기→위치 순서로 설정해 볼 것.
