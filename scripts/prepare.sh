#!/bin/bash
# 准备环境脚本 - 切音频、开浏览器、开OBS、切换场景

URL="$1"
STATE_FILE="$HOME/.recording-pipeline/state.json"

if [[ -z "$URL" ]]; then
    echo "用法: $0 \u003cURL\u003e"
    exit 1
fi

# 切换到 BlackHole
echo "切换到 BlackHole 音频..."
SwitchAudioSource -s "BlackHole 2ch" -t output
if [[ $? -ne 0 ]]; then
    echo "❌ 音频切换失败"
    exit 1
fi
echo "✅ 音频已切换到 BlackHole"

# 打开浏览器
echo "打开浏览器: $URL"
open "$URL"
sleep 2

# 启动 OBS（--disable-shutdown-check 跳过 safe-mode 弹窗 + websocket 探活，P-001）
bash "$(dirname "$0")/launch_obs.sh" || echo "⚠️ OBS/websocket 未就绪，见 Telegram 告警"

# 使用 AppleScript 切换到「网页直播录制」场景
osascript << 'EOF'
tell application "OBS"
    activate
end tell

delay 2

tell application "System Events"
    tell process "OBS"
        -- 尝试点击场景
        try
            click menu item "网页直播录制" of menu 1 of menu bar item "场景" of menu bar 1
            delay 1
        on error
            -- 备选：快捷键切换到第二个场景
            keystroke "2" using {command down}
            delay 1
        end try
    end tell
end tell
EOF

# 自动修复 Chrome source 的 window ID（每次 Chrome 重启后 ID 会变）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_PY="python3"
if [[ -f "$VENV_PY" ]]; then
    echo "修复 OBS Chrome source window ID..."
    "$VENV_PY" "$SCRIPT_DIR/obs_control.py" fix_chrome || echo "⚠️  fix_chrome 失败，请手动在 OBS Properties 里选择 Chrome 窗口"
else
    echo "⚠️  venv python3 未找到，跳过 fix_chrome"
fi

# 更新状态
mkdir -p "$HOME/.recording-pipeline"
cat > "$STATE_FILE" << EOF
{
    "url": "$URL",
    "status": "prepared",
    "prepared_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo ""
echo "✅ 环境准备完成"
echo "  - 音频: BlackHole"
echo "  - 浏览器: 已打开 $URL"
echo "  - OBS: 已启动，场景已切换"
echo ""
echo "请在浏览器中扫码登录，完成后回复「准备好了」"
