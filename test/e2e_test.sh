#!/bin/bash
# 갱신된 go.sh 를 사본으로 만들어 E2E 재검증
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK=/tmp/go_e2e
rm -rf "$WORK"; mkdir -p "$WORK"
cp "$HERE/go.sh" "$HERE/go.env" "$WORK/"
sed -i 's#^shm_env_file="/dev/shm/.go.env"#shm_env_file="'"$WORK"'/.go.env"#' "$WORK/go.sh"
sed -i 's#</dev/tty#</dev/stdin#g' "$WORK/go.sh"
sed -i 's#^\[ ! -L /bin/go \].*##' "$WORK/go.sh"
bash -n "$WORK/go.sh" || exit 1

show() { sed 's/\x1b\[[0-9;]*m//g' "$1" | grep -aE 'Main Menu|CMDs|이전 메뉴로 이동|이력|메인메뉴로 이동|없는' | head -"${2:-14}"; }

echo "### T1: 메인 → i(relay) → b → 메인  (b 가 실제로 한단계 돌아가야 함)"
printf 'i\nb\nq\n' | (cd "$WORK" && timeout 120 bash go.sh) >"$WORK/t1.txt" 2>&1
show "$WORK/t1.txt" 10

echo
echo "### T2: 메인 → i(relay) → 1(han CMD목록) → 0 → 서브메뉴목록 → 0 → 메인"
printf 'i\n1\n0\n0\n0\n' | (cd "$WORK" && timeout 280 bash go.sh) >"$WORK/t2.txt" 2>&1
show "$WORK/t2.txt" 12

echo
echo "### T3: 메인 → i → b → bb(없는 이력) → q"
printf 'i\nb\nbb\nq\n' | (cd "$WORK" && timeout 120 bash go.sh) >"$WORK/t3.txt" 2>&1
show "$WORK/t3.txt" 10
