#!/bin/bash
# deploy_multi.sh "URL1|名称1" "URL2|名称2" ["URL3|名称3"]
# 部署一场「多直播并发录制」的**登录环境**(不启动 OBS、不碰 global.ini)。
#
# 设计要点(保护单流)：部署阶段只做「用各自浏览器打开直播页 + 提示登录」，把 OBS 启动
# 和 global.ini→multi-live 的切换推迟到开录脚本(mrec_start.sh)那一刻，并在停录后立刻还原。
# 这样 global.ini 指向 multi-live 的时间窗压缩到「只有多流真正录制的那段」，早晨/白天的
# 单流场次完全不受影响。
#
# 并发每路 = 不同浏览器 App：slot1=Chrome, slot2=Safari, slot3=Edge(需先装)。
set -u
SLOT_APP=("" "Google Chrome" "Safari" "Microsoft Edge")

if [[ $# -lt 1 || $# -gt 3 ]]; then
    echo "用法: deploy_multi.sh \"URL1|名称1\" \"URL2|名称2\" [\"URL3|名称3\"]" >&2
    exit 1
fi

echo "=== 各路用对应浏览器打开直播页(供登录) ==="
slot=0
for arg in "$@"; do
    slot=$((slot+1))
    url="${arg%%|*}"; name="${arg#*|}"
    app="${SLOT_APP[$slot]}"
    if [[ "$app" == "Microsoft Edge" && ! -d "/Applications/Microsoft Edge.app" ]]; then
        echo "❌ slot$slot 需要 Microsoft Edge，但未安装。3 路并发请先装 Edge。" >&2
        exit 1
    fi
    echo "  slot$slot [$app] $name → $url"
    open -a "$app" "$url"
    sleep 1
done

cat <<EOF

============================================================
✅ 登录环境已部署（未启动 OBS、未改任何 OBS 配置）。请 Mark 现在逐个登录：
$(slot=0; for arg in "$@"; do slot=$((slot+1)); name="${arg#*|}"; echo "  · slot$slot [${SLOT_APP[$slot]}] $name —— 在该浏览器里扫码/登录直播间"; done)

注意：
  · 不同浏览器 cookie 不共享，同一小鹅通店铺在 Chrome 和 Safari 里要各登一次。
  · 两路窗口都留在主屏(UGREEN)、不要最小化(后台会被降频丢帧)。
  · OBS 会在「开录时刻」由 launchd 自动启动并加载 multi-live，录完自动还原回单流配置——
    白天若有单流场次不受影响。
============================================================
EOF
