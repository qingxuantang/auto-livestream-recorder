#!/bin/bash
# mrec_session_prep.sh <label> <url_chrome> <url_safari> "<提示语>"
# launchd 录前触发：提前打开当天两场页面供确认登录 + Telegram 提示 → 自毁本任务。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
LABEL="$1"; URL_C="$2"; URL_S="$3"; MSG="$4"
open -a "Google Chrome" "$URL_C"
open -a "Safari" "$URL_S"
bash "$SK/send_telegram.sh" "$MSG"
bash "$SK/selfdestruct_job.sh" "$LABEL"
