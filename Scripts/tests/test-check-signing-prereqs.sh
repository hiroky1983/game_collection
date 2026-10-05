#!/bin/bash
# check-signing-prereqs.sh の検証（#1041）。会長の Mac のキーチェーン・Xcode のログインには
# 触らず、security コマンドと API キー JSON を偽物に差し替えて 4 通りの組み合わせを見る。
#
# 使い方: bash Scripts/tests/test-check-signing-prereqs.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-signing-prereqs.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 偽の security: 署名 ID の一覧に $FAKE_IDENTITY を出す
cat >"$TMP/security" <<'SH'
#!/bin/bash
echo "     0 valid identities found"
[ -n "${FAKE_IDENTITY:-}" ] && echo "  1) ABCDEF \"$FAKE_IDENTITY\""
exit 0
SH
chmod +x "$TMP/security"

printf '{"key_id":"K","issuer_id":"I","key":"-----BEGIN PRIVATE KEY-----\\nx\\n-----END PRIVATE KEY-----"}' >"$TMP/good.json"
printf '{"key_id":"K","issuer_id":"I","key":"broken"}' >"$TMP/bad.json"
printf '{"key_id":"","issuer_id":"I","key":"-----BEGIN PRIVATE KEY-----\\nx\\n-----END PRIVATE KEY-----"}' >"$TMP/noid.json"

run() { # $1=identity $2=json path
  FAKE_IDENTITY="$1" ASC_KEY_JSON="$2" SECURITY_BIN="$TMP/security" bash "$TARGET" >"$TMP/out" 2>"$TMP/err"
}

run "" "$TMP/none.json" && ng "証明書なし・キーなしは落ちる" || ok "証明書なし・キーなしは落ちる"
grep -q "署名できません" "$TMP/err" && ok "落ちる理由を出す" || ng "落ちる理由を出す"
run "" "$TMP/bad.json" && ng "証明書なし・壊れたキーは落ちる" || ok "証明書なし・壊れたキーは落ちる"
run "" "$TMP/noid.json" && ng "証明書なし・key_id が空は落ちる" || ok "証明書なし・key_id が空は落ちる"
run "" "$TMP/good.json" && ok "証明書なし・キーあり（API で自動復旧）は通る" || ng "証明書なし・キーあり（API で自動復旧）は通る"
run "Apple Distribution: X (TEAM)" "$TMP/none.json" && ok "証明書あり・キーなしは通る" || ng "証明書あり・キーなしは通る"
run "Apple Development: X (TEAM)" "$TMP/none.json" && ng "Development 証明書だけでは通らない" || ok "Development 証明書だけでは通らない"

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
