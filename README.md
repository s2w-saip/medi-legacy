# medi-legacy — 한빛메디컬 HB-WMS

MediOS 데모가 붙는 **고객 레거시**다. SAIP 밖이다.

레거시는 **HB-WMS 하나**다. 구축정의서 4.1 이 OMS·MDM·ERP 로 나눠 적은 것은 이 통합 WMS 의
모듈(주문 · 기준정보 · 정산)이고, 근거는 S0 화면의 메뉴다 — 이름부터 "통합창고관리시스템" 이다.

## 구성

| | 무엇 | 포트 |
|---|---|---|
| `wmsdb` | PostgreSQL — 스키마 `wms`(레거시 본체) · `wmsapi`(연계 뷰·RPC) | `55433` 내부 |
| `wmsapi` | PostgREST — 조회 뷰 16 + 쓰기 RPC 2. **밖으로 직접 열지 않는다** | — |
| `wmsweb` | nginx — 경계 하나 | **`8099`** |

경계 8099 가 네 갈래를 가른다.

| 경로 | 무엇 |
|---|---|
| `/` | **S0 레거시 WMS 화면** — 출고 KPI 현황. 툴바의 "AI 판단 요청" 이 데모의 출발 버튼 |
| `/api/` | 연계 API — 커넥터가 읽는 뷰, 승인 뒤 부르는 RPC |
| `/cp/notifications` | 거래처 안내 채널. **WMS 가 아니다.** `POST` 만 받는다 |
| `/external/` | 제3자 목 — `customs` · `courier` · `weather`. 고객 시스템과 경로를 가른다 |

**쓰기는 `POST` 뿐이다.** SAIP 워크플로의 `webhook` 액션이 `POST` 만 보내므로 `PUT` 은 만들지 않았다.
`PUT /cp/notifications` 는 405 로 막힌다.

## 쓰기

```bash
curl -X POST http://10.0.20.132:8099/api/rpc/apply_allocation -H 'Content-Type: application/json' \
  -d '{"p_actor":"센터장","p_changes":[{"ord_no":"#48810","alloc_qty":10,"lot_no":"L-2607","out_dt":"2026-09-21","status":"할당완료"}]}'
```

에이전트가 바꾼 줄은 `chg_by='AGT'` 로 남아 레거시 화면에서 구분된다. 모든 쓰기는 `wms.audit_log` 에 기록된다.

## 쓰는 법

```bash
make up      # 3 서비스 기동
make seed    # 스키마·뷰·RPC + 더미 생성·적재 → 자동으로 check 까지
make check   # 시연이 걸린 숫자 8가지 검증
make reset   # 시연 시작 상태로 (배정 해제 · 안내·감사 로그 비우기)
```

## 다른 호스트/쿠버네티스에서 띄울 때

화면·API 는 이미 같은 origin(nginx 8099 → `/api/`)이라 html 을 고칠 것이 없다. 호스트마다 다른 값은 둘뿐이다.

| 무엇 | 어디서 | 기본값(시연 VM) |
|---|---|---|
| "AI 판단 요청" 버튼이 여는 MediOS 주소 | `wms/web/config.js` — `window.WMS_CONFIG = { mediosUrl: '…' }`. index.html 이 먼저 읽고 `window.WMS_CONFIG?.mediosUrl` 을 쓴다. 빌드 없음 — 쿠버네티스에서는 `web` 이미지에 compose 기본값으로 들어 있는 이 파일 하나를 ConfigMap 으로 `/usr/share/nginx/html/config.js` 에 덮어씌운다(예: `https://medios.dev.saip.io/medi`) | `http://10.0.20.132:8088/medi` |
| PostgREST OpenAPI 에 적히는 공개 주소 | env `WMS_PUBLIC_URL` (`.env` 또는 배포 env) → `PGRST_OPENAPI_SERVER_PROXY_URI=${WMS_PUBLIC_URL}/api` | `http://10.0.20.132:8099` |

쿠버네티스 예: 공개 URL `https://medi-legacy.dev.saip.io` 하나 — `WMS_PUBLIC_URL=https://medi-legacy.dev.saip.io`, config.js 의 `mediosUrl: 'https://medios.dev.saip.io/medi'`. 브라우저는 origin 하나만 본다.
쿠버네티스용 이미지는 루트 [Dockerfile](Dockerfile) 의 타깃 `web`·`db-restore` 다 — 아래 "K8s 시연용 이미지".

## 데이터

기준 시각 **2026-09-21(월) 07:26**, 지난주는 9/14~9/18. `wms/gen_wms_data.py` 가 매번 같은 숫자를 낸다.

거래처 400 · 품목 2,000(대체 60쌍) · Lot 8,000 · 주문 450 · 발주·입고예정 40 · 공급사 납기 이력 72 · 영업 메모 5.
그 안에 시연이 걸린 값이 심겨 있다 — 지난주 정시출고율 **94.0%**(지연 29 = 입고 18 · 창고 3 · 배송 1 · 기타 7),
경합 SKU 6개가 전부 공급공장 **P-01** 대기(그중 둘은 통관 검사 지정), **SKU 4471 재고 20 vs 미배정 주문 4건 40개**,
P-01 최근 6회 중 4회 지연 평균 +2.3일.

기획 문서의 어긋남 교정(F1·F2·F12)을 반영했다 — C의원 주문은 4471·5개, 4472 결품은 대전G병원,
E병원은 경기E병원 하나다.

문서: [MediOS 개발 계획](http://10.0.20.132:8091/docs/plans/2026-09-21-medios-dev-plan.html) ·
[구축정의서·교정안](http://10.0.20.132:8091/docs/plans/2026-09-21-medi-outbound-agent.html)

## K8s 시연용 이미지

로컬은 `docker compose up` 그대로다. K8s 에 올릴 때만 [Dockerfile](Dockerfile) 의 타깃 둘을 굽는다 — `web`(nginx, S0 화면 내장)·`db-restore`(`dumps/2026-09-22` 덤프를 `PGHOST` 로 복원하는 일회성 Job, 환경변수는 `dumps/2026-09-22/restore-k8s.sh` 머리글). postgres·PostgREST 는 공식 이미지를 그대로 쓰고 환경변수는 `docker-compose.yml` 과 같다. **PostgREST Service 이름은 `wmsapi`, 포트 3000** — `wms/nginx-default.conf` 가 그 이름으로 `/api` 를 넘긴다(없으면 nginx 가 기동하지 않는다). 복원 뒤 PostgREST 를 재시작한다.

빌드 머신이 macOS(Apple Silicon, arm64)이고 목적지는 AKS(linux/amd64)다 — `--platform` 을 빼면 arm64 이미지가 만들어져 노드에서 `exec format error` 가 난다.

```bash
docker buildx build --platform linux/amd64 --target web        -t <registry>/demo-medi-legacy-web:<tag> --push .
docker buildx build --platform linux/amd64 --target db-restore -t <registry>/demo-medi-legacy-db-restore:<tag> --push .
```
