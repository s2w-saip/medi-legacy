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

-- S2 1층 · 구간 판정. 사유 코드가 몇 개든 구간은 셋이다(기타 포함 넷).
CREATE OR REPLACE VIEW wmsapi.delay_segment AS
SELECT seg, count(*) AS delay_cnt, sum(qty) AS short_qty,
       round(100.0*count(*)/sum(count(*)) OVER (),0) AS pct,
       count(*) FILTER (WHERE reason_cd IS NULL) AS no_reason_cnt
FROM wms.delay_reason GROUP BY seg;

-- S2 2층 · 고른 구간 안의 사유. 사유가 비어 있는 줄을 숨기지 않는다.
CREATE OR REPLACE VIEW wmsapi.delay_reason AS
SELECT seg, coalesce(reason_cd,'NO-REASON') AS reason_cd,
       coalesce(reason_nm,'기타 · 사유 미입력') AS reason_nm,
       count(*) AS delay_cnt, sum(qty) AS short_qty
FROM wms.delay_reason GROUP BY 1,2,3;

-- S3 · 결품 → SKU → 입고예정 → 공급공장
CREATE OR REPLACE VIEW wmsapi.shortage_trace AS
SELECT i.inb_no, i.item_cd, it.item_nm, i.plan_dt, i.status, i.customs_no,
       p.po_no, p.vendor_cd, v.vendor_nm, v.plant_cd
FROM wms.inbound_plan i
JOIN wms.purchase_order p USING (po_no)
JOIN wms.vendor v USING (vendor_cd)
JOIN wms.item it ON it.item_cd = i.item_cd
WHERE i.item_cd IN ('4471','4472','4480','5102','5107','6210');

-- S4 · 소스 대조. 한 줄에 우리 시스템이 아는 값과, 밖에서 확인할 키와,
-- 이미 우리 안에 있는데 아무도 안 보던 납기 이력이 같이 선다.
CREATE OR REPLACE VIEW wmsapi.inbound_conflict AS
SELECT i.inb_no, i.item_cd, i.plan_qty,
       i.plan_dt                                   AS wms_plan_dt,      -- WMS 가 들고 있는 예정일
       i.status                                    AS wms_status,
       i.customs_no                                AS customs_key,      -- 외부 통관 조회 키
       p.po_no, v.vendor_cd, v.plant_cd,
       h.late_cnt, h.total_cnt, h.avg_delay                             -- 정산관에 있던 값
FROM wms.inbound_plan i
JOIN wms.purchase_order p USING (po_no)
JOIN wms.vendor v USING (vendor_cd)
LEFT JOIN LATERAL (
  SELECT count(*) FILTER (WHERE delay_days>0) AS late_cnt, count(*) AS total_cnt,
         round(avg(delay_days),1) AS avg_delay
  FROM (SELECT delay_days FROM wms.vendor_lead_history
        WHERE vendor_cd = v.vendor_cd ORDER BY promise_dt DESC LIMIT 6) r
) h ON true;

-- S4 · 위험 주문 — 납기가 걸렸는데 아직 배정이 안 된 것
CREATE OR REPLACE VIEW wmsapi.risk_order AS
SELECT o.ord_no, o.cust_cd, c.cust_nm, c.grade, c.region, c.top10_yn, c.penalty_krw,
       o.due_dt, o.ord_type, o.urgent_yn, l.item_cd, l.ord_qty,
       coalesce(s.on_hand,0) AS on_hand,
       CASE WHEN coalesce(s.on_hand,0) = 0 THEN '결품' ELSE '경합' END AS risk_tx,
       m.memo_tx
FROM wms.sales_order o
JOIN wms.sales_order_line l USING (ord_no)
JOIN wms.outbound_alloc a USING (ord_no, line_no)
JOIN wms.customer c USING (cust_cd)
LEFT JOIN LATERAL (SELECT sum(qty) AS on_hand FROM wms.stock_lot WHERE item_cd = l.item_cd) s ON true
LEFT JOIN LATERAL (SELECT memo_tx FROM wms.sales_memo WHERE cust_cd = o.cust_cd
                   ORDER BY memo_dt DESC LIMIT 1) m ON true
WHERE a.status = '미배정' AND o.due_dt <= '2026-09-28';

-- S5 · 배분 후보. 점수는 SAIP 가 계산한다 — 여기서는 근거가 될 사실만 낸다.
CREATE OR REPLACE VIEW wmsapi.allocation_candidate AS
SELECT r.*, (SELECT alt_item_cd FROM wms.item_alt WHERE item_cd = r.item_cd LIMIT 1) AS alt_item_cd
FROM wmsapi.risk_order r;

-- S7 · 출고관리 > 출고재고할당 (레거시 화면이 보는 그 표)
CREATE OR REPLACE VIEW wmsapi.outbound_alloc AS
SELECT a.alloc_no, a.ord_no, o.cust_cd, c.cust_nm, a.item_cd, l.ord_qty, a.alloc_qty,
       a.lot_no, a.out_dt, a.status, a.chg_by, a.chg_at
FROM wms.outbound_alloc a
JOIN wms.sales_order o USING (ord_no)
JOIN wms.sales_order_line l ON l.ord_no = a.ord_no AND l.line_no = a.line_no
JOIN wms.customer c USING (cust_cd);

CREATE OR REPLACE VIEW wmsapi.stock_lot AS
SELECT lot_no, item_cd, qty, exp_dt, recv_dt, loc_cd FROM wms.stock_lot WHERE qty > 0;
CREATE OR REPLACE VIEW wmsapi.customer AS
SELECT cust_cd, cust_nm, cust_type, grade, region, top10_yn, penalty_krw FROM wms.customer;
CREATE OR REPLACE VIEW wmsapi.item_alt AS SELECT item_cd, alt_item_cd, note FROM wms.item_alt;
CREATE OR REPLACE VIEW wmsapi.sales_memo AS SELECT memo_id, cust_cd, memo_dt, memo_tx, author FROM wms.sales_memo;
CREATE OR REPLACE VIEW wmsapi.cp_notification AS
SELECT notice_id, ord_no, cust_cd, channel, body_tx, sent_at FROM wms.cp_notification;
CREATE OR REPLACE VIEW wmsapi.audit_log AS
SELECT audit_id, actor, action, detail, acted_at FROM wms.audit_log ORDER BY acted_at DESC;

GRANT SELECT ON ALL TABLES IN SCHEMA wmsapi TO wms_anon;
