#!/bin/bash
# アプリ側の URL 直書きが LP の定数とずれていないか確認する（#3547）。
#
# なぜ要るか: web/app/lib/site.ts は「独自ドメインを取得したら SITE_URL だけ差し替える」と謳うが、
# アプリは規約・プライバシーポリシーの基点 URL と App Store の商品ページ URL を別に直書きしている。
# ずれても CI は緑のままで、旧ドメインを閉じた時点で設定画面の規約リンクが切れる（審査にも影響する）。
#
# 照合する組（web 側を正とする）:
#   web/app/lib/site.ts           SITE_URL      ↔  App/SettingsView.swift       legalBaseURL
#   web/app/lib/site.ts           APP_STORE_ID  ↔  App/AppGameServices.swift    appStoreURL の id
#
# 使い方: bash Scripts/check-lp-site-url.sh [リポジトリのルート]
# 終了コード: 0 = 一致 / 1 = 食い違い or 読み取り失敗
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

SITE="$ROOT/web/app/lib/site.ts"
SETTINGS="$ROOT/App/SettingsView.swift"
SERVICES="$ROOT/App/AppGameServices.swift"

for f in "$SITE" "$SETTINGS" "$SERVICES"; do
  [ -f "$f" ] || { echo "NG: $f が見つかりません"; exit 1; }
done

# 先頭の1件だけを取る（取れなければ空）
first() { sed -nE "$1" "$2" | head -n 1; }

SITE_URL="$(first 's/^export const SITE_URL[[:space:]]*=[[:space:]]*"([^"]+)".*$/\1/p' "$SITE")"
SITE_ID="$(first 's/^export const APP_STORE_ID[[:space:]]*=[[:space:]]*"([0-9]+)".*$/\1/p' "$SITE")"
APP_BASE="$(first 's/^[[:space:]]*(private )?static let legalBaseURL[[:space:]]*=[[:space:]]*"([^"]+)".*$/\2/p' "$SETTINGS")"
APP_ID="$(first 's/^[[:space:]]*static let appStoreURL[[:space:]]*=[[:space:]]*URL\(string: "https:\/\/apps\.apple\.com\/[^"]*\/id([0-9]+)"\).*$/\1/p' "$SERVICES")"

STATUS=0
for pair in "site.ts SITE_URL=$SITE_URL" "site.ts APP_STORE_ID=$SITE_ID" \
            "SettingsView.swift legalBaseURL=$APP_BASE" "AppGameServices.swift appStoreURL の id=$APP_ID"; do
  [ -n "${pair#*=}" ] || { echo "NG: ${pair%%=*} を読み取れません"; STATUS=1; }
done
[ "$STATUS" -eq 0 ] || exit 1

# 末尾のスラッシュ違いは同じ基点 URL
if [ "${SITE_URL%/}" != "${APP_BASE%/}" ]; then
  echo "NG: SettingsView.swift の legalBaseURL（${APP_BASE}）が site.ts の SITE_URL（${SITE_URL}）と違います"
  STATUS=1
fi
if [ "$SITE_ID" != "$APP_ID" ]; then
  echo "NG: AppGameServices.swift の appStoreURL の id（${APP_ID}）が site.ts の APP_STORE_ID（${SITE_ID}）と違います"
  STATUS=1
fi

[ "$STATUS" -eq 0 ] && echo "OK: 規約の基点 URL（${SITE_URL}）と App Store ID（${SITE_ID}）はアプリと LP で一致"
exit "$STATUS"
