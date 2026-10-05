#!/bin/bash
# `fastlane beta` をログ全量保存つきで実行する（#1041 C）。
# `| tail -60` で切ると EXPORT FAILED の理由が消え、原因特定に往復が出る（2026-09-16）。
# 出力は画面と ~/Library/Logs/asobiba-ship/beta-<日時>.log の両方へ全量出す
# （gym の xcodebuild ログも同じディレクトリに残る。置き場は fastlane/Fastfile の SHIP_LOG_DIR）。
#
# 使い方: Scripts/ship-beta.sh   （リポジトリのどこから実行してもよい）
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1
LOG_DIR="$HOME/Library/Logs/asobiba-ship"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/beta-$(date +%Y%m%d-%H%M%S).log"
echo "ログ: $LOG"
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
bundle exec fastlane beta 2>&1 | tee "$LOG"
exit "${PIPESTATUS[0]}"
