# 🐾 치이카와 데스크톱 (ChiikawaDesktop)

바탕화면과 프로그램 창 위를 자유롭게 걸어 다니는 **치이카와 데스크톱 펫** 앱입니다. (macOS & Windows 지원)

---

## ✨ 무엇을 할 수 있나요?

- **창 위 & 바닥 산책**: 열려 있는 인터넷 창, 폴더 창 위와 화면 바닥을 돌아다닙니다. 낮은 창 턱은 폴짝 점프해서 올라가고, 창 옆면을 잡고 기어오르기도 합니다. (듀얼 모니터 간 이동 지원)
- **마우스 반응**:
  - **짧게 클릭**: 치이카와·모몽가는 제자리에서 울고, **하치와레·우사기는 노래를 부릅니다!** (노래 중 다시 클릭하면 멈춤)
  - **길게 누르거나 드래그**: 마우스에 대롱대롱 매달려 울면서 바둥거리고, 놓으면 떨어진 자리에서 발라당 넘어진 뒤 다시 걸어 다닙니다.
- **내 맘대로 설정**: 상단 메뉴바의 **`🐾 치이카와`** 아이콘(또는 캐릭터 우클릭)에서 **캐릭터 소환/휴식(최대 4명)**, **크기 조절(`아주 작게` ~ `아주 크게`)**, **시작프로그램 등록**을 설정할 수 있습니다.

---

## 🚀 다운로드 및 실행 방법

### 1. 가장 쉬운 방법 (macOS 바로 실행)
1. **[Releases 다운로드 페이지](https://github.com/hope9901/chiikawa-desktop/releases)**에서 **`ChiikawaDesktop-macOS.zip`**을 다운로드한 뒤 압축을 풉니다.
2. **`ChiikawaDesktop.app`**을 더블클릭하면 바로 실행됩니다!
   > 💡 처음 실행 시 *"확인되지 않은 개발자"* 안내가 뜨면, `ChiikawaDesktop.app`을 **마우스 우클릭 → 열기**를 누르거나 터미널에 `xattr -cr ChiikawaDesktop.app`을 입력해 주세요.

### 2. 소스 코드로 직접 실행하기
- **macOS**: 터미널에서 아래 명령어를 입력하면 자동으로 빌드 및 실행됩니다.
  ```bash
  git clone https://github.com/hope9901/chiikawa-desktop.git
  cd chiikawa-desktop
  ./run_macos.sh
  ```
- **Windows (Windows 10/11, .NET 8 설치 환경)**: 폴더 안의 **`build_windows.bat`**을 더블클릭하면 `build_windows\ChiikawaDesktop.exe`가 생성됩니다.

---

## 💻 컴퓨터 켤 때마다 자동으로 나오게 하기

1. 화면 오른쪽 위 메뉴바의 **`🐾 치이카와`** 클릭 (또는 캐릭터 우클릭)
2. **`시작프로그램 등록 (로그인 시 자동 실행)`**을 클릭해 체크(`✓`)를 켜두면 컴퓨터를 켤 때마다 자동으로 나타납니다.

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
