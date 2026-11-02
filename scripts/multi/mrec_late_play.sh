#!/bin/bash
# mrec_late_play.sh <label> <源cap> "<x,y>" <浏览器App> "<提示语>"
# 用于「某一路直播晚于开录时间才开始」——如今晚邢不行 21:00 才播（录制 20:00 就开了）。
# 到点：刷新该浏览器(Cmd+R 拿到最新直播态) → 音量表引导给该路点播放(重试~22分钟) → 提醒Mark兜底 → 自毁。
# 不停录、不动另一路。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
PY=python3; CC=/opt/homebrew/bin/cliclick
LABEL="$1"; CAP="$2"; XY="$3"; APP="$4"; MSG="$5"
LOG="$HOME/.multi-recording/late_play.log"
echo "$(date '+%F %T') late_play $CAP@$XY app=$APP" >> "$LOG"

# 1) 刷新该浏览器活动标签(拿最新直播态)
osascript >/dev/null 2>&1 <<OSA || true
tell application "$APP" to activate
delay 1
tell application "System Events"
  try
    tell process "$APP"
      set frontmost to true
      keystroke "r" using command down
    end tell
  end try
end tell
OSA

# 2) 提醒 Mark（人工兜底）
bash "$SK/send_telegram.sh" "$MSG" >/dev/null 2>&1

# 3) 音量表引导点播放(只点该路; 已出声则停) —— 邢不行可能晚点开, 重试 ~22 分钟
is_silent(){ local db; db=$("$PY" "$SK/mobs_control.py" meters "$CAP" 2 2>/dev/null); [ -z "$db" ] && db=-200; awk -v d="$db" 'BEGIN{print (d+0 < -50)?1:0}'; }
sleep 6
for a in $(seq 1 44); do
    s=$(is_silent)
    echo "$(date '+%T') 第${a}轮: $CAP 静音=$s" >> "$LOG"
    [ "$s" = 0 ] && { echo "已出声, 结束" >> "$LOG"; break; }
    "$CC" c:$XY >> "$LOG" 2>&1
    sleep 24
done
f=$(is_silent)
[ "$f" = 1 ] && bash "$SK/send_telegram.sh" "⚠️ 邢不行那路($CAP)自动点播放后仍无声，若已开播请在对应浏览器手动点一下播放。" >/dev/null 2>&1

# 4) 自毁
bash "$SK/selfdestruct_job.sh" "$LABEL"
