# 원격 접속 가이드 (LAN)

MiniOps는 Mac Mini에서 로컬 HTTP API를 제공합니다. **같은 Wi‑Fi( LAN )** 에 있는 다른 기기에서 추가 소프트웨어 없이 상태를 조회할 수 있습니다.

## 1. Mac Mini (서버) 설정

서버에는 **miniopsd** (헤드리스 에이전트)를 설치합니다. GUI가 필요 없습니다.

```bash
brew tap wwwshe/miniops https://github.com/wwwshe/MiniOps.git
brew trust wwwshe/miniops
brew install miniops
brew services start miniops
miniopsd --print-config
```

자세한 설치: [server-install.md](server-install.md)

1. `miniopsd --print-config`로 **LAN URL** · **API Token** 확인
2. (선택) Health Check URL은 서버 설정 파일(plist)로 등록

### Mac Mini IP 직접 확인

```bash
# Wi‑Fi IP (일반적)
ipconfig getifaddr en0

# 또는
ifconfig en0 | grep "inet "
```

## 2. 같은 Wi‑Fi에서 조회

### MiniOps Mac 앱 (클라이언트)

1. 같은 Wi‑Fi에 연결된 Mac에 MiniOps 메뉴바 앱 설치
2. 설정에서 입력:
   - **서버 URL**: `http://192.168.0.10:8787` (Mac Mini LAN IP) — **`https://` 아님**
   - **API Token**: Mac Mini에서 `miniopsd --print-config`로 복사
3. **LAN에서 서버 찾기** (같은 Wi‑Fi, Bonjour) 또는 **연결 테스트**

> **TLS 오류 (`A TLS error caused the secure connection to fail`)**  
> MiniOps API는 평문 **HTTP**만 제공합니다. `https://192.168.x.x:8787`로 접속하면 위 오류가 납니다. 반드시 `http://`를 사용하세요.

메뉴바에 표시되는 CPU/Memory/Disk/Docker는 **Mac Mini 서버** 기준입니다.

**API Token은 보안상 자동 공유되지 않습니다.** 맥미니에서 한 번 복사해 입력해야 합니다.

### LAN에서 서버 찾기가 안 될 때

Bonjour(mDNS)는 **서버·클라이언트 둘 다 최신 빌드**가 필요합니다.

**맥미니 (서버):**

```bash
brew update
brew upgrade miniops
brew services restart miniops
```

로그에 `(Bonjour: _miniops._tcp)`가 보이면 광고 중입니다.

**클라이언트 Mac:**

- Xcode에서 MiniOps 앱 다시 빌드·실행
- **시스템 설정 → 개인정보 보호 및 보안 → 로컬 네트워크**에서 MiniOps 허용

직접 `http://<IP>:8787` 입력은 Bonjour 없이도 동작합니다.

Bonjour가 막혀 있으면 앱이 **같은 Wi‑Fi 서브넷**을 스캔해 `/api/v1/health`로 서버를 찾습니다 (수 초 소요).

### 터미널 (curl)

```bash
# 헬스 체크 (인증 불필요)
curl http://192.168.0.10:8787/api/v1/health

# 전체 상태 (토큰 필요)
curl -H "Authorization: Bearer <your-token>" \
  http://192.168.0.10:8787/api/v1/status

# 메트릭
curl -H "Authorization: Bearer <your-token>" \
  http://192.168.0.10:8787/api/v1/metrics

# Docker 컨테이너
curl -H "Authorization: Bearer <your-token>" \
  http://192.168.0.10:8787/api/v1/docker

# Health Check 결과
curl -H "Authorization: Bearer <your-token>" \
  http://192.168.0.10:8787/api/v1/health-checks
```

`192.168.0.10`은 Mac Mini의 실제 LAN IP로 바꾸세요.

## 3. 구성 요약

| 구성 요소 | 설치 위치 | 역할 |
|-----------|-----------|------|
| **miniopsd** | Mac Mini | CPU/Memory/Disk/Docker 수집 + LAN API 제공 |
| **메뉴바 앱** | 같은 Wi‑Fi의 다른 Mac | miniopsd API로 **서버** 상태 조회 (클라이언트 전용) |

Mac Mini에서 GUI 없이 모니터링하려면 **miniopsd**만 설치하면 됩니다. 메뉴바 앱은 다른 Mac에서 서버 상태를 볼 때 사용합니다.

## 4. API 엔드포인트

| Method | Path | 인증 | 설명 |
|--------|------|------|------|
| GET | `/api/v1/health` | 불필요 | API 자체 상태 |
| GET | `/api/v1/status` | Bearer | 전체 상태 요약 |
| GET | `/api/v1/metrics` | Bearer | CPU/Memory/Disk |
| GET | `/api/v1/docker` | Bearer | Docker 컨테이너 목록 |
| GET | `/api/v1/docker/{name}/logs?tail=200` | Bearer | Docker 컨테이너 로그 (최근 N줄) |
| GET | `/api/v1/health-checks` | Bearer | Health Check 결과 |
| GET | `/api/v1/settings` | Bearer | 서버 설정 (`dockerPath` 등) |
| PATCH | `/api/v1/settings` | Bearer | 서버 설정 변경 (`{"dockerPath":"..."}`) |

## 5. 보안 권장사항

- API Token을 공개 저장소나 채팅에 올리지 마세요
- API는 기본적으로 **같은 LAN** 에서만 접근하는 것을 권장합니다
- MiniOps API URL(`localhost:8787/api/...`)은 Health Check 대상으로 등록하지 마세요 (자기 참조 방지)
- 외부(인터넷)에 노출하려면 리버스 프록시 + HTTPS를 별도로 구성하세요

## 6. 문제 해결

| 증상 | 확인 사항 |
|------|-----------|
| 연결 거부 | MiniOps 실행 여부, API 활성화, 포트 번호 |
| 401 Unauthorized | Bearer Token 헤더 형식 확인 |
| Docker unavailable | Docker Desktop 실행, Settings의 docker 경로 |
| LAN에서 접속 안 됨 | Mac Mini와 조회 기기가 **같은 Wi‑Fi** 인지 확인 |
| IP를 모르겠음 | Mac Mini에서 `ipconfig getifaddr en0` 실행 |
| macOS 방화벽 | 시스템 설정 → 네트워크 → 방화벽에서 MiniOps 허용 |

## 7. (선택) 외부에서 접속이 필요할 때

MiniOps는 LAN 사용을 기본으로 합니다. 집 밖에서 접속하려면 아래 중 하나를 **별도로** 구성하세요.

- 공유기 포트포워딩 + HTTPS
- Cloudflare Tunnel

이 경우에도 MiniOps **서버 URL**에 해당 주소를 입력하면 메뉴바 앱에서 조회할 수 있습니다.
