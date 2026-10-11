#!/bin/bash
# `fastlane beta` の署名の前提を、アーカイブを始める前に確かめる（#1041）。
#
# 2026-09-16、v1.1.5 の出荷で「Distribution 証明書がキーチェーンに無い・Xcode が No Accounts」の
# まま 20 分アーカイブして export の最後に落ちた。署名が「この Mac のキーチェーンと Xcode の
# ログイン状態」という壊れやすい前提に乗っていたため。今は Admin 権限の ASC API キー
# （~/.appstoreconnect/asc-key.json）で xcodebuild が証明書・プロファイルを発行できるので、
# 次のどちらかが満たされていれば通す:
#   1. キーチェーンに有効な Apple Distribution の署名 ID がある
#   2. 使える ASC API キーがある（証明書が無くても API キーで自動復旧する）
# どちらも無いときだけ、理由を出して 1 秒で落とす。
#
# 使い方: Scripts/check-signing-prereqs.sh
# 環境変数（テスト用の差し替え口）:
#   ASC_KEY_JSON  : API キー JSON のパス（既定 ~/.appstoreconnect/asc-key.json）
#   SECURITY_BIN  : security コマンド（既定 security）
# 終了コード: 0 = 前提を満たす / 1 = 署名できない
set -uo pipefail

KEY_JSON="${ASC_KEY_JSON:-$HOME/.appstoreconnect/asc-key.json}"
SECURITY="${SECURITY_BIN:-security}"

HAS_CERT=no
if "$SECURITY" find-identity -v -p codesigning 2>/dev/null | grep -q 'Apple Distribution'; then
  HAS_CERT=yes
fi

# key_id / issuer_id / key（.p8 の中身）が揃っているかだけを見る。中身は出力しない。
HAS_KEY=no
if [ -f "$KEY_JSON" ] && /usr/bin/python3 - "$KEY_JSON" <<'PY' >/dev/null 2>&1
import json, sys
d = json.load(open(sys.argv[1]))
assert d["key_id"] and d["issuer_id"] and "BEGIN PRIVATE KEY" in d["key"]
PY
then
  HAS_KEY=yes
fi

if [ "$HAS_CERT" = no ] && [ "$HAS_KEY" = no ]; then
  echo "check-signing-prereqs: 署名できません。" >&2
  echo "  - キーチェーンに Apple Distribution の署名 ID がありません（security find-identity -v -p codesigning）" >&2
  echo "  - ASC API キー [$KEY_JSON] も読めません（key_id / issuer_id / key が必要）" >&2
  echo "  対処: API キーを置く（#781）か、Xcode にログインして証明書を発行してください。" >&2
  exit 1
fi

if [ "$HAS_CERT" = yes ]; then
  echo "check-signing-prereqs: Apple Distribution の署名 ID あり"
else
  echo "check-signing-prereqs: 署名 ID はキーチェーンに無いが、ASC API キーで自動発行できるため続行します"
fi
exit 0
