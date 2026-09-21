-- 시연이 걸린 숫자. 하나라도 어긋나면 화면이 정의서와 달라진다. make check 가 돌린다.
SELECT '지난주 485/456/29/18/94.0' AS 검사, sum(ord_cnt)||'/'||sum(ontime_cnt)||'/'||sum(delay_cnt)||'/'||sum(short_cnt)||'/'||round(100.0*sum(ontime_cnt)/sum(ord_cnt),1) AS 실측
  FROM wms.outbound_daily WHERE out_dt BETWEEN '2026-09-14' AND '2026-09-18'
UNION ALL SELECT '지연 29 · 사유 미입력 8', count(*)||' · '||count(*) FILTER (WHERE reason_cd IS NULL)
  FROM wms.delay_reason
UNION ALL SELECT '지연 주문이 실재하는가 29', count(*)::text
  FROM wms.delay_reason d JOIN wms.sales_order o USING (ord_no)
UNION ALL SELECT '사유 없는 건 중 입고 대기 6', count(*)::text
  FROM wms.delay_reason d JOIN wms.sales_order_line l USING (ord_no)
  WHERE d.reason_cd IS NULL AND l.item_cd IN ('4471','4472','4480','5102','5107','6210')
UNION ALL SELECT 'SKU4471 재고20 · 미배정 4건 40개',
  (SELECT sum(qty) FROM wms.stock_lot WHERE item_cd='4471')||' · '||count(*)||'건 '||sum(l.ord_qty)||'개'
  FROM wms.sales_order_line l JOIN wms.outbound_alloc a USING (ord_no,line_no)
  WHERE l.item_cd='4471' AND a.status='미배정'
UNION ALL SELECT '경합 입고예정 6 · 검사지정 2', count(*)||' · '||count(*) FILTER (WHERE status='검사 지정')
  FROM wms.inbound_plan WHERE item_cd IN ('4471','4472','4480','5102','5107','6210')
UNION ALL SELECT 'P-01 최근6 지연4 평균2.3', count(*) FILTER (WHERE delay_days>0)||' · '||round(avg(delay_days),1)
  FROM (SELECT delay_days FROM wms.vendor_lead_history WHERE vendor_cd='V-P01' ORDER BY promise_dt DESC LIMIT 6) t
UNION ALL SELECT '금일 83·61·22·17·6·7',
  ord_received||'·'||alloc_done||'·'||alloc_wait||'·'||picking||'·'||inbound_week||'·'||urgent_ord FROM wmsapi.today_work
UNION ALL SELECT '레거시가 판단을 내보내지 않는가', CASE WHEN count(*)=0 THEN '0 (정상)' ELSE count(*)||' (가공 뷰가 남아 있다)' END
  FROM information_schema.views WHERE table_schema='wmsapi'
    AND table_name IN ('risk_order','allocation_candidate','inbound_conflict','delay_segment')
UNION ALL SELECT '행수 거래처400 품목2000 Lot8000 주문479',
  (SELECT count(*) FROM wms.customer)||' '||(SELECT count(*) FROM wms.item)||' '||(SELECT count(*) FROM wms.stock_lot)||' '||(SELECT count(*) FROM wms.sales_order);
