#!/bin/bash
# 设置定时提醒

MINUTES="$1"

if [[ -z "$MINUTES" ]]; then
    echo "用法: $0 \u003c分钟数\u003e"
    exit 1
fi

# 创建提醒脚本
REMINDER_SCRIPT="$HOME/.recording-pipeline/reminder.sh"
mkdir -p "$HOME/.recording-pipeline"

cat > "$REMINDER_SCRIPT" << 'EOF'
#!/bin/bash
osascript -e 'display notification "⏰ 录制提醒：预计还有30分钟结束。继续请回复『继续』，结束请回复『结束』" with title "录制进度"'
# 同时写入提醒标记文件
echo "$(date)" > "$HOME/.recording-pipeline/reminder_triggered"
EOF

chmod +x "$REMINDER_SCRIPT"

# 计算提醒时间
REMINDER_TIME=$(date -v+${MINUTES}M +"%H:%M %Y-%m-%d")

# 使用 at 设置定时任务
echo "$REMINDER_SCRIPT" | at "$REMINDER_TIME" 2>/dev/null

if [[ $? -eq 0 ]]; then
    echo "✅ 定时提醒已设置: ${REMINDER_TIME}"
else
    echo "⚠️ at 命令不可用，将使用替代方案"
    # 创建后台等待进程
    (
        sleep $((MINUTES * 60))
        "$REMINDER_SCRIPT"
    ) &
    echo "✅ 后台提醒进程已启动"
fi
