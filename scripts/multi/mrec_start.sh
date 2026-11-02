#!/bin/bash
# mrec_start.sh <tag> —— 多流开录核心(由 launchd 的 mrec<tag>_start.sh 到点调用)。
# 关键设计(保护单流)：
#  · 先 snapshot 当前(单流基线)global.ini 的 [Basic]，供停录/崩溃守护还原；
#  · 用 `--collection multi-live --profile multi` **命令行参数**启动 OBS，不手动预改
#    global.ini——OBS 起来后自己才把 global.ini 写成 multi-live，避免「OBS 没起且
#    global.ini=multi-live」的假崩溃窗口被守护误判。
#  · 音频走 App 采集(多音轨)，不碰 BlackHole、不切系统音频。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
STATE="$HOME/.multi-recording"
LOG="$STATE/mrec_${1:-x}.log"
PY=python3
exec >>"$LOG" 2>&1
echo "===== $(date '+%F %T') mrec_start $* ====="

# ── P-003 磁盘空间守护：录前硬闸（多路写得快+要拆轨，阈值比单路 5GB 高）──
ABORT_GB=15; WARN_GB=40; STOP_GB=12
free_gb(){ df -g "$HOME/Recordings" 2>/dev/null | awk 'NR==2{print $4+0}'; }
FREE=$(free_gb)
echo "磁盘剩余: ${FREE}GB (abort<${ABORT_GB} / warn<${WARN_GB})"
if [ "${FREE:-0}" -lt "$ABORT_GB" ]; then
    bash "$SK/send_telegram.sh" "❌ 多路录制已取消：磁盘仅剩 ${FREE}GB (<${ABORT_GB}GB)，两路并录会撑爆盘。请清理 ~/Recordings 后重排录制。"
    echo "磁盘不足(${FREE}GB<${ABORT_GB}GB)，取消开录"; exit 1
elif [ "${FREE:-0}" -lt "$WARN_GB" ]; then
    bash "$SK/send_telegram.sh" "⚠️ 多路录制：磁盘仅剩 ${FREE}GB (<建议 ${WARN_GB}GB)，两路长录可能不够，已继续开录，请尽快清理空间以防中途撑爆。"
fi

# 0) 若已有 OBS 在跑，先优雅退出(单流/多流互斥；避免占用单流的 OBS 实例)
if pgrep -f "OBS.app/Contents/MacOS/OBS" >/dev/null; then
    echo "检测到 OBS 已在运行，先退出以独占多流会话"
    osascript -e 'quit app "OBS"' >/dev/null 2>&1 &
    for i in $(seq 1 8); do pgrep -f "OBS.app/Contents/MacOS/OBS" >/dev/null || break; sleep 1; done
    pkill -9 -f "OBS.app/Contents/MacOS/OBS" 2>/dev/null
    rm -f "$HOME/Library/Application Support/obs-studio/.sentinel/"run_* 2>/dev/null
fi

# 1) 快照单流基线 [Basic]
"$PY" "$SK/global_basic.py" snapshot

# 2) 防休眠/降频(App Nap 会让后台窗口丢帧)，绑到会话，停录时杀
caffeinate -dimsu &
echo $! > "$STATE/caffeinate.pid"

# 3) 启动 OBS 明确加载 multi-live + 多音轨 multi 配置
#    --disable-shutdown-check：跳过上次非干净退出触发的 safe-mode 弹窗，否则模态框会阻塞
#    obs-websocket(4455) 初始化，开录静默失败（LL-109，与单流 launch_obs.sh 对齐，2026-10-22 补）。
open /Applications/OBS.app --args --collection multi-live --profile multi --disable-missing-files-check --disable-shutdown-check
for i in $(seq 1 20); do
    if lsof -nP -iTCP:4455 -sTCP:LISTEN >/dev/null 2>&1; then break; fi
    sleep 1
done
if ! lsof -nP -iTCP:4455 -sTCP:LISTEN >/dev/null 2>&1; then
    bash "$SK/send_telegram.sh" "⚠️ 多流录制：OBS 起来后 20s 内 websocket(4455) 仍未监听，开录可能失败，请人工看一眼 OBS 是否弹窗卡住" 2>/dev/null || true
fi
sleep 3

# 4) 兜底重绑 cap1/cap2 到各自 App + 独立音轨(幂等)
"$PY" "$SK/mobs_control.py" bind cap1 "[Google Chrome]" 1
"$PY" "$SK/mobs_control.py" bind cap2 "[Safari]" 2

# 5) 开录
"$PY" "$SK/mobs_control.py" start
sleep 2
STATUS=$("$PY" "$SK/mobs_control.py" status)
echo "开录状态: $STATUS"
bash "$SK/send_telegram.sh" "🎬 多直播录制已开始（$*）：$STATUS。两路各录独立音轨，结束后自动拆轨转写。"

# ── P-003 录制中磁盘监控：每 120s 查剩余，低于 STOP_GB 强制停录保住已录部分 ──
#    绑会话(pid 写文件)，mrec_stop.sh 停录时一并 kill（同 caffeinate）。
( while true; do
    sleep 120
    f=$(free_gb)
    if [ "${f:-99}" -lt "$STOP_GB" ]; then
        "$PY" "$SK/mobs_control.py" stop 2>/dev/null
        bash "$SK/send_telegram.sh" "⚠️ 多路录制：磁盘仅剩 ${f}GB (<${STOP_GB}GB)，已强制停录保住已录部分，请立即清理空间。"
        break
    fi
  done ) &
echo $! > "$STATE/diskwatch.pid"
echo "磁盘监控已起 (pid $(cat "$STATE/diskwatch.pid"), 每120s, floor ${STOP_GB}GB)"
