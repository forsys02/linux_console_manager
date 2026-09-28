#!/bin/bash
unset IFS; clear

# ─────────────────────────────────────────────────────────────────────
# 표시 헬퍼 (2026-09-28 추가)
#   _fit : 개행/탭/CR 을 눈에 보이는 기호로 바꾼 뒤 폭에 맞춰 문자 단위 절단
#          (결과는 전역 REPLY — 파일명에 개행이 있어도 살아있게 명령치환 안 씀)
#   why  : clearmenu 는 "출력 줄 수 = page_size + 4" 가 고정이라는 전제로
#          커서를 page_size+4 만큼 올린다. 줄이 하나라도 줄바꿈되면 커서가
#          부족해져 화면이 영구적으로 깨진다 → 모든 표시줄은 1줄로 강제.
#   주의  : ${s//패턴/\n} 에서 치환어의 \n 은 확장되지 않아 아예 삭제된다.
#          (실측 'tab<TAB>here' → 'tabhere') → 반드시 변수로 넘긴다.
# ─────────────────────────────────────────────────────────────────────
NC="\033[0;m"
_ESC_N='\n'    # 단일따옴표 = 역슬래시 + n (2바이트) 가독용 기호
_ESC_T='\t'
_ESC_R='\r'
_fit() {
    local s=$1 n=$2
    s=${s//$'\n'/$_ESC_N}
    s=${s//$'\t'/$_ESC_T}
    s=${s//$'\r'/$_ESC_R}
    if [ -n "$n" ] && [ "$n" -ge 2 ] && [ "${#s}" -gt "$n" ]; then
        s=${s:0:$(( n - 1 ))}…
    fi
    REPLY=$s
}

explorer() {
    pwd="$1"
    realpath() {
        echo $1 | sed -e 's/\/\.\//\//g' | awk -F'/' -v OFS="/" 'BEGIN{printf "/";}{top=1; for (i=2; i<=NF; i++) {if ($i == "..") {top--; delete stack[top];} else if ($i != "") {stack[top]=$i; top++;}} for (i=1; i<top; i++){printf "%s", stack[i]; printf OFS;}}{print ""}'
    }

    pwd="$(realpath "$pwd")"
    # ── 메뉴 수집 ────────────────────────────────────────────────────
    #  2026-09-28 수정 : `ls -lt | grep "^-" | awk '{print $NF}'` 폐기
    #    - 공백/탭이 든 파일명 → 마지막 필드만 남아 "다른 파일"로 조작됨
    #      (name with space.txt → space.txt, 한글 파일명 → 파일.txt)
    #    - 개행이 든 파일명 → 2개 항목으로 쪼개져 구분 불가
    #    - `grep "^-"` 가 심볼릭 링크(l)와 깨진 링크를 통째로 가림
    #  대체 : find -printf '%f\0' 로 NUL 단위 수집 → read -r -d '' 로 통째 읽기.
    #         폴더=이름순 / 파일=최근수정순. (숨김파일도 함께 보인다)
    #  주의 : ls 에는 NUL 출력 옵션이 없다(ls -z 는 없는 옵션) → find 필수.
    local -a menu
    local line _n
    # NUL 구분 정렬 지원(coreutils 8.24+) 여부 → 미지원 시스템 폴백
    local _sortz=0
    printf '' | sort -z -d >/dev/null 2>&1 && _sortz=1
    _zsort()  { [ "$_sortz" = 1 ] && sort -z -d  || { tr '\0' '\n' | sort -d  | tr '\n' '\0'; }; }
    _zsortn() { [ "$_sortz" = 1 ] && sort -z -rn || { tr '\0' '\n' | sort -rn | tr '\n' '\0'; }; }

    menu=( "../" )
    while IFS= read -r -d '' line; do
        menu+=( "$line" )
    done < <( find "$pwd" -mindepth 1 -maxdepth 1 -type d -printf '%f/\0' 2>/dev/null | _zsort )

    _n=0
    while IFS= read -r -d '' line; do
        [ "$_n" -ge 300 ] && break
        menu+=( "${line#* }" )        # '%T@ %f' → 앞의 타임스탬프만 제거
        _n=$(( _n + 1 ))
    done < <( find "$pwd" -mindepth 1 -maxdepth 1 -type f -printf '%T@ %f\0' 2>/dev/null | _zsortn )

    normal="$NC" ; background="\033[7;40m" ; foreground="\033[36m" ; menu_length=${#menu[@]} ; selected=0
    page=0
    # ── 터미널 크기 판정 : 비tty / TERM 미설정(tput 실패) 시 0·음수가 되면
    #    page_size 가 0 → "division by 0" 로 죽고, 음수면 seq 가 역range → 화면 소실
    termheight=$(tput lines 2>/dev/null) || termheight=24
    termwidth=$(tput cols  2>/dev/null) || termwidth=80
    case $termheight in ''|*[!0-9]*) termheight=24 ;; esac
    case $termwidth  in ''|*[!0-9]*) termwidth=80  ;; esac
    [ "$termwidth" -lt 60 ] && termwidth=80
    page_size=$(($termheight - 8))
    [ $page_size -gt 20 ] && page_size=20
    [ $page_size -lt 1 ]  && page_size=1
    namew=$(($termwidth - 5))      # "N. " = 4칸 + 여유 1칸
    selw=$(($termwidth - 52))       # ">>> Select: [...]: " 고정폭 약 47칸 + 여유
    [ $selw -lt 4 ] && selw=4

    clearmenu() {
        echo -ne "\033[$(( ${page_size} + 4 ))A"  # up
        echo -ne "\033[J"  # delete
    }

    clear; echo; echo -e  "### Select File/Folder. \033[1;36m${pwd}\033[0m"

    trap 'stty sane; exit 0' SIGINT
    while true; do
        echo "========================================= [$(($page + 1))/$(( ${#menu[*]} / $page_size + 1 ))]"

        for index in $(seq $(($page * $page_size)) $(($page * $page_size + $page_size - 1))); do
            _label=$(( $index + 1 )).
            if [ "${index}" -eq "${selected}" ]; then
                _fit "${menu[$index]}" "$namew"
                printf '%-3s %b%s%b\n' "$_label" "$background" "$REPLY" "$normal"
            else
                if [ "${menu[index]}" != "${menu[index]//\//}" ]; then # folder or file
                    _fit "${menu[$index]}" "$namew"
                    printf '%-3s %b%s%b\n' "$_label" "$foreground" "$REPLY" "$normal"
                else
                    _fit "${menu[$index]}" "$namew"
                    printf '%-3s %s\n' "$_label" "$REPLY"
                fi
            fi
        done

        if [ "${selected}" -eq "${menu_length}" ]; then
            echo -e " 0. ${background}Cancel${normal}"
        else
            echo " 0. Cancel"
        fi

        echo "========================================= [$(($page + 1))/$(( ${#menu[*]} / $page_size + 1 ))]"

        up=$(printf '\u2191') down=$(printf '\u2193') left=$(printf '\u2190') right=$(printf '\u2192')

        _fit "${menu[${selected}]:-Cancel}" "$selw"
        printf ">>> Select: %s [$up$down,PageUp$left,PageDown$right,Enter,s,q]: \n" "$REPLY"

        local input valid_input
        while true; do
            valid_input=false
            IFS= read -r -sn1 input < /dev/tty

            case $input in
                $'\x1b')
                    read -n2 -t1 arrow < /dev/tty
                    case $arrow in
                        '[A') # Up
                            if [ $selected -gt 0 ]; then
                                selected=$((selected - 1))
                                if [ $selected -lt $(($page * $page_size)) ]; then
                                    page=$(($page - 1))
                                fi
                            fi
                            valid_input=true
                            ;;
                        '[B') # Down
                            if [ $selected -lt ${#menu[*]} ]; then
                                selected=$((selected + 1))
                                if [ $selected -ge $(($page * $page_size + $page_size)) ]; then
                                    page=$(($page + 1))
                                fi
                            fi
                            valid_input=true
                            ;;
                        '[C') # Right (PageDown)
                            if [ $selected -lt ${#menu[*]} ]; then
                                selected=$(($page * $page_size + $page_size))
                                page=$(($page + 1))
                                if [ $page -gt $((${menu_length} / ${page_size})) ]; then
                                    page=$((${menu_length} / ${page_size}))
                                fi
                                [ $selected -gt ${#menu[*]} ] && selected=${#menu[*]}
                            fi
                            valid_input=true
                            ;;
                        '[D') # Left (PageUp)
                            if [ $selected -gt 0 ]; then
                                selected=$(($page * $page_size - 1)) ; [ $selected -lt 0 ] && selected=0
                                page=$(($page - 1)) ; [ $page -lt 0 ] && page=0
                            fi
                            valid_input=true
                            ;;
                    esac
                    ;;
                "0"|"q"|"Q")
                    echo "Canceled..."
                    exit
                    ;;
                ""|"s"|"S")
                    if [ "${selected}" -eq "${menu_length}" ]; then
                        echo "Canceled..."
                        exit
                    else
                        newpwd="${pwd}/${menu[${selected}]}"
                        newpwd="$( realpath "${newpwd}" )"
                        if [ "$input" == 's' ] || [ "$input" == 'S' ] ; then
                            dfile "${newpwd%%/}"
                        elif [ -d "$newpwd" ] ; then
                            explorer "$newpwd"
                        else
                            dfile "${newpwd%%/}"
                        fi
                        break 2
                    fi
                    ;;
                *)
                    clearmenu
                    break
                    ;;
            esac

            if [ "$valid_input" = true ]; then
                clearmenu
                break
            fi
        done

    done

    selecteditem="${menu[$selected]}"

}

dfile() {
    # 2026-09-28 : 루트(/)에서 ../ 를 고르고 's' 를 누르면 ${newpwd%%/} 가 빈문자열이 된다
    #              → tail -n10 (인자 0개) 가 stdin 대기로 무한 정지했던 문제 방지
    [ -n "$1" ] || { echo "⚠️  대상 경로가 비어 있습니다. (루트 경로 선택됨)"; return 1; }
    case $1 in -*) set -- "./$1" ;; esac   # 옵션으로 오인되는 이름 방지

    echo "Dest: $1"
    echo "Choose action:"
    echo "1. Copy"
    echo "2. Move"
    echo "3. Delete"
    echo "f. find"
    echo

    if [ -f "$1" ]; then
        echo "4. Edit with vi"
        echo "5. Edit with nano"
        echo "6. Cat"
        [ "$(which batcat)" ] && echo "7. batCat"
        echo
    fi

    read -p "Enter your choice: " choice

    case $choice in
        1)
            echo "Copying..."
            ;;
        2)
            echo "Moving..."
            ;;
        3)
            echo "Deleting..."
            ;;
        f)
            echo "Finding..."
            ;;
        4)
            vim "$1" || vi "$1"
            ;;
        5)
            nano "$1"
            ;;
        6)
            cat "$1" | less -R
            ;;
        7)
            batcat "$1" | less -R
            ;;
        *)
            echo "Invalid choice."
            ;;
    esac

    echo -e "\n\033[1;36m==== tail output ====\033[0m"
    tail -n10 -- "$1"
    echo -e "\033[1;36m=====================\033[0m"
    explorer "$(dirname "$1")"
}

explorer "${1:-$PWD}"
