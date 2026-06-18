# Mac Mini 서버 설치 (헤드리스)

GUI 없이 Mac Mini에서 MiniOps 에이전트를 실행하는 방법입니다.

## Homebrew (권장)

최신 Homebrew는 로컬 `Formula/*.rb` 직접 설치를 지원하지 않습니다. **tap**으로 설치하세요.

```bash
# GitHub 저장소를 tap으로 등록 후 설치 (저장소 클론 불필요)
brew tap wwwshe/miniops https://github.com/wwwshe/MiniOps.git
brew trust wwwshe/miniops
brew install miniops

# 백그라운드 서비스 시작
brew services start miniops

# 설정 확인
miniopsd --print-config
```

API Token 확인:

```bash
miniopsd --print-token
```

서비스 중지:

```bash
brew services stop miniops
```

### `brew install --formula` 오류

다음과 같은 메시지가 나오면 로컬 formula 설치가 막힌 것입니다.

```
Error: Homebrew requires formulae to be in a tap, rejecting:
  Formula/miniops.rb
```

위 **tap** 방식(`brew tap wwwshe/miniops ...`)을 사용하세요.

### `untrusted tap` 오류

```
Error: Refusing to load formula wwwshe/miniops/miniops from untrusted tap wwwshe/miniops.
```

최신 Homebrew는 비공식 tap을 한 번 신뢰해야 설치할 수 있습니다.

```bash
brew trust wwwshe/miniops
brew install miniops
```

### 요구 사항

- macOS 14+
- Xcode 또는 Command Line Tools (`xcode-select --install`) — `brew install` 시 소스 빌드에 필요

## 수동 설치

```bash
git clone https://github.com/wwwshe/MiniOps.git
cd MiniOps
swift build -c release --product miniopsd
./scripts/install-miniopsd.sh

# 포그라운드 실행 (테스트)
miniopsd

# 설정 확인
miniopsd --print-config
```

## launchd (수동)

```bash
# 빌드 후
cp scripts/com.miniops.miniopsd.plist ~/Library/LaunchAgents/
# plist 내 miniopsd 경로를 실제 설치 경로로 수정
launchctl load ~/Library/LaunchAgents/com.miniops.miniopsd.plist
```

## 설정 파일

`miniopsd`와 메뉴바 앱(MiniOps)은 **같은 설정**을 공유합니다.

- 경로: `~/Library/Preferences/com.miniops.settings.plist`
- API 포트 기본값: `8787`
- 최초 실행 시 API Token 자동 생성

## 동작

`miniopsd`는 다음을 수행합니다.

- CPU / Memory / Disk 수집
- Docker 컨테이너 상태 확인
- Health Check (설정된 URL)
- LAN HTTP API 제공 (`:8787`)

## 다른 Mac에서 조회

1. 서버에서 `miniopsd --print-config`로 LAN URL과 Token 확인
2. 다른 Mac에 **MiniOps 메뉴바 앱** 설치
3. 설정 → **원격 서버 조회** → URL + Token 입력

또는 curl:

```bash
curl -H "Authorization: Bearer <token>" http://192.168.0.10:8787/api/v1/status
```

자세한 내용: [remote-access.md](remote-access.md)
