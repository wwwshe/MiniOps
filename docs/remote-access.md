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
2. (선택) Health Check URL은 추후 메뉴바 앱 또는 설정 파일로 등록

### Mac Mini IP 직접 확인

```bash
# Wi‑Fi IP (일반적)
ipconfig getifaddr en0

# 또는
ifconfig en0 | grep "inet "
```

## 2. 같은 Wi‑Fi에서 조회

### MiniOps Mac 앱 (클라이언트)

1. 같은 Wi‑Fi에 연결된 Mac에 MiniOps 설치
2. 설정 → **서버** 탭 → **원격 서버 조회** 선택
3. 입력:
   - **서버 URL**: `http://192.168.0.10:8787` (Mac Mini LAN IP)
   - **API Token**: Mac Mini에서 복사한 토큰
4. **연결 테스트** 클릭

메뉴바에 표시되는 CPU/Memory/Disk/Docker는 **Mac Mini 서버** 기준입니다.

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

## 3. 두 가지 모드

| 모드 | 설치 위치 | 역할 |
|------|-----------|------|
| **서버 (에이전트)** | Mac Mini | CPU/Memory/Disk/Docker 수집 + API 제공 |
| **원격 서버 조회 (클라이언트)** | 같은 Wi‑Fi의 다른 Mac | LAN API로 **서버** 상태 조회 |

Mac Mini에서만 쓸 경우 **서버 (에이전트)** 만 선택하면 됩니다. 다른 Mac은 필요 없습니다.

## 4. API 엔드포인트

| Method | Path | 인증 | 설명 |
|--------|------|------|------|
| GET | `/api/v1/health` | 불필요 | API 자체 상태 |
| GET | `/api/v1/status` | Bearer | 전체 상태 요약 |
| GET | `/api/v1/metrics` | Bearer | CPU/Memory/Disk |
| GET | `/api/v1/docker` | Bearer | Docker 컨테이너 목록 |
| GET | `/api/v1/health-checks` | Bearer | Health Check 결과 |

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

이 경우에도 MiniOps **서버 URL**에 해당 주소를 입력하면 클라이언트 모드로 조회할 수 있습니다.
