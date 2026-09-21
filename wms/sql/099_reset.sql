-- 시연 시작 상태로. 승인 전에는 아무것도 바뀌어 있으면 안 된다.
UPDATE wms.outbound_alloc SET alloc_qty=0, lot_no=NULL, out_dt=NULL, status='미배정', chg_by=NULL, chg_at=NULL
 WHERE ord_no IN ('#48810','#48811','#48812','#48820');
TRUNCATE wms.cp_notification, wms.audit_log RESTART IDENTITY;
SELECT '시연 시작 상태로 복원' AS 결과, count(*) AS 미배정
  FROM wms.outbound_alloc WHERE item_cd='4471' AND status='미배정';
