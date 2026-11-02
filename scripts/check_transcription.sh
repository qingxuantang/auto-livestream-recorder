#!/bin/bash
# 检查转写状态

VIDEO_NAME="$1"
STATE_FILE="$HOME/.recording-pipeline/state.json"

if [[ -z "$VIDEO_NAME" ]]; then
    # 从状态文件获取
    if [[ -f "$STATE_FILE" ]]; then
        VIDEO_NAME=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('video_name', ''))" 2>/dev/null)
    fi
fi

if [[ -z "$VIDEO_NAME" ]]; then
    # 查找最新的 SRT 文件
    LATEST_SRT=$(find "$HOME/Recordings/transcripts" -name "*.srt" -mtime -1 | sort -r | head -1)
    
    if [[ -n "$LATEST_SRT" ]]; then
        echo "completed"
        echo "文件: $LATEST_SRT"
        
        # 统计字数
        WORD_COUNT=$(wc -m < "$LATEST_SRT" | tr -d ' ')
        echo "字数: $WORD_COUNT"
        
        # 获取时长
        DURATION=$(grep -o '\d\{2\}:\d\{2\}:\d\{2\}' "$LATEST_SRT" | tail -1 || echo "未知")
        echo "时长: $DURATION"
    else
        echo "pending"
        echo "转写尚未完成或文件不存在"
    fi
else
    SRT_FILE="$HOME/Recordings/transcripts/$(date +%Y-%m-%d)/${VIDEO_NAME}.srt"
    
    if [[ -f "$SRT_FILE" ]]; then
        echo "completed"
        echo "文件: $SRT_FILE"
    else
        echo "pending"
        echo "文件不存在: $SRT_FILE"
    fi
fi
