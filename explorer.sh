#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
#  explorer.sh — 콘솔 파일 탐색기 (TUI)
#
#  · 탐색 : 폴더 하강/상승, 경로 스택(되돌리기), 위치 기억
#  · 보기 : 이름순/시간순/크기순 정렬 · 숨김 토글 · 심볼릭 링크 표시 · 이름 검색
#  · 작업 : 복사 · 이동 · 삭제 · 이름변경 · 새폴더 · 새파일 · 편집 · 보기 · 하위검색
#  · 안전 : 모든 경로 인용 + `--` · 삭제는 절대경로를 다시 찍고 확인 · 실패해도 목록 유지
#
#  화면 하단 `?` 키에 전체 조작법이 나온다.
# ═══════════════════════════════════════════════════════════════════════
clear

# ── 표시 상수 ──────────────────────────────────────────────────────────
_C_RESET="\033[0;m"
_C_DIR="\033[36m"          # 폴더
_C_LINK="\033[35m"         # 심볼릭 링크
_C_EXEC="\033[1;32m"       # 실행 파일
_C_FILE="\033[0;m"         # 일반 파일
_C_DIM="\033[2m"
_C_SEL="\033[7;40m"        # 선택(반전)
_C_OK="\033[1;32m"
_C_WARN="\033[1;33m"
_C_ERR="\033[1;31m"
_C_HEAD="\033[1;37m"
_ESC_N='\n'                # 표시용 기호 : 단일따옴표 = 역슬래시+문자 (2바이트)
_ESC_T='\t'
_ESC_R='\r'

# ── 화면 높이 구성요소 ────────────────────────────────────────────────
#   한 프레임 = 아래를 이 순서로 각 1줄씩 출력한다.
#   _clear_frame 는 "프레임 줄수" 만큼 커서를 올린다.
#   여기 값이 틀리면 redraw 마다 화면이 깨진다. 항을 바꾸면 같이 고칠 것.
_UI_TOPBAR=1               # ==== [p/n] ====
_UI_STATUS=2               # 상태줄 2줄
_UI_CANCEL=1               #   0. Cancel
_UI_BOTBAR=1               # ==== [p/n] ====
_UI_SELECT=1               # >>> Select:
_UI_FRAME=$(( _UI_TOPBAR + _UI_STATUS + _UI_CANCEL + _UI_BOTBAR + _UI_SELECT ))
_UI_RESERVED=$(( _UI_FRAME + 1 ))   # +1 = 하단 여백(커서가 끝에 닿으면 스크롤됨)

# ── 전역 상태 ─────────────────────────────────────────────────────────
_CWD=''
_items=()          # 표시용 이름 (폴더는 '/' 접미)
_types=()          # find %y  (d/f/l/b/c/s/p)
_modes=()          # find %M  (권한 문자열)
_SEL_PATH=''
_SEL_KIND=''
_ndir=0; _nfile=0
_pages=1; _page=0; _sel=0
_SORT=name         # name | mtime | size
_HIDDEN=0          # 0=숨김 감춤 1=보임
_SORTZ=0
_REDRAW_ALL=0      # 1 이면 부분 갱신 대신 화면 전체 재도画
_MSGWAIT=1.1
_LASTPAT=''
_STAT_TMP=''
_HELP=''
_BAR=''
_page_size=10; _w_item=40; _w_path=40; _w_sel=40

# ═══════════════════════════════════════════════════════════════════════
#  표시 헬퍼
# ═══════════════════════════════════════════════════════════════════════

#  _fit "문자열" 최대폭  →  전역 REPLY
#    개행/탭/CR 을 눈에 보이는 기호로 바꾼 뒤 문자 단위로 자른다.
#    REPLY 를 쓰는 이유 : $( ) 명령치환은 이름 끝의 개행을 삼켜버린다.
_fit() {
    local s=$1 n=$2
    s=${s//$'\n'/$_ESC_N}
    s=${s//$'\t'/$_ESC_T}
    s=${s//$'\r'/$_ESC_R}
    if [ -n "$n" ] && [ "$n" -ge 2 ] 2>/dev/null && [ "${#s}" -gt "$n" ]; then
        s=${s:0:$(( n - 1 ))}…
    fi
    REPLY=$s
}

#  _hsize 바이트  →  전역 REPLY (12 / 1.2K / 1.5M / 3.4G …)
_hsize() {
    local b=$1 v f=0 u=0 d s
    case $b in ''|*[!0-9]*) REPLY='?'; return 0 ;; esac
    if [ "$b" -lt 1024 ]; then REPLY="$b B"; return 0; fi
    v=$b
    while [ $v -ge 1024 ] && [ $u -lt 3 ]; do f=$(( v % 1024 )); v=$(( v / 1024 )); u=$(( u + 1 )); done
    d=$(( f * 10 / 1024 ))
    case $u in 1) s=K;; 2) s=M;; *) s=G;; esac
    REPLY="$v.$d$s"
}

#  _join "디렉터리" "이름"  →  전역 REPLY (루트 처리 포함)
_join() {
    if [ "$1" = / ]; then REPLY="/$2"; else REPLY="$1/$2"; fi
}

#  _barw 길이  →  전역 REPLY
_barw() {
    local n=$1 i s=''
    for (( i=0; i<n; i++ )); do s+='='; done
    REPLY=$s
}

_full() { printf '\033[H\033[2J\033[3J'; }

# ═══════════════════════════════════════════════════════════════════════
#  터미널 크기 / NUL 정렬
# ═══════════════════════════════════════════════════════════════════════
_term_init() {
    local th tw
    th=$(tput lines 2>/dev/null) || th=24
    tw=$(tput cols  2>/dev/null) || tw=80
    case $th in ''|*[!0-9]*) th=24 ;; esac
    case $tw in ''|*[!0-9]*) tw=80 ;; esac
    [ "$tw" -lt 60 ] && tw=80
    termwidth=$tw; termheight=$th

    _page_size=$(( th - _UI_RESERVED ))
    [ $_page_size -gt 20 ] && _page_size=20
    [ $_page_size -lt 3 ]  && _page_size=3
    # 상태줄1 여백 : "경로 "4 + "  "2 + "[이름순] "9 + " "1 + "[숨김 OFF] "12 + "  "2 + "폴더 N · 파일 M"16 = 46
    _w_path=$(( tw - 48 ))
    # 상태줄2 여백 : "선택  "4 + "  · 종류 · 크기 · 시각"28 = 32
    _w_sel=$(( tw - 34 ))
    _w_item=$(( tw - 6 ))
    [ $_w_path -lt 16 ] && _w_path=16
    [ $_w_sel  -lt 16 ] && _w_sel=16
    [ $_w_item -lt 16 ] && _w_item=16
    _barw $(( tw < 46 ? tw - 4 : 41 )); _BAR=$REPLY

    _HELP='이동 ▲▼ ←→ | Enter 들어가기·작업메뉴 | s 작업메뉴 | d 삭제 | o 정렬 | H 숨김 | / 검색 | D 폴더만들기 | t 파일만들기 | f 하위검색 | i 정보 | ? 도움말 | q 종료'
    _fit "$_HELP" "$tw"; _HELP=$REPLY
}
_term_restore() { stty sane 2>/dev/null; }

_detect_sortz() {
    _SORTZ=0
    printf '' | sort -z -d >/dev/null 2>&1 && _SORTZ=1
}
_zsort()  { if [ "$_SORTZ" = 1 ]; then sort -z -d
            else tr '\0' '\n' | sort -d  | tr '\n' '\0'; fi; }
_zsortn() { if [ "$_SORTZ" = 1 ]; then sort -z -rn
            else tr '\0' '\n' | sort -rn | tr '\n' '\0'; fi; }
_f() { find "$@" 2>/dev/null; }

# ═══════════════════════════════════════════════════════════════════════
#  목록 수집 : find 1회 + sort 1회
#    기록 형식 '<정렬키> <타입> <권한> <이름>'
#    정렬키·타입·권한에 공백이 없어 안전하므로 공백/탭/개행 든 파일명도
#    NUL 로 통째 보존된다.
# ═══════════════════════════════════════════════════════════════════════
_collect() {
    local line nm t md i fmt sfn
    local -a hx=() raw=() rtype=() rmode=()
    local -a ditems=() dtypes=() dmodes=()
    local -a fitems=() ftypes=() fmodes=()

    [ "$_HIDDEN" = 1 ] || hx=( ! -name '.*' )
    case $_SORT in
        mtime) fmt='%T@ %y %M %f'; sfn=_zsortn ;;
        size)  fmt='%s %y %M %f';  sfn=_zsortn ;;
        *)     fmt='x %y %M %f';   sfn=_zsort  ;;
    esac

    while IFS= read -r -d '' line; do
        nm=${line#* }                 # 정렬키 제거
        t=${nm%% *}; nm=${nm#* }      # 타입
        md=${nm%% *}; nm=${nm#* }     # 권한
        if [ "$t" = d ]; then raw+=( "$nm/" ); else raw+=( "$nm" ); fi
        rtype+=( "$t" ); rmode+=( "$md" )
    done < <( _f "$_CWD" -mindepth 1 -maxdepth 1 "${hx[@]}" -printf "$fmt\0" | $sfn )

    for (( i=0; i<${#raw[@]}; i++ )); do
        if [ "${rtype[i]}" = d ]; then
            ditems+=( "${raw[i]}" ); dtypes+=( "${rtype[i]}" ); dmodes+=( "${rmode[i]}" )
        else
            fitems+=( "${raw[i]}" ); ftypes+=( "${rtype[i]}" ); fmodes+=( "${rmode[i]}" )
        fi
    done

    _items=( "../" "${ditems[@]}" "${fitems[@]}" )
    _types=( d  "${dtypes[@]}"  "${ftypes[@]}"  )
    _modes=( d  "${dmodes[@]}"  "${fmodes[@]}"  )
    _ndir=${#ditems[@]}
    _nfile=${#fitems[@]}
}

# ═══════════════════════════════════════════════════════════════════════
#  키 / 한 줄 입력
# ═══════════════════════════════════════════════════════════════════════
_key() {
    _KEY=''; _SEQ=''
    IFS= read -r -sn1 _KEY < /dev/tty || return 1
    if [ "$_KEY" = $'\x1b' ]; then
        read -n2 -t1 _SEQ < /dev/tty
        case $_SEQ in
            '[A'|'OA') _KEY=UP   ;;
            '[B'|'OB') _KEY=DOWN ;;
            '[C'|'OC') _KEY=NEXT ;;
            '[D'|'OD') _KEY=PREV ;;
            '[H'|'OH'|'[1~') _KEY=HOME ;;
            '[F'|'OF'|'[4~') _KEY=END  ;;
            '[5~') _KEY=PREV ;;
            '[6~') _KEY=NEXT ;;
            '[3~') _KEY=DELK  ;;
            *) _KEY=ESC ;;
        esac
    fi
    return 0
}

_prompt() {           # _prompt "안내" "기본값"  →  전역 _ANSWER
    _ANSWER=''
    _REDRAW_ALL=1
    printf '%s' "$1"
    IFS= read -r _ANSWER < /dev/tty || { printf '\n'; return 1; }
    [ -z "$_ANSWER" ] && _ANSWER=$2
    return 0
}

_confirm() {          # _confirm "질문"  →  0=yes 1=no
    local a
    _REDRAW_ALL=1
    while :; do
        printf '  %s  [y/N]: ' "$1"
        IFS= read -r a < /dev/tty || { printf '\n'; return 1; }
        case $a in
            y|Y|yes|Yes|YES|예|ㅇ) return 0 ;;
            n|N|no|No|NO|아니오|ㄴ) return 1 ;;
            '') return 1 ;;
            *) printf '    y 또는 n 을 입력하세요\n' ;;
        esac
    done
}

_pause() {
    _REDRAW_ALL=1
    printf '\n   Enter 키를 누르면 돌아갑니다…'
    IFS= read -r _x < /dev/tty
}

_msg() {              # _msg ok|warn|err|plain "문장"
    local kind=$1; shift
    case $kind in
        ok)    printf '\n  %s✔ %s%s\n' "$_C_OK"   "$*" "$_C_RESET" ;;
        warn)  printf '\n  %s▲ %s%s\n' "$_C_WARN" "$*" "$_C_RESET" ;;
        err)   printf '\n  %s✘ %s%s\n' "$_C_ERR"  "$*" "$_C_RESET" ;;
        plain) printf '\n    %s\n' "$*" ;;
    esac
    _REDRAW_ALL=1
    sleep "$_MSGWAIT"
}

# ═══════════════════════════════════════════════════════════════════════
#  경로 처리
# ═══════════════════════════════════════════════════════════════════════
#  _abs "입력" "기준 디렉터리"  →  전역 _ABS
#     ~ 확장 · 상대경로 · 심볼릭 링크/.. 해석(cd -P) · 존재 확인 겸용
_abs() {
    local in=$1 base=$2 t
    [ -z "$in" ] && return 1
    case $in in
        '~')   t=$HOME ;;
        '~/'*) t=$HOME/${in#\~/} ;;
        *)     t=$in ;;
    esac
    case $t in /*) ;; *) t=$base/$t ;; esac
    _ABS=$( cd -P -- "$t" 2>/dev/null && pwd ) || { _ABS=''; return 1; }
    return 0
}

_sel_resolve() {      # → 전역 _SEL_PATH / _SEL_KIND (cancel|parent|d|f|l|…)
    local n=${#_items[@]} i=$_sel nm
    _SEL_PATH=''; _SEL_KIND=''
    if [ "$i" -ge "$n" ]; then _SEL_KIND=cancel; return 1; fi
    if [ "$i" -eq 0 ]; then _SEL_KIND=parent; return 2; fi
    nm=${_items[i]}; _SEL_KIND=${_types[i]}
    [ "$nm" = */ ] && nm=${nm%/}
    _join "$_CWD" "$nm"; _SEL_PATH=$REPLY
    return 0
}

#  선택이 실제 대상(폴더/파일)이면 0
_sel_is_target() {
    _sel_resolve
    case $_SEL_KIND in cancel|parent|'') return 1 ;; esac
    return 0
}

_check_name() {
    case $1 in
        '')   _msg err '이름을 입력하세요.'; return 1 ;;
        */*)  _msg err '이름에 / 를 쓸 수 없습니다.'; return 1 ;;
        .|..) _msg err "'$1' 은 사용할 수 없습니다."; return 1 ;;
        -*)   _msg err '- 로 시작하는 이름은 사용할 수 없습니다.'; return 1 ;;
    esac
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
#  그리기
# ═══════════════════════════════════════════════════════════════════════
_calc_pages() {
    _pages=$(( ${#_items[@]} / _page_size + 1 ))
    [ $_pages -lt 1 ] && _pages=1
    [ $_page -ge $_pages ] && _page=$(( _pages - 1 ))
    [ $_page -lt 0 ] && _page=0
    [ $_sel -ge ${#_items[@]} ] && _sel=${#_items[@]}
    [ $_sel -lt 0 ] && _sel=0
}

#  목록 1줄 : REPLY=표시문자열  REPLY2=색
_row_text() {
    local i=$1 nm t md c
    if [ "$i" -eq 0 ]; then
        nm='../'; t=d; md='drwxr-xr-x'; c=$_C_DIR
    else
        nm=${_items[i]}; t=${_types[i]}; md=${_modes[i]}
        [ "$t" = l ] && nm="$nm@"
        if   [ "$t" = d ]; then c=$_C_DIR
        elif [ "$t" = l ]; then c=$_C_LINK
        elif [ "$t" = f ]; then
            case $md in *x*) c=$_C_EXEC ;; *) c=$_C_FILE ;; esac
        else c=$_C_DIM
        fi
    fi
    _fit "$nm" "$_w_item"
    REPLY2=$c
}

_status1() {
    local sn
    case $_SORT in mtime) sn='시간순' ;; size) sn='크기순' ;; *) sn='이름순' ;; esac
    _fit "$_CWD" "$_w_path"
    printf '%s경로%s %s  %s[%s]%s %s[숨김 %s]%s  %s폴더 %s · 파일 %s%s\n' \
        "$_C_DIM" "$_C_RESET" "$REPLY" \
        "$_C_DIM" "$sn" "$_C_RESET" \
        "$_C_DIM" "$([ "$_HIDDEN" = 1 ] && echo ON || echo OFF)" "$_C_RESET" \
        "$_C_DIM" "$_ndir" "$_nfile" "$_C_RESET"
}

_status2() {
    local kindname sz mt
    _sel_resolve
    if [ "$_SEL_KIND" = cancel ]; then
        printf '%s선택%s  %s0. Cancel — 이 자리에서 종료%s\n' "$_C_DIM" "$_C_RESET" "$_C_SEL" "$_C_RESET"; return
    fi
    if [ "$_SEL_KIND" = parent ]; then
        printf '%s선택%s  %s../   ← 상위 폴더%s\n' "$_C_DIM" "$_C_RESET" "$_C_DIM" "$_C_RESET"; return
    fi
    case $_SEL_KIND in
        d) kindname='폴더' ;; l) kindname='링크' ;; f) kindname='파일' ;; *) kindname='특수' ;;
    esac
    sz='?'; mt='?'
    if stat -c '%s|%y' -- "$_SEL_PATH" >"$_STAT_TMP" 2>/dev/null; then
        IFS='|' read -r sz mt < "$_STAT_TMP"
        mt=${mt#* }; mt=${mt:5:5} ${mt:11:5}
        _hsize "$sz"; sz=$REPLY
    fi
    _fit "$_SEL_PATH" "$_w_sel"
    printf '%s선택%s  %s  %s· %s · %s · %s%s\n' \
        "$_C_DIM" "$_C_RESET" "$REPLY" "$_C_DIM" "$kindname" "$sz" "$mt" "$_C_RESET"
}

_draw() {
    local i lab
    _calc_pages
    printf '%s %b[%d/%d]%b\n' "$_BAR" "$_C_HEAD" $(( _page + 1 )) "$_pages" "$_C_RESET"
    _status1
    _status2
    for (( i=_page * _page_size; i < _page * _page_size + _page_size; i++ )); do
        lab="$(( i + 1 ))."
        _row_text "$i"
        if [ "$i" -eq "$_sel" ]; then
            printf '%-4s %b%s%b\n' "$lab" "$_C_SEL" "$REPLY" "$_C_RESET"
        else
            printf '%-4s %b%s%b\n' "$lab" "$REPLY2" "$REPLY" "$_C_RESET"
        fi
    done
    if [ "$_sel" -eq "${#_items[@]}" ]; then
        printf '%-4s %bCancel%b\n' "0." "$_C_SEL" "$_C_RESET"
    else
        printf '%-4s Cancel\n' "0."
    fi
    printf '%s %b[%d/%d]%b\n' "$_BAR" "$_C_HEAD" $(( _page + 1 )) "$_pages" "$_C_RESET"
    printf '>>> %s\n' "$_HELP"
}

_clear_frame() {
    printf '\033[%dA' $(( _page_size + _UI_FRAME ))
    printf '\033[J'
}

# ═══════════════════════════════════════════════════════════════════════
#  도움말
# ═══════════════════════════════════════════════════════════════════════
_help() {
    _REDRAW_ALL=1
    clear
    cat <<'EOH'
  ┌──────────────────────────────────────────────────────────────────┐
  │                 파일 탐색기 — 조작법                             │
  └──────────────────────────────────────────────────────────────────┘

   ▲▼ / j k       한 칸 위·아래           Home End   맨 위 / 맨 아래
   ←→ / h l       이전·다음 페이지        PgUp PgDn  ditto
   g / G          맨 위 / 맨 아래        BackSpace  상위 폴더

   Enter          폴더면 들어가기 · 파일이면 작업 메뉴
   s              선택 항목 작업 메뉴 (폴더·파일 공통)
   d              선택 항목 삭제 (확인)

   c  복사         m  이동          r  이름 변경     i  정보
   e  vi 편집      n  nano 편집     v  less 로 보기   b  batcat 로 보기
   f  하위 검색    p  경로 클립보드

   D  새 폴더 만들기     t  새 파일 만들기     R  새로 고침
   o  정렬 전환(이명·시간·크기)              H  숨김 파일 토글
   /  이름 검색           N  다음 일치 찾기

   ?  이 도움말           q  또는  0  종료

  ── 표시 규칙 ───────────────────────────────────────────────────────
    폴더/            링크@            실행 파일은 초록색
    개행·탭이 든 이름은 \n \t 로 바꿔 한 줄로 보여준다
      → 목록 줄수가 흔들리지 않아 화면이 깨지지 않는다
    너무 긴 이름은 … 로 잘라 화면 밖으로 새지 않게 한다
    폴더는 항상 파일보다 먼저, 그 안에서 정렬 순서를 지킨다
    상태줄 2번째 줄에서 이름·종류·크기·수정시각을 바로 볼 수 있다
EOH
    _pause
}

# ═══════════════════════════════════════════════════════════════════════
#  복사 / 이동
# ═══════════════════════════════════════════════════════════════════════
_do_copy_move() {
    local src=$1 mode=$2 label dst target base rc cnt
    if [ "$mode" = copy ]; then label='복사'; else label='이동'; fi
    base=${src##*/}

    if [ -z "$base" ] || [ "$src" = / ]; then
        _msg err "루트(/) 는 $label 할 수 없습니다."; return 1
    fi
    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
        _msg err "대상이 이미 없습니다: $src"; return 1
    fi
    while :; do
        printf '\n  %s%s%s\n' "$_C_HEAD" "$label" "$_C_RESET"
        printf '    원본       : %s\n' "$src"
        printf '    현재 폴더  : %s\n' "$_CWD"
        printf '    %s(Enter=현재 폴더 · ../ 또는 ../이름 · /절대경로 · ~/경로)%s\n' "$_C_DIM" "$_C_RESET"
        _prompt '    목적지 > ' "$_CWD" || return 1
        if ! _abs "$_ANSWER" "$_CWD"; then
            _msg err "폴더를 찾을 수 없습니다: $_ANSWER"; continue
        fi
        dst=$_ABS
        if [ ! -d "$dst" ]; then _msg err "디렉터리가 아닙니다: $dst"; continue; fi
        if [ ! -w "$dst" ]; then _msg err "쓰기 권한이 없습니다: $dst"; continue; fi
        break
    done

    if [ "$dst" = "$src" ]; then _msg warn '원본과 목적지가 같습니다.'; return 1; fi
    case "$dst/" in "$src/"*) _msg err '목적지가 원본 안이라 작업할 수 없습니다.'; return 1 ;; esac

    _join "$dst" "$base"; target=$REPLY
    if [ -e "$target" ] || [ -L "$target" ]; then
        if ! _confirm "이미 있습니다. 덮어쓸까요? → $target"; then
            _msg warn "건너뜀: $target"; return 1
        fi
        if ! rm -rf -- "$target"; then
            _msg err "기존 대상을 지우지 못했습니다: $target"; return 1
        fi
    fi

    if [ -d "$src" ] && [ ! -L "$src" ]; then
        cnt=$(find "$src" -mindepth 1 2>/dev/null | wc -l)
        printf '    폴더 안 항목 %s 개\n' "$cnt"
    fi
    printf '    %s  →  %s\n' "$src" "$target"

    if [ "$mode" = copy ]; then cp -a -- "$src" "$target"
    else                       mv -- "$src" "$target"; fi
    rc=$?
    if [ $rc -eq 0 ]; then _msg ok "$label 완료 → $target"
    else                 _msg err "$label 실패 (코드 $rc)"; fi
    return $rc
}

# ═══════════════════════════════════════════════════════════════════════
#  삭제
# ═══════════════════════════════════════════════════════════════════════
_do_delete() {
    local t=$1 sz
    if [ -z "$t" ] || [ "$t" = / ] || [ "$t" = "$_CWD" ]; then
        _msg err "삭제할 수 없는 대상입니다: ${t:-<빈 경로>}"; return 1
    fi
    if [ ! -e "$t" ] && [ ! -L "$t" ]; then
        _msg warn "이미 없습니다: $t"; return 1
    fi
    printf '\n  %s━━━━━━━━━━━━ ⚠ 삭제 확인 ━━━━━━━━━━━━%s\n' "$_C_ERR" "$_C_RESET"
    printf '    대상 : %s%s%s\n' "$_C_HEAD" "$t" "$_C_RESET"
    if [ -L "$t" ]; then
        printf '    종류 : 심볼릭 링크 → %s\n' "$(readlink -- "$t" 2>/dev/null)"
        printf '           %s(대상 파일은 지워지지 않습니다)%s\n' "$_C_DIM" "$_C_RESET"
    elif [ -d "$t" ]; then
        printf '    종류 : 폴더 — 안의 모든 항목까지 삭제\n'
        printf '    항목 : %s 개\n' "$(find "$t" -mindepth 1 2>/dev/null | wc -l)"
    else
        if stat -c '%s' -- "$t" >"$_STAT_TMP" 2>/dev/null; then
            IFS= read -r sz < "$_STAT_TMP"; _hsize "$sz"; sz=$REPLY
        fi
        printf '    종류 : 파일 · %s\n' "$sz"
    fi
    printf '    %s이 작업은 되돌릴 수 없습니다%s\n' "$_C_ERR" "$_C_RESET"
    if ! _confirm '정말 삭제할까요?'; then
        _msg warn '삭제를 취소했습니다.'; return 1
    fi
    if rm -rf -- "$t"; then _msg ok "삭제 완료: $t"; return 0
    else                    _msg err "삭제 실패: $t"; return 1; fi
}

# ═══════════════════════════════════════════════════════════════════════
#  이름 변경 / 생성
# ═══════════════════════════════════════════════════════════════════════
_do_rename() {
    local t=$1 dir base nn
    dir=${t%/*}; [ -z "$dir" ] && dir=/
    base=${t##*/}
    printf '\n  %s이름 변경%s\n' "$_C_HEAD" "$_C_RESET"
    printf '    현재 이름 : %s\n' "$base"
    printf '    %s(한글·공백·기호 가능. / 는 불가)%s\n' "$_C_DIM" "$_C_RESET"
    _prompt '    새 이름 > ' "$base" || return 1
    nn=$_ANSWER
    _check_name "$nn" || return 1
    if [ "$nn" = "$base" ]; then _msg warn '이름이 같습니다.'; return 1
    fi
    _join "$dir" "$nn"
    if [ -e "$REPLY" ] || [ -L "$REPLY" ]; then
        _msg err "같은 이름이 이미 있습니다: $nn"; return 1
    fi
    if mv -- "$t" "$REPLY" 2>/dev/null; then _msg ok "이름 변경 완료: $nn"; return 0
    else _msg err '이름 변경 실패 (권한 없음?)'; return 1; fi
}

_do_mkdir() {
    printf '\n  %s새 폴더 만들기%s\n' "$_C_HEAD" "$_C_RESET"
    printf '    위치 : %s\n' "$_CWD"
    _prompt '    새 폴더 이름 > ' '' || return 1
    _check_name "$_ANSWER" || return 1
    _join "$_CWD" "$_ANSWER"
    if [ -e "$REPLY" ] || [ -L "$REPLY" ]; then
        _msg err "이미 있습니다: $_ANSWER"; return 1
    fi
    if mkdir -- "$REPLY" 2>/dev/null; then _msg ok "만들었습니다: $_ANSWER"
    else _msg err '만들지 못했습니다 (권한 없음?)'; return 1; fi
}

_do_touch() {
    printf '\n  %s새 파일 만들기%s\n' "$_C_HEAD" "$_C_RESET"
    printf '    위치 : %s\n' "$_CWD"
    _prompt '    새 파일 이름 > ' '' || return 1
    _check_name "$_ANSWER" || return 1
    _join "$_CWD" "$_ANSWER"
    if [ -e "$REPLY" ] || [ -L "$REPLY" ]; then
        _msg err "이미 있습니다: $_ANSWER"; return 1
    fi
    if : > "$REPLY" 2>/dev/null; then _msg ok "만들었습니다: $_ANSWER"
    else _msg err '만들지 못했습니다 (권한 없음?)'; return 1; fi
}

# ═══════════════════════════════════════════════════════════════════════
#  정보 / 편집 / 보기 / 하위검색 / 경로복사
# ═══════════════════════════════════════════════════════════════════════
_do_info() {
    local t=$1
    printf '\n  %s━━━━━━━━━━━━━━━ 항목 정보 ━━━━━━━━━━━━━━━%s\n' "$_C_HEAD" "$_C_RESET"
    ls -ldh -- "$t" 2>/dev/null
    if [ -L "$t" ]; then
        printf '  링크 대상 : %s\n' "$(readlink -- "$t" 2>/dev/null)"
        printf '  실제 대상 : %s\n' "$(readlink -f -- "$t" 2>/dev/null || echo '없음 (끊어진 링크)')"
    fi
    if command -v file >/dev/null 2>&1; then
        printf '  형식     : %s\n' "$(file -b -- "$t" 2>/dev/null)"
    fi
    if [ -d "$t" ] && [ ! -L "$t" ]; then
        printf '  폴더 크기 : %s\n' "$(du -sh -- "$t" 2>/dev/null | cut -f1)"
        printf '  항목 수   : %s 개 (하위 포함)\n' "$(find "$t" -mindepth 1 2>/dev/null | wc -l)"
    elif [ -f "$t" ]; then
        printf '  줄 수     : %s 줄\n' "$(wc -l < "$t" 2>/dev/null)"
    fi
    _pause
}

_do_edit() {
    local t=$1 ed=$2
    _REDRAW_ALL=1
    if [ -d "$t" ] && [ ! -L "$t" ]; then _msg err '폴더는 편집할 수 없습니다.'; return 1; fi
    if [ ! -e "$t" ]; then _msg err "파일이 없습니다: $t"; return 1; fi
    if ! command -v "$ed" >/dev/null 2>&1; then
        _msg err "$ed 가 설치되어 있지 않습니다."; return 1
    fi
    _term_restore
    "$ed" "$t" < /dev/tty
    _term_init
}

_do_view() {
    local t=$1
    _REDRAW_ALL=1
    if [ -d "$t" ] && [ ! -L "$t" ]; then _msg err '폴더는 볼 수 없습니다.'; return 1; fi
    if [ ! -e "$t" ]; then _msg err "파일이 없습니다: $t"; return 1; fi
    _term_restore
    if command -v batcat >/dev/null 2>&1; then
        batcat -- "$t" 2>/dev/null | less -R < /dev/tty
    else
        cat -- "$t" 2>/dev/null | less -R < /dev/tty
    fi
    _term_init
}

_do_find() {
    local root=$1 pat found=0 f
    if [ -z "$root" ] || [ ! -d "$root" ]; then _msg err '폴더가 아닙니다.'; return 1; fi
    printf '\n  %s하위 검색%s   대상: %s\n' "$_C_HEAD" "$_C_RESET" "$root"
    _prompt '    검색어 > ' '' || return 1
    [ -z "$_ANSWER" ] && { _msg warn '검색어가 비었습니다.'; return 1; }
    pat=$_ANSWER
    printf '    검색 중…\n'
    while IFS= read -r -d '' f; do
        _fit "${f#$root/}" "$_w_sel"
        printf '    %s%s%s\n' "$_C_DIM" "$REPLY" "$_C_RESET"
        found=$(( found + 1 ))
        if [ $found -ge 300 ]; then
            printf '    %s… 300개 초과로 중단%s\n' "$_C_DIM" "$_C_RESET"
            break
        fi
    done < <( find "$root" -name "*$pat*" -print0 2>/dev/null )
    [ $found -eq 0 ] && printf '    결과 없음\n'
    printf '    총 %s 건\n' "$found"
    _pause
}

_copy_path() {
    local t=$1
    if command -v xclip >/dev/null 2>&1; then
        printf '%s' "$t" | xclip -selection clipboard 2>/dev/null && { _msg ok '클립보드에 복사했습니다.'; return 0; }
    elif command -v xsel >/dev/null 2>&1; then
        printf '%s' "$t" | xsel -b 2>/dev/null && { _msg ok '클립보드에 복사했습니다.'; return 0; }
    fi
    _fit "$t" "$_w_sel"
    printf '\n    %s%s%s\n' "$_C_DIM" "$REPLY" "$_C_RESET"
    _pause
}

# ═══════════════════════════════════════════════════════════════════════
#  목록 안에서 찾기
# ═══════════════════════════════════════════════════════════════════════
_select_to() {
    _sel=$1
    _page=$(( _sel / _page_size ))
    [ $_page -ge $_pages ] && _page=$(( _pages - 1 ))
    [ $_page -lt 0 ] && _page=0
}

_jump() {             # 현재 선택 다음부터 한 바퀴 돌며 부분일치
    local pat=$1 i n=${#_items[@]}
    for (( i=$_sel; i<n; i++ )); do
        case "${_items[i]}" in *"$pat"*) _select_to "$i"; return 0 ;; esac
    done
    for (( i=0; i<$_sel && i<n; i++ )); do
        case "${_items[i]}" in *"$pat"*) _select_to "$i"; return 0 ;; esac
    done
    return 1
}

_do_search() {
    printf '\n  %s이름 검색%s   (현재 선택 다음부터 한 바퀴)\n' "$_C_HEAD" "$_C_RESET"
    _prompt '    검색어 > ' '' || return 1
    [ -z "$_ANSWER" ] && return 1
    _LASTPAT=$_ANSWER
    _calc_pages
    if _jump "$_LASTPAT"; then _msg ok "찾았습니다: ${_items[_sel]}"
    else _msg warn "'$_LASTPAT' 과(와) 일치하는 항목이 없습니다."; fi
}

_do_search_next() {
    if [ -z "${_LASTPAT:-}" ]; then _msg warn '먼저 / 로 검색어를 입력하세요.'; return 1; fi
    _calc_pages
    _sel=$(( _sel + 1 ))
    [ $_sel -ge ${#_items[@]} ] && _sel=0
    if _jump "$_LASTPAT"; then _msg ok "찾았습니다: ${_items[_sel]}"
    else _msg warn "'$_LASTPAT' 더 이상 없습니다."; fi
}

# ═══════════════════════════════════════════════════════════════════════
#  항목 작업 메뉴
# ═══════════════════════════════════════════════════════════════════════
dfile() {
    local t=$1
    while :; do
        _REDRAW_ALL=1
        _full
        printf '\n  %s━━━━━━━━━━━━━━━ 항목 작업 ━━━━━━━━━━━━━━━%s\n' "$_C_HEAD" "$_C_RESET"
        if [ -z "$t" ] || [ "$t" = / ]; then
            printf '    %s선택된 항목이 없어 작업할 수 없습니다%s\n' "$_C_WARN" "$_C_RESET"
            printf '\n   Enter 키를 누르면 돌아갑니다…'
            IFS= read -r _x < /dev/tty
            return 1
        fi
        _fit "$t" "$_w_sel"
        printf '    대상 : %s%s%s\n' "$_C_HEAD" "$REPLY" "$_C_RESET"
        if [ ! -e "$t" ] && [ ! -L "$t" ]; then
            printf '    %s⚠ 대상이 이미 없습니다%s\n' "$_C_WARN" "$_C_RESET"
        elif [ -L "$t" ]; then
            printf '    %s→ %s%s\n' "$_C_DIM" "$(readlink -- "$t" 2>/dev/null)" "$_C_RESET"
        fi
        printf '\n'
        printf '  %s복사%s            %s이동%s            %s삭제%s\n'  "$_C_DIR" "$_C_RESET" "$_C_DIR" "$_C_RESET" "$_C_ERR" "$_C_RESET"
        printf '  %s이름 변경%s        %s정보%s\n'                              "$_C_DIR" "$_C_RESET" "$_C_DIR" "$_C_RESET"
        printf '\n'
        if [ -f "$t" ] || [ -L "$t" ]; then
            printf '  %svi 로 편집%s   %snano%s   %sless 로 보기%s'  "$_C_DIR" "$_C_RESET" "$_C_DIM" "$_C_RESET" "$_C_DIR" "$_C_RESET"
            command -v batcat >/dev/null 2>&1 && printf '   %sbatcat%s' "$_C_DIR" "$_C_RESET"
            printf '\n'
        fi
        printf '  %s하위 검색%s        %s경로 복사%s\n'  "$_C_DIR" "$_C_RESET" "$_C_DIR" "$_C_RESET"
        printf '\n  %sq%s  %s취소하고 목록으로%s\n'  "$_C_DIM" "$_C_RESET" "$_C_DIM" "$_C_RESET"

        _key || return 1
        case $_KEY in
            c|C) _do_copy_move "$t" copy ;;
            m|M) _do_copy_move "$t" move ;;
            d|D) _do_delete  "$t"; return 0 ;;
            r|R) _do_rename  "$t"; return 0 ;;
            i|I) _do_info    "$t" ;;
            e|E) _do_edit    "$t" vi;   return 0 ;;
            n|N) _do_edit    "$t" nano; return 0 ;;
            v|V) _do_view    "$t";      return 0 ;;
            b|B) _do_view    "$t";      return 0 ;;
            f|F) _do_find    "$t" ;;
            p|P) _copy_path  "$t" ;;
            q|Q|ESC|'') return 0 ;;
        esac
        _MSGWAIT=0.5
    done
}

# ═══════════════════════════════════════════════════════════════════════
#  상위 폴더로
# ═══════════════════════════════════════════════════════════════════════
_go_up() {
    [ "$_CWD" = / ] && return 0
    if [ ${#_STACK[@]} -gt 0 ]; then
        local k=$(( ${#_STACK[@]} - 1 ))
        _CWD=${_STACK[k]}; _sel=${_STACK_SEL[k]}; _page=${_STACK_PAGE[k]}
        _STACK=("${_STACK[@]:0:k}")
        _STACK_SEL=("${_STACK_SEL[@]:0:k}")
        _STACK_PAGE=("${_STACK_PAGE[@]:0:k}")
    else
        _CWD=${_CWD%/*}
        [ -z "$_CWD" ] && _CWD=/
        _sel=0; _page=0
    fi
}

# ═══════════════════════════════════════════════════════════════════════
#  메인
# ═══════════════════════════════════════════════════════════════════════
explorer() {
    local start=${1:-$PWD}
    if ! _abs "$start" "$PWD"; then
        printf '⚠ 경로를 찾을 수 없습니다: %s\n' "$start" >&2
        return 1
    fi
    _CWD=$_ABS
    _STAT_TMP="${TMPDIR:-/tmp}/.explorer.$$"
    : > "$_STAT_TMP" 2>/dev/null

    _detect_sortz
    _term_init

    local -a _STACK=() _STACK_SEL=() _STACK_PAGE=()
    _page=0; _sel=0

    trap '_term_restore; rm -f "$_STAT_TMP" 2>/dev/null; exit 0' INT
    trap '_term_restore; rm -f "$_STAT_TMP" 2>/dev/null' EXIT

    while :; do
        _collect
        _calc_pages
        _draw

        _key || break
        case $_KEY in
            UP|k|$'\x0b') [ $_sel -gt 0 ] && _sel=$(( _sel - 1 )) ;;
            DOWN|j|$'\x0a') [ $_sel -lt ${#_items[@]} ] && _sel=$(( _sel + 1 )) ;;
            NEXT|l|$'\x06')
                _page=$(( _page + 1 )); [ $_page -ge $_pages ] && _page=$(( _pages - 1 )) ;;
            PREV|h|$'\x02')
                _page=$(( _page - 1 )); [ $_page -lt 0 ] && _page=0 ;;
            HOME|g|$'\x01') _sel=0; _page=0 ;;
            END|G|$'\x05')
                _sel=$(( ${#_items[@]} - 1 )); [ $_sel -lt 0 ] && _sel=0
                _page=$(( _sel / _page_size )) ;;
            $'\x7f'|$'\x08') _go_up ;;
            $'\r'|$'\n')
                _sel_resolve
                case $_SEL_KIND in
                    cancel) break ;;
                    parent) _go_up ;;
                    d)
                        _STACK+=( "$_CWD" ); _STACK_SEL+=( "$_sel" ); _STACK_PAGE+=( "$_page" )
                        _CWD=$_SEL_PATH; _sel=0; _page=0 ;;
                    *) _MSGWAIT=0.5 dfile "$_SEL_PATH" ;;
                esac ;;
            s|S) if _sel_is_target; then _MSGWAIT=0.5 dfile "$_SEL_PATH"; fi ;;
            d|DELK) if _sel_is_target; then _MSGWAIT=0.5 _do_delete "$_SEL_PATH"; fi ;;
            c) if _sel_is_target; then _MSGWAIT=0.5 _do_copy_move "$_SEL_PATH" copy; fi ;;
            m) if _sel_is_target; then _MSGWAIT=0.5 _do_copy_move "$_SEL_PATH" move; fi ;;
            r) if _sel_is_target; then _MSGWAIT=0.5 _do_rename  "$_SEL_PATH"; fi ;;
            i) if _sel_is_target; then _do_info "$_SEL_PATH"; fi ;;
            e) if _sel_is_target; then _do_edit "$_SEL_PATH" vi; fi ;;
            v) if _sel_is_target; then _do_view "$_SEL_PATH"; fi ;;
            b) if _sel_is_target; then _do_view "$_SEL_PATH"; fi ;;
            p) if _sel_is_target; then _copy_path "$_SEL_PATH"; fi ;;
            f) if _sel_is_target; then _do_find "$_SEL_PATH"; fi ;;
            D) _MSGWAIT=0.5 _do_mkdir ;;
            t) _MSGWAIT=0.5 _do_touch ;;
            R) _MSGWAIT=0.5 _msg ok '새로 고쳤습니다.' ;;
            o|O)
                local sn=''
                case $_SORT in
                    name)  _SORT=mtime; sn='시간순(최신순)' ;;
                    mtime) _SORT=size;  sn='크기순(큰것부터)' ;;
                    *)     _SORT=name;  sn='이름순' ;;
                esac
                _sel=0; _page=0
                _MSGWAIT=0.5 _msg ok "정렬: $sn" ;;
            H)  [ "$_HIDDEN" = 1 ] && _HIDDEN=0 || _HIDDEN=1
                _sel=0; _page=0
                _MSGWAIT=0.5 _msg ok "숨김 파일: $([ "$_HIDDEN" = 1 ] && echo 표시 || echo 감춤)" ;;
            '/') _do_search ;;
            N)   _do_search_next ;;
            '?') _help ;;
            q|Q|0) break ;;
        esac
        _MSGWAIT=1.1
        _term_init
        if [ "$_REDRAW_ALL" = 1 ]; then
            _full; _REDRAW_ALL=0
        else
            _clear_frame
        fi
    done

    trap - EXIT INT
    rm -f "$_STAT_TMP" 2>/dev/null
    printf '\n  파일 탐색기를 종료했습니다.\n'
    return 0
}

explorer "${1:-$PWD}"
