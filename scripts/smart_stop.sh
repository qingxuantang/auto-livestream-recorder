#!/bin/bash
# smart_stop.sh — 智能停录：到达计划时长后，按 BlackHole 音频活动判断直播是否真的结束。
# 用法: smart_stop.sh "<直播名称>"
#
# 逻辑(2026-07-02 Mark 需求)：
#   到达计划时长 → 循环：
#     采集 BlackHole 整 3 分钟，取窗口 max_volume：
#       · 若 max_volume ≤ 静音阈值(整3分钟全静音) → 判定直播结束 → 真正停录 → 退出
#       · 若期间有任何声音 → Telegram 通知并延长 30 分钟(录制不停) → 再测 3 分钟
#   安全阀：最多延长 MAX_EXT 次后强停；磁盘剩余 < MIN_FREE_GB 强停。
#
# 关键点：整个判定/延长期间 OBS 录制从不停止，只有确认静音那一刻才真正 stop，
#         因此不产生录制断点。BlackHole 支持多客户端，采样与 OBS 录制可并发，互不影响。

export PATH=/opt/homebrew/bin:/usr/bin:/bin:$PATH
SK="$(cd "$(dirname "$0")" && pwd)"

STREAM_NAME="${1:-直播}"

# ===== 可调参数 =====
SILENCE_DB=-60        # 静音阈值(dB)：max_volume 低于此值视为静音。实测直播≈-12dB、数字静音≈-90dB
CHECK_SECONDS=180     # 每次判定的采样窗口：3 分钟
EXTEND_SECONDS=1800   # 每次延长：30 分钟
MAX_EXT=6             # 最多自动延长次数(+3h 封顶)，到顶强停
MIN_FREE_GB=5         # 磁盘剩余低于此值(GB)强停

log() { echo "[smart_stop $(date '+%F %T')] $*"; }

# 解析 BlackHole 在 avfoundation 里的音频设备索引(索引可能随设备增减变化，动态解析)
# 设备行形如: [AVFoundation indev @ 0x..] [0] BlackHole 2ch —— 取行内数字方括号即索引
bh_index() {
    ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
      | grep 'BlackHole 2ch' | grep -oE '\[[0-9]+\]' | head -1 | tr -d '[]'
}

# 采集 BlackHole 指定秒数，返回窗口 max_volume(整数 dB，静音时给一个很低的值)
measure_maxvol() {
    local idx="$1" secs="$2" out mv
    out=$(ffmpeg -hide_banner -f avfoundation -i ":${idx}" -t "$secs" -af volumedetect -f null - 2>&1)
    mv=$(echo "$out" | grep -oE 'max_volume: -?[0-9.]+ dB' | grep -oE '\-?[0-9.]+' | head -1)
    if [ -z "$mv" ]; then
        # 采集失败(设备被占/报错)：返回一个"有声"值，宁可延长也不误停
        echo "0"
    else
        # 取整(bash 不支持浮点比较)
        printf '%.0f\n' "$mv"
    fi
}

# 磁盘剩余 GB(Recordings 所在卷)
free_gb() {
    df -g "$HOME/Recordings" 2>/dev/null | awk 'NR==2{print $4}'
}

# 真正停录 + 切回扬声器 + 通知
do_real_stop() {
    local reason="$1"
    log "真正停录：$reason"
    bash "$SK/stop_recording.sh" >> "$HOME/Recordings/process.log" 2>&1 || true
    SwitchAudioSource -s "Mac mini Speakers" -t output 2>/dev/null
    "$SK/send_telegram.sh" "⏹️ ${STREAM_NAME}录制已停止。${reason} 音频已切回扬声器。转写+归档由后台守护进程自动处理,完成后发你字幕。" 2>/dev/null || true
}

IDX=$(bh_index)
if [ -z "$IDX" ]; then
    log "未找到 BlackHole 设备索引，退化为直接停录"
    do_real_stop "(未能启动静音判定，已直接停录)"
    exit 0
fi
log "BlackHole 索引=$IDX，阈值=${SILENCE_DB}dB，窗口=${CHECK_SECONDS}s，最多延长 ${MAX_EXT} 次"

ext=0
while true; do
    fg=$(free_gb)
    if [ -n "$fg" ] && [ "$fg" -lt "$MIN_FREE_GB" ]; then
        do_real_stop "⚠️磁盘剩余仅 ${fg}GB(<${MIN_FREE_GB}GB),强制停止以防录满。"
        break
    fi

    log "开始 ${CHECK_SECONDS}s 静音判定(已延长 ${ext} 次)…"
    mv=$(measure_maxvol "$IDX" "$CHECK_SECONDS")
    log "窗口 max_volume=${mv}dB"

    if [ "$mv" -le "$SILENCE_DB" ]; then
        do_real_stop "满时长后检测到持续3分钟静音(峰值${mv}dB),判定直播已结束。"
        break
    fi

    ext=$((ext + 1))
    if [ "$ext" -gt "$MAX_EXT" ]; then
        do_real_stop "⚠️已达自动延长上限(${MAX_EXT}次/+3h,峰值${mv}dB仍有声),为安全强制停止。"
        break
    fi
    "$SK/send_telegram.sh" "🔊 ${STREAM_NAME}：到达计划时长但检测到仍在直播(峰值${mv}dB),已自动延长30分钟(第${ext}次,累计+$((ext*30))分钟)。录制未中断。" 2>/dev/null || true
    log "检测到声音,延长 30 分钟(第 ${ext} 次)"
    sleep "$EXTEND_SECONDS"
done
log "smart_stop 结束"
