#!/bin/bash
# mrec_reminder.sh <label> <消息> —— launchd 定时纯提醒：发 Telegram + 自毁本任务。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
LABEL="$1"; MSG="$2"
bash "$SK/send_telegram.sh" "$MSG"
bash "$SK/selfdestruct_job.sh" "$LABEL"
