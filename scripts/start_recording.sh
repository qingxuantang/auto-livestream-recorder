#!/bin/bash
# 开始 OBS 录制 - 由定时任务或用户触发

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$HOME/.recording-pipeline/state.json"
SCHEDULE_FILE="$HOME/.recording-pipeline/schedule.json"
PID_FILE="$HOME/.recording-pipeline/obs_recording.pid"

# 读取录制参数
if [[ -f "$SCHEDULE_FILE" ]]; then
    DURATION_MINUTES=$(python3 -c "import json; print(json.load(open('$SCHEDULE_FILE')).get('duration_minutes', 120))")
    REMINDER_MINUTES=$(python3 -c "import json; print(json.load(open('$SCHEDULE_FILE')).get('reminder_minutes', 90))")
    python3 -c "
import json
with open('$SCHEDULE_FILE', 'r') as f:
    data = json.load(f)
data['status'] = 'recording'
data['recording_started_at'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$SCHEDULE_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
else
    DURATION_MINUTES=120
    REMINDER_MINUTES=90
fi

# 确保 OBS 在运行（--disable-shutdown-check + websocket 探活，P-001）
bash "$SCRIPT_DIR/launch_obs.sh" || exit 1

# 通过 WebSocket 开始录制
python3 "$SCRIPT_DIR/obs_control.py" start || exit 1

echo $$ > "$PID_FILE"

# 更新状态文件
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

echo "  开始时间: $(date '+%H:%M')"
echo "  预估时长: ${DURATION_MINUTES} 分钟"

# 设置定时提醒（Telegram 推送）
if [[ $REMINDER_MINUTES -gt 0 && $REMINDER_MINUTES -lt $DURATION_MINUTES ]]; then
    echo "  提醒时间: ${REMINDER_MINUTES} 分钟后 ($(date -v+${REMINDER_MINUTES}M +'%H:%M'))"
    (
        sleep $((REMINDER_MINUTES * 60))
        "$SCRIPT_DIR/send_telegram.sh" "⏰ 录制提醒：已录制 ${REMINDER_MINUTES} 分钟，预计还有 30 分钟结束。继续请回复「继续」，结束请回复「结束」"
        echo "$(date)" > "$HOME/.recording-pipeline/reminder_triggered"
    ) &
fi
