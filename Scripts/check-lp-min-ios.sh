#!/bin/bash
# LP の最低 iOS 表記が project.yml の deploymentTarget と一致するか確認する（#3533）。
#
# なぜ要るか: アプリの最低 OS を上げても、LP の MIN_IOS_VERSION（JSON-LD で使用）と、定数を使わず
# 直書きしている利用規約（ja / en）が古いまま残っても CI が緑のままになる。規約は法的文書なのでずれは実害。
#
# 照合する4箇所（project.yml を正とする）:
#   project.yml                      deploymentTarget.iOS
#   web/app/lib/site.ts              MIN_IOS_VERSION
#   web/app/(ja)/terms/page.tsx      「iOS X.Y以上」
#   web/app/en/terms/page.tsx        「iOS X.Y or later」
#
# 使い方: bash Scripts/check-lp-min-ios.sh [リポジトリのルート]
# 終了コード: 0 = 一致 / 1 = 食い違い or 読み取り失敗
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

PROJECT="$ROOT/project.yml"
SITE="$ROOT/web/app/lib/site.ts"
TERMS_JA="$ROOT/web/app/(ja)/terms/page.tsx"
TERMS_EN="$ROOT/web/app/en/terms/page.tsx"

for f in "$PROJECT" "$SITE" "$TERMS_JA" "$TERMS_EN"; do
  [ -f "$f" ] || { echo "NG: $f が見つかりません"; exit 1; }
done

# 先頭の1件だけを取る（取れなければ空）
first() { sed -nE "$1" "$2" | head -n 1; }

APP="$(first 's/^[[:space:]]*iOS:[[:space:]]*"?([0-9]+(\.[0-9]+)*)"?[[:space:]]*$/\1/p' "$PROJECT")"
SITE_V="$(first 's/^export const MIN_IOS_VERSION[[:space:]]*=[[:space:]]*"([0-9.]+)".*$/\1/p' "$SITE")"
JA_V="$(first 's/.*iOS ([0-9]+(\.[0-9]+)*)以上.*/\1/p' "$TERMS_JA")"
EN_V="$(first 's/.*iOS ([0-9]+(\.[0-9]+)*) or later.*/\1/p' "$TERMS_EN")"

STATUS=0
for pair in "project.yml deploymentTarget.iOS=$APP" "site.ts MIN_IOS_VERSION=$SITE_V" \
            "terms(ja) iOS …以上=$JA_V" "terms(en) iOS … or later=$EN_V"; do
  [ -n "${pair#*=}" ] || { echo "NG: ${pair%=*} を読み取れません"; STATUS=1; }
done
[ "$STATUS" -eq 0 ] || exit 1

for pair in "site.ts MIN_IOS_VERSION=$SITE_V" "terms(ja)=$JA_V" "terms(en)=$EN_V"; do
  if [ "${pair#*=}" != "$APP" ]; then
    echo "NG: ${pair%=*} の iOS ${pair#*=} が project.yml の deploymentTarget（iOS $APP）と違います"
    STATUS=1
  fi
done

[ "$STATUS" -eq 0 ] && echo "OK: 最低 iOS 表記はすべて $APP で一致"
exit "$STATUS"
