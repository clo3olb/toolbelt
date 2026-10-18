#!/bin/bash
# 새 버전 배포: 빌드·서명 → zip EdDSA 서명 → appcast.xml 생성 → GitHub Release 게시 → 확인
# 사용: make publish NOTES=<변경 내용 마크다운 파일>   (DRY_RUN=1 이면 게시하지 않고 zip·서명·appcast까지만)
# 전제: Info.plist 버전을 올려 커밋·푸시해 둔 상태, 키체인에 Sparkle 키(계정 clo3olb-toolbelt)
set -euo pipefail

NOTES="${1:-}"
REPO="clo3olb/toolbelt"
ACCOUNT="clo3olb-toolbelt"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

[ -n "$NOTES" ] && [ -f "$NOTES" ] || { echo "변경 내용 파일이 필요합니다: make publish NOTES=<파일>"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Info.plist)
TAG="v$VERSION"
ZIP="build/Toolbelt-$VERSION.zip"
APPCAST="build/appcast.xml"

DRY_RUN="${DRY_RUN:-0}"

# 1. 확인: 커밋·푸시가 끝났는지, 같은 버전이 이미 없는지 (DRY_RUN이면 건너뜀)
if [ "$DRY_RUN" != "1" ]; then
    [ -z "$(git status --porcelain)" ] || { echo "커밋하지 않은 변경이 있습니다. 먼저 커밋하세요."; exit 1; }
    git fetch -q origin
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "origin/main과 다릅니다. 먼저 push하세요."; exit 1; }
    if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then echo "$TAG 릴리스가 이미 있습니다. Info.plist 버전을 올리세요."; exit 1; fi
    LATEST_BUILD=$(curl -fsL "https://github.com/$REPO/releases/latest/download/appcast.xml" 2>/dev/null \
        | sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' | head -1 || true)
    if [ -n "$LATEST_BUILD" ] && [ "$BUILD" -le "$LATEST_BUILD" ]; then
        echo "CFBundleVersion($BUILD)이 배포된 최신 빌드($LATEST_BUILD)보다 커야 Sparkle이 업데이트로 인식합니다."; exit 1
    fi

fi

# 2. 빌드·서명·zip
make release

# 3. zip EdDSA 서명 (sparkle:edSignature="…" length="…")
SIG_ATTRS=$("$SPARKLE_BIN/sign_update" --account "$ACCOUNT" "$ZIP")
SIGNATURE=$(echo "$SIG_ATTRS" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" --verify "$ZIP" "$SIGNATURE" >/dev/null
echo "zip 서명 확인됨"

# 4. appcast.xml (최신 버전 하나만 담는다 — feed는 releases/latest를 가리킨다)
python3 - "$NOTES" "$VERSION" "$BUILD" "$MIN_OS" "$TAG" "$SIG_ATTRS" "$APPCAST" "$REPO" <<'PY'
import sys, html, re, email.utils
notes, version, build, min_os, tag, sig_attrs, out, repo = sys.argv[1:]
# 마크다운 일부(## 제목, - 목록, 문단, **굵게**)를 HTML로
def inline(t): return re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", html.escape(t))
parts, in_list = [], False
for line in open(notes, encoding="utf-8").read().splitlines():
    s = line.strip()
    if s.startswith("- "):
        if not in_list: parts.append("<ul>"); in_list = True
        parts.append(f"<li>{inline(s[2:])}</li>")
        continue
    if in_list: parts.append("</ul>"); in_list = False
    if s.startswith("#"): parts.append(f"<h3>{inline(s.lstrip('#').strip())}</h3>")
    elif s: parts.append(f"<p>{inline(s)}</p>")
if in_list: parts.append("</ul>")
url = f"https://github.com/{repo}/releases/download/{tag}/Toolbelt-{version}.zip"
xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Toolbelt</title>
    <link>https://github.com/{repo}</link>
    <item>
      <title>Toolbelt {version}</title>
      <pubDate>{email.utils.formatdate(localtime=False)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>
      <description><![CDATA[{''.join(parts)}]]></description>
      <enclosure url="{url}" {sig_attrs.strip()} type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""
open(out, "w", encoding="utf-8").write(xml)
PY
xmllint --noout "$APPCAST"
echo "appcast 생성됨: $APPCAST"

if [ "$DRY_RUN" = "1" ]; then echo "DRY_RUN: 게시하지 않았습니다 ($ZIP, $APPCAST)"; exit 0; fi

# 5. GitHub Release 게시 (zip + appcast.xml)
gh release create "$TAG" "$ZIP" "$APPCAST" --repo "$REPO" --title "Toolbelt $VERSION" --notes-file "$NOTES"

# 6. 배포된 appcast가 이 버전을 가리키는지 확인
#    게시 직후 GitHub의 releases/latest 연결이 갱신되는 데 1~2분 걸리므로 최대 5분 기다린다.
for i in $(seq 1 20); do
    PUBLISHED=$(curl -fsL "https://github.com/$REPO/releases/latest/download/appcast.xml" 2>/dev/null \
        | sed -n 's:.*<sparkle\:shortVersionString>\(.*\)</sparkle\:shortVersionString>.*:\1:p' || true)
    if [ "$PUBLISHED" = "$VERSION" ]; then
        echo "완료: $TAG 게시, 자동 업데이트 피드가 $VERSION을 가리킵니다."
        exit 0
    fi
    echo "피드 갱신 대기 중… (${PUBLISHED:-아직 이전 버전})"
    sleep 15
done
echo "경고: 5분이 지나도 피드가 $VERSION을 가리키지 않습니다. 릴리스는 게시됐으니 잠시 뒤 다시 확인하세요:"
echo "  curl -sL https://github.com/$REPO/releases/latest/download/appcast.xml | grep shortVersionString"
exit 1
