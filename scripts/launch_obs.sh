#!/bin/bash
# launch_obs.sh — 幂等启动 OBS（P-001 修复 B/C）
#   B) 带 --disable-shutdown-check：跳过崩溃/安全模式检测，safe-mode 弹窗永不出现，
#      不会再阻塞 obs-websocket 初始化。--args 只在冷启那次被 OBS 接收，pgrep 守卫
#      保证不会开出第二个实例。
#   C) 启动后探测 obs-websocket(4455) 是否在 WAIT_SECS 内 listen；超时 Telegram 告警，
#      把"连不上"从静默失败变红灯（LL-009/010）。
# 退出码：0 = OBS 且 websocket 就绪；1 = websocket 未就绪（已告警）。
set -uo pipefail
SK="$(cd "$(dirname "$0")" && pwd)"
WS_PORT="${OBS_WS_PORT:-4455}"
WAIT_SECS="${OBS_WS_WAIT:-15}"

if ! pgrep -x "OBS" >/dev/null; then
    echo "启动 OBS（--disable-shutdown-check，跳过 safe-mode 弹窗）…"
    open -a /Applications/OBS.app --args --disable-shutdown-check
else
    echo "OBS 已在运行"
fi

ws_up() { lsof -nP -iTCP:"$WS_PORT" -sTCP:LISTEN 2>/dev/null | grep -qi obs; }

for ((i=0; i<WAIT_SECS; i++)); do
    if ws_up; then
        echo "✅ obs-websocket (${WS_PORT}) 就绪"
        exit 0
    fi
    sleep 1
done

echo "❌ obs-websocket (${WS_PORT}) 在 ${WAIT_SECS}s 内未就绪（疑似 safe-mode 弹窗或崩溃）" >&2
"$SK/send_telegram.sh" "⚠️ OBS 开录异常：websocket(${WS_PORT}) 在 ${WAIT_SECS}s 内没起来，疑似卡在 safe-mode 弹窗或崩溃。自动录制可能失败，请上机看一眼 OBS。" 2>/dev/null || true
exit 1
