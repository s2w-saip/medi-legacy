# syntax=docker/dockerfile:1
# medi-legacy(한빛메디컬 HB-WMS 더미) — K8s 시연용 이미지 2개. 로컬은 docker-compose.yml(공식 이미지 + 바인드 마운트)을 그대로 쓴다.
#   web        : nginx 80 — S0 화면(wms/web, 제3자 목 JSON 포함)과 nginx 설정을 구워 넣는다 (compose 의 바인드 마운트 대신)
#                ※ nginx-default.conf 가 /api 를 http://wmsapi:3000 으로 넘기므로 K8s 에서 PostgREST Service 이름은 wmsapi, 포트 3000 이어야 기동한다
#   db-restore : dumps/2026-09-22 의 hbwms 덤프를 PGHOST 로 pg_restore 하는 일회성 Job (restore-k8s.sh)
# postgres(wmsdb)·PostgREST(wmsapi) 는 공식 이미지(postgres:16-alpine · postgrest/postgrest:v12.2.3)를 매니페스트에서 그대로 쓴다 — 환경변수는 docker-compose.yml 참고.
# 빌드: docker build --target web -t medi-legacy-web:local .   /   docker build --target db-restore -t medi-legacy-db-restore:local .

FROM nginx:1.27-alpine AS web
COPY wms/nginx-default.conf /etc/nginx/conf.d/default.conf
COPY wms/web/ /usr/share/nginx/html/
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --retries=5 --start-period=3s CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1

FROM postgres:16-alpine AS db-restore
COPY dumps/2026-09-22/hbwms.dump dumps/2026-09-22/roles.sql /dump/
COPY dumps/2026-09-22/restore-k8s.sh /usr/local/bin/restore-k8s.sh
USER postgres
ENTRYPOINT ["/usr/local/bin/restore-k8s.sh"]
