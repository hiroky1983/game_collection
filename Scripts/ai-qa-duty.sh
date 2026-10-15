#!/bin/bash
# 自動QA当番（Issue #2314・会長決裁 2026-10-16）。launchd から 1 日 1 回（深夜帯）呼ばれる
# （`Scripts/com.asobiba.ai-qa.plist`。入れ方は docs/ai-devops.md「自動QA当番」）。
#
# 会長が多忙で Issue の洗い出しが減るため、会長の代わりにアプリを触って Issue の種を出す。
#   1) release の最新（最大の vX.Y.Z）をビルドする
#   2) **自分で作ったシミュレータ 1 台**で全ゲームを起動し、条件を変えて撮影する
#        標準の iPhone / iPhone SE（小画面）× 日本語・標準サイズ / 英語・文字サイズ大
#   3) 起動直後に落ちたゲーム・新しいクラッシュログを機械的に拾う
#   4) 画像を `claude` に見せ、はみ出し・44pt 未満・訳漏れ・真っ白を同じ性質ごとにまとめて起票させる
#      （プロンプトは `Scripts/ai-qa-prompt.md`）
#   5) 自分の端末だけ shutdown → delete し、撮影物を消す
#
# 資源の規律:
#   - 会長の端末は触らない。操作するのは **この実行が `simctl create` した UDID だけ**（名前 ai-qa-*）。
#     DeviceHub を quit しない。シミュレータは全体 2 台まで（会長 1 + この当番 1）なので、起動中が 2 台以上なら見送る
#   - 開発当番（ai-duty.sh）の全スロットのロックを取ってから走る（`duty:heavy` と同じ「重い処理は他と同時に走らせない」
#     排他）。当番が 1 つでも動いていれば見送り、走っている間に起動した当番は「全スロット使用中」で空振りして
#     3 分後に回る（詰まるのではなく後ろへずれる）
#   - 派生データは当番とは別（~/.asobiba-qa/derived-data）。撮影物は実行ごとの scratch に置き、終了時に消す
set -uo pipefail

QA_HOME_DIR="${QA_HOME_DIR:-$HOME/.asobiba-qa}"
QA_DIR="$QA_HOME_DIR/game_collection"
LOG="${QA_LOG:-$HOME/Library/Logs/asobiba-ai-qa.log}"
LOCK_BASE="${TMPDIR:-/tmp}/asobiba-ai-duty.lock"   # 開発当番のスロットロック（ai-duty.sh の LOCK_BASE と同じ）
QA_LOCK="${TMPDIR:-/tmp}/asobiba-ai-qa.lock"
DUTY_MAX_SLOTS="${DUTY_MAX_SLOTS:-2}"
BUNDLE_ID="com.hirockysan1983.asobiba"
CHAIRMAN_UDID="7B217727-E958-437B-AF0A-5CE3FBA8229C"  # 会長が見ている端末。絶対に触らない
QA_LAUNCH_WAIT="${QA_LAUNCH_WAIT:-5}"
QA_MAX_SECONDS="${QA_MAX_SECONDS:-2700}"              # 撮影に使ってよい上限（超えたら残りは次回に回す）
QA_FETCH_TIMEOUT="${QA_FETCH_TIMEOUT:-90}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }
mkdir -p "$(dirname "$LOG")" "$QA_HOME_DIR"

# ---- 排他: 自分のロック + 開発当番の全スロット ------------------------------------------------
HELD_LOCKS=()
take_lock() {  # take_lock <dir> — 取れたら 0。生きた PID が持っていれば 1。死んだ PID のロックは回収する
  local d="$1" old age
  if ! mkdir "$d" 2>/dev/null; then
    old=$(cat "$d/pid" 2>/dev/null || true)
    if [ -z "$old" ]; then
      # PID 未書き込みは取得直後かもしれないので 60 秒は待つ。それ以上古ければ異常終了の残骸として回収する
      age=$(( $(date +%s) - $(stat -f %m "$d" 2>/dev/null || date +%s) ))
      [ "$age" -ge 60 ] || return 1
    elif kill -0 "$old" 2>/dev/null; then
      return 1
    fi
    rm -rf "$d" 2>/dev/null
    mkdir "$d" 2>/dev/null || return 1
  fi
  { echo $$ >"$d/pid"; } 2>/dev/null || return 1
  sleep 1
  [ "$(cat "$d/pid" 2>/dev/null || true)" = "$$" ] || return 1
  HELD_LOCKS+=("$d")
}
release_locks() {
  local d
  for d in "${HELD_LOCKS[@]:-}"; do
    if [ -n "$d" ] && [ "$(cat "$d/pid" 2>/dev/null || true)" = "$$" ]; then rm -rf "$d" 2>/dev/null; fi
  done
  HELD_LOCKS=()
}
UDID=""; RUN_DIR=""; SCRATCH=""
cleanup() {
  # 自分が作った端末だけ落として消す（名前が ai-qa- で始まり、会長の UDID でないことを確かめてから）
  if [ -n "$UDID" ] && [ "$UDID" != "$CHAIRMAN_UDID" ]; then destroy_sim "$UDID"; fi
  [ -n "$SCRATCH" ] && rm -rf "$SCRATCH" 2>/dev/null
  if [ -n "$RUN_DIR" ]; then
    git -C "$QA_DIR" worktree remove --force "$RUN_DIR" >>"$LOG" 2>&1 || log "worktree の削除に失敗: $RUN_DIR"
    git -C "$QA_DIR" worktree prune >>"$LOG" 2>&1
  fi
  release_locks
}
trap cleanup EXIT

take_lock "$QA_LOCK" || { log "前回の自動QAが実行中のため見送り"; exit 0; }
# 当番のスロットを全部取る（重い処理を当番と同時に走らせない）。1 つでも生きていれば見送り
for n in $(seq 1 "$DUTY_MAX_SLOTS"); do
  if [ "$n" -eq 1 ]; then sd="$LOCK_BASE"; else sd="$LOCK_BASE.$n"; fi
  take_lock "$sd" || { log "開発当番のスロット$n が使用中のため見送り"; exit 0; }
done

# ---- シミュレータ操作 -----------------------------------------------------------------------
booted_count() { xcrun simctl list devices booted 2>/dev/null | grep -c '(Booted)' || true; }
destroy_sim() {  # destroy_sim <udid> — 名前が ai-qa- で始まる端末だけ
  local u="$1" name
  name=$(xcrun simctl list devices -j 2>/dev/null | python3 -c "
import json,sys
u=sys.argv[1]
for r in json.load(sys.stdin)['devices'].values():
    for d in r:
        if d['udid']==u: print(d['name'])
" "$u" 2>/dev/null)
  case "$name" in
    ai-qa-*) xcrun simctl shutdown "$u" >>"$LOG" 2>&1; xcrun simctl delete "$u" >>"$LOG" 2>&1; log "端末を削除: $name ($u)" ;;
    *) log "名前が ai-qa- でない端末は削除しない: ${name:-不明} ($u)" ;;
  esac
}
latest_ios_runtime() {
  xcrun simctl list runtimes -j | python3 -c "
import json,sys
rs=[r for r in json.load(sys.stdin)['runtimes'] if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
rs.sort(key=lambda r:[int(x) for x in r['version'].split('.')])
print(rs[-1]['identifier'] if rs else '')
"
}

if [ "$(booted_count)" -ge 2 ]; then
  log "起動中のシミュレータが 2 台以上（全体の上限）のため見送り"
  exit 0
fi
gh auth status >/dev/null 2>&1 || { log "gh 未認証またはオフライン"; exit 0; }

# ---- クローン・最新 release の worktree --------------------------------------------------------
if [ ! -d "$QA_DIR/.git" ]; then
  gh repo clone hiroky1983/game_collection "$QA_DIR" >>"$LOG" 2>&1 || { log "clone 失敗"; exit 0; }
fi
GIT_TERMINAL_PROMPT=0 git -C "$QA_DIR" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime="$QA_FETCH_TIMEOUT" \
  fetch origin --prune --quiet >>"$LOG" 2>&1 || { log "fetch 失敗のため見送り"; exit 0; }
# 「最新の release」は origin/ の追跡 ref だけから選ぶ（ローカルの幽霊ブランチを拾わない）
BRANCH=$(git -C "$QA_DIR" for-each-ref --format='%(refname:short)' 'refs/remotes/origin/release/v*' \
  | sed 's#^origin/##' | sort -V | tail -1)
[ -n "$BRANCH" ] || { log "release ブランチが無いため見送り"; exit 0; }
git -C "$QA_DIR" worktree prune >>"$LOG" 2>&1
RUN_DIR="$QA_HOME_DIR/runs/run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$QA_HOME_DIR/runs"
git -C "$QA_DIR" worktree add --detach "$RUN_DIR" "origin/$BRANCH" >>"$LOG" 2>&1 || { log "worktree 作成失敗"; RUN_DIR=""; exit 0; }
SHA=$(git -C "$RUN_DIR" rev-parse --short HEAD)
# プロンプトは main の版を使う（release に未取り込みでも最新の指示で動く）
# （QA_PROMPT_FILE は main に入る前の手動実行・テスト用）
if [ -n "${QA_PROMPT_FILE:-}" ]; then cp "$QA_PROMPT_FILE" "$QA_HOME_DIR/prompt.md"
else git -C "$QA_DIR" show origin/main:Scripts/ai-qa-prompt.md >"$QA_HOME_DIR/prompt.md" 2>/dev/null; fi
[ -s "$QA_HOME_DIR/prompt.md" ] || { log "ai-qa-prompt.md が見つからないため見送り"; exit 0; }
GAME_IDS=$(bash "$SCRIPT_DIR/list-game-ids.sh" "$RUN_DIR" 2>>"$LOG") || { log "ゲーム ID を列挙できないため見送り"; exit 0; }

SCRATCH="$QA_HOME_DIR/scratch-$$"
SHOTS="$SCRATCH/shots"; MANIFEST="$SCRATCH/manifest.tsv"
mkdir -p "$SHOTS"; : >"$MANIFEST"
DD="$QA_HOME_DIR/derived-data"
log "自動QA開始 (branch=$BRANCH sha=$SHA games=$(echo "$GAME_IDS" | wc -l | tr -d ' '))"

# ---- ビルド（端末とは独立に generic destination で）-----------------------------------------------
cd "$RUN_DIR" || exit 0
command -v xcodegen >/dev/null && xcodegen generate >>"$LOG" 2>&1
bash Scripts/apply-package-resolved.sh >>"$LOG" 2>&1
if ! xcodebuild -project GameCollection.xcodeproj -scheme GameCollection -configuration Debug \
     -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" \
     CODE_SIGNING_ALLOWED=NO build >"$SCRATCH/build.log" 2>&1; then
  # ビルドが落ちること自体は CI・開発当番が拾う領域。QA は見送る
  log "ビルド失敗のため見送り（末尾）: $(tail -5 "$SCRATCH/build.log" | tr '\n' ' ')"
  exit 0
fi
APP="$DD/Build/Products/Debug-iphonesimulator/GameCollection.app"
[ -d "$APP" ] || { log "ビルド成果物が無い: $APP"; exit 0; }

CRASH_BEFORE=$(ls ~/Library/Logs/DiagnosticReports/GameCollection-*.ips 2>/dev/null | sort)
RUNTIME=$(latest_ios_runtime)
[ -n "$RUNTIME" ] || { log "iOS ランタイムが見つからない"; exit 0; }
START=$(date +%s)

# ---- 撮影: 端末を 1 台ずつ作って壊す（同時に 1 台まで）--------------------------------------------
capture_device() {  # capture_device <tag> <devicetype id>
  local tag="$1" dtype="$2" cond game f alive launched pid
  local lang_args=()
  UDID=$(xcrun simctl create "ai-qa-$tag-$$" "$dtype" "$RUNTIME" 2>>"$LOG") || { log "端末作成失敗: $tag"; UDID=""; return 1; }
  if [ "$UDID" = "$CHAIRMAN_UDID" ]; then log "会長の端末と同じ UDID のため中止"; UDID=""; return 1; fi
  echo "$UDID" >>"${DUTY_SIM_RECORD:-/dev/null}"
  xcrun simctl boot "$UDID" >>"$LOG" 2>&1 && xcrun simctl bootstatus "$UDID" -b >>"$LOG" 2>&1 || { log "起動失敗: $tag"; return 1; }
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 >/dev/null 2>&1
  xcrun simctl install "$UDID" "$APP" >>"$LOG" 2>&1 || { log "インストール失敗: $tag"; return 1; }
  for cond in ja-default en-large; do
    if [ "$cond" = en-large ]; then
      xcrun simctl ui "$UDID" content_size extra-extra-large >>"$LOG" 2>&1
      lang_args=(-AppleLanguages '(en)' -AppleLocale en_US)
    else
      xcrun simctl ui "$UDID" content_size large >>"$LOG" 2>&1
      lang_args=()
    fi
    for game in hub $GAME_IDS; do
      if [ $(( $(date +%s) - START )) -gt "$QA_MAX_SECONDS" ]; then
        log "撮影時間の上限(${QA_MAX_SECONDS}s)に達したため、$tag/$cond/$game 以降は次回に回す"; break 2
      fi
      xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1
      # simctl launch は「<bundle id>: <pid>」を返す。シミュレータのアプリはホスト側のプロセスなので、
      # 待ったあとにその PID が生きているかで「起動直後に落ちたか」を見る
      # （`simctl spawn launchctl list` で探す方式は負荷時に取りこぼし、生きているのに消えた扱いになった）
      if [ "$game" = hub ]; then
        launched=$(xcrun simctl launch "$UDID" "$BUNDLE_ID" -screenshotMode ${lang_args[@]+"${lang_args[@]}"} 2>/dev/null)
      else
        launched=$(xcrun simctl launch "$UDID" "$BUNDLE_ID" -screenshotMode -startGame "$game" ${lang_args[@]+"${lang_args[@]}"} 2>/dev/null)
      fi
      pid="${launched##*: }"
      sleep "$QA_LAUNCH_WAIT"
      alive=no
      case "$pid" in ''|*[!0-9]*) ;; *) kill -0 "$pid" 2>/dev/null && alive=yes ;; esac
      f="qa-$(date +%Y%m%d)-$tag-$cond-$game.png"
      xcrun simctl io "$UDID" screenshot --type png "$SHOTS/$f" >/dev/null 2>&1
      [ -s "$SHOTS/$f" ] && sips -Z 900 "$SHOTS/$f" >/dev/null 2>&1
      printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$tag" "$cond" "$game" "$alive" >>"$MANIFEST"
    done
  done
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1
  destroy_sim "$UDID"; UDID=""
}
capture_device iphone com.apple.CoreSimulator.SimDeviceType.iPhone-17
capture_device se com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation

CRASH_AFTER=$(ls ~/Library/Logs/DiagnosticReports/GameCollection-*.ips 2>/dev/null | sort)
NEW_CRASHES=$(comm -13 <(echo "$CRASH_BEFORE") <(echo "$CRASH_AFTER") | grep . || true)
DEAD=$(awk -F'\t' '$5=="no"{print $1}' "$MANIFEST")
TOTAL=$(wc -l <"$MANIFEST" | tr -d ' ')
log "撮影完了: ${TOTAL} 枚 / 起動 ${QA_LAUNCH_WAIT} 秒後に消えていた: $(echo "$DEAD" | grep -c . || true) / 新しいクラッシュログ: $(echo "$NEW_CRASHES" | grep -c . || true)"
if [ "$TOTAL" -eq 0 ]; then log "1 枚も撮れなかったため claude は起動しない"; exit 0; fi

# ---- 入力フィルタ（第三者の本文を AI に渡さない。監査当番と同じ理由・Issue #164）-----------------------
GH_SHIM_DIR="$QA_HOME_DIR/gh-shim"
src="$RUN_DIR/Scripts/duty-gh-shim"
rm -rf "$GH_SHIM_DIR"
mkdir -p "$GH_SHIM_DIR" && chmod 700 "$GH_SHIM_DIR" \
  && cp "$src/gh" "$src/filter.jq" "$GH_SHIM_DIR/" && chmod +x "$GH_SHIM_DIR/gh" \
  || { log "入力フィルタを用意できないため claude は起動しない"; exit 0; }
stub="$GH_SHIM_DIR/.probe-gh"; json="$GH_SHIM_DIR/.probe.json"
printf '#!/bin/bash\ncat "%s"\n' "$json" >"$stub"; chmod +x "$stub"
jq -nc '{number:1,title:"t",author:{login:"duty-shim-probe"},body:"DUTY-SHIM-LEAK",comments:[]}' >"$json"
probe=$(DUTY_REAL_GH="$stub" "$GH_SHIM_DIR/gh" issue view 1 2>/dev/null)
rm -f "$stub" "$json"
case "$probe" in *DUTY-SHIM-LEAK*) log "入力フィルタ: 第三者の本文が素通しのため claude は起動しない"; exit 0 ;; esac

# ---- claude: 画像を見て起票 ------------------------------------------------------------------
# Edit/Write は渡さない（コードは触らない）。Sonnet 固定（週間リミット対策・監査当番と同じ）
cd "$SCRATCH" || exit 0
PATH="$GH_SHIM_DIR:$PATH" claude --model "${QA_MODEL:-sonnet}" \
  --allowedTools "Bash,Read,Glob,Grep" \
  -p "$(cat "$QA_HOME_DIR/prompt.md")

（今回の自動QA）
- ビルド: ${BRANCH} @ ${SHA}
- 撮影物の置き場: ${SHOTS}（一覧と起動直後の生死: ${MANIFEST}。列 = ファイル名・端末・条件・ゲームID・起動 ${QA_LAUNCH_WAIT} 秒後にアプリが生きていたか）
- 起動直後に消えていた撮影: ${DEAD:-なし}
- この実行中に増えたクラッシュログ: ${NEW_CRASHES:-なし}
- 撮影した枚数: ${TOTAL}" >>"$LOG" 2>&1
log "自動QA終了 (exit=$?)"
