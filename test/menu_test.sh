#!/bin/bash
# ===========================================================================
#  218개 메뉴 전수 파싱 점검 (go.sh 의 print_menulist + listof_comm 동일 규약 재현)
#    - 본문이 없는 메뉴 : 진입하면 "error : num_commands -> 0" 화면이 뜬다
#    - 1줄짜리 메뉴     : relay(포인터) 메뉴 → 자동 하위메뉴로 내려간다
# ===========================================================================
cd "$(dirname "$0")/.." || exit 1
ENVF=go.env
[ -f "$ENVF" ] || exit 1

total=0; empty=0; relay=0
> /tmp/_empty_menus.txt
> /tmp/_relay_menus.txt

while IFS= read -r hdr; do
    total=$((total + 1))
    # print_menulist 와 동일하게 태그/제목 분리
    sub=$(echo "$hdr" | sed -n 's/^%%% \({submenu_[a-z_]*\}\).*/\1/p')
    if [ -n "$sub" ]; then
        title=$(echo "$hdr" | awk -F'}' '{print $2}')   # go.sh: awk -F'}' '{print $2}'
    else
        title=$(echo "$hdr" | sed -r 's/^%%% //')      # go.sh: sed -r 's/%%% //'
    fi
    body=$(awk -v t="%%% ${sub}${title}" 'BEGIN { gsub(/[][().*+?^$\\|]/, "\\\\&", t) } !f && $0 ~ t { f=1; next } /^$/ { f=0 } f' "$ENVF")
    # 한글환경 런타임과 동일하게 %%%e 줄은 제거된다
    body=$(echo "$body" | grep -v '^%%%e ')
    cmds=$(echo "$body" | grep -v "^%% " | grep -c .)
    if [ "$cmds" -eq 0 ]; then
        empty=$((empty + 1))
        echo "  EMPTY : $hdr" >> /tmp/_empty_menus.txt
    elif [ "$cmds" -eq 1 ]; then
        relay=$((relay + 1))
        echo "  RELAY : $hdr  ->  $(echo "$body" | grep -v '^%% ' | head -1)" >> /tmp/_relay_menus.txt
    fi
done < <(grep -E '^%%% ' "$ENVF")

echo "메뉴 총 $total 개 / 본문없음 $empty 개 / 1줄(relay) $relay 개"
echo
echo "--- 본문이 비어있는 메뉴(진입시 error 화면) ---"
if [ -s /tmp/_empty_menus.txt ]; then cat /tmp/_empty_menus.txt; else echo "  없음"; fi
echo
echo "--- 1줄짜리(relay/포인터) 메뉴 : 자동 하위메뉴로 내려감 ---"
if [ -s /tmp/_relay_menus.txt ]; then cat /tmp/_relay_menus.txt; else echo "  없음"; fi
