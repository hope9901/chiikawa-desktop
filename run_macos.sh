#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🐾 ChiikawaDesktop (macOS) 빌드 및 실행을 시작합니다..."

chmod +x "$SCRIPT_DIR/build_app.sh"
"$SCRIPT_DIR/build_app.sh"

if [[ "${1:-}" == "--install" ]]; then
    echo "📦 /Applications/ChiikawaDesktop.app 으로 복사 중..."
    rm -rf "/Applications/ChiikawaDesktop.app"
    cp -R "$SCRIPT_DIR/ChiikawaDesktop.app" "/Applications/ChiikawaDesktop.app"
    killall ChiikawaDesktop 2>/dev/null || true
    open "/Applications/ChiikawaDesktop.app"
    echo "✅ /Applications 설치 및 실행 완료! 상단 메뉴바의 '🐾 치이카와'에서 '시작프로그램 등록'을 켜면 부팅 시마다 자동 실행됩니다."
else
    killall ChiikawaDesktop 2>/dev/null || true
    open "$SCRIPT_DIR/ChiikawaDesktop.app"
    echo "✅ 실행 완료! 상단 메뉴바의 '🐾 치이카와'에서 '시작프로그램 등록'을 켜면 부팅 시마다 자동 실행됩니다."
fi
