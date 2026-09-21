-- HB-WMS 쓰기 인터페이스 — 승인 뒤에만 불린다. 둘 다 POST 다.
-- 워크플로 webhook 액션이 POST 만 보내므로 PUT 은 쓰지 않는다(교정 F7).
\set ON_ERROR_STOP on

-- 출고 배정 변경. 에이전트가 바꾼 줄은 chg_by='AGT' 로 남아 레거시 화면에서 구분된다.
CREATE OR REPLACE FUNCTION wmsapi.apply_allocation(p_actor text, p_changes jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE c jsonb; n int := 0;
BEGIN
  IF p_actor IS NULL OR p_changes IS NULL OR jsonb_typeof(p_changes) <> 'array' THEN
    RAISE EXCEPTION 'p_actor 와 p_changes(배열)가 필요합니다';
  END IF;
  FOR c IN SELECT * FROM jsonb_array_elements(p_changes) LOOP
    UPDATE wms.outbound_alloc a
       SET alloc_qty = coalesce((c->>'alloc_qty')::int, a.alloc_qty),
           lot_no    = coalesce(c->>'lot_no', a.lot_no),
           out_dt    = coalesce((c->>'out_dt')::date, a.out_dt),
           status    = coalesce(c->>'status', a.status),
           chg_by    = 'AGT',
           chg_at    = now()
     WHERE a.ord_no = c->>'ord_no';
    IF FOUND THEN n := n + 1; END IF;
  END LOOP;
  INSERT INTO wms.audit_log (actor, action, detail)
  VALUES (p_actor, 'apply_allocation', jsonb_build_object('changed', n, 'changes', p_changes));
  RETURN jsonb_build_object('ok', true, 'changed', n, 'actor', p_actor, 'at', now());
END $$;

-- 거래처 안내 발송. WMS 가 아니라 안내 채널(CP)이다 — nginx 가 /cp/notifications 로 가린다.
CREATE OR REPLACE FUNCTION wmsapi.send_notice(p_ord_no text, p_cust_cd text, p_channel text, p_body text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_id bigint;
BEGIN
  IF p_ord_no IS NULL OR p_body IS NULL THEN
    RAISE EXCEPTION 'p_ord_no 와 p_body 가 필요합니다';
  END IF;
  INSERT INTO wms.cp_notification (ord_no, cust_cd, channel, body_tx)
  VALUES (p_ord_no, p_cust_cd, coalesce(p_channel,'알림톡+이메일'), p_body)
  RETURNING notice_id INTO v_id;
  INSERT INTO wms.audit_log (actor, action, detail)
  VALUES ('CP', 'send_notice', jsonb_build_object('notice_id', v_id, 'ord_no', p_ord_no));
  RETURN jsonb_build_object('ok', true, 'notice_id', v_id, 'ord_no', p_ord_no, 'at', now());
END $$;

GRANT EXECUTE ON FUNCTION wmsapi.apply_allocation(text, jsonb) TO wms_anon;
GRANT EXECUTE ON FUNCTION wmsapi.send_notice(text, text, text, text) TO wms_anon;
