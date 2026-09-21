-- HB-WMS 쓰기 인터페이스 — 승인 뒤에만 불린다. 둘 다 POST 다.
--
-- 인자는 **jsonb 하나**다. SAIP 워크플로의 post_execution webhook 이 본문을
-- `{"params": …, "action_result": …}` 로 감싸 보내고, PostgREST 는 `Prefer: params=single-object`
-- 로 그 본문 전체를 인자 하나에 담는다. 인자를 여럿으로 쪼개 두면 맞는 함수가 없어 404 가 난다.
-- 사람이 직접 부를 때도 같은 모양으로 보내면 된다.
\set ON_ERROR_STOP on

-- 출고 배정 변경. 에이전트가 바꾼 줄은 chg_by='AGT' 로 남아 레거시 화면에서 구분된다.
CREATE OR REPLACE FUNCTION wmsapi.apply_allocation(payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE body jsonb; actor text; c jsonb; n int := 0;
BEGIN
  body  := coalesce(payload->'action_result', payload);
  actor := coalesce(body->>'p_actor', 'SAIP');
  IF jsonb_typeof(body->'p_changes') <> 'array' THEN
    RAISE EXCEPTION 'p_changes(배열)가 필요합니다 — 받은 것: %', left(payload::text, 200);
  END IF;
  FOR c IN SELECT * FROM jsonb_array_elements(body->'p_changes') LOOP
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
  VALUES (actor, 'apply_allocation', jsonb_build_object('changed', n, 'changes', body->'p_changes'));
  RETURN jsonb_build_object('ok', true, 'changed', n, 'actor', actor, 'at', now());
END $$;

-- 거래처 안내 발송. WMS 가 아니라 안내 채널(CP)이다 — nginx 가 /cp/notifications 로 가린다.
CREATE OR REPLACE FUNCTION wmsapi.send_notice(payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE body jsonb; v_id bigint;
BEGIN
  body := coalesce(payload->'action_result', payload);
  IF body->>'p_ord_no' IS NULL OR body->>'p_body' IS NULL THEN
    RAISE EXCEPTION 'p_ord_no 와 p_body 가 필요합니다 — 받은 것: %', left(payload::text, 200);
  END IF;
  INSERT INTO wms.cp_notification (ord_no, cust_cd, channel, body_tx)
  VALUES (body->>'p_ord_no', body->>'p_cust_cd',
          coalesce(body->>'p_channel', '알림톡+이메일'), body->>'p_body')
  RETURNING notice_id INTO v_id;
  INSERT INTO wms.audit_log (actor, action, detail)
  VALUES ('CP', 'send_notice', jsonb_build_object('notice_id', v_id, 'ord_no', body->>'p_ord_no'));
  RETURN jsonb_build_object('ok', true, 'notice_id', v_id, 'ord_no', body->>'p_ord_no', 'at', now());
END $$;

GRANT EXECUTE ON FUNCTION wmsapi.apply_allocation(jsonb) TO wms_anon;
GRANT EXECUTE ON FUNCTION wmsapi.send_notice(jsonb) TO wms_anon;
