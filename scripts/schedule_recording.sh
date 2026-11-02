#!/bin/bash
# 预约录制主脚本 - 解析时间并设置定时任务

URL="$1"
DURATION="$2"
START_TIME="$3"
SCHEDULE_FILE="$HOME/.recording-pipeline/schedule.json"

if [[ -z "$URL" || -z "$DURATION" || -z "$START_TIME" ]]; then
    echo "用法: $0 \u003cURL\u003e \u003c时长\u003e \u003c开始时间\u003e"
    echo "  开始时间: 20:00 | +30m | now"
    exit 1
fi

# 解析时长为分钟
parse_duration() {
    local dur="$1"
    local minutes=0
    
    if [[ "$dur" =~ ^([0-9]+)h$ ]]; then
        minutes=$((${BASH_REMATCH[1]} * 60))
    elif [[ "$dur" =~ ^([0-9]+)m$ ]]; then
        minutes=${BASH_REMATCH[1]}
    elif [[ "$dur" =~ ^([0-9]+)\.([0-9]+)h$ ]]; then
        local hours=${BASH_REMATCH[1]}
        local frac=${BASH_REMATCH[2]}
        minutes=$((hours * 60 + frac * 6))
    else
        minutes=$((dur * 60))
    fi
    
    echo $minutes
}

# 解析开始时间为 Unix 时间戳
parse_start_time() {
    local time_str="$1"
    local target_time
    
    if [[ "$time_str" == "now" ]]; then
        echo "now"
        return
    elif [[ "$time_str" =~ ^\+([0-9]+)m$ ]]; then
        # +30m 格式 - N分钟后
        local mins=${BASH_REMATCH[1]}
        target_time=$(date -v+${mins}M +"%Y-%m-%d %H:%M:%S")
    elif [[ "$time_str" =~ ^([0-9]+):([0-9]+)$ ]]; then
        # 20:00 格式 - 今天的时间
        local hour=${BASH_REMATCH[1]}
        local min=${BASH_REMATCH[2]}
        target_time=$(date -j -f "%H:%M" "${hour}:${min}" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")
        
        # 如果解析失败，尝试今天
        if [[ -z "$target_time" ]]; then
            target_time="$(date +%Y-%m-%d) ${hour}:${min}:00"
        fi
    else
        # 其他格式，尝试直接解析
        target_time="$time_str"
    fi
    
    echo "$target_time"
}

DURATION_MINUTES=$(parse_duration "$DURATION")
START_TIME_PARSED=$(parse_start_time "$START_TIME")

# 计算提醒时间
REMINDER_MINUTES=$((DURATION_MINUTES - 30))
if [[ $REMINDER_MINUTES -lt 0 ]]; then
    REMINDER_MINUTES=0
fi

# 创建预约文件
mkdir -p "$HOME/.recording-pipeline"
cat > "$SCHEDULE_FILE" << EOF
{
    "url": "$URL",
    "duration_minutes": $DURATION_MINUTES,
    "reminder_minutes": $REMINDER_MINUTES,
    "start_time": "$START_TIME_PARSED",
    "scheduled_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "status": "scheduled"
}
EOF

echo "✅ 预约已创建"
echo "  URL: $URL"
echo "  时长: ${DURATION_MINUTES}分钟"
echo "  开始时间: $START_TIME_PARSED"

if [[ "$START_TIME" == "now" ]]; then
    echo "  状态: 立即开始"
else
    echo "  状态: 已预约，等待开始时间"
    
    # 设置定时任务
    if [[ "$START_TIME" =~ ^\+([0-9]+)m$ ]]; then
        # 相对时间，使用后台进程
        mins=${BASH_REMATCH[1]}
        (
            sleep $((mins * 60))
            "$HOME/.claude/skills/screen-recording-pipeline/scripts/start_recording.sh"
        ) &
        echo "  定时任务: ${mins}分钟后自动开始"
    else
        # 绝对时间，使用 at 命令
        at_time=$(date -j -f "%Y-%m-%d %H:%M:%S" "$START_TIME_PARSED" +"%H:%M %Y-%m-%d" 2>/dev/null || echo "")
        if [[ -n "$at_time" ]]; then
            echo "$HOME/.claude/skills/screen-recording-pipeline/scripts/start_recording.sh" | at "$at_time" 2>/dev/null
            echo "  定时任务: at $at_time"
        else
            echo "  ⚠️ 无法设置定时任务，请在开始时间手动运行 start_recording.sh"
        fi
    fi
fi
