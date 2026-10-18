APP := build/Toolbelt.app
SPARKLE := $(APP)/Contents/Frameworks/Sparkle.framework/Versions/B
INSTALL_DIR := /Applications
# 서명 identity. 키체인의 자체 서명 인증서로 고정 → 재빌드해도 손쉬운 사용 권한이 유지된다.
# 인증서가 없는 환경에서는 `make install SIGN_ID=-` (ad-hoc).
SIGN_ID ?= Toolbelt Signing

.PHONY: build app install run clean icon quit release publish

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/Toolbelt $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	mkdir -p $(APP)/Contents/Resources
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	mkdir -p $(APP)/Contents/Frameworks
	ditto .build/release/Sparkle.framework $(APP)/Contents/Frameworks/Sparkle.framework
	@# Sparkle 안쪽 실행 파일부터 같은 인증서로 서명한 뒤 앱을 서명한다 (--deep은 쓰지 않음)
	codesign --force --sign "$(SIGN_ID)" $(SPARKLE)/XPCServices/Installer.xpc
	codesign --force --sign "$(SIGN_ID)" --preserve-metadata=entitlements $(SPARKLE)/XPCServices/Downloader.xpc
	codesign --force --sign "$(SIGN_ID)" $(SPARKLE)/Autoupdate
	codesign --force --sign "$(SIGN_ID)" $(SPARKLE)/Updater.app
	codesign --force --sign "$(SIGN_ID)" $(APP)/Contents/Frameworks/Sparkle.framework
	codesign --force --sign "$(SIGN_ID)" --identifier kr.clo3olb.toolbelt $(APP)

# 정상 종료 요청 → 녹음 중이면 파일을 마무리하고 꺼진다. 10초 안에 안 꺼지면 강제 종료.
quit:
	@osascript -e 'tell application id "kr.clo3olb.toolbelt" to quit' >/dev/null 2>&1 || true
	@for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Toolbelt >/dev/null || exit 0; sleep 1; done; pkill -x Toolbelt || true

install: app quit
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/Toolbelt.app
	cp -R $(APP) $(INSTALL_DIR)/
	open $(INSTALL_DIR)/Toolbelt.app

run: app quit
	open $(APP)

VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
RELEASE_ZIP := build/Toolbelt-$(VERSION).zip

# GitHub Releases에 올릴 zip. 사용자 권한이 업데이트 후에도 유지되도록 반드시 고정 인증서로 서명한다 (ad-hoc 금지).
release:
	@if [ "$(SIGN_ID)" = "-" ]; then echo "release는 ad-hoc 서명으로 만들 수 없습니다 (SIGN_ID=Toolbelt Signing)"; exit 1; fi
	$(MAKE) app
	codesign --verify --strict $(APP)
	rm -f $(RELEASE_ZIP)
	ditto -c -k --keepParent $(APP) $(RELEASE_ZIP)
	@echo "만듦: $(RELEASE_ZIP) (버전 $(VERSION), Info.plist의 CFBundleShortVersionString)"

# 새 버전 배포 (Sparkle 자동 업데이트 포함): make publish NOTES=<변경 내용 파일> — Scripts/publish.sh
publish:
	DRY_RUN=$(DRY_RUN) Scripts/publish.sh "$(NOTES)"

# Scripts/make-icon.swift로 1024 원본을 그리고 iconset → Resources/AppIcon.icns 생성.
icon:
	rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset Resources
	swift Scripts/make-icon.swift build/AppIcon-1024.png
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s build/AppIcon-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s * 2)); sips -z $$d $$d build/AppIcon-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf .build build
