# CHANGELOG

모든 변경 이력. 날짜는 적용일 기준.

## 2026-09-28 — 배포 경로 srt.byus.net 이전 (v1.2)

`go.sh` / `go.env` 를 내려받는 주소를 **`byus.net` → `srt.byus.net`** 으로 통일했습니다.
웹 배포 위치도 `http://srt.byus.net/go.sh` · `http://srt.byus.net/go.env` 로 잡았습니다.

### 변경

- `go.sh` 최초 실행 시 `go.env` 자동 내려받기 → `http://srt.byus.net/go.env`
- `go.sh` `update` 함수(메뉴 `update` 키) → `http://srt.byus.net/go.sh` · `go.env`
- `go.env` [init] 메뉴의 최초 실행 안내 → `wget -O go.sh http://srt.byus.net/go.sh`
- `go.env` [help] 메뉴에 **`go.sh update - srt`** 항목 추가 (GitHub 경로와 병렬 사용 가능)
- `MANUAL_KR.md` / `MANUAL_EN.md` 설치 안내 URL 갱신
- `go.env` [help] 의 GitHub 업데이트 항목이 `wget … go.{sh,env}` 로 **중괄호를 그대로 전송해 404** 였던 문제 수정
  → `for f in sh env; do … done` 루프로 교체하고 파일별 권한(700/600) 자동 설정

### 유지 (의도적)

- `byus.net/explorer.sh` (파일관리 스크립트) , `byus.net/koreane.txt` (한글 단어 파일) 는
  별개 리소스라 기존 주소를 그대로 둡니다.

---

## 2026-09-28 — 메뉴 이동(navigation) 전면 정비 (v1.1)

`go.sh` 를 실제로 여러 경로로 돌려보며 발견한 **메뉴 간 이동 어거움** 을 한 번에 정리했습니다.
핵심은 `oldscut / ooldscut / oooldscut` �� 변수 밀기 방식 → **이력 스택(navigation stack)** 교체입니다.

### 추가

- **메뉴 이동 이력 스택 신설** (`nav_save / nav_drop / nav_peek / nav_set / nav_goto /
  nav_sync / nav_cmdlist / nav_back / nav_main`)
  - 실제 이동 경로를 스택으로 기록하고 `b` / `bb` / `bbb` 는 스택에서 정확히 N단계 되돌아갑니다.
  - 이력은 32단계까지만 보관하며, 같은 화면을 연속으로 쌓지 않습니다.
- **이동 키 안내줄** 추가 — 메뉴 하단에
  `[b] 이전화면 [bb] 2단계전 [bbb] 3단계전 [m] 메인메뉴 [e] 파일관리 [h] 실행히스토리 [conf] 설정편집 [sh] 내장쉔`
- 입력 프롬프트에 실제 동작하는 키만 표기 (`b:뒤로 bb:2단계 m:메인 h:이력 e:파일 conf:설정`).

### 수정 (동작 오류)

- **다른 화면의 단축키로 엉뚱한 메뉴가 열리던 문제**
  - `keysarr` / `idx_mapping` 이 화면을 바꿔도 초기화되지 않아, 이전 화면에서 모은 단축키가
    남은 채 번호가 재사용 → 다른 메뉴의 번호로 점프. 매 화면마다 초기화.
- **`b` 를 연속으로 누르면 A↔B 왕복(헛돌이)하던 문제**
  - 스택 교체로 해결. `bb`/`bbb` 가 현재 메뉴를 가리키던 경우도 함께 해소.
- **relay 경유 서브메뉴에서 `0` 을 누르면 상위메뉴를 잃어버리던 문제**
  - 기존 `grep -B1` 방식은 `{submenu_sys}` 본문행을 상위메뉴로 오인식 → 한글환경에선 곧바로
    메인메뉴로 튀어나갔습니다. 이제 실제 경로 기준 1단계 위 화면으로 복귀합니다.
- **flow 메뉴에서 엔터만 눌렀을 때 `menufunc` 이중 호출**
  - `b` 처리와 CMD 목록 쪽 처리가 겹쳐 같은 화면이 두 번 호출되던 것을 1회로 정리.
  - flow 여부 판정도 `ooldscut` 대신 실제 상위 화면으로 변경.
- **숫자 아닌 입력 시 `case` 자체가 실행되지 않던 문제**
  - `[[ ... || $cmd_choice -ge 100 ]]` 은 bash 문법 오류를 내고 전체 조건이 실패 →
    키 처리 자체가 건너뛰어졌습니다. `expr` 기반 숫자 판정으로 교체.
- **바로가기 해석 실패한 `99` 가 엉뚱한 메뉴 명령을 실행하던 문제**
  - `99` 는 내부용 값이므로 단축키 해석에 성공한 경우에만 통과하도록 보호선 추가.
- **바로가기(단축키) 중복 시 마지막 항목이 이기던 문제**
  - 루프에 `break` 를 추가해 "첫 번째 항목 우선" 규칙을 코드에서도 보장.
- **프롬프트에 `conf` 로 안내하지만 실제로는 없던 키**
  - `conf conf1 confb confmy conff confc conffc pconf str search ff ffc fffc format` 을
    CMD 화면과 메뉴 화면 양쪽에서 동일하게 동작하도록 보강.
- **CMD 화면의 읽기 트랩이 해제되지 않던 문제**
  - `pre_commands` 가 없는 화면에서 `trap - SIGINT SIGTERM EXIT` 이 주석처리되어 있어
    트랩이 이후 실행까지 남고 있었습니다.
- **go.env : `cd varWWWroot ;; menufunc eee`**
  - `menufunc eee` 는 eee 라는 메뉴가 없어 결국 메인메뉴가 떠버리는 동작이었습니다.
    의도대로 파일관리로 열도록 `explorer varWWWroot` 로 교체.
- **go.env : `awk/sed 변수 사용예제` 메뉴에 단축키가 없어 단축키로 진입 불가** → `[awksd]` 부여.

### 개선 (안내)

- 범위를 벗어난 번호 입력 시 `이 화면에 없는 번호입니다` 안내 (이전에는 아무 반응 없음).
- 같은 화면에서 같은 단축키를 누를 때 `이미 'xx' 화면 입니다. (b: 이전화면 / m: 메인메뉴)` 안내.
  (기존 `이곳이그곳!!!` + 2초 대기 제거)
- 1줄짜리(단일 명령/relay) 메뉴는 실행 후 자동으로 상위 화면으로 복귀.

### 검증

- `bash -n go.sh` 문법 검사 통과.
- `test/nav_test.sh` — 이력 스택 단위 테스트 21건 통과
  (스택 저장/조회, 왕복 방지, relay 경유, bb/bbb, 이력 상한, bash2 안전성, flow 판별).
- `test/env_test.sh` — go.env 정합성 감사 통과
  (중복 단축키 0건, orphan 태그 0건, relay 태그 100% 유효, 제목 구분자 충돌 0건).
- `test/menu_test.sh` — 218개 메뉴 본문 파싱 전수 점검 통과
  (본문 없는 메뉴 0건, 1줄 relay 메뉴 14건 정상 인식).
- `test/e2e_test.sh` — 실제 구동 검증
  (CMD목록→`0`→상위메뉴, relay→`b`→메인, relay→CMD→`0`→서브메뉴목록, 이력 소진 안내).
- `test/run_all.sh` 로 한 번에 실행 가능.
