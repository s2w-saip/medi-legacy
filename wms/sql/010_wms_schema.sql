-- HB-WMS v4.2.17 통합창고관리시스템 — 레거시 스키마
-- 모듈 구성은 S0 화면의 메뉴 그대로다: 기준정보 · 입고 · 출고 · 재고 · 운송 · 정산 · KPI
-- 정의서 4.1 이 OMS·MDM·ERP 로 나눠 적은 것은 이 안의 모듈이다(교정 F4).
\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS wmsapi CASCADE;
DROP SCHEMA IF EXISTS wms CASCADE;
CREATE SCHEMA wms;
CREATE SCHEMA wmsapi;

-- ── 기준정보관리 ─────────────────────────────────────────────
-- 거래처·품목·대체품·공급사. 4.1 의 "MDM·계약" 이 여기로 접힌다.
CREATE TABLE wms.customer (
  cust_cd      text PRIMARY KEY,
  cust_nm      text NOT NULL,
  cust_type    text NOT NULL,                 -- 병원 | 의원 | 대리점
  grade        text NOT NULL,                 -- A | B | C
  region       text NOT NULL,
  top10_yn     char(1) NOT NULL DEFAULT 'N',
  penalty_krw  integer NOT NULL DEFAULT 0     -- 납기 지연 시 건당 배상액. 0 이면 조항 없음
);
CREATE TABLE wms.item (
  item_cd   text PRIMARY KEY,
  item_nm   text NOT NULL,
  category  text NOT NULL,
  uom       text NOT NULL DEFAULT 'EA',
  import_yn char(1) NOT NULL DEFAULT 'Y'
);
CREATE TABLE wms.item_alt (
  item_cd     text NOT NULL REFERENCES wms.item(item_cd),
  alt_item_cd text NOT NULL,
  note        text,
  PRIMARY KEY (item_cd, alt_item_cd)
);
CREATE TABLE wms.vendor (
  vendor_cd text PRIMARY KEY,
  vendor_nm text NOT NULL,
  country   text NOT NULL,
  plant_cd  text NOT NULL
);

-- ── 주문관리 (출고관리 > 출고주문조회) ────────────────────────
-- 4.1 의 "OMS" 가 여기로 접힌다. S0 금일 현황의 '출고주문 접수·응급주문' 이 이 표다.
CREATE TABLE wms.sales_order (
  ord_no    text PRIMARY KEY,
  cust_cd   text NOT NULL REFERENCES wms.customer(cust_cd),
  ord_dt    date NOT NULL,
  due_dt    date NOT NULL,
  ord_type  text NOT NULL DEFAULT '판매',     -- 판매 | 응급
  urgent_yn char(1) NOT NULL DEFAULT 'N',
  status    text NOT NULL DEFAULT '접수'
);
CREATE TABLE wms.sales_order_line (
  ord_no   text NOT NULL REFERENCES wms.sales_order(ord_no),
  line_no  smallint NOT NULL,
  item_cd  text NOT NULL REFERENCES wms.item(item_cd),
  ord_qty  integer NOT NULL,
  PRIMARY KEY (ord_no, line_no)
);

-- ── 입고관리 ──────────────────────────────────────────────────
CREATE TABLE wms.purchase_order (
  po_no      text PRIMARY KEY,
  vendor_cd  text NOT NULL REFERENCES wms.vendor(vendor_cd),
  item_cd    text NOT NULL REFERENCES wms.item(item_cd),
  po_qty     integer NOT NULL,
  po_dt      date NOT NULL,
  promise_dt date NOT NULL
);
CREATE TABLE wms.inbound_plan (
  inb_no     text PRIMARY KEY,
  po_no      text NOT NULL REFERENCES wms.purchase_order(po_no),
  item_cd    text NOT NULL REFERENCES wms.item(item_cd),
  plan_qty   integer NOT NULL,
  plan_dt    date NOT NULL,                   -- WMS 가 들고 있는 예정일 — S4 에서 틀린 것으로 드러나는 값
  status     text NOT NULL,                   -- 반입 전 | 검사 지정 | 수리 완료 | 입고 완료
  customs_no text                             -- 통관 건 번호. 외부 통관 API 의 키다
);

-- ── 출고관리 ──────────────────────────────────────────────────
CREATE TABLE wms.outbound_alloc (
  alloc_no  bigserial PRIMARY KEY,
  ord_no    text NOT NULL REFERENCES wms.sales_order(ord_no),
  line_no   smallint NOT NULL,
  item_cd   text NOT NULL,
  alloc_qty integer NOT NULL DEFAULT 0,
  lot_no    text,
  out_dt    date,
  status    text NOT NULL DEFAULT '미배정',   -- 미배정 | 할당완료 | 부분할당 | 입고대기 | 피킹중 | 출고완료
  chg_by    text,                              -- 변경자. 에이전트가 바꾼 줄은 'AGT'
  chg_at    timestamptz
);
CREATE INDEX ON wms.outbound_alloc (ord_no);
CREATE TABLE wms.outbound_daily (
  out_dt      date PRIMARY KEY,
  ord_cnt     integer NOT NULL,
  ontime_cnt  integer NOT NULL,
  delay_cnt   integer NOT NULL,
  short_cnt   integer NOT NULL,
  out_qty     integer NOT NULL,
  parcel_cnt  integer NOT NULL
);
-- 지연 사유. seg 가 구간이다 — 사유 코드가 몇 개든 구간은 셋이다(현업 우려 반영).
CREATE TABLE wms.delay_reason (
  ord_no    text NOT NULL,
  seg       text NOT NULL,                    -- 입고 | 창고 | 배송 | 기타
  reason_cd text,                              -- 비어 있을 수 있다 — '사유 미입력' 이 곧 결론이다
  reason_nm text,
  qty       integer NOT NULL DEFAULT 0,
  occur_dt  date NOT NULL
);

-- ── 재고관리 ──────────────────────────────────────────────────
CREATE TABLE wms.stock_lot (
  lot_no  text PRIMARY KEY,
  item_cd text NOT NULL REFERENCES wms.item(item_cd),
  qty     integer NOT NULL,
  exp_dt  date,                                -- 유효기간. 일부러 일부 비운다
  recv_dt date NOT NULL,
  loc_cd  text NOT NULL
);
CREATE INDEX ON wms.stock_lot (item_cd);

-- ── 운송관리 ──────────────────────────────────────────────────
-- 운송사 추적 자체는 외부 API 다. 이 표는 그 결과를 받아 보관하는 자리다(교정 F11).
CREATE TABLE wms.shipment (
  ship_no    text PRIMARY KEY,
  ord_no     text NOT NULL,
  carrier_cd text NOT NULL,
  status     text NOT NULL,
  eta_dt     date
);

-- ── 정산관 ────────────────────────────────────────────────────
-- 4.1 의 "ERP 구매" 가 여기로 접힌다(결정 5). S4 의 두 번째 근거 —
-- 이미 우리 시스템 안에 있는데 아무도 안 보던 값이다.
CREATE TABLE wms.vendor_lead_history (
  vendor_cd  text NOT NULL REFERENCES wms.vendor(vendor_cd),
  po_no      text NOT NULL,
  promise_dt date NOT NULL,
  actual_dt  date NOT NULL,
  delay_days integer NOT NULL
);
CREATE INDEX ON wms.vendor_lead_history (vendor_cd);

-- ── 영업 메모 (업로드) ────────────────────────────────────────
CREATE TABLE wms.sales_memo (
  memo_id bigserial PRIMARY KEY,
  cust_cd text NOT NULL,
  memo_dt date NOT NULL,
  memo_tx text NOT NULL,
  author  text NOT NULL
);

-- ── KPI/리포트 ────────────────────────────────────────────────
CREATE TABLE wms.kpi_weekly (
  seq        smallint PRIMARY KEY,
  kpi_cd     text NOT NULL,
  kpi_nm     text NOT NULL,
  target_tx  text NOT NULL,
  actual_val numeric NOT NULL,
  prev_val   numeric NOT NULL,
  rate_val   numeric NOT NULL,
  judge      text NOT NULL,                   -- 달성 | 미달
  alert_tx   text,
  dec_pt     smallint NOT NULL DEFAULT 1   -- 화면 표시 자릿수. PostgREST 가 numeric 을 수로 내보내 94.0 이 94 가 된다
);

-- ── 안내 발송 기록 (CP 채널 — WMS 가 아니다) ──────────────────
CREATE TABLE wms.cp_notification (
  notice_id bigserial PRIMARY KEY,
  ord_no    text NOT NULL,
  cust_cd   text NOT NULL,
  channel   text NOT NULL,
  body_tx   text NOT NULL,
  sent_at   timestamptz NOT NULL DEFAULT now()
);

-- ── 감사 로그 ─────────────────────────────────────────────────
CREATE TABLE wms.audit_log (
  audit_id bigserial PRIMARY KEY,
  actor    text NOT NULL,
  action   text NOT NULL,
  detail   jsonb,
  acted_at timestamptz NOT NULL DEFAULT now()
);

-- ── 연계 롤 ───────────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='wms_anon') THEN CREATE ROLE wms_anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='wms_api') THEN
    CREATE ROLE wms_api LOGIN PASSWORD 'wms_api_pw';
  END IF;
END $$;
GRANT wms_anon TO wms_api;
GRANT USAGE ON SCHEMA wmsapi TO wms_anon;
GRANT USAGE ON SCHEMA wms TO wms_anon;
