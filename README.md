# ILKO
<img width="3840" height="2160" alt="image" src="https://github.com/user-attachments/assets/563746b9-5627-4205-8f23-21652b40bcc3" />

> 네트워크 기반 자동 월페이퍼 전환 — 집에선 덕질, 밖에선 일코

[YOUTUBE : ILKO(일코) - 씹덕들의 일코를 위한 네트워크 기반 월페이퍼 자동 전환 서비스](https://youtu.be/oWZAOatEMrA)

(영상 내에서는 월페이퍼가 이미지처럼 보이는데, 실제로는 mp4로 재생 됩니다. 영상 녹화 시에는 사진취급 되네요.)

Wi-Fi 게이트웨이를 감지해 장소에 맞는 월페이퍼로 자동 전환하는 앱. **macOS · Windows** 지원.  
집에선 좋아하는 캐릭터 라이브 월페이퍼, 카페·회사에선 조용한 기본 배경으로

Based on [LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS) by thusvill, licensed under GPL v3.

---

## 주요 기능

| 기능 | macOS | Windows |
|------|:-----:|:-------:|
| 게이트웨이 MAC 기반 자동 전환 | ✅ | ✅ |
| 라이브 영상 월페이퍼 (mp4) | ✅ | ✅ |
| 정적 이미지 월페이퍼 | ✅ | ✅ |
| 멀티모니터 지원 | ✅ | ✅ |
| Wi-Fi 단절 시 기본 프로필 자동 전환 | ✅ | ✅ |
| 프로필별 네트워크 등록 | ✅ | ✅ |
| 시스템 트레이 / 메뉴바 상주 | ✅ | ✅ |

---

## macOS

### 설치 (DMG 권장)

1. [Releases](../../releases/latest)에서 `ILKO-vX.X.X.dmg` 다운로드
2. DMG 열고 `ILKO.app` → Applications 폴더로 드래그
3. **터미널에서 아래 명령 실행** (최초 1회):
   ```bash
   xattr -d com.apple.quarantine /Applications/ILKO.app
   ```
   > 이 단계를 건너뛰면 *"손상되었기 때문에 열 수 없습니다"* 오류가 발생합니다.
4. ILKO 실행 → 메뉴바 아이콘 확인

### 소스 빌드

**요구사항:** macOS 14.6+, Xcode Command Line Tools

```bash
git clone https://github.com/BitByte08/ilko.git
cd ilko
make run
```

DMG 직접 생성:

```bash
make dmg VERSION=1.0.0
# 결과물: dist/ILKO-1.0.0.dmg
```

### 사용법

1. 앱 실행 → 메뉴바 아이콘 확인
2. 툴바 👥 버튼 → **프로필 추가** — 네트워크 게이트웨이와 월페이퍼 파일 지정
3. 백그라운드에서 자동 전환 시작

> **파일명 주의:** 비디오 파일명에 `.`이 2개 이상이면 인식 불가.  
> `rem-loop.mp4` ✅ / `rem.1920x1080.mp4` ❌

### 시스템 요구사항

- macOS 14.6 (Sonoma) 이상

---

## Windows

### 설치

**EXE (권장)**

1. [Releases](../../releases/latest)에서 `ILKO-vX.X.X-windows-x64.exe` 다운로드
2. 다운받은 EXE 실행 — 설치 불필요, 단독 실행 파일
3. 시스템 트레이 아이콘 확인

> .NET 런타임 내장 파일이라 별도 설치 없이 바로 실행됩니다.

**소스 빌드**

요구사항: Windows 10 이상, [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)

```bash
git clone https://github.com/BitByte08/ilko.git
cd ilko/windows
"C:\Program Files\dotnet\dotnet.exe" run
```

### 사용법

1. 앱 실행 → 시스템 트레이 아이콘 확인
2. 좌측 사이드바에서 **프로필 추가(+)** 버튼 클릭
3. 프로필 편집 창에서 배경화면 파일 선택 (이미지 또는 영상)
4. 네트워크를 등록하면 해당 Wi-Fi 연결 시 자동으로 월페이퍼 전환

#### 라이브 영상 월페이퍼 동작 방식

Windows 버전은 **Windows Media Foundation(MFPlay) + WorkerW** 방식으로 영상을 바탕화면에 렌더링합니다.

- `Progman`에 `0x052C` 메시지를 보내 WorkerW(바탕화면 아이콘 뒤 레이어)를 확보
- WinForms HWND를 WorkerW 자식으로 SetParent
- `MFPCreateMediaPlayer`로 EVR이 해당 HWND에 D3D9 COPY 모드로 직접 렌더링
- 영상 종료 시 자동 루프

#### 지원 형식

| 종류 | 형식 |
|------|------|
| 영상 | `.mp4`, `.mov`, `.avi`, `.mkv` 등 Windows Media Foundation 지원 형식 |
| 이미지 | `.jpg`, `.jpeg`, `.png`, `.bmp`, `.gif` |

#### 알려진 제한사항

- 영상 월페이퍼는 바탕화면 아이콘 뒤에 렌더링됩니다 (정상 동작)
- 일부 DRM이 걸린 영상 파일은 재생되지 않을 수 있습니다

### 시스템 요구사항

- Windows 10 이상
- .NET 8 Runtime
- Windows Media Foundation (기본 내장)

---

## 월페이퍼 영상 다운로드 링크 모음 (여러분들이 찾은 사이트를 계속해서 추가해주세요!)
- https://motionbgs.com/
- https://moewalls.com/anime

---

## 크레딧

Based on [LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS) by thusvill — GPL v3.

---

For licensing details, see [LICENSE](LICENSE).
