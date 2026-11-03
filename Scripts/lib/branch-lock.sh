#!/bin/bash
# release ブランチの凍結（lock_branch）を確かめる共通関数（#3227）。
#
# 経緯: 凍結を確かめる `gh api` の失敗を「凍結なし」と読み替える呼び出しが 3 か所あり（pick-issue-milestone.sh・
# ai-duty.sh 仕事7 と仕事13）、レート制限・認証切れ・通信障害のとき、提出済みで凍結した版を現行版や出荷対象と
# 誤判定しうる上、失敗は無言でログに原因が残らなかった。保護設定が無いブランチは 404 を返すが、それは正常な
# 「凍結なし」なので、404 だけを false とし、それ以外の失敗は呼び出し側が止められるよう非 0 で返す。
#
# 使い方: branch_lock_state <owner/repo> <X.Y.Z>
#   標準出力: true | false（成功時のみ）
#   終了コード: 0 = 判定できた（404 の false を含む）/ 1 = 判定できない（原因を標準エラーに 1 行出す）
branch_lock_state() {
  local repo="$1" ver="$2" out err rc
  err=$(mktemp "${TMPDIR:-/tmp}/branch-lock.XXXXXX") || { echo "release/v${ver} の保護設定を取得できません（一時ファイルを作れない）" >&2; return 1; }
  out=$(gh api "repos/${repo}/branches/release%2Fv${ver}/protection" --jq '.lock_branch.enabled' 2>"$err")
  rc=$?
  if [ "$rc" -eq 0 ]; then
    rm -f "$err"
    [ "$out" = "true" ] && echo true || echo false
    return 0
  fi
  # 実物の gh は HTTP エラーで stderr に "(HTTP 404)"、stdout にエラーの JSON（"status":"404"）を出して非 0 で終わる
  if grep -q 'HTTP 404' "$err" || printf '%s' "$out" | grep -q '"status": *"404"'; then
    rm -f "$err"
    echo false
    return 0
  fi
  echo "release/v${ver} の保護設定を取得できません（gh exit=${rc}: $(tr '\n' ' ' <"$err" | cut -c1-200)）" >&2
  rm -f "$err"
  return 1
}
