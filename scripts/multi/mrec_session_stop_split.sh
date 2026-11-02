#!/bin/bash
# mrec_session_stop_split.sh <label> <tag> <轨1a名> <轨1b名> <轨2名> <边界秒>
# 用于"同一浏览器先后两场(邢不行 策略19→市场洞察3) + 另一浏览器一场(羽昕)"的收尾。
# 停录 → 退OBS → 还原global.ini → 杀caffeinate → 拆轨：
#   track2(Safari/羽昕) 整轨 → <轨2名>
#   track1(Chrome/邢不行) 在【边界秒附近的静音缺口】处切成两段(切Tab时会产生静音):
#       前段 → <轨1a名>(策略19), 后段 → <轨1b名>(市场洞察3)
#   找不到明显缺口 → 回退：track1 整轨作 <轨1a名>_合并 + Telegram 提示人工拆。
# 各段去首尾静音(防 whisper 幻觉) 后投放 ~/Recordings/raw/。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
STATE="$HOME/.multi-recording"; OBS_CFG="$HOME/Library/Application Support/obs-studio"
FF=/opt/homebrew/bin/ffmpeg; FFP=/opt/homebrew/bin/ffprobe; RAW="$HOME/Recordings/raw"
LABEL="$1"; TAG="$2"; T1A="$3"; T1B="$4"; T2="$5"; BND="${6:-3600}"
LOG="$STATE/mrec_${TAG}.log"; exec >>"$LOG" 2>&1
DATE=$(date +%Y-%m-%d)
echo "===== $(date '+%F %T') stop_split tag=$TAG 边界${BND}s ====="

# 1) 停录 + 退 OBS + 还原 + 杀 caffeinate
python3 "$SK/mobs_control.py" stop || true; sleep 4
osascript -e 'quit app "OBS"' >/dev/null 2>&1 &
for i in $(seq 1 10); do pgrep -f "OBS.app/Contents/MacOS/OBS" >/dev/null || break; sleep 1; done
pgrep -f "OBS.app/Contents/MacOS/OBS" >/dev/null && { pkill -9 -f "OBS.app/Contents/MacOS/OBS"; sleep 1; rm -f "$OBS_CFG/.sentinel/"run_*; }
python3 "$SK/global_basic.py" restore
[ -f "$STATE/caffeinate.pid" ] && kill "$(cat "$STATE/caffeinate.pid")" 2>/dev/null; rm -f "$STATE/caffeinate.pid"

MKV=$(ls -t "$HOME/Recordings/multi-raw/"*.mkv 2>/dev/null | head -1)
if [ -z "$MKV" ]; then
    bash "$SK/send_telegram.sh" "⚠️ 停录后未找到 multi-raw 里的 mkv，请人工检查。"; exit 0
fi
safe(){ printf '%s' "$1" | tr '/:\\' '___' | tr -d '\r\n'; }

# 辅助：从 <源mkv> 的 track a:<idx>，截 [start,end] 段、去首尾静音、写到 raw/<名>.mkv
extract(){ # $1=srcmkv $2=aidx $3=start(空=0) $4=end(空=到尾) $5=名
  local out="$RAW/${DATE}_$(safe "$5").mkv" ss="" to=""
  [ -n "$3" ] && ss="-ss $3"; [ -n "$4" ] && to="-to $4"
  # 先按时间切+提取该音轨(视频+该轨)
  local tmp="$STATE/_seg_${2}.mkv"
  $FF -y -loglevel error $ss $to -i "$MKV" -map 0:v:0 -map 0:a:$2 -c copy "$tmp" || return 1
  # 去首尾静音：silencedetect 找首个有声起点/末个有声终点
  local dur; dur=$($FFP -v error -show_entries format=duration -of csv=p=0 "$tmp" 2>/dev/null)
  local s0 s1
  s0=$($FF -hide_banner -nostats -i "$tmp" -map 0:a:0 -af silencedetect=noise=-50dB:d=8 -f null - 2>&1 \
        | awk '/silence_end/{print $NF; exit}')
  s1=$($FF -hide_banner -nostats -i "$tmp" -map 0:a:0 -af silencedetect=noise=-50dB:d=8 -f null - 2>&1 \
        | awk '/silence_start/{v=$NF} END{print v}')
  local a="${s0:-0}" b="${s1:-$dur}"
  # 合理性兜底：起点<终点且时长>60s 才裁，否则用整段
  awk -v a="$a" -v b="$b" 'BEGIN{exit !(b-a>60)}' || { a=0; b="$dur"; }
  $FF -y -loglevel error -ss "$a" -to "$b" -i "$tmp" -map 0:v:0 -map 0:a:0 -c copy "$out" \
     && echo "  ✅ $out ($(awk -v a="$a" -v b="$b" 'BEGIN{printf "%.0f",b-a}')s)" || echo "  ❌ 写 $out 失败"
  rm -f "$tmp"
}

# 2) track2(羽昕) 整轨
extract "$MKV" 1 "" "" "$T2"

# 3) track1(邢不行) 在边界附近找静音缺口拆两段
GAP=$($FF -hide_banner -nostats -i "$MKV" -map 0:a:0 -af silencedetect=noise=-50dB:d=15 -f null - 2>&1 \
     | awk -v b="$BND" '/silence_start/{s=$NF} /silence_end/{e=$NF; m=(s+e)/2; if(m>b-420 && m<b+420){print m; exit}}')
if [ -n "$GAP" ]; then
    echo "  邢不行轨在 ${GAP}s 处发现切场静音缺口 → 拆两段"
    extract "$MKV" 0 "" "$GAP" "$T1A"      # 前段=策略19
    extract "$MKV" 0 "$GAP" "" "$T1B"      # 后段=市场洞察3
    bash "$SK/send_telegram.sh" "✅ 多流停录并拆轨完成：羽昕、邢不行·策略19、邢不行·市场洞察3（按 ${GAP%.*}s 切场缺口拆分）已投转写队列。global.ini 已还原。"
else
    echo "  ⚠️ 边界附近没找到明显静音缺口 → 邢不行两场合并为一个文件, 提示人工拆"
    extract "$MKV" 0 "" "" "${T1A}_加_${T1B}_合并"
    bash "$SK/send_telegram.sh" "⚠️ 多流已停录：羽昕已单独出；但邢不行两场(策略19+市场洞察3)在 21:00 附近没测到清晰切场静音缺口，已合并成一个文件投转写，需要的话我再手动按实际切换点拆。global.ini 已还原。"
fi
rm -f "$MKV"; echo "已删多轨原始 mkv"
