#!/bin/bash
# bash2 하위 호환성 유지 (redhat7/oops1)
#
#debug=y
#set -x

CURRENT_PID=$$
PARENT_PID=$PPID
#echo "CURRENT_PID:$CURRENT_PID PARENT_PID:$PARENT_PID"
# 부모 프로세스가 go.sh인지 확인
PARENT_CMD=$(ps -o cmd= -p $PARENT_PID)
# 부모 프로세스가 go.sh일 경우 재귀 실행 방지 (단, 업데이트 재실행 GO_ALLOW_REEXEC=1 은 허용)
if [ "${GO_ALLOW_REEXEC:-0}" != "1" ] && [[ $PARENT_CMD == *"go.sh"* ]]; then
    echo "go.sh가 이미 실행 중입니다. (재귀 실행 방지)"
    exit 1
fi

echo
[ -z "$1" ] && who am i && sleep 0.2
#[ -t 0 ] && stty sane && stty erase ^?

# 존재 하는 파일의 절대경로 출력 readlink -f
readlinkf() {
    p="$1"
    while [ -L "$p" ]; do
        lt="$(readlink "$p")"
        if [[ $lt == /* ]]; then p="$lt"; else p="$(dirname "$p")/$lt"; fi
    done
    echo "$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)/$(basename "$p")"
}

# 실행중인 go.sh 파일의 절대경로 체크
basefile="$(readlinkf "$0")"
base="$(dirname "$basefile")"

gofile="$base/go.sh"
envorg="$base/go.env"

# env="$base/.go.env"
# env 파일을 메모리에 상주 cat 부하 감소 (/dev/shm 미지원 환경 안전 폴백)
shm_env_file="/dev/shm/.go.env"
fallback_env_file="$base/.go.env"
if [ -d /dev/shm ] && [ -w /dev/shm ]; then
    rm -f "$shm_env_file" 2>/dev/null
    env="$shm_env_file"
else
    env="$fallback_env_file"
fi

# 서버별로 별도의 추가 go.env 가 필요한 경우, 기본 go.env 와 추가로 불러오는 go.my.env
# 메뉴구성전 cat go.my.env >> go.env 합쳐서 파싱
envorg2="$base/go.my.env"
[ ! -f "$envorg2" ] && touch "$envorg2"

# gofile +x perm
#echo "base: $base"
chmod +x "$gofile"
chmod 600 "$envorg" "$envorg2"

# go.env 환경파일이 없을경우 다운로드
if [ ! -f "$envorg" ]; then
    echo -n ">>> go.env config file not found. Download? [y/n]: " && read -r down </dev/tty
    [ "$down" = "y" ] || [ "$down" = "Y" ] && output_dir="$(
        cd "$(dirname "${0}")"
        pwd
    )" && {
        # (2026-09-28) 기존: curl -m1 / wget -T 1 = 1초 타임아웃 + 실패해도 조용히 진행
        #   → go.env 없이 실행되어 메뉴 데이터가 통째로 비어버림.
        #   임시파일에 받고 용량 확인 후 mv 하므로, 실패 시 .go.env 지우지 않고 확실히 중단한다.
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --connect-timeout 5 -m 60 http://srt.byus.net/go.env -o "${output_dir}/.go.env.dl" 2>/dev/null || rm -f "${output_dir}/.go.env.dl"
        fi
        if [ ! -s "${output_dir}/.go.env.dl" ] && command -v wget >/dev/null 2>&1; then
            wget -q -T 10 --tries=2 http://srt.byus.net/go.env -O "${output_dir}/.go.env.dl" 2>/dev/null || rm -f "${output_dir}/.go.env.dl"
        fi
        if [ -s "${output_dir}/.go.env.dl" ]; then
            mv -f "${output_dir}/.go.env.dl" "${output_dir}/go.env"
            echo ">>> go.env downloaded: ${output_dir}/go.env ($(wc -c <"${output_dir}/go.env") bytes)"
        else
            echo ">>> ❌ go.env 다운로드 실패 (http://srt.byus.net/go.env)"
            echo ">>>    네트워크/서버 상태를 확인한 뒤 go.sh 를 다시 실행하세요. (중단)"
            exit 1
        fi
    }
fi

# /bin/gosh softlink
[ ! -L /bin/go ] && [ ! -L /bin/gosh ] && ln -s "$base"/go.sh /bin/gosh && echo -ne "$(ls -al /bin/gosh) \n>>> Soft link created for /bin/gosh. Press [Enter] " && read -r x </dev/tty

# 개인 환경변수 파일 불러오기 // 스크립트가 돌동안 사용이 가능하며 // env 에서 확인 가능
# ex) mydomain=ismee.net
if [ -f "$HOME"/go.private.env ]; then
    chmod 600 "$HOME"/go.private.env
    while IFS= read -r line; do
        if echo "$line" | grep -q -E '^[a-zA-Z_]+(=\"[^\"]*\"|=[^[:space:]]*)$'; then
            export "$line"
        fi
    done <"$HOME"/go.private.env
fi

# varVAR reuse -> saveVAR -> autoloadVAR
# loadVAR
encrypt() {
    # 인수중 마지막 인자 -> key ex) encrypt hello world mykey or echo "hello world" | encrypt mykey
    [ "$1" ] && local k="${!#}"
    [ ! "$k" ] && k="${ENC_KEY:-$HOSTNAME}"
    local message=""
    IFS='' read -r -d '' -t1 message
    [ "$2" ] && message="$message $(echo "${*:1:$(($# - 1))}" | tr '\n' ' ')"
    printf '%s' "$message" | openssl enc -des-ede3-cbc -pass pass:"$k" 2>/dev/null | perl -MMIME::Base64 -ne 'print encode_base64($_);'
}
decrypt() {
    [ "$1" ] && local k="${!#}"
    [ ! "$k" ] && k="${ENC_KEY:-$HOSTNAME}"
    local encrypted_message=""
    IFS='' read -r -d '' -t1 encrypted_message
    [ "$2" ] && encrypted_message="$encrypted_message $(echo "${*:1:$(($# - 1))}")"
    printf '%s' "$encrypted_message" | perl -MMIME::Base64 -ne 'print decode_base64($_);' | openssl enc -des-ede3-cbc -pass pass:"$k" -d 2>/dev/null
}
[ -f ~/.go.private.var ] && source ~/.go.private.var
# 10분 이내 export 된 변수 재사용 (복호화 성공 시에만 source 하고 즉시 삭제하여 평문 재복호화 버그 방지)
if [ -f "$HOME/.go.export.var" ]; then
    if find "$HOME/.go.export.var" -type f -mmin +10 2>/dev/null | grep -q .; then
        rm -f "$HOME/.go.export.var"
    elif decrypt < "$HOME/.go.export.var" > "$HOME/.go.export.var.dec" 2>/dev/null && [ -s "$HOME/.go.export.var.dec" ]; then
        source "$HOME/.go.export.var.dec" 2>/dev/null
    fi
    rm -f "$HOME/.go.export.var" "$HOME/.go.export.var.dec" 2>/dev/null
fi

# 터미널 출력 인코딩 (go.sh 자체 리터럴을 이 기준으로 변환한다) : utf8 | euckr
GOTERM_ENC="utf8"

# ---------------------------------------------------------
# 인코딩 변환 (잘림 방지)
#
#  RHEL 7.2 (glibc 2.17) 의 iconv 는 //IGNORE 를 지정해도
#  EUC-KR 로 표현 안 되는 문자를 만나면 그 자리에서 출력이 통째로 중단한다.
#    예) go.env 7393줄 중 2884줄만 나옴 -> 메인메뉴가 10번에서 잘림
#  그래서 //IGNORE 결과를 믿지 않고 줄수를 검증한 뒤,
#  잘렸으면 //TRANSLIT 로 다시 시도한다. (//TRANSLIT 는 완주한다)
# ---------------------------------------------------------
iconv_safe() { # 사용법 : iconv_safe <from> <to> <입력파일> <출력파일>
    #  ⚠ 변수명을 f 로 두면 안 된다. iconv 의 -f 는 --from-encoding 플래그라
    #    "iconv -f $f" 가 인코딩이 아니라 파일명으로 해석되어 변환이 통째로 실패한다.
    #    (실 사고: 메뉴가 빈 화면으로 뜬다)
    local s="$1" d="$2" i="$3" o="$4"
    local a b c
    [ -f "$i" ] || { cp -f "$i" "$o" 2>/dev/null; return 1; }
    a=$(wc -l < "$i" 2>/dev/null || echo 0)          # 원본 라인수
    iconv -f "$s" -t "$d//IGNORE"  "$i" > "$o.t1" 2>/dev/null
    b=$(wc -l < "$o.t1" 2>/dev/null || echo 0)
    if [ "$b" -ge "$a" ]; then                       # 완주했으면 그대로 채택
        mv -f "$o.t1" "$o"
        return 0
    fi
    # 잘렸으면 //TRANSLIT 로 재시도 (완주한다)
    iconv -f "$s" -t "$d//TRANSLIT" "$i" > "$o.t2" 2>/dev/null
    c=$(wc -l < "$o.t2" 2>/dev/null || echo 0)
    if [ "$c" -ge "$a" ]; then
        mv -f "$o.t2" "$o"
    else
        rm -f "$o.t2" 2>/dev/null
    fi
    rm -f "$o.t1" 2>/dev/null
    # 최종 안전망 : 결과가 비었으면 원본을 그대로 복사한다 (빈 메뉴 방지)
    [ -s "$o" ] || cp -f "$i" "$o" 2>/dev/null
    return 0
}

# go.sh 자체 리터럴(UTF-8) 을 터미널 인코딩으로 변환해 출력
#   구서버(EUC-KR 터미널)에서는 go.sh 에 박힌 한글 리터럴만 깨져 보인다.
#   go.env 는 iconv 로 변환되지만 go.sh 자신은 변환되지 않아 하단 안내가 두부더미가 된다.
#   [규칙] Bash 2.05 호환 & 이중 iconv 깨짐 방지:
#     1) "${@:2}" 는 Bash 2.05 에서 인자들을 공백 하나로 합쳐버리는 버그가 있으므로 shift 후 "$@" 를 쓴다.
#     2) $2 이후 인자($env 에서 읽은 제목/설명 등)는 이미 GOTERM_ENC(euckr) 상태이므로,
#        printf 결과 전체를 다시 iconv -f utf-8 에 넣으면 glibc iconv 가 EUC-KR 바이트에서 즉시 중단되어
#        줄 끝 개행(\n)까지 잘리고 방향키 이동 시 \033[8A 줄 수가 어긋나 화면이 붕괴된다.
#        따라서 go.sh 리터럴인 포맷 문자열($1)만 iconv 변환한 뒤 printf "$_fmt" "$@" 로 출력한다.
ko() { # 사용법 : ko "포맷문자열" [인자...]
    local _fmt="$1"
    shift
    if [ "$GOTERM_ENC" = "euckr" ]; then
        _fmt="$(printf '%s' "$_fmt" | iconv -f utf-8 -t euc-kr//TRANSLIT 2>/dev/null)"
    fi
    printf "$_fmt" "$@"
}

# 터미널 자동감지
# 터미널 utf8 환경이고 go.env 가 euckr 인경우 -> utf8 로 인코딩
if [ "$(echo $LANG | grep -i "utf")" ] && [ ! "$(file "$envorg" | grep -i "utf")" ]; then
    iconv_safe euc-kr utf-8 "$envorg" "$env"
    # cat go.my.env >> go.env
    [ -s "$envorg2" ] && iconv_safe euc-kr utf-8 "$envorg2" "$env.my"
    [ -f "$env" ] && { sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' "$env" > "$env.p" && mv -f "$env.p" "$env"; }
    [ -f "$env.my" ] && { sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' "$env.my" >> "$env"; rm -f "$env.my"; }
# 터미널 utf8 환경아니고 go.env 가 utf8 인경우 -> euckr 로 인코딩
elif [ ! "$(echo $LANG | grep -i "utf")" ] && [ "$(file "$envorg" | grep -i "utf")" ]; then
    GOTERM_ENC="euckr"
    iconv_safe utf-8 euc-kr "$envorg" "$env"
    [ -s "$envorg2" ] && iconv_safe utf-8 euc-kr "$envorg2" "$env.my"
    [ -f "$env" ] && { sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' "$env" > "$env.p" && mv -f "$env.p" "$env"; }
    [ -f "$env.my" ] && { sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' "$env.my" >> "$env"; rm -f "$env.my"; }
else
    cp -a "$envorg" "$env"
    cat "$envorg2" >>"$env" 2>/dev/null
    # LANG 이 비어 있어도 터미널은 euc-kr 일 수 있다. EUC-KR 터미널이면 go.sh 리터럴 변환이 필요하다.
    case "$(locale charmap 2>/dev/null)" in
        EUC-KR | euc-KR | CP949 | cp949) GOTERM_ENC="euckr" ;;
    esac
fi
# 어떤 이유로든 $env 가 비면 메뉴가 통째로 사라진다. 마지막 안전망.
[ -s "$env" ] || cp -a "$envorg" "$env" 2>/dev/null
export GOTERM_ENC
# go.env / go.my.env 내 전용 함수 블록(#---[go.env:func]--- ~ #---[/go.env:func]---) 로드 (메뉴 비노출)
if grep -q '^#---\[go\.env:func\]---' "$env" 2>/dev/null; then
    awk '/^#---\[go\.env:func\]---/{f=1;next} /^#---\[\/go\.env:func\]---/{f=0;next} f' "$env" > "$env.func.sh"
    [ -s "$env.func.sh" ] && source "$env.func.sh"
fi

# console error level print
[[ $(tty) == /dev/tty* ]] && echo 3 4 1 7 >/proc/sys/kernel/printk 2>/dev/null

# cmd 라인뒤 주석제거 // 빈줄은 그대로 //  trim
#sed -i 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' "$env"
#sed -i -e 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' -e '/^[[:blank:]]\+$/d' "$env"

sed -i \
    -e 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' `# 주석 제거 (공백 뒤 # 포함)` \
    -e 's/[[:blank:]]\+$//' `# 줄 끝 공백 제거 trim` \
    "$env"

#############################################################
# 메뉴 언어 필터 golang_filter   (L 키 = 한글 <-> English 즉시 토글)
#
#  [원칙 1] 마커 정규화 : %%%e / #e / :e / %%e  ->  %%% / # / : / %%
#  [원칙 2] 고아 보존   : 영문 대응 라인이 '바로 다음 줄' 에 있을 때만 한 쌍으로 취급.
#                       짝 없는 라인은 두 언어 모두에서 반드시 살아남는다.
#                       (go.env 의 '%%' 선명령 199줄 중 160줄은 한글 없는 실제 기능명령)
#                       -> 한쪽 통째 삭제를 하면 이 160개가 죽는다. 반드시 이 규칙을 지킬것.
#  [원칙 3] 빈줄 억제 금지 : 빈줄은 아래 listof_comm awk 의 메뉴블록 구분자다.
#                       버리면 모든 메뉴가 EOF 까지 하나로 합쳐진다(에러 없이 조용히 깨진다).
#
#  locale 자동감지(기존 동작)와 L 키 수동전환을 이 필터 하나로 통합했다.
#  go.env 는 KR/EN 양쪽 출력이 기존 sed 와 byte-identical 임을 실측 검증 완료.
#############################################################
envlang_master="$env.lang"
# 기존 환경변수 GOLANG 유지 (시작 시 .golang > go.my.env > 환경변수 > 자동감지 순으로 결정)
golang_file=""

golang_filter() { # $1 = kr|en   (성공 0 / 실패 1)
    [ "$1" = "kr" ] || [ "$1" = "en" ] || return 1
    [ -s "$envlang_master" ] || return 1
    # 마스터 무결성 검사 : 영문 헤더(%%e 계열)가 한 줄도 없으면 이미 언어필터가 씌워진 손상본이다.
    # 그 상태로 L 을 누르면 조용히 엉뚱한 언어가 출력되므로 여기서 막는다.
    grep -q '^%%%e ' "$envlang_master" 2>/dev/null || return 1
    awk -v LG="$1" '
        function emit(s) { printf "%s\n", s }
        function classify(s,   t, sd, n) {
            if      (s ~ /^%%%e /) { t="H"; sd="en"; n="%%% " substr(s,6) }
            else if (s ~ /^%%% /)  { t="H"; sd="kr"; n="%%% " substr(s,5) }
            else if (s ~ /^%%e /)  { t="P"; sd="en"; n="%% "  substr(s,5) }
            else if (s ~ /^%% /)   { t="P"; sd="kr"; n="%% "  substr(s,4) }
            else if (s ~ /^#he /)  { t="D"; sd="en"; n="#h " substr(s,5) }
            else if (s ~ /^#h /)   { t="D"; sd="kr"; n="#h " substr(s,4) }
            else if (s ~ /^#e /)   { t="C"; sd="en"; n="# "   substr(s,4) }
            else if (s ~ /^# /)    { t="C"; sd="kr"; n="# "   substr(s,3) }
            else if (s ~ /^!!! :e /) { t="L"; sd="en"; n="!!! : " substr(s,8) }
            else if (s ~ /^!!! : /)  { t="L"; sd="kr"; n="!!! : " substr(s,7) }
            else if (s ~ /^:e /)   { t="L"; sd="en"; n=": "   substr(s,4) }
            else if (s ~ /^: /)    { t="L"; sd="kr"; n=": "   substr(s,3) }
            else                   { t="X"; sd="";  n=s }
            TYPE=t; SIDE=sd; NORM=n
        }
        function store() { p_has=1; p_type=TYPE; p_side=SIDE; p_norm=NORM }
        function reset() { p_has=0; p_type=""; p_side=""; p_norm="" }
        BEGIN { p_has=0; p_type=""; p_side=""; p_norm="" }
        {
            classify($0)
            if (TYPE == "X") { if (p_has) { emit(p_norm); reset() } emit($0); next }
            if (!p_has) { store(); next }
            if (TYPE == p_type && SIDE != p_side) {
                if (LG == p_side) emit(p_norm); else emit(NORM)
                reset(); next
            }
            emit(p_norm)
            store()
        }
        END { if (p_has) emit(p_norm) }
    ' "$envlang_master" >"$env.lf" 2>/dev/null || {
        rm -f "$env.lf" 2>/dev/null
        return 1
    }
    # 안전장치 : 결과가 비었거나 원본보다 길면(awk 오류) 원본 훼손 방지를 위해 폐기
    _lf_n=$(wc -l <"$env.lf" 2>/dev/null)
    _mf_n=$(wc -l <"$envlang_master" 2>/dev/null)
    if [ -z "$_lf_n" ] || [ "$_lf_n" -lt 1 ] || [ "$_lf_n" -gt "$_mf_n" ] 2>/dev/null; then
        rm -f "$env.lf" 2>/dev/null
        return 1
    fi
    mv -f "$env.lf" "$env" 2>/dev/null || return 1
    GOLANG="$1"
    export GOLANG
    return 0
}

# 언어 전환 + 언어결합 캐시 무효화
#   바로가기 배열(shortcutarr/shortcutstr)은 최초 1회만 만들어지고 계속 재사용된다.
#   여기서 비우지 않으면 제목이 옛 언어인 채로 scuttitle/scutsub/st 가 계속 동작한다.
golang_toggle() { # $1 = kr|en
    golang_filter "$1" || return 1
    shortcutarr=()
    shortcutstr="@@@"
    if [ -n "$golang_file" ]; then
        printf '%s\n' "$GOLANG" >"$golang_file" 2>/dev/null
    fi
    return 0
}

# scut 의 현재 언어 제목을 $env 에서 직접 읽는다. (출력 없음)
#   golang_toggle 직후에는 shortcutarr 캐시가 비워져 있으므로
#   scuttitle 을 쓰면 빈 문자열이 나와 화면이 메인메뉴로 튀는다.
#   캐시 재구축을 기다리지 않고 $env 를 직접 읽으면 언제나 정확하다.
#   서브태그 {submenu_*} 와 맨뒤 @@@ 는 제거하고 제목만 돌려준다.
golang_title_of() { # $1 = scut
    [ -z "$1" ] && return 0
    [ "$1" = "m" ] && return 0
    # 주의 : sed 에서 \{ 는 '구간 시작' 연산자로 해석돼 구문이 깨진다.
    #        중괄호는 반드시 문자클래스 [{][}] 로 다룬다.
    grep -E "^%%% .*\\[$1\\]" "$env" 2>/dev/null | head -1 | awk '{
        s = $0
        sub(/^%%% /, "", s)
        if (s ~ /^[{]/) sub(/^[^{]*[}][ ]*/, "", s)
        sub(/@@@.*/, "", s)
        print s
    }'
    return 0
}

# 바로가기 배열 재구축 (중복검사 대화상자는 포함하지 않는다)
#   언어 전환 직후 scuttitle/scutsub/st 가 당장 필요하므로 캐시를 바로 다시 만들어 준다.
#   scutrelay / relay 태그까지 함께 붙여 scutsub·notscutrelay 가 정상 동작하게 한다.
#   [규칙] for-in 확장은 경로확장(glob)을 수행하므로 루프 동안 set -f (noglob) 로 끄고 복원한다.
#   [규칙] [scut] 추출은 파라미터 치환으로 fork 0회로 처리한다.
build_shortcutarr() {
    IFS=$'\n' _bsi="$(cat "$env" | grep -E "^%%%|^\{submenu.*" | awk '/^%%%/ {if (prev) print prev; prev = $0; next} /^{submenu_/ {print prev "@@@" $0; prev = ""; next} {if (prev) print prev; print $0; prev = ""} END {if (prev) print prev}' | grep -E '\[.+\]')"
    shortcutarr=(); shortcutstr="@@@"; _bidx=0
    case $- in *f*) _wasf=1 ;; *) _wasf=0 ;; esac
    set -f
    for _bitems in $_bsi; do
        _bsname="${_bitems#*[}"
        _bsname="${_bsname%%]*}"
        shortcutarr[$_bidx]="${_bsname}@@@${_bitems}"
        shortcutstr="${shortcutstr}${_bsname}|${_bidx}@@@"
        ((_bidx++))
    done
    [ "$_wasf" = "1" ] || set +f
    unset -v _bsi _bidx _bsname _bitems _wasf
    return 0
}

# 인코딩만 확정된 "두 언어 모두 포함" 원본을 마스터로 보관 (L 토글의 재실행 지점)
cp -f "$env" "$envlang_master" 2>/dev/null

# 시작시 언어/보기모드 결정 : 영구저장(.golang / .goview) > go.my.env > 환경변수 > 자동감지
local_myenv=""
[ -f "$envorg2" ] && local_myenv="$envorg2"
[ -z "$local_myenv" ] && [ -f "$HOME/go.my.env" ] && local_myenv="$HOME/go.my.env"

# 언어(GOLANG) 영구 저장 파일 경로 결정 및 로드 (.golang > go.my.env > 환경변수 > locale 자동감지)
if [ -n "$base" ] && [ -w "$base" ]; then
    golang_file="$base/.golang"
else
    golang_file="$HOME/.golang"
fi
_saved_golang=""
[ -f "$golang_file" ] && _saved_golang="$(head -n 1 "$golang_file" 2>/dev/null | tr -d '\r\n ')"
if [ "$_saved_golang" = "kr" ] || [ "$_saved_golang" = "en" ]; then
    GOLANG="$_saved_golang"
elif [ -n "$local_myenv" ]; then
    _myenv_golang="$(grep -m1 '^[[:blank:]]*GOLANG=' "$local_myenv" 2>/dev/null | cut -d= -f2- | tr -d '\r' | sed -e 's/^[[:blank:]]*//' -e 's/[[:blank:]]*$//' -e 's/^"//' -e 's/"$//')"
    [ -n "$_myenv_golang" ] && GOLANG="$_myenv_golang"
fi

# 보기모드(GOVIEW) 영구 저장 파일 경로 결정 및 로드 (.goview > go.my.env > 환경변수 > easy)
goview_file=""
if [ -n "$base" ] && [ -w "$base" ]; then
    goview_file="$base/.goview"
else
    goview_file="$HOME/.goview"
fi
_saved_goview=""
[ -f "$goview_file" ] && _saved_goview="$(head -n 1 "$goview_file" 2>/dev/null | tr -d '\r\n ')"
if [ "$_saved_goview" = "easy" ] || [ "$_saved_goview" = "cmd" ]; then
    GOVIEW="$_saved_goview"
elif [ -n "$local_myenv" ]; then
    _myenv_goview="$(grep -m1 '^[[:blank:]]*GOVIEW=' "$local_myenv" 2>/dev/null | cut -d= -f2- | tr -d '\r' | sed -e 's/^[[:blank:]]*//' -e 's/[[:blank:]]*$//' -e 's/^"//' -e 's/"$//')"
    [ -n "$_myenv_goview" ] && GOVIEW="$_myenv_goview"
fi
unset -v local_myenv _saved_golang _myenv_golang _saved_goview _myenv_goview
if [ "$GOLANG" != "kr" ] && [ "$GOLANG" != "en" ]; then
    GOLANG=""
    if (($(locale | grep -ci "kr") == 0)); then
        GOLANG="en"
    else
        GOLANG="kr"
    fi
fi
# 필터 실패시 기존 sed 방식으로 폴백한다 (마스터를 그대로 쓰면 두 언어가 함께 보여 메뉴가 중복된다)
if ! golang_filter "$GOLANG"; then
    if (($(locale | grep -ci "kr") == 0)); then
        sed -i -e '/^%%% /d' -e 's/^%%%e /%%% /g' "$env"
    else
        sed -i '/^%%%e /d' "$env"
    fi
fi
export GOLANG

# ===============================================================
# [V] 보기 모드 (easy: 쉬움 모드 ↔ cmd: 기존 명령어 모드)
#   기본값: easy (초보자 친화적 설명 및 확인 카드 표시)
# ===============================================================
[ "$GOVIEW" != "easy" ] && [ "$GOVIEW" != "cmd" ] && GOVIEW="easy"
export GOVIEW

goview_toggle() {
    if [ "$GOVIEW" = "easy" ]; then
        GOVIEW="cmd"
        if [ "$GOLANG" = "kr" ]; then
            ko "보기 모드: 명령어 모드 (기존) [V] - 저장됨\n"
        else
            echo "View mode: Command mode [V] - saved"
        fi
    else
        GOVIEW="easy"
        if [ "$GOLANG" = "kr" ]; then
            ko "보기 모드: 쉬움 모드 (설명 및 카드 확인) [V] - 저장됨\n"
        else
            echo "View mode: Easy mode [V] - saved"
        fi
    fi
    export GOVIEW
    if [ -n "$goview_file" ]; then
        printf '%s\n' "$GOVIEW" >"$goview_file" 2>/dev/null
    fi
    return 0
}

# tmp 폴더 set
if [[ $(id -u) == "0" ]] && echo "" >>/tmp/go_history.txt 2>/dev/null; then
    gotmp="/tmp"
    chmod 600 /tmp/go_history.txt
else
    [[ $(id -u) == "0" ]] && mv -f /tmp/go_history.txt /tmp/go_history.txt.
    gotmp="$HOME/tmp"
    mkdir -p "$gotmp"
    touch "$gotmp"/go_history.txt
    chmod 600 "$gotmp"/go_history.txt
fi

# public_ip & offline check ( dns or ping err )
publicip="$(wget --timeout=1 -q -O - http://icanhazip.com 2>/dev/null || wget --timeout 1 -q -O - http://checkip.amazonaws.com 2>/dev/null || echo "offline")"
[ "$publicip" == "offline" ] && offline="offline"
export "publicip"

localip=$(ip -4 addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | tr '\n' ' ')
[ -z "$localip" ] && localip=$(ip -4 addr show | awk '{while(match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {print substr($0, RSTART, RLENGTH) ; $0 = substr($0, RSTART+RLENGTH)}}' | grep -vE "127.0.0.1|255$" | tr '\n' ' ')
export "localip"

localip1=${localip%% *}
export "localip1"

guestip=$(who am i | awk -F'[():]' '{print $3}')
export "guestip"

gateway="$(ip route | grep 'default' | awk '{print $3}')"
export "gateway"

colorvar() {
    BOLD='\033[1m'
    RED1='\033[1;31m'
    RED='\033[0;31m'
    GRN1='\033[1;32m'
    GRN='\033[0;32m'
    MAG1='\033[1;35m'
    MAG='\033[0;35m'
    CYN1='\033[1;36m'
    CYN='\033[0;36m'
    YEL1='\033[1;33m'
    YEL='\033[0;33m'
    WHT1='\033[1;37m'
    WHT='\033[0;37m'
    YBL='\033[1;33;44m'
    YRE='\033[1;33;41m'
    NC='\033[0m'
}
colorvar

scutp() {
    echo "--------------------------------"
    echo "init scut print"
    echo "oldscut:$scut"
    echo "ooldscut:$oldscut"
    echo "oooldscut:$ooldscut"
    echo "ooooldscut:$oooldscut"
    echo "scut:$scut"
    echo "--------------------------------"
    echo "env | grep scut"
    env | grep scut | sort
    echo "--------------------------------"
}
#scutp

############################################################
# 최종 명령문을 실행하는 함수 process_commands // exec Process
############################################################
process_commands() {
    local command="$1"
    local cfm=$2
    local nodone=$3
    #readxy "in process_commands"

    [[ ${command:0:1} == "#" ]] && return # 주석선택시 취소

    if [ "$cfm" == "y" ] || [ "$cfm" == "Y" ] || [ -z "$cfm" ]; then # !!! check

        #echo && echo "=============================================="
        echo "=============================================="
        #if partcom=$(echo "$command" | awk -F '[:;]' '{for (i = 1; i <= NF; i++) {gsub(/^[ \t]+|[ \t]+$/, "", $i); if ($i ~ /^[a-zA-Z0-9_-]+$/) {print $i; break}}}') && [ -n "$partcom" ] && st "$partcom" >/dev/null; then
        # scut 감지

        # 명령어가 바로가기 scut 인지 판별
        partcom=""
        if [ "${command}" != "${command#:}" ]; then
            partcom=$(echo "$command" | awk '
    {
        nblk = split($0, blocks, /[;:]/)
        # ": scut" 형태면 앞의 빈 블록(인덱스 1)을 건너뛰고 2부터 본다.
        # 콜론이 없으면 1부터 본다.
        start = ($0 ~ /^:/) ? 2 : 1

        for (i = start; i <= nblk; i++) {
            blk = blocks[i]
            gsub(/^[ \t]+|[ \t]+$/, "", blk)
            n = split(blk, a, /[ \t]+/)

            if (n == 1 && a[1] ~ /^[a-zA-Z0-9_-]+$/) {
                print a[1]
                break
            }
        }
    }')
        else
            if [ "${command%% *}" = "$command" ]; then
                partcom="$command"
            fi
        fi
        #		readxy "partcom: $partcom"

        if [ -n "$partcom" ] && [ -z "$IN_BASHCOMM" ] && st "$partcom" >/dev/null; then
            echo "→ 내부 메뉴 [$partcom] 로 점프"
            menufunc "$(scutsub "$partcom")" "$(scuttitle "$partcom")" "$(notscutrelay "$partcom")"
            return 0
        elif echo "$command" | grep -Eq 'wget|tail -f|journalctl -f|ping|vmstat|logs -f|top|docker logs|script -q'; then
            # 탈출 ctrlc 만 가능한 경우 -> trap ctrlc 감지시 menu return
            (
                #echo "ctrl c trap process..."
                #trap 'stty sane' SIGINT
                trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
                #trap - SIGINT
                # pipemenu 로 들어오는 값은 eval 이 실행되면서 선택이 되어 취소가 불가능하다.
                # Cancel 같은 특수값을 select 에 추가하여 반회피 한다
                # pipemenu 는 파일 리스트 등에 한정하여 쓴다
                readxx $LINENO "> command: $command"
                [ "$command" = "Cancel" ] || safe_eval "$command"
                #eval "$command"
            )
            trap - SIGINT
            # flow 메뉴 구성을 위한 분기
            # elif [ "$command" = "${command%% *}" ] && st "$command" > /dev/null; then
        else
            readxx $LINENO ">> command: $command"
            #readxy $LINENO ">> command: $command"
            #command=$(command)
            [ "$command" = "Cancel" ] || safe_eval "$command"
            #echo "$command" | grep -Eq 'Cancel' || eval "$command"
        fi
        # log
        # cmd "/path/to/file" && echo $_ | xargs -I {} sh -c 'chmod +x {} && cat {}'
        lastarg=""
        lastarg="$(echo "$command" | awk99 | sed 's/"//g')" # 마지막 인수 재사용시 "제거 (ex.fileurl)
        echo "$command" >>"$gotmp"/go_history.txt 2>/dev/null
        # post
        # cd 명령이 들어왔을때 현재 위치의 ls
        echo "${command%% *}" | grep -qE "cd" && echo && echo "pwd: $(pwd) ... ls -ltr | tail -n5 " && echo $(pwd) >/dev/shm/pwd && dline && ls -ltr | tail -n5 && echo
        # rm 또는 mkdri 이 들어왔을때 마지막 인자의 ls
        echo "${command%% *}" | grep -qE "rm" >/dev/null 2>&1 && (
            command_args=($command)
            last_arg="${command_args[$((${#command_args[@]} - 1))]}"
            target_dir=$(dirname "$last_arg")
            [ ! -d "$target_dir" ] && target_dir="."
            echo "pwd: $(pwd) ... ls -ltr indirectory: $target_dir | tail -n5 " && echo && ls -ltr "$target_dir" | tail -n5 && echo
        )
        echo "=============================================="
        # unset var_value var_name
        unset -v var_value var_name
        echo && [ ! "$nodone" ] && echo -n "--> " && YEL && echo "${command//@@//}" && NC
        [ "$pipeitem" ] && echo "selected: $pipeitem"
        # sleep 1 or [Enter]
        #if [[ $command == vi* ]] || [[ $command == explorer* ]] || [[ $command == ": nodone"* ]] ; then
        if echo "$command" | egrep -q '^(vi.*|explorer.*|: nodone.*|bm)'; then
            nodone=y && sleep 1
            #elif [ -z "$IN_BASHCOMM" ] && echo "${command%% *}" | grep -qwE 'cd'; then
        elif [ -z "$IN_BASHCOMM" ] && (
            set -- $command
            [ "${1%% *}" = "cd" ] || [[ ${1} == "ls" && ${2} == "-al" ]] || [[ ${1} == "ls" && ${2} == "" ]] && [ -z "$3" ]
        ); then
            #readxy "1:$1 2:$2 3:$3"
            bashcomm
            nodone=y
        else
            :
            #readxy "1:$1 2:$2 3:$3 IN_BASHCOMM:$IN_BASHCOMM"
        fi

        #[ ! "$nodone" ] && { echo -en "--> \033[1;34mDone...\033[0m [60s.Enter] " && read -re -t 60 x ; }
        #[ ! "$nodone" ] && { echo -en "--> \033[1;34mDone...\033[0m [Enter] " && read -n1 -r; }
        [ ! "$nodone" ] && { echo -en "--> \033[1;34mDone...\033[0m [Enter] " && IFS=' ' read -re newcmds newcmds1 </dev/tty; }
    else
        echo "$command"
        echo "process_commands -> Canceled..."
    fi
    cmd_choice=""
}

#############################################################
# 환경파일에서 %%% 로 시작하는 모든 메뉴 출력 함수 print_menulist
#############################################################

print_menulist() {
    if [[ -n $chosen_command_sub ]] && [[ $chosen_command_sub != "{}" ]]; then
        # submenu list
        # 서브 메뉴에 {...} 테그를 떼고 이름만 출력
        # {submenu} 떼고 출력
        cat "$env" | grep -E '^%%%' | grep "$chosen_command_sub" | awk -F'}' '{print $2}'
    else
        # mainmenu list
        # 메인 메뉴는 따로 테그가 없어서 바로 출력
        cat "$env" | grep -E '^%%%' | grep -vE '\{submenu' | sed 's/%%% //'
    fi
}

###############################################################
# 하단 단축키 안내 (언어 인식 + 터미널 폭 대응)
#   - 메뉴 하단에는 [?] help 만 노출하고, [b] 등 단축키 안내(menu_keyhelp)는
#     [?] 입력 시에만 출력한다.
###############################################################
menu_keybar() { # compact 한줄 (호환/테스트용 유지, 폭 65~66칸)
    # ko 는 printf "$1" 이므로 줄바꿈은 문자열에 \n 을 넣어야 한다.
    if [ "$GOLANG" = "kr" ]; then
        ko "  [b]뒤로 [bb]2 [m]메인 [e]파일 [h]이력 [conf]설정 [L]언어 [?]help\n"
    else
        ko "  [b]back [bb]2 [m]menu [e]file [h]hist [conf]set [L]lang [?]help\n"
    fi
}

menu_keyhelp() { # detail 몇줄 (? 입력 시 표시, 72칸 이내)
    if [ "$GOLANG" = "kr" ]; then
        ko "==============================================\n"
        ko "  이동  [b]뒤로 [bb]2 [bbb]3 [m]메인 [ESC]위 < > 메뉴  [ ] 페이지\n"
        ko "  기능  [I/II]색인 [V]보기 [A]전체 [e]파일 [h]이력 [conf]설정 [?번호]설명\n"
        ko "  언어  [L]한글(L k)/English(L e)  [kr]인코딩변환(글자깨질때)\n"
    else
        ko "==============================================\n"
        ko "  move  [b]back [bb]x2 [bbb]x3 [m]main [ESC]up < > menu  [ ] page\n"
        ko "  tool  [I/II]index [V]view [A]all [e]file [h]hist [conf]set [?N]info\n"
        ko "  lang  [L]Korean(L k)/English(L e) [kr]encoding(fix garbled)\n"
    fi
}

menu_prompt() { # $1=최대번호 $2=스크롤여부(0|1) (? 는 항상 help 로 표시)
    local _vtxt="" _arr="↑↓" _lr="←→" _has_pg="${2:-0}"
    if [ "${GOTERM_ENC:-}" = "euckr" ]; then
        _arr="Up/Dn"
        _lr="L/R"
    fi
    if [ "${GOVIEW:-easy}" = "easy" ]; then
        [ "$GOLANG" = "kr" ] && _vtxt="$(ko '[V]명령어')" || _vtxt="[V]Cmd"
    else
        [ "$GOLANG" = "kr" ] && _vtxt="$(ko '[V]쉬움')" || _vtxt="[V]Easy"
    fi
    if [ "$GOLANG" = "kr" ]; then
        if [ "$_has_pg" = "1" ]; then
            ko ">>> 선택 [0-%s]  [%s]이동 [%s]페이지 [Enter]실행 %s [I]색인 [F]상세 [?]도움 : " "$1" "$_arr" "$_lr" "$_vtxt"
        else
            ko ">>> 선택 [0-%s]  [%s]이동 [Enter]실행 %s [I]색인 [F]상세 [?]도움 [q]종료 : " "$1" "$_arr" "$_vtxt"
        fi
    else
        if [ "$_has_pg" = "1" ]; then
            printf '>>> Select [0-%s]  [%s]Move [%s]Page [Enter]Go %s [I]Index [F]Detail [?]Help : ' "$1" "$_arr" "$_lr" "$_vtxt"
        else
            printf '>>> Select [0-%s]  [%s]Move [Enter]Go %s [I]Index [F]Detail [?]Help [q]Quit : ' "$1" "$_arr" "$_vtxt"
        fi
    fi
}

###############################################################
# [ESC] 단독 ESC 를 Ctrl-D 와 동일하게 (상위메뉴 복귀 / 종료)
#   문제: read -e(readline) 는 단독 ESC 를 그냥 버린다.
#         (실측: ESC+Enter => 값 "" rc=0) -> Ctrl-D(rc=1) 경로와 구분 불가
#   해법: 첫 1바이트만 먼저 선취해서 ESC(0x1b) 인지 먼저 판별한다.
#     1) Ctrl-D(0x04)              -> rc=1  (기존 EOF 경로 그대로)
#     2) ESC + 뒤따르는 바이트 없음  -> rc=1  (단독 ESC = Ctrl-D 와 동일)
#     3) ESC[ / ESC O               -> 화살표등 다른 시퀀스 -> 삼킨뒤 readline 위임
#     4) 그 외 첫글자                -> 값 맨 앞에 붙여 원래대로 복원
#   - 첫글자는 공백분리 하지 않고 통째로 읽은뒤 붙인다.
#     (공백 2단어 입력 "h e" 가 "he" 로 뭉개지는 것 방지)
#   - 첫글자 위치에서 백스페이스/지우개키는 무시하고 다시 대기한다.
#   - 사용법: menu_read "프롬프트" "변수1" "변수2"
#             반환 0 = 정상입력 / 1 = ESC 또는 Ctrl-D (호출부가 q 처리)
###############################################################
menu_read() {
    local _mrp="$1" _n1="$2" _n2="$3" _allow_nav="${4:-0}" _c="" _x="" _rest="" _rc=0 _eol=0
    local -a _w=()
    #  [규칙] IFS 고정 (인수 분리 버그 근본 차단)
    #   아래 "${_w[*]:1}" 은 배열 결합이면서 **IFS 의 첫 글자를 구분자로 쓴다.**
    #   IFS 가 $'\n' 로 오염되어 있으면 "shutdown -h now" 의 now 가
    #   공백이 아니라 '줄바꿈' 으로 붙어 choice1="-h\nnow" 가 되고,
    #   safe_eval 에 2줄짜리 명령이 전달되어 인수가 깨진다 (실측).
    #   menu_read 는 어디서 호출되든 동일하게 동작해야 하므로
    #   함수 진입 즉시 기본값으로 고정한다 (안전망 1줄).
    local IFS=$' \t\n'
    # [규칙] 구 bash 호환: read -t 소수(0.35)는 bash 4+ 만 지원 -> 3.x 이하는 정수 1초
    local _esc_t=1
    [ "${BASH_VERSINFO[0]:-0}" -ge 4 ] && _esc_t=0.35
    _MENU_V1=""
    _MENU_V2=""
    printf '%s' "$_mrp" # readline 프롬프트는 여기서 직접 출력
    while :; do
        _c=""
        # 첫글자 대기(무제한). 사용자가 ESC 를 누르면 여기서 잡힌다
        IFS= read -rsn1 _c </dev/tty 2>/dev/null || { _rc=1; break; }
        if [ "$_c" = $'\004' ]; then _rc=1; break; fi # Ctrl-D
        if [ "$_c" = $'\033' ]; then                  # ESC
            _x=""
            IFS= read -rsn1 -t $_esc_t _x </dev/tty 2>/dev/null
            # 뒤바이트 없음(또는 ESC 연속) = 단독 ESC -> Ctrl-D 와 동일
            if [ -z "$_x" ] || [ "$_x" = $'\033' ]; then _rc=1; break; fi
            # '[' 'O' = 화살표/기능키 시퀀스 -> _allow_nav=1 이면 커서 이동 이벤트 반환
            if [ "$_x" = "[" ] || [ "$_x" = "O" ]; then
                IFS= read -rsn1 -t $_esc_t _x </dev/tty 2>/dev/null
                if [ "$_allow_nav" = "1" ]; then
                    case "$_x" in
                        "A")
                            _MENU_V1="__NAV_UP__"
                            [ -n "$_n1" ] && eval "$_n1=\"\$_MENU_V1\""
                            [ -n "$_n2" ] && eval "$_n2=\"\""
                            return 0
                            ;;
                        "B")
                            _MENU_V1="__NAV_DOWN__"
                            [ -n "$_n1" ] && eval "$_n1=\"\$_MENU_V1\""
                            [ -n "$_n2" ] && eval "$_n2=\"\""
                            return 0
                            ;;
                        "C")
                            _MENU_V1="__NAV_RIGHT__"
                            [ -n "$_n1" ] && eval "$_n1=\"\$_MENU_V1\""
                            [ -n "$_n2" ] && eval "$_n2=\"\""
                            return 0
                            ;;
                        "D")
                            _MENU_V1="__NAV_LEFT__"
                            [ -n "$_n1" ] && eval "$_n1=\"\$_MENU_V1\""
                            [ -n "$_n2" ] && eval "$_n2=\"\""
                            return 0
                            ;;
                        "5"|"6")
                            local _x2="" _pg_nav=""
                            [ "$_x" = "5" ] && _pg_nav="__NAV_PGUP__" || _pg_nav="__NAV_PGDN__"
                            IFS= read -rsn1 -t $_esc_t _x2 </dev/tty 2>/dev/null
                            while [ -n "$_x2" ] && [ "$_x2" != "~" ]; do
                                case "$_x2" in
                                    [0-9\;]) IFS= read -rsn1 -t $_esc_t _x2 </dev/tty 2>/dev/null ;;
                                    *) break ;;
                                esac
                            done
                            _MENU_V1="$_pg_nav"
                            [ -n "$_n1" ] && eval "$_n1=\"\$_MENU_V1\""
                            [ -n "$_n2" ] && eval "$_n2=\"\""
                            return 0
                            ;;
                        [0-9])
                            local _x2=""
                            IFS= read -rsn1 -t $_esc_t _x2 </dev/tty 2>/dev/null
                            while [ -n "$_x2" ] && [ "$_x2" != "~" ]; do
                                case "$_x2" in
                                    [0-9\;]) IFS= read -rsn1 -t $_esc_t _x2 </dev/tty 2>/dev/null ;;
                                    *) break ;;
                                esac
                            done
                            ;;
                    esac
                    _c=""
                    continue
                fi
            fi
            if [ "$_allow_nav" = "1" ]; then
                _c=""
                continue
            fi
            _c=""
            break
        fi
        case "$_c" in
            "") _eol=1 && break ;;                                       # Enter = 빈입력 (read -n1 이 Newline 을 만나 반환한 빈값)
            $'\010' | $'\011' | $'\025' | $'\177') _c="" && continue ;; # 편집키 무시
            $'\012' | $'\015') _c="" && _eol=1 && break ;;               # Enter = 빈입력
            [[:cntrl:]]) _c="" && continue ;;                            # 그외 제어문자 무시
        esac
        break
    done
    if [ "$_rc" -eq 0 ] && [ "$_eol" -eq 0 ]; then
        if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
            # Bash 4+: read -i 로 첫글자를 readline 버퍼에 직접 넣어
            # Backspace / Ctrl-U 로 첫글자까지 완전히 지우고 재입력할 수 있게 한다.
            local _rl_rc=0
            IFS= read -re -i "$_c" _rest </dev/tty
            _rl_rc=$?
            if [ "$_rl_rc" -ne 0 ]; then
                printf '\n' >/dev/tty
                [ -z "$_rest" ] && _rc=1
            fi
        else
            # Bash < 4.0 폴백: -i 미지원이므로 1글자 단위 편집 루프로 Backspace 지원
            local _line="$_c" _ch="" _seq=""
            [ -n "$_c" ] && printf '%s' "$_c" >/dev/tty
            while :; do
                _ch=""
                IFS= read -rsn1 _ch </dev/tty 2>/dev/null || {
                    [ -z "$_line" ] && _rc=1
                    break
                }
                case "$_ch" in
                    $'\004')
                        if [ -z "$_line" ]; then _rc=1; break; fi
                        continue
                        ;;
                    "" | $'\012' | $'\015')
                        break
                        ;;
                    $'\177' | $'\010')
                        if [ -n "$_line" ]; then
                            _line="${_line%?}"
                            printf '\b \b' >/dev/tty
                        fi
                        ;;
                    $'\025')
                        while [ -n "$_line" ]; do
                            _line="${_line%?}"
                            printf '\b \b' >/dev/tty
                        done
                        ;;
                    $'\033')
                        _seq=""
                        IFS= read -rsn1 -t 1 _seq </dev/tty 2>/dev/null
                        if [ -z "$_seq" ] || [ "$_seq" = $'\033' ]; then
                            if [ -z "$_line" ]; then _rc=1; break; fi
                        elif [ "$_seq" = "[" ] || [ "$_seq" = "O" ]; then
                            IFS= read -rsn1 -t 1 _seq </dev/tty 2>/dev/null
                            if [ "$_allow_nav" = "1" ] && [ -z "$_line" ]; then
                                case "$_seq" in
                                    "A") _MENU_V1="__NAV_UP__"; [ -n "$_n1" ] && eval "$_n1=\"\$_MENU_V1\""; [ -n "$_n2" ] && eval "$_n2=\"\""; return 0 ;;
                                    "B") _MENU_V1="__NAV_DOWN__"; [ -n "$_n1" ] && eval "$_n1=\"\$_MENU_V1\""; [ -n "$_n2" ] && eval "$_n2=\"\""; return 0 ;;
                                    "C") _MENU_V1="__NAV_RIGHT__"; [ -n "$_n1" ] && eval "$_n1=\"\$_MENU_V1\""; [ -n "$_n2" ] && eval "$_n2=\"\""; return 0 ;;
                                    "D") _MENU_V1="__NAV_LEFT__"; [ -n "$_n1" ] && eval "$_n1=\"\$_MENU_V1\""; [ -n "$_n2" ] && eval "$_n2=\"\""; return 0 ;;
                                    "5"|"6")
                                        local _x2="" _pg_nav=""
                                        [ "$_seq" = "5" ] && _pg_nav="__NAV_PGUP__" || _pg_nav="__NAV_PGDN__"
                                        IFS= read -rsn1 -t 1 _x2 </dev/tty 2>/dev/null
                                        while [ -n "$_x2" ] && [ "$_x2" != "~" ]; do
                                            case "$_x2" in
                                                [0-9\;]) IFS= read -rsn1 -t 1 _x2 </dev/tty 2>/dev/null ;;
                                                *) break ;;
                                            esac
                                        done
                                        _MENU_V1="$_pg_nav"
                                        [ -n "$_n1" ] && eval "$_n1=\"\$_MENU_V1\""
                                        [ -n "$_n2" ] && eval "$_n2=\"\""
                                        return 0
                                        ;;
                                esac
                            fi
                            case "$_seq" in
                                [0-9])
                                    local _x2=""
                                    IFS= read -rsn1 -t 1 _x2 </dev/tty 2>/dev/null
                                    while [ -n "$_x2" ] && [ "$_x2" != "~" ]; do
                                        case "$_x2" in
                                            [0-9\;]) IFS= read -rsn1 -t 1 _x2 </dev/tty 2>/dev/null ;;
                                            *) break ;;
                                        esac
                                    done
                                    ;;
                            esac
                        fi
                        ;;
                    [[:cntrl:]])
                        continue
                        ;;
                    *)
                        _line="${_line}${_ch}"
                        printf '%s' "$_ch" >/dev/tty
                        ;;
                esac
            done
            printf '\n' >/dev/tty
            _rest="$_line"
        fi
        # [규칙] Bash 2 호환: <<< / read -a / ${arr[*]:1} 금지 -> 순수 파라미터 확장으로 단어 분리
        while [ "${_rest# }" != "$_rest" ]; do _rest="${_rest# }"; done # 앞 공백 제거
        _MENU_V1="${_rest%% *}"
        if [ "$_rest" != "$_MENU_V1" ]; then
            _MENU_V2="${_rest#* }"
            while [ "${_MENU_V2# }" != "$_MENU_V2" ]; do _MENU_V2="${_MENU_V2# }"; done
            while [ "${_MENU_V2% }" != "$_MENU_V2" ]; do _MENU_V2="${_MENU_V2% }"; done
        fi
    else
        # Enter(빈입력) / ESC / Ctrl-D : 커서를 다음줄로 내려 기존 표기와 맞춘다
        printf '\n' >/dev/tty
    fi
    # [규칙] Bash 2 호환: printf -v 는 bash 3.1+ -> eval 로 대입 (변수명은 내부 고정값)
    [ -n "$_n1" ] && eval "$_n1=\"\$_MENU_V1\""
    [ -n "$_n2" ] && eval "$_n2=\"\$_MENU_V2\""
    return $_rc
}

###############################################################
# [풀기] 긴 한줄 명령을 순서대로 분해해 보여준다
#   - 구분자 : 최상위 ';'   ( go.sh 의 단계구분 ';;' 는 단계경계로 따로 처리 )
#   - 따옴표 / 괄호 / 중괄호 안쪽의 ';' 는 쪼개지 않는다.
#     ( awk '{for(i=2; i<=NF; i+=2) ...}' 같은 프로그램 내부는 통째로 보존 )
#   - 블록구문( for/while/until/case/select ... do/done/esac/fi )은 쪼개지 않는다.
#     ( 쪼개면 'for i in x' / 'do echo' 처럼 문법이 깨진 조각으로 보인다 )
#   - 112칸을 넘는 문장은 5칸 들여쓰기로 이어붙여 화면 밖으로 나가지 않게 한다.
#   - 출력 : 번호 붙은 문장들( 문장 1개 = fold 포함 여러줄 가능 ). 총 문장수 = wc -l 이 아님.
###############################################################
cmd_unfold() { # $1 = 명령문 1줄
    printf '%s\n' "$1" | awk '
    function blkstart(s) { return (s ~ /^[ \t]*(if|for|while|until|case|select)([ \t]|$)/) }
    function blkend(s)   { t = s; sub(/[ \t]+$/, "", t); return (t ~ /(^|[ \t;])(done|esac|fi)([ \t;]|$)/) }
    function flush(   s, t) {
        s = cur
        gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s)
        cur = ""
        if (s == "") return
        n++
        t = ""
        while (length(s) > 112) { t = t substr(s, 1, 112) "\n     "; s = substr(s, 113) }
        print "  " n ") " t s
    }
    {
        line = $0; cur = ""; q = ""; d = 0; esc = 0; bd = 0; n = 0
        L = length(line)
        for (i = 1; i <= L; i++) {
            c = substr(line, i, 1)
            if (esc)        { cur = cur c; esc = 0; continue }
            if (c == "\\")  { cur = cur c; esc = 1; continue }
            if (q != "") {                                   # 따옴표 안 = 문자 그대로
                if (c == q) q = ""
                cur = cur c
                continue
            }
            if (c == "\047") { q = "\047"; cur = cur c; continue }
            if (c == "\"")  { q = "\"";  cur = cur c; continue }
            if (c == "(" || c == "{" || c == "[") { d++; cur = cur c; continue }
            if (c == ")" || c == "}" || c == "]") { if (d > 0) d--; cur = cur c; continue }
            if (c == ";") {
                if (d > 0) { cur = cur c; continue }        # 괄호 안 ; 는 보존
                if (bd > 0) {                                # 블록 내부
                    if (blkend(cur)) { bd--; flush(cur); if (bd == 0 && substr(line, i + 1, 1) == ";") i++ }
                    else cur = cur c
                    continue
                }
                if (blkstart(cur)) { bd = 1; cur = cur c; continue } # 블록 시작 = 쪼개지 않음
                flush(cur)
                if (substr(line, i + 1, 1) == ";") i++      # 단계구분 ;; 는 한 번에 넘긴다
                continue
            }
            cur = cur c
        }
        flush(cur)
    }'
}
###############################################################
# [#h] CMD 목록 "설명 조회" — 실행하지 않고 설명만 보고한다
#   입력 : "?8" 또는 "? 8"  ->  8 번 명령의 #h 설명 + 원본 명령줄 출력
#          "?"              ->  단축키 도움말
#   반환 : 0 = 조회를 처리했음(목록 제자리 유지, 선택 아님)
#          1 = 일반 선택 입력(처리 대상 아님)
#   - 선택(cmd_choice)을 비워두므로 실행으로 넘어가지 않는다.
###############################################################
cmd_desc_peek() {
    local _q="" _qi="" _qd="" _qc="" _uq="" _un=0
    case "${cmd_choice-}" in
        "?")
            if [ -n "${cmd_choice1-}" ]; then _q="${cmd_choice1}"; else _q="?"; fi
            ;;
        "?"*) _q="${cmd_choice#\?}" ;;
    esac
    [ -z "$_q" ] && return 1
    _q="${_q//[[:space:]]/}"
    echo
    if [ "$_q" = "?" ]; then
        menu_keyhelp
    elif [ -n "$_q" ] && [ -z "${_q##[0-9]*}" ] && [ -z "${_q//[0-9]/}" ] && [ "$_q" -ge 1 ] && [ "$_q" -lt "${display_idx:-0}" ]; then
        _qi="${original_indices[$((_q - 1))]}"
        _qd="${chosen_desc[$((_qi - 1))]-}"
        _qc="${chosen_commands[$((_qi - 1))]-}"
        printf "\x1b[1;33m>>> %s 번 명령\x1b[0m\n" "$_q"
        if [ -n "$_qd" ]; then
            printf '%s\n' "$_qd" | sed -e 's/^/\x1b[1;37m  /' -e 's/$/\x1b[0m/'
        else
            printf '\x1b[1;30m  ( go.env 에 #h 설명이 없습니다 )\x1b[0m\n'
        fi
        # [풀기] 문장이 여러개로 이어붙은 명령은 순서대로 풀어 보여준다.
        #        ( ;; 와 ; 기준으로 분리, 따옴표/괄호/블록구문 안 ; 는 보존 )
        #        한 문장짜리 짧은 명령은 예전처럼 '--> 원본' 한 줄로 보여준다.
        if [ -n "$_qc" ]; then
            _uq="$(cmd_unfold "$_qc")"
            # 문장 첫줄만 "  N) " 패턴이므로 grep -c 로 문장수를 센다 (fold 연속줄 제외)
            _un=$(printf '%s\n' "$_uq" | grep -cE '^  [0-9]+[)] ')
            if [ "${_un:-0}" -gt 1 ]; then
                printf '\x1b[1;36m  -- command unfolded, %s steps --\x1b[0m\n' "$_un"
                printf '%s\n' "$_uq"
            else
                printf '\x1b[1;30m  --> %s\x1b[0m\n' "${_qc//@@//}"
            fi
        fi
    else
        echo " [?] 뒤에는 목록에 있는 번호만 입력가능합니다 (1-$(( ${display_idx:-1} - 1 )))"
    fi
    echo
    cmd_choice=""
    cmd_choice1=""
    return 0
}

###############################################################
# [#h] 쉬움 모드(Easy Mode) 항목 렌더링
#   - 배지: [위험](빨강), [변경](노랑), [조회](초록)
#   - 설명 제목: 1) #h 첫 줄  2) 직전 # 주석  3) : 라벨 ;  4) 자동 동작 제목
###############################################################
# [규칙] AGENTS.md § 쉬움 모드 제목 = 모든 실행 항목에 사람이 읽는 제목을 표시
# go.env 의 오래된 명령에는 #h/#he 쌍이 없을 수 있다. 원문 명령을 그대로 노출하지
# 않도록, 공통 동작을 읽어 현재 언어의 제목을 만들어 목록/미리보기/확인 카드에 쓴다.
easy_auto_title() {
    local easy_cmd="$1"
    local easy_label=""
    local easy_name=""

    # : 제목 ; 명령 형태는 이미 사람이 쓴 제목이므로 그대로 쓴다.
    case "$easy_cmd" in
        :*";"*)
            easy_label="${easy_cmd#:}"
            easy_label="${easy_label%%;*}"
            easy_label="${easy_label#"${easy_label%%[![:space:]]*}"}"
            easy_label="${easy_label%"${easy_label##*[![:space:]]}"}"
            [ -n "$easy_label" ] && printf '%s\n' "$easy_label" && return
            ;;
    esac

    easy_cmd="${easy_cmd#!!!}"
    easy_cmd="${easy_cmd#"${easy_cmd%%[![:space:]]*}"}"
    easy_cmd="${easy_cmd%"${easy_cmd##*[![:space:]]}"}"

    if [ "$GOLANG" = "kr" ]; then
        local _kr_out=""
        case "$easy_cmd" in
            *"systemctl status"*) _kr_out="서비스 상태를 확인합니다" ;;
            *"systemctl restart"*|*"systemctl try-reload-or-restart"*) _kr_out="서비스를 다시 시작합니다" ;;
            *"systemctl reload"*) _kr_out="서비스 설정을 다시 불러옵니다" ;;
            *"systemctl enable"*) _kr_out="서비스 자동 시작을 설정합니다" ;;
            *"systemctl disable"*) _kr_out="서비스 자동 시작을 해제합니다" ;;
            *"systemctl start"*) _kr_out="서비스를 시작합니다" ;;
            *"systemctl stop"*) _kr_out="서비스를 중지합니다" ;;
            *"journalctl"*) _kr_out="시스템 로그를 확인합니다" ;;
            *"apt "*"install"*|*"apt-get "*"install"*|*"yum "*"install"*|*"dnf "*"install"*|"yyay "*) _kr_out="패키지를 설치합니다" ;;
            *"apt "*"remove"*|*"yum "*"remove"*|*"dnf "*"remove"*) _kr_out="패키지를 제거합니다" ;;
            *"apt "*"update"*|*"apt "*"upgrade"*|*"yum "*"update"*|*"dnf "*"update"*) _kr_out="패키지 목록 또는 시스템을 업데이트합니다" ;;
            *"docker-compose"*" up"*|*"docker compose"*" up"*) _kr_out="Docker Compose 서비스를 시작합니다" ;;
            *"docker-compose"*" down"*|*"docker compose"*" down"*) _kr_out="Docker Compose 서비스를 중지합니다" ;;
            *"docker-compose"*" logs"*|*"docker compose"*" logs"*) _kr_out="Docker Compose 로그를 봅니다" ;;
            *"docker "*" ps"*) _kr_out="Docker 컨테이너 목록을 봅니다" ;;
            *"docker "*" start"*) _kr_out="Docker 컨테이너를 시작합니다" ;;
            *"docker "*" stop"*) _kr_out="Docker 컨테이너를 중지합니다" ;;
            *"docker "*" rm"*) _kr_out="Docker 컨테이너를 삭제합니다" ;;
            *"git clone"*) _kr_out="Git 저장소를 복제합니다" ;;
            *"git pull"*) _kr_out="Git 저장소를 최신 상태로 받습니다" ;;
            *"git push"*) _kr_out="Git 변경 사항을 원격 저장소에 올립니다" ;;
            *"git status"*) _kr_out="Git 변경 상태를 확인합니다" ;;
            *"git diff"*) _kr_out="Git 변경 내용을 비교합니다" ;;
            *"certbot"*) _kr_out="SSL 인증서를 발급하거나 관리합니다" ;;
            *"fail2ban-client unban --all"*) _kr_out="모든 감옥 차단 일괄 해제 (초기화)" ;;
            *"fail2ban-client unban"*) _kr_out="지정한 IP 차단 일괄 해제" ;;
            *"fail2ban-client set"*" unbanip"*) _kr_out="선택한 감옥에서 지정한 IP 차단 수동 해제" ;;
            *"fail2ban-client set"*" banip"*) _kr_out="선택한 감옥에 지정한 IP 수동 차단 등록" ;;
            *"fail2ban-client status"*) _kr_out="Fail2ban 감옥 상태 및 차단 통계 확인" ;;
            *"firewall-cmd"*"--remove-rich-rule"*) _kr_out="방화벽 리치 룰(Rich Rule) 차단 수동 삭제" ;;
            *"firewall-cmd"*"--list-rich-rules"*) _kr_out="방화벽 리치 룰(Rich Rule) 차단 목록 조회" ;;
            *"firewall-cmd"*) _kr_out="방화벽 규칙을 확인하거나 변경합니다" ;;
            *"pkill -kill -t"*|*"pkill"*"pts"*) _kr_out="특정 터미널(pts) 세션 강제 종료 (kick)" ;;
            *"pkill"*"sshd"*|*"kill"*"sshd"*) _kr_out="특정 IP의 모든 SSH 연결 일괄 강제 퇴출" ;;
            *"pkill "*|*"kill "*) _kr_out="프로세스를 강제 종료합니다" ;;
            *"w |"*|"w") _kr_out="현재 서버 접속자 및 활성 터미널 세션 확인" ;;
            *"explorer /etc/fail2ban"*) _kr_out="Fail2ban 설정 폴더 내부 파일 탐색" ;;
            *"yyay fail2ban"*) _kr_out="Fail2ban 침입 차단 보안 패키지 설치" ;;
            *"ufw "*) _kr_out="UFW 방화벽을 관리합니다" ;;
            *"iptables"*) _kr_out="iptables 방화벽 규칙을 확인하거나 변경합니다" ;;
            *"ssh "*|"ssh"*) _kr_out="원격 서버에 SSH로 연결하거나 명령을 실행합니다" ;;
            *"scp "*|"rsync "*|"ncp "*|"ncpr "*) _kr_out="파일을 서버 사이에 전송합니다" ;;
            *"curl "*|"wget "*) _kr_out="웹에서 파일 또는 응답을 가져옵니다" ;;
            *"mysql"*|"mariadb"*) _kr_out="MariaDB 또는 MySQL을 관리합니다" ;;
            *"vi "*|"vi2 "*|"vi3 "*|"vim "*|"nano "*) _kr_out="설정 파일을 편집합니다" ;;
            *"tail -f"*) _kr_out="로그를 실시간으로 봅니다" ;;
            *"cat "*|"less "*|"head "*) _kr_out="파일 내용을 확인합니다" ;;
            *"find "*) _kr_out="파일 또는 폴더를 찾습니다" ;;
            *"grep "*|*"cgrep"*) _kr_out="텍스트에서 조건에 맞는 내용을 찾습니다" ;;
            *"ls "*|"ls") _kr_out="파일과 폴더 목록을 봅니다" ;;
            *"mkdir "*) _kr_out="폴더를 만듭니다" ;;
            *"cp "*) _kr_out="파일을 복사합니다" ;;
            *"mv "*) _kr_out="파일을 이동하거나 이름을 바꿉니다" ;;
            *"rm "*) _kr_out="파일 또는 폴더를 삭제합니다" ;;
            *"chmod "*|*"chown "*|*"setfacl "*) _kr_out="파일 또는 폴더 권한을 설정합니다" ;;
            *"ip "*|"ifconfig"*|"nmcli"*) _kr_out="네트워크 설정과 상태를 확인합니다" ;;
            *"ping "*|"traceroute "*|"dig "*|"nslookup "*) _kr_out="네트워크 연결 또는 DNS를 확인합니다" ;;
            *"nmap "*) _kr_out="호스트의 네트워크 포트를 검사합니다" ;;
            *"reboot"*|"shutdown "*) _kr_out="시스템 전원을 제어합니다" ;;
            export\ *|[a-zA-Z_]*=*) _kr_out="변수 값을 설정하거나 준비합니다" ;;
            *)
                easy_name="${easy_cmd%%[[:space:];]*}"
                [ -z "$easy_name" ] && easy_name="$(ko '명령')"
                ko '%s 실행\n' "$easy_name"
                return
                ;;
        esac
        ko "${_kr_out}\n"
    else
        case "$easy_cmd" in
            *"systemctl status"*) echo "Check service status" ;;
            *"systemctl restart"*|*"systemctl try-reload-or-restart"*) echo "Restart service" ;;
            *"systemctl reload"*) echo "Reload service configuration" ;;
            *"systemctl enable"*) echo "Enable service at boot" ;;
            *"systemctl disable"*) echo "Disable service at boot" ;;
            *"systemctl start"*) echo "Start service" ;;
            *"systemctl stop"*) echo "Stop service" ;;
            *"journalctl"*) echo "Check system logs" ;;
            *"apt "*"install"*|*"apt-get "*"install"*|*"yum "*"install"*|*"dnf "*"install"*|"yyay "*) echo "Install packages" ;;
            *"apt "*"remove"*|*"yum "*"remove"*|*"dnf "*"remove"*) echo "Remove packages" ;;
            *"apt "*"update"*|*"apt "*"upgrade"*|*"yum "*"update"*|*"dnf "*"update"*) echo "Update packages or system" ;;
            *"docker-compose"*" up"*|*"docker compose"*" up"*) echo "Start Docker Compose services" ;;
            *"docker-compose"*" down"*|*"docker compose"*" down"*) echo "Stop Docker Compose services" ;;
            *"docker-compose"*" logs"*|*"docker compose"*" logs"*) echo "View Docker Compose logs" ;;
            *"docker "*" ps"*) echo "List Docker containers" ;;
            *"docker "*" start"*) echo "Start Docker container" ;;
            *"docker "*" stop"*) echo "Stop Docker container" ;;
            *"docker "*" rm"*) echo "Remove Docker container" ;;
            *"git clone"*) echo "Clone Git repository" ;;
            *"git pull"*) echo "Pull latest Git changes" ;;
            *"git push"*) echo "Push Git changes" ;;
            *"git status"*) echo "Check Git status" ;;
            *"git diff"*) echo "View Git changes" ;;
            *"certbot"*) echo "Issue or manage SSL certificate" ;;
            *"fail2ban-client unban --all"*) echo "Unban all IPs across all jails" ;;
            *"fail2ban-client unban"*) echo "Unban specified IP across all jails" ;;
            *"fail2ban-client set"*" unbanip"*) echo "Manually unban IP in selected jail" ;;
            *"fail2ban-client set"*" banip"*) echo "Manually ban IP in selected jail" ;;
            *"fail2ban-client status"*) echo "Check Fail2ban jail status and statistics" ;;
            *"firewall-cmd"*"--remove-rich-rule"*) echo "Remove firewalld rich-rule ban" ;;
            *"firewall-cmd"*"--list-rich-rules"*) echo "List firewalld rich-rules for banned IPs" ;;
            *"firewall-cmd"*) echo "Manage firewall rules" ;;
            *"pkill -kill -t"*|*"pkill"*"pts"*) echo "Disconnect specified terminal session (kick)" ;;
            *"pkill"*"sshd"*|*"kill"*"sshd"*) echo "Kill all SSH sessions from specified IP" ;;
            *"pkill "*|*"kill "*) echo "Kill running process" ;;
            *"w |"*|"w") echo "View logged-in sessions and connected users" ;;
            *"explorer /etc/fail2ban"*) echo "Explore Fail2ban configuration directory" ;;
            *"yyay fail2ban"*) echo "Install Fail2ban intrusion prevention package" ;;
            *"ufw "*) echo "Manage UFW firewall" ;;
            *"iptables"*) echo "Manage iptables firewall rules" ;;
            *"ssh "*|"ssh"*) echo "Connect to or run a command on a remote server" ;;
            *"scp "*|"rsync "*|"ncp "*|"ncpr "*) echo "Transfer files between servers" ;;
            *"curl "*|"wget "*) echo "Download a file or web response" ;;
            *"mysql"*|"mariadb"*) echo "Manage MariaDB or MySQL" ;;
            *"vi "*|"vi2 "*|"vi3 "*|"vim "*|"nano "*) echo "Edit configuration file" ;;
            *"tail -f"*) echo "Follow log output" ;;
            *"cat "*|"less "*|"head "*) echo "View file contents" ;;
            *"find "*) echo "Find files or folders" ;;
            *"grep "*|*"cgrep"*) echo "Search matching text" ;;
            *"ls "*|"ls") echo "List files and folders" ;;
            *"mkdir "*) echo "Create directory" ;;
            *"cp "*) echo "Copy files" ;;
            *"mv "*) echo "Move or rename files" ;;
            *"rm "*) echo "Remove files or folders" ;;
            *"chmod "*|*"chown "*|*"setfacl "*) echo "Set file or folder permissions" ;;
            *"ip "*|"ifconfig"*|"nmcli"*) echo "Check network settings and status" ;;
            *"ping "*|"traceroute "*|"dig "*|"nslookup "*) echo "Check network connection or DNS" ;;
            *"nmap "*) echo "Scan host network ports" ;;
            *"reboot"*|"shutdown "*) echo "Control system power" ;;
            export\ *|[a-zA-Z_]*=*) echo "Set or prepare variable values" ;;
            *)
                easy_name="${easy_cmd%%[[:space:];]*}"
                [ -z "$easy_name" ] && easy_name="Command"
                printf 'Run %s\n' "$easy_name"
                ;;
        esac
    fi
}

_easy_sync_badges() {
    local _key="${GOLANG}:${GOTERM_ENC:-utf8}"
    [ "${_EASY_B_KEY:-}" = "$_key" ] && return
    _EASY_B_KEY="$_key"
    if [ "$GOLANG" = "kr" ]; then
        _EASY_B_WARN="\x1b[1;31m$(ko '[위험]')\x1b[0m"
        _EASY_B_CHG="\x1b[1;33m$(ko '[변경]')\x1b[0m"
        _EASY_B_VIEW="\x1b[1;32m$(ko '[조회]')\x1b[0m"
    else
        _EASY_B_WARN="\x1b[1;31m[WARN]\x1b[0m"
        _EASY_B_CHG="\x1b[1;33m[CHG ]\x1b[0m"
        _EASY_B_VIEW="\x1b[1;32m[VIEW]\x1b[0m"
    fi
}

_cmd_kind_badge() {
    local _raw="$1" _body _tok _lbl
    _body="${_raw#!!!}"
    _body="${_body#"${_body%%[![:space:]]*}"}"
    case "$_body" in
        :[[:space:]]*\;*)
            _body="${_body#*;}"
            _body="${_body#;}"
            _body="${_body#"${_body%%[![:space:]]*}"}"
            ;;
    esac
    _body="${_body%"${_body##*[![:space:]]}"}"
    _tok="${_body%%[[:space:]]*}"
    [ -z "$_tok" ] && return 0
    if [ "$_tok" = "$_body" ] && st "$_tok" >/dev/null 2>&1; then
        [ "$GOLANG" = "kr" ] && _lbl="$(ko '[→메뉴]')" || _lbl='[→menu]'
        printf '\x1b[1;35m%s\x1b[0m' "$_lbl"
    elif declare -F "$_tok" >/dev/null 2>&1; then
        printf '\x1b[1;33m[fn]\x1b[0m'
    fi
}

render_item_easy() {
    local pi="$1"
    local c_cmd="$2"
    local hdesc="$3"
    local prev_comm="$4"
    local badge=""
    local title=""

    _easy_sync_badges

    # 1. 배지 결정 (Bash 2 내장 case 로 fork 없이 판별 - 줄 앞/중간 !!! 모두 감지)
    local _trim_cmd="${c_cmd#"${c_cmd%%[![:space:]]*}"}"
    if [ "${_trim_cmd:0:3}" = "!!!" ] || case "$c_cmd" in *" !!! "*|*" !!!"|*";!!!"*|*"; !!!"*) true ;; *) false ;; esac || [[ "$c_cmd" == *"unban --all"* ]] || { [[ "$c_cmd" == *"unban"* ]] && rx_match "$c_cmd" '(unban[[:space:]]+--all)'; }; then
        badge="$_EASY_B_WARN"
    else
        case "$c_cmd" in
            *install*|*apt*|*yum*|*dnf*|*"rm "*|*"rm	"*|*"systemctl restart"*|*reboot*|*"sed -i"*|*">>"*|*kill*|*pkill*|*unban*|*banip*)
                badge="$_EASY_B_CHG"
                ;;
            *)
                if [[ "$c_cmd" == *"systemctl"* ]] && rx_match "$c_cmd" 'systemctl[[:space:]]+restart'; then
                    badge="$_EASY_B_CHG"
                else
                    badge="$_EASY_B_VIEW"
                fi
                ;;
        esac
    fi

    # 2. 제목 결정 (4단 폴백 사다리) — Bash 2.05 호환: 큰따옴표 내부 ${var%%$'\n'*} 금지 -> 변수 $_nl 사용
    local _nl=$'\n'
    if [ -n "$hdesc" ]; then
        title="${hdesc%%$_nl*}"
    elif [ -n "$prev_comm" ] && [ "${#prev_comm}" -gt 2 ]; then
        title="$prev_comm"
    else
        case "$c_cmd" in
            :*";"*)
                title="${c_cmd#:}"
                title="${title%%;*}"
                title="${title#"${title%%[![:space:]]*}"}"
                title="${title%"${title##*[![:space:]]}"}"
                ;;
            *)
                title="$(easy_auto_title "$c_cmd")"
                ;;
        esac
    fi
    title="$(_strip_dup_num "$title")"

    # 3. 명령어 힌트 (쉬움 모드에서 실제 실행될 명령 요약 노출)
    local raw_hint="$c_cmd"
    raw_hint="${raw_hint#*!!!}"
    raw_hint="${raw_hint#"${raw_hint%%[![:space:]]*}"}"
    raw_hint="${raw_hint%"${raw_hint##*[![:space:]]}"}"
    case "$raw_hint" in
        :*";"*)
            raw_hint="${raw_hint#*;}"
            raw_hint="${raw_hint#"${raw_hint%%[![:space:]]*}"}"
            ;;
    esac
    if [ ${#raw_hint} -gt 55 ]; then
        raw_hint="${raw_hint:0:52}..."
    fi

    local _kbadge
    _kbadge="$(_cmd_kind_badge "$c_cmd")"
    if [ -n "$raw_hint" ] && [ "$raw_hint" != "$title" ]; then
        printf "\e[1m%-4s\e[0m %b %s \x1b[1;30m(%s)\x1b[0m%b\n" "${pi}" "$badge" "$title" "$raw_hint" "${_kbadge:+ $_kbadge}"
    else
        printf "\e[1m%-4s\e[0m %b %s%b\n" "${pi}" "$badge" "$title" "${_kbadge:+ $_kbadge}"
    fi
}

###############################################################
# [규칙] Bash 2 호환: [[ x =~ re ]] 는 Bash 3.0+ 전용 -> 파싱 단계에서 구문오류로 기동 불가
#   rx_match "문자열" "ERE"            : 일치하면 0 (grep -E)
#   rx_cap   "문자열" "BRE" 그룹번호    : sed 로 캡처 그룹 추출 (-E/-r 미사용: 구 sed 호환)
###############################################################
rx_match() { printf '%s\n' "$1" | grep -E -e "$2" >/dev/null 2>&1; }
rx_cap() { printf '%s\n' "$1" | sed -n "s@$2@\\$3@p" | sed -n '1p'; }

###############################################################
# 명령줄에서 미치환 var[A-Z]* 토큰만 안전하게 제거 (인터랙티브 실행용)
###############################################################
strip_cmd_vars() {
    local _s=" $1 " _next=""
    while :; do
        _next="$(printf '%s' "$_s" | sed \
            -e 's/[[:space:]]"var[A-Z][a-zA-Z0-9_.-]*__[a-zA-Z0-9_.@-]*"[[:space:]]/ /g' \
            -e 's/[[:space:]]"var[A-Z][a-zA-Z0-9_.-]*"[[:space:]]/ /g' \
            -e 's/[[:space:]]'\''var[A-Z][a-zA-Z0-9_.-]*__[a-zA-Z0-9_.@-]*'\''[[:space:]]/ /g' \
            -e 's/[[:space:]]'\''var[A-Z][a-zA-Z0-9_.-]*'\''[[:space:]]/ /g' \
            -e 's/[[:space:]]var[A-Z][a-zA-Z0-9_.-]*__[a-zA-Z0-9_.@-]*[[:space:]]/ /g' \
            -e 's/[[:space:]]var[A-Z][a-zA-Z0-9_.-]*[[:space:]]/ /g')"
        [ "$_next" = "$_s" ] && break
        _s="$_next"
    done
    printf '%s' "$_s" | sed -e 's/[[:space:]]\{1,\}/ /g' -e 's/^ //' -e 's/ $//'
}

###############################################################
# [#h] 쉬움 모드(Easy Mode) 번호 선택 시 확인 카드 (Card UI)
#   인수: $1 = 명령줄 원문
#         $2 = #h 설명 전체
#         $3 = 선택한 표시 번호 (예: 2)
#         $4 = 전체 표시 개수 (예: 8)
#   반환: 0 = 실행 승인
#         1 = 취소 (n 또는 ESC)
#         2 = 설정 편집 (e)
#         3 = 인자 없이 바로 실행 (i, var* 보유 일반 명령 한정)
###############################################################
show_cmd_card() {
    local cmd="$1"
    local desc="$2"
    local sel_num="${3:-1}"
    local total_num="${4:-1}"

    local is_danger=0
    local badge=""
    local title=""
    local body=""

    _easy_sync_badges

    # 위험 판단 (render_item_easy 와 동일 기준 유지 - 줄 앞/중간 !!! 모두 감지)
    if rx_match "$cmd" '(^|[[:space:];])!!!([[:space:]]|$)'; then
        is_danger=1
        cmd="$(printf '%s\n' "$cmd" | sed -e 's/^[[:space:]]*!!![[:space:]]*//' -e 's/\([[:space:];]\)!!![[:space:]]*/\1/g')"
        badge="$_EASY_B_WARN"
    elif rx_match "$cmd" '(unban[[:space:]]+--all)'; then
        is_danger=1
        badge="$_EASY_B_WARN"
    elif rx_match "$cmd" '(install|apt|yum|dnf|rm[[:space:]]|systemctl[[:space:]]+restart|reboot|sed[[:space:]]+-i|>>|kill|pkill|unban|banip)'; then
        badge="$_EASY_B_CHG"
    else
        badge="$_EASY_B_VIEW"
    fi

    # 제목 및 본문 분리
    if [ -n "$desc" ]; then
        title="$(echo "$desc" | head -n1)"
        body="$(echo "$desc" | sed '1d')"
    elif rx_match "$cmd" '^:[[:space:]]*([^;]+);'; then
        title="$(rx_cap "$cmd" '^:[[:space:]]*\([^;][^;]*\);.*' 1)"
        title="$(echo "$title" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        body=""
    else
        title="$(easy_auto_title "$cmd")"
        body=""
    fi
    title="$(_strip_dup_num "$title")"

    echo
    echo "======================================================================"
    printf " [%s/%s] %s   %b\n" "$sel_num" "$total_num" "$title" "$badge"
    echo "======================================================================"

    # 무엇을 하나요 (설명 섹션)
    if [ -n "$body" ]; then
        if [ "$GOLANG" = "kr" ]; then
            printf "\x1b[1;36m 무엇을 하나요\x1b[0m\n"
        else
            printf "\x1b[1;36m Description\x1b[0m\n"
        fi
        printf '%s\n' "$body" | sed -e 's/^/   /'
        echo
    elif [ -n "$title" ]; then
        if [ "$GOLANG" = "kr" ]; then
            printf "\x1b[1;36m 무엇을 하나요\x1b[0m\n"
        else
            printf "\x1b[1;36m Description\x1b[0m\n"
        fi
        printf "   %s\n\n" "$title"
    fi

    # 실행 시 물어보는 값 (변수 안내) — Bash 2 / 구 grep(2.4.x) 호환: grep -o 대신 awk match 루프 사용
    local vars=""
    vars="$(echo "$cmd" | awk '{ s=$0; while (match(s, /var[A-Z][a-zA-Z0-9_@-]*/)) { print substr(s, RSTART, RLENGTH); s=substr(s, RSTART+RLENGTH) } }' | sort -u)"
    if [ -n "$vars" ]; then
        if [ "$GOLANG" = "kr" ]; then
            printf "\x1b[1;35m 실행 시 물어보는 값 (변수)\x1b[0m\n"
        else
            printf "\x1b[1;35m Prompt Variables\x1b[0m\n"
        fi
        for v in $vars; do
            local v_clean="${v//@space@/ }"
            v_clean="${v_clean//@colon@/:}"
            v_clean="${v_clean//@dot@/.}"
            v_clean="${v_clean//@@//}"
            local vname="${v_clean%%__*}"
            vname="${vname#var}"
            local vopts="${v_clean#*__}"
            if [ "$vopts" != "$v_clean" ] && [ -n "$vopts" ]; then
                local vdef="${vopts%%__*}"
                printf "   \x1b[1;37m%-10s\x1b[0m 기본값: %s\n" "$vname" "$vdef"
            else
                printf "   \x1b[1;37m%-10s\x1b[0m\n" "$vname"
            fi
        done
        echo
    fi

    # 실제로 실행되는 명령 (cmd_unfold)
    local uq="$(cmd_unfold "$cmd")"
    local un=$(printf '%s\n' "$uq" | grep -cE '^  [0-9]+[)] ')
    if [ "${un:-0}" -gt 1 ]; then
        if [ "$GOLANG" = "kr" ]; then
            printf "\x1b[1;33m 실제로 실행되는 명령 (%s단계)\x1b[0m\n" "$un"
        else
            printf "\x1b[1;33m Commands to execute (%s steps)\x1b[0m\n" "$un"
        fi
        printf '%s\n' "$uq"
    else
        if [ "$GOLANG" = "kr" ]; then
            printf "\x1b[1;33m 실제로 실행되는 명령\x1b[0m\n"
        else
            printf "\x1b[1;33m Command to execute\x1b[0m\n"
        fi
        printf "   %s\n" "$cmd"
    fi
    echo "----------------------------------------------------------------------"

    # 사용자 확인 프롬프트
    local card_ans="" card_ans1=""
    if [ "$is_danger" -eq 1 ]; then
        if [ "$GOLANG" = "kr" ]; then
            menu_read " !! 위험한 명령입니다. 실행하려면 yes 를 입력하세요.    [n] 취소 : " card_ans card_ans1
        else
            menu_read " !! Dangerous command. Type yes to execute.    [n] Cancel : " card_ans card_ans1
        fi
        local rc=$?
        if [ $rc -eq 1 ] || { [ "$card_ans" != "yes" ] && [ "$card_ans" != "YES" ]; }; then
            echo " [취소됨]"
            return 1
        fi
        return 0
    else
        if [ -n "$vars" ]; then
            if [ "$GOLANG" = "kr" ]; then
                menu_read "$(ko " [Enter] 변수입력    [i] 인자없이 실행    [n] 취소    [e] 편집 : ")" card_ans card_ans1
            else
                menu_read " [Enter] Set vars    [i] Run w/o args    [n] Cancel    [e] Edit : " card_ans card_ans1
            fi
        else
            if [ "$GOLANG" = "kr" ]; then
                menu_read " [Enter] 실행    [n] 취소    [e] 편집(conf) : " card_ans card_ans1
            else
                menu_read " [Enter] Run    [n] Cancel    [e] Edit conf : " card_ans card_ans1
            fi
        fi
        local rc=$?
        if [ $rc -eq 1 ]; then
            echo " [취소됨]"
            return 1
        fi
        case "$card_ans" in
            "" | "y" | "Y")
                return 0
                ;;
            "i" | "I")
                if [ -n "$vars" ]; then
                    return 3
                fi
                echo " [취소됨]"
                return 1
                ;;
            "e" | "E")
                return 2
                ;;
            *)
                echo " [취소됨]"
                return 1
                ;;
        esac
    fi
}

###############################################################
# [mc.py 참조] 중복 번호([1], 1., [Step 1] 등) 제거 & 하단 실시간 상세 카드
###############################################################
# 구형 리눅스(Red Hat 7.2 등)에서 최신 TERM(xterm-256color 등) 접속 시 terminfo 미존재로
# tput lines / tput cols 가 실패(빈 문자열 반환)하여 24x120 으로 잘못 고정되는 문제 방지:
# 커널 PTY 크기(stty size </dev/tty)를 먼저 읽고, 실패 시 tput -> TERM=xterm tput 순으로 폴백한다.
_get_term_size() {
    _TS_LINES="${LINES:-}"
    _TS_COLS="${COLUMNS:-}"
    if [ -z "$_TS_LINES" ] || [ -z "$_TS_COLS" ]; then
        local _stty_sz=""
        _stty_sz="$(stty size </dev/tty 2>/dev/null)"
        if [ -n "$_stty_sz" ]; then
            local _sl="${_stty_sz%% *}" _sc="${_stty_sz#* }"
            case "$_sl" in [1-9][0-9]*) [ -z "$_TS_LINES" ] && _TS_LINES="$_sl" ;; esac
            case "$_sc" in [1-9][0-9]*) [ -z "$_TS_COLS" ] && _TS_COLS="$_sc" ;; esac
        fi
    fi
    [ -n "$_TS_LINES" ] || _TS_LINES="$(tput lines 2>/dev/null)"
    [ -n "$_TS_LINES" ] || _TS_LINES="$(TERM=xterm tput lines 2>/dev/null)"
    case "$_TS_LINES" in [1-9][0-9]*) ;; *) _TS_LINES=24 ;; esac
    [ -n "$_TS_COLS" ] || _TS_COLS="$(tput cols 2>/dev/null)"
    [ -n "$_TS_COLS" ] || _TS_COLS="$(TERM=xterm tput cols 2>/dev/null)"
    case "$_TS_COLS" in [1-9][0-9]*) ;; *) _TS_COLS=120 ;; esac
}

# 이전 화면을 스크롤백 버퍼 위로 완전히 밀어올린 뒤 현재 뷰포트 최상단(1,1)부터 깨끗하게 시작
# - 최신 clear 의 \033[3J(스크롤백 삭제)를 쓰지 않아 마우스 스크롤업으로 이전 메뉴/출력을 그대로 볼 수 있음
_clear_keep_scrollback() {
    local _TS_LINES="" _TS_COLS="" _tl _i=0 _nl_buf=""
    _get_term_size
    _tl="$_TS_LINES"
    while [ "$_i" -lt "$_tl" ]; do
        _nl_buf="${_nl_buf}"$'\n'
        _i=$((_i + 1))
    done
    printf '%s\033[H\033[2J' "$_nl_buf"
}

_strip_dup_num() {
    local _t="$1"
    _t="${_t#"${_t%%[![:space:]]*}"}"
    case "$_t" in
        "["[0-9]"]"*|"["[0-9][0-9]"]"*|"["[0-9]"-"[0-9]"]"*|"["[Ss]"tep "[0-9]"]"*)
            _t="${_t#*]}"
            _t="${_t#"${_t%%[![:space:]]*}"}"
            ;;
        [0-9]". "*|[0-9][0-9]". "*|[0-9]"-"[0-9]". "*)
            _t="${_t#*. }"
            _t="${_t#"${_t%%[![:space:]]*}"}"
            ;;
    esac
    printf '%s' "$_t"
}

# 다중 페이지 인디케이터 바 (하단 상세 카드 위 1줄 여백 활용, 폭 80칸 정렬)
#   인자: $1=need_scroll(0|1) $2=scroll_top $3=vp_h $4=total_flat
_render_page_bar() {
    local _ns="${1:-0}" _stop="${2:-0}" _vph="${3:-1}" _tot="${4:-0}"
    if [ "$_ns" -ne 1 ] || [ "$_vph" -le 0 ] || [ "$_tot" -le "$_vph" ]; then
        printf '\r\x1b[K\n'
        return 0
    fi
    local _tpg=$(( (_tot + _vph - 1) / _vph ))
    [ "$_tpg" -lt 2 ] && _tpg=2
    local _has_prev=0 _has_next=0
    [ "$_stop" -gt 0 ] && _has_prev=1
    [ $((_stop + _vph)) -lt "$_tot" ] && _has_next=1

    local _cpg=$(( _stop / _vph + 1 ))
    [ "$_has_prev" -eq 0 ] && _cpg=1
    [ "$_has_next" -eq 0 ] && _cpg=$_tpg
    [ "$_cpg" -lt 1 ] && _cpg=1
    [ "$_cpg" -gt "$_tpg" ] && _cpg=$_tpg

    local _la _ra _lstr _rstr
    if [ "${GOTERM_ENC:-}" = "euckr" ]; then
        _la=" <------"
        _ra="------> "
    else
        _la=" ◀──────"
        _ra="──────▶ "
    fi
    if [ "$_has_prev" -eq 1 ]; then
        _lstr="\x1b[1;33m${_la}\x1b[0m"
    else
        _lstr="        "
    fi
    if [ "$_has_next" -eq 1 ]; then
        _rstr="\x1b[1;33m${_ra}\x1b[0m"
    else
        _rstr="        "
    fi

    local _mid="[ ${_cpg} / ${_tpg} ]"
    local _rem=$(( 64 - ${#_mid} ))
    [ "$_rem" -lt 2 ] && _rem=2
    local _lpad=$(( _rem / 2 ))
    local _rpad=$(( _rem - _lpad ))
    printf '\r%b%*s\x1b[1;36m%s\x1b[0m%*s%b\x1b[K\n' "$_lstr" "$_lpad" "" "$_mid" "$_rpad" "" "$_rstr"
}

_render_cmd_detail_card() {
    local _sel="$1" _orig="$2" _tpg="${3:-1}" _cpg="${4:-1}" _max="${5:-1}"
    local _cmd="" _desc="" _title="" _body="" _badge="" _is_sub=0
    if [ -n "$_orig" ] && [ "$_orig" -ge 1 ] 2>/dev/null; then
        _cmd="${chosen_commands[$((_orig - 1))]}"
        _desc="${chosen_desc[$((_orig - 1))]-}"
    fi

    local _sline _icon _dot _arr _lr _tri
    if [ "${GOTERM_ENC:-}" = "euckr" ]; then
        _sline="--------------------------------------------------------------------------------"
        _icon="[*]"
        _dot="*"
        _arr="Up/Dn"
        _lr="L/R"
        _tri="$(ko '▶')"
    else
        _sline="────────────────────────────────────────────────────────────────────────────────"
        _icon="🔎"
        _dot="•"
        _arr="↑↓"
        _lr="←→"
        _tri="▶"
    fi

    if echo "$_cmd" | grep -q "submenu_"; then
        _is_sub=1
        if [ "$GOLANG" = "kr" ]; then
            _badge="\x1b[1;35m[${_tri} $(ko '서브메뉴')]\x1b[0m"
        else
            _badge="\x1b[1;35m[${_tri} SUBMENU]\x1b[0m"
        fi
    elif [ "${_cmd#!!!}" != "$_cmd" ]; then
        _badge="${_EASY_B_WARN:-\x1b[1;31m[WARN]\x1b[0m}"
    elif rx_match "$_cmd" '(unban[[:space:]]+--all)'; then
        _badge="${_EASY_B_WARN:-\x1b[1;31m[WARN]\x1b[0m}"
    elif rx_match "$_cmd" '(install|apt|yum|dnf|rm[[:space:]]|systemctl[[:space:]]+restart|reboot|sed[[:space:]]+-i|>>|kill|pkill|unban|banip)'; then
        _badge="${_EASY_B_CHG:-\x1b[1;33m[CHG]\x1b[0m}"
    else
        _badge="${_EASY_B_VIEW:-\x1b[1;32m[VIEW]\x1b[0m}"
    fi

    if [ -n "$_desc" ]; then
        _title="$(printf '%s' "$_desc" | head -n1)"
        _body="$(printf '%s' "$_desc" | sed -n '2p')"
    elif rx_match "$_cmd" '^:[[:space:]]*([^;]+);'; then
        _title="$(rx_cap "$_cmd" '^:[[:space:]]*\([^;][^;]*\);.*' 1)"
        _title="$(printf '%s' "$_title" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    else
        _title="$(easy_auto_title "$_cmd")"
    fi
    _title="$(_strip_dup_num "$_title")"
    [ -z "$_title" ] && _title="#$_sel"
    [ ${#_title} -gt 54 ] && _title="${_title:0:51}..."

    local _clean_cmd="$_cmd"
    _clean_cmd="${_clean_cmd#!!! }"
    _clean_cmd="${_clean_cmd#!!!}"
    _clean_cmd="${_clean_cmd//@space@/ }"
    _clean_cmd="${_clean_cmd//@colon@/:}"
    _clean_cmd="${_clean_cmd//@dot@/.}"
    _clean_cmd="${_clean_cmd//@@//}"
    if [ ${#_clean_cmd} -gt 66 ]; then
        _clean_cmd="${_clean_cmd:0:63}..."
    fi

    local _vars=""
    _vars="$(printf '%s' "$_cmd" | awk '{ s=$0; while (match(s, /var[A-Z][a-zA-Z0-9_@-]*/)) { v=substr(s, RSTART+3, RLENGTH-3); sub(/__.*/, "", v); if (!seen[v]++) out = out (out ? ", " : "") v; s=substr(s, RSTART+RLENGTH) } } END { print out }')"

    # 항상 고정 5줄 출력 (상단 1줄 페이지 바는 호출부에서 실시간 렌더링 -> 합계 6줄)
    printf "\r\x1b[38;5;110m%s\x1b[0m\x1b[K\n" "$_sline"
    if [ "$GOLANG" = "kr" ]; then
        ko "\r %s \x1b[1;33m선택된 항목 상세\x1b[0m  -  \x1b[1;37m[%s] %s\x1b[0m   %b\x1b[K\n" "$_icon" "$_sel" "$_title" "$_badge"
        if [ -n "$_body" ]; then
            [ ${#_body} -gt 64 ] && _body="${_body:0:61}..."
            ko "\r    \x1b[1;36m%s 설명 :\x1b[0m %s\x1b[K\n" "$_dot" "$_body"
        else
            ko "\r    \x1b[1;33m%s 명령 :\x1b[0m \x1b[37m%s\x1b[0m\x1b[K\n" "$_dot" "$_clean_cmd"
        fi
        if [ -n "$_vars" ]; then
            ko "\r    \x1b[1;35m%s 변수 :\x1b[0m %s\x1b[K\n" "$_dot" "$_vars"
        elif [ -n "$_body" ]; then
            ko "\r    \x1b[1;33m%s 명령 :\x1b[0m \x1b[37m%s\x1b[0m\x1b[K\n" "$_dot" "$_clean_cmd"
        elif [ "$_is_sub" -eq 1 ]; then
            ko "\r    \x1b[38;5;250m%s 안내 : Enter 를 누르면 하위 메뉴로 이동합니다.\x1b[0m\x1b[K\n" "$_dot"
        else
            ko "\r    \x1b[38;5;250m%s 안내 : 추가 변수 없음 (Enter 누르면 확인/실행)\x1b[0m\x1b[K\n" "$_dot"
        fi
        printf "\r\x1b[38;5;110m%s\x1b[0m\x1b[K\n" "$_sline"
    else
        printf "\r %s \x1b[1;33mSelected Item Detail\x1b[0m  -  \x1b[1;37m[%s] %s\x1b[0m   %b\x1b[K\n" "$_icon" "$_sel" "$_title" "$_badge"
        if [ -n "$_body" ]; then
            [ ${#_body} -gt 64 ] && _body="${_body:0:61}..."
            printf "\r    \x1b[1;36m%s Desc :\x1b[0m %s\x1b[K\n" "$_dot" "$_body"
        else
            printf "\r    \x1b[1;33m%s Cmd  :\x1b[0m \x1b[37m%s\x1b[0m\x1b[K\n" "$_dot" "$_clean_cmd"
        fi
        if [ -n "$_vars" ]; then
            printf "\r    \x1b[1;35m%s Vars :\x1b[0m %s\x1b[K\n" "$_dot" "$_vars"
        elif [ -n "$_body" ]; then
            printf "\r    \x1b[1;33m%s Cmd  :\x1b[0m \x1b[37m%s\x1b[0m\x1b[K\n" "$_dot" "$_clean_cmd"
        elif [ "$_is_sub" -eq 1 ]; then
            printf "\r    \x1b[38;5;250m%s Info : Press Enter to open submenu.\x1b[0m\x1b[K\n" "$_dot"
        else
            printf "\r    \x1b[38;5;250m%s Info : No prompt variables (Enter to run/confirm)\x1b[0m\x1b[K\n" "$_dot"
        fi
        printf "\r\x1b[38;5;110m%s\x1b[0m\x1b[K\n" "$_sline"
    fi
}

_render_main_detail_card() {
    local _sel="$1" _m_title="$2" _m_key="$3" _m_is_sub="${4:-0}" _max="${5:-1}"
    local _preview=""
    if [ -n "${_m_detail_cache[$_sel]-}" ]; then
        _preview="${_m_detail_cache[$_sel]}"
    elif [ -n "$_m_key" ] && [ -f "${env:-}" ]; then
        _preview="$(awk -v k="[$_m_key]" -v lang="${GOLANG:-kr}" '
            index($0, k) > 0 && /^%%%/ { found=1; next }
            found && /^%%%/ { exit }
            found && /^$/ { exit }
            found && lang=="kr" && /^#h / {
                s=$0; sub(/^#h /, "", s);
                if (!seen++) out=s;
                next
            }
            found && lang!="kr" && /^#he / {
                s=$0; sub(/^#he /, "", s);
                if (!seen++) out=s;
                next
            }
            found && /^: / {
                s=$0; sub(/^: /, "", s); sub(/;.*/, "", s);
                cmds = cmds (cmds ? " / " : "") s;
                if (++ccnt >= 3 && out != "") exit;
                next
            }
            found && /^# / && $0 !~ /^# [-─━═]/ {
                s=$0; sub(/^# /, "", s);
                if (cmnt == "") cmnt=s;
                next
            }
            found && $0 !~ /^[#%]/ && $0 !~ /^[[:space:]]*$/ {
                s=$0; sub(/^!!! /, "", s); sub(/[[:space:]].*/, "", s);
                if (rawc == "") rawc=s;
            }
            END {
                if (out != "") print out;
                else if (cmds != "") print cmds;
                else if (cmnt != "") print cmnt;
                else if (rawc != "") print rawc;
            }
        ' "$env" 2>/dev/null)"
        _preview="$(_strip_dup_num "$_preview")"
        [ -z "$_preview" ] && _preview="-"
        _m_detail_cache[$_sel]="$_preview"
    fi
    [ "$_preview" = "-" ] && _preview=""
    [ ${#_preview} -gt 66 ] && _preview="${_preview:0:63}..."

    local _sline _icon _dot _arr _tri _dia
    if [ "${GOTERM_ENC:-}" = "euckr" ]; then
        _sline="--------------------------------------------------------------------------------"
        _icon="[*]"
        _dot="*"
        _arr="Up/Dn"
        _tri="$(ko '▶')"
        _dia="$(ko '◈')"
    else
        _sline="────────────────────────────────────────────────────────────────────────────────"
        _icon="🔎"
        _dot="•"
        _arr="↑↓"
        _tri="▶"
        _dia="◈"
    fi

    local _clean_title="$_m_title"
    _clean_title="$(printf '%s' "$_clean_title" | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/^[[:space:]]*>//')"
    _clean_title="$(_strip_dup_num "$_clean_title")"
    [ ${#_clean_title} -gt 50 ] && _clean_title="${_clean_title:0:47}..."

    local _badge=""
    if [ "$_m_is_sub" -eq 1 ]; then
        if [ "$GOLANG" = "kr" ]; then
            _badge="\x1b[1;35m[${_tri} $(ko '서브메뉴')]\x1b[0m"
        else
            _badge="\x1b[1;35m[${_tri} SUBMENU]\x1b[0m"
        fi
    else
        if [ "$GOLANG" = "kr" ]; then
            _badge="\x1b[1;32m[${_dia} $(ko '명령어 모음')]\x1b[0m"
        else
            _badge="\x1b[1;32m[${_dia} COMMANDS]\x1b[0m"
        fi
    fi

    # 항상 고정 5줄 출력 (상단 1줄 페이지 바는 호출부에서 실시간 렌더링 -> 합계 6줄)
    printf "\r\x1b[38;5;110m%s\x1b[0m\x1b[K\n" "$_sline"
    if [ "$GOLANG" = "kr" ]; then
        ko "\r %s \x1b[1;33m선택된 메뉴 상세\x1b[0m  -  \x1b[1;37m[%s] %s\x1b[0m   %b\x1b[K\n" "$_icon" "$_sel" "$_clean_title" "$_badge"
        if [ -n "$_m_key" ]; then
            ko "\r    \x1b[1;36m%s 단축키 :\x1b[0m [%s]  \x1b[38;5;250m(프롬프트에 바로 입력 가능)\x1b[0m\x1b[K\n" "$_dot" "$_m_key"
        else
            ko "\r    \x1b[1;36m%s 번호   :\x1b[0m %s번 항목\x1b[K\n" "$_dot" "$_sel"
        fi
        if [ -n "$_preview" ]; then
            ko "\r    \x1b[1;33m%s 미리보기 :\x1b[0m %s\x1b[K\n" "$_dot" "$_preview"
        else
            ko "\r    \x1b[38;5;250m%s 안내   : Enter 를 누르면 해당 메뉴로 이동합니다.\x1b[0m\x1b[K\n" "$_dot"
        fi
        printf "\r\x1b[38;5;110m%s\x1b[0m\x1b[K\n" "$_sline"
    else
        printf "\r %s \x1b[1;33mSelected Menu Detail\x1b[0m  -  \x1b[1;37m[%s] %s\x1b[0m   %b\x1b[K\n" "$_icon" "$_sel" "$_clean_title" "$_badge"
        if [ -n "$_m_key" ]; then
            printf "\r    \x1b[1;36m%s Shortcut :\x1b[0m [%s]  \x1b[38;5;250m(Type directly at prompt)\x1b[0m\x1b[K\n" "$_dot" "$_m_key"
        else
            printf "\r    \x1b[1;36m%s Index    :\x1b[0m #%s\x1b[K\n" "$_dot" "$_sel"
        fi
        if [ -n "$_preview" ]; then
            printf "\r    \x1b[1;33m%s Preview  :\x1b[0m %s\x1b[K\n" "$_dot" "$_preview"
        else
            printf "\r    \x1b[38;5;250m%s Info     : Press Enter to open this menu.\x1b[0m\x1b[K\n" "$_dot"
        fi
        printf "\r\x1b[38;5;110m%s\x1b[0m\x1b[K\n" "$_sline"
    fi
}

###############################################################
# 메인 서비스 함수 menufunc
###############################################################
declare -a shortcutarr shortcutstr
# exec go.sh shortcut // or menufunc {submenu_sys} 제목 or menufunc {} 제목 choice

menufunc() {
    #scutp
    #set -x
    # 초기 메뉴는 인수없음, 인수 있을경우 서브 메뉴진입
    # $1 $2 가 동시에 인수로 들어와야 작동
    # $1 $2 $3 가 들어오면 $3(명령줄) 종속 메뉴로 바로 이동
    readxx "$LINENO menufunc start input_value_input1:/$1/ input2:/$2/ input3:/$3/"
    #readxy "$LINENO menufunc start input_value_input1:/$1/ input2:/$2/ input3:/$3/"
    #readxy "$newscut"
    local chosen_command_sub="$1" # ex) {submenu_lamp} or {}
    local title_of_menu_sub="$2"  # ex) debian lamp set flow
    local title_of_menu="$2"      # ex) debian lamp set flow
    local title="$2"              # ex) debian lamp set flow
    # 진입 컨텍스트 스냅샷 (이후 chosen_command_sub/title_of_menu_sub 이 변형되므로 별도 보관)
    local NAVENTRY_sub="$1" NAVENTRY_title="$2"
    declare -a keysarr idx_mapping
    readxx "$LINENO // choice:$choice // title_of_menu:$title_of_menu // chosen_command_sub:$chosen_command_sub // title:$title"
    #readxy "$LINENO // $choice // $title_of_menu // $chosen_command_sub // $title"

    [ -n "$3" ] && local initvar="$3" # ex) 2 or scut
    [ -z "$2" ] && [ -n "$1" ] && local initvar="$1"
    #[ "$1" == "{}" ] && local initvar="" # choice 가 불필요한경우 relaymenu mainmenu
    local choiceloop=0
    #pre_commands=()
    # 히스토리 파일 정의하고 불러옴
    HISTFILE="$gotmp/go_history.txt"
    #history -r "$HISTFILE"

    # 화면 진입 이력 동기화 (이전 화면은 스택에 보관)
    nav_sync "$NAVENTRY_sub" "$NAVENTRY_title"

    # [I] 색인 검색으로 진입한 1회만 검색어 하이라이트 유지, 일반 이동 시 자동 해제
    if [ "${_IDX_HILITE_ARMED:-0}" = "1" ]; then
        _IDX_HILITE_ARMED=0
    else
        _IDX_HILITE_KW=""
    fi

    # 탈출코드 또는 ctrlc 가 입력되지 않는 경우 루프 loop
    ############### main loop ###################
    ############### main loop ###################
    ############### main loop ###################
    while true; do # choice loop
        oldchoice="$choice"
        choice=""
        choice1="" # 이전 입력의 두번째 단어가 남으면 단축키/바로가기 판정이 꼬임
        nav_shortcut_hit="" # 바로가기 해석 여부 (99 내부값 통과용)
        unset -v skipmain
        #[[ -n "$cmd_choice" && -z "$choice" ]] && choice="$cmd_choice" || choice=""
        cmd_choice=""

        if [ "$initvar" ]; then
            # readxy "initvar ok"
            # 최초 실행시 특정 메뉴 shortcut 가져옴 ex) bash go.sh px
            choice="$initvar" && initvar=""
            # relay 메뉴가 아니면 main page skip
            [ -z "$title_of_menu_sub" ] && { skipmain="y" && chosen_command_sub="$(scutsub "$choice")" && title_of_menu_sub="$(scuttitle "$choice")"; } || unset -v skipmain
            #[ -z "$title_of_menu_sub" ] && { skipmain="y" && chosen_command_sub="$(scutsub "$command")" && title_of_menu_sub="$(scuttitle "$command")"; } || unset -v skipmain
            [ -n "$(notscutrelay "$choice")" ] && skipmain="y" #&& readxy skipmain2
            #[ -z "$title_of_menu_sub" ] && { skipmain="y" && readxy skipmain && chosen_command_sub="$(scutsub "$command")" && title_of_menu_sub="$(scuttitle "$command")"; } || unset -v skipmain
            #[ -z "$title_of_menu_sub" ] && skipmain="y" || unset -v skipmain # && readxy "only initvar enter"
        fi

        choiceloop=$((choiceloop + 1))

        # 서브메뉴 타이틀 변경
        [ "$title_of_menu_sub" ] && {
            # 서브메뉴
            scut=$(echo "$title_of_menu_sub" | awk -F'[][]' '{print $2}')
            readxx $LINENO scutset scut: $scut
            title="\x1b[1;37;45m $title_of_menu_sub \x1b[0m"
        } || {
            # 메인메뉴
            scut="m"
            title="\x1b[1;33;44m Main Menu \x1b[0m Load: $(loadvar)// $(free -m | awk 'NR==2 { printf("FreeMem: %d/%d\n", $4, $2) }')"
        }
        updatescut() {
            [ "$scut" ] && {
                #[ "$scut" ] && [ "$scut" != "m" ] && {
                [ "$scut" != "$oldscut" ] && toldscut=$oldscut && export oldscut="$scut" &&
                    [ "$toldscut" != "$ooldscut" ] && tooldscut=$ooldscut && export ooldscut="$toldscut" &&
                    [ "$tooldscut" != "$oooldscut" ] && toooldscut=$ooldscut && export oooldscut="$tooldscut" &&
                    [ "$toooldscut" != "$ooooldscut" ] && toooldscut=$ooldscut && export ooooldscut="$toooldscut"
                #[ "$scut" != "m" ] && [ "$scut" != "$oldscut" ] && toldscut=$oldscut && export oldscut="$scut" && \
                #[ "$oldscut" != "m" ] && [ "$toldscut" != "$ooldscut" ] && tooldscut=$ooldscut && export ooldscut="$toldscut" && \
                #[ "$ooldscut" != "m" ] && [ "$tooldscut" != "$oooldscut" ] && toooldscut=$ooldscut && export oooldscut="$tooldscut" && \
                #[ "$oooldscut" != "m" ] && [ "$toooldscut" != "$ooooldscut" ] && toooldscut=$ooldscut && export ooooldscut="$toooldscut"
            }
            #flow="$oooldscut>$ooldscut>$oldscut>$scut"
            flow="$oooldscut>$ooldscut>$oldscut"
        }
        updatescut

        # 메인메뉴에서 서브 메뉴의 shortcut 도 사용할수 있도록 기능개선
        # 쇼트컷 배열생성
        readxx "$LINENO // $choice // $title_of_menu // $chosen_command_sub // $title"
        if [ ${#shortcutarr[@]} -eq 0 ]; then

            readxx $LINENO shortcutarr.count.0: "${#shortcutarr[@]} 값없음체크"
            # 모든 shortcut 배열로 가져옴 shortcutarr array
            # 연계메뉴의 불러올 하부메뉴 포함되도록 개선 awk
            # IFS=$'\n' allof_shortcut_item="$(cat "$env" | grep "%%% " | grep -E '\[.+\]')"
            # i@@@%%% 시스템 초기설정과 기타 [i] -----> i@@@%%% 시스템 초기설정과 기타 [i]@@@{submenu_sys}
            # shortcut 있는 항목만 배열화
            IFS=$'\n' allof_shortcut_item="$(cat "$env" | grep -E "^%%%|^\{submenu.*" | awk '/^%%%/ {if (prev) print prev; prev = $0; next} /^{submenu_/ {print prev "@@@" $0; prev = ""; next} {if (prev) print prev; print $0; prev = ""} END {if (prev) print prev}' | grep -E '\[.+\]')"

            # 바로가기 버튼 중복 체크
            #scut_dups=$(echo "$allof_shortcut_item" | grep -o '\[[^]]\+\]' | sort | uniq -d | sed 's/^\[//;s/\]$//')
            scut_dups=$(echo "$allof_shortcut_item" | sed -n 's/.*\[\([^]]\+\)\].*/\1/p' | sort | uniq -d)
            # [L] 언어토글 키는 대문자를 쓴다.
            # scut 매칭은 case-sensitive 라 [l] 과 [L] 은 중복으로 안 잡히지만,
            # 사용자가 [L] 을 직접 정의하면 [L] 이 언어토글에 가로채여 그 메뉴로 못 들어간다.
            # 그래서 대소문자 무시 충돌도 같이 경고한다.
            scut_dups_ci=$(echo "$allof_shortcut_item" | sed -n 's/.*\[\([^]]\+\)\].*/\1/p' | tr 'A-Z' 'a-z' | sort | uniq -d)
            for scut in $(echo "$scut_dups_ci" | grep -v "^$" | sort -u); do
                [ -n "$(echo "$scut_dups" | grep -ix "$scut")" ] && continue
                echo -e "\n\033[1;33m⚠️ 대소문자만 다른 scut 충돌 감지 : [$scut] vs [$(echo "$scut" | tr 'a-z' 'A-Z')]\033[0m"
                echo -e "   \033[1;33m대문자 [L] 은 '한글/English 언어전환' 전용키다. 충돌을 피하려면 소문자로 바꾸세요.\033[0m"
                grep -n "\[$(echo "$scut" | tr 'a-z' 'A-Z')\]\|\[$scut\]" "$env" | head -5 | sed 's/^/   > /'
            done

            for scut in $scut_dups; do
                echo -e "\n\033[1;31m⚠️ 중복된 scut 감지: [$scut]\033[0m"
                grep -n "\[$scut\]" "$env" | awk 'NR==1 { print "\033[1;32m✅ 첫 번째 항목 (유지):\033[0m\n  ▶ " $0; next } { print "\033[1;33m⚠️ 중복 항목:\033[0m\n  ✂  " $0 }'
                # while
                grep -n "\[$scut\]" "$env" | tail -n +2 | while IFS=":" read lineno line; do
                    echo

                    if readxy "라인 $lineno: 이 항목을 수정할래?"; then
                        read -p "새로운 scut 입력 (예: ssl_alt): " newscut </dev/tty
                        if [ -n "$newscut" ]; then
                            sed -i "${lineno}s/\[$scut\]/\[$newscut\]/" "$env"
                            echo -e "\033[1;32m✅ [$newscut] 으로 변경 완료 (라인 $lineno)\033[0m"
                        fi
                    else
                        echo "⏩ 이 항목은 건너뜁니다."
                    fi

                done
            done

            #echo "$allof_shortcut_item"

            # 배열 생성만 분리된 함수로 위임 (언어 전환 후 캐시 재생성에서도 같은 로직 사용)
            build_shortcutarr
        fi

        # choice 가 없을때 선택할수 있는 메뉴 출력

        ############## 메뉴 출력 ###############

        [ -z "$debug" ] && [ -z "$noclear" ] && {
            _clear_keep_scrollback
            unset noclear
        }
        local _m_nav_cur=1 _m_nav_moved=0
        local -a _m_disp_lines _m_disp_nums _m_item_titles _m_item_keys _m_item_is_sub _m_detail_cache
        local _m_hdr_buf="" _m_pre_out=""
        _m_disp_lines=()
        _m_disp_nums=()
        _m_item_titles=()
        _m_item_keys=()
        _m_item_is_sub=()
        _m_detail_cache=()

        if [ -z "$skipmain" ]; then
            local _m_dline _m_hline
            if [ "${GOTERM_ENC:-}" = "euckr" ]; then
                _m_dline="================================================================================"
                _m_hline="--------------------------------------------------------------------------------"
            else
                _m_dline="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                _m_hline="────────────────────────────────────────────────────────────────────────────────"
            fi
            _m_hdr_buf="$(printf '\x1b[38;5;75m%s\x1b[0m :%s\n' "$_m_dline" "$choiceloop")"$'\n'
            _m_hdr_buf="${_m_hdr_buf}$(echo -e "* $title $flow")"$'\n'
            _m_hdr_buf="${_m_hdr_buf}$(printf '\x1b[38;5;110m%s\x1b[0m\n' "$_m_hline")"$'\n'
            if [ ! "$title_of_menu_sub" ]; then
                local _os_name _host_str _net_bar=""
                _os_name="$(grep "PRETTY_NAME" /etc/*-release 2>/dev/null | awk -F'"' '{print $2}')"
                [ -z "$_os_name" ] && _os_name="$(cat /etc/*-release 2>/dev/null | sort -u)"
                _host_str="$(printf '\x1b[1;37m%s\x1b[0m' "$(hostname)")"
                if [ "$offline" == "offline" ]; then
                    _net_bar="  \x1b[1;31m[offline]\x1b[0m"
                fi
                _m_hdr_buf="${_m_hdr_buf}$(printf '  %s - %b%b\n\x1b[38;5;110m%s\x1b[0m\n' "$_os_name" "$_host_str" "$_net_bar" "$_m_hline")"$'\n'
            else
                # %% cmds -> pre_commands 검출및 실행 (submenu 일때만, 1회 캡처 캐싱 + 중복 구분선 제거)
                if [ ${#pre_commands[@]} -gt 0 ]; then
                    local _pc_raw="" _pc_item
                    for _pc_item in "${pre_commands[@]}"; do
                        readxx "$LINENO // $choice // $title_of_menu // $chosen_command_sub // $title"
                        _pc_raw="${_pc_raw}$(eval "${_pc_item#%% }" | sed 's/^[[:space:]]*/  /g')"$'\n'
                    done
                    _pc_raw="$(printf '%s' "$_pc_raw" | sed -e '/^[[:space:]]*\(\x1b\[[0-9;]*m\)*\(====*\|────*\|━━━━*\).*$/d')"
                    if [ -n "$_pc_raw" ]; then
                        if printf '%s' "$_pc_raw" | grep -qE '0m'; then
                            _m_pre_out="${_pc_raw}"$'\n'"$(printf '\x1b[38;5;110m%s\x1b[0m\n' "$_m_hline")"
                        else
                            _m_pre_out="$(printf '\x1b[0;36m%s\x1b[0m\n\x1b[38;5;110m%s\x1b[0m\n' "$_pc_raw" "$_m_hline")"
                        fi
                    fi
                fi
            fi
            local items
            menu_idx=0
            shortcut_idx=0
            # 이전 화면에서 모은 단축키가 남아있으면 다른 화면의 번호로 점프하므로 초기화
            keysarr=()
            idx_mapping=()

            readxx "$LINENO // $choice // $title_of_menu // $chosen_command_sub // $title"
            # 메인 메뉴 아이콘 배지 사전 변환 (EUC-KR 터미널에서 UTF-8 3바이트 '? ?' 깨짐 방지, 루프당 iconv 0회)
            local _mb_star _mb_tri _mb_dia
            if [ "${GOTERM_ENC:-}" = "euckr" ]; then
                _mb_star="$(ko '★')"
                _mb_tri="$(ko '▶')"
                _mb_dia="$(ko '◈')"
            else
                _mb_star="★"
                _mb_tri="▶"
                _mb_dia="◈"
            fi
            # 메인 or 서브 메뉴 리스트 구성 loop
            while read line; do
                #set +x
                menu_idx=$((menu_idx + 1))
                items=$(echo "$line" | sed -e 's/%%% //' -e 's/%% //')

                # shortcut array keysarr make
                # 노출된 메뉴 shortcut 생성 -> 번호와 연결
                key=$(echo "$items" | awk 'match($0, /\[([^]]+)\]/) {print substr($0, RSTART + 1, RLENGTH - 2)}')
                [ "$key" ] && {
                    keysarr[$shortcut_idx]="$key"
                    idx_mapping[$shortcut_idx]=$menu_idx
                    ((shortcut_idx++))
                }

                # 메인 메뉴일 때 (title_of_menu_sub 가 비어있을 때) 5대 테마 구분선 + 섹션 간 여백 삽입
                if [ -z "$title_of_menu_sub" ]; then
                    local _ghdr=""
                    if [ "$menu_idx" -eq 1 ]; then
                        [ "$GOLANG" = "kr" ] && _ghdr="───【 ◈ 시스템 & 프로세스 & 로그 】─────────────────────────────" || _ghdr="--- [ System, Process & Logs ] --------------------------------"
                    elif [ "$menu_idx" -eq 6 ]; then
                        [ "$GOLANG" = "kr" ] && _ghdr="───【 ◈ 네트워크 & 보안 & 기본 설정 】─────────────────────────" || _ghdr="--- [ Network, Security & System Setup ] ----------------------"
                    elif [ "$menu_idx" -eq 9 ]; then
                        [ "$GOLANG" = "kr" ] && _ghdr="───【 ◈ 스토리지 & 클라우드 & 원격 터미널 】─────────────────────" || _ghdr="--- [ Storage, Cloud & Remote Terminal ] ----------------------"
                    elif [ "$menu_idx" -eq 13 ]; then
                        [ "$GOLANG" = "kr" ] && _ghdr="───【 ◈ 웹서버 & 가상화 & 컨테이너 (LAMP/Docker) 】─────────────" || _ghdr="--- [ Web, Virtualization & Containers (LAMP/Docker) ] --------"
                    elif [ "$menu_idx" -eq 19 ]; then
                        [ "$GOLANG" = "kr" ] && _ghdr="───【 ◈ BYUS 자체제작 앱 & 알림 / 도움말 】─────────────────────" || _ghdr="--- [ BYUS Custom Apps, Alerts & Help ] -----------------------"
                    fi
                    if [ -n "$_ghdr" ]; then
                        if [ "$menu_idx" -gt 1 ]; then
                            _m_disp_lines[${#_m_disp_lines[@]}]=""
                            _m_disp_nums[${#_m_disp_nums[@]}]=""
                        fi
                        _m_disp_lines[${#_m_disp_lines[@]}]=" $(ko "\033[1;36m${_ghdr}\033[0m")"
                        _m_disp_nums[${#_m_disp_nums[@]}]=""
                    fi
                else
                    # 서브메뉴일 때 제목 앞 중복 번호(예: BYUS 1. / 1단계: 등) 정리
                    items="$(_strip_dup_num "$items")"
                    items="$(printf '%s' "$items" | sed -e 's/^BYUS [0-9][0-9]*\.[[:space:]]*/BYUS /')"
                fi

                # 서브메뉴(>) 여부 판별 및 메인 메뉴 아이콘 배지 결정
                local _badge="" _is_sub_flag=0
                if [ -z "$title_of_menu_sub" ]; then
                    if [ "$key" = "apps" ]; then
                        _badge="\x1b[1;33m${_mb_star}\x1b[0m"
                        _is_sub_flag=1
                        items="$(echo "$items" | sed -e 's/^[[:space:]]*>//')"
                    else
                        local _t_it="${items#"${items%%[![:space:]]*}"}"
                        local _t_ln="${line#"${line%%[![:space:]]*}"}"
                        if [ "${_t_it:0:1}" = ">" ] || { [ "${_t_ln:0:3}" = "%%%" ] && [[ "${_t_ln#%%%}" == "${_t_ln#%%%[![:space:]]*}>"* || "${_t_ln:3:1}" = ">" ]]; }; then
                            _badge="\x1b[1;31m${_mb_tri}\x1b[0m"
                            _is_sub_flag=1
                            items="$(echo "$items" | sed -e 's/^[[:space:]]*>//')"
                        elif rx_match "$line" '^[[:space:]]*%%%[[:space:]]*>'; then
                            _badge="\x1b[1;31m${_mb_tri}\x1b[0m"
                            _is_sub_flag=1
                            items="$(echo "$items" | sed -e 's/^[[:space:]]*>//')"
                        else
                            _badge="\x1b[1;32m${_mb_dia}\x1b[0m"
                        fi
                    fi
                else
                    if printf '%s' "$items" | grep -q '>'; then
                        _is_sub_flag=1
                    fi
                fi

                items=$(echo -e "$(echo "$items" | sed -e 's/^>/\o033[1;31m>\o033[0m/g' -e "s/\(.*\[$ooldscut\].*\)$/\o033[1;37m>\1\o033[0m/")")
                _m_item_titles[$menu_idx]="$items"
                _m_item_keys[$menu_idx]="$key"
                _m_item_is_sub[$menu_idx]="$_is_sub_flag"

                if [ -z "$title_of_menu_sub" ]; then
                    _m_disp_lines[${#_m_disp_lines[@]}]="$(printf "\e[1m%-3s\e[0m ${_badge} ${items}" ${menu_idx}.)"
                else
                    _m_disp_lines[${#_m_disp_lines[@]}]="$(printf "\e[1m%-3s\e[0m ${items}" ${menu_idx}.)"
                fi
                _m_disp_nums[${#_m_disp_nums[@]}]="$menu_idx"
            done < <(print_menulist) # %%% 모음 가져와서 파싱

            # 0 / q 종료 기능은 입력 핸들러에서 그대로 유지 (화면 2줄 절약을 위해 0. Exit [q] 표시 생략)

            local _TS_LINES="" _TS_COLS="" _m_painted=0 _m_peeked=0 _m_term_lines _m_term_cols
            _get_term_size
            _m_term_lines="$_TS_LINES"
            _m_term_cols="$_TS_COLS"

            local -a _m_flat_lines _m_flat_nums _m_item_start _m_item_end _m_card_cache
            _m_flat_lines=()
            _m_flat_nums=()
            _m_item_start=()
            _m_item_end=()
            _m_card_cache=()
            local _mdi _mdl _mdn _mline _mis_first _mfi _mnl=$'\n'
            for ((_mdi = 0; _mdi < ${#_m_disp_lines[@]}; _mdi++)); do
                _mdl="${_m_disp_lines[$_mdi]}"
                _mdn="${_m_disp_nums[$_mdi]}"
                if [ -z "$_mdl" ]; then
                    _mfi=${#_m_flat_lines[@]}
                    _m_flat_lines[$_mfi]=""
                    _m_flat_nums[$_mfi]=""
                    continue
                fi
                _mis_first=1
                while [ -n "$_mdl" ]; do
                    case "$_mdl" in
                        *"$_mnl"*)
                            _mline="${_mdl%%$_mnl*}"
                            _mdl="${_mdl#*$_mnl}"
                            ;;
                        *)
                            _mline="$_mdl"
                            _mdl=""
                            ;;
                    esac
                    _mfi=${#_m_flat_lines[@]}
                    _m_flat_lines[$_mfi]="$_mline"
                    if [ -n "$_mdn" ] && [ "$_mis_first" -eq 1 ]; then
                        _m_flat_nums[$_mfi]="$_mdn"
                        _m_item_start[$_mdn]=$_mfi
                        _m_item_end[$_mdn]=$_mfi
                        _mis_first=0
                    else
                        _m_flat_nums[$_mfi]=""
                        [ -n "$_mdn" ] && _m_item_end[$_mdn]=$_mfi
                    fi
                done
            done

            local _m_top_lines=5 _m_vp_h _m_total_flat=${#_m_flat_lines[@]}
            [ -n "$title_of_menu_sub" ] && _m_top_lines=4
            if [ -n "$_m_pre_out" ]; then
                local _m_pre_cnt
                _m_pre_cnt="$(printf '%s\n' "$_m_pre_out" | awk -v cols="$_m_term_cols" '{ gsub(/\033\[[0-9;]*[a-zA-Z]/, ""); l=length($0); c += (l > cols && cols > 0) ? int((l - 1) / cols) + 1 : 1 } END { print c+0 }')"
                _m_top_lines=$((_m_top_lines + _m_pre_cnt))
            fi
            _m_vp_h=$((_m_term_lines - _m_top_lines - 7))
            [ "$_m_vp_h" -lt 5 ] && _m_vp_h=5

            local _m_need_scroll=0 _m_scroll_top=0 _m_max_scroll=0
            [ "$_m_total_flat" -gt "$_m_vp_h" ] && _m_need_scroll=1
            _m_max_scroll=$((_m_total_flat - _m_vp_h))
            [ "$_m_max_scroll" -lt 0 ] && _m_max_scroll=0

            _m_ensure_visible() {
                [ "$_m_need_scroll" -eq 0 ] && return
                local _cs="${_m_item_start[$_m_nav_cur]:-0}"
                local _ce="${_m_item_end[$_m_nav_cur]:-$_cs}"
                if [ "$_cs" -lt "$_m_scroll_top" ]; then
                    _m_scroll_top="$_cs"
                    [ "$_m_scroll_top" -lt 0 ] && _m_scroll_top=0
                elif [ "$_ce" -ge $((_m_scroll_top + _m_vp_h)) ]; then
                    _m_scroll_top=$((_ce - _m_vp_h + 1))
                    [ "$_m_scroll_top" -gt "$_m_max_scroll" ] && _m_scroll_top=$_m_max_scroll
                    [ "$_m_scroll_top" -lt 0 ] && _m_scroll_top=0
                fi
            }

            _m_pick_in_view() {
                local _vi _ve=$((_m_scroll_top + _m_vp_h))
                [ "$_ve" -gt "$_m_total_flat" ] && _ve="$_m_total_flat"
                for ((_vi = _m_scroll_top; _vi < _ve; _vi++)); do
                    if [ -n "${_m_flat_nums[$_vi]}" ]; then
                        _m_nav_cur="${_m_flat_nums[$_vi]}"
                        return 0
                    fi
                done
                for ((_vi = _m_scroll_top - 1; _vi >= 0; _vi--)); do
                    if [ -n "${_m_flat_nums[$_vi]}" ]; then
                        _m_nav_cur="${_m_flat_nums[$_vi]}"
                        return 0
                    fi
                done
            }

            _m_render_screen() {
                local _do_home="${1:-0}" _di _dn _dl _pfx _s_idx _e_idx _vp_drawn=0 _card_only=0 _fbuf=""
                local _cr=$'\r' _nl=$'\n' _el=$'\033[K' _pfx_sel=$'\033[1;33m'"${_mb_tri}"$'\033[0m '
                if [ "$_do_home" = "0" ]; then
                    _fbuf="${_fbuf}$(printf '%s' "$_m_hdr_buf" | sed 's/$/\x1b[K/')"$'\n'
                    [ -n "$_m_pre_out" ] && _fbuf="${_fbuf}$(printf '%s\n' "$_m_pre_out" | sed 's/$/\x1b[K/')"$'\n'
                    _fbuf="${_fbuf}"$'\r\x1b[K\n'
                elif [ "$_m_peeked" -eq 1 ]; then
                    _fbuf="${_fbuf}"$'\033[?25l\033[2J\033[H'
                    _fbuf="${_fbuf}$(printf '%s' "$_m_hdr_buf" | sed 's/$/\x1b[K/')"$'\n'
                    [ -n "$_m_pre_out" ] && _fbuf="${_fbuf}$(printf '%s\n' "$_m_pre_out" | sed 's/$/\x1b[K/')"$'\n'
                    _fbuf="${_fbuf}"$'\r\x1b[K\n'
                    _m_peeked=0
                elif [ "$_m_painted" -gt 0 ] && [ "$_m_painted" -lt "$_m_term_lines" ]; then
                    _fbuf="${_fbuf}$(printf '\033[?25l\r\033[K\033[%dA' "$_m_painted")"
                elif [ "$menu_idx" -ge 1 ]; then
                    _fbuf="${_fbuf}"$'\033[?25l\r\033[K\033[6A'
                    _card_only=1
                fi

                if [ "$_card_only" -eq 0 ]; then
                    _m_painted=0
                    if [ "$_m_need_scroll" -eq 1 ]; then
                        _s_idx=$_m_scroll_top
                        _e_idx=$((_m_scroll_top + _m_vp_h))
                        [ "$_e_idx" -gt "$_m_total_flat" ] && _e_idx=$_m_total_flat
                    else
                        _s_idx=0
                        _e_idx=$_m_total_flat
                    fi
                    for ((_di = _s_idx; _di < _e_idx; _di++)); do
                        _dl="${_m_flat_lines[$_di]}"
                        _dn="${_m_flat_nums[$_di]}"
                        if [ -n "$_dn" ] && [ "$_dn" = "$_m_nav_cur" ]; then
                            _pfx="$_pfx_sel"
                        else
                            _pfx="  "
                        fi
                        _m_painted=$((_m_painted + 1))
                        _vp_drawn=$((_vp_drawn + 1))
                        _fbuf="${_fbuf}${_cr}${_pfx}${_dl}${_el}${_nl}"
                    done
                    if [ "$_m_need_scroll" -eq 1 ]; then
                        while [ "$_vp_drawn" -lt "$_m_vp_h" ]; do
                            _fbuf="${_fbuf}${_cr}${_el}${_nl}"
                            _m_painted=$((_m_painted + 1))
                            _vp_drawn=$((_vp_drawn + 1))
                        done
                    fi
                    if [ "$menu_idx" -ge 1 ]; then
                        _m_painted=$((_m_painted + 6))
                    else
                        _m_painted=$((_m_painted + 1))
                    fi
                fi

                if [ "$menu_idx" -ge 1 ]; then
                    # 캐시 미적중 시 부모 셸에서 1회 채워둔 뒤 단일 버퍼에 병합 (Subshell 캐시 유실 방지 + 1회 Write)
                    if [ -z "${_m_card_cache[$_m_nav_cur]-}" ]; then
                        if [ -z "${_m_detail_cache[$_m_nav_cur]-}" ]; then
                            _render_main_detail_card "$_m_nav_cur" "${_m_item_titles[$_m_nav_cur]-}" "${_m_item_keys[$_m_nav_cur]-}" "${_m_item_is_sub[$_m_nav_cur]-0}" "$menu_idx" >/dev/null
                        fi
                        _m_card_cache[$_m_nav_cur]="$(_render_main_detail_card "$_m_nav_cur" "${_m_item_titles[$_m_nav_cur]-}" "${_m_item_keys[$_m_nav_cur]-}" "${_m_item_is_sub[$_m_nav_cur]-0}" "$menu_idx")"
                    fi
                    _fbuf="${_fbuf}$(_render_page_bar "$_m_need_scroll" "$_m_scroll_top" "$_m_vp_h" "$_m_total_flat")${_nl}${_m_card_cache[$_m_nav_cur]}${_nl}"
                else
                    _fbuf="${_fbuf}$(printf '\r\x1b[38;5;110m%s\x1b[0m\x1b[K\n' "${_m_hline:-────────────────────────────────────────────────────────────────────────────────}")"$'\n'
                fi
                [ "$_do_home" = "1" ] && _fbuf="${_fbuf}"$'\033[?25h'
                printf '%s' "$_fbuf"
            }
            _m_render_screen 0
        fi
        ############## 메뉴 출력 끝 ###############
        [[ $chosen_command_sub == "{}" ]] && [[ "$cmd_choice_scut" ]] && choice="$cmd_choice_scut" && cmd_choice_scut=""
        #readxx $LINENO read "choice menu pre_choice:" $choice
        if [[ -z $choice ]]; then
            # readchoice read choice
            trap 'saveVAR;stty sane;exit' SIGINT SIGTERM EXIT # 트랩 설정
            history -r
            _mp="$(menu_prompt "$menu_idx" "$_m_need_scroll")"
            while :; do
                menu_read "$_mp" choice choice1 1
                _rr=$?
                if [ "$choice" = "__NAV_UP__" ] && [ "$menu_idx" -ge 1 ]; then
                    _m_nav_moved=1
                    _m_nav_cur=$((_m_nav_cur - 1))
                    [ "$_m_nav_cur" -lt 1 ] && _m_nav_cur="$menu_idx"
                    _m_ensure_visible
                    _m_render_screen 1
                    choice=""
                    choice1=""
                    continue
                elif [ "$choice" = "__NAV_DOWN__" ] && [ "$menu_idx" -ge 1 ]; then
                    _m_nav_moved=1
                    _m_nav_cur=$((_m_nav_cur + 1))
                    [ "$_m_nav_cur" -gt "$menu_idx" ] && _m_nav_cur=1
                    _m_ensure_visible
                    _m_render_screen 1
                    choice=""
                    choice1=""
                    continue
                elif { [ "$choice" = "__NAV_PGUP__" ] || [ "$choice" = "__NAV_LEFT__" ]; } && [ "$menu_idx" -ge 1 ]; then
                    _m_nav_moved=1
                    if [ "$_m_need_scroll" -eq 1 ]; then
                        if [ "$_m_scroll_top" -le 0 ]; then
                            _m_nav_cur=1
                        else
                            _m_scroll_top=$(( ((_m_scroll_top - 1) / _m_vp_h) * _m_vp_h ))
                            [ "$_m_scroll_top" -lt 0 ] && _m_scroll_top=0
                            _m_pick_in_view
                        fi
                    else
                        _m_nav_cur=$((_m_nav_cur - 5))
                        [ "$_m_nav_cur" -lt 1 ] && _m_nav_cur=1
                    fi
                    _m_render_screen 1
                    choice=""
                    choice1=""
                    continue
                elif { [ "$choice" = "__NAV_PGDN__" ] || [ "$choice" = "__NAV_RIGHT__" ]; } && [ "$menu_idx" -ge 1 ]; then
                    _m_nav_moved=1
                    if [ "$_m_need_scroll" -eq 1 ]; then
                        _m_pg_next=$(( (_m_scroll_top / _m_vp_h + 1) * _m_vp_h ))
                        if [ "$_m_pg_next" -ge "$_m_total_flat" ]; then
                            _m_nav_cur="$menu_idx"
                        else
                            _m_scroll_top=$_m_pg_next
                            _m_pick_in_view
                        fi
                    else
                        _m_nav_cur=$((_m_nav_cur + 5))
                        [ "$_m_nav_cur" -gt "$menu_idx" ] && _m_nav_cur="$menu_idx"
                    fi
                    _m_render_screen 1
                    choice=""
                    choice1=""
                    continue
                elif [ "$choice" = "__NAV_LEFT__" ] || [ "$choice" = "__NAV_RIGHT__" ] || [ "$choice" = "__NAV_PGUP__" ] || [ "$choice" = "__NAV_PGDN__" ]; then
                    printf '\r\033[K'
                    choice=""
                    choice1=""
                    continue
                fi
                # [?] 는 단축키 안내를 아래쪽에 몇줄만 띄우고, 화면을 지우지 않고 다시 입력받는다
                if [ "$choice" = "?" ]; then
                    menu_keyhelp
                    _m_peeked=1
                    choice=""
                    choice1=""
                    continue
                fi
                if [ -z "$choice" ] && [ "$_rr" -eq 0 ] && [ "$menu_idx" -ge 1 ]; then
                    choice="$_m_nav_cur"
                fi
                [ "$_rr" -eq 1 ] && choice="q" # ctrl d 또는 ESC 로 빠져나가는 경우
                break
            done
            unset -v _mp _rr
            trap - SIGINT SIGTERM EXIT   # 트랩 해제 (이후에는 기본 동작)
        fi
        unset -v skipmain

        #shortcut 이 중복되더라도 첫번째 키만 가져옴
        key_idx=$(echo "${keysarr[*]}" | tr ' ' '\n' | awk -v target="$choice" '$0 == target {print(NR-1); exit}')

        #shortcut 을 참조하여 choice 번호 설정
        [ -n "$key_idx" ] && choice=${idx_mapping[$key_idx]} # && #readxx $LINENO key $key_idx

        # choice 와 shortcut 이 동일한 경우 pass
        #if [[ $choice && "choice" == "scut" ]]; then
        readxx $LINENO what choice $choice current_shortcut_page $scut
        #    continue
        #fi
        # 눈에 보이지 않는 메뉴 호출시
        # 서브메뉴에 숨어있는 shortcut 호출이 있을때 (숫자가 아닐때)
        # 경유메뉴에서 호출시 작동오류 check
        #readxx $LINENO you choice? $choice
        # if [ "$choice" ] && (( ! $choice > 0 )) 2>/dev/null; then choice 에 영어가 들어오면 참인데 오작동 가끔발생
        # readxy "$LINENO // $choice // $title_of_menu // $chosen_command_sub // $title"
        if [ "$choice" ] && [ -z "$choice1" ] && { ! echo "$choice" | grep -Eq '^[1-9][0-9]*$' || echo "$choice" | grep -Eq '^[a-zA-Z]+$'; }; then
            #readxx $LINENO you choice? yes $choice
            # subshortcut 을 참조하여 title_of_menu 설정
            # ex) chosen_command:{submenu_systemsetup} // title_of_menu:시스템 초기설정과 기타 (submenu) [i]
            for item in "${shortcutarr[@]}"; do
                # echo $item
                if [ "$choice" == "${item%%@@@*}" ]; then
                    #newscut=$choice

                    # 형태 -> v@@@%%% proxmox / kvm / minecraft [v]@@@{submenu_virt}
                    itema2=$(echo "$item" | awk -F'@@@' '{print $2}')
                    readxx $LINENO itema2: "$itema2"
                    # chosen_command_sub 는 중괄호 포함 내용 {command_value} 저장
                    chosen_command_sub="$(echo "$itema2" | awk -F'[{}]' 'BEGIN{OFS="{"} {print OFS $2 "}"}')"
                    chosen_command_relay="$(echo "$item" | awk -F'@@@' '{print $3}' | awk -F'[{}]' 'BEGIN{OFS="{"} {print OFS $2 "}"}')"
                    readxx $LINENO 단축키판단후 chosen_command_sub $chosen_command_sub chosen_command_relay $chosen_command_relay
                    readxx $LINENO item ${item}
                    # 중괄호 시작 메뉴 아닐때 빈변수 반환 title 조정

                    # mainmenu
                    if [[ $chosen_command_sub == "{}" ]]; then
                        # ex) d@@@%%% 서버 데몬 관리 [d]
                        #readxx $LINENO $env $chosen_command_sub $title_of_menu_sub $title_of_menu
                        chosen_command_sub=""
                        chosen_command_relay=""
                        readxx $LINENO 중괄호없는메뉴 대표메뉴 chosen_command_sub 삭제 $chosen_command_sub
                        title_of_menu="${itema2#*\%\%\% }"
                        readxx $LINENO 필수 title_of_menu:$title_of_menu

                        # relay {} .. {}
                    elif [[ $chosen_command_relay != "{}" && $chosen_command_relay ]]; then
                        # ex) shortcutarr[8] = i@@@%%% 시스템 초기설정과 기타 [i]@@@{submenu_sys}
                        # ex) shortcutarr[141] = hid@@@%%% {submenu_sys}>히든메뉴 [hid]@@@{submenu_hidden}
                        title_of_menu="${itema2#*\}}"
                        itema3=$(echo "$item" | awk -F'@@@' '{print $3}')
                        chosen_command_relay_sub=$chosen_command_sub
                        chosen_command_sub="${itema3#*\%\%\% }"
                        readxx $LINENO 인계메뉴 chosen_command_sub $chosen_command_sub chosen_command_relay $chosen_command_relay

                        # submenu
                    else
                        # ex) shortcutarr[123] = irc@@@%%% {submenu_com}irc chat [irc]
                        chosen_command_relay=""
                        readxx $LINENO 중괄호메뉴일때
                        title_of_menu="${itema2#*\}}"
                    fi

                    # choice 99 로 아래 메뉴 진입 시도 (바로가기 전용 내부 값)
                    readxx $LINENO choice_fail_check: $choice
                    choice=99
                    nav_shortcut_hit="y" # 99 는 바로가기 해석 결과로만 통과시킨다
                    readxx $LINENO choice_fail_check: $choice
                    break # 중복 단축키가 있어도 첫번째 항목만 사용
                fi
            done
        fi

        # 메인/서브 메뉴에서 정상 범위의 숫자가 입력된경우
        # 1 ~ 98 까지 메뉴 지원 // 99 특수기능 ex) shortcut,conf,kr,q // cf) 100~9999 특수기능(timer)
        # if [ -n "$choice" ] && { case "$choice" in [0-9] | [1-9][0-9]) true ;; *) false ;; esac } && { [ "$choice" -ge 1 ] && [ "$choice" -le "$menu_idx" ] || [ "$choice" -eq 99 ]; }; then
        # if (echo "$choice" | grep -Eq '^[1-9]$|^[1-9][0-9]$') && [ "$choice" -ge 1 ] && [ "$choice" -le "$menu_idx" ] || [ "$choice" -eq 99 ] 2>/dev/null; then
        # 99 는 단축키 바로가기 해석용 내부값이므로, 해석에 실패한 99 는 여기서 막는다
        # (막지 않으면 이전화면 제목이 재사용되어 엉뚱한 메뉴의 명령이 실행됨)
        if [[ $choice != 0* ]] && [[ -z $choice1 ]] && { [ "$choice" != 99 ] || [ -n "$nav_shortcut_hit" ]; } && ((choice >= 1 && choice <= 99 && choice <= menu_idx || choice == 99)) 2>/dev/null; then

            readxx $LINENO choice99 choice: $choice
            # 선택한 줄번호의 타이틀 가져옴
            [ ! "$choice" == 99 ] && title_of_menu="$(print_menulist | awk -v choice="$choice" 'NR==choice {print}')"

            ###############################################################
            # 선택한 줄번호의 타이틀에 맞는 리스트가져옴
            ###############################################################
            listof_comm() {
                # 필요인수: ${sub_menu}${title_of_menu}
                #
                # 선택한 메뉴가 서브메뉴인경우 ${chosen_command_sub}가 포함된 리스트 수집
                # 선택한 메뉴가 메인메뉴인경우 ${chosen_command_sub} -> 공백처리
                # 메뉴 4종류: 메인단독 / 메인경유 / 서브경유 / 최종
                # 1. %%% 서버 데몬 관리 [d]
                # 2. %%% 시스템 초기설정과 기타 [i]
                #    {submenu_sys}
                # 3. %%% {submenu_sys}>히든메뉴 [hid]
                #    {submenu_hidden}
                # 4. %%% {submenu_hidden}원격 백업 관리 [rb]
                #
                sub_menu="${chosen_command_sub-}"
                [[ $sub_menu == "{}" ]] && sub_menu=""
                # 재하청 메뉴는 relay_sub 를 sub_menu 로 사용.
                [ -n "$chosen_command_relay_sub" ] && sub_menu="$chosen_command_relay_sub" && chosen_command_relay_sub=""
                readxx $LINENO "lisof_comm func in - IFS check title_of_menu: $title_of_menu sub_menu: $sub_menu {chosen_command_sub}:${chosen_command_sub-} chosen_command_relay_sub:$chosen_command_relay_sub"
                #  [규칙] IFS 진입 시 저장 / 종료 시 복원 (인수 분리 버그 근본 차단)
                #   아래 IFS=$'\n' xxx=($(...)) 3곳은 '명령 없이 대입만 하는 문장'이라
                #   IFS 를 영구히 $'\n' 로 바꿔버린다 (실측).
                #   그 결과 프롬프트(menu_read)의 "${_w[*]:1}" 이 공백이 아니라
                #   '줄바꿈' 으로 인수를 붙여 "shutdown -h now" 가 2줄로 쪼개진다.
                #   중간에 break 로 빠져나가도 복원되도록 함수 최상단에서 저장한다.
                _lic_ifs="$IFS"
                # %%% 부부터 빈줄까지 변수에
                #IFS=$'\n' allof_chosen_commands="$(cat "$env" | awk -v title_of_menu="%%% ${sub_menu}${title_of_menu}" 'BEGIN {gsub(/[\(\)\[\]]/, "\\\\&", title_of_menu)} !flag && $0 ~ title_of_menu{flag=1; next} /^$/{flag=0} flag')"
                IFS=$'\n' allof_chosen_commands="$(cat "$env" | awk -v title_of_menu="%%% ${sub_menu}${title_of_menu}" 'BEGIN { gsub(/[][().*+?^$\\|]/, "\\\\&", title_of_menu) } !flag && $0 ~ title_of_menu { flag=1; next } /^$/ { flag=0 } flag')"

                #unset IFS ; dline ; echo "$allof_chosen_commands" ; dline
                # 제목배고 선명령 빼고 순서 명령문들 배열
                IFS=$'\n' chosen_commands=($(echo "${allof_chosen_commands}" | grep -v "^%% "))
                # [#h] "명령 설명" 태그 : #h 줄은 번호를 달지 않고(원래 # 주석 규칙 그대로)
                #      바로 아래 명령줄의 설명으로 붙인다. chosen_commands 와 같은 인덱스로
                #      chosen_desc 를 만들어두면 목록표시/실행표시 양쪽에서 짝 조회가 된다.
                #      (길이를 유지하므로 num_commands / original_indices 계산은 그대로)
                #      - #h 뒤에 연속으로 여러줄을 쓰면 그 전체가 한 설명(줄바꿈 유지)이 된다
                #      - 영문 설명은 바로 다음줄에 #he 로 쓰면 L 언어토글에 연동된다
                unset chosen_desc
                chosen_desc=()
                _cd_pending=""
                _cd_ifs="$IFS"
                local _cd_cr=$'\r'
                IFS=$'\n'
                for _cd_line in $(echo "${allof_chosen_commands}" | grep -v "^%% "); do
                    if rx_match "$_cd_line" '^[[:space:]]*#h(e)?[[:space:]]+(.*)$'; then
                        # 태그 줄 자체에는 설명을 붙이지 않는다 (바로 다음 명령줄의 짝)
                        _cd_text="$(rx_cap "$_cd_line" '^[[:space:]]*#h[e]*[[:space:]][[:space:]]*\(.*\)$' 1)"
                        _cd_text="${_cd_text%$_cd_cr}"
                        if [ -n "$_cd_pending" ]; then
                            _cd_pending="$_cd_pending"$'\n'"$_cd_text" # 여러줄 설명 누적
                        else
                            _cd_pending="$_cd_text"
                        fi
                        # [규칙] Bash 2 호환: arr+=() 금지 -> 인덱스 대입
                        chosen_desc[${#chosen_desc[@]}]=""
                    elif rx_match "$_cd_line" '^[[:space:]]*#'; then
                        # 일반 주석줄은 설명을 소비하지 않는다.
                        # (#h 와 명령줄 사이에 참고주석이 있어도 설명은 명령줄에 붙는다)
                        chosen_desc[${#chosen_desc[@]}]=""
                    else
                        # 설명 태그가 없는 기존 명령도 쉬움 모드 제목을 자동으로 보충한다.
                        # 목록뿐 아니라 ?번호 미리보기와 실행 확인 카드도 같은 제목을 사용한다.
                        if [ -n "$_cd_pending" ]; then
                            chosen_desc[${#chosen_desc[@]}]="$_cd_pending"
                        else
                            chosen_desc[${#chosen_desc[@]}]="$(easy_auto_title "$_cd_line")"
                        fi
                        _cd_pending=""
                    fi
                done
                IFS="$_cd_ifs"
                unset _cd_line _cd_pending _cd_text _cd_ifs
                # 선명령 모듬 배열
                # pre_commands=()
                IFS=$'\n' pre_commands=($(echo "${allof_chosen_commands}" | grep "^%% "))
                #  [규칙] 진입시 저장한 IFS 로 복원 (위 주석 참고)
                #   미복원 시 프롬프트의 인수 결합이 줄바꿈으로 바뀌어 명령이 쪼개진다.
                IFS="$_lic_ifs"
                unset _lic_ifs
            }
            listof_comm

            ###############################################################
            # cmds 보여주는 loop func
            ###############################################################
            cmds() {
                local cmdloop=0
                local _cmd_page=1 _cmd_page_all=0 _cmd_total_pages=1
                #echo "$LINENO --- cmds enter" && sleep 1
                while true; do # 하부 메뉴 CMDs cmd_choice loop
                    cmdloop=$((cmdloop + 1))
                    chosen_command=""
                    sel_desc="" # [#h] 이 선택에 붙은 설명. 매 회차 초기화 (이전값 잔류 방지)
                    num_commands=${#chosen_commands[@]} # 줄길이 체크
                    # [#h/#he 제외 1줄 판정] #h/#he 메타 설명만 붙은 1줄 메뉴도 즉시 실행되도록 실제 명령줄 수를 센다.
                    #   (일반 # 주석은 [logg] 등 텍스트 표시용 메뉴 보존을 위해 기존처럼 카운트에 포함한다.)
                    local _non_meta_cnt=0 _first_non_meta_idx=0 _nm_i=0 _nm_tc=""
                    while [ "$_nm_i" -lt "$num_commands" ]; do
                        _nm_tc="${chosen_commands[$_nm_i]}"
                        _nm_tc="${_nm_tc#"${_nm_tc%%[![:space:]]*}"}"
                        case "$_nm_tc" in
                            "#h "*|"#he "*|"#h"|"#he") ;;
                            *)
                                [ "$_non_meta_cnt" -eq 0 ] && _first_non_meta_idx="$_nm_i"
                                _non_meta_cnt=$((_non_meta_cnt + 1))
                                ;;
                        esac
                        _nm_i=$((_nm_i + 1))
                    done

                    # 명령줄이 1줄이면 바로 실행 1줄 이상이면 리스트 출력
                    # 1줄은 분기메뉴일때 relay 시켜 또다른 메뉴를 불러오는 효과 %%% %% 를 뺀 나머지가 {...} 한줄만 남을때
                    # readxx $LINENO chosen_command_sub $chosen_command_sub
                    # 한줄짜리
                    if [ "$num_commands" -eq 1 ] || [ "$_non_meta_cnt" -eq 1 ]; then
                        scut=$(echo "$title_of_menu" | awk -F'[][]' '{print $2}') # && echo "scut -> $scut" && #readxx
                        updatescut
                        # relay
                        chosen_command=${chosen_commands[$_first_non_meta_idx]}
                        sel_desc="${chosen_desc[$_first_non_meta_idx]-}"
                    elif [ "$num_commands" -gt 1 ]; then

                        # go.env 환경파일에서 가져온 명령문 출력 // CMDs // command list print func
                        ####################### choice_list #######################
                        ####################### choice_list #######################
                        ####################### choice_list #######################
                        choice_list() {
                            local IFS=$' \t\n'
                            local _cl_hdr_buf="" _cl_pre_out="" _cl_pg_first="" _cl_pg_last=""
                            local -a _cl_disp_lines _cl_disp_nums
                            _cl_disp_lines=()
                            _cl_disp_nums=()

                            # scut history 관리 -> flow
                            scut=$(echo "$title_of_menu" | awk -F'[][]' '{print $2}') # && echo "scut -> $scut" && #readxx
                            updatescut

                            local _vmode_badge=""
                            if [ "${GOVIEW:-easy}" = "easy" ]; then
                                [ "$GOLANG" = "kr" ] && _vmode_badge="$(ko '보기: 쉬움 (V 로 전환)')" || _vmode_badge="View: Easy (toggle V)"
                            else
                                [ "$GOLANG" = "kr" ] && _vmode_badge="$(ko '보기: 명령어 (V 로 전환)')" || _vmode_badge="View: Cmd (toggle V)"
                            fi
                            local _cl_dline _cl_hline
                            if [ "${GOTERM_ENC:-}" = "euckr" ]; then
                                _cl_dline="================================================================================"
                                _cl_hline="--------------------------------------------------------------------------------"
                            else
                                _cl_dline="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                                _cl_hline="────────────────────────────────────────────────────────────────────────────────"
                            fi
                            local _hl_badge=""
                            if [ -n "${_IDX_HILITE_KW:-}" ]; then
                                _hl_badge="$(printf '  \x1b[1;37;41m [I] %s \x1b[0m' "$_IDX_HILITE_KW")"
                            fi
                            _cl_hdr_buf="$(printf '\x1b[38;5;75m%s\x1b[0m :: %s\n' "$_cl_dline" "$cmdloop")"$'\n'
                            _cl_hdr_buf="${_cl_hdr_buf}$(printf '* \x1b[1;37;45m %s CMDs \x1b[0m %s \x1b[1;33;44m pwd: %s \033[0m  \x1b[1;36m%s\x1b[0m%b\n' "$title_of_menu" "$flow" "$(pwd)" "$_vmode_badge" "$_hl_badge")"$'\n'
                            _cl_hdr_buf="${_cl_hdr_buf}$(printf '\x1b[38;5;110m%s\x1b[0m\n' "$_cl_hline")"$'\n'
                            # pre excute (1회 캡처 캐싱 + 중복 테두리 제거)
                            if [ ${#pre_commands[@]} -gt 0 ]; then
                                local _pc_raw="" _pc_item
                                for _pc_item in "${pre_commands[@]}"; do
                                    _pc_raw="${_pc_raw}$(eval "${_pc_item#%% }" | sed 's/^[[:space:]]*/  /g')"$'\n'
                                done
                                _pc_raw="$(printf '%s' "$_pc_raw" | sed -e '/^[[:space:]]*\(\x1b\[[0-9;]*m\)*\(====*\|────*\|━━━━*\).*$/d')"
                                if [ -n "$_pc_raw" ]; then
                                    if printf '%s' "$_pc_raw" | grep -qE '0m'; then
                                        _cl_pre_out="${_pc_raw}"$'\n'"$(printf '\x1b[38;5;110m%s\x1b[0m' "$_cl_hline")"
                                    else
                                        _cl_pre_out="$(printf '\x1b[0;36m%s\x1b[0m\n\x1b[38;5;110m%s\x1b[0m' "$_pc_raw" "$_cl_hline")"
                                    fi
                                fi
                            fi

                            display_idx=1
                            unset original_indices
                            original_indices=()
                            local prev_comment=""

                            # 터미널 크기 및 상단 고정 줄 수 계산 (가운데 스크롤 뷰포트용)
                            local _TS_LINES="" _TS_COLS="" _term_lines _term_cols _top_lines=4 _vp_h=10 _tc=""
                            _get_term_size
                            _term_lines="$_TS_LINES"
                            _term_cols="$_TS_COLS"
                            if [ -n "$_cl_pre_out" ]; then
                                local _pre_cnt
                                _pre_cnt="$(printf '%s\n' "$_cl_pre_out" | awk -v cols="$_term_cols" '{ gsub(/\033\[[0-9;]*[a-zA-Z]/, ""); l=length($0); c += (l > cols && cols > 0) ? int((l - 1) / cols) + 1 : 1 } END { print c+0 }')"
                                _top_lines=$((_top_lines + _pre_cnt))
                            fi
                            _vp_h=$((_term_lines - _top_lines - 7))
                            [ "$_vp_h" -lt 5 ] && _vp_h=5

                            # 전체 항목 렌더링 (페이지 분할 없이 스크롤 뷰포트에서 슬라이싱)
                            # [규칙] 널명령(: 라벨) 색상: 256색 터미널=금색(220), ANSI 16색=밝은 노란색(1;33)
                            local _nullabel_clr='\x1b[1;33m' _has_256c=0 _tc_n=""
                            case "${COLORTERM:-}" in
                                truecolor|24bit) _has_256c=1 ;;
                            esac
                            if [ "$_has_256c" -eq 0 ]; then
                                case "${TERM:-}" in
                                    *256color*|*truecolor*|*direct*|alacritty|kitty|xterm-kitty|wezterm|foot*)
                                        _has_256c=1 ;;
                                    *)
                                        _tc_n="$(tput colors 2>/dev/null)"
                                        case "$_tc_n" in
                                            [0-9]*) [ "$_tc_n" -ge 256 ] 2>/dev/null && _has_256c=1 ;;
                                        esac
                                        ;;
                                esac
                            fi
                            [ "$_has_256c" -eq 1 ] && _nullabel_clr='\x1b[1;38;5;220m'
                            local _pending_hdr_lines="" _cl_nl=$'\n'
                            for ((item = 1; item <= ${#chosen_commands[@]}; item++)); do

                                c_cmd="${chosen_commands[$((item - 1))]}"
                                _hdesc="${chosen_desc[$((item - 1))]-}"
                                _tc="${c_cmd#"${c_cmd%%[![:space:]]*}"}"

                                case "$_tc" in
                                    "#h "*|"#he "*|"%%%"*) continue ;;
                                    "#"*)
                                        prev_comment="${_tc#\#}"
                                        prev_comment="${prev_comment#"${prev_comment%%[![:space:]]*}"}"
                                        prev_comment="${prev_comment%"${prev_comment##*[![:space:]]}"}"
                                        if [ -z "$prev_comment" ]; then
                                            # 빈 '#' 주석은 지저분한 '#' 기호 대신 깔끔한 빈 줄(공백)로 표현 (중복 방지)
                                            if [ "${GOVIEW:-easy}" != "easy" ] && [ -z "$_pending_hdr_lines" ] && [ -n "${_cl_pg_first:-}" ]; then
                                                _pending_hdr_lines=" "
                                            fi
                                        elif [ "${GOVIEW:-easy}" != "easy" ]; then
                                            local _hdr_item=""
                                            case "$prev_comment" in
                                                "─"*|"━"*|"═"*|"-"*"【"*|"["*|"- "*"["*|"--"*|"---"*)
                                                    _hdr_item="   \x1b[1;36m${prev_comment}\x1b[0m"
                                                    ;;
                                                *)
                                                    _hdr_item="    \x1b[1;36m# ${prev_comment}\x1b[0m"
                                                    ;;
                                            esac
                                            if [ -n "${_cl_pg_first:-}" ] && [ -z "$_pending_hdr_lines" ]; then
                                                _pending_hdr_lines="${_cl_nl}${_hdr_item}"
                                            elif [ "$_pending_hdr_lines" = " " ]; then
                                                _pending_hdr_lines="${_cl_nl}${_hdr_item}"
                                            else
                                                _pending_hdr_lines="${_pending_hdr_lines:+${_pending_hdr_lines}${_cl_nl}}${_hdr_item}"
                                            fi
                                        else
                                            case "$prev_comment" in
                                                "─"*|"━"*|"═"*|"-"*"【"*|"["*|"- "*"["*|"--"*|"---"*)
                                                    local _hdr_item="   \x1b[1;36m${prev_comment}\x1b[0m"
                                                    if [ -n "${_cl_pg_first:-}" ] && [ -z "$_pending_hdr_lines" ]; then
                                                        _pending_hdr_lines="${_cl_nl}${_hdr_item}"
                                                    elif [ "$_pending_hdr_lines" = " " ]; then
                                                        _pending_hdr_lines="${_cl_nl}${_hdr_item}"
                                                    else
                                                        _pending_hdr_lines="${_pending_hdr_lines:+${_pending_hdr_lines}${_cl_nl}}${_hdr_item}"
                                                    fi
                                                    ;;
                                            esac
                                        fi
                                        continue
                                        ;;
                                esac

                                # 주석 아닌 경우 배열 순번에 줄번호 할당
                                original_indices[${#original_indices[@]}]="$item"
                                pi="${display_idx}."
                                display_idx=$((display_idx + 1))

                                local _cur_item_no=$((display_idx - 1))
                                [ -z "${_cl_pg_first:-}" ] && _cl_pg_first=$_cur_item_no
                                _cl_pg_last=$_cur_item_no

                                if [ -n "$_pending_hdr_lines" ]; then
                                    _cl_disp_lines[${#_cl_disp_lines[@]}]="$(echo -e "$_pending_hdr_lines")"
                                    _cl_disp_nums[${#_cl_disp_nums[@]}]=""
                                    _pending_hdr_lines=""
                                fi

                                if [ "${GOVIEW:-easy}" = "easy" ]; then
                                    # 쉬움 모드 렌더링 (배열에 캡처하여 커서 이동 시 재파싱 0회)
                                    local _easy_line
                                    _easy_line="$(render_item_easy "$pi" "$c_cmd" "$_hdesc" "$prev_comment")"
                                    if [ -n "${_IDX_HILITE_KW:-}" ]; then
                                        if printf '%s\n' "$_easy_line" | grep -qiF -- "$_IDX_HILITE_KW" 2>/dev/null; then
                                            _easy_line="$(printf '%s\n' "$_easy_line" | _idx_hilite_ansi "$_IDX_HILITE_KW")"
                                        elif printf '%s\n' "$c_cmd" | grep -qiF -- "$_IDX_HILITE_KW" 2>/dev/null; then
                                            _easy_line="${_easy_line} $(printf '\033[1;37;41m[%s]\033[0m' "$_IDX_HILITE_KW")"
                                        fi
                                    fi
                                    _cl_disp_lines[${#_cl_disp_lines[@]}]="$_easy_line"
                                    _cl_disp_nums[${#_cl_disp_nums[@]}]="$_cur_item_no"
                                    prev_comment=""
                                else
                                    # 기존 명령어 모드 렌더링
                                    prev_comment=""
                                    # 명령구문에서 파일경로 추출 (실제 시스템 경로만, sed패턴/와일드카드/가상FS 제외)
                                    file_paths="$(echo "$c_cmd" | awk '
/^[[:space:]]*#/ { next }
{
    for (i = 1; i <= NF; i++) {
        token = $i
        gsub(/^["'"'"'(]+|["'"'"'),;]+$/, "", token)
        gsub(/[^a-zA-Z0-9\/_.-]+$/, "", token)
        if (token ~ /[\$\*\?\[\]=<>|]/) continue
        if (token ~ /^https?:\/\//) continue
        if (token ~ /^\/(etc|var|usr|opt|home[0-9]*|root|boot|lib|lib64|sbin|bin|srv|mnt|media|script|backup|data)\/[^[:space:]]+$/ &&
            token !~ /var[A-Z][a-zA-Z0-9_.-]*/ &&
            token !~ /\/$/) {
            print length(token), token
        }
    }
}' | sort -rnk1,1 | awk '!seen[$2]++ { print $2 }')"
                                    _cl_ifs="$IFS"
                                    IFS=$' \n'
                                    _fp_i=0
                                    _fp_paths=""
                                    for file_path in $file_paths; do
                                        _fp_i=$((_fp_i + 1))
                                        c_cmd="${c_cmd//$file_path/__FP_${_fp_i}__}"
                                        _fp_paths="${_fp_paths}${_fp_i} ${file_path}"$'\n'
                                    done
                                    IFS=$'\n'
                                    for _fp_entry in $_fp_paths; do
                                        [ -z "$_fp_entry" ] && continue
                                        _fp_idx="${_fp_entry%% *}"
                                        file_path="${_fp_entry#* }"
                                        [ ! -e "$file_path" ] && file_marker="@@@" || file_marker="@@@@"
                                        c_cmd="${c_cmd//__FP_${_fp_idx}__/${file_marker}${file_path}${file_marker}}"
                                    done
                                    IFS="$_cl_ifs"
                                    unset -v _cl_ifs _fp_i _fp_paths _fp_entry _fp_idx

                                    # ': [1] 라벨 ; 명령' 또는 ': 1. 라벨 ; 명령' 에서 앞의 중복 번호 제거
                                    case "$c_cmd" in
                                        ": ["[0-9]"] "*|": ["[0-9][0-9]"] "*|": ["[0-9]"-"[0-9]"] "*)
                                            c_cmd=": ${c_cmd#*] }"
                                            ;;
                                        ": "[0-9]". "*|": "[0-9][0-9]". "*|": "[0-9]"-"[0-9]". "*)
                                            c_cmd=": ${c_cmd#*. }"
                                            ;;
                                    esac

                                    max_len=330
                                    processed_cmd="$c_cmd"
                                    if ((${#c_cmd} > max_len)); then
                                        processed_cmd="${c_cmd:0:max_len}..."
                                    fi

                                    # [규칙] 널명령(: 라벨) 색칠 분리
                                    #  ': 라벨 ; 명령' 의 라벨은 색칠 규칙 대상에서 완전히 제외하고,
                                    #  명령 부분만 색칠한 뒤 라벨을 금색(256색) / 노란색(ANSI 16색)으로 감싸 다시 붙인다.
                                    local _pi_pfx _kbadge _rendered _fold_w
                                    _fold_w=$((_term_cols > 30 ? _term_cols - 8 : 22))
                                    [ "$_fold_w" -gt 126 ] && _fold_w=126
                                    _pi_pfx="$(printf "\e[1m%-3s\e[0m " "${pi}")"
                                    _kbadge="$(_cmd_kind_badge "$c_cmd")"
                                    _rendered="$(echo "$processed_cmd" | fold -sw "$_fold_w" | sed -e '2,$s/^/    /' \
                                        -e '/^\(: \|!!! : \)/ { h; s/^[^;]*;/__NULLABEL__;/; }' \
                                        -e 's/@@@@\([^ ]*\)@@@@/\x1b[1;37m\1\x1b[0m/g' \
                                        -e 's/@@@\([^ ]*\)@@@/\x1b[1;30;9m\1\x1b[0m/g' \
                                        -e '/^#/! s/\(var[A-Z][a-zA-Z0-9_@-]*__[a-zA-Z0-9_@.-]*\|var[A-Z][a-zA-Z0-9_@-]*\)/\x1b[1;35m\1\x1b[0m/g' \
                                        -e 's/@space@/ /g' \
                                        -e 's/@colon@/:/g' \
                                        -e 's/@dot@/./g' \
                                        -e '/^#/! s/@@/\//g' \
                                        -e '/^#/! s/\(!!!\|eval\|exportvar\|export\)/\x1b[1;33m\1\x1b[0m/g' \
                                        -e '/^#/! s/\(status\|running\)/\x1b[33m\1\x1b[0m/g' \
                                        -e '/^#/! s/\(template_insert\|template_copy\|template_view\|template_edit\|batcat \|vi2 \|vi3 \|tac \|cat3 \|cat \)/\x1b[1;34m&\x1b[0m/g' \
                                        -e '/^#/! s/\(hash_add\|hash_restore\|hash_remove\|change\|insert\|explorer\)/\x1b[1;34m&\x1b[0m/g' \
                                        -e '/^#/! s/\(unsetvar\|unset\|stopped\|stop\|stopall\|allstop\|download\|\<down\>\|disable\|disabled\)/\x1b[31m\1\x1b[0m/g' \
                                        -e '/^#/! s/\(restart\|reload\|autostart\|startall\|start\|update\|upgrade\|\<up\>\|enable\|enabled\)/\x1b[1;32m\1\x1b[0m/g' \
                                        -e '/^#/! s/\(\.\.\.\|;;\)/\x1b[1;36m\1\x1b[0m/g' \
                                        -e '/^__NULLABEL__/ { x; s/;.*$//; s/@@@@//g; s/@@@//g; G; s/__NULLABEL__;//; s/\n/;/; s/^\([^;]*\);/'"${_nullabel_clr}"'\1\x1b[0m;/; }' \
                                        -e '/^ *#/!b a' -e 's/\(\x1b\[0m\)/\x1b[1;36m/g' -e ':a' \
                                        -e 's/# \(.*\)/\x1b[1;36m# \1\x1b[0m/' \
                                        -e 's/#$/\x1b[1;36m#\x1b[0m/')"
                                    if [ -n "${_IDX_HILITE_KW:-}" ] && printf '%s\n' "$_rendered" | grep -qiF -- "$_IDX_HILITE_KW" 2>/dev/null; then
                                        _rendered="$(printf '%s\n' "$_rendered" | _idx_hilite_ansi "$_IDX_HILITE_KW")"
                                    fi
                                    if [ -n "$_kbadge" ]; then
                                        _cl_disp_lines[${#_cl_disp_lines[@]}]="$(printf "%s%s %b" "$_pi_pfx" "$_rendered" "$_kbadge")"
                                    else
                                        _cl_disp_lines[${#_cl_disp_lines[@]}]="$(printf "%s%s" "$_pi_pfx" "$_rendered")"
                                    fi
                                    _cl_disp_nums[${#_cl_disp_nums[@]}]="$_cur_item_no"
                                fi
                            done # end of for item in $(seq 1 ${#chosen_commands[@]}); do

                            # 평면 줄 배열 생성 (스크롤 뷰포트 슬라이싱용, 서브셸 0회)
                            # [규칙] Bash 2.05 호환: 큰따옴표 내부 ${var%%$'\n'*} / ${var#*$'\n'} 금지 (작은따옴표가 리터럴로 들어가 무한루프 발생) -> 변수 $_cl_nl 사용
                            local -a _cl_flat_lines _cl_flat_nums _cl_item_start _cl_item_end _cl_card_cache
                            _cl_flat_lines=()
                            _cl_flat_nums=()
                            _cl_item_start=()
                            _cl_item_end=()
                            _cl_card_cache=()
                            local _di _dl _dn _line _is_first _fi
                            for ((_di = 0; _di < ${#_cl_disp_lines[@]}; _di++)); do
                                _dl="${_cl_disp_lines[$_di]}"
                                _dn="${_cl_disp_nums[$_di]}"
                                if [ -z "$_dl" ]; then
                                    _fi=${#_cl_flat_lines[@]}
                                    _cl_flat_lines[$_fi]=""
                                    _cl_flat_nums[$_fi]=""
                                    continue
                                fi
                                _is_first=1
                                while [ -n "$_dl" ]; do
                                    case "$_dl" in
                                        *"$_cl_nl"*)
                                            _line="${_dl%%$_cl_nl*}"
                                            _dl="${_dl#*$_cl_nl}"
                                            ;;
                                        *)
                                            _line="$_dl"
                                            _dl=""
                                            ;;
                                    esac
                                    _fi=${#_cl_flat_lines[@]}
                                    _cl_flat_lines[$_fi]="$_line"
                                    if [ -n "$_dn" ] && [ "$_is_first" -eq 1 ]; then
                                        _cl_flat_nums[$_fi]="$_dn"
                                        _cl_item_start[$_dn]=$_fi
                                        _cl_item_end[$_dn]=$_fi
                                        _is_first=0
                                    else
                                        _cl_flat_nums[$_fi]=""
                                        [ -n "$_dn" ] && _cl_item_end[$_dn]=$_fi
                                    fi
                                done
                            done

                            local _total_flat=${#_cl_flat_lines[@]}
                            local _need_scroll=0 _scroll_top=0 _max_scroll=0
                            [ "${_cmd_page_all:-0}" -eq 0 ] && [ "$_total_flat" -gt "$_vp_h" ] && _need_scroll=1
                            _max_scroll=$((_total_flat - _vp_h))
                            [ "$_max_scroll" -lt 0 ] && _max_scroll=0

                            local _cl_nav_cur="${_cl_pg_first:-1}" _cl_nav_moved=0 _cl_painted=0 _cl_peeked=0
                            local _cl_tri="▶"
                            [ "${GOTERM_ENC:-}" = "euckr" ] && _cl_tri="$(ko '▶')"

                            _cl_ensure_visible() {
                                [ "$_need_scroll" -eq 0 ] && return
                                local _cs="${_cl_item_start[$_cl_nav_cur]:-0}"
                                local _ce="${_cl_item_end[$_cl_nav_cur]:-$_cs}"
                                if [ "$_cs" -lt "$_scroll_top" ]; then
                                    _scroll_top="$_cs"
                                    [ "$_scroll_top" -lt 0 ] && _scroll_top=0
                                elif [ "$_ce" -ge $((_scroll_top + _vp_h)) ]; then
                                    _scroll_top=$((_ce - _vp_h + 1))
                                    [ "$_scroll_top" -gt "$_max_scroll" ] && _scroll_top=$_max_scroll
                                    [ "$_scroll_top" -lt 0 ] && _scroll_top=0
                                fi
                            }

                            _cl_pick_in_view() {
                                local _vi _ve=$((_scroll_top + _vp_h))
                                [ "$_ve" -gt "$_total_flat" ] && _ve="$_total_flat"
                                for ((_vi = _scroll_top; _vi < _ve; _vi++)); do
                                    if [ -n "${_cl_flat_nums[$_vi]}" ]; then
                                        _cl_nav_cur="${_cl_flat_nums[$_vi]}"
                                        return 0
                                    fi
                                done
                                for ((_vi = _scroll_top - 1; _vi >= 0; _vi--)); do
                                    if [ -n "${_cl_flat_nums[$_vi]}" ]; then
                                        _cl_nav_cur="${_cl_flat_nums[$_vi]}"
                                        return 0
                                    fi
                                done
                            }

                            _cl_render_screen() {
                                local _do_home="${1:-0}" _fi _dl _dn _pfx _s_idx _e_idx _vp_drawn=0 _card_only=0 _fbuf=""
                                local _cr=$'\r' _nl=$'\n' _el=$'\033[K' _pfx_sel=$'\033[1;33m'"${_cl_tri}"$'\033[0m '
                                if [ "$_do_home" = "0" ]; then
                                    [ -z "$debug" ] && _clear_keep_scrollback
                                    _fbuf="${_fbuf}$(printf '%s' "$_cl_hdr_buf" | sed 's/$/\x1b[K/')"$'\n'
                                    [ -n "$_cl_pre_out" ] && _fbuf="${_fbuf}$(printf '%s\n' "$_cl_pre_out" | sed 's/$/\x1b[K/')"$'\n'
                                    _fbuf="${_fbuf}"$'\r\x1b[K\n'
                                elif [ "$_cl_peeked" -eq 1 ]; then
                                    _fbuf="${_fbuf}"$'\033[?25l\033[2J\033[H'
                                    _fbuf="${_fbuf}$(printf '%s' "$_cl_hdr_buf" | sed 's/$/\x1b[K/')"$'\n'
                                    [ -n "$_cl_pre_out" ] && _fbuf="${_fbuf}$(printf '%s\n' "$_cl_pre_out" | sed 's/$/\x1b[K/')"$'\n'
                                    _fbuf="${_fbuf}"$'\r\x1b[K\n'
                                    _cl_peeked=0
                                elif [ "$_cl_painted" -gt 0 ] && [ "$_cl_painted" -lt "$_term_lines" ]; then
                                    _fbuf="${_fbuf}$(printf '\033[?25l\r\033[K\033[%dA' "$_cl_painted")"
                                else
                                    _fbuf="${_fbuf}"$'\033[?25l\r\033[K\033[6A'
                                    _card_only=1
                                fi

                                if [ "$_card_only" -eq 0 ]; then
                                    _cl_painted=0
                                    if [ "$_need_scroll" -eq 1 ]; then
                                        _s_idx=$_scroll_top
                                        _e_idx=$((_scroll_top + _vp_h))
                                        [ "$_e_idx" -gt "$_total_flat" ] && _e_idx=$_total_flat
                                    else
                                        _s_idx=0
                                        _e_idx=$_total_flat
                                    fi
                                    for ((_fi = _s_idx; _fi < _e_idx; _fi++)); do
                                        _dl="${_cl_flat_lines[$_fi]}"
                                        _dn="${_cl_flat_nums[$_fi]}"
                                        if [ -n "$_dn" ] && [ "$_dn" = "$_cl_nav_cur" ]; then
                                            _pfx="$_pfx_sel"
                                        else
                                            _pfx="  "
                                        fi
                                        _cl_painted=$((_cl_painted + 1))
                                        _vp_drawn=$((_vp_drawn + 1))
                                        _fbuf="${_fbuf}${_cr}${_pfx}${_dl}${_el}${_nl}"
                                    done
                                    if [ "$_need_scroll" -eq 1 ]; then
                                        while [ "$_vp_drawn" -lt "$_vp_h" ]; do
                                            _fbuf="${_fbuf}${_cr}${_el}${_nl}"
                                            _cl_painted=$((_cl_painted + 1))
                                            _vp_drawn=$((_vp_drawn + 1))
                                        done
                                    fi
                                    _cl_painted=$((_cl_painted + 6))
                                fi

                                local _orig_sel="${original_indices[$((_cl_nav_cur - 1))]-}"
                                local _has_scroll=1
                                [ "$_need_scroll" -eq 1 ] && _has_scroll=2
                                if [ -z "${_cl_card_cache[$_cl_nav_cur]-}" ]; then
                                    _cl_card_cache[$_cl_nav_cur]="$(_render_cmd_detail_card "$_cl_nav_cur" "$_orig_sel" "$_has_scroll" "1" "$((display_idx - 1))")"
                                fi
                                _fbuf="${_fbuf}$(_render_page_bar "$_need_scroll" "$_scroll_top" "$_vp_h" "$_total_flat")${_nl}${_cl_card_cache[$_cl_nav_cur]}${_nl}"
                                [ "$_do_home" = "1" ] && _fbuf="${_fbuf}"$'\033[?25h'
                                printf '%s' "$_fbuf"
                            }
                            _cl_render_screen 0

                            old_cmd_choice="$cmd_choice"
                            cmd_choice=""

                            # menu_prompt loop (normal)
                            # menu_prompt loop (pre_commands 통합)
                            while :; do
                                trap 'saveVAR;stty sane;exit' SIGINT SIGTERM EXIT # 트랩 설정
                                history -r
                                if [ -n "$newcmds" ]; then
                                    readxy "$newcmds $newcmds1" && { cmd_choice="$newcmds" && cmd_choice1="$newcmds1"; } || { menu_read "$(menu_prompt "$((display_idx - 1))" "$_need_scroll")" cmd_choice cmd_choice1 1; }
                                    _cl_rc=$?
                                    unset -v newcmds newcmds1
                                else
                                    menu_read "$(menu_prompt "$((display_idx - 1))" "$_need_scroll")" cmd_choice cmd_choice1 1
                                    _cl_rc=$?
                                fi
                                trap - SIGINT SIGTERM EXIT       # 트랩 해제 (이후에는 기본 동작)

                                if [ "$cmd_choice" = "__NAV_UP__" ]; then
                                    _cl_nav_moved=1
                                    _cl_nav_cur=$((_cl_nav_cur - 1))
                                    [ "$_cl_nav_cur" -lt "${_cl_pg_first:-1}" ] && _cl_nav_cur="${_cl_pg_last:-$((display_idx - 1))}"
                                    _cl_ensure_visible
                                    _cl_render_screen 1
                                    cmd_choice=""
                                    cmd_choice1=""
                                    continue
                                elif [ "$cmd_choice" = "__NAV_DOWN__" ]; then
                                    _cl_nav_moved=1
                                    _cl_nav_cur=$((_cl_nav_cur + 1))
                                    [ "$_cl_nav_cur" -gt "${_cl_pg_last:-$((display_idx - 1))}" ] && _cl_nav_cur="${_cl_pg_first:-1}"
                                    _cl_ensure_visible
                                    _cl_render_screen 1
                                    cmd_choice=""
                                    cmd_choice1=""
                                    continue
                                elif [ "$cmd_choice" = "__NAV_PGDN__" ] || [ "$cmd_choice" = "__NAV_RIGHT__" ] || [ "$cmd_choice" = "]" ]; then
                                    [ "$cmd_choice" = "]" ] && printf '\033[1A\r\033[K'
                                    if [ "$_need_scroll" -eq 1 ]; then
                                        _cl_pg_next=$(( (_scroll_top / _vp_h + 1) * _vp_h ))
                                        if [ "$_cl_pg_next" -ge "$_total_flat" ]; then
                                            _cl_nav_cur="${_cl_pg_last:-$((display_idx - 1))}"
                                        else
                                            _scroll_top=$_cl_pg_next
                                            _cl_pick_in_view
                                        fi
                                    else
                                        _cl_nav_cur=$((_cl_nav_cur + 5))
                                        [ "$_cl_nav_cur" -gt "${_cl_pg_last:-$((display_idx - 1))}" ] && _cl_nav_cur="${_cl_pg_last:-$((display_idx - 1))}"
                                    fi
                                    _cl_nav_moved=1
                                    _cl_render_screen 1
                                    cmd_choice=""
                                    cmd_choice1=""
                                    continue
                                elif [ "$cmd_choice" = "__NAV_PGUP__" ] || [ "$cmd_choice" = "__NAV_LEFT__" ] || [ "$cmd_choice" = "[" ]; then
                                    [ "$cmd_choice" = "[" ] && printf '\033[1A\r\033[K'
                                    if [ "$_need_scroll" -eq 1 ]; then
                                        if [ "$_scroll_top" -le 0 ]; then
                                            _cl_nav_cur="${_cl_pg_first:-1}"
                                        else
                                            _scroll_top=$(( ((_scroll_top - 1) / _vp_h) * _vp_h ))
                                            [ "$_scroll_top" -lt 0 ] && _scroll_top=0
                                            _cl_pick_in_view
                                        fi
                                    else
                                        _cl_nav_cur=$((_cl_nav_cur - 5))
                                        [ "$_cl_nav_cur" -lt "${_cl_pg_first:-1}" ] && _cl_nav_cur="${_cl_pg_first:-1}"
                                    fi
                                    _cl_nav_moved=1
                                    _cl_render_screen 1
                                    cmd_choice=""
                                    cmd_choice1=""
                                    continue
                                fi

                                [ "$_cl_rc" -eq 1 ] && cmd_choice="q" # ctrl d 또는 ESC 로 빠져나가는 경우
                                # [#h] 설명 조회("?8" 또는 "?") 처리였다면 목록 제자리에서 다시 입력받는다
                                if cmd_desc_peek; then
                                    _cl_peeked=1
                                    continue
                                fi
                                # flow 메뉴 하위 CMD 화면에서 커서를 움직이지 않고 엔터만 치면 flow 상위메뉴로 복귀
                                if [ -z "${cmd_choice-}" ] && [ "$_cl_nav_moved" -eq 0 ] && nav_peek | grep -q '^flow_'; then
                                    cmd_choice="b"
                                    echo "Back to flow menu... [$(nav_peek | awk -F'|' '{print $1}')]"
                                fi
                                # 빈 Enter 를 치면 현재 커서 항목(초기 1번 또는 이동한 항목) 실행
                                if [ -z "${cmd_choice-}" ] && [ "$_cl_rc" -eq 0 ]; then
                                    cmd_choice="$_cl_nav_cur"
                                fi
                                [ -n "$pre_commands" ] && break
                                [[ -n $cmd_choice ]] && break
                            done
                            readxx $LINENO cmd_choice: $cmd_choice

                            ############ read cmd_choice
                            ############ read cmd_choice

                            # 선택하지 않으면 메뉴 다시 print // 선택하면 실제 줄번호 부여 -> 루프 2회 돌아서 주석 처리됨
                            # 참고) cmd_choice 변수는 최종 명령줄 화면에서 수신값 choice 변수는 메뉴(서브) 화면에서 수신값
                            # cmd_choice 는 4번 골랐다고 4번이 아니고 4번에 해당되는 줄번호를 가짐
                            _cl_last_cur="${_cl_nav_cur:-1}"
                            display_choice="$cmd_choice"
                            [ "$cmd_choice" ] && [[ $cmd_choice == [0-9] || $cmd_choice == [1-9][0-9] ]] && [ "$cmd_choice" -gt 0 ] && cmd_choice=${original_indices[$((cmd_choice - 1))]}
                        } # end of choice_list()
                        ####################### end of choice_list #######################
                        ####################### end of choice_list #######################
                        ####################### end of choice_list #######################

                        # $env 환경파일에서 가져온 명령문 출력 && read cmd_choice
                        # 실제 CMD 목록을 화면에 띄우는 이 시점에 (메뉴목록) 화면을 이력에 남긴다
                        # (relay 1줄메뉴나 CMD 목록을 띄우지 않는 경로에서는 이력을 건드리지 않는다)
                        nav_cmdlist "$title_of_menu" "$sub_menu"
                        choice_list

                        # 명령어 선택후
                        if [ -n "$cmd_choice" ] && { case "$cmd_choice" in [0-9] | [1-9][0-9]) true ;; *) false ;; esac } && [ "$cmd_choice" -ge 1 ] && [ "$cmd_choice" -le "$num_commands" ]; then
                            chosen_command=${chosen_commands[$((cmd_choice - 1))]}
                            # [#h] 선택한 줄에 붙어있던 설명을 함께 챙긴다 (실행 직전 표시용)
                            sel_desc="${chosen_desc[$((cmd_choice - 1))]-}"
                        fi

                    else
                        # 명령줄을 한줄도 찾지 못한경우 -> 오류판정
                        echo "error : num_commands -> $num_commands // sub_menu: $sub_menu // debug: find -> chosen_commands=" && readxy
                        echo ":459"
                        readxx $LINENO submenu 옵션:$sub_menu title_of_menu 필수: $title_of_menu
                        break
                    fi ### end of [ $num_commands -eq 1 ] # 명령줄 출력 부분 완료

                    readxx $LINENO chosen_command $chosen_command
                    #readxx $LINENO cmd_choice: $cmd_choice

                    ###################################################
                    # 명령줄 판단 부분
                    ###################################################

                    # 명령줄이 {submenu_sys} 형태인경우 서브 메뉴 구성을 위해 다시 menufunc 부름
                    # 메뉴가 2중 리프레시 되는 이유 -> 조정 필요 chosen_command

                    # relay menu
                    if [ "$(echo "$chosen_command" | grep "submenu_")" ]; then

                        readxx $LINENO relayrelay cmd_choice: $cmd_choice chosen_command $chosen_command
                        #execute_relay_pre_commands "$title_of_menu" "$chosen_command_sub"
                        menufunc "$chosen_command" "${title_of_menu}"

                    ################ 실졍 명령줄이 넘어온경우
                    ################ 실졍 명령줄이 넘어온경우
                    ################ 실졍 명령줄이 넘어온경우
                    elif [ "$chosen_command" ] && [ "${chosen_command:0:1}" != "#" ]; then
                        echo
                        local skip_vars=0 cmd_is_danger=0
                        if [ "${GOVIEW:-easy}" = "easy" ]; then
                            # [V] 쉬움 모드: 번호 선택 시 확인 카드 (Card UI)
                            show_cmd_card "$chosen_command" "${sel_desc:-${chosen_desc-}}" "${display_choice:-1}" "$((display_idx - 1))"
                            local card_rc=$?
                            if [ $card_rc -eq 1 ]; then
                                # 취소 (n 또는 ESC) -> 목록 제자리로 복귀
                                cmd_choice=""
                                chosen_command=""
                                continue
                            elif [ $card_rc -eq 2 ]; then
                                # e (설정 편집)
                                _CONF_CUR_ITEM="${display_choice:-1}"
                                conf
                                cmd_choice=""
                                chosen_command=""
                                continue
                            elif [ $card_rc -eq 3 ]; then
                                # i (인자 없이 인터랙티브 실행)
                                skip_vars=1
                            fi
                            # 실행 승인 (0 또는 3) - 줄 앞/중간 !!! 모두 감지 후 쏙 제거
                            if rx_match "$chosen_command" '(^|[[:space:];])!!!([[:space:]]|$)'; then
                                cmd_is_danger=1
                                chosen_command="$(printf '%s\n' "$chosen_command" | sed -e 's/^[[:space:]]*!!![[:space:]]*//' -e 's/\([[:space:];]\)!!![[:space:]]*/\1/g')"
                            fi
                            cfm=y
                        else
                            # 기존 명령어 모드 (cmd):
                            # [#h] 이 명령에 붙은 설명(도움말)을 실행 직전에 다시 보여준다
                            if [ -n "${sel_desc:-${chosen_desc-}}" ]; then
                                echo
                                printf '%s\n' "${sel_desc:-${chosen_desc-}}" | sed -e 's/^/\x1b[1;37m  /' -e 's/$/\x1b[0m/'
                                echo
                            fi
                            # Danger 판단 (줄 앞/중간 어디에 !!! 가 있어도 감지 후 쏙 제거)
                            if rx_match "$chosen_command" '(^|[[:space:];])!!!([[:space:]]|$)'; then
                                cmd_is_danger=1
                                chosen_command="$(printf '%s\n' "$chosen_command" | sed -e 's/^[[:space:]]*!!![[:space:]]*//' -e 's/\([[:space:];]\)!!![[:space:]]*/\1/g')"
                                echo -e "--> \x1b[1;31m${chosen_command//@@//}\x1b[0m"
                                echo
                                printf "\x1b[1;33;41;4m !!!Danger!!! \x1b[0m Excute [Y/y/Enter or N/n]: " && read cfm
                            else
                                echo
                                cfm=y
                            fi
                        fi
                        # ;; 로 이어진 명령들은 순차적으로 실행 (앞의 결과를 보고 뒤의 변수를 입력 가능)
                        # 명령즐을 ;; 기준으로 나누어 배열을 만듬
                        if [[ $chosen_command != *"case"* ]] && [[ $chosen_command != *"esac"* ]]; then
                            IFS=$'\n' cmd_array=($(echo "$chosen_command" | sed 's/;;/\n/g')) # 명령어 배열 생성
                            unset IFS
                        else
                            cmd_array=("$chosen_command")
                        fi

                        readxx $LINENO cmd_choice: $cmd_choice

                        local count=1
                        for cmd in "${cmd_array[@]}"; do # 배열을 반복하며 명령어 처리
                            if [ "${skip_vars:-0}" -eq 1 ]; then
                                cmd="$(strip_cmd_vars "$cmd")"
                                [ -z "$cmd" ] && cancel=yes
                            fi

                            echo -e "--> \x1b[1;36;40m${cmd//@@//}\x1b[0m"

                            # 동일한 var 는 제외하고 read // awk '!seen[$0]++'
                            # noDanger
                            if [ "$cfm" == "y" ] || [ "$cfm" == "Y" ] || [ -z "$cfm" ]; then
                              if [ "${skip_vars:-0}" -eq 0 ]; then

                                # 명령줄에 varVAR 형태 기본값 지정을 위한 loop (ex. varA varB 등 한 명령줄에 여러개의 변수요청)
                                ################
                                readvarcount=0
                                while read -r var; do
                                    ################
                                    # 변수 입력시 취소가 들어왔으면 while loop 종료
                                    # echo "readvarcount:$readvarcount var_value:$var_value dvar_value:$dvar_value"
                                    if [ "$readvarcount" -gt 0 ] && { [ "$var_value" = "Cancel" ] || [ "$dvar_value" = "Cancel" ]; }; then
                                        break
                                    fi
                                    var_value=""
                                    dvar_value=""
                                    #echo "init_var_name: $var_name" && readx
                                    IFS=" :"
                                    var_name="var${var#var}"
                                    #echo "IFS var_name: $var_name" && read x
                                    unset IFS

                                    # 변수조정 varVAR.conf -> varVAR ( 변수이름에 점사용 쩨한 ) varVAR.conf -> varVAR 이 변수
                                    if [[ $var_name != *__* ]]; then var_name="${var_name%%.*}" && var_name="${var_name%%:*}" && var_name="${var_name%%-*}"; fi
                                    #if [[ $var_name != *__* ]]; then var_name="${var_name%%.*}"; fi
                                    # 변수조정 varVAR@localhost -> varVAR ( 변수이름에 @사용 제한 )
                                    if [[ $var_name != *__* ]]; then var_name="${var_name#@}" && var_name="${var_name%%@*}"; fi
                                    # 변수조정 varVAR__ -> varAVR ( 변수에__ 이 있지만 기본값이 없을때 )
                                    if [[ $var_name == *__ ]]; then var_name="${var_name%%__*}"; fi
                                    # 순수 var_name 취득 varVAR__abc -> varVAR // varVAR__abc@aaa.com -> varVAR varAVAR@varBVAR__abc
                                    # temp_prefix="${var_name%%__*}"
                                    # org_var_name="${temp_prefix%@*}" # 입력부터 @ 를 기준으로 변수 분리 되도록 조정
                                    org_var_name="${var_name%%__*}"
                                    pre_var_value="${!org_var_name}" # 사전에 입력했던 값이 있으면 변수설정

                                    # 기본값이 있을때 파싱
                                    if [[ $var_name == *__[a-zA-Z0-9.@-]* ]]; then

                                        # @space@ -> 공백 치환
                                        # @dot@ -. 점 치환
                                        # @@ -> / 치환
                                        dvar_value="${var_name#*__}" && dvar_value="${dvar_value//@dot@/.}" && dvar_value="${dvar_value//@space@/ }" && dvar_value="${dvar_value//@colon@/:}" && dvar_value="${dvar_value//@@/\/}"
                                        # __ 를 구분으로 배열생성
                                        # dvar_value_array=($(echo "$dvar_value" | awk -F'__' '{for(i=1;i<=NF;i++)print $i}'))

                                        IFS=$'\n' # 개행(\n)을 기준으로만 나누도록 설정
                                        dvar_value_array=()
                                        while read -r item; do
                                            dvar_value_array=("${dvar_value_array[@]}" "$item")
                                        done < <(echo "$dvar_value" | awk -F'__' '{for(i=1;i<=NF;i++)print $i}')
                                        unset IFS # 원래 상태로 복구

                                        #printarr dvar_value_array

                                        # 현재 시간을 기본값으로 넣고자 할때 datetag(ymd) or datetag2(ymdhms) 사용 adatetag 는 letter 로 시작하는 제한이 있을때
                                        [ "$dvar_value" == "datetag" ] && dvar_value=$(datetag)   # ymd
                                        [ "$dvar_value" == "datetag2" ] && dvar_value=$(datetag2) # ymd_hms
                                        [ "$dvar_value" == "adatetag" ] && dvar_value=at_$(datetag)
                                        [ "$dvar_value" == "adatetag2" ] && dvar_value=at_$(datetag2)
                                        [ "$dvar_value" == "publicip" ] && dvar_value=$publicip
                                        [ "$dvar_value" == "localip" ] && dvar_value=$localip1
                                        [ "$dvar_value" == "guestip" ] && dvar_value=$guestip

                                        # 기본값이 여러개 일때 select 로 선택진행 ex) aa__bb__cc select
                                        if [ ${#dvar_value_array[@]} -gt 1 ]; then
                                            trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
                                            {
                                                # 이전에 선택했던 값이 있으면 함께 출력
                                                if [ -n "${!org_var_name}" ]; then
                                                    # 이전에 사용했던 값이 있을때 // 그중 비밀번호 변수 일때
                                                    if echo "${org_var_name}" | grep -Eq "varPassword|varPW"; then
                                                        masked_dvar_value="${pre_var_value:0:2}$(printf '*%.0s' $(seq 3 ${#pre_var_value}))"
                                                    else
                                                        masked_dvar_value="${pre_var_value}"
                                                    fi

                                                    PS3="==============================================
>>> Prev.selected value: $(tput bold)$(tput setaf 5)$(tput setab 0)${masked_dvar_value//\\/}$(tput sgr0)
>>> Enter Name or Nums. or all $(tput bold)$(tput setaf 5)$(tput setab 0)[${var_name%%__*}]$(tput sgr0): "
                                                else
                                                    PS3="==============================================
>>> Enter Name or Nums. or all $(tput bold)$(tput setaf 5)$(tput setab 0)[${var_name%%__*}]$(tput sgr0): "
                                                fi

                                                # [규칙] 구 bash 호환: local -a x=(...) 복합대입 금지 (선언/대입 분리)
                                                local -a _sel_opts
                                                _sel_opts=("${dvar_value_array[@]}" All Cancel)
                                                [ "${cmd_is_danger:-0}" -eq 0 ] && _sel_opts=("${_sel_opts[@]}" Interactive)
                                                IFS='\n'
                                                select dvar_value in "${_sel_opts[@]}"; do
                                                    reply=$REPLY && break
                                                done
                                                unset IFS
                                                unset PS3
                                            } </dev/tty
                                            trap - INT

                                            # 객관식도 가능하고 주관식도 가능 // 그리고 취사선택 및 all 선택시 모든 요소 출력
                                            if echo "$reply" | tr -d ' ' | grep -q '^[0-9]\+$'; then
                                                # 객관식 (복수선택가능)
                                                selected_values=""
                                                for num in $reply; do
                                                    if echo "$num" | grep -q '^[0-9]\+$' && [ "$num" -ge 1 ] && [ "$num" -le "${#dvar_value_array[@]}" ]; then
                                                        selected_values="$selected_values ${dvar_value_array[$((num - 1))]}"
                                                    elif [ "$num" -eq $((${#dvar_value_array[@]} + 1)) ]; then
                                                        selected_values="All"
                                                    elif [ "$num" -eq $((${#dvar_value_array[@]} + 2)) ]; then
                                                        selected_values="Cancel"
                                                    elif [ "${cmd_is_danger:-0}" -eq 0 ] && [ "$num" -eq $((${#dvar_value_array[@]} + 3)) ]; then
                                                        selected_values="Interactive"
                                                    fi

                                                done
                                                dvar_value="$selected_values"
                                            else
                                                # 주관식
                                                dvar_value="$reply"
                                            fi
                                            # 시작공백제거
                                            dvar_value=$(echo "$dvar_value" | sed 's/^ *//')

                                            if [ "${cmd_is_danger:-0}" -eq 0 ] && { [ "$dvar_value" = "Interactive" ] || [ "$dvar_value" = "i" ] || [ "$dvar_value" = "I" ]; }; then
                                                cmd="$(strip_cmd_vars "$cmd")"
                                                [ -z "$cmd" ] && { cancel=yes && echo "Canceled..."; } || echo "--> Interactive: $cmd"
                                                eval flagof_"${var_name%%__*}"=set
                                                break
                                            fi

                                            # "all"을 입력했을 경우 "All Cancel"을 제외하고 모든 값 출력
                                            if echo "$dvar_value" | grep -qi '^all$'; then
                                                dvar_value=$(printf "%s\n" "${dvar_value_array[@]}" | grep -viE '^all$|^cancel$' | xargs)
                                            fi

                                        # 기본값이 하나일때
                                        else
                                            trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
                                            [ "$(echo "${var_name%%__*}" | grep -i path)" ] && GRN1 && echo "pwd: $(pwd)" && NC
                                            # 이전에 선택했던 값이 있으면 함께 출력
                                            local _var_hint=""
                                            [ "${cmd_is_danger:-0}" -eq 0 ] && _var_hint=" / i:NoArgs"
                                            if [ -n "${!org_var_name}" ]; then
                                                printf "==============================================
>>> Prev.selected value: $(tput bold)$(tput setaf 5)$(tput setab 0)${!org_var_name//\\/}$(tput sgr0)
!!(Cancel:c${_var_hint}) Enter value for ${MAG1}[ ${YRE}${var_name%%__*}${NC}${MAG1} Default:$dvar_value] ${NC}:"
                                            else
                                                printf "==============================================
!!(Cancel:c${_var_hint}) Enter value for ${MAG1}[ ${YRE}${var_name%%__*}${NC}${MAG1} Default:$dvar_value] ${NC}:"
                                            fi

                                            # printf "!!(Cancel:c) Enter value for \e[1;35;40m[${var_name%%__*} Default:$dvar_value] \e[0m: "
                                            readv var_value </dev/tty
                                            trap - INT
                                            [ "$var_value" == "c" ] && var_value="Cancel"
                                            if [ "${cmd_is_danger:-0}" -eq 0 ] && { [ "$var_value" == "i" ] || [ "$var_value" == "I" ]; }; then
                                                cmd="$(strip_cmd_vars "$cmd")"
                                                [ -z "$cmd" ] && { cancel=yes && echo "Canceled..."; } || echo "--> Interactive: $cmd"
                                                eval flagof_"${var_name%%__*}"=set
                                                break
                                            fi
                                        fi
                                        # 이미 값을 할당한 변수는 재할당 요청을 하지 않도록 flag 설정
                                        # 기본값에 @ 허용하지만 변수이름자체는 @ 허용 안함
                                        eval flagof_"${var_name%%__*}"=set
                                        #eval flagof_"${org_var_name}"=set

                                    # 기본값에 쓸수 없는 문자가 들어올경우 종료
                                    elif [[ $var_name == *__[a-zA-Z./]* ]]; then
                                        printf "!!! error -> var: only var[A-Z][a-zA-Z0-9_@-]* -> / 필요시 @@ 로 대체 입력가능 \n " && exit 0

                                    # 변수 기본값이 없을때
                                    else
                                        # 기본 값이 없을때,
                                        # 변수이름에는 점을 사용할수 없으며, 점 앞까지가 변수이름으로 지정
                                        # var_name=${var_name%%.*}
                                        # $HOME/go.private.env 에 정의된 변수가 있을때
                                        # 이전에 동일한 이름 변수에 값이 할당된 적이 있을때

                                        temp_prefix="${var_name%%__*}"
                                        org_var_name="${temp_prefix%@*}"

                                        if [ "${!var_name}" ] || [ "${!var_name%%__*}" ]; then
                                            dvar_value="${!var_name}"
                                            # 변수에서 \ 제거 - 오작동
                                            dvar_value=${dvar_value//\\/}
                                            # 이미 설정한 변수는 pass
                                            if [ "$(eval echo \"\${flagof_"${var_name%%__*}"}\")" == "set" ]; then
                                                var_value="$dvar_value"
                                                :
                                            else
                                                # 이전에 사용했던 값이 있을때 // 그중 비밀번호 변수 일때
                                                if echo "${var_name}" | grep -Eq "varPassword|varPW"; then
                                                    masked_dvar_value="${dvar_value:0:2}$(printf '*%.0s' $(seq 3 ${#dvar_value}))"
                                                else
                                                    masked_dvar_value="${dvar_value}"
                                                fi
                                                trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
                                                local _env_hint=""
                                                [ "${cmd_is_danger:-0}" -eq 0 ] && _env_hint=" / i:NoArgs"
                                                #printf "!!(Cancel:c) Enter value for \e[1;35;40m[ ${var_name} env Default:$masked_dvar_value ] \e[0m:"
                                                printf "!!(Cancel:c${_env_hint}) Enter value for ${MAG1}[ ${YRE}${var_name}${NC}${MAG1} env Default:$masked_dvar_value ] ${NC}:"
                                                readv var_value </dev/tty
                                                trap - INT
                                                [ "$var_value" == "c" ] && var_value="Cancel"
                                                if [ "${cmd_is_danger:-0}" -eq 0 ] && { [ "$var_value" == "i" ] || [ "$var_value" == "I" ]; }; then
                                                    cmd="$(strip_cmd_vars "$cmd")"
                                                    [ -z "$cmd" ] && { cancel=yes && echo "Canceled..."; } || echo "--> Interactive: $cmd"
                                                    eval flagof_"${var_name%%__*}"=set
                                                    break
                                                fi
                                                eval flagof_"${var_name%%__*}"=set
                                                #eval flagof_"${org_var_name}"=set
                                            fi

                                        else
                                            trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
                                            [ "$(echo "${var_name}" | grep -i path)" ] && GRN1 && echo "pwd: $(pwd)" && NC
                                            if [ "${cmd_is_danger:-0}" -eq 0 ]; then
                                                if [ "$GOLANG" = "kr" ]; then
                                                    printf "!!(Enter:%s / i:%s) Enter value for \e[1;35;40m[$var_name]\e[0m:" "$(ko "취소")" "$(ko "인자없이 실행")"
                                                else
                                                    printf "!!(Enter:Cancel / i:NoArgs) Enter value for \e[1;35;40m[$var_name]\e[0m:"
                                                fi
                                            else
                                                printf "Enter value for \e[1;35;40m[$var_name]\e[0m:"
                                            fi
                                            readv var_value </dev/tty
                                            trap - INT
                                            if [ "${cmd_is_danger:-0}" -eq 0 ] && { [ "$var_value" == "i" ] || [ "$var_value" == "I" ]; }; then
                                                cmd="$(strip_cmd_vars "$cmd")"
                                                [ -z "$cmd" ] && { cancel=yes && echo "Canceled..."; } || echo "--> Interactive: $cmd"
                                                eval flagof_"${var_name%%__*}"=set
                                                break
                                            fi
                                            # ' " \ ->quoting
                                            if printf "%s" "$var_value" | grep -qE "[\\'\"]"; then
                                                var_value="$(printf %q "$var_value")"
                                            fi
                                            #echo "$var_value" && readx
                                            eval flagof_"${var_name%%__*}"=set
                                            #eval flagof_"${org_var_name}"=set
                                        fi

                                        # 변수 이름에 nospace 가 있을때 ex) varVARnospace
                                        # 들어온값 space -> , 로 치환
                                        [[ ${var_name} == *nospace ]] && var_value="${var_value// /,}"
                                    fi
                                    echo

                                    # 변수 파싱 끝 최종
                                    # 변수에 read 수신값 할당
                                    #
                                    # 입력값 없지만 기본값 있을때
                                    if [ ! "$var_value" ] && [ "$dvar_value" ]; then
                                        # 변수의 기본값을 지정 (varABC__22) 기본값은 숫자와영문자만 가능
                                        if [[ $var_name == *__[a-zA-Z0-9.@-]* ]]; then
                                            var_value="$dvar_value"
                                        elif [ "${!var_name}" ]; then
                                            var_value="$dvar_value"
                                        fi
                                    # 입력값 없거나 cancel 일때
                                    elif [ -z "$var_value" ] || [ "$var_value" == "Cancel" ]; then
                                        { cancel=yes && echo "Canceled..." && eval flagof_"${var_name%%__*}"=set && break; }
                                    # 입력값 있을때
                                    else
                                        # echo "here var_name~~:$var_name // var_value~~:$var_value" ;
                                        :
                                    fi
                                    # 최종 var_value(직접 입력 및 env Default 포함) 앞뒤 공백 및 ANSI/제어문자 제거 (Bash 2.05 호환)
                                    local _esc_ch=$'\033'
                                    var_value="$(printf '%s' "$var_value" | sed -e "s/${_esc_ch}\\[[0-9;]*[a-zA-Z]//g" -e 's/[[:cntrl:]]//g')"
                                    var_value="${var_value#"${var_value%%[![:space:]]*}"}"
                                    var_value="${var_value%"${var_value##*[![:space:]]}"}"
                                    if [[ $var_name == varDomain* ]]; then
                                        var_value="${var_value#http://}"
                                        var_value="${var_value#https://}"
                                        var_value="${var_value%%/*}"
                                        var_value="${var_value//[[:space:]]/}"
                                    fi

                                    # varVAR 를 실제값으로 변환
                                    # 1. var_name을 sed 정규식 패턴에 안전하게 사용하도록 이스케이프 (동일)
                                    regex_safe_var_name=$(printf '%s' "$var_name" | sed 's/[.^$*\[\]\\]/\\&/g')

                                    # 2. var_value를 sed 치환 문자열에 안전하게 사용하도록 이스케이프 (구분자 # 포함 - 동일)
                                    escaped_value=$(printf '%s' "$var_value" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e 's/#/\\#/g')

                                    # 순환하면서 varVAR 변환 11:11 같이 숫자: 이 포함된 경우 sed 에서 발작증상 \1 와 충돌
                                    tmp_token="__REPL_TOKEN__"
                                    #readxy "before / regex_safe_var_name $regex_safe_var_name"
                                    #while echo "$cmd" | grep -Eq "(^|[^a-zA-Z0-9])$regex_safe_var_name([^a-zA-Z0-9]|$)"; do
                                    counter=0
                                    while echo "$cmd" | grep -Eq "$regex_safe_var_name([^a-zA-Z0-9]|$)"; do
                                        if ((counter++ > 20)); then
                                            echo "ERROR: Possible infinite loop detected"
                                            break
                                        fi
                                        #readxy "regex_safe_var_name $regex_safe_var_name // {tmp_token} ${tmp_token}"
                                        #echo "DEBUG: Trying to replace '$regex_safe_var_name' in '$cmd'"
                                        #cmd=$(printf '%s' "$cmd" | sed -e "s:\(^\|[^a-zA-Z0-9]\)$regex_safe_var_name\([^a-zA-Z0-9]\|$\):\\1${tmp_token}\\2:")
                                        # 구 sed(3.x/4.1.x) 호환: sed -E 대신 기본 정규식(sed -e) 사용
                                        escaped_regex_safe_var_name=$(printf '%s' "$regex_safe_var_name" | sed -e 's/[]\/$*.^:[]/\\&/g')
                                        cmd=$(printf '%s' "$cmd" | sed -e "s:$escaped_regex_safe_var_name\([^a-zA-Z0-9]\|$\):${tmp_token}\\1:g")
                                        #echo "DEBUG: After : '$cmd'"
                                        cmd="${cmd//$tmp_token/$escaped_value}"
                                    done
                                    #echo "===before====" ; declare -f "$escaped_value"
                                    # unset bug?? .. delete func()
                                    #unset $escaped_value
                                    #echo "===after=====" ; declare -f "$escaped_value"

                                    unset -v escaped_value

                                    #echo "here~~~ var_namme: //$var_name// var_valuue: //$var_value//" && read x < /dev/tty

                                    # 실행중 // 동일 이름 변수 재사용 export
                                    # 기본값이 주어진 변수도 재사용 export
                                    # [ "$var_value" ] && eval "export ${var_name%%__*}='${var_value}'"
                                    if ! printf "%s" "$var_value" | grep -qE "[\\'\"]"; then
                                        [ "$var_value" ] && export ${var_name%%__*}="$(printf %q "$var_value")"
                                        #[ "$var_value" ] && export ${org_var_name}="$(printf %q "$var_value")"
                                    fi

                                    # while loop count
                                    readvarcount=$((readvarcount + 1))

                                    #done < <(echo "$cmd" | sed 's/\(var[A-Z][a-zA-Z0-9_.@-]*\)/\n\1\n/g' | sed -n '/var[A-Z][a-zA-Z0-9_.@-]*/p' | awk '!seen[$0]++')
                                    # 변수에는 @ 불가 변수값에는 @ 가능 // 구분하여 변수분할

                                done < <(echo "$cmd" | sed 's/\(var[A-Z][a-zA-Z0-9_.-]*\(__[a-zA-Z0-9_.@-]*\)\?\)/\n\1\n/g' | sed -n '/var[A-Z][a-zA-Z0-9_.-]*/p' | awk '!seen[$0]++')
                              fi

                                ##################
                                # 끝: 명령줄에 varVAR 형태 기본값 지정을 위한 loop (ex. varA varB 등 한 명령줄에 여러개의 변수요청)
                                # end of while read -r var; do
                                ##################

                            else # cfm -> n
                                # Danger item -> canceled
                                cmd="Cancel"
                            fi # end of cfm=y

                            # 해당 메뉴의 선택명령이 딱 하나일때 바로 실행
                            # 한줄짜리 한줄만 하나만
                            if ((${#cmd_array[@]} == 1)); then
                                [ ! "$cancel" == "yes" ] && process_commands "$cmd" "$cfm"
                            else
                                # 명령어가 끝날때 Done... [Enter] print
                                [ ! "$cancel" == "yes" ] && { if ((${#cmd_array[@]} > count)); then process_commands "$cmd" "$cfm" "nodone"; else process_commands "$cmd" "$cfm"; fi; }
                            fi
                            readxx $LINENO cmd_choice: $cmd_choice

                            ((count++))
                        done # end of for
                        unset cancel
                        readxx $LINENO cmd_choice: $cmd_choice

                        # flagof 변수 초기화
                        # 이미 값을 할당한 변수는 재할당 요청을 하지 않도록 flag 설정 -> 초기화
                        #unset $(compgen -v | grep '^flagof_')
                        for flag in $(compgen -v | grep '^flagof_'); do
                            unset ${flag}
                        done

                        # 한줄짜리 한줄만 하나만
                        # 명령줄이 하나일때 실행 loop 종료하고 상위 메뉴 이동
                        #[ $num_commands -eq 1 ] && break
                        if [ "$num_commands" -eq 1 ] || [ "${_non_meta_cnt:-0}" -eq 1 ]; then
                            # 이전에는 ooldscut(파일순서 기준 최근 메뉴) 를 보고 이동해서
                            # 실제 경로와 다른곳으로 튀거나 아무 이동도 안 하는 경우가 있었음
                            # 이력 스택의 바로 위 화면으로 정확히 복귀
                            if [ -n "$NAV_scut" ]; then
                                echo "go to [${NAV_scut}] ${NAV_title}" #; readxy
                                nav_back 1
                            fi
                            break
                        fi

                        # 아래 구문 skip
                        continue

                    fi # end of if [ "$(echo "$chosen_command" | grep "submenu_")" ]; then / elif [ "$chosen_command" ] && [ "${chosen_command:0:1}" != "#" ]; then

                    ################ 실졍 명령줄이 넘어온경우 end
                    ################ 실졍 명령줄이 넘어온경우 end
                    ################ 실졍 명령줄이 넘어온경우 end

                    #
                    # 참고) cmd_choice 변수는 최종 명령줄 화면에서 수신값 // choice 변수는 메뉴(서브) 화면에서 수신값
                    # cmd_choice 4번 메뉴를 골랐다고 4번이 아니고 4번에 해당되는 줄번호를 가짐
                    # direct command sub_menu
                    #
                    # 숫자 명령줄 번호가 선택이 안된 경우 이곳까지 내려옴
                    # lastcmd
                    readxx "번호를 선택받지 못하였다. cmd bottom"
                    readxx $LINENO cmd_choice: $cmd_choice
                    #set -x
                    #[[ -n $cmd_choice && ( $cmd_choice == "0" || ${cmd_choice#0} != "$cmd_choice" || ${cmd_choice//[0-9]/} ) ]] || ! (( cmd_choice >= 1 && cmd_choice <= 99 )) 2>/dev/null &&
                    # 숫자판정 : [[ ]] 안에서 문자열에 -ge 를 쓰면 bash 가 "syntax error in conditional expression" 을 뱉고
                    # case 자체가 실행되지 않았음 → 숫자인지 먼저 expr 로 확인한다
                    if [ -n "$cmd_choice" ] && { [ "$cmd_choice" = "0" ] || [ "${cmd_choice#0}" != "$cmd_choice" ] || [ -n "${cmd_choice//[0-9]/}" ] || { expr "$cmd_choice" : '[0-9][0-9]*$' >/dev/null 2>&1 && [ "$cmd_choice" -ge 100 ]; }; }; then
                        case "$cmd_choice" in
                            "]" | "[" | "A" | "all" | "I" | "II") ;;
                            *)
                                YEL1
                                echo
                                echo "check your cmd_choice: $cmd_choice"
                                NC
                                ;;
                        esac
                        case "$cmd_choice" in
                        # --- Pagination ---
                        "]")
                            [ "$_cmd_page" -lt "$_cmd_total_pages" ] && _cmd_page=$((_cmd_page + 1)) || _cmd_page=1
                            _cmd_page_all=0
                            continue
                            ;;
                        "[")
                            [ "$_cmd_page" -gt 1 ] && _cmd_page=$((_cmd_page - 1)) || _cmd_page=$_cmd_total_pages
                            _cmd_page_all=0
                            continue
                            ;;
                        "A" | "all")
                            _cmd_page_all=$((1 - ${_cmd_page_all:-0}))
                            continue
                            ;;
                        # --- View Mode Toggle ---
                        "V" | "v")
                            goview_toggle
                            continue
                            ;;
                        # --- Basic Navigation & Commands ---
                        "0" | "q" | ".")
                            # CMD 목록 → 한 단계 위 화면(메뉴목록)으로 복귀
                            # 기존 grep -B1 방식은 relay 경유 서브메뉴에서 상위메뉴를 분실/오인식함
                            unsetvar varl
                            saveVAR
                            nav_back 1
                            return 0
                            ;;

                        ".." | "sh")
                            bashcomm && continue
                            ;;
                        "..." | "," | "bash")
                            /bin/bash # Start sub-shell
                            continue  # Run cmds after sub-shell exits
                            ;;
                        "m")
                            nav_main
                            return 0
                            ;;
                        # 화면 프롬프트에 안내되지만 이전에는 case 가 없어 동작하지 않던 키들
                        conf.)
                            saveVAR
                            conf_sec $cmd_choice1
                            continue
                            ;;
                        conf | conf1 | confb | confmy | conff | confc | conffc | pconf)
                            saveVAR
                            [ "$cmd_choice" = "conf" ] && [ -z "$cmd_choice1" ] && _CONF_CUR_ITEM="${_cl_last_cur:-1}"
                            "$cmd_choice" $cmd_choice1
                            continue
                            ;;
                        str | search)
                            "$cmd_choice" $cmd_choice1
                            continue
                            ;;
                        I)
                            if menu_index_search "$cmd_choice1"; then
                                savescut
                                menufunc "$(scutsub "$_IDX_TARGET_SCUT")" "$(scuttitle "$_IDX_TARGET_SCUT")" "$(notscutrelay "$_IDX_TARGET_SCUT")"
                                return 0
                            fi
                            continue
                            ;;
                        II)
                            if menu_index_search "${_IDX_LAST_KW:-}"; then
                                savescut
                                menufunc "$(scutsub "$_IDX_TARGET_SCUT")" "$(scuttitle "$_IDX_TARGET_SCUT")" "$(notscutrelay "$_IDX_TARGET_SCUT")"
                                return 0
                            fi
                            continue
                            ;;
                        ff | fff | ffc | fffc | F)
                            if [ "$cmd_choice" = "F" ]; then
                                if [ -z "$cmd_choice1" ]; then
                                    [ "$GOLANG" = "kr" ] && printf ">>> 상세 볼 번호 (예: 2) : " || printf ">>> Item No. to inspect : "
                                    read -r cmd_choice1
                                fi
                                [ -n "$cmd_choice1" ] && { fff "$cmd_choice1"; printf ">>> [Enter] "; read -r _; }
                            else
                                "$cmd_choice" $cmd_choice1
                                case "$cmd_choice1" in
                                    [0-9]*) printf ">>> [Enter] " ; read -r _ ;;
                                esac
                            fi
                            continue
                            ;;
                        F[0-9]*)
                            fff "${cmd_choice#F}"
                            printf ">>> [Enter] " ; read -r _
                            continue
                            ;;
                        format)
                            format
                            continue
                            ;;
                        "restart" | "rest")
                            echo "Restart $gofile.. [$scut]" && sleep 0.5 && savescut && exec "$gofile" "$scut"
                            ;;
                        "b" | "00")
                            savescut && nav_back 1 # 이전 화면으로
                            return 0
                            ;;
                        "bb")
                            savescut && nav_back 2 # 두 단계 이전 화면으로
                            return 0
                            ;;
                        "bbb")
                            savescut && nav_back 3 # 세 단계 이전 화면으로
                            return 0
                            ;;
                        "<" | "before")
                            beforescut=$(st $scut b)
                            echo "Move to Before menu.. [$beforescut]" && sleep 0.5 && savescut && menufunc "$(scutsub "$beforescut")" "$(scuttitle "$beforescut")" "$(notscutrelay "$beforescut")"
                            return 0
                            ;;
                        ">" | "next")
                            nextscut=$(st $scut n)
                            echo "Move to Next menu.. [$nextscut]" && sleep 0.5 && savescut && menufunc "$(scutsub "$nextscut")" "$(scuttitle "$nextscut")" "$(notscutrelay "$nextscut")"
                            return 0
                            ;;
                        "chat" | "ai" | "hi" | "hello")
                            ollama run gemma3 2>/dev/null && continue
                            ;;
                            #"conf")
                            #    conf && continue
                            #    ;;
                            #"confmy")
                            #    confmy && continue
                            #    ;;
                            #"confc")
                            #    confc && continue
                            #    ;;
                            #"conff")
                            #    conff "$cmd_choice1" && continue
                            #    ;;
                            #"conffc")
                            #    conffc && continue
                            #    ;;
                        L)
                            # [L] CMD 화면에서도 언어 전환 (메뉴 화면과 동일 키)
                            #  CMD 목록(chosen_commands)은 listof_comm 계산값이라 언어 전환 후 낡는다.
                            #  재계산 대신 현재 메뉴 목록으로 되돌아가 새 언어로 다시 진입한다(안전·명확).
                            case "$cmd_choice1" in
                                k) _lnew="kr" ;;
                                e) _lnew="en" ;;
                                *) _lnew="$([ "$GOLANG" = "kr" ] && echo en || echo kr)" ;;
                            esac
                            if golang_toggle "$_lnew"; then
                                # 캐시 재구축 후 여기로 돌아와야 scutsub/scuttitle 이 값을 준다
                                build_shortcutarr
                                if [ "$_lnew" = "kr" ]; then
                                    ko "한글 메뉴로 전환 [L] - 저장됨"
                                else
                                    echo "English menu [L] - saved"
                                fi
                                if [ "$scut" != "m" ] && [ -n "$scut" ]; then
                                    menufunc "$(scutsub "$scut")" "$(scuttitle "$scut")" "$(notscutrelay "$scut")"
                                else
                                    nav_main
                                fi
                                continue
                            fi
                            ko "언어 전환 실패 (마스터 파일 없음?) : %s" "$envlang_master"
                            continue
                            ;;
                        "?")
                            # [?] CMD 화면에서도 단축키 안내를 아래쪽에 몇줄 띄운다
                            menu_keyhelp
                            cmd_choice=""
                            cmd_choice1=""
                            continue
                            ;;
                        "h")
                            gohistory && continue
                            ;;
                        "hh")
                            hh && read -rep "[Enter] " x && continue
                            ;;
                        "df")
                            if [[ ! $cmd_choice1 ]]; then
                                { /bin/df -h | grep -vE '^/dev/loop|/var/lib/docker' | sed -e "s/파일 시스템/파일시스템/g" | cgrepn /mnt/ 0 | cper | column -t; } && readnewcmds && continue
                            else
                                /bin/df $cmd_choice1 && readnewcmds && continue
                            fi
                            ;;
                        "t")
                            { htop 2>/dev/null || top; } && continue
                            ;;
                        "tt")
                            { iftop -t 2>/dev/null || (yyay iftop && iftop -t); } && continue
                            ;;
                        "ttt" | "dfm")
                            { dfmonitor; } && continue
                            ;;
                        "em")
                            { mc -b || { yyay mc && mc -b; }; } && continue
                            ;;
                        "e")
                            if [ -f "$cmd_choice1" ]; then cmd_choice1=$(dirname "$cmd_choice1"); fi
                            { ranger "$cmd_choice1" 2>/dev/null || explorer "$cmd_choice1"; } && { [ -s /dev/shm/pwd ] && cd "$(</dev/shm/pwd)" || true; } && dline && RED1 && echo "pwd: $(pwd)" && NC && dline && continue
                            ;;
                        "ee")
                            { ranger /etc 2>/dev/null || explorer /etc; } && { [ -s /dev/shm/pwd ] && cd "$(</dev/shm/pwd)" || true; } && dline && RED1 && echo "pwd: $(pwd)" && NC && dline && continue
                            ;;
                        "eee")
                            { _pwd_t="$( [ -s /dev/shm/pwd ] && cat /dev/shm/pwd || pwd )"; ranger "$_pwd_t" 2>/dev/null || explorer "$_pwd_t"; } && { [ -s /dev/shm/pwd ] && cd "$(</dev/shm/pwd)" || true; } && dline && RED1 && echo "pwd: $(pwd)" && NC && dline && continue
                            ;;
                        "cdr")
                            { [ -s /dev/shm/pwd ] && cd "$(</dev/shm/pwd)" || true; } && dline && RED1 && echo "pwd: $(pwd)" && NC && dline && ls -ltr | tail && bashcomm && continue
                            ;;
                        "ll")
                            { journalctl -n10000 -e; } && continue
                            ;;

                        # --- Default block for complex checks and fallback ---
                        *)
                            #readxy "cmd: [$cmd_choice]"

                            # Check 1: Shortcut menu jump? (Requires $cmd_choice1 empty & match in $shortcutstr)
                            if [[ -z $cmd_choice1 ]] && echo "$shortcutstr" | grep -q "@@@$cmd_choice|"; then
                                readxx $LINENO cmd_choice:"$cmd_choice" shortcut_moving
                                cmd_choice_scut=$cmd_choice

                                #newscut=$cmd_choice
                                #savescut && exec "$gofile" "$cmd_choice" # exec terminates
                                #reaadxy $LINENO
                                # readxy "$LINENO // $choice // $title_of_menu // $chosen_command_sub // $title"
                                if [ -n "$(notscutrelay "$cmd_choice")" ]; then
                                    menufunc "$(scutsub "$cmd_choice")" "$(scuttitle "$cmd_choice")" "$(notscutrelay "$cmd_choice")"
                                else
                                    # relay 메뉴에서 pre_commands 가 이전 메뉴것을 가져오는 것을 방지
                                    #savescut && exec "$gofile" "$cmd_choice"
                                    menufunc "$cmd_choice"
                                fi

                            # Check 2: Alarm? (Numeric, starts with 0, not just "0")
                            elif [[ ! ${cmd_choice//[0-9]/} ]] && [[ ${cmd_choice:0:1} == "0" ]] && [[ $cmd_choice != "0" || $cmd_choice != "00" ]]; then
                                echo "alarm set -> $cmd_choice $cmd_choice1" && sleep 1
                                alarm "$cmd_choice" "$cmd_choice1" && {
                                    echo
                                    readx
                                    continue
                                }

                            # Check 2-1: proxmox vm enter? 100~
                            elif [[ -z $cmd_choice1 ]] && expr "$cmd_choice" : '[0-9][0-9]*$' >/dev/null 2>&1 && [ "$cmd_choice" -ge 100 ] && command -v pct >/dev/null 2>&1; then
                                dline
                                vmslistview | cgrepn running -3 | cgrepn1 $cmd_choice 3
                                readxy "Proxmox vm --> $(RED1)$cmd_choice$(NC) Enter" && enter "$cmd_choice"
                                continue
                            # Check 3: Valid Linux command? (Not purely numeric, exists, and NOT an alias)
                            elif [[ "${cmd_choice//[0-9]/}" ]] && [ "$(type -t "${cmd_choice%%[|;]*}" 2>/dev/null)" != "alias" ] && command -v "${cmd_choice%%[|;]*}" >/dev/null 2>&1; then
                                echo # Newline for formatting
                                echo "Executing command: $cmd_choice $cmd_choice1"
                                process_commands "$cmd_choice $cmd_choice1" y
                                continue

                            # Check 4: Alias from .bashrc? (Fallback if not a command or is an alias)
                            elif [ "${cmd_choice//[0-9]/}" ] && aliascmd=$(grep -E "^[[:space:]]*alias[[:space:]]+${cmd_choice}=" ~/.bashrc 2>/dev/null | tail -n 1 | sed -e "s/^[[:space:]]*alias[[:space:]]*${cmd_choice}=//" -e "s/^['\"]//" -e "s/['\"]$//") && [[ -n $aliascmd ]]; then

                                echo "Executing in subshell with argument '$cmd_choice1': $aliascmd $cmd_choice1"

                                GRN1
                                dline
                                NC
                                # Bash 2.05 ~ 5.x 호환: shopt -s expand_aliases 를 source 보다 먼저 켜고, eval -- 대신 eval 사용
                                trap 'stty sane' SIGINT
                                bash -c 'shopt -s expand_aliases; source ~/.bashrc 2>/dev/null; eval "$0" "$@"' "$cmd_choice" ${cmd_choice1:+"$cmd_choice1"}
                                trap - INT
                                GRN1
                                dline
                                NC

                                # Clean up the temporary variable

                                # Optional: Log execution
                                echo "$cmd_choice $cmd_choice1" >>"$gotmp"/go_history.txt 2>/dev/null
                                echo -en "--> \033[1;34mDone...\033[0m [Enter] " && IFS=' ' read -re newcmds newcmds1 </dev/tty
                                unset -v aliascmd
                                continue

                            # Fallback: Unknown or invalid input
                            else
                                #cmd_choice=""
                                echo "Unknown or invalid command: $cmd_choice $cmd_choice1"
                                #sleep 1 # Give user time to see the message
                                #cmds
                            fi
                            ;;
                        esac
                    fi

                    echo "no hook cmd_choice: $cmd_choice --- pre_commands refresh loop"
                    #unset cmd_choice cmd_choice1
                    cmd_choice=""

                done #        end of      while true ; do # 하부 메뉴 loop 끝 command list

            }

            readxx $LINENO cmds_auto_enter
            # cmds loop 시작
            cmds

            #
            ###############################################################
            # cmds 루프에서 나온후
            ###############################################################

            # 서브 메뉴 쇼트컷 탈출시
            # 메뉴중에 정상범위 숫자도 아니고 메인쇼트컷도 아닌 예외 메뉴 할당
            # readxx end cmds

        #elif -> line of -- if ((choice >= 1 && choice <= 99 && choice <= menu_idx || choice == 99)) 2>/dev/null; then
        ###############################################################################################################
        elif [ "$choice" ]; then
            case "$choice" in
            m) # 메인/서브 메뉴 탈출
                nav_main
                return 0
                ;;
            0 | "q" | .) # 메인/서브 메뉴 탈출 (quit)
                # title_of_menu_sub=""
                # chosen_command_sub=""
                chosen_command=""

                # 서브메뉴에서 탈출할경우 메인메뉴로 돌아옴
                if [ "$title_of_menu_sub" ]; then
                    nav_main
                    return 0
                else
                    saveVAR
                    exit 0
                fi
                ;;
            b | 00)
                savescut && nav_back 1 # 이전 화면으로
                return 0
                ;;
            bb)
                savescut && nav_back 2 # 두 단계 이전 화면으로
                return 0
                ;;
            bbb)
                savescut && nav_back 3 # 세 단계 이전 화면으로
                return 0
                ;;
            df)
                # Original condition checked for ! "$choice1"
                if [ ! "$choice1" ]; then
                    /bin/df -h | grep -vE '^/dev/loop|/var/lib/docker' | sed -e "s/파일 시스템/파일시스템/g" | cgrepn /mnt/ 0 | cper | column -t && readx
                else # Do nothing if choice1 exists, as per original logic implicit structure
                    /bin/df $choice1 && readx
                fi
                ;;
            chat | ai | hi | hello)
                ollama run gemma3 2>/dev/null
                ;;
            h)
                gohistory
                ;;
            t)
                { htop 2>/dev/null || top; }
                ;;
            tt)
                { iftop -t 2>/dev/null || (yyay iftop && iftop -t); }
                ;;
            ttt | dfm)
                { dfmonitor; }
                ;;
            em)
                mc -b || { yyay mc && mc -b; }
                ;;
            "e")
                if [ -f "$choice1" ]; then choice1=$(dirname "$choice1"); fi
                { ranger $choice1 2>/dev/null || explorer; }
                [ -s /dev/shm/pwd ] && cd "$(</dev/shm/pwd)"
                dline && RED1 && echo "pwd: $(pwd)" && NC && dline
                ;;
            "ee")
                { ranger /etc 2>/dev/null || explorer /etc; }
                [ -s /dev/shm/pwd ] && cd "$(</dev/shm/pwd)"
                dline && RED1 && echo "pwd: $(pwd)" && NC && dline
                ;;
            "eee")
                #{ ranger $(</dev/shm/pwd) 2>/dev/null || explorer $(</dev/shm/pwd) ; }
                _pwd_t="$( [ -s /dev/shm/pwd ] && cat /dev/shm/pwd || pwd )"
                ranger "$_pwd_t" 2>/dev/null || explorer "$_pwd_t"
                [ -s /dev/shm/pwd ] && cd "$(</dev/shm/pwd)"
                dline && RED1 && echo "pwd: $(pwd)" && NC && dline
                ;;
            "cdr")
                [ -s /dev/shm/pwd ] && cd "$(</dev/shm/pwd)"
                dline && RED1 && echo "pwd: $(pwd)" && NC && dline && ls -ltr | tail && bashcomm
                ;;
            ll)
                { journalctl -n10000 -e; }
                ;;
            update | uu)
                update
                ;;
            .. | sh) # 내장 함수와 .bashrc alias 를 쓸수 있는 bash
                bashcomm
                ;;
            ... | , | bash) # alias 를 쓸수 있는 bash
                /bin/bash
                ;;
            V | v)
                goview_toggle
                continue
                ;;
            I)
                if menu_index_search "$choice1"; then
                    savescut
                    menufunc "$(scutsub "$_IDX_TARGET_SCUT")" "$(scuttitle "$_IDX_TARGET_SCUT")" "$(notscutrelay "$_IDX_TARGET_SCUT")"
                fi
                continue
                ;;
            II)
                if menu_index_search "${_IDX_LAST_KW:-}"; then
                    savescut
                    menufunc "$(scutsub "$_IDX_TARGET_SCUT")" "$(scuttitle "$_IDX_TARGET_SCUT")" "$(notscutrelay "$_IDX_TARGET_SCUT")"
                fi
                continue
                ;;
            L)
                # [L] 메뉴 언어 즉시 전환 (한글 <-> English)  // 인코딩 변환이 아니다
                #  'kr'(인코딩)과 혼동되지 않으려고 대문자 단일키를 택했다.
                #  go.env [scut] 211개 / go.sh case 라벨 전부에 대문자가 하나도 없어 충돌 0.
                #  L 단독 = 토글 ,  "L k" = 한글 ,  "L e" = English
                case "$choice1" in
                    k) _lnew="kr" ;;
                    e) _lnew="en" ;;
                    *) _lnew="$([ "$GOLANG" = "kr" ] && echo en || echo kr)" ;;
                esac
                if golang_toggle "$_lnew"; then
                    # 캐시를 즉시 재구축한다. 안 하면 scuttitle/scutsub 가 빈 배열을 읽어
                    #   제목이 빈 문자열이 되고 화면이 메인메뉴로 튀는다.
                    build_shortcutarr
                    # 현재 화면 제목만 새 언어로 다시 읽는다.
                    title_of_menu_sub=""
                    title_of_menu=""
                    if [ "$scut" != "m" ] && [ -n "$scut" ]; then
                        title_of_menu_sub="$(golang_title_of "$scut")"
                        title_of_menu="$title_of_menu_sub"
                    fi
                    # chosen_command_sub({submenu_*}) 는 의도적으로 비우지 않는다.
                    #   비우면 print_menulist 가 메인메뉴 분기로 떨어져
                    #   서브메뉴에서 L 을 눌렀는데 메인메뉴로 튀는 문제가 생긴다.
                    #   이 태그는 언어와 무관하다 (%%%e -> %%% 정규화시 {submenu_*} 가 보존됨)
                    if [ "$_lnew" = "kr" ]; then
                        ko "한글 메뉴로 전환 [L] - 저장됨"
                    else
                        echo "English menu [L] - saved"
                    fi
                    continue
                fi
                ko "언어 전환 실패 (마스터 파일 없음?) : %s" "$envlang_master"
                ;;
            krr)
                # 한글이 네모나 다이아몬드 보이는 경우 (콘솔 tty) jftterm
                if [[ $(who am i | awk '{print $2}') == tty[1-9]* ]] && ! ps -ef | grep -q "[j]fbterm"; then
                    which jfbterm 2>/dev/null && jfbterm || (yum install -y jfbterm && jfbterm)
                fi
                ;;

            kr)
                # hangul encoding force chg
                # ssh 로 이곳 저곳 서버로 이동할때 terminal 클라이언트 한글 환경과 서버 한글 환경이 다르면 한글이 깨짐
                if [[ ! "$(file $env | grep -i "utf")" && -s $env ]]; then
                    echo "utf chg" && sleep 1
                    if [[ "$(file "$envorg" | grep -i "utf")" ]]; then
                        cat "$envorg" | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$env"
                    else
                        cat "$envorg" | iconv -f euc-kr -t utf-8//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$env"
                    fi
                    echo >>"$env"
                    if [[ "$(file "$envorg2" | grep -i "utf")" ]]; then
                        cat "$envorg2" | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >>"$env"
                    else
                        cat "$envorg2" | iconv -f euc-kr -t utf-8//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >>"$env"
                    fi
                    #[ "$envko" ] && sed -i 's/^envko=.*/envko=utf8/' $HOME/go.private.env || echo "envko=utf8" >>$HOME/go.private.env
                elif [[ "$(file $env | grep -i "utf")" && -s $env ]]; then
                    echo "euc-kr chg" && sleep 1
                    if [[ "$(file "$envorg" | grep -i "utf")" ]]; then
                        cat "$envorg" | iconv -f utf-8 -t euc-kr//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$env"
                    else
                        cat "$envorg" | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$env"
                    fi
                    echo >>"$env"
                    if [[ "$(file "$envorg2" | grep -i "utf")" ]]; then
                        cat "$envorg2" | iconv -f utf-8 -t euc-kr//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >>"$env"
                    else
                        cat "$envorg2" | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >>"$env"
                    fi

                fi
                # 한글 인코딩 관련 $env 환경파일 수정으로 새로시작
                savescut && exec "$gofile" "$scut"
                ;;
            # alarm: Starts with 0, contains only digits, not just "0"
            #0[1-9][0-9]*)
            0[0-9][0-9]* | 0[0-9]*)
                # Verify it consists *only* of digits, matching original check: ! "${choice//[0-9]/}"
                if [ -z "${choice//[0-9]/}" ]; then
                    echo "alarm set --> $choice $choice1" && sleep 1 && alarm "$choice" "$choice1" && {
                        echo
                        readx
                    }
                # else # If it matches pattern but isn't purely numeric (e.g., "0abc"), fall through to '*'
                #    : # Or potentially handle as an error/unknown command later in '*'
                fi
                ;;

            *) # Handle remaining complex conditions or unrecognized choices
                # shortcut 과 choice 가 동일할때 choice 없음 쌩엔터
                if [[ -z $choice1 ]] && [[ $choice == "$scut" ]]; then
                    echo "이미 '$scut' 화면 입니다. (b: 이전화면 / m: 메인메뉴)" && sleep 1
                    choice=""
                    #readxx $LINENO shortcut move choice $choice

                # Check : proxmox vm enter? 100~
                elif [[ -z $choice1 ]] && expr "$choice" : '[0-9][0-9]*$' >/dev/null 2>&1 && [ "$choice" -ge 100 ] && command -v pct >/dev/null 2>&1; then
                    dline
                    vmslistview | cgrepn running -3 | cgrepn1 $choice 3
                    readxy "Proxmox vm --> $(RED1)$choice$(NC) Enter" && enter "$choice"

                # Check : 범위를 벗어난 번호 (예: 99 는 바로가기 내부값)
                elif expr "$choice" : '[0-9][0-9]*$' >/dev/null 2>&1; then
                    echo "'$choice' 는 이 화면에 없는 번호입니다. (0~$menu_idx 또는 단축키)"
                    choice=""

                # 메뉴/설정 바로가기 (CMD 화면과 동일하게 동작하도록 통일)
                elif [ "$choice" = "conf." ]; then
                    conf_sec $choice1

                elif [ -z "$choice1" ] && case "$choice" in conf | conf1 | confb | confmy | conff | confc | conffc | pconf | str | search | ff | ffc | fffc | format) true ;; *) false ;; esac; then
                    [ "$choice" = "conf" ] && [ -n "${_m_nav_cur:-}" ] && _CONF_CUR_MENU_KEY="${_m_item_keys[$_m_nav_cur]-}"
                    "$choice" $choice1

                # 실제 리눅스 명령이 들어온 경우 실행 (alias 는 Check 4 로 넘김)
                elif [ "${choice//[0-9]/}" ] && [ "$(type -t "$choice" 2>/dev/null)" != "alias" ] && command -v "$choice" >/dev/null 2>&1; then
                    {
                        echo "Executing command: $choice $choice1"
                        process_commands "$choice $choice1" y
                    }

                # choice 가 이까지 왔으면 .bashrc alias 평소 습관처럼 쳤다고 봐야지
                elif [ "${choice//[0-9]/}" ] && aliascmd=$(grep -E "^[[:space:]]*alias[[:space:]]+${choice}=" ~/.bashrc 2>/dev/null | tail -n 1 | sed -e "s/^[[:space:]]*alias[[:space:]]*${choice}=//" -e "s/^['\"]//" -e "s/['\"]$//") && [[ -n $aliascmd ]]; then

                    echo "Executing in subshell with argument '$choice1': $aliascmd $choice1"

                    GRN1
                    dline
                    NC
                    # Bash 2.05 ~ 5.x 호환: shopt -s expand_aliases 를 source 보다 먼저 켜고, eval -- 대신 eval 사용
                    trap 'stty sane' SIGINT
                    bash -c 'shopt -s expand_aliases; source ~/.bashrc 2>/dev/null; eval "$0" "$@"' "$choice" ${choice1:+"$choice1"}
                    trap - INT
                    GRN1
                    dline
                    NC

                    echo "$choice $choice1" >>"$gotmp"/go_history.txt 2>/dev/null
                    echo -en "--> \033[1;34mDone...\033[0m [Enter] " && IFS=' ' read -re newcmds newcmds1 </dev/tty
                    unset -v aliascmd

                fi
                ;;
            esac
        else
            #echo "No hooked!!!! go home!!!" && sleep 0.5 && choice=""
            #choice=""
            unset -v noclear choice
        fi
    done # end of main while
    ############### main loop end ###################
    ############### main loop end ###################
    ############### main loop end ###################
}

##############################################################################################################
##############################################################################################################
# 아래는 go.env 에서 사용가능한 함수 subfunc
##############################################################################################################
##############################################################################################################

# 메뉴 번호(예: 1)를 현재 메뉴의 첫 실행 토큰(함수명/서브메뉴/명령)으로 해석
_resolve_menu_tok() {
    local _n="$1" _ridx _raw _body
    [ "${#_n}" -gt 0 ] || return 1
    case "$_n" in *[!0-9]*) return 1 ;; esac
    [ "$_n" -ge 1 ] 2>/dev/null || return 1
    _ridx="${original_indices[$((_n - 1))]-}"
    [ -n "$_ridx" ] || return 1
    _raw="${chosen_commands[$((_ridx - 1))]-}"
    _body="${_raw#!!!}"
    _body="${_body#"${_body%%[![:space:]]*}"}"
    case "$_body" in
        :[[:space:]]*\;*)
            _body="${_body#*;}"
            _body="${_body#;}"
            _body="${_body#"${_body%%[![:space:]]*}"}"
            ;;
    esac
    _body="${_body%"${_body##*[![:space:]]}"}"
    printf '%s\n' "$_body"
}

# 함수의 내용을 출력하는 함수 ex) fff atqq / fff 1 (메뉴 번호 지원)
fff() {
    local _arg="${1-}" _body _tok
    case "$_arg" in
        ''|*[!0-9]*) declare -f "$@" ;;
        *)
            _body="$(_resolve_menu_tok "$_arg")" || { echo "해당 번호($_arg)를 찾을 수 없습니다."; return 1; }
            _tok="${_body%%[[:space:]]*}"
            if declare -F "$_tok" >/dev/null 2>&1; then
                declare -f "$_tok" | { batcat -l bash 2>/dev/null || cat; }
            elif [ "$_tok" = "$_body" ] && st "$_tok" >/dev/null 2>&1; then
                echo "=== [서브메뉴: $_tok] ==="
                awk -v k="$_tok" '$0 ~ "\\[" k "\\]$"{p=1} p && /^$/{exit} p' "$env"
            else
                echo "=== [명령어 원문 (#$_arg)] ==="
                printf '%s\n' "$_body" | sed -e 's/ *;; */\n;;\n/g' -e 's/ *&& */ \&\&\n    /g' -e 's/ *|| */ ||\n    /g' -e 's/; */;\n/g' | { batcat -l bash 2>/dev/null || cat; }
            fi
            ;;
    esac
}
ff() {
    if [ -z "$1" ]; then
        declare -f
        return
    fi

    local target="$1" _body
    case "$target" in
        *[!0-9]*) ;;
        *)
            _body="$(_resolve_menu_tok "$target")" && target="${_body%%[[:space:]]*}"
            if ! declare -F "$target" >/dev/null 2>&1; then
                fff "$1"
                return
            fi
            ;;
    esac
    _ff_seen_funcs=" $target "

    _ff_inner() {
        local func_name="$1"
        local indent="$2"
        local f defined all_funcs called_funcs line

        # Get all defined functions
        all_funcs=$(declare -F | awk '{print $3}')

        # Extract called functions from the function body
        called_funcs=$(declare -f "$func_name" 2>/dev/null | awk '
            NR > 1 {  # Skip function declaration line
                gsub(/[;(){}]/, " ");  # Replace semicolons and braces with spaces
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^[a-zA-Z_][a-zA-Z0-9_]*$/ &&
                        $i !~ /^(local|echo|if|then|fi|for|do|done|while|return|declare|unset)$/) {
                        print $i
                    }
                }
            }' | sort -u)

        # Print called functions recursively
        for f in $called_funcs; do
            if echo "$all_funcs" | grep -qw "$f" && ! echo "$_ff_seen_funcs" | grep -qw "$f"; then
                _ff_seen_funcs="${_ff_seen_funcs}${f} "
                echo "${indent}${f} () {"
                _ff_inner "$f" "    $indent"
                echo "${indent}}"
                echo
            fi
        done

        # Print the function body
        declare -f "$func_name" 2>/dev/null | sed '1,2d;$d' | while IFS= read -r line; do
            echo "${indent}${line}"
        done
    }

    echo "${target} () {"
    _ff_inner "$target" "    "
    echo "}"
    unset _ff_seen_funcs
}

debugon() { sed -i '0,/#debug=y/s/#debug=y/debug=y/' $base/go.sh && exec $base/go.sh $scut; }
debugoff() { sed -i '0,/debug=y/s/debug=y/#debug=y/' $base/go.sh && exec $base/go.sh $scut; }

trapf() {
    trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
    eval $@
    trap - SIGINT
}
ensure_cmd() {
    # ensure_cmd arp net-tools      # arp 명령이 없으면 net-tools 설치
    # ensure_cmd curl               # curl 명령이 없으면 curl 설치
    # ensure_cmd ifconfig net-tools # ifconfig도 net-tools 소속

    local cmd="$1"
    local pkg="${2:-$1}" # 설치할 패키지 이름, 없으면 cmd 이름과 동일

    if ! command -v "$cmd" >/dev/null 2>&1; then
        nohup bash -c "apt install -y $pkg" >/dev/null 2>&1
        #nohup bash -c "apt install -y $pkg" >/dev/null 2>&1 &
    fi
}

ffc() {
    ff "$@" | { batcat -l bash 2>/dev/null || cat; }
}
fffc() {
    fff "$@" | { batcat -l bash 2>/dev/null || cat; }
}

#find() { test -z "$1" && command find . -type f -exec du -m {} + | awk '{if($1>10)printf "\033[1;31m%-60s %s MB\033[0m\n",$2,$1;else printf "%-60s %s MB\n",$2,$1}' || command find "$@"; }
find() { test -z "$1" && command find . -type f -exec du -m {} + | awk '{c="\033[0m"; if($1>1000)c="\033[1;31m"; else if($1>100)c="\033[1;33m"; else if($1>10)c="\033[1;37m"; printf "%s%-60s %s MB\033[0m\n", c, $2, $1}' | less -RX || command find "$@"; }

# go.sh 스크립트 상단 함수 정의하는 곳에 추가

# awk 명령어 래퍼 함수 (-W interactive 지원 체크 및 적용)
# awkf 함수 - stderr 체크, 짧은 버전
awkf() {
    local error_output
    # 테스트 실행하고 표준 에러만 변수에 저장
    error_output=$(awk -W interactive -e "BEGIN{exit}" </dev/null 2>&1 >/dev/null)

    # 에러 메시지에 "unrecognized"가 **없으면**(! grep) 옵션 사용
    if ! echo "$error_output" | grep -q "unrecognized"; then
        awk -W interactive "$@"
    else
        # 에러 메시지가 있으면 옵션 없이 실행
        awk "$@"
    fi
}

sortip() {
    sort -k1,1 -t. -k1,1n -k2,2n -k3,3n -k4,4n
}

# colored ip 공통 엔진 (mode: full | 24 | 16)
#  - 256색 콘솔: 남색/검정 배경에서도 선명한 24색 전경 팔레트 우선 (배경색 남용 방지)
#  - 16색 콘솔 : 어두운 파랑(34) 제외 고대비 전경색 우선 후 배경색 조합
#  - 기존 gsub(IP, ...) 정규식 오매칭/중첩 버그 제거 (순차 슬라이싱 치환)
_cip_run() {
    local _mode="${1:-full}"
    local _c256=0
    case "${TERM:-}|${COLORTERM:-}" in
        *256color*|*truecolor*|*24bit*) _c256=1 ;;
        *)
            local _tc
            _tc="$(tput colors 2>/dev/null)"
            [ -n "$_tc" ] && [ "$_tc" -ge 256 ] 2>/dev/null && _c256=1
            ;;
    esac
    awkf -v MODE="$_mode" -v C256="$_c256" '
    BEGIN {
        if (C256 == 1) {
            nfg = split("51 226 82 213 208 117 156 220 203 147 87 215 120 183 195 178 177 79 210 159 228 111 219 192", PAL, " ")
            nbg = split("236 23 53 58 24 52", BGPAL, " ")
        } else {
            nfg = split("1;36 1;33 1;32 1;35 1;31 1;37 0;36 0;33 0;32 0;35", PAL, " ")
            nbg = split("40 44 45 46 41 42", BGPAL, " ")
        }
        TC = 0
    }
    {
        line = $0
        out = ""
        while (match(line, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
            pre = substr(line, 1, RSTART - 1)
            IP  = substr(line, RSTART, RLENGTH)
            line = substr(line, RSTART + RLENGTH)
            key = IP
            if (MODE == "24") sub(/\.[0-9]+$/, "", key)
            else if (MODE == "16") sub(/\.[0-9]+\.[0-9]+$/, "", key)
            if (!(key in CODE)) {
                if (C256 == 1) {
                    if (TC < nfg) {
                        CODE[key] = sprintf("\033[1;38;5;%sm", PAL[TC + 1])
                    } else {
                        fi = (TC % nfg) + 1
                        bi = (int(TC / nfg) % nbg) + 1
                        CODE[key] = sprintf("\033[1;38;5;%s;48;5;%sm", PAL[fi], BGPAL[bi])
                    }
                } else {
                    if (TC < nfg) {
                        CODE[key] = sprintf("\033[%sm", PAL[TC + 1])
                    } else {
                        fi = (TC % 6) + 1
                        bi = (int(TC / nfg) % nbg) + 1
                        CODE[key] = sprintf("\033[%s;%sm", PAL[fi], BGPAL[bi])
                    }
                }
                TC++
            }
            out = out pre CODE[key] IP "\033[0m"
        }
        print out line
    }' 2>/dev/null
}

# colored ip (1 line multi ip apply)
cip()   { _cip_run full; }

# 실시간 출력 tail -f 등에 즉각 반응
ipc() { ip a | cgrep DOWN | cgrep1 UP | cip; }
ipa() { ip a | cgrep DOWN | cgrep1 UP | cip; }
ipl() { ip l | cgrep DOWN | cgrep1 UP | cip; }

# colored ip cidr/24 -> same color
cip24() { _cip_run 24; }

# colored ip cidr/16 -> same color
cip16() { _cip_run 16; }

# 검색문자열들 색칠(red)
cgrep() {
    awk_cmd=""
    for word in "$@"; do
        escaped_word=${word//\//\\/}
        awk_cmd="${awk_cmd}{gsub(/$escaped_word/, \"\033[1;31m&\033[0m\")}"
    done
    awk "${awk_cmd}{print}"
}
cgrepi() {
    awk_cmd=""
    for word in "$@"; do
        escaped_word=$(printf '%s\n' "$word" | sed 's/[]\/.^$*+?{}[]/\\&/g')
        awk_cmd="${awk_cmd}BEGIN{IGNORECASE=1} {gsub(/$escaped_word/, \"\033[1;31m&\033[0m\")} "
    done
    awk "${awk_cmd}{print}"
}
# 검색문자열들 색칠(yellow)
cgrep1() {
    awk_cmd=""
    for word in "$@"; do
        escaped_word=${word//\//\\/}
        awk_cmd="${awk_cmd}{gsub(/$escaped_word/, \"\033[1;33m&\033[0m\")}"
    done
    awk "${awk_cmd}{print}"
}
# 검색문자열줄을 색칠 (red)
cgrepl() {
    awk_cmd=""
    for word in "$@"; do
        escaped_word=${word//\//\\/}
        awk_cmd="${awk_cmd}\$0 ~ /$escaped_word/ {print \"\\033[1;31m\" \$0 \"\\033[0m\"; next} "
    done
    awk "${awk_cmd}{print}"
}
# 검색문자열줄을 색칠 (yellow)
cgrepline() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat="($pattern)" '
        $0 ~ pat {
            print "\033[1;33m" $0 "\033[0m"
            next
        }
        { print }
    '
}
# 검색문자열줄을 색칠 (red)
cgrepline1() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat="($pattern)" '
        $0 ~ pat {
            print "\033[1;31m" $0 "\033[0m"
            next
        }
        { print }
    '
}
# 탈출코드를 특정색으로 지정
cgrep3132() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat="${pattern}" '{gsub(pat, "\033[1;31m&\033[0;32m"); print $0;}'
}
cgrep3133() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat="${pattern}" '{gsub(pat, "\033[1;31m&\033[0;33m"); print $0;}'
}
cgrep3134() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat="${pattern}" '{gsub(pat, "\033[1;31m&\033[0;34m"); print $0;}'
}
cgrep3135() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat="${pattern}" '{gsub(pat, "\033[1;31m&\033[0;35m"); print $0;}'
}
cgrep3136() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat="${pattern}" '{gsub(pat, "\033[1;31m&\033[0;36m"); print $0;}'
}
cgrep3336() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat="${pattern}" '{gsub(pat, "\033[1;33m&\033[0;36m"); print $0;}'
}
cgrepline3136() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat=".*${pattern}.*$" '{gsub(pat, "\033[1;31m&\033[0;36m"); print $0;}'
}
cgrep3137() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat="${pattern}" '{gsub(pat, "\033[1;31m&\033[0;37m"); print $0;}'
}

cgrepn() {
    # Bash 2 호환: local arr=(...) 금지 -> 선언/대입 분리, 음수 인덱스 금지
    local args
    args=("$@")
    local search_strs
    search_strs=()
    local num_cols=0
    if [ "${#args[@]}" -eq 0 ]; then
        echo "Usage: cgrepn [search_strings...] [num_cols]"
        return 1
    fi
    local last_idx=$((${#args[@]} - 1))
    if echo "${args[$last_idx]}" | grep -qE '^-?[0-9]+$'; then
        num_cols="${args[$last_idx]}"
        search_strs=("${args[@]:0:$last_idx}")
    else
        search_strs=("${args[@]}")
        num_cols=""
    fi
    if [ "${#search_strs[@]}" -eq 0 ]; then
        echo "Error: No search strings provided."
        return 1
    fi
    perl -s -pe '
        BEGIN {
            $color_yellow = "\e[1;33m";  # Bold yellow color
            $color_reset = "\e[0m";      # Reset color
            @search_words = split / /, $search_strs;  # Split search strings
            $num = defined($num_cols) && $num_cols ne "" ? $num_cols : 0;  # Default to 0 if undefined
            if ($num < 0) { $before = -$num; $after = 0; }  # Negative: words before
            elsif ($num > 0) { $before = 0; $after = $num; }  # Positive: words after
            else { $before = 0; $after = 0; }  # Zero: no extra words
        }
        # Highlight the first word only if num_cols=0 and any search word is present in the line
        if (defined($num_cols) && $num_cols eq "0") {
            my $line = $_;
            my $should_highlight = 0;
            foreach my $search (@search_words) {
                if ($line =~ /\Q$search\E/) {
                    $should_highlight = 1;
                    last;
                }
            }
            if ($should_highlight) {
                s/^(\S+)/$color_yellow$1$color_reset/;
            }
        }
        foreach my $search (@search_words) {
            my $pattern;
            if (!defined($num_cols) || $num_cols eq "0") {
                # No num_cols or num_cols=0: highlight only search string
                $pattern = quotemeta($search);
            } else {
                # Highlight search string with before/after words
                $pattern = "(?:\\S+[\\s\\t]*){0,$before}" . quotemeta($search) . "(?:[\\s\\t]*\\S+){0,$after}";
            }
            s/($pattern)/$color_yellow$1$color_reset/g;  # Apply yellow color to matches
        }
    ' -- -search_strs="${search_strs[*]}" -num_cols="$num_cols"
}

cgrepn1() {
    # Bash 2 호환: local arr=(...) 금지 -> 선언/대입 분리, 음수 인덱스 금지
    local args
    args=("$@")
    local search_strs
    search_strs=()
    local num_cols=0
    if [ "${#args[@]}" -eq 0 ]; then
        echo "Usage: cgrepn [search_strings...] [num_cols]"
        return 1
    fi
    local last_idx=$((${#args[@]} - 1))
    if echo "${args[$last_idx]}" | grep -qE '^-?[0-9]+$'; then
        num_cols="${args[$last_idx]}"
        search_strs=("${args[@]:0:$last_idx}")
    else
        search_strs=("${args[@]}")
        num_cols=""
    fi
    if [ "${#search_strs[@]}" -eq 0 ]; then
        echo "Error: No search strings provided."
        return 1
    fi
    perl -s -pe '
        BEGIN {
            $color = "\e[1;31m";  # Bold red color
            $color_reset = "\e[0m";      # Reset color
            @search_words = split / /, $search_strs;  # Split search strings
            $num = defined($num_cols) && $num_cols ne "" ? $num_cols : 0;  # Default to 0 if undefined
            if ($num < 0) { $before = -$num; $after = 0; }  # Negative: words before
            elsif ($num > 0) { $before = 0; $after = $num; }  # Positive: words after
            else { $before = 0; $after = 0; }  # Zero: no extra words
        }
        # Highlight the first word only if num_cols=0 and any search word is present in the line
        if (defined($num_cols) && $num_cols eq "0") {
            my $line = $_;
            my $should_highlight = 0;
            foreach my $search (@search_words) {
                if ($line =~ /\Q$search\E/) {
                    $should_highlight = 1;
                    last;
                }
            }
            if ($should_highlight) {
                s/^(\S+)/$color$1$color_reset/;
            }
        }
        foreach my $search (@search_words) {
            my $pattern;
            if (!defined($num_cols) || $num_cols eq "0") {
                # No num_cols or num_cols=0: highlight only search string
                $pattern = quotemeta($search);
            } else {
                # Highlight search string with before/after words
                $pattern = "(?:\\S+[\\s\\t]*){0,$before}" . quotemeta($search) . "(?:[\\s\\t]*\\S+){0,$after}";
            }
            s/($pattern)/$color$1$color_reset/g;  # Apply yellow color to matches
        }
    ' -- -search_strs="${search_strs[*]}" -num_cols="$num_cols"
}

# 필드의 공백을 유지하면서 검색어 색칠(python)
cgrepfN() {
    [ $# -lt 2 ] && {
        echo "Usage: cgrepfN <field> <word>..." >&2
        return 1
    }
    expr "$1" : '^[0-9]\+$' >/dev/null && [ "$1" -gt 0 ] || {
        echo "Error: Field must be a positive number" >&2
        return 1
    }
    field=$1
    shift
    [ $# -eq 0 ] && {
        echo "Error: No valid words" >&2
        return 1
    }
    python3 -c '
import sys, re
field = int(sys.argv[1]) - 1
words = sys.argv[2:]
for line in sys.stdin:
    prefix = re.match(r"[ \t]*", line).group()
    parts = re.split(r"([ \t]+)", line.rstrip("\n"))
    fields = [p for i, p in enumerate(parts) if i % 2 == 0]
    seps = [p for i, p in enumerate(parts) if i % 2 == 1]
    if len(fields) >= field + 1:
        for word in words:
            fields[field] = re.sub(r"\b" + re.escape(word) + r"\b", "\033[1;31m" + word + "\033[0m", fields[field])
        line = prefix
        for i in range(len(fields)):
            line += fields[i]
            if i < len(seps):
                line += seps[i]
        print(line)
    else:
        print(line, end="")
' "$field" "$@"
}

# 특정 필드에 검색어가 있을때 색칠
_cgrepfN() {
    local field="$1"
    shift
    local script=''

    for word in "$@"; do
        escaped=$(printf '%s\n' "$word" | sed 's/[]\/.^$*+?{}[]/\\&/g')
        script="${script} if (\$$field ~ /${escaped}/) gsub(/${escaped}/, \"\033[1;31m&\033[0m\", \$$field);"
    done

    awk "{${script} print}"
}

cgrepf1() { cgrepfN 1 "$@"; }
cgrepf2() { cgrepfN 2 "$@"; }
cgrepf3() { cgrepfN 3 "$@"; }
cgrepf4() { cgrepfN 4 "$@"; }
cgrepf5() { cgrepfN 5 "$@"; }

# 한 줄에 세미콜론(;)으로 이어진 다중 명령 사이에 자동으로 46칸 구분선(---) 삽입
#  - 따옴표('...', "..."), $(...), (...), 제어문(if/for/while/case), 변수대입/export/cd 등은 안전하게 제외
_inject_cmd_sep() {
    local _in="$1"
    case "$_in" in
        *\;*) ;;
        *) printf '%s\n' "$_in"; return 0 ;;
    esac
    printf '%s\n' "$_in" | awk '
    BEGIN {
        sep = "----------------------------------------------"
    }
    {
        s = $0
        n = length(s)
        out = ""
        seg = ""
        sq = 0; dq = 0; esc = 0; paren = 0
        for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (esc) {
                out = out c; seg = seg c; esc = 0; continue
            }
            if (sq) {
                out = out c; seg = seg c
                if (c == "\047") sq = 0
                continue
            }
            if (dq) {
                out = out c; seg = seg c
                if (c == "\\") esc = 1
                else if (c == "\"") dq = 0
                continue
            }
            if (c == "\\") { out = out c; seg = seg c; esc = 1; continue }
            if (c == "\047") { out = out c; seg = seg c; sq = 1; continue }
            if (c == "\"") { out = out c; seg = seg c; dq = 1; continue }
            if (c == "(") { paren++; out = out c; seg = seg c; continue }
            if (c == ")" && paren > 0) { paren--; out = out c; seg = seg c; continue }
            if (c == "{" && paren == 0) { out = out c; seg = ""; continue }

            if (c == ";" && paren == 0) {
                # ;; (case 종료자 등) 은 그대로 통과
                if (i < n && substr(s, i + 1, 1) == ";") {
                    out = out ";;"; seg = ""; i++; continue
                }
                # 뒤쪽 첫 토큰 확인
                rest = substr(s, i + 1)
                sub(/^[ \t]+/, "", rest)
                next_tok = rest
                sub(/[ \t;)}&|].*$/, "", next_tok)

                # 앞쪽 세그먼트 정리
                prev = seg
                gsub(/^[ \t]+|[ \t]+$/, "", prev)
                prev_first = prev
                sub(/[ \t].*$/, "", prev_first)
                prev_last = prev
                sub(/^.*[ \t]/, "", prev_last)

                skip = 0
                if (prev == "" || rest == "") skip = 1
                if (rest ~ /^[})#]/) skip = 1
                if (next_tok ~ /^(then|do|done|fi|else|elif|esac|in)$/) skip = 1
                if (prev_last ~ /^(&&|then|do|else|elif|in|\|\|)$/) skip = 1
                if (prev ~ /^[A-Za-z_][A-Za-z0-9_]*=/) skip = 1
                if (prev_first ~ /^(export|local|unset|cd|alias|unalias|readonly|declare|typeset|trap|set|shopt|ulimit|umask|source|\.|true|false|:|for|while|until|if|elif|case|select)$/) skip = 1
                if (prev ~ /echo[ \t]+["\047]?[-=]{3,}/) skip = 1

                if (skip) {
                    out = out ";"
                } else {
                    out = out "; echo \"" sep "\";"
                }
                seg = ""
                continue
            }
            out = out c
            seg = seg c
        }
        print out
    }'
}

safe_eval() {
    local cmd="$1" re='(^|[[:space:]])(rm[[:space:]]+-rf[[:space:]]+/[[:space:]]*($|[[:space:]]+|#)|reboot|shutdown|mkfs)([[:space:]]|$)|\>\s*/etc/(passwd|shadow|group)\b|\>\s*/dev/sd[a-z]+\b'
    # ': 라벨 ; 실제명령' 에서 라벨 안의 ( ) < > | & 등으로 eval 문법 오류가 나지 않게 라벨을 제거 (bash2 호환)
    case "$cmd" in
        :[[:space:]]*|' ':[[:space:]]*)
            case "$cmd" in
                *\;*)
                    cmd="${cmd#*;}"
                    case "$cmd" in \;*) cmd="${cmd#;}" ;; esac
                    ;;
                *) return 0 ;;
            esac
            ;;
    esac
    echo "$cmd" | grep -qE "$re" && {
        echo
        RED1
        echo "!!! 위험 명령어 감지!"
        echo "   $cmd"
        NC
        readxy "   실행하시겠습니까?" || return 1
    }
    cmd="$(_inject_cmd_sep "$cmd")"
    if echo "$cmd" | grep -qE '\|[[:space:]]*less(\s|$)'; then
        #eval "$cmd"
        eval "$cmd" </dev/tty
    else
        eval "$cmd"
    fi
}

load() {
    local BOLD=$(tput bold)
    local RED="${BOLD}$(tput setaf 1)"
    local GREEN="${BOLD}$(tput setaf 2)"
    local YELLOW="${BOLD}$(tput setaf 3)"
    local BLUE="${BOLD}$(tput setaf 4)"
    local NC=$(tput sgr0)
    local SIGNIFICANT_THRESHOLD=15

    echo -e "\n${BLUE}=============================================="
    echo "CPU Load Analysis Starting..."
    echo -e "==============================================${NC}\n"

    local cpu_line
    cpu_line=$(LC_ALL=en_US.UTF-8 top -bn1 | grep '^%Cpu' | tr -s ' ' | sed 's/[[:space:]]*$//')

    if [ -z "$cpu_line" ]; then
        echo "${RED}Error: Failed to retrieve CPU stats or 'top' command failed.${NC}"
        return 1
    fi

    #echo "$cpu_line" | od -c
    echo "$cpu_line" | cgrep us sy wa
    #echo "cpu_line: $cpu_line" | cgrepn us sy wa -1
    echo

    local us=0 sy=0 wa=0
    us=$(echo "$cpu_line" | awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /us/) print $i}' | awk '{print int($(NF-1))}')
    sy=$(echo "$cpu_line" | awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /sy/) print int($i)}')
    wa=$(echo "$cpu_line" | awk -F',' '{for(i=NF;i>0;i--) if($i ~ /wa/) {print int($i); break}}')

    if ! echo "$us$sy$wa" | grep -Eq '^[0-9]+$'; then
        echo "${RED}Error: Failed to parse CPU usage values.${NC}"
        echo "Parsed values -> us=$us, sy=$sy, wa=$wa"
        return 1
    fi

    #echo -e "\nParsed values -> us=${us}, sy=${sy}, wa=${wa}"
    echo -e "${BLUE}CPU Usage Summary:${NC}"
    echo " - User (us): ${YELLOW}${us}%${NC}"
    echo " - System (sy): ${YELLOW}${sy}%${NC}"
    echo " - I/O Wait (wa): ${YELLOW}${wa}%${NC}"
    local total=$((us + sy + wa))
    echo " - Total Load: ${YELLOW}${total}%${NC}"

    if [ "$wa" -ge "$SIGNIFICANT_THRESHOLD" ] && [ "$wa" -ge "$sy" ] && [ "$wa" -ge "$us" ]; then
        echo -e "\n${RED}High I/O wait detected. Possible disk bottleneck or NFS issue.${NC}"
    else
        echo -e "\n${GREEN}OK: CPU load looks normal.${NC}"
        return 0
    fi

    while true; do

        echo -e "\n${GREEN}=== Recommended Diagnostic Commands ===${NC}"
        echo "1) iotop (View top I/O processes)"
        echo "2) iostat -xz 1 (Detailed disk stats)"
        echo "3) vmstat 1 (Watch 'b' and 'wa' columns)"
        echo "4) free -h (Memory & swap usage)"
        echo "5) Exit"
        echo -n "Select an option [1-5]: "
        trap 'echo;break' INT
        read ans
        trap - INT

        case "$ans" in
        1) CMD="sudo iotop" ;;
        2) CMD="iostat -xz 1" ;;
        3) CMD="vmstat 1" ;;
        4) CMD="free -h" ;;
        5) break ;;
        *)
            echo "${RED}Invalid option.${NC}"
            continue
            ;;
        esac

        ACTUAL=$(echo "$CMD" | awk '{print ($1=="sudo") ? $2 : $1}')
        if ! command -v "$ACTUAL" >/dev/null 2>&1; then
            echo "${RED}Error: '$ACTUAL' not found. Please install it.${NC}"
            continue
        fi

        [[ $ACTUAL == "iotop" || $ACTUAL == "top" || $ACTUAL == "htop" ]] && clear

        echo -e "\n${YELLOW}▶ Running: $CMD (Ctrl+C to stop)${NC}\n"

        # 메뉴에서 Ctrl+C 눌렀을 때 루프 재시작
        trap 'echo -e "\n${YELLOW}Returning to menu...${NC}";continue' INT
        bash -c "$CMD"
        trap - INT

        echo -e "\n${GREEN}=== Command finished. Returning to menu ===${NC}\n"
    done
}

# 줄긋기 draw line
dline() {
    num_characters="${1:-46}"
    delimiter="${2:-=}"
    printf "%.0s$delimiter" $(seq "$num_characters")
    printf "\n"
}

# 줄긋기와 제목
dlines() {
    local total_len=46
    local title=""
    local last="${!#}"

    if [ "$last" -eq "$last" ] 2>/dev/null && [ "$last" -ge 40 ]; then
        total_len=$last
        set -- "${@:1:$(($# - 1))}"
    fi

    # 줄바꿈 제거 + 양끝 공백 제거
    title="$(echo "$*" | tr '\n' ' ' | sed 's/^ *//;s/ *$//')"

    if [ -z "$title" ]; then
        printf '%.0s=' $(seq "$total_len")
        printf '\n'
        return
    fi

    local middle=" [ $title ] "
    local middle_len=${#middle}
    local remain_len=$((total_len - middle_len))

    if [ "$remain_len" -lt 0 ]; then
        printf "%s\n" "$middle"
    else
        local left_len=$((remain_len / 2))
        local right_len=$((remain_len - left_len))
        printf '%.0s=' $(seq "$left_len")
        printf "%s" "$middle"
        printf '%.0s=' $(seq "$right_len")
        printf '\n'
    fi
}

# Function to hl percentages and optionally format KiB numbers human-readably (-h).
# highlight
hl() {
    # Default thresholds
    local THRESHOLD_TOP=90
    local THRESHOLD_MEDIUM=70
    local THRESHOLD_LOW=50
    local FORMAT_HUMAN=0 # Flag to enable human-readable formatting (assumes KiB input)

    # --- Option Parsing ---
    # Options: -h (human readable KiB), -T/M/L (thresholds), -H (help)
    while getopts "T:M:L:hH" opt; do
        case "$opt" in
        T) THRESHOLD_TOP="$OPTARG" ;;
        M) THRESHOLD_MEDIUM="$OPTARG" ;;
        L) THRESHOLD_LOW="$OPTARG" ;;
        h) FORMAT_HUMAN=1 ;; # Enable human-readable formatting (assumes KiB)
        H)                   # Help option
            echo "Usage: command | hl [options]"
            echo "Highlights percentages and optionally formats numbers human-readably."
            echo
            echo "Options:"
            echo "  -h           Assume input numbers are KiB (Kilobytes) and format human-readably"
            echo "               (K, M, G, T...). Use for 'pvesm status', 'df -k', 'free'."
            echo "               Does not affect % or existing units like in 'df -h'."
            echo "  -T VALUE     Threshold for top usage percentage (red, default: $THRESHOLD_TOP)"
            echo "  -M VALUE     Threshold for medium usage percentage (purple, default: $THRESHOLD_MEDIUM)"
            echo "  -L VALUE     Threshold for low usage percentage (yellow, default: $THRESHOLD_LOW)"
            echo "  -H           Show this help message"
            return 0
            ;;
        *)
            echo "Unknown option: -$OPTARG" >&2
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))

    # --- Input Handling ---
    local input_data
    input_data=$(cat) # Read all input from stdin

    if [[ -z $input_data ]]; then
        if [[ -t 0 ]]; then echo "Error: No input received via pipe or redirection." >&2; else echo "Error: Received empty input." >&2; fi
        echo "Usage: command | hl [options]" >&2
        return 1
    fi

    # --- AWK Processing ---
    # Pass data and options to awk. No input_unit needed as -h implies KiB.
    echo "$input_data" | awk -v top="$THRESHOLD_TOP" \
        -v medium="$THRESHOLD_MEDIUM" \
        -v low="$THRESHOLD_LOW" \
        -v format_human="$FORMAT_HUMAN" \
        '
    # Function to format KiB number into human-readable (K, M, G...) - for -h option
    # Assumes input value is in KiB. Corrected logic for K values.
    function format_kib_to_human(kib_value) {
        kib_value = kib_value + 0; # Ensure numeric

        # Handle zero separately
        if (kib_value == 0) return "0";

        # Define thresholds (powers of 1024 relative to KiB input)
        m_thresh = 1024;    # MiB threshold (in KiB)
        g_thresh = 1024*1024; # GiB threshold (in KiB)
        t_thresh = 1024*1024*1024; # TiB threshold (in KiB)
        p_thresh = 1024*1024*1024*1024; # PiB threshold (in KiB)

        # Determine the appropriate unit and format
        # Refine: Show integer K for values >= 1 KiB and < 1 MiB (1024 KiB)
        if (kib_value < m_thresh)   return sprintf("%dK", kib_value);
        # Show .1f for M, G, T, P
        if (kib_value < g_thresh)   return sprintf("%.1fM", kib_value / m_thresh);
        if (kib_value < t_thresh)   return sprintf("%.1fG", kib_value / g_thresh);
        if (kib_value < p_thresh)   return sprintf("%.1fT", kib_value / t_thresh);
        return sprintf("%.1fP", kib_value / p_thresh);
        # Note: Previous commented out section with apostrophe issue is removed for clarity.
    }

    # ANSI color codes
    BEGIN {
        RED    = "\033[1;31m"; PURPLE = "\033[1;35m"; YELLOW = "\033[1;33m"; RESET  = "\033[0m";
    }

    # Header
    NR == 1 { print; next; }

    # Data lines
    {
        highlighted_first_col = 0;
        for (i = 1; i <= NF; i++) {

            # --- 1. Apply Human-Readable Formatting (-h option assumes KiB input) ---
            # Check if formatting enabled, field is number, and no existing units/percent
            if (format_human && $i ~ /^[0-9]+(\.[0-9]+)?$/ && $i !~ /[KMGTPE%]/) {
                 $i = format_kib_to_human($i);
            }

            # --- 2. Apply Percentage Highlighting (Always runs) ---
            if (match($i, /([0-9]+(\.[0-9]+)?)%/)) {
                original_match = substr($i, RSTART, RLENGTH);
                p = substr(original_match, 1, RLENGTH - 1) + 0;
                color_code = "";
                if      (p >= top)    { color_code = RED; }
                else if (p >= medium) { color_code = PURPLE; }
                else if (p >= low)    { color_code = YELLOW; }
                if (color_code != "") {
                    colored_string = color_code original_match RESET;
                    gsub(original_match, colored_string, $i);
                    if (p >= top) { highlighted_first_col = 1; }
                }
            }
        } # --- End field loop ---

        # --- 3. Highlight First Column if needed ---
        if (highlighted_first_col && index($1, RESET) == 0) { $1 = RED $1 RESET; }

        print;
    }' | column -t
}

# colored percent
#cper() { awk 'match($0,/([5-9][0-9]|100)%/){p=substr($0,RSTART,RLENGTH-1);gsub(p"%","\033[1;"(p==100?31:p>89?31:p>69?35:33)"m"p"%\033[0m")}1'; }
cper() {
    awk '{
    if (match($0,/([5-9][0-9](\.[0-9]+)?|100(\.[0-9]+)?)%/)) {
      p = substr($0, RSTART, RLENGTH-1);
      color = (p+0==100 ? 31 : p+0>=90 ? 31 : p+0>=70 ? 35 : 33);
      gsub(p"%", "\033[1;" color "m" p "%\033[0m");

      # 90% 이상이면 $1 필드도 빨강색(31)으로 강조
      if (p+0 >= 90) {
        $1 = "\033[1;31m" $1 "\033[0m";
      }
    }
    print;
  }'
}

# colored url
courl() { awk '{match_str="https?:\\/\\/[^ ]+";gsub(match_str, "\033[1;36;04m&\033[0m"); print $0;}'; }

# colored host
chost() { awk '{match_str="([a-zA-Z0-9_-]+\\.)*([a-zA-Z0-9_-]+\\.)(com|net|org|co.kr|or.kr|pe.kr|io|co|info|biz|me|xyz)";gsub(match_str, "\033[1;33;40m&\033[0m"); print $0;}'; }

# colored diff
cdiff() {
    local f1 f2 old new R Y N l
    f1="$1"
    f2="$2"
    [ "$f1" -nt "$f2" ] && {
        old="$f2"
        new="$f1"
    } || {
        old="$f1"
        new="$f2"
    }
    #    R='\033[1;31m'
    #    Y='\033[1;33m'
    #    N='\033[0m'
    #    diff -u "$old" "$new" | while IFS= read -r l; do case "$l" in "-"*) printf "${R}${l}${N}\n" ;; "+"*) printf "${Y}${l}${N}\n" ;; *) printf "${l}\n" ;; esac done
    R=$'\033[1;31m'
    Y=$'\033[1;33m'
    N=$'\033[0m'
    diff -u "$old" "$new" | while IFS= read -r l; do case "$l" in "-"*) printf "%s%s%s\n" "$R" "$l" "$N" ;; "+"*) printf "%s%s%s\n" "$Y" "$l" "$N" ;; *) printf "%s\n" "$l" ;; esac done

}

# .vim/backup 의 최신 백업파일과 현재 파일의 차이를 보여줌
vidiff() {
    local backup_dir="$HOME/.vim/backup"

    if [[ -z $1 ]]; then
        echo "Usage: vidiff <filename>"
        return 1
    fi

    local target_file
    target_file=$(basename -- "$1") # 파일명만 추출

    # 가장 최근의 백업 파일 찾기
    local latest_backup
    latest_backup=$(ls -t "$backup_dir"/"$target_file"* 2>/dev/null | head -n 1)

    if [[ -z $latest_backup ]]; then
        echo "No backup file found for $target_file"
        return 1
    fi

    cdiff "$latest_backup" "$1" | less -RX
}

# rbackup diff
gdiff() {
    d="$(cdiff $base/go.sh.1.bak $base/go.sh)"
    [ -n "$d" ] && echo "$d" || cdiff $base/go.sh.2.bak $base/go.sh
    ls -ltr $base | grep 'go.sh.[0-9].bak'
}
gdifff() {
    d="$(cdiff $base/go.env.1.bak $base/go.env)"
    [ -n "$d" ] && echo "$d" || cdiff $base/go.env.2.bak $base/go.env
    ls -ltr $base | grep 'go.env.[0-9].bak'
}
# vi backup file diff
godiff() {
    vidiff $gofile
    ls -al $gofile $envorg
}
godifff() {
    vidiff $envorg
    ls -al $gofile $envorg
}

# colored dir
cdir() { awk '{match_str="(/[a-zA-Z0-9][^ ()|$]+)"; gsub(match_str, "\033[36m&\033[0m"); print $0; }'; }

# cpipe -> courl && cip24 && cdir
cpipe() {
    awkf '
    BEGIN {
        # --- 색상 코드 정의 ---
        clr_rst = "\033[0m"
        clr_red = "\033[1;31m"
        clr_yel = "\033[1;33m"
        clr_grn = "\033[1;32m"
        clr_grn0 = "\033[0;32m"
        clr_blu = "\033[1;34m"
        clr_blu0 = "\033[0;34m"
        clr_cyn = "\033[1;36m"
        clr_cyn0 = "\033[0;36m"
        clr_mag = "\033[1;35m"

        # --- 경로 패턴 정의 (cpipe에서 성공) ---
        pat_path_in_paren = "\\(/[^():[:space:]]+:[0-9]+\\)" # 괄호 안 경로+라인번호
        pat_path_in_quotes = "\"(/[^[:space:]]+)\"" # 따옴표 안 경로
        # pat_path_standalone = "/[[:alnum:]][[:alnum:]._/-]*[[:alnum:]._/-]" # 독립 경로
		pat_path_standalone = "/[^0-9][[:alnum:]._/-]*[[:alnum:]._/-]"  # 숫자로 시작하지 않는 독립 경로
        pat_url = "https?://[^[:space:]]+"  # URL
    }
    {
        # 작업 라인 백업
        line = $0

        # --- 경로 강조 (cpipe 로직, $0에 직접 적용) ---
        if ($0 ~ pat_url) {
            gsub(pat_url, clr_cyn0 "&" clr_rst, $0)
        }
        if ($0 ~ pat_path_in_paren) {
            gsub(pat_path_in_paren, clr_cyn0 "&" clr_rst, $0)
        }
        if ($0 ~ pat_path_in_quotes) {
             gsub(pat_path_in_quotes, clr_cyn0 "&" clr_rst, $0)
        }
        if ($0 ~ pat_path_standalone) {
            gsub(pat_path_standalone, clr_cyn0 "&" clr_rst, $0)
        }

        # --- IP 주소 강조 (old_cpipe 원본 복원) ---
        # 경로 강조 후 line에 저장된 원본으로 IP 처리
        while (match(line, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
            IP = substr(line, RSTART, RLENGTH)
            line = substr(line, 1, RSTART-1) substr(line, RSTART+RLENGTH)
            Prefix = IP; sub(/\.[0-9]+$/, "", Prefix)
            if (!(Prefix in FC)) {
                BN[Prefix] = 1
                if (TC < 6) {
                    FC[Prefix] = 36 - TC
                } else {
                    do {
                        FC[Prefix] = 30 + (TC - 6) % 8
                        BC[Prefix] = (40 + (TC - 6)) % 48
                        TC++
                    } while (FC[Prefix] == BC[Prefix] - 10)
                    if (FC[Prefix] == 37) FC[Prefix]--
                }
                TC++
            }
            if (BC[Prefix] > 0)
                CP = sprintf("\033[%d;%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], BC[Prefix], IP)
            else
                CP = sprintf("\033[%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], IP)
            # $0에 IP 색상 적용 (경로 색상 유지)
            gsub(IP, CP, $0)
        }

        # --- journalctl 특화 강조 (old_cpipe 원본 유지) ---
        gsub(/\[  OK  \]/, clr_cyn "[  OK  ]" clr_rst, $0)
        gsub(/\[FAILED\]/, clr_red "[FAILED]" clr_rst, $0)
        gsub(/\[WARN\]/, clr_yel "[WARN]" clr_rst, $0)
        gsub(/\[INFO\]/, clr_cyn "[INFO]" clr_rst, $0)

        # --- 기타 강조 (old_cpipe 원본 유지) ---
        gsub(/denied|failed|error|authentication failure|timed out|unreachable/, clr_red "&" clr_rst, $0)
        gsub(/UID=[0-9]+|PID=[0-9]+|exe=[^ ]+/, clr_mag "&" clr_rst, $0)
		# 시간
        #gsub(/[0-9]{2}:[0-9]{2}:[0-9]{2}/, clr_yel "&" clr_rst, $0)
		gsub(/([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]/, clr_yel "&" clr_rst, $0)


        # 최종 결과 출력 (개행 보장)
        printf "%s\n", $0
    }'
}

# cpipef() { sed -E "s/([0-9]{1,3}\.){3}[0-9]{1,3}/\x1B[1;33m&\x1B[0m/g;  s/(https?:\/\/[^ ]+)/\x1B[1;36;04m&\x1B[0m/g" ; }
cpipef() { sed "s/\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}/\x1B[1;33m&\x1B[0m/g;  s/\(https\?\:\/\/[^ ]\+\)/\x1B[1;36;04m&\x1B[0m/g"; }

# color_alternate_lines
stripe() { awk '{printf (NR % 2 == 0) ? "\033[37m" : "\033[36m"; print $0 "\033[0m"}'; }

# ansi ex) RED ; echo "haha" ; BLU ; echo "hoho" ; NC
RED() { echo -en "\033[31m"; }
GRN() { echo -en "\033[32m"; }
YEL() { echo -en "\033[33m"; }
BLU() { echo -en "\033[34m"; }
MAG() { echo -en "\033[35m"; }
CYN() { echo -en "\033[36m"; }
WHT() { echo -en "\033[37m"; }
NC() { echo -en "\033[0m"; }

# 밝은색
RED1() { echo -en "\033[1;31m"; }
GRN1() { echo -en "\033[1;32m"; }
YEL1() { echo -en "\033[1;33m"; }
BLU1() { echo -en "\033[1;34m"; }
MAG1() { echo -en "\033[1;35m"; }
CYN1() { echo -en "\033[1;36m"; }
WHT1() { echo -en "\033[1;37m"; }
YBL() { echo -en "\033[1;33;44m"; }
YRE() { echo -en "\033[1;33;41m"; }

# noansi
noansised() { sed 's/\\033\[[0-9;]*[MKHJm]//g'; }
noansi() { perl -p -e 's/\e\[[0-9;]*[MKHJm]//g' 2>/dev/null; } # Escape 문자(ASCII 27) 를 모두 동일하게 인식 \033, \x1b, 및 \e 모두 처리가능

# pipe 로 넘어온 줄의 모든 필드를 select 구분자-> 빈칸 빈줄 파이프(|}
pipemenu() {
    local prompt_message="$@"
    #[ -n "$prompt_message" ] && dlines "$prompt_message"
    PS3="==============================================
>>> ${prompt_message:+"$prompt_message - "}Select No. : "
    IFS=$' \n|'
    #items=$( while read -r line; do awk '{print $0}' < <(echo "$line"); done ; echo "Cancel" ; )
    items="$(
        cat
        echo Cancel
    )"
    #{ [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && export pipeitem="$item" && break; done </dev/tty; }
    # Cancel 번호가 자꾸 바껴서 0번 누르면 Cancel 처리 되게 조정
    #{ [ "$items" ] && select item in $items; do [[ "$REPLY" == 0 ]] && export pipeitem="Cancel" && echo "Cancel" && break || { [ -n "$item" ] && export pipeitem="$item" && echo "$item" && break; }; done </dev/tty; }
    { [ "$items" ] && select item in $items; do [[ $REPLY == 0 || $REPLY == [Qq] || -z $item ]] && export pipeitem="Cancel" && echo "Cancel" && break || { [ -n "$item" ] && export pipeitem="$item" && echo "$item" && break; }; done </dev/tty; }

    #[ $pipeitem == "Cancel" ] && echo && echo "Pressing 0 is treated as Cancel." > /dev/tty
    unset IFS
    unset PS3
    [ "$pipeitem" = "Cancel" ] && return 1
    return 0
}
# pipemenu alias
pm() { pipemenu "$@"; }

# pipe 로 넘어온 줄의 첫번째 필드를 select
pipemenu1() {
    local prompt_message="$@"
    #PS3="==============================================
    PS3="$(dlines "$prompt_message")
>>> ${prompt_message:+"$prompt_message - "}Select No. : "
    export pipeitem=""
    items=$(
        while read -r line; do echo "$line" | awk '{print $1}'; done
        echo Cancel
    )
    #{ [ "$items" ] && select item in $items; do [[ "$REPLY" == 0 ]] && export pipeitem="Cancel" && echo "Cancel" && break || { [ -n "$item" ] && export pipeitem="$item" && echo "$item" && break; }; done </dev/tty; }
    { [ "$items" ] && select item in $items; do [[ $REPLY == 0 || $REPLY == [Qq] || -z $item ]] && export pipeitem="Cancel" && echo "Cancel" && break || { [ -n "$item" ] && export pipeitem="$item" && echo "$item" && break; }; done </dev/tty; }
    unset PS3
    [ "$pipeitem" = "Cancel" ] && return 1
    return 0
}
_pipemenu1() {
    local prompt_message="$@"
    PS3="==============================================
>>> ${prompt_message:+"$prompt_message - "}Select No. : "
    export pipeitem=""
    items=$(
        while read -r line; do awk '{print $1}' < <(echo "$line"); done
        echo "Cancel"
    )
    { [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && export pipeitem="$item" && break; done </dev/tty; }
    unset PS3
}

# pipe 로 넘어온 라인별로 select
pipemenulist() {
    local prompt_message="$@"
    PS3="==============================================
>>> ${prompt_message:+"$prompt_message - "}Select No. : "
    IFS=$'\n'
    export pipeitem=""
    items=$(
        cat
        echo Cancel
    )
    #{ [ "$items" ] && select item in $items; do [[ "$REPLY" == 0 ]] && export pipeitem="Cancel" && echo "Cancel" && break || { [ -n "$item" ] && export pipeitem="$item" && echo "$item" && break; }; done </dev/tty; }
    { [ "$items" ] && select item in $items; do [[ $REPLY == 0 || $REPLY == [Qq] || -z $item ]] && export pipeitem="Cancel" && echo "Cancel" && break || { [ -n "$item" ] && export pipeitem="$item" && echo "$item" && break; }; done </dev/tty; }
    unset IFS
    unset PS3
    [ "$pipeitem" = "Cancel" ] && return 1
    return 0
}
_pipemenulist() {
    local prompt_message="$@"
    PS3="==============================================
>>> ${prompt_message:+"$prompt_message - "}Select No. : "
    IFS=$'\n'
    export pipeitem=""
    items=$(
        while read -r line; do awk '{print $0}' < <(echo "$line"); done
        echo "Cancel"
    )
    { [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && export pipeitem="$item" && break; done </dev/tty; }
    unset IFS
    unset PS3
}

# clear
fclear() {
    local _i=0
    while [ "$_i" -lt 100 ]; do
        printf '\n'
        _i=$((_i + 1))
    done
    clear
}

# 파이프로 들어온 줄을 dialog 메뉴로 파싱
fdialog() {
    local i=0
    while IFS= read -r line; do
        options[i]="${line%% *}"
        options[i + 1]=$(echo "${line#* }" | awk '{if (NF>1) {$1=$1;print} else {print " "}}')
        ((i += 2))
    done
    choice=$(dialog --clear --stdout --menu "Select option:" 22 76 16 "${options[@]}")
    echo "$choice"
}
fdialogw() {
    local i=0
    while IFS= read -r line; do
        options[i]="${line%% *}"
        options[i + 1]=$(echo "${line#* }" | awk '{if (NF>1) {$1=$1;print} else {print " "}}')
        ((i += 2))
    done
    choice=$(whiptail --clear --menu "Select option:" 22 76 16 "${options[@]}" 3>&1 1>&2 2>&3)
    echo "$choice"
}

# 경로 조정 /abc/de/.././fba/ -> /abc/fba/
realpathf() { while [ $# -gt 0 ]; do
    echo "$1" | sed -e 's/\/\.\//\//g' | awk -F'/' -v OFS="/" 'BEGIN{printf "/";}{top=1; for (i=2; i<=NF; i++) {if ($i == "..") {top--; delete stack[top];} else if ($i != "") {stack[top]=$i; top++;}} for (i=1; i<top; i++) {printf "%s", stack[i]; printf OFS;}}{print ""}'
    shift
done; }

# 파이프로 들어온 각열을 dialog 메뉴로 파싱
fdialog1() {
    local i=0
    while IFS=' ' read -ra words; do for word in "${words[@]}"; do
        options[i]="$word"
        options[i + 1]=" "
        ((i += 2))
    done; done
    choice=$(dialog --clear --stdout --menu "Select option:" 22 76 16 "${options[@]}")
    echo "$choice"
}

# 라인 stripe
pipemenulistc() {
    PS3="==============================================
>>> Select No. : "
    IFS=$'\n'
    items=$(
        while read -r line; do awk '{print $0}' < <(echo "$line"); done | stripe
        echo "Cancel"
    )
    [ "$items" ] && select item in $items; do [ -n "$item" ] && {
        echo "$item"
        echo "$item" | grep -q "Cancel" && export pipeitem="$item" cfm="n" && break || export pipeitem="$item" && break
    }; done </dev/tty
    unset IFS
    unset PS3
}

oneline() {
    tr '\n' ' '
}

# strfunc
# shortcutarr 배열에서 값 추출 // 메뉴 단축키를 입력하면 해당 단축키의 item 모두 출력
# scutall i
# 배열 값 4가지
# 배열 끝에 {...} 항목이 없으면 cmd-choice 있으면 choice 재진입
# notscutrelay 값이 있으면 cmd-choice -> relay 메뉴 출력 없어도 됨
#
# d@@@%%% 서버 데몬 관리 [d] - cmd-choice
# i@@@%%% 시스템 초기설정과 기타 [i]@@@{submenu_sys} - relay - choice
# dd@@@%%% {submenu_hidden}DDoS 공격 관리 [dd] - cmd-choice
# lamp@@@%%% {submenu_sys}>Lamp (apache,php,mysql) [lamp]@@@{submenu_lamp} - relay - choice
# scut2
scutall() {
    scut=$1
    for i in "${!shortcutarr[@]}"; do
        [[ ${shortcutarr[$i]} == *"[$scut]"* ]] && echo "${shortcutarr[$i]}" && return
    done
}
scuttitle() {
    scut=$1
    item="$(scutall $scut)"
    echo "$item" | awk -F'%%% ' '{if (NF > 1) {gsub(/\{[^}]+\}/, "", $2); gsub(/@@@.*/, "", $2); print $2}}'

}
scutsub() {
    scut="$1"
    scutrelayout="$(scutrelay $scut)"
    if [ -n "$scutrelayout" ]; then
        echo "$scutrelayout"
    else
        item="$(scutall $scut)"
        scutsuboutput="$(echo "$item" | awk -F'%%% ' '{if ($2 ~ /^\{[^}]+\}/) {print $2} else {print ""}}' | awk '{match($0, /\{[^}]+\}/); print substr($0, RSTART, RLENGTH)}')"
        if [ -n "$scutsuboutput" ]; then
            echo "$scutsuboutput"
        else
            echo "{}"
        fi
    fi
    #readxx scutsubfunc scutsuboutput:"$scutsuboutput" scutrelayout:"$scutrelayout"
}

# relay 메뉴가 아닌경우만 $scut out "b" "bb" menu
notscutrelay() {
    scut=$1
    item="$(scutall $scut)"
    [ ! "$(echo "$item" | awk '{if (match($0, /\{[^}]+\}$/)) print substr($0, RSTART, RLENGTH)}')" ] && echo $scut
}

# 끝에 {...} 존재하는 배열요소
scutrelay() {
    scut=$1
    item="$(scutall $scut)"
    echo "$item" | awk '{if (match($0, /\{[^}]+\}$/)) print substr($0, RSTART, RLENGTH)}'
}

###############################################################################
# 메뉴 이동 이력 스택 (navigation stack)
#
# 기존 oldscut/ooldscut/oooldscut 방식은 "값이 바뀔 때만 밀기"라서
# 되돌아가기(b)를 연속으로 누르면 A -> B -> A -> B 로 왕복(헛돌이) 하고
# bb(bb 두 단계 뒤)가 현재메뉴를 가리키는 등 경로가 꼬인다.
# 실제 이동 경로를 스택으로 관리해 b/bb/bbb 를 정확히 동작시킨다.
#
# 스택 항목 형식 : "scut|sub|title|"   (|sub| 은 비워도 됨)
#   scut   : 메뉴 단축키 (메인메뉴는 "m")
#   sub    : 서브메뉴 태그 (예: {submenu_sys}) 또는 빈값
#   title  : 화면 제목 (메뉴 제목줄)
###############################################################################
declare -a NAVSTACK
NAV_scut=""    # 현재 화면의 scut
NAV_sub=""     # 현재 화면의 서브메뉴 태그
NAV_title=""   # 현재 화면의 제목
NAV_MAX=32     # 이력 보관 개수 상한

# 현재 화면을 이력에 저장
nav_save() { # $1=scut $2=sub $3=title
    [ -z "$1" ] && return 1
    # 같은 화면을 연속으로 쌓지 않음 (A->B->A 왕복시 이력 오염 방지)
    # (빈 배열에서 음수 인덱스를 쓰면 bash2/3 에서 bad array subscript 오류가 나므로 먼저 비었는지 확인)
    if [ ${#NAVSTACK[@]} -gt 0 ] && [ "${NAVSTACK[$((${#NAVSTACK[@]} - 1))]}" = "$1|$2|$3|" ]; then
        return 0
    fi
    NAVSTACK[${#NAVSTACK[@]}]="$1|$2|$3|"
    [ ${#NAVSTACK[@]} -gt "$NAV_MAX" ] && { unset "NAVSTACK[0]"; NAVSTACK=("${NAVSTACK[@]}"); }
    return 0
}

# 이력 마지막 항목 제거
nav_drop() {
    [ ${#NAVSTACK[@]} -eq 0 ] && return 1
    unset "NAVSTACK[$((${#NAVSTACK[@]} - 1))]"
    NAVSTACK=("${NAVSTACK[@]}")
    return 0
}

# 이력 마지막 항목 확인 (제거 않음)
nav_peek() {
    [ ${#NAVSTACK[@]} -eq 0 ] && return 1
    echo "${NAVSTACK[$((${#NAVSTACK[@]} - 1))]}"
}

# 이력 항목 -> NAV_scut / NAV_sub / NAV_title
nav_set() {
    [ -z "$1" ] && return 1
    NAV_scut="${1%%|*}"
    local rest="${1#*|}"
    NAV_sub="${rest%%|*}"
    NAV_title="${rest#*|}"
    NAV_title="${NAV_title%|}"
    [ -n "$NAV_scut" ] || NAV_scut="m"
    return 0
}

# 이력 초기화 (go.sh 재실행 / 수동 호출용)
nav_reset() {
    NAVSTACK=()
    NAV_scut=""
    NAV_sub=""
    NAV_title=""
    return 0
}

# 화면 전환 : 현재 화면을 이력에 남기고 새 화면으로 이동
nav_goto() { # $1=scut $2=sub $3=title
    [ "$NAV_scut|$NAV_sub" = "$1|$2" ] && return 0 # 같은 화면이면 이력 불필요
    [ -n "$NAV_scut" ] && nav_save "$NAV_scut" "$NAV_sub" "$NAV_title"
    NAV_scut="$1"
    NAV_sub="$2"
    NAV_title="$3"
    [ -n "$NAV_scut" ] || NAV_scut="m"
    return 0
}

# menufunc 진입시 호출 : 진입 컨텍스트(sub, title) 로 이력 동기화
#   $1=sub(또는 scut)  $2=title
#   호출 형태 3가지
#     menufunc                      → ("",        "")
#     menufunc "{submenu_sys}" "타"  → ("{submenu_sys}", "타")
#     menufunc "px"                 → ("px",       "")
nav_sync() {
    local nsub="$1" ntitle="$2" nscut=""
    if [ -n "$nsub" ] && [ "${nsub:0:1}" != "{" ]; then
        if [ -z "$ntitle" ]; then
            ntitle="$(scuttitle "$nsub")" # menufunc "px" 처럼 제목이 없을때
        else
            nsub="" # $1 이 단축키로 넘어온 경우 서브태그 아님
        fi
    fi
    nscut=$(echo "$ntitle" | awk -F'[][]' '{print $2}')
    [ -n "$nscut" ] || nscut="m"
    nav_goto "$nscut" "$nsub" "$ntitle"
}

# CMD 목록 화면 진입 : 메뉴목록 화면을 이력에 남김
nav_cmdlist() { # $1=선택된 메뉴제목  $2=sub_menu
    local cscut
    cscut=$(echo "$1" | awk -F'[][]' '{print $2}')
    [ -n "$cscut" ] || return 0
    nav_goto "$cscut" "$2" "$1"
}

# 이전 화면으로 이동 (b / bb / bbb)
nav_back() { # $1=단계수(기본 1)
    local n="${1:-1}" d="" k iv=""
    for k in $(seq 1 "$n" 2>/dev/null || echo 1); do
        d="$(nav_peek)" || break
        nav_drop
    done
    if [ -z "$d" ]; then
        nav_reset
        echo "◀ 이전 화면 이력이 없습니다. 메인메뉴로 이동합니다."
        menufunc
        return 0
    fi
    nav_set "$d" # 현재 화면을 되돌린것으로 처리 (재 저장 방지)
    # [I] 색인 검색 결과 화면으로 복귀
    if [ "$NAV_scut" = "__IDX__" ]; then
        if menu_index_search "$NAV_title"; then
            savescut
            menufunc "$(scutsub "$_IDX_TARGET_SCUT")" "$(scuttitle "$_IDX_TARGET_SCUT")" "$(notscutrelay "$_IDX_TARGET_SCUT")"
        else
            nav_back 1
        fi
        return 0
    fi
    # [L] 로 언어를 전환한 뒤에는 이력에 쌓아둔 제목이 옛 언어 문자열로 남아 있다.
    # 그대로 쓰면 아래 listof_comm 의 헤더 텍스트 매칭이 실패해서
    # '명령목록이 통째로 빈 화면'이 되므로, 저장된 제목이 현재 $env 에서 더 이상
    # 발견되지 않을 때에만 scut 기준으로 현재 언어 제목으로 다시 해석한다.
    # (제목이 유효한 정상 경로에서는 NAV_title 을 전혀 건드리지 않는다)
    if [ -n "$NAV_title" ] && [ "$NAV_scut" != "m" ] && [ -f "$env" ] && ! grep -qF "$NAV_title" "$env" 2>/dev/null; then
        _nav_rt="$(scuttitle "$NAV_scut")"
        [ -n "$_nav_rt" ] && NAV_title="$_nav_rt"
        unset -v _nav_rt
    fi
    # 바로가기(직접 CMD 화면 진입)는 실제 메뉴 단축키일 때만 지정
    # ([scut] 없는 메뉴 / 존재하지 않는 단축키면 빈값으로 둔다)
    if [ "$NAV_scut" != "m" ] && st "$NAV_scut" >/dev/null 2>&1; then
        iv="$(notscutrelay "$NAV_scut")"
    fi
    echo "◀ 이전 메뉴로 이동.. [${NAV_scut}] ${NAV_title}"
    menufunc "$NAV_sub" "$NAV_title" "$iv"
}

# 메인메뉴로 이동 (이력은 남김)
nav_main() {
    nav_goto "m" "" ""
    echo "◀ 메인메뉴로 이동"
    menufunc
}

# 함수 이름: sub_to_scut
# 기능: 주어진 submenu 태그에 해당하는 단축키(scut)를 찾아 반환합니다.
# 인자: $1 - 찾고자 하는 submenu 태그 (예: {submenu_sys})
# 반환: 찾은 단축키 문자열 (못 찾으면 빈 문자열)
sub_to_scut() {
    local target_sub="$1"
    local item shortcut relay_tag menu_tag

    # 인자 유효성 검사 (선택적)
    if [[ -z $target_sub ]] || [[ $target_sub != "{"*"}" ]]; then
        # echo "Error: Invalid submenu tag format: $target_sub" >&2
        return 1 # 오류 또는 빈 값 반환 결정
    fi

    # shortcutarr 배열 순회
    for item in "${shortcutarr[@]}"; do
        # 형식: scut@@@%%% [{menu_tag}]title [scut]@@@{relay_tag}
        # 또는: scut@@@%%% {menu_tag}title [scut]

        shortcut="${item%%@@@*}" # 단축키 추출

        # 릴레이 태그 추출 (@@@가 2개 있는 경우)
        if [[ $item == *"@@@"* ]]; then
            relay_tag=$(echo "$item" | awk -F'@@@' '{print $NF}') # 마지막 필드가 릴레이 태그
            # 릴레이 태그가 목표 태그와 일치하는지 확인
            if [[ $relay_tag == "$target_sub" ]]; then
                echo "$shortcut"
                return 0 # 찾았으므로 성공 종료
            fi
        fi

        # 메뉴 태그 추출 (%%% 다음에 오는 {...})
        menu_tag=$(echo "$item" | awk -F'%%% ' '{print $2}' | awk -F'}' '{print $1 "}"}' | grep '{submenu_')
        # 메뉴 태그가 목표 태그와 일치하는지 확인
        if [[ $menu_tag == "$target_sub" ]]; then
            echo "$shortcut"
            return 0 # 찾았으므로 성공 종료
        fi
    done

    # 못 찾은 경우
    # echo "Error: Shortcut for submenu tag '$target_sub' not found." >&2
    return 1 # 실패 또는 빈 값 반환
}

# blkid -> fstab ex) blkid2fstab /dev/sdd1 /tmp
blkid2fstab() {
    d=${2/\/\///}
    [ ! -d "$d" ] && echo "mkdir $d"
    fstabadd="$(printf "# UUID=%s\t%s\t%s\tdefaults,nosuid,noexec,noatime\t0 0\n" "$(blkid -o value -s UUID "$1")" "$d" "$(blkid -o value -s TYPE "$1")")"
    echo "$fstabadd" >>/etc/fstab
}

# ==============================================================================
# disksetup : 미마운트/미파티션 디스크 전천후 마법사 (ext4/xfs/btrfs/PV/LVM/LVM-Thin/Mount/fstab/Proxmox)
# ==============================================================================

# 디스크 장치의 1번 파티션 경로 계산 (/dev/nvme0n1 -> /dev/nvme0n1p1, /dev/sdb -> /dev/sdb1)
_disksetup_part1() {
    local dev="$1"
    case "$dev" in
    *[0-9]) echo "${dev}p1" ;;
    *) echo "${dev}1" ;;
    esac
}

# 디스크 사용 상태 판별: "STATE|REASON|DETAIL" 출력
#   STATE: INUSE / FREE
_disksetup_status() {
    local name="$1"
    local dev="/dev/$name"
    local mps fstypes pv_info vg_name pv_dev holders parts p p_size p_fs detail=""

    # 1) 마운트 여부 (디스크 자체 + 모든 하위 파티션/DM/LV)
    mps="$(lsblk -nr -o MOUNTPOINT "$dev" 2>/dev/null | awk 'NF {print $1}' | paste -sd ',' -)"
    if [ -n "$mps" ]; then
        echo "INUSE|MOUNTED($mps)|-"
        return 0
    fi

    # 2) 스왑 여부
    if [ -r /proc/swaps ] && awk -v d="$dev" 'NR>1 && ($1==d || $1 ~ ("^" d "[0-9p]")) {found=1} END{exit !found}' /proc/swaps; then
        echo "INUSE|SWAP|-"
        return 0
    fi

    # 3) ZFS / Linux RAID 멤버 여부
    fstypes="$(lsblk -nr -o FSTYPE "$dev" 2>/dev/null | awk 'NF {print $1}')"
    if echo "$fstypes" | grep -qE '^zfs_member$'; then
        echo "INUSE|ZFS|-"
        return 0
    fi
    if echo "$fstypes" | grep -qE '^linux_raid_member$'; then
        echo "INUSE|RAID|-"
        return 0
    fi

    # 4) LVM PV 여부 (VG 소속이면 INUSE, VG 없는 고아 PV면 FREE:ORPHAN-PV)
    if command -v pvs >/dev/null 2>&1; then
        pv_info="$(pvs --noheadings --separator '|' -o pv_name,vg_name 2>/dev/null | tr -d ' ' | awk -F'|' -v d="$dev" '$1==d || $1 ~ ("^" d "[0-9p]") {print $0; exit}')"
        if [ -n "$pv_info" ]; then
            pv_dev="${pv_info%%|*}"
            vg_name="${pv_info#*|}"
            if [ -n "$vg_name" ]; then
                echo "INUSE|LVM(vg:$vg_name)|$pv_dev"
                return 0
            else
                echo "FREE|ORPHAN-PV|$pv_dev"
                return 0
            fi
        fi
    fi

    # 5) 커널 holders (dm-crypt / multipath / md 등 활성 점유)
    holders="$(ls -A "/sys/block/$name/holders" 2>/dev/null)"
    if [ -z "$holders" ]; then
        local hp
        for hp in "/sys/block/$name/${name}"*/holders; do
            [ -d "$hp" ] || continue
            holders="$(ls -A "$hp" 2>/dev/null)"
            [ -n "$holders" ] && break
        done
    fi
    if [ -n "$holders" ]; then
        echo "INUSE|HOLDER($holders)|-"
        return 0
    fi

    # 6) 미사용 디스크 세부 분류 (RAW vs UNMOUNTED)
    parts="$(lsblk -nr -o NAME,TYPE "$dev" 2>/dev/null | awk '$2=="part" {print $1}')"
    if [ -z "$parts" ]; then
        local raw_fs
        raw_fs="$(lsblk -dn -o FSTYPE "$dev" 2>/dev/null | awk 'NF {print $1}')"
        if [ -n "$raw_fs" ]; then
            echo "FREE|RAW-FS($raw_fs)|no-part,fs=$raw_fs"
        else
            echo "FREE|RAW|파티션 없음 (생디스크)"
        fi
        return 0
    fi

    for p in $parts; do
        p_size="$(lsblk -dn -o SIZE "/dev/$p" 2>/dev/null | awk 'NF {print $1; exit}')"
        p_fs="$(lsblk -dn -o FSTYPE "/dev/$p" 2>/dev/null | awk 'NF {print $1; exit}')"
        [ -z "$p_fs" ] && p_fs="no-fs"
        detail="${detail:+$detail, }${p}(${p_size}/${p_fs})"
    done
    echo "FREE|UNMOUNTED|$detail"
    return 0
}

# 파괴적 작업 전 이중 확인 (장치명 직접 타이핑 강제)
_disksetup_confirm_destructive() {
    local expect="$1"
    local title="$2"
    local ans
    echo
    RED1
    echo "=================================================================="
    echo "  [경고 / DANGER] $title"
    echo "  대상 장치의 기존 데이터가 영구 삭제될 수 있습니다!"
    echo "=================================================================="
    NC
    printf "진행하려면 대상 이름 '%s' 을(를) 정확히 입력하세요 (취소: Enter/q): " "$expect"
    read -r ans </dev/tty
    if [ "$ans" != "$expect" ]; then
        YEL1; echo "[-] 확인 불일치로 작업을 안전하게 취소했습니다."; NC
        return 1
    fi
    return 0
}

# 디스크 시그니처 및 파티션 테이블 초기화
_disksetup_wipe_disk() {
    local dev="$1"
    local p
    # 하위 파티션 시그니처 먼저 제거
    for p in $(lsblk -nr -o NAME,TYPE "$dev" 2>/dev/null | awk '$2=="part" {print $1}'); do
        if command -v wipefs >/dev/null 2>&1; then
            wipefs -a "/dev/$p" 2>/dev/null || true
        fi
    done
    if command -v wipefs >/dev/null 2>&1; then
        wipefs -a "$dev"
    else
        dd if=/dev/zero of="$dev" bs=1M count=2 conv=fsync 2>/dev/null
    fi
    if command -v sgdisk >/dev/null 2>&1; then
        sgdisk --zap-all "$dev" 2>/dev/null || true
    fi
    partprobe "$dev" 2>/dev/null || blockdev --rereadpt "$dev" 2>/dev/null || true
    command -v udevadm >/dev/null 2>&1 && udevadm settle 2>/dev/null || sleep 1
}

# GPT 100% 단일 파티션 생성 ($1: /dev/sdX, $2: linux|lvm)
_disksetup_mkpart_gpt() {
    local dev="$1"
    local kind="${2:-linux}"
    local part1 i

    _disksetup_wipe_disk "$dev" || return 1

    if command -v parted >/dev/null 2>&1; then
        parted -s "$dev" mklabel gpt || return 1
        if [ "$kind" = "lvm" ]; then
            parted -s -a optimal "$dev" mkpart primary 0% 100% || return 1
            parted -s "$dev" set 1 lvm on || return 1
        else
            parted -s -a optimal "$dev" mkpart primary ext4 0% 100% || return 1
        fi
    elif command -v sgdisk >/dev/null 2>&1; then
        local tcode="8300"
        [ "$kind" = "lvm" ] && tcode="8e00"
        sgdisk -n 1:0:0 -t "1:$tcode" "$dev" || return 1
    elif command -v sfdisk >/dev/null 2>&1; then
        if [ "$kind" = "lvm" ]; then
            printf "label: gpt\n,,V\n" | sfdisk "$dev" || return 1
        else
            printf "label: gpt\n,,L\n" | sfdisk "$dev" || return 1
        fi
    else
        RED1; echo "[!] parted, sgdisk, sfdisk 중 어떤 파티션 도구도 설치되어 있지 않습니다."; NC
        return 1
    fi

    partprobe "$dev" 2>/dev/null || blockdev --rereadpt "$dev" 2>/dev/null || true
    command -v udevadm >/dev/null 2>&1 && udevadm settle 2>/dev/null || sleep 2

    part1="$(_disksetup_part1 "$dev")"
    i=0
    while [ ! -b "$part1" ] && [ "$i" -lt 10 ]; do
        sleep 0.5
        i=$((i + 1))
    done
    if [ ! -b "$part1" ]; then
        RED1; echo "[!] 생성된 파티션($part1) 장치를 찾을 수 없습니다."; NC
        return 1
    fi
    return 0
}

# 마운트 및 /etc/fstab 등록 헬퍼 ($1: target_dev, $2: default_mp)
_disksetup_mount_and_fstab() {
    local target_dev="$1"
    local default_mp="${2:-/mnt/data}"
    local mp fstype uuid fstab_dev ans bak entry

    echo
    CYN1; echo "--- [마운트 및 /etc/fstab 등록] ---"; NC
    while true; do
        printf "마운트할 디렉토리 경로 입력 (기본: %s, 취소: q): " "$default_mp"
        read -r mp </dev/tty
        [ "$mp" = "q" ] || [ "$mp" = "Q" ] && { echo "마운트를 건너뜁니다."; return 0; }
        [ -z "$mp" ] && mp="$default_mp"
        case "$mp" in
        /*) ;;
        *)
            RED1; echo "[!] 절대 경로('/'로 시작)로 입력하세요. 예: /mnt/disk1"; NC
            continue
            ;;
        esac
        if [ "$mp" = "/" ]; then
            RED1; echo "[!] 루트('/')에는 마운트할 수 없습니다."; NC
            continue
        fi
        if command -v mountpoint >/dev/null 2>&1 && mountpoint -q "$mp" 2>/dev/null; then
            RED1; echo "[!] '$mp' 는 이미 다른 장치가 마운트되어 있습니다. 다른 경로를 입력하세요."; NC
            continue
        fi
        break
    done

    mkdir -p "$mp" || { RED1; echo "[!] 디렉토리 생성 실패: $mp"; NC; return 1; }
    echo ">>> mount $target_dev $mp"
    if ! mount "$target_dev" "$mp"; then
        RED1; echo "[!] 마운트 실패: $target_dev -> $mp"; NC
        return 1
    fi
    GRN1; echo "[OK] 마운트 완료: $target_dev -> $mp"; NC
    df -h "$mp"

    echo
    printf "/etc/fstab 에 부팅 시 자동 마운트를 등록할까요? [Y/n]: "
    read -r ans </dev/tty
    case "$ans" in
    [nN]*)
        echo "[-] /etc/fstab 등록을 건너뜁니다."
        return 0
        ;;
    esac

    uuid="$(blkid -o value -s UUID "$target_dev" 2>/dev/null)"
    fstype="$(blkid -o value -s TYPE "$target_dev" 2>/dev/null)"
    [ -z "$fstype" ] && fstype="auto"

    if [ -n "$uuid" ]; then
        fstab_dev="UUID=$uuid"
    else
        fstab_dev="$target_dev"
    fi

    # 중복 체크 (주석 제외)
    if grep -vE '^[[:space:]]*#' /etc/fstab 2>/dev/null | awk -v d="$fstab_dev" -v m="$mp" '$1==d || $2==m {found=1} END{exit !found}'; then
        YEL1; echo "[!] /etc/fstab 에 이미 동일한 장치($fstab_dev) 또는 경로($mp)가 등록되어 있어 추가를 건너뜁니다."; NC
        return 0
    fi

    bak="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    cp -a /etc/fstab "$bak" 2>/dev/null && echo "[백업] $bak"
    entry="$(printf "%s\t%s\t%s\tdefaults,noatime,nofail\t0 2" "$fstab_dev" "$mp" "$fstype")"
    echo "$entry" >>/etc/fstab
    GRN1; echo "[OK] /etc/fstab 등록 완료:"; NC
    echo "  $entry"
    echo ">>> mount -a 검증 중..."
    if mount -a; then
        GRN1; echo "[OK] mount -a 검증 통과!"; NC
    else
        RED1; echo "[!] mount -a 경고 발생! /etc/fstab 을 확인하세요. (백업: $bak)"; NC
    fi
    return 0
}

# 전천후 디스크 마법사 메인 함수
disksetup() {
    if [ "$(id -u)" -ne 0 ]; then
        RED1; echo "[!] disksetup 은 root 권한으로 실행해야 합니다."; NC
        return 1
    fi
    if ! command -v lsblk >/dev/null 2>&1; then
        RED1; echo "[!] lsblk 명령어가 필요합니다."; NC
        return 1
    fi

    local -a free_names=()
    local -a free_sizes=()
    local -a free_models=()
    local -a free_reasons=()
    local -a free_details=()
    local -a busy_lines=()
    local line name size model tran st state reason detail
    local idx=0 sel sel_name sel_dev sel_size sel_model sel_reason sel_detail
    local mode fstype label part1 default_mp

    echo
    CYN1
    echo "=========================================================================="
    echo "  [disksetup] 전천후 디스크 초기화 / LVM / LVM-Thin / 포맷 / 마운트 마법사"
    echo "=========================================================================="
    NC

    # 1. 물리 디스크 스캔 (구버전 lsblk 호환: -P key=value 대신 -dn -o NAME,TYPE,SIZE,MODEL)
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        case "$name" in
        loop* | ram* | sr* | fd* | zram* | dm-* | md*) continue ;;
        esac
        size="$(lsblk -dn -o SIZE "/dev/$name" 2>/dev/null | awk 'NF {print $1; exit}')"
        model="$(lsblk -dn -o MODEL "/dev/$name" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        tran="$(lsblk -dn -o TRAN "/dev/$name" 2>/dev/null | awk 'NF {print $1; exit}')"
        [ -z "$model" ] && model="-"
        [ -n "$tran" ] && model="[$tran] $model"

        # 0B / 미디어 없음 / USB 재인식 과도기 유령 장치 차단
        local blk_sectors=""
        [ -r "/sys/block/$name/size" ] && read -r blk_sectors <"/sys/block/$name/size"
        if [ -z "$size" ] || [ "$size" = "0B" ] || [ "$blk_sectors" = "0" ]; then
            busy_lines[${#busy_lines[@]}]="$(printf "  [대기] /dev/%-10s  %-8s  %-24s  %s" "$name" "${size:-0B}" "${model:0:24}" "NO-MEDIA/0B")"
            continue
        fi

        st="$(_disksetup_status "$name")"
        state="${st%%|*}"
        local rest="${st#*|}"
        reason="${rest%%|*}"
        detail="${rest#*|}"

        if [ "$state" = "FREE" ]; then
            free_names[${#free_names[@]}]="$name"
            free_sizes[${#free_sizes[@]}]="$size"
            free_models[${#free_models[@]}]="$model"
            free_reasons[${#free_reasons[@]}]="$reason"
            free_details[${#free_details[@]}]="$detail"
        else
            busy_lines[${#busy_lines[@]}]="$(printf "  [보호] /dev/%-10s  %-8s  %-24s  %s" "$name" "$size" "${model:0:24}" "$reason")"
        fi
    done < <(lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}')

    # 보호 디스크(사용 중) 요약 표시
    if [ "${#busy_lines[@]}" -gt 0 ]; then
        WHT; echo "[사용 중 / 보호 디스크 (선택 불가 - 안전 보호)]"; NC
        local bl
        for bl in "${busy_lines[@]}"; do
            printf "\033[90m%s\033[0m\n" "$bl"
        done
        echo
    fi

    # 선택 가능한 미사용/미마운트 디스크 목록 표시
    GRN1; echo "[선택 가능한 미사용 / 미마운트 디스크]"; NC
    if [ "${#free_names[@]}" -eq 0 ]; then
        YEL1
        echo "  작업 가능한 미마운트/미파티션 디스크가 없습니다."
        echo "  (현재 모든 물리 디스크가 마운트되었거나 LVM/ZFS/RAID/Swap 으로 사용 중입니다.)"
        NC
        echo
        echo "참고용 전체 블록 장치 현황:"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL 2>/dev/null || lsblk
        return 0
    fi

    printf "  %-4s %-15s %-9s %-22s %-14s %s\n" "번호" "장치" "용량" "모델" "상태" "파티션/상세"
    echo "  ------------------------------------------------------------------------------"
    idx=0
    while [ "$idx" -lt "${#free_names[@]}" ]; do
        local num=$((idx + 1))
        local color="\033[1;32m"
        case "${free_reasons[$idx]}" in
        UNMOUNTED*) color="\033[1;33m" ;;
        ORPHAN-PV*) color="\033[1;36m" ;;
        esac
        printf "  ${color}[%2d]\033[0m /dev/%-10s %-9s %-22s %-14s %s\n" \
            "$num" "${free_names[$idx]}" "${free_sizes[$idx]}" "${free_models[$idx]:0:22}" \
            "${free_reasons[$idx]}" "${free_details[$idx]}"
        idx=$((idx + 1))
    done
    echo "  ------------------------------------------------------------------------------"
    echo "  (팁: 'a' 입력 시 전체 lsblk 트리 보기, 'q' 또는 Enter 로 종료)"

    # 2. 디스크 번호 선택
    local range_hint="1"
    if [ "${#free_names[@]}" -ge 2 ] && [ "${#free_names[@]}" -le 4 ]; then
        local r_i=2
        while [ "$r_i" -le "${#free_names[@]}" ]; do
            range_hint="$range_hint / $r_i"
            r_i=$((r_i + 1))
        done
    elif [ "${#free_names[@]}" -gt 4 ]; then
        range_hint="1~${#free_names[@]}"
    fi
    while true; do
        printf "작업할 디스크 번호 선택 [%s / a / q]: " "$range_hint"
        read -r sel </dev/tty
        case "$sel" in
        "" | q | Q | 0)
            echo "[-] disksetup 을 종료합니다."
            return 0
            ;;
        a | A)
            echo
            lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL 2>/dev/null || lsblk
            echo
            continue
            ;;
        *[!0-9]*)
            RED1; echo "[!] 1 ~ ${#free_names[@]} 사이의 번호를 입력하세요."; NC
            continue
            ;;
        esac
        if [ "$sel" -ge 1 ] && [ "$sel" -le "${#free_names[@]}" ]; then
            idx=$((sel - 1))
            sel_name="${free_names[$idx]}"
            sel_dev="/dev/$sel_name"
            sel_size="${free_sizes[$idx]}"
            sel_model="${free_models[$idx]}"
            sel_reason="${free_reasons[$idx]}"
            sel_detail="${free_details[$idx]}"
            break
        fi
        RED1; echo "[!] 1 ~ ${#free_names[@]} 사이의 번호를 입력하세요."; NC
    done

    # 선택 직후 안전 재검증
    st="$(_disksetup_status "$sel_name")"
    if [ "${st%%|*}" != "FREE" ]; then
        RED1; echo "[!] 안전 차단: $sel_dev 상태가 변경되어 사용 중($st)입니다. 작업을 중단합니다."; NC
        return 1
    fi

    echo
    YEL1
    echo ">>> 선택된 디스크: $sel_dev ($sel_size / $sel_model)"
    echo "    현재 상태: $sel_reason | $sel_detail"
    NC
    echo
    CYN1; echo "[수행할 작업을 선택하세요]"; NC
    echo "  [1] 기존 파티션 그대로 마운트 (+ /etc/fstab 자동 등록)  [데이터 보존]"
    echo "  [2] GPT 단일 파티션 + ext4 포맷 + 마운트 (+ fstab)       [가장 많이 씀]"
    echo "  [3] GPT 단일 파티션 + xfs / btrfs 포맷 + 마운트 (+ fstab)"
    echo "  [4] LVM-Thin 전체 세팅: 파티션(lvm) -> PV -> VG -> Thin Pool (+ Proxmox 등록)"
    echo "  [5] LVM 일반 볼륨 세팅: 파티션(lvm) -> PV -> VG -> LV -> 포맷 + 마운트 (+ fstab)"
    echo "  [6] PV만 생성 (pvcreate) / 기존 VG에 확장 (vgextend)"
    echo "  [7] 디스크 완전 초기화 (wipefs + 파티션 테이블 삭제 -> 생디스크화)"
    echo "  [0] 취소 / 종료"
    echo
    printf "작업 번호 선택 [0~7]: "
    read -r mode </dev/tty

    case "$mode" in
    "" | 0 | q | Q)
        echo "[-] 작업을 취소했습니다."
        return 0
        ;;

    # ------------------------------------------------------------------
    # [1] 기존 파티션 바로 마운트 (포맷 없이 데이터 보존)
    # ------------------------------------------------------------------
    1)
        local -a parts_arr=()
        local p p_sz p_fs p_sel target_part
        while IFS= read -r p; do
            [ -n "$p" ] && parts_arr[${#parts_arr[@]}]="$p"
        done < <(lsblk -nr -o NAME,TYPE "$sel_dev" 2>/dev/null | awk '$2=="part" {print $1}')

        if [ "${#parts_arr[@]}" -eq 0 ]; then
            # 파티션 없이 디스크 자체에 FS가 있는 경우 지원
            local raw_fs
            raw_fs="$(lsblk -dn -o FSTYPE "$sel_dev" 2>/dev/null | awk 'NF {print $1}')"
            if [ -n "$raw_fs" ]; then
                target_part="$sel_dev"
                echo "[안내] 파티션은 없지만 장치 자체에 $raw_fs 파일시스템이 감지되어 $sel_dev 을 마운트합니다."
            else
                RED1; echo "[!] $sel_dev 에 마운트할 기존 파티션이나 파일시스템이 없습니다. [2]~[5]번으로 먼저 구성하세요."; NC
                return 1
            fi
        elif [ "${#parts_arr[@]}" -eq 1 ]; then
            target_part="/dev/${parts_arr[0]}"
            p_fs="$(lsblk -dn -o FSTYPE "$target_part" 2>/dev/null | awk '{print $1}')"
            echo "[선택됨] 단일 파티션 자동 선택: $target_part (FS: ${p_fs:-unknown})"
        else
            echo
            CYN1; echo "[마운트할 파티션 선택]"; NC
            idx=0
            while [ "$idx" -lt "${#parts_arr[@]}" ]; do
                p="/dev/${parts_arr[$idx]}"
                p_sz="$(lsblk -dn -o SIZE "$p" 2>/dev/null | awk '{print $1}')"
                p_fs="$(lsblk -dn -o FSTYPE "$p" 2>/dev/null | awk '{print $1}')"
                printf "  [%d] %-16s  %-8s  FS: %s\n" "$((idx + 1))" "$p" "$p_sz" "${p_fs:-none}"
                idx=$((idx + 1))
            done
            printf "파티션 번호 [1~%d]: " "${#parts_arr[@]}"
            read -r p_sel </dev/tty
            case "$p_sel" in
            "" | *[!0-9]*)
                echo "[-] 취소했습니다."
                return 0
                ;;
            esac
            if [ "$p_sel" -lt 1 ] || [ "$p_sel" -gt "${#parts_arr[@]}" ]; then
                echo "[-] 취소했습니다."
                return 0
            fi
            target_part="/dev/${parts_arr[$((p_sel - 1))]}"
        fi

        p_fs="$(lsblk -dn -o FSTYPE "$target_part" 2>/dev/null | awk '{print $1}')"
        if [ -z "$p_fs" ]; then
            RED1; echo "[!] $target_part 에 파일시스템이 감지되지 않습니다(포맷 필요). [2] 또는 [3]번을 이용하세요."; NC
            return 1
        fi
        local p_label def_mp_name
        p_label="$(blkid -o value -s LABEL "$target_part" 2>/dev/null | tr -cd 'A-Za-z0-9._-')"
        def_mp_name="${p_label:-${target_part##*/}}"
        _disksetup_mount_and_fstab "$target_part" "/mnt/$def_mp_name"
        ;;

    # ------------------------------------------------------------------
    # [2] GPT + ext4 포맷 + 마운트 / [3] GPT + xfs or btrfs 포맷 + 마운트
    # ------------------------------------------------------------------
    2 | 3)
        if [ "$mode" = "2" ]; then
            fstype="ext4"
        else
            echo
            echo "  [1] xfs"
            echo "  [2] btrfs"
            echo "  [3] ext4"
            printf "파일시스템 선택 [1~3, 기본 1(xfs)]: "
            local fs_sel
            read -r fs_sel </dev/tty
            case "$fs_sel" in
            "" | 1) fstype="xfs" ;;
            2) fstype="btrfs" ;;
            3) fstype="ext4" ;;
            *) echo "[-] 취소했습니다."; return 0 ;;
            esac
        fi

        if ! command -v "mkfs.$fstype" >/dev/null 2>&1; then
            RED1; echo "[!] mkfs.$fstype 명령어가 설치되어 있지 않습니다. (예: e2fsprogs / xfsprogs / btrfs-progs)"; NC
            return 1
        fi

        printf "볼륨 레이블 입력 (선택사항, 생략: Enter): "
        read -r label </dev/tty
        part1="$(_disksetup_part1 "$sel_dev")"

        echo
        CYN1; echo "[실행 계획 미리보기]"; NC
        echo "  1) 디스크 초기화 & GPT 단일 파티션 생성: $sel_dev -> $part1 (100%)"
        echo "  2) 파일시스템 포맷: mkfs.$fstype $part1 ${label:+(label: $label)}"
        echo "  3) 마운트 & /etc/fstab 등록"

        _disksetup_confirm_destructive "$sel_name" "$sel_dev 전체 초기화 후 $fstype 포맷" || return 1

        echo ">>> [1/3] GPT 파티션 생성 중..."
        _disksetup_mkpart_gpt "$sel_dev" "linux" || return 1

        echo ">>> [2/3] mkfs.$fstype 포맷 중..."
        case "$fstype" in
        ext4)
            if [ -n "$label" ]; then
                mkfs.ext4 -F -L "$label" "$part1" || return 1
            else
                mkfs.ext4 -F "$part1" || return 1
            fi
            ;;
        xfs)
            if [ -n "$label" ]; then
                mkfs.xfs -f -L "$label" "$part1" || return 1
            else
                mkfs.xfs -f "$part1" || return 1
            fi
            ;;
        btrfs)
            if [ -n "$label" ]; then
                mkfs.btrfs -f -L "$label" "$part1" || return 1
            else
                mkfs.btrfs -f "$part1" || return 1
            fi
            ;;
        esac
        GRN1; echo "[OK] 포맷 완료: $part1 ($fstype)"; NC

        default_mp="/mnt/${label:-$sel_name}"
        _disksetup_mount_and_fstab "$part1" "$default_mp"
        ;;

    # ------------------------------------------------------------------
    # [4] LVM-Thin 전체 세팅 (+ Proxmox pvesm 등록 옵션)
    # ------------------------------------------------------------------
    4)
        if ! command -v pvcreate >/dev/null 2>&1 || ! command -v lvcreate >/dev/null 2>&1; then
            RED1; echo "[!] lvm2 도구(pvcreate/vgcreate/lvcreate)가 설치되어 있지 않습니다."; NC
            return 1
        fi

        local pv_mode="part" pv_target vg_action="new" vg_name thin_pool thin_size
        local -a exist_vgs=()

        if [ "$sel_reason" = "ORPHAN-PV" ]; then
            pv_mode="orphan"
            pv_target="$sel_detail"
            CYN1; echo "[안내] 기존 고아 PV($pv_target)를 재사용합니다."; NC
        else
            echo
            echo "  [1] GPT 1번 파티션 생성(lvm 플래그) 후 PV 생성 (권장)"
            echo "  [2] 디스크 전체($sel_dev)에 파티션 없이 직접 PV 생성"
            printf "PV 생성 방식 [1/2, 기본 1]: "
            local pm_sel
            read -r pm_sel </dev/tty
            case "$pm_sel" in
            2)
                pv_mode="raw"
                pv_target="$sel_dev"
                ;;
            *)
                pv_mode="part"
                pv_target="$(_disksetup_part1 "$sel_dev")"
                ;;
            esac
        fi

        # 기존 VG 목록 조회
        while IFS= read -r line; do
            [ -n "$line" ] && exist_vgs[${#exist_vgs[@]}]="$line"
        done < <(vgs --noheadings -o vg_name 2>/dev/null | awk '{print $1}')

        echo
        if [ "${#exist_vgs[@]}" -gt 0 ]; then
            echo "  [1] 새 Volume Group(VG) 생성"
            echo "  [2] 기존 VG 확장 (현재 VG: ${exist_vgs[*]})"
            printf "VG 방식 선택 [1/2, 기본 1]: "
            local vga_sel
            read -r vga_sel </dev/tty
            if [ "$vga_sel" = "2" ]; then
                vg_action="extend"
                idx=0
                while [ "$idx" -lt "${#exist_vgs[@]}" ]; do
                    printf "    [%d] %s\n" "$((idx + 1))" "${exist_vgs[$idx]}"
                    idx=$((idx + 1))
                done
                printf "확장할 기존 VG 번호 [1~%d]: " "${#exist_vgs[@]}"
                local vgi
                read -r vgi </dev/tty
                case "$vgi" in
                "" | *[!0-9]*)
                    echo "[-] 취소했습니다."
                    return 0
                    ;;
                esac
                if [ "$vgi" -lt 1 ] || [ "$vgi" -gt "${#exist_vgs[@]}" ]; then
                    echo "[-] 취소했습니다."
                    return 0
                fi
                vg_name="${exist_vgs[$((vgi - 1))]}"
            fi
        fi

        if [ "$vg_action" = "new" ]; then
            local def_vg="vg_${sel_name}"
            printf "새 VG 이름 입력 (기본: %s): " "$def_vg"
            read -r vg_name </dev/tty
            [ -z "$vg_name" ] && vg_name="$def_vg"
        fi

        printf "Thin Pool 이름 입력 (기본: thinpool): "
        read -r thin_pool </dev/tty
        [ -z "$thin_pool" ] && thin_pool="thinpool"

        printf "Thin Pool 용량 입력 (기본: 100%%FREE, 예: 100%%FREE / 95%%FREE / 400G): "
        read -r thin_size </dev/tty
        [ -z "$thin_size" ] && thin_size="100%FREE"

        echo
        CYN1; echo "[실행 계획 미리보기 - LVM-Thin]"; NC
        if [ "$pv_mode" = "part" ]; then
            echo "  1) GPT 파티션(lvm) 생성: $sel_dev -> $pv_target"
            echo "  2) PV 생성: pvcreate -f $pv_target"
        elif [ "$pv_mode" = "raw" ]; then
            echo "  1) 디스크 시그니처 초기화: $sel_dev"
            echo "  2) PV 생성: pvcreate -f $pv_target"
        else
            echo "  1) 기존 고아 PV 사용: $pv_target"
        fi
        if [ "$vg_action" = "new" ]; then
            echo "  3) VG 생성: vgcreate $vg_name $pv_target"
        else
            echo "  3) VG 확장: vgextend $vg_name $pv_target"
        fi
        if [[ "$thin_size" == *%* ]]; then
            echo "  4) Thin Pool 생성: lvcreate -l $thin_size --thinpool $thin_pool $vg_name"
        else
            echo "  4) Thin Pool 생성: lvcreate -L $thin_size --thinpool $thin_pool $vg_name"
        fi

        _disksetup_confirm_destructive "$sel_name" "$sel_dev LVM-Thin ($vg_name/$thin_pool) 구성" || return 1

        if [ "$pv_mode" = "part" ]; then
            _disksetup_mkpart_gpt "$sel_dev" "lvm" || return 1
            pvcreate -ff -y "$pv_target" || return 1
        elif [ "$pv_mode" = "raw" ]; then
            _disksetup_wipe_disk "$sel_dev" || return 1
            pvcreate -ff -y "$pv_target" || return 1
        fi

        if [ "$vg_action" = "new" ]; then
            vgcreate "$vg_name" "$pv_target" || return 1
        else
            vgextend "$vg_name" "$pv_target" || return 1
        fi

        if [[ "$thin_size" == *%* ]]; then
            lvcreate -l "$thin_size" --thinpool "$thin_pool" "$vg_name" || return 1
        else
            lvcreate -L "$thin_size" --thinpool "$thin_pool" "$vg_name" || return 1
        fi

        GRN1; echo "[OK] LVM-Thin Pool 생성 완료!"; NC
        pvs; vgs; lvs "$vg_name/$thin_pool"

        # Proxmox VE 자동 감지 -> pvesm lvmthin 스토리지 등록 옵션
        if command -v pvesm >/dev/null 2>&1; then
            echo
            CYN1; echo "[Proxmox VE 감지됨] pvesm lvmthin 스토리지로 바로 등록할 수 있습니다."; NC
            printf "Proxmox 스토리지로 등록할까요? [Y/n]: "
            local pve_ans pve_id
            read -r pve_ans </dev/tty
            case "$pve_ans" in
            [nN]*) ;;
            *)
                local def_id="${vg_name#vg_}"
                [ -z "$def_id" ] && def_id="$vg_name"
                printf "Proxmox 스토리지 ID 입력 (기본: %s): " "$def_id"
                read -r pve_id </dev/tty
                [ -z "$pve_id" ] && pve_id="$def_id"
                echo ">>> pvesm add lvmthin $pve_id --vgname $vg_name --thinpool $thin_pool --content images,rootdir"
                if pvesm add lvmthin "$pve_id" --vgname "$vg_name" --thinpool "$thin_pool" --content images,rootdir; then
                    GRN1; echo "[OK] Proxmox 스토리지 등록 완료: $pve_id"; NC
                    pvesm status
                else
                    RED1; echo "[!] pvesm add lvmthin 실패 (위 오류 확인)"; NC
                fi
                ;;
            esac
        fi

        # 선택: Thin LV 생성 + 포맷 + 마운트 옵션
        echo
        printf "이 Thin Pool 안에 일반 마운트용 Thin LV도 바로 생성/포맷/마운트할까요? [y/N]: "
        local tlv_ans tlv_name tlv_vsize tlv_fs
        read -r tlv_ans </dev/tty
        case "$tlv_ans" in
        [yY]*)
            printf "Thin LV 이름 입력 (기본: lv_data): "
            read -r tlv_name </dev/tty
            [ -z "$tlv_name" ] && tlv_name="lv_data"
            printf "Thin LV 가상 크기 입력 (예: 200G / 500G): "
            read -r tlv_vsize </dev/tty
            [ -z "$tlv_vsize" ] && { echo "[-] 크기가 비어 Thin LV 생성을 건너뜁니다."; return 0; }
            printf "포맷 파일시스템 (ext4 / xfs, 기본 ext4): "
            read -r tlv_fs </dev/tty
            [ -z "$tlv_fs" ] && tlv_fs="ext4"
            lvcreate -V "$tlv_vsize" -T "$vg_name/$thin_pool" -n "$tlv_name" || return 1
            if [ "$tlv_fs" = "xfs" ]; then
                mkfs.xfs -f "/dev/$vg_name/$tlv_name" || return 1
            else
                mkfs.ext4 -F "/dev/$vg_name/$tlv_name" || return 1
            fi
            _disksetup_mount_and_fstab "/dev/$vg_name/$tlv_name" "/mnt/$tlv_name"
            ;;
        esac
        ;;

    # ------------------------------------------------------------------
    # [5] LVM 일반 볼륨 세팅: PV -> VG -> LV -> 포맷 + 마운트 (+ fstab)
    # ------------------------------------------------------------------
    5)
        if ! command -v pvcreate >/dev/null 2>&1 || ! command -v lvcreate >/dev/null 2>&1; then
            RED1; echo "[!] lvm2 도구(pvcreate/vgcreate/lvcreate)가 설치되어 있지 않습니다."; NC
            return 1
        fi

        local vg_name lv_name lv_size lv_fs pv_target
        if [ "$sel_reason" = "ORPHAN-PV" ]; then
            pv_target="$sel_detail"
        else
            pv_target="$(_disksetup_part1 "$sel_dev")"
        fi

        local def_vg="vg_${sel_name}"
        printf "VG 이름 입력 (기존 VG면 확장, 신규면 생성 / 기본: %s): " "$def_vg"
        read -r vg_name </dev/tty
        [ -z "$vg_name" ] && vg_name="$def_vg"

        printf "LV 이름 입력 (기본: lv_data): "
        read -r lv_name </dev/tty
        [ -z "$lv_name" ] && lv_name="lv_data"

        printf "LV 용량 입력 (기본: 100%%FREE, 예: 100%%FREE / 200G): "
        read -r lv_size </dev/tty
        [ -z "$lv_size" ] && lv_size="100%FREE"

        printf "포맷 파일시스템 (ext4 / xfs, 기본: ext4): "
        read -r lv_fs </dev/tty
        [ -z "$lv_fs" ] && lv_fs="ext4"
        if ! command -v "mkfs.$lv_fs" >/dev/null 2>&1; then
            RED1; echo "[!] mkfs.$lv_fs 명령어가 없습니다."; NC
            return 1
        fi

        local vg_exists=0
        vgs "$vg_name" >/dev/null 2>&1 && vg_exists=1

        echo
        CYN1; echo "[실행 계획 미리보기 - LVM 일반 볼륨]"; NC
        [ "$sel_reason" != "ORPHAN-PV" ] && echo "  1) GPT 파티션(lvm) & PV 생성: $sel_dev -> $pv_target"
        if [ "$vg_exists" -eq 1 ]; then
            echo "  2) 기존 VG 확장: vgextend $vg_name $pv_target"
        else
            echo "  2) 새 VG 생성: vgcreate $vg_name $pv_target"
        fi
        echo "  3) LV 생성: /dev/$vg_name/$lv_name ($lv_size)"
        echo "  4) 포맷($lv_fs) & 마운트 & /etc/fstab 등록"

        _disksetup_confirm_destructive "$sel_name" "$sel_dev LVM 일반 볼륨(/dev/$vg_name/$lv_name) 구성" || return 1

        if [ "$sel_reason" != "ORPHAN-PV" ]; then
            _disksetup_mkpart_gpt "$sel_dev" "lvm" || return 1
            pvcreate -ff -y "$pv_target" || return 1
        fi
        if [ "$vg_exists" -eq 1 ]; then
            vgextend "$vg_name" "$pv_target" || return 1
        else
            vgcreate "$vg_name" "$pv_target" || return 1
        fi

        if [[ "$lv_size" == *%* ]]; then
            lvcreate -l "$lv_size" -n "$lv_name" "$vg_name" || return 1
        else
            lvcreate -L "$lv_size" -n "$lv_name" "$vg_name" || return 1
        fi

        if [ "$lv_fs" = "xfs" ]; then
            mkfs.xfs -f "/dev/$vg_name/$lv_name" || return 1
        else
            mkfs.ext4 -F "/dev/$vg_name/$lv_name" || return 1
        fi
        GRN1; echo "[OK] LV 생성 및 $lv_fs 포맷 완료: /dev/$vg_name/$lv_name"; NC

        _disksetup_mount_and_fstab "/dev/$vg_name/$lv_name" "/mnt/$lv_name"
        ;;

    # ------------------------------------------------------------------
    # [6] PV만 생성 (pvcreate) / 기존 VG에 확장 (vgextend)
    # ------------------------------------------------------------------
    6)
        if ! command -v pvcreate >/dev/null 2>&1; then
            RED1; echo "[!] lvm2 도구(pvcreate)가 설치되어 있지 않습니다."; NC
            return 1
        fi

        local pv_target vg_name=""
        local -a exist_vgs=()
        if [ "$sel_reason" = "ORPHAN-PV" ]; then
            pv_target="$sel_detail"
            echo "[안내] 이미 고아 PV($pv_target) 상태입니다."
        else
            pv_target="$(_disksetup_part1 "$sel_dev")"
        fi

        while IFS= read -r line; do
            [ -n "$line" ] && exist_vgs[${#exist_vgs[@]}]="$line"
        done < <(vgs --noheadings -o vg_name 2>/dev/null | awk '{print $1}')

        if [ "${#exist_vgs[@]}" -gt 0 ]; then
            echo
            echo "  [0] PV만 생성 (VG 확장 안 함)"
            idx=0
            while [ "$idx" -lt "${#exist_vgs[@]}" ]; do
                printf "  [%d] PV 생성 후 기존 VG '%s' 에 확장(vgextend)\n" "$((idx + 1))" "${exist_vgs[$idx]}"
                idx=$((idx + 1))
            done
            printf "선택 [0~%d, 기본 0]: " "${#exist_vgs[@]}"
            local vgi
            read -r vgi </dev/tty
            case "$vgi" in
            "" | *[!0-9]*) ;;
            *)
                if [ "$vgi" -ge 1 ] && [ "$vgi" -le "${#exist_vgs[@]}" ]; then
                    vg_name="${exist_vgs[$((vgi - 1))]}"
                fi
                ;;
            esac
        fi

        echo
        CYN1; echo "[실행 계획 미리보기 - PV / VG 확장]"; NC
        [ "$sel_reason" != "ORPHAN-PV" ] && echo "  1) GPT 파티션(lvm) & pvcreate -ff -y $pv_target"
        [ -n "$vg_name" ] && echo "  2) vgextend $vg_name $pv_target"

        _disksetup_confirm_destructive "$sel_name" "$sel_dev PV 생성${vg_name:+ 및 VG($vg_name) 확장}" || return 1

        if [ "$sel_reason" != "ORPHAN-PV" ]; then
            _disksetup_mkpart_gpt "$sel_dev" "lvm" || return 1
            pvcreate -ff -y "$pv_target" || return 1
        fi
        if [ -n "$vg_name" ]; then
            vgextend "$vg_name" "$pv_target" || return 1
        fi
        GRN1; echo "[OK] 작업 완료!"; NC
        pvs; vgs
        ;;

    # ------------------------------------------------------------------
    # [7] 디스크 완전 초기화 (wipefs + 파티션 테이블 제거)
    # ------------------------------------------------------------------
    7)
        echo
        CYN1; echo "[실행 계획 미리보기 - 완전 초기화]"; NC
        echo "  1) 하위 파티션 및 $sel_dev 시그니처 제거 (wipefs -a / sgdisk --zap-all)"
        echo "  2) 커널 파티션 테이블 갱신 (partprobe)"

        _disksetup_confirm_destructive "$sel_name" "$sel_dev 완전 초기화 (모든 파티션/시그니처 삭제)" || return 1

        _disksetup_wipe_disk "$sel_dev" || return 1
        GRN1; echo "[OK] $sel_dev 완전 초기화 완료 (생디스크 상태)"; NC
        lsblk "$sel_dev"
        ;;

    *)
        RED1; echo "[!] 잘못된 작업 번호입니다."; NC
        return 1
        ;;
    esac
}

# ==============================================================================
# [isodl] OS ISO 공식 미러 실시간 버전 스크랩 & 자동 다운로더
#   사용법: isodl [ubuntu|ubuntu-desktop|debian|alma|rocky|virtio|pve|pbs] [-d <저장경로>]
# ==============================================================================
_isodl_fetch() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 6 --max-time 15 -A "curl/7.88.1" "$url" 2>/dev/null && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -qO- -T 12 -t 2 --user-agent="curl/7.88.1" "$url" 2>/dev/null && return 0
    fi
    return 1
}

# 구버전 리눅스(sort -V 미지원) 호환 버전 역순 정렬
_isodl_vsort_desc() {
    if [ "$(printf '1.2\n1.10\n' | sort -V 2>/dev/null | head -n 1)" = "1.2" ]; then
        sort -V -r
    else
        awk '{
            orig = $0
            s = $0
            key = ""
            while (match(s, /[0-9]+/)) {
                pre = substr(s, 1, RSTART - 1)
                num = substr(s, RSTART, RLENGTH)
                key = key pre sprintf("%08d", num + 0)
                s = substr(s, RSTART + RLENGTH)
            }
            key = key s
            print key "\t" orig
        }' | sort -r | cut -f2-
    fi
}

# HTML에서 href="..." 값만 추출 (POSIX sed 호환)
_isodl_hrefs() {
    sed -n 's/.*href="\([^"]*\)".*/\1/p'
}

# Ubuntu Server / Desktop 스크랩 ($1: server|desktop)
_isodl_scrape_ubuntu() {
    local kind="${1:-server}"
    local base_url="https://releases.ubuntu.com"
    local html dirs ver sub_html iso_pat iso
    html="$(_isodl_fetch "${base_url}/")" || return 1

    # 메이저 릴리즈 디렉토리(XX.XX/)만 추출 후 최신순 상위 6개
    dirs="$(printf '%s\n' "$html" | _isodl_hrefs \
        | grep -E '^[0-9]+\.[0-9]+/$' \
        | sed 's#/$##' | sort -u | _isodl_vsort_desc | head -n 6)"

    if [ "$kind" = "desktop" ]; then
        iso_pat='^ubuntu-[0-9][0-9.]*-desktop-amd64\.iso$'
    else
        iso_pat='^ubuntu-[0-9][0-9.]*-live-server-amd64\.iso$'
    fi

    while IFS= read -r ver; do
        [ -z "$ver" ] && continue
        sub_html="$(_isodl_fetch "${base_url}/${ver}/")" || continue
        iso="$(printf '%s\n' "$sub_html" | _isodl_hrefs \
            | grep -E "$iso_pat" | grep -v 'beta' \
            | sort -u | _isodl_vsort_desc | head -n 1)"
        [ -n "$iso" ] && printf '%s|%s|%s/%s/%s\n' "$ver" "$iso" "$base_url" "$ver" "$iso"
    done <<EOF
$dirs
EOF
}

# Debian netinst 스크랩 (최신 current + 아카이브 이전 버전/메이저)
_isodl_scrape_debian() {
    local cur_url="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd"
    local arch_url="https://cdimage.debian.org/cdimage/archive"
    local cur_html cur_iso cur_ver arch_html vers ver maj
    local prev_maj="" maj_cnt=0 total_cnt=0

    cur_html="$(_isodl_fetch "${cur_url}/")"
    if [ -n "$cur_html" ]; then
        cur_iso="$(printf '%s\n' "$cur_html" | _isodl_hrefs \
            | grep -E '^debian-[0-9]+\.[0-9]+\.[0-9]+-amd64-netinst\.iso$' \
            | sort -u | _isodl_vsort_desc | head -n 1)"
        if [ -n "$cur_iso" ]; then
            cur_ver="$(printf '%s\n' "$cur_iso" | sed 's/^debian-\([0-9.]*\)-amd64-netinst\.iso$/\1/')"
            printf '%s (최신)|%s|%s/%s\n' "$cur_ver" "$cur_iso" "$cur_url" "$cur_iso"
            total_cnt=$((total_cnt + 1))
        fi
    fi

    arch_html="$(_isodl_fetch "${arch_url}/")" || return 0
    vers="$(printf '%s\n' "$arch_html" | _isodl_hrefs \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+/$' \
        | sed 's#/$##' | sort -u | _isodl_vsort_desc)"

    # 메이저별 상위 2개씩(최신 메이저는 3개) 최대 8개 선별
    while IFS= read -r ver; do
        [ -z "$ver" ] && continue
        [ "$ver" = "$cur_ver" ] && continue
        maj="${ver%%.*}"
        if [ "$maj" != "$prev_maj" ]; then
            prev_maj="$maj"
            maj_cnt=0
        fi
        maj_cnt=$((maj_cnt + 1))
        if [ "$maj_cnt" -le 2 ]; then
            printf '%s|%s|%s/%s/amd64/iso-cd/%s\n' \
                "$ver" "debian-${ver}-amd64-netinst.iso" "$arch_url" "$ver" "debian-${ver}-amd64-netinst.iso"
            total_cnt=$((total_cnt + 1))
        fi
        [ "$total_cnt" -ge 8 ] && break
    done <<EOF
$vers
EOF
}

# AlmaLinux 스크랩 (메이저 최신 3개 × minimal/dvd/boot)
_isodl_scrape_alma() {
    local base_url="https://repo.almalinux.org/almalinux"
    local html majors maj sub_html isos ed iso
    html="$(_isodl_fetch "${base_url}/")" || return 1

    majors="$(printf '%s\n' "$html" | _isodl_hrefs \
        | grep -E '^[0-9]+/$' | sed 's#/$##' | sort -u | _isodl_vsort_desc | head -n 3)"

    while IFS= read -r maj; do
        [ -z "$maj" ] && continue
        sub_html="$(_isodl_fetch "${base_url}/${maj}/isos/x86_64/")" || continue
        isos="$(printf '%s\n' "$sub_html" | _isodl_hrefs | sort -u)"
        for ed in minimal dvd boot; do
            iso="$(printf '%s\n' "$isos" | grep -E "^AlmaLinux-${maj}\.[0-9]+-x86_64-${ed}\.iso$" | _isodl_vsort_desc | head -n 1)"
            [ -z "$iso" ] && iso="$(printf '%s\n' "$isos" | grep -E "^AlmaLinux-${maj}-latest-x86_64-${ed}\.iso$" | head -n 1)"
            [ -n "$iso" ] && printf 'Alma %s (%s)|%s|%s/%s/isos/x86_64/%s\n' "$maj" "$ed" "$iso" "$base_url" "$maj" "$iso"
        done
    done <<EOF
$majors
EOF
}

# Rocky Linux 스크랩 (메이저 최신 3개 × minimal/dvd/boot)
_isodl_scrape_rocky() {
    local base_url="https://download.rockylinux.org/pub/rocky"
    local html majors maj sub_html isos ed iso
    html="$(_isodl_fetch "${base_url}/")" || return 1

    majors="$(printf '%s\n' "$html" | _isodl_hrefs \
        | grep -E '^[0-9]+/$' | sed 's#/$##' | sort -u | _isodl_vsort_desc | head -n 3)"

    while IFS= read -r maj; do
        [ -z "$maj" ] && continue
        sub_html="$(_isodl_fetch "${base_url}/${maj}/isos/x86_64/")" || continue
        isos="$(printf '%s\n' "$sub_html" | _isodl_hrefs | sort -u)"
        for ed in minimal dvd boot; do
            if [ "$ed" = "dvd" ]; then
                iso="$(printf '%s\n' "$isos" | grep -E "^Rocky-${maj}\.[0-9]+-x86_64-dvd1?\.iso$" | _isodl_vsort_desc | head -n 1)"
                [ -z "$iso" ] && iso="$(printf '%s\n' "$isos" | grep -E "^Rocky-${maj}-latest-x86_64-dvd1?\.iso$" | head -n 1)"
            else
                iso="$(printf '%s\n' "$isos" | grep -E "^Rocky-${maj}\.[0-9]+-x86_64-${ed}\.iso$" | _isodl_vsort_desc | head -n 1)"
                [ -z "$iso" ] && iso="$(printf '%s\n' "$isos" | grep -E "^Rocky-${maj}-latest-x86_64-${ed}\.iso$" | head -n 1)"
            fi
            [ -n "$iso" ] && printf 'Rocky %s (%s)|%s|%s/%s/isos/x86_64/%s\n' "$maj" "$ed" "$iso" "$base_url" "$maj" "$iso"
        done
    done <<EOF
$majors
EOF
}

# Windows VirtIO Drivers 스크랩 (latest + stable + archive 최신 5개)
_isodl_scrape_virtio() {
    local base_url="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads"
    local html dirs d sub_html iso ver

    printf 'latest (최신)|virtio-win-latest.iso|%s/latest-virtio/virtio-win.iso\n' "$base_url"
    printf 'stable (안정)|virtio-win-stable.iso|%s/stable-virtio/virtio-win.iso\n' "$base_url"

    html="$(_isodl_fetch "${base_url}/archive-virtio/")" || return 0
    dirs="$(printf '%s\n' "$html" | _isodl_hrefs \
        | grep -E '^virtio-win-[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?/$' \
        | sed 's#/$##' | sort -u | _isodl_vsort_desc | head -n 5)"

    while IFS= read -r d; do
        [ -z "$d" ] && continue
        sub_html="$(_isodl_fetch "${base_url}/archive-virtio/${d}/")" || continue
        iso="$(printf '%s\n' "$sub_html" | _isodl_hrefs \
            | grep -E '^virtio-win-[0-9].*\.iso$' | sort -u | _isodl_vsort_desc | head -n 1)"
        [ -z "$iso" ] && iso="$(printf '%s\n' "$sub_html" | _isodl_hrefs | grep -E '^virtio-win\.iso$' | head -n 1)"
        if [ -n "$iso" ]; then
            ver="${d#virtio-win-}"
            printf '%s|%s|%s/archive-virtio/%s/%s\n' "$ver" "$iso" "$base_url" "$d" "$iso"
        fi
    done <<EOF
$dirs
EOF
}

# Proxmox VE / Backup Server 스크랩 ($1: pve|pbs)
_isodl_scrape_proxmox() {
    local kind="${1:-pve}"
    local base_url="http://download.proxmox.com/iso"
    local html pat isos iso ver
    html="$(_isodl_fetch "${base_url}/")" || return 1

    if [ "$kind" = "pbs" ]; then
        pat='^proxmox-backup-server_[0-9].*\.iso$'
    else
        pat='^proxmox-ve_[0-9].*\.iso$'
    fi

    isos="$(printf '%s\n' "$html" | _isodl_hrefs \
        | sed 's#^\./##' | grep -E "$pat" | grep -v 'arm64' \
        | sort -u | _isodl_vsort_desc | head -n 8)"

    while IFS= read -r iso; do
        [ -z "$iso" ] && continue
        ver="$(printf '%s\n' "$iso" | sed 's/^[^_]*_\(.*\)\.iso$/\1/')"
        printf '%s|%s|%s/%s\n' "$ver" "$iso" "$base_url" "$iso"
    done <<EOF
$isos
EOF
}

# Ubuntu Cloud Image (.img) 스크랩 (최신 2개 + 짝수년 .04 LTS 최대 6개)
_isodl_scrape_cloud_ubuntu() {
    local base_url="https://cloud-images.ubuntu.com/releases"
    local html dirs ver picked="" cnt=0 sub_html img
    html="$(_isodl_fetch "${base_url}/")" || return 1

    dirs="$(printf '%s\n' "$html" | _isodl_hrefs \
        | grep -E '^[0-9]+\.[0-9]+/$' \
        | sed 's#/$##' | sort -u | _isodl_vsort_desc)"

    # 최신 2개 + 짝수년 .04 LTS 위주로 최대 6개 선별
    while IFS= read -r ver; do
        [ -z "$ver" ] && continue
        local yy="${ver%%.*}" mm="${ver#*.}"
        if [ "$cnt" -lt 2 ] || { [ "$mm" = "04" ] && [ $((yy % 2)) -eq 0 ]; }; then
            picked="${picked}${ver}
"
            cnt=$((cnt + 1))
            [ "$cnt" -ge 6 ] && break
        fi
    done <<EOF
$dirs
EOF

    while IFS= read -r ver; do
        [ -z "$ver" ] && continue
        sub_html="$(_isodl_fetch "${base_url}/${ver}/release/")" || continue
        img="$(printf '%s\n' "$sub_html" | _isodl_hrefs \
            | grep -E "^ubuntu-${ver}-server-cloudimg-amd64\.img$" \
            | sort -u | head -n 1)"
        if [ -n "$img" ]; then
            local yy="${ver%%.*}" mm="${ver#*.}" tag="$ver"
            [ "$mm" = "04" ] && [ $((yy % 2)) -eq 0 ] && tag="${ver} LTS"
            printf '%s|%s|%s/%s/release/%s\n' "$tag" "$img" "$base_url" "$ver" "$img"
        fi
    done <<EOF
$picked
EOF
}

# Debian Cloud Image (.qcow2) 스크랩 (generic + genericcloud, 최신 메이저순)
_isodl_scrape_cloud_debian() {
    local base_url="https://cloud.debian.org/images/cloud"
    local html codenames cn sub_html img num raw=""
    html="$(_isodl_fetch "${base_url}/")" || return 1

    codenames="$(printf '%s\n' "$html" | _isodl_hrefs \
        | grep -E '^[a-z]+/$' | sed 's#/$##' \
        | grep -Ev '^(sid|experimental|stretch|buster)$' | sort -u)"

    while IFS= read -r cn; do
        [ -z "$cn" ] && continue
        sub_html="$(_isodl_fetch "${base_url}/${cn}/latest/")" || continue
        for pat in 'debian-[0-9]+-generic-amd64\.qcow2' 'debian-[0-9]+-genericcloud-amd64\.qcow2'; do
            img="$(printf '%s\n' "$sub_html" | _isodl_hrefs | grep -E "^${pat}$" | sort -u | head -n 1)"
            if [ -n "$img" ]; then
                num="$(printf '%s\n' "$img" | sed 's/^debian-\([0-9]*\)-.*/\1/')"
                local ed="generic"
                case "$img" in *genericcloud*) ed="genericcloud" ;; esac
                raw="${raw}${num}|Debian ${num} (${cn}/${ed})|${img}|${base_url}/${cn}/latest/${img}
"
            fi
        done
    done <<EOF
$codenames
EOF

    printf '%s' "$raw" | _isodl_vsort_desc | cut -d'|' -f2- | head -n 8
}

# AlmaLinux Cloud Image (.qcow2) 스크랩 (메이저 최신 3개 × GenericCloud + ext4)
_isodl_scrape_cloud_alma() {
    local base_url="https://repo.almalinux.org/almalinux"
    local html majors maj sub_html imgs img
    html="$(_isodl_fetch "${base_url}/")" || return 1

    majors="$(printf '%s\n' "$html" | _isodl_hrefs \
        | grep -E '^[0-9]+/$' | sed 's#/$##' | sort -u | _isodl_vsort_desc | head -n 3)"

    while IFS= read -r maj; do
        [ -z "$maj" ] && continue
        sub_html="$(_isodl_fetch "${base_url}/${maj}/cloud/x86_64/images/")" || continue
        imgs="$(printf '%s\n' "$sub_html" | _isodl_hrefs | sort -u)"

        img="$(printf '%s\n' "$imgs" | grep -E "^AlmaLinux-${maj}-GenericCloud-${maj}\.[0-9]+-.*\.x86_64\.qcow2$" | _isodl_vsort_desc | head -n 1)"
        [ -z "$img" ] && img="$(printf '%s\n' "$imgs" | grep -E "^AlmaLinux-${maj}-GenericCloud-latest\.x86_64\.qcow2$" | head -n 1)"
        [ -n "$img" ] && printf 'Alma %s (Cloud)|%s|%s/%s/cloud/x86_64/images/%s\n' "$maj" "$img" "$base_url" "$maj" "$img"

        img="$(printf '%s\n' "$imgs" | grep -E "^AlmaLinux-${maj}-GenericCloud-ext4-${maj}\.[0-9]+-.*\.x86_64\.qcow2$" | _isodl_vsort_desc | head -n 1)"
        [ -n "$img" ] && printf 'Alma %s (ext4)|%s|%s/%s/cloud/x86_64/images/%s\n' "$maj" "$img" "$base_url" "$maj" "$img"
    done <<EOF
$majors
EOF
}

# Rocky Linux Cloud Image (.qcow2) 스크랩 (메이저 최신 3개 × Base + LVM)
_isodl_scrape_cloud_rocky() {
    local base_url="https://download.rockylinux.org/pub/rocky"
    local html majors maj sub_html imgs img
    html="$(_isodl_fetch "${base_url}/")" || return 1

    majors="$(printf '%s\n' "$html" | _isodl_hrefs \
        | grep -E '^[0-9]+/$' | sed 's#/$##' | sort -u | _isodl_vsort_desc | head -n 3)"

    while IFS= read -r maj; do
        [ -z "$maj" ] && continue
        sub_html="$(_isodl_fetch "${base_url}/${maj}/images/x86_64/")" || continue
        imgs="$(printf '%s\n' "$sub_html" | _isodl_hrefs | sort -u)"

        img="$(printf '%s\n' "$imgs" | grep -E "^Rocky-${maj}-GenericCloud-Base-${maj}\.[0-9]+-.*\.x86_64\.qcow2$" | _isodl_vsort_desc | head -n 1)"
        [ -z "$img" ] && img="$(printf '%s\n' "$imgs" | grep -E "^Rocky-${maj}-GenericCloud-Base\.latest\.x86_64\.qcow2$" | head -n 1)"
        [ -n "$img" ] && printf 'Rocky %s (Base)|%s|%s/%s/images/x86_64/%s\n' "$maj" "$img" "$base_url" "$maj" "$img"

        img="$(printf '%s\n' "$imgs" | grep -E "^Rocky-${maj}-GenericCloud-LVM-${maj}\.[0-9]+-.*\.x86_64\.qcow2$" | _isodl_vsort_desc | head -n 1)"
        [ -n "$img" ] && printf 'Rocky %s (LVM)|%s|%s/%s/images/x86_64/%s\n' "$maj" "$img" "$base_url" "$maj" "$img"
    done <<EOF
$majors
EOF
}

# Proxmox LXC 컨테이너 템플릿 (.tar.zst/.tar.xz) 스크랩 ($1: 배포판 필터 선택)
_isodl_scrape_lxc() {
    local filt="$1"
    local base_url="http://download.proxmox.com/images/system"
    local html files f label
    html="$(_isodl_fetch "${base_url}/")" || return 1

    files="$(printf '%s\n' "$html" | _isodl_hrefs \
        | grep -E '_amd64\.tar\.(zst|xz)$' \
        | sort -u | _isodl_vsort_desc)"

    if [ -n "$filt" ]; then
        files="$(printf '%s\n' "$files" | grep -i "^${filt}")"
    else
        # 전체 조회 시 주요 6개 배포판별로 최신 3개씩 균등 선별
        local d picked=""
        for d in ubuntu debian almalinux rockylinux alpine centos; do
            picked="${picked}$(printf '%s\n' "$files" | grep -E "^${d}-" | head -n 3)
"
        done
        files="$picked"
    fi

    while IFS= read -r f; do
        [ -z "$f" ] && continue
        label="$(printf '%s\n' "$f" | sed 's/^\([^_]*\)_.*/\1/')"
        printf '%s|%s|%s/%s\n' "$label" "$f" "$base_url" "$f"
    done <<EOF
$files
EOF
}

# 메인 인터랙티브 OS 이미지 자동 버전 스크랩 & 다운로더 (ISO / Cloud Image / LXC)
isodl() {
    local save_dir="" custom_dir=0 distro_arg="" lxc_filt=""
    while [ $# -gt 0 ]; do
        case "$1" in
        -d|--dir)
            save_dir="$2"
            custom_dir=1
            shift 2
            ;;
        -h|--help)
            echo "사용법: isodl [대상] [-d 저장경로]"
            echo "  ISO   : ubuntu, ubuntu-desktop, debian, alma, rocky, virtio, pve, pbs"
            echo "  Cloud : cloud-ubuntu, cloud-debian, cloud-alma, cloud-rocky (또는 clouddl)"
            echo "  LXC   : lxc [ubuntu|debian|alma|rocky|alpine] (또는 lxcdl)"
            return 0
            ;;
        *)
            if [ -z "$distro_arg" ]; then
                distro_arg="$1"
            else
                lxc_filt="$1"
            fi
            shift
            ;;
        esac
    done

    if [ -z "$save_dir" ]; then
        if [ -d "/var/lib/vz/template/iso" ] && [ -w "/var/lib/vz/template/iso" ]; then
            save_dir="/var/lib/vz/template/iso"
        else
            save_dir="$(pwd)"
        fi
    fi

    if [ ! -d "$save_dir" ]; then
        RED1; echo "[!] 저장 경로가 존재하지 않습니다: $save_dir"; NC
        return 1
    fi

    local distro_key="" distro_name="" dsel raw_list target_dir
    local -a item_labels=()
    local -a item_names=()
    local -a item_urls=()
    local idx sel pick_label pick_name pick_url
    local spd_in spd_val out_path dl_rc exist_sz

    while true; do
        distro_key=""
        distro_name=""
        target_dir="$save_dir"

        if [ -n "$distro_arg" ]; then
            case "$distro_arg" in
            ubuntu|ubuntu-server|u|us|1)        distro_key="ubuntu-server";  distro_name="Ubuntu Server ISO" ;;
            ubuntu-desktop|desktop|ud|2)        distro_key="ubuntu-desktop"; distro_name="Ubuntu Desktop ISO" ;;
            debian|deb|d|3)                     distro_key="debian";         distro_name="Debian ISO (netinst)" ;;
            alma|almalinux|a|4)                 distro_key="alma";           distro_name="AlmaLinux ISO" ;;
            rocky|rockylinux|r|5)               distro_key="rocky";          distro_name="Rocky Linux ISO" ;;
            virtio|win|windows|v|6)             distro_key="virtio";         distro_name="Windows VirtIO Drivers" ;;
            pve|proxmox|proxmox-ve|7)           distro_key="pve";            distro_name="Proxmox VE ISO" ;;
            pbs|proxmox-backup|8)               distro_key="pbs";            distro_name="Proxmox Backup Server ISO" ;;
            cloud-ubuntu|cu|9)                  distro_key="cloud-ubuntu";   distro_name="Ubuntu Cloud Image (.img)" ;;
            cloud-debian|cd|10)                 distro_key="cloud-debian";   distro_name="Debian Cloud Image (.qcow2)" ;;
            cloud-alma|ca|11)                   distro_key="cloud-alma";     distro_name="AlmaLinux Cloud Image (.qcow2)" ;;
            cloud-rocky|cr|12)                  distro_key="cloud-rocky";    distro_name="Rocky Linux Cloud Image (.qcow2)" ;;
            lxc|ct|13)                          distro_key="lxc";            distro_name="Proxmox LXC Template (.tar.zst/.xz)" ;;
            *)
                RED1; echo "[!] 알 수 없는 대상입니다: $distro_arg"; NC
                distro_arg=""
                continue
                ;;
            esac
            distro_arg=""
        else
            echo
            CYN1
            echo "=========================================================================="
            echo "  [isodl] OS 이미지 실시간 버전 스크랩 & 다운로더 (ISO / Cloud / LXC)"
            echo "=========================================================================="
            NC
            WHT; echo "  저장 경로: $save_dir  (LXC는 /var/lib/vz/template/cache 자동 사용)"; NC
            echo "--------------------------------------------------------------------------"
            YEL1; echo "  [설치용 ISO]"; NC
            echo "   1) Ubuntu Server          (LTS / 최신 6개)"
            echo "   2) Ubuntu Desktop         (LTS / 최신 6개)"
            echo "   3) Debian                 (netinst 최신 + 이전 메이저)"
            echo "   4) AlmaLinux              (최신 3개 메이저: minimal / dvd / boot)"
            echo "   5) Rocky Linux            (최신 3개 메이저: minimal / dvd / boot)"
            echo "   6) Windows VirtIO Drivers (latest / stable / archive)"
            echo "   7) Proxmox VE             (PVE 설치 ISO)"
            echo "   8) Proxmox Backup Server  (PBS 설치 ISO)"
            GRN1; echo "  [바로 쓰는 Cloud Image (.qcow2 / .img - Cloud-Init)]"; NC
            echo "   9) Ubuntu Cloud Image     (.img - 최신 + LTS)"
            echo "  10) Debian Cloud Image     (.qcow2 - generic / genericcloud)"
            echo "  11) AlmaLinux Cloud Image  (.qcow2 - GenericCloud 10/9/8)"
            echo "  12) Rocky Linux Cloud      (.qcow2 - GenericCloud Base/LVM 10/9/8)"
            MAG1; echo "  [바로 쓰는 LXC 컨테이너 템플릿 (.tar.zst / .tar.xz)]"; NC
            echo "  13) Proxmox LXC Template   (Ubuntu/Debian/Alma/Rocky/Alpine 등)"
            echo "   0) 종료 (q)"
            echo "--------------------------------------------------------------------------"
            printf ">>> 배포판 선택 [0-13]: "
            read -r dsel </dev/tty || return 0
            case "$dsel" in
            0|q|Q|"") echo "취소되었습니다."; return 0 ;;
            1)  distro_key="ubuntu-server";  distro_name="Ubuntu Server ISO" ;;
            2)  distro_key="ubuntu-desktop"; distro_name="Ubuntu Desktop ISO" ;;
            3)  distro_key="debian";         distro_name="Debian ISO (netinst)" ;;
            4)  distro_key="alma";           distro_name="AlmaLinux ISO" ;;
            5)  distro_key="rocky";          distro_name="Rocky Linux ISO" ;;
            6)  distro_key="virtio";         distro_name="Windows VirtIO Drivers" ;;
            7)  distro_key="pve";            distro_name="Proxmox VE ISO" ;;
            8)  distro_key="pbs";            distro_name="Proxmox Backup Server ISO" ;;
            9)  distro_key="cloud-ubuntu";   distro_name="Ubuntu Cloud Image (.img)" ;;
            10) distro_key="cloud-debian";   distro_name="Debian Cloud Image (.qcow2)" ;;
            11) distro_key="cloud-alma";     distro_name="AlmaLinux Cloud Image (.qcow2)" ;;
            12) distro_key="cloud-rocky";    distro_name="Rocky Linux Cloud Image (.qcow2)" ;;
            13) distro_key="lxc";            distro_name="Proxmox LXC Template (.tar.zst/.xz)" ;;
            *)
                RED1; echo "[!] 0~13 사이 번호를 선택하세요."; NC
                continue
                ;;
            esac
        fi

        # LXC 템플릿은 -d 지정이 없으면 Proxmox 표준 cache 경로 자동 사용
        if [ "$distro_key" = "lxc" ] && [ "$custom_dir" -eq 0 ]; then
            if [ -d "/var/lib/vz/template/cache" ] && [ -w "/var/lib/vz/template/cache" ]; then
                target_dir="/var/lib/vz/template/cache"
            fi
        fi

        echo
        YEL1; echo "[...] ${distro_name} 공식 사이트에서 버전 목록을 조회 중입니다..."; NC

        raw_list=""
        case "$distro_key" in
        ubuntu-server)  raw_list="$(_isodl_scrape_ubuntu server)" ;;
        ubuntu-desktop) raw_list="$(_isodl_scrape_ubuntu desktop)" ;;
        debian)         raw_list="$(_isodl_scrape_debian)" ;;
        alma)           raw_list="$(_isodl_scrape_alma)" ;;
        rocky)          raw_list="$(_isodl_scrape_rocky)" ;;
        virtio)         raw_list="$(_isodl_scrape_virtio)" ;;
        pve)            raw_list="$(_isodl_scrape_proxmox pve)" ;;
        pbs)            raw_list="$(_isodl_scrape_proxmox pbs)" ;;
        cloud-ubuntu)   raw_list="$(_isodl_scrape_cloud_ubuntu)" ;;
        cloud-debian)   raw_list="$(_isodl_scrape_cloud_debian)" ;;
        cloud-alma)     raw_list="$(_isodl_scrape_cloud_alma)" ;;
        cloud-rocky)    raw_list="$(_isodl_scrape_cloud_rocky)" ;;
        lxc)            raw_list="$(_isodl_scrape_lxc "$lxc_filt")"; lxc_filt="" ;;
        esac

        item_labels=()
        item_names=()
        item_urls=()

        while IFS='|' read -r pick_label pick_name pick_url; do
            [ -z "$pick_url" ] && continue
            item_labels[${#item_labels[@]}]="$pick_label"
            item_names[${#item_names[@]}]="$pick_name"
            item_urls[${#item_urls[@]}]="$pick_url"
        done <<EOF
$raw_list
EOF

        if [ "${#item_urls[@]}" -eq 0 ]; then
            RED1; echo "[!] ${distro_name} 목록을 가져오지 못했습니다. (네트워크 또는 사이트 구조 변경 확인 필요)"; NC
            continue
        fi

        echo
        CYN1
        echo "--------------------------------------------------------------------------"
        echo "  [${distro_name}] 조회된 목록 (최신순, 총 ${#item_urls[@]}개)"
        echo "  저장 경로: ${target_dir}"
        echo "--------------------------------------------------------------------------"
        NC
        idx=0
        while [ "$idx" -lt "${#item_urls[@]}" ]; do
            out_path="${target_dir}/${item_names[$idx]}"
            if [ -f "$out_path" ]; then
                exist_sz="$(ls -lh "$out_path" 2>/dev/null | awk '{print $5}')"
                printf "  %2d) %-22s  %-44s  \033[1;32m[이미 있음 %s]\033[0m\n" \
                    "$((idx + 1))" "[${item_labels[$idx]}]" "${item_names[$idx]}" "$exist_sz"
            else
                printf "  %2d) %-22s  %s\n" \
                    "$((idx + 1))" "[${item_labels[$idx]}]" "${item_names[$idx]}"
            fi
            idx=$((idx + 1))
        done
        echo "--------------------------------------------------------------------------"
        echo "   b) 배포판 다시 선택   |   0/q) 종료"
        echo "--------------------------------------------------------------------------"

        printf ">>> 다운로드할 번호 선택 [1-%d, b, q]: " "${#item_urls[@]}"
        read -r sel </dev/tty || return 0

        case "$sel" in
        b|B) continue ;;
        0|q|Q|"") echo "취소되었습니다."; return 0 ;;
        esac

        if ! printf '%s\n' "$sel" | grep -Eq '^[0-9]+$' || [ "$sel" -lt 1 ] || [ "$sel" -gt "${#item_urls[@]}" ]; then
            RED1; echo "[!] 잘못된 번호입니다: $sel"; NC
            continue
        fi

        idx=$((sel - 1))
        pick_label="${item_labels[$idx]}"
        pick_name="${item_names[$idx]}"
        pick_url="${item_urls[$idx]}"
        out_path="${target_dir}/${pick_name}"

        echo
        WHT1; echo "  선택 파일 : $pick_name"; NC
        echo "  다운 URL  : $pick_url"
        echo "  저장 경로 : $out_path"
        echo
        printf ">>> 속도 제한 [Enter/1:무제한, 2:10m, 3:20m, 4:50m, 5:100m, 직접입력 예:7m]: "
        read -r spd_in </dev/tty || return 0
        spd_val=""
        case "$spd_in" in
        ""|1|0) spd_val="" ;;
        2)      spd_val="10m" ;;
        3)      spd_val="20m" ;;
        4)      spd_val="50m" ;;
        5)      spd_val="100m" ;;
        *)      spd_val="$spd_in" ;;
        esac

        echo
        if [ -n "$spd_val" ]; then
            GRN1; echo "[>>] 다운로드 시작 (속도 제한: ${spd_val}, 이어받기 지원)..."; NC
        else
            GRN1; echo "[>>] 다운로드 시작 (속도 무제한, 이어받기 지원)..."; NC
        fi

        dl_rc=1
        if command -v wget >/dev/null 2>&1; then
            if [ -n "$spd_val" ]; then
                wget -c --limit-rate="$spd_val" -O "$out_path" "$pick_url"
                dl_rc=$?
            else
                wget -c -O "$out_path" "$pick_url"
                dl_rc=$?
            fi
        elif command -v curl >/dev/null 2>&1; then
            if [ -n "$spd_val" ]; then
                curl -fSL -C - --limit-rate "$spd_val" -o "$out_path" "$pick_url"
                dl_rc=$?
            else
                curl -fSL -C - -o "$out_path" "$pick_url"
                dl_rc=$?
            fi
        else
            RED1; echo "[!] wget 또는 curl 이 설치되어 있지 않습니다."; NC
            return 1
        fi

        if [ "$dl_rc" -eq 0 ] && [ -s "$out_path" ]; then
            echo
            GRN1; echo "[OK] 다운로드 완료!"; NC
            ls -lh "$out_path"
            command -v push >/dev/null 2>&1 && push "OS 이미지 다운로드 완료: ${pick_name} (${HOSTNAME})"
            return 0
        else
            echo
            RED1; echo "[!] 다운로드 실패 (exit=${dl_rc})"; NC
            [ -f "$out_path" ] && [ ! -s "$out_path" ] && rm -f "$out_path"
            return 1
        fi
    done
}

# 바로 쓰는 Cloud Image (.qcow2 / .img) 전용 단축 함수
clouddl() {
    case "$1" in
    ubuntu|u) shift; isodl cloud-ubuntu "$@" ;;
    debian|d) shift; isodl cloud-debian "$@" ;;
    alma|a)   shift; isodl cloud-alma "$@" ;;
    rocky|r)  shift; isodl cloud-rocky "$@" ;;
    -h|--help)
        echo "사용법: clouddl [ubuntu|debian|alma|rocky] [-d 저장경로]"
        return 0
        ;;
    "")
        echo
        GRN1; echo "  [clouddl] 바로 쓰는 Cloud Image (.qcow2 / .img) 선택"; NC
        echo "  1) Ubuntu Cloud Image (.img)"
        echo "  2) Debian Cloud Image (.qcow2)"
        echo "  3) AlmaLinux Cloud Image (.qcow2)"
        echo "  4) Rocky Linux Cloud Image (.qcow2)"
        echo "  0) 취소"
        local csel
        printf ">>> 선택 [0-4]: "
        read -r csel </dev/tty || return 0
        case "$csel" in
        1) isodl cloud-ubuntu ;;
        2) isodl cloud-debian ;;
        3) isodl cloud-alma ;;
        4) isodl cloud-rocky ;;
        *) return 0 ;;
        esac
        ;;
    *)
        isodl "$@"
        ;;
    esac
}

# 바로 쓰는 Proxmox LXC 컨테이너 템플릿 전용 단축 함수
lxcdl() {
    isodl lxc "$@"
}

# 명령어 사용가능여부 체크 acmd curl -m3 -o
able() { command -v "$1" &>/dev/null && return 0 || return 1; }

# 명령어 이름 출력후 결과 출력
eval0() {
    local c="$*"
    echo -n "$c: "
    eval "$c"
}

# ip filter
gip() { grep -E '([0-9]{1,3}\.){3}[0-9]{1,3}'; }
# ip only filter - 1 line multi ip
gipa() { awk '{while(match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {print substr($0, RSTART, RLENGTH) ; $0 = substr($0, RSTART+RLENGTH)}}'; }
# ip && port
gipp() { awk '{while(match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/)) {print substr($0, RSTART, RLENGTH) ; $0 = substr($0, RSTART+RLENGTH)}}'; }
# 첫번째 필드와 아이피와 포트 출력  $1 && ip && port
gipp1() { awk '{printf $1 " "}; {while(match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/)) {ip_port = substr($0, RSTART, RLENGTH); printf ip_port " "; $0 = substr($0, RSTART+RLENGTH)}; print ""}'; }
# 두번째 필드와 아이피와 포트 출력
gipp2() { awk '{printf $2 " "}; {while(match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/)) {ip_port = substr($0, RSTART, RLENGTH); printf ip_port " "; $0 = substr($0, RSTART+RLENGTH)}; print ""}'; }

# ip only filter gip5-> 5번째 필드에서 아이피만 추출
gip0() { awk 'match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {print substr($0, RSTART, RLENGTH)}'; }
gip1() { awk 'match($1, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {print substr($1, RSTART, RLENGTH)}'; }
gip2() { awk 'match($2, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {print substr($2, RSTART, RLENGTH)}'; }
gip5() { awk 'match($5, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {print substr($5, RSTART, RLENGTH)}'; }

# 특정필드에 검색어가 있는 줄추출 gfind 1 search
gfind() { awk -v search="$2" -v f="$1" 'match($f, search) {print $0}'; }

# exceptip filter
eip() { [ -s "$gotmp"/go_exceptips_grep.txt ] && grep -vEf "$gotmp"/go_exceptips_grep.txt || cat; }

# field except // grep -v 은 줄전체를 기준으로 하지만 eip5 는 5번째 필드를 기준으로 세분화함
eipf() {
    field="$1"
    if [ -s "$gotmp"/go_exceptips_grep.txt ]; then

        awk -v field="$field" -v gotmp="$gotmp" 'BEGIN { while (getline < (gotmp "/go_exceptips_grep.txt")) exceptips[$0] = 1 } { ma = 0; for (except in exceptips) { if (index($field, except) == 1) { ma = 1; break } } if (ma == 0) print }' -
    else cat; fi
}
eip3() { eipf 3; }
eip4() { eipf 4; }
eip5() { eipf 5; }

nodeip() {
    local node="$1"
    jq -r --arg node "$node" '.nodelist[$node].ip // empty' /etc/pve/.members
}

# proxmox vmslist

vmslist() {
    pvesh get /cluster/resources -type vm --output-format json 2>/dev/null |
        jq -r '
            .[] |
            if (.name == null or .name == "") then
                {id: .id, name: "unknown", status: "cluster_down"}
            else
                {id: .id, name: .name, status: .status}
            end
            | "\(.id) \(.name) \(.status)"
        ' | column -t
}

vmslistview() {
    output=$(vmslist)
    vmslistcount=$(echo "$output" | wc -l)
    ((vmslistcount > 10)) && echo "$output" | s3cols || echo "$output" | s2cols
}

# 긴줄을 2열로 13 24 36...
s2cols() {
    inp=$(cat)
    t_lines=$(echo "$inp" | wc -l)
    l_p_col=$((t_lines / 2 + (t_lines % 2 > 0 ? 1 : 0)))
    echo "$inp" | awk -v l_p_col=$l_p_col '{ if (NR <= l_p_col) c1[NR] = $0; else c2[NR - l_p_col] = $0 } END { for (i = 1; i <= l_p_col; ++i) { line = c1[i]; if (i in c2) line = line " | " c2[i]; print line; } }' | column -t
}

# 긴줄을 3열로 147 258 369...
s3cols() {
    inp=$(cat)
    t_lines=$(echo "$inp" | wc -l)
    l_p_col=$((t_lines / 3 + (t_lines % 3 > 0 ? 1 : 0)))
    echo "$inp" | awk -v l_p_col=$l_p_col '{ if (NR <= l_p_col) c1[NR] = $0; else if (NR > l_p_col && NR <= l_p_col * 2) c2[NR - l_p_col] = $0; else c3[NR - l_p_col * 2] = $0 } END { for (i = 1; i <= l_p_col; ++i) { line = c1[i] " | "; if (i in c2) line = line c2[i] " | "; if (i in c3) line = line c3[i]; print line; } }' | column -t
}

# datetag
datetag1() { date "+%Y%m%d"; }
datetag() { datetag1; }
ymd() { datetag1; }
datetag=$(datetag)
export datetag ymd=$datetag
datetag2() { date "+%Y%m%d_%H%M%S"; }
ydmhms() { datetag2; }
datetag3() { date "+%Y%m%d_%H%M%S"_$((RANDOM % 9000 + 1000)); }
ymdhmsr() { datetag3; }
datetagw() { date "+%Y%m%d_%w"; } # 0-6
ymdw() { datetagw; }
lastday() { date -d "$(date '+%Y-%m-01') 1 month -1 day" '+%Y-%m-%d'; }
# after
lastdaya() { date -d "$(date '+%Y-%m-01') 2 month -1 day" '+%Y-%m-%d'; }
# before
lastdayb() { date -d "$(date '+%Y-%m-01') 0 month -1 day" '+%Y-%m-%d'; }

# seen # not sort && uniq
seen() { awk '!seen[$0]++'; }
# not sort && uniq && lastseen print
#lastseen() { awk '{ records[$0] = NR } END { for (record in records) { sorted[records[record]] = record } for (i = 1; i <= NR; i++) { if (sorted[i]) { print sorted[i] } } }'; }
lastseen() { awk '{ last[$0] = NR; line[NR] = $0 } END { for (i = 1; i <= NR; i++) if (last[line[i]] == i) print line[i] }'; }

readv() {
    # printf + read -rep ' ' 조합 시 bash readline 이 앞선 ANSI/긴 프롬프트 길이를 몰라 줄 맨 앞을 덮어쓰는 버그 방지
    printf '\n'
    IFS="" read -rep '>>> : ' "$1"
}

# 후보 명령어 중 순서대로 실행 가능한 첫 번째 명령을 실행
# 사용법: execute 후보1 후보2 ... [-- 인자1 인자2 ...]
execute() {
    local _cands=() _args=() _sep=0 _a _bin
    for _a in "$@"; do
        if [ $_sep -eq 0 ] && [ "$_a" = "--" ]; then
            _sep=1
        elif [ $_sep -eq 0 ]; then
            _cands[${#_cands[@]}]="$_a"
        else
            _args[${#_args[@]}]="$_a"
        fi
    done
    for _a in "${_cands[@]}"; do
        _bin=""
        if [ -x "$_a" ]; then
            _bin="$_a"
        else
            _bin="$(command -v "$_a" 2>/dev/null)"
        fi
        if [ -n "$_bin" ] && [ -x "$_bin" ]; then
            "$_bin" "${_args[@]}"
            return $?
        fi
    done
    echo "execute: not found (${_cands[*]})" >&2
    return 127
}

# bashcomm .bashrc 의 alias 사용가능 // history 사용가능
bashcomm() {
    IN_BASHCOMM=1
    echo
    local original_aliases prev_empty=false cmd
    original_aliases=$(shopt -p expand_aliases)
    shopt -s expand_aliases
    source "${HOME}/.bashrc"
    unalias q 2>/dev/null

    HISTFILE="$gotmp/go_history.txt"
    history -r "$HISTFILE"

    local exit_loop=false

    while ! $exit_loop; do
        # show working directory info
        CYN
        user=$(id -un)
        pwdv=$(pwd)
        echo -n "user: $user  |  pwd: "
        [[ -L $pwdv ]] && ls -al "$pwdv" | awk '{print $(NF-2),$(NF-1),$NF}' || echo "$pwdv"
        NC

        #trap 'stty sane;break' SIGINT
        trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
        IFS="" read -rep 'BaSH_Command_[q] > ' cmd
        [[ $? -eq 1 ]] && cmd="q"
        trap - INT

        if [[ $cmd == "q" ]]; then
            exit_loop=true
        elif [[ -z $cmd ]]; then
            if $prev_empty; then
                exit_loop=true
            else
                prev_empty=true
            fi
        else
            prev_empty=false
            history -s "$cmd"
            eval "process_commands \"$cmd\" y nodone"
            history -a "$HISTFILE"
        fi
    done

    # 한 번만 호출
    eval "$original_aliases"
    unset -v IN_BASHCOMM
}

# rbackup -> rollback
rollback() {
    local d base org
    d="$(dirname "$1")"
    base="$(basename "$1")"
    org="${base}.org.$(date +%Y%m%d)"
    echo "$d / $base / mv to $org && rollback"
    readx
    [ ! -f "$1" ] && {
        echo "오류: 파일 없음."
        return 1
    }
    trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
    PS3="시간순 정렬 - 복구할 파일 선택: "
    select file in $(find "$d" -maxdepth 1 -name "${base}.[0-9]*.bak" -print0 | xargs -0 ls -lt | awk '{print $NF}' | head -n 5); do [ -n "$file" ] && {
        cdiff "$1" "$file"
        readx
        mv -n "$1" "$d/$org" && cp -f "$file" "$d/$base" && echo "복원됨: '$d/$base', 원래: '$d/$org'" && readx
        break
    }; done </dev/tty
    trap - INT
    savescut && exec "$gofile" $scut
}

st() {
    # 1. 인수가 없을 때 (`st`): 전체 문자열 출력 (기존과 동일)
    if [ $# -eq 0 ]; then
        if [ -z "$shortcutstr" ]; then
            echo "오류: shortcutstr 변수가 정의되지 않았습니다." 1>&2
            return 1
        fi
        echo "$shortcutstr"
        return 0
    fi

    local shortcut="$1"

    # 2. 인수가 하나일 때 (`st <shortcut>`): shortcut 존재 여부 확인 후 출력
    if [ $# -eq 1 ]; then
        if [ -z "$shortcutstr" ]; then
            echo "오류: shortcutstr 변수가 정의되지 않았습니다." 1>&2
            return 1
        fi
        # awk를 사용하여 shortcut이 첫 번째 필드로 존재하는지 확인
        local found_shortcut=$(echo "$shortcutstr" | awk -v needle="$shortcut" -v RS='@@@' -F'|' '
            # 문자열이 RS로 시작할 경우 첫 번째 빈 레코드 건너뛰기
            NR <= 1 && $0 == "" { next }
            # 첫 번째 필드가 주어진 shortcut(needle)과 일치하는지 확인
            $1 == needle {
                print needle  # 찾았으면 입력된 shortcut(needle) 자체를 출력
                exit # 찾았으면 즉시 awk 종료
            }
        ') # awk의 출력을 변수에 저장

        # awk가 무언가를 출력했는지 확인 (즉, shortcut을 찾았는지 확인)
        if [ -n "$found_shortcut" ]; then
            echo "$found_shortcut" # 찾은 shortcut 출력
            return 0               # 성공 종료
        else
            # 찾지 못했으면 아무것도 출력하지 않고 실패(1) 반환 (선택 사항)
            # 또는 성공(0)으로 간주하고 아무것도 출력하지 않을 수도 있음
            return 1 # 예: 못 찾았으면 실패로 처리
        fi
    fi

    # 3. 인수가 두 개일 때 (`st <shortcut> <n|b>`): 다음/이전 단축키 이름 출력 (기존 로직 활용)
    if [ $# -eq 2 ]; then
        local mode="$2"
        if [ -z "$shortcutstr" ]; then
            echo "오류: shortcutstr 변수가 정의되지 않았습니다." 1>&2
            return 1
        fi

        # mode 유효성 검사
        if [ "$mode" != "n" ] && [ "$mode" != "b" ]; then
            echo "사용법: st <shortcut> [<n|b>] 또는 st" 1>&2
            return 1
        fi

        # 다음/이전 항목의 *이름*($1)을 찾는 awk 로직
        echo "$shortcutstr" | awk -v shortcut="$shortcut" -v mode="$mode" -v RS='@@@' -F'|' '
            NR <= 1 && $0 == "" { next } # 첫 번째 빈 레코드 건너뛰기

            mode == "n" {
                if (print_next) {
                    print $1 # 다음 항목의 이름($1) 출력
                    exit # awk 종료
                }
                if ($1 == shortcut) {
                    print_next = 1
                }
            }

            mode == "b" {
                if ($1 == shortcut) {
                    if (prev_key != "") {
                       print prev_key # 이전 항목의 이름(prev_key) 출력
                    }
                    exit # awk 종료
                }
                prev_key = $1
            }
        '
        # awk의 종료 상태를 확인하여 성공/실패를 더 명확히 할 수 있지만,
        # 여기서는 원본처럼 awk 실행 자체는 성공(0)으로 간주
        return 0
    fi

    # 4. 인수가 너무 많을 때: 사용법 안내
    echo "사용법: st <shortcut> [<n|b>] 또는 st" 1>&2
    return 1
}

# shortcut view n> b<
# shortcut array view
str() {
    if [ "$1" ]; then
        printarr shortcutarr | grep "%%%" | awk -F'%%%' '{print $2}' | grep $1 | cgrep $1
    else
        st
        echo
        printarr shortcutarr | cgrep1 @@@ | less -r
    fi
}
search() { [ "$1" ] && str $1; }

# [I] 메뉴 색인 검색 (명령어 빈도수 + 제목/설명 매칭 정렬 후 번호 선택으로 즉시 이동)
#   - 사용: I [Enter] 후 검색어 입력, 또는 "I tailscale" / "I find" 처럼 바로 인자 전달
#   - 반환: 선택 성공 시 전역 _IDX_TARGET_SCUT 설정 후 return 0 / 취소 시 return 1
#   - 호환: Bash 2.05+ / 구 GNU awk / UTF-8 & EUC-KR / 한글 & 영문(GOLANG)
menu_index_search() {
    _IDX_TARGET_SCUT=""
    local _kw="$1"
    local _mi_ifs="$IFS"
    local _dl _hl _br
    if [ "${GOTERM_ENC:-}" = "euckr" ]; then
        _dl="================================================================================"
        _hl="--------------------------------------------------------------------------------"
        _br="L"
    else
        _dl="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        _hl="────────────────────────────────────────────────────────────────────────────────"
        _br="└"
    fi

    while true; do
        if [ -z "$_kw" ]; then
            local _p_in="" _in1="" _in2="" _irc=0
            if [ "$GOLANG" = "kr" ]; then
                _p_in="$(ko '>>> [I] 색인 검색어 (명령어/키워드, [Enter/ESC] 취소) : ')"
            else
                _p_in=">>> [I] Index search (cmd/keyword, [Enter/ESC] cancel) : "
            fi
            menu_read "$_p_in" _in1 _in2
            _irc=$?
            if [ "$_irc" -ne 0 ] || [ -z "$_in1" ]; then
                IFS="$_mi_ifs"
                return 1
            fi
            if [ -n "$_in2" ]; then
                _kw="${_in1} ${_in2}"
            else
                _kw="$_in1"
            fi
        fi

        # $env 전체 메뉴 블록을 1패스로 색인 스캔 후 빈도수 내림차순 정렬
        # 정렬키: 1) 실제 명령어 빈도(cmd_hits) 2) 제목/설명 매칭(meta_hits) 3) 변수명 매칭(var_hits) 4) 원래 메뉴 순서
        local _raw=""
        _raw="$(GO_IDX_KW="$_kw" awk '
        function flush_block(    k_hits) {
            if (scut != "" && (cmd_hits > 0 || meta_hits > 0 || var_hits > 0)) {
                printf "%06d\t%06d\t%06d\t%06d\t%s\t%s\t%s\n", cmd_hits, meta_hits, var_hits, (999999 - ord), scut, title, sample
            }
            scut = ""; title = ""; sample = ""
            cmd_hits = 0; meta_hits = 0; var_hits = 0
            in_blk = 0
        }
        BEGIN {
            kw = tolower(ENVIRON["GO_IDX_KW"])
            ord = 0; in_blk = 0
            scut = ""; title = ""; sample = ""
            cmd_hits = 0; meta_hits = 0; var_hits = 0
        }
        /^[[:space:]]*$/ {
            flush_block()
            next
        }
        /^%%% / {
            flush_block()
            ord++
            in_blk = 1
            hdr = substr($0, 5)
            sub(/\r$/, "", hdr)
            if (match(hdr, /\[[^]]+\]/)) {
                scut = substr(hdr, RSTART + 1, RLENGTH - 2)
            }
            title = hdr
            sub(/^\{[^}]+\}/, "", title)
            sub(/^[[:space:]]*>[[:space:]]*/, "", title)
            sub(/^[[:space:]]+/, "", title)
            sub(/[[:space:]]+$/, "", title)
            gsub(/\t/, " ", title)
            if (kw != "" && index(tolower(title), kw) > 0) {
                meta_hits++
            }
            next
        }
        !in_blk { next }
        /^%%%e / || /^%% / { next }
        {
            line = $0
            sub(/\r$/, "", line)
            if (line ~ /^[[:space:]]*#/) {
                if (kw != "" && index(tolower(line), kw) > 0) {
                    meta_hits++
                }
                next
            }
            if (line ~ /^[[:space:]]*\{submenu_[^}]+\}[[:space:]]*$/) {
                next
            }
            clean_cmd = line
            gsub(/var[A-Z][A-Za-z0-9_]*/, "", clean_cmd)
            if (kw != "" && index(tolower(clean_cmd), kw) > 0) {
                cmd_hits++
                if (sample == "") {
                    s = line
                    sub(/^[[:space:]]+/, "", s)
                    gsub(/\t/, " ", s)
                    if (length(s) > 74) s = substr(s, 1, 71) "..."
                    sample = s
                }
            } else if (kw != "" && index(tolower(line), kw) > 0) {
                var_hits++
                if (sample == "") {
                    s = line
                    sub(/^[[:space:]]+/, "", s)
                    gsub(/\t/, " ", s)
                    if (length(s) > 74) s = substr(s, 1, 71) "..."
                    sample = s
                }
            }
        }
        END {
            flush_block()
        }
        ' "$env" 2>/dev/null | LC_ALL=C sort -r)"

        if [ -z "$_raw" ]; then
            echo
            if [ "$GOLANG" = "kr" ]; then
                printf '\033[1;33m%s\033[0m\n' "$(ko "  [I] '%s' 에 해당하는 메뉴를 찾지 못했습니다." "$_kw")"
            else
                printf '\033[1;33m  [I] No menu matched "%s".\033[0m\n' "$_kw"
            fi
            _kw=""
            continue
        fi

        unset _idx_scuts _idx_titles _idx_cmds _idx_metas _idx_vars _idx_samples
        _idx_scuts=()
        _idx_titles=()
        _idx_cmds=()
        _idx_metas=()
        _idx_vars=()
        _idx_samples=()

        local _total=0 _max_show=25 _shown=0
        local _c1 _c2 _c3 _c4 _c5 _c6 _c7
        while IFS=$'\t' read -r _c1 _c2 _c3 _c4 _c5 _c6 _c7; do
            [ -z "$_c5" ] && continue
            _total=$((_total + 1))
            if [ "$_shown" -lt "$_max_show" ]; then
                _c1=$((10#${_c1:-0}))
                _c2=$((10#${_c2:-0}))
                _c3=$((10#${_c3:-0}))
                _idx_scuts[${#_idx_scuts[@]}]="$_c5"
                _idx_titles[${#_idx_titles[@]}]="$_c6"
                _idx_cmds[${#_idx_cmds[@]}]="$_c1"
                _idx_metas[${#_idx_metas[@]}]="$_c2"
                _idx_vars[${#_idx_vars[@]}]="$_c3"
                _idx_samples[${#_idx_samples[@]}]="$_c7"
                _shown=$((_shown + 1))
            fi
        done <<EOF_IDX
$_raw
EOF_IDX
        IFS="$_mi_ifs"

        # 결과 화면 출력
        _IDX_LAST_KW="$_kw"
        _clear_keep_scrollback
        printf '\033[38;5;75m%s\033[0m\n' "$_dl"
        if [ "$GOLANG" = "kr" ]; then
            if [ "$_total" -gt "$_shown" ]; then
                printf '\033[1;33m  [I] %s\033[0m\n' "$(ko '색인 검색 결과 : "%s" (총 %d개 메뉴, 상위 %d개 표시)' "$_kw" "$_total" "$_shown")"
            else
                printf '\033[1;33m  [I] %s\033[0m\n' "$(ko '색인 검색 결과 : "%s" (총 %d개 메뉴)' "$_kw" "$_total")"
            fi
        else
            if [ "$_total" -gt "$_shown" ]; then
                printf '\033[1;33m  [I] Index results for "%s" (%d menus, showing top %d)\033[0m\n' "$_kw" "$_total" "$_shown"
            else
                printf '\033[1;33m  [I] Index results for "%s" (%d menus)\033[0m\n' "$_kw" "$_total"
            fi
        fi
        printf '\033[38;5;110m%s\033[0m\n' "$_hl"

        local _i=0 _no _sc _ti _ch _mh _vh _sm _badge
        while [ "$_i" -lt "$_shown" ]; do
            _no=$((_i + 1))
            _sc="${_idx_scuts[$_i]}"
            _ti="${_idx_titles[$_i]}"
            _ch="${_idx_cmds[$_i]}"
            _mh="${_idx_metas[$_i]}"
            _vh="${_idx_vars[$_i]}"
            _sm="${_idx_samples[$_i]}"

            if [ "$_ch" -gt 0 ]; then
                if [ "$GOLANG" = "kr" ]; then
                    _badge="$(printf '\033[1;32m(%s)\033[0m' "$(ko '명령 %d건' "$_ch")")"
                else
                    _badge="$(printf '\033[1;32m(%d cmds)\033[0m' "$_ch")"
                fi
            elif [ "$_mh" -gt 0 ]; then
                if [ "$GOLANG" = "kr" ]; then
                    _badge="$(printf '\033[0;36m(%s)\033[0m' "$(ko '제목/설명 %d건' "$_mh")")"
                else
                    _badge="$(printf '\033[0;36m(%d title/desc)\033[0m' "$_mh")"
                fi
            else
                if [ "$GOLANG" = "kr" ]; then
                    _badge="$(printf '\033[0;33m(%s)\033[0m' "$(ko '변수 %d건' "$_vh")")"
                else
                    _badge="$(printf '\033[0;33m(%d var)\033[0m' "$_vh")"
                fi
            fi

            printf ' \033[1;37m%2d.\033[0m \033[1;36m[%-8s]\033[0m %s  %b\n' "$_no" "$_sc" "$_ti" "$_badge"
            if [ -n "$_sm" ]; then
                printf '     \033[0;37m%s %s\033[0m\n' "$_br" "$_sm"
            fi
            _i=$((_i + 1))
        done

        printf '\033[38;5;110m%s\033[0m\n' "$_hl"

        local _sel_p _sel1="" _sel2="" _src=0
        if [ "$GOLANG" = "kr" ]; then
            _sel_p="$(ko '>>> 이동할 번호 [1-%d]  [Enter] 1번  [/검색어] 재검색  [0/q/ESC] 취소 : ' "$_shown")"
        else
            _sel_p="$(printf '>>> Select [1-%d]  [Enter] #1  [/keyword] Re-search  [0/q/ESC] Cancel : ' "$_shown")"
        fi

        while true; do
            menu_read "$_sel_p" _sel1 _sel2
            _src=$?
            if [ "$_src" -ne 0 ] || [ "$_sel1" = "0" ] || [ "$_sel1" = "q" ] || [ "$_sel1" = "Q" ]; then
                unset _idx_scuts _idx_titles _idx_cmds _idx_metas _idx_vars _idx_samples
                IFS="$_mi_ifs"
                return 1
            fi
            # 빈 Enter -> 1번으로 바로 이동
            if [ -z "$_sel1" ]; then
                _sel1="1"
            fi
            # /키워드 -> 재검색
            case "$_sel1" in
                /*)
                    _kw="${_sel1#/}"
                    [ -n "$_sel2" ] && _kw="${_kw} ${_sel2}"
                    break
                    ;;
            esac
            # 숫자 선택 확인
            if expr "$_sel1" : '^[0-9][0-9]*$' >/dev/null 2>&1 && [ "$_sel1" -ge 1 ] && [ "$_sel1" -le "$_shown" ]; then
                _IDX_TARGET_SCUT="${_idx_scuts[$((_sel1 - 1))]}"
                _IDX_LAST_KW="$_kw"
                _IDX_HILITE_KW="$_kw"
                _IDX_HILITE_ARMED=1
                local _kw_nav="${_kw//|/ }"
                if [ "${NAV_scut:-}" = "__IDX__" ]; then
                    NAV_title="$_kw_nav"
                else
                    nav_goto "__IDX__" "__IDX__" "$_kw_nav"
                fi
                unset _idx_scuts _idx_titles _idx_cmds _idx_metas _idx_vars _idx_samples
                IFS="$_mi_ifs"
                return 0
            fi
            if [ "$GOLANG" = "kr" ]; then
                printf '  \033[1;33m%s\033[0m\n' "$(ko '1~%d 사이 번호 또는 /검색어, 0(취소)을 입력하세요.' "$_shown")"
            else
                printf '  \033[1;33mEnter 1-%d, /keyword, or 0 to cancel.\033[0m\n' "$_shown"
            fi
        done
    done
}

# [I] ANSI 색상 코드를 보존하면서 일반 텍스트 구간의 검색어만 대소문자 무시 형광 하이라이트
_idx_hilite_ansi() {
    local _hl_kw="$1"
    [ -z "$_hl_kw" ] && { cat; return 0; }
    GO_HL_KW="$_hl_kw" awk '
    function hl_plain(str,    low, pos, res, mlen, orig) {
        if (kw == "" || str == "") return str
        mlen = length(kw)
        res = ""
        while (str != "") {
            low = tolower(str)
            pos = index(low, kw)
            if (pos == 0) {
                res = res str
                break
            }
            orig = substr(str, pos, mlen)
            res = res substr(str, 1, pos - 1) "\033[1;37;41m" orig "\033[0m" cur_ansi
            str = substr(str, pos + mlen)
        }
        return res
    }
    BEGIN {
        kw = tolower(ENVIRON["GO_HL_KW"])
    }
    {
        s = $0
        out = ""
        cur_ansi = ""
        while (s != "") {
            if (match(s, /\033\[[0-9;]*[A-Za-z]/)) {
                plain = substr(s, 1, RSTART - 1)
                seq = substr(s, RSTART, RLENGTH)
                out = out hl_plain(plain) seq
                if (seq == "\033[0m" || seq == "\033[m") {
                    cur_ansi = ""
                } else if (substr(seq, length(seq), 1) == "m") {
                    cur_ansi = seq
                }
                s = substr(s, RSTART + RLENGTH)
            } else {
                out = out hl_plain(s)
                break
            }
        }
        print out
    }'
}

# flow save and exec go.sh
savescut() {
    :
    #scutp
    #export scut=$scut oldscut=$oldscut ooldscut=$ooldscut oooldscut=$oooldscut ooooldscut=$ooooldscut
    #dline ; env | grep scut
}

# varVAR 형태의 변수를 파일에 저장해 두었다가 스크립트 재실행시 사용
# [규칙] `declare -p`(인수 없음)는 bash 2.05(구형)에서 내부 malloc 가드를 깨뜨려
#        종료 시 "*ap++ == 0x55 / Stopping myself..." abort 를 뿜는다 (mini·byus 실측).
#        `export -p` 는 동일한 `declare -x NAME="value"` 형식을 내면서 크래시가 없고,
#        bash 2.05 의 declare -p 는 `NAME=value` 형식이라 저장 자체가 0건이었다.
viewVAR() { export -p | grep "^declare -x var[A-Z]"; }
saveVAR() {
    export -p | grep "^declare -x var[A-Z]" >>~/.go.private.var
    #declare -p | grep "^declare -x" >~/.go.export.var
    export -p | grep "^declare -x" | encrypt >~/.go.export.var
    cat ~/.go.private.var | lastseen >~/.go.private.var.tmp && mv ~/.go.private.var.tmp ~/.go.private.var
    chmod 600 ~/.go.private.var
}
loadVAR() {
    [ -f ~/.go.private.var ] && source ~/.go.private.var
    if [ -f "$HOME/.go.export.var" ]; then
        if find "$HOME/.go.export.var" -type f -mmin +10 2>/dev/null | grep -q .; then
            rm -f "$HOME/.go.export.var"
        elif decrypt < "$HOME/.go.export.var" > "$HOME/.go.export.var.dec" 2>/dev/null && [ -s "$HOME/.go.export.var.dec" ]; then
            source "$HOME/.go.export.var.dec" 2>/dev/null
        fi
        rm -f "$HOME/.go.export.var" "$HOME/.go.export.var.dec" 2>/dev/null
    fi
}
editVAR() {
    [ -f ~/.go.private.var ] && vim ~/.go.private.var
}
initVAR() {
    [ -f ~/.go.private.var ] && rm -f ~/.go.private.var
    for var in $(compgen -v | grep -E "^var[A-Z]"); do
        unset "$var"
    done

}
format() {
    shfmt -i 4 -s -w $gofile || ay shfmt && shfmt -i 4 -s -w $gofile
}
newtemp() {
    echo "template_edit $1
template_view $1
!!! template_copy $1 $2 ;; cat \"\$lastarg\"

$1)
        cat >\"\$file_path\" <<'EOF'
EOF
;;
"
}
# 지정 파일의 특정 줄 번호로 백업 후 vim 점프
_conf_open_line() {
    local _f="$1" _ln="$2"
    [ ! -f "$_f" ] && return 1
    rbackup "$_f"
    if [ -n "$_ln" ] && [ "$_ln" -gt 0 ] 2>/dev/null; then
        vim +"$_ln" -c "silent! normal! zt" "$_f" || vi +"$_ln" "$_f" || nano +"$_ln" "$_f"
    else
        vim "$_f" || vi "$_f" || nano "$_f"
    fi
}

# go.env / go.sh / go.my.env 에서 함수 정의(fn() / function fn) 파일 및 줄 번호 탐색
_conf_find_func_loc() {
    local _fn="$1" _f="" _ln=""
    [ -z "$_fn" ] && return 1
    _CONF_FUNC_FILE=""
    _CONF_FUNC_LINE=""
    for _f in "$envorg" "$gofile" "$envorg2"; do
        [ -f "$_f" ] || continue
        _ln=$(awk -v fn="$_fn" '
            $0 ~ "^[[:space:]]*" fn "[[:space:]]*\\(\\)" || $0 ~ "^[[:space:]]*function[[:space:]]+" fn "([[:space:]]|\\(|$)" {
                print NR; exit
            }
        ' "$_f" 2>/dev/null)
        if [ -n "$_ln" ]; then
            _CONF_FUNC_FILE="$_f"
            _CONF_FUNC_LINE="$_ln"
            return 0
        fi
    done
    return 1
}

# go.env 에서 현재 챕터([scut] 또는 title_of_menu) 내 해당 명령어 줄 번호(NR) 탐색
_conf_find_cmd_line() {
    local _f="$1" _sc="$2" _raw="$3" _ttl="${4:-}" _ln=""
    [ -f "$_f" ] || return 1
    [ -z "$_raw" ] && return 1
    _ln=$(awk -v sc="$_sc" -v ttl="$_ttl" -v target="$_raw" '
        BEGIN {
            in_blk = 0; hit = 0; fb = 0
            # 영문 모드(:e -> :) 변환 대비 비교용 문자열
            t_alt = target
            if (substr(t_alt, 1, 2) == ": ") t_alt = ":e " substr(t_alt, 3)
        }
        {
            line = $0
            sub(/\r$/, "", line)
        }
        !in_blk {
            if (sc != "" && line ~ "^%%% .*\\[" sc "\\]") { in_blk = 1; next }
            if (sc == "" && ttl != "" && index(line, "%%% ") == 1 && index(line, ttl) > 0) { in_blk = 1; next }
            next
        }
        in_blk && line == "" { exit }
        in_blk {
            if (line == target || line == t_alt) { hit = NR; exit }
            if (fb == 0 && index(line, target) > 0) fb = NR
        }
        END {
            if (hit > 0) print hit
            else if (fb > 0) print fb
        }
    ' "$_f" 2>/dev/null)
    if [ -n "$_ln" ]; then
        printf '%s' "$_ln"
        return 0
    fi
    return 1
}

# 화면 번호(1..N)에 해당하는 항목을 판별해 서브메뉴 / 함수 정의 / 명령어 줄로 바로 점프
_conf_edit_cmd() {
    local _disp="$1" _orig="" _raw="" _body="" _tok="" _ln=""
    [ -z "$_disp" ] && return 1
    _orig="${original_indices[$((_disp - 1))]-}"
    [ -z "$_orig" ] && return 1
    _raw="${chosen_commands[$((_orig - 1))]-}"
    [ -z "$_raw" ] && return 1

    # _cmd_kind_badge 와 동일한 방식으로 명령어 첫 토큰 추출
    _body="${_raw#!!!}"
    _body="${_body#"${_body%%[![:space:]]*}"}"
    case "$_body" in
        :[[:space:]]*\;*)
            _body="${_body#*;}"
            _body="${_body#;}"
            _body="${_body#"${_body%%[![:space:]]*}"}"
            ;;
    esac
    _body="${_body%"${_body##*[![:space:]]}"}"
    _tok="${_body%%[[:space:]]*}"

    # 1) 서브메뉴 단축키([→메뉴]) -> 해당 서브메뉴 챕터로 점프
    if [ -n "$_tok" ] && [ "$_tok" = "$_body" ] && st "$_tok" >/dev/null 2>&1; then
        if grep -q "^%%% .*\[${_tok}\]" "$envorg" 2>/dev/null; then
            vi2 "$envorg" "$_tok"
            return 0
        elif [ -f "$envorg2" ] && grep -q "^%%% .*\[${_tok}\]" "$envorg2" 2>/dev/null; then
            vi2 "$envorg2" "$_tok"
            return 0
        fi
    fi

    # 2) 함수 메뉴([fn]) -> go.env / go.sh 내 함수 정의 위치로 점프
    if [ -n "$_tok" ] && declare -F "$_tok" >/dev/null 2>&1; then
        if _conf_find_func_loc "$_tok"; then
            _conf_open_line "$_CONF_FUNC_FILE" "$_CONF_FUNC_LINE"
            return 0
        fi
    fi

    # 3) 일반 명령어 -> 현재 챕터 내 해당 명령어 줄로 바로 점프
    _ln="$(_conf_find_cmd_line "$envorg" "$scut" "$_raw" "${title_of_menu:-}")"
    if [ -n "$_ln" ]; then
        _conf_open_line "$envorg" "$_ln"
        return 0
    fi
    if [ -f "$envorg2" ]; then
        _ln="$(_conf_find_cmd_line "$envorg2" "$scut" "$_raw" "${title_of_menu:-}")"
        if [ -n "$_ln" ]; then
            _conf_open_line "$envorg2" "$_ln"
            return 0
        fi
    fi

    # 폴백: 현재 챕터 헤더
    vi2 "$envorg" "$scut"
}

# vi2 envorg && restart go.sh
conf() {
    #readxy $cmd_choice1
    saveVAR
    local _arg="$1" _handled=0
    if [ -z "$_arg" ]; then
        if [ -n "${_CONF_CUR_ITEM:-}" ]; then
            _conf_edit_cmd "$_CONF_CUR_ITEM" && _handled=1
        elif [ -n "${_CONF_CUR_MENU_KEY:-}" ]; then
            vi2 "$envorg" "$_CONF_CUR_MENU_KEY" $cmd_choice1
            _handled=1
        fi
    elif expr "$_arg" : '^[1-9][0-9]*$' >/dev/null 2>&1 && [ "${display_idx:-0}" -gt 1 ] 2>/dev/null && [ "$_arg" -lt "$display_idx" ] 2>/dev/null; then
        _conf_edit_cmd "$_arg" && _handled=1
    fi
    if [ "$_handled" -eq 0 ]; then
        if [ -n "$_arg" ]; then
            if grep -q "^%%% .*\[${_arg}\]" "$envorg" 2>/dev/null; then
                vi2 "$envorg" "$_arg" $cmd_choice1
            elif declare -F "$_arg" >/dev/null 2>&1 && _conf_find_func_loc "$_arg"; then
                _conf_open_line "$_CONF_FUNC_FILE" "$_CONF_FUNC_LINE"
            else
                vi2 "$envorg" "$_arg" $cmd_choice1
            fi
        else
            vi2 "$envorg" "$scut" $cmd_choice1
        fi
    fi
    unset -v _CONF_CUR_ITEM _CONF_CUR_MENU_KEY _CONF_FUNC_FILE _CONF_FUNC_LINE
    savescut && exec "$gofile" "$scut"
}
# conf. : 원래 conf 동작 (현재 섹션 첫 줄 편집 후 재시작, 인자 지정 시 해당 섹션 첫 줄)
conf_sec() {
    saveVAR
    unset -v _CONF_CUR_ITEM _CONF_CUR_MENU_KEY _CONF_FUNC_FILE _CONF_FUNC_LINE
    if [ -n "$1" ]; then
        vi2 "$envorg" "$1"
    else
        vi2 "$envorg" "$scut"
    fi
    savescut && exec "$gofile" "$scut"
}
conf1() {
    saveVAR
    vi2 "$envorg" $scut tailedit
    savescut && exec "$gofile" "$scut"
}
confb() { conf1; }
confmy() {
    vi2 "$envorg2" $scut
    savescut && exec "$gofile" "$scut"
}
conff() {
    saveVAR
    [ -n "$1" ] && vi22 "$gofile" "$1" || vi22 "$gofile"
    savescut && exec "$gofile" "$scut"
}
confc() { rollback "$envorg"; }
conffc() { rollback "$gofile"; }

# confp # env 환경변수로 불러와 스크립트가 실행되는 동안 변수로 쓸수 있음
confp() { vi2a $HOME/go.private.env; }

# screen server // 스크립트에서 백그라운드로 계속 실행시키고자 하는 경우
scserver() {
    set -- $@ # 공백 기준으로 재파싱
    local title_raw="${1}_${2}"
    local title=$(echo "$title_raw" | sed 's/[^a-zA-Z0-9._-]/_/g')

    screen -dmS "$title" bash -c "$* ;echo \"On Screen ---> $title\" ;echo;df -h; exec /bin/bash"
    echo "Started screen session '$title' with: $*"
    screen -list
}
# Detached 세션 번호만 순서대로 접속
scra() {
    screen -list | grep 'Detached)' | awk '{print $1}' | cut -d. -f1 | tac | while read s; do
        echo "접속: $s"
        screen -rx "$s" </dev/tty
    done
    scl
}

# 모든 세션 번호 순서대로 접속 (Attached + Detached)
scraa() {
    screen -list | grep -E '(Attached|Detached)\)' | awk '{print $1}' | cut -d. -f1 | tac | while read s; do
        echo "접속: $s"
        screen -rx "$s" </dev/tty
    done
    scl
}

scl() { screen -ls | cgrepline1 Attached | cgrepline Detached; }

scrm() {
    echo before
    screen -ls
    dline
    for i in $(screen -ls | grep tach | grep "$1" | awk '{print $1}'); do screen -S $i -p 0 -X quit; done
    echo "after"
    screen -ls
    dline
}

goo() {
    echo "
디시 인사이드 말투. 나 형인거 알지?  한글로. 쉽게 이해할 수 있는 예를 들면서 설명. 내가 한 질문을 기존 대화와 융합하여 왜 이런 질문을 했는지 심층 분석후 답변. 문제 원인과 해결방법, 해결방법의 키포인트 설명. 참고할 팁이나 주의사항이 있으면함께 안내. 통찰력 있는 해설과 유사한 다른 분야도 소개. 새로운아이디어 제안.마무리에 결론만 내리지 말고, 꼬리를 무는 질문을 던져줘. 질문은 지능의 척도야. 너의 수준높은 질문을 부탁해. 각 섹션에 이모티콘을 충분히 활용하되, 소스는 장황하지 않고 최대한 간결하게 깔끔하게,중요사항!! 소스코드 부분은 내가 복사를 할수 있기 때문에 절대 이모티콘 넣으면 안되. bash script 질문은 bash2 호환 되게. 한줄명령은 한줄명령으로 대응. 소스 변수는 되도록 최소화하여 직관적이게 표현


"
}

# print conf
pconf() {
    if [ "$1" ]; then
        awk -v key="$1" '$0 ~ "\\[" key "\\]$" {p=1} p && /^$/ {exit} p' "$envorg" | cpipe
    else
        awk -v key="$scut" '$0 ~ "\\[" key "\\]$" {p=1} p && /^$/ {exit} p' "$envorg" | cpipe
    fi
}

ver() { ls -al $basefile; }
verr() { cdiff $basefile $basefile.1.bak; }

# bell
bell() { echo -ne "\a"; }
# telegram push
push() {
    local message _resp _desc _code
    message="$*"
    [ ! "$message" ] && IFS='' read -d '' -t1 message
    # 인수도 파이프값도 없을때 기본값 hostname 으로 지정
    [ ! "$message" ] && message="$HOSTNAME"

    if [ "$@" ] && [[ -z ${telegram_token} || -z ${telegram_chatid} ]]; then
        read -rep "Telegram. Add token and chatid? (y/n): " add_vars

        if [[ ${add_vars} == "y" ]]; then
            read -rep "Token: " telegram_token
            read -rep "Chatid: " telegram_chatid
            echo "telegram_token=${telegram_token}" >>"$HOME/go.private.env"
            echo "telegram_chatid=${telegram_chatid}" >>"$HOME/go.private.env"
            echo "$HOME/go.private.env <- telegram conf added!!! "
            export telegram_token=${telegram_token} && export telegram_chatid=${telegram_chatid}
        fi
    fi

    if [[ ${telegram_token} && ${telegram_chatid} ]]; then
        local _send_msg="$message" _enc_msg
        if [ ! "$(echo "$LANG" | grep -i "utf")" ] && command -v iconv >/dev/null 2>&1; then
            _send_msg="$(printf '%s' "$_send_msg" | iconv -f EUC-KR -t UTF-8 2>/dev/null || printf '%s' "$_send_msg")"
        fi
        if [ "${#_send_msg}" -gt 3800 ]; then
            _send_msg="$(printf '%s' "$_send_msg" | head -c 3800)"$'\n'"... (truncated: total ${#message} bytes)"
        fi
        _enc_msg="$(printf '%s' "${_send_msg:-ex) push \"msg\"}" | od -t x1 -A n | tr -d '\n' | tr ' ' '%')"
        _resp="$(curl -4 -m8 -ks -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" -d "chat_id=${telegram_chatid}&text=${_enc_msg}" 2>&1)"
        result=$?
        if [ "$result" -eq 0 ] && echo "$_resp" | grep -q '"ok":true'; then
            GRN1 && echo "push msg sent"
        elif [ "$result" -eq 0 ]; then
            _code="$(echo "$_resp" | sed -n 's/.*"error_code":\([0-9]*\).*/\1/p')"
            _desc="$(echo "$_resp" | sed -n 's/.*"description":"\([^"]*\)".*/\1/p')"
            RED1
            case "$_code" in
                401) ko "Err:401 -> 텔레그램 봇 토큰 인증 실패 (${_desc:-Unauthorized}) — ~/go.private.env 의 telegram_token 을 확인하세요" ;;
                400) ko "Err:400 -> 텔레그램 요청 오류 (${_desc:-Bad Request}) — ChatID(${telegram_chatid}) 또는 메시지 형식을 확인하세요" ;;
                403) ko "Err:403 -> 봇 권한 거부 (${_desc:-Forbidden}) — 봇 대화방에서 /start 를 먼저 눌러주세요" ;;
                404) ko "Err:404 -> 봇 토큰 형식 또는 API 경로 오류 (${_desc:-Not Found}) — telegram_token 을 확인하세요" ;;
                *)   ko "Err:${_code:-API} -> 텔레그램 API 오류: ${_desc:-$_resp}" ;;
            esac
        else
            RED1
            case "$result" in
                6)  ko "Err:6 -> DNS 조회 실패 (api.telegram.org 호스트를 찾을 수 없음)" ;;
                7)  ko "Err:7 -> 서버 연결 실패 (api.telegram.org:443 접속 거부/방화벽)" ;;
                28) ko "Err:28 -> 연결 시간 초과 (api.telegram.org 응답 지연 / 타임아웃)" ;;
                35) ko "Err:35 -> SSL/TLS 핸드셰이크 오류" ;;
                *)  ko "Err:$result -> push 전송 실패 (curl 종료코드: $result)" ;;
            esac
        fi
        NC
    fi
    # 기본적으로 인자 출력
    echo "$message"
}

push1() {
    local message _resp _desc _code _send_msg _enc_msg
    message="$*"
    [ -z "$message" ] && IFS='' read -d '' -t1 message
    [ -z "$message" ] && message="$HOSTNAME"

    # Telegram 정보가 없으면 메시지만 출력
    if [[ -z ${telegram_token} || -z ${telegram_chatid} ]]; then
        echo -e "\a[push1] $message"
        return 1
    fi

    _send_msg="$message"
    if [ ! "$(echo "$LANG" | grep -i "utf")" ] && command -v iconv >/dev/null 2>&1; then
        _send_msg="$(printf '%s' "$_send_msg" | iconv -f EUC-KR -t UTF-8 2>/dev/null || printf '%s' "$_send_msg")"
    fi
    if [ "${#_send_msg}" -gt 3800 ]; then
        _send_msg="$(printf '%s' "$_send_msg" | head -c 3800)"$'\n'"... (truncated: total ${#message} bytes)"
    fi
    _enc_msg="$(printf '%s' "${_send_msg}" | od -t x1 -A n | tr -d '\n' | tr ' ' '%')"

    # Telegram으로 전송
    _resp="$(curl -4 -m8 -ks -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" \
        -d "chat_id=${telegram_chatid}&text=${_enc_msg}" 2>&1)"

    result=$?
    if [ "$result" -eq 0 ] && echo "$_resp" | grep -q '"ok":true'; then
        GRN1 && echo "push1 msg sent" && bell
    elif [ "$result" -eq 0 ]; then
        _code="$(echo "$_resp" | sed -n 's/.*"error_code":\([0-9]*\).*/\1/p')"
        _desc="$(echo "$_resp" | sed -n 's/.*"description":"\([^"]*\)".*/\1/p')"
        RED1 && ko "Err:${_code:-API} -> push1 실패 (${_desc:-$_resp})" && bell
    else
        RED1 && ko "Err:$result -> push1 전송 실패 (curl 코드: $result)" && bell
    fi
    NC

    echo "$message"
}

pushc() {
    local _cmd="$*" _out _rc
    if [ -z "$_cmd" ]; then
        echo "Usage: pushc \"<command>\""
        return 1
    fi
    _out="$(eval "$_cmd" 2>&1)"
    _rc=$?
    push "[$HOSTNAME] $ $_cmd (exit:$_rc)"$'\n'"$_out"
    return $_rc
}

pushfile() {
    local _f="$1"
    if [ -z "$_f" ] || [ ! -f "$_f" ]; then
        ko "오류: 파일을 찾을 수 없습니다: ${_f:-<미지정>}"
        return 1
    fi
    push "[$HOSTNAME] file: $_f"$'\n'"$(head -c 3500 "$_f")"
}

atqq() { atq | sort | while read -r l; do
    echo $l
    j=$(echo $l | awk1)
    at -c $j | tail -n2 | head -n1
done; }

# 0060 msg           # 60분 후에 "60분 알람 msg "이라는 메시지를 텔레그램으로 전송합니다.
# 00001700 msg or 0000 1700 msg      # 오후 5시에 "17:00 알람 msg "이라는 메시지를 텔레그램으로 전송합니다.
# 000017001 msg      # 내일 오후 5시에 "17:00 알람 msg "이라는 메시지를 텔레그램으로 전송합니다.

#
# nameserver zonefile serial update
serialup() {
    local zonefile="$1"
    local today
    today=$(date +"%Y%m%d") # YYYYMMDD 형식의 오늘 날짜

    # 파일이 존재하는지 확인
    if [[ ! -f $zonefile ]]; then
        echo "오류: 파일 '$zonefile'이 존재하지 않습니다."
        return 1
    fi

    # 현재 시리얼 찾기 (SOA 레코드에 있는 숫자 10자리)
    local current_serial
    #current_serial=$(grep -Eo '[0-9]{10}' "$zonefile" |head -n1)
    current_serial=$(awk 'match($0, /[0-9]{10}/) { print substr($0, RSTART, RLENGTH); exit }' "$zonefile")

    # 현재 시리얼이 없으면 기본값 설정
    if [[ -z $current_serial ]]; then
        new_serial="${today}00"
    else
        # 기존 시리얼에서 날짜 부분 추출
        local old_date="${current_serial:0:8}"
        local old_nn="${current_serial:8:2}"

        # 오늘 날짜와 같은 경우 NN 증가, 다르면 00으로 초기화
        if [[ $old_date == "$today" ]]; then
            new_nn=$(printf "%02d" $((10#$old_nn + 1))) # 01 -> 02 등 숫자로 변환 후 증가
        else
            new_nn="00"
        fi

        new_serial="${today}${new_nn}"
    fi

    # 시리얼을 업데이트 (sshfs 에서 sed -i 안됨)
    #sed -i "s/$current_serial/$new_serial/" "$zonefile"
    cp "$zonefile" "${zonefile}~~"                                       # 원본 파일을 ~~ 백업 파일로 복사
    sed "s#$current_serial#$new_serial#" "${zonefile}~~" >"${zonefile}~" # ~~ 백업 파일을 수정하여 ~ 임시 파일로 저장
    #mv "${zonefile}~" "$zonefile" # ~ 임시 파일을 원본 파일로 덮어쓰기
    cp "${zonefile}~" "$zonefile" && rm "${zonefile}~"

    cdiff ${zonefile}~~ ${zonefile}

    echo "업데이트 완료: $zonefile (새 시리얼: $new_serial)"
}

# [정리] 도메인 형식 검증 - 한국 TLD(ne/or/re/pe/go.kr) 누락과 임의 접미사(foo.com.zzzz) 통과를 바로잡음.
#        [ssl] 센터 1단계에서 도메인 변수 검증에 재사용한다.
isdomain() { echo "$1" | grep -E '^(www\.)?([a-z0-9]+(-[a-z0-9]+)*\.)+(com|net|org|io|info|xyz|app|dev|co\.kr|or\.kr|ne\.kr|re\.kr|pe\.kr|go\.kr|kr)$' >/dev/null && return 0 || return 1; }

# [규칙] go.env [ssl] 센터 사전점검/진단용 - whois 로 등록기관·네임서버(등록정보)·만료일을 요약한다.
#        인자 없으면 세션의 $ssldomain 을 쓴다. TLD 별 표기가 달라 한/영 키워드를 모두 훑는다.
ssl_whois() {
    local d="${1:-$ssldomain}"
    [ -z "$d" ] && { echo "[WARN] 대상 도메인 없음 - 먼저 '도메인 설정' 항목을 실행하세요."; return 1; }
    if ! command -v whois >/dev/null 2>&1; then
        echo "[WARN] whois 미설치 - 'yyay whois' 로 설치 후 다시 실행하세요."
        return 1
    fi
    local w
    w="$(whois "$d" 2>/dev/null)"
    if [ -z "$w" ]; then
        echo "[WARN] whois 응답 없음: $d (오프라인 또는 미등록 도메인)"
        return 1
    fi
    echo "--- WHOIS 등록정보 요약: $d ---"
    printf '%s\n' "$w" | grep -iE '(^|[[:space:]])(Registrar|Name Server|DNS|Domain Name|Registry Expiry Date|Registrar Registration Expiration Date|Expiry Date|Expiration Date|Created Date|Creation Date|Updated Date|등록기관|등록대행자|네임서버|만료일|유효기간|등록일)[[:space:]]*:' | head -n 24
    echo "--- 실제 위임 NS (dig @8.8.8.8) ---"
    dig +short NS "$d" @8.8.8.8
    echo "[팁] whois 의 네임서버와 dig NS 가 다르면 등록사 위임이 아직 안 된 상태입니다."
}

urlencode() { od -t x1 -A n | tr " " %; }
urldecode() { echo -en "$(sed 's/+/ /g; s/%/\\x/g')"; }

# mv 동작을 최대한 모방하는 rmv (sshfs 환경용)
rmv() {
    local src src_normalized dest dest_type rsync_ret overall_ret=0 i=1

    # --- 1. 인자 개수 확인 ---
    if [ "$#" -lt 2 ]; then
        echo "rmv: missing destination file operand after '$1'" >&2 # mv 에러 메시지 스타일
        echo "Try 'rmv --help' for more information." >&2
        return 1
    fi

    # --- 2. 목적지 인자 가져오기 (eval 사용 주의) ---
    eval dest="\$$#"

    # --- 3. 목적지 타입 판별 ---
    if [ -d "$dest" ]; then
        dest_type="directory"
    elif [ -e "$dest" ]; then
        dest_type="file"
    else
        dest_type="nonexistent"
    fi

    # --- 4. 소스 개수에 따른 동작 분기 ---
    if [ $(($# - 1)) -gt 1 ]; then # 소스가 2개 이상일 때
        # 소스 여러 개일 때 목적지는 반드시 디렉토리여야 함 (mv 규칙)
        if [ "$dest_type" != "directory" ]; then
            echo "rmv: target '$dest' is not a directory" >&2
            return 1
        fi

        # 목적지가 디렉토리면 루프 돌면서 하나씩 rsync 시도
        i=1
        while [ $i -lt $# ]; do
            eval src="\$$i"
            src_normalized=${src%/} # 소스 슬래시 제거 (mv처럼)

            if [ ! -e "$src_normalized" ]; then
                echo "rmv: cannot stat '$src': No such file or directory" >&2
                overall_ret=1 # 실패 기록
                i=$((i + 1))
                continue # 다음 소스로 넘어감
            fi

            echo "Moving '$src_normalized' to '$dest/'" # 간단한 메시지
            rsync -a --progress --remove-source-files "$src_normalized" "$dest/"
            rsync_ret=$?

            if [ $rsync_ret -ne 0 ]; then
                echo "rmv: failed to move '$src_normalized' to '$dest/' (rsync error $rsync_ret)" >&2
                overall_ret=1 # 실패 기록
            fi
            i=$((i + 1))
        done

    else                        # 소스가 1개일 때
        eval src="\$$1"         # 첫 번째 인자가 소스
        src_normalized=${src%/} # 소스 슬래시 제거 (mv처럼)

        if [ ! -e "$src_normalized" ]; then
            echo "rmv: cannot stat '$src': No such file or directory" >&2
            return 1 # 소스 없으면 바로 종료 (mv 동작)
        fi

        case "$dest_type" in
        directory)
            # 목적지가 디렉토리: 디렉토리 안으로 이동 (rsync 사용)
            echo "Moving '$src_normalized' to '$dest/'"
            rsync -a --progress --remove-source-files "$src_normalized" "$dest/"
            rsync_ret=$?
            if [ $rsync_ret -ne 0 ]; then
                echo "rmv: failed to move '$src_normalized' to '$dest/' (rsync error $rsync_ret)" >&2
                overall_ret=1
            fi
            ;;
        file)
            # 목적지가 파일: 덮어쓰기 시도 (rsync 사용 - 비원자적!)
            # mv 는 보통 여기서 덮어쓸지 물어보지만(-i), rmv는 일단 덮어쓰는 것으로 구현 (-f 와 유사)
            # 주의: 원자성이 보장되지 않음! cp + rm 과 유사하게 동작할 수 있음.
            echo "Moving '$src_normalized' to '$dest' (overwriting existing file)"
            # 파일을 파일로 rsync 할 때는 목적지 경로에 슬래시(/) 붙이면 안 됨!
            rsync -a --progress --remove-source-files "$src_normalized" "$dest"
            rsync_ret=$?
            if [ $rsync_ret -ne 0 ]; then
                echo "rmv: failed to move '$src_normalized' to '$dest' (rsync error $rsync_ret)" >&2
                overall_ret=1
            fi
            ;;
        nonexistent)
            # 목적지 없음: Rename 시도 (rsync 사용 - 비원자적!)
            echo "Renaming '$src_normalized' to '$dest'"
            # 파일을 존재하지 않는 경로로 rsync (새 파일 생성)
            rsync -a --progress --remove-source-files "$src_normalized" "$dest"
            rsync_ret=$?
            if [ $rsync_ret -ne 0 ]; then
                echo "rmv: failed to rename '$src_normalized' to '$dest' (rsync error $rsync_ret)" >&2
                overall_ret=1
            fi
            ;;
        esac
    fi

    # --- 5. 최종 결과 반환 ---
    # overall_ret 가 0이면 성공, 0이 아니면 실패 (mv와 유사)
    return $overall_ret
}

alarm() {
    # 인수로 넘어올때 "$1" "$2" // $2에 read 나머지 모두
    # 인수로 넘어올때 "$1" "$2" "$3" ... // 두가지 형태 존재

    ensure_cmd atq at

    local input="$1"
    shift
    local telegram_msg="$1"
    shift
    while [ $# -gt 0 ]; do
        telegram_msg="$telegram_msg $1"
        shift
    done
    if [ ! "$input" ]; then
        : 현재 알람 테스트 내역 출력
        echo ">>> alarm set list..."
        CYN
        atqq
        NC
        ps -ef | grep "[a]larm_task" | awknf8 | cgrep "alarm_task_$input" | grep -v "awk"
    fi
    if [[ ${input:0:4} == "0000" ]]; then
        [ ! "${input:4:2}" ] && input="$input$(echo "$telegram_msg" | awk1)" && telegram_msg="$(echo "$telegram_msg" | awknf2)" # && echo "input: $input // msg: $telegram_msg"
        local time_in_hours="${input:4:2}"
        local time_in_minutes="${input:6:2}"
        local days="${input:8:2}"
        [ -z "$days" ] && days=0
        telegram_msg="${time_in_hours}:${time_in_minutes}-Alarm ${telegram_msg}"
        echo ": alarm_task_$input && curl -4 -m8 -ks -X POST \"https://api.telegram.org/bot${telegram_token}/sendMessage\" -d chat_id=${telegram_chatid} -d text=\"${telegram_msg}\"" | at "$time_in_hours":"$time_in_minutes" "$( ((days > 0)) && echo "today + $days" days)" &>/dev/null

        atq | sort | while read -r l; do
            echo $l
            j=$(echo $l | awk1)
            at -c $j | tail -n2 | head -n1
        done | stripe | cgrep alarm_task_$input
    elif [[ ${input:0:2} == "00" ]]; then
        local time_in_minutes="${input:2}"
        time_in_minutes="${time_in_minutes#0}"
        telegram_pre="${time_in_minutes}분 카운트 완료."
        [ ! "$(file "$gofile" | grep -i "utf")" ] && telegram_pre="$(echo "$telegram_pre" | iconv -f EUC-KR -t UTF-8)"
        [ ! "$(echo $LANG | grep -i "utf")" ] && telegram_msg="$(echo "$telegram_msg" | iconv -f EUC-KR -t UTF-8)"
        telegram_msg="${telegram_pre}${telegram_msg}"

        date
        current_seconds=$(date +%S)
        current_seconds="${current_seconds#0}"
        wait_seconds=$((current_seconds - 4))
        adjusted_minutes=$((time_in_minutes))
        ((wait_seconds < 0)) && wait_seconds=$((60 + wait_seconds)) && adjusted_minutes=$((time_in_minutes - 1))

        echo ": alarm_task_$input && sleep $wait_seconds && curl -4 -m8 -ks -X POST 'https://api.telegram.org/bot${telegram_token}/sendMessage' -d chat_id=${telegram_chatid} -d text='${telegram_msg}'" | at now + "$adjusted_minutes" minutes &>/dev/null

        atq | sort | while read -r l; do
            echo $l
            j=$(echo $l | awk1)
            at -c $j | tail -n2 | head -n1
        done | stripe | cgrep alarm_task_$input
    elif [[ ${input:0:1} == "0" ]]; then
        local time_in_seconds="${input:1}"
        time_in_seconds="${time_in_seconds#0}"
        telegram_pre="${time_in_seconds}초 카운트 완료."
        [ ! "$(file "$gofile" | grep -i "utf")" ] && telegram_pre="$(echo "$telegram_pre" | iconv -f EUC-KR -t UTF-8)"
        [ ! "$(echo $LANG | grep -i "utf")" ] && telegram_msg="$(echo "$telegram_msg" | iconv -f EUC-KR -t UTF-8)"
        telegram_msg="${telegram_pre}${telegram_msg}"

        date
        #echo "input: $input // msg: $telegram_msg"
        sleepdot $time_in_seconds && curl -4 -m8 -ks -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" -d chat_id=${telegram_chatid} -d text="${telegram_msg}" &>/dev/null

        atq | sort | while read -r l; do
            echo $l
            j=$(echo $l | awk1)
            at -c $j | tail -n2 | head -n1
        done | stripe | cgrep alarm_task_$input
    fi
}

# print array - debug (bash2)
printarr() {
    local arr_name=$1
    local count
    count=$(eval echo '${#'$arr_name'[@]}')

    echo "count: $count"
    local i=0
    while [ $i -lt $count ]; do
        local value
        value=$(eval echo '${'"$arr_name"'['$i']}')
        echo "${arr_name}[$i] = $value"
        i=$((i + 1))
    done
}

# history view
hh() { cat "$gotmp"/go_history.txt 2>/dev/null | grep -v "^eval " | lastseen | tail -10 | stripe; }
gohistory() {
    echo
    echo "= go_history ================================="
    eval "$(cat "$gotmp"/go_history.txt 2>/dev/null | grep -v "^eval " | lastseen | tail -n20 | pipemenulistc | noansi)"
    echo && { echo -en "\033[1;34mDone...\033[0m [Enter] " && read -r x; }
}

# loadvar
loadvar() {
    load=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    color="0"
    int_load=${load%.*}
    case 1 in $((int_load >= 3))) color="1;33;41" ;; $((int_load == 2))) color="1;31" ;; $((int_load == 1))) color="1;35" ;; esac
    echo -ne "\033[${color}m ${load} \033[0m "
}

# awk NF select awk8 -> 8열 출력 // awk2
for ((i = 1; i <= 10; i++)); do eval "awk${i}() { awk '{print \$$i}'; }"; done
# awk2c -> 2nd raw yellow colored
for ((i = 1; i <= 10; i++)); do
    eval "awk${i}c() { awk -v col=$i '{
    for (j = 1; j <= NF; j++) {
      if (j == col) {
        printf \"\\033[1;33m%s\\033[0m \", \$j;
      } else {
        printf \"%s \", \$j;
      }
    }
    printf \"\\n\";
  }' \"\$@\"; }"
done

# awk nf nf-1 ( ex. awk99 -> last raw print )
awk99() { awk '{print $NF}'; }
awk98() { awk '(NF>1){print $(NF-1)}'; }
# colored nf / nf-1
awk99c() { awk '{ for (j=1; j<NF; j++) printf "%s ", $j; if (NF) printf "\033[1;33m%s\033[0m\n", $NF; else printf "\n"; }' "$@"; }
awk98c() { awk '{ for (j=1; j<=NF; j++) { if (j == NF-1) printf "\033[1;33m%s\033[0m ", $j; else printf "%s ", $j; } printf "\n"; }' "$@"; }

# awk NR pass awknr2 -> 2행부터 끝까지 출력
for ((i = 1; i <= 10; i++)); do eval "awknr${i}() { awk 'NR >= '$i' '; }"; done
# awk NF pass awknf8 -> 8열부터 끝까지 출력
# 특정열이 없을경우 버그 나는것 수정
for ((i = 1; i <= 10; i++)); do eval "awknf${i}() { awk '{if (NF >= $i) print substr(\$0, index(\$0,\$$i))}' ; }"; done

# ssh handshake 과정중 오류로 접속이 안될때 ~/ssh/.config 에 설정후 재접속
# 정상 접속이 안될때만 함수 이용하여 접속 // 오히려 정상접속일 경우에는 output 변수관련 멈춤 발생

sshre() {
    output=$(ssh "$@" 2>&1)
    if echo "$output" | grep -q "no matching host key type found"; then
        algorithms=$(echo "$output" | sed -n 's/.*Their offer: //p' | tr -d '\r' | sed 's/ /,/g' | head -n1)
        printf "Host %s\n    HostKeyAlgorithms +%s\n    PubkeyAcceptedKeyTypes +ssh-rsa\n" "$1" "$algorithms" | tee -a "$HOME/.ssh/config" >/dev/null
        echo "HostKey config saved, reconnecting..."
        ssh "$@"
    elif echo "$output" | grep -q "no matching key exchange method found"; then
        algorithms=$(echo "$output" | sed -n 's/.*Their offer: //p' | tr -d '\r' | sed 's/ /,/g' | head -n1)
        printf "Host %s\n    KexAlgorithms +%s\n" "$1" "$algorithms" | tee -a "$HOME/.ssh/config" >/dev/null
        echo "Kex config saved, reconnecting..."
        ssh "$@"
    fi
}

# ssh auto connect
idpw() {
    id="$1"
    pw="$2"
    host="${3:-$HOSTNAME}"
    port="${4:-22}"
    { expect -c "set timeout 3;log_user 0; spawn ssh -p $port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET $id@$host; expect -re \"password:\" { sleep 0.2 ; send \"$pw\r\" } -re \"key fingerprint\" { sleep 0.2 ; send \"yes\r\" ; expect -re \"password:\" ; sleep 0.2 ; send \"$pw\r\" }; expect \"*Last login*\" { exit 0 } \"*Welcome to *\" { exit 0 } timeout { exit 1 } eof { exit 1 };"; }
    [ $? == "0" ] && echo -e "\e[1;36m>>> ID: $id PW: $pw HOST: $host Success!!! \e[0m" || echo -e "\e[1;31m>>> ID: $id PW: $pw HOST:$host FAIL !!! \e[0m"
}

userinfo() {
    dline() {
        num_characters="${1-46}"
        delimiter="${2-=}"
        i=1
        while [ "$i" -le "$num_characters" ]; do
            printf "%s" "$delimiter"
            i=$((i + 1))
        done
        printf "\n"
    }

    if [ -z "$1" ] || [ "$1" = "--help" ]; then
        echo -e "\033[1mUsage:\033[0m userinfo <username> [section]"
        echo "Sections: all (default), basic, activity, resources"
        return 1
    fi
    USERNAME="$1"
    SECTION="${2-all}"
    USERINFO=$(getent passwd "$USERNAME")
    if [ -z "$USERINFO" ]; then
        echo -e "\033[1;31m[!] 사용자 '$USERNAME' 정보를 찾을 수 없습니다.\033[0m"
        return 1
    fi

    # Replace <<< with echo | read for bash2 compatibility
    echo "$USERINFO" | (
        IFS=':' read NAME PASS USER_UID GID INFO HOME SHELL
        if [ "$SECTION" = "all" ] || [ "$SECTION" = "basic" ]; then
            ACCOUNT_STATUS=$(passwd -S "$USERNAME" 2>/dev/null | awk '{print $2}')
            case "$ACCOUNT_STATUS" in
            P) ACCOUNT_STATUS_DESC="Password set" ;;
            L) ACCOUNT_STATUS_DESC="Locked" ;;
            NP) ACCOUNT_STATUS_DESC="No password" ;;
            *) ACCOUNT_STATUS_DESC="Unknown" ;;
            esac
            LAST_CHANGED_DATE=$(passwd -S "$USERNAME" 2>/dev/null | awk '{print $3}')
            CHAGE_INFO=$(chage -l "$USERNAME" 2>/dev/null | awk -F': ' '
                /Last password change/ { printf "Last change: %s; ", $2 }
                /Password expires/ { printf "Expires: %s; ", $2 }
                /Minimum/ { printf "Min days: %s; ", $2 }
                /Maximum/ { printf "Max days: %s; ", $2 }
                /warning/ { printf "Warn days: %s", $2 }')
            echo -e "\033[1;34m기본 정보\033[0m"
            dline
            echo -e "\033[1;37m사용자명\033[0m: \033[1;36m$NAME\033[0m"
            echo -e "\033[1;37mUID\033[0m: \033[1;36m$USER_UID\033[0m"
            echo -e "\033[1;37mGID\033[0m: \033[1;36m$GID\033[0m"
            echo -e "\033[1;37m전체 이름\033[0m: \033[1;36m$INFO\033[0m"
            echo -e "\033[1;37m홈 디렉토리\033[0m: \033[1;36m$HOME\033[0m"
            echo -e "\033[1;37m기본 쉘\033[0m: \033[1;36m$SHELL\033[0m"
            echo -e "\033[1;37m계정 상태\033[0m: \033[1;36m$ACCOUNT_STATUS_DESC\033[0m"
            echo -e "\033[1;37m최근 변경일\033[0m: \033[1;36m$LAST_CHANGED_DATE\033[0m"
            echo -e "\033[1;37m비밀번호 정책\033[0m: \033[1;36m$CHAGE_INFO\033[0m"
        fi
        if [ "$SECTION" = "all" ] || [ "$SECTION" = "activity" ]; then
            WHO_INFO=$(who | grep "^$USERNAME" || echo "현재 로그인 정보 없음")
            LAST_LOG=$(last -w -n 5 "$USERNAME" 2>/dev/null | grep . || echo "로그인 이력 없음")
            PROCESS_INFO=$(ps -u "$USERNAME" -o pid,tty,stat,time,cmd 2>/dev/null | grep -v "PID" || echo "실행 중인 프로세스 없음")
            if [ -r /var/log/maillog ]; then
                MAIL_LOG=$(grep "$USERNAME" /var/log/maillog 2>/dev/null | tail -n 5)
                [ -z "$MAIL_LOG" ] && MAIL_LOG="메일 관련 로그 기록 없음"
            else
                if [ -r /var/log/mail.log ]; then
                    MAIL_LOG=$(grep "$USERNAME" /var/log/mail.log 2>/dev/null | tail -n 5)
                    [ -z "$MAIL_LOG" ] && MAIL_LOG="메일 관련 로그 기록 없음"
                else
                    MAIL_LOG="메일 로그 파일 없음 또는 접근 권한 없음"
                fi
            fi
            dline
            echo -e "\033[1;34m활동 정보\033[0m"
            dline
            echo -e "\033[1;37m현재 로그인 세션\033[0m: \033[1;36m$WHO_INFO\033[0m"
            echo -e "\033[1;37m최근 로그인 로그 (최대 5회)\033[0m:"
            echo -e "\033[1;36m$LAST_LOG\033[0m"
            echo -e "\033[1;37m사용자 프로세스\033[0m:"
            echo -e "\033[1;36m$PROCESS_INFO\033[0m"
            echo -e "\033[1;37m메일 관련 로그 (최대 5줄)\033[0m:"
            echo -e "\033[1;36m$MAIL_LOG\033[0m"
        fi
        if [ "$SECTION" = "all" ] || [ "$SECTION" = "resources" ]; then
            ID_INFO=$(id "$USERNAME")
            GROUPS_INFO=$(groups "$USERNAME" | cut -d: -f2 | sed 's/^[ 	]*//')
            HOME_INFO=$(ls -ld "$HOME" | awk '{print $1, $3, $4, $6, $7, $8, $9}')
            HOME_USAGE=$(du -sh "$HOME" 2>/dev/null | cut -f1 || echo "사용량 확인 불가")
            SHADOW_INFO=$(sudo grep "^$USERNAME:" /etc/shadow 2>/dev/null | cut -d: -f1-8 || echo "Shadow 정보 접근 불가 (sudo 권한 필요)")
            dline
            echo -e "\033[1;34m권한 및 리소스\033[0m"
            dline
            echo -e "\033[1;37mID 및 그룹 정보\033[0m: \033[1;36m$ID_INFO\033[0m"
            echo -e "\033[1;37m소속 그룹\033[0m: \033[1;36m$GROUPS_INFO\033[0m"
            echo -e "\033[1;37m홈 디렉토리 상태\033[0m: \033[1;36m$HOME_INFO\033[0m"
            echo -e "\033[1;37m홈 디렉토리 사용량\033[0m: \033[1;36m$HOME_USAGE\033[0m"
            echo -e "\033[1;37m비밀번호 정보\033[0m: \033[1;36m$SHADOW_INFO\033[0m"
        fi
        if [ "$SECTION" != "all" ] && ! echo " basic activity resources " | grep -q " $SECTION "; then
            echo -e "\033[1;31m[!] 잘못된 섹션: '$SECTION'\033[0m"
            echo "사용 가능한 섹션: all, basic, activity, resources"
            return 1
        fi
    )
}

idinfo() { userinfo $@; }
qssh() {
    local default_user="root"
    local arp_scan_timeout=3

    if [[ $# -eq 0 || $# -gt 2 ]]; then
        echo "Usage: qssh <vmid> [ssh_user]"
        echo "  Example 1 (default user '$default_user'): qssh 101"
        echo "  Example 2 (specify user): qssh 101 myuser"
        return 1
    fi

    local vmid="$1"
    local user="${2:-$default_user}"
    [[ -z $user ]] && echo "Error: SSH username cannot be empty." && return 1

    echo "=============================================="
    echo "--- Processing qssh for VM $vmid (User: $user) ---"
    echo "[1] Locating VM in cluster..."

    local node
    node=$(pvesh get /cluster/resources --output-format=json |
        jq -r ".[] | select(.type==\"qemu\" and .vmid==$vmid) | .node")

    if [[ -z $node ]]; then
        echo "Error: VM $vmid not found in cluster."
        return 1
    fi

    echo "  > Found VM $vmid on node: $node"
    echo "[2] Fetching MAC address from config..."

    local config_output
    config_output=$(ssh "$node" pvesh get /nodes/$node/qemu/$vmid/config --noborder 2>/dev/null)
    local mac
    mac=$(echo "$config_output" | sed -n 's/.*=\([0-9A-Fa-f:]\{17\}\).*/\1/p' | head -n1)
    local bridge
    bridge=$(echo "$config_output" | sed -n 's/.*bridge=\([^, ]\+\).*/\1/p' | head -n1)

    if [[ -z $mac || -z $bridge ]]; then
        echo "Error: Failed to extract MAC or bridge from config."
        return 1
    fi

    local lower_mac
    lower_mac=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
    echo "  > MAC: $mac (as $lower_mac), Bridge: $bridge"

    echo "[3a] Checking ARP cache for $lower_mac..."
    local ip
    ip=$(arp -n | grep -i "$lower_mac" | awk '{print $1}' | head -n1)

    if [[ -z $ip ]]; then
        echo "  > Not found in ARP cache. Trying arp-scan on $bridge..."
        if ! command -v arp-scan &>/dev/null; then
            echo "Error: arp-scan not found. Please install it (e.g. apt install arp-scan)."
            return 1
        fi
        local arp_out
        arp_out=$(arp-scan --interface="$bridge" --localnet --numeric --quiet --timeout=$((arp_scan_timeout * 1000)) 2>/dev/null | grep -i "$lower_mac")
        ip=$(echo "$arp_out" | awk '{print $1}' | head -n1)

        if [[ -z $ip ]]; then
            echo "Error: MAC $lower_mac not found on $bridge via arp-scan."
            return 1
        fi
        echo "  > Found IP via arp-scan: $ip"
    else
        echo "  > Found IP in ARP cache: $ip"
    fi

    echo "[4] SSH connecting to $user@$ip ..."
    ssh "$user@$ip"
    local code=$?
    echo "--- SSH session ended with code $code. ---"
    echo "=============================================="
    return $code
}

enter() {
    local vmid="$1"
    local default_user="root"

    if [ -z "$vmid" ] || ! expr "$vmid" : '^[0-9]\+$' >/dev/null; then
        echo "Usage: enter <vmid>"
        return 1
    fi

    echo "--- Checking type for VMID $vmid..."

    local vmtype node
    node=$(pvesh get /cluster/resources --output-format=json |
        jq -r ".[] | select(.vmid == $vmid) | .node")
    vmtype=$(pvesh get /cluster/resources --output-format=json |
        jq -r ".[] | select(.vmid == $vmid) | .type")

    if [[ -z $node || -z $vmtype ]]; then
        echo "❌ VMID $vmid not found in cluster."
        return 1
    fi

    echo "  > VM $vmid is a $vmtype on node $node"

    if [[ $vmtype == "lxc" ]]; then
        echo ">>> Entering LXC container via pct..."
        pct enter "$vmid"
    elif [[ $vmtype == "qemu" ]]; then
        echo ">>> Connecting via qssh..."
        qssh "$vmid" "$default_user"
    else
        echo "⚠️ Unsupported type: $vmtype"
        return 1
    fi
}

# assh host [id] pw [port]  (pw 에 특수문자가 있는 경우 'pw' 형태로 이용가능)
assh() {
    local host id pw port
    # Bash 2 호환: local arr=(...) 금지 -> 선언/대입 분리
    local args
    args=("$@")
    local arg_count=${#args[@]}
    local client_charmap server_charmap server_charmap_output detect_ssh_cmd
    local use_luit="false"
    local encoding_info=""
    local detect_exit_code

    # --- Argument Parsing ---
    id="root"
    port=22
    local ignored_encoding=""

    case $arg_count in
    1) host="${args[0]}" ;;
    2)
        host="${args[0]}"
        pw="${args[1]}"
        ;;
    3)
        host="${args[0]}"
        if [[ ${args[2]} == "ut" || ${args[2]} == "kr" ]]; then
            pw="${args[1]}"
            ignored_encoding="${args[2]}"
        else
            id="${args[1]}"
            pw="${args[2]}"
        fi
        ;;
    4)
        host="${args[0]}"
        id="${args[1]}"
        pw="${args[2]}"
        if echo "${args[3]}" | grep -qE '^[0-9]+$'; then
            port="${args[3]}"
        else
            ignored_encoding="${args[3]}"
        fi
        ;;
    5)
        host="${args[0]}"
        id="${args[1]}"
        pw="${args[2]}"
        port="${args[3]}"
        ignored_encoding="${args[4]}"
        ;;
    *)
        echo "Usage: assh <host> [id] [password] [port]"
        echo "       assh <host> [password]"
        echo "Note: Encoding parameter (ut/kr) is ignored; auto-detection is used."
        return 1
        ;;
    esac

    # --- 1. Get Client Locale ---
    client_charmap=$(locale charmap 2>/dev/null)
    if [[ -z $client_charmap ]]; then
        echo "Warning: Could not determine client character map. Assuming UTF-8." >&2
        client_charmap="UTF-8"
    fi
    echo "Client locale charmap: $client_charmap"

    # --- 2. Detect Server Locale ---
    local remote_cmd_path="/usr/bin/locale"
    local remote_cmd_arg="charmap"
    detect_ssh_cmd="ssh -p $port -o PreferredAuthentications=password -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR $id@$host $remote_cmd_path $remote_cmd_arg"

    echo "Attempting to detect server locale for $id@$host:$port..."

    # --- Expect Script for Detection ---
    server_charmap_output=$(expect -c "
        set err_pattern \"\\\\(^bash:.*\\\\(no such file\\\\|command not found\\\\)\\\\)\\\\|\\\\(^/bin/sh:.*\\\\(not found\\\\)\\\\)\"
        log_user 0 ;
        set server_buffer \"\";
        set stty_original [stty -g];
        stty -echo ;
        set timeout 10
        spawn $detect_ssh_cmd
        expect {
            \"password:\" { sleep 0.2; send \"$pw\\r\"; exp_continue; }
            \"yes/no)?\" { sleep 0.2; send \"yes\\r\"; expect \"password:\" { sleep 0.2; send \"$pw\\r\"; exp_continue } }
            eof {
                set server_buffer \$expect_out(buffer)
                catch wait result;
                set exit_status [lindex \$result 3];
                if { \$exit_status == 0 } {
                    puts \$server_buffer;
                } else {
                    puts stderr \"SSH command failed during locale detection (Exit: \$exit_status). Output:\";
                    puts stderr \$server_buffer;
                }
                exit \$exit_status;
            }
            timeout { puts stderr \"Timeout during server locale detection.\"; exit 124; }
            \"Permission denied\" { set server_buffer \$expect_out(buffer); puts stderr \"Authentication failed during locale detection. Output:\"; puts stderr \$server_buffer; exit 1; }
            \"Connection refused\" { puts stderr \"Connection refused during locale detection.\"; exit 1; }
            \"No route to host\" { puts stderr \"No route to host during locale detection.\"; exit 1; }
            -re \$err_pattern {
                set server_buffer \$expect_out(buffer);
                puts stderr \"Error reported by remote shell during locale detection:\";
                puts stderr \$server_buffer;
                exit 127;
            }
            -re {\[#$%>\]\\s*$} {
                 set server_buffer \$expect_out(buffer);
                 puts stderr \"Unexpected prompt during non-interactive locale detection. Output:\";
                 puts stderr \$server_buffer;
                 exit 1;
            }
        }
        stty \$stty_original ;
    ")
    detect_exit_code=$?
    # --- End of Expect Script ---

    # --- Process Captured Output ---
    if [[ $detect_exit_code -eq 0 ]] && [[ -n $server_charmap_output ]]; then
        server_charmap=$(echo "$server_charmap_output" | awk 'NF{last_non_empty=$0} END{print last_non_empty}' | tr -d '[:space:]')
        # Added ANSI_X3.4-1968 as a common non-UTF8 case
        if [[ -n $server_charmap ]] && [[ $server_charmap != *"command not found"* ]] && [[ $server_charmap != *"No such file"* ]]; then
            echo "Server locale charmap detected: $server_charmap"
            # --- 3. Conditional Logic ---
            if [[ $client_charmap == "UTF-8" ]] && [[ $server_charmap != "UTF-8" ]]; then
                # Use luit if client is UTF-8 and server is not. Assume euc-kr for luit.
                if command -v luit >/dev/null 2>&1; then
                    echo "Client is UTF-8, Server is $server_charmap. Using 'luit -encoding euc-kr'."
                    use_luit="true"
                    encoding_info="(auto: luit euc-kr)"
                else
                    echo "Warning: Client is UTF-8, Server is $server_charmap, but 'luit' command not found. Connecting directly." >&2
                    encoding_info="(auto: direct, luit missing)"
                fi
            else
                echo "Client ($client_charmap) and Server ($server_charmap) encodings compatible or non-UTF8 client. Using direct connection."
                encoding_info="(auto: direct)"
            fi
        else
            echo "Warning: Locale detection command succeeded but output seems invalid:" >&2
            echo "$server_charmap_output" >&2
            echo "Assuming compatible encoding (direct connection)." >&2
            encoding_info="(auto: parse failed, direct)"
            detect_exit_code=1
        fi
    else
        echo "Warning: Failed to detect server locale (Detection script exit code: $detect_exit_code). Assuming compatible encoding (direct connection)." >&2
        encoding_info="(auto: detection failed, direct)"
        if [[ $detect_exit_code -eq 0 ]]; then detect_exit_code=1; fi
    fi

    # --- 4. Construct Final SSH Command ---
    local final_ssh_base_cmd="ssh -tt -p $port -o PreferredAuthentications=password -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET $id@$host"
    local final_ssh_cmd

    if [[ $use_luit == "true" ]]; then
        if command -v luit >/dev/null 2>&1; then
            final_ssh_cmd="luit -encoding euc-kr $final_ssh_base_cmd"
        else
            echo "Error: luit selected but command not found. Cannot proceed." >&2
            return 1
        fi
    else
        final_ssh_cmd="$final_ssh_base_cmd"
    fi

    # --- 5. Execute Main Connection (Comment Removed) ---
    echo "Connecting: host:$host id:$id port:$port $encoding_info"
    expect -c "
        set stty_original [stty -g];
        stty raw -echo;
        set timeout 5 ;
        spawn $final_ssh_cmd
        expect {
            # Use standard decimal for sleep
            \"password:\" { sleep 0.2; send \"$pw\\r\"; }
            \"yes/no)?\" { sleep 0.2; send \"yes\\r\"; expect \"password:\" { sleep 0.2; send \"$pw\\r\" } }
            timeout { puts stderr \"\nTimeout waiting for password prompt on final connection.\"; stty \$stty_original; exit 1; }
            \"Permission denied\" { puts stderr \"\nAuthentication failed on final connection.\"; stty \$stty_original; exit 1; }
            \"Connection refused\" { puts stderr \"\nConnection refused on final connection.\"; stty \$stty_original; exit 1; }
        }
        # *** Problematic comment removed from here ***
        interact {
            eof {
                puts \"\nConnection closed.\"
                stty \$stty_original
            }
            # Map Ctrl+C to send Ctrl+C to remote
            \\003 { send \\003 }
        }
    "
    # Fallback restoration by bash
    stty sane
}

# 인수 없을때 read -p
get_input() { [ -z "$1" ] && read -p "$2: " input && echo "$input" || echo "$1"; }

# ncp zstd or tar 압축 전송
ncp() {
    if [ $# -eq 0 ]; then
        echo "ncp: 원격 호스트의 파일/디렉토리를 로컬로 복사합니다 (tar + zstd/gzip 사용)."
        echo "사용법 (인수 제공 시):"
        echo "  ncp <원격 호스트> <원격 경로> <로컬 디렉토리> [SSH 포트]"
        echo "-------------------------------------"
    fi
    local h p r l i dir cmd
    h=$(get_input "$1" "원격 호스트 (예: abc.com)")
    p=$([[ -n $4 ]] && echo "-p $4" || echo "")
    r=$(get_input "$2" "원격 경로")
    l=$(get_input "$3" "로컬 디렉토리")
    i=$(basename "$r")
    dir=$(dirname "$r")
    cmd="(ssh $p $h 'command -v zstd &>/dev/null ' && command -v zstd &>/dev/null ) && ssh $p $h 'cd \"${dir}\" && tar cf - \"${i}\" | zstd ' | { pv ||cat; }| zstd -d | tar xf - -C \"${l}\" || ssh $p $h 'cd \"${dir}\" && tar czf - \"${i}\"' | { pv ||cat; } | tar xzf - -C \"${l}\""
    echo "$cmd"
    eval "$cmd"
    bell
}

ncpr() {
    if [ $# -eq 0 ]; then
        echo "ncpr: 로컬 파일/디렉토리를 원격 호스트로 복사합니다 (tar + zstd/gzip 사용)."
        echo "사용법 (인수 제공 시):"
        echo "  ncpr <로컬 경로> <원격 호스트> <원격 대상 디렉토리> [SSH 포트]"
        echo "-------------------------------------"
    fi
    local l h r p i dir cmd
    l=$(get_input "$1" "로컬 경로")
    h=$(get_input "$2" "원격 호스트 (예: abc.com)")
    r=$(get_input "$3" "원격 경로")
    p=$([[ -n $4 ]] && echo "-p $4" || echo "")
    i=$(basename "$l")
    dir=$(dirname "$r")
    cmd="(ssh $p $h 'command -v zstd &>/dev/null ' && command -v zstd &>/dev/null ) && tar cf - \"${l}\" | zstd | { pv ||cat; } | ssh $p $h 'cd \"${dir}\" && zstd -d | tar xf - -C \"${dir}\"' || tar czf - \"${l}\" | { pv ||cat; } | ssh $p $h 'cd \"${dir}\" && tar xzf - -C \"${dir}\"'"
    echo "$cmd"
    eval "$cmd"
}

# ncp 로 파일을 카피할때 압축파일 형태로 로컬에 저장
ncpzip() {
    if [ $# -eq 0 ]; then
        echo "ncpzip: 원격 파일/디렉토리를 로컬 파일로 압축하여 저장합니다 (tar + zstd/gzip 사용)."
        echo "사용법: ncpzip <원격 호스트> <원격 경로> <로컬 저장 디렉토리> [SSH 포트]"
        echo "-------------------------------------"
    fi
    local h p r l i dir
    h=$(get_input "$1" "원격 호스트 (예: abc.com)")
    p=$([[ -n $4 ]] && echo "-p $4" || echo "")
    r=$(get_input "$2" "원격 경로")
    l=$(get_input "$3" "로컬 디렉토리")
    i=$(basename "$r")
    dir=$(dirname "$r")
    # pv 는 stderr 로 상태바를 보여주므로 2>/dev/null 하면 보이지 않음
    ssh $p $h "command -v zstd &>/dev/null " && command -v zstd &>/dev/null && { ssh $p $h "cd '$dir' && tar cf - '$i' | zstd " | (pv || cat) >"${l}/${h}.${i}.tar.zst" && ls -alh "${l}/${h}.${i}.tar.zst"; } || {
        ssh $p $h "cd '$dir' && tar czf - '$i'" | (pv || cat) >"${l}/${h}.${i}.tgz"
        ls -alh "${l}/${h}.${i}.tgz"
    }
}

# ncpzip 이후 업데이트된 파일이 있을때 업데이트
ncpzipupdate() {
    if [ $# -eq 0 ]; then
        echo "ncpzipupdate: 원격지의 변경된 파일만 로컬 업데이트 파일로 압축 저장합니다 (tar + zstd/gzip 사용)."
        echo "사용법: ncpzipupdate <원격 호스트> <원격 경로> <로컬 저장 디렉토리> [SSH 포트]"
        echo "-------------------------------------"
    fi
    local h r l p i dir b uf ts
    h=$(get_input "$1")
    r=$(get_input "$2")
    l=$(get_input "$3")
    p=$([[ -n $4 ]] && echo "-p $4" || echo "")
    i=$(basename "$r")
    b="${l}/${h}.${i}"
    ts=$(date +%Y%m%d.%H%M%S)
    if [ -f "${b}.tar.zst" ]; then last_modified=$(date -r "${b}.tar.zst" +%s); elif [ -f "${b}.tgz" ]; then last_modified=$(date -r "${b}.tgz" +%s); else
        echo "No backup files found for $i."
        return
    fi
    uf=$(ssh $p $h "find $r -type f -newermt @${last_modified}")
    if [ "$uf" ]; then
        echo "$i updating..."
        if [ -f "${b}.tar.zst" ]; then
            echo "$uf" >"${b}.tar.zst.update.${ts}.txt"
            ssh $p $h "tar -cf - -T /dev/stdin" <"${b}.tar.zst.update.${ts}.txt" | zstd | (pv || cat) >"${b}.tar.zst.update.${ts}.tar.zst"
        elif [ -f "${b}.tgz" ]; then
            echo "$uf" >"${b}.tgz.update.${ts}.txt"
            ssh $p $h "tar -czf - -T /dev/stdin" <"${b}.tgz.update.${ts}.txt" | (pv || cat) >"${b}.tgz.update.${ts}.tgz"
        fi
    else echo "$i skipped..."; fi
}

# rotate backup
# 업데이트가 빈번한 파일의 경우 // 모든 백업파일이 오늘 날짜인 경우 // 이전날짜의 백업파일 별도 보관
# file.1.bak 형태로 백업 조정 (원본설정으로 취급되는것 방지)
rbackup() {
    # [규칙] 전역 변수 오염 금지: base/d/cmd/i/t 를 local 로 가둔다
    #  (local 없으면 전역 $base(=go.sh 디렉터리)가 파일명으로 덮여 이후 'cd $base' 가 깨진다)
    local t d base i cdate d8 d9
    t=$(date +%Y%m%d)
    while [ $# -gt 0 ]; do
        d="${1%/}"
        base="$d"
        if [ -f "$d" ] && { [ ! -f "${base}.1.bak" ] || ! diff -q "$d" "${base}.1.bak" >/dev/null 2>&1; }; then
            d9=$(date -r "${base}.9.bak" +%Y%m%d 2>/dev/null)
            d8=$(date -r "${base}.8.bak" +%Y%m%d 2>/dev/null)
            if [ -f "${base}.9.bak" ] && [ "$t" = "$d8" ] && [ "$t" != "$d9" ]; then
                cdate=$(date -r "${base}.9.bak" +%Y%m%d)
                mv -f "${base}.9.bak" "${base}.${cdate}.bak"
            fi
            for i in 8 7 6 5 4 3 2 1; do
                [ -f "${base}.${i}.bak" ] && mv -f "${base}.${i}.bak" "${base}.$((i + 1)).bak" 2>/dev/null
            done
            cp -p "$d" "${base}.1.bak"
        fi
        shift
    done
}

#
#rbackup() {
#    t=$(date +%Y%m%d)
#    while [ $# -gt 0 ]; do
#        d="${1%/}"
#        base="${d}"
#        if [ -f "$d" ] && [[ "$(diff $d ${base}.1.bak 2>/dev/null)" || ! -f ${base}.1.bak ]]; then
#            d3=$(date -r ${base}.3.bak +%Y%m%d 2>/dev/null)
#            d4=$(date -r ${base}.4.bak +%Y%m%d 2>/dev/null)
#            if [ -f "${base}.4.bak" ] && [[ $t == "$d3" && $t != "$d4" ]]; then
#                cdate=$(date -r ${base}.4.bak +%Y%m%d)
#                mv ${base}.4.bak ${base}.${cdate}.bak
#            fi
#            for i in 3 2 1 ""; do
#                cmd=${i:+mv}
#                cmd=${cmd:-cp}
#                $cmd ${base}.${i}.bak ${base}.$((${i:-0} + 1)).bak 2>/dev/null
#            done
#            cp $d ${base}.1.bak
#        fi
#        shift
#    done
#}

# 함수 이름: insert
# 사용법: echo "삽입할 텍스트" | insert <대상_파일> <찾을_문자열>
# 설명:
#   표준 입력 텍스트를 <대상_파일> 내 <찾을_문자열> 첫 번째 줄 다음에 삽입합니다.
#   수정 전 파일을 원본과 같은 디렉토리에 <원본파일이름>_YYYYMMDD_HHMMSS.bak 형식으로 백업합니다.
#   sed 명령 실패 시 백업 파일로 복구합니다. 수정 후 차이를 diff로 보여줍니다.
#   임시 파일 대신 /dev/stdin을 사용하여 안정성을 확보합니다.

insert() {
    local filename="$1" search_string="$2" line_num backup_filename timestamp

    # 1. 기본 검증
    if [ -z "$filename" ] || [ -z "$search_string" ] ||
        [ ! -f "$filename" ] || [ ! -r "$filename" ] || [ ! -w "$filename" ] || [ -t 0 ]; then
        echo 'Usage: echo "text" | insert <file> <string>' >&2
        echo "Error: Check arguments, file permissions ('$filename'), and ensure input is piped." >&2
        return 1
    fi

    # 2. 줄 번호 찾기

    # 서치내용에 특수기호 무효화
    #line_num=$(awk -v p="$search_string" '$0 ~ p { print NR; exit } END { if (!NR) exit 1 }' "$filename") ||
    line_num=$(awk -v p="$search_string" 'index($0, p) > 0 { print NR; found=1; exit } END { if (!found) exit 1 }' "$filename") ||
        {
            echo "Error: String '$search_string' not found in '$filename'." >&2
            return 1
        }

    # 3. 백업 (Vim 스타일 이름, 같은 디렉토리)
    timestamp=$(date +%Y%m%d_%H%M%S)               # YYYYMMDD_HHMMSS 형식
    backup_filename="${filename}_${timestamp}.bak" # 원본이름_타임스탬프.bak 형식

    echo "Info: Backing up '$filename' to '$backup_filename'..."
    cp -p "$filename" "$backup_filename" ||
        {
            echo "Error: Failed to backup to '$backup_filename'." >&2
            return 1
        }
    echo "Info: Backup complete."

    # 4. 삽입 (sed 'r /dev/stdin' 사용) 및 실패 시 복구
    echo "Info: Attempting to insert text from stdin after line $line_num in '$filename'..."
    if ! sed -i "${line_num}r /dev/stdin" "$filename"; then
        echo "Error: Failed to insert text using sed 'r /dev/stdin' (exit code $?)." >&2
        echo "Info: Attempting to restore from backup '$backup_filename'..."
        if cp -p "$backup_filename" "$filename"; then
            echo "Info: Successfully restored '$filename' from backup." >&2
        else
            echo "CRITICAL ERROR: Failed to restore '$filename' from backup '$backup_filename'. Manual intervention required!" >&2
        fi
        return 1 # 삽입 실패 (복구 시도 후)
    fi

    echo "Info: Text inserted successfully."

    # 5. 변경 사항 비교 (Diff)
    echo "--- Changes Applied (diff -u backup current) ---"
    cdiff "$backup_filename" "$filename"
    echo "-------------------------------------------------"

    # 6. 완료
    echo "Success: '$filename' modified. Backup saved as '$backup_filename'."
    return 0
}

change() {
    local filepath="$1" search="$2" replace="$3" line="$4"
    local backup_suffix timestamp backup_filename exit_code
    if [ $# -lt 3 ]; then
        echo "Usage: change <filepath> <find_string> <replace_string> [line|find <context>]" 1>&2
        return 1
    fi

    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_suffix="_${timestamp}.bak"
    backup_filename="${filepath}${backup_suffix}"

    cp -a "$filepath" "$backup_filename" || return 2

    if [ "$line" ] && [ "$line" = "line" ]; then
        perl "-i" -p -e "s{.*}{$replace} if m#^$(perl -e 'print quotemeta shift' "$search")#" "$filepath"

    elif [ "$line" = "find" ] && [ "$5" ]; then
        # [섹션] 안에서 특정 문자열을 한 번만 치환 (sed 버전)
        local esc_search esc_replace esc_context sed_script
        esc_search=$(printf '%s' "$search" | sed 's:[\\/&]:\\&:g')
        esc_replace=$(printf '%s' "$replace" | sed 's:[\\/&]:\\&:g')
        esc_context=$(printf '%s' "$5" | sed 's:[\\/&]:\\&:g')

        sed_script="/^\[$esc_context\]/,/^\[/{
            /$esc_search/ {
                s/$esc_search/$esc_replace/
                t end
            }
        }
        :end"

        sed "$sed_script" "$backup_filename" >"$filepath"

    else
        perl "-i" -p -e "s|$(perl -e 'print quotemeta shift' "$search")|$replace|g" "$filepath"
    fi

    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "Change applied. Backup: $backup_filename"
        if [ -f "$backup_filename" ]; then
            echo "--- Diff (backup vs current) ---"
            cdiff "$backup_filename" "$filepath"
            echo "------------------------------"
        else
            echo "Warning: Backup file '$backup_filename' not found for diff." 1>&2
        fi
        return 0
    else
        echo "Error during change operation (code: $exit_code). Check backup: $backup_filename" 1>&2
        return $exit_code
    fi
}

# 함수 이름: change
# 사용법: change <파일경로> <찾을_문자열> <바꿀_문자열> <line:검색라인교체시>
# 설명:
#   핵심 기능만 수행: Perl -i로 백업 및 치환, diff로 비교.
#   구분자 '|||' 사용. 문자열 내 특수문자 처리는 최소화됨 (백슬래시만 처리).

_change() {
    local filepath="$1" search="$2" replace="$3" line="$4"
    local backup_suffix timestamp backup_filename exit_code

    # 1. 인자 개수 확인 (최소한)
    if [ $# -lt 3 ]; then
        echo "Usage: change <filepath> <find_string> <replace_string>" >&2
        return 1
    fi

    # 2. 백업 접미사 생성
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_suffix="_${timestamp}.bak"
    backup_filename="${filepath}${backup_suffix}" # 예상 백업 파일명

    # 3. Perl 실행 (이스케이프 없음! 변수 직접 삽입)
    #    -e 다음 코드를 큰따옴표(")로 감싸 쉘 변수($search, $replace) 확장 허용.
    #    - 변수 내용이 Perl 구문을 깨뜨리지 않는다고 가정 (매우 위험).

    # $4 에 line 값이 들어오면, 검색되는 줄을 삭제하고 대체
    # perl "-i${backup_suffix}" -p -e "s|$(perl -e 'print quotemeta shift' "$search")|$replace|g" "$filepath"
    if [ "$line" ] && [ "$line" == "line" ]; then
        # 첫글자부터 같아야 search
        perl "-i${backup_suffix}" -p -e "s{.*}{$replace} if m#^$(perl -e 'print quotemeta shift' "$search")#" "$filepath"
    else
        # 위치 상관없이 search -> 주석으로 인해 동일한 검색이 많을 경우 중복변경
        perl "-i${backup_suffix}" -p -e "s|$(perl -e 'print quotemeta shift' "$search")|$replace|g" "$filepath"
        # perl "-i${backup_suffix}" -p -e "s{.*}{$replace} if m#$(perl -e 'print quotemeta shift' "$search")#" "$filepath"
    fi

    exit_code=$?

    # 4. 결과 처리 및 Diff 실행
    if [ $exit_code -eq 0 ]; then
        echo "Change applied (no escape). Backup: $backup_filename"
        # Diff 실행 (백업 파일 존재 확인 후)
        if [ -f "$backup_filename" ]; then
            echo "--- Diff (backup vs current) ---"
            cdiff "$backup_filename" "$filepath"
            echo "------------------------------"
        else
            echo "Warning: Backup file '$backup_filename' not found for diff." >&2
        fi
        return 0
    else
        echo "Error during change operation (no escape - code: $exit_code). Check backup: $backup_filename" >&2
        # 실패 시 원본 파일은 백업 파일에 보존될 수 있음 (perl -i 동작)
        return $exit_code
    fi
}

change1() {
    sed -i "0,/${2}/s/${2}/${3}/" "$1"
}

hash_add() {
    local fpath="$1" search="$2" num_arg="$3"
    local up=0 down=0 num=0
    local ts bk_fname ret DIFF_CMD="cdiff" # cdiff 유지

    # Check argument count
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
        echo "Usage: hash_add <filepath> <search> [range]" 1>&2
        echo "  range=0 또는 생략      → 현재줄만" 1>&2
        echo "  range=+N 또는 N        → 현재줄 + 아래 N줄 (예: +2 또는 2)" 1>&2
        echo "  range=-N               → 현재줄 + 위 N줄 (예: -2)" 1>&2
        echo "  range=+-N              → 현재줄 + 위 N줄 + 아래 N줄 (예: +-2)" 1>&2 # Changed from *N
        return 1
    fi

    # Check if file exists
    [ ! -f "$fpath" ] && {
        echo "Error: File not found: $fpath" 1>&2
        return 1
    }

    # Parse range argument (순서 중요: +- 가 + 보다 먼저 와야 함)
    case "$num_arg" in
    '' | 0)
        up=0
        down=0
        ;;
    +-*) # Matches +-N (먼저 검사)
        num="${num_arg#+-}"
        if ! expr "$num" : '^[0-9]\+$' >/dev/null; then
            echo "Invalid range format: $num_arg (must be +- followed by a number)" 1>&2
            return 1
        fi
        up="$num"
        down="$num"
        ;;
    +*) # Matches +N
        up=0
        num="${num_arg#+}"
        if ! expr "$num" : '^[0-9]\+$' >/dev/null; then
            echo "Invalid range format: $num_arg (must be + followed by a number)" 1>&2
            return 1
        fi
        down="$num"
        ;;
    -*) # Matches -N
        down=0
        num="${num_arg#-}"
        if ! expr "$num" : '^[0-9]\+$' >/dev/null; then
            echo "Invalid range format: $num_arg (must be - followed by a number)" 1>&2
            return 1
        fi
        up="$num"
        ;;
    *[!0-9+-]*) # Catch completely invalid characters early
        echo "Invalid range format: $num_arg. Use N, +N, -N, or +-N." 1>&2
        return 1
        ;;
    *) # Matches N (interpreted as +N) or potentially invalid combinations like --, ++ if not caught above
        if expr "$num_arg" : '^[0-9]\+$' >/dev/null; then
            up=0
            down="$num_arg"
        else
            echo "Invalid range format: $num_arg. Use N, +N, -N, or +-N." 1>&2
            return 1
        fi
        ;;
    esac

    # Create backup
    ts=$(date +%Y%m%d_%H%M%S)
    bk_fname="${fpath}_${ts}.bak"
    if ! cp -a "$fpath" "$bk_fname"; then
        echo "Error: Failed to create backup $bk_fname" 1>&2
        return 1
    fi

    # Process the file with awk
    awk -v pat="$search" -v up="$up" -v down="$down" '
    {
        lines[NR] = $0
        if ($0 ~ pat) {
            match_lines[++mc] = NR # Store matched line numbers
        }
    }
    END {
        # Mark lines to be commented
        for (j = 1; j <= mc; j++) {
            m = match_lines[j] # Current matched line number
            start_line = (m - up > 0) ? m - up : 1
            end_line = (m + down < NR) ? m + down : NR

            # Ensure end_line does not exceed total lines (NR)
            if (end_line > NR) end_line = NR;

            for (i = start_line; i <= end_line; i++) {
                 # Check validity again just in case and mark
                 if (i > 0 && i <= NR) {
                    mark[i] = 1
                 }
            }
        }

        # Print lines, commenting marked ones
        for (i = 1; i <= NR; i++) {
            if (mark[i] && lines[i] !~ /^[[:space:]]*#/) {
                print "# " lines[i]
            } else {
                print lines[i]
            }
        }
    }' "$bk_fname" >"$fpath"
    ret=$?

    # Report results
    if [ $ret -eq 0 ]; then
        echo "Hash Add done. Backup: $bk_fname"
        if ! cmp -s "$bk_fname" "$fpath"; then
            echo "--- Diff (${DIFF_CMD}) ---"
            "$DIFF_CMD" "$bk_fname" "$fpath" # cdiff 사용
            echo "--------------------------"
        else
            echo "Info: No effective changes were made."
            # Optionally remove the backup if no changes occurred
            # rm "$bk_fname"
        fi
        return 0
    else
        echo "Error occurred during awk processing (code: $ret). Restoring from backup." 1>&2
        # Attempt to restore from backup on error
        if mv "$bk_fname" "$fpath"; then
            echo "Restored original file from $bk_fname." 1>&2
        else
            echo "Error: Failed to restore from backup. Original file may be corrupted. Backup remains: $bk_fname" 1>&2
        fi
        return $ret
    fi
}

hash_restore() {
    local fpath="$1" latest_bak
    if [ -z "$fpath" ]; then
        echo "Usage: hash_restore <filepath>" 1>&2
        return 1
    fi
    if [ ! -f "$fpath" ]; then
        echo "Error: Target file does not exist: $fpath" 1>&2
        return 1
    fi
    # 최신 백업 찾기
    latest_bak=$(ls -t "${fpath}"_*.bak 2>/dev/null | head -n 1)
    if [ -z "$latest_bak" ]; then
        echo "No backup found for: $fpath" 1>&2
        return 1
    fi
    echo "Restoring: $fpath ← $latest_bak"
    cp -a "$latest_bak" "$fpath"
    echo "Restore complete."
}

hash_remove() {
    local fpath="$1" search="$2" num_arg="$3"
    local up=0 down=0 num=0
    local ts bk_fname ret DIFF_CMD="cdiff" # cdiff 유지

    # Check argument count
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
        echo "Usage: hash_remove <filepath> <search> [range]" 1>&2
        echo "  range=0 또는 생략      → 현재줄만" 1>&2
        echo "  range=+N 또는 N        → 현재줄 + 아래 N줄 (예: +2 또는 2)" 1>&2
        echo "  range=-N               → 현재줄 + 위 N줄 (예: -2)" 1>&2
        echo "  range=+-N              → 현재줄 + 위 N줄 + 아래 N줄 (예: +-2)" 1>&2
        return 1
    fi

    # Check if file exists
    [ ! -f "$fpath" ] && {
        echo "Error: File not found: $fpath" 1>&2
        return 1
    }

    # Parse range argument (순서 중요: +- 가 + 보다 먼저 와야 함)
    case "$num_arg" in
    '' | 0)
        up=0
        down=0
        ;;
    +-*) # Matches +-N (먼저 검사)
        num="${num_arg#+-}"
        if ! expr "$num" : '^[0-9]\+$' >/dev/null; then
            echo "Invalid range format: $num_arg (must be +- followed by a number)" 1>&2
            return 1
        fi
        up="$num"
        down="$num"
        ;;
    +*) # Matches +N
        up=0
        num="${num_arg#+}"
        if ! expr "$num" : '^[0-9]\+$' >/dev/null; then
            echo "Invalid range format: $num_arg (must be + followed by a number)" 1>&2
            return 1
        fi
        down="$num"
        ;;
    -*) # Matches -N
        down=0
        num="${num_arg#-}"
        if ! expr "$num" : '^[0-9]\+$' >/dev/null; then
            echo "Invalid range format: $num_arg (must be - followed by a number)" 1>&2
            return 1
        fi
        up="$num"
        ;;
    *[!0-9+-]*) # Catch completely invalid characters early
        echo "Invalid range format: $num_arg. Use N, +N, -N, or +-N." 1>&2
        return 1
        ;;
    *) # Matches N (interpreted as +N) or potentially invalid combinations
        if expr "$num_arg" : '^[0-9]\+$' >/dev/null; then
            up=0
            down="$num_arg"
        else
            echo "Invalid range format: $num_arg. Use N, +N, -N, or +-N." 1>&2
            return 1
        fi
        ;;
    esac

    # Create backup
    ts=$(date +%Y%m%d_%H%M%S)
    bk_fname="${fpath}_${ts}.bak"
    if ! cp -a "$fpath" "$bk_fname"; then
        echo "Error: Failed to create backup $bk_fname" 1>&2
        return 1
    fi

    # Process the file with awk to remove comments
    awk -v pat="$search" -v up="$up" -v down="$down" '
    {
        lines[NR] = $0
        # 검색 패턴과 일치하는 라인 번호 저장 (주석 여부와 관계 없음)
        if ($0 ~ pat) {
            match_lines[++mc] = NR
        }
    }
    END {
        # 주석 해제할 라인 마킹
        for (j = 1; j <= mc; j++) {
            m = match_lines[j] # 현재 매치된 라인 번호
            start_line = (m - up > 0) ? m - up : 1
            end_line = m + down # NR 비교는 아래 루프에서 처리

            for (i = start_line; i <= end_line; i++) {
                 # 유효한 라인 번호 범위 내에서만 마킹
                 if (i > 0 && i <= NR) {
                    mark[i] = 1
                 }
            }
        }

        # 라인 출력, 마크된 라인이고 "# " 로 시작하면 제거 후 출력
        for (i = 1; i <= NR; i++) {
            # 라인이 마크되었고, 맨 앞에 (공백 포함 가능) "# "가 있으면 sub 함수로 제거
            if (mark[i] && sub(/^[[:space:]]*# /, "", lines[i])) {
                # sub()가 성공하면 (즉, "# "가 있었으면) 변경된 lines[i]를 출력
                print lines[i]
            } else {
                # 마크되지 않았거나, 마크되었지만 "# "로 시작하지 않으면 원본 lines[i] 출력
                print lines[i]
            }
        }
    }' "$bk_fname" >"$fpath"
    ret=$?

    # Report results
    if [ $ret -eq 0 ]; then
        echo "Hash Remove done. Backup: $bk_fname"
        if ! cmp -s "$bk_fname" "$fpath"; then
            echo "--- Diff (${DIFF_CMD}) ---"
            "$DIFF_CMD" "$bk_fname" "$fpath" # cdiff 사용
            echo "--------------------------"
        else
            echo "Info: No effective changes were made."
        fi
        return 0
    else
        echo "Error occurred during awk processing (code: $ret). Restoring from backup." 1>&2
        # Attempt to restore from backup on error
        if mv "$bk_fname" "$fpath"; then
            echo "Restored original file from $bk_fname." 1>&2
        else
            echo "Error: Failed to restore from backup. Original file may be corrupted. Backup remains: $bk_fname" 1>&2
        fi
        return $ret
    fi
}

hash-add() { hash_add $@; }
hash-remove() { hash_remove $@; }

eprintf() {
    # 사용자 안내 메시지 (stderr)
    echo "설정 내용을 입력하세요. 입력 완료 후 Ctrl+D를 누르세요:" >&2

    local line
    local ansi_c_content="" # ANSI-C $'' 안에 들어갈 내용
    local first_line=1      # 첫 줄 플래그

    # /dev/tty 에서 한 줄씩 읽기
    while IFS= read -r line || [[ -n $line ]]; do
        # 이스케이프: \ -> \\, ' -> \'
        line=${line//\\/\\\\}
        line=${line//\'/\\\'}
        line=${line//%/%%}
        # 내용 조합: 첫 줄은 그대로, 이후 줄은 \n 과 함께 추가
        if [[ $first_line -eq 1 ]]; then
            ansi_c_content="$line"
            first_line=0
        else
            ansi_c_content="${ansi_c_content}\\n$line" # 줄 사이에 \n 추가 (Bash 2 호환: += 금지)
        fi
    done </dev/tty

    # 입력 내용 없으면 경고 후 종료
    if [[ -z $ansi_c_content && $first_line -eq 1 ]]; then
        echo "경고: 입력된 내용이 없습니다." >&2
        return 1
    fi

    # ANSI-C 내용의 가장 끝에 줄바꿈 이스케이프(\n)를 추가합니다.
    # 이렇게 하면 생성된 printf 명령 실행 시 마지막 내용 뒤에 줄바꿈이 발생합니다.
    # (입력이 아예 없었던 경우는 제외)
    if [[ $first_line -eq 0 ]]; then # 입력이 한 줄이라도 있었으면
        ansi_c_content="${ansi_c_content}\n" # 내용 끝에 \n 추가 (Bash 2 호환: += 금지)
    fi

    # 최종 printf 명령어 문자열을 '한 줄로' 출력하고, 그 뒤에 줄바꿈을 추가합니다.
    # 형식: printf $'{포맷팅된 내용}\n' (이제 {포맷팅된 내용} 끝에 \n 이 포함됨)
    # 바깥쪽 printf의 포맷 문자열 끝에 \n 을 추가하여 eprintf 함수 자체 출력 후 줄바꿈 발생
    printf "printf \$'%s'\n" "$ansi_c_content"
    #                      ^^-- eprintf 출력 후 줄바꿈 위해 유지

    # 함수 실행 후 프롬프트가 새 줄에서 시작됨
}

# 환경변수에 추가 prefix[0-999]=$2
exportvar() {
    p=$1
    v=$2
    i=1
    while true; do
        n="${p}${i}"
        if [ -z "${!n}" ]; then
            export ${n}="${v}"
            YEL1
            echo "Exported: ${n}=${v}"
            NC
            break
        fi
        ((i++))
    done
}
# prefix[0-999] 환경변수 모두 unset
unsetvar() {
    p=$1
    i=1
    while true; do
        n="${p}${i}"
        if (! declare -p ${n} 2>/dev/null); then break; fi
        unset ${n}
        echo "Unset: ${n}"
        ((i++))
    done
}
# 강제종료시 남아있을수 있는 로컬변수 선언 초기화
#unsetvar varl

# wait enter
readx() { read -p "[Enter] " x </dev/tty; }
# enter or cmds
readnewcmds() { IFS=' ' read -rep "[Enter] " newcmds newcmds1 </dev/tty; }
readxy() {
    dline
    while true; do
        [ "$1" ] && printf "$CYN1%s$NC " "$1" # 메시지 있으면 줄바꿈 없이 출력
        read -p "preceed? [Enter/y/Y = OK, n = Cancel] " x </dev/tty
        case "$x" in
        [yY] | "") return 0 ;; # 진행
        [nN])
            echo "Cancelled."
            return 1
            ;; # 중단
        *) echo "Please enter y, n or just Enter." ;;
        esac
    done
}

#readxx() { :; }
# debug -> readxx
readxx() { [ -n "$debug" ] && {
    local arg1="${1-NULL}" arg2="${2-NULL}" arg3="${3-NULL}" arg4="${4-NULL}" arg5="${5-NULL}" arg6="${6-NULL}" arg7="${7-NULL}" arg8="${8-NULL}"
    echo -e "Debug Here!!   \e[1;37;41mline:\e[0m $arg1  \e[1;37;41m 1:\e[0m $arg2 \e[1;37;41m 2:\e[0m $arg3 \e[1;37;41m 3:\e[0m $arg4  \e[1;37;41m 4:\e[0m $arg5 \e[1;37;41m 5:\e[0m $arg6 \e[1;37;41m 6:\e[0m $arg7  \e[1;37;41m 7:\e[0m $arg8 \e[1;37;41m 8:\e[0m ${9-NULL} \e[1;37;41m 9:\e[0m ${10-NULL}[Enter]"
    read x </dev/tty
}; }

# sleepdot // ex) sleepdot 30 or sleepdot
# $1 로 할당된 실제 시간(초)이 지나면 종료 되도록 개선 sleep $1 과 동일하지만 시각화
sleepdot() {
    echo -n "sleepdot $1 "
    bashver=${BASH_VERSINFO[0]}
    ((bashver < 3)) && real1sec=1 || real1sec=1
    s=$(date +%s)
    c=1
    stopdot=0

    trap 'stopdot=1' INT

    [ -z "$1" ] && echo -n ">>> Quit -> [Anykey] "

    while [ -z "$x" ]; do
        if [ "$stopdot" = 1 ]; then
            echo
            echo "Canceled"
            trap - INT
            return 1 # Ctrl+C로 중단 시 실패로 종료
        fi

        [ "$1" ] && sleep 1
        echo -n "."
        [ $((c % 5)) -eq 0 ] && echo -n " "
        [ $((c % 30)) -eq 0 ] && echo $c
        t=$(($(date +%s) - s))
        [ $((c % 300)) -eq 0 ] && echo
        c=$((c + 1))

        if [ "$1" ] && [ $t -ge $1 ]; then
            break
        elif [ -z "$1" ]; then
            IFS=z read -t$real1sec -n1 x && break
        fi
    done

    trap - INT
    echo
    return 0 # 정상 종료
}

# backup & vi
vi22() {
    [ ! -f "$1" ] && return 1
    rbackup "$1"
    if [ -n "$2" ]; then
        vim -c "autocmd VimEnter * ++once let @/ = '$2'" \
            -c "autocmd VimEnter * ++once normal! n zt" "$1"
    else
        vim "$1" || vi "$1" || nano "$1"
    fi
}

# 인수중 하나 선택
cat3() {
    [ $# -eq 0 ] && echo "Usage: cat3 file1 [file2 ...]" && return 1
    select f in "$@" "Cancel"; do
        [ "$f" = "Cancel" ] && break
        [ -n "$f" ] && [ -f "$f" ] && cat "$f" || echo "'$f' not found"
        break
    done
}
vi3() {
    [ $# -eq 0 ] && echo "Usage: vi3 file1 [file2 ...]" && return 1
    if [ $# -eq 1 ]; then [ -f "$1" ] && vi2 "$1" || echo "'$1' not found"; return $?; fi
    select f in "$@" "Cancel"; do
        [ "$f" = "Cancel" ] && break
        [ -n "$f" ] && [ -f "$f" ] && vi2 "$f" || echo "'$f' not found"
        break
    done
}
vi2() {
    [ ! -f "$1" ] && echo "File not found on $(hostname): $1" && return 1
    rbackup "$1"
    # 문자열 찾고 그 위치에서 편집
    #if [ -n "$2" ]; then vim -c "autocmd VimEnter * silent! execute '/^%%% .*\[$2\]'" "$1"; else vim "$1" || vi "$1"; fi
    if [ -n "$3" ]; then
        #readxy "$3"
        if [ "$3" == "tailedit" ]; then
            # 문자열 찾고 그 위치의 문단끝에서 편집
            if [ -n "$2" ]; then vim -c "autocmd VimEnter * silent! execute '/^%%% .*\[$2\]' | silent! normal! } zb'" "$1" || nano "$1"; else vim "$1" || vi "$1"; fi
        else
            # $2 대신 $3 를 찾음
            if [ -n "$3" ]; then vim -c "autocmd VimEnter * silent! execute '/^%%% .*\[$3\]' | silent! normal! } zb'" "$1" || nano "$1"; else vim "$1" || vi "$1"; fi
        fi
    else
        # 문자열 찾고 그 위치의 처음에서 편집
        if [ -n "$2" ]; then vim -c "autocmd VimEnter * silent! execute '/^%%% .*\[$2\]' | silent! normal! zt'" "$1" || nano "$1"; else vim "$1" || vi "$1" || nano "$1"; fi
    fi
}
vi2e() {
    [ ! -f "$1" ] && return 1
    rbackup $1
    vim -c "set fileencoding=euc-kr" $1
}
vi2u() {
    [ ! -f "$1" ] && return 1
    rbackup $1
    vim -c "set fileencoding=utf-8" $1
}
vi2a() {
    [ ! -f "$1" ] && return 1
    rbackup "$1" && [ "$(locale charmap)" = "UTF-8" ] && [ ! "$(file -i "$1" | grep "utf")" ] &&
        iconv -f euc-kr -t utf-8//IGNORE -o "$1.utf8" "$1" 2>/dev/null && mv "$1.utf8" "$1"

    vim -c "[ -n \"$2\" ] && autocmd VimEnter * silent! execute '/^%%% .*\[$2\]' | silent! normal! }'" "$1" || vi "$1"
}

# server-status
weblog() { lynx --dump --width=260 http://localhost/server-status | cpipe | less -RX; }

logview() {
    local logfile="$1" mode="$2"
    [[ -f $logfile ]] || {
        echo "[logview] File not found: $logfile" >&2
        return 1
    }

    if [[ $mode == "f" ]]; then
        trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
        tail -f "$logfile" | cpipe
        trap - SIGINT
    else
        tac "$logfile" | cpipe | less -RX
    fi
}

ftplog() { logview /var/log/xferlog; }
ftplogf() { logview /var/log/xferlog f; }
bootlog() { dmesg | cpipe | less -RX; }

# journalctl
log() { journalctl -e; }
loge() { journalctl -rp warning; }
er() { journalctl -rp warning; }
err() {
    trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
    journalctl -f -p warning
    trap - SIGINT
}
logf() {
    trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
    journalctl -f
    trap - SIGINT
}
# select function
logsff() { $(declare -F | awk '{print $3}' | grep log | grep -v dialog | sort | pipemenu); }
logsfff() { for i in $(declare -F | awk '{print $3}' | grep log | grep -v dialog | sort); do fff $i; done | cpipe | less -RX; }

# select & logview
logs() { log=$(find /var/log/ -maxdepth 1 -mtime -1 -type f -name '*.log' | sort | pipemenu) && logview $log; }
logsf() { log=$(find /var/log/ -maxdepth 1 -mtime -1 -type f -name '*.log' | sort | pipemenu) && logview $log f; }

# 활성화된 서비스 목록에서 선택
ss() { systemctl status $(systemctl list-unit-files --type=service | grep enabled | awk -F'.service' '{print $1}' | pipemenu1); }
ssg() {
    [ -z "$1" ] && echo "Usage: ssg <keyword>" && return 1
    systemctl status $(systemctl list-unit-files --type=service | grep "$1" | awk -F'.service' '{print $1}')
}
# 개별 주요 서비스들
ssa() { systemctl status $(systemctl | grep -Eo 'apache2|nginx' | head -n1); }      # Apache/nginx
sss() { systemctl status $(systemctl | grep -Eo 'sshd?' | head -n1); }              # SSH
ssn() { systemctl status $(systemctl | grep -Eo 'networking|netplan' | head -n1); } # network
ssd() { systemctl status docker; }                                                  # Docker
ssb() { systemctl status fail2ban; }                                                # Fail2Ban
ssu() { systemctl status ufw; }                                                     # UFW Firewall
ssc() { systemctl status cron; }                                                    # Cron
# 자동 감지형
ssm() { systemctl status $(systemctl | grep -Eo 'mariadb|mysql' | head -n1); }                                     # MySQL or MariaDB
ssp() { systemctl status $(systemctl | awk '/php[0-9.]*-fpm/ {for(i=1;i<=NF;i++) if($i ~ /^php[0-9.]*-fpm/) {print $i; break}}' | sort -r | head -n1); }                          # 최신 PHP-FPM
ssf() { systemctl status $(systemctl list-unit-files --type=service | grep ftp | awk -F'.service' '{print $1}'); } # ftp
# Proxmox 관련 (사용 중이라면)
ssv() { systemctl status $(echo pvedaemon pveproxy qmeventd lxc | pipemenu); }

###############################################################
# 통합 서버 데몬 관리 TUI (dm — Daemon Manager)
# - CentOS/RHEL/Alma/Rocky (systemd / chkconfig) + Debian/Ubuntu (systemd / update-rc.d) 통합
# - 진입 시점 스냅샷 저장 및 개별(u)/전체(U) 원복 지원
# - SSH/네트워크/Proxmox/핵심 OS 데몬 사전 차단 (Proxmox 파쇄식 확인 타이핑 필수)
# - 실효 환경 파일 자동 탐지 -> vi2 편집 -> 문법 사전 검증(sshd -t 등) -> 재시작 제안
# - Bash 3.x+ 호환 (연관 배열 미사용, 인덱스 배열만 사용)
###############################################################
_dm_detect_env() {
    _DM_INIT=""
    _DM_OS="Linux"
    _DM_RUNLEVEL="3"
    _DM_ENC="${GOTERM_ENC:-}"
    if [ -z "$_DM_ENC" ]; then
        case "${LANG:-} $(locale charmap 2>/dev/null)" in
            *[Uu][Tt][Ff]*) _DM_ENC="utf8" ;;
            *) _DM_ENC="euckr" ;;
        esac
    fi
    if [ -f /etc/os-release ]; then
        _DM_OS=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null)
    elif [ -f /etc/redhat-release ]; then
        _DM_OS=$(head -n1 /etc/redhat-release 2>/dev/null)
    elif [ -f /etc/debian_version ]; then
        _DM_OS="Debian $(cat /etc/debian_version 2>/dev/null)"
    fi
    [ -z "$_DM_OS" ] && _DM_OS="$(uname -s 2>/dev/null)"

    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        _DM_INIT="systemd"
    elif command -v chkconfig >/dev/null 2>&1; then
        _DM_INIT="sysv_rh"
        local _rl
        _rl=$(runlevel 2>/dev/null | awk '{print $2}')
        case "$_rl" in [0-6]) _DM_RUNLEVEL="$_rl" ;; *) _DM_RUNLEVEL="3" ;; esac
    elif [ -d /etc/init.d ]; then
        _DM_INIT="sysv_deb"
        local _rl
        _rl=$(runlevel 2>/dev/null | awk '{print $2}')
        case "$_rl" in [0-6]) _DM_RUNLEVEL="$_rl" ;; *) _DM_RUNLEVEL="2" ;; esac
    else
        _DM_INIT="unknown"
    fi
}

# UTF-8 -> 터미널 인코딩(EUC-KR) 안전 출력 헬퍼 (구서버 한글/줄바꿈/iconv 절단 방지)
# Red Hat 7.2 (glibc 2.2) iconv 는 EUC-KR 에 없는 이모지/기호를 만나면 그 자리에서 출력이 중단될 수 있으므로
# 변환 전 비-EUC-KR 기호를 ASCII 로 먼저 치환한다.
_dm_iconv_euckr() {
    LC_ALL=C sed \
        -e 's/✔/[OK]/g' \
        -e 's/✖/[ERR]/g' \
        -e 's/⚠/[WARN]/g' \
        -e 's/⛔/[STOP]/g' \
        -e 's/🛡/[SAFE]/g' \
        -e 's/⏱/[TIMER]/g' \
        -e 's/📝/[EDIT]/g' \
        -e 's/ℹ/[i]/g' \
        -e 's/🔍/[i]/g' \
        -e 's/🔒/[LOCK]/g' \
        -e 's/▶/>/g' \
        -e 's/●/*/g' \
        -e 's/○/./g' \
        -e 's/•/-/g' \
        -e 's/—/-/g' \
        -e 's/─/-/g' \
        -e 's/❌/[ERR]/g' \
        -e 's/🎲/[RAND]/g' \
        -e 's/⌨️/[KEY]/g' \
        -e 's/⌨/[KEY]/g' \
        -e 's/🔄/[RE]/g' \
        -e 's/📧/[MAIL]/g' \
        -e 's/📨/[SEND]/g' \
        -e 's/📱/[SMS]/g' \
        -e 's/🚀/[ALL]/g' \
        -e 's/🔐/[AUTH]/g' \
        -e 's/📁/[DIR]/g' \
        -e 's/🔧/[FIX]/g' \
        -e 's/🔎/[FIND]/g' \
        -e 's/📂/[OPEN]/g' \
        -e 's/🗄️/[DB]/g' \
        -e 's/🗄/[DB]/g' \
        -e 's/💾/[BAK]/g' \
        -e 's/💻/[SQL]/g' \
        -e 's/📋/[INFO]/g' \
        -e 's/🌐/[ALL]/g' \
        -e 's/📊/[TRF]/g' \
        -e 's/💿/[DISK]/g' \
        -e 's/🌍/[DNS]/g' \
        -e 's/💰/[PAY]/g' \
        | iconv -f utf-8 -t euc-kr//IGNORE 2>/dev/null
}

_dm_p() {
    local _fmt="$1"
    shift
    if [ "$_DM_ENC" = "euckr" ]; then
        printf "$_fmt" "$@" | _dm_iconv_euckr
    else
        printf "$_fmt" "$@"
    fi
}

# 위험 등급 및 사전 경고 문구 판별
# 출력(전역): _DM_R_LVL (CRIT|WARN|OK), _DM_R_MSG
_dm_risk_info() {
    local svc="$1"
    _DM_R_LVL="OK"
    _DM_R_MSG=""
    case "$svc" in
        ssh|sshd|dropbear|openssh-server|openssh)
            _DM_R_LVL="CRIT"
            _DM_R_MSG="원격 SSH 접속이 끊겨 서버에 다시 들어올 수 없게 됩니다!"
            ;;
        network|networking|NetworkManager|systemd-networkd|systemd-resolved|netplan*|ifupdown*|wg-quick*|tailscaled|openvpn*)
            _DM_R_LVL="CRIT"
            _DM_R_MSG="네트워크가 중단되어 모든 원격 연결(SSH 포함)이 즉시 끊깁니다!"
            ;;
        pve-cluster|corosync|pvedaemon|pveproxy|pvestatd|qmeventd|pve-ha-lrm|pve-ha-crm)
            _DM_R_LVL="CRIT"
            _DM_R_MSG="Proxmox 클러스터/웹UI/VM 제어가 마비될 수 있습니다!"
            ;;
        dbus|systemd-udevd|systemd-logind|systemd-journald|udev|lvm2*|mdmonitor|multipathd|polkit|systemd-homed)
            _DM_R_LVL="CRIT"
            _DM_R_MSG="OS 핵심 시스템 데몬으로 중단 시 부팅/로그인/디스크가 마비될 수 있습니다!"
            ;;
        firewalld|ufw|iptables|ip6tables|nftables|fail2ban|csf|lfd)
            _DM_R_LVL="WARN"
            _DM_R_MSG="방화벽/보안 규칙 변경으로 접속이 차단되거나 보안이 해제될 수 있습니다."
            ;;
        httpd|apache2|nginx|mariadb|mysqld|mysql|postgresql*|named|bind9|postfix|sendmail|exim*|dovecot|vsftpd|proftpd|pure-ftpd|php*-fpm|docker|containerd|crond|cron|haproxy|redis*|memcached|smb|smbd|nmbd)
            _DM_R_LVL="WARN"
            _DM_R_MSG="운영 중인 주요 서버 서비스(웹/DB/DNS/메일 등)가 중단됩니다."
            ;;
    esac
}

# 핵심 데몬 한글 역할 사전 (없으면 빈 문자열 -> 시스템 Description 폴백)
_dm_builtin_desc() {
    case "$1" in
        ssh|sshd|openssh-server) echo "SSH 원격 접속 서버 (OpenSSH)" ;;
        dropbear) echo "경량 SSH 원격 접속 서버" ;;
        httpd|apache2) echo "Apache HTTP 웹 서버" ;;
        nginx) echo "Nginx 고성능 웹 서버 / 리버스 프록시" ;;
        mariadb) echo "MariaDB 관계형 데이터베이스 서버" ;;
        mysqld|mysql) echo "MySQL 관계형 데이터베이스 서버" ;;
        postgresql*) echo "PostgreSQL 관계형 데이터베이스 서버" ;;
        named|bind9) echo "BIND DNS 네임서버" ;;
        postfix) echo "Postfix SMTP 메일 전송 서버" ;;
        sendmail) echo "Sendmail SMTP 메일 전송 서버" ;;
        exim*) echo "Exim SMTP 메일 전송 서버" ;;
        dovecot) echo "Dovecot IMAP/POP3 메일 수신 서버" ;;
        vsftpd) echo "vsftpd FTP 파일 전송 서버" ;;
        proftpd) echo "ProFTPD FTP 파일 전송 서버" ;;
        pure-ftpd) echo "Pure-FTPd FTP 파일 전송 서버" ;;
        php*-fpm) echo "PHP FastCGI 프로세스 매니저 (PHP-FPM)" ;;
        crond|cron) echo "정기 예약 작업(Cron) 스케줄러" ;;
        atd) echo "일회성 예약 작업(at) 데몬" ;;
        rsyslog|syslog|syslog-ng) echo "시스템 로그 수집/기록 데몬" ;;
        systemd-journald) echo "Systemd 바이너리 저널 로그 데몬" ;;
        chronyd) echo "Chrony NTP 시간 동기화 데몬" ;;
        ntpd|ntp|systemd-timesyncd) echo "NTP 네트워크 시간 동기화 데몬" ;;
        firewalld) echo "Firewalld 동적 방화벽 관리 데몬" ;;
        ufw) echo "UFW(Uncomplicated Firewall) 방화벽" ;;
        iptables|ip6tables) echo "IPTables 패킷 필터 방화벽" ;;
        nftables) echo "nftables 차세대 패킷 필터 방화벽" ;;
        fail2ban) echo "로그 기반 브루트포스 침입 차단 데몬" ;;
        network|networking) echo "시스템 네트워크 인터페이스 관리" ;;
        NetworkManager) echo "동적 네트워크 연결 관리 데몬" ;;
        systemd-networkd) echo "Systemd 네트워크 설정 데몬" ;;
        systemd-resolved) echo "Systemd 로컬 DNS 리졸버" ;;
        docker) echo "Docker 컨테이너 엔진 데몬" ;;
        containerd) echo "컨테이너 런타임 데몬 (containerd)" ;;
        haproxy) echo "HAProxy 로드밸런서 / 프록시" ;;
        redis|redis-server) echo "Redis 인메모리 캐시/데이터 저장소" ;;
        memcached) echo "Memcached 인메모리 객체 캐시" ;;
        smb|smbd) echo "Samba SMB/CIFS 파일 공유 서버" ;;
        nmb|nmbd) echo "Samba NetBIOS 이름 서비스" ;;
        nfs-server|nfs|nfsd) echo "NFS 네트워크 파일시스템 서버" ;;
        rpcbind|portmap) echo "RPC 포트 매핑 데몬 (NFS 의존)" ;;
        xinetd) echo "확장 인터넷 슈퍼 데몬 (온디맨드 서비스)" ;;
        snmpd) echo "SNMP 네트워크 모니터링 에이전트" ;;
        smartd|smartmontools) echo "디스크 S.M.A.R.T. 상태 감시 데몬" ;;
        auditd) echo "리눅스 커널 보안 감사 로그 데몬" ;;
        irqbalance) echo "멀티코어 CPU 인터럽트 부하 분산" ;;
        tuned) echo "시스템 성능 프로파일 자동 튜닝" ;;
        dbus) echo "시스템 프로세스 간 메시지 버스 (D-Bus)" ;;
        systemd-logind) echo "사용자 로그인/세션 관리 데몬" ;;
        systemd-udevd|udev) echo "커널 장치 노드(/dev) 동적 관리" ;;
        pveproxy) echo "Proxmox VE 웹 관리 API 프록시 (8006)" ;;
        pvedaemon) echo "Proxmox VE 백엔드 관리 데몬" ;;
        pve-cluster) echo "Proxmox 클러스터 파일시스템 (/etc/pve)" ;;
        pvestatd) echo "Proxmox 노드/VM 상태 통계 수집" ;;
        corosync) echo "Proxmox 고가용성 클러스터 통신 엔진" ;;
        qmeventd) echo "Proxmox QEMU/KVM 이벤트 감시 데몬" ;;
        lxc*|pve-guests) echo "Proxmox LXC/VM 게스트 자동시작 관리" ;;
        tailscaled) echo "Tailscale 메시 VPN 데몬" ;;
        wg-quick*) echo "WireGuard VPN 터널 인터페이스" ;;
        openvpn*) echo "OpenVPN 가상 사설망 데몬" ;;
        clamd*|clamav*) echo "ClamAV 악성코드/바이러스 백신 데몬" ;;
        spamassassin|spamd) echo "SpamAssassin 스팸 메일 필터 데몬" ;;
        mysqld_safe) echo "MySQL 안전 래퍼 데몬" ;;
        webmin) echo "Webmin 웹 기반 서버 관리 도구" ;;
        cockpit*) echo "Cockpit 웹 기반 리눅스 관리 콘솔" ;;
        avahi-daemon) echo "mDNS/DNS-SD 로컬 네트워크 탐색" ;;
        cups|cupsd) echo "CUPS 프린터 인쇄 서버" ;;
        bluetooth) echo "블루투스 장치 관리 데몬" ;;
        ModemManager) echo "모바일 광대역 모뎀 관리 데몬" ;;
        getty@*|serial-getty@*) echo "가상/시리얼 터미널 로그인 콘솔" ;;
        *) echo "" ;;
    esac
}

# 주요 서버 데몬 필터 판별 (f 키 '주요서버' 모드용)
_dm_is_major() {
    case "$1" in
        ssh|sshd|dropbear|httpd|apache2|nginx|mariadb|mysqld|mysql|postgresql*|named|bind9|\
        postfix|sendmail|exim*|dovecot|vsftpd|proftpd|pure-ftpd|php*-fpm|crond|cron|\
        firewalld|ufw|iptables|nftables|fail2ban|network|networking|NetworkManager|\
        systemd-networkd|systemd-resolved|docker|containerd|haproxy|redis*|memcached|\
        smb|smbd|nfs*|rsyslog|chronyd|ntpd|xinetd|pveproxy|pvedaemon|pve-cluster|corosync|\
        tailscaled|wg-quick*|openvpn*)
            return 0 ;;
        *) return 1 ;;
    esac
}

# 시스템에서 서비스 설명 보충 조회 (캐시되지 않았거나 빈 설명일 때)
_dm_fetch_sys_desc() {
    local svc="$1" d=""
    if [ "$_DM_INIT" = "systemd" ]; then
        d=$(systemctl show -p Description --value "${svc}.service" 2>/dev/null)
        [ -z "$d" ] && d=$(systemctl show -p Description "${svc}.service" 2>/dev/null | sed 's/^Description=//')
    else
        local f=""
        [ -f "/etc/rc.d/init.d/$svc" ] && f="/etc/rc.d/init.d/$svc"
        [ -z "$f" ] && [ -f "/etc/init.d/$svc" ] && f="/etc/init.d/$svc"
        if [ -n "$f" ]; then
            d=$(awk '
                /^#[[:space:]]*Short-Description:/ { sub(/^#[[:space:]]*Short-Description:[[:space:]]*/,""); print; exit }
                /^#[[:space:]]*description:/ { sub(/^#[[:space:]]*description:[[:space:]]*/,""); gsub(/\\$/,""); print; exit }
            ' "$f" 2>/dev/null)
        fi
    fi
    # 구서버 EUC-KR iconv 중단 방지: 제어문자/비정상 바이트 제거 (영문 Description 은 안전 유지)
    if [ "$_DM_ENC" = "euckr" ]; then
        d=$(printf '%s' "$d" | LC_ALL=C tr -cd '\40-\176')
    fi
    echo "$d"
}

# 데몬 실효 설정 파일 후보 탐지 (한 줄에 1경로, 중복 제거, 실제 존재 파일만)
_dm_find_configs() {
    local svc="$1"
    local raw="" c="" f=""
    _add_if_file() {
        local p
        for p in "$@"; do
            [ -f "$p" ] && raw="${raw}${p}"$'\n'
        done
    }

    # 1) 배포판 통합 주요 서비스 실효 설정 매핑 (CentOS + Debian 공통)
    case "$svc" in
        ssh|sshd|openssh-server)
            _add_if_file /etc/ssh/sshd_config /etc/ssh/ssh_config
            for f in /etc/ssh/sshd_config.d/*.conf; do _add_if_file "$f"; done
            ;;
        dropbear)
            _add_if_file /etc/default/dropbear /etc/sysconfig/dropbear
            ;;
        httpd)
            _add_if_file /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/vhost.conf /etc/sysconfig/httpd
            ;;
        apache2)
            _add_if_file /etc/apache2/apache2.conf /etc/apache2/ports.conf /etc/apache2/envvars /etc/apache2/sites-enabled/000-default.conf
            ;;
        nginx)
            _add_if_file /etc/nginx/nginx.conf /etc/nginx/conf.d/default.conf /etc/nginx/sites-enabled/default
            ;;
        mariadb|mysqld|mysql)
            _add_if_file /etc/my.cnf /etc/my.cnf.d/mariadb-server.cnf /etc/my.cnf.d/server.cnf /etc/mysql/my.cnf /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/mysql.conf.d/mysqld.cnf
            ;;
        postgresql*)
            for f in /etc/postgresql/*/*/postgresql.conf /var/lib/pgsql/data/postgresql.conf /var/lib/pgsql/*/data/postgresql.conf; do _add_if_file "$f"; done
            ;;
        named|bind9)
            _add_if_file /etc/named.conf /etc/named.rfc1912.zones /etc/bind/named.conf /etc/bind/named.conf.options /etc/bind/named.conf.local /etc/sysconfig/named
            ;;
        postfix)
            _add_if_file /etc/postfix/main.cf /etc/postfix/master.cf
            ;;
        sendmail)
            _add_if_file /etc/mail/sendmail.mc /etc/mail/sendmail.cf /etc/mail/access /etc/mail/local-host-names
            ;;
        dovecot)
            _add_if_file /etc/dovecot/dovecot.conf /etc/dovecot/conf.d/10-mail.conf /etc/dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-ssl.conf
            ;;
        vsftpd)
            _add_if_file /etc/vsftpd/vsftpd.conf /etc/vsftpd.conf /etc/vsftpd/user_list
            ;;
        proftpd)
            _add_if_file /etc/proftpd.conf /etc/proftpd/proftpd.conf
            ;;
        php*-fpm)
            _add_if_file /etc/php-fpm.conf /etc/php-fpm.d/www.conf /etc/php.ini
            for f in /etc/php/*/fpm/php-fpm.conf /etc/php/*/fpm/pool.d/www.conf /etc/php/*/fpm/php.ini; do _add_if_file "$f"; done
            ;;
        crond|cron)
            _add_if_file /etc/crontab /etc/sysconfig/crond /etc/default/cron
            ;;
        fail2ban)
            _add_if_file /etc/fail2ban/jail.local /etc/fail2ban/jail.conf /etc/fail2ban/fail2ban.conf
            ;;
        firewalld)
            _add_if_file /etc/firewalld/firewalld.conf
            ;;
        ufw)
            _add_if_file /etc/ufw/ufw.conf /etc/default/ufw
            ;;
        iptables|ip6tables)
            _add_if_file /etc/sysconfig/iptables /etc/sysconfig/iptables-config /etc/iptables/rules.v4
            ;;
        nftables)
            _add_if_file /etc/nftables.conf /etc/sysconfig/nftables.conf
            ;;
        rsyslog)
            _add_if_file /etc/rsyslog.conf
            ;;
        chronyd)
            _add_if_file /etc/chrony.conf /etc/chrony/chrony.conf
            ;;
        ntpd|ntp)
            _add_if_file /etc/ntp.conf
            ;;
        haproxy)
            _add_if_file /etc/haproxy/haproxy.cfg
            ;;
        redis|redis-server)
            _add_if_file /etc/redis.conf /etc/redis/redis.conf
            ;;
        memcached)
            _add_if_file /etc/sysconfig/memcached /etc/memcached.conf
            ;;
        smb|smbd|nmb|nmbd)
            _add_if_file /etc/samba/smb.conf
            ;;
        docker)
            _add_if_file /etc/docker/daemon.json
            ;;
        xinetd)
            _add_if_file /etc/xinetd.conf
            ;;
        networking|network)
            _add_if_file /etc/network/interfaces /etc/sysconfig/network
            ;;
        NetworkManager)
            _add_if_file /etc/NetworkManager/NetworkManager.conf
            ;;
        systemd-resolved)
            _add_if_file /etc/systemd/resolved.conf /etc/resolv.conf
            ;;
        pveproxy|pvedaemon|corosync|pve-cluster)
            _add_if_file /etc/default/pveproxy /etc/pve/corosync.conf /etc/corosync/corosync.conf /etc/hosts
            ;;
    esac

    # 2) 동적 탐지: systemd 유닛 속성(1회 호출) / init.d 스크립트에서 설정 경로 추출
    if [ "$_DM_INIT" = "systemd" ]; then
        local _frag="" _drop="" _envf="" _exec="" _tok="" _prev="" _prop=""
        while IFS= read -r _prop; do
            case "$_prop" in
                FragmentPath=*)     _frag="${_prop#FragmentPath=}" ;;
                DropInPaths=*)      _drop="${_prop#DropInPaths=}" ;;
                EnvironmentFiles=*) _envf="${_prop#EnvironmentFiles=}" ;;
                ExecStart=*)        _exec="${_prop#ExecStart=}" ;;
            esac
        done <<EOF
$(systemctl show -p FragmentPath -p DropInPaths -p EnvironmentFiles -p ExecStart "${svc}.service" 2>/dev/null)
EOF

        # ExecStart 안의 -c /path, -f /path, --config=/path 추출
        for _tok in $_exec; do
            case "$_tok" in
                --config=*|--conf=*|--config-file=*|--defaults-file=*)
                    c="${_tok#*=}"
                    c="${c%;}"
                    _add_if_file "$c"
                    ;;
                /*)
                    case "$_prev" in
                        -c|-f|-C|--config|--conf) _add_if_file "${_tok%;}" ;;
                    esac
                    ;;
            esac
            _prev="$_tok"
        done

        # EnvironmentFiles (예: /etc/sysconfig/xxx (ignore_errors=yes))
        for _tok in $_envf; do
            case "$_tok" in
                -*) _tok="${_tok#-}" ;;
            esac
            case "$_tok" in
                /*) _add_if_file "$_tok" ;;
            esac
        done

        # DropIn 오버라이드 & FragmentPath(유닛 파일 자체)
        for _tok in $_drop; do _add_if_file "$_tok"; done
        [ -n "$_frag" ] && _add_if_file "$_frag"
    else
        local _initf=""
        [ -f "/etc/rc.d/init.d/$svc" ] && _initf="/etc/rc.d/init.d/$svc"
        [ -z "$_initf" ] && [ -f "/etc/init.d/$svc" ] && _initf="/etc/init.d/$svc"
        if [ -n "$_initf" ]; then
            local _found
            _found=$(grep -Eo '/etc/[A-Za-z0-9._/-]+\.(conf|cfg|cnf|ini|cf|yaml|yml)' "$_initf" 2>/dev/null | head -n 6)
            for c in $_found; do _add_if_file "$c"; done
            _add_if_file "/etc/sysconfig/$svc" "/etc/default/$svc" "$_initf"
        fi
    fi

    # 3) 범용 경로 폴백
    _add_if_file "/etc/${svc}/${svc}.conf" "/etc/${svc}.conf" "/etc/sysconfig/${svc}" "/etc/default/${svc}"

    # 중복 제거(순서 유지)
    printf '%s' "$raw" | awk 'NF && !seen[$0]++'
}

# 설정 변경 후 문법 사전 검증 (0=통과 또는 검사기 없음, 1=문법 오류)
_dm_config_test() {
    local svc="$1"
    local _cmd=""
    case "$svc" in
        ssh|sshd|openssh-server) command -v sshd >/dev/null 2>&1 && _cmd="sshd -t" ;;
        httpd)
            if command -v httpd >/dev/null 2>&1; then _cmd="httpd -t"
            elif command -v apachectl >/dev/null 2>&1; then _cmd="apachectl -t"
            fi ;;
        apache2) command -v apache2ctl >/dev/null 2>&1 && _cmd="apache2ctl -t" ;;
        nginx) command -v nginx >/dev/null 2>&1 && _cmd="nginx -t" ;;
        named|bind9) command -v named-checkconf >/dev/null 2>&1 && _cmd="named-checkconf" ;;
        postfix) command -v postfix >/dev/null 2>&1 && _cmd="postfix check" ;;
        haproxy) command -v haproxy >/dev/null 2>&1 && [ -f /etc/haproxy/haproxy.cfg ] && _cmd="haproxy -c -f /etc/haproxy/haproxy.cfg" ;;
        php*-fpm)
            local _pf=""
            _pf=$(command -v "$svc" 2>/dev/null || command -v php-fpm 2>/dev/null)
            [ -n "$_pf" ] && _cmd="$_pf -t"
            ;;
    esac
    [ -z "$_cmd" ] && return 0
    printf '\033[1;36m[문법 사전 검증] %s ...\033[0m\n' "$_cmd"
    if eval "$_cmd"; then
        printf '\033[1;32m✔ 문법 검증 통과!\033[0m\n'
        return 0
    else
        printf '\033[1;31m✖ 문법 오류가 감지되었습니다! 안전을 위해 재시작을 차단합니다.\033[0m\n'
        return 1
    fi
}

# 서비스 목록 로드 (초기 스냅샷 옵션: $1=1 이면 초기값도 저장)
_dm_load_services() {
    local save_init="${1:-0}"
    _DM_NAMES=()
    _DM_BOOT=()
    _DM_RUN=()
    _DM_DESC=()
    _DM_RISK=()
    if [ "$save_init" = "1" ]; then
        _DM_INIT_BOOT=()
        _DM_INIT_RUN=()
    fi

    local _tmp_list
    _tmp_list=$(mktemp /tmp/go_dm.XXXXXX 2>/dev/null || echo "/tmp/go_dm_$$")

    if [ "$_DM_INIT" = "systemd" ]; then
        local _tmp_u
        _tmp_u=$(mktemp /tmp/go_dmu.XXXXXX 2>/dev/null || echo "/tmp/go_dmu_$$")
        systemctl list-units --type=service --all --no-legend --no-pager 2>/dev/null >"$_tmp_u"
        systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null | awk -v uf="$_tmp_u" '
            BEGIN {
                while ((getline line < uf) > 0) {
                    sub(/^[[:space:]●*]+/, "", line)
                    n = split(line, a, /[[:space:]]+/)
                    if (n >= 4) {
                        nm = a[1]
                        sub(/\.service$/, "", nm)
                        run[nm] = a[3]
                        # 설명 추출 (5번째 필드부터 끝까지)
                        desc = ""
                        for (i = 5; i <= n; i++) desc = desc (i > 5 ? " " : "") a[i]
                        sdesc[nm] = desc
                    }
                }
                close(uf)
            }
            {
                nm = $1
                if (nm == "" || index(nm, "@.service") > 0) next
                sub(/\.service$/, "", nm)
                st = $2
                if (st != "enabled" && st != "disabled" && st != "static" && st != "masked" && st != "indirect" && st != "enabled-runtime") next
                r = (nm in run) ? run[nm] : "inactive"
                d = (nm in sdesc) ? sdesc[nm] : ""
                if (!(nm in seen)) {
                    seen[nm] = 1
                    printf "%s\t%s\t%s\t%s\n", nm, st, r, d
                }
            }
        ' | sort -t$'\t' -k1,1 >"$_tmp_list"
        rm -f "$_tmp_u"
    elif [ "$_DM_INIT" = "sysv_rh" ]; then
        LC_ALL=C chkconfig --list 2>/dev/null | awk -v rl="$_DM_RUNLEVEL" '
            /^[A-Za-z0-9._-]+/ && index($0, rl":") > 0 {
                nm = $1
                st = "disabled"
                for (i = 2; i <= NF; i++) {
                    if ($i == rl":on") { st = "enabled"; break }
                }
                printf "%s\t%s\t%s\t\n", nm, st, "unknown"
            }
        ' | sort -t$'\t' -k1,1 >"$_tmp_list"
    elif [ "$_DM_INIT" = "sysv_deb" ]; then
        local _f _nm _st
        for _f in /etc/init.d/*; do
            [ -f "$_f" ] && [ -x "$_f" ] || continue
            _nm="${_f##*/}"
            case "$_nm" in
                README|skeleton|rc|rcS|functions|*.dpkg-*|*.sh|halt|reboot|single|killprocs|sendsigs|umount*) continue ;;
            esac
            if ls /etc/rc"${_DM_RUNLEVEL}".d/S*"${_nm}" >/dev/null 2>&1; then
                _st="enabled"
            else
                _st="disabled"
            fi
            printf '%s\t%s\tunknown\t\n' "$_nm" "$_st"
        done | sort -t$'\t' -k1,1 >"$_tmp_list"
    fi

    local _nm _bt _rn _ds _bd _idx=0
    while IFS=$'\t' read -r _nm _bt _rn _ds; do
        [ -z "$_nm" ] && continue
        # SysVinit 초고속 실행상태 추정 (pid / lock)
        if [ "$_rn" = "unknown" ]; then
            if [ -f "/var/lock/subsys/$_nm" ] || ls /var/run/"$_nm"*.pid /run/"$_nm"*.pid >/dev/null 2>&1; then
                _rn="active"
            else
                _rn="inactive"
            fi
        fi
        _bd=$(_dm_builtin_desc "$_nm")
        [ -n "$_bd" ] && _ds="$_bd"
        _dm_risk_info "$_nm"
        _DM_NAMES[$_idx]="$_nm"
        _DM_BOOT[$_idx]="$_bt"
        _DM_RUN[$_idx]="$_rn"
        _DM_DESC[$_idx]="$_ds"
        _DM_RISK[$_idx]="$_DM_R_LVL"
        if [ "$save_init" = "1" ]; then
            _DM_INIT_BOOT[$_idx]="$_bt"
            _DM_INIT_RUN[$_idx]="$_rn"
        fi
        _idx=$((_idx + 1))
    done <"$_tmp_list"
    rm -f "$_tmp_list"
    _DM_TOTAL=$_idx
}

# 단일 서비스 상태 실시간 갱신 (배열 인덱스 $1)
_dm_refresh_one() {
    local idx="$1"
    local svc="${_DM_NAMES[$idx]}"
    if [ "$_DM_INIT" = "systemd" ]; then
        local _bt _rn
        _bt=$(systemctl is-enabled "${svc}.service" 2>/dev/null | head -n1)
        [ -z "$_bt" ] && _bt="static"
        _rn=$(systemctl is-active "${svc}.service" 2>/dev/null | head -n1)
        [ -z "$_rn" ] && _rn="inactive"
        _DM_BOOT[$idx]="$_bt"
        _DM_RUN[$idx]="$_rn"
    elif [ "$_DM_INIT" = "sysv_rh" ]; then
        if LC_ALL=C chkconfig --list "$svc" 2>/dev/null | grep -q "${_DM_RUNLEVEL}:on"; then
            _DM_BOOT[$idx]="enabled"
        else
            _DM_BOOT[$idx]="disabled"
        fi
        if service "$svc" status >/dev/null 2>&1; then
            _DM_RUN[$idx]="active"
        else
            _DM_RUN[$idx]="inactive"
        fi
    elif [ "$_DM_INIT" = "sysv_deb" ]; then
        if ls /etc/rc"${_DM_RUNLEVEL}".d/S*"${svc}" >/dev/null 2>&1; then
            _DM_BOOT[$idx]="enabled"
        else
            _DM_BOOT[$idx]="disabled"
        fi
        if service "$svc" status >/dev/null 2>&1; then
            _DM_RUN[$idx]="active"
        else
            _DM_RUN[$idx]="inactive"
        fi
    fi
}

# 실제 데몬 액션 실행 (enable|disable|start|stop|restart)
_dm_exec_action() {
    local svc="$1" act="$2"
    if [ "$_DM_INIT" = "systemd" ]; then
        systemctl "$act" "${svc}.service" 2>&1
        return $?
    elif [ "$_DM_INIT" = "sysv_rh" ]; then
        case "$act" in
            enable)  chkconfig "$svc" on 2>&1 ;;
            disable) chkconfig "$svc" off 2>&1 ;;
            start|stop|restart) service "$svc" "$act" 2>&1 ;;
        esac
        return $?
    elif [ "$_DM_INIT" = "sysv_deb" ]; then
        case "$act" in
            enable)  update-rc.d "$svc" enable 2>&1 || update-rc.d "$svc" defaults 2>&1 ;;
            disable) update-rc.d "$svc" disable 2>&1 ;;
            start|stop|restart) service "$svc" "$act" 2>&1 || "/etc/init.d/$svc" "$act" 2>&1 ;;
        esac
        return $?
    fi
    return 1
}

# 안전 가드 확인 (CRIT = Proxmox 파쇄식 명령어 재입력, WARN = y/N)
# 반환: 0=허용, 1=취소/차단
_dm_guard_confirm() {
    local svc="$1" act="$2"
    # enable / start 는 안전한 방향 -> 즉시 허용
    case "$act" in
        enable|start) return 0 ;;
    esac

    _dm_risk_info "$svc"
    if [ "$_DM_R_LVL" = "OK" ]; then
        return 0
    fi

    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\n'
    if [ "$_DM_R_LVL" = "CRIT" ]; then
        # restart 의 경우 SSH/네트워크도 끊김 위험 경고 + 문법검증 후 확인
        local _phrase="${act} ${svc}"
        _dm_p '\033[1;41;37m ⛔ [치명적 데몬 보호] %s (%s) \033[0m\n' "$svc" "$act"
        _dm_p '\033[1;31m  ⚠ 경고: %s\033[0m\n' "$_DM_R_MSG"
        _dm_p '\033[1;33m  ▶ 정말 실행하려면 아래 문구를 정확히 입력하세요 (취소: Enter):\033[0m\n'
        _dm_p '    확인 문구: \033[1;37m%s\033[0m\n' "$_phrase"
        _dm_p '    입력 >>> '
        local _typed=""
        IFS= read -r _typed </dev/tty
        if [ "$_typed" = "$_phrase" ]; then
            return 0
        fi
        _dm_p '\033[1;32m  🛡 취소되었습니다. (%s 보호됨)\033[0m\n' "$svc"
        sleep 1
        return 1
    elif [ "$_DM_R_LVL" = "WARN" ]; then
        _dm_p '\033[1;33m ⚠ [주의 데몬] %s -> %s\033[0m\n' "$svc" "$act"
        _dm_p '   %s\n' "$_DM_R_MSG"
        _dm_p '   계속 진행할까요? [y/N]: '
        local _ans=""
        IFS= read -r _ans </dev/tty
        case "$_ans" in
            y|Y|yes|YES) return 0 ;;
            *) return 1 ;;
        esac
    fi
    return 0
}

# 위험 데몬용 Dead-Man's Switch (윈도우 모니터 확인창 방식 자동 원복 타이머)
# - SSH/네트워크/방화벽/Proxmox 등 원격 끊김 가능 작업 시 백그라운드 워치독(SIGHUP 면역) 가동
# - 20초 안에 [y] 확정하지 않거나 SSH 세션이 끊기면 자동으로 직전 상태(및 설정 파일)로 원복!
# 인자: $1=svc  $2=act(disable|stop|restart)  $3=orig_cfg(옵션)  $4=bak_cfg(옵션)
_dm_need_deadman() {
    local svc="$1" act="$2"
    case "$act" in
        disable|stop|restart) ;;
        *) return 1 ;;
    esac
    _dm_risk_info "$svc"
    [ "$_DM_R_LVL" = "CRIT" ] && return 0
    case "$svc" in
        firewalld|ufw|iptables|ip6tables|nftables) return 0 ;;
    esac
    return 1
}

_dm_deadman_run() {
    local svc="$1" act="$2" orig_cfg="${3:-}" bak_cfg="${4:-}"
    local _flag="/tmp/go_dm_confirm_$$"
    local _wait_sec=20
    local _wd_sec=25

    # 원복 명령 조립 (init 시스템별)
    local _rev_cmd=""
    if [ -n "$orig_cfg" ] && [ -n "$bak_cfg" ] && [ -f "$bak_cfg" ]; then
        _rev_cmd="cp -f '$bak_cfg' '$orig_cfg' 2>/dev/null; "
    fi
    if [ "$_DM_INIT" = "systemd" ]; then
        case "$act" in
            disable) _rev_cmd="${_rev_cmd}systemctl enable '${svc}.service' >/dev/null 2>&1" ;;
            stop)    _rev_cmd="${_rev_cmd}systemctl start '${svc}.service' >/dev/null 2>&1" ;;
            restart) _rev_cmd="${_rev_cmd}systemctl restart '${svc}.service' >/dev/null 2>&1" ;;
        esac
    elif [ "$_DM_INIT" = "sysv_rh" ]; then
        case "$act" in
            disable) _rev_cmd="${_rev_cmd}chkconfig '${svc}' on >/dev/null 2>&1" ;;
            stop)    _rev_cmd="${_rev_cmd}service '${svc}' start >/dev/null 2>&1" ;;
            restart) _rev_cmd="${_rev_cmd}service '${svc}' restart >/dev/null 2>&1" ;;
        esac
    elif [ "$_DM_INIT" = "sysv_deb" ]; then
        case "$act" in
            disable) _rev_cmd="${_rev_cmd}update-rc.d '${svc}' enable >/dev/null 2>&1" ;;
            stop)    _rev_cmd="${_rev_cmd}service '${svc}' start >/dev/null 2>&1 || '/etc/init.d/${svc}' start >/dev/null 2>&1" ;;
            restart) _rev_cmd="${_rev_cmd}service '${svc}' restart >/dev/null 2>&1 || '/etc/init.d/${svc}' restart >/dev/null 2>&1" ;;
        esac
    fi

    touch "$_flag"
    # SIGHUP 면역 독립 백그라운드 워치독: SSH 세션이 끊겨도 _wd_sec 후 자동 원복!
    (
        trap '' HUP INT TERM
        sleep "$_wd_sec"
        if [ -f "$_flag" ]; then
            eval "$_rev_cmd"
            rm -f "$_flag"
        fi
        [ -n "$bak_cfg" ] && rm -f "$bak_cfg" 2>/dev/null
    ) </dev/null >/dev/null 2>&1 &
    local _wd_pid=$!

    # 실제 액션 실행
    local _out _rc
    _out=$(_dm_exec_action "$svc" "$act")
    _rc=$?
    if [ $_rc -ne 0 ]; then
        rm -f "$_flag"
        kill "$_wd_pid" 2>/dev/null
        [ -n "$bak_cfg" ] && rm -f "$bak_cfg" 2>/dev/null
        _DM_MSG="✖ ${svc} ${act} 실패: $(printf '%s' "$_out" | head -n1)"
        return $_rc
    fi

    # 카운트다운 확인 (윈도우 모니터 해상도 확인창 스타일)
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    _dm_p '\n\033[1;43;30m ⏱ [자동 원복 보호 작동] %s (%s) 적용됨 \033[0m\n' "$svc" "$act"
    _dm_p '   세션이 정상이면 \033[1;32m[y]\033[0m 를 눌러 확정하세요. (무응답/끊김/[n] 시 자동 원복)\n'

    local _left=$_wait_sec _ans="" _confirmed=0
    while [ "$_left" -gt 0 ]; do
        _dm_p '\r   남은 시간: \033[1;33m%2d초\033[0m — 유지(확정)할까요? [y=확정 / n=즉시원복] : ' "$_left"
        _ans=""
        if IFS= read -rsn1 -t 1 _ans </dev/tty 2>/dev/null; then
            case "$_ans" in
                y|Y)
                    _confirmed=1
                    break
                    ;;
                n|N|$'\033')
                    _confirmed=2
                    break
                    ;;
            esac
        fi
        _left=$((_left - 1))
    done
    printf '\n'

    if [ "$_confirmed" -eq 1 ]; then
        rm -f "$_flag"
        kill "$_wd_pid" 2>/dev/null
        [ -n "$bak_cfg" ] && rm -f "$bak_cfg" 2>/dev/null
        _DM_MSG="✔ ${svc} (${act}) 변경 확정 완료! (자동 원복 타이머 해제)"
        return 0
    else
        # 시간 초과 또는 n 입력 -> 즉시 원복 수행
        rm -f "$_flag"
        kill "$_wd_pid" 2>/dev/null
        eval "$_rev_cmd"
        [ -n "$bak_cfg" ] && rm -f "$bak_cfg" 2>/dev/null
        if [ "$_confirmed" -eq 2 ]; then
            _DM_MSG="🛡 사용자 취소 — ${svc} 이전 상태로 즉시 원복 완료!"
        else
            _DM_MSG="⏱ 확인 시간 초과 — ${svc} 이전 상태로 자동 원복 완료!"
        fi
        return 1
    fi
}

# 변경된 데몬 수 계산
_dm_count_changed() {
    local i=0 c=0
    while [ "$i" -lt "$_DM_TOTAL" ]; do
        if [ "${_DM_BOOT[$i]}" != "${_DM_INIT_BOOT[$i]}" ] || [ "${_DM_RUN[$i]}" != "${_DM_INIT_RUN[$i]}" ]; then
            c=$((c + 1))
        fi
        i=$((i + 1))
    done
    echo "$c"
}

# 개별 원복 (배열 인덱스 $1)
_dm_undo_one() {
    local idx="$1"
    local svc="${_DM_NAMES[$idx]}"
    local ib="${_DM_INIT_BOOT[$idx]}" ir="${_DM_INIT_RUN[$idx]}"
    local cb="${_DM_BOOT[$idx]}" cr="${_DM_RUN[$idx]}"
    local did=0

    if [ "$cb" != "$ib" ]; then
        if [ "$ib" = "enabled" ]; then
            _dm_exec_action "$svc" enable >/dev/null
            did=1
        elif [ "$ib" = "disabled" ]; then
            _dm_exec_action "$svc" disable >/dev/null
            did=1
        fi
    fi
    if [ "$cr" != "$ir" ]; then
        if [ "$ir" = "active" ]; then
            _dm_exec_action "$svc" start >/dev/null
            did=1
        elif [ "$ir" = "inactive" ]; then
            _dm_exec_action "$svc" stop >/dev/null
            did=1
        fi
    fi
    _dm_refresh_one "$idx"
    return $did
}

# 전체 원복 (진입 시점 스냅샷으로 일괄 복원)
_dm_undo_all() {
    local chg
    chg=$(_dm_count_changed)
    if [ "$chg" -eq 0 ]; then
        _DM_MSG="변경된 데몬이 없습니다."
        return 0
    fi
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\n\033[1;33m[전체 원복] 진입 시점 초기 상태로 되돌릴 데몬 (%s건):\033[0m\n' "$chg"
    local i=0
    while [ "$i" -lt "$_DM_TOTAL" ]; do
        if [ "${_DM_BOOT[$i]}" != "${_DM_INIT_BOOT[$i]}" ] || [ "${_DM_RUN[$i]}" != "${_DM_INIT_RUN[$i]}" ]; then
            printf '  • %-22s boot: %s -> %s | run: %s -> %s\n' \
                "${_DM_NAMES[$i]}" "${_DM_BOOT[$i]}" "${_DM_INIT_BOOT[$i]}" "${_DM_RUN[$i]}" "${_DM_INIT_RUN[$i]}"
        fi
        i=$((i + 1))
    done
    printf '\n위 %s건을 모두 초기 상태로 원복할까요? [y/N]: ' "$chg"
    local _ans=""
    IFS= read -r _ans </dev/tty
    case "$_ans" in
        y|Y|yes|YES)
            i=0
            while [ "$i" -lt "$_DM_TOTAL" ]; do
                if [ "${_DM_BOOT[$i]}" != "${_DM_INIT_BOOT[$i]}" ] || [ "${_DM_RUN[$i]}" != "${_DM_INIT_RUN[$i]}" ]; then
                    _dm_undo_one "$i"
                fi
                i=$((i + 1))
            done
            _DM_MSG="✔ ${chg}건 모두 진입 시점 초기 상태로 원복 완료!"
            return 0
            ;;
        *)
            _DM_MSG="전체 원복을 취소했습니다."
            return 1
            ;;
    esac
}

# 필터링된 인덱스 목록 구성
_dm_build_view() {
    _DM_VIEW=()
    local i=0 v=0 nm bt rn
    local q_low
    q_low=$(printf '%s' "$_DM_SEARCH" | tr 'A-Z' 'a-z')
    while [ "$i" -lt "$_DM_TOTAL" ]; do
        nm="${_DM_NAMES[$i]}"
        bt="${_DM_BOOT[$i]}"
        rn="${_DM_RUN[$i]}"
        case "$_DM_FILTER" in
            enabled)  [ "$bt" != "enabled" ] && { i=$((i + 1)); continue; } ;;
            running)  [ "$rn" != "active" ] && { i=$((i + 1)); continue; } ;;
            major)    _dm_is_major "$nm" || { i=$((i + 1)); continue; } ;;
            changed)
                if [ "$bt" = "${_DM_INIT_BOOT[$i]}" ] && [ "$rn" = "${_DM_INIT_RUN[$i]}" ]; then
                    i=$((i + 1)); continue
                fi ;;
        esac
        if [ -n "$q_low" ]; then
            local nm_low ds_low
            nm_low=$(printf '%s' "$nm" | tr 'A-Z' 'a-z')
            ds_low=$(printf '%s' "${_DM_DESC[$i]}" | tr 'A-Z' 'a-z')
            case "$nm_low $ds_low" in
                *"$q_low"*) ;;
                *) i=$((i + 1)); continue ;;
            esac
        fi
        _DM_VIEW[$v]="$i"
        v=$((v + 1))
        i=$((i + 1))
    done
    _DM_VCNT=$v
    [ "$_DM_CUR" -ge "$_DM_VCNT" ] && _DM_CUR=$((_DM_VCNT - 1))
    [ "$_DM_CUR" -lt 0 ] && _DM_CUR=0
    [ "$_DM_TOP" -gt "$_DM_CUR" ] && _DM_TOP=$_DM_CUR
}

# 실효 환경 파일 선택 후 vi2 편집 -> 수정 감지 시 문법검사 후 재시작 제안
_dm_edit_config() {
    local idx="$1"
    local svc="${_DM_NAMES[$idx]}"
    local cfg_list
    cfg_list=$(_dm_find_configs "$svc")
    if [ -z "$cfg_list" ]; then
        _DM_MSG="⚠ '${svc}' 의 실효 설정 파일을 찾지 못했습니다."
        return 1
    fi

    tput cnorm 2>/dev/null
    stty echo 2>/dev/null

    local _arr=() _n=0 _line=""
    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _arr[$_n]="$_line"
        _n=$((_n + 1))
    done <<EOF
$cfg_list
EOF

    local target=""
    if [ "$_n" -eq 1 ]; then
        target="${_arr[0]}"
    else
        printf '\033[2J\033[H'
        _dm_p '\033[1;36m* [%s] 실효 환경 파일 선택 (vi2 로 백업 후 편집)\033[0m\n' "$svc"
        printf '%s\n' "--------------------------------------------------------------------"
        local k=0
        while [ "$k" -lt "$_n" ]; do
            printf '  \033[1;33m%2d.\033[0m %s\n' "$((k + 1))" "${_arr[$k]}"
            k=$((k + 1))
        done
        _dm_p '  \033[0;37m 0.\033[0m 취소\n'
        printf '%s\n' "--------------------------------------------------------------------"
        _dm_p '편집할 파일 번호 [1-%s, 0=취소] (기본 1): ' "$_n"
        local _sel=""
        IFS= read -r _sel </dev/tty
        [ -z "$_sel" ] && _sel="1"
        if [ "$_sel" = "0" ] || [ "$_sel" = "q" ]; then
            _DM_MSG="편집 취소"
            return 0
        fi
        case "$_sel" in
            [0-9]*)
                if [ "$_sel" -ge 1 ] && [ "$_sel" -le "$_n" ]; then
                    target="${_arr[$((_sel - 1))]}"
                else
                    _DM_MSG="잘못된 번호입니다."
                    return 1
                fi
                ;;
            *) _DM_MSG="편집 취소"; return 0 ;;
        esac
    fi

    local before_ck after_ck _tmp_bak=""
    before_ck=$(cksum "$target" 2>/dev/null)
    _tmp_bak=$(mktemp /tmp/go_dm_bak.XXXXXX 2>/dev/null || echo "/tmp/go_dm_bak_$$")
    cp -a "$target" "$_tmp_bak" 2>/dev/null
    vi2 "$target"
    after_ck=$(cksum "$target" 2>/dev/null)

    if [ "$before_ck" != "$after_ck" ]; then
        printf '\n\033[1;33m📝 [%s] 설정 파일이 변경되었습니다: %s\033[0m\n' "$svc" "$target"
        if ! _dm_config_test "$svc"; then
            printf '다시 vi2로 수정할까요? [Y/n]: '
            local _re=""
            IFS= read -r _re </dev/tty
            case "$_re" in
                n|N) rm -f "$_tmp_bak" 2>/dev/null; _DM_MSG="⚠ 문법 오류 상태로 저장됨 (재시작 안 함): $target" ;;
                *)   vi2 "$target"; rm -f "$_tmp_bak" 2>/dev/null; _DM_MSG="재편집 완료: $target" ;;
            esac
            return 0
        fi
        printf '변경 사항을 적용하기 위해 [%s] 데몬을 재시작(restart) 할까요? [y/N]: ' "$svc"
        local _ans=""
        IFS= read -r _ans </dev/tty
        case "$_ans" in
            y|Y|yes|YES)
                if [ "$_DM_INIT" = "systemd" ]; then
                    case "$target" in
                        /etc/systemd/*|/lib/systemd/*|/usr/lib/systemd/*)
                            systemctl daemon-reload 2>/dev/null ;;
                    esac
                fi
                if _dm_need_deadman "$svc" restart; then
                    _dm_deadman_run "$svc" restart "$target" "$_tmp_bak"
                    _dm_refresh_one "$idx"
                else
                    rm -f "$_tmp_bak" 2>/dev/null
                    local _out
                    _out=$(_dm_exec_action "$svc" restart)
                    local _rc=$?
                    _dm_refresh_one "$idx"
                    if [ $_rc -eq 0 ]; then
                        _DM_MSG="✔ ${svc} 설정 반영 및 재시작 완료!"
                    else
                        _DM_MSG="✖ ${svc} 재시작 실패: $(printf '%s' "$_out" | head -n1)"
                    fi
                fi
                ;;
            *) rm -f "$_tmp_bak" 2>/dev/null; _DM_MSG="✔ 설정 저장 완료 (재시작 안 함): $target" ;;
        esac
    else
        rm -f "$_tmp_bak" 2>/dev/null
        _DM_MSG="변경 없음: $target"
    fi
}

# 상태/로그 상세 보기 (i 키)
_dm_show_status() {
    local idx="$1"
    local svc="${_DM_NAMES[$idx]}"
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    if [ "$_DM_INIT" = "systemd" ]; then
        {
            printf '=== systemctl status %s.service ===\n' "$svc"
            systemctl status --no-pager -l "${svc}.service" 2>&1
            printf '\n=== 최근 저널 로그 (journalctl -n 30) ===\n'
            journalctl -u "${svc}.service" -n 30 --no-pager 2>&1
        } | less -RX
    else
        {
            printf '=== service %s status ===\n' "$svc"
            service "$svc" status 2>&1 || "/etc/init.d/$svc" status 2>&1
        } | less -RX
    fi
    _dm_refresh_one "$idx"
}

# 화면 레이아웃/기호 캐시 (진입 시 1회 & 창 크기 변경 시에만 갱신)
_dm_init_layout() {
    local _TS_LINES="" _TS_COLS=""
    _get_term_size
    _DM_ROWS=$_TS_LINES
    _DM_COLS=$_TS_COLS
    _DM_PAGE_H=$((_DM_ROWS - 10))
    [ "$_DM_PAGE_H" -lt 5 ] && _DM_PAGE_H=5
    local _w=$((_DM_COLS > 110 ? 110 : _DM_COLS - 1))
    _DM_HLINE=$(printf '%*s' "$_w" '' | tr ' ' '-')
    if [ "$_DM_ENC" = "euckr" ]; then
        _DM_S_CUR=">"; _DM_S_ACT="*"; _DM_S_FAIL="!"; _DM_S_OFF="."; _DM_S_INFO="[i]"; _DM_S_BUL="-"; _DM_S_DASH="-"
    else
        _DM_S_CUR="▶"; _DM_S_ACT="●"; _DM_S_FAIL="✖"; _DM_S_OFF="○"; _DM_S_INFO="🔍"; _DM_S_BUL="•"; _DM_S_DASH="—"
    fi
    _DM_DIRTY=1
}

# 단일 목록 줄 렌더링 (끝에 \033[K 로 줄 잔상만 제거 -> 깜빡임 0%)
_dm_render_row() {
    local vidx="$1" is_cur="$2"
    local idx="${_DM_VIEW[$vidx]}"
    local nm="${_DM_NAMES[$idx]}" bt="${_DM_BOOT[$idx]}" rn="${_DM_RUN[$idx]}"
    local ds="${_DM_DESC[$idx]}" rk="${_DM_RISK[$idx]}"
    local b_tag r_col r_sym rk_tag mod_mk

    if [ "$_DM_ENC" = "euckr" ]; then
        case "$bt" in
            enabled|enabled-runtime) b_tag=$'\033[1;32m[*]\033[0m' ;;
            disabled)                b_tag=$'\033[0;37m[ ]\033[0m' ;;
            masked)                  b_tag=$'\033[0;31m[x]\033[0m' ;;
            *)                       b_tag=$'\033[1;30m[-]\033[0m' ;;
        esac
    else
        case "$bt" in
            enabled|enabled-runtime) b_tag=$'\033[1;32m[✓]\033[0m' ;;
            disabled)                b_tag=$'\033[0;37m[ ]\033[0m' ;;
            masked)                  b_tag=$'\033[0;31m[✕]\033[0m' ;;
            *)                       b_tag=$'\033[1;30m[-]\033[0m' ;;
        esac
    fi

    case "$rn" in
        active) r_col=$'\033[1;32m'; r_sym="$_DM_S_ACT" ;;
        failed) r_col=$'\033[1;31m'; r_sym="$_DM_S_FAIL" ;;
        *)      r_col=$'\033[0;37m'; r_sym="$_DM_S_OFF" ;;
    esac

    case "$rk" in
        CRIT) rk_tag=$'\033[1;31m[잠금]\033[0m' ;;
        WARN) rk_tag=$'\033[1;33m[주의]\033[0m' ;;
        *)    rk_tag="      " ;;
    esac

    if [ "$bt" != "${_DM_INIT_BOOT[$idx]}" ] || [ "$rn" != "${_DM_INIT_RUN[$idx]}" ]; then
        mod_mk=$'\033[1;33m*\033[0m'
    else
        mod_mk=" "
    fi

    local max_d=$((_DM_COLS - 54))
    [ "$max_d" -lt 16 ] && max_d=16
    case "$ds" in
        *[![:print:]]*) ;;
        *) [ "${#ds}" -gt "$max_d" ] && ds="${ds:0:$((max_d - 2))}.." ;;
    esac

    if [ "$is_cur" = "1" ]; then
        printf '\033[1;33m%s\033[0m%s %s %s%s\033[0m \033[7m %-24.24s \033[0m %-8.8s %s %s\033[K\n' \
            "$_DM_S_CUR" "$mod_mk" "$b_tag" "$r_col" "$r_sym" "$nm" "$rn" "$rk_tag" "$ds"
    else
        printf ' %s %s %s%s\033[0m  %-24.24s  %-8.8s %s %s\033[K\n' \
            "$mod_mk" "$b_tag" "$r_col" "$r_sym" "$nm" "$rn" "$rk_tag" "$ds"
    fi
}

# 하단 상세 카드 + 상태바 렌더링
_dm_render_footer() {
    printf '\033[0;34m%s\033[0m\033[K\n' "$_DM_HLINE"
    if [ "$_DM_VCNT" -gt 0 ]; then
        local cidx="${_DM_VIEW[$_DM_CUR]}"
        local cnm="${_DM_NAMES[$cidx]}"
        local cds="${_DM_DESC[$cidx]}"
        [ -z "$cds" ] && cds="(설명 없음)"
        _dm_risk_info "$cnm"
        printf '\033[1;36m%s %s\033[0m %s %s\033[K\n' "$_DM_S_INFO" "$cnm" "$_DM_S_DASH" "$cds"
        printf '   %s 상태: 부팅=\033[1;37m%s\033[0m (초기:%s) | 실행=\033[1;37m%s\033[0m (초기:%s)' \
            "$_DM_S_BUL" "${_DM_BOOT[$cidx]}" "${_DM_INIT_BOOT[$cidx]}" "${_DM_RUN[$cidx]}" "${_DM_INIT_RUN[$cidx]}"
        [ "$_DM_R_LVL" = "CRIT" ] && printf '  \033[1;31m[원격/시스템 보호됨]\033[0m'
        [ "$_DM_R_LVL" = "WARN" ] && printf '  \033[1;33m[주요서비스 주의]\033[0m'
        printf '\033[K\n'
        local _first_cfg="${_DM_CFG_CACHE[$cidx]}"
        [ -z "$_first_cfg" ] && _first_cfg="(탐지된 설정 파일 없음)"
        printf '   %s 설정: \033[0;32m%s\033[0m\033[K\n' "$_DM_S_BUL" "$_first_cfg"
    else
        printf '\033[K\n\033[K\n\033[K\n'
    fi
    printf '\033[0;34m%s\033[0m\033[K\n' "$_DM_HLINE"
    if [ -n "$_DM_MSG" ]; then
        printf '\033[1;33m %s\033[0m\033[K' "$_DM_MSG"
    else
        if [ "$_DM_ENC" = "euckr" ]; then
            printf ' \033[0;37m[Up/Dn]이동 [Lt/Rt/PgUpDn]페이지 [Space]토글 [e/Enter]설정vi2 [s]시작 [x]중지 [r]재시작 [i]로그 [/]검색 [f]필터 [u/U]원복 [q]종료\033[0m\033[K'
        else
            printf ' \033[0;37m[↑↓]이동 [←→/PgUpDn]페이지 [Space]토글 [e/Enter]설정vi2 [s]시작 [x]중지 [r]재시작 [i]로그 [/]검색 [f]필터 [u/U]원복 [q]종료\033[0m\033[K'
        fi
    fi
}

# 전체 페이지 렌더링 (제자리 덮어쓰기: \033[H + 줄별 \033[K -> 무깜빡임)
_dm_render_full_body() {
    local list_h=$_DM_PAGE_H
    local cur_pg=1 tot_pg=1
    if [ "$_DM_VCNT" -gt 0 ]; then
        cur_pg=$(( (_DM_TOP / list_h) + 1 ))
        tot_pg=$(( ((_DM_VCNT - 1) / list_h) + 1 ))
    fi
    local flabel="전체"
    case "$_DM_FILTER" in
        enabled) flabel="부팅활성" ;;
        running) flabel="실행중" ;;
        major)   flabel="주요서버" ;;
        changed) flabel="변경됨" ;;
    esac

    printf '\033[H'
    printf '\033[1;36m* 통합 서버 데몬 관리 [dms]\033[0m  \033[0;37mOS: %s (%s)\033[0m  필터:\033[1;33m%s\033[0m (%d/%d)  \033[1;37mP.%d/%d\033[0m' \
        "$_DM_OS" "$_DM_INIT" "$flabel" "$_DM_VCNT" "$_DM_TOTAL" "$cur_pg" "$tot_pg"
    [ -n "$_DM_SEARCH" ] && printf '  검색:\033[1;35m/%s\033[0m' "$_DM_SEARCH"
    [ "${_DM_CHG_CNT:-0}" -gt 0 ] && printf '  \033[1;33m[변경:%d건 u/U원복]\033[0m' "$_DM_CHG_CNT"
    printf '\033[K\n\033[0;34m%s\033[0m\033[K\n' "$_DM_HLINE"

    local r=0 vidx
    if [ "$_DM_VCNT" -eq 0 ]; then
        printf '\033[K\n  (조건에 맞는 데몬이 없습니다. / 로 검색어를 지우거나 f 로 필터를 바꾸세요)\033[K\n'
        r=2
        while [ "$r" -lt "$list_h" ]; do
            printf '\033[K\n'
            r=$((r + 1))
        done
    else
        while [ "$r" -lt "$list_h" ]; do
            vidx=$((_DM_TOP + r))
            [ "$vidx" -ge "$_DM_VCNT" ] && break
            if [ "$vidx" -eq "$_DM_CUR" ]; then
                _dm_render_row "$vidx" 1
            else
                _dm_render_row "$vidx" 0
            fi
            r=$((r + 1))
        done
        while [ "$r" -lt "$list_h" ]; do
            printf '\033[K\n'
            r=$((r + 1))
        done
    fi
    _dm_render_footer
    printf '\033[J'
}

# 같은 페이지 내 초고속 부분(델타) 렌더링 (이전 커서 1줄 + 새 커서 1줄 + 하단 카드만 갱신)
_dm_render_delta_body() {
    local old_row=$((3 + _DM_LAST_CUR - _DM_TOP))
    local new_row=$((3 + _DM_CUR - _DM_TOP))
    local foot_row=$((3 + _DM_PAGE_H))
    printf '\033[%d;1H' "$old_row"
    _dm_render_row "$_DM_LAST_CUR" 0
    printf '\033[%d;1H' "$new_row"
    _dm_render_row "$_DM_CUR" 1
    printf '\033[%d;1H' "$foot_row"
    _dm_render_footer
}

_dm_render() {
    # 커서 범위 & 페이지 경계 정렬 + 커서 항목 캐시 보충 (부모 셸에서 실행)
    if [ "$_DM_VCNT" -gt 0 ]; then
        [ "$_DM_CUR" -lt 0 ] && _DM_CUR=0
        [ "$_DM_CUR" -ge "$_DM_VCNT" ] && _DM_CUR=$((_DM_VCNT - 1))
        _DM_TOP=$(( (_DM_CUR / _DM_PAGE_H) * _DM_PAGE_H ))
        local _cidx="${_DM_VIEW[$_DM_CUR]}"
        if [ -z "${_DM_DESC[$_cidx]}" ]; then
            local _cds
            _cds=$(_dm_fetch_sys_desc "${_DM_NAMES[$_cidx]}")
            [ -n "$_cds" ] && _DM_DESC[$_cidx]="$_cds" || _DM_DESC[$_cidx]=" "
        fi
        if [ -z "${_DM_CFG_CACHE[$_cidx]}" ]; then
            local _fc
            _fc=$(_dm_find_configs "${_DM_NAMES[$_cidx]}" | head -n 2 | tr '\n' ' ')
            [ -n "$_fc" ] && _DM_CFG_CACHE[$_cidx]="$_fc" || _DM_CFG_CACHE[$_cidx]="(탐지된 설정 파일 없음)"
        fi
    else
        _DM_TOP=0
    fi

    # 같은 페이지 안에서 커서만 이동했고, 이전 메시지도 없으면 초고속 델타 렌더링!
    if [ "${_DM_DIRTY:-1}" = "0" ] && [ "$_DM_VCNT" -gt 0 ] \
       && [ "$_DM_TOP" = "${_DM_LAST_TOP:--1}" ] && [ "${_DM_LAST_CUR:--1}" -ge 0 ] \
       && [ "$_DM_LAST_CUR" -lt "$_DM_VCNT" ] && [ -z "$_DM_MSG" ] && [ -z "${_DM_LAST_MSG:-}" ]; then
        if [ "$_DM_CUR" != "$_DM_LAST_CUR" ]; then
            if [ "$_DM_ENC" = "euckr" ]; then
                _dm_render_delta_body | _dm_iconv_euckr
            else
                _dm_render_delta_body
            fi
        fi
    else
        _DM_CHG_CNT=$(_dm_count_changed)
        if [ "$_DM_ENC" = "euckr" ]; then
            _dm_render_full_body | _dm_iconv_euckr
        else
            _dm_render_full_body
        fi
        _DM_DIRTY=0
    fi
    _DM_LAST_CUR=$_DM_CUR
    _DM_LAST_TOP=$_DM_TOP
    _DM_LAST_MSG="$_DM_MSG"
}

# 메인 진입 함수: dms [초기검색어]
dms() {
    _dm_detect_env
    if [ "$_DM_INIT" = "unknown" ]; then
        _dm_p '❌ 지원하는 init 시스템(systemd / chkconfig / init.d)을 찾지 못했습니다.\n'
        return 1
    fi

    _DM_SEARCH="${1:-}"
    _DM_FILTER="all"
    _DM_CUR=0
    _DM_TOP=0
    _DM_MSG=""
    _DM_LAST_CUR=-1
    _DM_LAST_TOP=-1
    _DM_LAST_MSG=""
    _DM_CHG_CNT=0
    _DM_CFG_CACHE=()

    _dm_p '\033[1;36m[dms] %s (%s) 서비스 목록 및 초기 스냅샷 로딩 중...\033[0m\n' "$_DM_OS" "$_DM_INIT"
    _dm_load_services 1
    _dm_build_view
    _dm_init_layout

    local _esc_t=1
    [ "${BASH_VERSINFO[0]:-0}" -ge 4 ] && _esc_t=0.25

    local _old_trap
    _old_trap=$(trap -p INT)
    trap 'tput cnorm 2>/dev/null; stty sane 2>/dev/null; printf "\n"; return 0' INT
    trap '_dm_init_layout' WINCH 2>/dev/null

    printf '\033[2J\033[H'
    tput civis 2>/dev/null
    while :; do
        _dm_render
        _DM_MSG=""

        local _k="" _x="" _x2=""
        IFS= read -rsn1 _k </dev/tty 2>/dev/null || break

        if [ "$_k" = $'\033' ]; then
            IFS= read -rsn1 -t "$_esc_t" _x </dev/tty 2>/dev/null
            if [ -z "$_x" ] || [ "$_x" = $'\033' ]; then
                _k="q"
            elif [ "$_x" = "[" ] || [ "$_x" = "O" ]; then
                IFS= read -rsn1 -t "$_esc_t" _x </dev/tty 2>/dev/null
                case "$_x" in
                    A) [ "$_DM_CUR" -gt 0 ] && _DM_CUR=$((_DM_CUR - 1)); continue ;;
                    B) [ "$_DM_CUR" -lt $((_DM_VCNT - 1)) ] && _DM_CUR=$((_DM_CUR + 1)); continue ;;
                    D) # ← 이전 페이지 (중복 없이 한 페이지 단위)
                       local _ph="${_DM_PAGE_H:-10}"
                       if [ "$_DM_TOP" -gt 0 ]; then
                           _DM_TOP=$((_DM_TOP - _ph))
                           [ "$_DM_TOP" -lt 0 ] && _DM_TOP=0
                           _DM_CUR=$_DM_TOP
                       else
                           _DM_CUR=0
                       fi
                       continue ;;
                    C) # → 다음 페이지 (중복 없이 한 페이지 단위)
                       local _ph="${_DM_PAGE_H:-10}"
                       local _nt=$((_DM_TOP + _ph))
                       if [ "$_nt" -lt "$_DM_VCNT" ]; then
                           _DM_TOP=$_nt
                           _DM_CUR=$_DM_TOP
                       elif [ "$_DM_VCNT" -gt 0 ]; then
                           _DM_CUR=$((_DM_VCNT - 1))
                       fi
                       continue ;;
                    5) IFS= read -rsn1 -t "$_esc_t" _x2 </dev/tty 2>/dev/null
                       local _ph="${_DM_PAGE_H:-10}"
                       if [ "$_DM_TOP" -gt 0 ]; then
                           _DM_TOP=$((_DM_TOP - _ph))
                           [ "$_DM_TOP" -lt 0 ] && _DM_TOP=0
                           _DM_CUR=$_DM_TOP
                       else
                           _DM_CUR=0
                       fi
                       continue ;;
                    6) IFS= read -rsn1 -t "$_esc_t" _x2 </dev/tty 2>/dev/null
                       local _ph="${_DM_PAGE_H:-10}"
                       local _nt=$((_DM_TOP + _ph))
                       if [ "$_nt" -lt "$_DM_VCNT" ]; then
                           _DM_TOP=$_nt
                           _DM_CUR=$_DM_TOP
                       elif [ "$_DM_VCNT" -gt 0 ]; then
                           _DM_CUR=$((_DM_VCNT - 1))
                       fi
                       continue ;;
                esac
                continue
            else
                continue
            fi
        fi

        case "$_k" in
            q|Q)
                local _chg
                _chg=$(_dm_count_changed)
                if [ "$_chg" -gt 0 ]; then
                    tput cnorm 2>/dev/null
                    stty echo 2>/dev/null
                    _dm_p '\n\033[1;33m⚠ 진입 시점 대비 변경된 데몬이 %d건 있습니다.\033[0m\n' "$_chg"
                    _dm_p '  [Enter] 그대로 종료  |  [u] 전체 원복 후 종료  |  [c] 돌아가기 : '
                    local _qans=""
                    IFS= read -r _qans </dev/tty
                    case "$_qans" in
                        u|U) _dm_undo_all && break ;;
                        c|C) _DM_DIRTY=1; tput civis 2>/dev/null; continue ;;
                        *)   break ;;
                    esac
                else
                    break
                fi
                ;;
            k) [ "$_DM_CUR" -gt 0 ] && _DM_CUR=$((_DM_CUR - 1)) ;;
            j) [ "$_DM_CUR" -lt $((_DM_VCNT - 1)) ] && _DM_CUR=$((_DM_CUR + 1)) ;;
            " ")
                [ "$_DM_VCNT" -eq 0 ] && continue
                local _idx="${_DM_VIEW[$_DM_CUR]}"
                local _svc="${_DM_NAMES[$_idx]}"
                local _bt="${_DM_BOOT[$_idx]}"
                local _act=""
                if [ "$_bt" = "enabled" ] || [ "$_bt" = "enabled-runtime" ]; then
                    _act="disable"
                elif [ "$_bt" = "disabled" ]; then
                    _act="enable"
                else
                    _DM_MSG="ℹ '${_svc}' 는 '${_bt}' 상태라 부팅 토글 대상이 아닙니다."
                    continue
                fi
                if _dm_guard_confirm "$_svc" "$_act"; then
                    if _dm_need_deadman "$_svc" "$_act"; then
                        _dm_deadman_run "$_svc" "$_act"
                        _dm_refresh_one "$_idx"
                    else
                        local _out
                        _out=$(_dm_exec_action "$_svc" "$_act")
                        local _rc=$?
                        _dm_refresh_one "$_idx"
                        if [ $_rc -eq 0 ]; then
                            _DM_MSG="✔ ${_svc} -> ${_act} 완료 (현재: ${_DM_BOOT[$_idx]})"
                        else
                            _DM_MSG="✖ ${_svc} ${_act} 실패: $(printf '%s' "$_out" | head -n1)"
                        fi
                    fi
                fi
                _DM_DIRTY=1; tput civis 2>/dev/null
                ;;
            ""|e|E)
                [ "$_DM_VCNT" -eq 0 ] && continue
                _dm_edit_config "${_DM_VIEW[$_DM_CUR]}"
                _DM_DIRTY=1; tput civis 2>/dev/null
                ;;
            s|S)
                [ "$_DM_VCNT" -eq 0 ] && continue
                local _idx="${_DM_VIEW[$_DM_CUR]}" _svc="${_DM_NAMES[$_idx]}" _out
                _out=$(_dm_exec_action "$_svc" start)
                local _rc=$?
                _dm_refresh_one "$_idx"
                [ $_rc -eq 0 ] && _DM_MSG="✔ ${_svc} 시작(start) 완료" || _DM_MSG="✖ ${_svc} 시작 실패: $(printf '%s' "$_out" | head -n1)"
                _DM_DIRTY=1
                ;;
            x|X)
                [ "$_DM_VCNT" -eq 0 ] && continue
                local _idx="${_DM_VIEW[$_DM_CUR]}" _svc="${_DM_NAMES[$_idx]}"
                if _dm_guard_confirm "$_svc" stop; then
                    if _dm_need_deadman "$_svc" stop; then
                        _dm_deadman_run "$_svc" stop
                        _dm_refresh_one "$_idx"
                    else
                        local _out
                        _out=$(_dm_exec_action "$_svc" stop)
                        local _rc=$?
                        _dm_refresh_one "$_idx"
                        [ $_rc -eq 0 ] && _DM_MSG="✔ ${_svc} 중지(stop) 완료" || _DM_MSG="✖ ${_svc} 중지 실패: $(printf '%s' "$_out" | head -n1)"
                    fi
                fi
                _DM_DIRTY=1; tput civis 2>/dev/null
                ;;
            r|R)
                [ "$_DM_VCNT" -eq 0 ] && continue
                local _idx="${_DM_VIEW[$_DM_CUR]}" _svc="${_DM_NAMES[$_idx]}"
                # 재시작 전 설정 문법 자동 검증 (오타 시 차단)
                tput cnorm 2>/dev/null
                stty echo 2>/dev/null
                if ! _dm_config_test "$_svc"; then
                    printf '아무 키나 누르면 돌아갑니다...'
                    IFS= read -rsn1 _ </dev/tty 2>/dev/null
                    _DM_MSG="✖ ${_svc} 문법 오류로 재시작 차단됨"
                    _DM_DIRTY=1; tput civis 2>/dev/null
                    continue
                fi
                if _dm_guard_confirm "$_svc" restart; then
                    if _dm_need_deadman "$_svc" restart; then
                        _dm_deadman_run "$_svc" restart
                        _dm_refresh_one "$_idx"
                    else
                        local _out
                        _out=$(_dm_exec_action "$_svc" restart)
                        local _rc=$?
                        _dm_refresh_one "$_idx"
                        [ $_rc -eq 0 ] && _DM_MSG="✔ ${_svc} 재시작(restart) 완료" || _DM_MSG="✖ ${_svc} 재시작 실패: $(printf '%s' "$_out" | head -n1)"
                    fi
                fi
                _DM_DIRTY=1; tput civis 2>/dev/null
                ;;
            i|I|l|L)
                [ "$_DM_VCNT" -eq 0 ] && continue
                _dm_show_status "${_DM_VIEW[$_DM_CUR]}"
                _DM_DIRTY=1; tput civis 2>/dev/null
                ;;
            /)
                tput cnorm 2>/dev/null
                stty echo 2>/dev/null
                _dm_p '\n검색 키워드 (빈 값=초기화): '
                IFS= read -r _DM_SEARCH </dev/tty
                _DM_CUR=0; _DM_TOP=0
                _dm_build_view
                _DM_DIRTY=1; tput civis 2>/dev/null
                ;;
            f|F)
                case "$_DM_FILTER" in
                    all)     _DM_FILTER="major" ;;
                    major)   _DM_FILTER="enabled" ;;
                    enabled) _DM_FILTER="running" ;;
                    running) _DM_FILTER="changed" ;;
                    *)       _DM_FILTER="all" ;;
                esac
                _DM_CUR=0; _DM_TOP=0
                _dm_build_view
                _DM_DIRTY=1
                ;;
            u)
                [ "$_DM_VCNT" -eq 0 ] && continue
                local _idx="${_DM_VIEW[$_DM_CUR]}" _svc="${_DM_NAMES[$_idx]}"
                if [ "${_DM_BOOT[$_idx]}" = "${_DM_INIT_BOOT[$_idx]}" ] && [ "${_DM_RUN[$_idx]}" = "${_DM_INIT_RUN[$_idx]}" ]; then
                    _DM_MSG="ℹ '${_svc}' 는 초기 상태와 동일합니다."
                else
                    _dm_undo_one "$_idx"
                    _DM_MSG="✔ '${_svc}' 진입 시점 초기 상태로 원복 완료!"
                fi
                _DM_DIRTY=1
                ;;
            U)
                _dm_undo_all
                _DM_DIRTY=1; tput civis 2>/dev/null
                ;;
        esac
    done

    tput cnorm 2>/dev/null
    stty sane 2>/dev/null
    [ -n "$_old_trap" ] && eval "$_old_trap" || trap - INT
    printf '\n'
}


# ==============================================================================
# 통합 서버 패키지 관리 TUI: pms (Package Manager Studio)
# - 모든 리눅스/유닉스 배포판 자동 대응:
#   dnf / yum / apt / apt-get / pacman / apk / zypper / pkg / rpm / dpkg / pkginfo
# - 기능: 설치됨 탐색 / 업데이트 조회·개별·전체 업그레이드 / 원격 저장소 검색·설치 /
#         삭제(핵심 OS 패키지 보호 가드) / 파일목록 / 명령어·경로 역검색(whatprovides) /
#         소스 레포지토리 관리(목록·활성토글·vi2편집·주요레포추가·캐시갱신·explorer)
# - Bash 2.x/3.x/4.x/5.x 및 EUC-KR 구서버 완벽 호환 (연관배열 미사용, 무깜빡임 델타 렌더링)
# ==============================================================================

_pm_detect_env() {
    _PM_OS="Linux"
    _PM_MGR="unknown"
    _PM_LOW="unknown"
    _PM_REPO_DIR=""
    _PM_ENC="utf8"

    if [ -f /etc/os-release ]; then
        _PM_OS=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null)
    elif [ -f /etc/redhat-release ]; then
        _PM_OS=$(head -n1 /etc/redhat-release 2>/dev/null)
    elif [ -f /etc/debian_version ]; then
        _PM_OS="Debian $(cat /etc/debian_version 2>/dev/null)"
    else
        _PM_OS=$(uname -s 2>/dev/null)
    fi
    [ -z "$_PM_OS" ] && _PM_OS="Linux"

    # 터미널 인코딩 판별 (EUC-KR 구서버 한글 보호)
    local _loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    case "$_loc" in
        *[Ee][Uu][Cc]*[Kk][Rr]*|*[Kk][Oo]_[Kk][Rr]|ko)
            if command -v iconv >/dev/null 2>&1; then
                _PM_ENC="euckr"
            fi ;;
    esac

    # 상위 패키지 매니저 자동 탐지
    if command -v dnf >/dev/null 2>&1; then
        _PM_MGR="dnf"; _PM_LOW="rpm"; _PM_REPO_DIR="/etc/yum.repos.d"
    elif command -v yum >/dev/null 2>&1; then
        _PM_MGR="yum"; _PM_LOW="rpm"; _PM_REPO_DIR="/etc/yum.repos.d"
    elif command -v apt >/dev/null 2>&1; then
        _PM_MGR="apt"; _PM_LOW="dpkg"; _PM_REPO_DIR="/etc/apt"
    elif command -v apt-get >/dev/null 2>&1; then
        _PM_MGR="apt-get"; _PM_LOW="dpkg"; _PM_REPO_DIR="/etc/apt"
    elif command -v pacman >/dev/null 2>&1; then
        _PM_MGR="pacman"; _PM_LOW="pacman"; _PM_REPO_DIR="/etc/pacman.d"
    elif command -v apk >/dev/null 2>&1; then
        _PM_MGR="apk"; _PM_LOW="apk"; _PM_REPO_DIR="/etc/apk"
    elif command -v zypper >/dev/null 2>&1; then
        _PM_MGR="zypper"; _PM_LOW="rpm"; _PM_REPO_DIR="/etc/zypp/repos.d"
    elif command -v pkg >/dev/null 2>&1; then
        _PM_MGR="pkg"; _PM_LOW="pkg"
        [ -d /usr/local/etc/pkg/repos ] && _PM_REPO_DIR="/usr/local/etc/pkg/repos" || _PM_REPO_DIR="/etc/pkg"
    elif command -v rpm >/dev/null 2>&1; then
        _PM_MGR="rpm"; _PM_LOW="rpm"; _PM_REPO_DIR="/etc/yum.repos.d"
    elif command -v dpkg >/dev/null 2>&1; then
        _PM_MGR="dpkg"; _PM_LOW="dpkg"; _PM_REPO_DIR="/etc/apt"
    elif command -v pkginfo >/dev/null 2>&1; then
        _PM_MGR="pkginfo"; _PM_LOW="pkginfo"
    fi
}

_pm_p() {
    local _fmt="$1"
    shift
    if [ "$_PM_ENC" = "euckr" ]; then
        printf "$_fmt" "$@" | _dm_iconv_euckr
    else
        printf "$_fmt" "$@"
    fi
}

# 핵심 시스템 패키지 보호 판별 (삭제 시 이중 안전 확인)
_pm_is_critical() {
    case "$1" in
        glibc|glibc-*|libc6|libc-bin|bash|coreutils|systemd|systemd-*|init|initscripts|sysvinit*|\
        openssh|openssh-*|ssh|sshd|dropbear|kernel|kernel-*|linux-image*|grub|grub2*|grub-*|\
        yum|yum-*|dnf|dnf-*|rpm|rpm-*|apt|apt-*|dpkg|dpkg-*|pacman|apk-tools|zypper|\
        sudo|passwd|shadow*|pam|libpam*|openssl|openssl-*|util-linux|procps*|iproute*|net-tools|\
        network*|NetworkManager|e2fsprogs|xfsprogs|lvm2|udev|dbus)
            return 0 ;;
    esac
    return 1
}

# 주요 서버/인프라 패키지 필터 판별 (f 키 '주요서버' 모드용)
_pm_is_major() {
    case "$1" in
        httpd*|apache2*|nginx*|php*|mariadb*|mysql*|postgresql*|mongodb*|redis*|memcached*|\
        named*|bind*|postfix*|sendmail*|exim*|dovecot*|vsftpd*|proftpd*|pure-ftpd*|\
        openssh*|ssh|dropbear|fail2ban*|firewalld*|ufw|iptables*|nftables*|\
        docker*|containerd*|podman*|haproxy*|keepalived*|certbot*|acme*|openssl*|\
        samba*|nfs*|cron*|at|rsyslog*|chrony*|ntp*|screen|tmux|vim*|git|curl|wget|python3*|\
        node*|npm|go|golang*|java*|jdk*|pve-*|proxmox*|tailscale*|wireguard*|openvpn*)
            return 0 ;;
    esac
    return 1
}

# 데이터 초기화
_pm_clear_data() {
    _PM_NAMES=()
    _PM_VERS=()
    _PM_DESCS=()
    _PM_STATES=()
    _PM_META=()
    _PM_TOTAL=0
}

# EUC-KR 환경에서 외부 영문/특수문자 안전화
_pm_safe_str() {
    if [ "$_PM_ENC" = "euckr" ]; then
        printf '%s' "$1" | LC_ALL=C tr -cd '\40-\176'
    else
        printf '%s' "$1"
    fi
}

# 1) 설치된 패키지 목록 로드
_pm_load_installed() {
    _pm_clear_data
    local _tmp="/tmp/go_pm_inst_$$"
    rm -f "$_tmp"

    case "$_PM_LOW" in
        rpm)
            LC_ALL=C rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{SUMMARY}\n' 2>/dev/null \
                | sort -u -t $'\t' -k1,1 >"$_tmp"
            ;;
        dpkg)
            LC_ALL=C dpkg-query -W -f='${Status}\t${Package}\t${Version}\t${binary:Summary}\n' 2>/dev/null \
                | awk -F'\t' '$1 ~ /install ok installed/ {print $2"\t"$3"\t"$4}' \
                | sort -u -t $'\t' -k1,1 >"$_tmp"
            ;;
        pacman)
            LC_ALL=C pacman -Q 2>/dev/null \
                | awk '{print $1"\t"$2"\t"}' | sort -u >"$_tmp"
            ;;
        apk)
            LC_ALL=C apk list --installed 2>/dev/null \
                | awk '{
                    pkg=$1; sub(/-[0-9].*/,"",pkg);
                    ver=$1; sub(/^[^0-9]*/,"",ver);
                    desc=""; for(i=4;i<=NF;i++) desc=desc (i>4?" ":"") $i;
                    print pkg"\t"ver"\t"desc
                }' | sort -u >"$_tmp"
            if [ ! -s "$_tmp" ]; then
                LC_ALL=C apk info -v 2>/dev/null | awk '{print $1"\tinstalled\t"}' | sort -u >"$_tmp"
            fi
            ;;
        pkg)
            LC_ALL=C pkg info 2>/dev/null \
                | awk '{
                    nm=$1; ver=$1;
                    if (match(nm, /-[0-9]/)) { ver=substr(nm, RSTART+1); nm=substr(nm, 1, RSTART-1); }
                    desc=""; for(i=2;i<=NF;i++) desc=desc (i>2?" ":"") $i;
                    print nm"\t"ver"\t"desc
                }' | sort -u >"$_tmp"
            ;;
        pkginfo)
            LC_ALL=C pkginfo 2>/dev/null \
                | awk '{nm=$2; desc=""; for(i=3;i<=NF;i++) desc=desc (i>3?" ":"") $i; print nm"\t-\t"desc}' \
                | sort -u >"$_tmp"
            ;;
    esac

    local i=0 _nm _vr _ds
    while IFS=$'\t' read -r _nm _vr _ds; do
        [ -n "$_nm" ] || continue
        _PM_NAMES[$i]="$_nm"
        _PM_VERS[$i]="${_vr:--}"
        _PM_DESCS[$i]="$_ds"
        _PM_STATES[$i]="installed"
        _PM_META[$i]=""
        i=$((i + 1))
    done <"$_tmp"
    rm -f "$_tmp"
    _PM_TOTAL=$i
}

# 2) 업데이트 가능 패키지 목록 로드
_pm_load_updates() {
    _pm_clear_data
    local _tmp="/tmp/go_pm_upd_$$"
    rm -f "$_tmp"

    case "$_PM_MGR" in
        dnf|yum)
            LC_ALL=C "$_PM_MGR" check-update -q 2>/dev/null \
                | awk 'NF>=3 && $1 !~ /^(Obsoleting|Security|Last|Loaded|Skipping|\*)/ && $1 ~ /\./ {
                    nm=$1; sub(/\.[^.]+$/,"",nm);
                    print nm"\t"$2"\t[Repo: "$3"]"
                }' | sort -u >"$_tmp"
            ;;
        apt|apt-get)
            if command -v apt >/dev/null 2>&1; then
                LC_ALL=C apt list --upgradable 2>/dev/null \
                    | awk -F'/' 'NR>1 && NF>=2 {
                        nm=$1; rest=$2;
                        split(rest, a, " ");
                        ver=a[2];
                        desc=rest;
                        print nm"\t"ver"\t"desc
                    }' | sort -u >"$_tmp"
            else
                LC_ALL=C apt-get -s upgrade 2>/dev/null \
                    | awk '/^Inst / {print $2"\t"$4"\t"$3" -> "$4}' | sort -u >"$_tmp"
            fi
            ;;
        pacman)
            LC_ALL=C pacman -Qu 2>/dev/null \
                | awk '{print $1"\t"$4"\t"$2" -> "$4}' | sort -u >"$_tmp"
            ;;
        apk)
            LC_ALL=C apk list --upgradable 2>/dev/null \
                | awk '{print $1"\t"$2"\t"$0}' | sort -u >"$_tmp"
            ;;
        zypper)
            LC_ALL=C zypper -q lu 2>/dev/null \
                | awk -F'|' 'NF>=5 && $1 ~ /^v/ {
                    gsub(/^[ \t]+|[ \t]+$/,"",$3);
                    gsub(/^[ \t]+|[ \t]+$/,"",$4);
                    gsub(/^[ \t]+|[ \t]+$/,"",$5);
                    print $3"\t"$5"\t"$4" -> "$5
                }' | sort -u >"$_tmp"
            ;;
        pkg)
            LC_ALL=C pkg version -l '<' 2>/dev/null \
                | awk '{print $1"\tupdate\t"$0}' | sort -u >"$_tmp"
            ;;
    esac

    local i=0 _nm _vr _ds
    if [ -f "$_tmp" ]; then
        while IFS=$'\t' read -r _nm _vr _ds; do
            [ -n "$_nm" ] || continue
            _PM_NAMES[$i]="$_nm"
            _PM_VERS[$i]="${_vr:-update}"
            _PM_DESCS[$i]="$_ds"
            _PM_STATES[$i]="upgradable"
            _PM_META[$i]=""
            i=$((i + 1))
        done <"$_tmp"
        rm -f "$_tmp"
    fi
    _PM_TOTAL=$i
}

# 3) 원격 저장소 패키지 검색
_pm_load_search() {
    local kw="$1"
    _pm_clear_data
    [ -z "$kw" ] && return 0
    local _tmp="/tmp/go_pm_srch_$$"
    rm -f "$_tmp"

    case "$_PM_MGR" in
        dnf|yum)
            LC_ALL=C "$_PM_MGR" search "$kw" 2>/dev/null \
                | awk -F' : ' 'NF>=2 && $1 !~ /^(=|Last|Loaded|Matched|Name)/ {
                    nm=$1; gsub(/^[ \t]+|[ \t]+$/,"",nm);
                    arch="";
                    if (match(nm, /\.[^.]+$/)) { arch=substr(nm, RSTART+1); nm=substr(nm, 1, RSTART-1); }
                    ds=$2; gsub(/^[ \t]+|[ \t]+$/,"",ds);
                    if (nm != "") print nm"\t"arch"\t"ds
                }' | sort -u -t $'\t' -k1,1 >"$_tmp"
            ;;
        apt|apt-get)
            LC_ALL=C apt-cache search "$kw" 2>/dev/null \
                | awk -F' - ' 'NF>=2 {print $1"\tremote\t"$2}' \
                | head -n 400 >"$_tmp"
            ;;
        pacman)
            LC_ALL=C pacman -Ss "$kw" 2>/dev/null \
                | awk '
                    /^[^ \t]/ {
                        split($1, a, "/"); nm=a[2]; ver=$2;
                        getline ds; gsub(/^[ \t]+/,"",ds);
                        print nm"\t"ver"\t"ds
                    }' | head -n 400 >"$_tmp"
            ;;
        apk)
            LC_ALL=C apk search -v "$kw" 2>/dev/null \
                | awk -F' - ' '{
                    nm=$1; ver="remote";
                    if (match(nm, /-[0-9]/)) { ver=substr(nm, RSTART+1); nm=substr(nm, 1, RSTART-1); }
                    print nm"\t"ver"\t"$2
                }' | head -n 400 >"$_tmp"
            ;;
        zypper)
            LC_ALL=C zypper -q se "$kw" 2>/dev/null \
                | awk -F'|' 'NF>=4 && $2 !~ /Name/ && $2 !~ /^--/ {
                    gsub(/^[ \t]+|[ \t]+$/,"",$2);
                    gsub(/^[ \t]+|[ \t]+$/,"",$3);
                    gsub(/^[ \t]+|[ \t]+$/,"",$4);
                    if ($2 != "") print $2"\t"$4"\t"$3
                }' | head -n 400 >"$_tmp"
            ;;
        pkg)
            LC_ALL=C pkg search "$kw" 2>/dev/null \
                | awk '{nm=$1; desc=""; for(i=2;i<=NF;i++) desc=desc (i>2?" ":"") $i; print nm"\tremote\t"desc}' \
                | head -n 400 >"$_tmp"
            ;;
        *)
            # rpm/dpkg 단독 구서버는 설치된 패키지 내에서 검색 폴백
            _pm_load_installed
            return 0
            ;;
    esac

    local i=0 _nm _vr _ds
    if [ -f "$_tmp" ]; then
        while IFS=$'\t' read -r _nm _vr _ds; do
            [ -n "$_nm" ] || continue
            _PM_NAMES[$i]="$_nm"
            _PM_VERS[$i]="${_vr:-remote}"
            _PM_DESCS[$i]="$_ds"
            _PM_STATES[$i]="remote"
            _PM_META[$i]=""
            i=$((i + 1))
        done <"$_tmp"
        rm -f "$_tmp"
    fi
    _PM_TOTAL=$i
}

# 4) 소스 레포지토리 목록 로드 (모든 배포판 대응)
# _PM_NAMES=레포ID/라벨, _PM_VERS=파일명, _PM_DESCS=설명/URL, _PM_STATES=enabled|disabled, _PM_META=전체파일경로|줄번호
_pm_load_repos() {
    _pm_clear_data
    local _tmp="/tmp/go_pm_repo_$$"
    rm -f "$_tmp"

    case "$_PM_MGR" in
        dnf|yum|zypper|rpm)
            local _rdir="/etc/yum.repos.d"
            [ "$_PM_MGR" = "zypper" ] && _rdir="/etc/zypp/repos.d"
            if [ -d "$_rdir" ]; then
                local _rf
                for _rf in "$_rdir"/*.repo "$_rdir"/*.repo.disabled; do
                    [ -f "$_rf" ] || continue
                    local _bn
                    _bn=$(basename "$_rf")
                    awk -v fpath="$_rf" -v bname="$_bn" '
                        function flush_repo() {
                            if (rid != "") {
                                st = (en == "0" || fpath ~ /\.disabled$/) ? "disabled" : "enabled";
                                info = (rname != "" ? rname : rurl);
                                if (info == "") info = bname;
                                print rid "\t" bname "\t" info "\t" st "\t" fpath;
                            }
                        }
                        /^[ \t]*\[[^]]+\]/ {
                            flush_repo();
                            rid=$0; gsub(/^[ \t]*\[|\][ \t]*$/, "", rid);
                            rname=""; rurl=""; en="1";
                            next;
                        }
                        /^[ \t]*name[ \t]*=/ { sub(/^[ \t]*name[ \t]*=[ \t]*/,""); rname=$0; next }
                        /^[ \t]*enabled[ \t]*=/ { sub(/^[ \t]*enabled[ \t]*=[ \t]*/,""); gsub(/[ \t].*/,""); en=$0; next }
                        /^[ \t]*(baseurl|mirrorlist|metalink)[ \t]*=/ {
                            if (rurl == "") { sub(/^[ \t]*[^=]*=[ \t]*/,""); rurl=$0; }
                            next;
                        }
                        END { flush_repo(); }
                    ' "$_rf" >>"$_tmp"
                done
            fi
            ;;
        apt|apt-get|dpkg)
            local _af
            for _af in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.list.disabled /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.sources.disabled; do
                [ -f "$_af" ] || continue
                local _bn
                _bn=$(basename "$_af")
                case "$_af" in
                    *.sources|*.sources.disabled)
                        local _st="enabled"
                        case "$_af" in *.disabled) _st="disabled" ;; esac
                        grep -qiE '^[[:space:]]*Enabled:[[:space:]]*no' "$_af" 2>/dev/null && _st="disabled"
                        local _uri
                        _uri=$(awk '/^URIs:/{$1=""; sub(/^[ \t]+/,""); print; exit}' "$_af" 2>/dev/null)
                        local _su
                        _su=$(awk '/^Suites:/{$1=""; sub(/^[ \t]+/,""); print; exit}' "$_af" 2>/dev/null)
                        printf '%s\t%s\t%s (%s)\t%s\t%s\n' "${_bn%.sources*}" "$_bn" "${_uri:-deb822}" "${_su:--}" "$_st" "$_af" >>"$_tmp"
                        ;;
                    *)
                        # .list 파일: deb / # deb 라인 파싱
                        awk -v fpath="$_af" -v bname="$_bn" '
                            /^[ \t]*#?[ \t]*deb(-src)?[ \t]+/ {
                                line=$0;
                                st = (line ~ /^[ \t]*#/ || fpath ~ /\.disabled$/) ? "disabled" : "enabled";
                                clean=line; sub(/^[ \t]*#[ \t]*/,"",clean);
                                # URL 및 suite 추출
                                split(clean, a, /[ \t]+/);
                                typ=a[1];
                                idx=2;
                                if (a[2] ~ /^\[/) {
                                    # [arch=amd64 ...] 스킵
                                    while (idx <= length(a) && a[idx] !~ /\]$/) idx++;
                                    idx++;
                                }
                                url=a[idx]; suite=a[idx+1];
                                rid=typ ":" suite;
                                if (rid == ":") rid=bname;
                                print rid "\t" bname ":" NR "\t" clean "\t" st "\t" fpath "|" NR;
                            }
                        ' "$_af" >>"$_tmp"
                        ;;
                esac
            done
            ;;
        pacman)
            if [ -f /etc/pacman.conf ]; then
                awk '
                    /^[ \t]*#?\[[^]]+\]/ {
                        raw=$0;
                        st = (raw ~ /^[ \t]*#/) ? "disabled" : "enabled";
                        rid=raw; gsub(/^[ \t]*#?\[|\][ \t]*$/,"",rid);
                        if (rid != "options") {
                            print rid "\tpacman.conf:" NR "\t[" rid "] repository\t" st "\t/etc/pacman.conf|" NR;
                        }
                    }
                ' /etc/pacman.conf >>"$_tmp"
            fi
            [ -f /etc/pacman.d/mirrorlist ] && printf 'mirrorlist\tmirrorlist\t/etc/pacman.d/mirrorlist\tenabled\t/etc/pacman.d/mirrorlist\n' >>"$_tmp"
            ;;
        apk)
            if [ -f /etc/apk/repositories ]; then
                awk '
                    /^[ \t]*#?[ \t]*(https?:|\/)/ {
                        st = ($0 ~ /^[ \t]*#/) ? "disabled" : "enabled";
                        clean=$0; sub(/^[ \t]*#[ \t]*/,"",clean);
                        print "repo#" NR "\trepositories:" NR "\t" clean "\t" st "\t/etc/apk/repositories|" NR;
                    }
                ' /etc/apk/repositories >>"$_tmp"
            fi
            ;;
        pkg)
            local _pf
            for _pf in /etc/pkg/*.conf /usr/local/etc/pkg/repos/*.conf; do
                [ -f "$_pf" ] || continue
                local _bn
                _bn=$(basename "$_pf")
                local _st="enabled"
                grep -qiE 'enabled[[:space:]]*:[[:space:]]*(no|false)' "$_pf" 2>/dev/null && _st="disabled"
                local _u
                _u=$(grep -iE 'url[[:space:]]*:' "$_pf" 2>/dev/null | head -n1 | sed 's/^[ \t]*//')
                printf '%s\t%s\t%s\t%s\t%s\n' "${_bn%.conf}" "$_bn" "${_u:-$_pf}" "$_st" "$_pf" >>"$_tmp"
            done
            ;;
    esac

    local i=0 _nm _vr _ds _st _mt
    if [ -f "$_tmp" ]; then
        while IFS=$'\t' read -r _nm _vr _ds _st _mt; do
            [ -n "$_nm" ] || continue
            _PM_NAMES[$i]="$_nm"
            _PM_VERS[$i]="$_vr"
            _PM_DESCS[$i]="$_ds"
            _PM_STATES[$i]="${_st:-enabled}"
            _PM_META[$i]="$_mt"
            i=$((i + 1))
        done <"$_tmp"
        rm -f "$_tmp"
    fi
    _PM_TOTAL=$i
}

# 필터 및 검색 적용 뷰 생성
_pm_build_view() {
    _PM_VIEW=()
    local i=0 v=0 nm ds st
    local q_low
    q_low=$(printf '%s' "$_PM_SEARCH" | tr 'A-Z' 'a-z')

    while [ "$i" -lt "$_PM_TOTAL" ]; do
        nm="${_PM_NAMES[$i]}"
        ds="${_PM_DESCS[$i]}"
        st="${_PM_STATES[$i]}"

        if [ "$_PM_MODE" = "installed" ] && [ "$_PM_FILTER" = "major" ]; then
            _pm_is_major "$nm" || { i=$((i + 1)); continue; }
        elif [ "$_PM_MODE" = "repos" ]; then
            if [ "$_PM_FILTER" = "enabled" ] && [ "$st" != "enabled" ]; then
                i=$((i + 1)); continue
            elif [ "$_PM_FILTER" = "disabled" ] && [ "$st" != "disabled" ]; then
                i=$((i + 1)); continue
            fi
        fi

        if [ -n "$q_low" ]; then
            local nm_low ds_low
            nm_low=$(printf '%s' "$nm" | tr 'A-Z' 'a-z')
            ds_low=$(printf '%s' "$ds" | tr 'A-Z' 'a-z')
            case "$nm_low $ds_low" in
                *"$q_low"*) ;;
                *) i=$((i + 1)); continue ;;
            esac
        fi

        _PM_VIEW[$v]="$i"
        v=$((v + 1))
        i=$((i + 1))
    done
    _PM_VCNT=$v
    [ "$_PM_CUR" -ge "$_PM_VCNT" ] && _PM_CUR=$((_PM_VCNT - 1))
    [ "$_PM_CUR" -lt 0 ] && _PM_CUR=0
    [ "$_PM_TOP" -gt "$_PM_CUR" ] && _PM_TOP=$_PM_CUR
}

# 레포 활성/비활성 토글 (Space)
_pm_toggle_repo() {
    local idx="$1"
    local rid="${_PM_NAMES[$idx]}"
    local st="${_PM_STATES[$idx]}"
    local mt="${_PM_META[$idx]}"
    local fpath="${mt%%|*}"
    local lno=""
    case "$mt" in
        *\|*) lno="${mt#*|}" ;;
    esac

    [ -f "$fpath" ] || { _PM_MSG="⚠ 설정 파일을 찾을 수 없습니다: $fpath"; return 1; }

    local _bak="${fpath}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$fpath" "$_bak" 2>/dev/null

    case "$_PM_MGR" in
        dnf|yum|zypper|rpm)
            local _new_val="0" _new_st="disabled"
            [ "$st" = "disabled" ] && { _new_val="1"; _new_st="enabled"; }
            case "$fpath" in
                *.disabled)
                    local _un="${fpath%.disabled}"
                    mv -f "$fpath" "$_un" 2>/dev/null && fpath="$_un"
                    ;;
            esac
            awk -v target="$rid" -v nval="$_new_val" '
                BEGIN { in_sec=0; done_en=0 }
                /^[ \t]*\[[^]]+\]/ {
                    if (in_sec && !done_en) { print "enabled=" nval; done_en=1 }
                    sec=$0; gsub(/^[ \t]*\[|\][ \t]*$/, "", sec);
                    in_sec = (sec == target) ? 1 : 0;
                    print; next;
                }
                in_sec && /^[ \t]*enabled[ \t]*=/ {
                    print "enabled=" nval; done_en=1; next;
                }
                { print }
                END { if (in_sec && !done_en) print "enabled=" nval }
            ' "$fpath" >"${fpath}.pms_tmp" && mv -f "${fpath}.pms_tmp" "$fpath"
            rm -f "$_bak" 2>/dev/null
            _PM_MSG="✔ 레포 [${rid}] -> ${_new_st} 전환 완료! (c 키로 캐시 갱신 권장)"
            ;;
        apt|apt-get|dpkg)
            if [ -n "$lno" ]; then
                if [ "$st" = "enabled" ]; then
                    awk -v ln="$lno" 'NR==ln { print "# " $0; next } { print }' "$fpath" >"${fpath}.pms_tmp" \
                        && mv -f "${fpath}.pms_tmp" "$fpath"
                    _PM_MSG="✔ 레포 [${rid}] 비활성화(주석) 완료! (c 키로 apt update 권장)"
                else
                    awk -v ln="$lno" 'NR==ln { sub(/^[ \t]*#[ \t]*/,""); print; next } { print }' "$fpath" >"${fpath}.pms_tmp" \
                        && mv -f "${fpath}.pms_tmp" "$fpath"
                    _PM_MSG="✔ 레포 [${rid}] 활성화 완료! (c 키로 apt update 권장)"
                fi
                rm -f "$_bak" 2>/dev/null
            else
                # deb822 .sources 파일
                if [ "$st" = "enabled" ]; then
                    mv -f "$fpath" "${fpath}.disabled" 2>/dev/null
                    _PM_MSG="✔ ${rid} 비활성화 (.disabled) 완료! (c 키로 apt update 권장)"
                else
                    mv -f "$fpath" "${fpath%.disabled}" 2>/dev/null
                    _PM_MSG="✔ ${rid} 활성화 완료! (c 키로 apt update 권장)"
                fi
                rm -f "$_bak" 2>/dev/null
            fi
            ;;
        apk)
            if [ -n "$lno" ]; then
                if [ "$st" = "enabled" ]; then
                    awk -v ln="$lno" 'NR==ln { print "#" $0; next } { print }' "$fpath" >"${fpath}.pms_tmp" \
                        && mv -f "${fpath}.pms_tmp" "$fpath"
                    _PM_MSG="✔ APK 레포 #${lno} 비활성화 완료!"
                else
                    awk -v ln="$lno" 'NR==ln { sub(/^[ \t]*#[ \t]*/,""); print; next } { print }' "$fpath" >"${fpath}.pms_tmp" \
                        && mv -f "${fpath}.pms_tmp" "$fpath"
                    _PM_MSG="✔ APK 레포 #${lno} 활성화 완료!"
                fi
                rm -f "$_bak" 2>/dev/null
            fi
            ;;
        *)
            rm -f "$_bak" 2>/dev/null
            _PM_MSG="ℹ 이 배포판(${_PM_MGR})은 [e] 키로 vi2 직접 편집을 이용하세요."
            return 0
            ;;
    esac
    _pm_load_repos
    _pm_build_view
}

# 레포 설정 파일 vi2 백업 편집
_pm_edit_repo() {
    local idx="$1"
    local mt="${_PM_META[$idx]}"
    local fpath="${mt%%|*}"
    [ -f "$fpath" ] || { _PM_MSG="⚠ 편집할 레포 파일이 없습니다: $fpath"; return 1; }

    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    local _bck _ack
    _bck=$(cksum "$fpath" 2>/dev/null)
    vi2 "$fpath"
    _ack=$(cksum "$fpath" 2>/dev/null)
    if [ "$_bck" != "$_ack" ]; then
        _pm_p '\n\033[1;33m📝 레포 설정이 변경되었습니다: %s\033[0m\n' "$fpath"
        _pm_p '지금 저장소 메타데이터 캐시를 갱신할까요? [Y/n]: '
        local _ans=""
        IFS= read -r _ans </dev/tty
        case "$_ans" in
            n|N) _PM_MSG="✔ 레포 저장 완료 (캐시 미갱신): $(basename "$fpath")" ;;
            *)   _pm_refresh_cache; _PM_MSG="✔ 레포 저장 및 캐시 갱신 완료!" ;;
        esac
    else
        _PM_MSG="변경 없음: $(basename "$fpath")"
    fi
    _pm_load_repos
    _pm_build_view
}

# 주요 레포 / 커스텀 레포 추가 마법사 (a 키)
_pm_add_repo_wizard() {
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\033[2J\033[H'
    _pm_p '\033[1;36m* 소스 레포지토리 추가 마법사 (OS: %s / PM: %s)\033[0m\n' "$_PM_OS" "$_PM_MGR"
    printf '%s\n' "--------------------------------------------------------------------"
    case "$_PM_MGR" in
        dnf|yum)
            _pm_p '  \033[1;33m1.\033[0m EPEL 저장소 설치 (epel-release) + yum/dnf-utils\n'
            _pm_p '  \033[1;33m2.\033[0m CRB / PowerTools 저장소 활성화 (RHEL/Alma/Rocky 8/9)\n'
            _pm_p '  \033[1;33m3.\033[0m 커스텀 .repo 파일 URL로 추가 (config-manager --add-repo)\n'
            _pm_p '  \033[1;33m4.\033[0m 새 .repo 파일 직접 생성 후 vi2 편집 (/etc/yum.repos.d/)\n'
            _pm_p '  \033[0;37m0.\033[0m 취소\n'
            printf '%s\n' "--------------------------------------------------------------------"
            _pm_p '선택 [0-4]: '
            local _sel=""
            IFS= read -r _sel </dev/tty
            case "$_sel" in
                1)
                    "$_PM_MGR" install -y epel-release yum-utils 2>&1 || "$_PM_MGR" install -y epel-release 2>&1
                    _pm_pause "EPEL 설치 완료"
                    _PM_MSG="✔ EPEL 저장소 설치 완료"
                    ;;
                2)
                    if command -v dnf >/dev/null 2>&1; then
                        dnf config-manager --set-enabled crb 2>&1 || dnf config-manager --set-enabled powertools 2>&1
                    else
                        yum-config-manager --enable powertools 2>&1 || yum-config-manager --enable crb 2>&1
                    fi
                    _pm_pause "CRB/PowerTools 활성화 완료"
                    _PM_MSG="✔ CRB/PowerTools 활성화 시도 완료"
                    ;;
                3)
                    _pm_p '추가할 .repo URL 입력: '
                    local _url=""
                    IFS= read -r _url </dev/tty
                    if [ -n "$_url" ]; then
                        if command -v dnf >/dev/null 2>&1; then
                            dnf config-manager --add-repo "$_url" 2>&1
                        else
                            yum-config-manager --add-repo "$_url" 2>&1
                        fi
                        _pm_pause "레포 URL 추가 완료"
                        _PM_MSG="✔ 커스텀 레포 추가 완료"
                    fi
                    ;;
                4)
                    _pm_p '새 레포 파일명 (.repo 제외, 예: custom): '
                    local _rn=""
                    IFS= read -r _rn </dev/tty
                    if [ -n "$_rn" ]; then
                        _rn="${_rn%.repo}"
                        local _nf="/etc/yum.repos.d/${_rn}.repo"
                        if [ ! -f "$_nf" ]; then
                            cat >"$_nf" <<REPOEOF
[${_rn}]
name=${_rn} Repository
baseurl=https://example.com/repo/
enabled=1
gpgcheck=0
REPOEOF
                        fi
                        vi2 "$_nf"
                        _PM_MSG="✔ ${_nf} 편집 완료"
                    fi
                    ;;
                *) _PM_MSG="레포 추가 취소" ;;
            esac
            ;;
        apt|apt-get)
            _pm_p '  \033[1;33m1.\033[0m Ubuntu universe / multiverse 저장소 활성화 + apt update\n'
            _pm_p '  \033[1;33m2.\033[0m PPA 저장소 추가 (add-apt-repository ppa:...)\n'
            _pm_p '  \033[1;33m3.\033[0m 새 .list 파일 생성 후 vi2 편집 (/etc/apt/sources.list.d/)\n'
            _pm_p '  \033[1;33m4.\033[0m 메인 /etc/apt/sources.list 바로 vi2 편집\n'
            _pm_p '  \033[0;37m0.\033[0m 취소\n'
            printf '%s\n' "--------------------------------------------------------------------"
            _pm_p '선택 [0-4]: '
            local _sel=""
            IFS= read -r _sel </dev/tty
            case "$_sel" in
                1)
                    apt-get install -y software-properties-common 2>&1
                    add-apt-repository -y universe 2>&1
                    add-apt-repository -y multiverse 2>&1
                    apt-get update 2>&1
                    _pm_pause "universe/multiverse 활성화 완료"
                    _PM_MSG="✔ universe/multiverse 활성화 완료"
                    ;;
                2)
                    _pm_p '추가할 PPA 입력 (예: ppa:ondrej/php): '
                    local _ppa=""
                    IFS= read -r _ppa </dev/tty
                    if [ -n "$_ppa" ]; then
                        command -v add-apt-repository >/dev/null 2>&1 || apt-get install -y software-properties-common 2>&1
                        add-apt-repository -y "$_ppa" 2>&1 && apt-get update 2>&1
                        _pm_pause "PPA 추가 완료"
                        _PM_MSG="✔ PPA 추가 완료: $_ppa"
                    fi
                    ;;
                3)
                    _pm_p '새 .list 파일명 (.list 제외, 예: custom): '
                    local _rn=""
                    IFS= read -r _rn </dev/tty
                    if [ -n "$_rn" ]; then
                        _rn="${_rn%.list}"
                        local _nf="/etc/apt/sources.list.d/${_rn}.list"
                        [ ! -f "$_nf" ] && echo "# deb https://example.com/apt stable main" >"$_nf"
                        vi2 "$_nf"
                        _PM_MSG="✔ ${_nf} 편집 완료"
                    fi
                    ;;
                4)
                    vi2 /etc/apt/sources.list
                    _PM_MSG="✔ /etc/apt/sources.list 편집 완료"
                    ;;
                *) _PM_MSG="레포 추가 취소" ;;
            esac
            ;;
        apk)
            vi2 /etc/apk/repositories
            _PM_MSG="✔ /etc/apk/repositories 편집 완료"
            ;;
        pacman)
            vi2 /etc/pacman.conf
            _PM_MSG="✔ /etc/pacman.conf 편집 완료"
            ;;
        *)
            _pm_p '이 배포판(%s)에서는 레포 디렉토리를 직접 열어 편집하세요: %s\n' "$_PM_MGR" "$_PM_REPO_DIR"
            _pm_pause ""
            ;;
    esac
    if [ "$_PM_MODE" = "repos" ]; then
        _pm_load_repos
        _pm_build_view
    fi
}

# 잠시 멈춤 헬퍼
_pm_pause() {
    local _msg="${1:-}"
    [ -n "$_msg" ] && _pm_p '\n\033[1;32m✔ %s\033[0m\n' "$_msg"
    _pm_p '\n아무 키나 누르면 [pms] 화면으로 돌아갑니다...'
    IFS= read -rsn1 _ </dev/tty 2>/dev/null
}

# 저장소 메타데이터 캐시 갱신 / 정리 (c 키)
_pm_refresh_cache() {
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\n'
    _pm_p '\033[1;36m[캐시 관리] 1) 메타데이터 갱신(update/makecache)  2) 캐시 정리(clean/autoremove)  0) 취소 [기본 1]: \033[0m'
    local _c=""
    IFS= read -r _c </dev/tty
    [ -z "$_c" ] && _c="1"
    case "$_c" in
        1)
            case "$_PM_MGR" in
                dnf|yum) "$_PM_MGR" makecache 2>&1 ;;
                apt|apt-get) "$_PM_MGR" update 2>&1 ;;
                pacman) pacman -Sy 2>&1 ;;
                apk) apk update 2>&1 ;;
                zypper) zypper refresh 2>&1 ;;
                pkg) pkg update 2>&1 ;;
                *) _pm_p '이 매니저(%s)는 원격 캐시 갱신을 지원하지 않습니다.\n' "$_PM_MGR" ;;
            esac
            _pm_pause "저장소 메타데이터 갱신 완료"
            _PM_MSG="✔ 저장소 캐시 갱신 완료!"
            ;;
        2)
            case "$_PM_MGR" in
                dnf) dnf clean all 2>&1; dnf autoremove -y 2>&1 ;;
                yum) yum clean all 2>&1 ;;
                apt|apt-get) "$_PM_MGR" autoremove -y 2>&1; "$_PM_MGR" clean 2>&1 ;;
                pacman) pacman -Sc --noconfirm 2>&1 ;;
                apk) apk cache clean 2>&1 ;;
                zypper) zypper clean --all 2>&1 ;;
                pkg) pkg clean -y 2>&1; pkg autoremove -y 2>&1 ;;
                *) _pm_p '캐시 정리 미지원(%s)\n' "$_PM_MGR" ;;
            esac
            _pm_pause "캐시/미사용 패키지 정리 완료"
            _PM_MSG="✔ 캐시 정리 완료!"
            ;;
        *) _PM_MSG="캐시 관리 취소" ;;
    esac
}

# 패키지 상세 정보 보기 (v / Enter)
_pm_show_info() {
    local pkg="$1"
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    {
        printf '=== Package Info: %s (PM: %s / %s) ===\n\n' "$pkg" "$_PM_MGR" "$_PM_LOW"
        case "$_PM_MGR" in
            dnf|yum)
                rpm -qi "$pkg" 2>/dev/null || "$_PM_MGR" info "$pkg" 2>&1
                ;;
            apt|apt-get)
                dpkg -s "$pkg" 2>/dev/null || apt-cache show "$pkg" 2>&1
                ;;
            pacman)
                pacman -Qi "$pkg" 2>/dev/null || pacman -Si "$pkg" 2>&1
                ;;
            apk)
                apk info -a "$pkg" 2>&1
                ;;
            zypper)
                rpm -qi "$pkg" 2>/dev/null || zypper info "$pkg" 2>&1
                ;;
            pkg)
                pkg info "$pkg" 2>/dev/null || pkg rquery '%n-%v\n%c\n%e' "$pkg" 2>&1
                ;;
            rpm) rpm -qi "$pkg" 2>&1 ;;
            dpkg) dpkg -s "$pkg" 2>&1 ;;
            pkginfo) pkginfo -l "$pkg" 2>&1 ;;
        esac
    } | less -RX
}

# 패키지가 설치한 파일 목록 보기 (l 키)
_pm_show_files() {
    local pkg="$1"
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    {
        printf '=== Installed Files: %s ===\n\n' "$pkg"
        case "$_PM_LOW" in
            rpm)     rpm -ql "$pkg" 2>&1 ;;
            dpkg)    dpkg -L "$pkg" 2>&1 ;;
            pacman)  pacman -Ql "$pkg" 2>&1 ;;
            apk)     apk info -L "$pkg" 2>&1 ;;
            pkg)     pkg info -l "$pkg" 2>&1 ;;
            pkginfo) pkgchk -l "$pkg" 2>&1 ;;
            *)       echo "지원하지 않는 패키지 백엔드: $_PM_LOW" ;;
        esac
    } | less -RX
}

# 패키지 설치 / 개별 업데이트 (i 키)
_pm_install_pkg() {
    local pkg="$1" mode="${2:-install}"
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null

    if [ -z "$pkg" ]; then
        _pm_p '\n설치할 패키지명 (또는 로컬 .rpm/.deb 경로, 빈 값=취소): '
        IFS= read -r pkg </dev/tty
        [ -z "$pkg" ] && { _PM_MSG="설치 취소"; return 0; }
    fi

    local _verb="설치"
    [ "$mode" = "upgrade" ] && _verb="업데이트"
    _pm_p '\n\033[1;33m[%s]\033[0m 패키지 \033[1;36m%s\033[0m 을(를) %s할까요? [Y/n]: ' "$_PM_MGR" "$pkg" "$_verb"
    local _ans=""
    IFS= read -r _ans </dev/tty
    case "$_ans" in
        n|N) _PM_MSG="${_verb} 취소: $pkg"; return 0 ;;
    esac

    local _rc=0
    case "$pkg" in
        *.rpm)
            rpm -Uvh "$pkg" 2>&1; _rc=$?
            ;;
        *.deb)
            dpkg -i "$pkg" 2>&1; _rc=$?
            ;;
        *)
            case "$_PM_MGR" in
                dnf|yum)
                    if [ "$mode" = "upgrade" ]; then
                        "$_PM_MGR" upgrade -y "$pkg" 2>&1; _rc=$?
                    else
                        "$_PM_MGR" install -y "$pkg" 2>&1; _rc=$?
                    fi
                    ;;
                apt|apt-get)
                    if [ "$mode" = "upgrade" ]; then
                        "$_PM_MGR" install --only-upgrade -y "$pkg" 2>&1; _rc=$?
                    else
                        "$_PM_MGR" install -y "$pkg" 2>&1; _rc=$?
                    fi
                    ;;
                pacman)  pacman -S --noconfirm "$pkg" 2>&1; _rc=$? ;;
                apk)     apk add "$pkg" 2>&1; _rc=$? ;;
                zypper)
                    if [ "$mode" = "upgrade" ]; then
                        zypper -n up "$pkg" 2>&1; _rc=$?
                    else
                        zypper -n in "$pkg" 2>&1; _rc=$?
                    fi
                    ;;
                pkg)     pkg install -y "$pkg" 2>&1; _rc=$? ;;
                *)       _pm_p '원격 설치 미지원(%s). 로컬 .rpm/.deb 경로를 입력하세요.\n' "$_PM_MGR"; _rc=1 ;;
            esac
            ;;
    esac

    if [ $_rc -eq 0 ]; then
        _pm_pause "${pkg} ${_verb} 완료!"
        _PM_MSG="✔ ${pkg} ${_verb} 완료!"
        if [ "$_PM_MODE" = "installed" ]; then
            _pm_load_installed; _pm_build_view
        elif [ "$_PM_MODE" = "updates" ]; then
            _pm_load_updates; _pm_build_view
        fi
    else
        _pm_pause "${pkg} ${_verb} 실패 (exit $_rc)"
        _PM_MSG="✖ ${pkg} ${_verb} 실패 (exit $_rc)"
    fi
}

# 패키지 삭제 (d / x 키 — 핵심 OS 패키지 이중 안전장치)
_pm_remove_pkg() {
    local pkg="$1"
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\n'

    if _pm_is_critical "$pkg"; then
        _pm_p '\033[1;41;37m ⛔ [핵심 시스템 패키지 보호] %s \033[0m\n' "$pkg"
        _pm_p '\033[1;31m   이 패키지를 삭제하면 OS 부팅/SSH/패키지 관리가 마비될 수 있습니다!\033[0m\n'
        _pm_p '   그래도 삭제하려면 패키지명(\033[1;33m%s\033[0m)을 그대로 입력하세요 (취소=Enter): ' "$pkg"
        local _typed=""
        IFS= read -r _typed </dev/tty
        if [ "$_typed" != "$pkg" ]; then
            _PM_MSG="🛡 핵심 패키지 보호됨 — 삭제 취소: $pkg"
            return 1
        fi
    else
        _pm_p '\033[1;33m⚠ 패키지 [%s] 을(를) 정말 삭제할까요? [y/N]: \033[0m' "$pkg"
        local _ans=""
        IFS= read -r _ans </dev/tty
        case "$_ans" in
            y|Y|yes|YES) ;;
            *) _PM_MSG="삭제 취소: $pkg"; return 1 ;;
        esac
    fi

    local _rc=0
    case "$_PM_MGR" in
        dnf|yum)     "$_PM_MGR" remove -y "$pkg" 2>&1; _rc=$? ;;
        apt|apt-get) "$_PM_MGR" remove -y "$pkg" 2>&1; _rc=$? ;;
        pacman)      pacman -R --noconfirm "$pkg" 2>&1; _rc=$? ;;
        apk)         apk del "$pkg" 2>&1; _rc=$? ;;
        zypper)      zypper -n rm "$pkg" 2>&1; _rc=$? ;;
        pkg)         pkg delete -y "$pkg" 2>&1; _rc=$? ;;
        rpm)         rpm -e "$pkg" 2>&1; _rc=$? ;;
        dpkg)        dpkg -r "$pkg" 2>&1; _rc=$? ;;
        *)           _pm_p '삭제 미지원(%s)\n' "$_PM_MGR"; _rc=1 ;;
    esac

    if [ $_rc -eq 0 ]; then
        _pm_pause "${pkg} 삭제 완료!"
        _PM_MSG="✔ ${pkg} 삭제 완료!"
        if [ "$_PM_MODE" = "installed" ]; then
            _pm_load_installed; _pm_build_view
        fi
    else
        _pm_pause "${pkg} 삭제 실패 (exit $_rc)"
        _PM_MSG="✖ ${pkg} 삭제 실패 (exit $_rc)"
    fi
}

# 전체 시스템 업그레이드 (U 키)
_pm_upgrade_all() {
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\n'
    _pm_p '\033[1;33m⚠ 시스템 전체 패키지를 최신 버전으로 일괄 업그레이드할까요? (%s) [y/N]: \033[0m' "$_PM_MGR"
    local _ans=""
    IFS= read -r _ans </dev/tty
    case "$_ans" in
        y|Y|yes|YES) ;;
        *) _PM_MSG="전체 업그레이드 취소"; return 0 ;;
    esac

    local _rc=0
    case "$_PM_MGR" in
        dnf|yum)     "$_PM_MGR" update -y 2>&1; _rc=$? ;;
        apt|apt-get) "$_PM_MGR" update 2>&1 && "$_PM_MGR" upgrade -y 2>&1; _rc=$? ;;
        pacman)      pacman -Syu --noconfirm 2>&1; _rc=$? ;;
        apk)         apk update 2>&1 && apk upgrade 2>&1; _rc=$? ;;
        zypper)      zypper -n up 2>&1; _rc=$? ;;
        pkg)         pkg upgrade -y 2>&1; _rc=$? ;;
        *)           _pm_p '전체 업그레이드 미지원(%s)\n' "$_PM_MGR"; _rc=1 ;;
    esac

    if [ $_rc -eq 0 ]; then
        _pm_pause "시스템 전체 업그레이드 완료!"
        _PM_MSG="✔ 시스템 전체 업그레이드 완료!"
    else
        _pm_pause "업그레이드 중 오류 발생 (exit $_rc)"
        _PM_MSG="✖ 전체 업그레이드 오류 (exit $_rc)"
    fi
    if [ "$_PM_MODE" = "updates" ]; then
        _pm_load_updates; _pm_build_view
    elif [ "$_PM_MODE" = "installed" ]; then
        _pm_load_installed; _pm_build_view
    fi
}

# 파일/명령어 소속 패키지 역검색 (w 키 — whatprovides / dpkg -S / rpm -qf)
_pm_whatprovides() {
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    _pm_p '\n역검색할 명령어 또는 파일 경로 (예: netstat, /etc/ssh/sshd_config): '
    local _q=""
    IFS= read -r _q </dev/tty
    [ -z "$_q" ] && { _PM_MSG="역검색 취소"; return 0; }

    local _target="$_q"
    if [ ! -e "$_target" ]; then
        local _wh
        _wh=$(command -v "$_q" 2>/dev/null)
        [ -n "$_wh" ] && [ -e "$_wh" ] && _target="$_wh"
    fi

    printf '\n'
    if [ -e "$_target" ]; then
        _pm_p '\033[1;36m[로컬 파일 소속 조회]\033[0m %s\n' "$_target"
        case "$_PM_LOW" in
            rpm)    rpm -qf "$_target" 2>&1 ;;
            dpkg)   dpkg -S "$_target" 2>&1 ;;
            pacman) pacman -Qo "$_target" 2>&1 ;;
            apk)    apk info --who-owns "$_target" 2>&1 ;;
            pkg)    pkg which "$_target" 2>&1 ;;
        esac
        _pm_pause ""
    else
        _pm_p '\033[1;36m[원격 저장소 역검색]\033[0m 명령어/파일 "%s" 제공 패키지 탐색 중...\n' "$_q"
        case "$_PM_MGR" in
            dnf|yum) "$_PM_MGR" provides "*/$_q" 2>&1 | head -n 40 ;;
            apt|apt-get)
                if command -v apt-file >/dev/null 2>&1; then
                    apt-file search "$_q" 2>&1 | grep -E "bin/${_q}$|/${_q}$" | head -n 30
                else
                    _pm_p '⚠ apt-file 미설치 상태입니다. apt-cache search 로 대체 검색합니다:\n'
                    apt-cache search "$_q" 2>&1 | head -n 25
                fi
                ;;
            pacman) pacman -F "$_q" 2>&1 | head -n 30 ;;
            zypper) zypper wp "$_q" 2>&1 | head -n 30 ;;
            *) _pm_p '원격 역검색 미지원(%s)\n' "$_PM_MGR" ;;
        esac
        _pm_p '\n바로 설치할 패키지명이 있으면 입력 (건너뛰기=Enter): '
        local _inst=""
        IFS= read -r _inst </dev/tty
        [ -n "$_inst" ] && _pm_install_pkg "$_inst" "install"
    fi
}

# 자세한 사용법 도움말 (? / h 키)
_pm_show_help() {
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    {
        _pm_p '\033[1;36m==========================================================================\033[0m\n'
        _pm_p '\033[1;36m  * 통합 서버 패키지 관리 [pms] — 자세한 사용법 안내\033[0m\n'
        _pm_p '\033[1;36m==========================================================================\033[0m\n'
        _pm_p '  현재 환경 : OS = \033[1;33m%s\033[0m  |  상위 PM = \033[1;32m%s\033[0m  |  하위 백엔드 = \033[1;32m%s\033[0m\n' "$_PM_OS" "$_PM_MGR" "$_PM_LOW"
        _pm_p '  레포 경로 : \033[0;32m%s\033[0m\n' "${_PM_REPO_DIR:-(미탐지)}"
        _pm_p '  지원 OS   : RHEL/Alma/Rocky/CentOS(dnf/yum/rpm), Debian/Ubuntu/PVE(apt/dpkg),\n'
        _pm_p '              Arch(pacman), Alpine(apk), openSUSE(zypper), FreeBSD(pkg), Solaris(pkginfo)\n'
        _pm_p '\n'
        _pm_p '\033[1;33m[1. 4대 뷰 모드 전환]\033[0m\n'
        _pm_p '  1            : 설치됨 모드 — 현재 시스템에 설치된 전체 패키지 목록 (기본)\n'
        _pm_p '  2  또는  u   : 업데이트 모드 — 업그레이드 가능한 패키지 목록 조회\n'
        _pm_p '  3  또는  s   : 원격검색 모드 — 저장소에서 새 패키지 검색 후 바로 설치\n'
        _pm_p '  4  또는 r/R  : 소스 레포 모드 — 저장소 목록·활성토글·vi2편집·추가 관리\n'
        _pm_p '  Tab          : 4대 모드 순환 전환 (설치됨 -> 업데이트 -> 원격검색 -> 레포)\n'
        _pm_p '\n'
        _pm_p '\033[1;33m[2. 이동 · 검색 · 필터]\033[0m\n'
        _pm_p '  ↑ / ↓ (k/j)  : 위/아래 1칸 이동 (무깜빡임 초고속 델타 렌더링)\n'
        _pm_p '  ← / → / PgUp / PgDn : 이전/다음 페이지 단위로 빠르게 이동\n'
        _pm_p '  /            : 현재 화면 목록 내 실시간 키워드 필터 (이름·설명 검색)\n'
        _pm_p '  ESC          : 필터 검색어가 있으면 검색어 초기화, 없으면 종료\n'
        _pm_p '  f / F        : 빠른 필터 토글\n'
        _pm_p '                 - 설치됨 모드 : [전체] <-> [주요서버 (웹/DB/PHP/SSH/도커/방화벽 등)]\n'
        _pm_p '                 - 레포 모드   : [전체] -> [활성만] -> [비활성만]\n'
        _pm_p '\n'
        _pm_p '\033[1;33m[3. 패키지 설치 · 업데이트 · 삭제 · 탐색]\033[0m\n'
        _pm_p '  s / S        : 원격 저장소 패키지 검색 (키워드 입력 -> 결과 리스트 표시)\n'
        _pm_p '  i / I        : 패키지 설치 / 단독 업데이트\n'
        _pm_p '                 - 원격검색 모드 : 커서 위 패키지 즉시 설치\n'
        _pm_p '                 - 업데이트 모드 : 커서 위 패키지 단독 업그레이드\n'
        _pm_p '                 - 설치됨 모드   : 패키지명 또는 로컬 .rpm/.deb 경로 직접 입력 설치\n'
        _pm_p '  d / x        : 커서 위 패키지 삭제\n'
        _pm_p '                 \033[1;31m[안전장치]\033[0m glibc/openssh/systemd/kernel/yum/dnf/apt/rpm 등\n'
        _pm_p '                 핵심 OS 패키지 삭제 시 빨간 경고 + 패키지명 직접 입력 이중 확인!\n'
        _pm_p '  v / Enter    : 패키지 상세 정보 보기 (버전·의존성·설명 등, less -RX)\n'
        _pm_p '  l / L        : 패키지가 설치한 전체 파일 경로 목록 보기 (rpm -ql / dpkg -L)\n'
        _pm_p '  w / W        : 명령어/파일 경로 역검색 (whatprovides / rpm -qf / dpkg -S)\n'
        _pm_p '                 - 설치된 파일이면 소속 패키지 즉시 표시\n'
        _pm_p '                 - 미설치 명령어면 제공 패키지를 찾아 바로 설치 제안!\n'
        _pm_p '  U (대문자)   : 시스템 전체 패키지 일괄 업그레이드 (실행 전 y/N 확인)\n'
        _pm_p '  c / C        : 저장소 캐시 관리 (1: 메타데이터 갱신 / 2: 캐시·미사용 정리)\n'
        _pm_p '\n'
        _pm_p '\033[1;33m[4. 소스 레포지토리 관리 (4 또는 r/R)]\033[0m\n'
        _pm_p '  Space        : 커서 위 레포 활성(enabled) <-> 비활성(disabled) 원터치 토글\n'
        _pm_p '                 (.repo enabled=1/0, apt .list 주석/# 토글, .sources .disabled 전환)\n'
        _pm_p '  e / Enter    : 커서 위 레포 설정 파일 vi2 백업 편집 (변경 시 캐시 갱신 자동 제안)\n'
        _pm_p '  a / A        : 레포 추가 마법사\n'
        _pm_p '                 - RHEL계열 : EPEL 설치 / CRB·PowerTools 활성 / URL추가 / 새 .repo 생성\n'
        _pm_p '                 - Debian계열: universe·multiverse 활성 / PPA 추가 / 새 .list 생성\n'
        _pm_p '  o / O        : 레포 설정 디렉토리를 explorer 파일 탐색기로 바로 열기\n'
        _pm_p '\n'
        _pm_p '\033[1;33m[5. 실전 활용 팁]\033[0m\n'
        _pm_p '  • 쉘에서 바로 검색 진입   : \033[1;32mpms php\033[0m  (설치된 php 패키지 바로 필터링)\n'
        _pm_p '  • 없는 명령어 패키지 찾기 : \033[1;32mw\033[0m -> netstat 입력 -> net-tools 확인 후 바로 설치\n'
        _pm_p '  • EPEL 켜고 새 패키지 설치: \033[1;32m4\033[0m -> \033[1;32ma\033[0m(1번 EPEL) -> \033[1;32ms\033[0m(검색) -> \033[1;32mi\033[0m(설치)\n'
        _pm_p '\n'
        _pm_p '\033[0;37m  [q] 를 누르면 도움말을 닫고 [pms] 화면으로 돌아갑니다.\033[0m\n'
    } | less -RX
}

# 화면 레이아웃/기호 캐시
_pm_init_layout() {
    local _TS_LINES="" _TS_COLS=""
    _get_term_size
    _PM_ROWS=$_TS_LINES
    _PM_COLS=$_TS_COLS
    _PM_PAGE_H=$((_PM_ROWS - 10))
    [ "$_PM_PAGE_H" -lt 5 ] && _PM_PAGE_H=5
    local _w=$((_PM_COLS > 115 ? 115 : _PM_COLS - 1))
    _PM_HLINE=$(printf '%*s' "$_w" '' | tr ' ' '-')
    if [ "$_PM_ENC" = "euckr" ]; then
        _PM_S_CUR=">"; _PM_S_INFO="[i]"; _PM_S_BUL="-"; _PM_S_DASH="-"
    else
        _PM_S_CUR="▶"; _PM_S_INFO="📦"; _PM_S_BUL="•"; _PM_S_DASH="—"
    fi
    _PM_DIRTY=1
}

# 단일 줄 렌더링
_pm_render_row() {
    local vidx="$1" is_cur="$2"
    local idx="${_PM_VIEW[$vidx]}"
    local nm="${_PM_NAMES[$idx]}" vr="${_PM_VERS[$idx]}" ds="${_PM_DESCS[$idx]}" st="${_PM_STATES[$idx]}"
    local s_tag

    if [ "$_PM_ENC" = "euckr" ]; then
        case "$st" in
            installed)  s_tag=$'\033[1;32m[I]\033[0m' ;;
            upgradable) s_tag=$'\033[1;33m[U]\033[0m' ;;
            remote)     s_tag=$'\033[1;36m[+]\033[0m' ;;
            enabled)    s_tag=$'\033[1;32m[*]\033[0m' ;;
            disabled)   s_tag=$'\033[0;37m[ ]\033[0m' ;;
            *)          s_tag=$'\033[0;37m[-]\033[0m' ;;
        esac
    else
        case "$st" in
            installed)  s_tag=$'\033[1;32m[✓]\033[0m' ;;
            upgradable) s_tag=$'\033[1;33m[↑]\033[0m' ;;
            remote)     s_tag=$'\033[1;36m[+]\033[0m' ;;
            enabled)    s_tag=$'\033[1;32m[✓]\033[0m' ;;
            disabled)   s_tag=$'\033[0;37m[ ]\033[0m' ;;
            *)          s_tag=$'\033[0;37m[-]\033[0m' ;;
        esac
    fi

    local max_d=$((_PM_COLS - 56))
    [ "$max_d" -lt 14 ] && max_d=14
    ds=$(_pm_safe_str "$ds")
    [ "${#ds}" -gt "$max_d" ] && ds="${ds:0:$((max_d - 2))}.."

    if [ "$is_cur" = "1" ]; then
        printf '\033[1;33m%s\033[0m %s \033[7m %-26.26s \033[0m \033[0;36m%-18.18s\033[0m %s\033[K\n' \
            "$_PM_S_CUR" "$s_tag" "$nm" "$vr" "$ds"
    else
        printf '  %s  %-26.26s  \033[0;36m%-18.18s\033[0m %s\033[K\n' \
            "$s_tag" "$nm" "$vr" "$ds"
    fi
}

# 하단 상세 카드 + 상태바
_pm_render_footer() {
    printf '\033[0;34m%s\033[0m\033[K\n' "$_PM_HLINE"
    if [ "$_PM_VCNT" -gt 0 ]; then
        local cidx="${_PM_VIEW[$_PM_CUR]}"
        local cnm="${_PM_NAMES[$cidx]}"
        local cvr="${_PM_VERS[$cidx]}"
        local cds="${_PM_DESCS[$cidx]}"
        local cst="${_PM_STATES[$cidx]}"
        local cmt="${_PM_META[$cidx]}"
        [ -z "$cds" ] && cds="(설명 없음 — [v/Enter]로 상세조회)"
        cds=$(_pm_safe_str "$cds")

        printf '\033[1;36m%s %s\033[0m %s %s\033[K\n' "$_PM_S_INFO" "$cnm" "$_PM_S_DASH" "$cds"
        if [ "$_PM_MODE" = "repos" ]; then
            printf '   %s 상태: \033[1;37m%s\033[0m | 파일: \033[0;32m%s\033[0m\033[K\n' \
                "$_PM_S_BUL" "$cst" "${cmt%%|*}"
            printf '   %s 동작: [Space]활성토글  [e/Enter]vi2편집  [a]레포추가  [c]캐시갱신  [o]explorer\033[K\n' "$_PM_S_BUL"
        else
            printf '   %s 버전: \033[1;37m%s\033[0m | 상태: \033[1;37m%s\033[0m | 매니저: \033[0;32m%s (%s)\033[0m' \
                "$_PM_S_BUL" "$cvr" "$cst" "$_PM_MGR" "$_PM_LOW"
            _pm_is_critical "$cnm" && printf '  \033[1;31m[핵심OS 보호됨]\033[0m'
            printf '\033[K\n'
            printf '   %s 동작: [v/Enter]상세  [l]파일목록  [i]설치/업뎃  [d]삭제  [w]명령어역검색  [R]레포관리\033[K\n' "$_PM_S_BUL"
        fi
    else
        printf '\033[K\n\033[K\n\033[K\n'
    fi
    printf '\033[0;34m%s\033[0m\033[K\n' "$_PM_HLINE"
    if [ -n "$_PM_MSG" ]; then
        printf '\033[1;33m %s\033[0m\033[K' "$_PM_MSG"
    else
        if [ "$_PM_MODE" = "repos" ]; then
            printf ' \033[0;37m[1]설치 [2]업뎃 [3]원격 [4]레포 | [Space]토글 [e]vi2 [a]추가 [c]캐시 [o]폴더 [/]검색 [f]필터 [?]도움 [q]종료\033[0m\033[K'
        else
            printf ' \033[0;37m[1]설치 [2]업뎃 [3]원격 [4]레포 | [s]검색 [i]설치 [d]삭제 [v]상세 [l]파일 [w]역검색 [U]전체업뎃 [c]캐시 [?]도움 [q]종료\033[0m\033[K'
        fi
    fi
}

# 전체 페이지 렌더링 (제자리 덮어쓰기)
_pm_render_full_body() {
    local list_h=$_PM_PAGE_H
    local cur_pg=1 tot_pg=1
    if [ "$_PM_VCNT" -gt 0 ]; then
        cur_pg=$(( (_PM_TOP / list_h) + 1 ))
        tot_pg=$(( ((_PM_VCNT - 1) / list_h) + 1 ))
    fi
    local mlabel="설치됨"
    case "$_PM_MODE" in
        updates) mlabel="업데이트" ;;
        search)  mlabel="원격검색:${_PM_RQUERY}" ;;
        repos)   mlabel="소스레포" ;;
    esac
    local flabel=""
    case "$_PM_FILTER" in
        major)    flabel=" [주요서버]" ;;
        enabled)  flabel=" [활성만]" ;;
        disabled) flabel=" [비활성만]" ;;
    esac

    printf '\033[H'
    printf '\033[1;36m* 통합 서버 패키지 관리 [pms]\033[0m  \033[0;37mOS: %s (%s)\033[0m  모드:\033[1;33m%s%s\033[0m (%d/%d)  \033[1;37mP.%d/%d\033[0m' \
        "$_PM_OS" "$_PM_MGR" "$mlabel" "$flabel" "$_PM_VCNT" "$_PM_TOTAL" "$cur_pg" "$tot_pg"
    [ -n "$_PM_SEARCH" ] && printf '  검색:\033[1;35m/%s\033[0m' "$_PM_SEARCH"
    printf '\033[K\n\033[0;34m%s\033[0m\033[K\n' "$_PM_HLINE"

    local r=0 vidx
    if [ "$_PM_VCNT" -eq 0 ]; then
        if [ "$_PM_MODE" = "updates" ]; then
            printf '\033[K\n  ✔ 업데이트 가능한 패키지가 없습니다. (모두 최신 상태 또는 [c]로 캐시 갱신)\033[K\n'
        elif [ "$_PM_MODE" = "search" ]; then
            printf '\033[K\n  ℹ [s] 키를 눌러 원격 저장소에서 패키지를 검색하세요.\033[K\n'
        elif [ "$_PM_MODE" = "repos" ]; then
            printf '\033[K\n  ℹ 탐지된 레포 항목이 없습니다. [a]로 레포를 추가하거나 [o]로 폴더를 여세요.\033[K\n'
        else
            printf '\033[K\n  (조건에 맞는 항목이 없습니다. / 로 검색어를 지우거나 f 로 필터를 바꾸세요)\033[K\n'
        fi
        r=2
        while [ "$r" -lt "$list_h" ]; do
            printf '\033[K\n'
            r=$((r + 1))
        done
    else
        while [ "$r" -lt "$list_h" ]; do
            vidx=$((_PM_TOP + r))
            [ "$vidx" -ge "$_PM_VCNT" ] && break
            if [ "$vidx" -eq "$_PM_CUR" ]; then
                _pm_render_row "$vidx" 1
            else
                _pm_render_row "$vidx" 0
            fi
            r=$((r + 1))
        done
        while [ "$r" -lt "$list_h" ]; do
            printf '\033[K\n'
            r=$((r + 1))
        done
    fi
    _pm_render_footer
    printf '\033[J'
}

# 같은 페이지 내 초고속 델타 렌더링 (깜빡임 0%)
_pm_render_delta_body() {
    local old_row=$((3 + _PM_LAST_CUR - _PM_TOP))
    local new_row=$((3 + _PM_CUR - _PM_TOP))
    local foot_row=$((3 + _PM_PAGE_H))
    printf '\033[%d;1H' "$old_row"
    _pm_render_row "$_PM_LAST_CUR" 0
    printf '\033[%d;1H' "$new_row"
    _pm_render_row "$_PM_CUR" 1
    printf '\033[%d;1H' "$foot_row"
    _pm_render_footer
}

_pm_render() {
    if [ "$_PM_VCNT" -gt 0 ]; then
        [ "$_PM_CUR" -lt 0 ] && _PM_CUR=0
        [ "$_PM_CUR" -ge "$_PM_VCNT" ] && _PM_CUR=$((_PM_VCNT - 1))
        _PM_TOP=$(( (_PM_CUR / _PM_PAGE_H) * _PM_PAGE_H ))
    else
        _PM_TOP=0
    fi

    if [ "${_PM_DIRTY:-1}" = "0" ] && [ "$_PM_VCNT" -gt 0 ] \
       && [ "$_PM_TOP" = "${_PM_LAST_TOP:--1}" ] && [ "${_PM_LAST_CUR:--1}" -ge 0 ] \
       && [ "$_PM_LAST_CUR" -lt "$_PM_VCNT" ] && [ -z "$_PM_MSG" ] && [ -z "${_PM_LAST_MSG:-}" ]; then
        if [ "$_PM_CUR" != "$_PM_LAST_CUR" ]; then
            if [ "$_PM_ENC" = "euckr" ]; then
                _pm_render_delta_body | _dm_iconv_euckr
            else
                _pm_render_delta_body
            fi
        fi
    else
        if [ "$_PM_ENC" = "euckr" ]; then
            _pm_render_full_body | _dm_iconv_euckr
        else
            _pm_render_full_body
        fi
        _PM_DIRTY=0
    fi
    _PM_LAST_CUR=$_PM_CUR
    _PM_LAST_TOP=$_PM_TOP
    _PM_LAST_MSG="$_PM_MSG"
}

# 모드 전환 헬퍼
_pm_switch_mode() {
    local new_mode="$1"
    _PM_MODE="$new_mode"
    _PM_FILTER="all"
    _PM_SEARCH=""
    _PM_CUR=0; _PM_TOP=0
    _PM_LAST_CUR=-1; _PM_LAST_TOP=-1
    case "$new_mode" in
        installed)
            _pm_p '\033[H\033[1;36m[pms] 설치된 패키지 목록 로딩 중...\033[0m\033[K'
            _pm_load_installed
            ;;
        updates)
            _pm_p '\033[H\033[1;36m[pms] 업데이트 가능 패키지 조회 중 (%s)...\033[0m\033[K' "$_PM_MGR"
            _pm_load_updates
            ;;
        search)
            if [ -n "$_PM_RQUERY" ]; then
                _pm_p '\033[H\033[1;36m[pms] 원격 저장소 검색 중: %s ...\033[0m\033[K' "$_PM_RQUERY"
                _pm_load_search "$_PM_RQUERY"
            else
                _pm_clear_data
            fi
            ;;
        repos)
            _pm_p '\033[H\033[1;36m[pms] 소스 레포지토리 목록 로딩 중...\033[0m\033[K'
            _pm_load_repos
            ;;
    esac
    _pm_build_view
    _PM_DIRTY=1
}

# 메인 진입 함수: pms [초기검색어]
pms() {
    _pm_detect_env
    if [ "$_PM_MGR" = "unknown" ]; then
        _pm_p '❌ 지원하는 패키지 매니저(dnf/yum/apt/pacman/apk/zypper/pkg/rpm/dpkg/pkginfo)를 찾지 못했습니다.\n'
        return 1
    fi

    _PM_MODE="installed"
    _PM_FILTER="all"
    _PM_SEARCH="${1:-}"
    _PM_RQUERY=""
    _PM_CUR=0; _PM_TOP=0
    _PM_MSG=""
    _PM_LAST_CUR=-1; _PM_LAST_TOP=-1; _PM_LAST_MSG=""

    _pm_p '\033[1;36m[pms] %s (PM: %s / %s) 패키지 목록 로딩 중...\033[0m\n' "$_PM_OS" "$_PM_MGR" "$_PM_LOW"
    _pm_load_installed
    _pm_build_view
    _pm_init_layout

    local _esc_t=1
    [ "${BASH_VERSINFO[0]:-0}" -ge 4 ] && _esc_t=0.25

    local _old_trap
    _old_trap=$(trap -p INT)
    trap 'tput cnorm 2>/dev/null; stty sane 2>/dev/null; printf "\n"; return 0' INT
    trap '_pm_init_layout' WINCH 2>/dev/null

    printf '\033[2J\033[H'
    tput civis 2>/dev/null
    while :; do
        _pm_render
        _PM_MSG=""

        local _k="" _x="" _x2=""
        IFS= read -rsn1 _k </dev/tty 2>/dev/null || break

        if [ "$_k" = $'\033' ]; then
            IFS= read -rsn1 -t "$_esc_t" _x </dev/tty 2>/dev/null
            if [ -z "$_x" ] || [ "$_x" = $'\033' ]; then
                if [ -n "$_PM_SEARCH" ]; then
                    _PM_SEARCH=""
                    _PM_CUR=0; _PM_TOP=0
                    _pm_build_view
                    _PM_DIRTY=1
                    continue
                fi
                _k="q"
            elif [ "$_x" = "[" ] || [ "$_x" = "O" ]; then
                IFS= read -rsn1 -t "$_esc_t" _x </dev/tty 2>/dev/null
                case "$_x" in
                    A) [ "$_PM_CUR" -gt 0 ] && _PM_CUR=$((_PM_CUR - 1)); continue ;;
                    B) [ "$_PM_CUR" -lt $((_PM_VCNT - 1)) ] && _PM_CUR=$((_PM_CUR + 1)); continue ;;
                    D) # ← 이전 페이지
                       local _ph="${_PM_PAGE_H:-10}"
                       if [ "$_PM_TOP" -gt 0 ]; then
                           _PM_TOP=$((_PM_TOP - _ph))
                           [ "$_PM_TOP" -lt 0 ] && _PM_TOP=0
                           _PM_CUR=$_PM_TOP
                       else
                           _PM_CUR=0
                       fi
                       continue ;;
                    C) # → 다음 페이지
                       local _ph="${_PM_PAGE_H:-10}"
                       local _nt=$((_PM_TOP + _ph))
                       if [ "$_nt" -lt "$_PM_VCNT" ]; then
                           _PM_TOP=$_nt; _PM_CUR=$_PM_TOP
                       elif [ "$_PM_VCNT" -gt 0 ]; then
                           _PM_CUR=$((_PM_VCNT - 1))
                       fi
                       continue ;;
                    5) IFS= read -rsn1 -t "$_esc_t" _x2 </dev/tty 2>/dev/null
                       local _ph="${_PM_PAGE_H:-10}"
                       if [ "$_PM_TOP" -gt 0 ]; then
                           _PM_TOP=$((_PM_TOP - _ph))
                           [ "$_PM_TOP" -lt 0 ] && _PM_TOP=0
                           _PM_CUR=$_PM_TOP
                       else
                           _PM_CUR=0
                       fi
                       continue ;;
                    6) IFS= read -rsn1 -t "$_esc_t" _x2 </dev/tty 2>/dev/null
                       local _ph="${_PM_PAGE_H:-10}"
                       local _nt=$((_PM_TOP + _ph))
                       if [ "$_nt" -lt "$_PM_VCNT" ]; then
                           _PM_TOP=$_nt; _PM_CUR=$_PM_TOP
                       elif [ "$_PM_VCNT" -gt 0 ]; then
                           _PM_CUR=$((_PM_VCNT - 1))
                       fi
                       continue ;;
                esac
                continue
            else
                continue
            fi
        fi

        case "$_k" in
            q|Q) break ;;
            \?|h|H)
                _pm_show_help
                _PM_DIRTY=1; tput civis 2>/dev/null
                ;;
            k) [ "$_PM_CUR" -gt 0 ] && _PM_CUR=$((_PM_CUR - 1)) ;;
            j) [ "$_PM_CUR" -lt $((_PM_VCNT - 1)) ] && _PM_CUR=$((_PM_CUR + 1)) ;;
            $'\t')
                case "$_PM_MODE" in
                    installed) _pm_switch_mode "updates" ;;
                    updates)   _pm_switch_mode "search" ;;
                    search)    _pm_switch_mode "repos" ;;
                    *)         _pm_switch_mode "installed" ;;
                esac
                ;;
            1) _pm_switch_mode "installed" ;;
            2|u) _pm_switch_mode "updates" ;;
            3) _pm_switch_mode "search" ;;
            4|r|R) _pm_switch_mode "repos" ;;
            s|S)
                tput cnorm 2>/dev/null
                stty echo 2>/dev/null
                _pm_p '\n원격 저장소 검색 키워드 (예: nginx, php, htop): '
                local _rq=""
                IFS= read -r _rq </dev/tty
                if [ -n "$_rq" ]; then
                    _PM_RQUERY="$_rq"
                    _pm_switch_mode "search"
                fi
                _PM_DIRTY=1; tput civis 2>/dev/null
                ;;
            /)
                tput cnorm 2>/dev/null
                stty echo 2>/dev/null
                _pm_p '\n목록 내 필터 검색어 (빈 값=초기화): '
                IFS= read -r _PM_SEARCH </dev/tty
                _PM_CUR=0; _PM_TOP=0
                _pm_build_view
                _PM_DIRTY=1; tput civis 2>/dev/null
                ;;
            f|F)
                if [ "$_PM_MODE" = "installed" ]; then
                    [ "$_PM_FILTER" = "all" ] && _PM_FILTER="major" || _PM_FILTER="all"
                elif [ "$_PM_MODE" = "repos" ]; then
                    case "$_PM_FILTER" in
                        all)     _PM_FILTER="enabled" ;;
                        enabled) _PM_FILTER="disabled" ;;
                        *)       _PM_FILTER="all" ;;
                    esac
                fi
                _PM_CUR=0; _PM_TOP=0
                _pm_build_view
                _PM_DIRTY=1
                ;;
            " ")
                if [ "$_PM_MODE" = "repos" ] && [ "$_PM_VCNT" -gt 0 ]; then
                    _pm_toggle_repo "${_PM_VIEW[$_PM_CUR]}"
                    _PM_DIRTY=1
                fi
                ;;
            ""|v|V)
                [ "$_PM_VCNT" -eq 0 ] && continue
                local _idx="${_PM_VIEW[$_PM_CUR]}"
                if [ "$_PM_MODE" = "repos" ]; then
                    _pm_edit_repo "$_idx"
                else
                    _pm_show_info "${_PM_NAMES[$_idx]}"
                fi
                _PM_DIRTY=1; tput civis 2>/dev/null
                ;;
            e|E)
                if [ "$_PM_MODE" = "repos" ] && [ "$_PM_VCNT" -gt 0 ]; then
                    _pm_edit_repo "${_PM_VIEW[$_PM_CUR]}"
                    _PM_DIRTY=1; tput civis 2>/dev/null
                else
                    _pm_switch_mode "repos"
                fi
                ;;
            l|L)
                [ "$_PM_VCNT" -eq 0 ] && continue
                [ "$_PM_MODE" = "repos" ] && continue
                _pm_show_files "${_PM_NAMES[${_PM_VIEW[$_PM_CUR]}]}"
                _PM_DIRTY=1; tput civis 2>/dev/null
                ;;
            i|I)
                if [ "$_PM_MODE" = "remote" ] || [ "$_PM_MODE" = "search" ]; then
                    if [ "$_PM_VCNT" -gt 0 ]; then
                        _pm_install_pkg "${_PM_NAMES[${_PM_VIEW[$_PM_CUR]}]}" "install"
                    else
                        _pm_install_pkg "" "install"
                    fi
                elif [ "$_PM_MODE" = "updates" ] && [ "$_PM_VCNT" -gt 0 ]; then
                    _pm_install_pkg "${_PM_NAMES[${_PM_VIEW[$_PM_CUR]}]}" "upgrade"
                else
                    _pm_install_pkg "" "install"
                fi
                _PM_DIRTY=1; tput civis 2>/dev/null
                ;;
            d|D|x|X)
                [ "$_PM_VCNT" -eq 0 ] && continue
                [ "$_PM_MODE" = "repos" ] && continue
                _pm_remove_pkg "${_PM_NAMES[${_PM_VIEW[$_PM_CUR]}]}"
                _PM_DIRTY=1; tput civis 2>/dev/null
                ;;
            w|W)
                _pm_whatprovides
                _PM_DIRTY=1; tput civis 2>/dev/null
                ;;
            U)
                _pm_upgrade_all
                _PM_DIRTY=1; tput civis 2>/dev/null
                ;;
            c|C)
                _pm_refresh_cache
                _PM_DIRTY=1; tput civis 2>/dev/null
                ;;
            a|A)
                _pm_add_repo_wizard
                _PM_DIRTY=1; tput civis 2>/dev/null
                ;;
            o|O)
                if [ -n "$_PM_REPO_DIR" ] && [ -d "$_PM_REPO_DIR" ]; then
                    tput cnorm 2>/dev/null
                    stty echo 2>/dev/null
                    explorer "$_PM_REPO_DIR"
                    _PM_DIRTY=1; tput civis 2>/dev/null
                else
                    _PM_MSG="ℹ 탐지된 레포 디렉토리가 없습니다."
                fi
                ;;
        esac
    done

    tput cnorm 2>/dev/null
    stty sane 2>/dev/null
    [ -n "$_old_trap" ] && eval "$_old_trap" || trap - INT
    printf '\n'
}


# ==============================================================================
# 통합 사용자·호스팅 계정 관리 TUI: ums (User Manager Studio)
# - 모든 리눅스/유닉스 배포판 자동 대응 (Alma/Rocky/CentOS/RHEL/Ubuntu/Debian/Arch/Alpine)
# - 기본 기능: 계정 목록/필터/검색, Lock/Unlock/Unban(faillock/pam_tally2 자동분기),
#              랜덤·수동 비밀번호 리셋, 대응 DB(MySQL/MariaDB) & 홈폴더/웹루트/용량 점검,
#              계정 생성/그룹·쉘 관리/안전 삭제(시스템 계정 보호 가드)
# - 로컬 호스팅 플러그인 자동 감지: 서버에 /script/is, /root/ppass, /script/loginchecksend,
#   /script/sms, /script/treset 등이 존재하면 메일/SMS 발송·트래픽·SSL·도메인·만기 연동 활성화
# - Bash 2.x/3.x/4.x/5.x 및 EUC-KR 구서버 완벽 호환 (연관배열 미사용, 무깜빡임 델타 렌더링)
# ==============================================================================

_um_detect_env() {
    _UM_OS="Linux"
    _UM_ENC="utf8"
    _UM_FAIL_TOOL="none"
    _UM_MIN_UID=1000
    _UM_HOSTING=0
    _UM_MYSQL=""
    _UM_MYSQLDUMP=""

    if [ -f /etc/os-release ]; then
        _UM_OS=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null)
    elif [ -f /etc/redhat-release ]; then
        _UM_OS=$(head -n1 /etc/redhat-release 2>/dev/null)
    elif [ -f /etc/debian_version ]; then
        _UM_OS="Debian $(cat /etc/debian_version 2>/dev/null)"
    else
        _UM_OS=$(uname -s 2>/dev/null)
    fi
    [ -z "$_UM_OS" ] && _UM_OS="Linux"

    # 터미널 인코딩 판별 (EUC-KR 구서버 한글 보호)
    local _loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    case "$_loc" in
        *[Ee][Uu][Cc]*[Kk][Rr]*|*[Kk][Oo]_[Kk][Rr]|ko)
            if command -v iconv >/dev/null 2>&1; then
                _UM_ENC="euckr"
            fi ;;
    esac

    # 일반 사용자 최소 UID 판별 (/etc/login.defs 기반, 구형 CentOS 5/6은 500)
    if [ -r /etc/login.defs ]; then
        local _mu
        _mu=$(awk '/^[ \t]*UID_MIN[ \t]+[0-9]+/{print $2; exit}' /etc/login.defs 2>/dev/null)
        [ -n "$_mu" ] && _UM_MIN_UID="$_mu"
    fi

    # 로그인 실패 잠금 도구 자동 탐지
    if command -v faillock >/dev/null 2>&1; then
        _UM_FAIL_TOOL="faillock"
    elif command -v pam_tally2 >/dev/null 2>&1; then
        _UM_FAIL_TOOL="pam_tally2"
    elif [ -x /sbin/pam_tally2 ]; then
        _UM_FAIL_TOOL="/sbin/pam_tally2"
    fi

    # DB 클라이언트 자동 탐지
    if command -v mariadb >/dev/null 2>&1; then
        _UM_MYSQL="mariadb"
    elif command -v mysql >/dev/null 2>&1; then
        _UM_MYSQL="mysql"
    elif command -v mysql5 >/dev/null 2>&1; then
        _UM_MYSQL="mysql5"
    fi
    if command -v mariadb-dump >/dev/null 2>&1; then
        _UM_MYSQLDUMP="mariadb-dump"
    elif command -v mysqldump >/dev/null 2>&1; then
        _UM_MYSQLDUMP="mysqldump"
    elif command -v mysqldump5 >/dev/null 2>&1; then
        _UM_MYSQLDUMP="mysqldump5"
    fi

    # 로컬 호스팅 관리 스크립트 자동 감지 (존재 시 확장 메뉴 활성화)
    if [ -x /script/is ] || [ -x /root/ppass ] || [ -x /script/loginchecksend ] || [ -x /script/treset ]; then
        _UM_HOSTING=1
    fi
}

_um_p() {
    local _fmt="$1"
    shift
    if [ "$_UM_ENC" = "euckr" ]; then
        printf "$_fmt" "$@" | _dm_iconv_euckr
    else
        printf "$_fmt" "$@"
    fi
}

# 외부 호스팅 스크립트 출력 인코딩 정규화 (UTF-8 터미널에서 EUC-KR/혼합 출력 줄 단위 자동 변환)
_um_norm_out() {
    if [ "$_UM_ENC" = "utf8" ] && command -v iconv >/dev/null 2>&1; then
        local _tmp="/tmp/.ums_out.$$"
        cat >"$_tmp"
        if iconv -f utf-8 -t utf-8 "$_tmp" >/dev/null 2>&1; then
            cat "$_tmp"
        else
            # 시스템 메시지(UTF-8)와 레거시 스크립트(EUC-KR/CP949)가 섞인 출력은 줄 단위로 판별 변환
            local _line _conv
            while IFS= read -r _line || [ -n "$_line" ]; do
                if printf '%s\n' "$_line" | iconv -f utf-8 -t utf-8 >/dev/null 2>&1; then
                    printf '%s\n' "$_line"
                else
                    _conv=$(printf '%s' "$_line" | iconv -f cp949 -t utf-8//IGNORE 2>/dev/null)
                    if [ -z "$_conv" ] && [ -n "$_line" ]; then
                        _conv=$(printf '%s' "$_line" | iconv -f euc-kr -t utf-8//IGNORE 2>/dev/null)
                    fi
                    if [ -n "$_conv" ]; then
                        printf '%s\n' "$_conv"
                    else
                        printf '%s\n' "$_line"
                    fi
                fi
            done <"$_tmp"
        fi
        rm -f "$_tmp" 2>/dev/null
    else
        cat
    fi
}

# /script/is 실행 전 필수 호스팅 데이터 파일 사전 확인 헬퍼
_um_has_is_data() {
    [ -r /etc/httpd/conf/httpd.conf ] || [ -r /root/userinfo ] || \
    [ -r /root/binu.txt.userinfo.all ] || [ -r /root/binu.txt.userinfo.all.datefix ]
}

# /script/is 안전 실행 (필수 파일 사전 점검 + 누락 안내 + stderr 노이즈 제거 + 인코딩 정규화)
_um_run_is() {
    local _u="$1"
    local _max="${2:-0}"
    if [ ! -x /script/is ]; then
        _um_p '  ⚠ /script/is 없음\n'
        return 1
    fi
    local _f _ok=0 _miss=""
    for _f in /etc/httpd/conf/httpd.conf /root/userinfo /root/binu.txt.userinfo.all /root/binu.txt.userinfo.all.datefix; do
        if [ -r "$_f" ]; then
            _ok=$((_ok + 1))
        else
            _miss="${_miss:+${_miss}, }$_f"
        fi
    done
    if [ "$_ok" -eq 0 ]; then
        _um_p '  ℹ 호스팅 계정 데이터 파일 없음 — 조회 생략\n'
        _um_p '    (누락: %s)\n' "$_miss"
        return 1
    fi
    [ -n "$_miss" ] && _um_p '  ℹ 일부 파일 없음(생략): %s\n' "$_miss"
    if [ "$_max" -gt 0 ] 2>/dev/null; then
        /script/is "$_u" 2>/dev/null | _um_norm_out | head -n "$_max"
    else
        /script/is "$_u" 2>/dev/null | _um_norm_out
    fi
}

_um_pause() {
    local _msg="${1:-계속하려면 Enter를 누르세요...}"
    _um_p '\n\033[0;37m%s\033[0m' "$_msg"
    local _dummy=""
    IFS= read -r _dummy </dev/tty
}

# 핵심 시스템 계정 보호 판별 (잠금/삭제 시 차단)
_um_is_protected() {
    local _u="$1" _uid="$2"
    case "$_u" in
        root|daemon|bin|sys|sync|nobody|sshd|systemd-*|dbus|polkitd|postfix|mysql|mariadb|apache|httpd|www-data|nginx|named|chrony|ntp)
            return 0 ;;
    esac
    if [ -n "$_uid" ] && [ "$_uid" -eq 0 ] 2>/dev/null; then
        return 0
    fi
    return 1
}

# 안전한 랜덤 비밀번호 생성 (12자, 영대/영소/숫자/안전특수문자 포함, 혼동문자 0O1lI 제외)
_um_gen_password() {
    local _len="${1:-12}"
    local _pw=""
    if [ -r /dev/urandom ]; then
        local _u1 _l1 _d1 _s1 _rest
        _u1=$(LC_ALL=C tr -dc 'ABCDEFGHJKLMNPQRSTUVWXYZ' </dev/urandom 2>/dev/null | head -c 2)
        _l1=$(LC_ALL=C tr -dc 'abcdefghjkmnpqrstuvwxyz' </dev/urandom 2>/dev/null | head -c 3)
        _d1=$(LC_ALL=C tr -dc '23456789' </dev/urandom 2>/dev/null | head -c 2)
        _s1=$(LC_ALL=C tr -dc '@#%+=!' </dev/urandom 2>/dev/null | head -c 1)
        local _rem=$((_len - 8))
        [ "$_rem" -lt 1 ] && _rem=4
        _rest=$(LC_ALL=C tr -dc 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789' </dev/urandom 2>/dev/null | head -c "$_rem")
        _pw="${_u1}${_l1}${_d1}${_s1}${_rest}"
        if command -v shuf >/dev/null 2>&1; then
            _pw=$(printf '%s' "$_pw" | fold -w1 | shuf | tr -d '\n')
        fi
    fi
    if [ ${#_pw} -lt 8 ]; then
        _pw=$(date +%s%N 2>/dev/null | md5sum 2>/dev/null | awk '{print substr($1,1,10)"@A"}')
    fi
    printf '%s' "$_pw"
}

# 단일 계정의 실패 잠금 횟수 조회
_um_get_fail_cnt() {
    local _u="$1"
    local _cnt=0
    if [ "$_UM_FAIL_TOOL" = "faillock" ]; then
        _cnt=$(faillock --user "$_u" 2>/dev/null | awk 'NR>2 && $0 ~ /[0-9]{4}-[0-9]{2}-[0-9]{2}/ {c++} END{print c+0}')
    elif [ "$_UM_FAIL_TOOL" != "none" ]; then
        _cnt=$("$_UM_FAIL_TOOL" --user "$_u" 2>/dev/null | awk -v u="$_u" '$1==u {print $2+0; exit}')
    fi
    [ -z "$_cnt" ] && _cnt=0
    printf '%s' "$_cnt"
}

# 전체 계정 목록 로딩 (/etc/passwd + /etc/shadow + /etc/group + faillock + DB/도메인/이메일 일괄 집계)
_um_load_users() {
    _UM_NAMES=()
    _UM_UIDS=()
    _UM_GIDS=()
    _UM_HOMES=()
    _UM_SHELLS=()
    _UM_GECOS=()
    _UM_STATES=()
    _UM_FAILS=()
    _UM_SUDO=()
    _UM_DBS=()
    _UM_DOMAINS=()
    _UM_EMAILS=()
    _UM_TOTAL=0

    local _tmp="/tmp/.ums_list.$$"
    local _ftmp="/tmp/.ums_fail.$$"
    local _dtmp="/tmp/.ums_dom.$$"
    local _etmp="/tmp/.ums_eml.$$"
    local _dbtmp="/tmp/.ums_db.$$"
    : >"$_ftmp"; : >"$_dtmp"; : >"$_etmp"; : >"$_dbtmp"

    # 1) 로그인 실패 횟수 일괄 수집
    if [ "$_UM_FAIL_TOOL" = "faillock" ]; then
        faillock 2>/dev/null | awk '
            /:$/ { u=$1; sub(/:$/,"",u); next }
            /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ { if (u != "") cnt[u]++ }
            END { for (k in cnt) print k "\t" cnt[k] }
        ' >"$_ftmp"
    elif [ "$_UM_FAIL_TOOL" != "none" ]; then
        "$_UM_FAIL_TOOL" 2>/dev/null | awk 'NR>1 && $2 ~ /^[0-9]+$/ && $2+0 > 0 { print $1 "\t" $2 }' >"$_ftmp"
    fi

    # 2) DB 디렉토리 일괄 수집 (0.01초)
    if [ -d /var/lib/mysql ]; then
        ls -1 /var/lib/mysql 2>/dev/null >"$_dbtmp"
    fi

    # 3) 웹서버 vhost(Apache/Nginx)에서 계정별 대표 도메인 일괄 매핑
    local _vhf=""
    for _f in /etc/httpd/conf/httpd.conf /usr/local/apache/conf/httpd.conf /usr/local/apache2/conf/httpd.conf /etc/httpd/conf.d/*.conf /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
        [ -r "$_f" ] && _vhf="$_vhf $_f"
    done
    if [ -n "$_vhf" ]; then
        awk '
            /^[ \t]*#/ { next }
            tolower($1) ~ /^<virtualhost/ || /^[ \t]*server[ \t]*\{/ { sn=""; u=""; next }
            tolower($1) == "servername" || tolower($1) == "server_name" {
                d=$2; gsub(/[;"]/,"",d); sub(/^www\./,"",d);
                if (d != "" && d != "_" && d != "localhost" && sn == "") sn=d;
            }
            tolower($1) == "documentroot" || tolower($1) == "root" {
                p=$2; gsub(/[;"]/,"",p);
                if (match(p, /\/home[0-9]*\/[^\/]+/)) {
                    seg=substr(p, RSTART, RLENGTH);
                    sub(/^\/home[0-9]*\//, "", seg);
                    u=seg;
                }
            }
            (tolower($1) ~ /^<\/virtualhost/ || /^[ \t]*\}/) {
                if (u != "" && sn != "" && !(u in dom)) dom[u]=sn;
                sn=""; u="";
            }
            {
                if (u != "" && sn != "" && !(u in dom)) dom[u]=sn;
            }
            END { for (k in dom) print k "\t" dom[k] }
        ' $_vhf 2>/dev/null >"$_dtmp"
    fi

    # 4) 로컬 userinfo 등록 이메일 일괄 매핑
    if [ -r /root/userinfo ]; then
        awk '{
            u=$1;
            for (i=2; i<=NF; i++) {
                if ($i ~ /@/) {
                    gsub(/[|,<>]/,"",$i);
                    print u "\t" $i;
                    break;
                }
            }
        }' /root/userinfo 2>/dev/null >"$_etmp"
    fi

    # 5) /etc/passwd + /etc/shadow + /etc/group + 실패/DB/도메인/이메일 통합 파싱
    awk -F: -v ffile="$_ftmp" -v dbfile="$_dbtmp" -v dfile="$_dtmp" -v efile="$_etmp" '
        BEGIN {
            while ((getline line < ffile) > 0) {
                split(line, a, "\t");
                if (a[1] != "") failc[a[1]] = a[2] + 0;
            }
            close(ffile);
            while ((getline line < dbfile) > 0) {
                if (line != "") has_db[line] = 1;
            }
            close(dbfile);
            while ((getline line < dfile) > 0) {
                split(line, a, "\t");
                if (a[1] != "") dom[a[1]] = a[2];
            }
            close(dfile);
            while ((getline line < efile) > 0) {
                split(line, a, "\t");
                if (a[1] != "" && !(a[1] in eml)) eml[a[1]] = a[2];
            }
            close(efile);
            while ((getline line < "/etc/group") > 0) {
                n = split(line, g, ":");
                if (g[1] == "wheel" || g[1] == "sudo" || g[1] == "admin") {
                    m = split(g[4], mem, ",");
                    for (i = 1; i <= m; i++) {
                        if (mem[i] != "") is_sudo[mem[i]] = 1;
                    }
                }
            }
            close("/etc/group");
            if ((getline line < "/etc/shadow") >= 0) {
                close("/etc/shadow");
                while ((getline line < "/etc/shadow") > 0) {
                    split(line, s, ":");
                    sh[s[1]] = s[2];
                    expd[s[1]] = s[8];
                }
                close("/etc/shadow");
            }
        }
        {
            u=$1; uid=$3; gid=$4; gec=$5; hom=$6; shl=$7;
            gsub(/[\t|]/, " ", gec);
            st="ACTIVE";
            sp = (u in sh) ? sh[u] : "";
            if (sp ~ /^!/) st="LOCKED";
            else if (sp ~ /^\*/) st="NOPW";
            else if (sp == "") st="EMPTY";
            if (expd[u] != "" && expd[u] ~ /^[0-9]+$/ && expd[u]+0 > 0 && expd[u]+0 <= 1) st="EXPIRED";
            fc = (u in failc) ? failc[u] : 0;
            su = (u == "root" || (u in is_sudo)) ? 1 : 0;
            db = (u in has_db) ? "DB" : "--";
            dm = (u in dom) ? dom[u] : "";
            em = (u in eml) ? eml[u] : "";
            gsub(/\|/, "", dm); gsub(/\|/, "", em);
            print u "|" uid "|" gid "|" hom "|" shl "|" gec "|" st "|" fc "|" su "|" db "|" dm "|" em;
        }
    ' /etc/passwd >"$_tmp" 2>/dev/null

    local i=0 _nm _uid _gid _hom _shl _gec _st _fc _su _db _dm _em
    while IFS='|' read -r _nm _uid _gid _hom _shl _gec _st _fc _su _db _dm _em; do
        [ -n "$_nm" ] || continue
        _UM_NAMES[$i]="$_nm"
        _UM_UIDS[$i]="$_uid"
        _UM_GIDS[$i]="$_gid"
        _UM_HOMES[$i]="$_hom"
        _UM_SHELLS[$i]="$_shl"
        _UM_GECOS[$i]="$_gec"
        _UM_STATES[$i]="$_st"
        _UM_FAILS[$i]="${_fc:-0}"
        _UM_SUDO[$i]="${_su:-0}"
        _UM_DBS[$i]="${_db:---}"
        _UM_DOMAINS[$i]="$_dm"
        _UM_EMAILS[$i]="$_em"
        i=$((i + 1))
    done <"$_tmp"
    _UM_TOTAL=$i
    rm -f "$_tmp" "$_ftmp" "$_dtmp" "$_etmp" "$_dbtmp" 2>/dev/null
}

# 단일 사용자 행 상태만 즉시 갱신 (Lock/Unlock/Unban 직후 초고속 반영)
_um_refresh_one() {
    local idx="$1"
    local u="${_UM_NAMES[$idx]}"
    local line
    line=$(awk -F: -v target="$u" '$1==target {g=$5; gsub(/\|/," ",g); print $3"|"$4"|"g"|"$6"|"$7; exit}' /etc/passwd 2>/dev/null)
    if [ -n "$line" ]; then
        local _uid _gid _gec _hom _shl
        IFS='|' read -r _uid _gid _gec _hom _shl <<EOF
$line
EOF
        _UM_UIDS[$idx]="$_uid"
        _UM_GIDS[$idx]="$_gid"
        _UM_GECOS[$idx]="$_gec"
        _UM_HOMES[$idx]="$_hom"
        _UM_SHELLS[$idx]="$_shl"
    fi
    local _sp
    _sp=$(awk -F: -v target="$u" '$1==target {print $2; exit}' /etc/shadow 2>/dev/null)
    local _st="ACTIVE"
    case "$_sp" in
        !*) _st="LOCKED" ;;
        \**) _st="NOPW" ;;
        "") _st="EMPTY" ;;
    esac
    _UM_STATES[$idx]="$_st"
    _UM_FAILS[$idx]=$(_um_get_fail_cnt "$u")
}

# 필터 및 검색 뷰 빌드
_um_build_view() {
    _UM_VIEW=()
    local i=0 vc=0
    local _sq=""
    [ -n "$_UM_SEARCH" ] && _sq=$(printf '%s' "$_UM_SEARCH" | tr '[:upper:]' '[:lower:]')

    while [ "$i" -lt "$_UM_TOTAL" ]; do
        local _nm="${_UM_NAMES[$i]}"
        local _uid="${_UM_UIDS[$i]}"
        local _hom="${_UM_HOMES[$i]}"
        local _shl="${_UM_SHELLS[$i]}"
        local _gec="${_UM_GECOS[$i]}"
        local _st="${_UM_STATES[$i]}"
        local _fc="${_UM_FAILS[$i]}"
        local _su="${_UM_SUDO[$i]}"
        local _ok=1

        case "$_UM_FILTER" in
            users)
                # 일반 사용자: UID >= MIN_UID (nobody 제외) 또는 /home/ 하위 홈 보유 계정
                if [ "$_nm" = "nobody" ] || [ "$_nm" = "nfsnobody" ]; then
                    _ok=0
                elif [ "$_uid" -lt "$_UM_MIN_UID" ] 2>/dev/null; then
                    case "$_hom" in
                        /home/*|/home1/*|/home2/*) _ok=1 ;;
                        *) _ok=0 ;;
                    esac
                fi
                ;;
            locked)
                if [ "$_st" != "LOCKED" ] && [ "${_fc:-0}" -le 0 ] 2>/dev/null; then
                    _ok=0
                fi
                ;;
            active)
                if [ "$_st" != "ACTIVE" ] || [ "${_fc:-0}" -gt 0 ] 2>/dev/null; then
                    _ok=0
                fi
                ;;
            sudo)
                [ "$_su" = "1" ] || _ok=0
                ;;
            system)
                [ "$_uid" -lt "$_UM_MIN_UID" ] 2>/dev/null || _ok=0
                ;;
            all)
                _ok=1
                ;;
        esac

        if [ "$_ok" -eq 1 ] && [ -n "$_sq" ]; then
            local _hay
            _hay=$(printf '%s %s %s %s %s %s' "$_nm" "$_hom" "$_gec" "$_shl" "${_UM_DOMAINS[$i]}" "${_UM_EMAILS[$i]}" | tr '[:upper:]' '[:lower:]')
            case "$_hay" in
                *"$_sq"*) _ok=1 ;;
                *) _ok=0 ;;
            esac
        fi

        if [ "$_ok" -eq 1 ]; then
            _UM_VIEW[$vc]=$i
            vc=$((vc + 1))
        fi
        i=$((i + 1))
    done
    _UM_VCNT=$vc
    if [ "$_UM_CUR" -ge "$_UM_VCNT" ]; then
        _UM_CUR=$((_UM_VCNT > 0 ? _UM_VCNT - 1 : 0))
    fi
}

# 레이아웃 계산 (dms/pms와 동일 규격 — _get_term_size로 실제 창 크기 활용 + 적정 가로폭 정렬)
_um_init_layout() {
    local _TS_LINES="" _TS_COLS=""
    _get_term_size
    _UM_ROWS="${_TS_LINES:-24}"
    _UM_COLS="${_TS_COLS:-80}"
    [ "$_UM_COLS" -lt 70 ] && _UM_COLS=70
    [ "$_UM_ROWS" -lt 16 ] && _UM_ROWS=16
    _UM_PAGE_H=$((_UM_ROWS - 10))
    [ "$_UM_PAGE_H" -lt 6 ] && _UM_PAGE_H=6
    local _w=$((_UM_COLS - 1))
    [ "$_w" -gt 132 ] && _w=132
    [ "$_w" -lt 60 ] && _w=60
    _UM_HLINE=$(printf '%*s' "$_w" '' | tr ' ' '-')
    _UM_DIRTY=1
    if [ "$_UM_ENC" = "euckr" ]; then
        _UM_S_CUR=">"; _UM_S_BUL="-"
    else
        _UM_S_CUR="▶"; _UM_S_BUL="•"
    fi
}

# 대응 DB 빠른 존재 여부 확인 (로컬 데이터 디렉토리 또는 MySQL)
_um_quick_db_badge() {
    local _u="$1"
    if [ -d "/var/lib/mysql/$_u" ]; then
        printf 'DB:OK'
        return 0
    fi
    if [ -n "$_UM_MYSQL" ]; then
        local _hit
        _hit=$("$_UM_MYSQL" -NBe "SHOW DATABASES LIKE '${_u}'" 2>/dev/null | head -n1)
        if [ -n "$_hit" ]; then
            printf 'DB:OK'
            return 0
        fi
    fi
    printf 'DB:-'
}

# 호스팅 계정 정보에서 이메일/휴대폰 번호 추출 헬퍼 (/script/is 또는 /root/userinfo 기반)
_um_extract_hosting_contact() {
    local _u="$1"
    _UM_C_EMAIL=""
    _UM_C_PHONE=""
    _UM_C_DOMAIN=""

    if [ -x /script/is ] && _um_has_is_data; then
        local _is_out
        _is_out=$(/script/is "$_u" 2>/dev/null | _um_norm_out)
        _UM_C_EMAIL=$(printf '%s\n' "$_is_out" | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | head -n1)
        _UM_C_PHONE=$(printf '%s\n' "$_is_out" | grep -oE '01[016789]-?[0-9]{3,4}-?[0-9]{4}' | head -n1)
        _UM_C_DOMAIN=$(printf '%s\n' "$_is_out" | grep -oE '([a-zA-Z0-9-]+\.)+(com|co\.kr|kr|net|org|or\.kr|ne\.kr|pe\.kr|re\.kr|go\.kr|ac\.kr|io|dev|shop|biz|info)' | grep -v '@' | head -n1)
    fi
    if [ -z "$_UM_C_EMAIL" ] && [ -r /root/userinfo ]; then
        _UM_C_EMAIL=$(awk -v u="$_u" '$1==u {for(i=2;i<=NF;i++) if($i ~ /@/) {print $i; exit}}' /root/userinfo 2>/dev/null)
    fi
    if [ -z "$_UM_C_PHONE" ] && [ -r /root/_ispnuma ]; then
        local _p
        _p=$(tr -d ' \r\n' </root/_ispnuma 2>/dev/null)
        case "$_p" in 01*) _UM_C_PHONE="$_p" ;; esac
    fi
}

# ==============================================================================
# 액션 1: 계정 종합 상세 보기 (Enter / v)
# ==============================================================================
_um_show_detail() {
    local idx="$1"
    local u="${_UM_NAMES[$idx]}"
    local hom="${_UM_HOMES[$idx]}"
    local shl="${_UM_SHELLS[$idx]}"
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\033[2J\033[H'
    _um_p '\033[1;36m* 사용자 종합 상세 정보: %s\033[0m\n' "$u"
    printf '%s\n' "------------------------------------------------------------------------"

    _um_p '\033[1;33m[1] 시스템 계정 · 권한 · 잠금 상태\033[0m\n'
    id "$u" 2>&1
    passwd -S "$u" 2>&1
    if [ "$_UM_FAIL_TOOL" = "faillock" ]; then
        printf 'faillock: '
        faillock --user "$u" 2>&1 | tail -n 5
    elif [ "$_UM_FAIL_TOOL" != "none" ]; then
        printf 'pam_tally2: '
        "$_UM_FAIL_TOOL" --user "$u" 2>&1
    fi
    printf 'Shell: %s  |  Home: %s\n' "$shl" "$hom"
    if command -v chage >/dev/null 2>&1; then
        chage -l "$u" 2>/dev/null | head -n 6
    fi

    _um_p '\n\033[1;33m[2] 홈 디렉토리 · 웹루트 · 디스크 용량\033[0m\n'
    if [ -d "$hom" ]; then
        ls -ld "$hom" 2>&1
        for _wr in "$hom/public_html" "$hom/www" "$hom/html"; do
            [ -d "$_wr" ] && ls -ld "$_wr" 2>&1
        done
        _um_p '디스크 사용량(du): '
        du -sh "$hom" 2>/dev/null || _um_p '(계산 불가)\n'
    else
        _um_p '  ⚠ 홈 디렉토리가 존재하지 않습니다: %s\n' "$hom"
    fi
    if command -v quota >/dev/null 2>&1; then
        local _qout
        _qout=$(quota -u "$u" 2>/dev/null)
        [ -n "$_qout" ] && printf '%s\n' "$_qout"
    fi

    _um_p '\n\033[1;33m[3] 대응 데이터베이스(MySQL/MariaDB) 점검\033[0m\n'
    local _db_found=0
    if [ -d "/var/lib/mysql/$u" ]; then
        _um_p '  데이터 디렉토리: '; du -sh "/var/lib/mysql/$u" 2>/dev/null
        _db_found=1
    fi
    if [ -n "$_UM_MYSQL" ]; then
        local _dbs
        _dbs=$("$_UM_MYSQL" -NBe "SHOW DATABASES LIKE '${u}%'" 2>/dev/null)
        if [ -n "$_dbs" ]; then
            _um_p '  매칭 DB 목록:\n'
            printf '%s\n' "$_dbs" | sed 's/^/    - /'
            _db_found=1
        fi
    fi
    [ "$_db_found" -eq 0 ] && _um_p '  (대응하는 DB가 없거나 DB root 자동접속 불가)\n'

    _um_p '\n\033[1;33m[4] 최근 접속 및 실행 중 프로세스\033[0m\n'
    if command -v lastlog >/dev/null 2>&1; then
        lastlog -u "$u" 2>/dev/null | tail -n 1
    fi
    local _pcnt
    _pcnt=$(ps -u "$u" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    _um_p '  현재 실행 중 프로세스: %s개\n' "${_pcnt:-0}"

    if [ "$_UM_HOSTING" -eq 1 ] && [ -x /script/is ]; then
        _um_p '\n\033[1;33m[5] 호스팅 계정 종합 정보 (/script/is %s)\033[0m\n' "$u"
        _um_run_is "$u" 30
    fi

    printf '%s\n' "------------------------------------------------------------------------"
    _um_pause "Enter를 누르면 목록으로 돌아갑니다..."
}

# ==============================================================================
# 액션 2: Lock / Unlock 토글 (Space / l)
# ==============================================================================
_um_toggle_lock() {
    local idx="$1"
    local u="${_UM_NAMES[$idx]}"
    local uid="${_UM_UIDS[$idx]}"
    local st="${_UM_STATES[$idx]}"

    if _um_is_protected "$u" "$uid"; then
        _UM_MSG="⚠ 핵심 시스템 계정 '${u}' 는 잠금/해제 보호 대상입니다."
        return 1
    fi

    if [ "$st" = "LOCKED" ]; then
        passwd -u "$u" >/dev/null 2>&1
        _um_refresh_one "$idx"
        _UM_MSG="✔ '${u}' 계정 잠금 해제(passwd -u) 완료! (현재: ${_UM_STATES[$idx]})"
    else
        tput cnorm 2>/dev/null
        stty echo 2>/dev/null
        _um_p '\n\033[1;33m🔒 계정 [%s] 로그인을 잠글까요? (passwd -l) [y/N]: \033[0m' "$u"
        local _ans=""
        IFS= read -r _ans </dev/tty
        case "$_ans" in
            y|Y)
                passwd -l "$u" >/dev/null 2>&1
                _um_refresh_one "$idx"
                _UM_MSG="✔ '${u}' 계정 잠금(passwd -l) 완료!"
                ;;
            *)
                _UM_MSG="취소됨: '${u}'"
                ;;
        esac
    fi
}

# ==============================================================================
# 액션 3: 완전 Unban (faillock/pam_tally2 초기화 + passwd -u + 차단IP 확인) (u 키)
# ==============================================================================
_um_unban_user() {
    local idx="$1"
    local u="${_UM_NAMES[$idx]}"
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\033[2J\033[H'
    _um_p '\033[1;36m* 계정 완전 잠금 해제 (Unban): %s\033[0m\n' "$u"
    printf '%s\n' "------------------------------------------------------------------------"

    local _last_ip=""
    if [ "$_UM_FAIL_TOOL" = "faillock" ]; then
        _um_p '▶ [1/3] faillock 실패 기록 확인 및 초기화...\n'
        faillock --user "$u" 2>&1
        _last_ip=$(faillock --user "$u" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -n1)
        faillock --user "$u" --reset 2>&1
        faillock --user "$u" 2>&1
    elif [ "$_UM_FAIL_TOOL" != "none" ]; then
        _um_p '▶ [1/3] pam_tally2 실패 기록 확인 및 초기화...\n'
        "$_UM_FAIL_TOOL" --user "$u" 2>&1
        _last_ip=$("$_UM_FAIL_TOOL" --user "$u" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -n1)
        "$_UM_FAIL_TOOL" --user "$u" --reset 2>&1
        "$_UM_FAIL_TOOL" --user "$u" 2>&1
    else
        _um_p '▶ [1/3] faillock/pam_tally2 미설치 환경 — 건너뜀\n'
    fi

    _um_p '\n▶ [2/3] passwd 잠금 해제 (passwd -u)...\n'
    passwd -u "$u" 2>&1 || true
    passwd -S "$u" 2>&1

    _um_p '\n▶ [3/3] 최근 실패 IP 방화벽/hosts.deny 차단 여부 점검...\n'
    if [ -n "$_last_ip" ]; then
        _um_p '  최근 실패 IP: %s\n' "$_last_ip"
        local _ipt_hit="" _hd_hit=""
        command -v iptables >/dev/null 2>&1 && _ipt_hit=$(iptables -nL 2>/dev/null | grep -F "$_last_ip" | head -n 5)
        [ -r /etc/hosts.deny ] && _hd_hit=$(grep -F "$_last_ip" /etc/hosts.deny 2>/dev/null | head -n 5)
        if [ -n "$_ipt_hit" ]; then
            _um_p '  \033[1;31m⚠ iptables 차단 발견:\033[0m\n%s\n' "$_ipt_hit"
        else
            _um_p '  iptables 차단 없음\n'
        fi
        if [ -n "$_hd_hit" ]; then
            _um_p '  \033[1;31m⚠ /etc/hosts.deny 차단 발견:\033[0m\n%s\n' "$_hd_hit"
        fi
    else
        _um_p '  추출된 최근 실패 IP 없음\n'
    fi

    _um_refresh_one "$idx"
    _UM_MSG="✔ '${u}' Unban 완료 (상태: ${_UM_STATES[$idx]} / 실패: ${_UM_FAILS[$idx]})"
    printf '%s\n' "------------------------------------------------------------------------"
    _um_pause "Enter를 누르면 목록으로 돌아갑니다..."
}

# ==============================================================================
# 액션 4: 비밀번호 리셋 (임의 랜덤 생성 / 수동 입력) + 호스팅 메일/SMS 발송 연동 (p 키)
# ==============================================================================
_um_reset_password() {
    local idx="$1"
    local u="${_UM_NAMES[$idx]}"
    local uid="${_UM_UIDS[$idx]}"

    if [ "$u" = "root" ] || [ "$uid" -eq 0 ] 2>/dev/null; then
        _UM_MSG="⚠ root 비밀번호는 보안상 터미널에서 직접 'passwd root' 를 사용하세요."
        return 1
    fi

    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\033[2J\033[H'
    _um_p '\033[1;36m* 비밀번호 리셋 & 알림 발송 마법사: %s\033[0m\n' "$u"
    printf '%s\n' "------------------------------------------------------------------------"

    # 호스팅 환경이면 연락처 사전 조회
    _UM_C_EMAIL=""; _UM_C_PHONE=""; _UM_C_DOMAIN=""
    if [ "$_UM_HOSTING" -eq 1 ]; then
        _um_extract_hosting_contact "$u"
        _um_p '  [호스팅 연락처] 도메인: \033[1;37m%s\033[0m | 메일: \033[1;32m%s\033[0m | 휴대폰: \033[1;33m%s\033[0m\n' \
            "${_UM_C_DOMAIN:--}" "${_UM_C_EMAIL:--}" "${_UM_C_PHONE:--}"
        printf '%s\n' "------------------------------------------------------------------------"
    fi

    local _rand_pw
    _rand_pw=$(_um_gen_password 12)
    _um_p '  \033[1;33m1.\033[0m 🎲 임의 랜덤 비밀번호로 리셋  (생성됨: \033[1;32m%s\033[0m)\n' "$_rand_pw"
    _um_p '  \033[1;33m2.\033[0m ⌨️  새 비밀번호 직접 입력\n'
    _um_p '  \033[1;33m3.\033[0m 🔄 랜덤 비밀번호 다시 생성\n'
    _um_p '  \033[0;37m0.\033[0m 취소\n'
    printf '%s\n' "------------------------------------------------------------------------"
    _um_p '선택 [0-3] (기본 1): '
    local _sel=""
    IFS= read -r _sel </dev/tty
    [ -z "$_sel" ] && _sel="1"

    while [ "$_sel" = "3" ]; do
        _rand_pw=$(_um_gen_password 12)
        _um_p '  🎲 새로 생성된 비밀번호: \033[1;32m%s\033[0m  — 이 값으로 진행할까요? [1=적용 / 3=재생성 / 0=취소]: ' "$_rand_pw"
        IFS= read -r _sel </dev/tty
        [ -z "$_sel" ] && _sel="1"
    done

    local _new_pw=""
    case "$_sel" in
        1) _new_pw="$_rand_pw" ;;
        2)
            _um_p '새 비밀번호 입력: '
            IFS= read -r _new_pw </dev/tty
            if [ -z "$_new_pw" ]; then
                _UM_MSG="취소됨: 빈 비밀번호"
                return 0
            fi
            ;;
        *)
            _UM_MSG="취소됨"
            return 0
            ;;
    esac

    # DB 비밀번호 동시 변경 여부
    local _chg_db="n"
    _um_p '\nDB 비밀번호도 함께 변경할까요? [y/N] (일반 FTP/SSH 초기화는 N 권장): '
    local _db_ans=""
    IFS= read -r _db_ans </dev/tty
    case "$_db_ans" in y|Y) _chg_db="y" ;; esac

    _um_p '\n▶ 비밀번호 변경 및 로그인 락 초기화 실행 중...\n'
    local _pw_ok=0
    if [ "$_UM_HOSTING" -eq 1 ] && [ -x /root/ppass ]; then
        # 호스팅 표준 /root/ppass 연동 (비번 변경 + pam_tally2 리셋 + DB 변경 질의)
        printf '%s\n' "$_chg_db" | /root/ppass "$u" "$_new_pw" 2>&1 | _um_norm_out
        _pw_ok=1
    else
        if command -v chpasswd >/dev/null 2>&1; then
            printf '%s:%s\n' "$u" "$_new_pw" | chpasswd 2>&1 && _pw_ok=1
        else
            printf '%s\n' "$_new_pw" | passwd --stdin "$u" 2>&1 && _pw_ok=1
        fi
        # DB 비밀번호 동시 변경 요청 시
        if [ "$_chg_db" = "y" ] && [ -n "$_UM_MYSQL" ]; then
            _um_p '▶ DB 사용자(%s) 비밀번호 변경 시도...\n' "$u"
            "$_UM_MYSQL" -e "ALTER USER '${u}'@'localhost' IDENTIFIED BY '${_new_pw}'; FLUSH PRIVILEGES;" 2>/dev/null \
                || "$_UM_MYSQL" -e "SET PASSWORD FOR '${u}'@'localhost' = PASSWORD('${_new_pw}'); FLUSH PRIVILEGES;" 2>/dev/null \
                || _um_p '  ⚠ DB 비밀번호 자동 변경 실패 (수동 확인 필요)\n'
        fi
    fi

    # faillock / pam_tally2 / passwd -u 추가 보강
    if [ "$_UM_FAIL_TOOL" = "faillock" ]; then
        faillock --user "$u" --reset >/dev/null 2>&1
    elif [ "$_UM_FAIL_TOOL" != "none" ]; then
        "$_UM_FAIL_TOOL" --user "$u" --reset >/dev/null 2>&1
    fi
    passwd -u "$u" >/dev/null 2>&1

    _um_refresh_one "$idx"
    _um_p '\n\033[1;32m✔ 비밀번호 리셋 완료!\033[0m  계정: \033[1;37m%s\033[0m  |  새 비번: \033[1;33m%s\033[0m  |  실패횟수: %s\n' \
        "$u" "$_new_pw" "${_UM_FAILS[$idx]}"

    # 호스팅 특화 알림 발송 (메일 / SMS / 로그인 검증)
    if [ "$_UM_HOSTING" -eq 1 ] && { [ -x /script/loginchecksend ] || [ -x /script/sms ] || [ -x /script/logincheck ]; }; then
        printf '%s\n' "------------------------------------------------------------------------"
        _um_p '\033[1;36m📨 고객 리셋 안내 발송 및 로그인 검증\033[0m\n'
        _um_p '  등록 이메일: \033[1;32m%s\033[0m  |  휴대폰: \033[1;33m%s\033[0m\n' "${_UM_C_EMAIL:--}" "${_UM_C_PHONE:--}"
        [ -x /script/loginchecksend ] && _um_p '  \033[1;33m1.\033[0m 📧 이메일 발송 (/script/loginchecksend)\n'
        [ -x /script/sms ] && _um_p '  \033[1;33m2.\033[0m 📱 SMS 문자 발송 (/script/sms)\n'
        [ -x /script/loginchecksend ] && [ -x /script/sms ] && _um_p '  \033[1;33m3.\033[0m 🚀 이메일 + SMS 일괄 발송 (권장)\n'
        [ -x /script/logincheck ] && _um_p '  \033[1;33m4.\033[0m 🔐 로그인 성공 검증 (/script/logincheck)\n'
        _um_p '  \033[0;37m0.\033[0m 발송 안 함 (종료)\n'
        _um_p '선택 [0-4]: '
        local _send_sel=""
        IFS= read -r _send_sel </dev/tty

        case "$_send_sel" in
            1)
                if [ -x /script/loginchecksend ]; then
                    /script/loginchecksend "$u" "$_new_pw" 2>&1 | _um_norm_out
                    _UM_MSG="✔ '${u}' 비번 리셋 + 이메일 발송 완료!"
                fi
                ;;
            2|3)
                if [ "$_send_sel" = "3" ] && [ -x /script/loginchecksend ]; then
                    _um_p '\n▶ [1/2] 이메일 발송 중 (/script/loginchecksend)...\n'
                    /script/loginchecksend "$u" "$_new_pw" 2>&1 | _um_norm_out
                fi
                if [ -x /script/sms ]; then
                    local _target_phone="$_UM_C_PHONE"
                    _um_p '\n▶ SMS 수신 휴대폰 번호 (Enter=기본값 [%s]): ' "${_target_phone:-없음}"
                    local _in_ph=""
                    IFS= read -r _in_ph </dev/tty
                    [ -n "$_in_ph" ] && _target_phone="$_in_ph"
                    if [ -n "$_target_phone" ]; then
                        local _sms_body=""
                        if [ -r /backup/ban/_sms ] && [ -s /backup/ban/_sms ]; then
                            _sms_body=$(cat /backup/ban/_sms 2>/dev/null)
                        else
                            _sms_body="[비밀번호 초기화] ID: ${u} / PW: ${_new_pw}"
                        fi
                        _um_p '▶ SMS 발송 중 -> %s ...\n' "$_target_phone"
                        # 비대화형 stdin 소비 함정 방지: 반드시 $2 인자로 본문 직접 전달
                        /script/sms "$_target_phone" "$_sms_body" 2>&1 | _um_norm_out
                        _UM_MSG="✔ '${u}' 비번 리셋 + 안내 발송 완료!"
                    else
                        _um_p '  ⚠ 휴대폰 번호가 없어 SMS 발송을 건너뛰었습니다.\n'
                    fi
                fi
                ;;
            4)
                if [ -x /script/logincheck ]; then
                    /script/logincheck "$u" "$_new_pw" 2>&1 | _um_norm_out
                fi
                _UM_MSG="✔ '${u}' 비번 리셋 및 로그인 검증 완료"
                ;;
            *)
                _UM_MSG="✔ '${u}' 비번 리셋 완료 (새 비번: ${_new_pw})"
                ;;
        esac
    else
        _UM_MSG="✔ '${u}' 비번 리셋 완료 (새 비번: ${_new_pw})"
    fi

    _um_pause "Enter를 누르면 목록으로 돌아갑니다..."
}

# ==============================================================================
# 액션 5: 대응 DB & 홈폴더 통합 점검/조치 (d 키)
# ==============================================================================
_um_check_db_home() {
    local idx="$1"
    local u="${_UM_NAMES[$idx]}"
    local hom="${_UM_HOMES[$idx]}"

    while :; do
        tput cnorm 2>/dev/null
        stty echo 2>/dev/null
        printf '\033[2J\033[H'
        _um_p '\033[1;36m* 대응 DB & 홈폴더 통합 점검/조치: %s (%s)\033[0m\n' "$u" "$hom"
        printf '%s\n' "------------------------------------------------------------------------"
        _um_p '  \033[1;33m1.\033[0m 📁 홈폴더 종합 점검 (권한·웹루트·디스크 용량·Top 15 폴더·Quota)\n'
        _um_p '  \033[1;33m2.\033[0m 🔧 홈폴더/웹루트(public_html) 소유권·권한 자동 보정\n'
        _um_p '  \033[1;33m3.\033[0m 🔎 홈폴더 내 대용량 파일 탐색 (50MB 이상)\n'
        _um_p '  \033[1;33m4.\033[0m 📂 홈폴더 파일 탐색기 열기 (explorer)\n'
        _um_p '  \033[1;33m5.\033[0m 🗄️  대응 DB 종합 점검 (DB목록·테이블 수·용량·DB유저 권한)\n'
        _um_p '  \033[1;33m6.\033[0m 💾 대응 DB 안전 백업 (mysqldump)\n'
        _um_p '  \033[1;33m7.\033[0m 💻 대응 DB 콘솔 접속 (mysql %s)\n' "$u"
        _um_p '  \033[0;37m0.\033[0m 돌아가기\n'
        printf '%s\n' "------------------------------------------------------------------------"
        _um_p '선택 [0-7]: '
        local _sel=""
        IFS= read -r _sel </dev/tty
        case "$_sel" in
            1)
                printf '\n'
                if [ -d "$hom" ]; then
                    ls -ld "$hom" 2>&1
                    for _wr in "$hom/public_html" "$hom/www" "$hom/html"; do
                        [ -d "$_wr" ] && ls -ld "$_wr" 2>&1
                    done
                    _um_p '\n▶ 하위 디렉토리 크기 Top 15:\n'
                    du -h --max-depth=2 "$hom" 2>/dev/null | sort -hr 2>/dev/null | head -n 15 \
                        || du -sk "$hom"/* 2>/dev/null | sort -rn | head -n 15
                    if command -v quota >/dev/null 2>&1; then
                        _um_p '\n▶ 디스크 Quota:\n'
                        quota -u "$u" 2>&1
                    fi
                else
                    _um_p '⚠ 홈 디렉토리가 존재하지 않습니다: %s\n' "$hom"
                fi
                _um_pause
                ;;
            2)
                if [ -d "$hom" ]; then
                    _um_p '\n홈폴더(%s) 소유권(%s:%s) 및 권한(701 / public_html 750)을 보정할까요? [y/N]: ' "$hom" "$u" "$u"
                    local _ans=""
                    IFS= read -r _ans </dev/tty
                    case "$_ans" in
                        y|Y)
                            chmod 701 "$hom" 2>&1
                            chown "${u}:${u}" "$hom" 2>&1
                            if [ -d "$hom/public_html" ]; then
                                chown -R "${u}:${u}" "$hom/public_html" 2>&1
                                chmod 750 "$hom/public_html" 2>&1
                            else
                                _um_p 'public_html 폴더가 없습니다. 새로 생성할까요? [y/N]: '
                                local _mk=""
                                IFS= read -r _mk </dev/tty
                                case "$_mk" in
                                    y|Y)
                                        mkdir -p "$hom/public_html"
                                        chown -R "${u}:${u}" "$hom/public_html"
                                        chmod 750 "$hom/public_html"
                                        ;;
                                esac
                            fi
                            ls -ald "$hom" "$hom/public_html" 2>/dev/null
                            _UM_MSG="✔ '${u}' 홈폴더 권한 보정 완료"
                            ;;
                    esac
                else
                    _um_p '⚠ 홈 디렉토리가 없습니다: %s\n' "$hom"
                fi
                _um_pause
                ;;
            3)
                if [ -d "$hom" ]; then
                    _um_p '\n▶ %s 내 50MB 이상 대용량 파일 목록:\n' "$hom"
                    find "$hom" -type f -size +50M -exec ls -lh {} + 2>/dev/null | head -n 30
                else
                    _um_p '⚠ 홈 디렉토리가 없습니다: %s\n' "$hom"
                fi
                _um_pause
                ;;
            4)
                if [ -d "$hom" ]; then
                    explorer "$hom"
                else
                    _um_p '⚠ 홈 디렉토리가 없습니다: %s\n' "$hom"
                    _um_pause
                fi
                ;;
            5)
                printf '\n'
                if [ -d "/var/lib/mysql/$u" ]; then
                    _um_p '▶ 물리 DB 디렉토리: '
                    du -sh "/var/lib/mysql/$u" 2>/dev/null
                fi
                if [ -n "$_UM_MYSQL" ]; then
                    _um_p '▶ 매칭 DB 및 용량 (MB):\n'
                    "$_UM_MYSQL" -e "
                        SELECT table_schema AS DB, COUNT(*) AS Tables,
                               ROUND(SUM(data_length + index_length)/1024/1024, 2) AS Size_MB
                        FROM information_schema.tables
                        WHERE table_schema LIKE '${u}%'
                        GROUP BY table_schema;
                    " 2>&1 || "$_UM_MYSQL" -e "SHOW DATABASES LIKE '${u}%';" 2>&1
                    _um_p '\n▶ DB 사용자 계정(mysql.user):\n'
                    "$_UM_MYSQL" -e "SELECT User, Host FROM mysql.user WHERE User LIKE '${u}%';" 2>&1
                else
                    _um_p '⚠ mysql/mariadb 클라이언트를 찾지 못했습니다.\n'
                fi
                _um_pause
                ;;
            6)
                local _bdir="/tmp"
                [ -d /backup/mysqldump ] && _bdir="/backup/mysqldump"
                [ -d /backup/ban ] && _bdir="/backup/ban"
                local _bfile="${_bdir}/${u}_$(date +%Y%m%d_%H%M%S).sql"
                _um_p '\n▶ DB [%s] 백업 -> %s\n' "$u" "$_bfile"
                if [ -n "$_UM_MYSQLDUMP" ]; then
                    if "$_UM_MYSQLDUMP" --single-transaction --quick "$u" >"$_bfile" 2>/dev/null \
                       || "$_UM_MYSQLDUMP" "$u" >"$_bfile" 2>/dev/null; then
                        ls -lh "$_bfile"
                        _UM_MSG="✔ DB 백업 완료: $_bfile"
                    else
                        rm -f "$_bfile" 2>/dev/null
                        _um_p '⚠ mysqldump 실패 (DB명 확인 또는 root 인증 필요)\n'
                    fi
                else
                    _um_p '⚠ mysqldump 명령을 찾지 못했습니다.\n'
                fi
                _um_pause
                ;;
            7)
                if [ -n "$_UM_MYSQL" ]; then
                    "$_UM_MYSQL" "$u"
                else
                    _um_p '⚠ mysql/mariadb 클라이언트를 찾지 못했습니다.\n'
                    _um_pause
                fi
                ;;
            0|"") break ;;
        esac
    done
}

# ==============================================================================
# 액션 6: 호스팅 계정 전용 액션 센터 (H 키 — 로컬 /script/* 자동 연동)
# ==============================================================================
_um_hosting_menu() {
    local idx="$1"
    local u="${_UM_NAMES[$idx]}"

    if [ "$_UM_HOSTING" -ne 1 ]; then
        _UM_MSG="ℹ 이 서버에는 로컬 호스팅 관리 스크립트(/script/*)가 설치되어 있지 않습니다."
        return 0
    fi

    _um_extract_hosting_contact "$u"

    while :; do
        tput cnorm 2>/dev/null
        stty echo 2>/dev/null
        printf '\033[2J\033[H'
        _um_p '\033[1;36m* 호스팅 계정 통합 액션 센터: %s\033[0m\n' "$u"
        _um_p '  도메인: \033[1;37m%s\033[0m  |  메일: \033[1;32m%s\033[0m  |  휴대폰: \033[1;33m%s\033[0m\n' \
            "${_UM_C_DOMAIN:--}" "${_UM_C_EMAIL:--}" "${_UM_C_PHONE:--}"
        printf '%s\n' "------------------------------------------------------------------------"
        _um_p '  \033[1;33m 1.\033[0m 📋 계정 종합 정보 조회 (/script/is)\n'
        _um_p '  \033[1;33m 2.\033[0m 🌐 전 서버 계정/도메인 검색 (/script/isall)\n'
        _um_p '  \033[1;33m 3.\033[0m 📊 트래픽 현황 조회 (/script/webfer) & 리셋 로그 (/script/ta)\n'
        _um_p '  \033[1;33m 4.\033[0m 🔄 트래픽 제한 초기화 (/script/treset)\n'
        _um_p '  \033[1;33m 5.\033[0m 💿 디스크 Quota 확인/수정 (quota / edquota)\n'
        _um_p '  \033[1;33m 6.\033[0m 🔐 계정 로그인 테스트 (/script/logincheck)\n'
        _um_p '  \033[1;33m 7.\033[0m 📧 등록 이메일 수정 (/script/vu) / 안내 메일 발송 (/root/emailsend)\n'
        _um_p '  \033[1;33m 8.\033[0m 📱 고객 휴대폰 SMS 발송 (/script/sms)\n'
        _um_p '  \033[1;33m 9.\033[0m 🔒 SSL 인증서 설치/점검 (/script/ssl)\n'
        _um_p '  \033[1;33m10.\033[0m 🌍 도메인/DNS 변경 (/root/dnschg) & 가상호스트 확인\n'
        _um_p '  \033[1;33m11.\033[0m 💰 만기·연장·단위 증설 계산 (/root/emoney · /script/da)\n'
        _um_p '  \033[0;37m 0.\033[0m 돌아가기\n'
        printf '%s\n' "------------------------------------------------------------------------"
        _um_p '선택 [0-11]: '
        local _sel=""
        IFS= read -r _sel </dev/tty
        case "$_sel" in
            1)
                _um_run_is "$u"
                _um_pause ;;
            2)
                [ -x /script/isall ] && /script/isall "$u" 2>&1 | _um_norm_out || _um_p '⚠ /script/isall 없음\n'
                _um_pause ;;
            3)
                [ -x /script/webfer ] && /script/webfer "$u" 2>&1 | _um_norm_out
                [ -x /script/ta ] && { _um_p '\n▶ 최근 트래픽 리셋 로그:\n'; /script/ta 2>&1 | _um_norm_out | tail -n 15; }
                _um_pause ;;
            4)
                if [ -x /script/treset ]; then
                    _um_p '\n계정 [%s] 트래픽 제한을 초기화할까요? [y/N]: ' "$u"
                    local _ta=""
                    IFS= read -r _ta </dev/tty
                    case "$_ta" in
                        y|Y)
                            /script/treset "$u" 2>&1 | _um_norm_out
                            _UM_MSG="✔ '${u}' 트래픽 초기화 실행 완료"
                            ;;
                    esac
                else
                    _um_p '⚠ /script/treset 없음\n'
                fi
                _um_pause ;;
            5)
                if command -v quota >/dev/null 2>&1; then
                    quota -u "$u" 2>&1
                    _um_p '\nedquota -u %s 로 용량 제한을 수정할까요? [y/N]: ' "$u"
                    local _eq=""
                    IFS= read -r _eq </dev/tty
                    case "$_eq" in y|Y) edquota -u "$u" ;; esac
                else
                    _um_p '⚠ quota 명령 없음\n'
                fi
                _um_pause ;;
            6)
                if [ -x /script/logincheck ]; then
                    _um_p '테스트할 비밀번호 입력: '
                    local _tpw=""
                    IFS= read -r _tpw </dev/tty
                    [ -n "$_tpw" ] && /script/logincheck "$u" "$_tpw" 2>&1 | _um_norm_out
                else
                    _um_p '⚠ /script/logincheck 없음\n'
                fi
                _um_pause ;;
            7)
                _um_p '  [1] 등록 이메일 수정 (/script/vu %s)  |  [2] 안내 메일 발송 (/root/emailsend %s) : ' "$u" "$u"
                local _em=""
                IFS= read -r _em </dev/tty
                if [ "$_em" = "1" ] && [ -x /script/vu ]; then
                    /script/vu "$u"
                elif [ "$_em" = "2" ] && [ -x /root/emailsend ]; then
                    /root/emailsend "$u"
                fi
                _um_extract_hosting_contact "$u"
                _um_pause ;;
            8)
                if [ -x /script/sms ]; then
                    local _ph="$_UM_C_PHONE"
                    _um_p '수신 휴대폰 번호 (Enter=기본 [%s]): ' "${_ph:-없음}"
                    local _iph=""
                    IFS= read -r _iph </dev/tty
                    [ -n "$_iph" ] && _ph="$_iph"
                    if [ -n "$_ph" ]; then
                        _um_p '발송할 SMS 내용 입력: '
                        local _msg=""
                        IFS= read -r _msg </dev/tty
                        if [ -n "$_msg" ]; then
                            /script/sms "$_ph" "$_msg" 2>&1 | _um_norm_out
                            _UM_MSG="✔ SMS 발송 완료 -> $_ph"
                        fi
                    fi
                else
                    _um_p '⚠ /script/sms 없음\n'
                fi
                _um_pause ;;
            9)
                if [ -x /script/ssl ]; then
                    /script/ssl "$u"
                else
                    _um_p '⚠ /script/ssl 없음\n'
                fi
                _um_pause ;;
            10)
                _um_p '  [1] 가상호스트 설정 검색 (httpd.conf/nginx)  |  [2] 도메인/DNS 변경 (/root/dnschg %s) : ' "$u"
                local _dn=""
                IFS= read -r _dn </dev/tty
                if [ "$_dn" = "1" ]; then
                    grep -rn -C 3 "$u" /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/ /usr/local/apache*/conf/ /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | head -n 45
                elif [ "$_dn" = "2" ] && [ -x /root/dnschg ]; then
                    /root/dnschg "$u"
                fi
                _um_pause ;;
            11)
                [ -x /root/emoney ] && { _um_p '▶ 만기/연장 계산 (/root/emoney):\n'; /root/emoney "$u" 2>&1 | _um_norm_out; }
                [ -x /script/da ] && { _um_p '\n▶ 단위 변경 일할 계산 (/script/da):\n'; /script/da "$u" 2>&1 | _um_norm_out; }
                _um_pause ;;
            0|"") break ;;
        esac
    done
}

# ==============================================================================
# 액션 7: 그룹 · 쉘 · 만료일 관리 (g 키)
# ==============================================================================
_um_manage_group_shell() {
    local idx="$1"
    local u="${_UM_NAMES[$idx]}"
    local shl="${_UM_SHELLS[$idx]}"

    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\033[2J\033[H'
    _um_p '\033[1;36m* 그룹 · 쉘 · 만료일 관리: %s\033[0m\n' "$u"
    printf '%s\n' "------------------------------------------------------------------------"
    id "$u" 2>&1
    _um_p '현재 쉘: %s\n' "$shl"
    printf '%s\n' "------------------------------------------------------------------------"
    _um_p '  \033[1;33m1.\033[0m 그룹 추가 (sudo / wheel / www-data / 직접입력)\n'
    _um_p '  \033[1;33m2.\033[0m 로그인 쉘 변경 (/bin/bash, /bin/sh, /sbin/nologin, /bin/pass 등)\n'
    _um_p '  \033[1;33m3.\033[0m 계정 만료일 조회 / 해제 (chage -E -1)\n'
    _um_p '  \033[0;37m0.\033[0m 취소\n'
    _um_p '선택 [0-3]: '
    local _sel=""
    IFS= read -r _sel </dev/tty
    case "$_sel" in
        1)
            _um_p '추가할 그룹명 (예: wheel, sudo, www-data): '
            local _grp=""
            IFS= read -r _grp </dev/tty
            if [ -n "$_grp" ]; then
                usermod -aG "$_grp" "$u" 2>&1 && _UM_MSG="✔ '${u}' -> 그룹 '${_grp}' 추가 완료"
                id "$u" 2>&1
                _um_pause
            fi
            ;;
        2)
            _um_p '  [1] /bin/bash  [2] /bin/sh  [3] /sbin/nologin  [4] /bin/pass  [5] 직접입력 : '
            local _s="" _nsh=""
            IFS= read -r _s </dev/tty
            case "$_s" in
                1) _nsh="/bin/bash" ;;
                2) _nsh="/bin/sh" ;;
                3) _nsh="/sbin/nologin" ;;
                4) _nsh="/bin/pass" ;;
                5) _um_p '쉘 경로 입력: '; IFS= read -r _nsh </dev/tty ;;
            esac
            if [ -n "$_nsh" ]; then
                usermod -s "$_nsh" "$u" 2>&1 && { _um_refresh_one "$idx"; _UM_MSG="✔ '${u}' 쉘 변경 완료: $_nsh"; }
                _um_pause
            fi
            ;;
        3)
            if command -v chage >/dev/null 2>&1; then
                chage -l "$u" 2>&1
                _um_p '\n계정 만료 제한을 해제(chage -E -1 -M 99999)할까요? [y/N]: '
                local _ch=""
                IFS= read -r _ch </dev/tty
                case "$_ch" in
                    y|Y)
                        chage -E -1 -M 99999 "$u" 2>&1
                        _um_refresh_one "$idx"
                        _UM_MSG="✔ '${u}' 만료 제한 해제 완료"
                        ;;
                esac
            fi
            _um_pause
            ;;
    esac
}

# ==============================================================================
# 액션 8: 새 사용자 생성 마법사 (a 키)
# ==============================================================================
_um_add_user() {
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\033[2J\033[H'
    _um_p '\033[1;36m* 새 사용자 계정 생성 마법사\033[0m\n'
    printf '%s\n' "------------------------------------------------------------------------"
    _um_p '새 계정 ID (영소문자/숫자, 빈 값=취소): '
    local _nu=""
    IFS= read -r _nu </dev/tty
    [ -z "$_nu" ] && { _UM_MSG="취소됨"; return 0; }
    if id "$_nu" >/dev/null 2>&1; then
        _UM_MSG="⚠ 이미 존재하는 계정입니다: $_nu"
        return 1
    fi

    _um_p '로그인 쉘 (Enter=/bin/bash): '
    local _nsh=""
    IFS= read -r _nsh </dev/tty
    [ -z "$_nsh" ] && _nsh="/bin/bash"

    local _rpw
    _rpw=$(_um_gen_password 12)
    _um_p '비밀번호 (Enter=랜덤 자동생성 [%s]): ' "$_rpw"
    local _npw=""
    IFS= read -r _npw </dev/tty
    [ -z "$_npw" ] && _npw="$_rpw"

    _um_p '웹루트(/home/%s/public_html)도 함께 생성할까요? [y/N]: ' "$_nu"
    local _mkw=""
    IFS= read -r _mkw </dev/tty

    useradd -m -d "/home/$_nu" -s "$_nsh" "$_nu" 2>&1
    if [ $? -eq 0 ]; then
        if command -v chpasswd >/dev/null 2>&1; then
            printf '%s:%s\n' "$_nu" "$_npw" | chpasswd 2>&1
        else
            printf '%s\n' "$_npw" | passwd --stdin "$_nu" 2>&1
        fi
        case "$_mkw" in
            y|Y)
                mkdir -p "/home/$_nu/public_html"
                chown -R "${_nu}:${_nu}" "/home/$_nu/public_html"
                chmod 701 "/home/$_nu"
                chmod 750 "/home/$_nu/public_html"
                ;;
        esac
        _um_load_users
        _um_build_view
        _um_p '\n\033[1;32m✔ 계정 생성 완료!\033[0m  ID: %s  |  PW: \033[1;33m%s\033[0m  |  Shell: %s\n' "$_nu" "$_npw" "$_nsh"
        _UM_MSG="✔ 새 계정 '${_nu}' 생성 완료 (PW: ${_npw})"
    else
        _UM_MSG="✖ 계정 '${_nu}' 생성 실패"
    fi
    _um_pause
}

# ==============================================================================
# 액션 9: 계정 안전 삭제 (x / D 키 — 핵심 계정 보호 + ID 재입력 이중 확인)
# ==============================================================================
_um_delete_user() {
    local idx="$1"
    local u="${_UM_NAMES[$idx]}"
    local uid="${_UM_UIDS[$idx]}"
    local hom="${_UM_HOMES[$idx]}"

    if _um_is_protected "$u" "$uid" || [ "$uid" -lt "$_UM_MIN_UID" ] 2>/dev/null; then
        _UM_MSG="⚠ 시스템/핵심 계정 '${u}' (UID:${uid}) 는 안전을 위해 삭제할 수 없습니다."
        return 1
    fi

    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\033[2J\033[H'
    _um_p '\033[1;31m* 위험 작업: 사용자 계정 삭제 (%s)\033[0m\n' "$u"
    printf '%s\n' "------------------------------------------------------------------------"
    _um_p '  대상 계정: \033[1;37m%s\033[0m (UID: %s)  |  홈: %s\n' "$u" "$uid" "$hom"
    _um_p '  \033[1;33m1.\033[0m 계정만 삭제 (홈 디렉토리 보존: userdel %s)\n' "$u"
    _um_p '  \033[1;31m2.\033[0m 계정 + 홈 디렉토리 완전 삭제 (userdel -r %s)\n' "$u"
    [ -x /root/userdrop ] && _um_p '  \033[1;31m3.\033[0m 호스팅 계정 완전 삭제 (/root/userdrop %s)\n' "$u"
    _um_p '  \033[0;37m0.\033[0m 취소\n'
    printf '%s\n' "------------------------------------------------------------------------"
    _um_p '선택 [0-3]: '
    local _sel=""
    IFS= read -r _sel </dev/tty
    case "$_sel" in
        1|2|3)
            _um_p '\033[1;31m확인을 위해 삭제할 계정명 [%s] 을(를) 정확히 다시 입력하세요: \033[0m' "$u"
            local _chk=""
            IFS= read -r _chk </dev/tty
            if [ "$_chk" != "$u" ]; then
                _UM_MSG="취소됨: 계정명 불일치"
                return 0
            fi
            if [ "$_sel" = "1" ]; then
                userdel "$u" 2>&1
            elif [ "$_sel" = "2" ]; then
                userdel -r "$u" 2>&1
            elif [ "$_sel" = "3" ] && [ -x /root/userdrop ]; then
                /root/userdrop "$u"
            fi
            _um_load_users
            _um_build_view
            _UM_MSG="✔ 계정 '${u}' 삭제 처리 완료"
            _um_pause
            ;;
        *)
            _UM_MSG="삭제 취소됨"
            ;;
    esac
}

# ==============================================================================
# 도움말 (? / h 키)
# ==============================================================================
_um_show_help() {
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    printf '\033[2J\033[H'
    _um_p '\033[1;36m* 통합 사용자·호스팅 계정 관리 TUI [ums] 도움말\033[0m\n'
    printf '%s\n' "------------------------------------------------------------------------"
    _um_p '  \033[1;33m↑/↓, j/k\033[0m       : 계정 위/아래 이동\n'
    _um_p '  \033[1;33m←/→, PgUp/PgDn\033[0m : 이전/다음 페이지 이동\n'
    _um_p '  \033[1;33mEnter / v\033[0m      : 계정 종합 상세 보기 (권한·락·홈·용량·DB·호스팅정보)\n'
    _um_p '  \033[1;33mSpace / l\033[0m      : 계정 잠금(Lock) / 해제(Unlock) 토글 (passwd -l/-u)\n'
    _um_p '  \033[1;33mu\033[0m              : 완전 Unban (faillock/pam_tally2 초기화 + passwd -u + 차단IP 점검)\n'
    _um_p '  \033[1;33mp\033[0m              : 비밀번호 리셋 (랜덤생성/수동입력) + 호스팅 메일/SMS 발송 연동\n'
    _um_p '  \033[1;33md\033[0m              : 대응 DB & 홈폴더 통합 점검/권한보정/대용량파일/백업/탐색기\n'
    _um_p '  \033[1;33mH\033[0m              : 호스팅 계정 전용 액션 센터 (트래픽·Quota·SSL·DNS·메일·SMS·만기)\n'
    _um_p '  \033[1;33mg\033[0m              : 그룹(sudo/wheel/www-data) · 쉘 · 만료일 관리\n'
    _um_p '  \033[1;33ma\033[0m              : 새 사용자 계정 생성 마법사\n'
    _um_p '  \033[1;33mx / D\033[0m          : 계정 안전 삭제 (시스템 계정 보호 + ID 재입력 확인)\n'
    _um_p '  \033[1;33m/\033[0m              : 실시간 검색 (계정ID / 홈폴더 / 메모)\n'
    _um_p '  \033[1;33mf\033[0m              : 필터 순환 (일반유저 -> 잠김/실패 -> 활성 -> 관리자 -> 시스템 -> 전체)\n'
    _um_p '  \033[1;33mr\033[0m              : 계정 목록 전체 새로고침\n'
    _um_p '  \033[1;33mq / ESC\033[0m        : 종료 (검색 중이면 ESC로 검색어 초기화)\n'
    printf '%s\n' "------------------------------------------------------------------------"
    _um_pause "Enter를 누르면 목록으로 돌아갑니다..."
}

# ==============================================================================
# 렌더링 엔진 (무깜빡임 델타 렌더링)
# ==============================================================================
_um_render_row() {
    local vidx="$1" is_cur="$2"
    local idx="${_UM_VIEW[$vidx]}"
    local nm="${_UM_NAMES[$idx]}"
    local uid="${_UM_UIDS[$idx]}"
    local hom="${_UM_HOMES[$idx]}"
    local shl="${_UM_SHELLS[$idx]}"
    local st="${_UM_STATES[$idx]}"
    local fc="${_UM_FAILS[$idx]}"
    local su="${_UM_SUDO[$idx]}"
    local db="${_UM_DBS[$idx]}"
    local dom="${_UM_DOMAINS[$idx]}"
    local eml="${_UM_EMAILS[$idx]}"
    local gec="${_UM_GECOS[$idx]}"

    local cur_mark=" "
    [ "$is_cur" -eq 1 ] && cur_mark="$_UM_S_CUR"

    local st_col='\033[0;32m' st_txt="$st"
    if [ "$st" = "LOCKED" ]; then
        st_col='\033[1;31m'
    elif [ "${fc:-0}" -gt 0 ] 2>/dev/null; then
        st_col='\033[1;31m'; st_txt="FAIL:${fc}"
    elif [ "$st" = "NOPW" ] || [ "$st" = "EXPIRED" ]; then
        st_col='\033[1;33m'
    fi

    local htag="[OK]" hcol='\033[0;32m'
    if [ ! -d "$hom" ]; then htag="[--]"; hcol='\033[0;37m'; fi
    local dbcol='\033[0;37m'
    [ "$db" = "DB" ] && dbcol='\033[1;36m'

    local sh_short="${shl##*/}"
    local hom_disp="$hom"
    [ ${#hom_disp} -gt 20 ] && hom_disp="${hom_disp:0:18}.."

    local memo_disp="$gec"
    [ "$su" = "1" ] && memo_disp="${memo_disp:+[S] }${memo_disp:-[SUDO]}"
    [ -z "$memo_disp" ] && memo_disp="-"
    [ ${#memo_disp} -gt 10 ] && memo_disp="${memo_disp:0:8}.."

    local dom_disp="${dom:--}"
    [ ${#dom_disp} -gt 24 ] && dom_disp="${dom_disp:0:22}.."

    local eml_disp="${eml:--}"
    [ ${#eml_disp} -gt 26 ] && eml_disp="${eml_disp:0:24}.."

    if [ "$_UM_COLS" -ge 124 ]; then
        if [ "$is_cur" -eq 1 ]; then
            printf '\033[1;37;44m %s %-15.15s %-7s %5s %-4s %-2s %-6.6s %-10.10s %-20.20s %-24.24s %-26.26s\033[0m\033[K\n' \
                "$cur_mark" "$nm" "$st_txt" "$uid" "$htag" "$db" "$sh_short" "$memo_disp" "$hom_disp" "$dom_disp" "$eml_disp"
        else
            printf ' %s \033[1;37m%-15.15s\033[0m %b%-7s\033[0m \033[0;37m%5s\033[0m %b%-4s\033[0m %b%-2s\033[0m \033[0;37m%-6.6s\033[0m \033[0;35m%-10.10s\033[0m \033[0;36m%-20.20s\033[0m \033[1;33m%-24.24s\033[0m \033[0;37m%-26.26s\033[0m\033[K\n' \
                "$cur_mark" "$nm" "$st_col" "$st_txt" "$uid" "$hcol" "$htag" "$dbcol" "$db" "$sh_short" "$memo_disp" "$hom_disp" "$dom_disp" "$eml_disp"
        fi
    elif [ "$_UM_COLS" -ge 98 ]; then
        if [ "$is_cur" -eq 1 ]; then
            printf '\033[1;37;44m %s %-15.15s %-7s %5s %-4s %-2s %-6.6s %-10.10s %-20.20s %-24.24s\033[0m\033[K\n' \
                "$cur_mark" "$nm" "$st_txt" "$uid" "$htag" "$db" "$sh_short" "$memo_disp" "$hom_disp" "$dom_disp"
        else
            printf ' %s \033[1;37m%-15.15s\033[0m %b%-7s\033[0m \033[0;37m%5s\033[0m %b%-4s\033[0m %b%-2s\033[0m \033[0;37m%-6.6s\033[0m \033[0;35m%-10.10s\033[0m \033[0;36m%-20.20s\033[0m \033[1;33m%-24.24s\033[0m\033[K\n' \
                "$cur_mark" "$nm" "$st_col" "$st_txt" "$uid" "$hcol" "$htag" "$dbcol" "$db" "$sh_short" "$memo_disp" "$hom_disp" "$dom_disp"
        fi
    else
        if [ "$is_cur" -eq 1 ]; then
            printf '\033[1;37;44m %s %-14.14s %-7s %5s %-4s %-2s %-6.6s %-10.10s %-18.18s\033[0m\033[K\n' \
                "$cur_mark" "$nm" "$st_txt" "$uid" "$htag" "$db" "$sh_short" "$memo_disp" "$hom_disp"
        else
            printf ' %s \033[1;37m%-14.14s\033[0m %b%-7s\033[0m \033[0;37m%5s\033[0m %b%-4s\033[0m %b%-2s\033[0m \033[0;37m%-6.6s\033[0m \033[0;35m%-10.10s\033[0m \033[0;36m%-18.18s\033[0m\033[K\n' \
                "$cur_mark" "$nm" "$st_col" "$st_txt" "$uid" "$hcol" "$htag" "$dbcol" "$db" "$sh_short" "$memo_disp" "$hom_disp"
        fi
    fi
}

_um_render_footer() {
    printf '\033[0;34m%s\033[0m\033[K\n' "$_UM_HLINE"
    if [ "$_UM_VCNT" -gt 0 ]; then
        local cidx="${_UM_VIEW[$_UM_CUR]}"
        local cnm="${_UM_NAMES[$cidx]}"
        local cuid="${_UM_UIDS[$cidx]}"
        local cgid="${_UM_GIDS[$cidx]}"
        local chom="${_UM_HOMES[$cidx]}"
        local cshl="${_UM_SHELLS[$cidx]}"
        local cst="${_UM_STATES[$cidx]}"
        local cfc="${_UM_FAILS[$cidx]}"
        local cgec="${_UM_GECOS[$cidx]}"
        local cdb="${_UM_DBS[$cidx]}"
        local cdom="${_UM_DOMAINS[$cidx]}"
        local ceml="${_UM_EMAILS[$cidx]}"
        local dbb="DB:-"
        [ "$cdb" = "DB" ] && dbb="DB:OK"
        local hstat="존재"
        [ -d "$chom" ] || hstat="없음"

        printf ' \033[1;33m선택 계정:\033[0m \033[1;37m%s\033[0m  (UID:%s GID:%s | 상태:%s | 실패:%s | %s)' \
            "$cnm" "$cuid" "$cgid" "$cst" "${cfc:-0}" "$dbb"
        [ -n "$cdom" ] && printf '  |  도메인:\033[1;33m%s\033[0m' "$cdom"
        [ -n "$ceml" ] && printf '  |  메일:\033[1;32m%s\033[0m' "$ceml"
        printf '\033[K\n'
        printf '   %s 홈: \033[0;36m%s\033[0m (%s) | 쉘: \033[0;37m%s\033[0m | 메모: %s\033[K\n' \
            "$_UM_S_BUL" "$chom" "$hstat" "$cshl" "${cgec:--}"
        if [ "$_UM_HOSTING" -eq 1 ]; then
            printf '   %s 동작: [Enter]상세  [Space]잠금토글  [u]Unban  [p]비번리셋+메일/SMS  [d]DB/홈점검  \033[1;32m[H]호스팅액션\033[0m\033[K\n' "$_UM_S_BUL"
        else
            printf '   %s 동작: [Enter]상세  [Space]잠금토글  [u]Unban  [p]비번리셋(랜덤/수동)  [d]DB/홈점검  [g]그룹/쉘\033[K\n' "$_UM_S_BUL"
        fi
    else
        printf '\033[K\n\033[K\n\033[K\n'
    fi
    printf '\033[0;34m%s\033[0m\033[K\n' "$_UM_HLINE"
    if [ -n "$_UM_MSG" ]; then
        printf '\033[1;33m %s\033[0m\033[K' "$_UM_MSG"
    else
        if [ "$_UM_HOSTING" -eq 1 ]; then
            printf ' \033[0;37m[Enter]상세 [Space]잠금 [u]Unban [p]비번리셋 [d]DB/홈 [H]호스팅 [g]그룹 [a]추가 [x]삭제 [/]검색 [f]필터 [r]갱신 [?]도움 [q]종료\033[0m\033[K'
        else
            printf ' \033[0;37m[Enter]상세 [Space]잠금 [u]Unban [p]비번리셋 [d]DB/홈 [g]그룹 [a]추가 [x]삭제 [/]검색 [f]필터 [r]갱신 [?]도움 [q]종료\033[0m\033[K'
        fi
    fi
}

_um_render_full_body() {
    local list_h=$_UM_PAGE_H
    local cur_pg=1 tot_pg=1
    if [ "$_UM_VCNT" -gt 0 ]; then
        cur_pg=$(( (_UM_TOP / list_h) + 1 ))
        tot_pg=$(( ((_UM_VCNT - 1) / list_h) + 1 ))
    fi
    local flabel="일반유저"
    case "$_UM_FILTER" in
        locked) flabel="잠김/실패" ;;
        active) flabel="활성만" ;;
        sudo)   flabel="관리자(SUDO)" ;;
        system) flabel="시스템계정" ;;
        all)    flabel="전체" ;;
    esac
    local hbadge=""
    [ "$_UM_HOSTING" -eq 1 ] && hbadge=" \033[1;32m[Hosting]\033[0m"

    printf '\033[H'
    printf '\033[1;36m* 통합 사용자 관리 [ums]\033[0m%b  \033[0;37mOS: %s\033[0m  필터:\033[1;33m%s\033[0m (%d/%d)  \033[1;37mP.%d/%d\033[0m' \
        "$hbadge" "$_UM_OS" "$flabel" "$_UM_VCNT" "$_UM_TOTAL" "$cur_pg" "$tot_pg"
    [ -n "$_UM_SEARCH" ] && printf '  검색:\033[1;35m/%s\033[0m' "$_UM_SEARCH"
    printf '\033[K\n'
    if [ "$_UM_COLS" -ge 124 ]; then
        printf '\033[0;36m   %-15s %-7s %5s %-4s %-2s %-6s %-10s %-20s %-24s %-26s\033[0m\033[K\n' \
            "ACCOUNT" "STATE" "UID" "HOME" "DB" "SHELL" "MEMO" "HOME_DIR" "DOMAIN" "EMAIL"
    elif [ "$_UM_COLS" -ge 98 ]; then
        printf '\033[0;36m   %-15s %-7s %5s %-4s %-2s %-6s %-10s %-20s %-24s\033[0m\033[K\n' \
            "ACCOUNT" "STATE" "UID" "HOME" "DB" "SHELL" "MEMO" "HOME_DIR" "DOMAIN"
    else
        printf '\033[0;36m   %-14s %-7s %5s %-4s %-2s %-6s %-10s %-18s\033[0m\033[K\n' \
            "ACCOUNT" "STATE" "UID" "HOME" "DB" "SHELL" "MEMO" "HOME_DIR"
    fi
    printf '\033[0;34m%s\033[0m\033[K\n' "$_UM_HLINE"

    local r=0 vidx
    if [ "$_UM_VCNT" -eq 0 ]; then
        printf '\033[K\n  (조건에 맞는 사용자가 없습니다. / 로 검색어를 지우거나 f 로 필터를 바꾸세요)\033[K\n'
        r=2
        while [ "$r" -lt "$list_h" ]; do
            printf '\033[K\n'
            r=$((r + 1))
        done
    else
        while [ "$r" -lt "$list_h" ]; do
            vidx=$((_UM_TOP + r))
            [ "$vidx" -ge "$_UM_VCNT" ] && break
            if [ "$vidx" -eq "$_UM_CUR" ]; then
                _um_render_row "$vidx" 1
            else
                _um_render_row "$vidx" 0
            fi
            r=$((r + 1))
        done
        while [ "$r" -lt "$list_h" ]; do
            printf '\033[K\n'
            r=$((r + 1))
        done
    fi
    _um_render_footer
    printf '\033[J'
}

_um_render_delta_body() {
    local old_row=$((4 + _UM_LAST_CUR - _UM_TOP))
    local new_row=$((4 + _UM_CUR - _UM_TOP))
    local foot_row=$((4 + _UM_PAGE_H))
    printf '\033[%d;1H' "$old_row"
    _um_render_row "$_UM_LAST_CUR" 0
    printf '\033[%d;1H' "$new_row"
    _um_render_row "$_UM_CUR" 1
    printf '\033[%d;1H' "$foot_row"
    _um_render_footer
}

_um_render() {
    if [ "$_UM_VCNT" -gt 0 ]; then
        [ "$_UM_CUR" -lt 0 ] && _UM_CUR=0
        [ "$_UM_CUR" -ge "$_UM_VCNT" ] && _UM_CUR=$((_UM_VCNT - 1))
        _UM_TOP=$(( (_UM_CUR / _UM_PAGE_H) * _UM_PAGE_H ))
    else
        _UM_TOP=0
    fi

    if [ "${_UM_DIRTY:-1}" = "0" ] && [ "$_UM_VCNT" -gt 0 ] \
       && [ "$_UM_TOP" = "${_UM_LAST_TOP:--1}" ] && [ "${_UM_LAST_CUR:--1}" -ge 0 ] \
       && [ "$_UM_LAST_CUR" -lt "$_UM_VCNT" ] && [ -z "$_UM_MSG" ] && [ -z "${_UM_LAST_MSG:-}" ]; then
        if [ "$_UM_CUR" != "$_UM_LAST_CUR" ]; then
            if [ "$_UM_ENC" = "euckr" ]; then
                _um_render_delta_body | _dm_iconv_euckr
            else
                _um_render_delta_body
            fi
        fi
    else
        if [ "$_UM_ENC" = "euckr" ]; then
            _um_render_full_body | _dm_iconv_euckr
        else
            _um_render_full_body
        fi
        _UM_DIRTY=0
    fi
    _UM_LAST_CUR=$_UM_CUR
    _UM_LAST_TOP=$_UM_TOP
    _UM_LAST_MSG="$_UM_MSG"
}

# 메인 진입 함수: ums [초기검색어]
ums() {
    _um_detect_env

    _UM_FILTER="users"
    _UM_SEARCH="${1:-}"
    _UM_CUR=0; _UM_TOP=0
    _UM_MSG=""
    _UM_LAST_CUR=-1; _UM_LAST_TOP=-1; _UM_LAST_MSG=""

    _um_p '\033[1;36m[ums] %s 사용자 및 잠금 상태 로딩 중...\033[0m\n' "$_UM_OS"
    _um_load_users
    _um_build_view
    # 일반 유저가 0명이고 검색어도 없으면 전체 보기로 자동 전환
    if [ "$_UM_VCNT" -eq 0 ] && [ -z "$_UM_SEARCH" ]; then
        _UM_FILTER="all"
        _um_build_view
    fi
    _um_init_layout

    local _esc_t=1
    [ "${BASH_VERSINFO[0]:-0}" -ge 4 ] && _esc_t=0.25

    local _old_trap
    _old_trap=$(trap -p INT)
    trap 'tput cnorm 2>/dev/null; stty sane 2>/dev/null; printf "\n"; return 0' INT
    trap '_um_init_layout' WINCH 2>/dev/null

    printf '\033[2J\033[H'
    tput civis 2>/dev/null
    while :; do
        _um_render
        _UM_MSG=""

        local _k="" _x="" _x2=""
        IFS= read -rsn1 _k </dev/tty 2>/dev/null || break

        if [ "$_k" = $'\033' ]; then
            IFS= read -rsn1 -t "$_esc_t" _x </dev/tty 2>/dev/null
            if [ -z "$_x" ] || [ "$_x" = $'\033' ]; then
                if [ -n "$_UM_SEARCH" ]; then
                    _UM_SEARCH=""
                    _UM_CUR=0; _UM_TOP=0
                    _um_build_view
                    _UM_DIRTY=1
                    continue
                fi
                _k="q"
            elif [ "$_x" = "[" ] || [ "$_x" = "O" ]; then
                IFS= read -rsn1 -t "$_esc_t" _x </dev/tty 2>/dev/null
                case "$_x" in
                    A) [ "$_UM_CUR" -gt 0 ] && _UM_CUR=$((_UM_CUR - 1)); continue ;;
                    B) [ "$_UM_CUR" -lt $((_UM_VCNT - 1)) ] && _UM_CUR=$((_UM_CUR + 1)); continue ;;
                    D) # ← 이전 페이지
                       local _ph="${_UM_PAGE_H:-10}"
                       if [ "$_UM_TOP" -gt 0 ]; then
                           _UM_TOP=$((_UM_TOP - _ph))
                           [ "$_UM_TOP" -lt 0 ] && _UM_TOP=0
                           _UM_CUR=$_UM_TOP
                       else
                           _UM_CUR=0
                       fi
                       continue ;;
                    C) # → 다음 페이지
                       local _ph="${_UM_PAGE_H:-10}"
                       local _nt=$((_UM_TOP + _ph))
                       if [ "$_nt" -lt "$_UM_VCNT" ]; then
                           _UM_TOP=$_nt; _UM_CUR=$_UM_TOP
                       elif [ "$_UM_VCNT" -gt 0 ]; then
                           _UM_CUR=$((_UM_VCNT - 1))
                       fi
                       continue ;;
                    5) IFS= read -rsn1 -t "$_esc_t" _x2 </dev/tty 2>/dev/null
                       local _ph="${_UM_PAGE_H:-10}"
                       if [ "$_UM_TOP" -gt 0 ]; then
                           _UM_TOP=$((_UM_TOP - _ph))
                           [ "$_UM_TOP" -lt 0 ] && _UM_TOP=0
                           _UM_CUR=$_UM_TOP
                       else
                           _UM_CUR=0
                       fi
                       continue ;;
                    6) IFS= read -rsn1 -t "$_esc_t" _x2 </dev/tty 2>/dev/null
                       local _ph="${_UM_PAGE_H:-10}"
                       local _nt=$((_UM_TOP + _ph))
                       if [ "$_nt" -lt "$_UM_VCNT" ]; then
                           _UM_TOP=$_nt; _UM_CUR=$_UM_TOP
                       elif [ "$_UM_VCNT" -gt 0 ]; then
                           _UM_CUR=$((_UM_VCNT - 1))
                       fi
                       continue ;;
                esac
                continue
            else
                continue
            fi
        fi

        case "$_k" in
            q|Q) break ;;
            \?|h)
                _um_show_help
                _UM_DIRTY=1; tput civis 2>/dev/null
                ;;
            k) [ "$_UM_CUR" -gt 0 ] && _UM_CUR=$((_UM_CUR - 1)) ;;
            j) [ "$_UM_CUR" -lt $((_UM_VCNT - 1)) ] && _UM_CUR=$((_UM_CUR + 1)) ;;
            /)
                tput cnorm 2>/dev/null
                stty echo 2>/dev/null
                _um_p '\n사용자 검색어 (계정ID/홈/메모, 빈 값=초기화): '
                IFS= read -r _UM_SEARCH </dev/tty
                _UM_CUR=0; _UM_TOP=0
                _um_build_view
                _UM_DIRTY=1; tput civis 2>/dev/null
                ;;
            f|F)
                case "$_UM_FILTER" in
                    users)  _UM_FILTER="locked" ;;
                    locked) _UM_FILTER="active" ;;
                    active) _UM_FILTER="sudo" ;;
                    sudo)   _UM_FILTER="system" ;;
                    system) _UM_FILTER="all" ;;
                    *)      _UM_FILTER="users" ;;
                esac
                _UM_CUR=0; _UM_TOP=0
                _um_build_view
                _UM_DIRTY=1
                ;;
            r|R)
                _um_load_users
                _um_build_view
                _UM_MSG="✔ 계정 목록 새로고침 완료 (총 ${_UM_TOTAL}명)"
                _UM_DIRTY=1
                ;;
            ""|v|V)
                [ "$_UM_VCNT" -eq 0 ] && continue
                _um_show_detail "${_UM_VIEW[$_UM_CUR]}"
                _UM_DIRTY=1; tput civis 2>/dev/null
                ;;
            " "|l|L)
                [ "$_UM_VCNT" -eq 0 ] && continue
                _um_toggle_lock "${_UM_VIEW[$_UM_CUR]}"
                _UM_DIRTY=1; tput civis 2>/dev/null
                ;;
            u|U)
                [ "$_UM_VCNT" -eq 0 ] && continue
                _um_unban_user "${_UM_VIEW[$_UM_CUR]}"
                _UM_DIRTY=1; tput civis 2>/dev/null
                ;;
            p|P)
                [ "$_UM_VCNT" -eq 0 ] && continue
                _um_reset_password "${_UM_VIEW[$_UM_CUR]}"
                _UM_DIRTY=1; tput civis 2>/dev/null
                ;;
            d)
                [ "$_UM_VCNT" -eq 0 ] && continue
                _um_check_db_home "${_UM_VIEW[$_UM_CUR]}"
                _UM_DIRTY=1; tput civis 2>/dev/null
                ;;
            H)
                [ "$_UM_VCNT" -eq 0 ] && continue
                _um_hosting_menu "${_UM_VIEW[$_UM_CUR]}"
                _UM_DIRTY=1; tput civis 2>/dev/null
                ;;
            g|G)
                [ "$_UM_VCNT" -eq 0 ] && continue
                _um_manage_group_shell "${_UM_VIEW[$_UM_CUR]}"
                _UM_DIRTY=1; tput civis 2>/dev/null
                ;;
            a|A)
                _um_add_user
                _UM_DIRTY=1; tput civis 2>/dev/null
                ;;
            x|X|D)
                [ "$_UM_VCNT" -eq 0 ] && continue
                _um_delete_user "${_UM_VIEW[$_UM_CUR]}"
                _UM_DIRTY=1; tput civis 2>/dev/null
                ;;
        esac
    done

    tput cnorm 2>/dev/null
    stty sane 2>/dev/null
    [ -n "$_old_trap" ] && eval "$_old_trap" || trap - INT
    printf '\n'
}

# ==============================================================================
# 통합 도커·컴포즈 관리 TUI: dkms (Docker & Compose Manager Studio)
# - Portainer + Dockge 핵심 기능을 콘솔에서 방향키 + 엔터 + 원키 단축키로 통합 제어
# - 6개 탭: [1]Containers [2]Stacks(Compose) [3]Images [4]Volumes [5]Networks [6]System&Stats
# - Compose v2(docker compose) / v1(docker-compose) 자동 판별 + 로컬 compose.yml 자동 스캔
# - Bash 3.x+ 및 EUC-KR/UTF-8 완벽 호환 (연관배열 미사용, 무깜빡임 델타 렌더링)
# ==============================================================================

_dk_p() {
    local _fmt="$1"
    shift
    if [ "$_DK_ENC" = "euckr" ] && declare -f _dm_iconv_euckr >/dev/null 2>&1; then
        printf "$_fmt" "$@" | _dm_iconv_euckr | iconv -f UTF-8 -t EUC-KR//TRANSLIT 2>/dev/null || printf "$_fmt" "$@"
    else
        printf "$_fmt" "$@"
    fi
}

_dk_pause() {
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    _dk_p '\n\033[1;33m[아무 키나 누르면 dkms 로 돌아갑니다...]\033[0m'
    IFS= read -rsn1 _ </dev/tty
}

_dk_detect_env() {
    _DK_ENC="utf8"
    _DK_VER="N/A"
    _DK_COMPOSE_BIN=""
    _DK_COMPOSE_VER="N/A"
    _DK_HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null)"
    [ -z "$_DK_SCAN_DIRS" ] && _DK_SCAN_DIRS="/data /opt /root /srv /docker /home"

    local _loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    case "$_loc" in
        *[Ee][Uu][Cc]*[Kk][Rr]*|*[Kk][Oo]_[Kk][Rr]|ko)
            command -v iconv >/dev/null 2>&1 && _DK_ENC="euckr" ;;
    esac

    if ! command -v docker >/dev/null 2>&1; then
        _dk_p '\033[1;31m[오류] docker 명령을 찾을 수 없습니다.\033[0m\n'
        _dk_p '먼저 [dki] 메뉴에서 Docker 를 설치해 주세요.\n'
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        _dk_p '\033[1;33m[경고] Docker 데몬이 실행 중이 아니거나 권한이 부족합니다.\033[0m\n'
        local _ans=""
        read -p "지금 Docker 데몬을 시작할까요? [Y/n]: " _ans </dev/tty
        if ! printf '%s' "$_ans" | grep -qE '^[Nn]$'; then
            systemctl start docker 2>/dev/null || service docker start 2>/dev/null
            sleep 2
        fi
        if ! docker info >/dev/null 2>&1; then
            _dk_p '\033[1;31m[실패] Docker 데몬에 연결할 수 없습니다.\033[0m\n'
            return 1
        fi
    fi

    _DK_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "OK")
    if docker compose version >/dev/null 2>&1; then
        _DK_COMPOSE_BIN="docker compose"
        _DK_COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "v2")
    elif command -v docker-compose >/dev/null 2>&1; then
        _DK_COMPOSE_BIN="docker-compose"
        _DK_COMPOSE_VER=$(docker-compose version --short 2>/dev/null || echo "v1")
    fi
    return 0
}

_dk_compose_run() {
    local _dir="$1"
    shift
    if [ -z "$_DK_COMPOSE_BIN" ]; then
        _dk_p '\033[1;31m[오류] docker compose / docker-compose 가 설치되어 있지 않습니다.\033[0m\n'
        return 1
    fi
    if [ -n "$_dir" ] && [ -d "$_dir" ]; then
        ( cd "$_dir" && $_DK_COMPOSE_BIN "$@" )
    else
        $_DK_COMPOSE_BIN "$@"
    fi
}

_dk_load_summary() {
    _DK_CNT_RUN=0
    _DK_CNT_STOP=0
    _DK_CNT_IMG=0
    _DK_CNT_VOL=0
    _DK_CNT_NET=0
    local _st
    while IFS= read -r _st; do
        [ -z "$_st" ] && continue
        if [ "$_st" = "running" ]; then
            _DK_CNT_RUN=$((_DK_CNT_RUN + 1))
        else
            _DK_CNT_STOP=$((_DK_CNT_STOP + 1))
        fi
    done < <(docker ps -a --format '{{.State}}' 2>/dev/null)
    _DK_CNT_IMG=$(docker images -q 2>/dev/null | wc -l | tr -d ' ')
    _DK_CNT_VOL=$(docker volume ls -q 2>/dev/null | wc -l | tr -d ' ')
    _DK_CNT_NET=$(docker network ls -q 2>/dev/null | wc -l | tr -d ' ')
}

_dk_load_tab() {
    _DK_IDS=()
    _DK_NAMES=()
    _DK_STATE=()
    _DK_COL2=()
    _DK_COL3=()
    _DK_META=()
    _DK_TOTAL=0

    local _line _c1 _c2 _c3 _c4 _c5 _c6 _c7 _dir _f _seen _dup _d _p _st _cf
    case "$_DK_TAB" in
        1) # Containers
            while IFS='|' read -r _c1 _c2 _c3 _c4 _c5 _c6 _c7; do
                [ -z "$_c1" ] && continue
                _DK_IDS[$_DK_TOTAL]="$_c1"
                _DK_NAMES[$_DK_TOTAL]="$_c2"
                _DK_STATE[$_DK_TOTAL]="$_c3"
                _DK_COL2[$_DK_TOTAL]="$_c4"
                _DK_COL3[$_DK_TOTAL]="$_c5"
                _DK_META[$_DK_TOTAL]="${_c6}|${_c7}"
                _DK_TOTAL=$((_DK_TOTAL + 1))
            done < <(docker ps -a --format '{{.ID}}|{{.Names}}|{{.State}}|{{.Status}}|{{.Image}}|{{.Label "com.docker.compose.project"}}|{{.Ports}}' 2>/dev/null)
            ;;
        2) # Stacks (Compose: container labels aggregate + local compose.yml scan, Compose v1/v2 universal)
            _seen=""
            while IFS='|' read -r _c1 _c2 _c3 _c4; do
                [ -z "$_c1" ] && continue
                _cf="${_c4%%,*}"
                _dir="$_c3"
                [ -z "$_dir" ] && [ -n "$_cf" ] && _dir=$(dirname "$_cf" 2>/dev/null)
                _DK_IDS[$_DK_TOTAL]="$_dir"
                _DK_NAMES[$_DK_TOTAL]="$_c1"
                case "$_c2" in
                    running*) _DK_STATE[$_DK_TOTAL]="running" ;;
                    *)        _DK_STATE[$_DK_TOTAL]="stopped" ;;
                esac
                _DK_COL2[$_DK_TOTAL]="$_c2"
                _DK_COL3[$_DK_TOTAL]="${_dir:-$_cf}"
                _DK_META[$_DK_TOTAL]="$_cf"
                [ -n "$_dir" ] && _seen="${_seen}|${_dir}|"
                _DK_TOTAL=$((_DK_TOTAL + 1))
            done < <(docker ps -a --format '{{.Label "com.docker.compose.project"}}|{{.State}}|{{.Label "com.docker.compose.project.working_dir"}}|{{.Label "com.docker.compose.project.config_files"}}' 2>/dev/null | awk -F'|' '
                $1 != "" {
                    p=$1; tot[p]++;
                    if ($2 == "running") run[p]++;
                    if (!(p in dir) && $3 != "") dir[p]=$3;
                    if (!(p in cf) && $4 != "") cf[p]=$4;
                    if (!(p in seen)) { order[++n]=p; seen[p]=1; }
                }
                END {
                    for (i=1; i<=n; i++) {
                        p=order[i]; r=run[p]+0; t=tot[p]+0;
                        st = (r > 0) ? ("running(" r "/" t ")") : ("exited(0/" t ")");
                        printf "%s|%s|%s|%s\n", p, st, dir[p], cf[p];
                    }
                }')
            # Scan local compose directories (depth <= 4)
            for _d in $_DK_SCAN_DIRS; do
                [ -d "$_d" ] || continue
                while IFS= read -r _f; do
                    [ -f "$_f" ] || continue
                    _dir=$(dirname "$_f")
                    case "$_seen" in *"|${_dir}|"*) continue ;; esac
                    _p=$(basename "$_dir")
                    _DK_IDS[$_DK_TOTAL]="$_dir"
                    _DK_NAMES[$_DK_TOTAL]="$_p"
                    _DK_STATE[$_DK_TOTAL]="local"
                    _DK_COL2[$_DK_TOTAL]="stopped (local)"
                    _DK_COL3[$_DK_TOTAL]="$_dir"
                    _DK_META[$_DK_TOTAL]="$_f"
                    _seen="${_seen}|${_dir}|"
                    _DK_TOTAL=$((_DK_TOTAL + 1))
                done < <(find "$_d" -maxdepth 4 -type f \( -name 'compose.yml' -o -name 'compose.yaml' -o -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \) 2>/dev/null | sort)
            done
            ;;
        3) # Images
            while IFS='|' read -r _c1 _c2 _c3 _c4; do
                [ -z "$_c1" ] && continue
                _DK_IDS[$_DK_TOTAL]="$_c1"
                _DK_NAMES[$_DK_TOTAL]="$_c2"
                case "$_c2" in
                    *"<none>"*) _DK_STATE[$_DK_TOTAL]="dangling" ;;
                    *)          _DK_STATE[$_DK_TOTAL]="image" ;;
                esac
                _DK_COL2[$_DK_TOTAL]="$_c3"
                _DK_COL3[$_DK_TOTAL]="$_c4"
                _DK_META[$_DK_TOTAL]="$_c1"
                _DK_TOTAL=$((_DK_TOTAL + 1))
            done < <(docker images --format '{{.ID}}|{{.Repository}}:{{.Tag}}|{{.Size}}|{{.CreatedSince}}' 2>/dev/null)
            ;;
        4) # Volumes
            while IFS='|' read -r _c1 _c2; do
                [ -z "$_c1" ] && continue
                _DK_IDS[$_DK_TOTAL]="$_c1"
                _DK_NAMES[$_DK_TOTAL]="$_c1"
                _DK_STATE[$_DK_TOTAL]="volume"
                _DK_COL2[$_DK_TOTAL]="$_c2"
                _DK_COL3[$_DK_TOTAL]="/var/lib/docker/volumes/${_c1}/_data"
                _DK_META[$_DK_TOTAL]="$_c2"
                _DK_TOTAL=$((_DK_TOTAL + 1))
            done < <(docker volume ls --format '{{.Name}}|{{.Driver}}' 2>/dev/null)
            ;;
        5) # Networks
            while IFS='|' read -r _c1 _c2 _c3 _c4; do
                [ -z "$_c1" ] && continue
                _DK_IDS[$_DK_TOTAL]="$_c1"
                _DK_NAMES[$_DK_TOTAL]="$_c2"
                _DK_STATE[$_DK_TOTAL]="network"
                _DK_COL2[$_DK_TOTAL]="${_c3}/${_c4}"
                _DK_COL3[$_DK_TOTAL]="$_c1"
                _DK_META[$_DK_TOTAL]="$_c3"
                _DK_TOTAL=$((_DK_TOTAL + 1))
            done < <(docker network ls --format '{{.ID}}|{{.Name}}|{{.Driver}}|{{.Scope}}' 2>/dev/null)
            ;;
        6) # System & Live Stats snapshot
            while IFS='|' read -r _c1 _c2 _c3 _c4 _c5 _c6; do
                [ -z "$_c1" ] && continue
                _DK_IDS[$_DK_TOTAL]="$_c1"
                _DK_NAMES[$_DK_TOTAL]="$_c1"
                _DK_STATE[$_DK_TOTAL]="running"
                _DK_COL2[$_DK_TOTAL]="CPU:${_c2} MEM:${_c4} (${_c3})"
                _DK_COL3[$_DK_TOTAL]="NET:${_c5} IO:${_c6}"
                _DK_META[$_DK_TOTAL]="$_c1"
                _DK_TOTAL=$((_DK_TOTAL + 1))
            done < <(docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}' 2>/dev/null)
            ;;
    esac
}

_dk_build_view() {
    _DK_VIEW=()
    _DK_VCNT=0
    local _i _q _hay
    _q=$(printf '%s' "$_DK_SEARCH" | tr '[:upper:]' '[:lower:]')
    _i=0
    while [ "$_i" -lt "$_DK_TOTAL" ]; do
        if [ -z "$_q" ]; then
            _DK_VIEW[$_DK_VCNT]="$_i"
            _DK_VCNT=$((_DK_VCNT + 1))
        else
            _hay=$(printf '%s %s %s %s' "${_DK_NAMES[$_i]}" "${_DK_COL2[$_i]}" "${_DK_COL3[$_i]}" "${_DK_META[$_i]}" | tr '[:upper:]' '[:lower:]')
            case "$_hay" in
                *"$_q"*)
                    _DK_VIEW[$_DK_VCNT]="$_i"
                    _DK_VCNT=$((_DK_VCNT + 1))
                    ;;
            esac
        fi
        _i=$((_i + 1))
    done
    [ "$_DK_CUR" -ge "$_DK_VCNT" ] && _DK_CUR=$((_DK_VCNT > 0 ? _DK_VCNT - 1 : 0))
    [ "$_DK_CUR" -lt 0 ] && _DK_CUR=0
    [ "$_DK_TOP" -gt "$_DK_CUR" ] && _DK_TOP="$_DK_CUR"
}

_dk_render_row() {
    local _vidx="$1" _is_cur="$2"
    local _idx="${_DK_VIEW[$_vidx]}"
    local _st="${_DK_STATE[$_idx]}"
    local _nm="${_DK_NAMES[$_idx]}"
    local _c2="${_DK_COL2[$_idx]}"
    local _c3="${_DK_COL3[$_idx]}"
    local _mark=" " _bg="" _rst='\033[0m' _ico _iclr

    case "$_st" in
        running)  _ico="●"; _iclr='\033[1;32m' ;;
        paused)   _ico="◐"; _iclr='\033[1;33m' ;;
        dangling) _ico="⚠"; _iclr='\033[1;33m' ;;
        local)    _ico="○"; _iclr='\033[0;36m' ;;
        image|volume|network) _ico="◆"; _iclr='\033[1;36m' ;;
        *)        _ico="○"; _iclr='\033[1;31m' ;;
    esac

    if [ "$_is_cur" = "1" ]; then
        _mark="▶"
        _bg='\033[44;1;37m'
        _iclr='\033[44;1;33m'
    fi

    # Truncate for clean column alignment
    [ "${#_nm}" -gt 24 ] && _nm="${_nm:0:23}~"
    [ "${#_c2}" -gt 26 ] && _c2="${_c2:0:25}~"
    local _c3_max=$((_DK_COLS - 58))
    [ "$_c3_max" -lt 16 ] && _c3_max=16
    [ "${#_c3}" -gt "$_c3_max" ] && _c3="${_c3:0:$((_c3_max - 1))}~"

    _dk_p "${_bg} %s ${_iclr}%s${_rst}${_bg} %-24s  %-26s  %s\033[K${_rst}" "$_mark" "$_ico" "$_nm" "$_c2" "$_c3"
}

_dk_render_full() {
    _DK_LINES=$(tput lines 2>/dev/null || echo 24)
    _DK_COLS=$(tput cols 2>/dev/null || echo 100)
    [ "$_DK_LINES" -lt 16 ] && _DK_LINES=16
    [ "$_DK_COLS" -lt 70 ] && _DK_COLS=70
    _DK_PAGE=$((_DK_LINES - 9))
    [ "$_DK_PAGE" -lt 5 ] && _DK_PAGE=5

    if [ "$_DK_CUR" -lt "$_DK_TOP" ]; then
        _DK_TOP="$_DK_CUR"
    elif [ "$_DK_CUR" -ge $((_DK_TOP + _DK_PAGE)) ]; then
        _DK_TOP=$((_DK_CUR - _DK_PAGE + 1))
    fi

    printf '\033[H'
    # Line 1: Header
    _dk_p '\033[1;36m◈ Docker & Compose Studio [dkms]\033[0m  \033[1;37m%s\033[0m  Docker:%s  Compose:%s  \033[1;32mRun:%s\033[0m/\033[1;31mStop:%s\033[0m Img:%s Vol:%s Net:%s\033[K\n' \
        "$_DK_HOST" "$_DK_VER" "$_DK_COMPOSE_VER" "$_DK_CNT_RUN" "$_DK_CNT_STOP" "$_DK_CNT_IMG" "$_DK_CNT_VOL" "$_DK_CNT_NET"

    # Line 2: Tab Bar
    local _t _tlbl _tbar=""
    for _t in 1 2 3 4 5 6; do
        case "$_t" in
            1) _tlbl="1:Containers" ;;
            2) _tlbl="2:Stacks(Compose)" ;;
            3) _tlbl="3:Images" ;;
            4) _tlbl="4:Volumes" ;;
            5) _tlbl="5:Networks" ;;
            6) _tlbl="6:System&Stats" ;;
        esac
        if [ "$_t" = "$_DK_TAB" ]; then
            _tbar="${_tbar}\033[46;1;30m [${_tlbl}] \033[0m "
        else
            _tbar="${_tbar}\033[0;37m ${_tlbl} \033[0m "
        fi
    done
    _dk_p "${_tbar}\033[K\n"

    # Line 3: Divider + Search status
    if [ -n "$_DK_SEARCH" ]; then
        _dk_p '\033[0;36m──────────────────────────────────────────────────────────────────────\033[0m \033[1;33m[검색: %s (%d건)]\033[0m\033[K\n' "$_DK_SEARCH" "$_DK_VCNT"
    else
        _dk_p '\033[0;36m──────────────────────────────────────────────────────────────────────\033[0m (%d건)\033[K\n' "$_DK_VCNT"
    fi

    # Line 4: Column Header
    case "$_DK_TAB" in
        1) _dk_p '\033[1;37m     %-24s  %-26s  %s\033[0m\033[K\n' "NAME" "STATUS" "IMAGE" ;;
        2) _dk_p '\033[1;37m     %-24s  %-26s  %s\033[0m\033[K\n' "STACK (PROJECT)" "STATUS" "COMPOSE DIR" ;;
        3) _dk_p '\033[1;37m     %-24s  %-26s  %s\033[0m\033[K\n' "REPOSITORY:TAG" "SIZE" "CREATED" ;;
        4) _dk_p '\033[1;37m     %-24s  %-26s  %s\033[0m\033[K\n' "VOLUME NAME" "DRIVER" "MOUNTPOINT" ;;
        5) _dk_p '\033[1;37m     %-24s  %-26s  %s\033[0m\033[K\n' "NETWORK NAME" "DRIVER/SCOPE" "NETWORK ID" ;;
        6) _dk_p '\033[1;37m     %-24s  %-26s  %s\033[0m\033[K\n' "CONTAINER (LIVE)" "CPU / MEM" "NET / BLOCK IO" ;;
    esac

    # Lines 5..(5+PAGE-1): List rows
    local _r=0 _v
    while [ "$_r" -lt "$_DK_PAGE" ]; do
        _v=$((_DK_TOP + _r))
        if [ "$_v" -lt "$_DK_VCNT" ]; then
            if [ "$_v" -eq "$_DK_CUR" ]; then
                _dk_render_row "$_v" 1
            else
                _dk_render_row "$_v" 0
            fi
            printf '\n'
        else
            if [ "$_r" -eq 0 ] && [ "$_DK_VCNT" -eq 0 ]; then
                _dk_p '   \033[0;33m(표시할 항목이 없습니다. Tab/1~6 으로 다른 탭을 보거나 n 으로 스택 생성)\033[0m\033[K\n'
            else
                printf '\033[K\n'
            fi
        fi
        _r=$((_r + 1))
    done

    # Footer: Tab-specific hotkeys
    _dk_p '\033[0;36m──────────────────────────────────────────────────────────────────────\033[0m\033[K\n'
    case "$_DK_TAB" in
        1) _dk_p '\033[1;33m[Enter]\033[0m메뉴 \033[1;32m[s]\033[0mStart/Stop \033[1;36m[R]\033[0m재시작 \033[1;35m[l]\033[0m로그 \033[1;37m[e]\033[0m쉘진입 \033[1;36m[i]\033[0m상세 \033[1;33m[c]\033[0mCompose편집 \033[1;31m[d]\033[0m삭제\033[K\n' ;;
        2) _dk_p '\033[1;33m[Enter]\033[0m상세 \033[1;32m[u]\033[0mUp-d \033[1;31m[D]\033[0mDown \033[1;36m[R]\033[0m재시작 \033[1;35m[P]\033[0mPull+Up \033[1;33m[v]\033[0mYAML편집 \033[1;37m[l]\033[0m로그 \033[1;32m[n]\033[0m새스택 \033[1;36m[+]\033[0m경로\033[K\n' ;;
        3) _dk_p '\033[1;33m[Enter/i]\033[0m상세 \033[1;32m[p]\033[0mPull이미지 \033[1;31m[d]\033[0m삭제 \033[1;35m[x]\033[0m미사용정리(Prune)\033[K\n' ;;
        4) _dk_p '\033[1;33m[Enter/i]\033[0m상세/마운트 \033[1;31m[d]\033[0m삭제 \033[1;35m[x]\033[0m미사용볼륨정리(Prune)\033[K\n' ;;
        5) _dk_p '\033[1;33m[Enter/i]\033[0m상세/서브넷 \033[1;31m[d]\033[0m삭제 \033[1;35m[x]\033[0m미사용네트워크정리(Prune)\033[K\n' ;;
        6) _dk_p '\033[1;32m[Enter/t]\033[0m실시간Stats \033[1;36m[i]\033[0m디스크점유(df-v) \033[1;35m[x]\033[0mSystemPrune \033[1;33m[B]\033[0m빌드캐시정리 \033[1;31m[R]\033[0m데몬재시작\033[K\n' ;;
    esac
    _dk_p '\033[0;37m[↑↓]이동 [←→/Tab/1-6]탭전환 [/]검색 [r]새로고침 [?]도움말 [q]종료\033[0m\033[K\n'
    _dk_p '\033[1;32m%s\033[0m\033[K' "${_DK_MSG:-}"
    _DK_DIRTY=0
    _DK_PREV_CUR="$_DK_CUR"
    _DK_PREV_TOP="$_DK_TOP"
}

_dk_render_delta() {
    if [ "$_DK_DIRTY" = "1" ] || [ "$_DK_TOP" -ne "$_DK_PREV_TOP" ] || [ "$_DK_CUR" -lt "$_DK_TOP" ] || [ "$_DK_CUR" -ge $((_DK_TOP + _DK_PAGE)) ]; then
        _dk_render_full
        return
    fi
    if [ "$_DK_PREV_CUR" -ne "$_DK_CUR" ]; then
        local _r1=$((5 + _DK_PREV_CUR - _DK_TOP))
        local _r2=$((5 + _DK_CUR - _DK_TOP))
        printf '\033[%d;1H' "$_r1"
        _dk_render_row "$_DK_PREV_CUR" 0
        printf '\033[%d;1H' "$_r2"
        _dk_render_row "$_DK_CUR" 1
        _DK_PREV_CUR="$_DK_CUR"
    fi
}

_dk_show_help() {
    tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
    _dk_p '\033[1;36m◈ 통합 도커·컴포즈 관리 TUI [dkms] 단축키 도움말\033[0m\n\n'
    _dk_p '  \033[1;37m[공통 이동/탭]\033[0m\n'
    _dk_p '    ↑/↓, j/k       : 항목 이동 (PgUp/PgDn 페이지 이동)\n'
    _dk_p '    ←/→, Tab, 1~6  : 6개 탭 즉시 전환 (Containers/Stacks/Images/Volumes/Networks/System)\n'
    _dk_p '    /              : 현재 탭 키워드 필터 검색 (빈 값으로 Enter = 초기화)\n'
    _dk_p '    r              : 데이터 새로고침   |   q : 종료\n\n'
    _dk_p '  \033[1;37m[Tab 1: Containers]\033[0m\n'
    _dk_p '    Enter : 액션 메뉴  | s : Start/Stop 토글 | R : 재시작 | l : 실시간 로그(Ctrl+C 복귀)\n'
    _dk_p '    e     : 쉘 즉시접속(bash->sh 폴백) | i : Inspect 요약 | c : Compose YAML 편집 | d : 삭제\n\n'
    _dk_p '  \033[1;37m[Tab 2: Stacks (Docker Compose)]\033[0m\n'
    _dk_p '    Enter : 스택 상세(compose ps) | u : up -d | D : down | R : restart | P : pull + up -d 업데이트\n'
    _dk_p '    v     : compose.yml/.env vi2 편집(+문법검증/반영) | l : 통합로그 | n : 새 스택 | + : 스캔경로 추가\n\n'
    _dk_p '  \033[1;37m[Tab 3~6: Images / Volumes / Networks / System]\033[0m\n'
    _dk_p '    i/Enter : 상세정보 | p : 이미지 Pull | d : 개별 삭제 | x : Prune 정리 | t : 실시간 stats\n'
    _dk_pause
}

_dk_container_inspect() {
    local _id="$1" _nm="$2"
    tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
    _dk_p '\033[1;36m◈ 컨테이너 상세 정보: %s (%s)\033[0m\n' "$_nm" "$_id"
    _dk_p '──────────────────────────────────────────────────────────────────────\n'
    docker inspect --format 'Image      : {{.Config.Image}}
State      : {{.State.Status}} (Running={{.State.Running}}, Restarting={{.State.Restarting}}, ExitCode={{.State.ExitCode}})
StartedAt  : {{.State.StartedAt}}
RestartPol : {{.HostConfig.RestartPolicy.Name}}
ComposeDir : {{index .Config.Labels "com.docker.compose.project.working_dir"}}
ComposeFile: {{index .Config.Labels "com.docker.compose.project.config_files"}}
Networks   : {{range $k, $v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}
Ports      : {{range $p, $conf := .NetworkSettings.Ports}}{{$p}}->{{range $conf}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}' "$_id" 2>/dev/null
    _dk_p '\n\n\033[1;33m[볼륨 마운트]\033[0m\n'
    docker inspect --format '{{range .Mounts}}  {{.Type}}: {{.Source}} -> {{.Destination}} ({{.Mode}}){{"\n"}}{{end}}' "$_id" 2>/dev/null
    _dk_p '\033[1;33m[환경변수 (상위 20개)]\033[0m\n'
    docker inspect --format '{{range .Config.Env}}  {{.}}{{"\n"}}{{end}}' "$_id" 2>/dev/null | head -n 20
    _dk_pause
}

_dk_container_action() {
    local _act="$1" _idx="$2"
    local _id="${_DK_IDS[$_idx]}" _nm="${_DK_NAMES[$_idx]}" _st="${_DK_STATE[$_idx]}"
    local _ans _wdir _cfile
    case "$_act" in
        menu)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _dk_p '\033[1;36m◈ 컨테이너 액션: %s [%s]\033[0m\n' "$_nm" "$_st"
            _dk_p '  1) Start / Stop 토글\n  2) Restart (재시작)\n  3) 실시간 로그 (logs -f)\n  4) 컨테이너 쉘 진입 (bash/sh)\n  5) 상세 Inspect 보기\n  6) 소속 Compose YAML 편집\n  7) 컨테이너 삭제 (rm)\n  0) 취소\n'
            read -p "선택 [0-7]: " _ans </dev/tty
            case "$_ans" in
                1) _dk_container_action toggle "$_idx" ;;
                2) _dk_container_action restart "$_idx" ;;
                3) _dk_container_action logs "$_idx" ;;
                4) _dk_container_action exec "$_idx" ;;
                5) _dk_container_inspect "$_id" "$_nm" ;;
                6) _dk_container_action compose_edit "$_idx" ;;
                7) _dk_container_action rm "$_idx" ;;
            esac
            return
            ;;
        toggle)
            if [ "$_st" = "running" ]; then
                docker stop "$_id" >/dev/null 2>&1 && _DK_MSG="✔ 중지 완료: $_nm" || _DK_MSG="✖ 중지 실패: $_nm"
            else
                docker start "$_id" >/dev/null 2>&1 && _DK_MSG="✔ 시작 완료: $_nm" || _DK_MSG="✖ 시작 실패: $_nm"
            fi
            _dk_load_summary; _dk_load_tab; _dk_build_view
            ;;
        restart)
            docker restart "$_id" >/dev/null 2>&1 && _DK_MSG="✔ 재시작 완료: $_nm" || _DK_MSG="✖ 재시작 실패: $_nm"
            _dk_load_summary; _dk_load_tab; _dk_build_view
            ;;
        logs)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _dk_p '\033[1;36m◈ 실시간 로그: %s (종료: Ctrl+C)\033[0m\n' "$_nm"
            ( trap 'exit 0' INT; docker logs -f --tail 100 "$_id" )
            _dk_pause
            ;;
        exec)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _dk_p '\033[1;36m◈ 컨테이너 쉘 접속: %s (종료: exit)\033[0m\n' "$_nm"
            docker exec -it "$_id" bash 2>/dev/null || docker exec -it "$_id" sh
            _DK_MSG="✔ 쉘 세션 종료: $_nm"
            ;;
        inspect)
            _dk_container_inspect "$_id" "$_nm"
            ;;
        compose_edit)
            _wdir=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$_id" 2>/dev/null)
            _cfile=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$_id" 2>/dev/null)
            _cfile="${_cfile%%,*}"
            if [ -n "$_cfile" ] && [ -f "$_cfile" ]; then
                _dk_stack_edit "$_wdir" "$_cfile"
            else
                _DK_MSG="⚠ Compose 기반 컨테이너가 아니거나 YAML 경로를 찾을 수 없습니다: $_nm"
            fi
            ;;
        rm)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _dk_p '\033[1;31m⚠ 컨테이너 삭제 확인: %s (%s / 상태=%s)\033[0m\n' "$_nm" "$_id" "$_st"
            read -p "정말 삭제할까요? [y/N]: " _ans </dev/tty
            if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                if [ "$_st" = "running" ]; then
                    docker rm -f "$_id" >/dev/null 2>&1 && _DK_MSG="✔ 강제 삭제 완료: $_nm" || _DK_MSG="✖ 삭제 실패: $_nm"
                else
                    docker rm "$_id" >/dev/null 2>&1 && _DK_MSG="✔ 삭제 완료: $_nm" || _DK_MSG="✖ 삭제 실패: $_nm"
                fi
                _dk_load_summary; _dk_load_tab; _dk_build_view
            else
                _DK_MSG="취소됨: $_nm"
            fi
            ;;
    esac
}

_dk_stack_edit() {
    local _dir="$1" _cfile="$2" _target _ans
    tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
    _target="$_cfile"
    if [ -f "${_dir}/.env" ]; then
        _dk_p '\033[1;36m◈ 편집할 파일 선택 (%s)\033[0m\n' "$_dir"
        _dk_p '  1) %s\n  2) %s/.env\n  0) 취소\n' "$(basename "$_cfile")" "$_dir"
        read -p "선택 [1]: " _ans </dev/tty
        case "$_ans" in
            0) return ;;
            2) _target="${_dir}/.env" ;;
        esac
    fi
    if declare -f vi2 >/dev/null 2>&1; then
        vi2 "$_target"
    else
        vi "$_target"
    fi
    _dk_p '\n\033[1;36m[문법 검증] compose config -q 실행 중...\033[0m\n'
    if _dk_compose_run "$_dir" config -q; then
        _dk_p '\033[1;32m✔ YAML 문법 정상!\033[0m\n'
        read -p "지금 바로 'compose up -d' 로 반영할까요? [Y/n]: " _ans </dev/tty
        if ! printf '%s' "$_ans" | grep -qE '^[Nn]$'; then
            _dk_compose_run "$_dir" up -d
            _DK_MSG="✔ 편집 & up -d 반영 완료: $(basename "$_dir")"
            _dk_load_summary; _dk_load_tab; _dk_build_view
        fi
    else
        _dk_p '\033[1;31m✖ YAML 문법 오류가 감지되었습니다! 반영을 중단합니다.\033[0m\n'
    fi
    _dk_pause
}

_dk_stack_new() {
    local _dir _ans _file
    tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
    _dk_p '\033[1;36m◈ 새 Docker Compose 스택 만들기\033[0m\n'
    read -p "스택 디렉터리 경로 (예: /data/docker/myapp): " _dir </dev/tty
    [ -z "$_dir" ] && return
    mkdir -p "$_dir" || { _DK_MSG="✖ 디렉터리 생성 실패: $_dir"; return; }
    _file="${_dir}/compose.yml"
    if [ ! -f "$_file" ]; then
        cat >"$_file" <<'EOF'
services:
  app:
    image: nginx:alpine
    container_name: myapp
    restart: unless-stopped
    ports:
      - "8080:80"
EOF
    fi
    _dk_stack_edit "$_dir" "$_file"
    case " $_DK_SCAN_DIRS " in
        *" $(dirname "$_dir") "*) ;;
        *) _DK_SCAN_DIRS="${_DK_SCAN_DIRS} $(dirname "$_dir")" ;;
    esac
    _dk_load_summary; _dk_load_tab; _dk_build_view
}

_dk_stack_action() {
    local _act="$1" _idx="$2"
    local _dir="${_DK_IDS[$_idx]}" _nm="${_DK_NAMES[$_idx]}" _cf="${_DK_META[$_idx]}"
    local _ans
    case "$_act" in
        menu)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _dk_p '\033[1;36m◈ 스택 상세: %s (%s)\033[0m\n' "$_nm" "$_dir"
            _dk_p '──────────────────────────────────────────────────────────────────────\n'
            _dk_compose_run "$_dir" ps -a 2>/dev/null
            _dk_p '\n  1) up -d (기동/반영)    2) down (내리기)    3) restart (재시작)\n'
            _dk_p '  4) pull + up -d (최신업데이트)  5) YAML/.env 편집(vi2)  6) 통합 로그\n  0) 돌아가기\n'
            read -p "선택 [0-6]: " _ans </dev/tty
            case "$_ans" in
                1) _dk_stack_action up "$_idx" ;;
                2) _dk_stack_action down "$_idx" ;;
                3) _dk_stack_action restart "$_idx" ;;
                4) _dk_stack_action update "$_idx" ;;
                5) _dk_stack_edit "$_dir" "$_cf" ;;
                6) _dk_stack_action logs "$_idx" ;;
            esac
            return
            ;;
        up)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _dk_p '\033[1;32m▶ compose up -d: %s (%s)\033[0m\n' "$_nm" "$_dir"
            _dk_compose_run "$_dir" up -d && _DK_MSG="✔ up -d 완료: $_nm" || _DK_MSG="✖ up -d 실패: $_nm"
            _dk_load_summary; _dk_load_tab; _dk_build_view
            _dk_pause
            ;;
        down)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _dk_p '\033[1;31m⚠ 스택 중지/제거 (compose down): %s (%s)\033[0m\n' "$_nm" "$_dir"
            read -p "정말 down 할까요? [y/N]: " _ans </dev/tty
            if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                _dk_compose_run "$_dir" down && _DK_MSG="✔ down 완료: $_nm" || _DK_MSG="✖ down 실패: $_nm"
                _dk_load_summary; _dk_load_tab; _dk_build_view
                _dk_pause
            fi
            ;;
        restart)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _dk_p '\033[1;36m▶ compose restart: %s\033[0m\n' "$_nm"
            _dk_compose_run "$_dir" restart && _DK_MSG="✔ 스택 재시작 완료: $_nm" || _DK_MSG="✖ 재시작 실패: $_nm"
            _dk_load_summary; _dk_load_tab; _dk_build_view
            _dk_pause
            ;;
        update)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _dk_p '\033[1;35m▶ 원클릭 최신 업데이트 (pull + up -d): %s\033[0m\n' "$_nm"
            if _dk_compose_run "$_dir" pull && _dk_compose_run "$_dir" up -d; then
                _DK_MSG="✔ pull + up -d 업데이트 완료: $_nm"
            else
                _DK_MSG="✖ 업데이트 실패: $_nm"
            fi
            _dk_load_summary; _dk_load_tab; _dk_build_view
            _dk_pause
            ;;
        edit)
            _dk_stack_edit "$_dir" "$_cf"
            ;;
        logs)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _dk_p '\033[1;36m◈ 스택 통합 로그: %s (종료: Ctrl+C)\033[0m\n' "$_nm"
            ( trap 'exit 0' INT; _dk_compose_run "$_dir" logs -f --tail 100 )
            _dk_pause
            ;;
    esac
}

dkms() {
    _dk_detect_env || return 1

    _DK_TAB=1
    _DK_CUR=0
    _DK_TOP=0
    _DK_PREV_CUR=0
    _DK_PREV_TOP=0
    _DK_SEARCH=""
    _DK_MSG="✔ dkms 준비 완료 (1~6 탭전환, Enter 메뉴, ? 도움말)"
    _DK_DIRTY=1

    _dk_load_summary
    _dk_load_tab
    _dk_build_view

    local _old_trap _k _k2 _k3 _idx _ans _img _ndir
    _old_trap=$(trap -p INT)
    trap 'tput cnorm 2>/dev/null; stty sane 2>/dev/null; printf "\n"; return 0' INT

    tput civis 2>/dev/null
    printf '\033[2J\033[H'

    while true; do
        _dk_render_delta
        stty -echo 2>/dev/null
        IFS= read -rsn1 _k </dev/tty

        # Arrow / Page / Home / End escape sequences
        if [ "$_k" = $'\x1b' ]; then
            IFS= read -rsn1 -t 1 _k2 </dev/tty
            if [ "$_k2" = "[" ]; then
                IFS= read -rsn1 -t 1 _k3 </dev/tty
                case "$_k3" in
                    A) [ "$_DK_CUR" -gt 0 ] && _DK_CUR=$((_DK_CUR - 1)) ;;
                    B) [ "$_DK_CUR" -lt $((_DK_VCNT - 1)) ] && _DK_CUR=$((_DK_CUR + 1)) ;;
                    C) _DK_TAB=$((_DK_TAB % 6 + 1)); _DK_CUR=0; _DK_TOP=0; _DK_SEARCH=""; _dk_load_tab; _dk_build_view; _DK_DIRTY=1 ;;
                    D) _DK_TAB=$(( (_DK_TAB + 4) % 6 + 1 )); _DK_CUR=0; _DK_TOP=0; _DK_SEARCH=""; _dk_load_tab; _dk_build_view; _DK_DIRTY=1 ;;
                    5) IFS= read -rsn1 -t 1 _ </dev/tty; _DK_CUR=$((_DK_CUR - _DK_PAGE)); [ "$_DK_CUR" -lt 0 ] && _DK_CUR=0; _DK_DIRTY=1 ;;
                    6) IFS= read -rsn1 -t 1 _ </dev/tty; _DK_CUR=$((_DK_CUR + _DK_PAGE)); [ "$_DK_CUR" -ge "$_DK_VCNT" ] && _DK_CUR=$((_DK_VCNT > 0 ? _DK_VCNT - 1 : 0)); _DK_DIRTY=1 ;;
                    H) _DK_CUR=0; _DK_DIRTY=1 ;;
                    F) _DK_CUR=$((_DK_VCNT > 0 ? _DK_VCNT - 1 : 0)); _DK_DIRTY=1 ;;
                esac
            else
                # Standalone Esc clears search filter
                if [ -n "$_DK_SEARCH" ]; then
                    _DK_SEARCH=""; _DK_CUR=0; _DK_TOP=0; _dk_build_view; _DK_DIRTY=1
                fi
            fi
            continue
        fi

        case "$_k" in
            q|Q) break ;;
            $'\t')
                _DK_TAB=$((_DK_TAB % 6 + 1)); _DK_CUR=0; _DK_TOP=0; _DK_SEARCH=""
                _dk_load_tab; _dk_build_view; _DK_DIRTY=1
                ;;
            1|2|3|4|5|6)
                if [ "$_DK_TAB" != "$_k" ]; then
                    _DK_TAB="$_k"; _DK_CUR=0; _DK_TOP=0; _DK_SEARCH=""
                    _dk_load_tab; _dk_build_view; _DK_DIRTY=1
                fi
                ;;
            k) [ "$_DK_CUR" -gt 0 ] && _DK_CUR=$((_DK_CUR - 1)) ;;
            j) [ "$_DK_CUR" -lt $((_DK_VCNT - 1)) ] && _DK_CUR=$((_DK_CUR + 1)) ;;
            \?|h)
                _dk_show_help; _DK_DIRTY=1; tput civis 2>/dev/null ;;
            /)
                tput cnorm 2>/dev/null; stty echo 2>/dev/null
                _dk_p '\n검색어 입력 (빈 값=초기화): '
                IFS= read -r _DK_SEARCH </dev/tty
                _DK_CUR=0; _DK_TOP=0; _dk_build_view; _DK_DIRTY=1; tput civis 2>/dev/null
                ;;
            r)
                _dk_load_summary; _dk_load_tab; _dk_build_view
                _DK_MSG="✔ 새로고침 완료"
                _DK_DIRTY=1
                ;;
            *)
                # Tab-specific hotkeys
                _idx=""
                [ "$_DK_VCNT" -gt 0 ] && _idx="${_DK_VIEW[$_DK_CUR]}"
                case "$_DK_TAB" in
                    1) # Containers
                        [ -z "$_idx" ] && continue
                        case "$_k" in
                            "") _dk_container_action menu "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null ;;
                            s)  _dk_container_action toggle "$_idx"; _DK_DIRTY=1 ;;
                            R)  _dk_container_action restart "$_idx"; _DK_DIRTY=1 ;;
                            l)  _dk_container_action logs "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null ;;
                            e)  _dk_container_action exec "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null ;;
                            i)  _dk_container_action inspect "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null ;;
                            c)  _dk_container_action compose_edit "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null ;;
                            d)  _dk_container_action rm "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null ;;
                        esac
                        ;;
                    2) # Stacks
                        case "$_k" in
                            n)
                                _dk_stack_new; _DK_DIRTY=1; tput civis 2>/dev/null ;;
                            +)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null
                                _dk_p '\n현재 스캔 경로: %s\n추가할 경로 입력: ' "$_DK_SCAN_DIRS"
                                IFS= read -r _ndir </dev/tty
                                if [ -n "$_ndir" ] && [ -d "$_ndir" ]; then
                                    _DK_SCAN_DIRS="${_DK_SCAN_DIRS} ${_ndir}"
                                    _dk_load_tab; _dk_build_view
                                    _DK_MSG="✔ 스캔 경로 추가: $_ndir"
                                fi
                                _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            "") [ -n "$_idx" ] && { _dk_stack_action menu "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null; } ;;
                            u)  [ -n "$_idx" ] && { _dk_stack_action up "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null; } ;;
                            D)  [ -n "$_idx" ] && { _dk_stack_action down "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null; } ;;
                            R)  [ -n "$_idx" ] && { _dk_stack_action restart "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null; } ;;
                            P)  [ -n "$_idx" ] && { _dk_stack_action update "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null; } ;;
                            v)  [ -n "$_idx" ] && { _dk_stack_action edit "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null; } ;;
                            l)  [ -n "$_idx" ] && { _dk_stack_action logs "$_idx"; _DK_DIRTY=1; tput civis 2>/dev/null; } ;;
                        esac
                        ;;
                    3) # Images
                        case "$_k" in
                            ""|i)
                                [ -z "$_idx" ] && continue
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _dk_p '\033[1;36m◈ 이미지 상세: %s (%s)\033[0m\n' "${_DK_NAMES[$_idx]}" "${_DK_IDS[$_idx]}"
                                docker image inspect --format 'RepoTags : {{.RepoTags}}
Arch/OS  : {{.Os}}/{{.Architecture}}
Size     : {{.Size}} bytes
Created  : {{.Created}}
Cmd      : {{.Config.Cmd}}
Exposed  : {{.Config.ExposedPorts}}' "${_DK_IDS[$_idx]}" 2>/dev/null
                                _dk_pause; _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            p)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _img=""
                                [ -n "$_idx" ] && [ "${_DK_NAMES[$_idx]}" != "<none>:<none>" ] && _img="${_DK_NAMES[$_idx]}"
                                read -p "Pull 할 이미지명 [기본: ${_img:-nginx:alpine}]: " _ans </dev/tty
                                [ -z "$_ans" ] && _ans="${_img:-nginx:alpine}"
                                docker pull "$_ans" && _DK_MSG="✔ Pull 완료: $_ans" || _DK_MSG="✖ Pull 실패: $_ans"
                                _dk_load_summary; _dk_load_tab; _dk_build_view
                                _dk_pause; _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            d)
                                [ -z "$_idx" ] && continue
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                read -p "이미지 삭제 (${_DK_NAMES[$_idx]} / ${_DK_IDS[$_idx]})? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    docker rmi "${_DK_IDS[$_idx]}" >/dev/null 2>&1 && _DK_MSG="✔ 이미지 삭제 완료" || _DK_MSG="✖ 삭제 실패 (사용 중 이미지)"
                                    _dk_load_summary; _dk_load_tab; _dk_build_view
                                fi
                                _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            x)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _dk_p '\033[1;33m◈ 미사용 이미지 정리 (docker image prune)\033[0m\n'
                                read -p "1) Dangling(<none>)만 정리  2) 모든 미사용 이미지 정리(-a)  0) 취소 [1]: " _ans </dev/tty
                                case "$_ans" in
                                    0) ;;
                                    2) docker image prune -a -f; _DK_MSG="✔ 모든 미사용 이미지 정리 완료" ;;
                                    *) docker image prune -f; _DK_MSG="✔ Dangling 이미지 정리 완료" ;;
                                esac
                                _dk_load_summary; _dk_load_tab; _dk_build_view
                                _dk_pause; _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                        esac
                        ;;
                    4) # Volumes
                        case "$_k" in
                            ""|i)
                                [ -z "$_idx" ] && continue
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _dk_p '\033[1;36m◈ 볼륨 상세: %s\033[0m\n' "${_DK_NAMES[$_idx]}"
                                docker volume inspect "${_DK_NAMES[$_idx]}" 2>/dev/null
                                _dk_p '\n\033[1;33m[연결된 컨테이너]\033[0m\n'
                                docker ps -a --filter "volume=${_DK_NAMES[$_idx]}" --format '  {{.Names}} ({{.Status}})' 2>/dev/null
                                _dk_pause; _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            d)
                                [ -z "$_idx" ] && continue
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                read -p "볼륨 삭제 (${_DK_NAMES[$_idx]})? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    docker volume rm "${_DK_NAMES[$_idx]}" >/dev/null 2>&1 && _DK_MSG="✔ 볼륨 삭제 완료" || _DK_MSG="✖ 삭제 실패 (사용 중 볼륨)"
                                    _dk_load_summary; _dk_load_tab; _dk_build_view
                                fi
                                _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            x)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                read -p "미사용 볼륨을 모두 정리(docker volume prune)할까요? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    docker volume prune -f
                                    _DK_MSG="✔ 미사용 볼륨 정리 완료"
                                    _dk_load_summary; _dk_load_tab; _dk_build_view
                                    _dk_pause
                                fi
                                _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                        esac
                        ;;
                    5) # Networks
                        case "$_k" in
                            ""|i)
                                [ -z "$_idx" ] && continue
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _dk_p '\033[1;36m◈ 네트워크 상세: %s\033[0m\n' "${_DK_NAMES[$_idx]}"
                                docker network inspect --format 'Name   : {{.Name}}
Driver : {{.Driver}}  Scope: {{.Scope}}
Subnets: {{range .IPAM.Config}}{{.Subnet}} (GW={{.Gateway}}) {{end}}
Containers:
{{range $k, $v := .Containers}}  - {{$v.Name}} : {{$v.IPv4Address}}{{"\n"}}{{end}}' "${_DK_IDS[$_idx]}" 2>/dev/null
                                _dk_pause; _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            d)
                                [ -z "$_idx" ] && continue
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                read -p "네트워크 삭제 (${_DK_NAMES[$_idx]})? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    docker network rm "${_DK_IDS[$_idx]}" >/dev/null 2>&1 && _DK_MSG="✔ 네트워크 삭제 완료" || _DK_MSG="✖ 삭제 실패"
                                    _dk_load_summary; _dk_load_tab; _dk_build_view
                                fi
                                _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            x)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                read -p "미사용 네트워크 정리(docker network prune)할까요? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    docker network prune -f
                                    _DK_MSG="✔ 미사용 네트워크 정리 완료"
                                    _dk_load_summary; _dk_load_tab; _dk_build_view
                                    _dk_pause
                                fi
                                _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                        esac
                        ;;
                    6) # System & Stats
                        case "$_k" in
                            ""|t)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _dk_p '\033[1;36m◈ 실시간 Docker Stats (종료: Ctrl+C)\033[0m\n'
                                ( trap 'exit 0' INT; docker stats )
                                _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            i)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _dk_p '\033[1;36m◈ Docker 디스크 사용량 (docker system df -v)\033[0m\n'
                                docker system df -v 2>/dev/null | less -RX
                                _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            x)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _dk_p '\033[1;31m⚠ docker system prune (중지된 컨테이너·미사용 네트워크·dangling 이미지 정리)\033[0m\n'
                                read -p "실행할까요? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    docker system prune -f
                                    _DK_MSG="✔ system prune 완료"
                                    _dk_load_summary; _dk_load_tab; _dk_build_view
                                    _dk_pause
                                fi
                                _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            B)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                read -p "Docker 빌드 캐시 정리(docker builder prune -f)할까요? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    docker builder prune -f
                                    _DK_MSG="✔ builder prune 완료"
                                    _dk_pause
                                fi
                                _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            R)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                read -p "Docker 데몬을 재시작할까요? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null
                                    sleep 2
                                    _DK_MSG="✔ Docker 데몬 재시작 완료"
                                    _dk_load_summary; _dk_load_tab; _dk_build_view
                                fi
                                _DK_DIRTY=1; tput civis 2>/dev/null
                                ;;
                        esac
                        ;;
                esac
                ;;
        esac
    done

    tput cnorm 2>/dev/null
    stty sane 2>/dev/null
    [ -n "$_old_trap" ] && eval "$_old_trap" || trap - INT
    printf '\n'
}

# ==============================================================================
# 통합 Proxmox VM & CT 관리 TUI: pxms (Proxmox VM & CT Manager Studio)
# - Proxmox WebUI + proxmox vms manager 36개 메뉴를 방향키 + 엔터 + 원키로 통합 제어
# - 6개 탭: [1]VM&CT [2]Snapshots [3]Backups [4]Storage&ISO [5]Node&Tasks [6]Tools(36)
# - pvesh + jq 기반 클러스터/단일 노드 자동 호환 (qm/pct 자동 폴백)
# - Bash 3.x+ 및 EUC-KR/UTF-8 완벽 호환 (연관배열 미사용, 무깜빡임 델타 렌더링)
# ==============================================================================

_px_p() {
    local _fmt="$1"
    shift
    if [ "$_PX_ENC" = "euckr" ] && declare -f _dm_iconv_euckr >/dev/null 2>&1; then
        printf "$_fmt" "$@" | _dm_iconv_euckr | iconv -f UTF-8 -t EUC-KR//TRANSLIT 2>/dev/null || printf "$_fmt" "$@"
    else
        printf "$_fmt" "$@"
    fi
}

_px_pause() {
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
    _px_p '\n\033[1;33m[아무 키나 누르면 pxms 로 돌아갑니다...]\033[0m'
    IFS= read -rsn1 _ </dev/tty
}

_px_detect_env() {
    _PX_ENC="utf8"
    _PX_NODE=""
    _PX_PVE_VER="N/A"
    _PX_HAS_JQ=0
    _PX_HAS_PVESH=0
    _PX_RUN_BG='\033[42;1;37m'

    local _loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    case "$_loc" in
        *[Ee][Uu][Cc]*[Kk][Rr]*|*[Kk][Oo]_[Kk][Rr]|ko)
            command -v iconv >/dev/null 2>&1 && _PX_ENC="euckr" ;;
    esac

    case "${COLORTERM:-}" in
        truecolor|24bit) _PX_RUN_BG='\033[48;5;22;1;97m' ;;
        *)
            case "${TERM:-}" in
                *256color*|*truecolor*|*direct*|alacritty|kitty|xterm-kitty|wezterm|foot*)
                    _PX_RUN_BG='\033[48;5;22;1;97m' ;;
            esac
            ;;
    esac

    if ! command -v pvesh >/dev/null 2>&1 && ! command -v qm >/dev/null 2>&1 && ! command -v pct >/dev/null 2>&1; then
        _px_p '\033[1;31m[오류] Proxmox 명령(pvesh / qm / pct)을 찾을 수 없습니다.\033[0m\n'
        _px_p 'Proxmox VE 호스트 서버에서 실행해 주세요.\n'
        return 1
    fi

    command -v jq >/dev/null 2>&1 && _PX_HAS_JQ=1
    command -v pvesh >/dev/null 2>&1 && _PX_HAS_PVESH=1

    _PX_NODE=$(basename "$(readlink /etc/pve/local 2>/dev/null)" 2>/dev/null)
    [ -z "$_PX_NODE" ] && _PX_NODE=$(hostname -s 2>/dev/null || hostname 2>/dev/null)

    if command -v pveversion >/dev/null 2>&1; then
        _PX_PVE_VER=$(pveversion 2>/dev/null | awk -F/ '{print $2}' | awk '{print $1}')
    fi
    [ -z "$_PX_PVE_VER" ] && _PX_PVE_VER="PVE"
    return 0
}

_px_find_conf() {
    local _vmid="$1" _type="$2" _node="$3" _c=""
    if [ -n "$_node" ] && [ -n "$_type" ]; then
        if [ "$_type" = "qemu" ] && [ -f "/etc/pve/nodes/${_node}/qemu-server/${_vmid}.conf" ]; then
            echo "/etc/pve/nodes/${_node}/qemu-server/${_vmid}.conf"
            return 0
        elif [ "$_type" = "lxc" ] && [ -f "/etc/pve/nodes/${_node}/lxc/${_vmid}.conf" ]; then
            echo "/etc/pve/nodes/${_node}/lxc/${_vmid}.conf"
            return 0
        fi
    fi
    _c=$(find /etc/pve/nodes -maxdepth 3 -name "${_vmid}.conf" 2>/dev/null | head -n1)
    [ -n "$_c" ] && echo "$_c"
}

_px_pick_backup_storage() {
    local _st="" _list="" _cnt=0 _ans=""
    if command -v pvesm >/dev/null 2>&1; then
        _list=$(pvesm status --content backup 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}')
    fi
    if [ -z "$_list" ]; then
        echo "local"
        return 0
    fi
    _cnt=$(printf '%s\n' "$_list" | grep -c .)
    if [ "$_cnt" -le 1 ]; then
        printf '%s\n' "$_list" | head -n1
        return 0
    fi
    _px_p '\033[1;36m백업 스토리지 선택:\033[0m\n' >/dev/tty
    local _i=1 _s _arr=()
    while IFS= read -r _s; do
        [ -z "$_s" ] && continue
        _arr[$_i]="$_s"
        printf '  %d) %s\n' "$_i" "$_s" >/dev/tty
        _i=$((_i + 1))
    done < <(printf '%s\n' "$_list")
    read -p "번호 선택 [1]: " _ans </dev/tty
    [ -z "$_ans" ] && _ans=1
    _st="${_arr[$_ans]}"
    [ -z "$_st" ] && _st="${_arr[1]}"
    echo "${_st:-local}"
}

_px_load_summary() {
    _PX_CNT_RUN=0
    _PX_CNT_STOP=0
    _PX_CNT_VM=0
    _PX_CNT_CT=0
    _PX_LOAD=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "-")
    _PX_MEM_PCT=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{if(t>0 && a>=0) printf "%.0f%%", (t-a)*100/t; else print "-"}' /proc/meminfo 2>/dev/null)
    [ -z "$_PX_MEM_PCT" ] && _PX_MEM_PCT="-"

    local _t _st
    if [ "$_PX_HAS_PVESH" = "1" ] && [ "$_PX_HAS_JQ" = "1" ]; then
        while IFS='|' read -r _t _st; do
            [ -z "$_t" ] && continue
            [ "$_t" = "qemu" ] && _PX_CNT_VM=$((_PX_CNT_VM + 1))
            [ "$_t" = "lxc" ]  && _PX_CNT_CT=$((_PX_CNT_CT + 1))
            if [ "$_st" = "running" ]; then
                _PX_CNT_RUN=$((_PX_CNT_RUN + 1))
            else
                _PX_CNT_STOP=$((_PX_CNT_STOP + 1))
            fi
        done < <(pvesh get /cluster/resources -type vm --output-format json 2>/dev/null | jq -r '.[] | "\(.type // "")|\(.status // "")"' 2>/dev/null)
    else
        if command -v qm >/dev/null 2>&1; then
            while read -r _id _nm _st _; do
                case "$_id" in [0-9]*) ;; *) continue ;; esac
                _PX_CNT_VM=$((_PX_CNT_VM + 1))
                [ "$_st" = "running" ] && _PX_CNT_RUN=$((_PX_CNT_RUN + 1)) || _PX_CNT_STOP=$((_PX_CNT_STOP + 1))
            done < <(qm list 2>/dev/null)
        fi
        if command -v pct >/dev/null 2>&1; then
            while read -r _id _st _; do
                case "$_id" in [0-9]*) ;; *) continue ;; esac
                _PX_CNT_CT=$((_PX_CNT_CT + 1))
                [ "$_st" = "running" ] && _PX_CNT_RUN=$((_PX_CNT_RUN + 1)) || _PX_CNT_STOP=$((_PX_CNT_STOP + 1))
            done < <(pct list 2>/dev/null)
        fi
    fi
}

_px_load_tab() {
    _PX_IDS=()
    _PX_NAMES=()
    _PX_STATE=()
    _PX_COL2=()
    _PX_COL3=()
    _PX_META=()
    _PX_TOTAL=0

    local _c1 _c2 _c3 _c4 _c5 _c6 _c7 _c8 _f _vmid _type _node _sn _st _desc _tm _stg _line _tname _sz _fmt
    case "$_PX_TAB" in
        1) # VM & CT (QEMU + LXC unified)
            if [ "$_PX_HAS_PVESH" = "1" ] && [ "$_PX_HAS_JQ" = "1" ]; then
                while IFS='|' read -r _c1 _c2 _c3 _c4 _c5 _c6 _c7 _c8; do
                    [ -z "$_c1" ] && continue
                    # c1=vmid c2=type c3=name c4=status c5=node c6=cpu% c7=mem_str c8=lock
                    _PX_IDS[$_PX_TOTAL]="$_c1"
                    _PX_NAMES[$_PX_TOTAL]="${_c2}/${_c1} ${_c3}"
                    if [ -n "$_c8" ]; then
                        _PX_STATE[$_PX_TOTAL]="locked"
                        _PX_COL2[$_PX_TOTAL]="${_c4} [${_c8}]"
                    else
                        _PX_STATE[$_PX_TOTAL]="$_c4"
                        _PX_COL2[$_PX_TOTAL]="$_c4"
                    fi
                    if [ "$_c4" = "running" ]; then
                        _PX_COL3[$_PX_TOTAL]="CPU:${_c6}%  MEM:${_c7}  @${_c5}"
                    else
                        _PX_COL3[$_PX_TOTAL]="MEM:${_c7}  @${_c5}"
                    fi
                    _PX_META[$_PX_TOTAL]="${_c2}|${_c5}|${_c1}|${_c3}|${_c8}"
                    _PX_TOTAL=$((_PX_TOTAL + 1))
                done < <(pvesh get /cluster/resources -type vm --output-format json 2>/dev/null | jq -r '
                    sort_by(.vmid) | .[] |
                    (((.cpu // 0) * 100) | floor) as $cp |
                    (((.mem // 0) / 1073741824 * 10) | floor / 10) as $mu |
                    (((.maxmem // 0) / 1073741824 * 10) | floor / 10) as $mt |
                    "\(.vmid)|\(.type)|\(.name // "unknown")|\(.status // "unknown")|\(.node // "-")|\($cp)|\($mu)G/\($mt)G|\(.lock // "")"
                ' 2>/dev/null)
            fi
            # Fallback if pvesh/jq unavailable or empty
            if [ "$_PX_TOTAL" -eq 0 ]; then
                if command -v pct >/dev/null 2>&1; then
                    while read -r _c1 _c2 _c3 _c4; do
                        case "$_c1" in [0-9]*) ;; *) continue ;; esac
                        local _nm="${_c4:-$_c3}"
                        _PX_IDS[$_PX_TOTAL]="$_c1"
                        _PX_NAMES[$_PX_TOTAL]="lxc/${_c1} ${_nm}"
                        _PX_STATE[$_PX_TOTAL]="$_c2"
                        _PX_COL2[$_PX_TOTAL]="$_c2"
                        _PX_COL3[$_PX_TOTAL]="@${_PX_NODE}"
                        _PX_META[$_PX_TOTAL]="lxc|${_PX_NODE}|${_c1}|${_nm}|"
                        _PX_TOTAL=$((_PX_TOTAL + 1))
                    done < <(pct list 2>/dev/null)
                fi
                if command -v qm >/dev/null 2>&1; then
                    while read -r _c1 _c2 _c3 _c4 _c5 _; do
                        case "$_c1" in [0-9]*) ;; *) continue ;; esac
                        _PX_IDS[$_PX_TOTAL]="$_c1"
                        _PX_NAMES[$_PX_TOTAL]="qemu/${_c1} ${_c2}"
                        _PX_STATE[$_PX_TOTAL]="$_c3"
                        _PX_COL2[$_PX_TOTAL]="$_c3"
                        _PX_COL3[$_PX_TOTAL]="MEM:${_c4}M  DISK:${_c5}G  @${_PX_NODE}"
                        _PX_META[$_PX_TOTAL]="qemu|${_PX_NODE}|${_c1}|${_c2}|"
                        _PX_TOTAL=$((_PX_TOTAL + 1))
                    done < <(qm list 2>/dev/null)
                fi
            fi
            ;;

        2) # Snapshots (fast .conf scan across /etc/pve/nodes)
            while IFS='|' read -r _c1 _c2 _c3 _c4 _c5 _c6; do
                [ -z "$_c1" ] && continue
                # c1=type c2=node c3=vmid c4=snapname c5=snaptime c6=desc
                local _dt="-"
                if [ -n "$_c5" ] && [ "$_c5" != "0" ]; then
                    _dt=$(date -d "@${_c5}" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$_c5")
                fi
                _PX_IDS[$_PX_TOTAL]="$_c3"
                _PX_NAMES[$_PX_TOTAL]="${_c1}/${_c3}  ${_c4}"
                _PX_STATE[$_PX_TOTAL]="snap"
                _PX_COL2[$_PX_TOTAL]="$_dt"
                _PX_COL3[$_PX_TOTAL]="${_c6:-@${_c2}}"
                _PX_META[$_PX_TOTAL]="${_c1}|${_c2}|${_c3}|${_c4}"
                _PX_TOTAL=$((_PX_TOTAL + 1))
            done < <(
                for _f in /etc/pve/nodes/*/qemu-server/*.conf /etc/pve/nodes/*/lxc/*.conf; do
                    [ -f "$_f" ] || continue
                    _node=$(echo "$_f" | awk -F/ '{print $5}')
                    if echo "$_f" | grep -q '/qemu-server/'; then
                        _type="qemu"
                    else
                        _type="lxc"
                    fi
                    _vmid=$(basename "$_f" .conf)
                    awk -v t="$_type" -v n="$_node" -v id="$_vmid" '
                        /^\[.*\]$/ {
                            if (sn != "" && sn != "PENDING") printf "%s|%s|%s|%s|%s|%s\n", t, n, id, sn, tm, ds;
                            sn=$0; gsub(/^\[|\]$/, "", sn); tm=""; ds=""; next
                        }
                        sn != "" && /^snaptime:/ { sub(/^snaptime:[ \t]*/, ""); tm=$0; next }
                        sn != "" && /^description:/ { sub(/^description:[ \t]*/, ""); ds=$0; next }
                        END {
                            if (sn != "" && sn != "PENDING") printf "%s|%s|%s|%s|%s|%s\n", t, n, id, sn, tm, ds;
                        }
                    ' "$_f" 2>/dev/null
                done
            )
            ;;

        3) # Backups (vzdump archives across active backup storages)
            if command -v pvesm >/dev/null 2>&1; then
                while IFS= read -r _stg; do
                    [ -z "$_stg" ] && continue
                    while read -r _c1 _c2 _c3 _c4 _c5 _; do
                        [ -z "$_c1" ] && continue
                        case "$_c1" in Volid|volid|---*) continue ;; esac
                        # c1=volid c2=format c3=type c4=size(bytes) c5=vmid
                        local _fn="${_c1##*/}"
                        local _gb=""
                        if echo "$_c4" | grep -qE '^[0-9]+$'; then
                            _gb=$(awk -v b="$_c4" 'BEGIN { if (b>=1073741824) printf "%.2fG", b/1073741824; else printf "%.1fM", b/1048576 }')
                        else
                            _gb="$_c4"
                        fi
                        _PX_IDS[$_PX_TOTAL]="$_c1"
                        _PX_NAMES[$_PX_TOTAL]="$_fn"
                        _PX_STATE[$_PX_TOTAL]="backup"
                        _PX_COL2[$_PX_TOTAL]="VM:${_c5:-?}  ${_gb}"
                        _PX_COL3[$_PX_TOTAL]="${_stg} (${_c2})"
                        _PX_META[$_PX_TOTAL]="${_stg}|${_c5}|${_c1}|${_c2}"
                        _PX_TOTAL=$((_PX_TOTAL + 1))
                    done < <(pvesm list "$_stg" --content backup 2>/dev/null | sort -r)
                done < <(pvesm status --content backup 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}')
            fi
            ;;

        4) # Storage & ISO
            if command -v pvesm >/dev/null 2>&1; then
                while read -r _c1 _c2 _c3 _c4 _c5 _c6 _c7; do
                    [ -z "$_c1" ] && continue
                    case "$_c1" in Name|---*) continue ;; esac
                    local _u _t _a
                    _t=$(awk -v k="${_c4:-0}" 'BEGIN { printf "%.1fG", k/1048576 }')
                    _u=$(awk -v k="${_c5:-0}" 'BEGIN { printf "%.1fG", k/1048576 }')
                    _a=$(awk -v k="${_c6:-0}" 'BEGIN { printf "%.1fG", k/1048576 }')
                    _PX_IDS[$_PX_TOTAL]="$_c1"
                    _PX_NAMES[$_PX_TOTAL]="$_c1"
                    if [ "$_c3" = "active" ]; then
                        _PX_STATE[$_PX_TOTAL]="running"
                    else
                        _PX_STATE[$_PX_TOTAL]="stopped"
                    fi
                    _PX_COL2[$_PX_TOTAL]="${_c2}  ${_c7}"
                    _PX_COL3[$_PX_TOTAL]="Used:${_u}/${_t} (Avail:${_a})"
                    _PX_META[$_PX_TOTAL]="${_c2}|${_c3}"
                    _PX_TOTAL=$((_PX_TOTAL + 1))
                done < <(pvesm status 2>/dev/null)
            fi
            ;;

        5) # Node & Tasks
            if [ "$_PX_HAS_PVESH" = "1" ] && [ "$_PX_HAS_JQ" = "1" ]; then
                while IFS='|' read -r _c1 _c2 _c3 _c4 _c5 _c6; do
                    [ -z "$_c1" ] && continue
                    # c1=upid c2=type c3=id c4=status c5=starttime c6=user
                    local _dt=""
                    if echo "$_c5" | grep -qE '^[0-9]+$'; then
                        _dt=$(date -d "@${_c5}" "+%m-%d %H:%M:%S" 2>/dev/null || echo "$_c5")
                    else
                        _dt="$_c5"
                    fi
                    _PX_IDS[$_PX_TOTAL]="$_c1"
                    _PX_NAMES[$_PX_TOTAL]="${_c2} ${_c3}"
                    case "$_c4" in
                        OK)        _PX_STATE[$_PX_TOTAL]="running" ;;
                        ""|running*) _PX_STATE[$_PX_TOTAL]="locked" ;;
                        *)         _PX_STATE[$_PX_TOTAL]="stopped" ;;
                    esac
                    _PX_COL2[$_PX_TOTAL]="${_c4:-running}"
                    _PX_COL3[$_PX_TOTAL]="${_dt}  (${_c6})"
                    _PX_META[$_PX_TOTAL]="${_c1}|${_PX_NODE}"
                    _PX_TOTAL=$((_PX_TOTAL + 1))
                done < <(pvesh get "/nodes/${_PX_NODE}/tasks" --limit 40 --output-format json 2>/dev/null | jq -r '
                    .[] | "\(.upid // "")|\(.type // "-")|\(.id // "-")|\(.status // "running")|\(.starttime // "")|\(.user // "-")"
                ' 2>/dev/null)
            fi
            ;;

        6) # Tools & Menus (all 36 proxmox vms manager menus)
            while IFS='|' read -r _c1 _c2 _c3 _c4; do
                [ -z "$_c1" ] && continue
                _PX_IDS[$_PX_TOTAL]="$_c1"
                _PX_NAMES[$_PX_TOTAL]="[${_c1}] ${_c2}"
                _PX_STATE[$_PX_TOTAL]="tool"
                _PX_COL2[$_PX_TOTAL]="$_c3"
                _PX_COL3[$_PX_TOTAL]="$_c4"
                _PX_META[$_PX_TOTAL]="$_c1"
                _PX_TOTAL=$((_PX_TOTAL + 1))
            done <<'EOF'
px|manage vms|[VM/제어]|LXC/KVM 목록·시작·중지·재부팅 기본 관리
pxx|start stop enter vm|[VM/제어]|빠른 VM/CT 제어 및 진입 (vm 함수)
pxm|monitoring vms|[모니터링]|VM/CT 리소스 실시간 모니터링
pxs|storage|[스토리지]|LVM/Thin/ZFS/디렉터리 스토리지 관리
pxc|cluster/node|[클러스터]|클러스터 상태·노드·corosync 관리
pxmerge|cluster merge / vmid remap|[클러스터]|클러스터 병합 및 VMID 중복 리매핑
node|node reset|[클러스터]|클러스터 노드 탈퇴·초기화 (주의)
iso|iso/lxc download|[스토리지]|ISO 이미지 및 LXC 템플릿 다운로드
pvssl|webui ssl-cert set|[보안/인증]|Proxmox WebUI SSL 인증서 설정
pxdump|backup vms|[백업/복구]|vzdump 스냅샷 백업 도구 모음
pxl|log / fail2ban|[모니터링]|PVE 시스템 로그 및 Fail2ban 차단 관리
snap|snapshot|[백업/복구]|VM/CT 스냅샷 생성·목록·롤백·삭제
pxg|gpu intel 1 - passthrough|[GPU패스스루]|Intel GPU 패스스루 1단계
pxgg|gpu intel 2 - SR-IOV|[GPU패스스루]|Intel i915 SR-IOV DKMS 설정
pxggg|gpu intel 3 - grub|[GPU패스스루]|Intel GPU 패스스루 GRUB 커널 옵션
pxga|gpu amd passthrough|[GPU패스스루]|AMD GPU 패스스루 설정
pxup|upgrade && noti-push|[유지보수]|PVE 업그레이드 및 푸시 알림
pxh|helper script|[유지보수]|Proxmox Helper Scripts 원클릭 실행
pbs|vm - backup server|[VM/템플릿]|Proxmox Backup Server(PBS) 구축
win11|vm - win11|[VM/템플릿]|Windows 11 VM 구축 가이드
bliss|vm - blissos Android|[VM/템플릿]|BlissOS 안드로이드 VM 구축
gphoto|vm - google photo backup|[VM/템플릿]|BlissOS 구글포토 무제한 백업 설정
nas|vm - xpenology nas|[VM/템플릿]|Xpenology 시놀로지 NAS VM 구축
opn|vm - opnsense firewall|[VM/템플릿]|OPNsense 방화벽 VM 구축
ubun|vm - ubuntu desktop/etc|[VM/템플릿]|Ubuntu Desktop 등 범용 VM 구축
pxci|host - cloud init generic|[Cloud-Init]|범용 Cloud-Init VM 템플릿 생성
pxcc|host - cloud init custom|[Cloud-Init]|기존 VM을 Cloud-Init 템플릿으로 변환
pxb|host - backup/restore/vnc|[백업/복구]|호스트 백업·복원·VNC 설정 모음
pxr|host - recover deleted vm|[백업/복구]|삭제된 VM/디스크 긴급 복구
pxt|host - tailscale vpn|[네트워크]|Tailscale VPN 서버 구축
pxd|host - dhcp server|[네트워크]|호스트 DHCP 서버 설정
ovs|host - open-vswitch|[네트워크]|Open vSwitch 가상 스위치 설정
mig|vmware(vmdk) migration|[마이그레이션]|VMware VMDK -> Proxmox 변환 이전
pxwg|emergency vm tunnel/switch|[네트워크/비상]|비상 VM 터널 및 트래픽 전환
pve_ip|host ip switch & net check|[네트워크/비상]|공인/사설/DHCP/USB IP 전환 및 점검
idc_ip|IDC 무작정 아이피 잡기|[네트워크/비상]|IDC 자동 대역 탐색·충돌감지·핑
EOF
            ;;
    esac
}

_px_build_view() {
    _PX_VIEW=()
    _PX_VCNT=0
    local _i _q _hay
    _q=$(printf '%s' "$_PX_SEARCH" | tr '[:upper:]' '[:lower:]')
    _i=0
    while [ "$_i" -lt "$_PX_TOTAL" ]; do
        if [ -z "$_q" ]; then
            _PX_VIEW[$_PX_VCNT]="$_i"
            _PX_VCNT=$((_PX_VCNT + 1))
        else
            _hay=$(printf '%s %s %s %s' "${_PX_NAMES[$_i]}" "${_PX_COL2[$_i]}" "${_PX_COL3[$_i]}" "${_PX_META[$_i]}" | tr '[:upper:]' '[:lower:]')
            case "$_hay" in
                *"$_q"*)
                    _PX_VIEW[$_PX_VCNT]="$_i"
                    _PX_VCNT=$((_PX_VCNT + 1))
                    ;;
            esac
        fi
        _i=$((_i + 1))
    done
    [ "$_PX_CUR" -ge "$_PX_VCNT" ] && _PX_CUR=$((_PX_VCNT > 0 ? _PX_VCNT - 1 : 0))
    [ "$_PX_CUR" -lt 0 ] && _PX_CUR=0
    [ "$_PX_TOP" -gt "$_PX_CUR" ] && _PX_TOP="$_PX_CUR"
}

_px_render_row() {
    local _vidx="$1" _is_cur="$2"
    local _idx="${_PX_VIEW[$_vidx]}"
    local _st="${_PX_STATE[$_idx]}"
    local _nm="${_PX_NAMES[$_idx]}"
    local _c2="${_PX_COL2[$_idx]}"
    local _c3="${_PX_COL3[$_idx]}"
    local _mark=" " _bg="" _rst='\033[0m' _ico _iclr _gap=" "

    if [ "$_PX_ENC" = "euckr" ]; then
        _gap="  "
        case "$_st" in
            running) _ico="●"; _iclr='\033[1;32m'; _bg="$_PX_RUN_BG" ;;
            locked)  _ico="◐"; _iclr='\033[1;33m'; _bg='\033[1;33m' ;;
            snap)    _ico="◈"; _iclr='\033[1;35m' ;;
            backup)  _ico="◆"; _iclr='\033[1;36m' ;;
            tool)    _ico="▸"; _iclr='\033[1;36m' ;;
            *)       _ico="○"; _iclr='\033[0;37m'; _bg='\033[0;37m' ;;
        esac
    else
        case "$_st" in
            running) _ico="🟢"; _iclr='\033[1;32m'; _bg="$_PX_RUN_BG" ;;
            locked)  _ico="🔒"; _iclr='\033[1;33m'; _bg='\033[1;33m' ;;
            snap)    _ico="📸"; _iclr='\033[1;35m' ;;
            backup)  _ico="💾"; _iclr='\033[1;36m' ;;
            tool)    _ico="🔧"; _iclr='\033[1;36m' ;;
            *)       _ico="⚫"; _iclr='\033[0;37m'; _bg='\033[0;37m' ;;
        esac
    fi

    if [ "$_is_cur" = "1" ]; then
        _mark="▶"
        if [ "$_st" = "running" ]; then
            _bg='\033[44;1;92m'
            _iclr='\033[44;1;92m'
        else
            _bg='\033[44;1;37m'
            _iclr='\033[44;1;33m'
        fi
    fi

    [ "${#_nm}" -gt 30 ] && _nm="${_nm:0:29}~"
    [ "${#_c2}" -gt 20 ] && _c2="${_c2:0:19}~"
    local _c3_max=$((_PX_COLS - 60))
    [ "$_c3_max" -lt 16 ] && _c3_max=16
    [ "${#_c3}" -gt "$_c3_max" ] && _c3="${_c3:0:$((_c3_max - 1))}~"

    _px_p "${_bg} %s %s${_gap}%-30s  %-20s  %s\033[K${_rst}" "$_mark" "$_ico" "$_nm" "$_c2" "$_c3"
}

_px_render_full() {
    _PX_LINES=$(tput lines 2>/dev/null || echo 24)
    _PX_COLS=$(tput cols 2>/dev/null || echo 100)
    [ "$_PX_LINES" -lt 16 ] && _PX_LINES=16
    [ "$_PX_COLS" -lt 70 ] && _PX_COLS=70
    _PX_PAGE=$((_PX_LINES - 9))
    [ "$_PX_PAGE" -lt 5 ] && _PX_PAGE=5

    if [ "$_PX_CUR" -lt "$_PX_TOP" ]; then
        _PX_TOP="$_PX_CUR"
    elif [ "$_PX_CUR" -ge $((_PX_TOP + _PX_PAGE)) ]; then
        _PX_TOP=$((_PX_CUR - _PX_PAGE + 1))
    fi

    printf '\033[H'
    # Line 1: Header
    _px_p '\033[1;36m◈ Proxmox VM & CT Studio [pxms]\033[0m  \033[1;37m%s\033[0m  PVE:%s  \033[1;32mRun:%s\033[0m/\033[1;31mStop:%s\033[0m  VM:%s CT:%s  Load:%s MEM:%s\033[K\n' \
        "$_PX_NODE" "$_PX_PVE_VER" "$_PX_CNT_RUN" "$_PX_CNT_STOP" "$_PX_CNT_VM" "$_PX_CNT_CT" "$_PX_LOAD" "$_PX_MEM_PCT"

    # Line 2: Tab Bar
    local _t _tlbl _tbar=""
    for _t in 1 2 3 4 5 6; do
        case "$_t" in
            1) _tlbl="1:VM&CT" ;;
            2) _tlbl="2:Snapshots" ;;
            3) _tlbl="3:Backups" ;;
            4) _tlbl="4:Storage&ISO" ;;
            5) _tlbl="5:Node&Tasks" ;;
            6) _tlbl="6:Tools(36)" ;;
        esac
        if [ "$_t" = "$_PX_TAB" ]; then
            _tbar="${_tbar}\033[46;1;30m [${_tlbl}] \033[0m "
        else
            _tbar="${_tbar}\033[0;37m ${_tlbl} \033[0m "
        fi
    done
    _px_p "${_tbar}\033[K\n"

    # Line 3: Divider + Search / Loading status
    if [ "${_PX_LOADING:-0}" = "1" ]; then
        _px_p '\033[0;36m──────\033[0m \033[1;33m(데이터 불러오는 중...)\033[0m \033[0;36m────────────────────────────────────────────────\033[0m\033[K\n'
    elif [ -n "$_PX_SEARCH" ]; then
        _px_p '\033[0;36m──────\033[0m \033[1;33m[검색: %s (%d건)]\033[0m \033[0;36m──────────────────────────────────────────\033[0m\033[K\n' "$_PX_SEARCH" "$_PX_VCNT"
    else
        _px_p '\033[0;36m──────\033[0m \033[1;37m(%d건)\033[0m \033[0;36m────────────────────────────────────────────────────────\033[0m\033[K\n' "$_PX_VCNT"
    fi

    # Line 4: Column Header
    case "$_PX_TAB" in
        1) _px_p '\033[1;37m      %-30s  %-20s  %s\033[0m\033[K\n' "TYPE/ID NAME" "STATUS" "RESOURCES / NODE" ;;
        2) _px_p '\033[1;37m      %-30s  %-20s  %s\033[0m\033[K\n' "TYPE/ID  SNAPSHOT" "CREATED" "DESCRIPTION" ;;
        3) _px_p '\033[1;37m      %-30s  %-20s  %s\033[0m\033[K\n' "BACKUP ARCHIVE" "VMID / SIZE" "STORAGE (FMT)" ;;
        4) _px_p '\033[1;37m      %-30s  %-20s  %s\033[0m\033[K\n' "STORAGE NAME" "TYPE / USE%" "CAPACITY" ;;
        5) _px_p '\033[1;37m      %-30s  %-20s  %s\033[0m\033[K\n' "TASK TYPE / TARGET" "STATUS" "START TIME (USER)" ;;
        6) _px_p '\033[1;37m      %-30s  %-20s  %s\033[0m\033[K\n' "[KEY] MENU NAME" "CATEGORY" "DESCRIPTION" ;;
    esac

    # Lines 5..(5+PAGE-1): List rows
    local _r=0 _v
    while [ "$_r" -lt "$_PX_PAGE" ]; do
        _v=$((_PX_TOP + _r))
        if [ "$_v" -lt "$_PX_VCNT" ]; then
            if [ "$_v" -eq "$_PX_CUR" ]; then
                _px_render_row "$_v" 1
            else
                _px_render_row "$_v" 0
            fi
            printf '\n'
        else
            if [ "$_r" -eq 0 ] && [ "${_PX_LOADING:-0}" = "1" ]; then
                if [ "$_PX_TAB" = "3" ]; then
                    if [ "$_PX_ENC" = "euckr" ]; then
                        _px_p '   \033[1;33m... 백업 스토리지 목록(pvesm list)을 불러오는 중입니다. 잠시만 기다려 주세요.\033[0m\033[K\n'
                    else
                        _px_p '   \033[1;33m⏳ 백업 스토리지 목록(pvesm list)을 불러오는 중입니다... 잠시만 기다려 주세요.\033[0m\033[K\n'
                    fi
                else
                    if [ "$_PX_ENC" = "euckr" ]; then
                        _px_p '   \033[1;33m... 데이터를 불러오는 중입니다. 잠시만 기다려 주세요.\033[0m\033[K\n'
                    else
                        _px_p '   \033[1;33m⏳ 데이터를 불러오는 중입니다... 잠시만 기다려 주세요.\033[0m\033[K\n'
                    fi
                fi
            elif [ "$_r" -eq 0 ] && [ "$_PX_VCNT" -eq 0 ]; then
                _px_p '   \033[0;33m(표시할 항목이 없습니다. Tab/1~6 으로 다른 탭을 보거나 r 로 새로고침)\033[0m\033[K\n'
            else
                printf '\033[K\n'
            fi
        fi
        _r=$((_r + 1))
    done

    # Footer: Tab-specific hotkeys
    _px_p '\033[0;36m──────────────────────────────────────────────────────────────────────\033[0m\033[K\n'
    case "$_PX_TAB" in
        1) _px_p '\033[1;33m[Enter]\033[0m메뉴 \033[1;32m[s]\033[0mStart/Stop \033[1;36m[R]\033[0m재부팅 \033[1;37m[e]\033[0m진입 \033[1;36m[i]\033[0m상세 \033[1;33m[c]\033[0mConf \033[1;35m[S]\033[0m스냅샷 \033[1;32m[b]\033[0m백업 \033[1;33m[u]\033[0m언락 \033[1;31m[d]\033[0m삭제\033[K\n' ;;
        2) _px_p '\033[1;33m[Enter/i]\033[0m스냅샷목록 \033[1;32m[n]\033[0m새스냅샷 \033[1;35m[B]\033[0m롤백(Rollback) \033[1;31m[d]\033[0m스냅샷삭제\033[K\n' ;;
        3) _px_p '\033[1;33m[Enter/i]\033[0m상세 \033[1;32m[b]\033[0mVM백업 \033[1;36m[A]\033[0m실행중전체백업 \033[1;35m[R]\033[0m복원(Restore) \033[1;31m[d]\033[0m삭제\033[K\n' ;;
        4) _px_p '\033[1;33m[Enter/i]\033[0m내부파일(pvesm list) \033[1;36m[l]\033[0mLVM/Thin(lvs) \033[1;32m[I]\033[0mISO/템플릿(pveam) \033[1;35m[z]\033[0mZFS상태\033[K\n' ;;
        5) _px_p '\033[1;33m[Enter/i]\033[0mTask로그 \033[1;36m[c]\033[0m클러스터(pvecm) \033[1;32m[t]\033[0m실시간모니터 \033[1;35m[l]\033[0mPVE/fail2ban로그 \033[1;31m[S]\033[0m서비스재시작\033[K\n' ;;
        6) _px_p '\033[1;33m[Enter]\033[0m선택한 Proxmox 고급 메뉴 실행 (종료 후 pxms 자동 복귀)  \033[1;36m[/]\033[0m키워드검색\033[K\n' ;;
    esac
    _px_p '\033[0;37m[↑↓]이동 [←→/Tab/1-6]탭전환 [/]검색 [r]새로고침 [?]도움말 [q]종료\033[0m\033[K\n'
    _px_p '\033[1;32m%s\033[0m\033[K' "${_PX_MSG:-}"
    _PX_DIRTY=0
    _PX_PREV_CUR="$_PX_CUR"
    _PX_PREV_TOP="$_PX_TOP"
}

_px_render_delta() {
    if [ "$_PX_DIRTY" = "1" ] || [ "$_PX_TOP" -ne "$_PX_PREV_TOP" ] || [ "$_PX_CUR" -lt "$_PX_TOP" ] || [ "$_PX_CUR" -ge $((_PX_TOP + _PX_PAGE)) ]; then
        _px_render_full
        return
    fi
    if [ "$_PX_PREV_CUR" -ne "$_PX_CUR" ]; then
        local _r1=$((5 + _PX_PREV_CUR - _PX_TOP))
        local _r2=$((5 + _PX_CUR - _PX_TOP))
        printf '\033[%d;1H' "$_r1"
        _px_render_row "$_PX_PREV_CUR" 0
        printf '\033[%d;1H' "$_r2"
        _px_render_row "$_PX_CUR" 1
        _PX_PREV_CUR="$_PX_CUR"
    fi
}

_px_load_tab_async() {
    _PX_IDS=()
    _PX_NAMES=()
    _PX_STATE=()
    _PX_COL2=()
    _PX_COL3=()
    _PX_META=()
    _PX_TOTAL=0
    _PX_VIEW=()
    _PX_VCNT=0
    if [ "$_PX_TAB" != "6" ]; then
        _PX_LOADING=1
        if [ "$_PX_ENC" = "euckr" ]; then
            _PX_MSG="... 데이터 불러오는 중"
        else
            _PX_MSG="⏳ 데이터 불러오는 중..."
        fi
        _PX_DIRTY=1
        _px_render_full
    fi
    _px_load_tab
    _PX_LOADING=0
    _px_build_view
    _PX_MSG=""
    _PX_DIRTY=1
}

_px_show_help() {
    tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
    _px_p '\033[1;36m◈ 통합 Proxmox VM & CT 관리 TUI [pxms] 단축키 도움말\033[0m\n\n'
    _px_p '  \033[1;37m[공통 이동/탭]\033[0m\n'
    _px_p '    ↑/↓, j/k       : 항목 이동 (PgUp/PgDn 페이지, Home/End 처음/끝)\n'
    _px_p '    ←/→, Tab, 1~6  : 6개 탭 즉시 전환 (VM&CT/Snapshots/Backups/Storage/Node/Tools)\n'
    _px_p '    /              : 현재 탭 키워드 필터 검색 (빈 값 Enter 또는 Esc = 초기화)\n'
    _px_p '    r              : 데이터 새로고침   |   q : 종료\n\n'
    _px_p '  \033[1;37m[Tab 1: VM & CT (QEMU + LXC 통합)]\033[0m\n'
    _px_p '    Enter : 종합 액션 메뉴 (Start/Stop/HardStop/Reboot/Enter/Config/Snap/Backup/Clone/Destroy)\n'
    _px_p '    s : Start/Shutdown 토글 | R : 재부팅 | e : 쉘진입(pct enter / qssh / qm terminal)\n'
    _px_p '    i : 상세정보+IP+LVM디스크 | c : .conf vi2 편집 | S : 빠른스냅샷 | b : 빠른백업 | u : 언락 | d : 삭제\n\n'
    _px_p '  \033[1;37m[Tab 2~5: Snapshots / Backups / Storage&ISO / Node&Tasks]\033[0m\n'
    _px_p '    Tab 2 : n 새스냅샷 | B 롤백 | d 삭제\n'
    _px_p '    Tab 3 : b 선택VM백업 | A 실행중전체백업 | R 복원(qmrestore/pct restore) | d 삭제\n'
    _px_p '    Tab 4 : Enter/i 스토리지내부목록 | l LVM(lvs) | I ISO/템플릿(pveam) | z ZFS상태\n'
    _px_p '    Tab 5 : Enter/i Task상세로그 | c 클러스터(pvecm) | t 실시간모니터 | l PVE/fail2ban로그 | S 서비스재시작\n\n'
    _px_p '  \033[1;37m[Tab 6: Tools (36개 Proxmox 고급 메뉴 전체 런처)]\033[0m\n'
    _px_p '    / 로 키워드 검색 후 Enter 로 즉시 실행 (종료 시 pxms 로 자동 복귀)\n'
    _px_pause
}

_px_vm_inspect() {
    local _type="$1" _node="$2" _vmid="$3" _nm="$4"
    tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
    _px_p '\033[1;36m◈ %s/%s (%s) @%s 상세 정보\033[0m\n' "$_type" "$_vmid" "$_nm" "$_node"
    _px_p '──────────────────────────────────────────────────────────────────────\n'
    if [ "$_PX_HAS_PVESH" = "1" ]; then
        pvesh get "/nodes/${_node}/${_type}/${_vmid}/status/current" --noborder 2>/dev/null
    elif [ "$_type" = "qemu" ]; then
        qm status "$_vmid" --verbose 2>/dev/null
    else
        pct status "$_vmid" --verbose 2>/dev/null
    fi
    _px_p '\n\033[1;33m[네트워크 / IP]\033[0m\n'
    if declare -f vmip >/dev/null 2>&1; then
        vmip "$_vmid" 2>/dev/null
    elif [ "$_type" = "lxc" ]; then
        pct exec "$_vmid" -- ip -4 -br addr 2>/dev/null
    else
        qm guest cmd "$_vmid" network-get-interfaces 2>/dev/null | head -n 30
    fi
    _px_p '\n\033[1;33m[LVM 디스크 볼륨]\033[0m\n'
    lvs --noheadings --units g -o lv_name,lv_size,data_percent 2>/dev/null | awk -v id="vm-${_vmid}-" '$1 ~ "^"id {printf "  %-28s Size:%-8s Used:%s%%\n", $1, $2, $3}'
    _px_p '\n\033[1;33m[설정 요약 (.conf)]\033[0m\n'
    local _conf
    _conf=$(_px_find_conf "$_vmid" "$_type" "$_node")
    if [ -n "$_conf" ] && [ -f "$_conf" ]; then
        grep -E '^(name|hostname|cores|sockets|memory|balloon|ostype|onboot|boot|net[0-9]|scsi[0-9]|virtio[0-9]|rootfs|mp[0-9]|hostpci|lock):' "$_conf" 2>/dev/null | head -n 25
    fi
    _px_pause
}

_px_vm_action() {
    local _act="$1" _idx="$2"
    local _meta="${_PX_META[$_idx]}"
    local _type _node _vmid _nm _lock _st _ans _conf _sn _desc _stg _newid _newnm _path _out
    IFS='|' read -r _type _node _vmid _nm _lock < <(printf '%s\n' "$_meta")
    _st="${_PX_STATE[$_idx]}"
    _path="/nodes/${_node}/${_type}/${_vmid}"

    case "$_act" in
        menu)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _px_p '\033[1;36m◈ VM/CT 종합 액션: %s/%s (%s) [%s] @%s\033[0m\n' "$_type" "$_vmid" "$_nm" "$_st" "$_node"
            _px_p '──────────────────────────────────────────────────────────────────────\n'
            _px_p '   1) Start / Shutdown(정상종료) 토글\n'
            _px_p '   2) 강제 중지 (Hard Stop)\n'
            _px_p '   3) 재부팅 (Reboot)\n'
            _px_p '   4) 쉘 진입 (LXC: pct enter / VM: qssh 또는 qm terminal)\n'
            _px_p '   5) 상세 정보 + IP + LVM 디스크 + 설정 요약\n'
            _px_p '   6) 설정 파일(.conf) 편집 (vi2)\n'
            _px_p '   7) 빠른 스냅샷 생성 (snapshot)\n'
            _px_p '   8) 즉시 백업 실행 (vzdump zstd)\n'
            _px_p '   9) 복제 (Clone -> 새 VMID)\n'
            _px_p '  10) 락 해제 (unlock)\n'
            _px_p '  11) VM/CT 영구 삭제 (destroy)\n'
            _px_p '   0) 취소\n'
            read -p "선택 [0-11]: " _ans </dev/tty
            case "$_ans" in
                1)  _px_vm_action toggle "$_idx" ;;
                2)  _px_vm_action hardstop "$_idx" ;;
                3)  _px_vm_action reboot "$_idx" ;;
                4)  _px_vm_action enter "$_idx" ;;
                5)  _px_vm_inspect "$_type" "$_node" "$_vmid" "$_nm" ;;
                6)  _px_vm_action edit_conf "$_idx" ;;
                7)  _px_vm_action snapshot "$_idx" ;;
                8)  _px_vm_action backup "$_idx" ;;
                9)  _px_vm_action clone "$_idx" ;;
                10) _px_vm_action unlock "$_idx" ;;
                11) _px_vm_action destroy "$_idx" ;;
            esac
            return
            ;;

        toggle)
            if [ "$_st" = "running" ]; then
                if [ "$_PX_HAS_PVESH" = "1" ]; then
                    _out=$(pvesh create "${_path}/status/shutdown" 2>&1)
                elif [ "$_type" = "qemu" ]; then
                    _out=$(qm shutdown "$_vmid" 2>&1)
                else
                    _out=$(pct shutdown "$_vmid" 2>&1)
                fi
                if [ $? -eq 0 ]; then
                    _PX_MSG="✔ 정상 종료(shutdown) 요청: ${_type}/${_vmid} (${_nm})"
                else
                    _PX_MSG="✖ 종료 실패: ${_out}"
                fi
            else
                if [ "$_PX_HAS_PVESH" = "1" ]; then
                    _out=$(pvesh create "${_path}/status/start" 2>&1)
                elif [ "$_type" = "qemu" ]; then
                    _out=$(qm start "$_vmid" 2>&1)
                else
                    _out=$(pct start "$_vmid" 2>&1)
                fi
                if [ $? -eq 0 ]; then
                    _PX_MSG="✔ 시작(start) 요청 완료: ${_type}/${_vmid} (${_nm})"
                else
                    _PX_MSG="✖ 시작 실패: ${_out}"
                fi
            fi
            sleep 1
            _px_load_summary; _px_load_tab; _px_build_view
            ;;

        hardstop)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _px_p '\033[1;31m⚠ 강제 중지 (Hard Stop): %s/%s (%s)\033[0m\n' "$_type" "$_vmid" "$_nm"
            read -p "정말 강제 중지할까요? [y/N]: " _ans </dev/tty
            if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                if [ "$_PX_HAS_PVESH" = "1" ]; then
                    pvesh create "${_path}/status/stop" >/dev/null 2>&1 && _PX_MSG="✔ 강제 중지 완료: ${_vmid}" || _PX_MSG="✖ 강제 중지 실패: ${_vmid}"
                elif [ "$_type" = "qemu" ]; then
                    qm stop "$_vmid" >/dev/null 2>&1 && _PX_MSG="✔ 강제 중지 완료: ${_vmid}" || _PX_MSG="✖ 강제 중지 실패: ${_vmid}"
                else
                    pct stop "$_vmid" >/dev/null 2>&1 && _PX_MSG="✔ 강제 중지 완료: ${_vmid}" || _PX_MSG="✖ 강제 중지 실패: ${_vmid}"
                fi
                sleep 1
                _px_load_summary; _px_load_tab; _px_build_view
            fi
            ;;

        reboot)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _px_p '\033[1;36m◈ 재부팅 확인: %s/%s (%s)\033[0m\n' "$_type" "$_vmid" "$_nm"
            read -p "재부팅할까요? [y/N]: " _ans </dev/tty
            if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                if [ "$_PX_HAS_PVESH" = "1" ]; then
                    pvesh create "${_path}/status/reboot" >/dev/null 2>&1 && _PX_MSG="✔ 재부팅 요청: ${_vmid}" || _PX_MSG="✖ 재부팅 실패: ${_vmid}"
                elif [ "$_type" = "qemu" ]; then
                    qm reboot "$_vmid" >/dev/null 2>&1 && _PX_MSG="✔ 재부팅 요청: ${_vmid}" || _PX_MSG="✖ 재부팅 실패: ${_vmid}"
                else
                    pct reboot "$_vmid" >/dev/null 2>&1 && _PX_MSG="✔ 재부팅 요청: ${_vmid}" || _PX_MSG="✖ 재부팅 실패: ${_vmid}"
                fi
                sleep 1
                _px_load_summary; _px_load_tab; _px_build_view
            fi
            ;;

        enter)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _px_p '\033[1;36m◈ 쉘 진입: %s/%s (%s) @%s (종료: exit 또는 Ctrl+O)\033[0m\n' "$_type" "$_vmid" "$_nm" "$_node"
            if [ "$_st" != "running" ]; then
                read -p "현재 중지 상태입니다. 먼저 시작하고 진입할까요? [Y/n]: " _ans </dev/tty
                if printf '%s' "$_ans" | grep -qE '^[Nn]$'; then
                    return
                fi
                if [ "$_PX_HAS_PVESH" = "1" ]; then
                    pvesh create "${_path}/status/start"
                elif [ "$_type" = "qemu" ]; then
                    qm start "$_vmid"
                else
                    pct start "$_vmid"
                fi
                sleep 3
            fi
            if [ "$_type" = "lxc" ]; then
                if [ "$_node" = "$_PX_NODE" ]; then
                    pct enter "$_vmid"
                else
                    ssh -t "$_node" "pct enter ${_vmid}"
                fi
            else
                _px_p '  1) SSH 접속 (qssh %s root)\n  2) 시리얼 콘솔 (qm terminal %s)\n  0) 취소\n' "$_vmid" "$_vmid"
                read -p "진입 방식 선택 [1]: " _ans </dev/tty
                case "$_ans" in
                    0) return ;;
                    2)
                        if [ "$_node" = "$_PX_NODE" ]; then
                            qm terminal "$_vmid"
                        else
                            ssh -t "$_node" "qm terminal ${_vmid}"
                        fi
                        ;;
                    *)
                        if declare -f qssh >/dev/null 2>&1; then
                            qssh "$_vmid" root
                        else
                            _px_p '\033[1;33mqssh 함수를 찾을 수 없어 qm terminal 로 전환합니다.\033[0m\n'
                            qm terminal "$_vmid"
                        fi
                        ;;
                esac
            fi
            _PX_MSG="✔ 쉘 세션 종료: ${_type}/${_vmid} (${_nm})"
            _px_load_summary; _px_load_tab; _px_build_view
            ;;

        inspect)
            _px_vm_inspect "$_type" "$_node" "$_vmid" "$_nm"
            ;;

        edit_conf)
            _conf=$(_px_find_conf "$_vmid" "$_type" "$_node")
            if [ -n "$_conf" ] && [ -f "$_conf" ]; then
                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                if declare -f vi2 >/dev/null 2>&1; then
                    vi2 "$_conf"
                else
                    vi "$_conf"
                fi
                _PX_MSG="✔ 설정 편집 완료: ${_conf}"
                _px_load_summary; _px_load_tab; _px_build_view
            else
                _PX_MSG="✖ 설정 파일을 찾을 수 없음: ${_vmid}.conf"
            fi
            ;;

        snapshot)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            local _def_sn="at_$(date '+%Y%m%d_%H%M%S')"
            _px_p '\033[1;35m◈ 스냅샷 생성: %s/%s (%s)\033[0m\n' "$_type" "$_vmid" "$_nm"
            read -p "스냅샷 이름 [기본: ${_def_sn}]: " _sn </dev/tty
            [ -z "$_sn" ] && _sn="$_def_sn"
            read -p "설명 (선택): " _desc </dev/tty
            [ -z "$_desc" ] && _desc="Created by pxms"
            if [ "$_type" = "qemu" ]; then
                qm snapshot "$_vmid" "$_sn" --description "$_desc" && _PX_MSG="✔ 스냅샷 생성: ${_vmid}@${_sn}" || _PX_MSG="✖ 스냅샷 실패: ${_vmid}"
            else
                pct snapshot "$_vmid" "$_sn" --description "$_desc" && _PX_MSG="✔ 스냅샷 생성: ${_vmid}@${_sn}" || _PX_MSG="✖ 스냅샷 실패: ${_vmid}"
            fi
            _px_pause
            ;;

        backup)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _px_p '\033[1;32m◈ 즉시 스냅샷 백업 (vzdump): %s/%s (%s)\033[0m\n' "$_type" "$_vmid" "$_nm"
            _stg=$(_px_pick_backup_storage)
            _px_p '대상 스토리지: \033[1;36m%s\033[0m (mode=snapshot, compress=zstd)\n' "$_stg"
            read -p "백업을 시작할까요? [Y/n]: " _ans </dev/tty
            if ! printf '%s' "$_ans" | grep -qE '^[Nn]$'; then
                vzdump "$_vmid" --mode snapshot --storage "$_stg" --compress zstd --notes-template "{{guestname}}" --remove 0 \
                    && _PX_MSG="✔ 백업 완료: ${_vmid} -> ${_stg}" || _PX_MSG="✖ 백업 실패: ${_vmid}"
                _px_pause
            fi
            ;;

        clone)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _px_p '\033[1;36m◈ VM/CT 복제 (Clone): %s/%s (%s)\033[0m\n' "$_type" "$_vmid" "$_nm"
            read -p "새 VMID 입력 (취소=빈값): " _newid </dev/tty
            [ -z "$_newid" ] && return
            read -p "새 이름/호스트명 [기본: ${_nm}-clone]: " _newnm </dev/tty
            [ -z "$_newnm" ] && _newnm="${_nm}-clone"
            if [ "$_type" = "qemu" ]; then
                qm clone "$_vmid" "$_newid" --name "$_newnm" --full 1 && _PX_MSG="✔ 복제 완료: ${_vmid} -> ${_newid}" || _PX_MSG="✖ 복제 실패"
            else
                pct clone "$_vmid" "$_newid" --hostname "$_newnm" --full 1 && _PX_MSG="✔ 복제 완료: ${_vmid} -> ${_newid}" || _PX_MSG="✖ 복제 실패"
            fi
            _px_load_summary; _px_load_tab; _px_build_view
            _px_pause
            ;;

        unlock)
            if [ "$_type" = "qemu" ]; then
                qm unlock "$_vmid" >/dev/null 2>&1 && _PX_MSG="✔ Unlock 완료: qemu/${_vmid}" || _PX_MSG="✖ Unlock 실패: qemu/${_vmid}"
            else
                pct unlock "$_vmid" >/dev/null 2>&1 && _PX_MSG="✔ Unlock 완료: lxc/${_vmid}" || _PX_MSG="✖ Unlock 실패: lxc/${_vmid}"
            fi
            _px_load_summary; _px_load_tab; _px_build_view
            ;;

        destroy)
            tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
            _px_p '\033[1;31m⚠ 영구 삭제 경고: %s/%s (%s) @%s\033[0m\n' "$_type" "$_vmid" "$_nm" "$_node"
            _px_p '이 작업은 디스크와 설정을 모두 삭제하며 되돌릴 수 없습니다!\n'
            read -p "확인을 위해 VMID (${_vmid}) 를 직접 입력하세요: " _ans </dev/tty
            if [ "$_ans" = "$_vmid" ]; then
                if [ "$_type" = "qemu" ]; then
                    qm stop "$_vmid" >/dev/null 2>&1
                    qm destroy "$_vmid" --purge && _PX_MSG="✔ 삭제 완료: qemu/${_vmid}" || _PX_MSG="✖ 삭제 실패: qemu/${_vmid}"
                else
                    pct stop "$_vmid" >/dev/null 2>&1
                    pct destroy "$_vmid" --purge && _PX_MSG="✔ 삭제 완료: lxc/${_vmid}" || _PX_MSG="✖ 삭제 실패: lxc/${_vmid}"
                fi
                _px_load_summary; _px_load_tab; _px_build_view
                _px_pause
            else
                _PX_MSG="삭제 취소됨: ${_vmid}"
            fi
            ;;
    esac
}

pxms() {
    _px_detect_env || return 1

    _PX_TAB=1
    _PX_CUR=0
    _PX_TOP=0
    _PX_PREV_CUR=0
    _PX_PREV_TOP=0
    _PX_SEARCH=""
    _PX_LOADING=0
    _PX_CNT_RUN="-"; _PX_CNT_STOP="-"; _PX_CNT_VM="-"; _PX_CNT_CT="-"; _PX_LOAD="-"; _PX_MEM_PCT="-"
    _PX_DIRTY=1

    local _old_trap _k _k2 _k3 _idx _ans _meta _t _n _id _sn _stg _vol _fmt _upid _newid _def_sn _desc _tkey _vms
    _old_trap=$(trap -p INT)
    trap 'tput cnorm 2>/dev/null; stty sane 2>/dev/null; printf "\n"; return 0' INT

    tput civis 2>/dev/null
    printf '\033[2J\033[H'

    _px_load_tab_async
    _px_load_summary
    _PX_MSG="✔ pxms 준비 완료 (1~6 탭전환, Enter 메뉴, / 검색, ? 도움말)"

    while true; do
        _px_render_delta
        stty -echo 2>/dev/null
        IFS= read -rsn1 _k </dev/tty

        # Arrow / Page / Home / End escape sequences
        if [ "$_k" = $'\x1b' ]; then
            IFS= read -rsn1 -t 1 _k2 </dev/tty
            if [ "$_k2" = "[" ]; then
                IFS= read -rsn1 -t 1 _k3 </dev/tty
                case "$_k3" in
                    A) [ "$_PX_CUR" -gt 0 ] && _PX_CUR=$((_PX_CUR - 1)) ;;
                    B) [ "$_PX_CUR" -lt $((_PX_VCNT - 1)) ] && _PX_CUR=$((_PX_CUR + 1)) ;;
                    C) _PX_TAB=$((_PX_TAB % 6 + 1)); _PX_CUR=0; _PX_TOP=0; _PX_SEARCH=""; _px_load_tab_async ;;
                    D) _PX_TAB=$(( (_PX_TAB + 4) % 6 + 1 )); _PX_CUR=0; _PX_TOP=0; _PX_SEARCH=""; _px_load_tab_async ;;
                    5) IFS= read -rsn1 -t 1 _ </dev/tty; _PX_CUR=$((_PX_CUR - _PX_PAGE)); [ "$_PX_CUR" -lt 0 ] && _PX_CUR=0; _PX_DIRTY=1 ;;
                    6) IFS= read -rsn1 -t 1 _ </dev/tty; _PX_CUR=$((_PX_CUR + _PX_PAGE)); [ "$_PX_CUR" -ge "$_PX_VCNT" ] && _PX_CUR=$((_PX_VCNT > 0 ? _PX_VCNT - 1 : 0)); _PX_DIRTY=1 ;;
                    H) _PX_CUR=0; _PX_DIRTY=1 ;;
                    F) _PX_CUR=$((_PX_VCNT > 0 ? _PX_VCNT - 1 : 0)); _PX_DIRTY=1 ;;
                esac
            else
                if [ -n "$_PX_SEARCH" ]; then
                    _PX_SEARCH=""; _PX_CUR=0; _PX_TOP=0; _px_build_view; _PX_DIRTY=1
                fi
            fi
            continue
        fi

        case "$_k" in
            q|Q) break ;;
            $'\t')
                _PX_TAB=$((_PX_TAB % 6 + 1)); _PX_CUR=0; _PX_TOP=0; _PX_SEARCH=""
                _px_load_tab_async
                ;;
            1|2|3|4|5|6)
                if [ "$_PX_TAB" != "$_k" ]; then
                    _PX_TAB="$_k"; _PX_CUR=0; _PX_TOP=0; _PX_SEARCH=""
                    _px_load_tab_async
                fi
                ;;
            k) [ "$_PX_CUR" -gt 0 ] && _PX_CUR=$((_PX_CUR - 1)) ;;
            j) [ "$_PX_CUR" -lt $((_PX_VCNT - 1)) ] && _PX_CUR=$((_PX_CUR + 1)) ;;
            \?|h)
                _px_show_help; _PX_DIRTY=1; tput civis 2>/dev/null ;;
            /)
                tput cnorm 2>/dev/null; stty echo 2>/dev/null
                _px_p '\n검색어 입력 (빈 값=초기화): '
                IFS= read -r _PX_SEARCH </dev/tty
                _PX_CUR=0; _PX_TOP=0; _px_build_view; _PX_DIRTY=1; tput civis 2>/dev/null
                ;;
            r)
                _px_load_tab_async
                _px_load_summary
                _PX_MSG="✔ 새로고침 완료"
                _PX_DIRTY=1
                ;;
            *)
                _idx=""
                [ "$_PX_VCNT" -gt 0 ] && _idx="${_PX_VIEW[$_PX_CUR]}"
                case "$_PX_TAB" in
                    1) # VM & CT
                        [ -z "$_idx" ] && continue
                        case "$_k" in
                            "") _px_vm_action menu "$_idx"; _PX_DIRTY=1; tput civis 2>/dev/null ;;
                            s)  _px_vm_action toggle "$_idx"; _PX_DIRTY=1 ;;
                            R)  _px_vm_action reboot "$_idx"; _PX_DIRTY=1; tput civis 2>/dev/null ;;
                            e)  _px_vm_action enter "$_idx"; _PX_DIRTY=1; tput civis 2>/dev/null ;;
                            i)  _px_vm_action inspect "$_idx"; _PX_DIRTY=1; tput civis 2>/dev/null ;;
                            c)  _px_vm_action edit_conf "$_idx"; _PX_DIRTY=1; tput civis 2>/dev/null ;;
                            S)  _px_vm_action snapshot "$_idx"; _PX_DIRTY=1; tput civis 2>/dev/null ;;
                            b)  _px_vm_action backup "$_idx"; _PX_DIRTY=1; tput civis 2>/dev/null ;;
                            u)  _px_vm_action unlock "$_idx"; _PX_DIRTY=1 ;;
                            d)  _px_vm_action destroy "$_idx"; _PX_DIRTY=1; tput civis 2>/dev/null ;;
                        esac
                        ;;

                    2) # Snapshots
                        case "$_k" in
                            ""|i)
                                [ -z "$_idx" ] && continue
                                IFS='|' read -r _t _n _id _sn < <(printf '%s\n' "${_PX_META[$_idx]}")
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;36m◈ 스냅샷 트리: %s/%s\033[0m\n' "$_t" "$_id"
                                [ "$_t" = "qemu" ] && qm listsnapshot "$_id" 2>/dev/null || pct listsnapshot "$_id" 2>/dev/null
                                _px_pause; _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            n)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;35m◈ 새 스냅샷 생성\033[0m\n'
                                read -p "대상 VMID 입력: " _id </dev/tty
                                [ -z "$_id" ] && { _PX_DIRTY=1; tput civis 2>/dev/null; continue; }
                                _def_sn="at_$(date '+%Y%m%d_%H%M%S')"
                                read -p "스냅샷 이름 [기본: ${_def_sn}]: " _sn </dev/tty
                                [ -z "$_sn" ] && _sn="$_def_sn"
                                read -p "설명 (선택): " _desc </dev/tty
                                [ -z "$_desc" ] && _desc="Created by pxms"
                                if [ -f "/etc/pve/nodes/${_PX_NODE}/qemu-server/${_id}.conf" ]; then
                                    qm snapshot "$_id" "$_sn" --description "$_desc" && _PX_MSG="✔ 스냅샷 생성: qemu/${_id}@${_sn}" || _PX_MSG="✖ 스냅샷 실패"
                                elif [ -f "/etc/pve/nodes/${_PX_NODE}/lxc/${_id}.conf" ]; then
                                    pct snapshot "$_id" "$_sn" --description "$_desc" && _PX_MSG="✔ 스냅샷 생성: lxc/${_id}@${_sn}" || _PX_MSG="✖ 스냅샷 실패"
                                else
                                    _PX_MSG="✖ 로컬 노드(${_PX_NODE})에서 VMID ${_id} 를 찾을 수 없습니다"
                                fi
                                _px_load_tab; _px_build_view; _px_pause; _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            B)
                                [ -z "$_idx" ] && continue
                                IFS='|' read -r _t _n _id _sn < <(printf '%s\n' "${_PX_META[$_idx]}")
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;31m⚠ 스냅샷 롤백 (Rollback): %s/%s -> [%s]\033[0m\n' "$_t" "$_id" "$_sn"
                                _px_p '현재 상태가 해당 스냅샷 시점으로 되돌아갑니다.\n'
                                read -p "정말 롤백할까요? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    if [ "$_t" = "qemu" ]; then
                                        qm rollback "$_id" "$_sn" && _PX_MSG="✔ 롤백 완료: qemu/${_id}@${_sn}" || _PX_MSG="✖ 롤백 실패"
                                    else
                                        pct rollback "$_id" "$_sn" && _PX_MSG="✔ 롤백 완료: lxc/${_id}@${_sn}" || _PX_MSG="✖ 롤백 실패"
                                    fi
                                    _px_pause
                                fi
                                _px_load_summary; _px_load_tab; _px_build_view; _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            d)
                                [ -z "$_idx" ] && continue
                                IFS='|' read -r _t _n _id _sn < <(printf '%s\n' "${_PX_META[$_idx]}")
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                read -p "스냅샷 삭제 (${_t}/${_id} @ ${_sn})? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    if [ "$_t" = "qemu" ]; then
                                        qm delsnapshot "$_id" "$_sn" && _PX_MSG="✔ 스냅샷 삭제: ${_id}@${_sn}" || _PX_MSG="✖ 삭제 실패"
                                    else
                                        pct delsnapshot "$_id" "$_sn" && _PX_MSG="✔ 스냅샷 삭제: ${_id}@${_sn}" || _PX_MSG="✖ 삭제 실패"
                                    fi
                                    _px_load_tab; _px_build_view; _px_pause
                                fi
                                _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                        esac
                        ;;

                    3) # Backups
                        case "$_k" in
                            ""|i)
                                [ -z "$_idx" ] && continue
                                IFS='|' read -r _stg _id _vol _fmt < <(printf '%s\n' "${_PX_META[$_idx]}")
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;36m◈ 백업 아카이브 상세\033[0m\n'
                                _px_p '  VolID   : %s\n  Storage : %s\n  VMID    : %s\n  Format  : %s\n' "$_vol" "$_stg" "$_id" "$_fmt"
                                _px_p '  Path    : %s\n' "$(pvesm path "$_vol" 2>/dev/null || echo '-')"
                                _px_pause; _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            b)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;32m◈ VM/CT 지정 백업 (vzdump)\033[0m\n'
                                read -p "백업할 VMID (공백 구분 복수 가능): " _id </dev/tty
                                [ -z "$_id" ] && { _PX_DIRTY=1; tput civis 2>/dev/null; continue; }
                                _stg=$(_px_pick_backup_storage)
                                vzdump $_id --mode snapshot --storage "$_stg" --compress zstd --notes-template "{{guestname}}" --remove 0 \
                                    && _PX_MSG="✔ 백업 완료: ${_id} -> ${_stg}" || _PX_MSG="✖ 백업 실패"
                                _px_load_tab; _px_build_view; _px_pause; _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            A)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _vms=$( { pct list 2>/dev/null; qm list 2>/dev/null; } | awk '/running/ {print $1}' | tr '\n' ' ')
                                _px_p '\033[1;36m◈ 실행 중인 전체 VM/CT 일괄 백업\033[0m\n  대상: %s\n' "${_vms:-없음}"
                                [ -z "$_vms" ] && { _px_pause; _PX_DIRTY=1; tput civis 2>/dev/null; continue; }
                                _stg=$(_px_pick_backup_storage)
                                read -p "실행할까요? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    vzdump $_vms --mode snapshot --storage "$_stg" --compress zstd --notes-template "{{guestname}}" --remove 0 \
                                        && _PX_MSG="✔ 일괄 백업 완료" || _PX_MSG="✖ 일괄 백업 일부 실패"
                                    _px_load_tab; _px_build_view; _px_pause
                                fi
                                _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            R)
                                [ -z "$_idx" ] && continue
                                IFS='|' read -r _stg _id _vol _fmt < <(printf '%s\n' "${_PX_META[$_idx]}")
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;35m◈ 백업 복원 (Restore)\033[0m\n  원본: %s\n' "$_vol"
                                read -p "복원할 대상 VMID (신규 ID 권장): " _newid </dev/tty
                                [ -z "$_newid" ] && { _PX_DIRTY=1; tput civis 2>/dev/null; continue; }
                                read -p "대상 디스크 스토리지 [기본: local-lvm]: " _ans </dev/tty
                                [ -z "$_ans" ] && _ans="local-lvm"
                                case "$_vol" in
                                    *vzdump-lxc-*)
                                        pct restore "$_newid" "$_vol" --storage "$_ans" && _PX_MSG="✔ LXC 복원 완료: ${_newid}" || _PX_MSG="✖ LXC 복원 실패" ;;
                                    *)
                                        qmrestore "$_vol" "$_newid" --storage "$_ans" && _PX_MSG="✔ QEMU 복원 완료: ${_newid}" || _PX_MSG="✖ QEMU 복원 실패" ;;
                                esac
                                _px_load_summary; _px_pause; _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            d)
                                [ -z "$_idx" ] && continue
                                IFS='|' read -r _stg _id _vol _fmt < <(printf '%s\n' "${_PX_META[$_idx]}")
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                read -p "백업 파일 영구 삭제 (${_vol})? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    pvesm free "$_vol" && _PX_MSG="✔ 백업 삭제 완료" || _PX_MSG="✖ 백업 삭제 실패"
                                    _px_load_tab; _px_build_view; _px_pause
                                fi
                                _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                        esac
                        ;;

                    4) # Storage & ISO
                        case "$_k" in
                            ""|i)
                                [ -z "$_idx" ] && continue
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;36m◈ 스토리지 콘텐츠: %s\033[0m\n' "${_PX_IDS[$_idx]}"
                                pvesm list "${_PX_IDS[$_idx]}" 2>/dev/null | less -RX
                                _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            l)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;36m◈ LVM / Thin 볼륨 상세 (vgs & lvs)\033[0m\n'
                                vgs 2>/dev/null; echo; lvs 2>/dev/null
                                _px_pause; _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            I)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;36m◈ ISO & LXC 템플릿 목록 (local)\033[0m\n'
                                pvesm list local --content iso 2>/dev/null
                                echo
                                pvesm list local --content vztmpl 2>/dev/null
                                echo
                                read -p "ISO/LXC 다운로드 메뉴 [iso] 로 이동할까요? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    declare -f process_commands >/dev/null 2>&1 && process_commands iso
                                fi
                                _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            z)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;36m◈ ZFS 풀 & 데이터셋 상태\033[0m\n'
                                if command -v zpool >/dev/null 2>&1; then
                                    zpool status 2>/dev/null; echo; zfs list 2>/dev/null
                                else
                                    _px_p 'ZFS 가 설치/구성되어 있지 않습니다.\n'
                                fi
                                _px_pause; _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                        esac
                        ;;

                    5) # Node & Tasks
                        case "$_k" in
                            ""|i)
                                [ -z "$_idx" ] && continue
                                IFS='|' read -r _upid _n < <(printf '%s\n' "${_PX_META[$_idx]}")
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;36m◈ Task 로그: %s\033[0m\n' "${_PX_NAMES[$_idx]}"
                                if [ "$_PX_HAS_JQ" = "1" ]; then
                                    pvesh get "/nodes/${_n}/tasks/${_upid}/log" --limit 500 --output-format json 2>/dev/null | jq -r '.[] | .t' | less -RX
                                else
                                    pvesh get "/nodes/${_n}/tasks/${_upid}/log" --limit 200 --noborder 2>/dev/null | less -RX
                                fi
                                _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            c)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;36m◈ 클러스터 상태 (pvecm status & nodes)\033[0m\n'
                                pvecm status 2>/dev/null; echo; pvecm nodes 2>/dev/null
                                _px_pause; _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            t)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                if command -v htop >/dev/null 2>&1; then
                                    htop
                                else
                                    top
                                fi
                                _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            l)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                _px_p '\033[1;36m◈ PVE 데몬 최근 로그 & Fail2ban\033[0m\n'
                                journalctl -u pvedaemon -u pveproxy -n 40 --no-pager 2>/dev/null
                                if command -v fail2ban-client >/dev/null 2>&1; then
                                    _px_p '\n\033[1;33m[Fail2ban 상태]\033[0m\n'
                                    fail2ban-client status 2>/dev/null
                                fi
                                _px_pause; _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                            S)
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                read -p "pveproxy 및 pvedaemon 서비스를 재시작할까요? [y/N]: " _ans </dev/tty
                                if printf '%s' "$_ans" | grep -qE '^[Yy]$'; then
                                    systemctl restart pveproxy pvedaemon && _PX_MSG="✔ pveproxy/pvedaemon 재시작 완료" || _PX_MSG="✖ 서비스 재시작 실패"
                                    _px_pause
                                fi
                                _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                        esac
                        ;;

                    6) # Tools (36 menus launcher)
                        case "$_k" in
                            "")
                                [ -z "$_idx" ] && continue
                                _tkey="${_PX_IDS[$_idx]}"
                                tput cnorm 2>/dev/null; stty echo 2>/dev/null; printf '\033[2J\033[H'
                                if declare -f process_commands >/dev/null 2>&1; then
                                    process_commands "$_tkey"
                                else
                                    _px_p '\033[1;31mprocess_commands 함수를 찾을 수 없습니다.\033[0m\n'
                                    _px_pause
                                fi
                                _PX_MSG="✔ 메뉴 종료 후 복귀: [${_tkey}]"
                                _px_load_summary; _px_load_tab; _px_build_view
                                _PX_DIRTY=1; tput civis 2>/dev/null
                                ;;
                        esac
                        ;;
                esac
                ;;
        esac
    done

    tput cnorm 2>/dev/null
    stty sane 2>/dev/null
    [ -n "$_old_trap" ] && eval "$_old_trap" || trap - INT
    printf '\n'
}

# euc-kr -> utf-8 file encoding
utt() { if ! file -i "$1" | grep -qi utf-8; then
    rbackup $1 || cp -a $1 $1.bak
    iconv -f euc-kr -t utf-8//IGNORE "$1" >"$1.temp" && cat "$1.temp" >"$1" && rm -f "$1.temp"
fi; }

# 안전한 다운로드 헬퍼 (2026-09-28)
#   wget -O / curl -o 는 실패 시 대상 파일을 0바이트로 TRUNCATE 해서
#   go.sh 자체가 파괴된다. 그래서 .dl 임시파일에 받고,
#   최소 크기를 확인한 뒤 mv 로 원자적 교체한다.
# _go_dl <url> <출력경로> <최소크기>
_go_dl() {
    local url="$1" out="$2" min="${3:-1000}" tmp="$2.dl"
    local dl_url="$url" sz=""
    case "$dl_url" in
        *\?*) dl_url="${dl_url}&_t=$(date +%s)" ;;
        *)    dl_url="${dl_url}?_t=$(date +%s)" ;;
    esac
    rm -f "$tmp"
    ko "  >> 다운로드: %s\n" "$url"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 -m 20 "$dl_url" -o "$tmp" 2>/dev/null || rm -f "$tmp"
    fi
    if [ ! -s "$tmp" ] && command -v wget >/dev/null 2>&1; then
        wget -q -T 10 -t 2 --cache=off "$dl_url" -O "$tmp" 2>/dev/null || rm -f "$tmp"
    fi
    [ -s "$tmp" ] || { echo " ❌ 다운로드 실패: $url" >&2; return 1; }
    sz=$(wc -c <"$tmp" 2>/dev/null | tr -d '[:space:]')
    [ -n "$sz" ] && [ "$sz" -ge "$min" ] || { echo " ❌ 용량 비정상(${sz:-0}B < ${min}B): $url" >&2; rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$out" || { rm -f "$tmp"; return 1; }
    return 0
}

# update
update() {
    rbackup "$gofile" "$envorg"
    echo "update file: $gofile $envorg"
    [ -f "$gofile" ] || { echo " ❌ $gofile 없음 - 갱신 중단" >&2; return 1; }
    if ! _go_dl http://srt.byus.net/go.sh "$gofile" 100000; then
        echo " ❌ go.sh 갱신 실패 - 기존 파일 그대로 보존됨" >&2
        return 1
    fi
    bash -n "$gofile" 2>/dev/null || {
        echo " ❌ 받은 go.sh 문법 오류 - 백업본으로 복구" >&2
        [ -f "$gofile.1.bak" ] && cp -a "$gofile.1.bak" "$gofile"
        return 1
    }
    chmod 700 "$gofile"
    if [ -f "$envorg" ]; then
        if _go_dl http://srt.byus.net/go.env "$envorg" 100000; then
            chmod 600 "$envorg"
        else
            echo " ❌ go.env 갱신 실패 - 갱신 중단" >&2
            return 1
        fi
    fi
    ko " [OK] 업데이트 완료! 재시작합니다...\n"
    savescut && GO_ALLOW_REEXEC=1 exec bash "$gofile" ${scut:+"$scut"}
}

# install
yyay() {
    [[ " $* " == *" Cancel "* ]] && echo "Canceled... " && return 1

    [ "$(which yum)" ] && yum="yum" || yum="apt"
    while [ $# -gt 0 ]; do
        $yum install -y $1
        shift
    done
}
ayyy() { yyay $@; }
aptupup() {
    apt update -y
    apt upgrade -y
}
aptupd() { apt update -y; }
aptupg() { atp upgrade -y; }
ay() { [ "$(which apt)" ] && while [ $# -gt 0 ]; do
    apt install -y $1
    shift
done; }
yy() { [ "$(which yum)" ] && while [ $# -gt 0 ]; do
    yum install -y $1
    shift
done; }

# ip -> ip(hostinfo) /etc/hosts
hostinfo() {
    awk '
  /^[0-9]+\./ {
      ip=$1;
      cmd="getent hosts " ip;
      if ((cmd | getline line) > 0) {
          split(line, hosts, " ");
          host=hosts[2];  # IP 다음 첫 번째 호스트 이름 선택
          if (host != "") {
              sub($1, $1 " (\033[1m" host "\033[0m)", $0);
          } else {
              sub($1, $1 " (unknown)", $0);
          }
      } else {
          sub($1, $1 " (unknown)", $0);
      }
      print
  }
  !/^[0-9]+\./ {
      print
  }
  '
}

# ipban & ipallow
ipcheck() { echo "$1" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; }
ii() { curl ipinfo.io/$1; }
iii() { whois $1; }
ipbanlog() {
    echo -e "\033[1;36m 최근 차단된 IP 관련 로그 (Fail2ban + iptables)\033[0m"
    journalctl -u fail2ban -n 100 --no-pager | grep -iE 'ban|drop|fail|denied' | cpipe | less -RX
}
ipban() {
    valid_ips=true
    for ip in "$@"; do ipcheck ${ip%/*} && iptables -A INPUT -s ${ip%/*} -j DROP || {
        valid_ips=false
        break
    }; done
    $valid_ips && iptables -L INPUT -v -n | grep DROP | tail -n20 | gip | cip
}
ipban24() {
    valid_ips=true
    for ip in "$@"; do
        base=${ip%/*}
        if ipcheck "$base"; then
            net="${base%.*}.0/24"
            iptables -A INPUT -s "$net" -j DROP
        else
            valid_ips=false
            break
        fi
    done
    #$valid_ips && iptables -L -v -n | tail -n20 | gip | cip
    $valid_ips && iptables -L INPUT -v -n | grep DROP | tail -n20 | gip | cip
}
ipban16() {
    valid_ips=true
    for ip in "$@"; do
        base=${ip%/*}
        if ipcheck "$base"; then
            net="$(echo "$base" | cut -d. -f1,2).0.0/16"
            iptables -A INPUT -s "$net" -j DROP
        else
            valid_ips=false
            break
        fi
    done
    $valid_ips && iptables -L INPUT -v -n | grep DROP | tail -n20 | gip | cip
}
ipbanlist() {
    echo -e "\033[1;36m현재 iptables DROP 룰 최근 목록 (마지막 50줄)\033[0m"
    iptables -L INPUT -v -n | grep DROP | tail -n 50 | gip | cip
}
ipallow() {
    valid_ips=true
    for ip in "$@"; do
        baseip=${ip%/*}
        if ipcheck "$baseip"; then
            iptables -D INPUT -s "$baseip" -j DROP 2>/dev/null
            iptables -D INPUT -s "${baseip%.*}.0/24" -j DROP 2>/dev/null
            iptables -D INPUT -s "${baseip%.*.*}.0.0/16" -j DROP 2>/dev/null
        else
            valid_ips=false
            break
        fi
    done
    $valid_ips && iptables -L INPUT -v -n | grep DROP | tail -n20 | gip | cip
}
ipallow24() {
    valid_ips=true
    for ip in "$@"; do ipcheck ${ip%/*} && iptables -D INPUT -s ${ip%/*}/24 -j DROP || {
        valid_ips=false
        break
    }; done
    $valid_ips && iptables -L INPUT -v -n | grep DROP | tail -n20 | gip | cip
}
ipallow16() {
    valid_ips=true
    for ip in "$@"; do ipcheck ${ip%/*} && iptables -D INPUT -s ${ip%/*}/16 -j DROP || {
        valid_ips=false
        break
    }; done
    $valid_ips && iptables -L INPUT -v -n | grep DROP | tail -n20 | gip | cip
}

# 파일 암호화/복호화 env 참조
encrypt_file_old() {
    k="${ENC_KEY:-$HOSTNAME}"
    i=$(readlinkf "$1")
    o="$i.enc"
    openssl enc -aes-256-cbc -in "$i" -out "$o" -pass pass:"$k"
    rm "$i"
    chmod 600 "$o"
}
decrypt_file_old() {
    k="${ENC_KEY:-$HOSTNAME}"
    i=$(readlinkf "$1")
    o="${i%.*}"
    openssl enc -aes-256-cbc -d -in "$i" -out "$o" -pass pass:"$k"
    rm "$i"
    chmod 600 "$o"
}
# new
encrypt_file() {
    [ -n "$2" ] && k="$2" || k="${ENC_KEY:-$HOSTNAME}"
    i=$(readlinkf "$1")
    o="$i.enc"
    openssl enc -des-ede3-cbc -in "$i" -out "$o" -pass pass:"$k" 2>/dev/null && {
        rm "$i"
        chmod 600 "$o"
    }
}
decrypt_file() {
    [ -n "$2" ] && k="$2" || k="${ENC_KEY:-$HOSTNAME}"
    i=$(readlinkf "$1")
    o="${i%.enc}"
    openssl enc -des-ede3-cbc -d -in "$i" -out "$o" -pass pass:"$k" 2>/dev/null && chmod 600 "$o"
}
# [중복 제거] encrypt() 와 decrypt() 는 상단(100행 부근)에 -r 플래그 및 printf 안전 처리와 함께 일원화 선언됨

# 중복 실행 방지 함수
runlock() {
    local lockfile_base
    lockfile_base="$(basename "$0").lock"
    Lockfile="/var/run/$lockfile_base"
    [ -f "$Lockfile" ] && {
        P=$(cat "$Lockfile")
        [ -n "$(ps --no-headers -f "$P")" ] && {
            echo "already running... exit."
            exit 1
        }
    }
    echo $$ >"$Lockfile"
    trap 'rm -f "$Lockfile"' INT EXIT TERM
}

# runlock 함수를 스크립트 파일에 삽입하는 함수
runlockadd() {
    local f="$1"
    local t
    t="$(mktemp ${TMPDIR:=/tmp}/tmpfile_XXXXXX)"

    grep -q "runlock()" "$f" && {
        echo "runlock function already exists."
        return
    }
    rbackup $f && sed -e '1a\runlock() { local lockfile_base="$(basename "$0").lock"; Lockfile="/var/run/$lockfile_base"; [ -f $Lockfile ] && { P=$(cat $Lockfile); [ -n "$(ps --no-headers -f $P)" ] && { echo "already running... exit."; exit 1; }; }; echo $$ > $Lockfile; trap '\''rm -f "$Lockfile"'\'' INT TERM EXIT; }' -e '1a\runlock' "$f" >"$t" && {
        cat "$t" >"$f"
        rm -f $t
        diff ${f}.1 ${f}
        ls -al ${f} ${f}.1
    }
}

bm() { bmon -p "$(basename -a /sys/class/net/e* | paste -sd ',')" || yyay bmon; }
# 카피나 압축등 df -m  에 변동이 있을경우 모니터링용

dfmonitor() {
    DF_INITIAL=$(df -m | grep -vE "udev|none|efi|fuse|tmpfs|Available|overlay|/snap/")
    DF_BEFORE=$DF_INITIAL
    while true; do
        clear
        echo -e "System Uptime:\n--------------"
        uptime
        echo -e "\nRunning processes (e.g., pv, cp, tar, zst, rsync, dd, mv):\n----------------------------------------------------------\n\033[36m"
        ps -ef | grep -E "\<(pv|cp|tar|zst|zstd|rsync|dd|mv)\>" | grep -v grep
        echo -e "\033[0m\nInitial df -m output:\n---------------------\n$DF_INITIAL"
        echo -e "\033[0m\nPrevious df -m output:\n-----------------------\n$DF_BEFORE\n"
        DF_AFTER=$(df -m | grep -vE "udev|none|efi|fuse|tmpfs|Available|overlay|/snap/")
        echo -e "New df -m output with changes highlighted:\n------------------------------------------"

        echo "$DF_AFTER" | while read line; do
            DEVICE=$(echo "$line" | awk '{print $1}')
            USED_NEW=$(echo "$line" | awk '{print $3+0}')
            AVAIL_NEW=$(echo "$line" | awk '{print $4+0}')
            OLD_LINE=$(echo "$DF_BEFORE" | grep "^$DEVICE ")
            USED_OLD=$(echo "$OLD_LINE" | awk '{print $3+0}')
            AVAIL_OLD=$(echo "$OLD_LINE" | awk '{print $4+0}')

            # 숫자인지 확인 (bash2 호환)
            echo "$USED_OLD" | grep -q '^[0-9]\+$' && echo "$AVAIL_OLD" | grep -q '^[0-9]\+$'
            if [ $? -eq 0 ]; then
                USED_DIFF=$((USED_NEW - USED_OLD))
                if [ $USED_DIFF -gt 0 ]; then
                    echo -e "\033[1;37;41m$line  [+${USED_DIFF}MB]\033[0m"
                elif [ $USED_DIFF -lt 0 ]; then
                    echo -e "\033[1;37;44m$line  [${USED_DIFF}MB]\033[0m"
                else
                    echo "$line"
                fi
            else
                echo "$line"
            fi
        done

        echo -e "\033[0m"
        DF_BEFORE=$DF_AFTER
        echo -n ">>> Quit -> [Anykey] "
        for i in $(seq 1 4); do
            read -p"." -t1 -n1 x && break
        done
        [ "$x" ] && break
    done
}

# proxmox running vmid vnname ip print
vmipscan() {
    local IFS=$' \t\n'
    local iface
    [ "$1" ] && iface="$1" || iface=$(ip route | awk '/default/ {print $5}')

    declare -A mac_ip_map
    while read -r ip mac; do
        mac_ip_map["$(echo "$mac" | tr '[:upper:]' '[:lower:]')"]="$ip"
    done < <(arp-scan -I $iface -l | awk '/^[0-9]/ {print $1, $2}')

    for node in $(pvesh get /nodes --noborder --noheader | awk '{print $1}'); do
        for vmid in $(pvesh get /nodes/$node/qemu --noborder --noheader | awk '/running/ {print $2}'); do
            config=$(pvesh get /nodes/$node/qemu/"$vmid"/config --noborder --noheader)
            vmname=$(echo "$config" | awk '$1 == "name" {print $2}')
            mac=$(echo "$config" | awk '$1 ~ /net0/ {print $2}' | sed -n 's/.*=\([0-9A-Fa-f:]\+\),bridge=.*/\1/p')
            [[ -n $mac ]] && ip="${mac_ip_map[$(echo "$mac" | tr '[:upper:]' '[:lower:]')]}"
            [[ -n $ip ]] && echo "-> $vmid $vmname $ip"
        done
    done
    unset IFS
}

vmip() {
    local vmid="$1"
    local debug="$2"
    [ -z "$vmid" ] && echo "Usage: vmip <vmid> [debug]" && return 1

    if [ "$debug" == "debug" ]; then
        echo "[DEBUG] Looking up VMID: $vmid"
    fi

    local info node type
    info=$(pvesh get /cluster/resources --output-format=json | jq -r ".[] | select(.vmid == $vmid) | \"\(.node) \(.type)\"")
    node=$(echo "$info" | awk '{print $1}')
    type=$(echo "$info" | awk '{print $2}')

    if [ -z "$node" ] || [ -z "$type" ]; then
        [ "$debug" == "debug" ] && echo "[DEBUG] Node or Type not found for VMID $vmid"
        echo "N/A"
        return 1
    fi

    [ "$debug" == "debug" ] && echo "[DEBUG] Node=$node, Type=$type"

    local config mac
    config=$(pvesh get /nodes/$node/$type/$vmid/config --noborder 2>/dev/null)
    mac=$(echo "$config" | grep -Eio '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -n1 | tr '[:upper:]' '[:lower:]')

    if [ -z "$mac" ]; then
        [ "$debug" == "debug" ] && echo "[DEBUG] MAC address not found."
        echo "N/A"
        return 1
    fi

    [ "$debug" == "debug" ] && echo "[DEBUG] MAC=$mac"

    local gateway iface
    gateway=$(ip route | awk '/default/ {print $3}')
    iface=$(ip route | awk '/default/ {print $5}')

    if [ -z "$gateway" ] || [ -z "$iface" ]; then
        [ "$debug" == "debug" ] && echo "[DEBUG] Gateway or Interface not found."
        echo "N/A"
        return 1
    fi

    [ "$debug" == "debug" ] && echo "[DEBUG] Gateway: $gateway"
    [ "$debug" == "debug" ] && echo "[DEBUG] Interface: $iface"

    local ip="" attempt=0
    while [ "$attempt" -lt 5 ] && [ -z "$ip" ]; do
        trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT

        [ "$debug" == "debug" ] && echo "[DEBUG] Running arp-scan (attempt $((attempt + 1)))..."

        arp-scan -I "$iface" --localnet 2>/dev/null |
            awk -v dev="$iface" '
{
    ip=$1; mac=$2;

    # IP가 올바른 IPv4 주소 형식인 경우에만 처리
    if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
        # ARP 테이블 갱신 명령어 출력
        print "ip neigh del " ip " dev " dev " 2>/dev/null";
        print "ip neigh add " ip " lladdr " mac " dev " dev " nud reachable";
    }
}' | bash

        #ip=$(ip neigh | grep -i "$mac" | awk '{print $1}' | head -n1)
        ip=$(ip neigh | grep -i "$mac" | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $1}' | head -n1)

        if [ -z "$ip" ]; then
            [ "$debug" == "debug" ] && echo "[DEBUG] IP not found for MAC=$mac, retrying..."
            sleepdot 3
        else
            [ "$debug" == "debug" ] && echo "[DEBUG] Found IP: $ip"
        fi

        attempt=$((attempt + 1))
        trap - SIGINT
    done

    if [ -z "$ip" ]; then
        echo "N/A"
        [ "$debug" == "stop" ] && echo "Unable to find IP, shutting down" && dlines vm $vmid stop && vm $vmid stop && return 1
    else
        echo "$ip"
    fi
}

_vmip() {
    local vmid="$1"
    local debug="$2" # 디버그 여부 확인
    [ -z "$vmid" ] && echo "Usage: vmip <vmid> [debug]" && return 1

    if [ "$debug" == "debug" ]; then
        echo "[DEBUG] Looking up VMID: $vmid"
    fi

    # VM의 노드와 타입 가져오기
    local info node type
    info=$(pvesh get /cluster/resources --output-format=json | jq -r ".[] | select(.vmid == $vmid) | \"\(.node) \(.type)\"")
    node=$(echo "$info" | awk '{print $1}')
    type=$(echo "$info" | awk '{print $2}')

    if [ -z "$node" ] || [ -z "$type" ]; then
        [ "$debug" == "debug" ] && echo "[DEBUG] Node or Type not found for VMID $vmid"
        echo "N/A"
        return 1
    fi

    [ "$debug" == "debug" ] && echo "[DEBUG] Node=$node, Type=$type"

    # VM의 설정에서 MAC 주소를 추출
    local config mac
    config=$(pvesh get /nodes/$node/$type/$vmid/config --noborder 2>/dev/null)
    mac=$(echo "$config" | grep -Eio '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -n1 | tr '[:upper:]' '[:lower:]')

    if [ -z "$mac" ]; then
        [ "$debug" == "debug" ] && echo "[DEBUG] MAC address not found."
        echo "N/A"
        return 1
    fi

    [ "$debug" == "debug" ] && echo "[DEBUG] MAC=$mac"

    # 기본 게이트웨이 주소 확인
    local gateway
    gateway=$(ip route | awk '/default/ {print $3}')

    if [ -z "$gateway" ]; then
        [ "$debug" == "debug" ] && echo "[DEBUG] No gateway found."
        echo "N/A"
        return 1
    fi

    [ "$debug" == "debug" ] && echo "[DEBUG] Gateway: $gateway"

    # 게이트웨이에 연결된 네트워크 인터페이스 찾기
    local iface
    iface=$(ip route | grep "default" | awk '{print $5}')

    if [ -z "$iface" ]; then
        [ "$debug" == "debug" ] && echo "[DEBUG] No valid network interface found."
        echo "N/A"
        return 1
    fi

    [ "$debug" == "debug" ] && echo "[DEBUG] Using interface: $iface"

    # arp-scan을 사용하여 네트워크 스캔을 수행하고, 결과를 디버깅
    [ "$debug" == "debug" ] && echo "[DEBUG] Running arp-scan..."
    local arp_scan_output ip attempt
    attempt=0
    ip=""

    while [ "$attempt" -lt 5 ] && [ -z "$ip" ]; do
        trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
        arp_scan_output=$(arp-scan --interface "$iface" "$gateway"/24 2>/dev/null)
        [ "$debug" == "debug" ] && echo "[DEBUG] arp-scan output:\n$arp_scan_output"

        ip=$(echo "$arp_scan_output" | grep -i "$mac" | awk '{print $1}')

        if [ -z "$ip" ]; then
            [ "$debug" == "debug" ] && echo "[DEBUG] IP not found for MAC=$mac, retrying..."
            sleepdot 3
        fi

        attempt=$((attempt + 1))
        trap - SIGINT
    done

    if [ -z "$ip" ]; then
        echo "N/A"
        [ "$debug" == "stop" ] && echo "Unable to find IP, shutting down" && dlines vm $vmid stop && vm $vmid stop && return 1
    else
        [ "$debug" == "debug" ] && echo "[DEBUG] Found IP: $ip"
        echo "$ip"
    fi
}

lvd() { lvs --noheadings --units g -o lv_name,lv_size,data_percent | awk '$2 != "0.00g" && NF==3 {u=$2*$3/100; printf "%s: %s / %.2fG / %s%%\n", $1, $2, u, $3}' | column -t; }
vms() { vmslistview | cgrepn running -3; }
vm() {
    unset -v vmid
    vmid=$1
    action=$2

    # If no VMID is provided, show available commands
    if [ -z "$1" ]; then
        process_commands pxx y nodone
        #process_commands "vmslistview | cgrepn running -3" y nodone
        return
    fi

    # Locate the configuration file for the VM
    conf=$(find /etc/pve/ -name "$vmid.conf" | head -n1) || return 1
    [ -z "$conf" ] && echo "VM $vmid not found" && return 1

    # Extract node name and VM type (qemu or lxc)
    node=$(echo "$conf" | awk -F/ '{print $5}')
    type=$(echo "$conf" | grep -q qemu && echo qemu || echo lxc) # Bash 2 호환: <<< 금지
    path="/nodes/$node/$type/$vmid"

    case "$action" in
    # Basic VM control actions
    start | stop | shutdown | reboot | reset | suspend | resume)
        OUTPUT="$(pvesh create "$path/status/$action" 2>&1)"
        echo "$OUTPUT"
        if echo "$OUTPUT" | grep -qE "device is already attached|Duplicate ID|vfio.*error|QEMU exited with code 1" && [ "$action" = "start" ]; then
            echo "VM $vmid failed to start. Stopping VM..."
            vm $vmid stop
            return 1
        else
            if echo "$action" | grep -qE "start"; then
                echo "Booting..." && sleepdot 5 && dlines ip checking && vmip $vmid stop && dline && vms && echo "$action Done..."
            elif echo "$action" | grep -qE "stop"; then
                echo "Halting..." && sleepdot 5 && dline && vms
                echo "$action Done..."
            fi
        fi
        ;;

    unlock)
        OUTPUT="$(pvesh delete "$path/lock" 2>&1)"
        echo "$OUTPUT"
        if echo "$OUTPUT" | grep -qi "does not exist"; then
            echo "No lock present on VM $vmid."
        elif echo "$OUTPUT" | grep -qi "permission denied"; then
            echo "Failed to unlock VM $vmid: Permission denied."
            return 1
        else
            echo "Unlocking..." && sleepdot 3 && dline && vms
            echo "unlock Done..."
        fi
        ;;

    startforce | startf)
        # 아이피를 못찾아도 stop 하지 않고 유지
        OUTPUT="$(pvesh create "$path/status/start" 2>&1)"
        echo "$OUTPUT"
        echo "Booting..." && sleepdot 5 && dlines ip checking && vmip $vmid && dline && vms
        echo "Done..."
        ;;

    config | conf)
        pvesh get "$path/config" --noborder | cgrepline name ostype | cgrepline1 args hostpci cpu
        ;;

    econfig | econf | confige | confe | starte | stope)
        vi2 $conf
        ;;
    # Get current VM status
    status | st | "")
        pvesh get "$path/status/current" --noborder | cgrepf2 stopped running
        dline
        lvs --noheadings --units g -o lv_name,lv_size,data_percent | awk -v id="vm-"$vmid '$2 != "0.00g" && $1 ~ "^"id && NF==3 {u=$2*$3/100; printf "%s: %s / %.2fG / %s%%\n", $1, $2, u, $3}'
        ;;

    ip | ipcheck)
        vmip $vmid
        ;;
    # Enter the VM (LXC: pct enter, QEMU: SSH)
    enter | e)
        echo "Entering $vmid ($type on $node)..."
        status=$(pvesh get "$path/status/current" --output-format=json | grep -o '"status":"[^"]*"' | cut -d: -f2 | tr -d '"')
        [ "$status" != "running" ] && {
            echo "Starting VM..."
            pvesh create "$path/status/start"
            for i in 1 2 3 4 5; do
                sleep 1
                status=$(pvesh get "$path/status/current" --output-format=json | grep -o '"status":"[^"]*"' | cut -d: -f2 | tr -d '"')
                [ "$status" = "running" ] && echo "Booting Now... wait..." && {
                    [ "$type" = "lxc" ] && sleepdot 3 || sleepdot 10
                } && break
            done
            [ "$status" != "running" ] && echo "Failed to start VM" && return 1
        }
        if [ "$type" = "lxc" ]; then
            pct enter "$vmid"
        else
            qssh "$vmid" root
        fi
        ;;

    # Backup the VM using vzdump with snapshot mode
    backup)
        echo "Backing up $vmid using vzdump..."
        #storage=$(pvesh get /storage -output-format=json | jq -r --arg node "$(basename "$(readlink /etc/pve/local)")" '.[] | select( (.nodes == $node) and (.type == "dir") and (.content|contains("backup"))) | .storage')
        storage=$(pvesh get /storage -output-format=json | jq -r --arg node "$(basename "$(readlink /etc/pve/local)")" \
            '.[] | select((.nodes == null or .nodes == $node) and (.type == "dir") and (.content | contains("backup"))) | .storage')

        if [[ $(echo "$storage" | wc -l) -gt 1 ]]; then
            storage=$(echo $storage | pipemenu stoage slect)
        fi

        # 스토리지 없으면 기본값 사용
        if [ -z "$storage" ]; then
            echo "No backup storage found, using default storage (local)."
            storage="local" # 기본값 설정 (필요에 따라 다른 기본값으로 바꿀 수 있음)
        fi

        vzdump $vmid --mode snapshot --storage "$storage" --compress zstd --notes-template "{{guestname}}" --remove 0
        bell
        ;;
    # Create a snapshot with auto-generated name (QEMU + LXC)
    snapshot)
        snapname=$3
        if [ -z "$snapname" ]; then
            snapname="at_$(datetag2)"
            echo "No name provided, using generated snapshot name: $snapname"
        fi
        echo "Creating snapshot '$snapname' for $type $vmid..."
        if [ "$type" = "qemu" ]; then
            qm snapshot "$vmid" "$snapname" --description "Auto snapshot created by vm_func"
            dline
            qm listsnapshot $vmid | awk2c
        else
            pct snapshot "$vmid" "$snapname"
            dline
            pct listsnapshot $vmid | awk2c
        fi
        ;;

    # Roll back to a snapshot (prompt if no name is given)
    rollback)
        snapname=$3
        if [ -z "$snapname" ]; then
            echo "Available snapshots for $type $vmid:"
            if [ "$type" = "qemu" ]; then
                dline
                qm listsnapshot $vmid | awk2c
                dline
                echo "Choose a snapshot to rollback:"
                select snapname in $(qm listsnapshot $vmid | awk2); do
                    [ -n "$snapname" ] && break
                    echo "Invalid choice."
                done
            else
                dline
                pct listsnapshot $vmid | awk2c
                dline
                echo "Choose a snapshot to rollback:"
                select snapname in $(pct listsnapshot $vmid | awk2); do
                    [ -n "$snapname" ] && break
                    echo "Invalid choice."
                done
            fi
            [ -z "$snapname" ] && echo "No snapshot name given." && return 1
        fi

        echo "Rolling back $type $vmid to snapshot '$snapname'..."
        if [ "$type" = "qemu" ]; then
            qm rollback "$vmid" "$snapname"
            echo "Starting container $vmid..."
            qm start $vmid
        else
            echo "Stopping container $vmid..."
            pct stop "$vmid"
            pct rollback "$vmid" "$snapname"
            echo "Starting container $vmid..."
            pct start "$vmid"
        fi
        ;;

    destroy)
        echo "Preparing to destroy VM $vmid..."
        echo "This will remove VM configuration only (disk will remain)."
        read -p "Type the VMID ($vmid) again to confirm: " confirm
        if [ "$confirm" != "$vmid" ]; then
            echo "VMID mismatch. Aborting."
            return 1
        fi
        qm destroy "$vmid"
        echo "VM $vmid destroyed (config only)."
        ;;
    destroyfull | destroyhard | destroyall)
        echo "Preparing to FULLY destroy VM $vmid (including disks)..."
        echo -e "${RED1}!!! This action is irreversible and will remove the VM and all its data!${NC}"
        read -p "Type the VMID ($vmid) again to confirm: " confirm
        if [ "$confirm" != "$vmid" ]; then
            echo "VMID mismatch. Aborting."
            return 1
        fi
        qm destroy "$vmid" --destroy-unreferenced-disks
        echo "VM $vmid fully destroyed (including disks)."
        ;;

    # Handle unsupported actions
    *)
        qm $action $vmid
        if [ $? != 0 ]; then
            echo "Unsupported action: $action"
            return 2
        fi
        ;;
    esac
    #	[ "$ooldscut" != "pxx" ] && menufunc $ooldscut
}

vmm() { watch_pve; }
watch_pve() {
    interval=${1:-5}
    local_node=$(hostname -s 2>/dev/null)
    [ -z "$local_node" ] && echo "Error: No hostname." 1>&2 && return 1
    for cmd in pvesh jq awk date grep sed hostname bc qm; do
        command -v $cmd >/dev/null || {
            echo "Missing $cmd" 1>&2
            return 1
        }
    done

    BOLD='\033[1m'
    RED='\033[1;31m'
    RED0='\033[0;31m'
    GRN='\033[1;32m'
    GRN0='\033[0;32m'
    CYN='\033[1;36m'
    CYN0='\033[0;36m'
    YEL='\033[1;33m'
    YEL0='\033[0;33m'
    NC='\033[0m'
    NODE_CPU_T=50
    NODE_CPU_M=10
    NODE_MEM_T=80
    NODE_MEM_M=40
    VM_CPU_T=70
    VM_CPU_M=10
    VM_MEM_T=80
    VM_MEM_M=40
    echo -e "${BOLD}Reading ARP cache...${NC}"
    arp_map="/tmp/.arp_map"
    >"$arp_map"

    ensure_cmd arp net-tools

    arp -n | awk '/ether/ {print tolower($3), $1}' >"$arp_map"
    if command -v arp-scan >/dev/null 2>&1; then
        (
            arp -n | awk '/ether/ {print tolower($3), $1}'
            arp-scan -I "$(ip route | awk '/default/ {print $5; exit}')" --localnet 2>/dev/null | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print tolower($2), $1}'
        ) | awk '!a[$0]++' >"$arp_map" 2>/dev/null &
    fi
    echo -e "${BOLD}ARP cache loaded. Monitoring '$local_node'. Ctrl+C to exit.${NC}"
    echo -e "${BOLD}Reading VMs config...${NC}"
    trap 'echo -e "\n${BOLD}Stopped.${NC}"; rm -f "$arp_map"; return 0' INT TERM

    # 노드와 IP 정보를 한 번에 가져오기
    members_file="/etc/pve/.members"
    nodelist_count=$(jq '.nodelist | length' "$members_file" 2>/dev/null)

    if [[ $nodelist_count -gt 0 ]]; then
        # 클러스터 노드가 있는 경우
        while IFS=" " read -r node ip; do
            eval "node_${node}_ip=\"$ip\""
        done < <(jq -r '.nodelist | to_entries[] | "\(.key) \(.value.ip)"' "$members_file")
    else
        # 단독 노드일 경우
        node=$(jq -r '.nodename' "$members_file")
        ip=$(hostname -I | awk '{print $1}') # 첫 번째 IP만 사용
        eval "node_${node}_ip=\"$ip\""
    fi

    #while IFS=" " read node ip; do
    #    eval "node_${node}_ip=\"$ip\"";
    #done < <(jq -r '.nodelist | to_entries[] | "\(.key) \(.value.ip)"' /etc/pve/.members);

    while :; do
        now=$(date +%s)
        output=""
        output="$output\n${BOLD}Uptime ($local_node):${NC} $(uptime)\n"
        output="$output\n${BOLD}Nodes:${NC}"
        output="$output
Node          IP Address           Status     CPU(%)       Mem(GB/%)                Uptime
"
        output="$output----------------------------------------------------------------------------------------------\n"

        # pvesh 명령으로 노드 정보 한 번에 처리
        while IFS='|' read -r node status cpu mem maxmem up; do
            cpu=${cpu:-0}
            mem=${mem:-0}
            maxmem=${maxmem:-1}
            up=${up:-0}
            cpu_p=$(awk -v c="$cpu" 'BEGIN{printf "%.0f", c*100}')
            [ "$cpu_p" -ge $NODE_CPU_T ] && cpu_c="$RED" || {
                [ "$cpu_p" -ge $NODE_CPU_M ] && cpu_c="$YEL" || cpu_c="$NC"
            }
            mem_gb=$(awk -v m="$mem" 'BEGIN{printf "%.1f", m/1024/1024/1024}')
            max_gb=$(awk -v m="$maxmem" 'BEGIN{printf "%.1f", m/1024/1024/1024}')
            mem_p=$(awk -v m="$mem" -v max="$maxmem" 'BEGIN{printf "%.0f", m*100/max}')
            [ -n "$mem_p" ] && [ "$mem_p" -ge "$NODE_MEM_T" ] 2>/dev/null && mem_c="$RED" || {
                [ "$mem_p" -ge "$NODE_MEM_M" ] 2>/dev/null && mem_c="$YEL" || mem_c="$NC"
            }
            up_fmt=$(awk -v u="$up" 'BEGIN{d=int(u/86400); h=int((u%86400)/3600); m=int((u%3600)/60); printf "%dd %02dh%02dm", d,h,m}')
            node_ip_var="node_${node}_ip"
            node_ip="${!node_ip_var}"
            [ "$status" = "offline" ] && status="${RED}offline${NC}" || status="${GRN}online${NC}"
            [ "$up" -lt 86400 ] && up_fmt="${YEL}${up_fmt}${NC}"
            line=$(printf "%-13s %-20s %-10s %b%6s%%%b    %6s/%-6sGB  (%b%3s%%%b)    %s" "$node" "$node_ip" "$status" "$cpu_c" "$cpu_p" "$NC" "$mem_gb" "$max_gb" "$mem_c" "$mem_p" "$NC" "$up_fmt")
            output="$output$line\n"
        done < <(pvesh get /cluster/resources --output-format=json | jq -r '
            sort_by(.node) |
            map(select(.type=="node"))[] |
            "\(.node)|\(.status)|\(.cpu)|\(.mem)|\(.maxmem)|\(.uptime // 0)"
        ')

        output="$output\n${BOLD}VMs:${NC}\n"
        line=$(printf "%-8s %-12s %-7s %-27s %-20s %-12s %-20s %-25s %-20s %-15s" "VMID" "Node" "Type" "Name" "IP Address" "CPU" "Mem(MB/%)" "Disk(R/W MBs)" "Net(In/Out MBs)" "Uptime")
        output="$output$line\n"
        output="$output-----------------------------------------------------------------------------------------------------------------------------------------------------------\n"

        pvesh get /cluster/resources --output-format=json | jq -r '
            .[]
            | select((.type=="qemu" or .type=="lxc") and .status=="running")
            | "\(.vmid)|\(.node)|\(.type)|\(.name)|\(.cpu)|\(.mem)|\(.maxmem)|\(.diskread//0)|\(.diskwrite//0)|\(.netin//0)|\(.netout//0)|\(.uptime // 0)"
        ' >/tmp/.vm_data.$$

        while IFS='|' read id node vm_type name cpu mem maxmem d_r d_w n_in n_out vm_uptime; do
            cpu_p=$(awk -v c="$cpu" 'BEGIN{printf "%.0f", c*100}')
            [ "$cpu_p" -ge $VM_CPU_T ] && cpu_c="$RED" || {
                [ "$cpu_p" -ge $VM_CPU_M ] && cpu_c="$YEL" || cpu_c="$NC"
            }
            mem_mb=$(awk -v m="$mem" 'BEGIN{printf "%.0f", m/1024/1024}')
            max_mb=$(awk -v m="$maxmem" 'BEGIN{printf "%.0f", m/1024/1024}')
            mem_p=$(awk -v m="$mem" -v max="$maxmem" 'BEGIN{printf "%.0f", m*100/max}')
            [ "$mem_p" -ge $VM_MEM_T ] && mem_c="$RED" || {
                [ "$mem_p" -ge $VM_MEM_M ] && mem_c="$YEL" || mem_c="$NC"
            }
            vm_mac=$(pvesh get /nodes/$node/$vm_type/$id/config --noborder 2>/dev/null | sed -n 's/.*=\([0-9A-Fa-f:]\{17\}\).*/\1/p' | head -n1 | tr '[:upper:]' '[:lower:]')
            vm_ip="${RED}N/A${NC}"
            [ -n "$vm_mac" ] && vm_ip=$(awk -v mac="$vm_mac" '$1==mac {print $2}' "$arp_map")
            [ -z "$vm_ip" ] && vm_ip="N/A"
            eval "old_d_r=\${disk_r_$id:-$d_r}"
            eval "old_d_w=\${disk_w_$id:-$d_w}"
            eval "old_n_in=\${net_in_$id:-$n_in}"
            eval "old_n_out=\${net_out_$id:-$n_out}"
            eval "last_time=\${last_time_$id:-$now}"
            dt=$((now - last_time))
            [ $dt -le 0 ] && dt=1
            dr_spd=$(awk -v now="$d_r" -v old="$old_d_r" -v t="$dt" 'BEGIN{d=now-old; if(d<0)d=0; printf "%.1f", d/t/1024/1024}')
            dw_spd=$(awk -v now="$d_w" -v old="$old_d_w" -v t="$dt" 'BEGIN{d=now-old; if(d<0)d=0; printf "%.1f", d/t/1024/1024}')
            ni_spd=$(awk -v now="$n_in" -v old="$old_n_in" -v t="$dt" 'BEGIN{d=now-old; if(d<0)d=0; printf "%.1f", d/t/1024/1024}')
            no_spd=$(awk -v now="$n_out" -v old="$old_n_out" -v t="$dt" 'BEGIN{d=now-old; if(d<0)d=0; printf "%.1f", d/t/1024/1024}')
            eval "disk_r_$id=$d_r"
            eval "disk_w_$id=$d_w"
            eval "net_in_$id=$n_in"
            eval "net_out_$id=$n_out"
            eval "last_time_$id=$now"
            vm_uptime_fmt=$(awk -v u="$vm_uptime" 'BEGIN{d=int(u/86400); h=int((u%86400)/3600); m=int((u%3600)/60); printf "%dd %02dh%02dm", d,h,m}')
            line=$(printf "%-8s %-12s %-7s %-27s %-20s %b%6s%%%b   %6s/%-6s(%b%3s%%%b)     D:%-10s/%-10s   N:%-10s/%-10s   %s" "$id" "$node" "$vm_type" "${name:0:27}" "$vm_ip" "$cpu_c" "$cpu_p" "$NC" "$mem_mb" "$max_mb" "$mem_c""$mem_p" "$NC" "$dr_spd" "$dw_spd" "$ni_spd" "$no_spd" "$vm_uptime_fmt")
            output="$output$line\n"
        done </tmp/.vm_data.$$
        rm -f /tmp/.vm_data.$$
        find /tmp/ -name ".vm_data.*" -type f -mtime +1 -exec rm -f {} \;

        clear
        echo -e "$output"
        sleep "$interval"
    done
}

# explorer.sh
explorer() {
    [ $# -eq 0 ] && echo "Usage: explorer file1 [file2 ...]" && return 1

    open() {
        if command -v ranger &>/dev/null; then
            ranger "$1"
        else
            sh="$HOME/explorer.sh"
            # (2026-09-28) srt.byus.net 이 유일 배포처로 통일 / byus.net 은 예비 경로
            [ -f "$sh" ] || { curl -fsSL -m 10 http://srt.byus.net/explorer.sh -o "$sh" 2>/dev/null \
                || curl -fsSL -m 10 http://byus.net/explorer.sh -o "$sh" 2>/dev/null \
                || rm -f "$sh"; }
            [ -s "$sh" ] && chmod 755 "$sh"
            "$sh" "$1"
        fi
    }

    [ $# -eq 1 ] && open "$1" && return

    select f in "$@" "Cancel"; do
        [ "$f" = "Cancel" ] && break
        [ -n "$f" ] && open "$f" && break
    done
}

exp() { explorer "$@"; }

pingcheck() { ping -c1 -W2 168.126.63.1 &>/dev/null && echo "y" || echo "n"; }
pingtest() {
    echo
    [ "$1" ] && ping -c3 $1 || ping -c3 168.126.63.1
}
pingtesta() {
    echo
    [ "$1" ] && ping $1 || ping 168.126.63.1
}
pingtestg() {
    echo
    ping $gateway
}
pp() { pingtest "$@"; }
ppa() { pingtesta "$@"; }
ppp() { pingtesta "$@"; }
ppg() { pingtestg "$@"; }

reconnect_down_veth_interfaces() {
    # 네트워크 재시작시 네트워크가 올라오지 않는 경우 발생
    # 모든 veth 인터페이스에 대해 반복
    for iface in $(ifconfig -a | grep veth | awk -F: '{print $1}'); do
        # 해당 인터페이스가 어떤 VM 또는 LXC와 연결되어 있는지 확인
        id=$(echo $iface | sed 's/veth\([0-9]*\)i0/\1/')

        config_path=$(find /etc/pve/nodes/ -maxdepth 3 -name ${id}.conf)

        if [ ! -f "$config_path" ]; then
            echo "Configuration file does not exist for interface: $iface"
            continue
        fi

        # 해당 VM이나 LXC가 어떤 브리지를 사용해야 하는지 확인
        bridge=$(cat ${config_path} | grep '^net' | sed 's/^.*bridge=\([^,]*\).*$/\1/')

        # 해당 인터페이스가 이미 브리지에 연결되어 있는지 확인
        # if ! ip link show $iface | grep -q "master $bridge"; then
        if ! brctl show $bridge | grep -q $iface; then
            # 해당 인터페이스를 적절한 브리지에 연결
            brctl addif $bridge $iface
            echo "Interface ${iface} of instance ${id} has been added to the bridge ${bridge}."
        fi
    done
}

rrnet() {
    [ ! "$1" == "yes" ] && return

    if [ ! -f /etc/network/interfaces ]; then
        echo "Error: /etc/network/interfaces does not exist."
        return 1
    fi

    backup_files=("/etc/network/interfaces.backup" "/etc/network/interfaces.1.bak" "/etc/network/interfaces.2.bak" "/etc/network/interfaces.3.bak")
    files=("/etc/network/interfaces" "${backup_files[@]}")

    for file in "${files[@]}"; do
        if [ -f $file ]; then
            cp $file /etc/network/interfaces 2>/dev/null
            #systemctl restart networking.service
            which ifreload && ifreload -a || systemctl restart networking.service

            if ping -c 4 8.8.8.8 >/dev/null; then
                echo "Network configuration from $file is successful."
                reconnect_down_veth_interfaces
                return 0
            else
                echo "Ping test failed for configuration from $file."
                [ "$file" == "/etc/network/interfaces" ] && cp /etc/network/interfaces /etc/network/interfaces.err."$(date "+%Y%m%d_%H%M%S")"

            fi

        elif [ "$file" != "/etc/network/interfaces" ]; then
            echo "Backup file $file does not exist."
        fi
    done

    echo "All configurations failed the ping test."
    return 1
}

dockersvcorg() { able docker && dockerps=$(docker ps | awknr2 2>/dev/null) && [ "${dockerps}" ] && echo "$dockerps" | grep "0.0.0.0" | awk '{split($2, arr, "/"); printf arr[1] " "}; {while(match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/)) {ip_port = substr($0, RSTART, RLENGTH); printf ip_port " "; $0 = substr($0, RSTART+RLENGTH)}; {print ""} ;  }'; }

dockersvc() {
    local output
    output="$(dockersvcorg)"
    [ "$output" ] && while read -r line; do
        name=$(echo $line | awk '{print $1}')
        ip_port=$(echo $line | awk '{print $2}')
        ip_port2=$(echo $line | awk '{print $3}')
        updated_line="$name -> ${localip1}:${ip_port##*:} ${publicip}:${ip_port##*:} $([ "$publicip" == "$(hostname -i)" ] && echo "$(hostname):${ip_port##*:}")"
        [ -n "$ip_port2" ] && updated_line="$updated_line\n$name -> ${localip1}:${ip_port2##*:} ${publicip}:${ip_port2##*:} $([ "$publicip" == "$(hostname -i)" ] && echo "$(hostname):${ip_port2##*:}")"
        result="${result}${updated_line}\n"
    done < <(echo "$output")
    echo -e "$result" | cip | chost | column -t
}

# podman 은 daemon 이 없어 docker 와 조회 명령이 다르다 (컨테이너 이름 + 공개 포트 -> 공인IP:포트 목록)
podmansvcorg() { able podman && podman ps --format "{{.Names}} {{.Ports}}" 2>/dev/null | awk '{ n=$1 ; $1="" ; if ($0 ~ /0\.0\.0\.0/) { printf "%s ", n ; while (match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/)) { printf "%s ", substr($0, RSTART, RLENGTH) ; $0 = substr($0, RSTART+RLENGTH) } ; print "" } }'; }

podmansvc() {
    local output result
    result=""
    output="$(podmansvcorg)"
    [ "$output" ] && while read -r line; do
        name=$(echo $line | awk '{print $1}')
        ip_port=$(echo $line | awk '{print $2}')
        ip_port2=$(echo $line | awk '{print $3}')
        updated_line="$name -> ${localip1}:${ip_port##*:} ${publicip}:${ip_port##*:} $([ "$publicip" == "$(hostname -i)" ] && echo "$(hostname):${ip_port##*:}")"
        [ -n "$ip_port2" ] && updated_line="$updated_line\n$name -> ${localip1}:${ip_port2##*:} ${publicip}:${ip_port2##*:} $([ "$publicip" == "$(hostname -i)" ] && echo "$(hostname):${ip_port2##*:}")"
        result="${result}${updated_line}\n"
    done < <(echo "$output")
    echo -e "$result" | cip | chost | column -t
}

# 각열의 필드길이를 제한 w|maxl 5 5 5 5 // 한줄폭을 넘어가는 데이터가 많을경우, 적당히 컷 필요없는 필드는 0으로 설정
maxl() {
    # Bash 2 호환: local arr=(...) 금지 -> 선언/대입 분리
    local args
    args=("$@")
    awk -v limits="${args[*]}" '{n = split(limits, limit_arr, " "); for (i = 1; i <= n; i++) { if (length($(i)) > limit_arr[i]) { $(i) = substr($(i), 1, limit_arr[i]) } } print $0 }'
}

incremental_backup() {
    local backup_file="$1"
    local custom_prefix="$2"

    local backup_dir
    backup_dir=$(dirname "$backup_file")
    local backup_timestamp
    backup_timestamp=$(date -r "$backup_file" +%s)

    local backup_folder
    backup_folder=$(tar tvzf $backup_file | head -n1 | awk '{print $NF}')

    # 조건에 따라 prefix를 설정합니다.
    local prefix
    prefix=$(echo "${backup_folder}" | awk -v prefix="$custom_prefix" -F/ '{if (NF > 2) {print "/"} else {if (length(prefix) > 0) {print prefix} else {printf "/%s", $2}}}')

    cd "$prefix" || return
    find "${backup_folder}/" -type f -newermt @$backup_timestamp >"$backup_dir/new_files.txt"

    local base_backup
    base_backup="${backup_file%.*}"
    local incremental_backup
    incremental_backup="${base_backup}_incremental_$(date +%Y-%m-%d-%H-%M-%S).tar.gz"

    tar -czvf "$incremental_backup" -C "$prefix" -T "$backup_dir/new_files.txt"

    rm "$backup_dir/new_files.txt"
}

# 기존 백업 파일을 인수로 하여 업데이트된 파일만 추가로 백업 incremental backup
# $1:backupfile.tgz [$2:path_prefix]
ibackup() {
    local backup_file
    backup_file="$1"
    local backup_filepath
    backup_filepath="$(readlinkf $1)"
    local custom_prefix="$2"
    local backup_dir
    backup_dir=$(dirname "$backup_file")
    local backup_folder
    backup_folder=$(tar tvzf $backup_file | head -n1 | awk '{print $NF}')
    # var/lib/mysql/ or account/ or root/ .. account 는 prefix 가 필요함

    # 압축파일이 경로형태면 /, 압축파일이 폴더하나면 $custom_prefix,
    local prefix
    prefix=$(echo "${backup_folder}" | awk -v prefix="$custom_prefix" -F/ '{if (NF > 2) {print "/"} else {if (length(prefix) > 0) {print prefix} else {print "/" }}}')

    echo "prefix $prefix backup_folder $backup_folder "

    if [ -d "${prefix}${backup_folder}" ]; then
        cd "$prefix" || return
        find "${prefix}${backup_folder}" -type f -newer "$backup_filepath" >"$backup_dir/new_files.txt"
        tar -czvf "${backup_file}.update.$(date +%Y%m%d.%H%M%S).tgz" -C "$backup_dir" -T "$backup_dir/new_files.txt"
    fi
}

# ifcfg-ethx 파일이 없어 생성해야 할 경우
ifcfgset() {
    if ! command -v ifconfig >/dev/null 2>&1 && ! command -v ip >/dev/null 2>&1; then
        echo "Error: neither ifconfig nor ip command found!" >&2
        return 1
    fi

    # Get all ethernet interfaces
    INTERFACES=""
    if command -v ifconfig >/dev/null 2>&1; then
        INTERFACES=$(ifconfig -a | grep HWaddr | awk '{print $1}')
    fi
    [ ! "$INTERFACES" ] && INTERFACES="$(ip link show 2>/dev/null | awk -F ': ' '/^[0-9]+:/ {gsub(/:$/, "", $2); sub(/@.*/, "", $2); if ($2 != "lo") print $2}')"

    for INTERFACE in $INTERFACES; do
        # Check if the configuration file already exists
        if [ -e /etc/sysconfig/network-scripts/ifcfg-$INTERFACE ]; then
            read -p "Configuration file for $INTERFACE already exists. Do you want to delete and reconfigure it? (y/n): " REPLY

            if [ "$REPLY" != "Y" ] && [ "$REPLY" != "y" ]; then
                echo "Skipping configuration for $INTERFACE."
                continue
            fi

            mv -f /etc/sysconfig/network-scripts/ifcfg-$INTERFACE /etc/sysconfig/network-scripts/ifcfg-$INTERFACE.bak
            ls -al /etc/sysconfig/network-scripts/
            echo
        fi

        # Extract HWADDR and IPADDR (ifconfig or ip fallback, old grep 2.4.x compatible)
        HWADDR=""
        IPADDR=""
        if command -v ifconfig >/dev/null 2>&1; then
            OUTPUT=$(ifconfig "$INTERFACE" 2>/dev/null)
            HWADDR=$(echo "$OUTPUT" | awk 'toupper($0) ~ /HWADDR / {for(i=1;i<=NF;i++) if(toupper($i)=="HWADDR"){print $(i+1); exit}}')
            [ ! "$HWADDR" ] && HWADDR=$(echo "$OUTPUT" | awk 'tolower($0) ~ /ether / {for(i=1;i<=NF;i++) if(tolower($i)=="ether"){print $(i+1); exit}}')
            IPADDR=$(echo "$OUTPUT" | awk '/inet addr:/ {for(i=1;i<=NF;i++) if($i ~ /^addr:/){sub(/^addr:/,"",$i); print $i; exit}}')
            [ ! "$IPADDR" ] && IPADDR=$(echo "$OUTPUT" | awk '/inet / {for(i=1;i<=NF;i++) if($i=="inet"){sub(/\/.*/,"",$(i+1)); print $(i+1); exit}}')
        fi
        if [ -z "$HWADDR" ] && [ -r "/sys/class/net/$INTERFACE/address" ]; then
            HWADDR=$(cat "/sys/class/net/$INTERFACE/address" 2>/dev/null)
        fi
        if [ -z "$IPADDR" ] && command -v ip >/dev/null 2>&1; then
            IPADDR=$(ip -o -4 addr show dev "$INTERFACE" 2>/dev/null | awk '{sub(/\/.*/,"",$4); print $4; exit}')
        fi
        GATEWAY="${IPADDR%.*}.1"

        # If IP address is not set, ask for it and set netmask and broadcast address to typical values
        read -p "Enter the IP address for $INTERFACE (or type dhcp, default: ${IPADDR:-none}): " INPUT_IPADDR

        if [ -z "$INPUT_IPADDR" ]; then
            INPUT_IPADDR="$IPADDR"
        fi
        if [ -z "$INPUT_IPADDR" ]; then
            echo "Error: IP address is empty. Skipping $INTERFACE."
            continue
        fi

        if [ "$INPUT_IPADDR" == "dhcp" ]; then
            BOOTPROTO="dhcp"
            NETMASK=""
            BROADCAST=""
        else
            BOOTPROTO="static"
            NETMASK="255.255.255.0"
            GATEWAY="$(echo $INPUT_IPADDR | cut -d '.' -f 1-3).1"
            BROADCAST="$(echo $INPUT_IPADDR | cut -d '.' -f 1-3).255"
        fi

        IPADDR=$INPUT_IPADDR

        # Create ifcfg file for this interface.
        cat >/etc/sysconfig/network-scripts/ifcfg-$INTERFACE <<EOF
DEVICE="$INTERFACE"
BOOTPROTO="$BOOTPROTO"
HWADDR="$HWADDR"
EOF

        if [ "$BOOTPROTO" == "static" ]; then
            cat >>/etc/sysconfig/network-scripts/ifcfg-$INTERFACE <<EOF
IPADDR="$IPADDR"
GATEWAY="$GATEWAY"
NETMASK="$NETMASK"
BROADCAST="$BROADCAST"
EOF

        fi

        cat >>/etc/sysconfig/network-scripts/ifcfg-$INTERFACE <<EOF
ONBOOT="yes"
TYPE="Ethernet"
EOF
        echo "/etc/sysconfig/network-scripts/ifcfg-$INTERFACE -----------"
        cat /etc/sysconfig/network-scripts/ifcfg-$INTERFACE
        echo
    done

    [ "$INTERFACES" ] && echo "Files created successfully." || echo "INTERFACES not found"
}

domchg() {
    local id="$1" olddomain="$2" newdomain="$3"
    local homedir oldconf newconf userinfo tmp oldre

    # 인수 확인
    if [ -z "$id" ] || [ -z "$olddomain" ] || [ -z "$newdomain" ]; then
        echo "❌ 사용법: domchg <id> <old-domain> <new-domain>"
        echo "예시: domchg myuser oldsite.com newsite.com"
        return 1
    fi

    # [정리] sed 정규식에서 도메인의 '.' 는 메타문자이므로 반드시 이스케이프한다.
    oldre="$(printf '%s\n' "$olddomain" | sed 's/\./\\./g')"

    # 기본 경로 설정
    homedir="$(getent passwd "$id" | cut -d: -f6)"
    [ -z "$homedir" ] && echo "❌ 사용자 $id의 홈디렉토리를 찾을 수 없습니다." && return 1

    oldconf="/etc/httpd/conf.d/$olddomain.conf"
    newconf="/etc/httpd/conf.d/$newdomain.conf"
    userinfo="$homedir/.userinfo"

    ### 1. Apache conf 변경
    if [ -f "$oldconf" ]; then
        tmp="$(mktemp)"
        sed "s/$oldre/$newdomain/g" "$oldconf" >"$tmp"

        echo "--- Apache conf 변경 전후 diff ($oldconf → $newconf) ---"
        cdiff "$oldconf" "$tmp"
        readxy "[Apache conf 변경을 적용할까요?]" && {
            mv "$tmp" "$newconf"
            rm -f "$oldconf"
            echo "✓ 변경 완료: $newconf"
        } || rm -f "$tmp"
    fi

    ### 2. .userinfo 업데이트
    if [ -f "$userinfo" ]; then
        echo "--- .userinfo 도메인 기록 ---"
        echo "[마지막 도메인] $(grep DOMAIN= "$userinfo" | tail -n1)"
        echo "[추가 예정] DOMAIN=$newdomain"
        readxy "[.userinfo에 이 도메인 정보를 추가할까요?]" && {
            echo "DOMAIN=$newdomain" >>"$userinfo"
            echo "✓ .userinfo 업데이트 완료"
        }
    fi

    ### 3. certbot 재발급 명령 미리보기
    # [규칙] 일반 도메인만 이 경로로 처리한다. 와일드카드/acme.sh/프록시/유료 ZIP 은 go.env [ssl] 센터 사용.
    echo "--- Certbot SSL 재발급 명령 미리보기 (일반 도메인 / DNS-01·와일드카드는 [ssl] 센터) ---"
    echo "certbot --apache -d $newdomain -d www.$newdomain"
    readxy "[Certbot을 실행할까요?]" && {
        certbot --apache -d "$newdomain" -d "www.$newdomain"
    }

    ### 4. wp-config.php 내 URL 변경
    local wpconfig="$homedir/public_html/wp-config.php"
    if [ -f "$wpconfig" ]; then
        tmp="$(mktemp)"
        sed "s|http://$oldre|http://$newdomain|g" "$wpconfig" >"$tmp"
        echo "--- wp-config.php 변경 전후 diff ---"
        cdiff "$wpconfig" "$tmp"
        readxy "[wp-config.php를 업데이트할까요?]" && {
            mv "$tmp" "$wpconfig"
            echo "✓ wp-config.php 변경 완료"
        } || rm -f "$tmp"
    fi

    ### 5. 리디렉션 conf (선택 사항)
    local redirconf="/etc/httpd/conf.d/${olddomain}_redirect.conf"
    if [ -f "$redirconf" ]; then
        echo "--- 리디렉션 conf 존재: $redirconf ---"
        readxy "[기존 리디렉션 conf를 $newdomain용으로 복사할까요?]" && {
            cp "$redirconf" "/etc/httpd/conf.d/${newdomain}_redirect.conf"
            sed -i "s/$oldre/$newdomain/g" "/etc/httpd/conf.d/${newdomain}_redirect.conf"
            echo "✓ 리디렉션 conf 복사 완료"
        }
    fi

    ### 6. 기타 도메인명 기반 파일/디렉토리 (옵션)
    local basedir
    for basedir in "$homedir/public_html/$olddomain" "$homedir/public_html/${olddomain}_logs"; do
        if [ -e "$basedir" ]; then
            newpath="${basedir/$olddomain/$newdomain}"
            echo "--- 디렉토리 이름 변경: $basedir → $newpath ---"
            readxy "[이 디렉토리를 변경할까요?]" && mv "$basedir" "$newpath"
        fi
    done

    echo "--- 완료: '$olddomain' → '$newdomain' 에 대한 모든 변경이 처리되었습니다 ---"
}

##############################################################################################################
##############################################################################################################
############## template copy/view func
##############################################################################################################
##############################################################################################################

template_edit() {
    [ $# -eq 0 ] && echo "Usage: template_edit file1 [file2 ...]" && return 1

    open() {
        [ -n "$1" ] && conff "$1)" || echo "'$1' not found"
    }

    [ $# -eq 1 ] && open "$1" && return

    select f in "$@" "Cancel"; do
        [ "$f" = "Cancel" ] && break
        [ -n "$f" ] && open "$f" && break
    done
}
template_view() {
    [ $# -eq 0 ] && echo "Usage: template_view file1 [file2 ...]" && return 1

    # 인자가 하나일 경우 바로 처리
    [ $# -eq 1 ] && dline && template_copy "$1" /dev/stdout | cpipe && return

    # 여러 개일 경우 선택지 제공
    select f in "$@" "Cancel"; do
        [ "$f" = "Cancel" ] && break
        [ -n "$f" ] && dline && template_copy "$f" /dev/stdout | cpipe && break
    done
}

template_view_source() { template_copy "$1" /dev/stdout; }
template_insert() { template_view_source "$1" | tee -a "$2" >/dev/null; }

# [정리] SSL 인증서 템플릿 전용 함수 — go.env [ssl]/[sslw]/[sslwr] 센터가 쓰는 DNS-01 hook/cleanup/renew 스크립트 생성.
#        기존 template_copy() 의 거대 case 에서 SSL 5종만 분리해 독립 관리한다 (동작 동일).
#        호출 규약: template_copy <템플릿명> <출력파일> 경로를 그대로 유지한다.
_ssl_template_copy() {
    local template=$1 file_path=$2

    case $template in

    hook.sh)
        cat >"$file_path" <<EOF
#!/bin/bash
echo "[HOOK] 인증용 TXT 레코드 추가 중"
export ssldomain="\$CERTBOT_DOMAIN"
export txt_value="\$CERTBOT_VALIDATION"
export zone_file="$zone_file"
export txt_record="_acme-challenge.${ssldomain}. IN TXT \"\$txt_value\""

echo "\$txt_record" >> "\$zone_file"
rndc reload "$ssldomain"
EOF

        ;;

    hookremote.sh)
        cat >"$file_path" <<EOF
# 사용자가 사전에 export 해야 하는 값들:
#ssldomain="example.com"
#remote_ns_host="byus.net"
#zone_file="/mnt/byus/var/named/${ssldomain}.zone"

#!/bin/bash

# 고정값: Certbot이 채워주는 변수
DOMAIN="\$CERTBOT_DOMAIN"
VALUE="\$CERTBOT_VALIDATION"
FQDN="_acme-challenge.\$DOMAIN."
RECORD="\$FQDN IN TXT \"\$VALUE\""
EXPECTED="\"\$VALUE\""

# 하드코딩된 설정
REMOTE_NS_HOST="${remote_ns_host}"
ZONE_FILE="${zone_file}"

echo "[HOOK] 인증 도메인: \$DOMAIN"
echo "[HOOK] 추가할 TXT 레코드: \$RECORD"
echo "[HOOK] 존 파일: \$ZONE_FILE"

echo "\$RECORD" >> "\$ZONE_FILE" || {
  echo "[ERROR] ❌ 레코드 추가 실패!"; exit 1;
}
echo "[OK] ✅ 존 파일에 레코드 추가됨."

ssh "\$REMOTE_NS_HOST" "rndc reload \$DOMAIN" || {
  echo "[WARN] ⚠️ 원격 리로드 실패 (진행은 계속)";
}

echo "[INFO] DNS 전파 확인 중..."

ns=\$(dig NS "\$DOMAIN." +short | head -n1)
[ -z "\$ns" ] && dig_target="" || dig_target="@\$ns"

for i in \$(seq 1 12); do
  result=\$(dig \$dig_target TXT "\$FQDN" +short)
  echo "\$result" | grep -Fxq "\$EXPECTED" && {
    echo "[OK] ✅ DNS 전파 완료됨"; exit 0;
  }
  echo "[WAIT] ⏳ 전파 대기 중 (\$i/12)"
  sleep 10
done

echo "[FAIL] ❌ 최대 대기 시간 초과 - Certbot 검증 실패 가능"
exit 1
EOF

        ;;

    cleanup.sh)
        cat >"$file_path" <<EOF
#!/bin/bash

echo "[CLEANUP] 인증용 TXT 레코드 제거 중..."

export ssldomain="\$CERTBOT_DOMAIN"
export txt_value="\$CERTBOT_VALIDATION"
export zone_file="$zone_file"
export txt_record="_acme-challenge.${ssldomain}. IN TXT \"\$txt_value\""

# 레코드 제거 (해당 줄 삭제)
sed -i "/_acme-challenge.*IN TXT.*\$txt_value/d" "\$zone_file"

# BIND 설정 재적용
rndc reload "$ssldomain"

echo "[CLEANUP] 완료: \$txt_record 삭제됨"
EOF

        ;;

    renew.sh)
        cat >"$file_path" <<EOF
#!/bin/bash
# [규칙] go.env [sslw] DNS-01 와일드카드 갱신 전용 — CERTBOT_* 는 certbot 이 훅에 주입하므로 여기서 export 하지 않는다.

certbot renew \
  --manual-auth-hook "/etc/letsencrypt/scripts/hook-${ssldomain}.sh" \
  --manual-cleanup-hook "/etc/letsencrypt/scripts/cleanup-${ssldomain}.sh" \
  --preferred-challenges dns \
  --agree-tos \
  --manual \
  --deploy-hook "systemctl reload httpd 2>/dev/null || systemctl reload apache2" \
  --cert-name $certpath
EOF

        ;;

    hook-sslwr.sh)
        cat >"$file_path" <<EOF
#!/bin/bash
# Certbot DNS-01 인증용 hook for ${ssldomain}
ZONEDIR="${zone_path:-/mnt/remote_name}"
ZONEFILE="$zone_file"
TMPFILE="\${ZONEFILE}.tmp"
TMPFLAG="\$ZONEDIR/reload.flag"
PROPAGATION_WAIT_TIME=5
MAX_RETRIES=20

check_mount() {
  if ! mountpoint -q "\$ZONEDIR"; then
    echo "[✖] 오류: Zone 디렉토리(\$ZONEDIR) 마운트 안됨! " >&2
    exit 1
  fi
  # 간단 쓰기 테스트
  if ! touch "\$ZONEDIR/.tmp_write_test.\$\$" 2>/dev/null; then
      echo "[✖] 오류: Zone 디렉토리(\$ZONEDIR) 쓰기 권한 없음! ✋" >&2
      exit 1
  else
      rm -f "\$ZONEDIR/.tmp_write_test.\$\$"
  fi
  # echo "[✔] 마운트/쓰기 권한 확인 완료." # 필요하면 주석 해제
}
add_record() {
  check_mount
  # 미삭제분 삭제
   s=\$(awk '/SOA/{found=1} found && /[0-9]{10}/ {match(\$0, /[0-9]{10}/, m); print m[0]; exit}' "\$ZONEFILE") &&
   [ -n "\$s" ] || { echo "❌ 시리얼을 찾지 못했습니다."; false; } &&
   n=\$((s+1)) &&
   sed -e "/_acme-challenge\.\${CERTBOT_DOMAIN//./\\.}\.\(\s\+[0-9]\+\)\?\s\+IN\s\+TXT/d" \
       -e "s/\b\$s\b/\$n/" "\$ZONEFILE" > "\$TMPFILE" &&
   mv "\$ZONEFILE" "\$ZONEFILE.org" &&
   mv "\$TMPFILE" "\$ZONEFILE"

  # 추가 TTL 300 강제조정
  echo "_acme-challenge.\${CERTBOT_DOMAIN}. 300 IN TXT \"\${CERTBOT_VALIDATION}\"" >> "\$ZONEFILE"
  # SOA serial 자동 갱신 (YYYYMMDDHH)
  # sed -i '/SOA/,/)/ s/[0-9]\{10\}/'"\$(date +%Y%m%d%H)"'/' "\$ZONEFILE"
  # sed '/SOA/,/)/ s/[0-9]\{10\}/'"\$(date +%Y%m%d%H)"'/' "\$ZONEFILE" > "\$TMPFILE" && mv "\$TMPFILE" "\$ZONEFILE"
  echo "trigger" > "\$TMPFLAG"
  echo "[✔] TXT 레코드 추가됨: _acme-challenge.\${CERTBOT_DOMAIN}"
}

remove_record() {
  check_mount
   s=\$(awk '/SOA/{found=1} found && /[0-9]{10}/ {match(\$0, /[0-9]{10}/, m); print m[0]; exit}' "\$ZONEFILE") &&
   [ -n "\$s" ] || { echo "❌ 시리얼을 찾지 못했습니다."; false; } &&
   n=\$((s+1)) &&
   sed -e "/_acme-challenge\.\${CERTBOT_DOMAIN//./\\.}\.\(\s\+[0-9]\+\)\?\s\+IN\s\+TXT/d" \
       -e "s/\b\$s\b/\$n/" "\$ZONEFILE" > "\$TMPFILE" &&
   mv "\$ZONEFILE" "\$ZONEFILE.org" &&
   mv "\$TMPFILE" "\$ZONEFILE"
  echo "[✔] TXT 레코드 제거됨"
}

wait_propagation() {
  for i in \$(seq 1 "\$MAX_RETRIES"); do
    dig +short TXT _acme-challenge."\$CERTBOT_DOMAIN" @\$sshrhost | grep -q "\$CERTBOT_VALIDATION" && {
      echo "[✔] DNS 전파 확인됨"; return 0;
    }
    echo "[\$i/\$MAX_RETRIES] DNS 전파 대기 중... (\${PROPAGATION_WAIT_TIME}초 후 재시도)"
    sleep "\$PROPAGATION_WAIT_TIME"
  done
  echo "[✖] 전파 실패 – 수동 확인 필요"; return 1
}

case "\$1" in
  auth-hook)
    add_record && wait_propagation ;;
  cleanup-hook)
    remove_record ;;
esac
EOF

        ;;

    esac
}

# ==============================================================================
# Proxmox Cluster Merge & VMID Auto-Remap Toolkit (pve_merge_*)
#   1) pve_merge_setup        : A(Target) / B(Joining) 호스트 등록 & SSH 확인
#   2) pve_merge_check        : 충돌(호스트명/클러스터/VMID/스토리지/스냅샷) 일괄 점검 (읽기전용)
#   3) pve_merge_plan         : B 노드 VMID 자동 변경 계획 검토 (Dry-Run, 읽기전용)
#   4) pve_merge_apply_vmid   : B 노드 VMID 일괄 자동 변경 실행 (실제 변경)
#   5) pve_merge_join_dryrun  : 클러스터 합치기 사전 검토 (Dry-Run, 읽기전용)
#   6) pve_merge_join         : conf 임시이동 -> 클러스터 조인 -> conf/스토리지 원복
#   7) pve_merge_restore_conf : 백업된 conf 비상 원복
# ==============================================================================
PVE_MERGE_STATE="${HOME:-/root}/.pve_merge.env"
PVE_MERGE_PLAN_FILE="/tmp/pve_merge_plan.tsv"

_pvem_load_state() {
    PVE_MERGE_A=""
    PVE_MERGE_B=""
    PVE_MERGE_OFFSET="200"
    PVE_MERGE_SSH_USER="root"
    [ -f "$PVE_MERGE_STATE" ] && . "$PVE_MERGE_STATE"
}

_pvem_require_state() {
    _pvem_load_state
    if [ -z "$PVE_MERGE_A" ] || [ -z "$PVE_MERGE_B" ]; then
        RED1; echo "[!] A/B 호스트가 등록되지 않았습니다. 먼저 1단계(pve_merge_setup)를 실행하세요."; NC
        return 1
    fi
    return 0
}

_pvem_is_local() {
    local target="$1"
    [ "$target" = "local" ] || [ "$target" = "localhost" ] || [ "$target" = "127.0.0.1" ] && return 0
    local h_short h_fqdn h_ips ip
    h_short="$(hostname -s 2>/dev/null)"
    h_fqdn="$(hostname -f 2>/dev/null)"
    h_ips="$(hostname -I 2>/dev/null)"
    [ -n "$h_short" ] && [ "$target" = "$h_short" ] && return 0
    [ -n "$h_fqdn" ] && [ "$target" = "$h_fqdn" ] && return 0
    for ip in $h_ips; do
        [ "$target" = "$ip" ] && return 0
    done
    return 1
}

_pvem_run() {
    local host="$1"
    shift
    local cmd="$*"
    if _pvem_is_local "$host"; then
        bash -c "$cmd"
    else
        ssh -n -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new \
            -o ControlMaster=no \
            "${PVE_MERGE_SSH_USER:-root}@${host}" "$cmd"
    fi
}

_pvem_check_ssh() {
    local label="$1" host="$2" out
    if _pvem_is_local "$host"; then
        return 0
    fi
    out="$(ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new \
        "${PVE_MERGE_SSH_USER:-root}@${host}" "echo OK" 2>&1)"
    if [ "$out" != "OK" ]; then
        RED1; echo "[FAIL] ${label} 호스트(${host}) SSH 키 인증 접속 실패!"; NC
        echo "  원인: $out"
        YEL1; echo "  해결: ssh-copy-id ${PVE_MERGE_SSH_USER:-root}@${host} 로 키를 등록하거나, 양쪽 키가 있는 서버에서 실행하세요."; NC
        return 1
    fi
    return 0
}

_pvem_require_ready() {
    _pvem_require_state || return 1
    _pvem_check_ssh "A" "$PVE_MERGE_A" || return 1
    _pvem_check_ssh "B" "$PVE_MERGE_B" || return 1
    return 0
}

_pvem_run_tty() {
    local host="$1"
    shift
    local cmd="$*"
    if _pvem_is_local "$host"; then
        bash -c "$cmd"
    else
        ssh -t -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new \
            "${PVE_MERGE_SSH_USER:-root}@${host}" "$cmd"
    fi
}

_pvem_list_guests() {
    # Output format: VMID|TYPE|STATUS|NAME|CONF_PATH
    local host="$1"
    _pvem_run "$host" '
        for d in /etc/pve/qemu-server /etc/pve/lxc; do
            [ -d "$d" ] || continue
            t="qemu"
            [ "$d" = "/etc/pve/lxc" ] && t="lxc"
            for f in "$d"/*.conf; do
                [ -e "$f" ] || continue
                b="$(basename "$f")"
                case "$b" in
                    *[!0-9]*.conf) continue ;;
                esac
                id="${b%.conf}"
                case "$id" in ""|*[!0-9]*) continue ;; esac
                if [ "$t" = "qemu" ]; then
                    name="$(awk -F": *" "/^name:/{print \$2; exit}" "$f" 2>/dev/null)"
                    st="$(qm status "$id" 2>/dev/null | awk "{print \$2}")"
                else
                    name="$(awk -F": *" "/^hostname:/{print \$2; exit}" "$f" 2>/dev/null)"
                    st="$(pct status "$id" 2>/dev/null | awk "{print \$2}")"
                fi
                [ -z "$name" ] && name="-"
                [ -z "$st" ] && st="unknown"
                printf "%s|%s|%s|%s|%s\n" "$id" "$t" "$st" "$name" "$f"
            done
        done | sort -t"|" -k1,1n
    '
}

_pvem_list_nonstandard_confs() {
    local host="$1"
    _pvem_run "$host" '
        for d in /etc/pve/qemu-server /etc/pve/lxc; do
            [ -d "$d" ] || continue
            for f in "$d"/*; do
                [ -e "$f" ] || continue
                b="$(basename "$f")"
                if ! printf "%s\n" "$b" | grep -Eq "^[0-9]+\.conf$"; then
                    printf "%s\n" "$f"
                fi
            done
        done
    '
}

_pvem_parse_storages() {
    # Output format: NAME|TYPE|DETAIL|NODES
    local host="$1"
    _pvem_run "$host" '
        [ -f /etc/pve/storage.cfg ] || exit 0
        awk "
            /^[a-zA-Z0-9_-]+:[ \t]+/ {
                if (name != \"\") print name \"|\" type \"|\" detail \"|\" nodes
                split(\$0, a, \":[ \t]+\")
                type = a[1]; name = a[2]; detail = \"\"; nodes = \"ALL\"
                next
            }
            /^[ \t]+path[ \t]+/ { detail = detail (detail?\",\":\"\") \"path=\" \$2 }
            /^[ \t]+vgname[ \t]+/ { detail = detail (detail?\",\":\"\") \"vg=\" \$2 }
            /^[ \t]+thinpool[ \t]+/ { detail = detail (detail?\",\":\"\") \"pool=\" \$2 }
            /^[ \t]+pool[ \t]+/ { detail = detail (detail?\",\":\"\") \"zpool=\" \$2 }
            /^[ \t]+nodes[ \t]+/ { nodes = \$2 }
            END { if (name != \"\") print name \"|\" type \"|\" detail \"|\" nodes }
        " /etc/pve/storage.cfg
    '
}

# 1단계: A/B 호스트 등록 및 SSH 연결 테스트
pve_merge_setup() {
    _pvem_load_state
    local arg_a="$1" arg_b="$2" arg_off="$3"
    local in_a in_b in_off

    CYN1; echo "======================================================================"
    echo " [1단계] Proxmox 클러스터 합치기 - A(대상) / B(합류) 호스트 등록"
    echo "======================================================================"; NC

    if [ -n "$arg_a" ] && [ -n "$arg_b" ]; then
        PVE_MERGE_A="$arg_a"
        PVE_MERGE_B="$arg_b"
        [ -n "$arg_off" ] && PVE_MERGE_OFFSET="$arg_off"
    else
        printf "  A 호스트 (유지할 마스터/클러스터 노드) [%s]: " "${PVE_MERGE_A:-예: pve1.example.com}"
        read -r in_a </dev/tty
        [ -n "$in_a" ] && PVE_MERGE_A="$in_a"

        printf "  B 호스트 (합류할 노드 - VMID 변경 대상) [%s]: " "${PVE_MERGE_B:-예: pve2.example.com}"
        read -r in_b </dev/tty
        [ -n "$in_b" ] && PVE_MERGE_B="$in_b"

        printf "  충돌 VMID 자동 할당 시작 번호 [%s]: " "${PVE_MERGE_OFFSET:-200}"
        read -r in_off </dev/tty
        [ -n "$in_off" ] && PVE_MERGE_OFFSET="$in_off"
    fi

    if [ -z "$PVE_MERGE_A" ] || [ -z "$PVE_MERGE_B" ]; then
        RED1; echo "[!] A, B 호스트를 모두 입력해야 합니다."; NC
        return 1
    fi
    if [ "$PVE_MERGE_A" = "$PVE_MERGE_B" ]; then
        RED1; echo "[!] A 와 B 호스트가 동일합니다."; NC
        return 1
    fi
    case "$PVE_MERGE_OFFSET" in
        ""|*[!0-9]*) PVE_MERGE_OFFSET=200 ;;
    esac

    cat > "$PVE_MERGE_STATE" <<EOF
PVE_MERGE_A='$PVE_MERGE_A'
PVE_MERGE_B='$PVE_MERGE_B'
PVE_MERGE_OFFSET='$PVE_MERGE_OFFSET'
PVE_MERGE_SSH_USER='${PVE_MERGE_SSH_USER:-root}'
EOF
    chmod 600 "$PVE_MERGE_STATE" 2>/dev/null

    echo ""
    GRN1; echo "[OK] 저장 완료: $PVE_MERGE_STATE"; NC
    echo "  - Host A (Target/Master) : $PVE_MERGE_A"
    echo "  - Host B (Joining/Remap) : $PVE_MERGE_B"
    echo "  - VMID 시작 번호         : $PVE_MERGE_OFFSET"
    echo ""
    echo "[연결 테스트]"
    local ver_a ver_b
    ver_a="$(_pvem_run "$PVE_MERGE_A" 'printf "%s | %s" "$(hostname -s)" "$(pveversion 2>/dev/null)"' 2>&1)"
    if [ $? -eq 0 ]; then
        GRN1; echo "  [OK] A ($PVE_MERGE_A) -> $ver_a"; NC
    else
        RED1; echo "  [FAIL] A ($PVE_MERGE_A) SSH 접속 실패: $ver_a"; NC
        return 1
    fi
    ver_b="$(_pvem_run "$PVE_MERGE_B" 'printf "%s | %s" "$(hostname -s)" "$(pveversion 2>/dev/null)"' 2>&1)"
    if [ $? -eq 0 ]; then
        GRN1; echo "  [OK] B ($PVE_MERGE_B) -> $ver_b"; NC
    else
        RED1; echo "  [FAIL] B ($PVE_MERGE_B) SSH 접속 실패: $ver_b"; NC
        return 1
    fi
}

# 2단계: 충돌 및 사전 조건 일괄 점검 (100% 읽기 전용)
pve_merge_check() {
    _pvem_require_ready || return 1

    local blockers=0 warns=0
    CYN1; echo "======================================================================"
    echo " [2단계] A / B 일괄 충돌 점검 (100% 읽기 전용)"
    echo "   A (Target)  : $PVE_MERGE_A"
    echo "   B (Joining) : $PVE_MERGE_B"
    echo "======================================================================"; NC

    # 1) 호스트명 & PVE 버전
    local hn_a hn_b ver_a ver_b ip_a ip_b
    hn_a="$(_pvem_run "$PVE_MERGE_A" 'hostname -s')"
    hn_b="$(_pvem_run "$PVE_MERGE_B" 'hostname -s')"
    ver_a="$(_pvem_run "$PVE_MERGE_A" 'pveversion 2>/dev/null')"
    ver_b="$(_pvem_run "$PVE_MERGE_B" 'pveversion 2>/dev/null')"
    ip_a="$(_pvem_run "$PVE_MERGE_A" 'hostname -I 2>/dev/null | tr " " "\n" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" | head -n1')"
    ip_b="$(_pvem_run "$PVE_MERGE_B" 'hostname -I 2>/dev/null | tr " " "\n" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" | head -n1')"

    echo ""
    YEL1; echo "[1/6] 호스트명 & 버전 비교"; NC
    echo "  - A: node=$hn_a  ip=$ip_a  ver=$ver_a"
    echo "  - B: node=$hn_b  ip=$ip_b  ver=$ver_b"
    if [ "$hn_a" = "$hn_b" ]; then
        RED1; echo "  [BLOCK] 호스트명이 동일합니다 ($hn_a == $hn_b). B 노드 호스트명 변경 필수!"; NC
        blockers=$((blockers + 1))
    else
        GRN1; echo "  [OK] 호스트명 중복 없음 ($hn_a != $hn_b)"; NC
    fi
    local maj_a maj_b
    maj_a="$(printf '%s' "$ver_a" | sed -n 's#pve-manager/\([0-9]*\)\..*#\1#p')"
    maj_b="$(printf '%s' "$ver_b" | sed -n 's#pve-manager/\([0-9]*\)\..*#\1#p')"
    if [ -n "$maj_a" ] && [ -n "$maj_b" ] && [ "$maj_a" != "$maj_b" ]; then
        YEL1; echo "  [WARN] PVE 메이저 버전 차이 (A: $maj_a vs B: $maj_b)"; NC
        warns=$((warns + 1))
    fi

    # 2) 클러스터 상태
    echo ""
    YEL1; echo "[2/6] 클러스터 상태 (corosync)"; NC
    local cl_a cl_b
    cl_a="$(_pvem_run "$PVE_MERGE_A" 'if [ -f /etc/pve/corosync.conf ]; then pvecm status 2>/dev/null | awk "/^Name:/{n=\$2} /^Nodes:/{c=\$2} END{printf \"CLUSTER:%s(nodes=%s)\", n, c}"; else echo "STANDALONE"; fi')"
    cl_b="$(_pvem_run "$PVE_MERGE_B" 'if [ -f /etc/pve/corosync.conf ]; then pvecm status 2>/dev/null | awk "/^Name:/{n=\$2} /^Nodes:/{c=\$2} END{printf \"CLUSTER:%s(nodes=%s)\", n, c}"; else echo "STANDALONE"; fi')"
    echo "  - A 상태: $cl_a"
    echo "  - B 상태: $cl_b"
    if [ "$cl_a" = "STANDALONE" ]; then
        YEL1; echo "  [WARN] A 노드가 아직 단독(Standalone)입니다. 합치기 전에 A에서 'pvecm create <클러스터명>' 이 필요합니다."; NC
        warns=$((warns + 1))
    fi
    case "$cl_b" in
        CLUSTER:*)
            RED1; echo "  [BLOCK] B 노드가 이미 클러스터($cl_b)에 속해 있습니다! 조인 전 B 노드 클러스터 리셋(corosync 초기화) 필수!"; NC
            blockers=$((blockers + 1))
            ;;
        STANDALONE)
            GRN1; echo "  [OK] B 노드는 단독(Standalone) 상태 (조인 가능)"; NC
            ;;
    esac

    # 3) VMID 목록 & 충돌 매트릭스
    echo ""
    YEL1; echo "[3/6] VMID 충돌 검사 (QEMU + LXC 통합 비교)"; NC
    local list_a list_b
    list_a="$(_pvem_list_guests "$PVE_MERGE_A")"
    list_b="$(_pvem_list_guests "$PVE_MERGE_B")"
    local cnt_a cnt_b
    cnt_a="$(printf '%s\n' "$list_a" | grep -c '|' 2>/dev/null)"
    cnt_b="$(printf '%s\n' "$list_b" | grep -c '|' 2>/dev/null)"
    echo "  - A 게스트 수: ${cnt_a:-0}개 | B 게스트 수: ${cnt_b:-0}개"

    local conflicts="" conflict_cnt=0 running_conflicts=0
    local line_b bid bt bst bname bconf match_a at ast aname
    while IFS='|' read -r bid bt bst bname bconf; do
        [ -z "$bid" ] && continue
        match_a="$(printf '%s\n' "$list_a" | awk -F'|' -v id="$bid" '$1==id {print; exit}')"
        if [ -n "$match_a" ]; then
            at="$(printf '%s' "$match_a" | cut -d'|' -f2)"
            ast="$(printf '%s' "$match_a" | cut -d'|' -f3)"
            aname="$(printf '%s' "$match_a" | cut -d'|' -f4)"
            conflict_cnt=$((conflict_cnt + 1))
            conflicts="${conflicts}${bid}|${bt}|${bst}|${bname}
"
            local cross=""
            [ "$at" != "$bt" ] && cross=" [QEMU<->LXC 교차충돌!]"
            RED1; printf "  [CONFLICT] VMID %-5s | A: %-4s %-8s (%s)  <-->  B: %-4s %-8s (%s)%s\n" \
                "$bid" "$at" "$ast" "$aname" "$bt" "$bst" "$bname" "$cross"; NC
            [ "$bst" = "running" ] && running_conflicts=$((running_conflicts + 1))
        fi
    done <<EOF
$list_b
EOF
    if [ "$conflict_cnt" -eq 0 ]; then
        GRN1; echo "  [OK] 충돌하는 VMID 없음!"; NC
    else
        YEL1; echo "  [WARN] 총 ${conflict_cnt}개 VMID 충돌 감지 (3단계 Dry-Run 검토 필요)"; NC
        warns=$((warns + 1))
        if [ "$running_conflicts" -gt 0 ]; then
            YEL1; echo "  [WARN] 충돌 대상 중 B 노드에서 현재 실행 중(running): ${running_conflicts}개 (변경 전 정지 필요)"; NC
        fi
    fi

    # 4) 충돌 대상의 스냅샷 / Linked Clone(base-) / 비표준 파일 검사
    echo ""
    YEL1; echo "[4/6] B 노드 스냅샷 / Linked Clone(base-) / 비표준 설정파일 검사"; NC
    if [ "$conflict_cnt" -gt 0 ]; then
        local cid ct cst cname
        while IFS='|' read -r cid ct cst cname; do
            [ -z "$cid" ] && continue
            local cpath="/etc/pve/qemu-server/${cid}.conf"
            [ "$ct" = "lxc" ] && cpath="/etc/pve/lxc/${cid}.conf"
            local has_snap has_base linked_refs
            has_snap="$(_pvem_run "$PVE_MERGE_B" "grep -Ec '^\[.+\]$' '$cpath' 2>/dev/null")"
            has_base="$(_pvem_run "$PVE_MERGE_B" "lvs --noheadings -o vg_name,lv_name 2>/dev/null | grep -E 'base-${cid}-disk-' || true")"
            linked_refs="$(_pvem_run "$PVE_MERGE_B" "grep -lE 'base-${cid}-disk-' /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf 2>/dev/null | grep -v '/${cid}\.conf$' || true")"
            if [ "${has_snap:-0}" -gt 0 ]; then
                YEL1; echo "  [WARN] B VMID $cid ($cname): 스냅샷 섹션 ${has_snap}개 존재 (리네임 전 스냅샷 정리 권장)"; NC
                warns=$((warns + 1))
            fi
            if [ -n "$has_base" ]; then
                YEL1; echo "  [WARN] B VMID $cid ($cname): 템플릿/베이스 볼륨 존재 -> $(echo "$has_base" | tr '\n' ' ')"; NC
                warns=$((warns + 1))
            fi
            if [ -n "$linked_refs" ]; then
                RED1; echo "  [BLOCK] B VMID $cid 의 base 볼륨을 다른 VM이 참조 중: $linked_refs"; NC
                blockers=$((blockers + 1))
            fi
        done <<EOF
$conflicts
EOF
    else
        GRN1; echo "  [OK] 충돌 VMID 없어 스냅샷/베이스 리스크 없음"; NC
    fi

    local nonstd_b
    nonstd_b="$(_pvem_list_nonstandard_confs "$PVE_MERGE_B")"
    if [ -n "$nonstd_b" ]; then
        YEL1; echo "  [WARN] B 노드에 비표준 파일(.bak/.mask 등) 존재 (조인 전 백업 후 함께 정리 권장):"; NC
        printf '%s\n' "$nonstd_b" | sed 's/^/         - /'
        warns=$((warns + 1))
    else
        GRN1; echo "  [OK] B 노드 비표준 설정 파일 없음"; NC
    fi

    # 5) 스토리지 비교
    echo ""
    YEL1; echo "[5/6] 스토리지(storage.cfg) 비교"; NC
    local st_a st_b
    st_a="$(_pvem_parse_storages "$PVE_MERGE_A")"
    st_b="$(_pvem_parse_storages "$PVE_MERGE_B")"
    local sname stype sdet snodes match_sa sa_type sa_det
    while IFS='|' read -r sname stype sdet snodes; do
        [ -z "$sname" ] && continue
        match_sa="$(printf '%s\n' "$st_a" | awk -F'|' -v n="$sname" '$1==n {print; exit}')"
        if [ -z "$match_sa" ]; then
            CYN1; printf "  [B전용] %-16s (%-7s) %-28s nodes=%s  -> 조인 후 A storage.cfg 병합 필요\n" \
                "$sname" "$stype" "$sdet" "$snodes"; NC
        else
            sa_type="$(printf '%s' "$match_sa" | cut -d'|' -f2)"
            sa_det="$(printf '%s' "$match_sa" | cut -d'|' -f3)"
            if [ "$sa_type" != "$stype" ] || [ "$sa_det" != "$sdet" ]; then
                RED1; printf "  [충돌!] %-16s A(%s %s) != B(%s %s)\n" "$sname" "$sa_type" "$sa_det" "$stype" "$sdet"; NC
                blockers=$((blockers + 1))
            else
                GRN1; printf "  [공통]  %-16s (%-7s) %s\n" "$sname" "$stype" "$sdet"; NC
            fi
        fi
    done <<EOF
$st_b
EOF

    # 6) 종합 판정
    echo ""
    CYN1; echo "----------------------------------------------------------------------"; NC
    if [ "$blockers" -gt 0 ]; then
        RED1; echo " [종합 판정: BLOCKED] 선결 차단 항목 ${blockers}건 / 주의 ${warns}건 (위 [BLOCK] 해소 후 조인 진행)"; NC
    elif [ "$warns" -gt 0 ]; then
        YEL1; echo " [종합 판정: WARN] 차단 항목 없음 / 주의 ${warns}건 (3단계 VMID 검토로 진행 가능)"; NC
    else
        GRN1; echo " [종합 판정: PASS] 충돌 및 차단 항목 없음! 바로 클러스터 합치기 가능"; NC
    fi
    CYN1; echo "----------------------------------------------------------------------"; NC
}

# 3단계: B 노드 VMID 자동 변경 계획 검토 (Dry-Run, 100% 읽기 전용)
pve_merge_plan() {
    _pvem_require_ready || return 1

    CYN1; echo "======================================================================"
    echo " [3단계] B 노드 VMID 자동 변경 검토 (DRY-RUN - 실제 변경 없음)"
    echo "   A: $PVE_MERGE_A  |  B: $PVE_MERGE_B  |  시작번호: ${PVE_MERGE_OFFSET:-200}"
    echo "======================================================================"; NC

    local list_a list_b
    list_a="$(_pvem_list_guests "$PVE_MERGE_A")"
    list_b="$(_pvem_list_guests "$PVE_MERGE_B")"

    # 사용 중인 모든 VMID 집합 (A 게스트 + B 게스트 + B LVM/ZFS 볼륨 내 ID)
    local b_vol_ids used_ids
    b_vol_ids="$(_pvem_run "$PVE_MERGE_B" '
        lvs --noheadings -o lv_name 2>/dev/null | grep -Eo "(vm|base|subvol)-[0-9]+-" | grep -Eo "[0-9]+"
        zfs list -H -o name 2>/dev/null | grep -Eo "(vm|base|subvol)-[0-9]+-" | grep -Eo "[0-9]+"
    ' | sort -un)"
    used_ids="$(printf '%s\n%s\n%s\n' \
        "$(printf '%s\n' "$list_a" | cut -d'|' -f1)" \
        "$(printf '%s\n' "$list_b" | cut -d'|' -f1)" \
        "$b_vol_ids" | grep -E '^[0-9]+$' | sort -un)"

    # B 스토리지 디렉토리 경로 목록 (dir 타입)
    local b_dir_paths
    b_dir_paths="$(_pvem_run "$PVE_MERGE_B" 'awk "/^[ \t]+path[ \t]+/{print \$2}" /etc/pve/storage.cfg 2>/dev/null | sort -u')"

    : > "$PVE_MERGE_PLAN_FILE"
    local next_id="${PVE_MERGE_OFFSET:-200}"
    local planned=0
    local bid bt bst bname bconf match_a

    while IFS='|' read -r bid bt bst bname bconf; do
        [ -z "$bid" ] && continue
        match_a="$(printf '%s\n' "$list_a" | awk -F'|' -v id="$bid" '$1==id {print; exit}')"
        [ -z "$match_a" ] && continue

        # 빈 새 VMID 탐색
        while printf '%s\n' "$used_ids" | grep -qx "$next_id"; do
            next_id=$((next_id + 1))
        done
        local new_id="$next_id"
        used_ids="${used_ids}
${new_id}"
        next_id=$((next_id + 1))
        planned=$((planned + 1))

        printf '%s\t%s\t%s\t%s\t%s\n' "$bid" "$new_id" "$bt" "$bst" "$bname" >> "$PVE_MERGE_PLAN_FILE"

        echo ""
        YEL1; printf "▶ [매핑 #%d] B 노드 %s %s (%s)  ==>  새 VMID: %s  (현재상태: %s)\n" \
            "$planned" "$bt" "$bid" "$bname" "$new_id" "$bst"; NC

        if [ "$bst" = "running" ]; then
            echo "   [1. 정지]   $( [ "$bt" = "qemu" ] && echo "qm" || echo "pct" ) shutdown $bid"
        fi

        # B 노드 LVM 볼륨 탐색 (다른 VM이 참조 중인 base- 볼륨은 보호하여 제외)
        local lvs_hit ext_base_refs
        ext_base_refs="$(_pvem_run "$PVE_MERGE_B" "grep -lE 'base-${bid}-disk-' /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf 2>/dev/null | grep -v '/${bid}\.conf$' || true")"
        lvs_hit="$(_pvem_run "$PVE_MERGE_B" "lvs --noheadings -o vg_name,lv_name 2>/dev/null | awk '\$2 ~ /^(vm|base|subvol)-${bid}-/{print \$1\"|\"\$2}'")"
        if [ -n "$lvs_hit" ]; then
            local vg lv new_lv
            while IFS='|' read -r vg lv; do
                [ -z "$lv" ] && continue
                case "$lv" in
                    base-*)
                        if [ -n "$ext_base_refs" ]; then
                            RED1; echo "   [2. SKIP]   ${vg}/${lv} (다른 VM 참조 중: $(echo "$ext_base_refs" | tr '\n' ' ') -> 안전상 변경 제외)"; NC
                            continue
                        fi
                        ;;
                esac
                new_lv="$(printf '%s' "$lv" | sed -E "s/^(vm|base|subvol)-${bid}-/\1-${new_id}-/")"
                echo "   [2. LVM]    lvrename ${vg}/${lv} ${vg}/${new_lv}"
            done <<EOF2
$lvs_hit
EOF2
        fi

        # B 노드 ZFS 볼륨 탐색
        local zfs_hit
        zfs_hit="$(_pvem_run "$PVE_MERGE_B" "zfs list -H -o name 2>/dev/null | grep -E '/(vm|base|subvol)-${bid}-' || true")"
        if [ -n "$zfs_hit" ]; then
            local zv new_zv
            while IFS= read -r zv; do
                [ -z "$zv" ] && continue
                new_zv="$(printf '%s' "$zv" | sed -E "s#/(vm|base|subvol)-${bid}-#/\1-${new_id}-#")"
                echo "   [2. ZFS]    zfs rename ${zv} ${new_zv}"
            done <<EOF2
$zfs_hit
EOF2
        fi

        # B 노드 Directory 이미지 폴더 탐색
        local dpath dir_hit
        while IFS= read -r dpath; do
            [ -z "$dpath" ] && continue
            dir_hit="$(_pvem_run "$PVE_MERGE_B" "[ -d '${dpath}/images/${bid}' ] && echo '${dpath}/images/${bid}' || true")"
            if [ -n "$dir_hit" ]; then
                echo "   [2. DIR]    mv ${dpath}/images/${bid} ${dpath}/images/${new_id}  (+ 내부 파일명 치환)"
            fi
        done <<EOF2
$b_dir_paths
EOF2

        # conf 치환 미리보기
        local new_conf="${bconf%/*}/${new_id}.conf"
        echo "   [3. CONF]   mv ${bconf} ${new_conf}"
        local conf_refs
        conf_refs="$(_pvem_run "$PVE_MERGE_B" "grep -E '(vm|base|subvol)-${bid}-|/${bid}/' '$bconf' 2>/dev/null || true")"
        if [ -n "$conf_refs" ]; then
            while IFS= read -r cl; do
                [ -z "$cl" ] && continue
                echo "               치환: $cl"
            done <<EOF2
$conf_refs
EOF2
        fi

        # 방화벽 파일
        local has_fw
        has_fw="$(_pvem_run "$PVE_MERGE_B" "[ -f '/etc/pve/firewall/${bid}.fw' ] && echo YES || true")"
        [ "$has_fw" = "YES" ] && echo "   [4. FW]     mv /etc/pve/firewall/${bid}.fw /etc/pve/firewall/${new_id}.fw"
    done <<EOF
$list_b
EOF

    echo ""
    CYN1; echo "----------------------------------------------------------------------"; NC
    if [ "$planned" -eq 0 ]; then
        GRN1; echo " [결과] 충돌하는 VMID가 없어 변경할 항목이 없습니다!"; NC
    else
        GRN1; echo " [DRY-RUN 완료] 총 ${planned}개 변경 계획이 생성되었습니다."; NC
        echo "  - 계획표 저장됨: $PVE_MERGE_PLAN_FILE"
        echo "  - 실제 변경은 전혀 수행되지 않았습니다. 검토 후 4단계 메뉴에서 실행하세요."
    fi
    CYN1; echo "----------------------------------------------------------------------"; NC
}

# 4단계: B 노드 VMID 일괄 자동 변경 실행 (실제 변경)
pve_merge_apply_vmid() {
    _pvem_require_ready || return 1

    if [ ! -s "$PVE_MERGE_PLAN_FILE" ]; then
        YEL1; echo "[!] 저장된 변경 계획표가 없습니다. 먼저 3단계(Dry-Run 검토)를 실행합니다..."; NC
        pve_merge_plan || return 1
        [ ! -s "$PVE_MERGE_PLAN_FILE" ] && return 0
    fi

    echo ""
    RED1; echo "======================================================================"
    echo " [4단계 - 주의!] B 노드($PVE_MERGE_B) VMID 실제 일괄 변경"
    echo "======================================================================"; NC
    echo "적용 예정 매핑표 ($PVE_MERGE_PLAN_FILE):"
    awk -F'\t' '{printf "  - [%s] %s (%s)  -->  %s\n", $3, $1, $5, $2}' "$PVE_MERGE_PLAN_FILE"
    echo ""
    printf "정말로 B 노드(%s)에 위 변경을 실행하시겠습니까? (진행하려면 APPLY 입력): " "$PVE_MERGE_B"
    local ans
    read -r ans </dev/tty
    if [ "$ans" != "APPLY" ]; then
        YEL1; echo "[취소됨] 변경을 수행하지 않았습니다."; NC
        return 0
    fi

    local ts bdir
    ts="$(date +%Y%m%d_%H%M%S)"
    bdir="/root/pve_merge_vmid_bak_${ts}"
    echo "[*] B 노드 설정 사전 백업 중: $bdir"
    _pvem_run "$PVE_MERGE_B" "mkdir -p '$bdir/qemu-server' '$bdir/lxc' '$bdir/firewall' && cp -a /etc/pve/qemu-server/* '$bdir/qemu-server/' 2>/dev/null; cp -a /etc/pve/lxc/* '$bdir/lxc/' 2>/dev/null; cp -a /etc/pve/firewall/* '$bdir/firewall/' 2>/dev/null; cp -a /etc/pve/storage.cfg '$bdir/' 2>/dev/null; lvs > '$bdir/lvs.before.txt' 2>/dev/null; true"

    local old_id new_id gtype gst gname
    while IFS="$(printf '\t')" read -r old_id new_id gtype gst gname; do
        [ -z "$old_id" ] && continue
        CYN1; echo ""; echo ">>> 처리 중: [$gtype] $old_id ($gname) -> $new_id"; NC

        # 실행 중이면 정지
        if [ "$gst" = "running" ]; then
            echo "  - 게스트 정지 시도..."
            if [ "$gtype" = "qemu" ]; then
                _pvem_run "$PVE_MERGE_B" "qm shutdown $old_id --timeout 60" || { RED1; echo "  [FAIL] 정지 실패, 건너뜀"; NC; continue; }
            else
                _pvem_run "$PVE_MERGE_B" "pct shutdown $old_id --timeout 60" || { RED1; echo "  [FAIL] 정지 실패, 건너뜀"; NC; continue; }
            fi
        fi

        # LVM rename (다른 VM이 참조 중인 base- 볼륨은 안전상 자동 제외)
        _pvem_run "$PVE_MERGE_B" "
            ext_refs=\"\$(grep -lE 'base-${old_id}-disk-' /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf 2>/dev/null | grep -v '/${old_id}\.conf$' || true)\"
            lvs --noheadings -o vg_name,lv_name 2>/dev/null | awk '\$2 ~ /^(vm|base|subvol)-${old_id}-/{print \$1\"|\"\$2}' | while IFS='|' read -r vg lv; do
                [ -z \"\$lv\" ] && continue
                case \"\$lv\" in
                    base-*)
                        if [ -n \"\$ext_refs\" ]; then
                            echo \"  - [SKIP] \${vg}/\${lv} (외부 VM 참조 중 -> 보호)\"
                            continue
                        fi
                        ;;
                esac
                new_lv=\"\$(printf '%s' \"\$lv\" | sed -E 's/^(vm|base|subvol)-${old_id}-/\1-${new_id}-/')\"
                echo \"  - lvrename \${vg}/\${lv} -> \${vg}/\${new_lv}\"
                lvrename \"\${vg}/\${lv}\" \"\${vg}/\${new_lv}\"
            done
        " || { RED1; echo "  [FAIL] LVM rename 오류"; NC; return 1; }

        # ZFS rename
        _pvem_run "$PVE_MERGE_B" "
            zfs list -H -o name 2>/dev/null | grep -E '/(vm|base|subvol)-${old_id}-' | while IFS= read -r zv; do
                [ -z \"\$zv\" ] && continue
                new_zv=\"\$(printf '%s' \"\$zv\" | sed -E 's#/(vm|base|subvol)-${old_id}-#/\1-${new_id}-#')\"
                echo \"  - zfs rename \${zv} -> \${new_zv}\"
                zfs rename \"\$zv\" \"\$new_zv\"
            done
        "

        # Directory images rename
        _pvem_run "$PVE_MERGE_B" "
            awk '/^[ \t]+path[ \t]+/{print \$2}' /etc/pve/storage.cfg 2>/dev/null | sort -u | while IFS= read -r dp; do
                [ -d \"\${dp}/images/${old_id}\" ] || continue
                echo \"  - mv \${dp}/images/${old_id} -> \${dp}/images/${new_id}\"
                mv \"\${dp}/images/${old_id}\" \"\${dp}/images/${new_id}\"
                for f in \"\${dp}/images/${new_id}\"/*; do
                    [ -e \"\$f\" ] || continue
                    bf=\"\$(basename \"\$f\")\"
                    nbf=\"\$(printf '%s' \"\$bf\" | sed -E 's/^(vm|base|subvol)-${old_id}-/\1-${new_id}-/')\"
                    [ \"\$bf\" != \"\$nbf\" ] && mv \"\$f\" \"\${dp}/images/${new_id}/\${nbf}\"
                done
            done
        "

        # conf 이동 및 치환
        local cdir="/etc/pve/qemu-server"
        [ "$gtype" = "lxc" ] && cdir="/etc/pve/lxc"
        _pvem_run "$PVE_MERGE_B" "
            sed -E \
                -e 's/(vm|base|subvol)-${old_id}-/\1-${new_id}-/g' \
                -e 's#/${old_id}/#/${new_id}/#g' \
                '${cdir}/${old_id}.conf' > '${cdir}/${new_id}.conf' && \
            rm -f '${cdir}/${old_id}.conf'
            [ -f '/etc/pve/firewall/${old_id}.fw' ] && mv '/etc/pve/firewall/${old_id}.fw' '/etc/pve/firewall/${new_id}.fw'
            true
        "
        GRN1; echo "  [OK] $old_id -> $new_id 완료"; NC
    done < "$PVE_MERGE_PLAN_FILE"

    rm -f "$PVE_MERGE_PLAN_FILE"
    echo ""
    GRN1; echo "[완료] B 노드 VMID 일괄 변경이 끝났습니다! (백업: $bdir)"; NC
    echo "  -> 이제 2단계(일괄 점검)를 다시 실행해 충돌 0건인지 확인하세요."
}

# 5단계: 클러스터 합치기 사전 검토 (Dry-Run, 100% 읽기 전용)
pve_merge_join_dryrun() {
    _pvem_require_ready || return 1

    CYN1; echo "======================================================================"
    echo " [5단계] 클러스터 합치기 사전 검토 (DRY-RUN - 실제 변경 없음)"
    echo "   A (Master)  : $PVE_MERGE_A"
    echo "   B (Joining) : $PVE_MERGE_B"
    echo "======================================================================"; NC

    local hn_a hn_b ip_a cl_a cl_b
    hn_a="$(_pvem_run "$PVE_MERGE_A" 'hostname -s')"
    hn_b="$(_pvem_run "$PVE_MERGE_B" 'hostname -s')"
    ip_a="$(_pvem_run "$PVE_MERGE_A" 'hostname -I 2>/dev/null | tr " " "\n" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" | head -n1')"
    cl_a="$(_pvem_run "$PVE_MERGE_A" '[ -f /etc/pve/corosync.conf ] && echo CLUSTER || echo STANDALONE')"
    cl_b="$(_pvem_run "$PVE_MERGE_B" '[ -f /etc/pve/corosync.conf ] && echo CLUSTER || echo STANDALONE')"

    echo "[사전 상태]"
    echo "  - A: node=$hn_a  ip=$ip_a  mode=$cl_a"
    echo "  - B: node=$hn_b  mode=$cl_b"
    [ "$cl_a" = "STANDALONE" ] && { YEL1; echo "  [필요] A 노드에서 먼저 'pvecm create <클러스터명>' 실행 필요"; NC; }
    [ "$cl_b" = "CLUSTER" ] && { RED1; echo "  [차단] B 노드가 기존 클러스터에 속해 있음 -> 먼저 B 노드 'node reset' (corosync 초기화) 필요!"; NC; }

    echo ""
    echo "[합치기 실행 시 B 노드($PVE_MERGE_B)에서 수행될 작업 순서]"
    local b_confs
    b_confs="$(_pvem_run "$PVE_MERGE_B" 'ls -1 /etc/pve/qemu-server/* /etc/pve/lxc/* 2>/dev/null || true')"
    local b_cnt
    b_cnt="$(printf '%s\n' "$b_confs" | grep -c '/' 2>/dev/null)"
    echo "  1. B 노드 설정 전체 백업 -> /root/pve_merge_join_<시각>/"
    echo "  2. B 노드 게스트 conf 파일 ${b_cnt:-0}개 임시 이동 (빈 노드 상태 만들기)"
    echo "  3. B 노드에서 조인 실행: pvecm add ${ip_a}"
    echo "  4. 조인 확인 후 백업된 conf 를 /etc/pve/nodes/${hn_b}/{qemu-server,lxc}/ 로 원복"
    echo "  5. B 전용 스토리지 블록을 /etc/pve/storage.cfg 에 병합:"

    local st_a st_b sname
    st_a="$(_pvem_parse_storages "$PVE_MERGE_A" | cut -d'|' -f1)"
    st_b="$(_pvem_parse_storages "$PVE_MERGE_B" | cut -d'|' -f1)"
    while IFS= read -r sname; do
        [ -z "$sname" ] && continue
        if ! printf '%s\n' "$st_a" | grep -qx "$sname"; then
            CYN1; echo "     + 스토리지 병합 대상: $sname (nodes $hn_b)"; NC
        fi
    done <<EOF
$st_b
EOF
    echo ""
    GRN1; echo "[DRY-RUN 완료] 실제 변경은 수행되지 않았습니다."; NC
}

# 6단계: 클러스터 합치기 실행 (conf 임시이동 -> pvecm add -> conf & 스토리지 원복)
pve_merge_join() {
    _pvem_require_ready || return 1

    local hn_b ip_a cl_a cl_b
    hn_b="$(_pvem_run "$PVE_MERGE_B" 'hostname -s')"
    ip_a="$(_pvem_run "$PVE_MERGE_A" 'hostname -I 2>/dev/null | tr " " "\n" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" | head -n1')"
    cl_a="$(_pvem_run "$PVE_MERGE_A" '[ -f /etc/pve/corosync.conf ] && echo CLUSTER || echo STANDALONE')"
    cl_b="$(_pvem_run "$PVE_MERGE_B" '[ -f /etc/pve/corosync.conf ] && echo CLUSTER || echo STANDALONE')"

    if [ "$cl_a" != "CLUSTER" ]; then
        RED1; echo "[!] A 노드($PVE_MERGE_A)가 아직 클러스터가 아닙니다. 먼저 A에서 'pvecm create <이름>' 을 실행하세요."; NC
        return 1
    fi
    if [ "$cl_b" = "CLUSTER" ]; then
        RED1; echo "[!] B 노드($PVE_MERGE_B)가 이미 다른 클러스터에 속해 있습니다. 먼저 B 노드의 corosync 를 초기화하세요."; NC
        return 1
    fi

    # VMID 충돌 0건 재확인
    local list_a list_b dup
    list_a="$(_pvem_list_guests "$PVE_MERGE_A" | cut -d'|' -f1)"
    list_b="$(_pvem_list_guests "$PVE_MERGE_B" | cut -d'|' -f1)"
    dup="$(comm -12 <(printf '%s\n' "$list_a" | sort -u) <(printf '%s\n' "$list_b" | sort -u) 2>/dev/null | tr '\n' ' ')"
    if [ -n "${dup// /}" ]; then
        RED1; echo "[!] 아직 충돌 VMID가 남아 있습니다: $dup (먼저 3~4단계로 VMID를 변경하세요)"; NC
        return 1
    fi

    RED1; echo "======================================================================"
    echo " [6단계 - 주의!] Proxmox 클러스터 합치기 실행"
    echo "   B($PVE_MERGE_B / $hn_b)  ==>  A($PVE_MERGE_A / $ip_a)"
    echo "======================================================================"; NC
    printf "정말로 B 노드의 conf를 임시 이동하고 클러스터에 합치시겠습니까? (JOIN 입력): "
    local ans
    read -r ans </dev/tty
    if [ "$ans" != "JOIN" ]; then
        YEL1; echo "[취소됨] 클러스터 합치기를 중단했습니다."; NC
        return 0
    fi

    local ts bdir
    ts="$(date +%Y%m%d_%H%M%S)"
    bdir="/root/pve_merge_join_${ts}"

    echo "[1/4] B 노드 conf 및 storage.cfg 백업 + 임시 이동 ($bdir)"
    _pvem_run "$PVE_MERGE_B" "
        mkdir -p '$bdir/qemu-server' '$bdir/lxc' '$bdir/firewall' && \
        cp -a /etc/pve/storage.cfg '$bdir/storage.cfg' 2>/dev/null; \
        cp -a /etc/pve/firewall/* '$bdir/firewall/' 2>/dev/null; \
        mv /etc/pve/qemu-server/* '$bdir/qemu-server/' 2>/dev/null; \
        mv /etc/pve/lxc/* '$bdir/lxc/' 2>/dev/null; \
        true
    " || { RED1; echo "[FAIL] 백업/이동 실패"; NC; return 1; }

    echo "[2/4] B 노드에서 pvecm add $ip_a 실행 (SSH 비밀번호/지문 확인 필요할 수 있음)"
    if ! _pvem_run_tty "$PVE_MERGE_B" "pvecm add $ip_a"; then
        RED1; echo "[FAIL] pvecm add 실패! 백업에서 B 노드 conf 를 원복합니다..."; NC
        _pvem_run "$PVE_MERGE_B" "
            cp -a '$bdir/qemu-server/'* /etc/pve/qemu-server/ 2>/dev/null; \
            cp -a '$bdir/lxc/'* /etc/pve/lxc/ 2>/dev/null; true
        "
        return 1
    fi

    echo "[3/4] 조인 성공! B 노드 conf 및 방화벽 원복 중..."
    sleep 3
    _pvem_run "$PVE_MERGE_B" "
        cp -a '$bdir/qemu-server/'*.conf '/etc/pve/nodes/${hn_b}/qemu-server/' 2>/dev/null; \
        cp -a '$bdir/lxc/'*.conf '/etc/pve/nodes/${hn_b}/lxc/' 2>/dev/null; \
        cp -a '$bdir/firewall/'*.fw '/etc/pve/firewall/' 2>/dev/null; \
        true
    "

    echo "[4/4] B 전용 스토리지 확인 및 안내"
    YEL1; echo "  * B 노드의 원본 storage.cfg 백업 위치: ${PVE_MERGE_B}:${bdir}/storage.cfg"; NC
    echo "  * A 노드의 /etc/pve/storage.cfg 에 B 전용 스토리지(nodes $hn_b)가 빠져있다면 병합하세요."
    echo ""
    GRN1; echo "[완료] 클러스터 상태 확인:"; NC
    _pvem_run "$PVE_MERGE_A" "pvecm status; echo; pvecm nodes"
}

# 7단계: 백업된 conf 비상 원복
pve_merge_restore_conf() {
    _pvem_require_state || return 1
    CYN1; echo "[7단계] B 노드($PVE_MERGE_B) 백업 목록 확인"; NC
    local baks
    baks="$(_pvem_run "$PVE_MERGE_B" 'ls -1dt /root/pve_merge_join_* /root/pve_merge_vmid_bak_* 2>/dev/null || true')"
    if [ -z "$baks" ]; then
        YEL1; echo "  [!] B 노드에 pve_merge 백업 디렉토리가 없습니다."; NC
        return 0
    fi
    echo "$baks" | nl -w2 -s'. '
    printf "원복할 백업 전체 경로를 입력하세요 (취소=Enter): "
    local sel
    read -r sel </dev/tty
    [ -z "$sel" ] && return 0
    local hn_b
    hn_b="$(_pvem_run "$PVE_MERGE_B" 'hostname -s')"
    _pvem_run "$PVE_MERGE_B" "
        cp -a '${sel}/qemu-server/'*.conf '/etc/pve/nodes/${hn_b}/qemu-server/' 2>/dev/null; \
        cp -a '${sel}/lxc/'*.conf '/etc/pve/nodes/${hn_b}/lxc/' 2>/dev/null; \
        true
    "
    GRN1; echo "[OK] conf 원복 완료 ($sel -> /etc/pve/nodes/${hn_b}/)"; NC
}

# ==============================================================================
# Locale & Timezone 자동감지 관리 (Debian/Ubuntu/Alma/Rocky/CentOS 5~9 범용)
# ==============================================================================
_locale_detect_os() {
    _LOC_FAMILY="unknown"
    _LOC_PRETTY="Unknown Linux"
    _LOC_PKG=""
    _LOC_CONF=""
    _LOC_SYSTEMD=0

    if [ -d /run/systemd/system ] && command -v localectl >/dev/null 2>&1; then
        _LOC_SYSTEMD=1
    fi

    if [ -f /etc/os-release ]; then
        _LOC_PRETTY="$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"')"
        local _id _id_like _ver_id _major
        _id="$(grep -E '^ID=' /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"' | tr 'A-Z' 'a-z')"
        _id_like="$(grep -E '^ID_LIKE=' /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"' | tr 'A-Z' 'a-z')"
        _ver_id="$(grep -E '^VERSION_ID=' /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"')"
        _major="${_ver_id%%.*}"
        case " $_id $_id_like " in
            *" debian "*|*" ubuntu "*)
                _LOC_FAMILY="debian"
                _LOC_PKG="apt-get"
                _LOC_CONF="/etc/default/locale"
                ;;
            *" rhel "*|*" centos "*|*" fedora "*|*" rocky "*|*" almalinux "*)
                if command -v dnf >/dev/null 2>&1 || [ "${_major:-0}" -ge 8 ] 2>/dev/null; then
                    _LOC_FAMILY="rhel8"
                    _LOC_PKG="dnf"
                    _LOC_CONF="/etc/locale.conf"
                elif [ "${_major:-0}" -eq 7 ] 2>/dev/null; then
                    _LOC_FAMILY="rhel7"
                    _LOC_PKG="yum"
                    _LOC_CONF="/etc/locale.conf"
                else
                    _LOC_FAMILY="rhel6"
                    _LOC_PKG="yum"
                    _LOC_CONF="/etc/sysconfig/i18n"
                fi
                ;;
            *" alpine "*)
                _LOC_FAMILY="alpine"
                _LOC_PKG="apk"
                _LOC_CONF="/etc/profile.d/locale.sh"
                ;;
        esac
    elif [ -f /etc/debian_version ]; then
        _LOC_FAMILY="debian"
        _LOC_PRETTY="Debian $(cat /etc/debian_version 2>/dev/null)"
        _LOC_PKG="apt-get"
        _LOC_CONF="/etc/default/locale"
    elif [ -f /etc/redhat-release ]; then
        _LOC_PRETTY="$(cat /etc/redhat-release 2>/dev/null)"
        if echo "$_LOC_PRETTY" | grep -qi '^Red Hat Linux release' || \
           echo "$_LOC_PRETTY" | grep -qE 'release [456]\.' || \
           { [ "$_LOC_SYSTEMD" -eq 0 ] && [ -f /etc/sysconfig/i18n ]; }; then
            _LOC_FAMILY="rhel6"
            command -v yum >/dev/null 2>&1 && _LOC_PKG="yum" || _LOC_PKG="rpm"
            _LOC_CONF="/etc/sysconfig/i18n"
        elif echo "$_LOC_PRETTY" | grep -qE 'release 7\.'; then
            _LOC_FAMILY="rhel7"
            _LOC_PKG="yum"
            _LOC_CONF="/etc/locale.conf"
        else
            _LOC_FAMILY="rhel8"
            _LOC_PKG="dnf"
            _LOC_CONF="/etc/locale.conf"
        fi
    fi

    if [ -z "$_LOC_CONF" ]; then
        if [ -f /etc/default/locale ]; then
            _LOC_CONF="/etc/default/locale"
        elif [ -f /etc/locale.conf ]; then
            _LOC_CONF="/etc/locale.conf"
        elif [ -f /etc/sysconfig/i18n ]; then
            _LOC_CONF="/etc/sysconfig/i18n"
        else
            _LOC_CONF="/etc/locale.conf"
        fi
    fi
}

locale_status() {
    _locale_detect_os
    CYN1
    echo "============================================================"
    ko " [Locale & Timezone 상태 진단]\n"
    echo "============================================================"
    NC
    printf "  %-14s : %s (%s)\n" "OS" "$_LOC_PRETTY" "$_LOC_FAMILY"
    ko "  패키지/init    : %s (systemd=%s)\n" "${_LOC_PKG:-none}" "$([ "$_LOC_SYSTEMD" -eq 1 ] && echo 'YES' || echo 'NO')"
    ko "  실효 설정파일  : %s\n" "$_LOC_CONF"
    ko "  현재 세션      : LANG=%s | LC_ALL=%s\n" "${LANG:-<empty>}" "${LC_ALL:-<unset>}"
    ko "  현재 시각      : %s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z (%z)')"

    echo ""
    YEL1; ko " [1] 실효 로케일 설정 파일 (%s)\n" "$_LOC_CONF"; NC
    if [ -f "$_LOC_CONF" ]; then
        sed 's/^/     /' "$_LOC_CONF"
    else
        ko "     (파일 없음)\n"
    fi

    if [ "$_LOC_SYSTEMD" -eq 1 ]; then
        echo ""
        YEL1; echo " [2] localectl / timedatectl"; NC
        localectl status 2>/dev/null | sed 's/^/     /'
        timedatectl 2>/dev/null | grep -E 'Local time|Universal time|Time zone|NTP|synchronized' | sed 's/^/     /'
    fi

    echo ""
    YEL1; ko " [3] 설치된 ko / en 로케일 (locale -a)\n"; NC
    local _avail
    _avail="$(locale -a 2>/dev/null | grep -iE '^(ko_KR|en_US|C\.UTF-8)' | tr '\n' ' ')"
    if [ -n "$_avail" ]; then
        printf "     %s\n" "$_avail"
    else
        ko "     (없음)\n"
    fi
}

locale_set() {
    local _mode="$1"
    shift 2>/dev/null || true
    local _with_fonts=0
    local _arg
    for _arg in "$@"; do
        case "$_arg" in
            --fonts|-f) _with_fonts=1 ;;
        esac
    done

    local _target _lang_base
    case "$_mode" in
        ko|kr|han|ko_KR.UTF-8)
            _target="ko_KR.UTF-8"
            _lang_base="ko_KR"
            ;;
        en|us|eng|en_US.UTF-8)
            _target="en_US.UTF-8"
            _lang_base="en_US"
            ;;
        *)
            RED1; ko "사용법: locale_set <ko|en> [--fonts]\n"; NC
            return 1
            ;;
    esac

    if [ "$(id -u)" -ne 0 ]; then
        RED1; ko "[!] root 권한이 필요합니다. (sudo 또는 root로 실행)\n"; NC
        return 1
    fi

    _locale_detect_os
    CYN1
    echo "============================================================"
    if [ "$_lang_base" = "ko_KR" ]; then
        ko " [한글화 자동 적용] %s\n" "$_target"
    else
        ko " [영어화 자동 적용] %s\n" "$_target"
    fi
    ko " OS: %s (%s) | 설정파일: %s\n" "$_LOC_PRETTY" "$_LOC_FAMILY" "$_LOC_CONF"
    echo "============================================================"
    NC

    case "$_LOC_FAMILY" in
        debian)
            # 1) locales 패키지 확보
            if ! dpkg -s locales >/dev/null 2>&1; then
                YEL1; ko " -> locales 패키지 설치 중...\n"; NC
                DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y locales
            fi
            # 2) 선택: 한글 폰트
            if [ "$_with_fonts" -eq 1 ] && [ "$_lang_base" = "ko_KR" ]; then
                YEL1; ko " -> 한글 폰트(fonts-nanum, fonts-noto-cjk) 설치 중...\n"; NC
                DEBIAN_FRONTEND=noninteractive apt-get install -y fonts-nanum fonts-noto-cjk 2>/dev/null || \
                DEBIAN_FRONTEND=noninteractive apt-get install -y fonts-nanum 2>/dev/null || true
                command -v fc-cache >/dev/null 2>&1 && fc-cache -fv >/dev/null 2>&1 || true
            fi
            # 3) /etc/locale.gen 주석 해제 및 생성
            if [ -f /etc/locale.gen ]; then
                if grep -qE "^[#[:space:]]*${_target}[[:space:]]+UTF-8" /etc/locale.gen; then
                    sed -i "s/^[#[:space:]]*${_target}[[:space:]]\+UTF-8/${_target} UTF-8/" /etc/locale.gen
                else
                    echo "${_target} UTF-8" >> /etc/locale.gen
                fi
            fi
            YEL1; ko " -> locale-gen 실행 중...\n"; NC
            locale-gen "$_target" 2>/dev/null || locale-gen
            # 4) 영구 설정 반영 (충돌 방지: 기존 LC_ALL 제거 후 LANG 설정)
            if [ -f /etc/default/locale ] && grep -q '^LC_ALL=' /etc/default/locale 2>/dev/null; then
                sed -i '/^LC_ALL=/d' /etc/default/locale
            fi
            if command -v update-locale >/dev/null 2>&1; then
                update-locale LANG="$_target"
            elif [ "$_LOC_SYSTEMD" -eq 1 ]; then
                localectl set-locale LANG="$_target"
            else
                echo "LANG=${_target}" > /etc/default/locale
            fi
            ;;

        rhel8)
            # AlmaLinux / Rocky / RHEL / CentOS 8~9 (dnf)
            local _pkg="glibc-langpack-en"
            [ "$_lang_base" = "ko_KR" ] && _pkg="glibc-langpack-ko"
            YEL1; echo " -> dnf install -y $_pkg ..."; NC
            dnf install -y "$_pkg"
            if [ "$_lang_base" = "ko_KR" ]; then
                dnf install -y glibc-gconv-extra 2>/dev/null || true
            fi
            if [ "$_LOC_SYSTEMD" -eq 1 ]; then
                localectl set-locale LANG="$_target"
            else
                echo "LANG=\"${_target}\"" > /etc/locale.conf
            fi
            ;;

        rhel7)
            # CentOS / RHEL 7 (yum + systemd)
            if ! locale -a 2>/dev/null | grep -qi "^${_lang_base}\.utf-\?8$"; then
                YEL1; ko " -> localedef로 %s 생성 중...\n" "$_target"; NC
                localedef -i "$_lang_base" -f UTF-8 "$_target"
            fi
            if [ "$_LOC_SYSTEMD" -eq 1 ]; then
                localectl set-locale LANG="$_target"
            else
                echo "LANG=\"${_target}\"" > /etc/locale.conf
            fi
            ;;

        rhel6)
            # 구버전 Red Hat Linux / CentOS 5~6 (non-systemd, /etc/sysconfig/i18n)
            if ! locale -a 2>/dev/null | grep -qi "^${_lang_base}\.utf-\?8$"; then
                YEL1; ko " -> localedef로 %s 생성 중...\n" "$_target"; NC
                localedef -i "$_lang_base" -f UTF-8 "$_target"
            fi
            if [ -f /etc/sysconfig/i18n ]; then
                cp -a /etc/sysconfig/i18n "/etc/sysconfig/i18n.bak.$(date +%Y%m%d%H%M%S)"
                if grep -q '^LANG=' /etc/sysconfig/i18n; then
                    sed -i "s/^LANG=.*/LANG=\"${_target}\"/" /etc/sysconfig/i18n
                else
                    echo "LANG=\"${_target}\"" >> /etc/sysconfig/i18n
                fi
            else
                echo "LANG=\"${_target}\"" > /etc/sysconfig/i18n
            fi
            ;;

        *)
            # 기타/최소 리눅스 fallback
            if ! locale -a 2>/dev/null | grep -qi "^${_lang_base}\.utf-\?8$"; then
                command -v localedef >/dev/null 2>&1 && localedef -i "$_lang_base" -f UTF-8 "$_target"
            fi
            if [ "$_LOC_SYSTEMD" -eq 1 ]; then
                localectl set-locale LANG="$_target"
            else
                echo "LANG=${_target}" > "$_LOC_CONF"
            fi
            ;;
    esac

    # 현재 쉘 세션에도 즉시 적용
    export LANG="$_target"
    unset LC_ALL 2>/dev/null || true

    echo ""
    GRN1
    if [ "$_lang_base" = "ko_KR" ]; then
        ko "[OK] 한글화 완료 -> %s\n" "$_target"
    else
        ko "[OK] 영어화 완료 -> %s\n" "$_target"
    fi
    NC
    ko "  * 실효 설정 (%s):\n" "$_LOC_CONF"
    [ -f "$_LOC_CONF" ] && sed 's/^/    /' "$_LOC_CONF"
    ko "  * 새 SSH 접속부터 영구 반영됩니다. (현재 세션 적용 완료: LANG=%s)\n" "$LANG"
}

timezone_set() {
    local _tz="${1:-Asia/Seoul}"
    if [ "$(id -u)" -ne 0 ]; then
        RED1; ko "[!] root 권한이 필요합니다.\n"; NC
        return 1
    fi
    if [ ! -f "/usr/share/zoneinfo/${_tz}" ]; then
        RED1; ko "[!] 존재하지 않는 타임존입니다: %s\n" "$_tz"; NC
        ko "    예시: Asia/Seoul, UTC, America/New_York\n"
        return 1
    fi

    _locale_detect_os
    if [ "$_LOC_SYSTEMD" -eq 1 ] && command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-timezone "$_tz"
    else
        ln -snf "/usr/share/zoneinfo/${_tz}" /etc/localtime
        [ -f /etc/timezone ] && echo "$_tz" > /etc/timezone
        if [ -f /etc/sysconfig/clock ]; then
            if grep -q '^ZONE=' /etc/sysconfig/clock; then
                sed -i "s|^ZONE=.*|ZONE=\"${_tz}\"|" /etc/sysconfig/clock
            else
                echo "ZONE=\"${_tz}\"" >> /etc/sysconfig/clock
            fi
        fi
    fi

    GRN1; ko "[OK] 타임존 설정 완료: %s\n" "$_tz"; NC
    ko "  * 현재 시각: %s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z (%z)')"
}

template_copy() {
    local template=$1 && local file_path=$2 && [ -f $file_path ] && rbackup $file_path
    local file_dir
    file_dir=$(dirname "$file_path")
    [ ! -d "$file_dir" ] && mkdir -p "$file_dir"

    case $template in

    wireguard.yml)
        cat >"$file_path" <<'EOF'
version: "3.8"
services:
  wg-easy:
    environment:
      # ?? Required:
      # Change this to your host's public address
      - WG_HOST=PUBLIC_IP

      #Optional:
      - PASSWORD=PASS_WORD
      - WG_PORT=51820
      - WG_DEFAULT_ADDRESS=10.8.0.x
      - WG_DEFAULT_DNS=168.126.63.1
      - WG_MTU=1420
      - WG_ALLOWED_IPS=192.168.0.0/16,10.0.0.0/16,172.16.0.0/16

    image: weejewel/wg-easy
    container_name: wg-easy
    volumes:
      - /data/wireguard/data:/etc/wireguard
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
EOF
        ;;

    traefik.yml)
        cat >"$file_path" <<'EOF'
version: "3.3"

services:

  traefik:
    image: "traefik:v2.9"
    container_name: "traefik"
    command:
      #- "--log.level=DEBUG"
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
      - "8080:8080"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"

  whoami:
    image: "traefik/whoami"
    container_name: "simple-service"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.rule=Host(`whoami.localhost`)"
      - "traefik.http.routers.whoami.entrypoints=web"
EOF
        ;;

    wordpress.yml)
        cat >"$file_path" <<'EOF'
version: '3.9'

services:
  db:
    image: mysql:latest
    volumes:
    - ./db:/var/lib/mysql
    restart: unless-stopped
    environment:
    - MYSQL_ROOT_PASSWORD=wppass
    - MYSQL_DATABASE=wp
    - MYSQL_USER=wp
    - MYSQL_PASSWORD=wppass
    networks:
    - wordpress

  wordpress:
    depends_on:
    - db
    image: wordpress:latest
    ports:
    - "8080:80"
    restart: unless-stopped
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wp
      WORDPRESS_DB_PASSWORD: wppass
      WORDPRESS_DB_NAME: wp
    volumes:
    - ./data:/var/www/html

    networks:
    - wordpress

  phpmyadmin:
    depends_on:
      - db
    image: phpmyadmin/phpmyadmin
    environment:
      PMA_HOSTS: db
    ports:
      - 3300:80
    networks:
      - wordpress

networks:
  wordpress: {}
EOF
        ;;

    guacamole.yml)
        cat >"$file_path" <<'EOF'
####################################################################################
# docker-compose file for Apache Guacamole
# created by PCFreak 2017-06-28
#
# Apache Guacamole is a clientless remote desktop gateway. It supports standard
# protocols like VNC, RDP, and SSH. We call it clientless because no plugins or
# client software are required. Thanks to HTML5, once Guacamole is installed on
# a server, all you need to access your desktops is a web browser.
####################################################################################
#
# What does this file do?
#
# Using docker-compose it will:
#
# - create a network 'guacnetwork_compose' with the 'bridge' driver.
# - create a service 'guacd_compose' from 'guacamole/guacd' connected to 'guacnetwork'
# - create a service 'postgres_guacamole_compose' (1) from 'postgres' connected to 'guacnetwork'
# - create a service 'guacamole_compose' (2)  from 'guacamole/guacamole/' conn. to 'guacnetwork'
# - create a service 'nginx_guacamole_compose' (3) from 'nginx' connected to 'guacnetwork'
#
# (1)
#  DB-Init script is in './init/initdb.sql' it has been created executing
#  'docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --postgres > ./init/initdb.sql'
#  once.
#  DATA-DIR       is in './data'
#  If you want to change the DB password change all lines with 'POSTGRES_PASSWORD:' and
#  change it to your needs before first start.
#  To start from scratch delete './data' dir completely
#  './data' will hold all data after first start!
#  The initdb.d scripts are only executed the first time the container is started
#  (and the database files are empty). If the database files already exist then the initdb.d
#  scripts are ignored (e.g. when you mount a local directory or when docker-compose saves
#  the volume and reuses it for the new container).
#
#  !!!!! MAKE SURE your folder './init' is executable (chmod +x ./init)
#  !!!!! or 'initdb.sql' will be ignored!
#
#  './data' will hold all data after first start!
#
# (2)
#  Make sure you use the same value for 'POSTGRES_USER' and 'POSTGRES_PASSWORD'
#  as configured under (1)
#
# (3)
#  ./nginx/templates folder will be mapped read-only into the container at /etc/nginx/templates
#  and according to the official nginx container docs the guacamole.conf.template will be
#  placed in /etc/nginx/conf.d/guacamole.conf after container startup.
#  ./nginx/ssl will be mapped into the container at /etc/nginx/ssl
#  prepare.sh creates a a self-signed certificate. If you want to use your own certs
#  just remove the part that generates the certs from prepare.sh and replace
#  'self-ssl.key' and 'self.cert' with your certificate.
#  nginx will export port 8443 to the outside world, make sure that this port is reachable
#  on your system from the "outside world". All other traffic is only internal.
#
#  You could remove the entire 'nginx' service from this file if you want to use your own
#  reverse proxy in front of guacamole. If doing so, make sure you change the line
#   from     - 8080/tcp
#   to       - 8080:8080/tcp
#  within the 'guacamole' service. This will expose the guacamole webinterface directly
#  on port 8080 and you can use it for your own purposes.
#  Note: Guacamole is available on :8080/guacamole, not /.
#
# !!!!! FOR INITAL SETUP (after git clone) run ./prepare.sh once
#
# !!!!! FOR A FULL RESET (WILL ERASE YOUR DATABASE, YOUR FILES, YOUR RECORDS AND CERTS) DO A
# !!!!!  ./reset.sh
#
#
# The initial login to the guacamole webinterface is:
#
#     Username: guacadmin
#     Password: guacadmin
#
# Make sure you change it immediately!
#
# version            date              comment
# 0.1                2017-06-28        initial release
# 0.2                2017-10-09        minor fixes + internal GIT push
# 0.3                2017-10-09        minor fixes + public GIT push
# 0.4                2019-08-14        creating of ssl certs now in prepare.sh
#                                      simplified nginx startup commands
# 0.5                2023-02-24        nginx now uses a template + some minor changes
# 0.6                2023-03-23        switched to postgres 15.2-alpine
#####################################################################################

version: '2.0'

# networks
# create a network 'guacnetwork_compose' in mode 'bridged'
networks:
  guacnetwork_compose:
    driver: bridge

# services
services:
  # guacd
  guacd:
    container_name: guacd_compose
    image: guacamole/guacd
    networks:
      guacnetwork_compose:
    restart: always
    volumes:
    - ./drive:/drive:rw
    - ./record:/record:rw
  # postgres
  postgres:
    container_name: postgres_guacamole_compose
    environment:
      PGDATA: /var/lib/postgresql/data/guacamole
      POSTGRES_DB: guacamole_db
      POSTGRES_PASSWORD: 'ChooseYourOwnPasswordHere1234'
      POSTGRES_USER: guacamole_user
    image: postgres:15.2-alpine
    networks:
      guacnetwork_compose:
    restart: always
    volumes:
    - ./init:/docker-entrypoint-initdb.d:z
    - ./data:/var/lib/postgresql/data:Z

  # guacamole
  guacamole:
    container_name: guacamole_compose
    depends_on:
    - guacd
    - postgres
    environment:
      GUACD_HOSTNAME: guacd
      POSTGRES_DATABASE: guacamole_db
      POSTGRES_HOSTNAME: postgres
      POSTGRES_PASSWORD: 'ChooseYourOwnPasswordHere1234'
      POSTGRES_USER: guacamole_user
    image: guacamole/guacamole
    links:
    - guacd
    networks:
      guacnetwork_compose:
    ports:
## enable next line if not using nginx
##    - 8080:8080/tcp # Guacamole is on :8080/guacamole, not /.
## enable next line when using nginx
    - 8080/tcp
    restart: always

########### optional ##############
  # nginx
  nginx:
   container_name: nginx_guacamole_compose
   restart: always
   image: nginx
   volumes:
   - ./nginx/templates:/etc/nginx/templates:ro
   - ./nginx/ssl/self.cert:/etc/nginx/ssl/self.cert:ro
   - ./nginx/ssl/self-ssl.key:/etc/nginx/ssl/self-ssl.key:ro
   ports:
   - 8443:443
   links:
   - guacamole
   networks:
     guacnetwork_compose:
####################################################################################
EOF
        ;;

    nginx-proxy-manager.yml)
        cat >"$file_path" <<'EOF'
version: '3.8'
services:
  app:
    image: 'docker.io/jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt

EOF
        ;;

    npm.yml)
        cat >"$file_path" <<'EOF'
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      # These ports are in format <host-port>:<container-port>
      - '80:80' # Public HTTP Port
      - '443:443' # Public HTTPS Port
      - '81:81' # Admin Web Port
      # Add any other Stream port you want to expose
      # - '21:21' # FTP
    environment:
      # Mysql/Maria connection parameters:
      DB_MYSQL_HOST: "db"
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: "npm"
      DB_MYSQL_PASSWORD: "npm"
      DB_MYSQL_NAME: "npm"
      # Uncomment this if IPv6 is not enabled on your host
      # DISABLE_IPV6: 'true'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    depends_on:
      - db

  db:
    image: 'jc21/mariadb-aria:latest'
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: 'npm'
      MYSQL_DATABASE: 'npm'
      MYSQL_USER: 'npm'
      MYSQL_PASSWORD: 'npm'
    volumes:
      - ./mysql:/var/lib/mysql
EOF
        ;;

    lamp.yml)
        cat >"$file_path" <<'EOF'
# docker-compose.yml (php:8-apache 기반 + Dockerfile 빌드, mysql:8 사용)
version: '3.8'

services:
  # 웹서버 + PHP 통합 (커스텀 Dockerfile 사용)
  app: # 서비스 이름을 그냥 'app'으로 변경 (기존 apache+php 분리했을 때처럼)
    build:
      context: . # Dockerfile 이 있는 경로 (현재 폴더 .)
      dockerfile: Dockerfile.php # 사용할 Dockerfile 이름 지정
    container_name: lamp_php_apache_app # 컨테이너 이름은 원하는대로
    ports:
      - "8080:80" # 호스트 8080 -> 컨테이너 80 (Apache 기본 포트)
    volumes:
      # PHP/HTML 소스코드를 컨테이너의 기본 웹 루트에 마운트
      - ./www:/var/www/html
      # (선택) 필요한 PHP 커스텀 설정 (php.ini) 마운트
      # - ./my-php.ini:/usr/local/etc/php/conf.d/custom.ini
    networks:
      - lamp_network
    depends_on:
      - db # DB 서비스가 먼저 시작되도록 의존성 설정
    restart: unless-stopped
    # environment: # PHP 스크립트에서 사용할 환경 변수 설정 (예시)
    #   - DB_HOST=db
    #   - DB_DATABASE=mydatabase
    #   - DB_USERNAME=myuser
    #   - DB_PASSWORD=mypassword # 실제로는 .env 파일 사용 권장!

  # 데이터베이스 (MySQL 8 버전대 사용 - 특정 버전 명시 권장)
  db:
    image: mysql:latest # MySQL 8.0 버전 명시
    # image: mysql:8 # MySQL 8 버전대를 사용해도 되지만, 8.0 처럼 명시하는게 더 안정적
    container_name: lamp_mysql_db
    environment:
      MYSQL_DATABASE: mydatabase
      MYSQL_USER: myuser
      MYSQL_PASSWORD: mypassword # 실제로는 .env 파일 사용 권장!
      MYSQL_ROOT_PASSWORD: myrootpassword # 실제로는 .env 파일 사용 권장!
      MYSQL_DEFAULT_AUTHENTICATION_PLUGIN: mysql_native_password
    volumes:
      #- db_data:/var/lib/mysql # 이름있는 볼륨 사용 (추천!)
      - ./db_data:/var/lib/mysql # 또는 로컬 바인드 마운트 사용
    networks:
      - lamp_network
    restart: unless-stopped

  # phpMyAdmin (버전 명시 권장)
  phpmyadmin:
    image: phpmyadmin:latest # 특정 버전 사용 권장
    container_name: lamp_phpmyadmin
    restart: unless-stopped
    ports:
      - "8081:80" # 호스트 8081 -> 컨테이너 80
    environment:
      PMA_HOST: db # 'db' 서비스 컨테이너에 연결
      MYSQL_ROOT_PASSWORD: myrootpassword # 실제로는 .env 파일 사용 권장!
    networks:
      - lamp_network
    depends_on:
      - db # DB 서비스가 먼저 시작되도록 의존성 설정

networks:
  lamp_network:
    driver: bridge

volumes:
  # MySQL 데이터 영속화를 위한 이름있는 볼륨 정의
  db_data:
EOF
        ;;

    lemp.yml)
        cat >"$file_path" <<'EOF'
# /data/lemp/docker-compose.yml (Latest Version)
version: '3.8'

services:
  # 1. 웹서버 (Nginx - latest stable on Alpine)
  web:
    # 'alpine' 태그는 보통 해당 이미지의 최신 안정화 버전을 Alpine 기반으로 제공함
    image: nginx:alpine
    container_name: lemp_nginx_www_latest # 이름 뒤에 _latest 추가 (선택)
    ports:
      - "8080:80"
    volumes:
      - ./www:/var/www/html:ro
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - lemp_network
    depends_on:
      - app
    restart: unless-stopped

  # 2. PHP 처리 엔진 (PHP-FPM - latest stable on Alpine)
  app:
    # 변경! 버전 번호 빼고 'fpm-alpine' -> 최신 안정 PHP FPM (Alpine) 이미지
    # image: php:fpm-alpine # build 로 조정
    # image: php:8.1-fpm-alpine
    build:
      context: . # Dockerfile 이 있는 경로 (현재 폴더 .)
      dockerfile: Dockerfile.php # 사용할 Dockerfile 이름 지정
    container_name: lemp_php_www_latest # 이름 뒤에 _latest 추가 (선택)
    volumes:
      - ./www:/var/www/html
    networks:
      - lemp_network
    depends_on:
      - db
    restart: unless-stopped

  # 3. 데이터베이스 (MySQL - latest stable)
  db:
    # 변경! 버전 번호 빼고 'latest' -> 최신 안정 MySQL 이미지
    image: mysql:latest
    # image: mysql:8.0
    container_name: lemp_mysql_www_latest # 이름 뒤에 _latest 추가 (선택)
    environment:
      # 경고: 실제 환경에서는 환경변수 파일을 사용하세요!
      MYSQL_DATABASE: mydatabase
      MYSQL_USER: myuser
      MYSQL_PASSWORD: mypassword
      MYSQL_ROOT_PASSWORD: myrootpassword
    volumes:
      - ./db_data:/var/lib/mysql
    networks:
      - lemp_network
    restart: unless-stopped

  # --- phpMyAdmin 서비스 추가! ---
  phpmyadmin:
    image: phpmyadmin:latest # 최신 버전 사용 (실제론 버전 명시 추천!)
    container_name: lemp_phpmyadmin
    restart: unless-stopped
    ports:
      - "8081:80" # 호스트 8081 포트로 접속 (8080은 Nginx가 쓰니깐 피해서)
    environment:
      PMA_HOST: db # 여기가 핵심! 연결할 DB 호스트 = 서비스 이름 'db'
      # PMA_PORT: 3306 # MySQL 기본 포트라 보통 생략 가능
      MYSQL_ROOT_PASSWORD: myrootpassword # DB 루트 비번 알려줘야 함 (보안주의!)
      #MYSQL_USER: myuser # 로그인 페이지에 기본 사용자명 제안 (선택)
      #MYSQL_PASSWORD: mypassword # 로그인 페이지에 기본 비번 제안 (선택, 비추!)
      UPLOAD_LIMIT: 1G # 혹시 phpMyAdmin으로 대용량 SQL 파일 업로드할 일 있으면 (선택)
    networks:
      - lemp_network # DB랑 같은 네트워크에 있어야 함
    depends_on: # DB 서비스가 먼저 뜨도록 설정
      - db

# 네트워크 정의
networks:
  lemp_network:
    driver: bridge
EOF
        ;;

    nginx.conf)
        cat >"$file_path" <<'EOF'
# /data/lemp/nginx.conf
server {
    listen 80;
    server_name localhost;
    # 컨테이너 내부의 웹 루트 경로. docker-compose.yml 에서 호스트의 /data/lemp/www 와 연결됨.
    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass app:9000; # 서비스 이름 'app'으로 PHP-FPM 컨테이너 연결
        fastcgi_index index.php;
        include fastcgi_params;
        # 컨테이너 내부 경로 기준 스크립트 파일명 지정
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
        ;;

    dk_lamp_index.php)
        cat >"$file_path" <<'EOF'
<?php

// MySQL 접속 테스트
$host = 'db'; // 서비스 이름 'db'
$dbname = 'mydatabase'; // docker-compose.yml 에서 설정한 값
$user = 'myuser';       // docker-compose.yml 에서 설정한 값
$pass = 'mypassword';   // docker-compose.yml 에서 설정한 값 (주의!)

try {
    $dbh = new PDO("mysql:host=$host;dbname=$dbname", $user, $pass);
    echo "<h1>lamp Stack is working! (Web Root: ./www)</h1>";
    echo "<p>PHP is processing files correctly.</p>";
    echo "<p>Successfully connected to MySQL database '$dbname'!</p>";
    $dbh = null;
} catch (PDOException $e) {
    echo "<h1>lamp Stack - PHP OK, but DB Connection Failed!</h1>";
    echo "<p>Could not connect to MySQL: " . $e->getMessage() . "</p>";
    echo "<p>Check DB container status and docker-compose.yml environment variables.</p>";
}

// PHP 정보 출력
phpinfo();

?>
EOF
        ;;

    dockerfile-cms.php)
        cat >"$file_path" <<'EOF'
# ./Dockerfile.php (종합선물세트 최종 버전)

# 안정적인 Debian 기반 PHP-Apache 이미지 선택 (예: PHP 8.2)
# CMS 호환성을 위해 8.1 이나 8.0 도 고려 가능
FROM php:8.2-apache

# 시스템 라이브러리 업데이트 및 필요 패키지 설치
# (gd, intl, mbstring, curl, xml, zip, sockets, exif, xsl, sodium 등 관련 라이브러리)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libxml2-dev \
    libicu-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    libsodium-dev \
    libxslt-dev \
    # 이미지 처리 필요시: imagemagick libmagickwand-dev
    # 기타 유틸리티 (선택 사항): git unzip wget vim nano
    git unzip wget vim nano \
    && rm -rf /var/lib/apt/lists/*


ARG PHP_EXTENSIONS="gd mysqli pdo pdo_mysql mbstring curl xml zip iconv intl sodium xsl exif sockets opcache"

# RUN 명령어 하나 안에서 셸 스크립트 실행
RUN set -e; \
    # 필요한 사전 설정 (예: gd)
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    \
    # 확장 목록을 공백 기준으로 반복 처리
    for ext in $PHP_EXTENSIONS; do \
        echo "---------- Installing $ext ----------"; \
        # docker-php-ext-install 실행 (동시 빌드 옵션 -j 는 빼는게 더 안정적일 수 있음)
        docker-php-ext-install "$ext"; \
        # 성공 메시지 (선택 사항)
        echo "---------- Successfully installed $ext ----------"; \
    done;

    # 이미지매직 설치 (주석 처리됨 - 필요시 아래 라인 활성화)
    # echo "---------- Installing imagick (optional) ----------";
    # pecl install imagick && docker-php-ext-enable imagick; \
    # echo "---------- Successfully installed imagick ----------";

    # 설치 후 정리 (선택 사항)
    # apt-get purge -y ... (빌드 의존성 제거)
    # rm -rf /tmp/* /var/lib/apt/lists/*


# 아파치 mod_rewrite 활성화 (htaccess 사용 위해 필수!)
RUN a2enmod rewrite

RUN sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
    && echo "Applied AllowOverride All to /etc/apache2/apache2.conf"

# (선택 사항) 기본적인 PHP 설정 파일 복사
#COPY ./configs/php-general.ini /usr/local/etc/php/conf.d/zz-general.ini

# (선택 사항) 아파치 설정 커스터마이징 (예: AllowOverride 확인/변경)
#COPY ./configs/apache-custom.conf /etc/apache2/conf-available/custom.conf
#RUN a2enconf custom

WORKDIR /var/www/html

# 아파치 기본 실행 (베이스 이미지에 정의되어 있음)
# CMD ["apache2-foreground"]
EOF
        ;;

    dockerfile.php)
        cat >"$file_path" <<'EOF'
FROM php:8-apache
RUN docker-php-ext-install pdo_mysql
EOF
        ;;

    dk_lemp_index.php)
        cat >"$file_path" <<'EOF'
<?php

// MySQL 접속 테스트
$host = 'db'; // 서비스 이름 'db'
$dbname = 'mydatabase'; // docker-compose.yml 에서 설정한 값
$user = 'myuser';       // docker-compose.yml 에서 설정한 값
$pass = 'mypassword';   // docker-compose.yml 에서 설정한 값 (주의!)

try {
    $dbh = new PDO("mysql:host=$host;dbname=$dbname", $user, $pass);
    echo "<h1>LEMP Stack is working! (Web Root: ./www)</h1>";
    echo "<p>PHP is processing files correctly.</p>";
    echo "<p>Successfully connected to MySQL database '$dbname'!</p>";
    $dbh = null;
} catch (PDOException $e) {
    echo "<h1>LEMP Stack - PHP OK, but DB Connection Failed!</h1>";
    echo "<p>Could not connect to MySQL: " . $e->getMessage() . "</p>";
    echo "<p>Check DB container status and docker-compose.yml environment variables.</p>";
}

// PHP 정보 출력
phpinfo();

?>
EOF
        ;;

    media.yml)
        cat >"$file_path" <<'EOF'
# /data/media_center/docker-compose.yml (File Browser 강화!)
version: '3.8'

services:
  # --- 1. Jellyfin (기존 설정 유지 - 단, 볼륨 경로는 읽기/쓰기(rw)로!) ---
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: media_jellyfin
    environment:
      PUID: 1000
      PGID: 1000
      TZ: Asia/Seoul
    volumes:
      - ./jellyfin_config:/config
      - ./jellyfin_cache:/cache
      # File Browser로 파일 변경할 거니깐 읽기/쓰기(rw) 권한 필요!
      - ./movies:/media/movies:rw
      - ./tvshows:/media/tvshows:rw
    ports:
      - "8096:8096"
    restart: unless-stopped
    networks:
      - media_network

  # --- 2. Navidrome (기존 설정 유지 - 단, 볼륨 경로는 읽기/쓰기(rw)로!) ---
  navidrome:
    image: deluan/navidrome:latest
    container_name: music_navidrome
    user: "1000:1000"
    ports:
      - "4533:4533"
    environment:
      TZ: Asia/Seoul
    volumes:
      - ./navidrome_data:/data
      # File Browser로 파일 변경할 거니깐 읽기/쓰기(rw) 권한 필요!
      - ./music:/music:rw
    restart: unless-stopped
    networks:
      - media_network

  # --- 3. File Browser (웹 UI + WebDAV 서버) ---
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: file_browser
    user: "1000:1000" # PUID:PGID (Jellyfin/Navidrome과 동일하게!)
    ports:
      # 웹 UI 접속 포트 (예: 8082)
      - "8082:80"
      # WebDAV 전용 포트를 따로 열 수도 있음 (선택사항)
      # - "8083:80" # 만약 이렇게 열면 WebDAV 클라이언트는 8083으로 접속
    volumes:
      # 설정 DB 저장 (필수!)
      - ./filebrowser/database.db:/database.db
      # 관리할 호스트 폴더 연결 (필수! 읽기/쓰기!)
      # - ./:/srv
      - ./movies:/srv/movies:rw
      - ./tvshows:/srv/tvshows:rw
      - ./music:/srv/music:rw
    security_opt:
      - apparmor:unconfined
    environment:
      # 기본 로그인 사용자 (admin) 비밀번호 설정 (선택, 초기 admin/admin)
      # FB_PASSWORD: YourSecurePasswordHere
      # WebDAV 접속 경로 설정 (기본값: /webdav)
      FB_WEBDAV: "/webdav"
      # 기본 웹 UI 접속 경로 설정 (선택, 기본값: /)
      # FB_BASEURL: "/files"
      # 시간대 설정
      TZ: Asia/Seoul
    # File Browser 설정 파일(config.json)을 직접 사용 시 command 주석 해제
    # command: ["--config", "/config/config.json"]
    restart: unless-stopped
    networks:
      - media_network

networks:
  media_network:
    driver: bridge
EOF
        ;;

    nextcloud.yml)
        cat >"$file_path" <<'EOF'

version: "3"
services:
  nextcloud:
    image: nextcloud:latest
    restart: always
    ports:
      - "8585:80"
    links:
      - "db:mariadb"
    volumes:
      - /data/nextcloud/nextcloud/:/var/www/html/
      - /data/nextcloud/data/:/var/www/html/data/
      - /data/nextcloud/apps/:/var/www/html/custom_apps/
      - /data/nextcloud/theme/:/var/www/html/themes/
    environment:
      - MYSQL_HOST=mariadb
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=nextcloud
    container_name: nextcloud
    depends_on:
      - db
  db:
    image: mariadb
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=root
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=nextcloud
    volumes:
      - /data/mariadb/data/:/var/lib/mysql/
      - /data/mariadb/log/:/var/lob/mysql/


EOF
        ;;

    playbook.yml)
        cat >"$file_path" <<'EOF'
- name: Install Nginx on various servers
  hosts: all
  become: yes
  gather_facts: yes

  tasks:
  - name: Install Nginx (Apt)
    apt:
      name: nginx
      state: present
      update_cache: yes
    when: "'apt' in ansible_pkg_mgr"

  - name: Install Nginx (Yum)
    yum:
      name: nginx
      state: present
    when: "'yum' in ansible_pkg_mgr"
EOF
        ;;

    playbook_script.yml)
        cat >"$file_path" <<'EOF'
- name: Run script and capture output
  hosts: all
  become: yes
  gather_facts: no

  tasks:
  - name: Execute script
    script: ~/pstree.sample.sh
    register: script_output

  - name: Display script output
    debug:
      var: script_output.stdout_lines

  - name: Save output to a file
    copy:
      content: "{{ script_output.stdout }}"
      dest: "~/playbook.output.txt"

  - name: Append output to a file
    lineinfile:
      path: "~/playbook.output.log.txt"
      line: "{{ script_output.stdout }}"

EOF
        ;;

    certbot.yml)
        cat >"$file_path" <<'EOF'
version: '3'

services:
  nginx:
    image: nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot

  certbot:
    image: certbot/certbot
    restart: unless-stopped
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
EOF
        ;;

    caddy.yml)
        cat >"$file_path" <<'EOF'

version: '3'
services:
  caddy:
    image: caddy/caddy:latest
    container_name: caddy
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./site:/usr/share/caddy
    ports:
      - "80:80"
      - "443:443"
    environment:
      - ACME_AGREE=true
      - ACME_CA=https://acme-v02.api.letsencrypt.org/directory
      - ACME_EMAIL=your_email@example.com
volumes:
  caddy_data:
  caddy_config:


EOF
        ;;

    caddyfile.yml)
        cat >"$file_path" <<'EOF'

example.com {
	root * /usr/share/caddy
	file_server
}

EOF
        ;;

    netplan.yml)
        interface="$(ip link show | awk -F ': ' '/^[0-9]+:/ {gsub(/:$/, "", $2); if ($2 != "lo") print $2}' | head -n1)"
        addresses="$(ip a | grep "$interface" | grep 'inet' | awk '{print $2}')"
        gateway="$(ip route | grep "$interface" | grep 'default' | awk '{print $3}')"
        if [ "$interface" ] && [ "$addresses" ] && [ "$gateway" ]; then
            cat >"$file_path" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      dhcp4: no
      addresses: [$addresses]
      gateway4: $gateway
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF
        else
            cat >"$file_path" <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
      addresses: [192.168.1.100/24]
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF
        fi
        ;;

    rocketchat.yml)
        cat >"$file_path" <<EOF
version: '2'
services:
  rocketchat:
    image: rocketchat/rocket.chat:latest
    restart: unless-stopped
    volumes:
      - ./uploads:/app/uploads
    environment:
      - PORT=3000
      - ROOT_URL=https://$localip1
      - MONGO_URL=mongodb://mongo:27017/rocketchat?replicaSet=rs0
      - MONGO_OPLOG_URL=mongodb://mongo:27017/local
      - MAIL_URL=smtp://smtp.email
    depends_on:
      - mongo
    ports:
      - 3000:3000

  mongo:
    image: mongo:latest
    restart: unless-stopped
    volumes:
     - ./data/db:/data/db
     - ./data/dump:/dump
    command: mongod --oplogSize 128 --replSet rs0 --storageEngine wiredTiger

  mongo-init-replica:
    image: mongo:latest
    #command: 'mongosh --host mongo --eval "rs.initiate({ _id: ''rs0'', members: [ { _id: 0, host: ''mongo:27017'' }] })"'
    entrypoint: ['mongosh', '--host', 'mongo', '--eval', 'rs.initiate({ _id: "rs0", members: [ { _id: 0, host: "mongo:27017" }] }); sleep(1000)']
    depends_on:
      - mongo
EOF
        ;;

    rhymix.yml)
        cat >"$file_path" <<'EOF'
version: '3'

services:

  db:
    image: mariadb:latest
    container_name: db
    restart: unless-stopped
    environment:
      - TZ=Asia/Seoul
      - MYSQL_ROOT_PASSWORD=dbpass
      - MYSQL_DATABASE=dbname
      - MYSQL_USER=dbuser
      - MYSQL_PASSWORD=dbpass
    volumes:
      - ./data/dbdata:/var/lib/mysql

  redis:
    container_name: redis
    image: redis:alpine
    restart: unless-stopped
    volumes:
      - ./data/dataredis:/data
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru --appendonly yes

  php:
    depends_on:
      - db
    build:
      context: ./build
    container_name: php
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=dbpass
      - MYSQL_DATABASE=dbname
      - MYSQL_USER=dbuser
      - MYSQL_PASSWORD=dbpass
    volumes:
      - ./site:/var/www/web
      - ./php/php.ini:/usr/local/etc/php/php.ini
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro

  nginx:
    depends_on:
      - php
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./site:/var/www/web
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./nginx/logs:/var/log/nginx/
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro

EOF
        ;;

    nagios.yml)

        cat >"$file_path" <<'EOF'

version: '3'
services:
  nagios4:
    image: jasonrivers/nagios:latest
    volumes:
      - ./nagios/etc/:/opt/nagios/etc/
      - ./nagios/var:/opt/nagios/var/
      - ./custom-plugins:/opt/Custom-Nagios-Plugins
      - ./nagiosgraph/var:/opt/nagiosgraph/var
      - ./nagiosgraph/etc:/opt/nagiosgraph/etc
    ports:
      - 3080:80
    container_name: nagios4

EOF
        ;;

    php74.docker.yml)

        cat >"$file_path" <<'EOF'
 FROM php:7.4-fpm

 RUN apt-get update && apt-get install -y \
         libfreetype6-dev \
         libjpeg62-turbo-dev \
         libpng-dev \
         libzip-dev \
     && docker-php-ext-configure gd --with-freetype --with-jpeg \
     && docker-php-ext-install -j$(nproc) gd \
     && docker-php-ext-install mysqli pdo_mysql zip exif pcntl bcmath

 RUN pecl install -o -f redis \
 && rm -rf /tmp/pear \
 && docker-php-ext-enable redis

 COPY ./conf/www.conf /usr/local/etc/php-fpm.d/www.conf

 EXPOSE 9000


EOF
        ;;

    cacti.yml)
        cat >"$file_path" <<'EOF'
version: '3'
services:
  cacti:
    image: smcline06/cacti
    ports:
      - 3080:80
    volumes:
      - ./cacti_data:/var/lib/cacti
      - ./cacti_config:/etc/cacti
    environment:
      - TZ=Asia/Seoul

EOF
        ;;

    haos.yml)
        cat >"$file_path" <<'EOF'

version: '3'
services:
  homeassistant:
    container_name: homeassistant
    image: "ghcr.io/home-assistant/home-assistant:stable"
    volumes:
      - ./config:/config
      - /etc/localtime:/etc/localtime:ro
    restart: unless-stopped
    privileged: true
    network_mode: host

EOF
        ;;

    semaphore.yml)
        cat >"$file_path" <<'EOF'

services:
  # uncomment this section and comment out the mysql section to use postgres instead of mysql
  #postgres:
    #restart: unless-stopped
    #image: postgres:14
    #hostname: postgres
    #volumes:
    #  - semaphore-postgres:/var/lib/postgresql/data
    #environment:
    #  POSTGRES_USER: semaphore
    #  POSTGRES_PASSWORD: semaphore
    #  POSTGRES_DB: semaphore
  # if you wish to use postgres, comment the mysql service section below
  mysql:
    restart: unless-stopped
    image: mysql:8.0
    hostname: mysql
    volumes:
      - semaphore-mysql:/var/lib/mysql
    environment:
      MYSQL_RANDOM_ROOT_PASSWORD: 'yes'
      MYSQL_DATABASE: semaphore
      MYSQL_USER: semaphore
      MYSQL_PASSWORD: semaphore
  semaphore:
    restart: unless-stopped
    ports:
      - 3000:3000
    image: semaphoreui/semaphore:latest
    environment:
      SEMAPHORE_DB_USER: semaphore
      SEMAPHORE_DB_PASS: semaphore
      SEMAPHORE_DB_HOST: mysql # for postgres, change to: postgres
      SEMAPHORE_DB_PORT: 3306 # change to 5432 for postgres
      SEMAPHORE_DB_DIALECT: mysql # for postgres, change to: postgres
      SEMAPHORE_DB: semaphore
      SEMAPHORE_PLAYBOOK_PATH: /tmp/semaphore/
      SEMAPHORE_ADMIN_PASSWORD: changeme
      SEMAPHORE_ADMIN_NAME: admin
      SEMAPHORE_ADMIN_EMAIL: admin@localhost
      SEMAPHORE_ADMIN: admin
      SEMAPHORE_ACCESS_KEY_ENCRYPTION: gs72mPntFATGJs9qK0pQ0rKtfidlexiMjYCH9gWKhTU=
      SEMAPHORE_LDAP_ACTIVATED: 'no' # if you wish to use ldap, set to: 'yes'
      SEMAPHORE_LDAP_HOST: dc01.local.example.com
      SEMAPHORE_LDAP_PORT: '636'
      SEMAPHORE_LDAP_NEEDTLS: 'yes'
      SEMAPHORE_LDAP_DN_BIND: 'uid=bind_user,cn=users,cn=accounts,dc=local,dc=shiftsystems,dc=net'
      SEMAPHORE_LDAP_PASSWORD: 'ldap_bind_account_password'
      SEMAPHORE_LDAP_DN_SEARCH: 'dc=local,dc=example,dc=com'
      SEMAPHORE_LDAP_SEARCH_FILTER: "(\u0026(uid=%s)(memberOf=cn=ipausers,cn=groups,cn=accounts,dc=local,dc=example,dc=com))"
    depends_on:
      - mysql # for postgres, change to: postgres
volumes:
  semaphore-mysql: # to use postgres, switch to: semaphore-postgres

EOF
        ;;

    vault.repo)
        cat >"$file_path" <<'EOF'
[vault]
name=CentOS-$releasever - Vault
baseurl=http://vault.centos.org/centos/$releasever/os/$basearch/
enabled=1
gpgcheck=1
exclude=php* pear* httpd* mysql*

EOF
        ;;

    centos-vault.repo)
        cat >"$file_path" <<'EOF'
[base]
name=CentOS-$releasever - Base
baseurl=http://ftp.iij.ad.jp/pub/linux/centos-vault/centos/$releasever/os/$basearch/
gpgcheck=0
priority=1
protect=1
exclude=php* pear* httpd* mysql*

[update]
name=CentOS-$releasever - Updates
baseurl=http://ftp.iij.ad.jp/pub/linux/centos-vault/centos/$releasever/updates/$basearch/
gpgcheck=0
priority=1
protect=1
exclude=php* pear* httpd* mysql*

[extras]
name=CentOS-$releasever - Extras
baseurl=http://ftp.iij.ad.jp/pub/linux/centos-vault/centos/$releasever/extras/$basearch/
gpgcheck=0
priority=1
protect=1
exclude=php* pear* httpd* mysql*

EOF
        ;;

    epel6.repo)
        cat >"$file_path" <<'EOF'
[epel]
name=Extra Packages for Enterprise Linux 6 - $basearch
baseurl=https://archives.fedoraproject.org/pub/archive/epel/6/$basearch/
failovermethod=priority
enabled=1
gpgcheck=0

EOF
        ;;

    postfix.yml)
        cat >"$file_path" <<EOF
# See /usr/share/postfix/main.cf.dist for a commented, more complete version

myhostname=$(hostname)

smtpd_banner = \$myhostname ESMTP \$mail_name (Debian/GNU)
biff = no

# appending .domain is the MUA's job.
append_dot_mydomain = no

# Uncomment the next line to generate "delayed mail" warnings
#delay_warning_time = 4h

alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mydestination = \$myhostname, localhost.\$mydomain, localhost
#relayhost =
mynetworks = 127.0.0.0/8
inet_interfaces = loopback-only
recipient_delimiter = +

compatibility_level = 2

inet_protocols = all
relayhost = smtp.gmail.com:587
smtp_use_tls = yes
smtp_sasl_auth_enable = yes
smtp_sasl_security_options =
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_tls_CAfile = /etc/ssl/certs/Entrust_Root_Certification_Authority.pem
smtp_tls_session_cache_database = btree:/var/lib/postfix/smtp_tls_session_cache
smtp_tls_session_cache_timeout = 3600s

EOF
        ;;

    vimrc1.yml)
        cat >"$file_path" <<'EOF'
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Maintainer:
"       Amir Salihefendic - @amix3k
"
" Awesome_version:
"       Get this config, nice color schemes and lots of plugins!
"
"       Install the awesome version from:
"
"           https://github.com/amix/vimrc
"
" Sections:
"    -> General
"    -> VIM user interface
"    -> Colors and Fonts
"    -> Files and backups
"    -> Text, tab and indent related
"    -> Visual mode related
"    -> Moving around, tabs and buffers
"    -> Status line
"    -> Editing mappings
"    -> vimgrep searching and cope displaying
"    -> Spell checking
"    -> Misc
"    -> Helper functions
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => General
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Sets how many lines of history VIM has to remember
set history=500

" Enable filetype plugins
filetype plugin on
filetype indent on

" Set to auto read when a file is changed from the outside
set autoread
au FocusGained,BufEnter * silent! checktime

" With a map leader it's possible to do extra key combinations
" like <leader>w saves the current file
let mapleader = ","

" Fast saving
nmap <leader>w :w!<cr>

" :W sudo saves the file
" (useful for handling the permission-denied error)
command! W execute 'w !sudo tee % > /dev/null' <bar> edit!


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => VIM user interface
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Set 7 lines to the cursor - when moving vertically using j/k
set so=7

" Avoid garbled characters in Chinese language windows OS
let $LANG='en'
set langmenu=en
source $VIMRUNTIME/delmenu.vim
source $VIMRUNTIME/menu.vim

" Turn on the Wild menu
set wildmenu

" Ignore compiled files
set wildignore=*.o,*~,*.pyc
if has("win16") || has("win32")
    set wildignore+=.git\*,.hg\*,.svn\*
else
    set wildignore+=*/.git/*,*/.hg/*,*/.svn/*,*/.DS_Store
endif

" Always show current position
set ruler

" Height of the command bar
set cmdheight=1

" A buffer becomes hidden when it is abandoned
set hid

" Configure backspace so it acts as it should act
set backspace=eol,start,indent
set whichwrap+=<,>,h,l

" Ignore case when searching
set ignorecase

" When searching try to be smart about cases
set smartcase

" Highlight search results
set hlsearch

" Makes search act like search in modern browsers
set incsearch

" Don't redraw while executing macros (good performance config)
set lazyredraw

" For regular expressions turn magic on
set magic

" Show matching brackets when text indicator is over them
set showmatch

" How many tenths of a second to blink when matching brackets
set mat=2

" No annoying sound on errors
set noerrorbells
set novisualbell
set t_vb=
set tm=500

" Properly disable sound on errors on MacVim
if has("gui_macvim")
    autocmd GUIEnter * set vb t_vb=
endif

" Add a bit extra margin to the left
"set foldcolumn=1


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Colors and Fonts
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Enable syntax highlighting
syntax enable

" Set regular expression engine automatically
set regexpengine=0

 " Enable 256 colors palette in Gnome Terminal
 if &t_Co > 2 || has("gui_running")
   syntax on
   set hlsearch
 endif

set background=dark

" Set extra options when running in GUI mode
if has("gui_running")
    set guioptions-=T
    set guioptions-=e
    set t_Co=256
    set guitablabel=%M\ %t
endif

" Set utf8 as standard encoding and en_US as the standard language
set encoding=utf8

" Use Unix as the standard file type
set ffs=unix,dos,mac


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Files, backups and undo
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Turn backup off, since most stuff is in SVN, git etc. anyway...
"set nobackup
"set nowb
"set noswapfile


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Text, tab and indent related
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Use spaces instead of tabs
set expandtab

" Be smart when using tabs ;)
set smarttab

" 1 tab == 4 spaces
set shiftwidth=4
set tabstop=4

" Linebreak on 500 characters
set lbr
set tw=500

set ai "Auto indent
set si "Smart indent
set wrap "Wrap lines


""""""""""""""""""""""""""""""
" => Visual mode related
""""""""""""""""""""""""""""""
" Visual mode pressing * or # searches for the current selection
" Super useful! From an idea by Michael Naumann
vnoremap <silent> * :<C-u>call VisualSelection('', '')<CR>/<C-R>=@/<CR><CR>
vnoremap <silent> # :<C-u>call VisualSelection('', '')<CR>?<C-R>=@/<CR><CR>


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Moving around, tabs, windows and buffers
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Map <Space> to / (search) and Ctrl-<Space> to ? (backwards search)
map <space> /
map <C-space> ?

" Disable highlight when <leader><cr> is pressed
map <silent> <leader><cr> :noh<cr>

" Smart way to move between windows
map <C-j> <C-W>j
map <C-k> <C-W>k
map <C-h> <C-W>h
map <C-l> <C-W>l

" Close the current buffer
map <leader>bd :Bclose<cr>:tabclose<cr>gT

" Close all the buffers
map <leader>ba :bufdo bd<cr>

map <leader>l :bnext<cr>
map <leader>h :bprevious<cr>

" Useful mappings for managing tabs
map <leader>tn :tabnew<cr>
map <leader>to :tabonly<cr>
map <leader>tc :tabclose<cr>
map <leader>tm :tabmove
map <leader>t<leader> :tabnext<cr>

" Let 'tl' toggle between this and the last accessed tab
let g:lasttab = 1
nmap <leader>tl :exe "tabn ".g:lasttab<CR>
au TabLeave * let g:lasttab = tabpagenr()


" Opens a new tab with the current buffer's path
" Super useful when editing files in the same directory
map <leader>te :tabedit <C-r>=escape(expand("%:p:h"), " ")<cr>/

" Switch CWD to the directory of the open buffer
map <leader>cd :cd %:p:h<cr>:pwd<cr>

" Specify the behavior when switching between buffers
try
  set switchbuf=useopen,usetab,newtab
  set stal=2
catch
endtry

" Return to last edit position when opening files (You want this!)
au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif


""""""""""""""""""""""""""""""
" => Status line
""""""""""""""""""""""""""""""
" Always show the status line
set laststatus=2

" Format the status line
set statusline=\ %{HasPaste()}%F%m%r%h\ %w\ \ CWD:\ %r%{getcwd()}%h\ \ \ Line:\ %l\ \ Column:\ %c


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Editing mappings
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Remap VIM 0 to first non-blank character
map 0 ^

" Move a line of text using ALT+[jk] or Command+[jk] on mac
nmap <M-j> mz:m+<cr>`z
nmap <M-k> mz:m-2<cr>`z
vmap <M-j> :m'>+<cr>`<my`>mzgv`yo`z
vmap <M-k> :m'<-2<cr>`>my`<mzgv`yo`z

if has("mac") || has("macunix")
  nmap <D-j> <M-j>
  nmap <D-k> <M-k>
  vmap <D-j> <M-j>
  vmap <D-k> <M-k>
endif

" Delete trailing white space on save, useful for some filetypes ;)
fun! CleanExtraSpaces()
    let save_cursor = getpos(".")
    let old_query = getreg('/')
    silent! %s/\s\+$//e
    call setpos('.', save_cursor)
    call setreg('/', old_query)
endfun

if has("autocmd")
    autocmd BufWritePre *.txt,*.js,*.py,*.wiki,*.sh,*.coffee :call CleanExtraSpaces()
endif


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Spell checking
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Pressing ,ss will toggle and untoggle spell checking
map <leader>ss :setlocal spell!<cr>

" Shortcuts using <leader>
map <leader>sn ]s
map <leader>sp [s
map <leader>sa zg
map <leader>s? z=


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Misc
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Remove the Windows ^M - when the encodings gets messed up
noremap <Leader>m mmHmt:%s/<C-V><cr>//ge<cr>'tzt'm

" Quickly open a buffer for scribble
map <leader>q :e ~/buffer<cr>

" Quickly open a markdown buffer for scribble
map <leader>x :e ~/buffer.md<cr>

" Toggle paste mode on and off
map <leader>pp :setlocal paste!<cr>


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Helper functions
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Returns true if paste mode is enabled
function! HasPaste()
    if &paste
        return 'PASTE MODE  '
    endif
    return ''
endfunction

" Don't close window, when deleting a buffer
command! Bclose call <SID>BufcloseCloseIt()
function! <SID>BufcloseCloseIt()
    let l:currentBufNum = bufnr("%")
    let l:alternateBufNum = bufnr("#")

    if buflisted(l:alternateBufNum)
        buffer #
    else
        bnext
    endif

    if bufnr("%") == l:currentBufNum
        new
    endif

    if buflisted(l:currentBufNum)
        execute("bdelete! ".l:currentBufNum)
    endif
endfunction

function! CmdLine(str)
    call feedkeys(":" . a:str)
endfunction

function! VisualSelection(direction, extra_filter) range
    let l:saved_reg = @"
    execute "normal! vgvy"

    let l:pattern = escape(@", "\\/.*'$^~[]")
    let l:pattern = substitute(l:pattern, "\n$", "", "")

    if a:direction == 'gv'
        call CmdLine("Ack '" . l:pattern . "' " )
    elseif a:direction == 'replace'
        call CmdLine("%s" . '/'. l:pattern . '/')
    endif

    let @/ = l:pattern
    let @" = l:saved_reg
endfunction

 " 단순 백업 설정 - 파일명_날짜시간.bak 형식
 function! MakeBackup()
   " 기본 백업 디렉토리 확인 및 생성
   let l:backupdir = $HOME."/.vim/backup"
   if !isdirectory(l:backupdir)
     call mkdir(l:backupdir, "p")
  endif

   " 파일명과 타임스탬프를 결합한 백업 파일명 생성
   let l:filename = expand("%:t")
   let l:timestamp = strftime("%Y%m%d_%H%M%S")
   let l:backupfile = l:backupdir."/".l:filename."_".l:timestamp.".bak"

   " 백업 파일 생성
   execute "silent !cp " . shellescape(expand("%:p")) . " " . shellescape(l:backupfile)
 endfunction

 autocmd BufWritePre * call MakeBackup()
 set fileencodings=utf8,euc-kr
 set paste
 set pastetoggle=<F2>
 set t_ti= t_te=

 if v:version >= 703
   let undodir=$HOME."/.vim/undo"
   if !isdirectory(undodir)
     call mkdir(undodir, "p")
   endif
   set undofile
   set undodir=$HOME/.vim/undo
   set undolevels=1000
   set undoreload=10000
 endif


EOF
        ;;

    vimrc2.yml)
        cat >"$file_path" <<'EOF'
" Arcy's vim environment (based on perky's)

let g:Arcy="4.9"

let mapleader="\<Space>"

set nocompatible
"set fileformat=unix
set formatoptions=tcql
set ai
"set laststatus=2
"set wrapmargin=2
set visualbell
set mat=3 showmatch
"set term=xterm
"set nu

set bs=2                " allow backspacing over everything in insert mode
"set nobackup          " do not keep a backup file, use versions instead

set viminfo='100,<50    " read/write a .viminfo file, don't store more
                        " than 100 lines of registers
set history=500         " keep 500 lines of command line history
set ruler               " show the cursor position all the time

set list lcs=tab:\|.,trail:~    " display tab as >------, and trail as ~

set fencs=utf-8,cp949,euc-kr,ucs-bom,latin1

set incsearch           " incremental searching
set ignorecase smartcase

set wildmenu

" netrw setting
let g:netrw_winsize = -28
let g:netrw_chgwin = -1
let g:netrw_browse_split = 0
let g:netrw_banner = 0
let g:netrw_liststyle = 3
" https://vi.stackexchange.com/questions/7889/cannot-exit-vim-even-using-q
" Per default, netrw leaves unmodified buffers open. This autocommand
" deletes netrw's buffer once it's hidden (using ':q', for example)
autocmd FileType netrw setl bufhidden=delete

if v:version >= 703
  let undodir=$HOME."/.vim/undo"
  if !isdirectory(undodir)
    call mkdir(undodir, "p")
  endif
  set undofile                " Save undo's after file closes
  set undodir=$HOME/.vim/undo " where to save undo histories
  set undolevels=1000         " How many undos
  set undoreload=10000        " number of lines to save for undo
endif

" Switch syntax highlighting on, when the terminal has colors
" Also switch on highlighting the last used search pattern.
if &t_Co > 2 || has("gui_running")
  syntax on
  set hlsearch
endif

" Force encoding as UTF-8, in cygwin ssh enviroment
if stridx(&term, "xterm") >= 0 && stridx($USERDOMAIN, "NT AUTHORITY") >= 0
  set enc=utf-8
endif

" Update function
if has("eval")
  fun! Updateit()
    " Install Vundle
    if !isdirectory($HOME."/.vim/bundle")
      !git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
    endif

    BundleInstall

    " Update vimrc
    winc n
    ,!uname -s
    yank
    undo
    winc c
    let os = @
    if stridx(os, "FreeBSD") >= 0
      !fetch -o ~/.vimrc.new https://arcy.org/.vimrc
    else
      !curl -o ~/.vimrc.new https://arcy.org/.vimrc
    endif

    if match(readfile($HOME."/.vimrc.new"), "\" Arcy") != 0
      echo "Error while downloading new vimrc"
      echo readfile($HOME."/.vimrc.new")
      return
    endif
    !mv ~/.vimrc.new ~/.vimrc
  endfun
endif

set background=dark

set <S-F1>=O2P
set <S-F2>=O2Q
set <S-F3>=O2R
set <S-F4>=O2S

map <S-F1> :echo "Arcy's environment version " g:Arcy<cr>
map <S-F2> :call Updateit()<CR>:source ~/.vimrc<CR>
map <F3> :Lexplore<cr>
map <S-F3> :bd<cr>
map <F4> :up<cr>
imap <F4> <ESC>:up<CR>a
map <S-F4> :q<cr>
map <F9> :<C-U>exec v:count1 . "cp"<CR>
map <F10> :<C-U>exec v:count1 . "cn"<CR>
map <S-F9> :bp<cr>
map <S-F10> :bn<cr>
map <F11> :N<cr>
map <F12> :n<cr>
map <S-F11> :tN<cr>
map <S-F12> :tn<cr>
map <C-j> <C-w>j
map <C-k> <C-w>k
map <C-h> <C-w>h
map <C-l> <C-w>l
map <C-n> <C-w>n
map <C-;> :redr!<cr>
map <C-i> :tabprev<cr>
map <C-p> :tabnext<cr>
map <C-m> :tabnew<cr>

" Leader mapping
noremap <Leader>b :term bash<CR>
noremap <Leader>t :Sexplore<CR>
noremap <Leader>T :Texplore<CR>
noremap <Leader>gs :Git<CR>
noremap <Leader>gd :Gdiff<CR>
noremap <Leader>ge :Gedit<CR>
noremap <Leader>gg :Ggrep <C-R><C-W><CR>
noremap <Leader>du :diffupdate<CR>
noremap <Leader>r :set relativenumber! nu!<CR>
noremap <Leader>p :set paste!<CR>
set pastetoggle=<F2>

" Disable man page
nnoremap K <nop>
" Disable ex mode
nmap Q q

" Command mode remap
cnoremap <C-a> <Home>
cnoremap <C-e> <End>
cnoremap <Esc>b <S-Left>
cnoremap <Esc>f <S-Right>

" Alt-Backspace to delete a word
inoremap <Esc><Backspace> <C-w>
cnoremap <Esc><Backspace> <C-w>

"map D o/*<cr> * <cr>*/<esc>ka

" Auto close tag with HTML files
function! s:CloseTags()
  imap <C--> <lt>/<C-x><C-o>
endfunction
autocmd BufRead,BufNewFile *.html,*.js,*.xml,*.vue call s:CloseTags()

" show relavite line number from cursor
augroup numbertoggle
  autocmd!
  autocmd VimEnter,WinEnter,BufWinEnter * setlocal relativenumber number
  autocmd WinLeave * setlocal norelativenumber number
augroup END

au BufNewFile,BufRead *.c          set si
au BufNewFile,BufRead *.php        set si et sw=4 sts=4
au BufNewFile,BufRead *.py         set si et sw=4 sts=4
au BufNewFile,BufRead *.html,*.css set sw=8 sts=8 noet
au BufNewFile,BufRead *.js,*.ts    set et sw=2 sts=2
au BufNewFile,BufRead *.rdf        set et sw=2 sts=2
au BufNewFile,BufRead *.vue        setlocal filetype=vue.html.javascript.css


" Load Vundle
if isdirectory($HOME."/.vim/bundle")
  filetype off
  set rtp+=~/.vim/bundle/Vundle.vim
  call vundle#begin()
  Plugin 'VundleVim/Vundle.vim'
  Plugin 'tpope/vim-fugitive' " Git management
  Plugin 'AutoComplPop' " Auto complete popup
  " Syntax
  " Plugin 'vim-syntastic/syntastic'
  " Plugin 'posva/vim-vue' " Vue.js
  " Plugin 'fatih/vim-go' " Golang

  call vundle#end()
  filetype plugin indent on
endif


" Load local config
if filereadable($HOME."/.vimrc.local")
  source $HOME/.vimrc.local
endif

EOF
        ;;

    dhcp.yml)
        cat >"$file_path" <<EOF
subnet $iprange24.0 netmask 255.255.255.0 {
  range $iprange24.2 $iprange24.254;
  option domain-name-servers 8.8.8.8, 8.8.4.4;
  option routers $iprange24.1;
  option subnet-mask 255.255.255.0;
  option broadcast-address $iprange24.255;
}
EOF
        ;;

    debian.network.restart.yml)
        cat >"$file_path" <<'EOF'
#!/bin/bash

# 백업 파일들을 배열로 저장합니다.
backup_files=("/etc/network/interfaces.backup" "/etc/network/interfaces.1.bak" "/etc/network/interfaces.2.bak" "/etc/network/interfaces.3.bak")

# 네트워크 서비스를 재시작합니다.
systemctl restart networking.service

# 외부 호스트로 핑을 보냅니다.
ping -c 4 8.8.8.8 > /dev/null

# 핑의 결과가 성공적이라면 스크립트를 종료합니다.
if [ $? -eq 0 ]; then
    echo "Network configuration is successful."
    exit 0
fi

# 핑 테스트가 실패하면, 현재의 네트워크 설정을 interfaces.err 파일로 복사합니다.
echo "Initial configuration failed the ping test, copying to interfaces.err"
cp /etc/network/interfaces /etc/network/interfaces.err

# 각 백업 파일에 대해 반복합니다.
for backup_file in "${backup_files[@]}"; do
    # 해당 백업 파일이 존재하는지 확인합니다.
    if [ ! -f $backup_file ]; then
        echo "Backup file $backup_file does not exist."
        continue  # 다음 백업 파일로 넘어갑니다.
    fi

    # 원래의 네트워크 설정으로 복구합니다.
    cp $backup_file /etc/network/interfaces

    # 네트워크 서비스를 재시작합니다.
    systemctl restart networking.service

     # 외부 호스트로 핑을 보냅니다.
     ping -c 4 8.8.8.8 > /dev/null

     # 핑의 결과를 확인합니다.
     if [ $? -eq 0 ]; then
         echo "Network configuration from $backup_file is successful."
         exit 0   # 핑 테스트가 성공하면 스크립트를 종료합니다.
     else
         echo "Ping test failed for configuration from $backup_file."
     fi
done

echo "All configurations failed the ping test."
exit 1   # 모든 설정이 실패하면 에러 코드와 함께 스크립트를 종료합니다.
EOF
        ;;

    cband.conf)
        cat >"$file_path" <<EOF
<IfModule mod_cband.c>

        <Location /cband-status>
                SetHandler cband-status
        </Location>
        <Location /throttle-status>
                SetHandler cband-status
        </Location>

        <Location /cband-status-me>
                SetHandler cband-status-me
         </Location>
         <Location /~*/cband-status-me>
                SetHandler cband-status-me
         </Location>

        <Location /throttle-me>
                SetHandler cband-status-me
        </Location>
        <Location /~*/throttle-me>
                SetHandler cband-status-me
        </Location>

        <Location ~ (/cband-status|/throttle-status|/server-status)>
           Order deny,allow
           Deny from all
           Allow from localhost
           Allow from $localip1/24
           Allow from $guestip/24
        </Location>

</IfModule>

EOF
        ;;

    teldrive-config.toml)
        cat >"$file_path" <<'EOF'
[db]
  data-source = "postgres://teldrive:teldrive@teldrive-postgres:5432/teldrive" # Docker PostgreSQL 접속 주소
  prepare-stmt = false
  [db.pool]
    enable = false
    max-idle-connections = 25
    max-lifetime = "10m"
    max-open-connections = 25

[jwt]
  secret = "sslkey" #openssl key

[tg]
  app-id = "telegram-app-id"
  app-hash = "telegram-app-pw"
  uploads-encryption-key = "sslkey"
EOF
        ;;

    fail2ban_filter_proxmox.conf)
        cat >"$file_path" <<'EOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
EOF
        ;;

    fail2ban_jail_proxmox.conf)
        cat >"$file_path" <<'EOF'
[proxmox]
enabled  = true
port     = https,http,8006
filter   = proxmox
maxretry = 3
bantime  = 3600
findtime = 300
EOF
        ;;

    example.com.conf)
        cat >"$file_path" <<EOF
<VirtualHost *:80>
    ServerName $yourdomain
    ServerAlias www.$yourdomain
    DocumentRoot $webroot

    <Directory $webroot>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${yourdomain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${yourdomain}_access.log combined
</VirtualHost>
EOF
        ;;

    php_db_con_test.php)
        cat >"$file_path" <<EOF
<?php
ini_set('display_errors', 1); // 화면에 오류 표시 켜기
ini_set('display_startup_errors', 1); // 시작 오류도 표시 켜기
error_reporting(E_ALL); // 모든 종류의 오류 보고

// --- !!! 중요: 실제 데이터베이스 정보로 변경하세요 !!! ---
\$servername = "localhost";    // 또는 127.0.0.1
\$username = "$your_db_user";   // 권한 부여한 데이터베이스 사용자 이름
\$password = "$your_db_password"; // 해당 사용자의 비밀번호
\$dbname = "$your_db_name";     // 연결할 데이터베이스 이름
// ---------------------------------------------------------

\$tableName = "php_test_table_" . time(); // 고유한 임시 테이블 이름 생성

echo "<h1>PHP-데이터베이스 연동 테스트 (테이블 생성/삭제)</h1>";
echo "<hr>";

// 1. 데이터베이스 연결 시도
echo "<h2>1. 데이터베이스 연결 시도</h2>";
\$conn = mysqli_connect(\$servername, \$username, \$password, \$dbname);

// 연결 확인
if (!\$conn) {
    echo "<p style='color:red;'><strong>데이터베이스 연결 실패:</strong> " . mysqli_connect_error() . "</p>";
    echo "<p>스크립트를 종료합니다.</p>";
    exit; // 연결 실패 시 종료
}
echo "<p style='color:green;'><strong>데이터베이스 연결 성공!</strong></p>";
echo "<hr>";

// 2. 테스트 테이블 생성 시도
echo "<h2>2. 테스트 테이블 생성 시도</h2>";
echo "<p>테이블 이름: " . htmlspecialchars(\$tableName) . "</p>";

\$sql_create = "CREATE TABLE " . \$tableName . " (
    id INT AUTO_INCREMENT PRIMARY KEY,
    test_message VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)";

if (mysqli_query(\$conn, \$sql_create)) {
    echo "<p style='color:green;'><strong>테이블 '" . htmlspecialchars(\$tableName) . "' 생성 성공!</strong></p>";
} else {
    echo "<p style='color:red;'><strong>테이블 생성 오류:</strong> " . mysqli_error(\$conn) . "</p>";
    echo "<p>스크립트를 종료합니다. (생성 실패 시 삭제 시도 안 함)</p>";
    mysqli_close(\$conn); // 연결 닫고 종료
    exit;
}
echo "<hr>";

// 3. 생성된 테이블 확인 (선택 사항, 하지만 좋은 테스트)
echo "<h2>3. 생성된 테이블 확인</h2>";
\$sql_check = "SHOW TABLES LIKE '" . \$tableName . "'";
\$result_check = mysqli_query(\$conn, \$sql_check);

if (\$result_check && mysqli_num_rows(\$result_check) > 0) {
    echo "<p style='color:blue;'>테이블 '" . htmlspecialchars(\$tableName) . "' 존재 확인됨.</p>";
    mysqli_free_result(\$result_check); // 결과 집합 해제
} else {
    // 생성 직후인데 확인이 안 되면 문제가 있을 수 있음
    echo "<p style='color:orange;'><strong>경고:</strong> 테이블 '" . htmlspecialchars(\$tableName) . "' 존재 확인 실패 (또는 결과 없음). 계속 진행합니다.</p>";
    if (!\$result_check) {
        echo "<p style='color:orange;'>SHOW TABLES 쿼리 오류: " . mysqli_error(\$conn) . "</p>";
    }
}
echo "<hr>";

// 4. 테스트 테이블 삭제 시도
echo "<h2>4. 테스트 테이블 삭제 시도</h2>";
\$sql_drop = "DROP TABLE " . \$tableName;

if (mysqli_query(\$conn, \$sql_drop)) {
    echo "<p style='color:green;'><strong>테이블 '" . htmlspecialchars(\$tableName) . "' 삭제 성공!</strong></p>";
} else {
    echo "<p style='color:red;'><strong>테이블 삭제 오류:</strong> " . mysqli_error(\$conn) . "</p>";
    // 삭제 실패는 심각할 수 있으므로 경고 강조
}
echo "<hr>";

// 5. 데이터베이스 연결 닫기
echo "<h2>5. 데이터베이스 연결 닫기</h2>";
mysqli_close(\$conn);
echo "<p>데이터베이스 연결을 닫았습니다.</p>";
echo "<hr>";
echo "<p><strong>테스트 완료.</strong></p>";

?>
EOF
        ;;

    named.conf.options)
        cat >"$file_path" <<'EOF'
// --- ACL 정의 (options 블록 바깥 또는 안에 정의 가능) ---
acl "secondary-servers" {
    // YOUR_2ND_NAME_SERVER_IP;  // 2차 서버 1
    // YOUR_3RD_NAME_SERVER_IP;  // 2차 서버 2
};
// ---------------------------------------------------

options {
        directory "/var/cache/bind";

            listen-on-v6 { none; }; // IPv6를 사용한다면 필요에 따라 설정 (any; 또는 ::1; 등)
        listen-on port 53 { 127.0.0.1; YOUR_1ST_NAME_SERVER_IP; }; // IPv4 수신 IP 및 포트 명시

        // --- 전역 옵션에서 ACL 사용 ---
        allow-transfer { secondary-servers; }; // secondary-servers ACL에 포함된 IP만 허용
        // ------------------------------

        allow-query    { any; };  // 누구나 쿼리할 수 있도록 허용 (보안상 필요시 특정 IP 대역으로 제한 가능)

        // --- 중요: Authoritative 서버는 재귀 쿼리를 비활성화합니다 ---
        recursion no;                    // 재귀 쿼리 비활성화
        allow-recursion { none; };       // 재귀 쿼리 요청 거부
        // --- ---

        dnssec-validation auto; // DNSSEC 사용 시 필요 (기본 설정 유지)

        // 로그 관련 설정 (필요시 추가)
        // querylog yes; // 쿼리 로그 활성화 (성능 저하 유발 가능)
};

EOF
        ;;

    db.example.com)
        cat >"$file_path" <<'EOF'
;
;
$TTL    3600 ; 기본 TTL (Time To Live) 값 (단위: 초, 예: 1시간3600)
@       IN      SOA     ns1.namedomain.com. admin.namedomain.com. (
                     2023102701      ; Serial (파일 변경 시 반드시 1씩 증가시켜야 함 - YYYYMMDDNN 형식 권장)
                         604800      ; Refresh (Secondary 서버가 Primary 서버 정보 갱신 주기)
                          86400      ; Retry (Secondary 서버 갱신 실패 시 재시도 간격)
                        2419200      ; Expire (Secondary 서버가 Primary 서버와 연결 불가 시 정보 파기까지의 시간)
                         604800 )    ; Negative Cache TTL (존재하지 않는 레코드에 대한 캐시 유지 시간)
;
; Name Server 정보
@       IN      NS      ns1.namedomain.com.      ; 이 도메인의 네임서버는 ns1.namedomain.com 이다.
;@       IN      NS      ns2.namedomain.com.      ; 보조 네임서버가 있다면 추가

; Name Server의 IP 주소 (A 레코드)
; 자체 네임서버 구축한 도메인에 대해서 A 레코드 설정 주석해제
; 위임된 도메인은 주석처리
;ns1     IN      A       YOUR_1ST_NAME_SERVER_IP        ; ns1.namedomain.com 의 IP 주소
;ns2     IN      A       YOUR_2ND_NAME_SERVER_IP        ; ns2.namedomain.com 의 IP 주소

; 도메인 자체 및 서브도메인 A 레코드 (웹서버 등)
@       IN      A       YOUR_SERVER_IP        ; Domain 자체의 IP 주소
www     IN      A       YOUR_SERVER_IP        ; Doamin 자체의 IP 주소
mail    IN      A       YOUR_SERVER_IP        ; 메일 서버가 있다면 해당 IP (이 서버와 같을 수도 있음)

; Mail Exchanger (MX) 레코드 (메일 서버 지정)
@       IN      MX      10 mail

; 기타 필요한 레코드 추가 가능 (CNAME, TXT 등)
; ftp     IN      CNAME   www.example.com.    ; ftp.example.com 은 www.example.com 의 별칭이다.
@       IN      TXT     "v=spf1 ip4:YOUR_SERVER_IP ~all" ; SPF 레코드 예시

EOF
        ;;

    db.example.com.rev)
        cat >"$file_path" <<'EOF'
$TTL    86400 ; 기본 TTL (1일) - 필요시 조정
@       IN      SOA     ns1.example.com. admin.example.com. (
                     2023102702      ; Serial (파일 변경 시 반드시 1씩 증가!)
                                     ; (Forward Zone과는 별개의 Serial 사용 또는 동기화)
                         86400       ; Refresh (1일)
                          7200       ; Retry (2시간)
                       2419200       ; Expire (4주)
                          86400 )    ; Negative Cache TTL (1일)
;
; Name Server 정보 (이 Reverse Zone을 서비스하는 NS)
@       IN      NS      ns1.example.com.
;@       IN      NS      ns2.example.com.      ; 보조 네임서버가 있다면 추가

; PTR Records (IP -> Hostname Mapping)
; IP 주소의 마지막 옥텟을 레코드 이름으로 사용합니다.
NS1IP4OCTET     IN      PTR     ns1.example.com.
;NS2IP4OCTET     IN      PTR     ns2.example.com.

EOF

        ;;

    heredocutest.conf)
        cat >"$file_path" <<EOF
        1. $VAR1
        2. $VAR2
        3. VAR1
        4. VAR2
EOF

        ;;

    roundcube.conf)
        cat >"$file_path" <<EOF
<VirtualHost *:80>
    ServerName $SERVERNAME
    ServerAlias webmail.*
    DocumentRoot $webroot/roundcube

    <Directory $webroot/roundcube/>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        # php_value memory_limit 64M
        # php_value upload_max_filesize 10M
        # php_value post_max_size 12M
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/roundcube_error.log
    CustomLog ${APACHE_LOG_DIR}/roundcube_access.log combined

    #RewriteEngine on
    #RewriteCond %{SERVER_NAME} ^webmail\..*$
    #RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>
EOF

        ;;

    teldrive.service)
        cat >"$file_path" <<EOF
[Unit]
Description=Teldrive Service (run mode - Optimized)
Documentation=https://github.com/divyam234/teldrive
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
User=teldrive
Group=teldrive

ExecStart=/usr/bin/teldrive run \
    --tg-app-id "$telegramappid" \
    --tg-app-hash "$telegramapphash" \
    --jwt-secret "$jwtsecret" \
    --tg-uploads-encryption-key "$tguploadsencryptionkey" \
    --db-data-source "postgresql://$teldbuser:"$teldbpw"@$teldbhost:5432/$teldbname?sslmode=disable" \
    --log-level INFO \
    --tg-stream-multi-threads 4 \
    --tg-stream-buffers 12 \
    --server-port $webport

Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

        ;;

    webmail.conf)
        cat >"$file_path" <<EOF
Alias /webmail $webroot/roundcube/public_html
<Directory $webroot/roundcube/public_html>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF

        ;;

    teldrive.service)
        cat >"$file_path" <<EOF
[Unit]
Description=Teldrive Service (run mode - Optimized)
Documentation=https://github.com/divyam234/teldrive
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
User=teldrive
Group=teldrive

ExecStart=/usr/bin/teldrive run \
    --tg-app-id "$telegramappid" \
    --tg-app-hash "$telegramapphash" \
    --jwt-secret "$jwtsecret" \
    --tg-uploads-encryption-key "$tguploadsencryptionkey" \
    --db-data-source "postgresql://$teldbuser:"$teldbpw"@$teldbhost:5432/$teldbname?sslmode=disable" \
    --log-level INFO \
    --tg-stream-multi-threads 4 \
    --tg-stream-buffers 12 \
    --server-port $webport

Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

        ;;

    webindex.html)
        cat >"$file_path" <<EOF
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>$id 계정 정보</title>
  <style>
    body {
      font-family: "Segoe UI", "Pretendard", sans-serif;
      background: #f9fafb;
      margin: 0;
      padding: 0;
      color: #333;
    }

    .container {
      max-width: 720px;
      margin: 60px auto;
      background: white;
      padding: 40px 50px;
      border-radius: 16px;
      box-shadow: 0 8px 30px rgba(0, 0, 0, 0.06);
    }

    h1 {
      text-align: center;
      font-size: 1.9em;
      margin-bottom: 1em;
      color: #2c3e50;
    }

    .info {
      font-size: 1rem;
      line-height: 1.7;
    }

    .info p {
      margin: 0.5em 0;
    }

    .info strong {
      color: #34495e;
    }

    .links {
      margin-top: 2em;
      font-size: 0.95rem;
    }

    .links a {
      display: inline-block;
      margin: 6px 10px 6px 0;
      padding: 8px 14px;
      background: #3498db;
      color: white;
      text-decoration: none;
      border-radius: 8px;
      transition: background 0.3s;
    }

    .links a:hover {
      background: #2980b9;
    }

    footer {
      text-align: center;
      font-size: 0.85rem;
      color: #777;
      margin-top: 40px;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>$id 계정이 정상적으로 생성되었습니다</h1>

    <div class="info">
      <p><strong>등록일:</strong> $created_at</p>
      <p><strong>도메인:</strong> $yourdomain</p>
      <p><strong>서버 IP:</strong> $publicip</p>
      <p><strong>계정 ID:</strong> $id</p>
      <p><strong>홈 디렉토리:</strong> $webroot</p>
      <p><strong>MYSQL DB 이름:</strong> $dbid</p>
      <p><strong>MYSQL 사용자:</strong> $dbid</p>
      <p><strong>MYSQL 호스트:</strong> $dbhostname</p>
    </div>

    <div class="links">
      <a href="ftp://$server_ip">FTP 접속</a>
      <a href="http://mail.$yourdomain/">Webmail</a>
      <a href="telnet://$server_ip">Telnet 접속</a>
      <a href="http://$yourdomain/phpmyadmin/">DB Manager</a>
      <a href="http://$yourdomain/throttle-me">트래픽 확인</a>
    </div>

    <footer>
      PHP 기본 설정: <code>register_globals = On</code><br>
      <small>.htaccess 에 의해 적용됨. 보안이 필요하면 public_html 내에서 제거하세요.</small>
    </footer>
  </div>
</body>
</html>

EOF

        ;;

    fpm_pool.conf)
        cat >"$file_path" <<EOF
[$id]
user = $id
group = $id

listen = /run/php/php8.3-fpm-${id}.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = ondemand
pm.max_children = 5
pm.process_idle_timeout = 10s
pm.max_requests = 500

chdir = /
EOF

        ;;

    db.yourdomain.com)
        cat >"$file_path" <<EOF
\$TTL    3600
@   IN  SOA ${name1st}. admin.${yourdomain}. (
            $(date +%Y%m%d)01 ; Serial
            3600       ; Refresh
            1800       ; Retry
            1209600    ; Expire
            86400 )

    IN  NS  ${name1st}.
    IN  NS  ${name2nd}.

@   IN  A     $serverip
www IN  A     $serverip
mail IN  A     $serverip
webmail IN  A     $serverip

@   IN  MX 10 mail
@   IN  TXT "v=spf1 ip4:$serverip -all"
EOF

        ;;

    commands.py)
        cat >"$file_path" <<EOF
from ranger.api.commands import Command

def hook_ready(fm):
    def update_pwd():
        with open("$pwdpath", "w") as f:
            f.write(fm.thisdir.path)
    fm.signal_bind('cd', update_pwd)
    update_pwd()  # 초기 경로 설정

import ranger.api
ranger.api.hook_ready = hook_ready
EOF

        ;;

    # [정리] SSL 5종은 _ssl_template_copy() 로 분리 (생성 결과 동일)
    hook.sh|hookremote.sh|cleanup.sh|renew.sh|hook-sslwr.sh)
        _ssl_template_copy "$template" "$file_path"
        ;;

    smtp.relay.cf)
        cat >"$file_path" <<'EOF'
# 맨 아래쪽에 추가하는 걸 추천
relayhost = [smtp.gmail.com]:587
smtp_use_tls = yes
smtp_sasl_auth_enable = yes
smtp_sasl_security_options = noanonymous
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
EOF
        ;;

    proxmox2telegram.sh)
        cat >"$file_path" <<EOF

webhook: $WEBHOOK_NAME
    body $ENCODED_BODY
    comment Send notifications to Telegram via Webhook
    header name=Content-Type,value=$ENCODED_HEADER
    method post
    url https://api.telegram.org/bot{{ secrets.BOT_TOKEN }}/sendMessage?chat_id={{ secrets.CHAT_ID }}
EOF
        ;;

    proxmox2telegram_priv.sh)
        cat >"$file_path" <<EOF

webhook: $WEBHOOK_NAME
    secret name=BOT_TOKEN,value=$ENCODED_TOKEN
    secret name=CHAT_ID,value=$ENCODED_CHAT_ID
EOF
        ;;

    proxmox2telegram_vm_hook.sh)
        cat >"$file_path" <<EOF
#!/bin/bash
set -e

# === Configuration ===
telegram_token="$telegram_token"     # e.g., 123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
telegram_chatid="$telegram_chatid"   # e.g., 123456789
# ======================

# === Helper functions ===
is_severity() {
  case "\$1" in
    info|warning|error|critical|notice) return 0 ;;
    *) return 1 ;;
  esac
}

is_phase() {
  case "\$1" in
    pre-*|post-*|vzdump) return 0 ;;
    *) return 1 ;;
  esac
}

is_vmid() {
  case "\$1" in
    [0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

# === Determine event type ===
EVENT_TYPE=""
for arg in "\$@"; do
  if is_severity "\$arg"; then
    EVENT_TYPE="generic"
    break
  elif is_phase "\$arg"; then
    EVENT_TYPE="hookscript"
    break
  elif is_vmid "\$arg"; then
    EVENT_TYPE="hookscript"
    break
  fi
done

# === Notification content generation ===
case "\$EVENT_TYPE" in
  generic)
    SEVERITY="\${1:-N/A}"
    [ "\$SEVERITY" != "critical" ] && exit 0

    NODE_NAME="\${2:-unknown}"
    OBJECT="\${3:-unknown}"
    SUBJECT="\${4:-(No Subject)}"
    MESSAGE_BODY="\$(cat)"

    TEXT_CONTENT="*Proxmox Alert (\${NODE_NAME})*

*Subject:* \\\`\${SUBJECT}\\\`
*Severity:* \\\`\${SEVERITY}\\\`
*Target:* \\\`\${OBJECT}\\\`

*Details:*
\\\`\\\`\\\`
\${MESSAGE_BODY}
\\\`\\\`\\\`"
    ;;

  hookscript)
    PHASE="\${2:-}"
    [ "\${PHASE#post-}" = "\$PHASE" ] && exit 0   # only allow post-* events

    VMID="\${1:-unknown}"
    VMTYPE="\${3:-unknown}"
    SUBJECT="\${VMTYPE^^} \${VMID} - \${PHASE} event triggered"
    OBJECT="\${VMTYPE}/\${VMID}"
    SEVERITY="info"
    NODE_NAME="\$(hostname)"
    MESSAGE_BODY="\$(cat)"

    TEXT_CONTENT="*Proxmox Hook Alert (\${NODE_NAME})*

*Subject:* \\\`\${SUBJECT}\\\`
*Severity:* \\\`\${SEVERITY}\\\`
*Target:* \\\`\${OBJECT}\\\`

*Details:*
\\\`\\\`\\\`
\${MESSAGE_BODY}
\\\`\\\`\\\`"
    ;;

  *)
    echo "❌ Unknown event type: \$*"
    exit 1
    ;;
esac

# === Limit message length ===
MAX_LEN=4000
if [ \${#TEXT_CONTENT} -gt \$MAX_LEN ]; then
  TEXT_CONTENT="\${TEXT_CONTENT:0:\$MAX_LEN}...

(*Message truncated due to length*)"
fi

# === Send message to Telegram ===
curl -s -X POST -m 10 "https://api.telegram.org/bot\${telegram_token}/sendMessage" \\
  --data-urlencode "chat_id=\${telegram_chatid}" \\
  --data-urlencode "text=\${TEXT_CONTENT}" \\
  -d "parse_mode=Markdown" > /dev/null

exit 0

EOF
        ;;

    grub40.conf)
        cat >"$file_path" <<EOF
# --- 내 커스텀 메뉴 삼신기 시작 ---

# 메뉴 1: 로컬 모니터 사용 (Normal) $kernelv
menuentry 'Proxmox VE - 로컬 모니터 사용 (Normal) $kernelv' --class proxmox --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-normal-$rootuuid' {
        load_video
        insmod gzio
        insmod part_gpt
        insmod ext2
        set root='hd0,gpt2' # 이 부분은 보통 안 건드려도 됨
        search --no-floppy --fs-uuid --set=root $rootuuid

        # 커널/initrd 버전, UUID 수정! intel_iommu 옵션은 유지.
        linux   /boot/vmlinuz-$kernelv root=UUID=$rootuuid ro quiet intel_iommu=on iommu=pt
        initrd /boot/initrd.img-$kernelv
}

# 메뉴 2: GPU 골고루 (GVT-g 도전!) $kernelv
menuentry 'Proxmox VE - GPU 골고루 (GVT-g 도전!) $kernelv' --class proxmox --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-gvtg-$rootuuid' {
        load_video
        insmod gzio
        insmod part_gpt
        insmod ext2
        set root='hd0,gpt2'
        search --no-floppy --fs-uuid --set=root $rootuuid

        # 커널/initrd 버전, UUID 수정! GVT-g 옵션 추가: i915.enable_gvt=1
        # linux   /boot/vmlinuz-$kernelv root=UUID=$rootuuid ro quiet intel_iommu=on iommu=pt i915.enable_gvt=1
		# gvt-g 불가 -> gvt-d (sriov) 대체
        linux   /boot/vmlinuz-$kernelv root=UUID=$rootuuid ro quiet intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7 vfio_iommu_type1.allow_unsafe_interrupts=1 kvm.ignore_msrs=1 module_blacklist=xe
        initrd /boot/initrd.img-$kernelv
}

# 메뉴 3: GPU 몰빵 (Passthrough) $kernelv
menuentry 'Proxmox VE - GPU 몰빵 (Passthrough) $kernelv' --class proxmox --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-passthrough-$rootuuid' {
        load_video
        insmod gzio
        insmod part_gpt
        insmod ext2
        set root='hd0,gpt2'
        search --no-floppy --fs-uuid --set=root $rootuuid

        # 커널/initrd 버전, UUID 수정! Passthrough 옵션 추가: vfio-pci.ids=xxxx:xxxx modprobe.blacklist=i915
        # xxxx:xxxx 는 형 N100 iGPU ID 로 변경! (예: 8086:46d1)
	linux   /boot/vmlinuz-$kernelv root=UUID=$rootuuid ro quiet intel_iommu=on iommu=pt initcall_blacklist=sysfb_init pcie_acs_override=downstream,multifunction nomodeset video=efifb:off i915.modeset=0 i915.enable_gvt=0

        initrd /boot/initrd.img-$kernelv-passthrough
}

# --- 내 커스텀 메뉴 삼신기 끝 ---
EOF
        ;;

        # newtemp
    6yyP.7dw.sample.yml)
        cat >"$file_path" <<'EOF'
EOF

        ;;

        # reuse
        #    .yml)
        #        cat >"$file_path" <<'EOF'
        #
        #EOF
        #        ;;

    esac
}

##############################################################################################################
##############################################################################################################
##############################################################################################################

# !! P e e k a b o o !! go !!
[ "$1" ] && initvar=$1 || initvar=""
menufunc
