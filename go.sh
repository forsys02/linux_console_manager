#!/bin/bash
# bash2 하위 호환성 유지 (redhat7/oops1)

# 존재 하는 파일의 절대경로 출력 readlink -f
readlinkf() {
    p="$1"
    while [ -L "$p" ]; do
        lt="$(readlink "$p")"
        if [[ $lt == /* ]]; then p="$lt"; else p="$(dirname "$p")/$lt"; fi
    done
    echo "$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)/$(basename "$p")"
}
realpathf() { while [ $# -gt 0 ]; do
    echo "$1" | sed -e 's/\/\.\//\//g' | awk -F'/' -v OFS="/" 'BEGIN{printf "/";}{top=1; for (i=2; i<=NF; i++) {if ($i == "..") {top--; delete stack[top];} else if ($i != "") {stack[top]=$i; top++;}} for (i=1; i<top; i++) {printf "%s", stack[i]; printf OFS;}}{print ""}'
    shift
done; }

basefile="$(readlinkf "$0")"
base="$(dirname "$basefile")"

gofile="$base/go.sh"
envorg="$base/go.env"
envtmp="$base/.go.env"

# go.env 환경파일이 없을경우 다운로드
if [ ! -f "$envorg" ]; then
    echo "base: $base"
    chmod +x "$gofile"
    echo -n ">>> go.env config file not found. Download? [y/n]: " && read -r down </dev/tty
    [ "$down" = "y" ] || [ "$down" = "Y" ] && output_dir="$(
        cd "$(dirname "${0}")"
        pwd
    )" && (command -v curl >/dev/null 2>&1 && curl -m1 http://byus.net/go.env -o "${output_dir}/go.env" || wget -q -O "${output_dir}/go.env" -T 1 http://byus.net/go.env || exit 0)
fi

# /bin/gosh softlink
[ ! -L /bin/go ] && [ ! -L /bin/gosh ] && ln -s "$base"/go.sh /bin/gosh && echo -ne "$(ls -al /bin/gosh) \n>>> Soft link created for /bin/gosh. Press [Enter] " && read -r x </dev/tty

# 개인 환경변수 파일 불러오기 // 스크립트가 돌동안 사용이 가능하며 // env 에서 확인 가능
if [ -f "$HOME"/go.private.env ]; then
    chmod 600 "$HOME"/go.private.env
    while IFS= read -r line; do
        if echo "$line" | grep -q -E '^[a-zA-Z_]+(=\"[^\"]*\"|=[^[:space:]]*)$'; then
            export "$line"
        fi
    done <"$HOME"/go.private.env
fi

# 환경 파일(한글euc-kr) 주석 제거 // 한글 인코딩 변환
if [ "$envko" ]; then # 사용자 수동 설정 저장
    [ "$envko" == "utf8" ] && ! grep -q -i "utf" <"$envorg" && cat "$envorg" | iconv -f euc-kr -t utf-8//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$envtmp"
    env="$envtmp"
    [ "$envko" == "euckr" ] && ! grep -q -i "utf" <"$envorg" && cat "$envorg" | iconv -f utf-8 -t euc-kr//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$envtmp"
    env="$envtmp"
    [ "$envko" == "euckr" ] && ! grep -q -i "utf" <"$envorg" && cp -a "$envorg" "$envtmp"
    sed -i 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' "$envtmp"
    env="$envtmp"
else
    if [ "$(echo $LANG | grep -i "utf")" ] && [ ! "$(file $envorg | grep -i "utf")" ]; then
        cat "$envorg" | iconv -f euc-kr -t utf-8//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$envtmp"
        env="$envtmp"
    elif [ ! "$(echo $LANG | grep -i "utf")" ] && [ "$(file $envorg | grep -i "utf")" ]; then
        cat "$envorg" | iconv -f utf-8 -t euc-kr//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$envtmp"
        env="$envtmp"
    else
        cp -a "$envorg" "$envtmp"
        sed -i 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' "$envtmp"
        env="$envtmp"
    fi
fi
# not kr
if (($(locale | grep -ci "kr") == 0)); then
    sed -i -e '/^%%% /d' -e 's/^%%%e /%%% /g' $envtmp
else
    sed -i '/^%%%e /d' $envtmp
fi

# tmp 폴더 set
if touch /tmp/go_history.txt; then
    gotmp="/tmp"
else
    gotmp="$HOME/tmp"
    mkdir -p $gotmp
fi

#export publicip="$(curl -m1 -ks icanhazip.com 2>/dev/null || curl -m1 -ks checkip.amazonaws.com 2>/dev/null)"
publicip="$(wget -q -O - http://icanhazip.com 2>/dev/null || wget -q -O - http://checkip.amazonaws.com 2>/dev/null)"
export "publicip"
localip=$(ip -4 addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | tr '\n' ' ')
export "localip"
localip1=${localip%% *}
export "localip1"
guestip=$(who am i | awk -F'[():]' '{print $3}')
export "guestip"
gateway="$(ip route | grep 'default' | awk '{print $3}')"
export "gateway"
[ ! "localip" ] && localip=$(ip -4 addr show | awk '{while(match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {print substr($0, RSTART, RLENGTH) ; $0 = substr($0, RSTART+RLENGTH)}}' | grep -vE "127.0.0.1|255$" | tr '\n' ' ')

# 명령이 넘어오면 실행하는 함수
process_commands() {
    local command="$1"
    local cfm=$2
    local nodone=$3
    [ "${command:0:1}" == "#" ] && return # 주석선택시 취소
    if [ "$cfm" == "y" ] || [ "$cfm" == "Y" ] || [ -z "$cfm" ]; then
        [ "${command%% *}" != "cd" ] && echo && echo "=============================================="
        eval "$command"
        echo "$command" >>$gotmp/go_history.txt 2>/dev/null && chmod 600 $gotmp/go_history.txt 2>/dev/null || chown root.root $gotmp/go_history.txt 2>/dev/null
        [ "${command%% *}" != "cd" ] && echo "=============================================="
        unset var_value var_name
        echo && [ ! "$nodone" ] && echo -n "--> " && GRN1 && echo "$command" && RST
        [ "$pipeitem" ] && echo "selected: $pipeitem"
        if [[ $command == vi* ]] || [[ $command == explorer* ]] || [[ $command == ": nodone"* ]]; then nodone=y && sleep 1; fi
        [ ! "$nodone" ] && { echo -en "--> \033[1;34mDone...\033[0m [Enter] " && read -r x; }
    else
        echo "Canceled..."
    fi
}

# 환경파일에서 %%% 로 시작하는 메뉴 가져옴
search_menulist() {
    if [ -z "$chosen_command_sub" ]; then
        # mainmenu list
        cat "$env" | grep -E '^%%%' | grep -vE '\{submenu' | sed -r 's/%%% //'
    else
        # submenu list
        cat "$env" | grep -E '^%%%' | grep "$chosen_command_sub" | awk -F'}' '{print $2}'
    fi
}

# 메인 서비스 함수
menufunc() {
    # 초기 메뉴는 인수없음, 인수 있을경우 서브 메뉴진입
    local chosen_command_sub=$1
    local title_of_menu_sub=$2

    # 히스토리 파일 정의하고 불러옴
    HISTFILE=$gotmp/go_history.txt
    history -r "$HISTFILE"

    # 탈출코드 또는 ctrlc 가 입력되지 않는 경우 루프
    while true; do
        clear || reset
        # 서브메뉴 타이틀 변경
        [ "$scut" ] && oldscut="$scut"
        [ "$title_of_menu_sub" ] && {
            scut=$(echo "$title_of_menu_sub" | awk -F'[][]' '{print $2}')
            title="\x1b[1;37;45m $title_of_menu_sub \x1b[0m"
        } || {
            scut=""
            oldscut=""
            title="\x1b[1;33;44m Main Menu \x1b[0m Load: $(loadvar)// $(free -m | awk 'NR==2 { printf("FreeMem: %d/%d\n", $4, $2) }')"
        }
        [ "$oldscut" ] && flow="$oldscut->$scut" || { [ "$scut" ] && flow="m->$scut" || flow=""; }

        # 메인메뉴에서 서브 메뉴의 shortcut 도 사용할수 있도록 기능개선
        if [ ! "$chosen_command_sub" ]; then
            IFS=$'\n' allof_sub_shortcut_item="$(cat "$env" | grep "%%% {submenu_" | grep -E '\[.+\]$')"
            subkey=()
            idx=0
            for items in $allof_sub_shortcut_item; do
                shortcutname=$(echo "$items" | awk 'match($0, /\[([^]]+)\]/) {print substr($0, RSTART + 1, RLENGTH - 2)}')
                subkey[$idx]="${shortcutname}|||${items}"
                ((idx++))
            done
        fi

        echo
        echo "=============================================="
        echo -e "* $title $flow"
        echo "=============================================="
        if [ ! "$title_of_menu_sub" ]; then
            echo -ne "$([ "$(grep "PRETTY_NAME" /etc/*-release 2>/dev/null)" ] && grep "PRETTY_NAME" /etc/*-release 2>/dev/null | awk -F'"' '{print $2}' || cat /etc/*-release 2>/dev/null | sort -u) - $(
                WHT1
                hostname
                RST
            )"
            echo "=============================================="
        else

            # pre_commands 검출및 실행 (submenu 일때만)
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
        declare -a keys
        declare -a idx_mapping

        # 메인 or 서브 메뉴 리스트 구성
        while read line; do
            menu_idx=$((menu_idx + 1))
            items=$(echo "$line" | sed -r -e 's/%%% //' -e 's/%% //')

            # shotcut array
            key=$(echo "$items" | awk 'match($0, /\[([^]]+)\]/) {print substr($0, RSTART + 1, RLENGTH - 2)}')
            [ "$key" ] && {
                keys[$shortcut_idx]="$key"
                idx_mapping[$shortcut_idx]=$menu_idx
                ((shortcut_idx++))
            }

            printf "\e[1m%-3s\e[0m ${items}\n" ${menu_idx}.
        done < <(search_menulist) # %%% 모음 가져와서 파싱

        echo "0.  Exit [q] // Hangul_Crash ??? --> [ko] "
        echo "=============================================="

        if [ "$initvar" ]; then
            # 최초 실행시 특정 메뉴 shortcut 가져옴 ex) bash go.sh px
            choice=$initvar && initvar=""
        else
            IFS=' ' read -rep ">>> Select No. ([0-${menu_idx}],[ShortCut],h,e,sh): " choice choice1
        fi

        #shortcut 이 중복되더라도 첫번째 키만 가져옴
        key_idx=$(echo "${keys[*]}" | tr ' ' '\n' | awk -v target="$choice" '$0 == target {print(NR-1); exit}')

        #shortcut 을 참조하여 choice 번호 설정
        [ -n "$key_idx" ] && choice=${idx_mapping[$key_idx]}

        # 환경파일에서 가져온 명령문 출력 // CMDs // command list print func
        choice_list() {
            echo
            oldscut="$scut" && scut=$(echo "$title_of_menu" | awk -F'[][]' '{print $2}')
            [ "$oldscut" ] && flow="$oldscut->$scut" || { [ "$scut" ] && flow="m->$scut" || flow=""; }
            echo "=============================================="
            echo -ne "* \x1b[1;37;45m $title_of_menu CMDs \x1b[0m $(printf "$flow \033[1;33;44m pwd: %s \033[0m" "$(pwd)") \n"
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
            unset cmd_choice original_indices
            original_indices=()
            for i in $(seq 1 ${#chosen_commands[@]}); do

                c_cmd="${chosen_commands[$((i - 1))]}"

                # 명령구문에서 파일경로 추출 /dev /proc 제외한 일반경로
                file_paths="$(echo "$c_cmd" | awk '{for (i = 1; i <= NF; i++) {if(!match($i, /^.*https?:\/\//) && match($i, /\/[^\/]+\/[^ $|]*[a-zA-Z0-9]+[-_.]*[a-zA-Z0-9]/)) {filepath = substr($i, RSTART, RLENGTH); if ((filepath !~ /^\/dev\//) && (filepath !~ /var[A-Z][a-zA-Z0-9_.-]*/) && (filepath !~ /^\/proc\//)) {print filepath, "\n"}}}}')"

                # 해당 서버에 없는 경로에 대해서는 음영처리 // 있는 경로는 밝게
                # 서버에 따라 환경파일의 경로가 달라 눈으로 체크
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
                pi=""
                if [ ${c_cmd:0:1} != "#" ]; then
                    pi="${display_idx}."
                    # 배열 확장
                    original_indices=("${original_indices[@]}" "$i")
                    display_idx=$((display_idx + 1))
                fi

                # 명령문에 색깔 입히기 // 주석은 탈출코드 주석색으로 조정
                printf "\e[1m%-3s\e[0m " ${pi}
                echo "$c_cmd" | fold -sw 120 | sed -e '2,$s/^/    /' `# 첫 번째 줄 제외 각 라인 들여쓰기` \
                    -e 's/@@@@\([^ ]*\)@@@@/\x1b[1;37m\1\x1b[0m/g' `# '@@@@' ! -fd file_path 밝은 흰색` \
                    -e 's/@@@\([^ ]*\)@@@/\x1b[1;30m\1\x1b[0m/g' `# '@@@' ! -fd file_path 어두운 회색` \
                    -e 's/\(var[A-Z][a-zA-Z0-9_.@-]*\)/\x1b[1;35m\1\x1b[0m/g' `# var 변수 자주색` \
                    -e 's/@@/\//g' `# 변수에 @@ 를 쓸경우 / 로 변환 ` \
                    -e 's/\(!!!\)/\x1b[1;33m\1\x1b[0m/g' `# '!!!' 경고표시 노란색` \
                    -e 's/\(;;\)/\x1b[1;36m\1\x1b[0m/g' `# ';;' 청록색` \
                    -e '/^ *#/!b a' -e 's/\(\x1b\[0m\)/\x1b[1;36m/g' -e ':a' `# 주석행의 탈출코드 조정` \
                    -e 's/#\(.*\)/\x1b[1;36m#\1\x1b[0m/' `# 주석을 청록색으로 포맷`

            done

            echo "=============================================="
            vx=""
            cmd_choice=""
            [ "$x" ] && [[ $x == [0-9] || $x == [1-9][0-9] ]] && vx=$x && x=""
            tail -n1 "$gotmp/go_history.txt" | grep -q "vi2" && [ "$vx" ] && echo "I won\'t discard the number you pressed." && sleep 0.5 && cmd_choice=$vx
            [ ! "$vx" ] && { IFS=' ' read -rep ">>> Select No. ([0-$((display_idx - 1))],h,e,sh,conf): " cmd_choice cmd_choice1; } && vx=""

            # 선택하지 않으면 메뉴 다시 print // 선택하면 실제 줄번호 부여 -> 루프 2회 돌아서 주석 처리됨
            [ "$cmd_choice" ] && [[ $cmd_choice == [0-9] || $cmd_choice == [1-9][0-9] ]] && [ "$cmd_choice" -gt 0 ] && cmd_choice=${original_indices[$((cmd_choice - 1))]}
        } # end of choice_list()

        # 환경파일에서 명령문들 가져오는 함수

        listof_comm() {
            # 선택한 메뉴가 서브메뉴인경우 ${chosen_command_sub}가 포함된 리스트 수집
            sub_menu="${chosen_command_sub-}"
            IFS=$'\n' allof_chosen_commands="$(cat "$env" | awk -v title_of_menu="%%% ${sub_menu}${title_of_menu}" 'BEGIN {gsub(/[\(\)\[\]]/, "\\\\&", title_of_menu)} !flag && $0 ~ title_of_menu{flag=1; next} /^$/{flag=0} flag')"
            IFS=$'\n' chosen_commands=($(echo "${allof_chosen_commands}" | grep -v "^%% "))
            IFS=$'\n' pre_commands=($(echo "${allof_chosen_commands}" | grep "^%% "))
        }

        # 서브메뉴에 숨어있는 shortcut 호출이 있을때
        if [ '$choice' ] && ((!$choice > 0)) 2>/dev/null; then
            # subshortcut 을 참조하여 title_of_menu 설정
            # ex) chosen_command:{submenu_systemsetup} // title_of_menu:시스템 초기설정과 기타 (submenu) [i]
            for item in "${subkey[@]}"; do
                # echo $item
                if [ "$choice" == "${item%%|||*}" ]; then
                    chosen_command_sub="$(echo $item | awk -F'[{}]' 'BEGIN{OFS="{"} {print OFS $2 "}"}')"
                    title_of_menu="${item#*\}}"
                    title_of_menu_sub="${item#*\}}"
                    # choice 99 로 아래 메뉴 진입 시도
                    choice=99
                fi
            done
        fi

        # 메인/서브 메뉴에서 정상 범위의 숫자가 입력된경우
        if [ -n "$choice" ] && { case "$choice" in [0-9] | [1-9][0-9]) true ;; *) false ;; esac } && { [ "$choice" -ge 1 ] && [ "$choice" -le "$menu_idx" ] || [ "$choice" -eq 99 ]; }; then
            # 선택한 줄번호의 타이틀 가져옴
            [ ! "$choice" == 99 ] && title_of_menu="$(search_menulist | awk -v choice="$choice" 'NR==choice {print}')"

            # 선택한 줄번호의 타이틀에 맞는 리스트가져옴
            listof_comm

            cmds() {

                while true; do # 하부 메뉴 CMDs loop

                    chosen_command=""
                    num_commands=${#chosen_commands[@]} # 줄길이 체크

                    if [ $num_commands -gt 1 ]; then

                        # 환경파일에서 가져온 명령문 출력 && read cmd_choice
                        choice_list

                        if [ -n "$cmd_choice" ] && { case "$cmd_choice" in [0-9] | [1-9][0-9]) true ;; *) false ;; esac } && [ "$cmd_choice" -ge 1 ] && [ "$cmd_choice" -le "$num_commands" ]; then
                            chosen_command=${chosen_commands[$((cmd_choice - 1))]}
                        fi
                    elif [ $num_commands -eq 1 ]; then
                        chosen_command=${chosen_commands[0]}
                    else
                        echo "error : num_commands->$num_commands"
                        break
                    fi ### end of [ $num_commands -gt 1 ]


                    if [ "$(echo "$chosen_command" | grep "submenu_")" ]; then
                        menufunc $chosen_command ${title_of_menu}

                    elif [ "$chosen_command" ] && [ "${chosen_command:0:1}" != "#" ]; then
                        echo
                        if [ "$(echo "$chosen_command" | awk '{print $1}')" == "!!!" ]; then
                            chosen_command=${chosen_command#* }
                            echo -e "--> \x1b[1;31m$chosen_command\x1b[0m"
                            echo
                            printf "\x1b[1;33;41;4m !!!Danger!!! \x1b[0m Excute [Y/y/Enter or N/n]: " && read cfm
                        else
                            echo
                            cfm=y
                        fi
                        # ;; 로 이어진 명령들은 순차적으로 실행 (앞의 결과를 보고 뒤의 변수를 입력 가능)
                        if [[ $chosen_command != *"case"* ]] && [[ $chosen_command != *"esac"* ]]; then
                            IFS=$'\n' cmd_array=($(echo "$chosen_command" | sed 's/;;/\n/g')) # 명령어 배열 생성
                        else
                            cmd_array=("$chosen_command")
                        fi

                        local count=1
                        for cmd in "${cmd_array[@]}"; do # 배열을 반복하며 명령어 처리

                            echo -e "--> \x1b[1;36;40m$cmd\x1b[0m"

                            # 동일한 var 는 제외하고 read // awk '!seen[$0]++'

                            if [ "$cfm" == "y" ] || [ "$cfm" == "Y" ] || [ -z "$cfm" ]; then

                                while read -r var; do
                                    var_value=""
                                    dvar_value=""
                                    var_name="var${var#var}"

                                    # 기본값이 있을때 파싱
                                    if [[ $var_name == *__[a-zA-Z0-9.@-]* ]]; then
                                        dvar_value="${var_name#*__}" && dvar_value="${dvar_value//@@/\/}"
                                        dvar_value_array=($(echo "$dvar_value" | awk -F'__' '{for(i=1;i<=NF;i++)print $i}'))

                                        # 현재 시간을 기본값으로 넣고자 할때 datetag(ymd) or datetag2(ymdhms) 사용 adatetag 는 letter 로 시작하는 제한이 있을때
                                        [ "$dvar_value" == "datetag" ] && dvar_value=$(datetag)
                                        [ "$dvar_value" == "datetag2" ] && dvar_value=$(datetag2)
                                        [ "$dvar_value" == "adatetag" ] && dvar_value=at_$(datetag)
                                        [ "$dvar_value" == "adatetag2" ] && dvar_value=at_$(datetag2)

                                        # 기본값이 여러개 일때 select 로 선택진행 ex) aa_bb_cc select
                                        if [ ${#dvar_value_array[@]} -gt 1 ]; then
                                            { ps3=$PS3 ; PS3="Enter value for $(tput bold)$(tput setaf 5)$(tput setab 0)[${var_name%%__*}]$(tput sgr0): " ; select dvar_value in "${dvar_value_array[@]}"; do
                                                reply=$REPLY
                                                break
                                            done;PS3=ps3 ; } </dev/tty
                                            dvar_value="${dvar_value_array[$((reply - 1))]}"
                                        # 기본값이 하나일때
                                        else
                                            [ "$(echo "${var_name%%__*}" | grep -i path)" ] && GRN1 && echo "pwd: $(pwd)" && RST
                                            printf "!!(Cancel:c) Enter value for \e[1;35;40m[${var_name%%__*} Default:$dvar_value] \e[0m: "
                                            readv var_value </dev/tty
                                        fi
                                        # 이미 값을 할당한 변수는 재할당 요청을 하지 않도록 flag 설정
                                        eval flagof_${var_name%%__*}=set

                                    # 기본값에 쓸수 없는 문자가 들어올경우 종료
                                    elif [[ $var_name == *__[a-zA-Z0-9./]* ]]; then
                                        printf "!!! error -> var: only var[A-Z][a-zA-Z0-9_.@-]* -> / 필요시 @@ 로 대체 입력가능 \n " && exit 0

                                    # 변수 기본값이 없을때
                                    else
                                        # $HOME/go.private.env 에 정의된 변수가 있을때
                                        # 이전에 동일한 이름 변수에 값이 할당된 적이 있을때
                                        if [ "${!var_name}" ] || [ "${!var_name%%__*}" ]; then
                                            dvar_value="${!var_name}"
                                            # 이미 설정한 변수는 pass
                                            if [ "$(eval echo \"\${flagof_"${var_name}"}\")" == "set" ]; then
                                                var_value="$dvar_value"
                                            else
                                                printf "!!(Cancel:c) Enter value for \e[1;35;40m[${var_name} env Default:$dvar_value] \e[0m: "
                                                readv var_value </dev/tty
                                                eval flagof_${var_name}=set
                                            fi

                                        else
                                            [ "$(echo "${var_name}" | grep -i path)" ] && GRN1 && echo "pwd: $(pwd)" && RST
                                            printf "Enter value for \e[1;35;40m[$var_name]\e[0m: "
                                            readv var_value </dev/tty
                                            eval flagof_${var_name}=set
                                        fi
                                    fi
                                    echo
                                    # 변수에 read 수신값 할당
                                    if [ ! "$var_value" ] && [ "$dvar_value" ]; then
                                        # 변수의 기본값을 지정 (varABC__22) 기본값은 숫자와영문자만 가능
                                        if [[ $var_name == *__[a-zA-Z0-9.@-]* ]]; then
                                            var_value="$dvar_value"
                                        elif [ "${!var_name}" ]; then
                                            var_value="$dvar_value"
                                        fi
                                    elif [ -z "$var_value" ]; then
                                        { cancel=yes && echo "Canceled..." && break; }
                                    elif [ "$var_value" == "c" ] || [ "$var_value" == "q" ] || [ "$var_value" == "." ]; then
                                        { cancel=yes && echo "Canceled..." && break; }
                                    fi
                                    cmd=${cmd//$var_name/$var_value}

                                    # 실행중 // 동일 이름 변수 재사용 export
                                    # 기본값이 주어진 변수도 재사용 export
                                    [ "$var_value" ] && eval "export ${var_name%%__*}='${var_value}'"

                                done < <(echo "$cmd" | sed 's/\(var[A-Z][a-zA-Z0-9_.@-]*\)/\n\1\n/g' | sed -n '/var[A-Z][a-zA-Z0-9_.@-]*/p' | awk '!seen[$0]++')
                            # end of while

                            else # cfm -> n
                                # Danger item -> canceled
                                cmd="canceled"
                            fi # end of cfm=y

                            # 해당 메뉴의 선택명령이 딱 하나일때 바로 실행
                            if ((${#cmd_array[@]} == 1)); then
                                [ ! "$cancel" == "yes" ] && process_commands "$cmd" "$cfm"
                            else
                                # 명령어가 끝날때 Done... [Enter] print
                                [ ! "$cancel" == "yes" ] && { if ((${#cmd_array[@]} > count)); then process_commands "$cmd" "$cfm" "nodone"; else process_commands "$cmd" "$cfm"; fi; }
                            fi
                            ((count++))
                        done # end of for
                        unset cancel

                        # flagof 변수 초기화
                        unset $(compgen -v | grep '^flagof_')

                    fi
                    # direct command sub_menu
                    [[ $cmd_choice == ".." || $cmd_choice == "sh" ]] && bashcomm && cmds
                    [[ $cmd_choice == "..." || $cmd_choice == "," || $cmd_choice == "bash" ]] && /bin/bash && cmds
                    [[ $cmd_choice == "m" ]] && menufunc

                    # 환경파일 수정 및 재시작
                    [[ $cmd_choice == "conf" ]] && conf && cmds
                    [[ $cmd_choice == "confc" ]] && confc && cmds
                    [[ $cmd_choice == "conff" ]] && conff && cmds
                    [[ $cmd_choice == "conffc" ]] && conffc && cmds

                    # gohistory history reselct
                    [[ $cmd_choice == "h" ]] && gohistory && cmds
                    # hh view history view
                    [[ $cmd_choice == "hh" ]] && hi && read -rep "[Enter] " x && cmds

                    # explorer
                    [[ $cmd_choice == "e" ]] && { ranger $cmd_choice1 2>/dev/null || explorer; } && cmds
                    [[ $cmd_choice == "t" ]] && { htop 2>/dev/null || top; } && cmds
                    [[ $cmd_choice == "tt" ]] && { iftop -t 2>/dev/null || (yyay iftop && iftop -t); } && cmds
                    [[ $cmd_choice == "ttt" || $cmd_choice == "dfm" ]] && { dfmonitor; } && cmds
                    [[ $cmd_choice == "em" ]] && { mc -b || { yyay mc && mc -b; }; } && cmds
                    [[ $cmd_choice == "ee" ]] && { ranger /etc 2>/dev/null || explorer /etc; } && cmds
                    [[ $cmd_choice == "ll" ]] && { journalctl -n10000 -e; } && cmds

                    # cancel exit 0
                    if [[ $cmd_choice == "0" || $cmd_choice == "q" || $cmd_choice == "." ]]; then
                        # 환경변수 초기화
                        unsetvar varl
                        # CMDs 루프종료
                        break
                    fi

                    # 숫자를 선택하지 않고 직접 명령을 입력한 경우 그 명령이 존재하면 실행
                    [ "$cmd_choice" ] && [ "${cmd_choice//[0-9]/}" ] && command -v "$cmd_choice" &>/dev/null && echo && eval "$cmd_choice $cmd_choice1" && read -p 'You Win! Done... [Enter] ' x

                    # alarm
                    [ "$cmd_choice" ] && [ ! "${cmd_choice//[0-9]/}" ] && [ "${cmd_choice:0:1}" == "0" ] && echo "alarm set -> $cmd_choice $cmd_choice1" && sleep 1 && alarm "$cmd_choice" "$cmd_choice1" && {
                        echo
                        readx
                        cmds
                    }

                    [ $num_commands -eq 1 ] && break

                done #        end of      while true ; do # 하부 메뉴 loop 끝 command list

            }
            cmds

            # 하부 메뉴 루프에서 나온후
            # 서브 메뉴 쇼트컷 탈출시
            [ "$choice" ] && [ "$choice" == "99" ] && menufunc

            # 메뉴중에 정상범위 숫자도 아니고 메인쇼트컷도 아닌 예외 메뉴 할당

        elif [ "$choice" ] && [ "$choice" == "koo" ]; then
            # 한글이 네모나 다이아몬드 보이는 경우 (콘솔 tty)
            if [[ $(who am i | awk '{print $2}') == tty[1-9]* ]] && ! ps -ef | grep -q "[j]fbterm"; then
                which jfbterm 2>/dev/null && jfbterm || (yum install -y jfbterm && jfbterm)
            fi
        elif [ "$choice" ] && [ "$choice" == "ko" ]; then
            # hangul encoding chg
            if [[ ! "$(file $env | grep -i "utf")" && -s $env ]]; then
                echo "utf chg" && sleep 1
                if [[ "$(file $envorg | grep -i "utf")" ]]; then
                    cat "$envorg" | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$envtmp"
                    env="$envtmp"
                else
                    cat "$envorg" | iconv -f euc-kr -t utf-8//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$envtmp"
                    env="$envtmp"
                fi
                [ "$envko" ] && sed -i 's/^envko=.*/envko=utf8/' $HOME/go.private.env || echo "envko=utf8" >>$HOME/go.private.env
            elif [[ "$(file $envorg | grep -i "utf")" && "$(file $env | grep -i "utf")" && -s $env ]]; then
                echo "euc-kr chg" && sleep 1
                cat "$envorg" | iconv -f utf-8 -t euc-kr//IGNORE 2>/dev/null | sed 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' >"$envtmp"
                env="$envtmp"
                [ "$envko" ] && sed -i 's/^envko=.*/envko=euckr/' $HOME/go.private.env || echo "envko=euckr" >>$HOME/go.private.env
            else
                echo "euc-kr print" && sleep 1
                cp -a "$envorg" "$envtmp"
                sed -i 's/\([[:blank:]]\+\)#\([[:blank:]]\|$\).*/\1/' "$envtmp"
                env="$envtmp"
                if ! echo "$LANG" | grep -iq 'utf'; then export LANG=euc-kr; fi
                [ "$envko" ] && sed -i 's/^envko=.*/envko=euckr/' $HOME/go.private.env || echo "envko=euckr" >>$HOME/go.private.env
            fi
            menufunc
        elif [ "$choice" ] && [ "$choice" == "conf" ]; then
            conf
        elif [ "$choice" ] && [ "$choice" == "confc" ]; then
            confc
        elif [ "$choice" ] && [ "$choice" == "conff" ]; then
            conff
        elif [ "$choice" ] && [ "$choice" == "conffc" ]; then
            conffc
        elif [ "$choice" ] && [ "$choice" == "h" ]; then
            gohistory
        elif [ "$choice" ] && [ "$choice" == "hi" ]; then
            hi && read -rep "[Enter] " x
        elif [ "$choice" ] && [ "$choice" == "e" ]; then
            { ranger $choice1 2>/dev/null || explorer; }
        elif [ "$choice" ] && [ "$choice" == "t" ]; then
            { htop 2>/dev/null || top; }
        elif [ "$choice" ] && [ "$choice" == "tt" ]; then
            { iftop -t 2>/dev/null || (yyay iftop && iftop -t); }
        elif [ "$choice" ] && [[ $choice == "ttt" || $choice == "dfm" ]]; then
            { dfmonitor; }
        elif [ "$choice" ] && [ "$choice" == "em" ]; then
            mc -b || { yyay mc && mc -b; }
        elif [ "$choice" ] && [ "$choice" == "ee" ]; then
            { ranger /etc 2>/dev/null || explorer /etc; }
        elif [ "$choice" ] && [ "$choice" == "ll" ]; then
            { journalctl -n10000 -e; }
        elif [ "$choice" ] && [[ $choice == "update" || $choice == "uu" ]]; then
            update
        # 내장 함수와 .bashrc alias 를 쓸수 있는 bash
        elif [ "$choice" ] && [[ $choice == ".." || $choice == "sh" ]]; then
            bashcomm
        # alias 를 쓸수 있는 bash
        elif [ "$choice" ] && [[ $choice == "..." || $choice == "," || $choice == "bash" ]]; then
            /bin/bash
            # 메인/서브 메뉴 탈출
        elif [ "$choice" ] && [[ $choice == "m" ]]; then
            menufunc
        elif [ "$choice" ] && [[ $choice == "0" || $choice == "q" || $choice == "." ]]; then

            # title_of_menu_sub=""
            chosen_command_sub=""
            chosen_command=""

            # 서브메뉴에서 탈출할경우 메인메뉴로 돌아옴
            [ "$title_of_menu_sub" ] && menufunc || exit 0

            # alarm
        elif [ "$choice" ] && [ ! "${choice//[0-9]/}" ] && [ "${choice:0:1}" == "0" ]; then
            echo "alarm set --> $choice $choice1" && sleep 1 && alarm "$choice" "$choice1" && {
                echo
                readx
            }
        else

            [ "$choice" ] && [ "${choice//[0-9]/}" ] && command -v "$choice" &>/dev/null && echo && eval "$choice $choice1" && read -p 'You Win! Done... [Enter] ' x

        fi
    done # end of main while
}

# go.env 에서 사용가능한 한줄 함수 subfunc

# 함수의 내용을 출력하는 함수 ex) ff atqq
ff() { declare -f "$@"; }

# colored ip (1 line multi ip apply)
#cip() { awk '{line=$0;while(match(line,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)){IP=substr(line,RSTART,RLENGTH);line=substr(line,RSTART+RLENGTH);if(!(IP in FC)){BN[IP]=1;if(TC<6){FC[IP]=36-TC;}else{do{FC[IP]=31+(TC-6)%7;BC[IP]=40+(TC-6)%8;TC++;}while(FC[IP]==BC[IP]-10);if(FC[IP]==37){FC[IP]=36;}}TC++;}if(BC[IP]>0){CP=sprintf("\033[%d;%d;%dm%s\033[0m",BN[IP],FC[IP],BC[IP],IP);}else{CP=sprintf("\033[%d;%dm%s\033[0m",BN[IP],FC[IP],IP);}gsub(IP,CP,$0);}print}' ;}
cip() { awk -W interactive '{line=$0;while(match(line,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)){IP=substr(line,RSTART,RLENGTH);line=substr(line,RSTART+RLENGTH);if(!(IP in FC)){BN[IP]=1;if(TC<6){FC[IP]=36-TC;}else{do{FC[IP]=37-(TC-6)%7;BC[IP]=40+(TC-6)%8;TC++;}while(FC[IP]==BC[IP]-10);if(FC[IP]<31)FC[IP]=37;}TC++;}if(TC>6&&BC[IP]>0){CP=sprintf("\033[%d;%d;%dm%s\033[0m",BN[IP],FC[IP],BC[IP],IP);}else{CP=sprintf("\033[%d;%dm%s\033[0m",BN[IP],FC[IP],IP);}gsub(IP,CP,$0);}print}' 2>/dev/null ||
    awk '{line=$0;while(match(line,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)){IP=substr(line,RSTART,RLENGTH);line=substr(line,RSTART+RLENGTH);if(!(IP in FC)){BN[IP]=1;if(TC<6){FC[IP]=36-TC;}else{do{FC[IP]=37-(TC-6)%7;BC[IP]=40+(TC-6)%8;TC++;}while(FC[IP]==BC[IP]-10);if(FC[IP]<31)FC[IP]=37;}TC++;}if(TC>6&&BC[IP]>0){CP=sprintf("\033[%d;%d;%dm%s\033[0m",BN[IP],FC[IP],BC[IP],IP);}else{CP=sprintf("\033[%d;%dm%s\033[0m",BN[IP],FC[IP],IP);}gsub(IP,CP,$0);}print}'; }

# 실시간 출력 tail -f 등에 즉각 반응
cipf() { sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/\x1B[1;31m&\x1B[0m/g'; }

ipc() { ip a | cgrep DOWN | cgrep1 UP | cip; }
ipa() { ip a | cgrep DOWN | cgrep1 UP | cip; }
ipl() { ip l | cgrep DOWN | cgrep1 UP | cip; }

# colred ip cidr/24 -> same color
cip24() { awk '{line=$0; while (match(line, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {IP=substr(line, RSTART, RLENGTH); line=substr(line, RSTART+RLENGTH); Prefix=IP; sub(/\.[0-9]+$/, "", Prefix); if (!(Prefix in FC)) {BN[Prefix]=1; if (TC<6) {FC[Prefix]=36-TC;} else { do {FC[Prefix]=30+(TC-6)%8; BC[Prefix]=(40+(TC-6))%48; TC++;} while (FC[Prefix]==BC[Prefix]-10); if (FC[Prefix]==37) {FC[Prefix]--;}} TC++;} if (BC[Prefix]>0) {CP=sprintf("\033[%d;%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], BC[Prefix], IP);} else {CP=sprintf("\033[%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], IP);} gsub(IP, CP, $0);} print;}'; }

# colred ip cidr/16 -> same color
cip16() { awk '{line=$0; while (match(line, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {IP=substr(line, RSTART, RLENGTH); line=substr(line, RSTART+RLENGTH); Prefix=IP; sub(/\.[0-9]+\.[0-9]+$/, "", Prefix); if (!(Prefix in FC)) {BN[Prefix]=1; if (TC<6) {FC[Prefix]=36-TC;} else { do {FC[Prefix]=30+(TC-6)%8; BC[Prefix]=(40+(TC-6))%48; TC++;} while (FC[Prefix]==BC[Prefix]-10); if (FC[Prefix]==37) {FC[Prefix]--;}} TC++;} if (BC[Prefix]>0) {CP=sprintf("\033[%d;%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], BC[Prefix], IP);} else {CP=sprintf("\033[%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], IP);} gsub(IP, CP, $0);} print;}'; }

# 검색문자열들 색칠(red)
cgrep() {
    for word in "$@"; do awk_cmd="${awk_cmd}{gsub(/$word/, \"\033[1;31m&\033[0m\")}"; done
    awk "${awk_cmd}{print}"
}
cgrep1() {
    for word in "$@"; do awk_cmd="${awk_cmd}{gsub(/$word/, \"\033[1;33m&\033[0m\")}"; done
    awk "${awk_cmd}{print}"
}
cgrepl() {
    for word in "$@"; do awk_cmd="${awk_cmd}/$word/ {print \"\033[1;31m\"\$0\"\033[0m\"; next} "; done
    awk "${awk_cmd}{print}"
}
cgrepline() {
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
cgrep3137() {
    pattern=$(echo "$*" | sed 's/ /|/g')
    awk -v pat="${pattern}" '{gsub(pat, "\033[1;31m&\033[0;37m"); print $0;}'
}

# 줄긋기 draw line
dline() {
    num_characters="${1:-50}"
    delimiter="${2:-=}"
    printf "%.0s$delimiter" $(seq "$num_characters")
    printf "\n"
}

# colored percent
cper() { awk 'match($0,/([5-9][0-9]|100)%/){p=substr($0,RSTART,RLENGTH-1);gsub(p"%","\033[1;"(p==100?31:p>89?31:p>69?35:33)"m"p"%\033[0m")}1'; }

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

# colored dir
cdir() { awk '{match_str="(/[a-zA-Z0-9][^ ()|$]+)"; gsub(match_str, "\033[36m&\033[0m"); print $0; }'; }

# cpipe -> courl && cip24 && cdir
cpipe() { awk -W interactive '{gsub("https?:\\/\\/[^ ]+", "\033[1;36;04m&\033[0m"); gsub(" /[a-z0-9A-Z][^ ()|$]+", "\033[36m&\033[0m"); line=$0; while (match(line, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {IP=substr(line, RSTART, RLENGTH); line=substr(line, RSTART+RLENGTH); Prefix=IP; sub(/\.[0-9]+$/, "", Prefix); if (!(Prefix in FC)) {BN[Prefix]=1; if (TC<6) {FC[Prefix]=36-TC;} else { do {FC[Prefix]=30+(TC-6)%8; BC[Prefix]=(40+(TC-6))%48; TC++;} while (FC[Prefix]==BC[Prefix]-10); if (FC[Prefix]==37) {FC[Prefix]--;}} TC++;} if (BC[Prefix]>0) {CP=sprintf("\033[%d;%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], BC[Prefix], IP);} else {CP=sprintf("\033[%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], IP);} gsub(IP, CP, $0);} print;}' 2>/dev/null ||
    awk '{gsub("https?:\\/\\/[^ ]+", "\033[1;36;04m&\033[0m"); gsub(" /[a-z0-9A-Z][^ ()|$]+", "\033[36m&\033[0m"); line=$0; while (match(line, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {IP=substr(line, RSTART, RLENGTH); line=substr(line, RSTART+RLENGTH); Prefix=IP; sub(/\.[0-9]+$/, "", Prefix); if (!(Prefix in FC)) {BN[Prefix]=1; if (TC<6) {FC[Prefix]=36-TC;} else { do {FC[Prefix]=30+(TC-6)%8; BC[Prefix]=(40+(TC-6))%48; TC++;} while (FC[Prefix]==BC[Prefix]-10); if (FC[Prefix]==37) {FC[Prefix]--;}} TC++;} if (BC[Prefix]>0) {CP=sprintf("\033[%d;%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], BC[Prefix], IP);} else {CP=sprintf("\033[%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], IP);} gsub(IP, CP, $0);} print;}'; }
#cpipe() { awk '{gsub("https?:\\/\\/[^ ]+", "\033[1;36;04m&\033[0m"); gsub(" /[a-z0-9A-Z][^ ()|$]+", "\033[36m&\033[0m"); line=$0; while (match(line, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {IP=substr(line, RSTART, RLENGTH); line=substr(line, RSTART+RLENGTH); Prefix=IP; sub(/\.[0-9]+$/, "", Prefix); if (!(Prefix in FC)) {BN[Prefix]=1; if (TC<6) {FC[Prefix]=36-TC;} else { do {FC[Prefix]=30+(TC-6)%8; BC[Prefix]=(40+(TC-6))%48; TC++;} while (FC[Prefix]==BC[Prefix]-10); if (FC[Prefix]==37) {FC[Prefix]--;}} TC++;} if (BC[Prefix]>0) {CP=sprintf("\033[%d;%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], BC[Prefix], IP);} else {CP=sprintf("\033[%d;%dm%s\033[0m", BN[Prefix], FC[Prefix], IP);} gsub(IP, CP, $0);} print;}'; }

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

# pipe 로 넘어온 줄의 첫번째 필드를 select
pipemenu1() {
    PS3="==============================================
 >>> Select No. : "
    export pipeitem=""
    items=$(while read -r line; do awk '{print $1}' < <(echo "$line"); done)
    [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && export pipeitem="$item" && break; done </dev/tty
    unset PS3
}
pipemenu1cancel() {
    PS3="==============================================
 >>> Select No. : "
    export pipeitem=""
    items=$(
        while read -r line; do awk '{print $1}' < <(echo "$line"); done
        echo ": Cancel"
    )
    [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && export pipeitem="$item" && break; done </dev/tty
    unset PS3
}

# pipe 로 넘어온 줄의 모든 필드를 select
pipemenu() {
    PS3="==============================================
>>> Select No. : "
    OLD_IFS=$IFS
    IFS=$' \n'
    export pipeitem=""
    items=$(while read -r line; do awk '{print $0}' < <(echo "$line"); done)
    [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && export pipeitem="$item" && break; done </dev/tty
    IFS=$OLD_IFS
    unset PS3
}
pipemenucancel() {
    PS3="==============================================
 >>> Select No. : "
    OLD_IFS=$IFS
    IFS=$' \n'
    items=$(
        while read -r line; do awk '{print $0}' < <(echo "$line"); done
        echo ":_Cancel"
    )
    [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && export pipeitem="$item" && break; done </dev/tty
    IFS=$OLD_IFS
    unset PS3
}

# pipe 로 넘어온 라인별로 select
pipemenulist() {
    PS3="==============================================
>>> Select No. : "
    OLD_IFS=$IFS
    IFS=$'\n'
    export pipeitem=""
    items=$(
        while read -r line; do awk '{print $0}' < <(echo "$line"); done
        echo ": Cancel"
    )
    [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && export pipeitem="$item" && break; done </dev/tty
    IFS=$OLD_IFS
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
    OLD_IFS=$IFS
    IFS=$'\n'
    items=$(
        while read -r line; do awk '{print $0}' < <(echo "$line"); done | stripe
        echo ": Cancel"
    )
    [ "$items" ] && select item in $items; do [ -n "$item" ] && echo "$item" && break; done </dev/tty
    IFS=$OLD_IFS
    unset PS3
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
    local c="$@"
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
eip() { [ -s $gotmp/go_exceptips_grep.txt ] && grep -vEf $gotmp/go_exceptips_grep.txt || cat; }

# field except // grep -v 은 줄전체를 기준으로 하지만 eip5 는 5번째 필드를 기준으로 세분화함
eipf() {
    field="$1"
    if [ -s $gotmp/go_exceptips_grep.txt ]; then

        awk -v field="$field" -v gotmp="$gotmp" 'BEGIN { while (getline < (gotmp "/go_exceptips_grep.txt")) exceptips[$0] = 1 } { ma = 0; for (except in exceptips) { if (index($field, except) == 1) { ma = 1; break } } if (ma == 0) print }' -
    else cat; fi
}
eip1() { eipf 1; }
eip2() { eipf 2; }
eip3() { eipf 3; }
eip4() { eipf 4; }
eip5() { eipf 5; }

# proxmox vmslist
#vmslist() { pvesh get /cluster/resources -type vm --noborder --noheader 2>/dev/null | awk '{print $1,$13,$15}' |awk '{if($2=="") print $1,"cluster down"; else print $0}' ; }
vmslist() { pvesh get /cluster/resources -type vm --noborder --noheader 2>/dev/null | awk '{print $1,$17,$23}' | awk '{if($2=="") print $1,"cluster down"; else print $0}'; }
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
datetag() { datetag1; }
datetag1() { date "+%Y%m%d"; }
datetag2() { date "+%Y%m%d_%H%M%S"; }
datetag3() { date "+%Y%m%d_%H%M%S"_$((RANDOM % 9000 + 1000)); }
datetagw() { date "+%Y%m%d_%w"; } # 0-6
lastday() { date -d "$(date '+%Y-%m-01') 1 month -1 day" '+%Y-%m-%d'; }
lastdaya() { date -d "$(date '+%Y-%m-01') 2 month -1 day" '+%Y-%m-%d'; }
lastdayb() { date -d "$(date '+%Y-%m-01') 0 month -1 day" '+%Y-%m-%d'; }

# seen # not sort && uniq
seen() { awk '!seen[$0]++'; }
# not sort && uniq && lastseen print
lastseen() { awk '{ records[$0] = NR } END { for (record in records) { sorted[records[record]] = record } for (i = 1; i <= NR; i++) { if (sorted[i]) { print sorted[i] } } }'; }

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
    source ~/.bashrc
    unalias q 2>/dev/null
    HISTFILE=$gotmp/go_history.txt
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
    echo "$d / $base / $org"
    read -r x
    [ ! -f "$1" ] && {
        echo "오류: 파일 없음."
        return 1
    }
    PS3="선택: "
    select file in $(find "$d" -maxdepth 1 -name "${base}.[0-9]*.bak" -print0 | xargs -0 ls -lt | awk '{print $NF}' | head -n 5); do [ -n "$file" ] && {
        mv -n "$1" "$d/$org" && cp -f "$file" "$d/$base" && echo "복원됨: '$d/$base', 원래: '$d/$org'"
        break
    }; done
    read -r x
}

# vi2 envorg && restart go.sh
conf() {
    vi2 $envorg $scut
    [ -f /html/go.env ] && cp -a $envorg /html/go.env && chmod 644 /html/go.env
    exec $gofile $scut
}
conff() {
    vi2 $gofile
    [ -f /html/go.sh ] && cp -a $gofile /html/go.sh && chmod 755 /html/go.sh
    exec $gofile $scut
}
confc() { rollback $envorg; }
conffc() { rollback $gofile; }

# confp # env 환경변수로 불러와 스크립트가 실행되는 동안 변수로 쓸수 있음
confp() { vi2a $HOME/go.private.env; }

# bell
bell() { echo -ne "\a"; }
# telegram push
push() {
    local message
    message="$@"
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
        ps -ef | grep [a]larm_task | awknf8 | cgrep "alarm_task_$input" | grep -v "awk"
    fi
    if [[ ${input:0:4} == "0000" ]]; then
        [ ! "${input:4:2}" ] && input="$input$(echo "$telegram_msg" | awk1)" && telegram_msg="$(echo "$telegram_msg" | awknf2)" # && echo "input: $input // msg: $telegram_msg"
        local time_in_hours="${input:4:2}"
        local time_in_minutes="${input:6:2}"
        local days="${input:8:2}"
        [ -z "$days" ] && days=0
        telegram_msg="${time_in_hours}:${time_in_minutes}-Alarm ${telegram_msg}"
        echo ": alarm_task_$input && curl -m1 -ks -X POST \"https://api.telegram.org/bot${telegram_token}/sendMessage\" -d chat_id=${telegram_chatid} -d text=\"${telegram_msg}\"" | at $time_in_hours:$time_in_minutes $( ((days > 0)) && echo "today + $days" days) &>/dev/null

        atq | sort | while read -r l; do
            echo $l
            j=$(echo $l | awk1)
            at -c $j | tail -n2 | head -n1
        done | stripe | cgrep alarm_task_$input
    elif [[ ${input:0:2} == "00" ]]; then
        local time_in_minutes="${input:2}"
        time_in_minutes="${time_in_minutes#0}"
        telegram_pre="${time_in_minutes}분 카운트 완료."
        [ ! "$(file $gofile | grep -i "utf")" ] && telegram_pre="$(echo "$telegram_pre" | iconv -f EUC-KR -t UTF-8)"
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
        [ ! "$(file $gofile | grep -i "utf")" ] && telegram_pre="$(echo "$telegram_pre" | iconv -f EUC-KR -t UTF-8)"
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

# history view
hh() { cat $gotmp/go_history.txt | grep -v "^eval " | lastseen | tail -10 | stripe; }
gohistory() {
    echo
    echo "= go_history ================================="
    eval $(cat $gotmp/go_history.txt | grep -v "^eval " | lastseen | tail -n20 | pipemenulistc | noansi)
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
# awk nf nf-1 awk99 -> 끝열 출력
awk99() { awk '{print $NF}'; }
awk98() { awk '(NF>1){print $(NF-1)}'; }
# awk NR pass awknr2 -> 2행부터 끝까지 출력
for ((i = 1; i <= 10; i++)); do eval "awknr${i}() { awk 'NR >= '$i' '; }"; done
# awk NF pass awknf8 -> 8열부터 끝까지 출력
# 특정열이 없을경우 버그 나는것 수정
for ((i = 1; i <= 10; i++)); do eval "awknf${i}() { awk '{if (NF >= $i) print substr(\$0, index(\$0,\$$i))}' ; }"; done

# ssh handshake 과정중 오류로 접속이 안될때 ~/ssh/.config 에 설정후 재접속
sshre() {
    output=$(ssh "$@" 2>&1)
    if echo "$output" | grep -q "no matching host key type found"; then
        algorithms=$(echo "$output" | grep -oP 'Their offer: \K.*?(?=\r|\n)' | sed 's/ /,/g')
        printf "Host %s\n HostKeyAlgorithms +%s\n" "$1" "$algorithms" | tee -a "$HOME/.ssh/config" >/dev/null
        echo "HostKey config saved, reconnecting..."
        ssh "$@"
    elif echo "$output" | grep -q "no matching key exchange method found"; then
        algorithms=$(echo "$output" | grep -oP 'Their offer: \K.*?(?=\r|\n)' | sed 's/ /,/g')
        printf "Host %s\n    KexAlgorithms +%s\n" "$1" "$algorithms" | tee -a "$HOME/.ssh/config" >/dev/null
        echo "Kex config saved, reconnecting..."
        ssh "$@"
    else echo "$output"; fi
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

# assh id:pw@host:port  (pw 에 특수문자가 없는 경우에 한하여 이용)
# assh id pw host port  (pw 에 특수문자가 있는 경우 'pw' 형태로 이용가능)
assh() {
    local input="$1"
    local id pw host port
    if [[ $input == *":"* ]] && [[ $input == *"@"* ]]; then IFS='@:' read -r id pw host port < <(echo "$input"); else
        id="$1"
        pw="$2"
        host="$3"
        port="$4"
    fi
    port="${port:-22}"
    echo "id:$id pw:$pw host:$host port:$port"
    expect -c "set timeout 3; spawn ssh -p $port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET $id@$host; expect \"password:\" { sleep 0.2; send \"$pw\\r\" } \"key fingerprint\" { sleep 0.2; send \"yes\\r\"; expect \"password:\" { sleep 0.2; send \"$pw\\r\" } }; interact"
}

# 인수 없을때 read -p
get_input() { [ -z "$1" ] && read -p "$2: " input && echo "$input" || echo "$1"; }

# ncp zstd or tar 압축 전송
ncp() {
    local h p r l i dir cmd
    h=$(get_input "$1" "원격 호스트 (예: abc.com)")
    p=$([[ -n $4 ]] && echo "-p $4" || echo "")
    r=$(get_input "$2" "원격 경로")
    l=$(get_input "$3" "로컬 디렉토리")
    i=$(basename "$r")
    dir=$(dirname "$r")
    cmd="(ssh $p $h 'command -v zstd &>/dev/null ' && command -v zstd &>/dev/null ) && ssh $p $h 'cd \"${dir}\" && tar cf - \"${i}\" | zstd ' | { pv 2>/dev/null||cat; }| zstd -d | tar xf - -C \"${l}\" || ssh $p $h 'cd \"${dir}\" && tar czf - \"${i}\"' | { pv 2>/dev/null||cat; } | tar xzf - -C \"${l}\""
    echo "$cmd"
    eval "$cmd"
}

ncpr() {
    local l h r p i dir cmd
    l=$(get_input "$1" "로컬 경로")
    h=$(get_input "$2" "원격 호스트 (예: abc.com)")
    r=$(get_input "$3" "원격 경로")
    p=$([[ -n $4 ]] && echo "-p $4" || echo "")
    i=$(basename "$l")
    dir=$(dirname "$r")
    cmd="(ssh $p $h 'command -v zstd &>/dev/null ' && command -v zstd &>/dev/null ) && tar cf - \"${l}\" | zstd | { pv 2>/dev/null||cat; } | ssh $p $h 'cd \"${dir}\" && zstd -d | tar xf - -C \"${dir}\"' || tar czf - \"${l}\" | { pv 2>/dev/null||cat; } | ssh $p $h 'cd \"${dir}\" && tar xzf - -C \"${dir}\"'"
    echo "$cmd"
    eval "$cmd"
}

# ncp 로 파일을 카피할때 압축파일 형태로 로컬에 저장
ncpzip() {
    local h p r l i dir
    h=$(get_input "$1" "원격 호스트 (예: abc.com)")
    p=$([[ -n $4 ]] && echo "-p $4" || echo "")
    r=$(get_input "$2" "원격 경로")
    l=$(get_input "$3" "로컬 디렉토리")
    i=$(basename "$r")
    dir=$(dirname "$r")
    ssh $p $h "command -v zstd &>/dev/null " && command -v zstd &>/dev/null && { ssh $p $h "cd '$dir' && tar cf - '$i' | zstd " | (pv 2>/dev/null || cat) >"${l}/${h}.${i}.tar.zst" && ls -alh "${l}/${h}.${i}.tar.zst"; } || {
        ssh $p $h "cd '$dir' && tar czf - '$i'" | (pv 2>/dev/null || cat) >"${l}/${h}.${i}.tgz"
        ls -alh "${l}/${h}.${i}.tgz"
    }
}

# ncpzip 이후 업데이트된 파일이 있을때 업데이트
ncpzipupdate() {
    local h r l p i dir b uf ts fn
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
            fn="${b}.tar.zst.update.${ts}.txt"
            echo "$uf" >"${b}.tar.zst.update.${ts}.txt"
            ssh $p $h "tar -cf - -T /dev/stdin" <"${b}.tar.zst.update.${ts}.txt" | zstd | (pv 2>/dev/null || cat) >"${b}.tar.zst.update.${ts}.tar.zst"
        elif [ -f "${b}.tgz" ]; then
            fn="${b}.tgz.update.${ts}.txt"
            echo "$uf" >"${b}.tgz.update.${ts}.txt"
            ssh $p $h "tar -czf - -T /dev/stdin" <"${b}.tgz.update.${ts}.txt" | (pv 2>/dev/null || cat) >"${b}.tgz.update.${ts}.tgz"
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
        base="${d}"
        if [ -f "$d" ] && [ "$(diff $d ${base}.1.bak 2>/dev/null)" -o ! -f ${base}.1.bak ]; then
            d3=$(date -r ${base}.3.bak +%Y%m%d 2>/dev/null)
            d4=$(date -r ${base}.4.bak +%Y%m%d 2>/dev/null)
            if [ -f "${base}.4.bak" ] && [[ $t == "$d3" && $t != "$d4" ]]; then
                cdate=$(date -r ${base}.4.bak +%Y%m%d)
                mv ${base}.4.bak ${base}.${cdate}.bak
            fi
            for i in 3 2 1 ""; do
                cmd=${i:+mv}
                cmd=${cmd:-cp}
                $cmd ${base}.${i}.bak ${base}.$((${i:-0} + 1)).bak 2>/dev/null
            done
            cp $d ${base}.1.bak
        fi
        shift
    done
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

# sleepdot // ex) sleepdot 30 or sleepdot
# $1 로 할당된 실제 시간(초)이 지나면 종료 되도록 개선 sleep $1 과 동일하지만 시각화
sleepdot() {
    echo -n "sleepdot $1 "
    bashver=${BASH_VERSINFO[0]}
    ((bashver < 3)) && real1sec=1 || real1sec=1
    s=$(date +%s)
    c=1
    [ -z "$1" ] && echo -n ">>> Quit -> [Anykey] "
    time while [ -z "$x" ]; do
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
vi2() {
    rbackup "$1"
    if [ -n "$2" ]; then vim -c "autocmd VimEnter * silent! | /^%%% .*\[$2\]" "$1"; else vim "$1" || vi "$1"; fi
}
vi2e() {
    rbackup $1
    vim -c "set fileencoding=euc-kr" $1
}
vi2u() {
    rbackup $1
    vim -c "set fileencoding=utf-8" $1
}
vi2a() {
    rbackup $1 && [ ! "$(file -i $1 | grep "utf")" ] && {
        iconv -f euc-kr -t utf-8//IGNORE -o $1.utf8 $1 2>/dev/null
        mv $1.utf8 $1
    }
    if [ -n "$2" ]; then vim -c "autocmd VimEnter * silent! | /^%%% .*\[$2\]" "$1"; else vim "$1" || vi "$1"; fi
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
    echo "update file: $gofile $envorg" && sleep 1 && [ -f "$gofile" ] && wget -q -T 3 http://byus.net/go.sh -O "$gofile" && chmod 700 "$gofile" && [ -f "$envorg" ] && wget -q -T 3 http://byus.net/go.env -O "$envorg" && chmod 600 "$envorg" && exec "$gofile" "$scut"
}

# install
yyay() {
    [ "$(which yum)" ] && yum="yum" || yum="apt"
    while [ $# -gt 0 ]; do
        $yum install -y $1
        shift
    done
}
ayyy() { yyay $*; }
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

# 카피나 압축등 df -m  에 변동이 있을경우 모니터링용

dfmonitor() {
    DF_INITIAL=$(df -m | grep -vE "udev|none|efi|fuse|tmpfs")
    DF_BEFORE=$DF_INITIAL
    while true; do
        clear
        echo -e "System Uptime:\n--------------"
        uptime
        echo -e "\nRunning processes (e.g., pv, cp, tar, zst, rsync, dd, mv):\n----------------------------------------------------------\n\033[36m"
        ps -ef | grep -E "\<(pv|cp|tar|zst|rsync|dd|mv)\>" | grep -v grep
        echo -e "\033[0m\nInitial df -m output:\n---------------------\n$DF_INITIAL"
        echo -e "\033[0m\nPrevious df -m output:\n-----------------------\n$DF_BEFORE\n"
        DF_AFTER=$(df -m | grep -vE "udev|none|efi|fuse|Available|tmpfs")
        DIFF=$(diff --unchanged-group-format='' --changed-group-format='%>' <(echo "$DF_BEFORE") <(echo "$DF_AFTER"))
        echo -e "New df -m output with changes highlighted:\n------------------------------------------"
        echo "${DF_AFTER}" | while IFS= read -r line; do if [[ ${DIFF} == *"$line"* ]] && [ ! -z "$DIFF" ]; then echo -e "\033[1;33;41m$line\033[0m"; else echo "$line"; fi; done
        echo -e "\033[0m"
        DF_BEFORE=$DF_AFTER
        echo -n ">>> Quit -> [Anykey] "
        for i in $(seq 1 4); do read -p"." -t1 -n1 x && break; done
        [ "$x" ] && break
        echo
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
    if [ ! -f /etc/network/interfaces ]; then
        echo "Error: /etc/network/interfaces does not exist."
        exit 1
    fi

    backup_files=("/etc/network/interfaces.backup" "/etc/network/interfaces.1.bak" "/etc/network/interfaces.2.bak" "/etc/network/interfaces.3.bak")
    files=("/etc/network/interfaces" "${backup_files[@]}")

    for file in "${files[@]}"; do
        if [ -f $file ]; then
            cp $file /etc/network/interfaces 2>/dev/null
            systemctl restart networking.service

            if ping -c 4 8.8.8.8 >/dev/null; then
                echo "Network configuration from $file is successful."
                reconnect_down_veth_interfaces
                return 0
            else
                echo "Ping test failed for configuration from $file."
                [ "$file" == "/etc/network/interfaces" ] && cp /etc/network/interfaces /etc/network/interfaces.err.$(date "+%Y%m%d_%H%M%S")

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
    local output="$(dockersvcorg)"
    [ "$output" ] && while read -r line; do
        name=$(echo $line | awk '{print $1}')
        ip_port=$(echo $line | awk '{print $2}')
        ip_port2=$(echo $line | awk '{print $3}')
        updated_line="$name -> ${localip1}:${ip_port##*:} ${publicip}:${ip_port##*:} $([ "$publicip" == $(hostname -i) ] && echo "$(hostname):${ip_port##*:}")"
        [ -n "$ip_port2" ] && updated_line="$updated_line\n$name -> ${localip1}:${ip_port2##*:} ${publicip}:${ip_port2##*:} $([ "$publicip" == $(hostname -i) ] && echo "$(hostname):${ip_port2##*:}")"
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

    local backup_dir=$(dirname "$backup_file")
    local backup_timestamp=$(date -r "$backup_file" +%s)

    local backup_folder=$(tar tvzf $backup_file | head -n1 | awk '{print $NF}')

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
    local backup_filepath="$(readlinkf $1)"
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

############## template copy sample

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
"       Amir Salihefendic ? @amix3k
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

set fileencodings=utf8,euc-kr

" Enable filetype plugins
filetype plugin on
filetype indent on

" Set to auto read when a file is changed from the outside
set autoread
au FocusGained,BufEnter * checktime

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

"Always show current position
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
set foldcolumn=1


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Colors and Fonts
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Enable syntax highlighting
syntax enable

" Enable 256 colors palette in Gnome Terminal
if $COLORTERM == 'gnome-terminal'
    set t_Co=256
endif

try
    colorscheme desert
catch
endtry

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
"set encoding=euc-kr

" Use Unix as the standard file type
set ffs=unix,dos,mac


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Files, backups and undo
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Turn backup off, since most stuff is in SVN, git etc. anyway...
set nobackup
set nowb
set noswapfile


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
map <leader>t<leader> :tabnext

" Let 'tl' toggle between this and the last accessed tab
let g:lasttab = 1
nmap <Leader>tl :exe "tabn ".g:lasttab<CR>
au TabLeave * let g:lasttab = tabpagenr()


" Opens a new tab with the current buffer's path
" Super useful when editing files in the same directory
map <leader>te :tabedit <C-r>=expand("%:p:h")<cr>/

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
set t_ti= t_te=

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

    .yml)
        cat >"$file_path" <<'EOF'

EOF
        ;;

    esac
}

# !! P e e k a b o o !! go !!
initvar=$1
menufunc
