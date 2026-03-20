#!/bin/bash
# Horizon run + Feishu webhook notification
# Usage: ./scripts/run-with-notify.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

cd "$PROJECT_DIR"

# Load env vars
source .env

# Set GITHUB_TOKEN for horizon
export GITHUB_TOKEN

echo "$LOG_PREFIX Starting Horizon..."

# Run Horizon
uv run horizon --hours 24

# Find latest summary (ZH)
SUMMARY_FILE=$(ls -t data/summaries/horizon-*-zh.md | head -1)

if [ -z "$SUMMARY_FILE" ]; then
    echo "$LOG_PREFIX No summary found!"
    exit 1
fi

echo "$LOG_PREFIX Sending summary to Feishu..."

# Send summary to Feishu webhook using curl
SUMMARY_CONTENT=$(cat "$SUMMARY_FILE")

python3 << PYEOF
import json
import subprocess

content = """$SUMMARY_CONTENT"""

# Extract selected items
items = []
in_item = False
current_item = ""
for line in content.split("\n"):
    if line.startswith("## ["):
        in_item = True
        current_item = line.replace("## ", "")
    elif in_item and line.startswith("**"):
        current_item += "\n" + line
        items.append(current_item)
        in_item = False
        if len(items) >= 2:
            break

# Build message
count = content.split('items,')[0].split()[-1] if 'items,' in content else "?"
msg = f"📰 Horizon 每日速递\n\n从 {count} 条内容中精选 {len(items)} 条:\n\n"
for i, item in enumerate(items, 1):
    msg += f"{i}. {item}\n\n"
msg += "📄 完整版: https://jensonxue.github.io/Horizon/"

# Save to temp file
with open("/tmp/feishu_msg.json", "w") as f:
    json.dump({"msg_type": "text", "content": {"text": msg}}, f)

print("Message prepared")
PYEOF

# Send to webhook
curl -X POST "https://open.feishu.cn/open-apis/bot/v2/hook/4889aafd-11e9-4c78-b181-edc7fcfe6950" \
    -H "Content-Type: application/json" \
    -d @/tmp/feishu_msg.json

echo "$LOG_PREFIX Done."
