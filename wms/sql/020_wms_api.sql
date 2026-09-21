-- HB-WMS 연계 인터페이스 — PostgREST 가 여는 조회 뷰. 원본 표는 밖에서 보이지 않는다.
\set ON_ERROR_STOP on
SET search_path = wmsapi, wms, public;

-- S0 · KPI/리포트 > 출고KPI현황
CREATE OR REPLACE VIEW wmsapi.kpi_weekly AS
SELECT seq, kpi_cd, kpi_nm, target_tx, actual_val, prev_val, rate_val, judge, alert_tx, dec_pt FROM wms.kpi_weekly;

CREATE OR REPLACE VIEW wmsapi.outbound_daily AS
SELECT out_dt, to_char(out_dt,'Dy') AS dow, ord_cnt, ontime_cnt, delay_cnt, short_cnt,
       round(100.0*ontime_cnt/nullif(ord_cnt,0),1) AS ontime_rate, out_qty, parcel_cnt
FROM wms.outbound_daily ORDER BY out_dt;

-- S0 · 금일 작업 현황
CREATE OR REPLACE VIEW wmsapi.today_work AS
SELECT (SELECT count(*) FROM wms.sales_order WHERE ord_dt='2026-09-21')        AS ord_received,
       (SELECT count(*) FROM wms.outbound_alloc a JOIN wms.sales_order o USING (ord_no)
          WHERE o.ord_dt='2026-09-21' AND a.status<>'미배정')                   AS alloc_done,
       (SELECT count(*) FROM wms.outbound_alloc a JOIN wms.sales_order o USING (ord_no)
          WHERE o.ord_dt='2026-09-21' AND a.status='미배정')                    AS alloc_wait,
       (SELECT count(*) FROM wms.outbound_alloc a JOIN wms.sales_order o USING (ord_no)
          WHERE o.ord_dt='2026-09-21' AND a.status='피킹중')                    AS picking,
       (SELECT count(*) FROM wms.inbound_plan
          WHERE plan_dt BETWEEN '2026-09-21' AND '2026-09-27')                 AS inbound_week,
       (SELECT count(*) FROM wms.sales_order WHERE urgent_yn='Y')              AS urgent_ord;

-- ── 원천만 낸다 ──────────────────────────────────────────────
-- 아래 뷰들은 레거시가 **아는 것**만 낸다. 구간 판정 · 입고 보정일 · 위험 주문 · 배분 점수는
-- 레거시 어디에도 없는 값이고 SAIP 파이프라인이 만든다. 한때 여기서 계산해 내보냈는데
-- (risk_order · allocation_candidate · inbound_conflict) 그러면 데모가 제품을 건너뛴다 — 지웠다.

-- 수주 + 그 줄의 할당 상태. 할당 여부는 출고재고할당 화면이 보여 주는 WMS 사실이라 함께 낸다
-- (없으면 이미 나간 주문까지 "위험" 으로 잡힌다).
CREATE OR REPLACE VIEW wmsapi.sales_order AS
SELECT o.ord_no, o.cust_cd, o.ord_dt, o.due_dt, o.ord_type, o.urgent_yn, o.status,
       l.line_no, l.item_cd, l.ord_qty,
       coalesce(a.status, '미배정') AS alloc_status, coalesce(a.alloc_qty, 0) AS alloc_qty
FROM wms.sales_order o
JOIN wms.sales_order_line l USING (ord_no)
LEFT JOIN wms.outbound_alloc a ON a.ord_no = l.ord_no AND a.line_no = l.line_no;

CREATE OR REPLACE VIEW wmsapi.inbound_plan AS
SELECT i.inb_no, i.po_no, i.item_cd, i.plan_qty, i.plan_dt, i.status, i.customs_no,
       p.vendor_cd, p.promise_dt, v.plant_cd, v.vendor_nm
FROM wms.inbound_plan i JOIN wms.purchase_order p USING (po_no) JOIN wms.vendor v USING (vendor_cd);

CREATE OR REPLACE VIEW wmsapi.purchase_order AS
SELECT po_no, vendor_cd, item_cd, po_qty, po_dt, promise_dt FROM wms.purchase_order;

CREATE OR REPLACE VIEW wmsapi.vendor_lead_history AS
SELECT vendor_cd, po_no, promise_dt, actual_dt, delay_days FROM wms.vendor_lead_history;

-- 지연 사유 — **코드만** 준다. 어느 구간에서 샌 것인지는 WMS 가 알 리 없고 SAIP 가 정한다.
-- 사유가 비어 있는 줄도 그대로 내보낸다. 비어 있다는 사실 자체가 분석 대상이다.
CREATE OR REPLACE VIEW wmsapi.delay_reason AS
SELECT ord_no, reason_cd, reason_nm, qty, occur_dt FROM wms.delay_reason;

CREATE OR REPLACE VIEW wmsapi.item AS
SELECT item_cd, item_nm, category, uom, import_yn FROM wms.item;

-- S7 · 출고관리 > 출고재고할당 (레거시 화면이 보는 그 표)
CREATE OR REPLACE VIEW wmsapi.outbound_alloc AS
SELECT a.alloc_no, a.ord_no, o.cust_cd, c.cust_nm, a.item_cd, l.ord_qty, a.alloc_qty,
       a.lot_no, a.out_dt, a.status, a.chg_by, a.chg_at
FROM wms.outbound_alloc a
JOIN wms.sales_order o USING (ord_no)
JOIN wms.sales_order_line l ON l.ord_no = a.ord_no AND l.line_no = a.line_no
JOIN wms.customer c USING (cust_cd);

-- 재고관리 > 재고현황조회 — 품목별 가용 재고. WMS 화면이 그대로 보여 주는 값이라 Lot 8,000행을
-- 전부 끌어올 이유가 없다(끌어오면 페이지 상한에 걸려 재고가 틀리고, 없는 부족이 생긴다).
CREATE OR REPLACE VIEW wmsapi.stock_on_hand AS
SELECT item_cd, sum(qty)::int AS on_hand, count(*)::int AS lot_cnt,
       count(*) FILTER (WHERE exp_dt IS NULL)::int AS no_exp_cnt
FROM wms.stock_lot GROUP BY item_cd;

CREATE OR REPLACE VIEW wmsapi.stock_lot AS
SELECT lot_no, item_cd, qty, exp_dt, recv_dt, loc_cd FROM wms.stock_lot WHERE qty > 0;
CREATE OR REPLACE VIEW wmsapi.customer AS
SELECT cust_cd, cust_nm, cust_type, grade, region, top10_yn, penalty_krw FROM wms.customer;
CREATE OR REPLACE VIEW wmsapi.item_alt AS SELECT item_cd, alt_item_cd, note FROM wms.item_alt;
CREATE OR REPLACE VIEW wmsapi.sales_memo AS SELECT memo_id, cust_cd, item_cd, memo_dt, memo_tx, author FROM wms.sales_memo;
CREATE OR REPLACE VIEW wmsapi.cp_notification AS
SELECT notice_id, ord_no, cust_cd, channel, body_tx, sent_at FROM wms.cp_notification;
CREATE OR REPLACE VIEW wmsapi.audit_log AS
SELECT audit_id, actor, action, detail, acted_at FROM wms.audit_log ORDER BY acted_at DESC;

GRANT SELECT ON ALL TABLES IN SCHEMA wmsapi TO wms_anon;
