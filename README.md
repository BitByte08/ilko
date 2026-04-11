# ilko

> 네트워크 기반 자동 월페이퍼 전환 — 집에선 덕질, 밖에선 일코

Wi-Fi 게이트웨이를 감지해 장소에 맞는 월페이퍼로 자동 전환하는 macOS 앱.  
집에선 좋아하는 캐릭터 라이브 월페이퍼, 카페·회사에선 조용한 기본 배경으로.

Based on [LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS) by thusvill, licensed under GPL v3.

---

## 주요 기능

- **게이트웨이 MAC 기반 자동 전환** — SCDynamicStore로 네트워크 변경을 실시간 감지, VPN 환경에서도 실제 Wi-Fi 게이트웨이를 정확히 식별
- **Wi-Fi 단절 시 기본 프로필** — 연결된 네트워크가 없거나 등록되지 않은 네트워크면 기본 (일코) 프로필로 자동 전환
- **프로필 관리** — 네트워크별 월페이퍼 프로필 등록, 툴바의 👥 버튼으로 접근
- **라이브 + 정적 월페이퍼** — `.mp4`, `.mov` 루프 재생 / `.jpg`, `.png` 정적 이미지
- **메뉴바 상주** — 현재 프로필 확인, 수동 전환, 로그인 시 자동 시작

---

## 설치 (소스 빌드)

**요구사항:** macOS 14+, Xcode Command Line Tools

```bash
git clone https://github.com/winshine0326/ilko.git
cd ilko
make run
```

Xcode 없이 빌드만 하려면:

```bash
make build
# 결과물: .build/Build/Products/Debug/LiveWallpaper.app
```

### Gatekeeper 우회

서명 없는 앱이므로 설치 후 아래 명령 실행:

```bash
xattr -d com.apple.quarantine /Applications/ilko.app
```

---

## 사용법

1. 앱 실행 → 메뉴바 아이콘 확인
2. 툴바 👥 버튼 → **프로필 추가** — 네트워크 게이트웨이와 월페이퍼 파일 지정
3. 백그라운드에서 자동 전환 시작

> **파일명 주의:** 비디오 파일명에 `.`이 2개 이상이면 인식 불가.  
> `rem-loop.mp4` ✅ / `rem.1920x1080.mp4` ❌

---

## 크레딧

Based on [LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS) by thusvill — GPL v3.

---

For licensing details, see [LICENSE](LICENSE).
