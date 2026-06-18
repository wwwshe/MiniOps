# MiniOps

AI 기반 Mac Mini 서버 모니터링 및 복구 도구

MiniOps는 Mac Mini 홈서버 운영자를 위한 AI 기반 운영 도우미입니다. CPU, 메모리, Docker 상태를 모니터링하고 Health Check를 수행합니다. 같은 Wi‑Fi(LAN)에서 HTTP API로 상태를 조회할 수 있습니다.

## v0.1 기능

- **miniopsd** — GUI 없는 서버 에이전트 (Homebrew 설치 가능)
- **메뉴바 앱** — 같은 Wi‑Fi의 다른 Mac에서 서버 상태 조회 (클라이언트)
- **Health Check** — 커스텀 URL 주기적 확인 (서버에서 설정)
- **로컬 HTTP API** — LAN 접근용 REST API (Bearer Token 인증)
- **Local First** — 모든 데이터는 Mac Mini에서 로컬 처리

## 두 가지 구성

| | Mac Mini (서버) | 같은 Wi‑Fi의 다른 Mac |
|--|-----------------|----------------------|
| 설치 | `brew install miniops` → `miniopsd` | MiniOps 메뉴바 앱 |
| GUI | 없음 (헤드리스) | 메뉴바 UI |
| 역할 | 수집 + API 제공 | 원격 조회 |

## Mac Mini 서버 설치 (Homebrew)

```bash
brew tap wwwshe/miniops https://github.com/wwwshe/MiniOps.git
brew install miniops
brew services start miniops

# LAN URL · API Token 확인
miniopsd --print-config
```

자세한 내용: [docs/server-install.md](docs/server-install.md)

## 요구 사항

- macOS 14.0+
- Xcode 15+ (빌드 시)
- Docker Desktop (Docker 모니터링 사용 시, 선택)

## 빌드 및 실행

```bash
git clone https://github.com/wwwshe/MiniOps.git
cd MiniOps
open MiniOps.xcodeproj
```

Xcode에서 `MiniOps` 스킴을 선택하고 Run (⌘R).

```bash
xcodebuild -scheme MiniOps -configuration Debug -destination 'platform=macOS' build

# 데몬 (SPM)
swift build -c release --product miniopsd
```

## 사용법

### Mac Mini (서버) — miniopsd

GUI 없이 백그라운드로 실행합니다. 설정은 `miniopsd --print-config`로 확인합니다.

### 다른 Mac (클라이언트) — 메뉴바 앱

1. 설정 → **원격 서버 조회** 선택
2. 서버 URL + API Token 입력 → **연결 테스트**

자세한 내용: [docs/remote-access.md](docs/remote-access.md)

### 터미널 (curl)

```bash
curl -H "Authorization: Bearer <token>" http://192.168.0.10:8787/api/v1/status
```

## API 엔드포인트

| Path | 설명 |
|------|------|
| `GET /api/v1/health` | API 헬스 (인증 불필요) |
| `GET /api/v1/status` | 전체 상태 요약 |
| `GET /api/v1/metrics` | CPU/Memory/Disk |
| `GET /api/v1/docker` | Docker 컨테이너 |
| `GET /api/v1/health-checks` | Health Check 결과 |

## 프로젝트 구조

```
MiniOps/
├── Packages/MiniOpsKit/   # SPM — Core, Monitoring, API
├── Sources/miniopsd/      # 헤드리스 데몬 (SPM executable)
├── MiniOps/             # Xcode — 메뉴바 앱 (Kit 의존)
├── Package.swift        # miniopsd 빌드
├── Formula/             # Homebrew formula
└── docs/
```

## 로드맵

| 버전 | 기능 |
|------|------|
| v0.1 | 메뉴바 + Health Check + LAN API |
| v0.2 | 웹 대시보드 + 로그 수집 |
| v0.3 | AI 로그 분석 (Ollama / Cloud) |
| v0.4 | Slack 알림 |

## 라이선스

[MIT](LICENSE)

## 기여

Issue와 Pull Request를 환영합니다.
