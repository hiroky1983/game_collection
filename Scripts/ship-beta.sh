#!/bin/bash
# `fastlane beta` をログ全量保存つきで実行する（#1041 C）。
# `| tail -60` で切ると EXPORT FAILED の理由が消え、原因特定に往復が出る（2026-09-16）。
# 出力は画面と ~/Library/Logs/asobiba-ship/beta-<日時>.log の両方へ全量出す
# （gym の xcodebuild ログも同じディレクトリに残る。置き場は fastlane/Fastfile の SHIP_LOG_DIR）。
#
# 使い方: Scripts/ship-beta.sh   （リポジトリのどこから実行してもよい）
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

# 版数（MARKETING_VERSION / CURRENT_PROJECT_VERSION）の更新を人の記憶に頼らない（2026-10-06・会長指示）。
# release/vX.Y.Z から上げるときは必ず bump-marketing-version.sh を通す。ずれていれば版数更新 PR を出して
# マージまで待ち（後方の番号は出さない検査つき）、正しければ何もしない。v1.1.1・v1.1.2・v1.1.10 で
# 前の版のまま fastlane beta の直前まで気づかなかった再発防止。
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
case "$BRANCH" in
  release/v*)
    bash Scripts/bump-marketing-version.sh --wait || exit 1
    git fetch -q origin "$BRANCH" || exit 1
    if ! git diff --quiet HEAD "origin/$BRANCH" -- project.yml; then
      # 版数更新 PR のマージを手元へ取り込む（fast-forward できなければ手元の状態を確認させる）
      git merge -q --ff-only "origin/$BRANCH" \
        || { echo "ship-beta: origin/$BRANCH を fast-forward で取り込めません。手元の $BRANCH を確認してください" >&2; exit 1; }
    fi
    ;;
esac
LOG_DIR="$HOME/Library/Logs/asobiba-ship"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/beta-$(date +%Y%m%d-%H%M%S).log"
echo "ログ: $LOG"
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"
bundle exec fastlane beta 2>&1 | tee "$LOG"
exit "${PIPESTATUS[0]}"
