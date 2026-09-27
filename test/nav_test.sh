#!/bin/bash
# ===========================================================================
#  go.sh 메뉴 이동(navigation) 회귀 테스트
#  - 실제 go.sh 에서 nav_* 블록을 그대로 추출해 테스트
#  - menufunc 스텁은 호출 인자를 "sub|title|init" 로 기록 (인자없으면 "||")
# ===========================================================================
cd "$(dirname "$0")/.." || exit 1
GOF=go.sh
[ -f "$GOF" ] || { echo "go.sh 없음"; exit 1; }

awk '/^# 메뉴 이동 이력 스택 \(navigation stack\)/{f=1} f&&/^# 함수 이름: sub_to_scut/{f=0} f' "$GOF" > /tmp/_nav_block.sh
[ -s /tmp/_nav_block.sh ] || { echo "FAIL: nav 블록 추출 실패"; exit 1; }

PASS=0
FAIL=0
menufunc() { CALLS+=("${1}|${2}|${3}"); }
savescut() { :; }
notscutrelay() { echo "$1"; }   # relay 아님 → init 로 scut 전달
scuttitle() { echo "TITLEOF[$1]"; }
# 실제 단축키로 간주되는 scut 만 st() 로 조회 성공시킨다
st() {
    case "$1" in
        p | d | l | n | i | han | flow_linux_basic | xscut) return 0 ;;
        *) return 1 ;;
    esac
}
ok() { PASS=$((PASS + 1)); printf "  ok   %s\n" "$1"; }
ng() { FAIL=$((FAIL + 1)); printf "  FAIL %s\n" "$1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (기대:[$2] 실제:[$3])"; fi; }
reset() { CALLS=(); nav_reset; }

. /tmp/_nav_block.sh

echo "== 1) 스택 저장/조회 =="
reset
nav_sync "" ""                                  # menufunc (메인)
nav_sync "" "시스템 정보 / 프로세스 관리 [p]"      # 메인 -> p
chk "p 진입시 메인 저장" "m|||" "$(nav_peek)"
nav_sync "" "서버 데몬 관리 [d]"                  # p -> d
chk "d 진입시 p 저장"  "p||시스템 정보 / 프로세스 관리 [p]|" "$(nav_peek)"
nav_sync "{submenu_com}" "file explorer [ex]"     # d -> ex
chk "ex 진입시 d 저장" "d||서버 데몬 관리 [d]|"  "$(nav_peek)"

echo "== 2) b 연속 입력 왕복(헛돌이) 없음 =="
reset
nav_sync "" ""
nav_sync "" "시스템 정보 [p]"
nav_sync "" "서버 데몬 관리 [d]"
nav_back 1; chk "1회 뒤로가기 → p" "|시스템 정보 [p]|p" "${CALLS[0]}"
nav_back 1; chk "2회 뒤로가기 → m (왕복 아님)" "||"  "${CALLS[1]}"
nav_back 1; chk "이력 없음 → 메인메뉴"         "||"   "${CALLS[2]}"

echo "== 3) relay(포인터) 경유 후 b =="
reset
nav_sync "" ""                                              # 메인
nav_sync "{submenu_sys}" "시스템 초기설정과 기타 [i]"        # i(relay) → {submenu_sys} 목록화면
chk "relay 진입시 메인 저장" "m|||"                        "$(nav_peek)"
nav_cmdlist "한글화 / 타임존 [han]" "{submenu_sys}"          # 목록 → han CMD 화면
chk "CMD 진입시 목록화면(i) 저장" "i|{submenu_sys}|시스템 초기설정과 기타 [i]|" "$(nav_peek)"
nav_back 1
chk "b → 서브메뉴 목록 복귀" "{submenu_sys}|시스템 초기설정과 기타 [i]|i" "${CALLS[0]}"
nav_back 1
chk "또 b → 메인"          "||"                          "${CALLS[1]}"

echo "== 4) bb / bbb =="
reset
nav_sync "" ""
nav_sync "" "P [p]"
nav_sync "" "D [d]"
nav_sync "" "L [l]"
nav_sync "" "N [n]"
nav_back 2; chk "N 에서 2단계 뒤 → D" "|D [d]|d" "${CALLS[0]}"
nav_back 3; chk "이력 소진 → 메인"    "||"      "${CALLS[1]}"

echo "== 5) 같은 화면 재진입은 이력 미적립 =="
reset
nav_sync "" ""
nav_sync "" "P [p]"
i=0; while [ $i -lt 3 ]; do nav_sync "" "P [p]"; i=$((i+1)); done
chk "동일화면 반복 진입시 이력 1건" "1" "${#NAVSTACK[@]}"

echo "== 6) m(메인메뉴) 이동은 이력 보존 =="
reset
nav_sync "" ""
nav_sync "" "D [d]"
nav_main
chk "m 이동시 D 이력 보존" "d||D [d]|" "$(nav_peek)"
chk "메인 호출(빈 인자)"  "||"        "${CALLS[0]}"

echo "== 7) bash2 안전 (빈 배열 음수 인덱스 금지) =="
reset
nav_peek >/dev/null 2>&1;  chk "빈 스택 peek 실패코드"  "1" "$?"
nav_save "" "" "" >/dev/null 2>&1; chk "빈 scut 저장 거부" "1" "$?"
nav_goto "" "" "" >/dev/null 2>&1; chk "빈 화면 goto → 스택 0건" "0" "${#NAVSTACK[@]}"

echo "== 8) 이력 상한 =="
reset
nav_sync "" ""
i=0
while [ $i -lt 70 ]; do nav_goto "x$i" "" "X$i"; i=$((i + 1)); done
if [ "${#NAVSTACK[@]}" -le "$NAV_MAX" ]; then ok "이력 상한 준수 (${#NAVSTACK[@]}<=$NAV_MAX)"; else ng "이력 상한 초과 (${#NAVSTACK[@]})"; fi

echo "== 9) flow 자동복귀 판정 =="
reset
nav_sync "" ""
nav_sync "" "Linux 기본 명령어 [flow_linux_basic]"
nav_sync "{submenu_com}" "file explorer [ex]"
if nav_peek | grep -q '^flow_'; then ok "flow 상위메뉴 판별 동작"; else ng "flow 상위메뉴 판별 실패: $(nav_peek)"; fi

echo "== 10) 1줄(relay) 메뉴 자동 복귀 경로 =="
reset
nav_sync "" ""                                   # 메인
nav_sync "" "flow_linux_basic flow [flow_linux_basic]"
nav_sync "{submenu_hidden}" "단일 명령 [one]"
nav_back 1
chk "1줄메뉴 → flow 상위" "|flow_linux_basic flow [flow_linux_basic]|flow_linux_basic" "${CALLS[0]}"

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
