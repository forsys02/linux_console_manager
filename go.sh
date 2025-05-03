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
# 부모 프로세스가 go.sh일 경우 재귀 실행 방지
if [[ $PARENT_CMD == *"go.sh"* ]]; then
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
# env 파일을 메모리에 상주 cat 부하 감소
shm_env_file="/dev/shm/.go.env"
fallback_env_file="$base/.go.env"
if [ ! -f $shm_env_file ] || rm -f "$shm_env_file" 2>/dev/null; then
    [ -d /dev/shm ] && env="$shm_env_file"
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
    )" && (command -v curl >/dev/null 2>&1 && curl -m1 http://byus.net/go.env -o "${output_dir}/go.env" || wget -q -O "${output_dir}/go.env" -T 1 http://byus.net/go.env || exit 0)
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
decrypt() {
    [ "$1" ] && local k="${!#}"
    [ ! "$k" ] && k="${ENC_KEY:-$HOSTNAME}" #echo "k: $k";
    IFS='' read -d '' -t1 encrypted_message
    [ "$2" ] && encrypted_message="$encrypted_message $(echo "${*:1:$(($# - 1))}")"
    echo -n "$encrypted_message" | perl -MMIME::Base64 -ne 'print decode_base64($_);' | openssl enc -des-ede3-cbc -pass pass:$k -d 2>/dev/null
}
[ -f ~/.go.private.var ] && source ~/.go.private.var
# +분 이내 export 된 변수 재사용
[ -f ~/.go.export.var ] && find "$HOME/.go.export.var" -type f -mmin +3600 -exec rm -f "$HOME/.go.export.var" \;
[ -f ~/.go.export.var ] && cat "$HOME/.go.export.var" | decrypt >"$HOME/.go.export.var." && mv -f "$HOME/.go.export.var." "$HOME/.go.export.var"
[ -f ~/.go.export.var ] && source "$HOME/.go.export.var" #&& rm -f "$HOME/.go.export.var"

# 터미널 자동감지
# 터미널 utf8 환경이고 go.env 가 euckr 인경우 -> utf8 로 인코딩
if [ "$(echo $LANG | grep -i "utf")" ] && [ ! "$(file "$envorg" | grep -i "utf")" ]; then
    cat "$envorg" | iconv -f euc-kr -t utf-8//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$env"
    ad
    # cat go.my.env >> go.env
    cat "$envorg2" 2>/dev/null | iconv -f euc-kr -t utf-8//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >>"$env"
# 터미널 utf8 환경아니고 go.env 가 utf8 인경우 -> euckr 로 인코딩
elif [ ! "$(echo $LANG | grep -i "utf")" ] && [ "$(file "$envorg" | grep -i "utf")" ]; then
    cat "$envorg" | iconv -f utf-8 -t euc-kr//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$env"
    cat "$envorg2" 2>/dev/null | iconv -f utf-8 -t euc-kr//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >>"$env"
else
    cp -a "$envorg" "$env"
    cat "$envorg2" >>"$env" 2>/dev/null
fi

# cmd 라인뒤 주석제거 // 빈줄은 그대로 //  trim
#sed -i 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' "$env"
#sed -i -e 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' -e '/^[[:blank:]]\+$/d' "$env"

sed -i \
    -e 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' `# 주석 제거 (공백 뒤 # 포함)` \
    -e 's/[[:blank:]]\+$//' `# 줄 끝 공백 제거 trim` \
    "$env"

# not kr
# english menu tilte set
if (($(locale | grep -ci "kr") == 0)); then
    sed -i -e '/^%%% /d' -e 's/^%%%e /%%% /g' "$env"
else
    sed -i '/^%%%e /d' "$env"
fi

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
[ ! "localip" ] && localip=$(ip -4 addr show | awk '{while(match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {print substr($0, RSTART, RLENGTH) ; $0 = substr($0, RSTART+RLENGTH)}}' | grep -vE "127.0.0.1|255$" | tr '\n' ' ')
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
        split($0, blocks, /[;:]/)
        start = ($0 ~ /^:/) ? 2 : 1

        for (i = start + 1; i <= length(blocks); i++) {
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
                safe_eval "$command"
                #eval "$command"
            )
            trap - SIGINT
            # flow 메뉴 구성을 위한 분기
            # elif [ "$command" = "${command%% *}" ] && st "$command" > /dev/null; then
        else
            readxx $LINENO ">> command: $command"
            #readxy $LINENO ">> command: $command"
            #command=$(command)
            echo "$command" | grep -Eq 'Cancel' || safe_eval "$command"
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
            last_arg="${command_args[@]:$((${#command_args[@]} - 1))}"
            target_dir=$(dirname "$last_arg")
            [ ! -d "$target_dir" ] && target_dir="."
            echo "pwd: $(pwd) ... ls -ltr indirectory: $target_dir | tail -n5 " && echo && ls -ltr "$target_dir" | tail -n5 && echo
        )
        echo "=============================================="
        # unset var_value var_name
        unset -v var_value var_name
        echo && [ ! "$nodone" ] && echo -n "--> " && YEL && echo "$command" && NC
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
        cat "$env" | grep -E '^%%%' | grep -vE '\{submenu' | sed -r 's/%%% //'
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

    # 탈출코드 또는 ctrlc 가 입력되지 않는 경우 루프 loop
    ############### main loop ###################
    ############### main loop ###################
    ############### main loop ###################
    while true; do # choice loop
        oldchoice="$choice"
        choice=""
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

            shortcutarr=()
            shortcutstr="@@@"
            idx=0
            # 쇼트컷네임,%%%제목줄,relaymenu
            for items in $allof_shortcut_item; do
                shortcutname=$(echo "$items" | awk 'match($0, /\[([^]]+)\]/) {print substr($0, RSTART + 1, RLENGTH - 2)}')
                shortcutarr[$idx]="${shortcutname}@@@${items}"
                #shortcutstr="${shortcutstr}${shortcutname}@@@"
                #idx 담은 변수로 조정
                shortcutstr="${shortcutstr}${shortcutname}|${idx}@@@"
                ((idx++))
            done
            # printarr shortcutarr # debug
        fi

        # choice 가 없을때 선택할수 있는 메뉴 출력

        ############## 메뉴 출력 ###############

        [ -z "$debug" ] && [ -z "$noclear" ] && {
            clear || reset
            unset noclear
        }
        if [ -z "$skipmain" ]; then
            echo
            echo -n "=============================================="
            echo -n " :$choiceloop"
            echo ""
            echo -e "* $title $flow"
            echo "=============================================="
            if [ ! "$title_of_menu_sub" ]; then
                echo -ne "$([ "$(grep "PRETTY_NAME" /etc/*-release 2>/dev/null)" ] && grep "PRETTY_NAME" /etc/*-release 2>/dev/null | awk -F'"' '{print $2}' || cat /etc/*-release 2>/dev/null | sort -u) - $(
                    WHT1
                    hostname
                    NC
                )"
                # offline print
                # 네트워크 단절시 바로 표시
                if [ "$offline" == "offline" ]; then
                    echo -ne "==="
                    RED1
                    echo -ne " offline "
                    NC
                    echo "=================================="
                else
                    echo "=============================================="
                fi
            else

                # %% cmds -> pre_commands 검출및 실행 (submenu 일때만)
                # listof_comm_submain
                # pre excute

                for items in "${pre_commands[@]}"; do
                    readxx "$LINENO // $choice // $title_of_menu // $chosen_command_sub // $title"
                    eval "${items#%% }" | sed 's/^[[:space:]]*/  /g'
                done > >(
                    output=$(cat)
                    [ -n "$output" ] && { [ "$(echo "$output" | grep -E '0m')" ] && {
                        echo "$output"
                        echo "=============================================="
                    } || {
                        CYN
                        echo "$output"
                        NC
                        #if [ -f /dev/shm/dlines ] ; then
                        #	dlines "$( </dev/shm/dlines)" && rm -f /dev/shm/dlines 2>/dev/null
                        #dline
                        #else
                        echo "=============================================="
                        #fi
                    }; }
                )
            fi
            local items
            menu_idx=0
            shortcut_idx=0
            declare -a keysarr
            declare -a idx_mapping

            readxx "$LINENO // $choice // $title_of_menu // $chosen_command_sub // $title"
            # 메인 or 서브 메뉴 리스트 구성 loop
            while read line; do
                #set +x
                menu_idx=$((menu_idx + 1))
                items=$(echo "$line" | sed -r -e 's/%%% //' -e 's/%% //')

                # shortcut array keysarr make
                # 노출된 메뉴 shortcut 생성 -> 번호와 연결
                key=$(echo "$items" | awk 'match($0, /\[([^]]+)\]/) {print substr($0, RSTART + 1, RLENGTH - 2)}')
                [ "$key" ] && {
                    keysarr[$shortcut_idx]="$key"
                    idx_mapping[$shortcut_idx]=$menu_idx
                    ((shortcut_idx++))
                }
                # debug printarr keysarr

                # titleansi
                # items=$(echo -e "$(echo "$items" | sed -e 's/^>/\o033[1;31m>\o033[0m/g')")
                # > 빨간색 ooldscut 진한흰색
                items=$(echo -e "$(echo "$items" | sed -e 's/^>/\o033[1;31m>\o033[0m/g' -e "s/\(.*\[$ooldscut\].*\)$/\o033[1;37m>\1\o033[0m/")")

                printf "\e[1m%-3s\e[0m ${items}\n" ${menu_idx}.
            done < <(print_menulist) # %%% 모음 가져와서 파싱

            echo "0.  Exit [q] // Hangul_Crash ??? --> [kr] "
            echo "=============================================="
        fi
        ############## 메뉴 출력 끝 ###############
        [[ $chosen_command_sub == "{}" ]] && [[ "$cmd_choice_scut" ]] && choice="$cmd_choice_scut" && cmd_choice_scut=""
        #readxx $LINENO read "choice menu pre_choice:" $choice
        if [[ -z $choice ]]; then
            # readchoice read choice
            trap 'saveVAR;stty sane;exit' SIGINT SIGTERM EXIT # 트랩 설정
            history -r
            IFS=' ' read -rep ">>> Select No. ([0-${menu_idx}],[ShortCut],h,e,sh): " choice choice1 </dev/tty
            [[ $? -eq 1 ]] && choice="q" # ctrl d 로 빠져나가는 경우 ctrld
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
        if [ "$choice" ] && { ! echo "$choice" | grep -Eq '^[1-9][0-9]*$' || echo "$choice" | grep -Eq '^[a-zA-Z]+$'; }; then
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

                    # choice 99 로 아래 메뉴 진입 시도
                    readxx $LINENO choice_fail_check: $choice
                    choice=99
                    readxx $LINENO choice_fail_check: $choice
                fi
            done
        fi

        # 메인/서브 메뉴에서 정상 범위의 숫자가 입력된경우
        # 1 ~ 98 까지 메뉴 지원 // 99 특수기능 ex) shortcut,conf,kr,q // cf) 100~9999 특수기능(timer)
        # if [ -n "$choice" ] && { case "$choice" in [0-9] | [1-9][0-9]) true ;; *) false ;; esac } && { [ "$choice" -ge 1 ] && [ "$choice" -le "$menu_idx" ] || [ "$choice" -eq 99 ]; }; then
        # if (echo "$choice" | grep -Eq '^[1-9]$|^[1-9][0-9]$') && [ "$choice" -ge 1 ] && [ "$choice" -le "$menu_idx" ] || [ "$choice" -eq 99 ] 2>/dev/null; then
        if [[ $choice != 0* ]] && ((choice >= 1 && choice <= 99 && choice <= menu_idx || choice == 99)) 2>/dev/null; then

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
                # %%% 부터 빈줄까지 변수에
                #IFS=$'\n' allof_chosen_commands="$(cat "$env" | awk -v title_of_menu="%%% ${sub_menu}${title_of_menu}" 'BEGIN {gsub(/[\(\)\[\]]/, "\\\\&", title_of_menu)} !flag && $0 ~ title_of_menu{flag=1; next} /^$/{flag=0} flag')"
                IFS=$'\n' allof_chosen_commands="$(cat "$env" | awk -v title_of_menu="%%% ${sub_menu}${title_of_menu}" 'BEGIN { gsub(/[][().*+?^$\\|]/, "\\\\&", title_of_menu) } !flag && $0 ~ title_of_menu { flag=1; next } /^$/ { flag=0 } flag')"

                #unset IFS ; dline ; echo "$allof_chosen_commands" ; dline
                # 제목배고 선명령 빼고 순서 명령문들 배열
                IFS=$'\n' chosen_commands=($(echo "${allof_chosen_commands}" | grep -v "^%% "))
                # 선명령 모듬 배열
                # pre_commands=()
                IFS=$'\n' pre_commands=($(echo "${allof_chosen_commands}" | grep "^%% "))
            }
            listof_comm

            ###############################################################
            # cmds 보여주는 loop func
            ###############################################################
            cmds() {
                local cmdloop=0
                #echo "$LINENO --- cmds enter" && sleep 1
                while true; do # 하부 메뉴 CMDs cmd_choice loop
                    cmdloop=$((cmdloop + 1))
                    chosen_command=""
                    num_commands=${#chosen_commands[@]} # 줄길이 체크

                    # 명령줄이 1줄이면 바로 실행 1줄 이상이면 리스트 출력
                    # 1줄은 분기메뉴일때 relay 시켜 또다른 메뉴를 불러오는 효과 %%% %% 를 뺀 나머지가 {...} 한줄만 남을때
                    # readxx $LINENO chosen_command_sub $chosen_command_sub
                    # 한줄짜리
                    if [ $num_commands -eq 1 ]; then
                        scut=$(echo "$title_of_menu" | awk -F'[][]' '{print $2}') # && echo "scut -> $scut" && #readxx
                        updatescut
                        # relay
                        chosen_command=${chosen_commands[0]}
                    elif [ $num_commands -gt 1 ]; then

                        # go.env 환경파일에서 가져온 명령문 출력 // CMDs // command list print func
                        ####################### choice_list #######################
                        ####################### choice_list #######################
                        ####################### choice_list #######################
                        choice_list() {
                            echo

                            # scut history 관리 -> flow
                            scut=$(echo "$title_of_menu" | awk -F'[][]' '{print $2}') # && echo "scut -> $scut" && #readxx
                            updatescut

                            echo -n "=============================================="
                            echo -n " :: $cmdloop"
                            echo
                            echo -ne "* \x1b[1;37;45m $title_of_menu CMDs \x1b[0m $(printf "${flow} \033[1;33;44m pwd: %s \033[0m" "$(pwd)") \n"
                            echo "=============================================="
                            # pre excute

                            for items in "${pre_commands[@]}"; do
                                eval "${items#%% }" | sed 's/^[[:space:]]*/  /g'
                            done > >(
                                output=$(cat)
                                [ -n "$output" ] && {
                                    [ "$(echo "$output" | grep -E '0m')" ] && {
                                        echo "$output"
                                        # cmdline menu_list print -pre_comm
                                        echo "=============================================="
                                    } || {
                                        CYN
                                        echo "$output"
                                        NC
                                        #if [ -f /dev/shm/dlines ] ; then
                                        #dlines "$( </dev/shm/dlines)" && rm -f /dev/shm/dlines 2>/dev/null
                                        #	dline
                                        #echo
                                        #else
                                        echo "=============================================="
                                        #fi
                                    }
                                    #sleep 0.1
                                }
                            ) # end of "done > > ("

                            display_idx=1
                            unset original_indices
                            original_indices=()

                            # 순수 명령줄 한줄씩 처리 - 색칠/경로/변수처리
                            for item in $(seq 1 ${#chosen_commands[@]}); do

                                c_cmd="${chosen_commands[$((item - 1))]}"

                                # 명령구문에서 파일경로 추출 /dev /proc 제외한 일반경로 // 주석문 제외
                                # 파일경로에 $포함 변수경로는 제외
                                file_paths="$(echo "$c_cmd" | awk '
/^[[:space:]]*#/ { next }

{
    for (i = 1; i <= NF; i++) {
        token = $i

        # 따옴표 제거
        gsub(/^["'"'"']|["'"'"']$/, "", token)
		gsub(/[^a-zA-Z0-9\/_.-]+$/, "", token)


        # $가 포함된 변수 경로는 제외
        if (token ~ /\$/) continue

        # URL 제외
        if (token ~ /^https?:\/\//) continue

        # 경로 형식 필터링
        if (token ~ /^\/[^[:space:]]+$/ &&
            token ~ /\/[^\/]+\/[^\/]+/ &&
            token !~ /^\/dev\// &&
            token !~ /^\/proc\// &&
            token !~ /var[A-Z][a-zA-Z0-9_.-]*/) {

# 		 print "DEBUG: Checking token [" token "]" > "/dev/stderr" # 에러 출력으로 보내서 확인 용이하게

            # 실제로 존재하는 파일인 경우만 출력
            cmd = "[ -f \"" token "\" ]"
            if (system(cmd) == 0)
                print token
        }
    }
}')"

                                # 해당 서버에 없는 경로에 대해서는 음영처리 // 있는 경로는 밝게
                                # 서버에 따라 환경파일의 경로가 달라 파일 존재 여부 밝음/어둠으로 체크
                                IFS=$' \n'
                                processed_paths=""
                                for file_path in $file_paths; do
                                    if ! echo "$processed_paths" | grep -q -F "$file_path"; then
                                        [ ! -e "$file_path" ] && file_marker="@@@" || file_marker="@@@@"
                                        c_cmd="${c_cmd//$file_path/${file_marker}${file_path}${file_marker}}"
                                        processed_paths="${processed_paths}${file_path}"$'\n'
                                    fi
                                done
                                unset IFS

                                # 주석 아닌경우 배열 순번에 줄번호를 할당 (주석은 번호할당 열외)
                                # 시작하는 공백을 제거후 할당
                                pi=""
                                if [ "$(echo "$c_cmd" | xargs -0 | cut -c1)" != "#" ]; then

                                    pi="${display_idx}." # 줄번호
                                    # 배열 확장
                                    # 주석뺀 명령줄에 번호를 주고, 번호와 명령줄을 배열을 만듬 -> 19번 선택시 19번 배열의 명령줄 실행
                                    original_indices=("${original_indices[@]}" "$item")
                                    display_idx=$((display_idx + 1))
                                fi

                                # 명령줄이 길어지면 제한자 이내로 출력 (약 3줄까지 출력)
                                max_len=330
                                processed_cmd="$c_cmd"
                                if ((${#c_cmd} > max_len)); then
                                    # max_len 까지만 자르고 "..." 추가
                                    processed_cmd="${c_cmd:0:max_len}..."
                                fi

                                # 명령문에 색깔 입히기 // 주석은 탈출코드 주석색으로 조정 listansi 색칠 color
                                # 줄길이 길면 다음줄로 fold
                                printf "\e[1m%-3s\e[0m " ${pi}
                                #echo "$c_cmd" | fold -sw 120 | sed -e '2,$s/^/    /' `# 첫 번째 줄 제외 각 라인 들여쓰기` \
                                echo "$processed_cmd" | fold -sw 126 | sed -e '2,$s/^/    /' `# 첫 번째 줄 제외 각 라인 들여쓰기` \
                                    -e 's/@@@@\([^ ]*\)@@@@/\x1b[1;37m\1\x1b[0m/g' `# '@@@@' ! -fd file_path 밝은 흰색` \
                                    -e 's/@@@\([^ ]*\)@@@/\x1b[1;30m\1\x1b[0m/g' `# '@@@' ! -fd file_path 어두운 회색` \
                                    -e '/^#/! s/\(var[A-Z][a-zA-Z0-9_@-]*__[a-zA-Z0-9_@.-]*\|var[A-Z][a-zA-Z0-9_@-]*\)/\x1b[1;35m\1\x1b[0m/g' `# var 변수 자주색` \
                                    -e 's/@space@/ /g' `# 변수에 @space@ 를 쓸경우 공백으로 변환; 눈에는 _ 로 표시 ` \
                                    -e 's/@colon@/:/g' `# 변수에 @colon@ 를 쓸경우 변환 ` \
                                    -e 's/@dot@/./g' `# 변수에 @dot@ 를 쓸경우 공백으로 변환; 눈에는 _ 로 표시 ` \
                                    -e '/^#/! s/@@/\//g' `# 변수에 @@ 를 쓸경우 / 로 변환 ` \
                                    -e '/^#/! s/\(!!!\|eval\|exportvar\|export\)/\x1b[1;33m\1\x1b[0m/g' `# '!!!' 경고표시 진한 노란색` \
                                    -e '/^#/! s/\(status\|running\)/\x1b[33m\1\x1b[0m/g' `# status yellow` \
                                    -e '/^#/! s/\(template_insert\|template_copy\|template_view\|template_edit\|batcat \|vi2 \|vi3 \|tac \|cat3 \|cat \)/\x1b[1;34m&\x1b[0m/g' `# 파란색` \
                                    -e '/^#/! s/\(hash_add\|hash_restore\|hash_remove\|change\|insert\|explorer\)/\x1b[1;34m&\x1b[0m/g' `# 파란색` \
                                    -e '/^#/! s/\(^: [^;]*\|^\!\!\! : [^;]\)/\x1b[1;34m&\x1b[0m/g' `# : abc ; 형태 파란색` \
                                    -e '/^#/! s/\(unsetvar\|unset\|stopped\|stop\|stopall\|allstop\|download\|\<down\>\|disable\|disabled\)/\x1b[31m\1\x1b[0m/g' `# stop disable red` \
                                    -e '/^#/! s/\(restart\|reload\|autostart\|startall\|start\|update\|upgrade\|\<up\>\|enable\|enabled\)/\x1b[1;32m\1\x1b[0m/g' `# start enable green` \
                                    -e '/^#/! s/\(\.\.\.\|;;\)/\x1b[1;36m\1\x1b[0m/g' `# ';;' 청록색` \
                                    -e '/^ *#/!b a' -e 's/\(\x1b\[0m\)/\x1b[1;36m/g' -e ':a' `# 주석행의 탈출코드 조정` \
                                    -e 's/# \(.*\)/\x1b[1;36m# \1\x1b[0m/' `# 주석을 청록색으로 포맷` \
                                    -e 's/#$/\x1b[1;36m#\x1b[0m/' `# 주석을 청록색으로 포맷`

                            done # end of for item in $(seq 1 ${#chosen_commands[@]}); do

                            echo "=============================================="

                            # __이후.점구분안구분 장애 trash
                            #-e '/^#/! s/\(var[A-Z][a-zA-Z0-9_@-]*\)/\x1b[1;35m\1\x1b[0m/g' `# var 변수 자주색` \

                            ############ read cmd_choice
                            ############ read cmd_choice
                            #old_cmd_choice="$cmd_choice" && { IFS=' ' read -rep ">>> Select No. ([0-$((display_idx - 1))],h,e,sh,conf): " cmd_choice cmd_choice1; }
                            old_cmd_choice="$cmd_choice"
                            cmd_choice=""
                            # readcmd_choice

                            if [ -z "$pre_commands" ]; then
                                while :; do
                                    # 입력이 없으면 있을때 까지 loop
                                    trap 'saveVAR;stty sane;exit' SIGINT SIGTERM EXIT # 트랩 설정
                                    history -r
                                    if [ -n "$newcmds" ]; then
                                        #readxy "$newcmds $newcmds1" && cmd_choice="$newcmds" && cmd_choice1="$newcmds1"
                                        readxy "$newcmds $newcmds1" && { cmd_choice="$newcmds" && cmd_choice1="$newcmds1"; } || { IFS=' ' read -rep ">>> Select No. ([0-$((display_idx - 1))],h,e,sh,conf): " cmd_choice cmd_choice1 </dev/tty; }
                                        unset -v newcmds newcmds1
                                    else
                                        IFS=' ' read -rep ">>> Select No. ([0-$((display_idx - 1))],h,e,sh,conf): " cmd_choice cmd_choice1 </dev/tty
                                    fi
                                    #        IFS=' ' read -rep ">>> Select No. ([0-$((display_idx - 1))],h,e,sh,conf): " cmd_choice cmd_choice1 </dev/tty
                                    [[ $? -eq 1 ]] && cmd_choice="q" # ctrl d 로 빠져나가는 경우
                                    #trap - SIGINT SIGTERM EXIT       # 트랩 해제 (이후에는 기본 동작)
                                    # flow 메뉴 하부 메뉴 종료
                                    [ -z "${cmd_choice-}" ] && echo "${ooldscut-}" | grep -q '^flow' && cmd_choice="b" && echo "Back to flow menu... [$ooldscut]" &&
                                        menufunc "$(scutsub "$ooldscut")" "$(scuttitle "$ooldscut")" "$(notscutrelay "$ooldscut")"
                                    [[ -n $cmd_choice ]] && break
                                done
                            else
                                # pre_command refresh
                                trap 'saveVAR;stty sane;exit' SIGINT SIGTERM EXIT # 트랩 설정
                                history -r
                                if [ -n "$newcmds" ]; then
                                    #readxy "$newcmds $newcmds1" && cmd_choice="$newcmds" && cmd_choice1="$newcmds1"
                                    readxy "$newcmds $newcmds1" && { cmd_choice="$newcmds" && cmd_choice1="$newcmds1"; } || { IFS=' ' read -rep ">>> Select No. ([0-$((display_idx - 1))],h,e,sh,conf): " cmd_choice cmd_choice1 </dev/tty; }
                                    unset -v newcmds newcmds1
                                else
                                    IFS=' ' read -rep ">>> Select No. ([0-$((display_idx - 1))],h,e,sh,conf): " cmd_choice cmd_choice1 </dev/tty
                                fi
                                #    IFS=' ' read -rep ">>> Select No. ([0-$((display_idx - 1))],h,e,sh,conf): " cmd_choice cmd_choice1 </dev/tty
                                [[ $? -eq 1 ]] && cmd_choice="q" # ctrl d 로 빠져나가는 경우
                                trap - SIGINT SIGTERM EXIT       # 트랩 해제 (이후에는 기본 동작)
                                # flow 메뉴 하부 메뉴 종료
                                [ -z "${cmd_choice-}" ] && echo "${ooldscut-}" | grep -q '^flow' && cmd_choice="b" && echo "Back to flow menu..."
                            fi
                            readxx $LINENO cmd_choice: $cmd_choice

                            ############ read cmd_choice
                            ############ read cmd_choice

                            # 선택하지 않으면 메뉴 다시 print // 선택하면 실제 줄번호 부여 -> 루프 2회 돌아서 주석 처리됨
                            # 참고) cmd_choice 변수는 최종 명령줄 화면에서 수신값 choice 변수는 메뉴(서브) 화면에서 수신값
                            # cmd_choice 는 4번 골랐다고 4번이 아니고 4번에 해당되는 줄번호를 가짐
                            [ "$cmd_choice" ] && [[ $cmd_choice == [0-9] || $cmd_choice == [1-9][0-9] ]] && [ "$cmd_choice" -gt 0 ] && cmd_choice=${original_indices[$((cmd_choice - 1))]}
                        } # end of choice_list()
                        ####################### end of choice_list #######################
                        ####################### end of choice_list #######################
                        ####################### end of choice_list #######################

                        # $env 환경파일에서 가져온 명령문 출력 && read cmd_choice
                        choice_list

                        # 명령어 선택후
                        if [ -n "$cmd_choice" ] && { case "$cmd_choice" in [0-9] | [1-9][0-9]) true ;; *) false ;; esac } && [ "$cmd_choice" -ge 1 ] && [ "$cmd_choice" -le "$num_commands" ]; then
                            chosen_command=${chosen_commands[$((cmd_choice - 1))]}
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
                        # Danger 판단
                        if [ "$(echo "$chosen_command" | awk '{print $1}')" == "!!!" ]; then
                            # !!! 제거 # !!! 앞에 공백이 간혹 있을때 버그 방지
                            chosen_command=${chosen_command#* }
                            chosen_command=${chosen_command#!!!}
                            echo -e "--> \x1b[1;31m$chosen_command\x1b[0m"
                            echo
                            # !!! -> danger print -> var cfm
                            printf "\x1b[1;33;41;4m !!!Danger!!! \x1b[0m Excute [Y/y/Enter or N/n]: " && read cfm
                        else
                            echo
                            cfm=y
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

                            echo -e "--> \x1b[1;36;40m$cmd\x1b[0m"

                            # 동일한 var 는 제외하고 read // awk '!seen[$0]++'
                            # noDanger
                            if [ "$cfm" == "y" ] || [ "$cfm" == "Y" ] || [ -z "$cfm" ]; then

                                # 명령줄에 varVAR 형태 기본값 지정을 위한 loop (ex. varA varB 등 한 명령줄에 여러개의 변수요청)
                                while read -r var; do
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

                                                IFS='\n'
                                                select dvar_value in "${dvar_value_array[@]}" All Cancel; do
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
                                                    fi

                                                done
                                                dvar_value="$selected_values"
                                            else
                                                # 주관식
                                                dvar_value="$reply"
                                            fi
                                            # 시작공백제거
                                            dvar_value=$(echo "$dvar_value" | sed 's/^ *//')

                                            # "all"을 입력했을 경우 "All Cancel"을 제외하고 모든 값 출력
                                            if echo "$dvar_value" | grep -qi '^all$'; then
                                                dvar_value=$(printf "%s\n" "${dvar_value_array[@]}" | grep -viE '^all$|^cancel$' | xargs)
                                            fi

                                        # 기본값이 하나일때
                                        else
                                            trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
                                            [ "$(echo "${var_name%%__*}" | grep -i path)" ] && GRN1 && echo "pwd: $(pwd)" && NC
                                            # 이전에 선택했던 값이 있으면 함께 출력
                                            if [ -n "${!org_var_name}" ]; then
                                                printf "==============================================
>>> Prev.selected value: $(tput bold)$(tput setaf 5)$(tput setab 0)${!org_var_name//\\/}$(tput sgr0)
!!(Cancel:c) Enter value for ${MAG1}[ ${YRE}${var_name%%__*}${NC}${MAG1} Default:$dvar_value] ${NC}:"
                                            else
                                                printf "==============================================
!!(Cancel:c) Enter value for ${MAG1}[ ${YRE}${var_name%%__*}${NC}${MAG1} Default:$dvar_value] ${NC}:"
                                            fi

                                            # printf "!!(Cancel:c) Enter value for \e[1;35;40m[${var_name%%__*} Default:$dvar_value] \e[0m: "
                                            readv var_value </dev/tty
                                            trap - INT
                                            [ "$var_value" == "c" ] && var_value="Cancel"
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
                                                #printf "!!(Cancel:c) Enter value for \e[1;35;40m[ ${var_name} env Default:$masked_dvar_value ] \e[0m:"
                                                printf "!!(Cancel:c) Enter value for ${MAG1}[ ${YRE}${var_name}${NC}${MAG1} env Default:$masked_dvar_value ] ${NC}:"
                                                readv var_value </dev/tty
                                                trap - INT
                                                [ "$var_value" == "c" ] && var_value="Cancel"
                                                eval flagof_"${var_name%%__*}"=set
                                                #eval flagof_"${org_var_name}"=set
                                            fi

                                        else
                                            trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
                                            [ "$(echo "${var_name}" | grep -i path)" ] && GRN1 && echo "pwd: $(pwd)" && NC
                                            printf "Enter value for \e[1;35;40m[$var_name]\e[0m:"
                                            readv var_value </dev/tty
                                            # ' " \ ->quoting
                                            if printf "%s" "$var_value" | grep -qE "[\\'\"]"; then
                                                var_value="$(printf %q "$var_value")"
                                            fi
                                            #echo "$var_value" && readx
                                            trap - INT
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
                                        escaped_regex_safe_var_name=$(printf '%s' "$regex_safe_var_name" | sed -e 's/[]\/$*.^|[]/\\&/g')
                                        cmd=$(printf '%s' "$cmd" | sed -E "s:$escaped_regex_safe_var_name([^a-zA-Z0-9]|$):${tmp_token}\\1:g")
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

                                    #done < <(echo "$cmd" | sed 's/\(var[A-Z][a-zA-Z0-9_.@-]*\)/\n\1\n/g' | sed -n '/var[A-Z][a-zA-Z0-9_.@-]*/p' | awk '!seen[$0]++')
                                    # 변수에는 @ 불가 변수값에는 @ 가능 // 구분하여 변수분할
                                done < <(echo "$cmd" | sed 's/\(var[A-Z][a-zA-Z0-9_.-]*\(__[a-zA-Z0-9_.@-]*\)\?\)/\n\1\n/g' | sed -n '/var[A-Z][a-zA-Z0-9_.-]*/p' | awk '!seen[$0]++')

                            # end of while

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
                        if [ "$num_commands" -eq 1 ]; then
                            #echo "scut:$scut / oldscut: $oldscut / ooldscut: $ooldscut" && readxy
                            if echo "$ooldscut" | grep -q '^flow_'; then
                                echo "go to $ooldscut" #; readxy
                                menufunc "$ooldscut"
                            elif echo "$scut" | grep -q '\<pxx\>'; then
                                echo "go to $ooldscut" #; readxy
                                menufunc "$ooldscut"
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
                    [[ -n $cmd_choice && ($cmd_choice == "0" || ${cmd_choice#0} != "$cmd_choice" || ${cmd_choice//[0-9]/}) || $cmd_choice -ge 100 ]] &&
                        {
                            YEL1
                            echo
                            echo "check your cmd_choice: $cmd_choice"
                            NC
                        } &&
                        case "$cmd_choice" in
                        # --- Basic Navigation & Commands ---
                        "0" | "q" | ".")
                            #if [ "$choice" == "99" ]; then
                            # scut 으로 들어온 경우, 상위메뉴타이틀 찾기
                            title_of_menu_sub="$(grep -B1 "^${chosen_command_sub}" "$env" | head -n1 | grep "^%%%" | sed -e 's/^%%% //g' -e 's/.*}//')"
                            title_of_menu=$title_of_menu_sub
                            readxx $LINENO "quit cmd_choice - pre_commands:$pre_commands"
                            t_chosen_command_sub=$chosen_command_sub
                            chosen_command_sub=""
                            listof_comm
                            chosen_command_sub=$t_chosen_command_sub
                            readxx $LINENO "quit cmd_choice after listof_comm - pre_commands:$pre_commands"
                            #[ -n "$title_of_menu_sub" ] && title_of_menu="$title_of_menu_sub"
                            readxx $LINENO "quit cmd_choice - env: $env title_of_menu_sub:$title_of_menu_sub {chosen_command_sub}:${chosen_command_sub} SHLVL:$SHLVL "
                            #fi
                            unsetvar varl
                            saveVAR
                            break # Exit the loop
                            ;;

                        ".." | "sh")
                            bashcomm && continue
                            ;;
                        "..." | "," | "bash")
                            /bin/bash # Start sub-shell
                            continue  # Run cmds after sub-shell exits
                            ;;
                        "m")
                            menufunc
                            ;;
                        "restart" | "rest")
                            echo "Restart $gofile.. [$scut]" && sleep 0.5 && savescut && exec "$gofile" "$scut"
                            ;;
                        "b" | "00")
                            echo "Back to previous menu.. [$ooldscut]" && savescut &&
                                menufunc "$(scutsub "$ooldscut")" "$(scuttitle "$ooldscut")" "$(notscutrelay "$ooldscut")"
                            ;;
                        "bb")
                            echo "Back two menus.. [$oooldscut]" && sleep 0.5 && savescut &&
                                menufunc "$(scutsub "$oooldscut")" "$(scuttitle "$oooldscut")" "$(notscutrelay "$oooldscut")"
                            ;;
                        "bbb")
                            echo "Back three menus.. [$ooooldscut]" && sleep 0.5 && savescut &&
                                menufunc "$(scutsub "$ooooldscut")" "$(scuttitle "$ooooldscut")" "$(notscutrelay "$ooooldscut")"
                            ;;
                        "<" | "before")
                            beforescut=$(st $scut b)
                            echo "Move to Before menu.. [$beforescut]" && sleep 0.5 && savescut && menufunc "$(scutsub "$beforescut")" "$(scuttitle "$beforescut")" "$(notscutrelay "$beforescut")"
                            ;;
                        ">" | "next")
                            nextscut=$(st $scut n)
                            echo "Move to Next menu.. [$nextscut]" && sleep 0.5 && savescut && menufunc "$(scutsub "$nextscut")" "$(scuttitle "$nextscut")" "$(notscutrelay "$nextscut")"
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
                            { ranger "$cmd_choice1" 2>/dev/null || explorer "$cmd_choice1"; } && cd $(</dev/shm/pwd) && dline && RED1 && echo "pwd: $(pwd)" && NC && dline && continue
                            ;;
                        "ee")
                            { ranger /etc 2>/dev/null || explorer /etc; } && cd $(</dev/shm/pwd) && dline && RED1 && echo "pwd: $(pwd)" && NC && dline && continue
                            ;;
                        "eee")
                            { ranger $(</dev/shm/pwd) 2>/dev/null || explorer $(</dev/shm/pwd); } && cd $(</dev/shm/pwd) && dline && RED1 && echo "pwd: $(pwd)" && NC && dline && continue
                            ;;
                        "cdr")
                            cd $(</dev/shm/pwd) && dline && RED1 && echo "pwd: $(pwd)" && NC && dline && ls -ltr | tail && bashcomm && continue
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
                            elif [[ -z $cmd_choice1 ]] && expr "$cmd_choice" : '^[0-9]\+$' >/dev/null && [ "$cmd_choice" -ge 100 ] && command -v pct >/dev/null 2>&1; then
                                dline
                                vmslistview | cgrepn running -3 | cgrepn1 $cmd_choice 3
                                readxy "Proxmox vm --> $(RED1)$cmd_choice$(NC) Enter" && enter "$cmd_choice"
                                continue
                            # Check 3: Valid Linux command? (Not purely numeric and exists)
                            #elif [[ "${cmd_choice//[0-9]/}" ]] && command -v "$cmd_choice" &>/dev/null; then
                            elif [[ "${cmd_choice//[0-9]/}" ]] && command -v "${cmd_choice%%[|;]*}" &>/dev/null; then
                                echo # Newline for formatting
                                echo "Executing command: $cmd_choice $cmd_choice1"
                                process_commands "$cmd_choice $cmd_choice1" y
                                # Log the executed command
                                # history -s "$cmd_choice $cmd_choice1"
                                # echo "$cmd_choice $cmd_choice1" >>"$gotmp"/go_history.txt 2>/dev/null
                                continue

                                # Check 4: Alias from .bashrc? (Fallback if not a command)
                                #elif [ "${cmd_choice//[0-9]/}" ] && aliascmd=$(grep -E "^[[:space:]]*alias[[:space:]]+$cmd_choice=" ~/.bashrc | sed -E "s/^[[:space:]]*alias[[:space:]]+$cmd_choice='(.*)'/\1/") && [[ -n $aliascmd ]]; then
                            elif [ "${cmd_choice//[0-9]/}" ] && aliascmd=$(grep -E "^[[:space:]]*alias[[:space:]]+$cmd_choice=" ~/.bashrc | sed -e "s/^[[:space:]]*alias[[:space:]]\+$cmd_choice='\(.*\)'/\1/") && [[ -n $aliascmd ]]; then

                                # Found alias definition 'aliascmd'.
                                # echo "cmd_choice:$cmd_choice -> Found alias in .bashrc: $cmd_choice='$aliascmd'"
                                echo "Executing in subshell with argument '$cmd_choice1': $aliascmd $cmd_choice1"

                                GRN1
                                dline
                                NC
                                # Execute in a subshell: Source .bashrc (to get all alias definitions, ignoring errors), enable alias expansion, then execute the original alias name ($cmd_choice, passed as $0) with arguments ($cmd_choice1 etc., passed via $@).
                                # This allows nested aliases like 'alias ll="ls -l"' and 'alias myll="ll -h"' to work correctly.
                                # WARNING: Sourcing .bashrc might fail silently or have side effects if it has strict interactive guards ([ -z "$PS1" ] && return).
                                trap 'stty sane' SIGINT
                                bash -c 'source ~/.bashrc 2>/dev/null; shopt -s expand_aliases; eval -- "$0" "$@"' "$cmd_choice" ${cmd_choice1:+"$cmd_choice1"}
                                #eval "$cmd_choice" "$cmd_choice1"
                                trap - INT
                                GRN1
                                dline
                                NC

                                # Clean up the temporary variable

                                # Optional: Log execution
                                echo "$cmd_choice $cmd_choice1" >>"$gotmp"/go_history.txt 2>/dev/null
                                echo 'Alias (from .bashrc) executed. Done... Sleep 2sec'
                                if ! echo "$aliascmd" | grep -q "ssh"; then sleep 2; fi
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
                menufunc
                ;;
            0 | "q" | .) # 메인/서브 메뉴 탈출 (quit)
                # title_of_menu_sub=""
                # chosen_command_sub=""
                chosen_command=""

                # 서브메뉴에서 탈출할경우 메인메뉴로 돌아옴
                if [ "$title_of_menu_sub" ]; then
                    menufunc
                else
                    saveVAR
                    exit 0
                fi
                ;;
            b | 00)
                echo "Back to previous menu.. [$ooldscut]" &&
                    savescut && menufunc "$(scutsub $ooldscut)" "$(scuttitle $ooldscut)" "$(notscutrelay "$ooldscut")" # back to previous menu
                ;;
            bb)
                echo "Back two menus.. [$oooldscut]" && sleep 0.5
                savescut && menufunc "$(scutsub $oooldscut)" "$(scuttitle $oooldscut)" "$(notscutrelay "$oooldscut")" # back to previous menu
                ;;
            bbb)
                echo "Back three menus.. [$ooooldscut]" && sleep 0.5
                savescut && menufunc "$(scutsub $ooooldscut)" "$(scuttitle $ooooldscut)" "$(notscutrelay "$ooooldscut")" # back to previous menu
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
                cd $(</dev/shm/pwd) && dline && RED1 && echo "pwd: $(pwd)" && NC && dline
                ;;
            "ee")
                { ranger /etc 2>/dev/null || explorer /etc; }
                cd $(</dev/shm/pwd) && dline && RED1 && echo "pwd: $(pwd)" && NC && dline
                ;;
            "eee")
                #{ ranger $(</dev/shm/pwd) 2>/dev/null || explorer $(</dev/shm/pwd) ; }
                ranger $(</dev/shm/pwd) 2>/dev/null || explorer $(</dev/shm/pwd)
                cd $(</dev/shm/pwd) && dline && RED1 && echo "pwd: $(pwd)" && NC && dline
                ;;
            "cdr")
                cd $(</dev/shm/pwd) && dline && RED1 && echo "pwd: $(pwd)" && NC && dline && ls -ltr | tail && bashcomm
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
                    echo "이곳이그곳!!! " && sleep 2
                    choice=""
                    #readxx $LINENO shortcut move choice $choice

                # Check : proxmox vm enter? 100~
                elif [[ -z $choice1 ]] && expr "$choice" : '^[0-9]\+$' >/dev/null && [ "$choice" -ge 100 ] && command -v pct >/dev/null 2>&1; then
                    dline
                    vmslistview | cgrepn running -3 | cgrepn1 $choice 3
                    readxy "Proxmox vm --> $(RED1)$choice$(NC) Enter" && enter "$choice"

                # 실제 리눅스 명령이 들어온 경우 실행
                # Check: is not purely numeric AND is a valid command
                elif [ "${choice//[0-9]/}" ] && command -v "$choice" &>/dev/null; then
                    {
                        echo "Executing command: $choice $choice1"
                        process_commands "$choice $choice1" y
                        # log
                        # history -s "$choice $choice1"
                        # echo "$choice $choice1" >>"$gotmp"/go_history.txt 2>/dev/null
                    }

                    # choice 가 이까지 왔으면 .bashrc alias 평소 습관처럼 쳤다고 봐야지
                    # Check: is not purely numeric AND is defined as an alias in .bashrc
                    # elif [ "${choice//[0-9]/}" ] && aliascmd=$(grep -E "^[[:space:]]*alias[[:space:]]+$choice=" ~/.bashrc | sed -E "s/^[[:space:]]*alias[[:space:]]+$choice='(.*)'/\1/") && [[ -n $aliascmd ]]; then
                elif [ "${choice//[0-9]/}" ] && aliascmd=$(grep -E "^[[:space:]]*alias[[:space:]]+$choice=" ~/.bashrc | sed -e "s/^[[:space:]]*alias[[:space:]]\+$choice='\(.*\)'/\1/") && [[ -n $aliascmd ]]; then

                    # echo "Choice:$choice -> Found alias in .bashrc: $choice='$aliascmd'"
                    echo "Executing in subshell with argument '$choice1': $aliascmd $choice1"

                    GRN1
                    dline
                    NC
                    # Execute in a subshell: Source .bashrc (to get all alias definitions, ignoring errors), enable alias expansion, then execute the original alias name ($cmd_choice, passed as $0) with arguments ($cmd_choice1 etc., passed via $@).
                    # This allows nested aliases like 'alias ll="ls -l"' and 'alias myll="ll -h"' to work correctly.
                    # WARNING: Sourcing .bashrc might fail silently or have side effects if it has strict interactive guards ([ -z "$PS1" ] && return).
                    trap 'stty sane' SIGINT
                    bash -c 'source ~/.bashrc 2>/dev/null; shopt -s expand_aliases; eval -- "$0" "$@"' "$choice" ${choice1:+"$choice1"}
                    #eval "$choice" "$choice1"
                    trap - INT
                    GRN1
                    dline
                    NC

                    echo "$choice $choice1" >>"$gotmp"/go_history.txt 2>/dev/null
                    echo 'Alias (from .bashrc) executed. Done... Sleep 2sec' && noclear="y"
                    if ! echo "$aliascmd" | grep -q "ssh"; then sleep 2; fi
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

# 함수의 내용을 출력하는 함수 ex) ff atqq
fff() { declare -f "$@"; }
ffe() { conff "^$1()"; }

ff() {
    if [ -z "$1" ]; then
        declare -f
        return
    fi

    local target="$1"
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

# colored ip (1 line multi ip apply)
cip() { awkf '{line=$0;while(match(line,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)){IP=substr(line,RSTART,RLENGTH);line=substr(line,RSTART+RLENGTH);if(!(IP in FC)){BN[IP]=1;if(TC<6){FC[IP]=36-TC;}else{do{FC[IP]=37-(TC-6)%7;BC[IP]=40+(TC-6)%8;TC++;}while(FC[IP]==BC[IP]-10);if(FC[IP]<31)FC[IP]=37;}TC++;}if(TC>6&&BC[IP]>0){CP=sprintf("\033[%d;%d;%dm%s\033[0m",BN[IP],FC[IP],BC[IP],IP);}else{CP=sprintf("\033[%d;%dm%s\033[0m",BN[IP],FC[IP],IP);}gsub(IP,CP,$0);}print}' 2>/dev/null; }

# 실시간 출력 tail -f 등에 즉각 반응
#cipf() { sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/\x1B[1;31m&\x1B[0m/g'; }
cipf() { sed -e 's/\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}/\o033[1;31m&\o033[0m/g'; }

ipc() { ip a | cgrep DOWN | cgrep1 UP | cip; }
ipa() { ip a | cgrep DOWN | cgrep1 UP | cip; }
ipl() { ip l | cgrep DOWN | cgrep1 UP | cip; }

# colred ip cidr/24 -> same color
cip24() { awk '{line=$0; while (match(line, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {IP=substr(line, RSTART, RLENGTH); line=substr(line, RSTART+RLENGTH); Prefix=IP; sub(/\.[0-9]+$/, "", Prefix); if (!(Prefix in FC)) {BN[Prefix]=1; if (TC<6) {FC[Prefix]=36-TC;} else { do {FC[Prefix]=30+(TC-6)%8; BC[Prefix]=(40+(TC-6))%48; TC++;} while (FC[Prefix]==BC[Prefix]-10); if (FC[Prefix]==37) {FC[Prefix]--;}} TC++;} if (BC[Prefix]>0) {CP=sprintf("\033[%d;%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], BC[Prefix], IP);} else {CP=sprintf("\033[%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], IP);} gsub(IP, CP, $0);} print;}'; }

# colred ip cidr/16 -> same color
cip16() { awk '{line=$0; while (match(line, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {IP=substr(line, RSTART, RLENGTH); line=substr(line, RSTART+RLENGTH); Prefix=IP; sub(/\.[0-9]+\.[0-9]+$/, "", Prefix); if (!(Prefix in FC)) {BN[Prefix]=1; if (TC<6) {FC[Prefix]=36-TC;} else { do {FC[Prefix]=30+(TC-6)%8; BC[Prefix]=(40+(TC-6))%48; TC++;} while (FC[Prefix]==BC[Prefix]-10); if (FC[Prefix]==37) {FC[Prefix]--;}} TC++;} if (BC[Prefix]>0) {CP=sprintf("\033[%d;%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], BC[Prefix], IP);} else {CP=sprintf("\033[%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], IP);} gsub(IP, CP, $0);} print;}'; }

# 검색문자열들 색칠(red)
cgrep() {
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
    for word in "$@"; do
        escaped_word=${word//\//\\/}
        awk_cmd="${awk_cmd}{gsub(/$escaped_word/, \"\033[1;33m&\033[0m\")}"
    done
    awk "${awk_cmd}{print}"
}
# 검색문자열줄을 색칠 (red)
cgrepl() {
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
    local args=("$@")
    local search_strs=()
    local num_cols=0
    if [ "${#args[@]}" -eq 0 ]; then
        echo "Usage: cgrepn [search_strings...] [num_cols]"
        return 1
    fi
    if echo "${args[-1]}" | grep -qE '^-?[0-9]+$'; then
        num_cols="${args[-1]}"
        search_strs=("${args[@]:0:${#args[@]}-1}")
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
    local args=("$@")
    local search_strs=()
    local num_cols=0
    if [ "${#args[@]}" -eq 0 ]; then
        echo "Usage: cgrepn [search_strings...] [num_cols]"
        return 1
    fi
    if echo "${args[-1]}" | grep -qE '^-?[0-9]+$'; then
        num_cols="${args[-1]}"
        search_strs=("${args[@]:0:${#args[@]}-1}")
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

safe_eval() {
    local cmd="$1" re='(^|[[:space:]])(rm[[:space:]]+-rf[[:space:]]+/[[:space:]]*($|[[:space:]]+|#)|reboot|shutdown|mkfs)([[:space:]]|$)|\>\s*/etc/(passwd|shadow|group)\b|\>\s*/dev/sd[a-z]+\b'
    echo "$cmd" | grep -qE "$re" && {
        echo
        RED1
        echo "!!! 위험 명령어 감지!"
        echo "   $cmd"
        NC
        readxy "   실행하시겠습니까?" || return 1
    }
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

# selectmenu
selectmenu() { select item in $@; do echo $item; done; }

# pipe 로 넘어온 줄의 모든 필드를 select 구분자-> 빈칸 빈줄 파이프(|}
pipemenu() {
    local prompt_message="$@"
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
}

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
    printf '\n%.0s' {1..100}
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
old_scutall() {
    # 밑줄 abc_bcd 같은 단축키 못찾음
    scut=$1
    scut_item_idx=$(echo "$shortcutstr" | sed -n "s/.*@@@$scut|\([0-9]*\)@@@.*/\1/p") # 배열번호 0~99 찾기
    scut_item="$([ -n "$scut_item_idx" ] && echo "${shortcutarr[$scut_item_idx]}")"   # 배열번호에 있는 값 추출
    echo "$scut_item"
}
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
# gipa0 아이피 끝자리 .0 대체 /24
gipa0() { awk '{while(match($0, /[0-9]+\.[0-9]+\.[0-9]+/)) {print substr($0, RSTART, RLENGTH) ".0"; $0 = substr($0, RSTART+RLENGTH)}}'; }
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
gip3() { awk 'match($3, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {print substr($3, RSTART, RLENGTH)}'; }
gip4() { awk 'match($4, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {print substr($4, RSTART, RLENGTH)}'; }
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
eip1() { eipf 1; }
eip2() { eipf 2; }
eip3() { eipf 3; }
eip4() { eipf 4; }
eip5() { eipf 5; }

nodeip() {
    local node="$1"
    jq -r --arg node "$node" '.nodelist[$node].ip // empty' /etc/pve/.members
}

# proxmox vmslist

vmslistold() { pvesh get /cluster/resources -type vm --noborder --noheader 2>/dev/null | awk '{print $1,$17,$23}' | awk '{if($2=="") print $1,"cluster down"; else print $0}'; }
vmslist() {
    pvesh get /cluster/resources -type vm --noborder --noheader 2>/dev/null |
        awk '{print $1,$17,$23}' |
        awk '{if($2=="") print $1,"unknown","cluster down"; else print $0}' |
        awk -F'[ /]' '{print $2, $1, $3, $4}' |
        column -t
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
    bashver=${BASH_VERSINFO[0]}
    ((bashver < 3)) && IFS="" read -rep $'\n>>> : ' $1 || IFS="" read -rep ' ' $1
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
oldst() {
    # 인수가 없으면 전체 문자열 출력 (Bash 2 호환)
    if [ $# -eq 0 ]; then
        echo "$shortcutstr"
        return 0
    fi

    # local 변수는 Bash 2에서 사용 가능
    local shortcut="$1"
    local mode="$2"

    # 필수 인수가 없거나 모드가 잘못된 경우 간단한 도움말 표시 (Bash 2 호환)
    # [ ] 구문과 -o (OR), -a (AND) 또는 개별 조건문 사용
    if [ -z "$shortcut" ] || [ -z "$mode" ]; then
        echo "사용법: st <shortcut> <n|b>  또는 st" >&2
        return 1
    fi
    # 모드 검사를 별도로 수행 (AND/OR 연산자 복잡성 회피)
    if [ "$mode" != "n" ] && [ "$mode" != "b" ]; then
        echo "사용법: st <shortcut> <n|b>  또는 st" >&2
        return 1
    fi

    # awk 사용: <<< 대신 echo ... | 사용 (Bash 2 호환)
    # awk 스크립트 내용은 동일하게 유지
    echo "$shortcutstr" | awk -v shortcut="$shortcut" -v mode="$mode" -v RS='@@@' -F'|' '
        # 첫 번째 빈 레코드 건너뛰기 (문자열이 @@@로 시작하므로)
        NR <= 1 { next }

        # "n" (next) 모드 처리
        mode == "n" {
            if (print_next) {
                print $1
                exit # awk 종료
            }
            if ($1 == shortcut) {
                print_next = 1
            }
        }

        # "b" (before) 모드 처리
        mode == "b" {
            if ($1 == shortcut) {
                # prev_key가 비어있으면(첫 항목) 아무것도 출력되지 않음
                print prev_key
                exit # awk 종료
            }
            prev_key = $1
        }
    '
    # awk가 결과를 표준 출력으로 직접 보냄

    # 요구사항에 따라 사용법 오류 외에는 항상 성공(0) 반환
    return 0
}
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

# flow save and exec go.sh
savescut() {
    :
    #scutp
    #export scut=$scut oldscut=$oldscut ooldscut=$ooldscut oooldscut=$oooldscut ooooldscut=$ooooldscut
    #dline ; env | grep scut
}

# varVAR 형태의 변수를 파일에 저장해 두었다가 스크립트 재실행시 사용
viewVAR() { declare -p | grep "^declare -x var[A-Z]"; }
saveVAR() {
    declare -p | grep "^declare -x var[A-Z]" >>~/.go.private.var
    #declare -p | grep "^declare -x" >~/.go.export.var
    declare -p | grep "^declare -x" | encrypt >~/.go.export.var
    cat ~/.go.private.var | lastseen >~/.go.private.var.tmp && mv ~/.go.private.var.tmp ~/.go.private.var
    chmod 600 ~/.go.private.var
}
loadVAR() {
    [ -f ~/.go.private.var ] && source ~/.go.private.var
    [ -f ~/.go.export.var ] && find "$HOME/.go.export.var" -type f -mmin +10 -exec rm -f "$HOME/.go.export.var" \;
    [ -f ~/.go.export.var ] && cat "$HOME/.go.export.var" | decrypt >"$HOME/.go.export.var." && mv -f "$HOME/.go.export.var." "$HOME/.go.export.var"
    [ -f ~/.go.export.var ] && source "$HOME/.go.export.var" && rm -f "$HOME/.go.export.var"
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
# vi2 envorg && restart go.sh
conf() {
    #readxy $cmd_choice1
    saveVAR
    if [ -n "$1" ]; then
        vi2 "$envorg" $1 $cmd_choice1
    else
        vi2 "$envorg" $scut $cmd_choice1
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
    local message
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
        curl -m3 -ks -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" -d chat_id=${telegram_chatid} -d text="${message:-ex) push "msg"}" >/dev/null
        result=$?
        #curl -m3 -ks -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" -d chat_id=${telegram_chatid} -d text="${message:-ex) push "msg"}" ; result=$?
        [ "$result" == 0 ] && { GRN1 && echo "push msg sent"; } || { RED1 && echo "Err:$result ->  push send error"; }
        NC
    fi
    # 기본적으로 인자 출력
    echo "$message"
}

push1() {
    local message
    message="$*"
    [ -z "$message" ] && IFS='' read -d '' -t1 message
    [ -z "$message" ] && message="$HOSTNAME"

    # Telegram 정보가 없으면 메시지만 출력
    if [[ -z ${telegram_token} || -z ${telegram_chatid} ]]; then
        echo -e "\a[push1] $message"
        return 1
    fi

    # Telegram으로 전송
    curl -m3 -ks -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" \
        -d chat_id="${telegram_chatid}" -d text="${message}" >/dev/null

    result=$?
    if [ "$result" -eq 0 ]; then
        GRN1 && echo "push1 msg sent" && bell
    else
        RED1 && echo "Err:$result -> push1 send error" && bell
    fi
    NC

    echo "$message"
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

isdomain() { echo "$1" | grep -E '^(www\.)?([a-z0-9]+(-[a-z0-9]+)*\.)+(com|net|kr|co.kr|org|io|info|xyz|app|dev)(\.[a-z]{2,})?$' >/dev/null && return 0 || return 1; }

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
        echo ": alarm_task_$input && curl -m3 -ks -X POST \"https://api.telegram.org/bot${telegram_token}/sendMessage\" -d chat_id=${telegram_chatid} -d text=\"${telegram_msg}\"" | at "$time_in_hours":"$time_in_minutes" "$( ((days > 0)) && echo "today + $days" days)" &>/dev/null

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

        echo ": alarm_task_$input && sleep $wait_seconds && curl -m3 -ks -X POST 'https://api.telegram.org/bot${telegram_token}/sendMessage' -d chat_id=${telegram_chatid} -d text='${telegram_msg}'" | at now + "$adjusted_minutes" minutes &>/dev/null

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
        sleepdot $time_in_seconds && curl -m3 -ks -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" -d chat_id=${telegram_chatid} -d text="${telegram_msg}" &>/dev/null

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
        algorithms=$(echo "$output" | grep -oP 'Their offer: \K.*?(?=\r|\n)' | sed 's/ /,/g')
        printf "Host %s\n    HostKeyAlgorithms +%s\n    PubkeyAcceptedKeyTypes +ssh-rsa\n" "$1" "$algorithms" | tee -a "$HOME/.ssh/config" >/dev/null
        echo "HostKey config saved, reconnecting..."
        ssh "$@"
    elif echo "$output" | grep -q "no matching key exchange method found"; then
        algorithms=$(echo "$output" | grep -oP 'Their offer: \K.*?(?=\r|\n)' | sed 's/ /,/g')
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

old_userinfo() {
    if [ -z "$1" ] || [ "$1" = "--help" ]; then
        printf "\033[1mUsage:\033[0m userinfo <username> [section]\n"
        echo "Sections: all (default), basic, activity, resources"
        return 1
    fi
    USERNAME="$1"
    SECTION="${2:-all}"
    USERINFO=$(getent passwd "$USERNAME")
    if [ -z "$USERINFO" ]; then
        printf "\033[1;31m[!] 사용자 '%s' 정보를 찾을 수 없습니다.\033[0m\n" "$USERNAME"
        return 1
    fi

    # <<< 제거 → echo + read 로 대체
    IFS=':'
    echo "$USERINFO" | while read NAME PASS USER_UID GID INFO HOME SHELL; do
        OUTPUT=""

        print_section() {
            title="$1"
            content="$2"
            OUTPUT="${OUTPUT}\033[1;34m\n╔══════════════════════════════════════╗\n║  $title\n╚══════════════════════════════════════╝\033[0m\n"
            if [ -z "$content" ]; then
                formatted_content="  (정보 없음)\n"
            else
                formatted_content=$(echo "$content" | awk -F':' '
                    NF == 0 { next }
                    NF == 1 { printf "  %s\n", $0; next }
                    NF > 1 {
                        key = $1
                        sub(/^[^:]+:[ \t]*/, "")
                        value = $0
                        gsub(/^[ \t]+|[ \t]+$/, "", key)
                        gsub(/^[ \t]+|[ \t]+$/, "", value)
                        if (value == "") value = "(없음)"
                        printf "  \033[1;37m%-30s\033[0m: \033[1;36m%s\033[0m\n", key, value
                    }
                ')
                [ -z "$formatted_content" ] && formatted_content="  (정보 없음)\n"
            fi
            OUTPUT="${OUTPUT}${formatted_content}\n"
        }

        if [ "$SECTION" = "all" ] || [ "$SECTION" = "basic" ]; then
            ACCOUNT_STATUS=$(passwd -S "$USERNAME" 2>/dev/null | awk '{print $2}')
            case "$ACCOUNT_STATUS" in
            P) ACCOUNT_STATUS_DESC="Password set" ;;
            L) ACCOUNT_STATUS_DESC="Locked" ;;
            NP) ACCOUNT_STATUS_DESC="No password" ;;
            *) ACCOUNT_STATUS_DESC="Unknown" ;;
            esac
            LAST_CHANGED_DATE=$(passwd -S "$USERNAME" 2>/dev/null | awk '{print $3}')
            CHAGE_INFO=$(chage -l "$USERNAME" 2>/dev/null | sed 's/ : /:/g')
            BASIC_CONTENT="사용자명: $NAME
UID: $USER_UID
GID: $GID
전체 이름: $INFO
홈 디렉토리: $HOME
기본 쉘: $SHELL

--- 계정 상태 ---
계정 상태: $ACCOUNT_STATUS_DESC
최근 변경일: $LAST_CHANGED_DATE

--- 비밀번호 정책 ---
$CHAGE_INFO"
            print_section "➤ 기본 정보 (Basic)" "$BASIC_CONTENT"
        fi

        if [ "$SECTION" = "all" ] || [ "$SECTION" = "activity" ]; then
            WHO_INFO=$(who | grep "$USERNAME" || echo "현재 로그인 정보 없음")
            LAST_LOG=$(last "$USERNAME" | head -n 5 || echo "로그인 이력 없음")
            PROCESS_INFO=$(ps -u "$USERNAME" --forest -o pid,tty,stat,time,cmd 2>/dev/null || echo "실행 중인 프로세스 없음")
            if [ -r /var/log/maillog ]; then
                MAIL_LOG=$(grep "$USERNAME" /var/log/maillog 2>/dev/null | tail -n 5)
            elif [ -r /var/log/mail.log ]; then
                MAIL_LOG=$(grep "$USERNAME" /var/log/mail.log 2>/dev/null | tail -n 5)
            else
                MAIL_LOG="메일 로그 파일 없음 또는 접근 권한 없음 (/var/log/maillog, /var/log/mail.log)"
            fi
            [ -z "$MAIL_LOG" ] && MAIL_LOG="메일 관련 로그 기록 없음"
            ACTIVITY_CONTENT="--- 현재 로그인 세션 ---
$WHO_INFO

--- 최근 로그인 로그 (최대 5회) ---
$LAST_LOG

--- 사용자 프로세스 ---
$PROCESS_INFO

--- 메일 관련 로그 (최대 5줄, sudo 필요) ---
$MAIL_LOG"
            print_section "➤ 활동 정보 (Activity)" "$ACTIVITY_CONTENT"
        fi

        if [ "$SECTION" = "all" ] || [ "$SECTION" = "resources" ]; then
            ID_INFO=$(id "$USERNAME")
            GROUPS_INFO=$(groups "$USERNAME")
            HOME_INFO=$(ls -ld "$HOME")
            HOME_USAGE=$(du -sh "$HOME" 2>/dev/null || echo "홈 디렉토리 사용량 확인 불가 (권한 또는 존재 여부)")
            SHADOW_INFO=$(sudo grep "^$USERNAME:" /etc/shadow 2>/dev/null | cut -d: -f1-8 || echo "Shadow 정보 접근 불가 (sudo 권한 필요)")
            RESOURCES_CONTENT="--- ID 및 그룹 정보 ---
$ID_INFO
소속 그룹: $GROUPS_INFO

--- 홈 디렉토리 상태 ---
$HOME_INFO

--- 홈 디렉토리 사용량 ---
$HOME_USAGE

--- 비밀번호 정보 (/etc/shadow, sudo 필요) ---
$SHADOW_INFO
(형식: username:password_hash:last_change:min_days:max_days:warn_days:inactive_days:expire_date)"
            print_section "➤ 권한 및 리소스 (Resources)" "$RESOURCES_CONTENT"
        fi

        if [ "$SECTION" != "all" ] && ! echo " basic activity resources " | grep -q " $SECTION "; then
            printf "\033[1;31m[!] 잘못된 섹션: '%s'\033[0m\n" "$SECTION"
            echo "사용 가능한 섹션: all, basic, activity, resources"
            return 1
        fi

        if [ -n "$OUTPUT" ]; then
            echo -e "$OUTPUT" # | less -RX
        else
            if echo " basic activity resources all " | grep -q " $SECTION "; then
                printf "\033[1;33m[!] 출력할 내용이 없습니다. 섹션 '%s'을 확인하세요.\033[0m\n" "$SECTION"
            fi
        fi
    done
    unset IFS
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

old_qssh() {
    # --- 설정 ---
    local default_user="root" # 사용자 미지정 시 기본값
    local arp_scan_timeout=3  # arp-scan 대기 시간 (초)
    # --- 설정 끝 ---

    # 인수 개수 확인 (최소 1개, 최대 2개)
    if [[ $# -eq 0 || $# -gt 2 ]]; then
        echo "Usage: qssh <vmid> [ssh_user]"
        echo "  Example 1 (default user '$default_user'): qssh 101"
        echo "  Example 2 (specify user):        qssh 101 myuser"
        return 1
    fi

    local vmid="$1" # 첫 번째 인수는 항상 VM ID
    # 두 번째 인수가 있으면 사용하고, 없으면 기본값 사용
    local user="${2:-$default_user}"

    # VM ID가 숫자인지 간단히 확인
    if ! echo "$vmid" | grep -qE '^[0-9]+$'; then

        echo "Error: Invalid VMID format '$vmid'. It should be a number."
        return 1
    fi

    # 사용자 이름이 비어있는지 확인 (거의 발생 안 함)
    if [[ -z $user ]]; then
        # 이 경우는 "$2"가 비어있는 문자열("")로 들어왔을 때 발생 가능
        echo "Error: SSH username cannot be empty if provided."
        return 1
    fi

    echo "--- Processing qssh for VM $vmid (User: $user) ---"

    # --- 이하 로직은 이전 버전과 동일 ---

    # 1. VM 설정 가져오기 및 MAC/브리지 추출
    echo "[1] Getting VM configuration..."
    local config_line
    config_line=$(qm config "$vmid" 2>/dev/null | grep -E '^net[0-9]+:' | grep 'bridge=' | head -n 1)

    if [[ -z $config_line ]]; then
        if ! qm status "$vmid" >/dev/null 2>&1; then
            echo "Error: VM $vmid does not seem to exist."
        else
            echo "Error: Could not find a bridged network interface for VM $vmid."
        fi
        return 1
    fi

    local mac bridge
    mac=$(echo "$config_line" | grep -oP '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
    bridge=$(echo "$config_line" | sed -n 's/.*bridge=\([^,]\+\).*/\1/p')

    if [[ -z $mac || -z $bridge ]]; then
        echo "Error: Failed to extract MAC or Bridge from: '$config_line'"
        return 1
    fi

    local lower_mac
    lower_mac=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
    echo "  > Found MAC: $mac (checking as $lower_mac) on Bridge: $bridge"

    # 2a. 로컬 ARP 캐시에서 IP 주소 먼저 확인
    echo "[2a] Checking local ARP cache for $lower_mac..."
    local ip=""
    ip=$(arp -n | grep -i "$lower_mac" | awk '{print $1}' | head -n 1)

    # 2b. ARP 캐시에 없으면 arp-scan 사용 (Fallback)
    if [[ -z $ip ]]; then
        echo "  > MAC not found in ARP cache. Proceeding with arp-scan..."

        if ! command -v arp-scan &>/dev/null; then
            echo "Error: 'arp-scan' command not found. Please install it (e.g., apt install arp-scan)."
            return 1
        fi

        echo "[2b] Finding IP address via arp-scan..."
        echo "  > Scanning on $bridge for MAC: $lower_mac..."
        local arp_scan_output
        arp_scan_output=$(arp-scan --interface="$bridge" --localnet --numeric --quiet --timeout=$((arp_scan_timeout * 1000)) 2>/dev/null | grep -i "$lower_mac")

        if [[ -z $arp_scan_output ]]; then
            echo "Error: arp-scan could not find MAC $lower_mac on interface $bridge."
            echo "  > Check if VM $vmid is running and has obtained an IP address."
            echo "  > Double check network/firewall settings."
            return 1
        fi

        ip=$(echo "$arp_scan_output" | head -n 1 | awk '{print $1}')

        if [[ -z $ip ]]; then
            echo "Error: Found MAC via arp-scan, but could not extract IP address from output line:"
            echo "  '$arp_scan_output'"
            return 1
        fi
        echo "  > Found IP via arp-scan: $ip"

    else
        echo "  > Found IP in ARP cache: $ip"
    fi

    if [[ -z $ip ]]; then
        echo "Error: Failed to determine IP address for MAC $lower_mac."
        return 1
    fi

    # 3. SSH 접속
    echo "[3] Attempting SSH connection..."
    echo "  > Running: ssh $user@$ip"
    # SSH 접속 시도 (-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null 옵션은
    # 보안상 필요에 따라 추가/제거. 여기서는 기본 ssh 명령 사용)
    ssh "$user@$ip"
    local ssh_exit_code=$?

    if [[ $ssh_exit_code -ne 0 ]]; then
        echo "--- SSH session for $user@$ip (VM $vmid) ended with exit code $ssh_exit_code. ---"
        return $ssh_exit_code
    else
        echo "--- SSH session for $user@$ip (VM $vmid) finished successfully. ---"
        return 0
    fi
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
    local args=("$@")
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
    t=$(date +%Y%m%d)
    while [ $# -gt 0 ]; do
        d="${1%/}"
        base="$d"
        if [ -f "$d" ] && [[ "$(diff $d ${base}.1.bak 2>/dev/null)" || ! -f ${base}.1.bak ]]; then
            d9=$(date -r ${base}.9.bak +%Y%m%d 2>/dev/null)
            d8=$(date -r ${base}.8.bak +%Y%m%d 2>/dev/null)
            if [ -f "${base}.9.bak" ] && [[ $t == "$d8" && $t != "$d9" ]]; then
                cdate=$(date -r ${base}.9.bak +%Y%m%d)
                mv ${base}.9.bak ${base}.${cdate}.bak
            fi
            for i in 8 7 6 5 4 3 2 1 ""; do
                cmd=${i:+mv}
                cmd=${cmd:-cp}
                $cmd ${base}.${i}.bak ${base}.$((${i:-0} + 1)).bak 2>/dev/null
            done
            cp $d ${base}.1.bak
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

old_hash_add() {
    # --- Arguments & Basic Validation ---
    local fpath="$1" search="$2" num_arg="$3"
    # Default: Comment 1 line (the matched one)
    local num_lines=1
    local bk_suffix ts bk_fname ret perl_p quoted_s DIFF_CMD="cdiff" # Assume cdiff exists

    # Validate number of arguments
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
        echo "Usage: hash_add <filepath> <search> [total_lines]" >&2
        echo "  - comments matched line (if not already commented)." >&2
        echo "  - if total_lines >= 1, comments that many lines total," >&2
        echo "    starting with the matched one. Subsequent lines get '# ' prepended." >&2
        return 1
    fi

    # Validate optional total_lines argument
    if [ $# -eq 3 ]; then
        # Must be an integer >= 1
        if ! echo "$num_arg" | grep -qE '^[1-9][0-9]*$'; then
            echo "Error: total_lines must be an integer >= 1." >&2
            return 1
        fi
        num_lines="$num_arg"
    fi

    # Validate file exists
    if [ ! -f "$fpath" ]; then
        echo "Error: File not found: $fpath" >&2
        return 1
    fi

    # --- Setup ---
    ts=$(date +%Y%m%d_%H%M%S)
    bk_suffix="_${ts}.bak"
    bk_fname="${fpath}${bk_suffix}"
    # Quote search pattern for Perl regex
    quoted_s=$(perl -e 'print quotemeta shift' "$search")
    [ -z "$quoted_s" ] && {
        echo "Error: Failed to quote search pattern (empty?)." >&2
        return 1
    }

    # --- Perl Script (concise, uses env vars P and N) ---
    # $c: counter for lines remaining to force-comment *after* the matched line.
    # $ENV{P}: Quoted search Pattern.
    # $ENV{N}: Total number of lines to comment (including matched).
    # On match, set counter c to N-1 (remaining lines).
    perl_p='
        BEGIN { $c = 0 }
        if (m/$ENV{P}/) {
            # Matched line: Comment if needed
            unless (/^\s*#/) { $_ = "# " . $_ }
            # Set counter for remaining lines (Total N lines - 1 matched line = N-1)
            $c = $ENV{N} - 1;
        } elsif ($c-- > 0) {
            # Subsequent lines to force-comment
            $_ = "# " . $_;
        }
        print;
    '
    # One-liner version:
    # perl_p='BEGIN{$c=0} if(m/$ENV{P}/){unless(/^\s*#/){$_="# ".$_} $c=$ENV{N}-1}elsif($c-->0){$_="# ".$_} print'

    # --- Execution ---
    export P="$quoted_s" N="$num_lines" # Pass total lines N
    perl "-i${bk_suffix}" -n -e "$perl_p" "$fpath"
    ret=$?
    unset P N # Clean up environment

    # --- Reporting ---
    if [ $ret -eq 0 ]; then
        echo "Hash Add potentially done. Backup: $bk_fname"
        # Check if backup exists and differs before showing diff
        if [ -f "$bk_fname" ]; then
            if ! cmp -s "$bk_fname" "$fpath"; then
                echo "--- Diff (${DIFF_CMD}) ---"
                "$DIFF_CMD" "$bk_fname" "$fpath"
                echo "--------------------"
            else
                echo "Info: No effective changes made to file content."
            fi
        else
            echo "Info: No changes made (no backup created)."
        fi
        return 0
    else
        echo "Error during Hash Add (code: $ret). Check backup: $bk_fname" >&2
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

old_hash_remove() {
    local fpath="$1" search="$2" num_arg="$3"
    local num_lines=1
    local bk_suffix ts bk_fname ret perl_p quoted_s DIFF_CMD="cdiff"
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
        echo "Usage: hash_remove <filepath> <search> [total_lines]" 1>&2
        return 1
    fi
    if [ $# -eq 3 ]; then
        if ! echo "$num_arg" | grep -Eq '^[1-9][0-9]*$'; then
            echo "Error: total_lines must be an integer >= 1." 1>&2
            return 1
        fi
        num_lines="$num_arg"
    fi
    if [ ! -f "$fpath" ]; then
        echo "Error: File not found: $fpath" 1>&2
        return 1
    fi
    if [ ! -w "$fpath" ]; then
        echo "Error: File not writable: $fpath" 1>&2
        return 1
    fi
    ts=$(date +%Y%m%d_%H%M%S)
    bk_suffix="_${ts}.bak"
    bk_fname="${fpath}${bk_suffix}"
    quoted_s=$(perl -e 'print quotemeta shift' "$search")
    [ -z "$quoted_s" ] && {
        echo "Error: Failed to quote search pattern (empty?)." 1>&2
        return 1
    }
    echo "Debug: Searching for pattern: $quoted_s" 1>&2
    perl_p='
        BEGIN { $c = 0 }
        if (m/^\s*#\s*.*?\Q$ENV{P}\E/) {
             s/^(\s*)#\s*/$1/;
             $c = $ENV{N} - 1;
             print STDERR "Debug: Matched and modified: $_";
        } elsif ($c-- > 0) {
             s/^(\s*)#\s*/$1/ if m/^\s*#\s*/;
        }
        print;
    '
    export P="$quoted_s" N="$num_lines"
    perl "-i${bk_suffix}" -n -e "$perl_p" "$fpath"
    ret=$?
    unset P N
    if [ $ret -eq 0 ]; then
        echo "Hash Remove potentially done. Backup: $bk_fname"
        if [ -f "$bk_fname" ]; then
            if ! cmp -s "$bk_fname" "$fpath"; then
                echo "--- Diff (${DIFF_CMD}) ---"
                "$DIFF_CMD" "$bk_fname" "$fpath"
                echo "--------------------"
            else
                echo "Info: No effective changes made to file content."
            fi
        else
            echo "Info: No changes made (no backup created)."
        fi
        return 0
    else
        echo "Error during Hash Remove (code: $ret). Check backup: $bk_fname" 1>&2
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
            ansi_c_content+="\\n$line" # 줄 사이에 \n 추가
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
        ansi_c_content+='\n'         # 내용 끝에 \n 추가
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

old_sleepdot() {
    echo -n "sleepdot $1 "
    bashver=${BASH_VERSINFO[0]}
    ((bashver < 3)) && real1sec=1 || real1sec=1
    s=$(date +%s)
    c=1
    stopdot=0

    # Ctrl+C 누르면 stopdot=1 설정
    trap 'stopdot=1' INT

    [ -z "$1" ] && echo -n ">>> Quit -> [Anykey] "

    while [ -z "$x" ]; do
        [ "$stopdot" = 1 ] && echo && echo "Canceled" && break
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

    trap - INT # trap 해제
    echo
}

old_sleepdot() {
    echo -n "sleepdot $1 "
    bashver=${BASH_VERSINFO[0]}
    ((bashver < 3)) && real1sec=1 || real1sec=1
    s=$(date +%s)
    c=1
    [ -z "$1" ] && echo -n ">>> Quit -> [Anykey] "
    #time while [ -z "$x" ]; do
    while [ -z "$x" ]; do
        [ "$1" ] && sleep 1
        echo -n "."
        [ $((c % 5)) -eq 0 ] && echo -n " "
        [ $((c % 30)) -eq 0 ] && echo $c
        t=$(($(date +%s) - s))
        [ $((c % 300)) -eq 0 ] && echo
        c=$((c + 1))
        if [ "$1" ] && [ $t -ge $1 ]; then break; elif [ -z "$1" ]; then IFS=z read -t$real1sec -n1 x && break; fi
    done
    echo
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
    select f in "$@" "Cancel"; do
        [ "$f" = "Cancel" ] && break
        [ -n "$f" ] && [ -f "$f" ] && vi2 "$f" || echo "'$f' not found"
        break
    done
}
vi2() {
    [ ! -f "$1" ] && echo "Canceled..." && return 1
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

webloga() { logview /var/log/apache2/access.log; }
weblogaf() { logview /var/log/apache2/access.log f; }
webloge() { logview /var/log/apache2/error.log; }
weblogef() { logview /var/log/apache2/error.log f; }
weblogff() { $(declare -F | awk '{print $3}' | grep weblog | sort | pipemenu); }
ftplog() { logview /var/log/xferlog; }
ftplogf() { logview /var/log/xferlog f; }
maillog() { logview /var/log/mail.log; }
maillogf() { logview /var/log/mail.log f; }
syslog() { logview /var/log/syslog; }
syslogf() { logview /var/log/syslog f; }
authlog() { logview /var/log/auth.log; }
authlogf() { logview /var/log/auth.log f; }
dpkglog() { logview /var/log/dpkg.log; }
dpkglogf() { logview /var/log/dpkg.log f; }
kernlog() { logview /var/log/kern.log; }
kernlogf() { logview /var/log/kern.log f; }
bootlog() { dmesg | cpipe | less -RX; }

# journalctl
log() { journalctl -e; }
loge() { journalctl -rp warning; }
logu() { journalctl -r -u $(systemctl list-unit-files --type=service | grep enable | awk -F'.service' '{print $1}' | pipemenu); }
logf() {
    trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
    journalctl -f
    trap - SIGINT
}

# select function
logsff() { $(declare -F | awk '{print $3}' | grep log | grep -v dialog | sort | pipemenu); }
logsfff() { for i in $(declare -F | awk '{print $3}' | grep log | grep -v dialog | sort); do fff $i; done | cpipe | less -RX; }

# select & logview
weblogs() { log=$(find /var/log/apache2/ -type f ! -name '*.gz' -size +0 | pipemenu) && [ -f $log ] && logview $log; }
weblogsf() { log=$(find /var/log/apache2/ -type f ! -name '*.gz' -size +0 | pipemenu) && [ -f $log ] && logview $log f; }
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
ssp() { systemctl status $(systemctl | grep -o 'php[0-9.]*-fpm' | sort -Vr | head -n1); }                          # 최신 PHP-FPM
ssf() { systemctl status $(systemctl list-unit-files --type=service | grep ftp | awk -F'.service' '{print $1}'); } # ftp
# Proxmox 관련 (사용 중이라면)
ssv() { systemctl status $(echo pvedaemon pveproxy qmeventd lxc | pipemenu); }

# euc-kr -> utf-8 file encoding
utt() { if ! file -i "$1" | grep -qi utf-8; then
    rbackup $1 || cp -a $1 $1.bak
    iconv -f euc-kr -t utf-8//IGNORE "$1" >"$1.temp" && cat "$1.temp" >"$1" && rm -f "$1.temp"
fi; }

# update
update() {
    rbackup "$gofile" "$envorg"
    echo "update file: $gofile $envorg" && sleep 1 && [ -f "$gofile" ] && wget -q -T 3 http://byus.net/go.sh -O "$gofile" && chmod 700 "$gofile" && [ -f "$envorg" ] && wget -q -T 3 http://byus.net/go.env -O "$envorg" && chmod 600 "$envorg" && savescut && exec "$gofile" "$scut"
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
old_ipallow() {
    valid_ips=true
    for ip in "$@"; do ipcheck ${ip%/*} && iptables -D INPUT -s ${ip%/*} -j DROP || {
        valid_ips=false
        break
    }; done
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
encrypt() {
    # 인수중 마지막 인자 -> key ex) encrypt hello world mykey or echo "hello world" | encrypt mykey
    [ "$1" ] && local k="${!#}"
    [ ! "$k" ] && k="${ENC_KEY:-$HOSTNAME}" #echo "k: $k"
    IFS='' read -d '' -t1 message
    [ "$2" ] && message="$message $(echo "${*:1:$(($# - 1))}" | tr '\n' ' ')"
    #echo "msg: $message"
    echo -n "$message" | openssl enc -des-ede3-cbc -pass pass:$k 2>/dev/null | perl -MMIME::Base64 -ne 'print encode_base64($_);'
}
decrypt() {
    [ "$1" ] && local k="${!#}"
    [ ! "$k" ] && k="${ENC_KEY:-$HOSTNAME}" #echo "k: $k";
    IFS='' read -d '' -t1 encrypted_message
    [ "$2" ] && encrypted_message="$encrypted_message $(echo "${*:1:$(($# - 1))}")"
    echo -n "$encrypted_message" | perl -MMIME::Base64 -ne 'print decode_base64($_);' | openssl enc -des-ede3-cbc -pass pass:$k -d 2>/dev/null
}

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

# proxmox vmid vnname ip print
vmipscan() {
    local IFS=$' \t\n'
    local iface
    [ "$1" ] && iface="$1" || iface="vmbr0"

    declare -A mac_ip_map
    while read -r ip mac; do
        mac_ip_map["$(echo "$mac" | tr '[:upper:]' '[:lower:]')"]="$ip"
    done < <(arp-scan -I $iface -l | awk '/^[0-9]/ {print $1, $2}')

    for node in $(pvesh get /nodes --noborder --noheader | awk '{print $1}'); do
        for vmid in $(pvesh get /nodes/$node/qemu --noborder --noheader | awk '/running/ {print $2}'); do
            config=$(pvesh get /nodes/$node/qemu/"$vmid"/config --noborder --noheader)
            vmname=$(echo "$config" | awk '$1 == "name" {print $2}')
            mac=$(echo "$config" | awk '$1 ~ /net0/ {print $2}' | grep -oP '(?<==)[0-9A-Fa-f:]+(?=,bridge=)')
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
            awk -v dev="$iface" '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[ \t]+([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ {
            print "ip neigh replace "$1" lladdr "$2" dev "dev
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
    type=$(grep -q qemu <<<"$conf" && echo qemu || echo lxc)
    path="/nodes/$node/$type/$vmid"

    case "$action" in
    # Basic VM control actions
    start | stop | shutdown | reboot | reset | suspend | resume)
        OUTPUT="$(pvesh create "$path/status/$action" 2>&1)"
        echo "$OUTPUT"
        if echo "$OUTPUT" | grep -qE "device is already attached|Duplicate ID|vfio.*error|QEMU exited with code 1" && [ "$action" = "start" ]; then
            echo "VM $VMID failed to start. Stopping VM..."
            vm $VMID stop
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
            echo "No lock present on VM $VMID."
        elif echo "$OUTPUT" | grep -qi "permission denied"; then
            echo "Failed to unlock VM $VMID: Permission denied."
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
        lvs --noheadings --units g -o lv_name,lv_size,data_percent | awk -v id="vm-"$VMID '$2 != "0.00g" && $1 ~ "^"id && NF==3 {u=$2*$3/100; printf "%s: %s / %.2fG / %s%%\n", $1, $2, u, $3}'
        ;;

    ip | ipcheck | "")
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
        storage=$(pvesh get /storage -output-format=json | jq -r --arg node "$(basename "$(readlink /etc/pve/local)")" '.[] | select( (.nodes == $node) and (.type == "dir") and (.content|contains("backup"))) | .storage')
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
            [ -f "$sh" ] || curl -m1 http://byus.net/explorer.sh -o "$sh" && chmod 755 "$sh"
            "$sh" "$1"
        fi
    }

    [ $# -eq 1 ] && open "$1" && return

    select f in "$@" "Cancel"; do
        [ "$f" = "Cancel" ] && break
        [ -n "$f" ] && open "$f" && break
    done
}

old_explorer() {

    command -v ranger &>/dev/null && {
        ranger "$1"
        return
    }
    explorer="$HOME/explorer.sh"
    [ -f "$explorer" ] && "$explorer" "$1" || { curl -m1 http://byus.net/explorer.sh -o "$explorer" && chmod 755 "$explorer" && "$explorer" "$1"; }
}
exp() { explorer "$@"; }

pingcheck() { ping -c1 168.126.63.1 &>/dev/null && echo "y" || echo "n"; }
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
        exit 1
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

# 각열의 필드길이를 제한 w|maxl 5 5 5 5 // 한줄폭을 넘어가는 데이터가 많을경우, 적당히 컷 필요없는 필드는 0으로 설정
maxl() {
    local args=("$@")
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
    [ ! "$(which ifconfig 2>/dev/null)" ] && "ifconfig command not found!" && exit

    # Get all ethernet interfaces
    INTERFACES=$(ifconfig -a | grep HWaddr | awk '{print $1}')
    [ ! "$INTERFACES" ] && INTERFACES="$(ip link show | awk -F ': ' '/^[0-9]+:/ {gsub(/:$/, "", $2); if ($2 != "lo") print $2}')"

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

        # Get ifconfig output for this interface
        OUTPUT=$(ifconfig $INTERFACE)

        # Extract necessary information
        HWADDR=$(echo "$OUTPUT" | grep -oi -E 'HWaddr [0-9a-f:]{17}' | cut -d ' ' -f 2)
        [ ! "$HWADDR" ] && HWADDR=$(echo "$OUTPUT" | grep -oi -E 'ether [0-9a-f:]{17}' | cut -d ' ' -f 2)
        IPADDR=$(echo "$OUTPUT" | grep -oi -E 'inet addr:[0-9\.]+' | cut -d ':' -f 2)
        [ ! "$IPADDR" ] && IPADDR=$(echo "$OUTPUT" | grep -oi -E 'inet [0-9\.]+' | cut -d ' ' -f 2)
        GATEWAY="${IPADDR%.*}.1"

        # If IP address is not set, ask for it and set netmask and broadcast address to typical values
        read -p "Enter the IP address for $INTERFACE (or type dhcp, default: $IPADDR): " INPUT_IPADDR

        if [ -z "$INPUT_IPADDR" ]; then
            INPUT_IPADDR=$IPADDR
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
    local homedir oldconf newconf userinfo tmp

    # 인수 확인
    if [ -z "$id" ] || [ -z "$olddomain" ] || [ -z "$newdomain" ]; then
        echo "❌ 사용법: domchg <id> <old-domain> <new-domain>"
        echo "예시: domchg myuser oldsite.com newsite.com"
        return 1
    fi

    # 기본 경로 설정
    homedir="$(getent passwd "$id" | cut -d: -f6)"
    [ -z "$homedir" ] && echo "❌ 사용자 $id의 홈디렉토리를 찾을 수 없습니다." && return 1

    oldconf="/etc/httpd/conf.d/$olddomain.conf"
    newconf="/etc/httpd/conf.d/$newdomain.conf"
    userinfo="$homedir/.userinfo"

    ### 1. Apache conf 변경
    if [ -f "$oldconf" ]; then
        tmp="$(mktemp)"
        sed "s/$olddomain/$newdomain/g" "$oldconf" >"$tmp"

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
    echo "--- Certbot SSL 재발급 명령 미리보기 ---"
    echo "certbot --apache -d $newdomain -d www.$newdomain"
    readxy "[Certbot을 실행할까요?]" && {
        certbot --apache -d "$newdomain" -d "www.$newdomain"
    }

    ### 4. wp-config.php 내 URL 변경
    local wpconfig="$homedir/public_html/wp-config.php"
    if [ -f "$wpconfig" ]; then
        tmp="$(mktemp)"
        sed "s|http://$olddomain|http://$newdomain|g" "$wpconfig" >"$tmp"
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
            sed -i "s/$olddomain/$newdomain/g" "/etc/httpd/conf.d/${newdomain}_redirect.conf"
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

old_template_edit() { conff $1; }
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

ExecStart=/usr/local/bin/teldrive run \
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

ExecStart=/usr/local/bin/teldrive run \
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

    hook.sh)
        cat >"$file_path" <<EOF
#!/bin/bash
echo "[HOOK] 인증용 TXT 레코드 추가 중"
export mydomain="\$CERTBOT_DOMAIN"
export txt_value="\$CERTBOT_VALIDATION"
export zone_file="$zone_file"
export txt_record="_acme-challenge.${mydomain}. IN TXT \"\$txt_value\""

echo "\$txt_record" >> "\$zone_file"
rndc reload "$mydomain"
EOF

        ;;

    hookremote.sh)
        cat >"$file_path" <<EOF
# 사용자가 사전에 export 해야 하는 값들:
#mydomain="example.com"
#remote_ns_host="byus.net"
#zone_file="/mnt/byus/var/named/${mydomain}.zone"

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
exit 0
EOF

        ;;

    cleanup.sh)
        cat >"$file_path" <<EOF
#!/bin/bash

echo "[CLEANUP] 인증용 TXT 레코드 제거 중..."

export mydomain="\$CERTBOT_DOMAIN"
export txt_value="\$CERTBOT_VALIDATION"
export zone_file="$zone_file"
export txt_record="_acme-challenge.${mydomain}. IN TXT \"\$txt_value\""

# 레코드 제거 (해당 줄 삭제)
sed -i "/_acme-challenge.*IN TXT.*\$txt_value/d" "\$zone_file"

# BIND 설정 재적용
rndc reload "$mydomain"

echo "[CLEANUP] 완료: $txt_record 삭제됨"
EOF

        ;;

    renew.sh)
        cat >"$file_path" <<EOF
#!/bin/bash

export CERTBOT_DOMAIN="$mydomain"
export CERTBOT_EMAIL="$myemail"

certbot renew \
  --manual-auth-hook "/etc/letsencrypt/scripts/hook-${mydomain}.sh" \
  --manual-cleanup-hook "/etc/letsencrypt/scripts/cleanup-${mydomain}.sh" \
  --preferred-challenges dns \
  --agree-tos \
  --manual \
  --deploy-hook "systemctl reload apache2" \
  --cert-name $certpath
EOF

        ;;

    hook-sslwr.sh)
        cat >"$file_path" <<EOF
#!/bin/bash
# Certbot DNS-01 인증용 hook for $yourdoamin
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
   sed -e "/_acme-challenge\.\${CERTBOT_DOMAIN//./\\.}\.(\s+[0-9]+)?\s\+IN\s\+TXT/d" \
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
   sed -e "/_acme-challenge\.\${CERTBOT_DOMAIN//./\\.}\.(\s+[0-9]+)?\s\+IN\s\+TXT/d" \
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
