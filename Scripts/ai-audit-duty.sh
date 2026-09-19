#!/bin/bash
# 監査当番（品質・セキュリティ・バグ・敵対的検証）の日次発火。launchd から1日1回呼ばれる
# （設定は会長の Mac の ~/Library/LaunchAgents/com.asobiba.ai-audit.plist・StartCalendarInterval 05:00。
#  ai-duty.sh の plist と同じくローカル環境の設定のためリポジトリには含めない）。
# 開発当番（ai-duty.sh、3分ごと）・経営企画室とは役割が異なり、
# **コードは一切変更せず**、前回の監査以降に release/* と main へマージされた PR の差分をまとめて読み、
#   1) バグ（境界条件・競合・中断データ・計測の欠落）を敵対的に探し、テストを実際に回して裏を取る
#   2) セキュリティ（秘密情報・権限・外部通信・第三者入力の扱い）
#   3) 品質（規程との整合: 1局=1RuleSet・解析イベントの語彙・docs の更新漏れ・テストの有無）
#   4) 結果を `report:audit` の Issue に 1 本まとめ、確度の高い欠陥は `bug` + `ai:proposed` で個別に起票する
# を行う。2026-09-14 会長指示「当番5分起動に変えてから CodeRabbit のリミットで動いていないことが多い。
# 1日1回、ブランチの変更に対して品質・セキュリティ・バグ・敵対的検証のフローを入れたい」
# （実測: 同日 release/v1.1.5 にマージした 11 本のうち CodeRabbit のレビューが付いたのは 1 本）を受けて新設。
# セットアップ手順は docs/ai-devops.md 参照。
set -uo pipefail

AUDIT_DIR="$HOME/.asobiba-audit/game_collection"
LOCK_DIR="${TMPDIR:-/tmp}/asobiba-ai-audit.lock"
LOG="$HOME/Library/Logs/asobiba-ai-audit.log"
AUDIT_FETCH_TIMEOUT="${AUDIT_FETCH_TIMEOUT:-90}"
AUDIT_FETCH_KILL_GRACE="${AUDIT_FETCH_KILL_GRACE:-5}"
AUDIT_LOCK_GRACE="${AUDIT_LOCK_GRACE:-30}"  # PID 未書き込みのロックを「取得直後」とみなす秒数
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

# AUDIT_LOCK_GRACE は外部から差し替えられるため、0 以上の10進整数だけを通して既定値へ戻す。
# `[ "$AGE" -lt "$AUDIT_LOCK_GRACE" ]` は非数値だと「整数式が必要」で**失敗（= 偽）**になり、
# 猶予の判定を素通りして取得直後の PID 未書き込みロックを回収してしまう
# （= 本来防いでいる多重起動が起きる。ai-duty.sh へ PR #173 で入った対策の横展開・Issue #180）
case "$AUDIT_LOCK_GRACE" in
  ''|*[!0-9]*)
    log "AUDIT_LOCK_GRACE=$AUDIT_LOCK_GRACE は 0 以上の整数でないため既定値 30 を使う"
    AUDIT_LOCK_GRACE=30
    ;;
esac

# タイムアウト付き fetch（自己更新・本更新の両方から使う共通処理）。
# macOS には timeout(1) が無いため自前で見張り、上限を超えたら諦める。
#   - SIGTERM → 猶予 → SIGKILL → 猶予 と escalate し、それでも終了を確認できなければ
#     wait せずに諦める（残る子プロセスはゾンビだが、当番の進行を止めるよりはよい）。
#     低速回線での完全なハング（low-speed-limit だけでは検知できない）にも効く
# 戻り値: 0=成功 / 1=失敗 or タイムアウト
fetch_with_timeout() {
  local dir="$1" gpid waited=0
  GIT_TERMINAL_PROMPT=0 git -C "$dir" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
    fetch origin --prune --quiet >>"$LOG" 2>&1 &
  gpid=$!
  while [ "$waited" -lt "$AUDIT_FETCH_TIMEOUT" ] && kill -0 "$gpid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$gpid" 2>/dev/null; then
    local sig grace
    for sig in TERM KILL; do
      kill -"$sig" "$gpid" 2>/dev/null
      grace=0
      while [ "$grace" -lt "$AUDIT_FETCH_KILL_GRACE" ] && kill -0 "$gpid" 2>/dev/null; do
        sleep 1
        grace=$((grace + 1))
      done
      kill -0 "$gpid" 2>/dev/null || break
    done
    if kill -0 "$gpid" 2>/dev/null; then
      log "fetch (pid=$gpid) が SIGKILL でも終了しないため wait せずに見送り"
      return 1
    fi
    wait "$gpid" 2>/dev/null
    log "fetch が ${AUDIT_FETCH_TIMEOUT} 秒を超えたため見送り"
    return 1
  fi
  wait "$gpid" 2>/dev/null
}

# 自己更新: ai-duty.sh と同一パターン・同一の理由（launchd は会長の作業ツリーの本ファイルを
# 起動するため、main へマージしただけでは反映されない。#128 の教訓を最初から踏まえる）。
# セキュリティ考慮（所有者専用ディレクトリ・blob ハッシュ名・構文検証）も ai-duty.sh に準拠。
self_update() {
  [ -n "${AUDIT_SELF_UPDATED:-}" ] && return 0
  [ -d "$AUDIT_DIR/.git" ] || return 0
  fetch_with_timeout "$AUDIT_DIR" || return 0
  local oid cache fresh tmp
  oid=$(git -C "$AUDIT_DIR" rev-parse "origin/main:Scripts/ai-audit-duty.sh" 2>/dev/null) || return 0
  [ -n "$oid" ] || return 0
  cache="$HOME/.asobiba-audit/bin"
  mkdir -p "$cache" && chmod 700 "$cache" || return 0
  find "$cache" -maxdepth 1 -type f -name 'ai-audit-*.sh' -mtime +7 -delete 2>/dev/null
  fresh="$cache/ai-audit-${oid}.sh"
  tmp=$(mktemp "$cache/ai-audit-XXXXXX") || return 0
  if ! git -C "$AUDIT_DIR" show "origin/main:Scripts/ai-audit-duty.sh" >"$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
    rm -f "$tmp"; return 0
  fi
  if ! bash -n "$tmp" 2>/dev/null; then
    rm -f "$tmp"; log "自己更新: origin/main の ai-audit-duty.sh が構文エラーのため見送り"; return 0
  fi
  if cmp -s "$tmp" "$0"; then rm -f "$tmp"; return 0; fi
  mv -f "$tmp" "$fresh" || { rm -f "$tmp"; return 0; }
  log "自己更新: origin/main の ai-audit-duty.sh へ切り替え (実行中=$0, blob=${oid:0:7})"
  export AUDIT_SELF_UPDATED=1
  exec /bin/bash "$fresh" "$@"
}
self_update "$@"

# 多重起動防止（前回がまだ働いていたらスキップ。死んだプロセスのロックは回収）
#   mkdir から PID_FILE の書き込みまでには僅かな隙があり、その間に来た次のプロセスが
#   「PID が読めない = 停止済み」と誤判定して有効なロックを奪うと両方走る（PR #163・
#   CodeRabbit 指摘）。PID が読めないロックは AUDIT_LOCK_GRACE 秒だけ「取得直後」とみなして
#   回収しない。そのうえで PID_FILE を書いてから読み直し、自分のものでなければ降りる
#   （競合したとき、最後に書いた1プロセスだけが残る）。**この確認は回収した回に限らず必ず行う**:
#   回収経路のプロセスの `rm -rf` は誰が今ロックを持っていようと消すため、mkdir で新規に
#   取れたプロセスも所有権を奪われうる（ai-duty.sh と同じ理由・Issue #180 で横展開）。
lock_age() {
  local mtime now
  mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null) || return 1
  [ -n "$mtime" ] || return 1
  now=$(date +%s)
  echo $((now - mtime))
}
# PID の記録。失敗するのは直前に他プロセスの回収（rm -rf）でロックごと消えた場合。
# リダイレクトの失敗はコマンド自身の stderr より先に評価されるため（`echo ... > f 2>/dev/null` では
# 抑止されない）、グループ全体の stderr を潰して launchd の stderr に生のエラーを出さない
write_pid() { { echo $$ >"$PID_FILE"; } 2>/dev/null; }
release_lock() {
  [ "$(cat "$PID_FILE" 2>/dev/null || true)" = "$$" ] || return 0
  # 削除中に他プロセスが同じディレクトリへ書き込むと rm が "Directory not empty" で失敗しうる。
  # EXIT トラップから呼ばれるので launchd の stderr へは出さず、残ってもそのロックは
  # PID 未書き込み扱いで次回の猶予超過に回収される
  rm -rf "$LOCK_DIR" 2>/dev/null || log "ロックの解放に失敗（次回の猶予超過で回収される）"
}
PID_FILE="$LOCK_DIR/pid"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    log "前回実行中 (pid=$OLD_PID) のためスキップ"
    exit 0
  fi
  if [ -z "$OLD_PID" ]; then
    AGE=$(lock_age || true)
    # 非数値（stat の想定外出力）と負値（mtime が未来 = 時刻の巻き戻り）は「不明」に倒す。
    # AUDIT_LOCK_GRACE と同じ理由で、比較が失敗すると回収する側に落ちてしまう
    case "$AGE" in ''|*[!0-9]*) AGE="" ;; esac
    if [ -z "$AGE" ] || [ "$AGE" -lt "$AUDIT_LOCK_GRACE" ]; then
      log "ロック取得直後（PID 未書き込み・経過=${AGE:-不明}秒）のためスキップ"
      exit 0
    fi
  fi
  log "停止済みプロセスのロックを回収 (pid=${OLD_PID:-不明})"
  # 削除中に他プロセスが書き込むと rm が失敗しうる（release_lock と同じ理由）。
  # 失敗しても直後の mkdir が失敗して降りるので、ここは stderr を汚さないだけでよい
  rm -rf "$LOCK_DIR" 2>/dev/null
  mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi
if ! write_pid; then
  log "ロックへの PID 記録に失敗（他プロセスに回収された）ためスキップ"
  exit 0
fi
sleep 1
if [ "$(cat "$PID_FILE" 2>/dev/null || true)" != "$$" ]; then
  log "ロックの所有権が他プロセスに移ったためスキップ (所有者=$(cat "$PID_FILE" 2>/dev/null || echo 不明))"
  exit 0
fi
trap 'release_lock' EXIT

gh auth status >/dev/null 2>&1 || { log "gh 未認証またはオフライン"; exit 0; }

# ベースクローンを用意（開発当番とは別クローン。worktree の同時操作で衝突させないため）
if [ ! -d "$AUDIT_DIR/.git" ]; then
  mkdir -p "$(dirname "$AUDIT_DIR")"
  gh repo clone hiroky1983/game_collection "$AUDIT_DIR" >>"$LOG" 2>&1 || { log "clone 失敗"; exit 0; }
fi
# fetch の失敗時は続行しない。古い origin/main のまま worktree を作ると、経営判断も docs/ の
# 更新も古い状態を根拠にしてしまう（PR #163・CodeRabbit 指摘）
fetch_with_timeout "$AUDIT_DIR" || { log "fetch 失敗のため今回は見送り"; exit 0; }

# 1実行 = 1使い捨て worktree
RUNS_DIR="$HOME/.asobiba-audit/runs"
mkdir -p "$RUNS_DIR"
find "$RUNS_DIR" -maxdepth 1 -type d -name 'run-*' -mtime +3 | while read -r d; do
  case "$d" in
    "$RUNS_DIR"/run-*) git -C "$AUDIT_DIR" worktree remove --force "$d" >>"$LOG" 2>&1 || rm -rf "$d" ;;
  esac
done
git -C "$AUDIT_DIR" worktree prune >>"$LOG" 2>&1

RUN_DIR="$RUNS_DIR/run-$(date +%Y%m%d-%H%M%S)"
git -C "$AUDIT_DIR" worktree add --detach "$RUN_DIR" origin/main >>"$LOG" 2>&1 || { log "worktree 作成失敗"; exit 0; }
# 終了時に worktree を必ず消す（ローカル資源の規律 2・#822）。`ai-duty.sh` の cleanup_worktree と同じ考え方で、
# 3 日後の掃除を待たずにその回のうちに片付ける。ロックの解放より先に行う。消せなかった回は起動時の
# 3 日掃除に任せ、ログに残す。
cleanup_run() {
  git -C "$AUDIT_DIR" worktree remove --force "$RUN_DIR" >>"$LOG" 2>&1 || log "worktree の削除に失敗: ${RUN_DIR}（起動時の掃除で回収）"
  git -C "$AUDIT_DIR" worktree prune >>"$LOG" 2>&1
  release_lock
}
trap 'cleanup_run' EXIT

# 書き込み範囲を docs/ 配下に技術的に制限する（CodeRabbit指摘: プロンプトの指示だけに
# コード変更禁止を委ねるな、というセキュリティ指摘への対応）。GitHub Issue 本文や
# WebSearch の結果には信頼できない第三者の文言が混ざりうるため、万一プロンプト注入で
# エージェントが App/ や Packages/ を編集しようとしても、コミット時にこの pre-commit
# フックが拒否する。Issue へのコメント・ラベル操作等（gh コマンド経由）はこのフックの
# 対象外だが、コード変更という最大の実害はここで技術的に塞ぐ。
#   - worktree の `.git` は共通 gitdir を指す**ファイル**であり、`.git/hooks/` は
#     全 worktree（会長の作業ツリーや開発当番のworktreeも含む）で共有されている。
#     そこへ直接書くと、この監査当番の実行がリポジトリ全体のコミットを止めてしまう
#     （実際に手元で検証し、共有ディレクトリであることを確認した上でこの実装を避けた）。
#   - 代わりに `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0` で
#     `core.hooksPath` をこのプロセスの環境変数としてのみ上書きする。これは git が
#     コマンドラインの `-c` と同じ優先度で読む環境変数オーバーライドで、**ディスク上の
#     どのファイルにも書き込まない**。`claude` の子プロセス（Bash ツール経由の git
#     コマンド）にも環境変数として継承される。他の worktree・会長の作業ツリーには
#     一切影響しないことを実際に検証済み
AUDIT_HOOKS_DIR="$RUN_DIR/.audit-hooks"
mkdir -p "$AUDIT_HOOKS_DIR"
cat > "$AUDIT_HOOKS_DIR/pre-commit" <<'HOOK'
#!/bin/bash
# ai-audit-duty.sh が実行時に GIT_CONFIG_* 経由で有効化。docs/ 以外への変更を含む
# コミットを拒否する（このプロセスの実行中のみ有効。他の worktree には影響しない）。
set -uo pipefail
offending=$(git diff --cached --name-only | grep -v '^docs/' || true)
if [ -n "$offending" ]; then
  echo "監査当番は docs/ 配下しか変更できません（コードは読むだけ）。以下がその対象外です:" >&2
  echo "$offending" >&2
  exit 1
fi
exit 0
HOOK
chmod +x "$AUDIT_HOOKS_DIR/pre-commit"
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=core.hooksPath
export GIT_CONFIG_VALUE_0="$AUDIT_HOOKS_DIR"

# 入力フィルタ（Issue #164）: claude セッション内の `gh` を Scripts/duty-gh-shim/gh 経由にして、
# 第三者の本文が AI のコンテキストへ入る前に機械的に除去する。実装当番（ai-duty.sh）と同一の
# ラッパー・同一の理由。監査当番はむしろ Issue 本文とコメントを読むのが主業務なので、
# 未信頼の自由記述に触れる量は開発当番より多い。
#   - 置き場所は worktree の外（開発当番と同じ理由。ただしクローンは別なのでディレクトリも別）
#   - 効いていることを実測できなければ claude を起動しない（fail closed）
AUDIT_TRUSTED_ACTORS="${DUTY_TRUSTED_ACTORS:-hiroky1983}"
GH_SHIM_DIR="$HOME/.asobiba-audit/gh-shim"
install_gh_shim() {
  local src="$RUN_DIR/Scripts/duty-gh-shim" probe
  [ -f "$src/gh" ] && [ -f "$src/filter.jq" ] || { log "入力フィルタ: $src が見つからない"; return 1; }
  rm -rf "$GH_SHIM_DIR" 2>/dev/null
  mkdir -p "$GH_SHIM_DIR" && chmod 700 "$GH_SHIM_DIR" || return 1
  cp "$src/gh" "$src/filter.jq" "$GH_SHIM_DIR/" || return 1
  chmod +x "$GH_SHIM_DIR/gh" || return 1
  PATH="$GH_SHIM_DIR:$PATH" "$GH_SHIM_DIR/gh" --version >/dev/null 2>&1 \
    || { log "入力フィルタ: 素通しの確認に失敗"; return 1; }
  # ラッパーの横取り判定まで含めて実測する（filter.jq 単体の確認では引数の読み違いによる
  # 素通しを検知できない。ai-duty.sh 側のコメント参照）
  local stub="$GH_SHIM_DIR/.probe-gh" json="$GH_SHIM_DIR/.probe.json" args
  cat >"$stub" <<PROBE
#!/bin/bash
cat "$json"
PROBE
  chmod +x "$stub" || { rm -f "$stub"; return 1; }
  jq -nc '{number:1,title:"t",author:{login:"duty-shim-probe"},body:"DUTY-SHIM-LEAK",comments:[]}' >"$json" \
    || { rm -f "$stub" "$json"; log "入力フィルタ: プローブの作成に失敗"; return 1; }
  for args in "issue view 1" "-R o/r issue view 1" "--repo o/r pr list" "duty-shim-alias 1"; do
    # shellcheck disable=SC2086
    probe=$(DUTY_REAL_GH="$stub" "$GH_SHIM_DIR/gh" $args 2>/dev/null)
    case "$probe" in
      *DUTY-SHIM-LEAK*)
        rm -f "$stub" "$json"
        log "入力フィルタ: 第三者の本文が素通しした（gh ${args}）"
        return 1 ;;
    esac
  done
  jq -nc --arg a "${AUDIT_TRUSTED_ACTORS%%,*}" \
    '{number:1,title:"t",author:{login:$a},body:"DUTY-SHIM-KEEP",comments:[]}' >"$json" || { rm -f "$stub" "$json"; return 1; }
  probe=$(DUTY_REAL_GH="$stub" "$GH_SHIM_DIR/gh" issue view 1 2>/dev/null)
  rm -f "$stub" "$json"
  case "$probe" in
    *DUTY-SHIM-KEEP*) ;;
    *) log "入力フィルタ: 会長の本文まで除去されている"; return 1 ;;
  esac
  return 0
}
if ! install_gh_shim; then
  log "入力フィルタ（Issue #164）を用意できないため今回は起動しない"
  exit 0
fi

# 監査の対象窓: 前回の実行時刻（無ければ 24 時間前）以降に release/* と main へマージされた PR。
# 時刻は UTC の ISO 8601 で保存し、gh の `merged:>=` 検索にそのまま渡す。
STATE_DIR="$HOME/.asobiba-audit"
LAST_RUN_FILE="$STATE_DIR/last-run"
SINCE=$(cat "$LAST_RUN_FILE" 2>/dev/null || true)
case "$SINCE" in
  20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
  *) SINCE=$(date -u -v-24H '+%Y-%m-%dT%H:%M:%SZ') ;;
esac
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
# `gh` の失敗（レート制限・オフライン）と「本当に 0 件」を区別する（#822）。失敗した回は窓を進めず、
# 次回にその期間の PR をもう一度対象にする。
if ! MERGED_PRS=$(gh pr list -R hiroky1983/game_collection --state merged --limit 100 \
  --search "merged:>=$SINCE" --json number,title,baseRefName,mergedAt \
  --jq 'sort_by(.mergedAt) | .[] | "#\(.number) [\(.baseRefName)] \(.title)"' 2>>"$LOG"); then
  log "gh pr list に失敗したため今回は見送り（窓は $SINCE のまま）"
  exit 0
fi
if [ -z "$MERGED_PRS" ]; then
  log "監査対象なし（$SINCE 以降にマージされた PR が無い）。今回は起動しない"
  mkdir -p "$STATE_DIR" && echo "$NOW" >"$LAST_RUN_FILE" 2>/dev/null
  exit 0
fi
PR_COUNT=$(printf '%s\n' "$MERGED_PRS" | wc -l | tr -d ' ')

log "監査当番起動 (workdir=$RUN_DIR, gh_shim=$GH_SHIM_DIR, since=$SINCE, prs=$PR_COUNT)"
cd "$RUN_DIR" || exit 0
# Sonnet で起動する（会長指示 2026-09-18: 週間リミット逼迫のため恒久対応で全モデル Sonnet に固定。
# 2026-09-14 の「複雑なタスクは Fable で」は撤回）。
PATH="$GH_SHIM_DIR:$PATH" claude --model "${AUDIT_MODEL:-sonnet}" \
  --allowedTools "Bash,Read,Glob,Grep,WebFetch,WebSearch" \
  -p "$(cat "$RUN_DIR/Scripts/ai-audit-prompt.md")

（今回の監査対象）${SINCE} 〜 ${NOW}（UTC）にマージされた PR ${PR_COUNT} 本:
$MERGED_PRS" >>"$LOG" 2>&1
RC=$?
# 正常終了したときだけ窓を進める（異常終了した回の PR は次回もう一度対象にする）
if [ "$RC" -eq 0 ]; then mkdir -p "$STATE_DIR" && echo "$NOW" >"$LAST_RUN_FILE"; fi
log "監査当番終了 (exit=$RC)"
