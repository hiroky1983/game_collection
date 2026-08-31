#!/bin/bash
# release/vX.Y.Z から配信するとき、project.yml の MARKETING_VERSION が
# ブランチ名の X.Y.Z と一致していることを確認する（#161）。
#
# MARKETING_VERSION の更新は release ブランチの作成時ではなく**配信直前**の手作業なので、
# ブランチを作った直後の不一致は正常な途中状態である。よって CI で常時検証はせず、
# 「一致していなければならない唯一の瞬間」= `fastlane beta` の実行前だけで落とす。
# v1.1.1 では 1.1.0 のまま TestFlight へ上げる直前まで気づかれず、審査中の v1.1.0 build 5 と
# 同一バージョングループにビルドが入りかけた（#133 で手当て）。
#
# 使い方: Scripts/check-marketing-version.sh [ブランチ名] [project.yml のパス]
#   引数を省略すると現在のブランチとリポジトリ直下の project.yml を見る。
# 終了コード: 0 = 一致 or 検証対象外 / 1 = 不一致 or project.yml を読めない
set -uo pipefail

BRANCH="${1:-}"
PROJECT_YML="${2:-}"

if [ -z "$BRANCH" ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
fi
if [ -z "$PROJECT_YML" ]; then
  PROJECT_YML="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")/project.yml"
fi

# release/vX.Y.Z 以外（main・feature ブランチ・detached HEAD）は期待値を導けないので検証しない。
# 黙って通ると「チェックが働いた」と誤解されるため、対象外である旨は必ず出す。
case "$BRANCH" in
  release/v*) EXPECTED="${BRANCH#release/v}" ;;
  *)
    echo "check-marketing-version: 現在のブランチ [$BRANCH] は release/vX.Y.Z ではないため検証しません"
    exit 0
    ;;
esac

# release/v で始まるのに X.Y.Z でない場合は、黙って通すと `release/vnext` や `release/v1.2` の
# ような名前で検証そのものを迂回できてしまう。規程（ai-devops）上そんなブランチは存在しないので落とす。
# 数字とドットだけ・空の要素なし・ドットがちょうど2個 = 3要素、で X.Y.Z の完全一致を見る。
DOTS="${EXPECTED//[!.]/}"
VALID=no
case "$EXPECTED" in
  *[!0-9.]* | "" | *..* | .* | *.) VALID=no ;;
  *) [ "${#DOTS}" -eq 2 ] && VALID=yes ;;
esac
if [ "$VALID" != "yes" ]; then
  echo "check-marketing-version: ブランチ名 [$BRANCH] が release/vX.Y.Z の形式ではありません" >&2
  echo "  配信は release/vX.Y.Z（数字3要素）からのみ行ってください（規程 docs/ai-devops.md「ブランチ戦略」）。" >&2
  exit 1
fi

if [ ! -f "$PROJECT_YML" ]; then
  echo "check-marketing-version: project.yml が見つかりません: $PROJECT_YML" >&2
  exit 1
fi

# `        MARKETING_VERSION: "1.1.2"` の形。ターゲットが増えて複数行あっても値が割れていないことを見る。
# tr の \015 \042 \047 は CR と " と ' （シェルの引用符と混ざらないよう8進で書く）。
# CR を落とすのは、awk が空白で区切るため CRLF 改行だと値の末尾に \r が残り、
# 一致しているのに配信をブロックしてしまうため。
ACTUAL="$(awk '$1 == "MARKETING_VERSION:" { print $2 }' "$PROJECT_YML" | tr -d '\015\042\047' | sort -u)"
COUNT="$(printf '%s' "$ACTUAL" | grep -c . || true)"

if [ "$COUNT" -eq 0 ]; then
  echo "check-marketing-version: $PROJECT_YML に MARKETING_VERSION がありません" >&2
  exit 1
fi
if [ "$COUNT" -gt 1 ]; then
  echo "check-marketing-version: MARKETING_VERSION の値が複数あります: $(printf '%s' "$ACTUAL" | tr '\n' ' ')" >&2
  exit 1
fi

if [ "$ACTUAL" != "$EXPECTED" ]; then
  cat >&2 <<EOF
check-marketing-version: MARKETING_VERSION がブランチ名と一致しません

  ブランチ        : ${BRANCH}（期待するバージョン: ${EXPECTED}）
  project.yml     : MARKETING_VERSION = ${ACTUAL}

配信前に project.yml の MARKETING_VERSION を $EXPECTED に更新してください
（更新後は xcodegen generate が fastlane beta 内で走るため手動生成は不要です）。
EOF
  exit 1
fi

# 変数展開の直後に全角文字を続けると macOS 標準の bash 3.2（UTF-8 ロケール）が変数名を
# 誤パースして「unbound variable」で落ちるため、必ず ${} でブレースする（fastlane beta が
# このスクリプト経由で止まった実害あり・2026-08-31）。
echo "check-marketing-version: OK（${BRANCH} / MARKETING_VERSION = ${ACTUAL}）"
