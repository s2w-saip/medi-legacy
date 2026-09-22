#!/usr/bin/env bash
# HB-WMS 더미 DB(hbwms) 복원 — dumps/2026-09-22. 사용: ./dumps/2026-09-22/restore.sh [--yes]
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; cd "$D/../.."
C=saip-medi-wmsdb
if [ "${1:-}" != --yes ]; then read -rp "hbwms DB 를 2026-09-22 덤프로 교체합니다 (기존 wms·wmsapi 객체는 지워짐). 계속? [y/N] " a; [ "$a" = y ] || exit 1; fi
(cd "$D" && sha256sum -c --quiet SHA256SUMS) || { echo "체크섬 불일치 — 덤프 파일이 손상됐다"; exit 1; }
docker compose up -d wmsdb
until [ "$(docker inspect -f '{{.State.Health.Status}}' "$C" 2>/dev/null)" = healthy ]; do sleep 2; done
docker exec -i "$C" psql -U hbwms -d hbwms -q < "$D/roles.sql" 2>&1 | grep -v 'already exists' || true        # 역할이 먼저 — 덤프 안 GRANT 21건이 참조한다
# wms_api 비밀번호 = PostgREST 가 쓰는 값(docker-compose.yml 의 PGRST_DB_URI, .env 반영). 덤프에는 해시를 넣지 않았다
PW="$(docker compose config --format json | python3 -c 'import json,sys,urllib.parse as u; print(u.urlsplit(json.load(sys.stdin)["services"]["wmsapi"]["environment"]["PGRST_DB_URI"]).password)')"
printf "ALTER ROLE wms_api WITH PASSWORD :'pw';\n" | docker exec -i "$C" psql -U hbwms -d hbwms -q -v pw="$PW"
if ! docker exec -i "$C" pg_restore -U hbwms -d hbwms --no-owner --clean --if-exists < "$D/hbwms.dump"; then
  echo "pg_restore 가 오류를 보고했다 — 위 로그를 확인한다"; exit 1; fi
docker compose up -d
docker compose restart wmsapi                                                                                    # PostgREST 스키마 캐시 재적재
echo "wms 표 $(docker exec "$C" psql -U hbwms -d hbwms -Atc "select count(*) from information_schema.tables where table_schema='wms' and table_type='BASE TABLE'") (기대 18) · wmsapi 뷰 $(docker exec "$C" psql -U hbwms -d hbwms -Atc "select count(*) from information_schema.views where table_schema='wmsapi'") (기대 17)"
make check
