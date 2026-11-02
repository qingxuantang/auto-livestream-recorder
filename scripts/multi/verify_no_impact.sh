#!/bin/bash
# verify_no_impact.sh —— 复核「多流那套对单流 skill 零影响」。随时可跑。
#   ① 单流 3 个关键文件(网页直播录制场景/单流profile/websocket) 与备份 md5 一致；
#   ② global.ini 当前钉定 = Untitled；
#   ③ .sentinel 无残留 run_*(不会弹崩溃框)。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
OBS_CFG="$HOME/Library/Application Support/obs-studio"
BK="$HOME/.multi-recording/backup-main-obs"
PY=python3
ok=1

echo "① 单流关键文件零改动:"
declare -a PAIRS=(
  "basic/scenes/Untitled.json:Untitled.json.bak"
  "basic/profiles/Untitled/basic.ini:Untitled-profile-basic.ini.bak"
  "plugin_config/obs-websocket/config.json:websocket.config.json.bak"
)
for p in "${PAIRS[@]}"; do
  cur="${p%%:*}"; bak="${p##*:}"
  if [ -f "$BK/$bak" ]; then
    a=$(md5 -q "$OBS_CFG/$cur"); b=$(md5 -q "$BK/$bak")
    [ "$a" = "$b" ] && echo "   ✅ $cur" || { echo "   ❌ $cur 变了!"; ok=0; }
  else echo "   ⚠️ 无备份 $bak(用旧备份名?)"; fi
done

echo "② global.ini 钉定:"
cur=$("$PY" "$SK/global_basic.py" current)
[ "$cur" = "Untitled" ] && echo "   ✅ current=Untitled" || { echo "   ❌ current=$cur (应为 Untitled)"; ok=0; }

echo "③ 崩溃标记:"
if ls "$OBS_CFG/.sentinel/"run_* >/dev/null 2>&1; then echo "   ⚠️ 有 run_ 残留(下次可能弹崩溃框)"; else echo "   ✅ .sentinel 无残留"; fi

echo
[ "$ok" = 1 ] && echo "==> ✅ 单流零影响 复核通过" || { echo "==> ❌ 复核未通过"; exit 1; }
