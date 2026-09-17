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
  # 画面を映すアプリ自体は終了しない。実行前のシミュレータがゼロでも、当番の実行中（最大1時間）に
  # 会長がそれを開いた可能性があり、`killall` はそれを問答無用で殺す（PR #110 の
  # CodeRabbit 指摘・Major）。会長の訴え（PC が重い）の原因は起動中のシミュレータであって
  # デバイスを持たないアプリ側ではないため、落とす必要も無い
  #
  # アプリの名前は Xcode 27 で変わった（2026-09-17）。`Simulator.app` は**消滅**し、
  # `Xcode.app/Contents/Applications/DeviceHub.app` が画面を映す側になっている
  # （`open -a Simulator` はもう通らない）。この関数は `simctl` しか使わないので挙動は変わらない。
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
#
# 3つ目の集合: 会長操作依頼（`ops:chairman`、Issue #556）。会長操作依頼は「本文冒頭に
# 【会長操作依頼】と明記し ai:proposed を付けない」規約（乱造ガード対象から外すため）のため、
# 規約どおりに運用すると上の2集合のどちらにも入らず通知から完全に漏れる（#171 が21日間
# 通知なしで滞留した実例）。`ops:chairman` は会長のコンソール操作でしか進まない印なので、
# **ai:approved / blocked の有無で除外しない**（#171 は ai:approved + blocked のまま沈んでいた）。
# 停止条件は Issue のクローズのみ: --state open で拾うため、会長が操作を終えてクローズすれば
# 次回の収集から自然に落ちて鳴り止む
NOTIFY_RINGI=""
NOTIFY_APPROVAL=""
NOTIFY_CHAIRMAN=""
NOTIFY_READY=0

# 通知対象の収集。gh が失敗したときは NOTIFY_READY を立てないので通知しない（黙って0件扱いにすると
# 「対象なし」と区別が付かず、稟議があるのに無音になる）
collect_notify_targets() {
  # --limit を省略すると 30 件で打ち切られ、超えた分が**黙って**通知から漏れる（PR #142 の
  # CodeRabbit 指摘）。滞留が増えたときほど漏れるという最悪の壊れ方をするので上限を明示する
  local ringi approval chairman
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
  # 会長操作依頼 = ops:chairman（Issue #556）。ai:approved / blocked で除外しない（上記コメント参照）
  chairman=$(gh issue list -R hiroky1983/game_collection --label "ops:chairman" --state open --limit 200 \
    --json number --jq '[.[].number] | map(tostring) | join(" ")' 2>/dev/null) || return 0
  NOTIFY_RINGI="$ringi"
  NOTIFY_APPROVAL="$approval"
  NOTIFY_CHAIRMAN="$chairman"
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

# $1 の番号から $2 に含まれる番号を落とす。同じ Issue が 2 つの集合に入ると、通知の本文に
# 二度並び、件数も二重に数えられる（PR #999 の CodeRabbit 指摘）。決裁待ちと承認待ちは
# jq 側のラベル条件で重ならないようにしてあるが、`ops:chairman` はラベルの組み合わせを
# 制限していない（会長操作依頼に `ai:proposed` や `ringi:pending` が付くことはありうる）ので、
# ここで落とす。
exclude_numbers() {
  local n m out="" skip
  for n in $1; do
    skip=0
    for m in $2; do
      if [ "$n" = "$m" ]; then skip=1; break; fi
    done
    if [ "$skip" -eq 0 ]; then out="$out $n"; fi
  done
  printf '%s' "${out# }"
}

notify_pending() {
  [ "$NOTIFY_READY" -eq 1 ] || return 0
  local ringi approval chairman key now last_key last_at body count
  ringi=$(sanitize_numbers "$NOTIFY_RINGI")
  approval=$(sanitize_numbers "$NOTIFY_APPROVAL")
  chairman=$(sanitize_numbers "$NOTIFY_CHAIRMAN")
  # 先に出る集合を優先して重複を落とす（決裁待ち → 承認待ち → 会長操作待ち）
  approval=$(exclude_numbers "$approval" "$ringi")
  chairman=$(exclude_numbers "$chairman" "$ringi $approval")
  [ -n "$ringi$approval$chairman" ] || return 0

  key="ringi=$ringi;approval=$approval;chairman=$chairman"
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
  if [ -n "$chairman" ]; then
    count=$((count + $(printf '%s' "$chairman" | wc -w)))
    [ -n "$body" ] && body="$body / "
    body="${body}会長操作待ち(ops:chairman): $(hash_numbers "$chairman")"
  fi

  # 以降のログの `${body}` は必ずブレースで囲む（#175）。UTF-8 ロケールの bash は 0x80 以上のバイトを
  # 識別子の一部として受け入れるため、ブレース無しの変数参照の直後に全角文字を置くと、変数名が
  # `body` + その全角文字の先頭バイトと解釈され、`set -u` で `unbound variable` になってスクリプトごと
  # 落ちる（= 手動実行時に通知が飛ばない）。launchd は C ロケールで走るため今まで露見していなかった。
  # 回帰検出はテスト12（UTF-8 での通し実行）とテスト13（全走査）で行う
  osascript -e "display notification \"$body\" with title \"あそびば: 会長の操作待ち ${count}件\"" >/dev/null 2>&1 || {
    log "通知: osascript に失敗したため見送り（対象: ${body}）"
    return 0
  }
  mkdir -p "$(dirname "$DUTY_NOTIFY_STATE")" 2>/dev/null
  printf '%s\n%s\n' "$key" "$now" >"$DUTY_NOTIFY_STATE" 2>/dev/null
  log "通知: 会長へ ${count}件（${body}）"
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
# 会長の書き込みを見分けるための共通 jq 定義（仕事5・仕事8・仕事11 が使う）。
# 当番(AI)・経営企画室・会長はすべて同じ `hiroky1983` トークンで投稿するため author では区別できず、
# 「自社が書いたコメント」を本文のマーカーで除外して最後の会長コメントを取り出す。
#   - 許可リスト外の author（coderabbitai・第三者）は無視する（#68: 自動プランで空振り起動）
#   - `<!-- ai-management-` で始まるコメントは経営企画室（Scripts/ai-management-duty.sh・日次）の
#     分析/リマインドなので除外する。除外しないと経営企画室が1本置くたびに開発当番が「会長の着信」と
#     誤認して毎時空振りする（#168。#120 と同じ失敗モードが経営企画室の常設化で再発した）。
#     マーカーは経営企画室側の重複防止用として ai-management-prompt.md が先頭行に必須化済み
#   - 当番自身の応答マーカーは `is_duty_reply` に集約し、仕事5・仕事8・仕事11 が**同じ集合**を見る
#     （#386。以前は判定ごとに部分集合しか知らず、仕事11 は `企画議論` を知らなかったため、
#     `ai:proposed` + `blocked` の Issue に規程 1-e どおり「企画議論」で応答すると
#     応答済みなのに毎時鳴り続けた。#184 で実際に発生。1-e と 2-b が要求する接頭辞が
#     競合しうる以上、どちらを選んでも止まるよう集合を揃えるほかない）。
#     仕事13 の停止マーカー `出荷準備:` も同じ集合に入れる（#483。会長操作依頼の Issue に blocked や
#     ai:proposed が付いていても、依頼コメントを置いた瞬間に仕事5・8・11 が鳴らないようにするため）。
#     `last_owner_body` 側の除外には**入れない**。あちらは「経営企画室のコメントを飛ばして
#     手前の会長コメントを見る」ためのもので、当番マーカーを入れると自分の応答を飛ばして
#     応答済みの古い会長コメントを拾い、かえって鳴り止まなくなる。
#     判定は `contains` ではなく**記録形式そのもの**（先頭一致）で行う。`contains("決裁反映")` だと
#     会長が「前回の決裁反映を確認した」のように語を引用しただけのコメントを当番の応答と誤認し、
#     決裁着信・解除確認をまるごと取りこぼす（PR #387 の CodeRabbit 指摘）。形式は
#     ai-duty-prompt.md の正典（`## 【要決裁】…` / `決裁反映: …`）に揃えてある。
# 変数に出しているのは、同じ定義を Scripts/tests/test-ai-duty-detect.sh から評価するため。
DUTY_JQ_COMMENT_LIB='
def last_owner_body($actors):
  [.comments.nodes[]
   | select((.author.login // "") as $l | ($actors | index($l)) != null)
   | select(((.body // "") | startswith("<!-- ai-management-")) | not)
   | (.body // "")] | last // "";

def is_duty_reply($b):
  ($b | startswith("企画議論"))
  or ($b | startswith("解除確認"))
  or ($b | startswith("着手見送り:"))
  or ($b | startswith("## 【要決裁】"))
  or ($b | startswith("決裁反映:"))
  or ($b | startswith("出荷準備:"));

def is_ringi_reply($actors):
  last_owner_body($actors) as $b
  | $b != "" and ((is_duty_reply($b)) | not);

def is_proposed_reply($actors):
  ([.labels.nodes[].name]) as $l
  | ($l | index("ai:approved")) == null
    and ($l | index("ai:in-progress")) == null
    and ($l | index("blocked")) == null
    and (last_owner_body($actors) as $b
         | $b != "" and ((is_duty_reply($b)) | not));

def is_blocked_reply($actors):
  last_owner_body($actors) as $b
  | $b != "" and ((is_duty_reply($b)) | not);

# 仕事12（ハンコによる決裁）用。会長の操作契約（docs/ai-company.md）では会長がやるのは
# 「ハンコ（ai:approved の付与）」と「Issue への返信」の2つだけで、`ringi:pending` を外すのは
# AI の責務である。よって「決裁スレッドを出したあとにハンコが押された」= 推奨案での決裁成立。
#   - 比較は ISO8601（UTC・`...Z`）文字列同士。GitHub の createdAt は桁が揃うので辞書順比較で足りる
#   - 基準に取るのは**稟議の記録2種だけ**（決裁スレッド `## 【要決裁】…` と反映記録 `決裁反映…`）で、
#     `is_duty_reply` の集合全部ではない。全部を基準にすると、ハンコの後に当番が無関係な記録
#     （企画議論・着手見送り等）を1本置いただけで**未処理のハンコを取りこぼす**。
#     一方この2種は「当番がその稟議を処理した」ことそのものの記録なので、基準にしても取りこぼさない
#   - 停止条件はこの基準がハンコより後になること。当番の処理は必ず
#     「反映（`決裁反映…` + ringi:pending 除去 = 集合から外れる）」か「決裁スレッドの再掲」の
#     どちらかで終わるため、応答した瞬間に必ず鳴り止む。停止を ringi:pending の除去だけに
#     依存させると、順序不明で再掲したときに毎時の空振りが恒久化する（#120・#168・#386 と同型）
#   - 反映記録は正典の `決裁反映: …` に加えて `## 決裁反映（…）` の見出し形も受ける（#164 の実データ）。
#     PR #387 の指摘どおり判定は先頭一致で行い、`contains` にはしない
#   - ハンコの付与イベントが取れない（順序不明）ときは、**稟議の記録がまだ1本も無い場合に限り**
#     発火させる。無条件に発火させると当番が何を書いても止まらないため
#   - **稟議の記録として数えるのは信頼アカウントの投稿だけ**（PR #446 の CodeRabbit 指摘・Major）。
#     このリポジトリは PUBLIC で誰でも Issue にコメントできるため、絞らないと第三者が
#     「決裁反映…」で始まるコメントを1本置くだけで基準時刻を進め、**正当なハンコの検知を握り潰せる**。
#     既存の `last_owner_body` が author を絞っているのと同じ理由・同じ形にする
#   - **ハンコは `ai:approved` の最新のラベル操作が信頼アカウントによる「付与」のときだけ有効**
#     （同指摘）。付与イベントだけを見て最大値を取ると、会長が付けたあとに剥がされ第三者
#     （= 書き込み権限を持つ別の共同作業者）が付け直した状態や、会長自身が剥がした状態を
#     「ハンコが押されたまま」と誤読する。最新の1件で判定すれば、剥がし（UnlabeledEvent）も
#     信頼外の付与も自動的に「ハンコ無し」に倒れる
def last_ringi_record_at($actors):
  [.comments.nodes[]
   | select((.author.login // "") as $a | ($actors | index($a)) != null)
   | (.body // "") as $b
   | select(($b | startswith("## 【要決裁】"))
            or ($b | startswith("決裁反映"))
            or ($b | startswith("## 決裁反映")))
   | (.createdAt // "")] | max // "";

def ai_approved_at($actors):
  ([.timelineItems.nodes[]? | select((.label.name // "") == "ai:approved")]
   | sort_by(.createdAt // "") | last) as $latest
  | if $latest == null then ""
    elif ($latest.__typename // "") != "LabeledEvent" then ""
    elif (($latest.actor.login // "") as $a | ($actors | index($a)) == null) then ""
    else ($latest.createdAt // "")
    end;

def is_ringi_stamp($actors):
  ([.labels.nodes[].name]) as $l
  | ($l | index("ringi:pending")) != null
    and ($l | index("ai:approved")) != null
    and (ai_approved_at($actors) as $stamp
         | last_ringi_record_at($actors) as $record
         | if $stamp != "" then $stamp > $record else $record == "" end);

# 仕事13（出荷準備の検知・#483）用。入力は ai-duty.sh 仕事13 の GraphQL 応答（マイルストーン単位）。
#   - 残作業として数えるのは「会長のハンコ済み（ai:approved）で、blocked・ringi:pending・ops:chairman の
#     どれも付いていない」オープン Issue だけ。未承認の ai:proposed は会長のハンコ待ちで AI の残作業では
#     ない（2026-09-08 経営企画室の検算: v1.1.3 は未承認の #79 が1件紛れただけで検知全体が沈黙した。
#     #106 が未承認3件のガードで6日放置されたのと同型）。ops:chairman（【会長操作依頼】）も同じ理由で除く
#     （#79 は承認済みのまま会長作業で1か月以上開いており、数えると永久に鳴らない）。除いた Issue は
#     当番が実機確認の依頼に列挙して会長に見せる（ai-duty-prompt.md 2.5）
#   - 停止マーカー（二段目）は、マイルストーンの ops:chairman Issue に信頼アカウントが置いた
#     `出荷準備: vX.Y.Z @<release ブランチ HEAD の SHA 先頭7桁>` で始まるコメント。**SHA まで一致した
#     ときだけ**止まる。依頼の後に release ブランチが動いたら（= 会長が確認するビルドの中身が変わった）
#     再び鳴らして依頼を出し直させるため。版だけで止めると、依頼後に積まれた修正が確認されないまま出る
#   - 判定は先頭一致（PR #387 と同じ理由）。版の直後に ` @` を要求するので v1.1.5 のマーカーが v1.1.50 に
#     当たることもない。第三者のコメントで検知を握り潰せないよう author を信頼アカウントに絞る（PR #446）
#   - マイルストーンの取得は title の部分一致検索なので、ここで完全一致に絞る。見つからなければ空文字を
#     返し、呼び出し側は「鳴らさない」に倒す
#   - オープン Issue の取得が打ち切られている（次のページがある・100件に達している）ときは件数の代わりに
#     `truncated` を返す（呼び出し側は数値でないので鳴らさない）。先頭 100件が除外対象ばかりだと、
#     101件目以降の承認済み Issue を見落として誤発火するため
def ship_remaining_issues:
  if (.openIssues.pageInfo.hasNextPage // false) or ((.openIssues.nodes | length) >= 100) then "truncated"
  else
    [.openIssues.nodes[]
     | ([.labels.nodes[].name]) as $l
     | select(($l | index("ai:approved")) != null
              and ($l | index("blocked")) == null
              and ($l | index("ringi:pending")) == null
              and ($l | index("ops:chairman")) == null)] | length
  end;

def ship_request_posted($actors; $ver; $sha):
  ("出荷準備: v" + $ver + " @" + $sha[0:7]) as $marker
  | [.requestIssues.nodes[].comments.nodes[]
     | select((.author.login // "") as $a | ($actors | index($a)) != null)
     | select((.body // "") | startswith($marker))] | length > 0;

def ship_milestone_state($actors; $ver; $sha):
  [.data.repository.milestones.nodes[]? | select(.title == ("v" + $ver))] | .[0]
  | if . == null then ""
    else "\(ship_remaining_issues) \(ship_request_posted($actors; $ver; $sha))"
    end;
'

# 仕事7の凍結判定（#580）を純粋関数に切り出す。gh/git の呼び出し結果（タグの有無・
# lock_branch の有無）を引数で受け取るだけにし、ネットワーク呼び出しはこの外側（呼び出し側）
# に残す——Scripts/tests/test-ai-duty-detect.sh がモュール無しで直接検証できるようにするため。
# 引数: $1 = -submitted タグの有無（"true"/"false" 相当。空文字列も未タグ扱い）
#       $2 = lock_branch.enabled の値（文字列。"true" だけが凍結済み）
# 戻り値: 0 = 未凍結（仕事あり）/ 1 = 凍結済み（仕事なし）
is_submission_unfrozen() {
  local tag_exists="$1" lock_enabled="$2"
  if [ -z "$tag_exists" ] || [ "$lock_enabled" != "true" ]; then
    return 0
  fi
  return 1
}

# 仕事13（出荷準備の検知・#483）の判定を純粋関数に切り出す（is_submission_unfrozen と同じ理由）。
# 対象の release ブランチを選ぶ段と、その版が出荷準備に入れるかを決める段に分けてある。
#
# ship_candidate_versions: 出荷準備の対象になりうる版を**古い順**に1行ずつ出す。
#   仕事7 のように最大の版（`sort -V | tail -1`）を選ぶと、次版（v1.1.6）を見て、出荷の順番が来ている版
#   （v1.1.5）を永久に見ない。次に出るのは常に「まだ出していない版のうち最も古いもの」なので古い順に並べ、
#   呼び出し側が先頭から凍結・先行量を確かめて1本に決める。
#   次の版はここで落とす:
#     - `vX.Y.Z-submitted` タグがある = 提出済み（停止条件の一段目。提出したら鳴り止む）
#     - App Store の公開バージョン以下 = 公開済み（main への取り込みと凍結漏れは仕事7 の担当）
#     - `release/vX.Y.Z` の形でない名前（過去の `release/v1.1.0-submitted` 複製ブランチ等）
# 引数: $1 = release ブランチ名の一覧（改行区切り）
#       $2 = タグの一覧（改行区切り。各行の最後の欄を ref とみなすので `git ls-remote` の出力も渡せる）
#       $3 = App Store の公開バージョン（取れなければ空。そのときは公開済みの除外をしない）
ship_candidate_versions() {
  local branches="$1" tags="$2" store="$3" v
  printf '%s\n' "$branches" \
    | sed -n 's#^release/v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$#\1#p' \
    | sort -V \
    | while read -r v; do
        # 注釈付きタグの `^{}` 行も同じタグとして扱う。部分一致にすると v1.1.1 のタグで v1.1.10 が落ちる
        printf '%s\n' "$tags" | awk -v t="refs/tags/v${v}-submitted" \
          '{ r = $NF; sub(/\^\{\}$/, "", r) } r == t { f = 1 } END { exit !f }' && continue
        if [ -n "$store" ] && [ "$(printf '%s\n%s\n' "$v" "$store" | sort -V | tail -1)" = "$store" ]; then
          continue
        fi
        echo "$v"
      done
}

# is_ship_target: 候補の版が出荷準備の対象か（古い順に当て、0 なら対象に決め、1 なら次の候補へ、2 なら打ち切る）。
#   - lock_branch が掛かっている = 提出済み（タグの打ち漏れがあっても止まる。停止条件の一段目）→ 次へ
#   - main より先行していない（ahead_by が 0 と正常に取れた）= 出すものが無い空の release ブランチ → 次へ
#   - ahead_by が取れなかった（空・数値でない。5xx やレート制限で gh がエラーの JSON を出す）→ **打ち切り**。
#     次へ進むと、出荷の順番が来ている版（v1.1.5）を飛ばして次版（v1.1.6）を対象にしてしまう
#   lock は "true" だけを凍結とみなす。保護設定が無いと gh api はエラーの JSON を出すため、
#   それを「凍結済み」と読むと未凍結の版を黙って飛ばす
# 引数: $1 = lock_branch.enabled の値 / $2 = main...release の ahead_by（lock が true なら見ない）
# 戻り値: 0 = 対象 / 1 = 対象外（次の候補へ）/ 2 = 判定不能（対象なしで打ち切る）
is_ship_target() {
  local lock_enabled="$1" ahead="$2"
  [ "$lock_enabled" = "true" ] && return 1
  case "$ahead" in ''|*[!0-9]*) return 2 ;; esac
  [ "$ahead" -gt 0 ] || return 1
  return 0
}

# is_ship_ready: 対象の版の出荷準備を始めてよいか。
#   - その release ブランチを base にするオープン PR が 0本（main 直の docs PR 等は数えない。数えると
#     運用系の PR が常に何本か開いている現状では永久に鳴らない）。当番の出す版数更新 PR もここで止まる
#   - そのマイルストーンの残作業（ship_remaining_issues）が 0件
#   - 実機確認の依頼（停止マーカー）が現在の HEAD に対してまだ無い（停止条件の二段目。提出まで数日
#     かかる間ずっと鳴り続けるのを防ぐ）
#   取得に失敗した値（空文字・数値でない）は「鳴らさない」に倒す。1回の取りこぼしは次の巡回で拾えるが、
#   誤発火は claude の起動1回分を毎回無駄にする
# 引数: $1 = オープン PR の本数 / $2 = 残作業の件数 / $3 = 依頼済みか（"true" / "false"）
# 戻り値: 0 = 仕事あり / 1 = 仕事なし
is_ship_ready() {
  local open_prs="$1" remaining="$2" requested="$3"
  [ "$open_prs" = "0" ] || return 1
  [ "$remaining" = "0" ] || return 1
  [ "$requested" = "false" ] || return 1
  return 0
}

# 仕事9（孤児化した ai:in-progress の回収・#83）の集計を純粋関数に切り出す（is_submission_unfrozen と同じ理由）。
#   - ai:approved が付いていない Issue は数えない（#1075）。回収の目的は「承認済み Issue を着手候補に戻す」ことで、
#     未承認の企画 Issue は外しても候補にならない。社長セッションが試作に入るときに付けた目印を壊すだけなので
#     当番は毎回見送り、それでも30分ごとに鳴り続けた（#1016 で 01:47〜06:23 JST に8回空振り）
#   - 最終更新から $2 秒以上経っているものだけ
#   - オープン PR に紐づいている（closingIssuesReferences）ものは除く
# 引数: $1 = `gh issue list --json number,updatedAt,labels` の出力 / $2 = 無更新とみなす秒数
#       $3 = オープン PR に紐づく Issue 番号の JSON 配列
# 出力: 件数（jq に失敗したら 0）
count_orphans() {
  printf '%s' "$1" \
    | jq --argjson age "$2" --argjson linked "$3" \
       '[.[] | . as $i
             | select(([$i.labels[]?.name] | index("ai:approved")) != null)
             | select(($i.updatedAt | fromdateiso8601) < (now - $age))
             | select(($linked | index($i.number)) == null)] | length' 2>/dev/null || echo 0
}

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
# worktree の後片付け（会長指示 2026-09-13「worktree は作業終了後に必ず掃除する」）。
# 1実行=1使い捨て worktree なので、終了時に自分の分を消す。push 済みのものは origin にあり、
# 未 push の変更は次回の当番が拾わない（新しい worktree で始まる）ため、残しても誰も読まない。
# 3日保持の掃除ループは、異常終了で EXIT トラップが走らなかった回の backstop として残す。
RUN_DIR=""
# 呼び出し元の環境から来た値は自分の置き場ではない。当番セッション内でテスト（test-ai-duty-lock.sh）が
# このスクリプトを走らせると、下で自分の置き場を決める前に EXIT した回の後片付けが、
# 実行中の当番の scratch を消していた（#762 の作業中に実測）。
DUTY_SCRATCH_DIR=""
cleanup_worktree() {
  # 撮影物・ビルドログ・一時スクリプトの置き場（実行ごと）。派生データは残す（次回の差分ビルド用）。
  if [ -n "${DUTY_SCRATCH_DIR:-}" ] && [ -d "$DUTY_SCRATCH_DIR" ]; then
    rm -r "$DUTY_SCRATCH_DIR" 2>>"$LOG" || log "後片付け: scratch $DUTY_SCRATCH_DIR を消せなかった（手で確認すること）"
  fi
  [ -n "$RUN_DIR" ] && [ -d "$RUN_DIR" ] || return 0
  cd / || true
  git -C "$DUTY_DIR" worktree remove --force "$RUN_DIR" >>"$LOG" 2>&1 \
    && log "後片付け: worktree $RUN_DIR を削除" \
    || { rm -rf "$RUN_DIR"; git -C "$DUTY_DIR" worktree prune >>"$LOG" 2>&1; log "後片付け: worktree $RUN_DIR を rm -rf で削除"; }
}
trap 'cleanup_simulators; cleanup_worktree; notify_pending; release_lock' EXIT

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

# 起動モデルの選択（会長指示 2026-09-14: デザイン系など複雑な案件は Fable 5.1 で動かす）。
# 仕事1 の候補を ai-duty-prompt.md 2 の選定手順と同じ順（マイルストーンの小さい順 → 番号の小さい順）で
# 1 件求め、それに `model:fable`（会長が付けるラベル）が付いていれば `--model fable` で起動し、
# プロンプトの補足で「仕事2 ではその Issue を選ぶこと」と指定する（起動後に別の候補へ替わると
# モデルと案件がずれるため）。付いていなければ従来どおり opus。取得に失敗したときも opus。
NEXT_CANDIDATE=$(gh issue list -R hiroky1983/game_collection --label "ai:approved" --state open \
  --json number,labels,milestone \
  --jq '[.[] | ([.labels[].name]) as $l
        | select(($l | index("ai:in-progress")) == null and ($l | index("ringi:pending")) == null
                 and ($l | index("blocked")) == null)
        | {number: .number,
           fable: (($l | index("model:fable")) != null),
           ver: ((.milestone.title // "v999.999.999") | ltrimstr("v") | split(".") | map(tonumber? // 999))}]
        | sort_by(.ver, .number) | .[0] // empty' 2>/dev/null || true)
DUTY_MODEL=opus
DUTY_MODEL_NOTE=""
if [ -n "$NEXT_CANDIDATE" ] && [ "$(jq -r '.fable' <<<"$NEXT_CANDIDATE" 2>/dev/null)" = "true" ]; then
  DUTY_MODEL=fable
  DUTY_MODEL_NOTE="今回は Fable 5.1 で起動している（\`model:fable\` の Issue はこのモデルで着手する・会長指示 2026-09-14）。仕事2 では #$(jq -r '.number' <<<"$NEXT_CANDIDATE") を選ぶこと。"
fi
export DUTY_MODEL

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
# 審査提出時の凍結（`vX.Y.Z-submitted` タグ + `lock_branch: true`）に実施主体が無く、
# v1.1.3 で丸ごと飛ばされた（#580・2026-09-10 経営企画室が発見。会長QAで遡及是正済み）。
# 規程（ai-devops.md L134-139）はこの2つを義務づけているが、実行する手順がどの定期出社にも
# 属していなかった。公開判定（下の RELEASED）と同じブロックで、同じ REL_BRANCH に対して
# タグと凍結の有無も確認する——新しい検知ジョブを増やさずに済む。
SUBMISSION_UNFROZEN=0
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
      SUBMITTED_TAG=$(git ls-remote --tags origin "v${REL_VER}-submitted" 2>/dev/null)
      LOCK_ENABLED=$(gh api "repos/hiroky1983/game_collection/branches/release%2Fv${REL_VER}/protection" \
        --jq '.lock_branch.enabled' 2>/dev/null || echo "false")
      if is_submission_unfrozen "${SUBMITTED_TAG:-}" "${LOCK_ENABLED:-false}"; then
        SUBMISSION_UNFROZEN=1
      fi
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
#   4) 承認 — ai:approved の無い Issue は除外する（#1075。理由は count_orphans の説明）。
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
ORPHANS=$(count_orphans "$(gh issue list -R hiroky1983/game_collection --label "ai:in-progress" --state open \
  --json number,updatedAt,labels 2>/dev/null)" "$DUTY_ORPHAN_MIN_AGE" "$LINKED_ISSUES")
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

# 仕事11: blocked 解除確認（Issue #158 で発覚した穴の解消）
# blocked は仕事1・仕事8の集計から機械的に除外されるため、通常この当番から見えない。
# しかし「解除条件を満たしたか」を再評価する経路がどこにも無く、会長が完了をコメントしても
# 検知できなかった（#158: 会長が Firebase コンソール操作を終えて「done」とコメントしたのに
# blocked のまま2日近く放置された）。仕事5・8と同じ DUTY_JQ_COMMENT_LIB のパターンで、
# blocked Issue に会長（= 自社マーカーの付かない信頼アカウントコメント）の新規コメントが付き、
# かつ当番の応答（先頭 "解除確認"）がまだ無いものだけを拾う。
BLOCKED_UPDATES=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    issues(states: OPEN, labels: ["blocked"], first: 20) {
      nodes {
        number
        comments(last: 20) { nodes { body author { login } } }
      }
    }
  }
}' 2>/dev/null | jq --arg trusted "$DUTY_TRUSTED_ACTORS" "$DUTY_JQ_COMMENT_LIB"'($trusted | split(",")) as $actors
  | [.data.repository.issues.nodes[]
  | select(is_blocked_reply($actors))] | length' 2>/dev/null || echo 0)

# 仕事12: ハンコによる決裁の着信（Issue #436）
# 会長の運用宣言（2026-09-02）: 「やるのはハンコ（ai:approved）を押すことと Issue に返信することだけ。
# ringi:pending を外すなどのラベル操作は一切やらない」。仕事5 は**コメント**での決裁しか見ておらず、
# ハンコだけ押された Issue は ringi:pending が残るせいで仕事1（着手対象）からも外れ、どの検知にも
# 掛からないまま沈む（#164 は 2026-08-19 にハンコが押されたのに 2026-09-02 の会長指摘まで2週間滞留した）。
# 「決裁スレッドを出したあとにハンコが押された」= 推奨案での決裁成立として当番を起こす。
# 判定は DUTY_JQ_COMMENT_LIB の is_ringi_stamp（発火・停止の条件と経緯はそちらのコメント参照）。
RINGI_STAMPS=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    issues(states: OPEN, labels: ["ringi:pending"], first: 20) {
      nodes {
        number
        labels(first: 20) { nodes { name } }
        comments(last: 20) { nodes { body createdAt author { login } } }
        timelineItems(last: 100, itemTypes: [LABELED_EVENT, UNLABELED_EVENT]) {
          nodes {
            __typename
            ... on LabeledEvent { createdAt label { name } actor { login } }
            ... on UnlabeledEvent { createdAt label { name } actor { login } }
          }
        }
      }
    }
  }
}' 2>/dev/null | jq --arg trusted "$DUTY_TRUSTED_ACTORS" "$DUTY_JQ_COMMENT_LIB"'($trusted | split(",")) as $actors
  | [.data.repository.issues.nodes[]
  | select(is_ringi_stamp($actors))] | length' 2>/dev/null || echo 0)

# 仕事13: 出荷準備の検知（Issue #483）
# release ブランチに内容が溜まったことを検知して出荷工程を起こす経路が無かった。仕事7 は公開**後**の
# 取り込みしか見ておらず、提出**前**を見る検知が1つも無かったため、v1.1.3 は main より135コミット先行した
# まま、社長セッションの手動起動まで誰にも起こされなかった（v1.1.3 の出荷も結局は手動で回った）。
# 「未提出の最も古い release ブランチに内容があり、その版の PR も残作業も無く、実機確認をまだ依頼していない」
# ときに当番を起こし、ai-duty-prompt.md 2.5 の前段（版数の確認・更新 PR・会長への実機確認の依頼）を行わせる。
# fastlane beta と App Store Connect への提出は会長の職掌なので当番はやらない。
# 停止条件は二段で、判定と経緯は上の純粋関数（ship_candidate_versions / is_ship_target / is_ship_ready）と
# DUTY_JQ_COMMENT_LIB の ship_* を参照:
#   一段目 = 提出（`vX.Y.Z-submitted` タグ か lock_branch）。版が対象から外れ、二度と鳴らない
#   二段目 = 当番の実機確認依頼（`出荷準備: vX.Y.Z @<SHA>`）。提出まで数日かかる間の空振り起動を止める
# 呼び出しは安い順に並べ、条件が崩れた時点でそれ以降は取りに行かない（数分おきに回るため）。
SHIP_READY=0
SHIP_VER=""
SHIP_SHA=""
SHIP_REFS=$(gh api "repos/hiroky1983/game_collection/git/matching-refs/heads/release/v" \
  --jq '.[] | "\(.ref | sub("^refs/heads/";""))\t\(.object.sha)"' 2>/dev/null || true)
if [ -n "$SHIP_REFS" ]; then
  # 公開バージョンは仕事7 が取れていればそれを使う（仕事7 は最大の版が先行していないと取りに行かない）
  SHIP_STORE_VER="${STORE_VER:-}"
  if [ -z "$SHIP_STORE_VER" ]; then
    SHIP_STORE_VER=$(curl -sf --max-time 10 "https://itunes.apple.com/lookup?id=${DUTY_APP_ID}&country=jp" 2>/dev/null \
      | jq -r '.results[0].version // empty' 2>/dev/null)
  fi
  SHIP_TAGS=$(gh api "repos/hiroky1983/game_collection/git/matching-refs/tags/v" \
    --jq '.[].ref | select(endswith("-submitted"))' 2>/dev/null || true)
  for V in $(ship_candidate_versions "$(printf '%s\n' "$SHIP_REFS" | cut -f1)" "$SHIP_TAGS" "${SHIP_STORE_VER:-}"); do
    SHIP_LOCK=$(gh api "repos/hiroky1983/game_collection/branches/release%2Fv${V}/protection" \
      --jq '.lock_branch.enabled' 2>/dev/null || echo "false")
    SHIP_AHEAD=""
    if [ "$SHIP_LOCK" != "true" ]; then
      # 失敗を 0 に丸めない（丸めると「空のブランチ」と区別できず次の版へ進んでしまう）
      SHIP_AHEAD=$(gh api "repos/hiroky1983/game_collection/compare/main...release/v${V}" --jq '.ahead_by' 2>/dev/null || true)
    fi
    is_ship_target "$SHIP_LOCK" "$SHIP_AHEAD"
    case $? in
      0) SHIP_VER="$V"; break ;;
      2) break ;;
    esac
  done
fi
if [ -n "$SHIP_VER" ]; then
  SHIP_SHA=$(printf '%s\n' "$SHIP_REFS" | awk -F'\t' -v b="release/v${SHIP_VER}" '$1 == b { print $2 }')
  SHIP_PRS=$(gh pr list -R hiroky1983/game_collection --state open --base "release/v${SHIP_VER}" --limit 200 \
    --json number --jq 'length' 2>/dev/null || true)
  SHIP_REMAINING=""
  SHIP_REQUESTED=""
  if [ "${SHIP_PRS:-}" = "0" ]; then
    # オープン Issue は 100件、ops:chairman の Issue は 50件・各コメント直近 50件まで見る。
    # オープン Issue が打ち切られていたら ship_remaining_issues が件数を返さず、鳴らさない側に倒れる。
    # マイルストーンの検索は部分一致で、v1.1.1 は v1.1.10〜19 にも当たるので枠を 50 に広げてある
    SHIP_STATE=$(gh api graphql -f title="v${SHIP_VER}" -f query='
query($title: String!) {
  repository(owner: "hiroky1983", name: "game_collection") {
    milestones(first: 50, query: $title, states: [OPEN, CLOSED]) {
      nodes {
        title
        openIssues: issues(states: OPEN, first: 100) {
          pageInfo { hasNextPage }
          nodes { number labels(first: 20) { nodes { name } } }
        }
        requestIssues: issues(labels: ["ops:chairman"], states: [OPEN, CLOSED], first: 50) {
          nodes { number comments(last: 50) { nodes { body author { login } } } }
        }
      }
    }
  }
}' 2>/dev/null | jq -r --arg trusted "$DUTY_TRUSTED_ACTORS" --arg ver "$SHIP_VER" --arg sha "$SHIP_SHA" \
      "$DUTY_JQ_COMMENT_LIB"'($trusted | split(",")) as $actors | ship_milestone_state($actors; $ver; $sha)' 2>/dev/null || true)
    if [ -n "${SHIP_STATE:-}" ]; then
      SHIP_REMAINING="${SHIP_STATE% *}"
      SHIP_REQUESTED="${SHIP_STATE#* }"
    fi
  fi
  if is_ship_ready "${SHIP_PRS:-}" "$SHIP_REMAINING" "$SHIP_REQUESTED"; then
    SHIP_READY=1
  fi
fi

# 実行モード決定。仕事が無ければ何もしない。
# 2026-08-19: 以前はここで「枯渇駆動の企画モード」（分析なしで機械的に2〜3件起票するだけ）に
# 切り替えていたが、その乱造ガード自体が「未承認3件で永久停止」という別の詰まりを生んでいた
# （#106 が6日間放置）。経営企画室の責務は Scripts/ai-management-duty.sh（日次）へ全面移管した。
MODE="duty"
PROMPT_FILE="Scripts/ai-duty-prompt.md"
if [ "${APPROVED:-0}" -eq 0 ] && [ "${THREADS:-0}" -eq 0 ] && [ "${PENDING_REVIEW:-0}" -eq 0 ] && [ "${CONFLICTS:-0}" -eq 0 ] && [ "${RINGI_REPLIES:-0}" -eq 0 ] && [ "${STALLED:-0}" -eq 0 ] && [ "${RELEASED:-0}" -eq 0 ] && [ "${SUBMISSION_UNFROZEN:-0}" -eq 0 ] && [ "${PROPOSED_REPLIES:-0}" -eq 0 ] && [ "${ORPHANS:-0}" -eq 0 ] && [ "${ORPHAN_COMMITS:-0}" -eq 0 ] && [ "${BLOCKED_UPDATES:-0}" -eq 0 ] && [ "${RINGI_STAMPS:-0}" -eq 0 ] && [ "${SHIP_READY:-0}" -eq 0 ]; then
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
# 前回までの実行用 worktree を**すべて**掃除する（会長指示 2026-09-13）。
# 以前は「3日より古いもの」だけを消していたが、実際には一度も消えず 9/9〜9/13 の5日で
# 52 個・50GB が溜まっていた（フルチェックアウト1個≈1GB）。ロックで直列に動いているので、
# この時点で残っている run-* は全部が終了済みの残骸であり、年齢を見ずに消してよい。
# 終了時の cleanup_worktree（EXIT トラップ）が本線で、ここは異常終了で残った回の backstop。
STALE_COUNT=0
for d in "$RUNS_DIR"/run-*; do
  [ -d "$d" ] || continue
  if git -C "$DUTY_DIR" worktree remove --force "$d" >>"$LOG" 2>&1; then
    STALE_COUNT=$((STALE_COUNT + 1))
  else
    log "掃除: worktree $d を git worktree remove で消せなかった（手で確認すること）"
  fi
done
git -C "$DUTY_DIR" worktree prune >>"$LOG" 2>&1
[ "$STALE_COUNT" -gt 0 ] && log "掃除: 前回までの worktree を $STALE_COUNT 個削除（runs=$(du -sh "$RUNS_DIR" 2>/dev/null | cut -f1)）"

RUN_DIR="$RUNS_DIR/run-$(date +%Y%m%d-%H%M%S)"
git -C "$DUTY_DIR" worktree add --detach "$RUN_DIR" origin/main >>"$LOG" 2>&1 || { log "worktree 作成失敗"; exit 0; }

# アプリのビルド（xcodebuild）の派生データは**この 1 か所を使い回す**（会長指示 2026-09-14「当番の残骸は
# そっちで何とかして」）。当番はそれまで実行ごとに /tmp/dd-<issue> などを新しく作っていて、2026-09-14 に
# 125 個・約 150GB が /tmp に残っていた。1 か所に固定すると SPM 依存の取得（初回 20〜30 分）も 2 回目から
# 差分ビルドで済む。before/after の比較ビルドは `$DUTY_DERIVED_DATA-base` の 1 個だけ許す。
# 撮影物・ビルドログ・一時スクリプトは `$DUTY_SCRATCH_DIR`（実行ごと。EXIT で消す）に置かせる。
DUTY_DERIVED_DATA="$HOME/.asobiba-duty/derived-data"
DUTY_SCRATCH_DIR="$HOME/.asobiba-duty/scratch/$(basename "$RUN_DIR")"
mkdir -p "$DUTY_DERIVED_DATA" "$DUTY_SCRATCH_DIR"
export DUTY_DERIVED_DATA DUTY_SCRATCH_DIR
# 派生データは 14 日使われなければ捨てる（Xcode やランタイムの更新で古いキャッシュが害になることがある）。
# 前回の scratch と、規程に反して /tmp に作られた派生データ（`*dd*` で SPM のチェックアウト
# `SourcePackages` を持つディレクトリ）は 1 日たっていれば消す。`rm -r`（-f 無し）で、消せなければログに残す。
for d in "$DUTY_DERIVED_DATA" "$DUTY_DERIVED_DATA-base"; do
  [ -d "$d" ] || continue
  if [ -n "$(find "$d" -maxdepth 0 -mtime +14 2>/dev/null)" ]; then
    rm -r "$d" 2>>"$LOG" && log "掃除: 14 日使われていない派生データ $d を削除" || log "掃除: $d を消せなかった（手で確認すること）"
  fi
done
for d in "$HOME/.asobiba-duty/scratch"/run-*; do
  [ -d "$d" ] && [ "$d" != "$DUTY_SCRATCH_DIR" ] || continue
  rm -r "$d" 2>>"$LOG" || log "掃除: scratch $d を消せなかった（手で確認すること）"
done
TMP_DD_COUNT=0
for d in /tmp/*dd*; do
  [ -d "$d" ] && [ -d "$d/SourcePackages" ] || continue
  [ -n "$(find "$d" -maxdepth 0 -mtime +1 2>/dev/null)" ] || continue
  rm -r "$d" 2>>"$LOG" && TMP_DD_COUNT=$((TMP_DD_COUNT + 1)) || log "掃除: /tmp の派生データ $d を消せなかった（手で確認すること）"
done
[ "$TMP_DD_COUNT" -gt 0 ] && log "掃除: /tmp に残っていた派生データを $TMP_DD_COUNT 個削除（規程は \$DUTY_DERIVED_DATA を使うこと）"

# 入力フィルタ（Issue #164）: claude セッション内の `gh` を Scripts/duty-gh-shim/gh 経由にして、
# 第三者（PUBLIC リポジトリなので誰でも書ける）の本文が AI のコンテキストへ入る前に機械的に除去する。
# 憲章の「指示として扱うのは会長と coderabbitai だけ」は、これまでプロンプトの記述だけで強制されていた。
#   - 置き場所を worktree の**外**にするのは、当番が release ブランチ等をチェックアウトすると
#     worktree 側の Scripts/ が入れ替わり、ラッパーごと消えて gh が動かなくなるため
#   - 効いていることを起動前に実測し、確認できなければ **claude を起動しない**（fail closed）。
#     フィルタ無しで走らせるくらいなら1回休むほうがよい。ラッパー自体の回帰は
#     Scripts/tests/test-duty-gh-shim.sh（CI で実行）が防ぐ
GH_SHIM_DIR="$HOME/.asobiba-duty/gh-shim"
install_gh_shim() {
  local src="$RUN_DIR/Scripts/duty-gh-shim" probe
  [ -f "$src/gh" ] && [ -f "$src/filter.jq" ] || { log "入力フィルタ: $src が見つからない"; return 1; }
  rm -rf "$GH_SHIM_DIR" 2>/dev/null
  mkdir -p "$GH_SHIM_DIR" && chmod 700 "$GH_SHIM_DIR" || return 1
  cp "$src/gh" "$src/filter.jq" "$GH_SHIM_DIR/" || return 1
  chmod +x "$GH_SHIM_DIR/gh" || return 1
  # 素通しの経路が生きているか（ここが壊れると当番はコメントもマージも一切できない）
  PATH="$GH_SHIM_DIR:$PATH" "$GH_SHIM_DIR/gh" --version >/dev/null 2>&1 \
    || { log "入力フィルタ: 素通しの確認に失敗"; return 1; }
  # 第三者の本文が実際に落ちるか（ここが壊れると黙って素通しになり、壊れたことに気づけない）。
  # **ラッパーの横取り判定まで含めて**実測する。filter.jq 単体の確認では、引数の読み違いによる
  # 素通しを検知できない（PR #448 の敵対的検証で、`-R` の先置きとエイリアス経由の2通りが
  # 実際に見つかった）。スタブの gh を噛ませ、代表的な並びで本文が漏れないことを確かめる
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
  jq -nc --arg a "${DUTY_TRUSTED_ACTORS%%,*}" \
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

# claude を起動する直前に実行前の状態を確定させる（これ以降に増えた分だけが当番のもの）
capture_sims_before
# 同時に起動してよいシミュレータは全体で2台まで（会長指示 2026-09-13。3台以上で Mac が固まる）。
# 実行前に何台起動しているかをプロンプトへ渡し、当番側で「あと何台起動できるか」を判断させる。
SIMS_BOOTED_COUNT=$(printf '%s' "${SIMS_BEFORE% }" | wc -w | tr -d ' ')
export SIMS_BOOTED_COUNT
# 仕事13 で起動したときは、対象の版と停止マーカーに書く SHA を補足で渡す（当番が別の版を選ばないため）
DUTY_SHIP_NOTE=""
if [ "$SHIP_READY" -eq 1 ]; then
  DUTY_SHIP_NOTE="仕事13（出荷準備）: release/v${SHIP_VER}（HEAD ${SHIP_SHA:0:7}）が出荷準備の条件を満たした。セクション 2.5 の手順を行うこと。"
fi

log "当番起動 (model=$DUTY_MODEL, mode=$MODE, approved=$APPROVED, cr_threads=$THREADS, cr_pending=$PENDING_REVIEW, conflicts=$CONFLICTS, ringi_replies=$RINGI_REPLIES, stalled=$STALLED, released=$RELEASED, submission_unfrozen=$SUBMISSION_UNFROZEN, proposed_replies=$PROPOSED_REPLIES, orphans=$ORPHANS, orphan_commits=$ORPHAN_COMMITS, blocked_updates=$BLOCKED_UPDATES, ringi_stamps=$RINGI_STAMPS, ship_ready=$SHIP_READY, ship_target=${SHIP_VER:-なし}, workdir=$RUN_DIR, gh_shim=$GH_SHIM_DIR, sims_before=[${SIMS_BEFORE% }])"
cd "$RUN_DIR" || exit 0
PATH="$GH_SHIM_DIR:$PATH" claude --model "$DUTY_MODEL" \
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep,WebFetch,WebSearch" \
  -p "$(cat "$RUN_DIR/$PROMPT_FILE")

（実行環境の補足）起動時点で起動中のシミュレータは ${SIMS_BOOTED_COUNT} 台。上限は全体で2台。xcodebuild の派生データは必ず \`-derivedDataPath ${DUTY_DERIVED_DATA}\`（比較用のベースは \`${DUTY_DERIVED_DATA}-base\`）を使い、撮影物・ビルドログ・一時スクリプトは \`${DUTY_SCRATCH_DIR}\` に置くこと（/tmp に新しいディレクトリを作らない。この 2 つは環境変数 DUTY_DERIVED_DATA / DUTY_SCRATCH_DIR でも参照できる）。${DUTY_MODEL_NOTE}${DUTY_SHIP_NOTE}" >>"$LOG" 2>&1
RC=$?
log "当番終了 (mode=$MODE, exit=$RC)"
