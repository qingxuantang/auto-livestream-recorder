#!/bin/bash
# autoplay_click.sh <源1> "<x1,y1>" <源2> "<x2,y2>"
# 多流自动点播放兜底(等价单流 cliclick 兜底)。用 OBS 音量表引导：每轮只点「还静音」的那一路
# (播放键还在→点它启动)，已出声的不再点(避免把在播的点成暂停)。
#
# 2026-08-22 教训(冬咚首场)：直播实际可播时间可能远晚于计划开始点(当天约 53 分钟才播上)，
# 旧版只重试 2 分钟就放弃 → 全程没点上。本版把重试窗口拉长到 ~35 分钟，并分阶段 Telegram
# 提醒 Mark 手点兜底；点静音路的中心点是安全的(实测不误导航)，长时间重试无副作用。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
PY=python3
CC=/opt/homebrew/bin/cliclick
# 支持 1 路或 2 路：只传前两参=只管一路（如某路晚开、由 late_play 单独处理）。
S1="$1"; XY1="$2"; S2="${3:-}"; XY2="${4:-}"
LOG="$HOME/.multi-recording/autoplay.log"
MAX_ROUNDS=${MAX_ROUNDS:-70}      # ~70 轮 × ~30s ≈ 35 分钟
echo "$(date '+%F %T') autoplay 开始 $S1@$XY1 ${S2:+$S2@$XY2} (max ${MAX_ROUNDS}轮)" >> "$LOG"

is_silent() {  # 采样峰值 dB, 返回 1=静音需点 / 0=已出声
    local db
    db=$("$PY" "$SK/mobs_control.py" meters "$1" 2 2>/dev/null)
    [ -z "$db" ] && db=-200
    awk -v d="$db" 'BEGIN{print (d+0 < -50)?1:0}'
}
nudge() { bash "$SK/send_telegram.sh" "$1" >/dev/null 2>&1; }

sleep 8
# 早期诊断截图(便于事后排查摆窗/坐标是否对)
screencapture -x "$HOME/.multi-recording/autoplay_shot.png" 2>/dev/null || true

warned3=0; warned10=0; warned20=0
start=$(date +%s)
for a in $(seq 1 "$MAX_ROUNDS"); do
    s1=$(is_silent "$S1")
    if [ -n "$S2" ]; then s2=$(is_silent "$S2"); else s2=0; fi
    elapsed=$(( $(date +%s) - start ))
    echo "$(date '+%T') 第${a}轮(${elapsed}s): $S1 静音=$s1${S2:+, $S2 静音=$s2}" >> "$LOG"
    if [ "$s1" = 0 ] && [ "$s2" = 0 ]; then echo "各路均已出声, 结束" >> "$LOG"; break; fi
    [ "$s1" = 1 ] && "$CC" c:$XY1 >> "$LOG" 2>&1
    [ -n "$S2" ] && [ "$s2" = 1 ] && "$CC" c:$XY2 >> "$LOG" 2>&1
    # 分阶段提醒 Mark 兜底(仍有静音路时)
    if [ "$elapsed" -ge 180 ] && [ "$warned3" = 0 ]; then warned3=1
        nudge "⏳ 多流开录已 3 分钟，仍有直播没出声，自动点播放还在重试。若你在场，麻烦手点一下还没播的那路兜底（左Chrome/右Safari）。"
    fi
    if [ "$elapsed" -ge 600 ] && [ "$warned10" = 0 ]; then warned10=1
        nudge "⏳ 已 10 分钟仍有路没出声。可能直播还没开始，或需要你手点播放。自动重试继续中。"
    fi
    if [ "$elapsed" -ge 1200 ] && [ "$warned20" = 0 ]; then warned20=1
        nudge "⚠️ 已 20 分钟仍有路没出声。请确认对应直播是否已开始、并手点播放键兜底。"
    fi
    sleep 22
done

f1=$(is_silent "$S1")
if [ -n "$S2" ]; then f2=$(is_silent "$S2"); else f2=0; fi
echo "$(date '+%T') autoplay 结束: $S1 静音=$f1${S2:+, $S2 静音=$f2}" >> "$LOG"
if [ "$f1" = 1 ] || [ "$f2" = 1 ]; then
    STILL=""; [ "$f1" = 1 ] && STILL="$STILL Chrome路"; { [ -n "$S2" ] && [ "$f2" = 1 ]; } && STILL="$STILL Safari路"
    nudge "⚠️ 自动点播放重试到头，这些路仍无声:$STILL 。若该直播确在播，请手动点一下对应浏览器的播放键。"
fi
