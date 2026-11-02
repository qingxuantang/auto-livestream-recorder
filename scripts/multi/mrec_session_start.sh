#!/bin/bash
# mrec_session_start.sh <label> <tag> <url_chrome> <url_safari>
# launchd 到点触发：打开+刷新两场页面 → 并排摆窗 → 开录 → 自动点播放(音量表引导) → 自毁。
# slot 固定：Chrome=cap1=音轨1(左半屏)，Safari=cap2=音轨2(右半屏)。
# 坐标为「左右半屏」布局标定值(2026-08-22 截图标定, 主屏 1920x1080 非Retina)。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
LABEL="$1"; TAG="$2"; URL_C="$3"; URL_S="$4"; URL_C2="${5:-}"
# 第6参=开录时自动点播放的目标(默认两路)。某路晚开时只传该时刻在播的那路，
# 例: "cap1 480,288"(只自动点 Chrome)，晚开那路交给 mrec_late_play 在其开播时刻处理。
AUTOPLAY_ARGS="${6:-cap1 480,288 cap2 1440,275}"
LOG="$HOME/.multi-recording/mrec_${TAG}.log"
exec >>"$LOG" 2>&1
echo "===== $(date '+%F %T') session_start label=$LABEL tag=$TAG (chrome2=${URL_C2:-无}) ====="

# 1) 打开页面。可选 URL_C2 = Chrome 里预开的第二场(背景标签，如邢不行 21:00 的市场洞察3)——
#    先开它(背景)、再开 URL_C(策略19)使其成为活动标签，20:00 录/自动点播放对准 URL_C。
[ -n "$URL_C2" ] && { open -a "Google Chrome" "$URL_C2"; sleep 1; }
open -a "Google Chrome" "$URL_C"; sleep 2
open -a "Safari" "$URL_S"; sleep 2

# 2) 强制刷新(Cmd+R, 避免拿到停在倒计时的过期页) + 并排摆窗(System Events, 可靠; 避开 Safari set bounds 超时)
osascript >/dev/null 2>&1 <<'OSA' || true
tell application "System Events"
  try
    tell application "Google Chrome" to activate
  end try
  delay 1
  try
    tell process "Google Chrome"
      set frontmost to true
      keystroke "r" using command down
    end tell
  end try
  delay 1
  try
    tell application "Safari" to activate
  end try
  delay 1
  try
    tell process "Safari"
      set frontmost to true
      keystroke "r" using command down
    end tell
  end try
  delay 3
  try
    tell process "Google Chrome"
      set position of window 1 to {0, 25}
      set size of window 1 to {960, 1055}
    end tell
  end try
  try
    tell process "Safari"
      set position of window 1 to {960, 25}
      set size of window 1 to {960, 1055}
    end tell
  end try
end tell
OSA
sleep 2

# 3) 开录(快照 global.ini → caffeinate → 启 OBS multi-live → 绑 cap1/cap2 → 开录 → 通知)
bash "$SK/mrec_start.sh" "$TAG"

# 4) 通知(自动点播放为主, 人工为辅)
bash "$SK/send_telegram.sh" "🎬 多流已开录（$TAG），正在自动点两路播放（音量表引导，只点还没出声的那路）。可瞄一眼两个直播是否都在播、每个浏览器只留该直播窗口在前；若某路自动点后仍没声我会单独提醒你手点兜底。22:30 自动停，想早停/延长随时说。"

# 5) 自动点播放兜底(前台跑完再自毁——否则第6步 bootout 会把后台 autoplay 一起杀掉)
bash "$SK/autoplay_click.sh" $AUTOPLAY_ARGS

# 6) 自毁本 launchd 任务(先删 plist 再 bootout)
bash "$SK/selfdestruct_job.sh" "$LABEL"
echo "$(date '+%F %T') session_start 完成"
