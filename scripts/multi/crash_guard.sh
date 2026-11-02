#!/bin/bash
# crash_guard.sh —— 崩溃兜底守护(由 launchd com.mark.mrec-guard 每 60s 触发)。
#
# 目的：多流录制正常结束时，停录脚本会把 global.ini 还原回单流那套。但若多流录到一半
# OBS 崩溃/被杀/断电，还原那步没执行，global.ini 会残留指向 multi-live——此时若单流
# skill 启动就会加载错场景。本守护确定性地清掉这种残留，不依赖大模型。
#
# 判据(必须同时成立才动手)：
#   ① OBS 当前**没有**在运行；且
#   ② global.ini 的当前场景集合 == multi-live
# → 判定为崩溃残留 → 用快照还原回单流那套 + Telegram 通知。
# 其余任何情况(OBS 在跑 / 已是单流那套)一律什么都不做，绝不干扰正常录制。

SK="$(cd "$(dirname "$0")" && pwd)"
PY=/usr/bin/python3
[ -x /opt/homebrew/bin/python3 ] && PY=/opt/homebrew/bin/python3

# ① OBS 在跑吗？
if pgrep -f "OBS.app/Contents/MacOS/OBS" >/dev/null 2>&1; then
    exit 0   # 有 OBS 在跑 → 可能是正常多流会话，不动
fi

# ② 当前场景集合是不是 multi-live？
CUR="$("$PY" "$SK/global_basic.py" current 2>/dev/null)"
if [ "$CUR" != "multi-live" ]; then
    exit 0   # 已经是单流那套(或其它) → 无残留，不动
fi

# 走到这 = OBS 没跑 且 global.ini=multi-live → 崩溃残留，还原
"$PY" "$SK/global_basic.py" restore >> "$HOME/.multi-recording/guard.log" 2>&1
echo "$(date '+%F %T') 检测到崩溃残留(OBS 未运行 且 global.ini=multi-live)，已自动还原回单流配置" \
    >> "$HOME/.multi-recording/guard.log"
bash "$SK/send_telegram.sh" "🛡️ 多流崩溃兜底守护：检测到 global.ini 残留在 multi-live 且 OBS 未运行，已自动还原回单流配置，保护单流录直播 skill。" >/dev/null 2>&1
exit 0
