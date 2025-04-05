#!/bin/bash
# bash2 하위 호환성 유지 (redhat7/oops1)
#
#debug="y"

echo
who am i && sleep 1

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

# envtmp="$base/.go.env"
# envtmp 파일을 메모리에 상주 cat 부하 감소
shm_env_file="/dev/shm/.go.env"
fallback_env_file="$base/.go.env"
if rm -f "$shm_env_file" 2>/dev/null; then
    envtmp="$shm_env_file"
else
    envtmp="$fallback_env_file"
fi
env="$envtmp"

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
[ -f ~/.go.private.var ] && source ~/.go.private.var

# 터미널 자동감지
# 터미널 utf8 환경이고 go.env 가 euckr 인경우 -> utf8 로 인코딩
if [ "$(echo $LANG | grep -i "utf")" ] && [ ! "$(file "$envorg" | grep -i "utf")" ]; then
    cat "$envorg" | iconv -f euc-kr -t utf-8//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$env"
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

# cmd 라인뒤 주석제거 // 빈줄은 그대로 // 공백이 들어간 빈줄은 삭제
#sed -i 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' "$env"
sed -i -e 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' -e '/^[[:blank:]]\+$/d' "$env"

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

# exported flow get
scut=${scut-}
oldscut=${oldscut-}
ooldscut=${ooldscut-}
oooldscut=${oooldscut-}
ooooldscut=${ooooldscut-}

############################################################
# 최종 명령문을 실행하는 함수 process_commands // execf
############################################################
process_commands() {
    local command="$1"
    local cfm=$2
    local nodone=$3

    [[ ${command:0:1} == "#" ]] && return # 주석선택시 취소

    if [ "$cfm" == "y" ] || [ "$cfm" == "Y" ] || [ -z "$cfm" ]; then # !!! check
        echo && echo "=============================================="
        # 탈출 ctrlc 만 가능한 경우 -> trap ctrlc 감지시 menu return
        if echo "$command" | grep -Eq 'tail -f|journalctl -f|ping|vmstat|logs -f|top|docker logs'; then
            (
                trap 'stty sane' SIGINT
                # pipemenu 로 들어오는 값은 eval 이 실행되면서 선택이 되어 취소가 불가능하다.
                # Cancel 같은 특수값을 select 에 추가하여 반회피 한다
                # pipemenu 는 파일 리스트 등에 한정하여 쓴다
                readxx $LINENO "> command: $command"
                eval "$command"
            )
            trap - SIGINT
        else
            readxx $LINENO ">> command: $command"
            #command=$(command)
            eval "$command"
        fi
        # log
        lastarg=""
        lastarg="$(echo "$command" | awk99 | sed 's/"//g')" # 마지막 인수 재사용시 "제거 (ex.fileurl)
        echo "$command" >>"$gotmp"/go_history.txt 2>/dev/null
        # post
        [ "${command%% *}" = "cd" ] && echo "pwd: $(pwd) ... ls -ltr | tail -n5 " && ls -ltr | tail -n5
        echo "=============================================="
        # unset var_value var_name
        unset -v var_value var_name
        echo && [ ! "$nodone" ] && echo -n "--> " && YEL && echo "$command" && RST
        [ "$pipeitem" ] && echo "selected: $pipeitem"
        # sleep 1 or [Enter]
        if [[ $command == vi* ]] || [[ $command == explorer* ]] || [[ $command == ": nodone"* ]]; then nodone=y && sleep 1; fi
        [ ! "$nodone" ] && { echo -en "--> \033[1;34mDone...\033[0m [Enter] " && read -r x; }
    else
        echo "$command"
        echo "Canceled..."
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
    # 초기 메뉴는 인수없음, 인수 있을경우 서브 메뉴진입
    # $1 $2 가 동시에 인수로 들어와야 작동
    # $1 $2 $3 가 들어오면 $3(명령줄) 종속 메뉴로 바로 이동
    readxx $LINENO menufunc input_value_input1:"$1" input2:"$2"
    local chosen_command_sub="$1"     # ex) {submenu_lamp} or {}
    local title_of_menu_sub="$2"      # ex) debian lamp set flow
    [ -n "$3" ] && local initvar="$3" # ex) 2 or scut
    #[ "$1" == "{}" ] && local initvar="" # choice 가 불필요한경우 relaymenu mainmenu
    local choiceloop=0
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
        cmd_choice=""

        if [ "$initvar" ]; then
            # 최초 실행시 특정 메뉴 shortcut 가져옴 ex) bash go.sh px
            choice="$initvar" && initvar=""
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
        [ "$scut" ] && [ "$scut" != "m" ] && [ "$scut" != "$oldscut" ] && {
            ooooldscut="$oooldscut"
            oooldscut="$ooldscut"
            ooldscut="$oldscut"
            oldscut="$scut"
        }
        [ "$ooldscut" ] && flow="$oooldscut>$ooldscut>$scut" || { [ "$scut" ] && flow="m>$scut" || flow=""; }

        # 메인메뉴에서 서브 메뉴의 shortcut 도 사용할수 있도록 기능개선
        # 쇼트컷 배열생성
        if [ ${#shortcutarr[@]} -eq 0 ]; then

            readxx $LINENO shortcutarr.count.0: "${#shortcutarr[@]} 값없음체크"
            # 모든 shortcut 배열로 가져옴 shortcutarr array
            # 연계메뉴의 불러올 하부메뉴 포함되도록 개선 awk
            # IFS=$'\n' allof_shortcut_item="$(cat "$env" | grep "%%% " | grep -E '\[.+\]')"
            # i@@@%%% 시스템 초기설정과 기타 [i] -----> i@@@%%% 시스템 초기설정과 기타 [i]@@@{submenu_sys}
            # shortcut 있는 항목만 배열화
            IFS=$'\n' allof_shortcut_item="$(cat "$env" | grep -E "^%%%|^\{submenu.*" | awk '/^%%%/ {if (prev) print prev; prev = $0; next} /^{submenu_/ {print prev "@@@" $0; prev = ""; next} {if (prev) print prev; print $0; prev = ""} END {if (prev) print prev}' | grep -E '\[.+\]')"

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

        # choice 가 없을때 선택 메뉴 출력

        ############## 메뉴 출력 ###############

        [ -z "$debug" ] && [ -z "$noclear" ] && {
            clear || reset
            unset noclear
        }
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
                RST
            )"
            # offline print
            if [ "$offline" == "offline" ]; then
                echo -ne "==="
                RED1
                echo -ne " offline "
                RST
                echo "=================================="
            else
                echo "=============================================="
            fi
        else

            # %% cmds -> pre_commands 검출및 실행 (submenu 일때만)
            # listof_comm_submain
            # pre excute
            for items in "${pre_commands[@]}"; do
                eval "${items#%% }" | sed 's/^[[:space:]]*/  /g'
            done > >(
                output=$(cat)
                [ -n "$output" ] && { [ "$(echo "$output" | grep -E '0m')" ] && {
                    echo "$output"
                    echo "=============================================="
                } || {
                    CYN
                    echo "$output"
                    RST
                    echo "=============================================="
                }; }
            )
        fi

        local items
        menu_idx=0
        shortcut_idx=0
        declare -a keysarr
        declare -a idx_mapping

        # 메인 or 서브 메뉴 리스트 구성 loop
        while read line; do
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
            items=$(echo -e "$(echo "$items" | sed -e 's/^>/\o033[1;31m>\o033[0m/g')")

            printf "\e[1m%-3s\e[0m ${items}\n" ${menu_idx}.
        done < <(print_menulist) # %%% 모음 가져와서 파싱

        echo "0.  Exit [q] // Hangul_Crash ??? --> [kr] "
        echo "=============================================="

        ############## 메뉴 출력 끝 ###############
        [[ $chosen_command_sub == "{}" ]] && [[ "$cmd_choice_scut" ]] && choice="$cmd_choice_scut" && cmd_choice_scut=""
        #readxx $LINENO read "choice menu pre_choice:" $choice
        if [[ -z $choice ]]; then
            # readchoice read choice
            trap 'saveVAR;stty sane;exit' SIGINT SIGTERM EXIT # 트랩 설정
            history -r
            IFS=' ' read -rep ">>> Select No. ([0-${menu_idx}],[ShortCut],h,e,sh): " choice choice1 </dev/tty
            [[ $? -eq 1 ]] && choice="q" # ctrl d 로 빠져나가는 경우
            trap - SIGINT SIGTERM EXIT   # 트랩 해제 (이후에는 기본 동작)
        fi

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
        if [ "$choice" ] && { ! echo "$choice" | grep -Eq '^[1-9][0-9]*$' || echo "$choice" | grep -Eq '^[a-zA-Z]+$'; }; then
            #readxx $LINENO you choice? yes $choice
            # subshortcut 을 참조하여 title_of_menu 설정
            # ex) chosen_command:{submenu_systemsetup} // title_of_menu:시스템 초기설정과 기타 (submenu) [i]
            for item in "${shortcutarr[@]}"; do
                # echo $item
                if [ "$choice" == "${item%%@@@*}" ]; then
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
        # 0 ~ 98 까지 메뉴 지원 // 99 특수기능 ex) shortcut,conf,kr,q // cf) 100~9999 특수기능(timer)
        # if [ -n "$choice" ] && { case "$choice" in [0-9] | [1-9][0-9]) true ;; *) false ;; esac } && { [ "$choice" -ge 1 ] && [ "$choice" -le "$menu_idx" ] || [ "$choice" -eq 99 ]; }; then
        # if (echo "$choice" | grep -Eq '^[1-9]$|^[1-9][0-9]$') && [ "$choice" -ge 1 ] && [ "$choice" -le "$menu_idx" ] || [ "$choice" -eq 99 ] 2>/dev/null; then
        if ((choice >= 1 && choice <= 99 && choice <= menu_idx || choice == 99)) 2>/dev/null; then

            readxx $LINENO choice99 choice: $choice
            # 선택한 줄번호의 타이틀 가져옴
            [ ! "$choice" == 99 ] && title_of_menu="$(print_menulist | awk -v choice="$choice" 'NR==choice {print}')"

            ###############################################################
            # 선택한 줄번호의 타이틀에 맞는 리스트가져옴
            ###############################################################
            listof_comm() {
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
                #readxx $LINENO title_of_menu: $title_of_menu sub_menu: $sub_menu
                # %%% 부터 빈줄까지 변수에
                IFS=$'\n' allof_chosen_commands="$(cat "$env" | awk -v title_of_menu="%%% ${sub_menu}${title_of_menu}" 'BEGIN {gsub(/[\(\)\[\]]/, "\\\\&", title_of_menu)} !flag && $0 ~ title_of_menu{flag=1; next} /^$/{flag=0} flag')"
                # 제목배고 선명령 빼고 순서 명령문들 배열
                IFS=$'\n' chosen_commands=($(echo "${allof_chosen_commands}" | grep -v "^%% "))
                # 선명령 모듬 배열
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
                    if [ $num_commands -eq 1 ]; then
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
                            [ "$scut" ] && [ "$scut" != "m" ] && [ "$scut" != "$oldscut" ] && {
                                ooooldscut="$oooldscut"
                                oooldscut="$ooldscut"
                                ooldscut="$oldscut"
                                oldscut="$scut"
                            }
                            [ "$ooldscut" ] && flow="$oooldscut>$ooldscut>$scut" || { [ "$scut" ] && flow="m>$scut" || flow=""; }

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
                                        echo "=============================================="
                                    } || {
                                        CYN
                                        echo "$output"
                                        RST
                                        echo "=============================================="
                                    }
                                    sleep 0.1
                                }
                            )

                            display_idx=1
                            unset original_indices
                            original_indices=()

                            # 순수 명령줄 한줄씩 처리 - 색칠/경로/변수처리
                            for item in $(seq 1 ${#chosen_commands[@]}); do

                                c_cmd="${chosen_commands[$((item - 1))]}"

                                # 명령구문에서 파일경로 추출 /dev /proc 제외한 일반경로 // 주석문 제외
                                #file_paths="$(echo "$c_cmd" | awk '{for (i = 1; i <= NF; i++) {if(!match($i, /^.*https?:\/\//) && match($i, /\/[^\/]+\/[^ $|]*[a-zA-Z0-9]+[-_.]*[a-zA-Z0-9]/)) {filepath = substr($i, RSTART, RLENGTH); if ((filepath !~ /^\/dev\//) && (filepath !~ /var[A-Z][a-zA-Z0-9_.-]*/) && (filepath !~ /^\/proc\//)) {print filepath, "\n"}}}}')"
                                file_paths="$(echo "$c_cmd" | awk '/^[[:space:]]*#/{next} {for (i = 1; i <= NF; i++) {if(!match($i, /^.*https?:\/\//) && match($i, /\/[^\/]+\/[^ $|]*[a-zA-Z0-9]+[-_.]*[a-zA-Z0-9]/)) {filepath = substr($i, RSTART, RLENGTH); if ((filepath !~ /^\/dev\//) && (filepath !~ /var[A-Z][a-zA-Z0-9_.-]*/) && (filepath !~ /^\/proc\//)) {print filepath}}}}')"

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
                                printf "\e[1m%-3s\e[0m " ${pi}
                                #echo "$c_cmd" | fold -sw 120 | sed -e '2,$s/^/    /' `# 첫 번째 줄 제외 각 라인 들여쓰기` \
                                echo "$processed_cmd" | cut -c 1-350 | fold -sw 120 | sed -e '2,$s/^/    /' `# 첫 번째 줄 제외 각 라인 들여쓰기` \
                                    -e 's/@space@/_/g' `# 변수에 @space@ 를 쓸경우 공백으로 변환; 눈에는 _ 로 표시 ` \
                                    -e 's/@dot@/./g' `# 변수에 @dot@ 를 쓸경우 공백으로 변환; 눈에는 _ 로 표시 ` \
                                    -e 's/@@@@\([^ ]*\)@@@@/\x1b[1;37m\1\x1b[0m/g' `# '@@@@' ! -fd file_path 밝은 흰색` \
                                    -e 's/@@@\([^ ]*\)@@@/\x1b[1;30m\1\x1b[0m/g' `# '@@@' ! -fd file_path 어두운 회색` \
                                    -e '/^#/! s/\(var[A-Z][a-zA-Z0-9_@-]*__[a-zA-Z0-9_@.-]*\|var[A-Z][a-zA-Z0-9_@-]*\)/\x1b[1;35m\1\x1b[0m/g' `# var 변수 자주색` \
                                    -e '/^#/! s/@@/\//g' `# 변수에 @@ 를 쓸경우 / 로 변환 ` \
                                    -e '/^#/! s/\(!!!\|eval\|export\)/\x1b[1;33m\1\x1b[0m/g' `# '!!!' 경고표시 진한 노란색` \
                                    -e '/^#/! s/\(status\|running\)/\x1b[33m\1\x1b[0m/g' `# status yellow` \
                                    -e '/^#/! s/\(template_copy\|template_view\|template_edit\|batcat \|cat \|hash_add\|hash_remove\|change\|insert\|explorer\|^: [^;]*\)/\x1b[1;34m&\x1b[0m/g' `# : abc ; 형태 파란색` \
                                    -e '/^#/! s/\(stopped\|stop\|stopall\|allstop\|disable\|disabled\)/\x1b[31m\1\x1b[0m/g' `# stop disable red` \
                                    -e '/^#/! s/\(restart\|reload\|autostart\|startall\|start\|enable\|enabled\)/\x1b[32m\1\x1b[0m/g' `# start enable green` \
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
                                    trap 'saveVAR;stty sane;exit' SIGINT SIGTERM EXIT # 트랩 설정
                                    history -r
                                    IFS=' ' read -rep ">>> Select No. ([0-$((display_idx - 1))],h,e,sh,conf): " cmd_choice cmd_choice1 </dev/tty
                                    [[ $? -eq 1 ]] && cmd_choice="q" # ctrl d 로 빠져나가는 경우
                                    #trap - SIGINT SIGTERM EXIT       # 트랩 해제 (이후에는 기본 동작)
                                    [[ -n $cmd_choice ]] && break
                                done
                            else
                                # pre_command refresh
                                trap 'saveVAR;stty sane;exit' SIGINT SIGTERM EXIT # 트랩 설정
                                history -r
                                IFS=' ' read -rep ">>> Select No. ([0-$((display_idx - 1))],h,e,sh,conf): " cmd_choice cmd_choice1 </dev/tty
                                [[ $? -eq 1 ]] && cmd_choice="q" # ctrl d 로 빠져나가는 경우
                                trap - SIGINT SIGTERM EXIT       # 트랩 해제 (이후에는 기본 동작)
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
                        echo "error : num_commands -> $num_commands // sub_menu: $sub_menu // debug: find -> chosen_commands="
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
                                    var_name="var${var#var}"

                                    # 변수조정 varVAR.conf -> varVAR ( 변수이름에 점사용 쩨한 ) varVAR.conf -> varVAR 이 변수
                                    if [[ $var_name != *__* ]]; then var_name="${var_name%%.*}"; fi
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
                                        dvar_value="${var_name#*__}" && dvar_value="${dvar_value//@dot@/.}" && dvar_value="${dvar_value//@space@/ }" && dvar_value="${dvar_value//@@/\/}"
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
                                                    PS3="==============================================
>>> Prev.selected value: $(tput bold)$(tput setaf 5)$(tput setab 0)${!org_var_name//\\/}$(tput sgr0)
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
                                                    fi
                                                    if [ "$num" -le "${#dvar_value_array[@]}" ]; then
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
                                            [ "$(echo "${var_name%%__*}" | grep -i path)" ] && GRN1 && echo "pwd: $(pwd)" && RST
                                            # 이전에 선택했던 값이 있으면 함께 출력
                                            if [ -n "${!org_var_name}" ]; then
                                                printf "==============================================
>>> Prev.selected value: $(tput bold)$(tput setaf 5)$(tput setab 0)${!org_var_name//\\/}$(tput sgr0)
!!(Cancel:c) Enter value for \e[1;35;40m[${var_name%%__*} Default:$dvar_value] \e[0m:"
                                            else
                                                printf "==============================================
!!(Cancel:c) Enter value for \e[1;35;40m[${var_name%%__*} Default:$dvar_value] \e[0m:"
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
                                            else
                                                trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
                                                printf "!!(Cancel:c) Enter value for \e[1;35;40m[${var_name} env Default:$dvar_value] \e[0m: "
                                                readv var_value </dev/tty
                                                trap - INT
                                                [ "$var_value" == "c" ] && var_value="Cancel"
                                                eval flagof_"${var_name%%__*}"=set
                                                #eval flagof_"${org_var_name}"=set
                                            fi

                                        else
                                            trap 'stty sane ; savescut && exec "$gofile" "$scut"' INT
                                            [ "$(echo "${var_name}" | grep -i path)" ] && GRN1 && echo "pwd: $(pwd)" && RST
                                            printf "Enter value for \e[1;35;40m[$var_name]\e[0m: "
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
                                    # echo "var_namme: //$var_name// var_valuue: //$var_value//" && read x < /dev/tty

                                    #cmd=${cmd//$var_name/$var_value} -> 경로등 특수문자 변환 문제
                                    #cmd=$(echo "$cmd" | sed "s|\b$var_name\b|$escaped_value|g") -> varA_ -> varA 인식못함

                                    #escaped_value=$(printf '%s\n' "$var_value" | sed 's/[&/\]/\\&/g')
                                    #cmd=$(echo "$cmd" | sed "s|\b$var_name\b|$escaped_value|g")
                                    #
                                    # 1. var_name을 sed 정규식 패턴에 안전하게 사용하도록 이스케이프 (동일)
                                    regex_safe_var_name=$(printf '%s' "$var_name" | sed 's/[.^$*\[\]\\]/\\&/g')

                                    # 2. var_value를 sed 치환 문자열에 안전하게 사용하도록 이스케이프 (구분자 # 포함 - 동일)
                                    escaped_value=$(printf '%s' "$var_value" | sed -e 's/\\/\\\\/g' -e 's/&/\\&/g' -e 's/#/\\#/g')

                                    # 3. 캡처 그룹을 사용하여 cmd 업데이트 (Lookaround 대신)
                                    #    (^|[^a-zA-Z0-9]): 시작(^) 이거나 영숫자가 아닌 문자(그룹 1)
                                    #    ([^a-zA-Z0-9]|$): 영숫자가 아닌 문자 이거나 끝($)(그룹 2)
                                    #    치환 시 \1$escaped_value\2 로 원래 경계 문자를 다시 넣어줌
                                    #cmd=$(printf '%s' "$cmd" | sed -E "s#(^|[^a-zA-Z0-9])$regex_safe_var_name([^a-zA-Z0-9]|$)#\1$escaped_value\2#g")
                                    #cmd=$(printf '%s' "$cmd" | sed -E "s:(^|[^a-zA-Z0-9])$regex_safe_var_name([^a-zA-Z0-9]|$):\1$escaped_value\2:g")
                                    cmd=$(printf '%s' "$cmd" | sed -e "s:\(^\|[^a-zA-Z0-9]\)$regex_safe_var_name\([^a-zA-Z0-9]\|$\):\1$escaped_value\2:g")

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

                        # 명령줄이 하나일때 실행 loop 종료하고 상위 메뉴 이동
                        [ $num_commands -eq 1 ] && break

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
                    [[ -n $cmd_choice && ($cmd_choice == "0" || ${cmd_choice#0} != "$cmd_choice" || ${cmd_choice//[0-9]/}) ]] &&
                        {
                            YEL1
                            echo
                            echo "check your cmd_choice: $cmd_choice"
                            RST
                        } &&
                        case "$cmd_choice" in
                        # --- Basic Navigation & Commands ---
                        "0" | "q" | ".")
                            if [ "$choice" == "99" ]; then
                                # scut 으로 들어온 경우, 상위메뉴타이틀 찾기
                                title_of_menu_sub="$(grep -B1 "^${chosen_command_sub}" "$env" | head -n1 | sed -e 's/^%%% //g' -e 's/.*}//')"
                                readxx $LINENO "env: $env title_of_menu_sub:$title_of_menu_sub SHLVL:$SHLVL "
                            fi
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
                            ;; # exec terminates the script here
                            #                        "bm")
                            #                            echo "Back to previous menu.. [$ooldscut]" && sleep 0.5 && savescut && exec "$gofile" "$ooldscut"
                            #                            ;; # exec terminates
                            #                        "bbm")
                            #                            echo "Back two menus.. [$oooldscut]" && sleep 0.5 && savescut && exec "$gofile" "$oooldscut"
                            #                            ;; # exec terminates
                            #                        "bbbm")
                            #                            echo "Back three menus.. [$ooooldscut]" && sleep 0.5 && savescut && exec "$gofile" "$ooooldscut"
                            #                            ;; # exec terminates
                        "b")
                            echo "Back to previous menu.. [$ooldscut]" && sleep 0.5 && savescut &&
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
                        "<")
                            beforescut=$(st $scut b)
                            echo "Move to Before menu.. [$beforescut]" && sleep 0.5 && savescut && menufunc "$(scutsub "$beforescut")" "$(scuttitle "$beforescut")" "$(notscutrelay "$beforescut")"
                            ;;
                        ">")
                            nextscut=$(st $scut n)
                            echo "Move to Next menu.. [$nextscut]" && sleep 0.5 && savescut && menufunc "$(scutsub "$nextscut")" "$(scuttitle "$nextscut")" "$(notscutrelay "$nextscut")"
                            ;;
                        "chat" | "ai" | "hi" | "hello")
                            ollama run gemma3 2>/dev/null && continue
                            ;;
                        "conf")
                            conf && continue
                            ;;
                        "confmy")
                            confmy && continue
                            ;;
                        "confc")
                            confc && continue
                            ;;
                        "conff")
                            conff && continue
                            ;;
                        "conffc")
                            conffc && continue
                            ;;
                        "h")
                            gohistory && continue
                            ;;
                        "hh")
                            hh && read -rep "[Enter] " x && continue
                            ;;
                        "e")
                            { ranger "$cmd_choice1" 2>/dev/null || explorer "$cmd_choice1"; } && continue
                            ;;
                        "df")
                            if [[ ! $cmd_choice1 ]]; then
                                { /bin/df -h | grep -vE '^/dev/loop|/var/lib/docker' | sed -e "s/파일 시스템/파일시스템/g" | cgrep1 /mnt/ | cper | column -t; } && readx && continue
                            else
                                /bin/df $cmd_choice1 && readx && continue
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
                        "ee")
                            { ranger /etc 2>/dev/null || explorer /etc; } && continue
                            ;;
                        "ll")
                            { journalctl -n10000 -e; } && continue
                            ;;

                        # --- Default block for complex checks and fallback ---
                        *)
                            # Check 1: Shortcut menu jump? (Requires $cmd_choice1 empty & match in $shortcutstr)
                            if [[ -z $cmd_choice1 ]] && echo "$shortcutstr" | grep -q "@@@$cmd_choice|"; then
                                readxx $LINENO cmd_choice:"$cmd_choice" shortcut_moving
                                cmd_choice_scut=$cmd_choice
                                #savescut && exec "$gofile" "$cmd_choice" # exec terminates
                                menufunc "$(scutsub "$cmd_choice")" "$(scuttitle "$cmd_choice")" "$(notscutrelay "$cmd_choice")"

                            # Check 2: Alarm? (Numeric, starts with 0, not just "0")
                            elif [[ ! ${cmd_choice//[0-9]/} ]] && [[ ${cmd_choice:0:1} == "0" ]] && [[ $cmd_choice != "0" ]]; then
                                echo "alarm set -> $cmd_choice $cmd_choice1" && sleep 1
                                alarm "$cmd_choice" "$cmd_choice1" && {
                                    echo
                                    readx
                                    continue
                                }

                            # Check 3: Valid Linux command? (Not purely numeric and exists)
                            elif [[ "${cmd_choice//[0-9]/}" ]] && command -v "$cmd_choice" &>/dev/null; then
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
                                RST
                                # Execute in a subshell: Source .bashrc (to get all alias definitions, ignoring errors), enable alias expansion, then execute the original alias name ($cmd_choice, passed as $0) with arguments ($cmd_choice1 etc., passed via $@).
                                # This allows nested aliases like 'alias ll="ls -l"' and 'alias myll="ll -h"' to work correctly.
                                # WARNING: Sourcing .bashrc might fail silently or have side effects if it has strict interactive guards ([ -z "$PS1" ] && return).
                                trap 'stty sane' SIGINT
                                bash -c 'source ~/.bashrc 2>/dev/null; shopt -s expand_aliases; eval -- "$0" "$@"' "$cmd_choice" ${cmd_choice1:+"$cmd_choice1"}
                                #eval "$cmd_choice" "$cmd_choice1"
                                trap - INT
                                GRN1
                                dline
                                RST

                                # Clean up the temporary variable

                                # Optional: Log execution
                                echo "$cmd_choice $cmd_choice1 # (cmd_choice via .bashrc alias)" >>"$gotmp"/go_history.txt 2>/dev/null
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
            conf)
                conf # vi.go.env
                ;;
            confmy)
                confmy # vi.go.my.env
                ;;
            confc)
                confc # rollback go.env
                ;;
            conff)
                [ "$choice1" ] && conff "$choice1" || conff # vi go.sh
                ;;
            conffc)
                conffc # rollback go.sh
                ;;
                #            bm)
                #                echo "Back to previous menu.. [$ooldscut]" && sleep 0.5
                #                savescut && exec $gofile $ooldscut # back to previous menu
                #                ;;
                #            bbm)
                #                echo "Back two menus.. [$oooldscut]" && sleep 0.5
                #                savescut && exec $gofile $oooldscut # back to previous menu
                #                ;;
                #            bbbm)
                #                echo "Back three menus.. [$ooooldscut]" && sleep 0.5
                #                savescut && exec $gofile $ooooldscut # back to previous menu
                #                ;;
            b)
                echo "Back to previous menu.. [$ooldscut]" && sleep 0.5
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
                    /bin/df -h | grep -vE '^/dev/loop|/var/lib/docker' | sed -e "s/파일 시스템/파일시스템/g" | cgrep1 /mnt/ | cper | column -t && readx
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
            e)
                { ranger $choice1 2>/dev/null || explorer; }
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
            ee)
                { ranger /etc 2>/dev/null || explorer /etc; }
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
            0[0-9]*)
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
                    RST
                    # Execute in a subshell: Source .bashrc (to get all alias definitions, ignoring errors), enable alias expansion, then execute the original alias name ($cmd_choice, passed as $0) with arguments ($cmd_choice1 etc., passed via $@).
                    # This allows nested aliases like 'alias ll="ls -l"' and 'alias myll="ll -h"' to work correctly.
                    # WARNING: Sourcing .bashrc might fail silently or have side effects if it has strict interactive guards ([ -z "$PS1" ] && return).
                    trap 'stty sane' SIGINT
                    bash -c 'source ~/.bashrc 2>/dev/null; shopt -s expand_aliases; eval -- "$0" "$@"' "$choice" ${choice1:+"$choice1"}
                    #eval "$choice" "$choice1"
                    trap - INT
                    GRN1
                    dline
                    RST

                    echo "$choice $choice1 # (choice via .bashrc alias)" >>"$gotmp"/go_history.txt 2>/dev/null
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
ff() { declare -f "$@"; }

# colored ip (1 line multi ip apply)
cip() { awk -W interactive '{line=$0;while(match(line,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)){IP=substr(line,RSTART,RLENGTH);line=substr(line,RSTART+RLENGTH);if(!(IP in FC)){BN[IP]=1;if(TC<6){FC[IP]=36-TC;}else{do{FC[IP]=37-(TC-6)%7;BC[IP]=40+(TC-6)%8;TC++;}while(FC[IP]==BC[IP]-10);if(FC[IP]<31)FC[IP]=37;}TC++;}if(TC>6&&BC[IP]>0){CP=sprintf("\033[%d;%d;%dm%s\033[0m",BN[IP],FC[IP],BC[IP],IP);}else{CP=sprintf("\033[%d;%dm%s\033[0m",BN[IP],FC[IP],IP);}gsub(IP,CP,$0);}print}' 2>/dev/null ||
    awk '{line=$0;while(match(line,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)){IP=substr(line,RSTART,RLENGTH);line=substr(line,RSTART+RLENGTH);if(!(IP in FC)){BN[IP]=1;if(TC<6){FC[IP]=36-TC;}else{do{FC[IP]=37-(TC-6)%7;BC[IP]=40+(TC-6)%8;TC++;}while(FC[IP]==BC[IP]-10);if(FC[IP]<31)FC[IP]=37;}TC++;}if(TC>6&&BC[IP]>0){CP=sprintf("\033[%d;%d;%dm%s\033[0m",BN[IP],FC[IP],BC[IP],IP);}else{CP=sprintf("\033[%d;%dm%s\033[0m",BN[IP],FC[IP],IP);}gsub(IP,CP,$0);}print}'; }

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
    awk -v pat="^.*${pattern}.*$" '{gsub(pat, "\033[1;33m&\033[0m"); print $0;}'
}
# 검색문자열줄을 색칠 (red)
cgrepline1() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat="^.*${pattern}.*$" '{gsub(pat, "\033[1;31m&\033[0m"); print $0;}'
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
    local num_cols="${@:-1}"          # 마지막 인수를 색칠 범위로 사용
    local search_strs=("${@:1:$#-1}") # 나머지는 검색어 목록

    # 색칠 범위 기본값 설정 (숫자가 아니면 기본값 0)
    if echo "$num_cols" | grep -qE '^-?[0-9]+$'; then
        : # num_cols 값이 유효한 숫자일 때 유지
    else
        num_cols=0
    fi

    perl -pe "
        BEGIN {
            \$color_red = \"\e[1;31m\";  # 빨간색
            \$color_reset = \"\e[0m\";   # 색상 초기화
            @search_words = qw(${search_strs[*]});
            \$num = $num_cols;
            if (\$num < 0) { \$before = -\$num; \$after = 0; }  # 음수: 앞쪽 강조
            elsif (\$num > 0) { \$before = 0; \$after = \$num; }  # 양수: 뒤쪽 강조
            else { \$before = 0; \$after = 0; }  # 0이면 해당 단어만
        }
        foreach my \$search (@search_words) {
            s/((\\S+\\s+){0,\$before}\$search(\\s+\\S+){0,\$after})/\$color_red\$1\$color_reset/g;
        }
    "
}

# 줄긋기 draw line
dline() {
    num_characters="${1:-50}"
    delimiter="${2:-=}"
    printf "%.0s$delimiter" $(seq "$num_characters")
    printf "\n"
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
    R='\033[1;31m'
    Y='\033[1;33m'
    N='\033[0m'
    diff -u "$old" "$new" | while IFS= read -r l; do case "$l" in "-"*) printf "${R}${l}${N}\n" ;; "+"*) printf "${Y}${l}${N}\n" ;; *) printf "${l}\n" ;; esac done
}

# .vim/backup 의 최신 백업파일과 현재 파일의 차이를 보여줌
fdiff() {
    local backup_dir="$HOME/.vim/backup"

    if [[ -z $1 ]]; then
        echo "Usage: fdiff <filename>"
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
    ls -al $gofile $envorg
}
gdifff() {
    d="$(cdiff $base/go.env.1.bak $base/go.env)"
    [ -n "$d" ] && echo "$d" || cdiff $base/go.env.2.bak $base/go.env
    ls -al $gofile $envorg
}
# vi diff
godiff() {
    fdiff $gofile
    ls -al $gofile $envorg
}
goodiff() {
    fdiff $envorg
    ls -al $gofile $envorg
}

# colored dir
cdir() { awk '{match_str="(/[a-zA-Z0-9][^ ()|$]+)"; gsub(match_str, "\033[36m&\033[0m"); print $0; }'; }

# cpipe -> courl && cip24 && cdir
cpipe() { awk -W interactive '{gsub("https?:\\/\\/[^ ]+", "\033[1;36;04m&\033[0m"); gsub(" /[a-z0-9A-Z][^ ()|$]+", "\033[36m&\033[0m"); line=$0; while (match(line, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {IP=substr(line, RSTART, RLENGTH); line=substr(line, RSTART+RLENGTH); Prefix=IP; sub(/\.[0-9]+$/, "", Prefix); if (!(Prefix in FC)) {BN[Prefix]=1; if (TC<6) {FC[Prefix]=36-TC;} else { do {FC[Prefix]=30+(TC-6)%8; BC[Prefix]=(40+(TC-6))%48; TC++;} while (FC[Prefix]==BC[Prefix]-10); if (FC[Prefix]==37) {FC[Prefix]--;}} TC++;} if (BC[Prefix]>0) {CP=sprintf("\033[%d;%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], BC[Prefix], IP);} else {CP=sprintf("\033[%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], IP);} gsub(IP, CP, $0);} print;}' 2>/dev/null ||
    awk '{gsub("https?:\\/\\/[^ ]+", "\033[1;36;04m&\033[0m"); gsub(" /[a-z0-9A-Z][^ ()|$]+", "\033[36m&\033[0m"); line=$0; while (match(line, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {IP=substr(line, RSTART, RLENGTH); line=substr(line, RSTART+RLENGTH); Prefix=IP; sub(/\.[0-9]+$/, "", Prefix); if (!(Prefix in FC)) {BN[Prefix]=1; if (TC<6) {FC[Prefix]=36-TC;} else { do {FC[Prefix]=30+(TC-6)%8; BC[Prefix]=(40+(TC-6))%48; TC++;} while (FC[Prefix]==BC[Prefix]-10); if (FC[Prefix]==37) {FC[Prefix]--;}} TC++;} if (BC[Prefix]>0) {CP=sprintf("\033[%d;%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], BC[Prefix], IP);} else {CP=sprintf("\033[%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], IP);} gsub(IP, CP, $0);} print;}'; }

# cpipef() { sed -E "s/([0-9]{1,3}\.){3}[0-9]{1,3}/\x1B[1;33m&\x1B[0m/g;  s/(https?:\/\/[^ ]+)/\x1B[1;36;04m&\x1B[0m/g" ; }
cpipef() { sed "s/\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}/\x1B[1;33m&\x1B[0m/g;  s/\(https\?\:\/\/[^ ]\+\)/\x1B[1;36;04m&\x1B[0m/g"; }

# color_alternate_lines
stripe() { awk '{printf (NR % 2 == 0) ? "\033[37m" : "\033[36m"; print $0 "\033[0m"}'; }

# ansi ex) RED ; echo "haha" ; BLU ; echo "hoho" ; RST
RED() { echo -en "\033[31m"; }
GRN() { echo -en "\033[32m"; }
YEL() { echo -en "\033[33m"; }
BLU() { echo -en "\033[34m"; }
MAG() { echo -en "\033[35m"; }
CYN() { echo -en "\033[36m"; }
WHT() { echo -en "\033[37m"; }
RST() { echo -en "\033[0m"; }

# 밝은색
RED1() { echo -en "\033[1;31m"; }
GRN1() { echo -en "\033[1;32m"; }
YEL1() { echo -en "\033[1;33m"; }
BLU1() { echo -en "\033[1;34m"; }
MAG1() { echo -en "\033[1;35m"; }
CYN1() { echo -en "\033[1;36m"; }
WHT1() { echo -en "\033[1;37m"; }
YBLU() { echo -en "\033[1;33;44m"; }
YRED() { echo -en "\033[1;33;41m"; }

# noansi
noansised() { sed 's/\\033\[[0-9;]*[MKHJm]//g'; }
noansi() { perl -p -e 's/\e\[[0-9;]*[MKHJm]//g' 2>/dev/null; } # Escape 문자(ASCII 27) 를 모두 동일하게 인식 \033, \x1b, 및 \e 모두 처리가능

# selectmenu
selectmenu() { select item in $@; do echo $item; done; }

# pipe 로 넘어온 줄의 모든 필드를 select 구분자-> 빈칸 빈줄 파이프(|}
#pipemenu() {
#    local prompt_message="$@"
#    PS3="==============================================
#>>> ${prompt_message:+"$prompt_message - "}Select No. : "
#    IFS=$' \n|'
#    export pipeitem=""
#    items=$(while read -r line; do awk '{print $0}' < <(echo "$line"); done)
#    { [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && export pipeitem="$item" && break; done </dev/tty; }
#    unset IFS
#    unset PS3
#}
pipemenu() {
    local prompt_message="$@"
    PS3="==============================================
>>> ${prompt_message:+"$prompt_message - "}Select No. : "
    IFS=$' \n|'
    items=$(
        while read -r line; do awk '{print $0}' < <(echo "$line"); done
        echo "Cancel"
    )

    [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && export pipeitem="$item" && break; done </dev/tty
    unset IFS
    unset PS3
}
pipemenucancel() { pipemenu; }

# pipe 로 넘어온 줄의 첫번째 필드를 select
#pipemenu1() {
#    local prompt_message="$@"
#    PS3="==============================================
#>>> ${prompt_message:+"$prompt_message - "}Select No. : "
#    export pipeitem=""
#    items=$(while read -r line; do awk '{print $1}' < <(echo "$line"); done)
#    { [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && export pipeitem="$item" && break; done </dev/tty; }
#    unset PS3
#}
pipemenu1() {
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
pipemenu1cancel() { pipemenu1; }

# pipe 로 넘어온 라인별로 select
pipemenulist() {
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
scutall() {
    scut=$1
    scut_item_idx=$(echo "$shortcutstr" | sed -n "s/.*@@@$scut|\([0-9]*\)@@@.*/\1/p") # 배열번호 0~99 찾기
    scut_item="$([ -n "$scut_item_idx" ] && echo "${shortcutarr[$scut_item_idx]}")"   # 배열번호에 있는 값 추출
    echo "$scut_item"
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

# blkid -> fstab ex) blkid2fstab /dev/sdd1 /tmp
blkid2fstab() {
    d=${2/\/\///}
    [ ! -d "$d" ] && echo "mkdir $d"
    fstabadd="$(printf "# UUID=%s\t%s\t%s\tdefaults,nosuid,noexec,noatime\t0 0\n" "$(blkid -o value -s UUID "$1")" "$d" "$(blkid -o value -s TYPE "$1")")"
    echo "$fstabadd" >>/etc/fstab
}

# 명령어 사용가능여부 체크 acmd curl -m1 -o
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
    ((bashver < 3)) && IFS="" read -rep $'\n>>> : ' $1 || IFS="" read -rep '' $1
}

# bashcomm .bashrc 의 alias 사용가능 // history 사용가능
bashcomm() {
    echo
    local original_aliases
    original_aliases=$(shopt -p expand_aliases)
    shopt -s expand_aliases
    source ${HOME}/.bashrc
    unalias q 2>/dev/null
    HISTFILE="$gotmp/go_history.txt"
    history -r "$HISTFILE"
    while :; do
        CYN
        pwdv=$(pwd)
        echo "pwd: $([ -L $pwdv ] && ls -al $pwdv | awk '{print $(NF-2),$(NF-1),$NF}' || echo $pwdv)"
        RST
        IFS="" read -rep 'BaSH_Command_[q] > ' cmd
        if [[ $cmd == "q" || -z $cmd ]]; then eval "$original_aliases" && break; else {
            history -s "$cmd"
            eval "process_commands \"$cmd\" y nodone"
            history -a "$HISTFILE"
        }; fi
    done
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

# shortcut view n> b<
st() {
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
    st
    echo
    printarr shortcutarr | cgrep1 @@@ | less -r
}

# flow save and exec go.sh
savescut() {
    export scut=$scut oldscut=$oldscut ooldscut=$ooldscut oooldscut=$oooldscut ooooldscut=$ooooldscut
}

# varVAR 형태의 변수를 파일에 저장해 두었다가 스크립트 재실행시 사용
viewVAR() { declare -p | grep "^declare -x var[A-Z]"; }
saveVAR() {
    declare -p | grep "^declare -x var[A-Z]" >>~/.go.private.var
    chmod 600 ~/.go.private.var
    awk '!seen[$0]++' ~/.go.private.var >~/.go.private.var.tmp && mv ~/.go.private.var.tmp ~/.go.private.var
}
loadVAR() {
    [ -f ~/.go.private.var ] && tail -n10 ~/.go.private.var && source ~/.go.private.var
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
    shfmt -i 4 -s -w $gofile
}
newtemp() {
    echo "template_edit $1
template_view $1
!!! template_copy $1 $2 ;; cat "\$lastarg"
"
}
# vi2 envorg && restart go.sh
conf() {
    vi2 "$envorg" $scut
    savescut && exec "$gofile" "$scut"
}
confmy() {
    vi2 "$envorg2" $scut
    savescut && exec "$gofile" "$scut"
}
conff() {
    [ $1 ] && vi22 "$gofile" "$1" || vi22 "$gofile"
    savescut && exec "$gofile" "$scut"
}
confc() { rollback "$envorg"; }
conffc() { rollback "$gofile"; }

# confp # env 환경변수로 불러와 스크립트가 실행되는 동안 변수로 쓸수 있음
confp() { vi2a $HOME/go.private.env; }

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
        curl -m1 -ks -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" -d chat_id=${telegram_chatid} -d text="${message:-ex) push "msg"}" >/dev/null
        result=$?
        #curl -m1 -ks -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" -d chat_id=${telegram_chatid} -d text="${message:-ex) push "msg"}" ; result=$?
        [ "$result" == 0 ] && { GRN1 && echo "push msg sent"; } || { RED1 && echo "Err:$result ->  push send error"; }
        RST
    fi
    # 기본적으로 인자 출력
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
    current_serial=$(grep -Eo '[0-9]{10}' "$zonefile")

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

    # 시리얼을 업데이트
    sed -i "s/$current_serial/$new_serial/" "$zonefile"

    echo "업데이트 완료: $zonefile (새 시리얼: $new_serial)"
}

isdomain() { echo "$1" | grep -E '^(www\.)?([a-z0-9]+(-[a-z0-9]+)*\.)+(com|net|kr|co.kr|org|io|info|xyz|app|dev)(\.[a-z]{2,})?$' >/dev/null && return 0 || return 1; }

urlencode() { od -t x1 -A n | tr " " %; }
urldecode() { echo -en "$(sed 's/+/ /g; s/%/\\x/g')"; }

alarm() {
    # 인수로 넘어올때 "$1" "$2" // $2에 read 나머지 모두
    # 인수로 넘어올때 "$1" "$2" "$3" ... // 두가지 형태 존재

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
        RST
        ps -ef | grep "[a]larm_task" | awknf8 | cgrep "alarm_task_$input" | grep -v "awk"
    fi
    if [[ ${input:0:4} == "0000" ]]; then
        [ ! "${input:4:2}" ] && input="$input$(echo "$telegram_msg" | awk1)" && telegram_msg="$(echo "$telegram_msg" | awknf2)" # && echo "input: $input // msg: $telegram_msg"
        local time_in_hours="${input:4:2}"
        local time_in_minutes="${input:6:2}"
        local days="${input:8:2}"
        [ -z "$days" ] && days=0
        telegram_msg="${time_in_hours}:${time_in_minutes}-Alarm ${telegram_msg}"
        echo ": alarm_task_$input && curl -m1 -ks -X POST \"https://api.telegram.org/bot${telegram_token}/sendMessage\" -d chat_id=${telegram_chatid} -d text=\"${telegram_msg}\"" | at "$time_in_hours":"$time_in_minutes" "$( ((days > 0)) && echo "today + $days" days)" &>/dev/null

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

        echo ": alarm_task_$input && sleep $wait_seconds && curl -m1 -ks -X POST 'https://api.telegram.org/bot${telegram_token}/sendMessage' -d chat_id=${telegram_chatid} -d text='${telegram_msg}'" | at now + "$adjusted_minutes" minutes &>/dev/null

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
        sleepdot $time_in_seconds && curl -m1 -ks -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" -d chat_id=${telegram_chatid} -d text="${telegram_msg}" &>/dev/null

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

qssh() {
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

# 함수 이름: change
# 사용법: change <파일경로> <찾을_문자열> <바꿀_문자열> <line:검색라인교체시>
# 설명:
#   핵심 기능만 수행: Perl -i로 백업 및 치환, diff로 비교.
#   구분자 '|||' 사용. 문자열 내 특수문자 처리는 최소화됨 (백슬래시만 처리).

change() {
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

hash_add() {
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

hash_remove() {
    # --- Arguments & Basic Validation ---
    local fpath="$1" search="$2" num_arg="$3"
    # Default: Uncomment 1 line (the matched one)
    local num_lines=1
    local bk_suffix ts bk_fname ret perl_p quoted_s DIFF_CMD="cdiff" # Assume cdiff exists

    # Validate number of arguments
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
        echo "Usage: hash_remove <filepath> <search> [total_lines]" >&2
        echo "  - uncomments matched line if it starts with '# ' and contains <search>." >&2
        echo "  - if total_lines >= 1, attempts to uncomment that many lines total," >&2
        echo "    starting with the matched one. Only removes leading '# ' if present." >&2
        return 1
    fi

    # Validate optional total_lines argument
    if [ $# -eq 3 ]; then
        # Must be an integer >= 1
        if ! echo "$num_arg" | grep -Eq '^[1-9][0-9]*$'; then
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
    # $c: counter for lines remaining to process *after* the matched line.
    # $ENV{P}: Quoted search Pattern (expected content *after* '# ').
    # $ENV{N}: Total number of lines to attempt uncommenting.
    # On match, set counter c to N-1 (remaining lines).
    perl_p='
        BEGIN { $c = 0 }
        # Check if line starts with optional space(s) + "# " AND contains the pattern P afterwards
        if (m/^\s*# .*?\Q$ENV{P}\E/) {
             # Remove the leading "# " prefix (preserving leading whitespace)
             s/^(\s*)# /$1/;
             # Set counter for remaining lines to process
             $c = $ENV{N} - 1;
        } elsif ($c-- > 0) {
             # For subsequent lines, remove leading "# " only IF present
             s/^(\s*)# /$1/ if m/^\s*# /;
        }
        print;
    '
    # One-liner version:
    # perl_p='BEGIN{$c=0} if(m/^\s*# .*?\Q$ENV{P}\E/){s/^(\s*)# /$1/; $c=$ENV{N}-1} elsif($c-->0){s/^(\s*)# /$1/ if m/^\s*# /} print'

    # --- Execution ---
    export P="$quoted_s" N="$num_lines" # Pass total lines N
    perl "-i${bk_suffix}" -n -e "$perl_p" "$fpath"
    ret=$?
    unset P N # Clean up environment

    # --- Reporting ---
    if [ $ret -eq 0 ]; then
        echo "Hash Remove potentially done. Backup: $bk_fname"
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
        echo "Error during Hash Remove (code: $ret). Check backup: $bk_fname" >&2
        return $ret
    fi
}

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
            RST
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
unsetvar varl

# wait enter
readx() { read -p "[Enter] " x </dev/tty; }
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
    if [ -n "$2" ]; then vim -c "autocmd VimEnter * silent! execute '/$2'" "$1"; else vim "$1" || vi "$1"; fi
}
vi2() {
    [ ! -f "$1" ] && echo "Canceled..." && return 1

    rbackup "$1"
    # 문자열 찾고 그 위치에서 편집
    #if [ -n "$2" ]; then vim -c "autocmd VimEnter * silent! execute '/^%%% .*\[$2\]'" "$1"; else vim "$1" || vi "$1"; fi
    # 문자열 찾고 그 위치의 문단끝에서 편집
    if [ -n "$2" ]; then vim -c "autocmd VimEnter * silent! execute '/^%%% .*\[$2\]' | silent! normal! }'" "$1"; else vim "$1" || vi "$1"; fi

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
weblog() { lynx --dump --width=260 http://localhost/server-status; }

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
ipban() {
    valid_ips=true
    for ip in "$@"; do ipcheck ${ip%/*} && iptables -A INPUT -s ${ip%/*} -j DROP || {
        valid_ips=false
        break
    }; done
    $valid_ips && iptables -L -v -n | tail -n20 | gip | cip
}
ipban24() {
    valid_ips=true
    for ip in "$@"; do ipcheck ${ip%/*} && iptables -A INPUT -s ${ip%/*}/24 -j DROP || {
        valid_ips=false
        break
    }; done
    $valid_ips && iptables -L -v -n | tail -n20 | gip | cip
}
ipban16() {
    valid_ips=true
    for ip in "$@"; do ipcheck ${ip%/*} && iptables -A INPUT -s ${ip%/*}/16 -j DROP || {
        valid_ips=false
        break
    }; done
    $valid_ips && iptables -L -v -n | tail -n20 | gip | cip
}
ipallow() {
    valid_ips=true
    for ip in "$@"; do ipcheck ${ip%/*} && iptables -D INPUT -s ${ip%/*} -j DROP || {
        valid_ips=false
        break
    }; done
    $valid_ips && iptables -L -v -n | tail -n20 | gip | cip
}
ipallow24() {
    valid_ips=true
    for ip in "$@"; do ipcheck ${ip%/*} && iptables -D INPUT -s ${ip%/*}/24 -j DROP || {
        valid_ips=false
        break
    }; done
    $valid_ips && iptables -L -v -n | tail -n20 | gip | cip
}
ipallow16() {
    valid_ips=true
    for ip in "$@"; do ipcheck ${ip%/*} && iptables -D INPUT -s ${ip%/*}/16 -j DROP || {
        valid_ips=false
        break
    }; done
    $valid_ips && iptables -L -v -n | tail -n20 | gip | cip
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

#dfmonitor() {
#    DF_INITIAL=$(df -m | grep -vE "udev|none|efi|fuse|tmpfs")
#    DF_BEFORE=$DF_INITIAL
#    while true; do
#        clear
#        echo -e "System Uptime:\n--------------"
#        uptime
#        echo -e "\nRunning processes (e.g., pv, cp, tar, zst, rsync, dd, mv):\n----------------------------------------------------------\n\033[36m"
#        ps -ef | grep -E "\<(pv|cp|tar|zst|rsync|dd|mv)\>" | grep -v grep
#        echo -e "\033[0m\nInitial df -m output:\n---------------------\n$DF_INITIAL"
#        echo -e "\033[0m\nPrevious df -m output:\n-----------------------\n$DF_BEFORE\n"
#        DF_AFTER=$(df -m | grep -vE "udev|none|efi|fuse|Available|tmpfs")
#        DIFF=$(diff --unchanged-group-format='' --changed-group-format='%>' <(echo "$DF_BEFORE") <(echo "$DF_AFTER"))
#        echo -e "New df -m output with changes highlighted:\n------------------------------------------"
#        echo "${DF_AFTER}" | while IFS= read -r line; do if [[ ${DIFF} == *"$line"* ]] && [ ! -z "$DIFF" ]; then echo -e "\033[1;33;41m$line\033[0m"; else echo "$line"; fi; done
#        echo -e "\033[0m"
#        DF_BEFORE=$DF_AFTER
#        echo -n ">>> Quit -> [Anykey] "
#        for i in $(seq 1 4); do read -p"." -t1 -n1 x && break; done
#        [ "$x" ] && break
#        echo
#    done
#}
dfmonitor() {
    DF_INITIAL=$(df -m | grep -vE "udev|none|efi|fuse|tmpfs|Available|overlay|/snap/")
    DF_BEFORE=$DF_INITIAL
    while true; do
        clear
        echo -e "System Uptime:\n--------------"
        uptime
        echo -e "\nRunning processes (e.g., pv, cp, tar, zst, rsync, dd, mv):\n----------------------------------------------------------\n\033[36m"
        ps -ef | grep -E "\<(pv|cp|tar|zst|rsync|dd|mv)\>" | grep -v grep
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
    # MAC-IP 매핑
    local IFS=$' \t\n'
    local iface
    [ "$1" ] && iface="$1" || iface="vmbr0"
    declare -A mac_ip_map
    while read -r ip mac; do
        mac_ip_map["$(echo "$mac" | tr '[:upper:]' '[:lower:]')"]="$ip"
    done < <(arp-scan -I $iface -l | awk '/^[0-9]/ {print $1, $2}')

    # VM 정보 출력
    for vmid in $(pvesh get /nodes/localhost/qemu --noborder --noheader | awk '/running/ {print $2}'); do
        config=$(pvesh get /nodes/localhost/qemu/"$vmid"/config --noborder --noheader)
        vmname=$(echo "$config" | awk '$1 == "name" {print $2}')
        mac=$(echo "$config" | awk '$1 ~ /net0/ {print $2}' | grep -oP '(?<==)[0-9A-Fa-f:]+(?=,bridge=)')
        [[ -n $mac ]] && ip="${mac_ip_map[$(echo "$mac" | tr '[:upper:]' '[:lower:]')]}" && [[ -n $ip ]] && echo "-> $vmid $vmname $ip"
    done
}

# explorer.sh
explorer() {
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
    ping -c3 $gateway
}
pp() { pingtest "$@"; }
ppa() { pingtesta "$@"; }
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
            which ifreload && sudo ifreload -a || sudo systemctl restart networking.service

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

##############################################################################################################
##############################################################################################################
############## template copy/view func
##############################################################################################################
##############################################################################################################

template_edit() { conff $1; }
template_view() { template_copy $1 /dev/stdout; }

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

    xxnpm.yml)
        cat >"$file_path" <<'EOF'
version: '3'
services:
  proxy:
    image: nginx:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf

  web:
    image: nginx:latest
    restart: always
    volumes:
      - ./source:/source
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot

  php:
    image: php:7.4-fpm
    expose:
      - "9000"
    volumes:
      - ./source:/source

  db:
    image: mariadb:latest
    volumes:
      - ./mysql:/var/lib/mysql
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=gosh

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

    xxnginx.conf)
        cat >"$file_path" <<'EOF'
user  nginx;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout  65;
    include /etc/nginx/conf.d/*.conf;
}

EOF
        ;;

    xxnginx.web.conf)
        cat >"$file_path" <<'EOF'

  server {
    listen 80 ;
    server_name example.com www.example.com;

   location /.well-known/acme-challenge/ {
      root     /var/www/certbot;
      allow all;
     }

   location / {
      return     301 https://$host$request_uri;
    }
  }

  server {
    listen 443 ssl;
    server_name example.com www.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    root /source;

    location ~ \.php$ {
      fastcgi_pass php:9000;
      fastcgi_index index.php;
      include fastcgi_params;
      fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

    error_log /var/log/nginx/api_error.log;
    access_log /var/log/nginx/api_access.log;
  }

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
        cat >"$file_path" <<'EOF'
<VirtualHost *:80>
    ServerName example.com
    ServerAlias www.example.com
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/example.com_error.log
    CustomLog ${APACHE_LOG_DIR}/example.com_access.log combined
</VirtualHost>
EOF
        ;;

    php_db_con_test.php)
        cat >"$file_path" <<'EOF'
<?php
ini_set('display_errors', 1); // 화면에 오류 표시 켜기
ini_set('display_startup_errors', 1); // 시작 오류도 표시 켜기
error_reporting(E_ALL); // 모든 종류의 오류 보고

// --- !!! 중요: 실제 데이터베이스 정보로 변경하세요 !!! ---
$servername = "localhost";    // 또는 127.0.0.1
$username = "your_db_user";   // 권한 부여한 데이터베이스 사용자 이름
$password = "your_db_password"; // 해당 사용자의 비밀번호
$dbname = "your_db_name";     // 연결할 데이터베이스 이름
// ---------------------------------------------------------

$tableName = "php_test_table_" . time(); // 고유한 임시 테이블 이름 생성

echo "<h1>PHP-데이터베이스 연동 테스트 (테이블 생성/삭제)</h1>";
echo "<hr>";

// 1. 데이터베이스 연결 시도
echo "<h2>1. 데이터베이스 연결 시도</h2>";
$conn = mysqli_connect($servername, $username, $password, $dbname);

// 연결 확인
if (!$conn) {
    echo "<p style='color:red;'><strong>데이터베이스 연결 실패:</strong> " . mysqli_connect_error() . "</p>";
    echo "<p>스크립트를 종료합니다.</p>";
    exit; // 연결 실패 시 종료
}
echo "<p style='color:green;'><strong>데이터베이스 연결 성공!</strong></p>";
echo "<hr>";

// 2. 테스트 테이블 생성 시도
echo "<h2>2. 테스트 테이블 생성 시도</h2>";
echo "<p>테이블 이름: " . htmlspecialchars($tableName) . "</p>";

$sql_create = "CREATE TABLE " . $tableName . " (
    id INT AUTO_INCREMENT PRIMARY KEY,
    test_message VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)";

if (mysqli_query($conn, $sql_create)) {
    echo "<p style='color:green;'><strong>테이블 '" . htmlspecialchars($tableName) . "' 생성 성공!</strong></p>";
} else {
    echo "<p style='color:red;'><strong>테이블 생성 오류:</strong> " . mysqli_error($conn) . "</p>";
    echo "<p>스크립트를 종료합니다. (생성 실패 시 삭제 시도 안 함)</p>";
    mysqli_close($conn); // 연결 닫고 종료
    exit;
}
echo "<hr>";

// 3. 생성된 테이블 확인 (선택 사항, 하지만 좋은 테스트)
echo "<h2>3. 생성된 테이블 확인</h2>";
$sql_check = "SHOW TABLES LIKE '" . $tableName . "'";
$result_check = mysqli_query($conn, $sql_check);

if ($result_check && mysqli_num_rows($result_check) > 0) {
    echo "<p style='color:blue;'>테이블 '" . htmlspecialchars($tableName) . "' 존재 확인됨.</p>";
    mysqli_free_result($result_check); // 결과 집합 해제
} else {
    // 생성 직후인데 확인이 안 되면 문제가 있을 수 있음
    echo "<p style='color:orange;'><strong>경고:</strong> 테이블 '" . htmlspecialchars($tableName) . "' 존재 확인 실패 (또는 결과 없음). 계속 진행합니다.</p>";
    if (!$result_check) {
        echo "<p style='color:orange;'>SHOW TABLES 쿼리 오류: " . mysqli_error($conn) . "</p>";
    }
}
echo "<hr>";

// 4. 테스트 테이블 삭제 시도
echo "<h2>4. 테스트 테이블 삭제 시도</h2>";
$sql_drop = "DROP TABLE " . $tableName;

if (mysqli_query($conn, $sql_drop)) {
    echo "<p style='color:green;'><strong>테이블 '" . htmlspecialchars($tableName) . "' 삭제 성공!</strong></p>";
} else {
    echo "<p style='color:red;'><strong>테이블 삭제 오류:</strong> " . mysqli_error($conn) . "</p>";
    // 삭제 실패는 심각할 수 있으므로 경고 강조
}
echo "<hr>";

// 5. 데이터베이스 연결 닫기
echo "<h2>5. 데이터베이스 연결 닫기</h2>";
mysqli_close($conn);
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
$TTL    604800 ; 기본 TTL (Time To Live) 값 (단위: 초, 예: 1주일)
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
;ns2     IN      A       YOUR_2ND_NAME_SERVER_IP        ; na2.namedomain.com 의 IP 주소

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
    DocumentRoot $roundcubepath/roundcube

    <Directory $roundcubepath/roundcube/>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        # PHP 설정 (필요시)
        # php_value memory_limit 64M
        # php_value upload_max_filesize 10M
        # php_value post_max_size 12M
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/roundcube_error.log
    CustomLog ${APACHE_LOG_DIR}/roundcube_access.log combined
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
