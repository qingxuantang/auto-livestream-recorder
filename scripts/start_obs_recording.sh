#!/bin/bash
# OBS 开始录制（用户确认后执行）

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$HOME/.recording-pipeline/state.json"
PID_FILE="$HOME/.recording-pipeline/obs_recording.pid"

# 更新状态
if [[ -f "$STATE_FILE" ]]; then
    python3 -c "
import json
with open('$STATE_FILE', 'r') as f:
    data = json.load(f)
data['status'] = 'recording'
data['recording_started_at'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$STATE_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
fi

# 确保 OBS 已启动（--disable-shutdown-check + websocket 探活，P-001）
bash "$SCRIPT_DIR/launch_obs.sh" || exit 1

# 通过 WebSocket 开始录制
python3 "$SCRIPT_DIR/obs_control.py" start || exit 1

echo $$ > "$PID_FILE"

# 设置定时提醒（如果有）
if [[ -f "$STATE_FILE" ]]; then
    REMINDER_MINUTES=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('reminder_minutes', 0))" 2>/dev/null)
    if [[ "$REMINDER_MINUTES" -gt 0 ]]; then
        echo "将在 ${REMINDER_MINUTES} 分钟后发送提醒"
        (
            sleep $((REMINDER_MINUTES * 60))
            "$SCRIPT_DIR/send_telegram.sh" "⏰ 录制提醒：已录制 ${REMINDER_MINUTES} 分钟，预计还有 30 分钟结束。继续请回复「继续」，结束请回复「结束」"
            echo "$(date)" > "$HOME/.recording-pipeline/reminder_triggered"
        ) &
    fi
fi
