#!/bin/bash
# GitHub Actions self-hosted runner をこの Mac にセットアップする。
# 実行前に docs/ai-devops.md の「セキュリティ上の注意」を読むこと（PUBLIC リポジトリのため）。
# 前提: gh CLI で hiroky1983 として認証済み（repo admin 権限）
set -euo pipefail

REPO="hiroky1983/game_collection"
RUNNER_DIR="$HOME/actions-runner-game_collection"

if [ -d "$RUNNER_DIR/.runner" ]; then
  echo "既にランナーが構成済みです: $RUNNER_DIR"
  exit 0
fi

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# 最新のランナーを取得 (Apple Silicon)
TAG=$(gh api repos/actions/runner/releases/latest --jq .tag_name)   # e.g. v2.320.0
VER="${TAG#v}"
if [ ! -f "./config.sh" ]; then
  curl -fL -o runner.tar.gz \
    "https://github.com/actions/runner/releases/download/${TAG}/actions-runner-osx-arm64-${VER}.tar.gz"
  tar xzf runner.tar.gz && rm runner.tar.gz
fi

# 登録トークンを取得して構成
TOKEN=$(gh api "repos/${REPO}/actions/runners/registration-token" -X POST --jq .token)
./config.sh --unattended \
  --url "https://github.com/${REPO}" \
  --token "$TOKEN" \
  --name "$(hostname -s)-asobiba" \
  --labels "self-hosted,macOS"

# launchd サービスとして常駐化（ログイン中に自動起動）
./svc.sh install
./svc.sh start
echo "完了。確認: gh api repos/${REPO}/actions/runners --jq '.runners[].status'"
