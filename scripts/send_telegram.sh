#!/bin/bash
# send_telegram.sh "<message>" — 通用可选通知器（去私有版）。
#
# 默认：只写本地日志（$HOME/Recordings/process.log），不向任何外部服务发送。
# 可选：若用户自行配置了下列环境变量，则额外推送通知——凭证由**用户自己**提供，
#       技能本身不内置任何 token / chat_id。
#
#   NOTIFY_TELEGRAM_TOKEN   + NOTIFY_TELEGRAM_CHAT_ID   → 发到用户自己的 Telegram
#   NOTIFY_WEBHOOK_URL                                   → POST {"text": "..."} 到用户自己的 webhook
#
# 配置方式：在部署 setup 时把这些变量写进技能运行环境（见 references/SETUP.md）。
MESSAGE="$1"
LOG="$HOME/Recordings/process.log"

# 1) 本地日志（始终）
mkdir -p "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [notify] $MESSAGE" >> "$LOG" 2>/dev/null
echo "📝 $MESSAGE"

sent=0
# 2) 可选 Telegram（用户自备凭证）
if [[ -n "$NOTIFY_TELEGRAM_TOKEN" && -n "$NOTIFY_TELEGRAM_CHAT_ID" ]]; then
    curl -s -X POST "https://api.telegram.org/bot${NOTIFY_TELEGRAM_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${NOTIFY_TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${MESSAGE}" > /dev/null 2>&1 && sent=1
fi
# 3) 可选通用 webhook（用户自备 URL）
if [[ -n "$NOTIFY_WEBHOOK_URL" ]]; then
    curl -s -X POST "$NOTIFY_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        --data "$(printf '{"text":%s}' "$(printf '%s' "$MESSAGE" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')")" \
        > /dev/null 2>&1 && sent=1
fi

[[ "$sent" == "1" ]] && echo "✅ 通知已发送" || true
exit 0
