#!/bin/bash
# mrec_stop.sh <tag> "名称1" "名称2" [名称3] —— 多流停录核心。
# 顺序对「保护单流」很关键：停录 → **先让 OBS 完全退出** → **再还原 global.ini** 回单流基线
# (OBS 已退出，不会再回写，还原确定生效) → 拆音轨投放 raw/ 让现有转写守护接手。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
STATE="$HOME/.multi-recording"
OBS_CFG="$HOME/Library/Application Support/obs-studio"
TAG="${1:-x}"; shift || true
LOG="$STATE/mrec_${TAG}.log"
PY=python3
exec >>"$LOG" 2>&1
echo "===== $(date '+%F %T') mrec_stop tag=$TAG names=$* ====="

# 1) 停录
"$PY" "$SK/mobs_control.py" stop || true
sleep 3   # 让 mkv 落盘/finalize

# 2) 优雅退出 OBS(退出后 global.ini 会被 OBS 写成 multi-live，下一步再覆盖回单流)
osascript -e 'quit app "OBS"' >/dev/null 2>&1 &
for i in $(seq 1 10); do pgrep -f "OBS.app/Contents/MacOS/OBS" >/dev/null || break; sleep 1; done
if pgrep -f "OBS.app/Contents/MacOS/OBS" >/dev/null; then
    pkill -9 -f "OBS.app/Contents/MacOS/OBS"; sleep 1
    rm -f "$OBS_CFG/.sentinel/"run_* 2>/dev/null
fi

# 3) 还原 global.ini 回单流基线(确定性，OBS 已退出)
"$PY" "$SK/global_basic.py" restore
echo "还原后 current: $("$PY" "$SK/global_basic.py" current)"

# 4) 杀防休眠 + 磁盘监控(P-003)
[ -f "$STATE/caffeinate.pid" ] && kill "$(cat "$STATE/caffeinate.pid")" 2>/dev/null && rm -f "$STATE/caffeinate.pid"
[ -f "$STATE/diskwatch.pid" ] && kill "$(cat "$STATE/diskwatch.pid")" 2>/dev/null && rm -f "$STATE/diskwatch.pid"

# 5) 拆音轨: 取 multi-raw 最新 mkv，按名称拆成单流文件投放 ~/Recordings/raw/
MKV=$(ls -t "$HOME/Recordings/multi-raw/"*.mkv 2>/dev/null | head -1)
if [ -n "$MKV" ] && [ $# -ge 1 ]; then
    echo "拆轨源: $MKV"
    bash "$SK/split_tracks.sh" "$MKV" "$@"
    bash "$SK/send_telegram.sh" "✅ 多直播录制已停止并拆轨完成（$*），各路已投放转写队列，稍后出字幕。global.ini 已还原回单流配置。"
else
    echo "⚠️ 未找到 multi-raw 里的 mkv 或未给名称，跳过拆轨"
    bash "$SK/send_telegram.sh" "⚠️ 多直播已停录，但未找到待拆的 mkv 或缺名称参数，请人工检查 ~/Recordings/multi-raw/。global.ini 已还原回单流配置。"
fi
