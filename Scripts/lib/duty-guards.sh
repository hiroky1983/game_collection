#!/bin/bash
# 当番の安全装置の共通関数（#3430）。経営企画室（ai-management-duty.sh）と監査当番（ai-audit-duty.sh）、
# 実装当番（ai-duty.sh は install_gh_shim のみ）が source する。
#
# 経緯: 同じ実装が複数のスクリプトにヒアドキュメント／関数ごと複製され、壊れたときに止まるテストが
# 無かった（1 本だけ直すと挙動がずれる）。ここに 1 本化し Scripts/tests/test-duty-guards.sh で守る。
# どちらも呼び出し側が `log` 関数を定義している前提（失敗理由をログに残す）。

# docs/ 以外をコミットさせないフックを <hooks_dir> に置き、GIT_CONFIG_* で core.hooksPath を
# このプロセス（と子プロセス）だけ上書きして有効化する。ディスク上の git 設定は書き換えない。
# 使い方: install_docs_only_hook <hooks_dir> <拒否時のメッセージ> [フック本体のパス]
# 本体は hooks_dir にコピーする（当番が worktree で別ブランチをチェックアウトしても消えないように）。
install_docs_only_hook() {
  local dir="$1" msg="$2" src="${3:-}"
  [ -n "$src" ] || src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/duty-hooks/docs-only-pre-commit"
  [ -f "$src" ] || { log "docs 専用フック: $src が見つからない"; return 1; }
  mkdir -p "$dir" && cp "$src" "$dir/docs-only-pre-commit" && chmod +x "$dir/docs-only-pre-commit" || return 1
  # git は引数なしでフックを呼ぶので、メッセージを焼き込んだ薄い入口を pre-commit として置く
  {
    printf '#!/bin/bash\n'
    printf 'exec bash %q %q\n' "$dir/docs-only-pre-commit" "$msg"
  } >"$dir/pre-commit" || return 1
  chmod +x "$dir/pre-commit" || return 1
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=core.hooksPath
  export GIT_CONFIG_VALUE_0="$dir"
}

# 入力フィルタ（Issue #164）を <shim_dir> に置き、効いていることを実測する。確認できなければ 1 を返す
# （呼び出し側は claude を起動しない = fail closed）。
# 使い方: install_gh_shim <shim_dir> <信頼アカウント（カンマ区切り・先頭が会長）> <duty-gh-shim の置き場>
# 置き場所を一度消して作り直すため、同時に動く当番どうしで shim_dir を共有しないこと。
install_gh_shim() {
  local shim_dir="$1" trusted="$2" src="$3" probe
  [ -f "$src/gh" ] && [ -f "$src/filter.jq" ] || { log "入力フィルタ: $src が見つからない"; return 1; }
  rm -rf "$shim_dir" 2>/dev/null
  mkdir -p "$shim_dir" && chmod 700 "$shim_dir" || return 1
  cp "$src/gh" "$src/filter.jq" "$shim_dir/" || return 1
  chmod +x "$shim_dir/gh" || return 1
  # 素通しの経路が生きているか（ここが壊れると当番はコメントもマージも一切できない）
  PATH="$shim_dir:$PATH" "$shim_dir/gh" --version >/dev/null 2>&1 \
    || { log "入力フィルタ: 素通しの確認に失敗"; return 1; }
  # 第三者の本文が実際に落ちるか（ここが壊れると黙って素通しになり、壊れたことに気づけない）。
  # **ラッパーの横取り判定まで含めて**実測する。filter.jq 単体の確認では、引数の読み違いによる
  # 素通しを検知できない（PR #448 の敵対的検証で、`-R` の先置きとエイリアス経由の2通りが
  # 実際に見つかった）。スタブの gh を噛ませ、代表的な並びで本文が漏れないことを確かめる
  local stub="$shim_dir/.probe-gh" json="$shim_dir/.probe.json" args
  cat >"$stub" <<PROBE
#!/bin/bash
cat "$json"
PROBE
  chmod +x "$stub" || { rm -f "$stub"; return 1; }
  jq -nc '{number:1,title:"t",author:{login:"duty-shim-probe"},body:"DUTY-SHIM-LEAK",comments:[]}' >"$json" \
    || { rm -f "$stub" "$json"; log "入力フィルタ: プローブの作成に失敗"; return 1; }
  for args in "issue view 1" "-R o/r issue view 1" "--repo o/r pr list" "duty-shim-alias 1"; do
    # shellcheck disable=SC2086
    probe=$(DUTY_REAL_GH="$stub" "$shim_dir/gh" $args 2>/dev/null)
    case "$probe" in
      *DUTY-SHIM-LEAK*)
        rm -f "$stub" "$json"
        log "入力フィルタ: 第三者の本文が素通しした（gh ${args}）"
        return 1 ;;
    esac
  done
  jq -nc --arg a "${trusted%%,*}" \
    '{number:1,title:"t",author:{login:$a},body:"DUTY-SHIM-KEEP",comments:[]}' >"$json" || { rm -f "$stub" "$json"; return 1; }
  probe=$(DUTY_REAL_GH="$stub" "$shim_dir/gh" issue view 1 2>/dev/null)
  rm -f "$stub" "$json"
  case "$probe" in
    *DUTY-SHIM-KEEP*) ;;
    *) log "入力フィルタ: 会長の本文まで除去されている"; return 1 ;;
  esac
  return 0
}
