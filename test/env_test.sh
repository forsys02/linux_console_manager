#!/bin/bash
# ===========================================================================
#  go.env 메뉴 데이터 정합성 감사 (정적 점검)
#   go.sh 는 런타임에 한글환경이면 `%%%e` 줄을 삭제하므로 KR 기준으로만 검사한다
# ===========================================================================
cd "$(dirname "$0")/.." || exit 1
GOF=go.sh
ENVF=go.env
[ -f "$GOF" ] && [ -f "$ENVF" ] || { echo "파일 없음"; exit 1; }

PASS=0; FAIL=0; WARN=0
ok() { PASS=$((PASS + 1)); printf "  ok   %s\n" "$1"; }
ng() { FAIL=$((FAIL + 1)); printf "  FAIL %s\n" "$1"; }
wr() { WARN=$((WARN + 1)); printf "  warn %s\n" "$1"; }

grep -E '^%%% ' "$ENVF" > /tmp/_kr_head.txt
sed -n 's/.*\[\([^]]\+\)\].*/\1/p' /tmp/_kr_head.txt | sort -u > /tmp/_scuts.txt
grep -E '^[a-zA-Z_][a-zA-Z0-9_]*\(\) *\{' "$GOF" | sed -n 's/^\([a-zA-Z_][a-zA-Z0-9_]*\)().*/\1/p' > /tmp/_funcs.txt
grep -E 'for \(\(i = 1; i <= 10; i\+\+\)\)' "$GOF" | sed -n 's/.*eval "\([a-zA-Z0-9_]*\).*/\1/p' >> /tmp/_funcs.txt
sort -u /tmp/_funcs.txt -o /tmp/_funcs.txt
echo "     메뉴 $(wc -l < /tmp/_kr_head.txt)개 / 단축키 $(wc -l < /tmp/_scuts.txt)개 / 함수 $(wc -l < /tmp/_funcs.txt)개"

echo "== 1) 중복 단축키 =="
dups=$(sort /tmp/_scuts.txt | uniq -d)
[ -z "$dups" ] && ok "중복 단축키 없음" || { for d in $dups; do ng "중복 단축키 [$d]"; done; }

echo "== 2) {submenu_*} 태그 정합성 =="
sed -n 's/^%%% \({submenu_[a-z_]*}\).*/\1/p' /tmp/_kr_head.txt | sort -u > /tmp/_tags_head.txt
sed -n 's/^\({submenu_[a-z_]*}\)$/\1/p' "$ENVF" | sort -u > /tmp/_tags_body.txt
ob=$(comm -13 /tmp/_tags_head.txt /tmp/_tags_body.txt)
oh=$(comm -23 /tmp/_tags_head.txt /tmp/_tags_body.txt)
[ -z "$ob" ] && ok "본문 태그에 대응 헤더 없음" || ng "본문 전용 태그: $(echo $ob)"
[ -z "$oh" ] && ok "헤더 태그 모두 본문 태그 보유" || wr "헤더만 존재(직접 선택형): $(echo $oh)"

echo "== 3) relay 본문 태그 유효성 =="
badrelay=$(sed -n 's/^\({submenu_[a-z_]*}\)$/\1/p' "$ENVF" | sort -u | while read -r t; do
    grep -q "^%%% $t" /tmp/_kr_head.txt || echo "$t"
done | tr '\n' ' ')
[ -z "$badrelay" ] && ok "relay 본문 태그 모두 실제 메뉴" || ng "헤더 없는 태그: $badrelay"

echo "== 4) 제목 내 | (스택 구분자) 충돌 =="
if grep -E '^%%% .*\[.+\].*\|' /tmp/_kr_head.txt >/dev/null; then
    grep -nE '^%%% .*\[.+\].*\|' /tmp/_kr_head.txt | sed 's/^/       /'; ng "제목에 | 포함"
else ok "제목에 | 없음"; fi

echo "== 5) 선택목록(varS__/varOPT__/varSetXxx__) 항목 존재 확인 =="
# varS__a__b  형태 → a, b 가 실제 함수/메뉴/명령 이어야 함
awk 'match($0, /var[A-Za-z0-9]+__[A-Za-z0-9@_.-]+/) {
    s = substr($0, RSTART, RLENGTH)
    n = split(s, p, "__")
    for (i = 2; i <= n; i++) print p[i]
}' "$ENVF" | sed 's/@[a-z0-9.]*$//' | sort -u > /tmp/_sel.txt
selmiss=$(while read -r s; do
    [ -z "$s" ] && continue
    grep -qx "$s" /tmp/_funcs.txt && continue
    grep -qx "$s" /tmp/_scuts.txt && continue
    command -v "$s" >/dev/null 2>&1 && continue
    echo "$s"
done < /tmp/_sel.txt | tr '\n' ' ')
if [ -z "$selmiss" ]; then ok "선택목록 항목 모두 존재"; else wr "환경에 없어 실행불가 항목(설치형 명령 포함): $(echo $selmiss)"; fi

echo "== 6) flow 메뉴 간 이동(다음/이전) 대상 존재 =="
fl=$(grep -oE 'flow_[a-z_]+' "$ENVF" | sort -u)
flmiss=$(echo "$fl" | while read -r f; do grep -q "\[$f\]" /tmp/_kr_head.txt || echo "$f"; done | tr '\n' ' ')
[ -z "$flmiss" ] && ok "모든 flow_* 참조가 실제 메뉴" || ng "없는 flow 메뉴 참조: $flmiss"

echo "== 7) [scut] 없는 메뉴 (단축키 도달 불가) =="
noscut=$(grep -vE '\[[^]]+\]' /tmp/_kr_head.txt)
if [ -z "$noscut" ]; then ok "모든 메뉴에 단축키 존재"; else
    echo "$noscut" | sed 's/^/       /'
    wr "단축키가 없는 메뉴 (숫자선택으로는 접근 가능)"
fi

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL WARN=$WARN"
[ "$FAIL" -eq 0 ] || exit 1
