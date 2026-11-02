#!/bin/bash
# 一次性 launchd 任务的可靠自毁 helper。
#
# 用法（在 recXXXX_start.sh / recXXXX_stop.sh 结尾调用）：
#   bash "$SK/selfdestruct_job.sh" com.mark.recXXXX-stop
#
# 为什么需要它（2026-07-14 实锤的坑）：
#   旧模板结尾写 `launchctl bootout gui/501/<self>; rm -f <plist>`。问题是
#   bootout 作用在“自己这个正在运行的 job”上会立刻给脚本进程发 SIGTERM，
#   于是分号后面的 `rm` 根本没机会执行 → plist 残留在 ~/Library/LaunchAgents/，
#   下次登录/重启 launchd 又把它加载回来。若该 plist 又是“只写 Hour/Minute、
#   没绑 Day/Month”的每日任务，就会像 com.mark.rec-linkedin-stop 那样每天 13:38
#   误触发一次（试图停一个没在跑的 OBS、切音频、发假的“录制已停”消息）。
#
# 修法：**先删文件，再 bootout**。文件先删掉，哪怕紧接着被 bootout 杀掉进程，
#   磁盘上也已经没有 plist → 下次登录不会重新加载。bootout 放最后、失败也无所谓
#   （文件已删，当前会话里的实例本轮跑完即消失，登出后不再回来）。
#
# 与“强制绑 Day/Month”是双保险：绑了日期即使自毁完全失败也一年内不会再触发。

set -u
LABEL="${1:?用法: selfdestruct_job.sh <launchd-label>}"
UID_NUM="$(id -u)"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

# 1) 先删磁盘上的 plist（关键：必须在 bootout 之前，保证一定删掉）
rm -f "$PLIST"

# 2) 再卸载当前已加载的实例（放后面；即便它把本进程杀掉，第 1 步也已完成）
launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true

exit 0
