#!/bin/bash
# 実装当番のローカル発火チェック。launchd から1時間おきに呼ばれる。
# 仕事（承認済み Issue / 未解決 CodeRabbit スレッド / レビュー未着の PR）がある時だけ claude を起動する。
# 作業は専用クローン（~/.asobiba-duty/）で行い、人間の作業ツリーとは衝突しない。
# セットアップ手順は docs/ai-devops.md の「実装ループ」参照。
set -uo pipefail

DUTY_DIR="$HOME/.asobiba-duty/game_collection"
LOCK_DIR="${TMPDIR:-/tmp}/asobiba-ai-duty.lock"
LOG="$HOME/Library/Logs/asobiba-ai-duty.log"
DUTY_FETCH_TIMEOUT="${DUTY_FETCH_TIMEOUT:-90}"  # 自己更新の fetch の上限秒数（テストから短縮できるよう外出し）
DUTY_FETCH_KILL_GRACE="${DUTY_FETCH_KILL_GRACE:-5}"  # SIGTERM / SIGKILL それぞれの猶予秒数（同上）
DUTY_LOCK_GRACE="${DUTY_LOCK_GRACE:-30}"  # PID 未書き込みのロックを「取得直後」とみなす秒数
DUTY_NOTIFY_STATE="${DUTY_NOTIFY_STATE:-$HOME/.asobiba-duty/last-notify}"  # 通知の連投防止の状態ファイル
DUTY_NOTIFY_INTERVAL="${DUTY_NOTIFY_INTERVAL:-86400}"  # 同じ対象を再通知しない秒数（既定 = 1日）
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

# DUTY_LOCK_GRACE は外部から差し替えられるため、0 以上の10進整数だけを通して既定値へ戻す。
# `[ "$AGE" -lt "$DUTY_LOCK_GRACE" ]` は非数値だと「整数式が必要」で**失敗（= 偽）**になり、
# 猶予の判定を素通りして取得直後の PID 未書き込みロックを回収してしまう
# （= 本来防いでいる多重起動が起きる。PR #173 の CodeRabbit 指摘）
case "$DUTY_LOCK_GRACE" in
  ''|*[!0-9]*)
    log "DUTY_LOCK_GRACE=$DUTY_LOCK_GRACE は 0 以上の整数でないため既定値 30 を使う"
    DUTY_LOCK_GRACE=30
    ;;
esac

# シミュレータの後片付け（Issue #100）。当番が動作確認のために起動したシミュレータだけを落とし、
# 実行前から起動していたもの（= 会長が使用中の可能性がある）には触らない差分方式。
#   - EXIT トラップから呼ぶ。claude が異常終了しても launchd に止められても必ず走らせるため
#     （正常終了時だけの後片付けだと、落ちた回のシミュレータが残り続ける）
#   - 実行前の状態を記録**できたとき**しか片付けない。記録に失敗した状態で片付けると
#     「起動中のすべてが当番のもの」と誤認して会長のシミュレータを落としてしまう
#   - **既知の限界**: 差分は「claude を起動する直前」のスナップショットとの比較なので、当番の実行中
#     （長いと1時間近い）に会長が新しく起動したシミュレータは「当番が起動した」と見えて落ちる。
#     Issue #100 の受け入れ条件が「当番の実行中に新しく起動されたものだけを落とす差分方式」と
#     定めているため実装はこれに従う。当番の起動したデバイスだけを厳密に特定するには当番自身に
#     UDID を記録させるしかないが、それを忘れることこそが本スクリプトの存在理由なので backstop に
#     はできない。実害が出たら「あそびば以外のアプリが前面にあるデバイスは落とさない」等の
#     追加条件を検討する
SIMS_BEFORE=""
SIMS_TRACKED=0

booted_sims() {
  xcrun simctl list devices booted -j 2>/dev/null \
    | jq -r '.devices[][]? | select(.state == "Booted") | .udid' 2>/dev/null
}

# 失敗（xcrun/jq が使えない等）は黙って握りつぶさずログに残す。ここが崩れると後片付けが
# 静かに効かなくなり、シミュレータが溜まり続ける（Issue #100 の実害そのもの）
capture_sims_before() {
  local raw
  raw=$(xcrun simctl list devices booted -j 2>/dev/null) || { log "後片付け: シミュレータ一覧の取得に失敗（simctl）。後片付けは行わない"; return 0; }
  SIMS_BEFORE=$(printf '%s' "$raw" | jq -r '.devices[][]? | select(.state == "Booted") | .udid' 2>/dev/null | tr '\n' ' ') \
    || { log "後片付け: シミュレータ一覧の解析に失敗（jq）。後片付けは行わない"; SIMS_BEFORE=""; return 0; }
  SIMS_TRACKED=1
}

cleanup_simulators() {
  [ "$SIMS_TRACKED" -eq 1 ] || return 0
  local u
  for u in $(booted_sims); do
    case " $SIMS_BEFORE " in
      *" $u "*) continue ;;  # 実行前から起動していた = 触らない
    esac
    xcrun simctl shutdown "$u" >>"$LOG" 2>&1 && log "後片付け: シミュレータ $u を shutdown"
  done
  # Simulator.app 自体は終了しない。実行前のシミュレータがゼロでも、当番の実行中（最大1時間）に
  # 会長が Simulator.app を開いた可能性があり、`killall` はそれを問答無用で殺す（PR #110 の
  # CodeRabbit 指摘・Major）。会長の訴え（PC が重い）の原因は起動中のシミュレータであって
  # デバイスを持たない Simulator.app ではないため、落とす必要も無い
}

# 会長への通知（Issue #132）。稟議（ringi:pending）と承認待ち（未承認の ai:proposed）はどちらも
# **会長にしか進められない**のに、会長に届く通知が1つも無かった。当番は会長アカウントのトークンで
# コメントするため、GitHub は「自分自身の操作」とみなして通知を出さない（#120 で確認済みの制約）。
# 起案しても会長の受信箱には何も起きず、決裁待ちがそのまま滞留する（#128 は約32時間放置され、
# その間ずっと仕事ゼロの当番が毎時起動していた）。launchd が会長の Mac の GUI セッションで動く前提を
# そのまま使い、追加の権限・費用・外部サービスなしに届く macOS のローカル通知で知らせる。
#   - 通知は EXIT トラップから出す。早期 exit（仕事なし）でも claude が異常終了しても必ず出すため。
#     決裁待ちだけが残っている「仕事なし」の回こそ通知の必要性が高い
#   - 連投防止: 対象 Issue の集合が同じなら DUTY_NOTIFY_INTERVAL（既定1日）に1回まで。
#     集合が変われば即通知する（新しい稟議の起案を丸1日待たせないため）
#   - 対象が0件なら何もしない（空振り時は無音）
#   - osascript に渡すのは **Issue 番号だけ**にする。タイトルを埋め込むと AppleScript の文字列を
#     壊すうえ、このリポジトリは PUBLIC で第三者も Issue を立てられるため注入の経路になる
NOTIFY_RINGI=""
NOTIFY_APPROVAL=""
NOTIFY_READY=0

# 通知対象の収集。gh が失敗したときは NOTIFY_READY を立てないので通知しない（黙って0件扱いにすると
# 「対象なし」と区別が付かず、稟議があるのに無音になる）
collect_notify_targets() {
  # --limit を省略すると 30 件で打ち切られ、超えた分が**黙って**通知から漏れる（PR #142 の
  # CodeRabbit 指摘）。滞留が増えたときほど漏れるという最悪の壊れ方をするので上限を明示する
  local ringi approval
  ringi=$(gh issue list -R hiroky1983/game_collection --label "ringi:pending" --state open --limit 200 \
    --json number --jq '[.[].number] | map(tostring) | join(" ")' 2>/dev/null) || return 0
  # 承認待ち = ai:proposed のうち会長のハンコがまだ無いもの。着手済み・外部イベント待ち（blocked）と、
  # 上の決裁待ちに既に出ているものは重複するので除く
  approval=$(gh issue list -R hiroky1983/game_collection --label "ai:proposed" --state open --limit 200 \
    --json number,labels \
    --jq '[.[] | ([.labels[].name]) as $l
          | select(($l | index("ai:approved")) == null and ($l | index("ai:in-progress")) == null
                   and ($l | index("blocked")) == null and ($l | index("ringi:pending")) == null)
          | .number] | map(tostring) | join(" ")' 2>/dev/null) || return 0
  NOTIFY_RINGI="$ringi"
  NOTIFY_APPROVAL="$approval"
  NOTIFY_READY=1
}

# 番号の羅列を "#128 #106" の形にする。tr -cd で数字と空白以外を落としてあるので osascript に渡しても安全
hash_numbers() {
  local n out=""
  for n in $1; do out="$out #$n"; done
  printf '%s' "${out# }"
}

# 改行・タブは先に空白へ寄せる。いきなり tr -cd で落とすと、収集側の出力が複数行になったときに
# "128" と "106" が "128106" という存在しない番号に化ける（PR #142 の CodeRabbit 指摘）
sanitize_numbers() {
  printf '%s' "$1" | tr '\n\t' '  ' | tr -cd '0-9 ' | tr -s ' ' | sed 's/^ //; s/ $//'
}

notify_pending() {
  [ "$NOTIFY_READY" -eq 1 ] || return 0
  local ringi approval key now last_key last_at body count
  ringi=$(sanitize_numbers "$NOTIFY_RINGI")
  approval=$(sanitize_numbers "$NOTIFY_APPROVAL")
  [ -n "$ringi$approval" ] || return 0

  key="ringi=$ringi;approval=$approval"
  now=$(date +%s)
  if [ -f "$DUTY_NOTIFY_STATE" ]; then
    last_key=$(sed -n '1p' "$DUTY_NOTIFY_STATE" 2>/dev/null)
    last_at=$(sed -n '2p' "$DUTY_NOTIFY_STATE" 2>/dev/null)
    case "${last_at:-}" in ''|*[!0-9]*) last_at=0 ;; esac
    if [ "$key" = "${last_key:-}" ] && [ "$((now - last_at))" -lt "$DUTY_NOTIFY_INTERVAL" ]; then
      return 0
    fi
  fi

  count=0
  body=""
  if [ -n "$ringi" ]; then
    count=$((count + $(printf '%s' "$ringi" | wc -w)))
    body="決裁待ち(ringi:pending): $(hash_numbers "$ringi")"
  fi
  if [ -n "$approval" ]; then
    count=$((count + $(printf '%s' "$approval" | wc -w)))
    [ -n "$body" ] && body="$body / "
    body="${body}承認待ち(ai:approved を付けるだけ): $(hash_numbers "$approval")"
  fi

  osascript -e "display notification \"$body\" with title \"あそびば: 会長の操作待ち ${count}件\"" >/dev/null 2>&1 || {
    log "通知: osascript に失敗したため見送り（対象: $body）"
    return 0
  }
  mkdir -p "$(dirname "$DUTY_NOTIFY_STATE")" 2>/dev/null
  printf '%s\n%s\n' "$key" "$now" >"$DUTY_NOTIFY_STATE" 2>/dev/null
  log "通知: 会長へ ${count}件（$body）"
}

# 自己更新: launchd が起動するのは会長の作業ツリー（~/myspace/game_collection）の本ファイルであり、
# main へマージしただけでは反映されない。会長が git pull するまで旧版が動き続け、修正済みの
# 発火条件が効かないまま空振り起動を繰り返す（2026-08-12: #73 の blocked 除外がこの理由で効かず、
# 10分おきに当番が空振り起動していた）。会長の手作業に依存せず、当番専用クローンから
# origin/main の最新版を取り出して実行し直す。
#   - 取得元は当番専用クローンのみ。会長の作業ツリーには一切触れない（別セッションとの競合回避）
#   - ロック取得より **前** に行う。exec は PID を変えないため、ロック取得後に exec すると
#     再入した自分自身を「前回実行中」と誤認して以後永久にスキップしてしまう
#   - 取り出し先は共有 /tmp ではなく所有者専用ディレクトリ（700）。共有 /tmp だとファイル名が
#     公開済みの blob ハッシュから予測でき、同一マシンの第三者が構文の通る偽スクリプトを先回りで
#     置くと、それをそのまま exec してしまう（PR #75 の CodeRabbit 指摘・Critical）。
#     既存ファイルの内容も信用せず、毎回 origin/main から取り出し直して照合する
#   - 実体は blob ハッシュ名で保存する。実行中の旧インスタンスが同じファイルを読んでいても
#     内容が同一で、置換も mv（原子的・inode 差し替え）なので破損しない
#   - この fetch はロックの外側で走るため、ハングすると launchd の10分間隔でプロセスが
#     積み上がる（ロックを取れていないので後続も素通りして同じ場所で詰まる）。
#     macOS には timeout(1) が無いので自前で見張り、上限を超えたら自己更新を諦めて先へ進む
self_update() {
  [ -n "${DUTY_SELF_UPDATED:-}" ] && return 0
  [ -d "$DUTY_DIR/.git" ] || return 0
  local gpid waited=0
  GIT_TERMINAL_PROMPT=0 git -C "$DUTY_DIR" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
    fetch origin --prune --quiet >>"$LOG" 2>&1 &
  gpid=$!
  while [ "$waited" -lt "$DUTY_FETCH_TIMEOUT" ] && kill -0 "$gpid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$gpid" 2>/dev/null; then
    # SIGTERM で死なない fetch を無制限に wait すると、タイムアウトを設けた意味が無くなる。
    # この関数はロックの**外側**で走るため、ここで詰まると launchd の毎時起動がそのまま
    # 積み上がる（後続もロックを取れていないので同じ場所で詰まる）。
    # SIGTERM → 猶予 → SIGKILL → 猶予 と escalate し、それでも終了を確認できなければ
    # wait せずに諦める（残る子プロセスはゾンビだが、当番の進行を止めるよりはよい）
    local sig grace
    for sig in TERM KILL; do
      kill -"$sig" "$gpid" 2>/dev/null
      grace=0
      while [ "$grace" -lt "$DUTY_FETCH_KILL_GRACE" ] && kill -0 "$gpid" 2>/dev/null; do
        sleep 1
        grace=$((grace + 1))
      done
      kill -0 "$gpid" 2>/dev/null || break
    done
    if kill -0 "$gpid" 2>/dev/null; then
      log "自己更新: fetch (pid=$gpid) が SIGKILL でも終了しないため wait せずに見送り"
      return 0
    fi
    wait "$gpid" 2>/dev/null
    log "自己更新: fetch が ${DUTY_FETCH_TIMEOUT} 秒を超えたため見送り"
    return 0
  fi
  if ! wait "$gpid" 2>/dev/null; then
    log "自己更新: fetch に失敗したため見送り"
    return 0
  fi
  local oid cache fresh tmp
  oid=$(git -C "$DUTY_DIR" rev-parse "origin/main:Scripts/ai-duty.sh" 2>/dev/null) || return 0
  [ -n "$oid" ] || return 0
  cache="$HOME/.asobiba-duty/bin"
  mkdir -p "$cache" && chmod 700 "$cache" || return 0
  # 古いキャッシュの掃除。このあと作る $fresh より前に行うので、更新対象を消してしまうことはない
  find "$cache" -maxdepth 1 -type f -name 'ai-duty-*.sh' -mtime +7 -delete 2>/dev/null
  fresh="$cache/ai-duty-${oid}.sh"
  tmp=$(mktemp "$cache/ai-duty-XXXXXX") || return 0
  if ! git -C "$DUTY_DIR" show "origin/main:Scripts/ai-duty.sh" >"$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
    rm -f "$tmp"; return 0
  fi
  # 壊れたスクリプトへ乗り換えて当番が止まるのを防ぐ
  if ! bash -n "$tmp" 2>/dev/null; then
    rm -f "$tmp"; log "自己更新: origin/main の ai-duty.sh が構文エラーのため見送り"; return 0
  fi
  if cmp -s "$tmp" "$0"; then rm -f "$tmp"; return 0; fi
  mv -f "$tmp" "$fresh" || { rm -f "$tmp"; return 0; }
  log "自己更新: origin/main の ai-duty.sh へ切り替え (実行中=$0, blob=${oid:0:7})"
  export DUTY_SELF_UPDATED=1
  exec /bin/bash "$fresh" "$@"
}
# 会長の書き込みを見分けるための共通 jq 定義（仕事5・仕事8 が使う）。
# 当番(AI)・経営企画室・会長はすべて同じ `hiroky1983` トークンで投稿するため author では区別できず、
# 「自社が書いたコメント」を本文のマーカーで除外して最後の会長コメントを取り出す。
#   - 許可リスト外の author（coderabbitai・第三者）は無視する（#68: 自動プランで空振り起動）
#   - `<!-- ai-management-` で始まるコメントは経営企画室（Scripts/ai-management-duty.sh・日次）の
#     分析/リマインドなので除外する。除外しないと経営企画室が1本置くたびに開発当番が「会長の着信」と
#     誤認して毎時空振りする（#168。#120 と同じ失敗モードが経営企画室の常設化で再発した）。
#     マーカーは経営企画室側の重複防止用として ai-management-prompt.md が先頭行に必須化済み
# 変数に出しているのは、同じ定義を Scripts/tests/test-ai-duty-detect.sh から評価するため。
DUTY_JQ_COMMENT_LIB='
def last_owner_body($actors):
  [.comments.nodes[]
   | select((.author.login // "") as $l | ($actors | index($l)) != null)
   | select(((.body // "") | startswith("<!-- ai-management-")) | not)
   | (.body // "")] | last // "";

def is_ringi_reply($actors):
  last_owner_body($actors) as $b
  | $b != ""
    and (($b | contains("【要決裁】")) | not)
    and (($b | contains("決裁反映")) | not);

def is_proposed_reply($actors):
  ([.labels.nodes[].name]) as $l
  | ($l | index("ai:approved")) == null
    and ($l | index("ai:in-progress")) == null
    and ($l | index("blocked")) == null
    and (last_owner_body($actors) as $b
         | $b != ""
           and (($b | startswith("企画議論")) | not)
           and (($b | contains("【要決裁】")) | not)
           and (($b | contains("決裁反映")) | not));
'

# テスト用の入口: 関数定義だけ読み込んで個別に検証できるようにする
# （Scripts/tests/test-ai-duty-notify.sh・test-ai-duty-detect.sh。source されたときだけ効く）
if [ -n "${DUTY_LIB_ONLY:-}" ]; then return 0 2>/dev/null || exit 0; fi

self_update "$@"

# 多重起動防止（前回の当番がまだ働いていたらスキップ。死んだプロセスのロックは回収）
#   mkdir から PID_FILE の書き込みまでには僅かな隙があり、その間に来た次のプロセスが
#   「PID が読めない = 停止済み」と誤判定して有効なロックを奪うと当番が二重に走る
#   （PR #163 で ai-management-duty.sh 側を直した CodeRabbit 指摘と同一構造・Issue #165）。
#   多重起動を防いでいるのはこのロックだけなので、破れると稼働中の当番の Issue から別の当番が
#   ai:in-progress を剥がす・同じ Issue に二重着手する・EXIT トラップが他方のシミュレータを
#   落とす、といった競合が起きる（ai-duty-prompt.md 2-c は「多重起動はロックで防がれている」を
#   前提に、30分以上更新の無い ai:in-progress を孤児と断定して回収する）。対策は3点:
#     1. PID が読めないロックは DUTY_LOCK_GRACE 秒だけ「取得直後」とみなして回収しない
#     2. PID_FILE を書いたあと読み直し、自分のものでなければ降りる（競合したとき、最後に
#        書いた1プロセスだけが残る）。**回収した回に限らず必ず確認する**のが要点で、
#        「mkdir で新規に取れたのだから競合していない」は成り立たない: 回収経路に入った
#        プロセスは猶予の判定を済ませており、その後の `rm -rf` は**誰が今ロックを
#        持っていようと消す**。新規取得したプロセスのロックがその `rm -rf` で消され、
#        回収側が取り直すと、確認を省いた新規取得側と回収側の両方が走る
#        （40 並行のストレステストで3〜5プロセスが同時に当選することを実測。確認を
#        無条件にすると常に1プロセスに戻る）
#     3. EXIT トラップは自分が所有者のときだけロックを削除する（競合した相手のロックを
#        巻き添えにしない）。cleanup_simulators / notify_pending は所有権と無関係に走らせる
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
  # 削除中に他プロセスが同じディレクトリへ書き込むと rm が "Directory not empty" で失敗しうる
  # （40 並行のストレステストで観測）。EXIT トラップから呼ばれるので launchd の stderr へは
  # 出さず、残ってもそのロックは PID 未書き込み扱いで次回の猶予超過に回収される
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
    # DUTY_LOCK_GRACE と同じ理由で、比較が失敗すると回収する側に落ちてしまう
    case "$AGE" in ''|*[!0-9]*) AGE="" ;; esac
    if [ -z "$AGE" ] || [ "$AGE" -lt "$DUTY_LOCK_GRACE" ]; then
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
# 所有権の確認は新規取得・回収のどちらの経路でも必ず行う（上のコメント 2. の理由）。
# sleep は競合相手が PID を書き終えるのを待つためのもので、launchd の毎時起動が
# 1秒遅れるだけの代償で二重当選を防ぐ
sleep 1
if [ "$(cat "$PID_FILE" 2>/dev/null || true)" != "$$" ]; then
  log "ロックの所有権が他プロセスに移ったためスキップ (所有者=$(cat "$PID_FILE" 2>/dev/null || echo 不明))"
  exit 0
fi
trap 'cleanup_simulators; notify_pending; release_lock' EXIT

gh auth status >/dev/null 2>&1 || { log "gh 未認証またはオフライン"; exit 0; }

# 会長の操作待ち（決裁・承認）を先に集める。以降のどこで exit しても EXIT トラップから通知が出る
collect_notify_targets

# 仕事1: 承認済みで未着手の Issue
# ai:in-progress（着手済み）と ringi:pending（会長の決裁待ち = 当番には進められない）は除外する。
# 除外しないと、成果物を出して決裁待ちになった Issue を毎時拾い直して同じ作業を繰り返す。
# blocked（Issue 自身が定めた着手条件が未達 = 外部イベント待ち）も同じ理由で除外する。
# 例: 「v1.1.0 リリースから2週間経過後」のような条件は当番の努力では満たせないため、
# 除外しないと条件成立まで毎時空振りで当番を起動し続けることになる（#54 で実際に発生）。
APPROVED=$(gh issue list -R hiroky1983/game_collection --label "ai:approved" --state open \
  --json number,labels \
  --jq '[.[] | ([.labels[].name]) as $l
        | select(($l | index("ai:in-progress")) == null and ($l | index("ringi:pending")) == null
                 and ($l | index("blocked")) == null)] | length' 2>/dev/null || echo 0)

# 仕事2: オープン PR 上の未解決 CodeRabbit スレッド
# 上限 50 PR × 100 スレッド（個人リポジトリの規模では実質全件。超えたら要ページング対応）
THREADS=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    pullRequests(states: OPEN, first: 50) {
      nodes {
        reviewThreads(first: 100) {
          nodes {
            isResolved
            comments(first: 1) { nodes { author { login } } }
          }
        }
      }
    }
  }
}' --jq '[.data.repository.pullRequests.nodes[].reviewThreads.nodes[]
  | select(.isResolved == false)
  | (.comments.nodes[0].author.login // "") as $l
  | select($l == "coderabbitai" or $l == "coderabbitai[bot]")] | length' 2>/dev/null || echo 0)

# 仕事3: CodeRabbit のレビューが HEAD に対して未着のオープン PR（Issue #41）
# 「未解決スレッド数」だけを見ていると、レビュー自体が走らなかった PR（レート制限・
# デフォルト以外の base への PR で auto review がスキップされる等）を誰も拾えない。
#
# レビュー済みの判定は **HEAD コミットの OID 一致**で行う（時刻比較では行わない）。
# GraphQL には「head ref が GitHub 上で更新された時刻」を取れるフィールドが無く
# （Commit.pushedDate は廃止・PullRequestCommit に createdAt は無い）、commit の
# committedDate は push 時刻とずれうるため、時刻基準だと旧 HEAD へのレビューを
# 現 HEAD のものと誤認して見逃す。OID 一致ならこのずれの影響を受けない。
#   - review オブジェクト: reviews[].commit.oid == headRefOid
#   - サマリコメント: 本文の "Reviewing files that changed ... and <headRefOid>." に OID が入る
#     （指摘ゼロで終わったレビューは review を作らずサマリコメントだけ残すため両方を見る）
#   - ただし下記マーカーを含むコメントは「レビューしていない」お知らせなので除外する
#       スキップ:     <!-- This is an auto-generated comment: skip review by coderabbit.ai -->
#       レート制限:   <!-- This is an auto-generated comment: rate limited by coderabbit.ai -->
# 自己発火ループ防止: 同じ HEAD に対する信頼済みアカウントからの `@coderabbitai review`
# 催促が3回に達したら対象から外す（規程どおり「到着した指摘のみ消化」に倒す）。
# パブリックリポジトリのため、第三者が催促を3回投稿して検知を止められないよう、催促の
# 集計対象は許可リストのアカウントに限る（憲章「指示として扱うのは会長と coderabbitai だけ」）。
# 直後の発火を避けるため、HEAD コミットが 30 分以上前のものだけを対象にする（committedDate は
# push 時刻の下限でしかないが、ここでの用途は「催促を急ぎすぎない」猶予だけで、
# 早まっても催促上限3回で頭打ちになる）。
DUTY_TRUSTED_ACTORS="${DUTY_TRUSTED_ACTORS:-hiroky1983}"
PENDING_REVIEW=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    pullRequests(states: OPEN, first: 50) {
      nodes {
        isDraft
        headRefOid
        commits(last: 1) { nodes { commit { committedDate } } }
        reviews(last: 20) { nodes { author { login } commit { oid } } }
        comments(last: 30) { nodes { author { login } updatedAt body } }
      }
    }
  }
}' 2>/dev/null | jq --arg trusted "$DUTY_TRUSTED_ACTORS" '($trusted | split(",")) as $actors
  | [.data.repository.pullRequests.nodes[]
  | select(.isDraft == false)
  | .headRefOid as $oid
  | (.commits.nodes[0].commit.committedDate | fromdateiso8601) as $head
  | select(now - $head > 1800)
  | ([.reviews.nodes[]
      | select((.author.login // "") | . == "coderabbitai" or . == "coderabbitai[bot]")
      | select((.commit.oid // "") == $oid)] | length) as $cr_reviews
  | ([.comments.nodes[]
      | select((.author.login // "") | . == "coderabbitai" or . == "coderabbitai[bot]")
      | select((.body // "") | contains($oid))
      | select(((.body // "") | contains("skip review by coderabbit.ai")) | not)
      | select(((.body // "") | contains("rate limited by coderabbit.ai")) | not)] | length) as $cr_comments
  | select($cr_reviews + $cr_comments == 0)
  | ([.comments.nodes[]
      | (.author.login // "") as $a
      | select($actors | index($a))
      | select((.updatedAt | fromdateiso8601) >= $head)
      | select((.body // "") | contains("@coderabbitai review"))] | length) as $nudges
  | select($nudges < 3)] | length' 2>/dev/null || echo 0)

# 仕事4: コンフリクトで滞留しているオープン PR（誰のトリガーにも掛からず放置される穴の解消）
CONFLICTS=$(gh pr list -R hiroky1983/game_collection --state open --json mergeable \
  --jq '[.[] | select(.mergeable == "CONFLICTING")] | length' 2>/dev/null || echo 0)

# 仕事5: 決裁コメントの着信（ringi:pending の Issue に決裁スレッド以外の新規コメントが付いたら
# 会長の決裁着信の可能性として当番を起こす。判定と反映は当番エージェントが行う）
# 注: 当番(AI)・経営企画室のコメントも会長と同じアカウント(hiroky1983)で投稿されるため author では
#     区別できない。よって「最後の会長コメント（= 自社のマーカーが付かないコメント）が決裁スレッド
#     (【要決裁】)でも反映記録(決裁反映)でもない」ことを検知条件とする。判定は上の
#     DUTY_JQ_COMMENT_LIB の is_ringi_reply（除外の内訳と経緯もそちらのコメント参照）。
RINGI_REPLIES=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    issues(states: OPEN, labels: ["ringi:pending"], first: 20) {
      nodes {
        number
        comments(last: 20) { nodes { body author { login } } }
      }
    }
  }
}' 2>/dev/null | jq --arg trusted "$DUTY_TRUSTED_ACTORS" "$DUTY_JQ_COMMENT_LIB"'($trusted | split(",")) as $actors
  | [.data.repository.issues.nodes[]
  | select(is_ringi_reply($actors))] | length' 2>/dev/null || echo 0)

# 仕事6: マージ可能なのに放置されている PR（CLEAN かつ auto-merge 未設定）
# 「完成したのに誰もマージしない」滞留（PR #58 で実際に発生）の検知
STALLED=$(gh pr list -R hiroky1983/game_collection --state open --json mergeStateStatus,autoMergeRequest \
  --jq '[.[] | select(.mergeStateStatus == "CLEAN") | select(.autoMergeRequest == null)] | length' 2>/dev/null || echo 0)

# 仕事7: App Store で公開済みなのに main へ未マージの release ブランチ
# 規程（ai-devops.md）では「公開後に release/vX.Y.Z → main をマージしタグを打つ」のは AI の責務だが、
# その起点はリリース Issue への会長の「公開された」コメントしかなく、Issue が閉じられると
# どのトリガーにも掛からず宙に浮く（#68 が審査提出の時点で close され、実際にこの状態になった）。
# 会長の申告を待たず App Store の公開バージョン（iTunes Lookup API）を直接見て、release ブランチの
# バージョンに追いついたら当番を起こす。main へ取り込み済みなら ahead_by == 0 になり再発火しない。
DUTY_APP_ID="${DUTY_APP_ID:-6781719499}"
RELEASED=0
REL_BRANCH=$(gh api "repos/hiroky1983/game_collection/git/matching-refs/heads/release/v" \
  --jq '.[].ref | sub("^refs/heads/";"")' 2>/dev/null | sort -V | tail -1)
if [ -n "${REL_BRANCH:-}" ]; then
  AHEAD=$(gh api "repos/hiroky1983/game_collection/compare/main...$REL_BRANCH" --jq '.ahead_by' 2>/dev/null || echo 0)
  if [ "${AHEAD:-0}" -gt 0 ]; then
    STORE_VER=$(curl -sf --max-time 10 "https://itunes.apple.com/lookup?id=${DUTY_APP_ID}&country=jp" 2>/dev/null \
      | jq -r '.results[0].version // empty' 2>/dev/null)
    REL_VER="${REL_BRANCH#release/v}"
    # 公開バージョン >= release ブランチのバージョン（= 世に出た）なら仕事あり
    if [ -n "${STORE_VER:-}" ] \
      && [ "$(printf '%s\n%s\n' "$REL_VER" "$STORE_VER" | sort -V | tail -1)" = "$STORE_VER" ]; then
      RELEASED=1
    fi
  fi
fi

# 仕事8: 企画議論の着信（未承認の ai:proposed Issue に会長がコメントしたら経営企画室が応答する）
# 決裁検知（仕事5）は ringi:pending しか見ておらず、提案段階の議論は誰も拾わなかった穴の解消。
# 承認済み・着手済み・blocked のものは他のフローが担当するため除外。
# 応答側は必ず「企画議論」で始まるコメントを返す（それが再検知を止める目印になる）。
# 当番も会長アカウントのトークンでコメントするため投稿者では AI と会長を区別できない。そのため
# 接頭辞は返信だけでなく、当番がこの種の Issue に投稿する記録コメント（保留・見送り等）にも必須。
# 規程は ai-duty-prompt.md 1-e-3（#120: #79 の保留記録がマーカー無しで毎時の空振り起動を生んだ）。
# 経営企画室のコメント（`<!-- ai-management-` 始まり）の除外は DUTY_JQ_COMMENT_LIB 側で行う（#168）。
PROPOSED_REPLIES=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    issues(states: OPEN, labels: ["ai:proposed"], first: 20) {
      nodes {
        number
        labels(first: 10) { nodes { name } }
        comments(last: 20) { nodes { body author { login } } }
      }
    }
  }
}' 2>/dev/null | jq --arg trusted "$DUTY_TRUSTED_ACTORS" "$DUTY_JQ_COMMENT_LIB"'($trusted | split(",")) as $actors
  | [.data.repository.issues.nodes[]
  | select(is_proposed_reply($actors))] | length' 2>/dev/null || echo 0)

# 仕事9: 孤児化した ai:in-progress の回収（Issue #83）
# 当番が着手直後に異常終了すると ai:in-progress が残留し、その Issue は仕事1の集計から
# 恒久的に外れて誰も着手できなくなる（#80 で発生。12:07 の実行が着手直後に死亡し約2.5時間滞留）。
#
# 誤検知ガードは2重:
#   1) ロック — ここに到達している時点で他の当番は動いていない。生きている先行プロセスが
#      あればロック取得の段階で既に exit 済みで、この行は実行されない。つまり
#      「ロックが存在せず（= 当番が動いていない）」という条件は到達自体が保証している。
#      逆に言うと、実行中の当番が長時間かけて実装している Issue は、次回の launchd 起動が
#      ロックで弾かれるため対象にならない。
#   2) 経過時間 — 最終更新から30分以上のものだけを対象にする。着手宣言・進捗コメント・
#      ラベル操作はいずれも updatedAt を更新するため、生きている作業は時間切れにならない。
#   3) 成果物 — オープン PR に紐づいている Issue（PR 本文の `Closes #N`）は除外する。
#      実装が PR まで到達していれば孤児ではなく、ラベルは PR のマージ（= Issue の close）で
#      自然に片付く。除外しないと、当番が「PR があるのでラベルは残す」と正しく判断するたびに
#      次の毎時起動でまた同じ Issue を拾い、マージされるまで空振りが続く。
DUTY_ORPHAN_MIN_AGE="${DUTY_ORPHAN_MIN_AGE:-1800}"  # 孤児とみなす無更新の秒数（テストから短縮できるよう外出し）
LINKED_ISSUES=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    pullRequests(states: OPEN, first: 50) {
      nodes { closingIssuesReferences(first: 10) { nodes { number } } }
    }
  }
}' --jq '[.data.repository.pullRequests.nodes[].closingIssuesReferences.nodes[].number]' 2>/dev/null)
# 取得に失敗したら「全部が紐づいている」とみなすのではなく空集合に倒すが、その場合でも
# 経過時間ガードが効くため、当番が起きて状況を確認するだけで実害は無い
LINKED_ISSUES="${LINKED_ISSUES:-[]}"
ORPHANS=$(gh issue list -R hiroky1983/game_collection --label "ai:in-progress" --state open \
  --json number,updatedAt 2>/dev/null \
  | jq --argjson age "$DUTY_ORPHAN_MIN_AGE" --argjson linked "$LINKED_ISSUES" \
     '[.[] | . as $i
           | select(($i.updatedAt | fromdateiso8601) < (now - $age))
           | select(($linked | index($i.number)) == null)] | length' 2>/dev/null || echo 0)
ORPHANS="${ORPHANS:-0}"

# 仕事10: マージ済み PR のブランチに取り残されたコミット（Issue #100）
# PR がマージされた後に同じブランチへ push すると、そのコミットはどの PR にも載らないまま
# 取り残される。レビューもされず main にも入らないのに、ローカルには「実装した」痕跡だけが残るため
# 誰も気づけない（481072e が実際にこれで失われ、シミュレータの後片付けが2日間効いていなかった）。
# 検知は「マージ済み PR の head ブランチがまだ存在し、その変更が **base にも main にも入っていない**」で行う。
#   - 判定は `git cherry`（patch-id 比較）。SHA の一致ではなく**内容**で見るため、あとから別 PR で
#     同じ変更が入り直した場合は自動的に検知が止む（実際 PR #20 のブランチに残る 57b90dd は
#     内容が main に入り直しており、SHA 比較だと永久に鳴り続けるが patch-id なら鳴らない）
#   - base と main の両方を見る: base だけだと未公開の release ブランチ向け PR がすべて
#     「main に無い」で誤検知し、main だけだと release ブランチに積んだ正規のコミットが誤検知される
#   - 同じブランチにオープン PR があるなら、そのコミットはレビュー対象なので孤児ではない
#   - ローカル git で判定する（self_update で fetch 済み）。GitHub の compare API だと PR 1本につき
#     1リクエストかかって全件走査できず、検知窓から外れた古い取り残しを永久に見逃す
#     （実際 481072e は PR #65 = 43本前で、直近20件の窓では捕まらなかった）
#   - 回収時に内容そのままの cherry-pick をしないなら（別実装で作り直した等）patch-id が変わって
#     鳴り続けるため、回収し終えたら**そのブランチを削除する**のが終了条件
#   - 走査対象はマージ済み PR の直近1000件（`gh pr list` はこの件数までページングする）。
#     現在のマージ済み PR は60件で全件を覆う。ここを超えたら古い方から検知漏れになるため、
#     そのときはページングを明示した実装へ切り替える
ORPHAN_COMMITS=0
if [ -d "$DUTY_DIR/.git" ]; then
  OPEN_PR_HEADS=$(gh pr list -R hiroky1983/game_collection --state open --json headRefName --jq '.[].headRefName' 2>/dev/null || true)
  while IFS=$'\t' read -r H B; do
    [ -n "${H:-}" ] && [ -n "${B:-}" ] || continue
    printf '%s\n' "$OPEN_PR_HEADS" | grep -qxF "$H" && continue   # オープン PR がある = レビュー対象
    # ブランチ削除済み（= 回収済み）や base ブランチ削除済みの PR はここで落ちる
    git -C "$DUTY_DIR" rev-parse --verify -q "refs/remotes/origin/$H" >/dev/null || continue
    git -C "$DUTY_DIR" rev-parse --verify -q "refs/remotes/origin/$B" >/dev/null || continue
    NOT_IN_BASE=$(git -C "$DUTY_DIR" cherry "refs/remotes/origin/$B" "refs/remotes/origin/$H" 2>/dev/null | awk '$1 == "+" { print $2 }')
    [ -n "$NOT_IN_BASE" ] || continue
    NOT_IN_MAIN=$(git -C "$DUTY_DIR" cherry refs/remotes/origin/main "refs/remotes/origin/$H" 2>/dev/null | awk '$1 == "+" { print $2 }')
    for C in $NOT_IN_BASE; do
      # ブランチ単位ではなくコミット単位で数える（起動ログの orphan_commits を実数に合わせる）
      printf '%s\n' "$NOT_IN_MAIN" | grep -qxF "$C" && ORPHAN_COMMITS=$((ORPHAN_COMMITS + 1))
    done
  done <<EOF
$(gh pr list -R hiroky1983/game_collection --state merged --limit 1000 \
    --json headRefName,baseRefName,headRepositoryOwner \
    --jq '.[] | select((.headRepositoryOwner.login // "") == "hiroky1983") | "\(.headRefName)\t\(.baseRefName)"' 2>/dev/null | sort -u)
EOF
fi

# 実行モード決定。仕事が無ければ何もしない。
# 2026-08-19: 以前はここで「枯渇駆動の企画モード」（分析なしで機械的に2〜3件起票するだけ）に
# 切り替えていたが、その乱造ガード自体が「未承認3件で永久停止」という別の詰まりを生んでいた
# （#106 が6日間放置）。経営企画室の責務は Scripts/ai-management-duty.sh（日次）へ全面移管した。
MODE="duty"
PROMPT_FILE="Scripts/ai-duty-prompt.md"
if [ "${APPROVED:-0}" -eq 0 ] && [ "${THREADS:-0}" -eq 0 ] && [ "${PENDING_REVIEW:-0}" -eq 0 ] && [ "${CONFLICTS:-0}" -eq 0 ] && [ "${RINGI_REPLIES:-0}" -eq 0 ] && [ "${STALLED:-0}" -eq 0 ] && [ "${RELEASED:-0}" -eq 0 ] && [ "${PROPOSED_REPLIES:-0}" -eq 0 ] && [ "${ORPHANS:-0}" -eq 0 ] && [ "${ORPHAN_COMMITS:-0}" -eq 0 ]; then
  log "仕事なし（企画・分析は Scripts/ai-management-duty.sh の担当）"
  exit 0
fi

# ベースクローンを用意（fetch 専用。ここでは一切作業しない）
if [ ! -d "$DUTY_DIR/.git" ]; then
  mkdir -p "$(dirname "$DUTY_DIR")"
  gh repo clone hiroky1983/game_collection "$DUTY_DIR" >>"$LOG" 2>&1 || { log "clone 失敗"; exit 0; }
fi
git -C "$DUTY_DIR" fetch origin --prune >>"$LOG" 2>&1

# 1実行 = 1使い捨て worktree。前回の残骸（異常終了時の未コミット変更等）と物理的に隔離する
RUNS_DIR="$HOME/.asobiba-duty/runs"
mkdir -p "$RUNS_DIR"
# 3日より古い実行用 worktree を掃除
find "$RUNS_DIR" -maxdepth 1 -type d -name 'run-*' -mtime +3 | while read -r d; do
  case "$d" in
    "$RUNS_DIR"/run-*) git -C "$DUTY_DIR" worktree remove --force "$d" >>"$LOG" 2>&1 || rm -rf "$d" ;;
  esac
done
git -C "$DUTY_DIR" worktree prune >>"$LOG" 2>&1

RUN_DIR="$RUNS_DIR/run-$(date +%Y%m%d-%H%M%S)"
git -C "$DUTY_DIR" worktree add --detach "$RUN_DIR" origin/main >>"$LOG" 2>&1 || { log "worktree 作成失敗"; exit 0; }

# claude を起動する直前に実行前の状態を確定させる（これ以降に増えた分だけが当番のもの）
capture_sims_before

log "当番起動 (mode=$MODE, approved=$APPROVED, cr_threads=$THREADS, cr_pending=$PENDING_REVIEW, conflicts=$CONFLICTS, ringi_replies=$RINGI_REPLIES, stalled=$STALLED, released=$RELEASED, proposed_replies=$PROPOSED_REPLIES, orphans=$ORPHANS, orphan_commits=$ORPHAN_COMMITS, workdir=$RUN_DIR, sims_before=[${SIMS_BEFORE% }])"
cd "$RUN_DIR" || exit 0
claude --model opus \
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep,WebFetch,WebSearch" \
  -p "$(cat "$RUN_DIR/$PROMPT_FILE")" >>"$LOG" 2>&1
RC=$?
log "当番終了 (mode=$MODE, exit=$RC)"
