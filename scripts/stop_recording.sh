#!/bin/bash
# 停止录制并清理

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$HOME/.recording-pipeline/state.json"
SCHEDULE_FILE="$HOME/.recording-pipeline/schedule.json"
PID_FILE="$HOME/.recording-pipeline/obs_recording.pid"

echo "停止 OBS 录制..."

# 通过 WebSocket 停止录制
python3 "$SCRIPT_DIR/obs_control.py" stop || exit 1

rm -f "$PID_FILE"

# 更新状态
for f in "$STATE_FILE" "$SCHEDULE_FILE"; do
    [[ -f "$f" ]] && python3 -c "
import json
with open('$f', 'r') as fh:
    data = json.load(fh)
data['status'] = 'stopped'
data['stopped_at'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$f', 'w') as fh:
    json.dump(data, fh, indent=2)
"
done

# 切回扬声器
echo "切回扬声器..."
SwitchAudioSource -s "Mac mini Speakers" -t output
echo "✅ 音频已切回扬声器"

# 干净退出 OBS，写入 clean-exit sentinel，避免下次启动弹 safe-mode（P-001 修复 A）
bash "$SCRIPT_DIR/quit_obs.sh" || echo "⚠️ OBS 未在预期时间内退出，请手动确认"

echo ""
echo "转写将在录制文件生成后自动开始"
echo "字幕文件将保存在 ~/Recordings/transcripts/"
