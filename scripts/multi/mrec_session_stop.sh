#!/bin/bash
# mrec_session_stop.sh <label> <tag> "<名称1>" "<名称2>"
# launchd 到点(硬停 backstop)触发：停录+退OBS+还原global.ini+拆轨投放raw/ → 自毁本任务。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
LABEL="$1"; TAG="$2"; shift 2
LOG="$HOME/.multi-recording/mrec_${TAG}.log"
exec >>"$LOG" 2>&1
echo "===== $(date '+%F %T') session_stop label=$LABEL tag=$TAG names=$* ====="

bash "$SK/mrec_stop.sh" "$TAG" "$@"
bash "$SK/selfdestruct_job.sh" "$LABEL"
echo "$(date '+%F %T') session_stop 完成"
