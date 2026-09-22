#!/usr/bin/env bash
# HB-WMS 더미 DB(hbwms) 복원 — 컨테이너/K8s Job 용. 덤프는 이미지 안 /dump 에 있다(Dockerfile db-restore 타깃).
# 환경변수: PGHOST(필수) PGPORT=5432 PGUSER=hbwms PGPASSWORD PGDATABASE=hbwms WMS_API_PASSWORD(PostgREST 접속 비밀번호, 주면 ALTER ROLE)
set -euo pipefail
: "${PGHOST:?PGHOST 가 필요하다 (postgres 서비스 이름)}"
export PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-hbwms}" PGDATABASE="${PGDATABASE:-hbwms}"
D="${DUMP_DIR:-/dump}"
until pg_isready -q; do echo "postgres 대기 $PGHOST:$PGPORT"; sleep 2; done
echo "1) 역할 (wms_anon · wms_api)"; psql -q < "$D/roles.sql" 2>&1 | grep -v 'already exists' || true
if [ -n "${WMS_API_PASSWORD:-}" ]; then printf "ALTER ROLE wms_api WITH PASSWORD :'pw';\n" | psql -q -v pw="$WMS_API_PASSWORD"; echo "   wms_api 비밀번호 설정"; fi
echo "2) pg_restore hbwms.dump (--clean --if-exists: 다시 돌려도 덮어쓴다)"
if ! pg_restore -d "$PGDATABASE" --no-owner --clean --if-exists "$D/hbwms.dump"; then echo "pg_restore 가 오류를 보고했다"; exit 1; fi
echo "3) 확인: wms 표 $(psql -Atc "select count(*) from information_schema.tables where table_schema='wms' and table_type='BASE TABLE'") (기대 18) · wmsapi 뷰 $(psql -Atc "select count(*) from information_schema.views where table_schema='wmsapi'") (기대 17) · stock_lot $(psql -Atc 'select count(*) from wms.stock_lot') (기대 8000)"
echo "완료 — PostgREST(wmsapi) 를 재시작해 스키마 캐시를 다시 읽게 한다"
