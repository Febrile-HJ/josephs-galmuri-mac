#!/bin/bash
# 조셉 갈무리(Joseph's Galmuri) 맥 설치·업데이트 (터미널 한 줄)
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Febrile-HJ/josephs-galmuri-mac/main/install.sh)"
# 1) Apple 실리콘·macOS 14 이상 확인  2) 새 판 정보와 비밀번호 걸린 DMG 받기, 크기·SHA-256 확인
# 3) 조셉에게 받은 비밀번호로 열기  4) 조셉 인증서로 서명된 앱인지 확인  5) 켜진 앱 끄기, 옛 앱은 휴지통으로
# 6) 새 앱 넣기, 비밀번호는 앱 안 업데이트용으로 남기기(앱이 켜질 때 키체인으로 옮기고 지운다)  7) 켜기
# 터미널로 받은 파일에는 macOS '인터넷에서 받음' 표시가 붙지 않아 차단 창이 뜨지 않는다.
set -euo pipefail
REPO="Febrile-HJ/josephs-galmuri-mac"
BASE="${JG_RELEASE_BASE:-https://github.com/$REPO/releases/latest/download}"
PREFIX="${JG_RELEASE_PREFIX:-https://github.com/$REPO/releases/}"
DEFAULT_TARGET="/Applications/Joseph's Galmuri.app"
TARGET="${JG_INSTALL_TARGET:-$DEFAULT_TARGET}"
CONFIG="${JG_CONFIG_DIR:-$HOME/Library/Application Support/kr.ai.lucatec.JosephsGalmuri}"
TRASH="${JG_TRASH_DIR:-$HOME/.Trash}"
REQ='identifier "kr.ai.lucatec.JosephsGalmuri" and certificate leaf = H"5a65db22a78e7437ffaf0468047b9b07607ddec5"'
APP_NAME="Joseph's Galmuri.app"
EXE="$TARGET/Contents/MacOS/JosephsGalmuri"

say() { printf '%s\n' "$*"; }
fail() { printf '\n설치하지 못했어요: %s\n' "$*" >&2; exit 1; }

say "조셉 갈무리 설치"
[[ "$(uname -m)" == "arm64" ]] || fail "Apple 실리콘(M 시리즈) 맥에서만 쓸 수 있어요."
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 14 )) || fail "macOS 14 이상이 필요해요 (지금 $(sw_vers -productVersion))."
[[ -w "$(dirname "$TARGET")" ]] || fail "응용 프로그램 폴더에 넣을 수 없어요. 관리자 계정에서 실행해 주세요."

WORK=$(mktemp -d)
cleanup() { hdiutil detach -quiet "$WORK/mnt" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK/mnt"

say "1) 새 판 정보 받기"
curl -fsSL "$BASE/latest.json" -o "$WORK/latest.json" || fail "새 판 정보를 받지 못했어요. 인터넷 연결을 확인해 주세요."
VERSION=$(plutil -extract version raw -o - "$WORK/latest.json" 2>/dev/null) || fail "새 판 정보가 올바르지 않아요."
URL=$(plutil -extract url raw -o - "$WORK/latest.json" 2>/dev/null) || fail "새 판 정보가 올바르지 않아요."
SHA=$(plutil -extract sha256 raw -o - "$WORK/latest.json" 2>/dev/null) || fail "새 판 정보가 올바르지 않아요."
SIZE=$(plutil -extract size raw -o - "$WORK/latest.json" 2>/dev/null) || fail "새 판 정보가 올바르지 않아요."
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ && "$SHA" =~ ^[0-9a-f]{64}$ && "$SIZE" =~ ^[0-9]+$ ]] || fail "새 판 정보가 올바르지 않아요."
[[ "$URL" == "$PREFIX"* && "$URL" == *.dmg && "$URL" != *..* ]] || fail "새 판 주소가 조셉의 배포 저장소가 아니에요."
say "   판 $VERSION ($(( SIZE / 1024 ))KB)"

say "2) 받기"
curl -fL --progress-bar "$URL" -o "$WORK/jg.dmg" || fail "파일을 받지 못했어요."
[[ "$(stat -f %z "$WORK/jg.dmg")" == "$SIZE" ]] || fail "받은 파일 크기가 달라요. 다시 실행해 주세요."
[[ "$(shasum -a 256 "$WORK/jg.dmg" | cut -d' ' -f1)" == "$SHA" ]] || fail "받은 파일이 새 판 정보와 달라요. 다시 실행해 주세요."

ask_password() {  # 화면이 있으면 macOS 대화상자(취소하면 멈춤), 원격 접속이면 터미널에서 묻는다
  if [[ -n "${JG_TEST_PASSWORD:-}" ]]; then printf '%s' "$JG_TEST_PASSWORD"; return; fi
  if [[ -n "${SSH_TTY:-}" ]]; then IFS= read -rsp "$1 " pw < /dev/tty && echo >&2 && printf '%s' "$pw"; return; fi
  osascript -e "text returned of (display dialog \"$1\" with title \"조셉 갈무리 설치\" default answer \"\" with hidden answer buttons {\"취소\", \"확인\"} default button \"확인\" cancel button \"취소\")" 2>/dev/null
}

say "3) 비밀번호로 열기"
PASSWORD=""
for try in 1 2 3; do
  if (( try == 1 )); then PASSWORD=$(ask_password "조셉에게 받은 설치 비밀번호를 넣어 주세요.") || fail "취소했어요."
  else PASSWORD=$(ask_password "비밀번호가 맞지 않아요. 다시 넣어 주세요.") || fail "취소했어요."; fi
  if [[ -n "$PASSWORD" ]] && printf '%s' "$PASSWORD" | hdiutil attach -quiet -nobrowse -readonly -noautoopen -stdinpass \
       -mountpoint "$WORK/mnt" "$WORK/jg.dmg" 2>/dev/null; then break; fi
  PASSWORD=""
  [[ -n "${JG_TEST_PASSWORD:-}" ]] && break
done
[[ -n "$PASSWORD" ]] || fail "비밀번호가 맞지 않아요."

say "4) 서명 확인"
codesign --verify --deep --strict -R "=$REQ" "$WORK/mnt/$APP_NAME" 2>/dev/null \
  || fail "조셉이 만든 앱이 아니에요. 설치하지 않았어요."
ditto "$WORK/mnt/$APP_NAME" "$WORK/$APP_NAME"
hdiutil detach -quiet "$WORK/mnt"
codesign --verify --deep --strict -R "=$REQ" "$WORK/$APP_NAME" 2>/dev/null \
  || fail "조셉이 만든 앱이 아니에요. 설치하지 않았어요."

say "5) 켜진 앱 끄기"
running() { pgrep -f "^$EXE\$" >/dev/null 2>&1; }
if running; then
  pkill -TERM -f "^$EXE\$" || true   # 앱 메뉴의 '끝내기'와 같은 길로 끝난다
  for _ in $(seq 1 30); do running || break; sleep 0.5; done
  running && fail "켜진 앱이 꺼지지 않았어요. 열린 창을 마치고 메뉴 막대 아이콘 › 끝내기 뒤 다시 실행해 주세요."
fi

say "6) 넣기"
if [[ -d "$TARGET" ]]; then
  OLD=$(plutil -extract CFBundleShortVersionString raw -o - "$TARGET/Contents/Info.plist" 2>/dev/null || echo "old")
  mkdir -p "$TRASH"
  mv "$TARGET" "$TRASH/Joseph's Galmuri $OLD $(date +%Y%m%d-%H%M%S).app"
  say "   옛 앱($OLD)은 휴지통으로 옮겼어요"
fi
mv "$WORK/$APP_NAME" "$TARGET"
mkdir -p "$CONFIG"
( umask 077; printf '%s' "$PASSWORD" > "$CONFIG/.update-password" )  # 앱이 켜질 때 키체인으로 옮기고 지운다
unset PASSWORD

if [[ -z "${JG_NO_LAUNCH:-}" ]]; then
  say "7) 켜기"
  open "$TARGET"
fi
say ""
say "완료: 조셉 갈무리 $VERSION"
say "캡처 단축키는 ⌘⇧2예요. 처음 캡처할 때 macOS가 「화면 및 시스템 오디오 녹음」 허용을 물어요."
say "다음 업데이트는 메뉴 막대 아이콘 › 업데이트 에서 할 수 있어요."
