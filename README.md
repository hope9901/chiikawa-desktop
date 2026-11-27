# 🐾 치이카와 데스크톱 (ChiikawaDesktop)

![치이카와 데스크톱 소개 영상](docs/media/intro.gif)

---

## ✨ 무엇을 할 수 있나요?

- **창 위 & 바닥 산책**: 열려 있는 인터넷 창, 폴더 창 위와 화면 바닥을 돌아다닙니다. 낮은 창 턱은 폴짝 점프해서 올라가고, 창 옆면을 잡고 기어오르기도 합니다. (듀얼 모니터 간 이동 지원)
- **마우스 반응**:
  - **짧게 클릭**: 치이카와·모몽가는 제자리에서 울고, **하치와레·우사기는 노래를 부릅니다!** (노래 중 다시 클릭하면 멈춤)
  - **길게 누르거나 드래그**: 마우스에 대롱대롱 매달려 울면서 바둥거리고, 놓으면 떨어진 자리에서 발라당 넘어진 뒤 다시 걸어 다닙니다.
- **내 맘대로 설정**: 캐릭터 우클릭 메뉴 또는 메뉴 아이콘(macOS는 상단 메뉴바의 🐾, Windows는 작업 표시줄 트레이)에서 **캐릭터 소환/휴식(최대 4명)**, **크기 조절(`아주 작게` ~ `아주 크게`)**, **시작프로그램 등록**을 설정할 수 있습니다.

---

## 🚀 다운로드 및 설치 방법

### 📥 바로 다운로드 (최신 버전)

| 운영체제 | 다운로드 | 비고 |
| --- | --- | --- |
| **Windows 10 / 11** (일반 PC) | [**ChiikawaDesktop-Windows-x64.exe**](https://github.com/hope9901/chiikawa-desktop/releases/latest/download/ChiikawaDesktop-Windows-x64.exe) | 대부분의 Windows PC는 이 파일 |
| **Windows 11** (ARM 노트북) | [ChiikawaDesktop-Windows-arm64.exe](https://github.com/hope9901/chiikawa-desktop/releases/latest/download/ChiikawaDesktop-Windows-arm64.exe) | Snapdragon 등 ARM 프로세서 PC |
| **macOS** | [**ChiikawaDesktop-macOS.zip**](https://github.com/hope9901/chiikawa-desktop/releases/latest/download/ChiikawaDesktop-macOS.zip) | Apple Silicon / Intel Mac |

> 모든 버전과 변경 내역은 [Releases 페이지](https://github.com/hope9901/chiikawa-desktop/releases)에서 볼 수 있습니다.
> 내 PC가 ARM인지 모르겠다면 `설정 → 시스템 → 정보 → 시스템 종류`를 확인해 주세요. *"x64 기반 프로세서"*라면 x64 파일을 받으면 됩니다.

---

### 🪟 Windows 10 / 11

**따로 설치할 필요가 없습니다.** exe 파일 하나에 프로그램, 캐릭터 이미지, 노래가 모두 들어 있고 .NET도 설치할 필요가 없습니다.

1. 위 표에서 **`ChiikawaDesktop-Windows-x64.exe`**를 다운로드합니다.
2. *(권장)* 다운로드한 exe를 원하는 폴더로 옮겨 둡니다. 예: `C:\Users\<내 이름>\ChiikawaDesktop\`
   - 시작프로그램으로 등록하면 **exe가 있는 위치**가 기록됩니다. 다운로드 폴더를 정리하다 지워지지 않도록 미리 옮겨 두는 것이 좋습니다.
3. exe를 **더블클릭**하면 화면 아래쪽에 캐릭터가 나타납니다. 첫 실행은 준비 과정 때문에 몇 초 정도 걸릴 수 있습니다.
4. **캐릭터를 우클릭**하거나 화면 오른쪽 아래 **작업 표시줄 알림 영역(트레이)의 ChiikawaDesktop 아이콘**을 클릭하면 메뉴가 열립니다. 여기서 캐릭터 소환·크기·종료를 설정합니다.
   - 트레이 아이콘은 기본 프로그램 모양이고, 마우스를 올리면 `ChiikawaDesktop`이라고 표시됩니다. 보이지 않으면 작업 표시줄의 **`^`(숨겨진 아이콘 표시)**를 눌러 보세요.

<details>
<summary><b>⚠️ "Windows의 PC 보호" 창이 뜨거나 실행이 막힐 때</b></summary>

- **"Windows의 PC 보호" (SmartScreen)**: 코드 서명이 없는 개인 프로젝트라서 뜨는 안내입니다. **`추가 정보` → `실행`**을 누르면 실행됩니다.
- **브라우저에서 다운로드가 차단될 때**: Edge/Chrome 다운로드 목록에서 `…` → **`유지`**(또는 `계속`)를 선택해 주세요.
- **Windows 11 "스마트 앱 컨트롤"이 차단할 때**: 스마트 앱 컨트롤이 켜져 있으면 서명되지 않은 앱이 차단될 수 있습니다. `Windows 보안 → 앱 및 브라우저 컨트롤 → 스마트 앱 컨트롤 설정`에서 상태를 확인해 주세요.
- **그래도 실행되지 않을 때**: 오류 창이 뜨거나 바로 꺼진다면 `%LOCALAPPDATA%\ChiikawaDesktop\error.log` 파일을 [Issues](https://github.com/hope9901/chiikawa-desktop/issues)에 첨부해 주세요. (탐색기 주소창에 `%LOCALAPPDATA%\ChiikawaDesktop`을 입력하면 폴더가 열립니다.)
</details>

<details>
<summary><b>🗑️ Windows에서 삭제하기</b></summary>

1. 시작프로그램으로 등록했다면 메뉴에서 **`시작프로그램 등록`** 체크를 먼저 해제합니다.
2. 메뉴에서 **`종료 (Quit)`**를 누른 뒤 `ChiikawaDesktop-Windows-x64.exe` 파일을 삭제합니다.
3. *(선택)* 설정과 임시 파일까지 지우려면 아래 폴더를 삭제합니다.
   - `%APPDATA%\ChiikawaDesktop` (설정)
   - `%LOCALAPPDATA%\ChiikawaDesktop` (오류 로그)
   - `%TEMP%\.net\ChiikawaDesktop` (실행 시 풀린 리소스)
</details>

---

### 🍎 macOS

1. 위 표에서 **`ChiikawaDesktop-macOS.zip`**을 다운로드한 뒤 더블클릭해 압축을 풉니다.
2. *(권장)* **`ChiikawaDesktop.app`**을 `응용 프로그램(Applications)` 폴더로 옮깁니다.
3. **`ChiikawaDesktop.app`**을 더블클릭하면 실행됩니다. 화면 오른쪽 위 메뉴바의 **🐾 아이콘**에서 설정할 수 있습니다.

<details>
<summary><b>⚠️ "확인되지 않은 개발자" 안내가 뜰 때</b></summary>

- `ChiikawaDesktop.app`을 **마우스 우클릭 → 열기 → 열기**를 누릅니다.
- 그래도 열리지 않으면 터미널에서 아래 명령어를 실행한 뒤 다시 열어 주세요.
  ```bash
  xattr -cr /Applications/ChiikawaDesktop.app
  ```
</details>

---

### 🛠️ 소스 코드로 직접 빌드하기 (개발자용)

일반 사용자는 위의 다운로드 파일을 쓰면 됩니다. 코드를 수정하거나 직접 빌드하고 싶을 때만 아래 방법을 사용하세요.

- **macOS**: 터미널에서 아래 명령어를 입력하면 빌드 후 바로 실행됩니다.
  ```bash
  git clone https://github.com/hope9901/chiikawa-desktop.git
  cd chiikawa-desktop
  ./run_macos.sh
  ```
- **Windows**: [.NET 8 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/8.0)가 필요합니다.
  1. 저장소를 `git clone`하거나 [Source code (zip)](https://github.com/hope9901/chiikawa-desktop/archive/refs/heads/main.zip)을 받아 압축을 풉니다.
  2. 폴더 안의 **`build_windows.bat`**을 더블클릭합니다.
     - .NET 8 SDK가 없으면 동의를 받은 뒤 WinGet으로 자동 설치합니다.
     - 빌드가 끝나면 `build_windows\ChiikawaDesktop.exe`(배포판과 같은 단일 exe)가 생성됩니다. PC가 ARM이면 ARM용으로 빌드됩니다.
  3. WinGet을 쓸 수 없는 환경이라면 위 링크에서 .NET 8 SDK를 직접 설치한 뒤 `build_windows.bat`을 실행해 주세요.

---

## 💻 컴퓨터 켤 때마다 자동으로 나오게 하기

1. 메뉴를 엽니다.
   - **Windows**: 캐릭터 우클릭 (또는 작업 표시줄 오른쪽 아래 트레이의 **ChiikawaDesktop 아이콘** 클릭)
   - **macOS**: 화면 오른쪽 위 메뉴바의 **🐾 아이콘** 클릭 (또는 캐릭터 우클릭)
2. **`시작프로그램 등록 (로그인 시 자동 실행)`**을 클릭해 체크(`✓`)를 켜두면 컴퓨터를 켤 때마다 자동으로 나타납니다.
   > 💡 Windows에서는 등록한 뒤 exe 파일을 다른 곳으로 옮기면 자동 실행이 되지 않습니다. 파일을 옮겼다면 체크를 껐다가 다시 켜 주세요.

---

## ⚖️ 저작권 안내 및 출처 (Copyright & Disclaimer)

본 프로젝트는 상업적 목적이 전혀 없는 **비영리 개인 팬 프로젝트(Non-profit Fan Project)**입니다.

1. **원작 캐릭터 저작권**
   - 본 프로그램에 등장하는 *치이카와(ちいかわ / Chiikawa)* 및 관련 캐릭터(치이카와, 하치와레, 우사기, 모몽가)의 모든 지식재산권과 저작권은 원작자 **나가노(Nagano / ナガノ)** 및 공식 권리자에게 있습니다.
   - 앱 구조 아이디어는 [ssskay/desktop-chiikawa-macos](https://github.com/ssskay/desktop-chiikawa-macos) (원작: CookieElmo)에서 영감을 받아 독자적인 코드로 재작성되었습니다.
  
2. **이미지(스프라이트) 제작 과정 및 출처**
   - 프로젝트 내 `assets/` 폴더의 캐릭터 모션 스프라이트 이미지들은 공식 게임이나 앱에서 추출한 리소스가 아니며, 팬 아트 레퍼런스를 바탕으로 오픈소스 AI 2D 스프라이트 생성 도구인 **[aldegad/sprite-gen](https://github.com/aldegad/sprite-gen)** 파이프라인을 활용하여 동작별로 직접 생성·후가공(배경 투명화 및 프레임 편집)하여 제작한 팬 메이드 이미지입니다.

3. **음원(Audio) 출처**
   - 캐릭터 클릭 시 재생되는 짧은 노래 음원은 아래 YouTube 영상에서 일부 구간을 추출·편집하여 사용하였습니다:
     - 하치와레(Hachiware) 노래 출처: [YouTube (https://www.youtube.com/watch?v=dIt_N7yNTgk)](https://www.youtube.com/watch?v=dIt_N7yNTgk)
     - 우사기(Usagi) 노래 출처: [YouTube (https://www.youtube.com/watch?v=OTbKZrUi8L0)](https://www.youtube.com/watch?v=OTbKZrUi8L0)

4. **권리자 삭제 요청 안내 (Takedown Policy)**
   - 원작자 또는 이미지·음원의 저작권 담당자께서 본 저장소나 포함된 리소스의 수정 또는 삭제를 요청하실 경우, 확인 즉시 해당 에셋 및 프로그램을 지체 없이 삭제·비공개 조치하겠습니다. (GitHub Issues를 통해 연락해 주시면 즉시 조치하겠습니다.)
