#!/bin/bash
# postprocess.sh — 录制结束后的本地后处理（去私有版）。
#
# 对 ~/Recordings/raw 下「还没有对应字幕」的 .mkv：
#   1) 本地 Whisper 转写 → SRT + 纯文字稿（transcripts/<日期>/）
#   2) 可选术语纠正（glossary_correct.py，用户自备词表才生效）
#   3) 可选入本地 RAG（仅当 RAG_ENABLED=1）
#   4) 可选通知（send_telegram.sh，用户配了才外发）
#   5) 清理 48h 以上、已成功转写的 raw（释放磁盘；无有效字幕则保留并通知）
#
# 全程只在**用户本地**进行，不向任何私有/第三方库推送。
set -u
SKILL="$(cd "$(dirname "$0")" && pwd)"
RAW_DIR="$HOME/Recordings/raw"
TR_DIR="$HOME/Recordings/transcripts"
LOG="$HOME/Recordings/process.log"
RETENTION_H="${RAW_RETENTION_HOURS:-48}"
mkdir -p "$RAW_DIR" "$TR_DIR"

log(){ echo "$(date '+%F %T') [postprocess] $*" | tee -a "$LOG"; }

srt_for(){ # 已存在该 base 的字幕？（任意日期子目录）
  local base="$1"
  find "$TR_DIR" -type f -name "${base}.srt" 2>/dev/null | head -1
}

for mkv in "$RAW_DIR"/*.mkv; do
  [ -e "$mkv" ] || continue
  base="$(basename "$mkv" .mkv)"
  # 分段保护：同名多段（base_1.mkv…）说明中断过，交人工，不处理
  if ls "$RAW_DIR/${base}_"*.mkv >/dev/null 2>&1; then
    log "⚠️ $base 疑似分段录制（存在 ${base}_N.mkv），跳过，请人工合并。"
    "$SKILL/send_telegram.sh" "⚠️ 录制 $base 疑似分段，未自动转写，请人工检查合并。" 2>/dev/null || true
    continue
  fi
  if [ -n "$(srt_for "$base")" ]; then continue; fi   # 已转写过
  day="$(date -r "$mkv" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')"
  out="$TR_DIR/$day"; mkdir -p "$out"
  srt="$out/${base}.srt"; txt="$out/${base}.txt"
  log "转写：$base → $srt"
  if python3 "$SKILL/transcribe_enhanced.py" "$mkv" "$srt" >>"$LOG" 2>&1 && [ -s "$srt" ]; then
    # 可选术语纠正（用户没放 user_glossary.json 则 no-op）
    python3 "$SKILL/glossary_correct.py" --apply "$srt" >>"$LOG" 2>&1 || true
    # 纯文字稿：去掉序号/时间轴行
    grep -vE '^[0-9]+$|-->' "$srt" | sed '/^[[:space:]]*$/d' > "$txt" 2>/dev/null || true
    log "✅ 转写完成：$srt"
    # 可选 RAG 入库
    if [ "${RAG_ENABLED:-0}" = "1" ]; then
      python3 "$SKILL/rag_index.py" index "$txt" >>"$LOG" 2>&1 && log "📚 已入 RAG：$base" || log "RAG 入库失败（忽略）"
    fi
    "$SKILL/send_telegram.sh" "✅ 录制已转写完成：$base（字幕+文字稿在 transcripts/$day/）" 2>/dev/null || true
  else
    log "❌ $base 转写失败或空结果，保留 raw 待人工。"
    "$SKILL/send_telegram.sh" "❌ 录制 $base 转写失败，已保留原始视频待人工检查。" 2>/dev/null || true
  fi
done

# 清理：>RETENTION_H 小时、且已有有效字幕的 raw
now=$(date +%s)
for mkv in "$RAW_DIR"/*.mkv; do
  [ -e "$mkv" ] || continue
  base="$(basename "$mkv" .mkv)"
  age_h=$(( (now - $(date -r "$mkv" +%s)) / 3600 ))
  [ "$age_h" -lt "$RETENTION_H" ] && continue
  s="$(srt_for "$base")"
  if [ -n "$s" ] && [ "$(grep -cE '\-\->' "$s" 2>/dev/null)" -ge 10 ]; then
    rm -f "$mkv" && log "🧹 清理超期 raw（已转写）：$base（${age_h}h）"
  else
    log "保留 $base：超期但无有效字幕，待人工。"
  fi
done
log "postprocess 完成"
