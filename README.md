# ILKO
<img width="200" height="200" alt="ilko_icon" src="https://github.com/user-attachments/assets/553cbecc-5f88-4f98-bfb2-90eb93b42c11" />

> 네트워크 기반 자동 월페이퍼 전환 — 집에선 덕질, 밖에선 일코

[YOUTUBE : ILKO(일코) - 씹덕들의 일코를 위한 네트워크 기반 월페이퍼 자동 전환 서비스](https://youtu.be/oWZAOatEMrA)

(영상 내에서는 월페이퍼가 이미지처럼 보이는데, 실제로는 mp4로 재생 됩니다. 영상 녹화 시에는 사진취급 되네요.)

Wi-Fi 게이트웨이를 감지해 장소에 맞는 월페이퍼로 자동 전환하는 macOS 앱.  
집에선 좋아하는 캐릭터 라이브 월페이퍼, 카페·회사에선 조용한 기본 배경으로

Based on [LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS) by thusvill, licensed under GPL v3.

---

## 주요 기능

- **게이트웨이 MAC 기반 자동 전환** — SCDynamicStore로 네트워크 변경을 실시간 감지, VPN 환경에서도 실제 Wi-Fi 게이트웨이를 정확히 식별
- **Wi-Fi 단절 시 기본 프로필** — 연결된 네트워크가 없거나 등록되지 않은 네트워크면 기본(일코) 프로필로 자동 전환
- **프로필 관리** — 네트워크별 월페이퍼 프로필 등록, 툴바의 👥 버튼으로 접근
- **라이브 + 정적 월페이퍼** — `.mp4`, `.mov` 루프 재생 / `.jpg`, `.png` 정적 이미지
- **메뉴바 상주** — 현재 프로필 확인, 수동 전환, 로그인 시 자동 시작

---

## 설치

### DMG (권장)

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
git clone https://github.com/winshine0326/ilko.git
cd ilko
make run
```

DMG 직접 생성:

```bash
make dmg VERSION=1.0.0
# 결과물: dist/ILKO-1.0.0.dmg
```

---

## 사용법

1. 앱 실행 → 메뉴바 아이콘 확인
2. 툴바 👥 버튼 → **프로필 추가** — 네트워크 게이트웨이와 월페이퍼 파일 지정
3. 백그라운드에서 자동 전환 시작

> **파일명 주의:** 비디오 파일명에 `.`이 2개 이상이면 인식 불가.  
> `rem-loop.mp4` ✅ / `rem.1920x1080.mp4` ❌

---

## 시스템 요구사항

- macOS 14.6 (Sonoma) 이상

---

## 크레딧

Based on [LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS) by thusvill — GPL v3.

---

For licensing details, see [LICENSE](LICENSE).
