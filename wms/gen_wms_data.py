#!/usr/bin/env python3
"""HB-WMS 더미 데이터 생성기 — 한빛메디컬 김포 물류센터.

기준 시각은 2026-09-21(월) 07:26. 지난주는 9/14(월)~9/18(금)이다.
정의서의 화면 숫자를 그대로 재현하되, 교정안 F1·F2 를 반영한다:
  F1  C의원 주문은 SKU 4471 · 5개다(4472 · 4개 아님). 빠진 4472 결품 1건은 대전G병원으로 옮긴다.
  F2  SKU 4471 은 재고 20 / 주문 40개(4건), 미배정 20.
  F12 E병원은 경기E병원 하나다 — 원문이 S4 에서 '부산E병원', S5 에서 '경기 E병원' 으로 갈렸다.

출력은 psql 이 그대로 먹는 SQL 한 덩이다(stdout).
"""
from __future__ import annotations
import argparse, datetime as dt, random, sys

NOW = dt.date(2026, 9, 21)
LAST_WEEK = [dt.date(2026, 9, d) for d in (14, 15, 16, 17, 18)]
WD = "월화수목금토일"

# ── 시연이 걸린 고정 값 ────────────────────────────────────────
HOT_SKUS = ["4471", "4472", "4480", "5102", "5107", "6210"]   # 경합 SKU 6개 — 전부 P-01 대기
HOT_INB  = {"4471": "IN-2609", "4472": "IN-2610", "4480": "IN-2614",
            "5102": "IN-2615", "5107": "IN-2618", "6210": "IN-2619"}
CUSTOMS  = {"IN-2609": "검사 지정", "IN-2610": "검사 지정"}      # 나머지 넷은 반입 전
P01_RECENT_DELAY = [3, 0, 2, 4, 0, 5]                          # 최근 6회 중 4회 지연, 합 14 → 평균 2.33
DAILY = [  # 일자, 주문, 정시, 지연, 결품, 출고수량, 택배
    (LAST_WEEK[0],  98,  96, 2, 1, 2811, 41),
    (LAST_WEEK[1], 112, 108, 4, 2, 3042, 47),
    (LAST_WEEK[2], 104,  97, 7, 5, 2733, 39),
    (LAST_WEEK[3],  96,  87, 9, 6, 2406, 36),
    (LAST_WEEK[4],  75,  68, 7, 4, 2528, 33),
]
# 지난주 지연 29건의 구간·사유 — 1층 구간 셋, 2층은 구간 안 분포(기타·미입력을 숨기지 않는다)
DELAY_MIX = [
    ("입고", "VEND-LATE",  "공급공장 납기 지연",        6, 120),
    ("입고", "CUSTOMS",    "통관 세관 검사 지정",        2,  48),
    ("입고", "PO-CYCLE",   "발주 주기 — 분기 초 집중",   4,  92),
    ("입고", None,          None,                        6,  80),   # 사유 미입력·분산
    ("창고", "PICK-LATE",  "피킹 지연",                  3,  36),
    ("배송", "CARRIER",    "운송사 지연",                1,  12),
    ("기타", "MISC",       "사유 분산",                  5,  61),
    ("기타", None,          None,                        2,  19),
]
NAMED = [  # 거래처코드, 이름, 유형, 등급, 지역, top10, 페널티(건당)
    ("C0001", "서울A병원",   "병원",   "A", "서울",     "Y", 0),
    ("C0002", "경기B병원",   "병원",   "A", "경기북부", "Y", 300_000),
    ("C0003", "C의원",       "의원",   "C", "서울",     "N", 0),
    ("C0004", "D대리점",     "대리점", "B", "경기북부", "N", 0),
    ("C0005", "경기E병원",   "병원",   "B", "경기북부", "N", 0),
    ("C0006", "인천F병원",   "병원",   "B", "인천",     "Y", 150_000),
    ("C0007", "대전G병원",   "병원",   "B", "대전",     "Y", 0),
]
# 경합 오더 — 교정 F1·F2 적용. 4471 재고 20 vs 주문 40개(4건)
HOT_ORDERS = [  # 주문번호, 거래처, SKU, 수량, 납기, 오더타입
    ("48810", "C0001", "4471", 10, dt.date(2026, 9, 22), "응급"),
    ("48811", "C0002", "4471", 10, dt.date(2026, 9, 23), "판매"),
    ("48812", "C0004", "4471", 15, dt.date(2026, 9, 23), "판매"),
    ("48820", "C0003", "4471",  5, dt.date(2026, 9, 24), "판매"),   # F1: 4472·4 → 4471·5
    ("48825", "C0007", "4472",  4, dt.date(2026, 9, 24), "판매"),   # F1: 옮겨온 4472 결품
    ("48831", "C0005", "4480",  6, dt.date(2026, 9, 25), "판매"),
]
DONE_ORDERS = [  # 이미 처리된 4471 — 앞선 Lot L-2601 에서 나갔다
    ("48790", "C0006", "4471", 4, dt.date(2026, 9, 21), "피킹중",   "L-2601"),
    ("48781", "C0007", "4471", 2, dt.date(2026, 9, 21), "출고완료", "L-2601"),
]
KPI = [  # 순번, 코드, 이름, 목표표기, 실적, 전주, 달성률, 판정, 알림, 소수 자릿수
    (1, "KPI-01", "정시출고율 (%)",            "97.0",  94.0,  97.1,  96.9, "미달", "정시출고율 94.0% < 목표 97.0%", 1),
    (2, "KPI-02", "지연주문건수 (건)",         "≤ 15",  29,    14,    51.7, "미달", "지연주문 29건 > 임계 15건", 0),
    (3, "KPI-03", "결품발생건수 (건)",         "≤ 5",   18,    4,     27.8, "미달", "결품발생 18건 > 임계 5건", 0),
    (4, "KPI-04", "피킹생산성 (건/인·일)",     "300",   312,   309,  104.0, "달성", None, 0),
    (5, "KPI-05", "피킹정확도 (%)",            "99.90", 99.93, 99.92, 100.0, "달성", None, 2),
    (6, "KPI-06", "일평균출고처리량 (EA)",     "2,600", 2704,  2651, 104.0, "달성", None, 0),
    (7, "KPI-07", "배송정시율 (%)",            "98.0",  98.4,  98.2, 100.4, "달성", None, 1),
    (8, "KPI-08", "재고실사정확도 (%)",        "100.0", 100.0, 100.0, 100.0, "달성", None, 1),
]

def q(v):
    if v is None: return "NULL"
    if isinstance(v, (int, float)): return str(v)
    if isinstance(v, dt.date): return "'%s'" % v.isoformat()
    return "'" + str(v).replace("'", "''") + "'"

def rows(table, cols, data):
    if not data: return ""
    head = "INSERT INTO %s (%s) VALUES\n" % (table, ", ".join(cols))
    return head + ",\n".join("  (" + ", ".join(q(v) for v in r) + ")" for r in data) + ";\n\n"

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=20260921)
    a = ap.parse_args()
    rnd = random.Random(a.seed)
    out = [f"-- 생성: gen_wms_data.py --seed {a.seed} · 기준 {NOW} (월) 07:26\n"
           "SET client_min_messages TO warning;\nBEGIN;\n\n"]

    # ── 기준정보: 거래처 400 (명명 7 + 393). 상위 10곳이 출고 30%, 페널티 조항 40곳
    cust = list(NAMED)
    regions = ["서울", "경기북부", "경기남부", "인천", "부산", "대구", "대전", "광주", "강원", "충북"]
    for i in range(8, 401):
        cd = "C%04d" % i
        typ = rnd.choices(["병원", "의원", "대리점"], [0.38, 0.42, 0.20])[0]
        top10 = "Y" if i <= 10 else "N"
        pen = 300_000 if i <= 40 and rnd.random() < 0.9 else (150_000 if i <= 40 else 0)
        cust.append((cd, f"{rnd.choice(regions)}{typ}{i:03d}", typ,
                     rnd.choices(["A", "B", "C"], [0.15, 0.45, 0.40])[0],
                     rnd.choice(regions), top10, pen))
    out.append(rows("wms.customer",
                    ["cust_cd", "cust_nm", "cust_type", "grade", "region", "top10_yn", "penalty_krw"], cust))

    # ── 기준정보: 품목 2000 (경합 6 포함) + 대체 60쌍 (경합 중 4471 만 대체 가능)
    cats = ["카테터", "스텐트", "가이드와이어", "시린지", "드레싱", "봉합사", "수술포", "주사침"]
    items, seen = [], set()
    for cd, nm in zip(HOT_SKUS, ["관상동맥 카테터 6Fr", "관상동맥 카테터 7Fr", "약물용출 스텐트 3.0",
                                 "가이드와이어 0.014", "가이드와이어 0.018", "혈관 봉합기구"]):
        items.append((cd, nm, cats[0] if cd.startswith("44") else cats[2], "EA", "Y")); seen.add(cd)
    n = 0
    while len(items) < 2000:
        cd = "%04d" % rnd.randint(1000, 9999)
        if cd in seen: continue
        seen.add(cd); n += 1
        items.append((cd, f"{rnd.choice(cats)} {rnd.randint(1,99)}호", rnd.choice(cats), "EA",
                      "Y" if rnd.random() < 0.72 else "N"))
    out.append(rows("wms.item", ["item_cd", "item_nm", "category", "uom", "import_yn"], items))
    alts = [("4471", "4471-B", "동일 규격 대체품 — 제조사 다름")]
    pool = [i[0] for i in items if i[0] not in HOT_SKUS]
    for s in rnd.sample(pool, 59):
        alts.append((s, s + "-B", "동일 규격 대체품"))
    out.append(rows("wms.item_alt", ["item_cd", "alt_item_cd", "note"], alts))

    # ── 기준정보: 공급사 6 (P-01 이 경합 SKU 전부를 쥔다)
    vend = [("V-P01", "Pacific Medical Devices", "일본", "P-01"),
            ("V-P02", "Nordic Surgical AB",      "스웨덴", "P-02"),
            ("V-P03", "Rhine MedTech GmbH",      "독일", "P-03"),
            ("V-P04", "Lombardy Devices SpA",    "이탈리아", "P-04"),
            ("V-P05", "Catalonia Medica SL",     "스페인", "P-05"),
            ("V-P06", "Kanto Precision Co.",     "일본", "P-06")]
    out.append(rows("wms.vendor", ["vendor_cd", "vendor_nm", "country", "plant_cd"], vend))

    # ── 정산관: 공급사 납기 이력 6사 × 12회. P-01 최근 6회는 고정값(S4 의 두 번째 근거)
    hist = []
    for v, _, _, _ in vend:
        for k in range(12):
            pr = NOW - dt.timedelta(days=14 * (12 - k) + rnd.randint(0, 3))
            d = P01_RECENT_DELAY[k - 6] if (v == "V-P01" and k >= 6) else (
                rnd.choice([0, 0, 0, 1, 2]) if v != "V-P01" else rnd.choice([0, 1, 2, 3]))
            hist.append((v, f"PO-{v[-3:]}{k:02d}", pr, pr + dt.timedelta(days=d), d))
    out.append(rows("wms.vendor_lead_history",
                    ["vendor_cd", "po_no", "promise_dt", "actual_dt", "delay_days"], hist))

    # ── 입고관리: 발주 40 · 입고예정 40 (경합 6 은 전부 P-01, 그중 둘이 통관 검사 지정)
    po, inb = [], []
    for idx, s in enumerate(HOT_SKUS):
        pno = "PO-88121" if s == "4471" else f"PO-881{22+idx}"
        po.append((pno, "V-P01", s, 120 + idx * 10, NOW - dt.timedelta(days=24), dt.date(2026, 9, 24)))
        no = HOT_INB[s]
        inb.append((no, pno, s, 120 + idx * 10, dt.date(2026, 9, 24),
                    CUSTOMS.get(no, "반입 전"), f"CS-{no[3:]}" if no in CUSTOMS else None))
    for k in range(34):
        v = rnd.choice(vend)[0]
        s = rnd.choice(pool)
        pno = f"PO-{88200+k}"
        pdt = NOW - dt.timedelta(days=rnd.randint(10, 40))
        prm = NOW + dt.timedelta(days=rnd.choice([-9, -7, -6, 8, 11, 14, 17, 20]))  # 금주(21~27)는 비운다
        po.append((pno, v, s, rnd.randint(30, 400), pdt, prm))
        inb.append((f"IN-{2700+k}", pno, s, rnd.randint(30, 400), prm,
                    rnd.choice(["반입 전", "반입 전", "수리 완료", "입고 완료"]), None))
    out.append(rows("wms.purchase_order",
                    ["po_no", "vendor_cd", "item_cd", "po_qty", "po_dt", "promise_dt"], po))
    out.append(rows("wms.inbound_plan",
                    ["inb_no", "po_no", "item_cd", "plan_qty", "plan_dt", "status", "customs_no"], inb))

    # ── 재고: Lot 8000. 경합 6 은 부족하고, 4471 은 L-2607 에 딱 20 남았다. 유효기간 6% 는 비운다
    lots = [("L-2607", "4471", 20, dt.date(2028, 3, 31), NOW - dt.timedelta(days=9), "A-01-03"),
            ("L-2601", "4471",  0, dt.date(2027, 11, 30), NOW - dt.timedelta(days=38), "A-01-02")]
    for s in HOT_SKUS[1:]:
        lots.append((f"L-26{rnd.randint(10,59)}{s[-1]}", s, 0, dt.date(2028, 1, 31),
                     NOW - dt.timedelta(days=rnd.randint(20, 60)), "A-02-01"))
    k = 0
    while len(lots) < 8000:
        k += 1
        s = rnd.choice(pool)
        exp = None if rnd.random() < 0.06 else NOW + dt.timedelta(days=rnd.randint(120, 900))
        lots.append((f"L-{30000+k}", s, rnd.randint(1, 240),
                     exp, NOW - dt.timedelta(days=rnd.randint(1, 180)),
                     f"{rnd.choice('ABCD')}-{rnd.randint(1,9):02d}-{rnd.randint(1,9):02d}"))
    out.append("COPY wms.stock_lot (lot_no, item_cd, qty, exp_dt, recv_dt, loc_cd) FROM stdin;\n")
    for lo in lots:
        out.append("\t".join("\\N" if v is None else str(v) for v in lo) + "\n")
    out.append("\\.\n\n")

    # ── 주문: 3영업일 × 150건. 경합 오더가 그 안에 산다
    orders, lines, allocs = [], [], []
    for no, cc, s, qty, due, typ in HOT_ORDERS:
        orders.append((f"#{no}", cc, NOW, due, typ,
                       "Y" if typ == "응급" else "N", "접수"))
        lines.append((f"#{no}", 1, s, qty))
        allocs.append((f"#{no}", 1, s, 0, None, None, "미배정", None, None))
    for no, cc, s, qty, odt, st, lot in DONE_ORDERS:
        orders.append((f"#{no}", cc, NOW - dt.timedelta(days=3), odt, "판매", "N", "처리중"))
        lines.append((f"#{no}", 1, s, qty))
        allocs.append((f"#{no}", 1, s, qty, lot, odt, st, None, None))
    # 오늘(07:26) 접수 83건 = 할당완료 44 + 피킹중 17 + 미배정 22. 고정 오더 6건이 미배정 안에 산다.
    # 앞선 이틀은 나머지를 채운다 — 더미 규모 "3영업일 × 150건" 의 합 450 을 지킨다.
    TODAY_MIX = ["할당완료"] * 44 + ["피킹중"] * 17 + ["미배정"] * (22 - len(HOT_ORDERS))
    rnd.shuffle(TODAY_MIX)
    seq = 0
    urgent = sum(1 for *_, t in HOT_ORDERS if t == '응급')   # 고정 오더의 응급을 먼저 센다
    while len(orders) < 450:
        seq += 1
        no = f"#{49000+seq}"
        cc = rnd.choice(cust)[0]
        today = len(TODAY_MIX) > 0
        odt = NOW if today else NOW - dt.timedelta(days=rnd.choice([3, 4]))
        d = odt + dt.timedelta(days=rnd.randint(0, 2))
        u = "Y" if urgent < 7 and rnd.random() < 0.05 else "N"
        if u == "Y": urgent += 1
        orders.append((no, cc, odt, d, "응급" if u == "Y" else "판매", u, "접수"))
        s = rnd.choice(pool)
        qty = rnd.randint(1, 40)
        lines.append((no, 1, s, qty))
        st = TODAY_MIX.pop() if today else rnd.choices(
            ["출고완료", "할당완료", "피킹중"], [0.72, 0.20, 0.08])[0]
        allocs.append((no, 1, s, qty if st != "미배정" else 0,
                       f"L-{30000+rnd.randint(1,7900)}" if st != "미배정" else None,
                       d if st != "미배정" else None, st, None, None))
    out.append(rows("wms.sales_order",
                    ["ord_no", "cust_cd", "ord_dt", "due_dt", "ord_type", "urgent_yn", "status"], orders))
    out.append(rows("wms.sales_order_line", ["ord_no", "line_no", "item_cd", "ord_qty"], lines))
    out.append(rows("wms.outbound_alloc",
                    ["ord_no", "line_no", "item_cd", "alloc_qty", "lot_no", "out_dt", "status", "chg_by", "chg_at"],
                    allocs))

    # ── 출고 실적 4주 + 지연 사유
    daily = []
    for w in range(3, 0, -1):
        for i, d in enumerate(LAST_WEEK):
            dd = d - dt.timedelta(days=7 * w)
            oc = rnd.randint(78, 118); dl = rnd.randint(1, 4); sh = rnd.randint(0, 2)
            daily.append((dd, oc, oc - dl, dl, sh, rnd.randint(2300, 3100), rnd.randint(30, 50)))
    daily += [(d, o, ot, dl, sh, qy, pc) for d, o, ot, dl, sh, qy, pc in DAILY]
    out.append(rows("wms.outbound_daily",
                    ["out_dt", "ord_cnt", "ontime_cnt", "delay_cnt", "short_cnt", "out_qty", "parcel_cnt"], daily))
    dr, n = [], 0
    for seg, cd, nm, cnt, qty in DELAY_MIX:
        base, rem = divmod(qty, cnt)          # 나머지는 마지막 건에 — 구간 합계가 정의서와 어긋나지 않게
        for k in range(cnt):
            n += 1
            dr.append((f"#{48600+n}", seg, cd, nm, base + (rem if k == cnt - 1 else 0),
                       rnd.choice(LAST_WEEK)))
    out.append(rows("wms.delay_reason", ["ord_no", "seg", "reason_cd", "reason_nm", "qty", "occur_dt"], dr))

    # ── 운송 · 메모 · KPI
    out.append(rows("wms.shipment", ["ship_no", "ord_no", "carrier_cd", "status", "eta_dt"],
                    [("SH-9001", "#48790", "CJ", "배송 중", NOW),
                     ("SH-9002", "#48781", "CJ", "배송 완료", NOW),
                     ("SH-9003", "#49012", "LOTTE", "배송 중", NOW + dt.timedelta(days=1))]))
    out.append(rows("wms.sales_memo", ["cust_cd", "memo_dt", "memo_tx", "author"],
                    [("C0003", NOW - dt.timedelta(days=1), "목요일 수술 예정 — 4471 필수", "영업 김"),
                     ("C0001", NOW - dt.timedelta(days=2), "응급 콜 대응 물량 상시 확보 요청", "영업 박"),
                     ("C0004", NOW - dt.timedelta(days=4), "월요일 정기 배송 유지", "영업 최"),
                     ("C0005", NOW - dt.timedelta(days=3), "시술 일정 변동 가능", "영업 김"),
                     ("C0006", NOW - dt.timedelta(days=6), "분기 계약 갱신 협의 중", "영업 이")]))
    out.append(rows("wms.kpi_weekly",
                    ["seq", "kpi_cd", "kpi_nm", "target_tx", "actual_val", "prev_val", "rate_val", "judge", "alert_tx", "dec_pt"],
                    KPI))
    out.append("COMMIT;\n")
    sys.stdout.write("".join(out))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
