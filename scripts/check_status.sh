#!/bin/bash
# 查询录制预约和当前状态

SCHEDULE_FILE="$HOME/.recording-pipeline/schedule.json"
STATE_FILE="$HOME/.recording-pipeline/state.json"

echo "=== 录制状态查询 ==="
echo ""

# 检查预约信息
if [[ -f "$SCHEDULE_FILE" ]]; then
    echo "📅 预约信息:"
    python3 -c "
import json
import sys
try:
    with open('$SCHEDULE_FILE', 'r') as f:
        data = json.load(f)
    print(f\"  URL: {data.get('url', 'N/A')}\")
    print(f\"  时长: {data.get('duration_minutes', 'N/A')} 分钟\")
    print(f\"  开始时间: {data.get('start_time', 'N/A')}\")
    print(f\"  状态: {data.get('status', 'N/A')}\")
    if 'recording_started_at' in data:
        print(f\"  实际开始: {data.get('recording_started_at')}\")
    if 'stopped_at' in data:
        print(f\"  结束时间: {data.get('stopped_at')}\")
except Exception as e:
    print(f'  无法读取: {e}')
"
else
    echo "📅 暂无预约"
fi

echo ""

# 检查当前状态
if [[ -f "$STATE_FILE" ]]; then
    echo "📊 当前状态:"
    python3 -c "
import json
try:
    with open('$STATE_FILE', 'r') as f:
        data = json.load(f)
    print(f\"  状态: {data.get('status', 'N/A')}\")
    print(f\"  URL: {data.get('url', 'N/A')}\")
    if 'prepared_at' in data:
        print(f\"  准备时间: {data.get('prepared_at')}\")
    if 'recording_started_at' in data:
        print(f\"  开始时间: {data.get('recording_started_at')}\")
except Exception as e:
    print(f'  无法读取: {e}')
"
else
    echo "📊 当前无进行中的录制"
fi

echo ""
echo "=== 最近的录制文件 ==="
ls -lt ~/Recordings/raw/*.mkv 2>/dev/null | head -3 || echo "  暂无录制文件"

echo ""
echo "=== 最近的字幕文件 ==="
ls -lt ~/Recordings/transcripts/*/*.srt 2>/dev/null | head -3 || echo "  暂无字幕文件"
