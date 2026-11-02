#!/bin/bash
# quit_obs.sh — 优雅退出 OBS（P-001 修复 A）
#   停录后调用，让 OBS 正常退出以写入"干净退出" sentinel，下次启动就不会被判
#   unclean、也就不会弹 safe-mode 对话框（该对话框会阻塞 obs-websocket，见 P-001）。
#   ⚠️ 绝不 kill -9：强杀本身就是 unclean，会适得其反。
# 前置：调用前录制应已停止（stop_recording.sh 已发 StopRecord），否则 quit 可能弹
#       "正在录制"确认框。
# 退出码：0 = 已干净退出（或本就没运行）；1 = 超时未退出（未强杀，需人工确认）。
set -uo pipefail
WAIT_SECS="${OBS_QUIT_WAIT:-10}"

if ! pgrep -x "OBS" >/dev/null; then
    echo "OBS 未运行，无需退出"
    exit 0
fi

echo "优雅退出 OBS…"
osascript -e 'tell application "OBS" to quit' 2>/dev/null || true

for ((i=0; i<WAIT_SECS; i++)); do
    if ! pgrep -x "OBS" >/dev/null; then
        echo "✅ OBS 已干净退出"
        exit 0
    fi
    sleep 1
done

echo "⚠️ OBS 在 ${WAIT_SECS}s 内未退出（可能有未保存/确认对话框）。为避免 unclean 未强杀，请手动确认。" >&2
exit 1
