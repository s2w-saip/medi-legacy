# 한빛메디컬 HB-WMS — 레거시 통합창고관리시스템 더미 (medi-legacy)
#
#   wmsdb   PostgreSQL 55433   레거시 DB (스키마 wms · 연계 뷰 wmsapi)
#   wmsapi  PostgREST  (내부)  조회 뷰 16 + 쓰기 RPC 2
#   wmsweb  nginx      8099    경계 하나 — / S0 화면 · /api 연계 · /cp 안내 채널 · /external 제3자 목
#
# 대상 DB 컨테이너는 WMSDB_CONTAINER 로 바꾼다 (기본 = 라이브 saip-medi-wmsdb).
SHELL := /bin/bash
DC    := docker compose
WMSDB_CONTAINER ?= saip-medi-wmsdb
PSQL      := docker exec -i $(WMSDB_CONTAINER) psql -U hbwms -d hbwms -q -v ON_ERROR_STOP=1
PSQL_LOAD := docker exec -e PGOPTIONS=--client-min-messages=warning -i $(WMSDB_CONTAINER) psql -U hbwms -d hbwms -q -v ON_ERROR_STOP=1
SEED  ?=
GEN   := python3 wms/gen_wms_data.py $(if $(SEED),--seed $(SEED),)
SQL_FILES := 010_wms_schema 020_wms_api 030_wms_rpc
BASE  := http://127.0.0.1:8099

.PHONY: help up down logs psql seed gen load check reset

help:
	@echo "up      레거시 3 서비스 기동 (DB → API → 화면)"
	@echo "down    중지"
	@echo "seed    스키마·뷰·RPC 적재 + 더미 생성·적재 (전체 초기화)"
	@echo "check   시연이 걸린 숫자 8가지 검증"
	@echo "reset   시연 시작 상태로 되돌리기 (배정 해제 · 안내·감사 로그 비우기)"
	@echo "psql    DB 셸"

up:
	$(DC) up -d
	@for i in $$(seq 1 30); do \
	  s=$$(docker inspect -f '{{.State.Health.Status}}' $(WMSDB_CONTAINER) 2>/dev/null || echo none); \
	  [ "$$s" = healthy ] && break; sleep 2; done
	@echo "S0 화면 $(BASE)/  ·  연계 API $(BASE)/api/"

down:
	$(DC) down

logs:
	$(DC) logs -f --tail=80

psql:
	docker exec -it $(WMSDB_CONTAINER) psql -U hbwms -d hbwms

gen:
	@$(GEN) > /tmp/hbwms_seed.sql && echo "생성 $$(wc -l < /tmp/hbwms_seed.sql) 줄"

seed: gen
	@for f in $(SQL_FILES); do $(PSQL_LOAD) < wms/sql/$$f.sql || exit 1; done
	@$(PSQL_LOAD) < /tmp/hbwms_seed.sql
	@echo "적재 완료"
	@$(MAKE) --no-print-directory check

# 시연이 걸린 숫자. 하나라도 어긋나면 화면이 정의서와 달라진다.
check:
	@$(PSQL) -P border=2 -f /dev/stdin < wms/sql/090_check.sql

# 승인 전에는 아무것도 바뀌어 있으면 안 된다.
reset:
	@$(PSQL) -P border=2 -f /dev/stdin < wms/sql/099_reset.sql
