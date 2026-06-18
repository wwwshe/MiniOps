# Mac Mini 서버 설치 (헤드리스)

GUI 없이 Mac Mini에서 MiniOps 에이전트를 실행하는 방법입니다.

## Homebrew (권장)

```bash
# 저장소 클론 후 로컬 formula 설치
git clone https://github.com/wwwshe/MiniOps.git
cd MiniOps
brew install --formula Formula/miniops.rb

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
