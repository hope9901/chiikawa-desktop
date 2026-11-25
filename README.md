# 🐾 ChiikawaDesktop (macOS & Windows)

**JSON 명세 기반(Spec-Driven)** 데스크톱 치이카와 펫 애플리케이션입니다.
모든 물리 상수, 상태 머신(FSM), 창 인식 규칙, 캐릭터 프로필이 [`spec/`](spec/) 폴더의 JSON에 단일 진실 공급원(Single Source of Truth)으로 정의되어 있으며, 이를 바탕으로 **macOS (Swift / AppKit)**와 **Windows (C# / .NET 8 WPF + Win32 API)** 양쪽에서 동일한 동작으로 구동됩니다.

---

## ✨ 주요 기능

- **창(Window) 상단 & 바닥 인식 산책**: 현재 열려 있는 앱 창들의 상단 테두리와 화면 바닥(Dock / 작업 표시줄 위)을 실시간으로 인식해 걸어 다닙니다.
- **창 탑승 이동 & 경계 이탈 자유낙하**: 캐릭터가 올라가 있는 창을 드래그하면 창과 함께 이동하며, 화면 밖으로 밀려나거나 다른 모니터로 넘어가면 안전하게 분리되어 자유낙하합니다.
- **작은 턱 폴짝 점프 & 창 옆면 기어오르기**:
  - 캐릭터 키의 절반 이하 높이 턱을 만나면 랜덤 확률로 폴짝 점프(`JUMP_STEP`)합니다.
  - 창의 양 끝 수직 벽면을 만나면 랜덤 확률로 벽을 잡고 기어오르며(`CLIMB_WALL`), 높은 창을 오를 때는 중간에 땀을 흘리며 쉬었다가(`CLIMB_REST`) 올라갑니다. (단, **우사기**는 쉬지 않고 끝까지 등반합니다!)
- **마우스 인터랙션 & 캐릭터 노래 재생**:
  - **하치와레 / 우사기**를 짧게 클릭하면 전용 노래 음원(`assets/<id>/audio/`)과 함께 노래 부르는 모션이 재생됩니다(노래 중 다시 클릭하면 정지).
  - **치이카와 / 모몽가**를 짧게 클릭하면 제자리에서 눈물을 흘리며 웁니다(`CRY_CLICK`).
  - 클릭을 유지하거나 드래그하면 마우스에 매달려 울면서 바둥거립니다(`DRAGGED_STRUGGLE`).
  - 마우스를 놓으면 떨어져 발라당 넘어지는 모션(`TUMBLE`) 후 착지한 곳에서 다시 활동합니다.
- **개별 캐릭터 소환/휴식 & 크기 슬라이더**:
  - 치이카와, 하치와레, 우사기, 모몽가(최대 4명, 중복 없음)를 메뉴에서 개별 소환/휴식 토글할 수 있습니다.
  - `1/4`, `2/4`, `3/4` 지점에 자석 턱(Detent)이 있는 슬라이더(`50% ~ 135%`)로 크기를 실시간 조절합니다.
- **시작프로그램 등록 (부팅 시 자동 실행)**:
  - 상단 메뉴바(`🐾 치이카와`) 또는 캐릭터 우클릭 메뉴에서 **`시작프로그램 등록 (로그인 시 자동 실행)`**을 체크하면 컴퓨터를 켤 때마다 자동으로 캐릭터들이 바탕화면에 나타납니다.

---

## 🚀 다운로드 및 실행 방법 (누구나 쉽게 실행하기)

### 방법 A. 빌드된 파일 바로 다운로드 (Releases)
1. GitHub 우측의 **[Releases](https://github.com/hope9901/chiikawa-desktop/releases)** 페이지에서 `ChiikawaDesktop-macOS.zip`을 다운로드하고 압축을 풉니다.
2. `ChiikawaDesktop.app`을 더블클릭하면 바로 실행됩니다.
   - *(만약 macOS에서 "확인되지 않은 개발자" 경고가 뜨면 터미널에서 `xattr -cr ChiikawaDesktop.app`을 실행하거나 우클릭 → 열기를 눌러주세요.)*

### 방법 B. 소스 코드 클론 후 원클릭 실행

#### 🍎 macOS
Xcode Command Line Tools(`swiftc`)만 있으면 별도 설치 없이 한 줄로 빌드 및 실행됩니다:
```bash
git clone https://github.com/hope9901/chiikawa-desktop.git
cd chiikawa-desktop
chmod +x run_macos.sh
./run_macos.sh
```
- 응용 프로그램(`/Applications`) 폴더에 설치까지 한 번에 하려면:
  ```bash
  ./run_macos.sh --install
  ```

#### 🪟 Windows (Windows 10 / 11, .NET 8 SDK)
1. 저장소를 다운로드(또는 `git clone`)한 뒤 **`build_windows.bat`** 파일을 더블클릭합니다.
2. 생성된 `build_windows\ChiikawaDesktop.exe`를 실행합니다.

---

## 💻 컴퓨터 부팅 시 항상 자동 실행되게 설정하는 법

앱을 실행한 뒤:
1. 화면 우측 상단 메뉴바(Windows는 작업 표시줄 트레이)의 **`🐾 치이카와`** 아이콘을 클릭하거나, 바탕화면의 **캐릭터를 마우스 우클릭**합니다.
2. 메뉴에서 **`시작프로그램 등록 (로그인 시 자동 실행)`**을 클릭해 체크(`✓`) 표시를 켜둡니다.
   - **macOS**: `~/Library/LaunchAgents/com.chiikawa.desktop.plist`에 자동 등록됩니다.
   - **Windows**: 레지스트리 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`에 자동 등록됩니다.

---

## 📂 디렉토리 구조

```text
chiikawa-desktop/
├── spec/                           # [플랫폼 독립적 JSON 블루프린트]
│   ├── architecture.json           # 모듈 구조 및 macOS/Windows API 매핑 명세
│   ├── physics_and_world.json      # 물리 상수, 점프/등반 확률, 슬라이더 턱, 창 인식 규칙
│   └── character_fsm.json          # 캐릭터 프로필 4종, 음원 설정 및 상태 머신(FSM) 정의
├── assets/                         # 캐릭터별(chiikawa, hachiware, usagi, momonga) 스프라이트 PNG & audio/
├── Sources/ChiikawaDesktop/        # [macOS 네이티브 구현체 - Swift / AppKit]
├── Windows/ChiikawaDesktopWin/     # [Windows 네이티브 구현체 - C# / .NET 8 WPF + Win32]
├── run_macos.sh                    # macOS 원클릭 빌드/설치/실행 스크립트
├── build_app.sh                    # macOS 앱 번들(ChiikawaDesktop.app) 빌드 스크립트
└── build_windows.bat               # Windows 실행 파일(ChiikawaDesktop.exe) 빌드 스크립트
```
