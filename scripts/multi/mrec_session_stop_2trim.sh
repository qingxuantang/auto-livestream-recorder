#!/bin/bash
# mrec_session_stop_2trim.sh <label> <tag> <轨1名> <轨2名>
# 两路各在自己浏览器全程录（如今晚 羽昕=Chrome/轨1、邢不行=Safari/轨2，邢不行21:00才开→轨2前段静音）。
# 停录 → 退OBS → 还原global.ini → 杀caffeinate → 两轨各自**去首尾静音**后投放 raw/。
# 去静音很关键：邢不行轨前~1小时是空的，不去掉会浪费转写并诱发 whisper 幻觉。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
STATE="$HOME/.multi-recording"; OBS_CFG="$HOME/Library/Application Support/obs-studio"
FF=/opt/homebrew/bin/ffmpeg; FFP=/opt/homebrew/bin/ffprobe; RAW="$HOME/Recordings/raw"
LABEL="$1"; TAG="$2"; T1="$3"; T2="$4"
LOG="$STATE/mrec_${TAG}.log"; exec >>"$LOG" 2>&1
DATE=$(date +%Y-%m-%d)
echo "===== $(date '+%F %T') stop_2trim tag=$TAG ====="

python3 "$SK/mobs_control.py" stop || true; sleep 4
osascript -e 'quit app "OBS"' >/dev/null 2>&1 &
for i in $(seq 1 10); do pgrep -f "OBS.app/Contents/MacOS/OBS" >/dev/null || break; sleep 1; done
pgrep -f "OBS.app/Contents/MacOS/OBS" >/dev/null && { pkill -9 -f "OBS.app/Contents/MacOS/OBS"; sleep 1; rm -f "$OBS_CFG/.sentinel/"run_*; }
python3 "$SK/global_basic.py" restore
[ -f "$STATE/caffeinate.pid" ] && kill "$(cat "$STATE/caffeinate.pid")" 2>/dev/null; rm -f "$STATE/caffeinate.pid"

MKV=$(ls -t "$HOME/Recordings/multi-raw/"*.mkv 2>/dev/null | head -1)
if [ -z "$MKV" ]; then bash "$SK/send_telegram.sh" "⚠️ 停录后未找到 multi-raw 的 mkv，请人工检查。"; exit 0; fi
safe(){ printf '%s' "$1" | tr '/:\\' '___' | tr -d '\r\n'; }

# 提取某音轨、去首尾静音、写 raw/<名>.mkv；成功打印时长
extract(){ # $1=aidx $2=名
  local out="$RAW/${DATE}_$(safe "$2").mkv" tmp="$STATE/_seg_$1.mkv"
  $FF -y -loglevel error -i "$MKV" -map 0:v:0 -map 0:a:$1 -c copy "$tmp" || { echo "  ❌ 抽轨$1失败"; return 1; }
  local dur s0 s1
  dur=$($FFP -v error -show_entries format=duration -of csv=p=0 "$tmp" 2>/dev/null)
  s0=$($FF -hide_banner -nostats -i "$tmp" -map 0:a:0 -af silencedetect=noise=-50dB:d=8 -f null - 2>&1 | awk '/silence_end/{print $NF; exit}')
  s1=$($FF -hide_banner -nostats -i "$tmp" -map 0:a:0 -af silencedetect=noise=-50dB:d=8 -f null - 2>&1 | awk '/silence_start/{v=$NF} END{print v}')
  local a="${s0:-0}" b="${s1:-$dur}"
  awk -v a="$a" -v b="$b" 'BEGIN{exit !(b-a>60)}' || { a=0; b="$dur"; }   # 兜底: 有效段<60s 就用整段
  $FF -y -loglevel error -ss "$a" -to "$b" -i "$tmp" -map 0:v:0 -map 0:a:0 -c copy "$out" \
     && echo "  ✅ $out ($(awk -v a="$a" -v b="$b" 'BEGIN{printf "%.0f",b-a}')s)" || echo "  ❌ 写$out失败"
  rm -f "$tmp"
}

extract 0 "$T1"   # 轨1 羽昕
extract 1 "$T2"   # 轨2 邢不行(去掉前段空白)
bash "$SK/send_telegram.sh" "✅ 多流停录并拆轨完成：$T1、$T2（各去首尾静音）已投转写队列。global.ini 已还原回单流配置。"
rm -f "$MKV"; echo "已删多轨原始 mkv"
