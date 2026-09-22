# HB-WMS 더미 DB(hbwms) 덤프 — 2026-09-22

컨테이너 `saip-medi-wmsdb`(postgres:16-alpine) 의 DB `hbwms`. 코드는 `master` HEAD `8992453` 기준, 덤프 시각 2026-09-22 05:22 UTC.

| 파일 | 무엇 | 검증 |
|---|---|---|
| `hbwms.dump` | `pg_dump -Fc` — `wms` 표 18 + `wmsapi` 뷰 17 · RPC 2(`apply_allocation`, `send_notice`) + GRANT 21 | TABLE DATA 18 = 라이브 18. 일회용 컨테이너에 복원해 18표 행 수와 `090_check.sql` 10항목 전부 일치 |
| `roles.sql` | `wms_anon`(NOLOGIN) · `wms_api`(LOGIN) + GRANT. **비밀번호 해시는 뺐다** — `restore.sh` 가 compose 설정(`.env` 반영)의 값으로 `ALTER ROLE` 한다 | `wms_api` 로 로그인해 뷰 17개 조회 확인 |
| `SHA256SUMS` | `sha256sum -c SHA256SUMS` | |

덤프 상태 = `make reset` 직후 (audit_log 0 · cp_notification 0 · 시퀀스 미사용). 생성기가 시드 고정이라 **`make up && make seed` 만으로도 같은 DB 가 난다** — 이 덤프는 보험이다.

## 복원

```bash
./dumps/2026-09-22/restore.sh          # 확인 질문 뒤 진행. --yes 로 생략
```

wmsdb 를 띄우고(healthy 대기) → 역할 → `pg_restore --clean --if-exists` → 나머지 기동 → PostgREST 재시작 → `make check`.
복원 뒤 `make seed` 를 돌리면 `010_wms_schema.sql` 의 `DROP SCHEMA CASCADE` 로 복원분이 지워진다(내용이 같아 손실은 없다). 시연 뒤 되돌릴 때는 `make reset && make check`.

## 새 호스트에서 바꿀 값

- env `WMS_PUBLIC_URL`(`.env`) — `docker-compose.yml:46` `PGRST_OPENAPI_SERVER_PROXY_URI` 가 `${WMS_PUBLIC_URL:-http://10.0.20.132:8099}/api` 로 읽는다. html 은 안 고친다
- `wms/web/config.js` 의 `mediosUrl` — "AI 판단 요청" 버튼이 여는 MediOS 주소(기본 옛 장비의 :8088). 안 바꾸면 데모 출발 버튼이 옛 장비로 간다. index.html 줄을 고치지 말고 이 파일(쿠버네티스면 ConfigMap)만 바꾼다
- PostgREST 접속 계정 `wms_api` 의 비밀번호는 `docker-compose.yml:41`(`.env` 의 `WMS_API_PASSWORD`)을 따른다 — `restore.sh` 가 그 값을 읽어 역할에 넣으므로 따로 맞출 것이 없다. `wms/sql/010_wms_schema.sql:192` 와도 같아야 `make seed` 경로가 맞는다
- platform 쪽 연결 `hbwms-legacy-api` 의 주소는 platform 덤프의 `saip_control.connections` 에 있다 — Factory 에서 고친다

## 복원 뒤 확인

```bash
make check                                                     # 10항목 기대=실측
curl -so/dev/null -w'%{http_code}\n' http://127.0.0.1:8099/     # 200
curl -s http://127.0.0.1:8099/api/today_work | head -c 200
```
