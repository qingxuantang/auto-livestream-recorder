#!/bin/bash
# 改进版转写脚本 - 跳过静音段落，重新计算时间戳

VIDEO="$1"
OUTPUT_DIR="${2:-$HOME/Recordings/transcripts/$(date +%Y-%m-%d)}"
TMP_DIR="$HOME/Recordings/.tmp"
MODEL_PATH="$HOME/.cache/whisper/ggml-medium.bin"
LOG_FILE="$HOME/Recordings/process.log"

# 参数
SILENCE_THRESHOLD=-50dB      # 静音阈值
MIN_SILENCE_DURATION=60      # 最小静音时长（秒）- 1分钟以上算静音
MIN_SEGMENT_DURATION=3       # 最小有效段落（秒）

if [[ -z "$VIDEO" ]]; then
    echo "用法: $0 \u003c视频文件\u003e [输出目录]"
    exit 1
fi

if [[ ! -f "$VIDEO" ]]; then
    echo "错误: 视频文件不存在: $VIDEO"
    exit 1
fi

filename=$(basename "$VIDEO" .mkv)
echo "[$(date)] 开始处理: $filename" | tee -a "$LOG_FILE"

mkdir -p "$OUTPUT_DIR" "$TMP_DIR"

# 步骤1: 检测静音段落
echo "[$(date)] 步骤1: 检测静音段落 (阈值: ${SILENCE_THRESHOLD}, 最小静音: ${MIN_SILENCE_DURATION}秒)" | tee -a "$LOG_FILE"

silence_info=$(ffmpeg -i "$VIDEO" -af "silencedetect=noise=${SILENCE_THRESHOLD}:d=${MIN_SILENCE_DURATION}" -f null - 2>&1 | grep -E "silence_start|silence_end|Duration")

# 解析静音段落
declare -a silence_starts
declare -a silence_ends

while IFS= read -r line; do
    if [[ "$line" =~ silence_start:\ *([0-9]+\.?[0-9]*) ]]; then
        silence_starts+=("${BASH_REMATCH[1]}")
    elif [[ "$line" =~ silence_end:\ *([0-9]+\.?[0-9]*) ]]; then
        silence_ends+=("${BASH_REMATCH[1]}")
    fi
done <<< "$silence_info"

# 获取视频总时长
duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO" | cut -d. -f1)
echo "[$(date)] 视频时长: ${duration}秒, 发现 ${#silence_starts[@]} 个静音段落" | tee -a "$LOG_FILE"

# 步骤2: 计算有效音频段落
declare -a valid_segments_start
declare -a valid_segments_end
declare -a valid_segments_duration

current_pos=0
for i in "${!silence_starts[@]}"; do
    silence_start=${silence_starts[$i]}
    silence_end=${silence_ends[$i]:-$duration}
    
    # 计算静音前的有效段落
    segment_start=$current_pos
    segment_end=$silence_start
    segment_duration=$(echo "$segment_end - $segment_start" | bc)
    
    # 只保留大于最小时长的段落
    if (( $(echo "$segment_duration >= $MIN_SEGMENT_DURATION" | bc -l) )); then
        valid_segments_start+=("$segment_start")
        valid_segments_end+=("$segment_end")
        valid_segments_duration+=("$segment_duration")
        echo "[$(date)] 有效段落: $(printf '%.0f' $segment_start)s - $(printf '%.0f' $segment_end)s (时长: $(printf '%.0f' $segment_duration)s)" | tee -a "$LOG_FILE"
    fi
    
    current_pos=$silence_end
done

# 检查最后一段
if (( $(echo "$duration - $current_pos >= $MIN_SEGMENT_DURATION" | bc -l) )); then
    valid_segments_start+=("$current_pos")
    valid_segments_end+=("$duration")
    valid_segments_duration+=("$(echo "$duration - $current_pos" | bc)")
    echo "[$(date)] 有效段落(结尾): $(printf '%.0f' $current_pos)s - ${duration}s" | tee -a "$LOG_FILE"
fi

if [[ ${#valid_segments_start[@]} -eq 0 ]]; then
    echo "[$(date)] 错误: 未找到有效音频段落" | tee -a "$LOG_FILE"
    exit 1
fi

echo "[$(date)] 共 ${#valid_segments_start[@]} 个有效段落，开始转写..." | tee -a "$LOG_FILE"

# 步骤3: 分别转写每个有效段落
declare -a segment_srts
first_valid_start=${valid_segments_start[0]}

for i in "${!valid_segments_start[@]}"; do
    start=${valid_segments_start[$i]}
    end=${valid_segments_end[$i]}
    segment_file="$TMP_DIR/${filename}_segment_${i}.wav"
    
    echo "[$(date)] 转写段落 $i: $(printf '%.0f' $start)s - $(printf '%.0f' $end)s" | tee -a "$LOG_FILE"
    
    # 提取该段落音频
    ffmpeg -hide_banner -loglevel error -i "$VIDEO" -ss "$start" -to "$end" -ar 16000 -ac 1 -c:a pcm_s16le "$segment_file" -y
    
    if [[ ! -f "$segment_file" ]]; then
        echo "[$(date)] 错误: 段落 $i 音频提取失败" | tee -a "$LOG_FILE"
        continue
    fi
    
    # 转写该段落
    segment_srt="$TMP_DIR/${filename}_segment_${i}.srt"
    whisper-cli \
        --model "$MODEL_PATH" \
        --file "$segment_file" \
        --output-srt \
        --output-file "$TMP_DIR/${filename}_segment_${i}" \
        --language zh 2>> "$LOG_FILE"
    
    if [[ -f "$segment_srt" ]]; then
        segment_srts+=("$segment_srt")
        echo "[$(date)] 段落 $i 转写完成" | tee -a "$LOG_FILE"
    else
        echo "[$(date)] 警告: 段落 $i 转写未生成SRT" | tee -a "$LOG_FILE"
    fi
    
    # 清理临时音频
    rm -f "$segment_file"
done

# 步骤4: 合并SRT，重新计算时间戳
echo "[$(date)] 步骤4: 合并SRT文件，重新计算时间戳..." | tee -a "$LOG_FILE"

final_srt="$OUTPUT_DIR/${filename}.srt"
subtitle_index=1

# 写入开头标记（第一个有效段落开始时间）
if [[ ${#valid_segments_start[@]} -gt 0 ]]; then
    first_start_time=$(printf "%02d:%02d:%02d" $((first_valid_start/3600)) $((first_valid_start%3600/60)) $((first_valid_start%60)))
    
    echo "$subtitle_index" > "$final_srt"
    echo "00:00:00,000 --> 00:00:03,000" >> "$final_srt"
    echo "[直播实际开始于原始视频 ${first_start_time}]" >> "$final_srt"
    echo "" >> "$final_srt"
    subtitle_index=$((subtitle_index + 1))
fi

# 合并各段落SRT（使用awk处理时间戳）
for i in "${!segment_srts[@]}"; do
    segment_srt=${segment_srts[$i]}
    segment_offset=${valid_segments_start[$i]}
    
    echo "[$(date)] 合并段落 $i (偏移: ${segment_offset}s)..." | tee -a "$LOG_FILE"
    
    # 使用awk调整时间戳
    awk -v offset="$segment_offset" -v first_offset="$first_valid_start" -v idx="$subtitle_index" '
    BEGIN { curr_idx = idx }
    /^[0-9]+$/ { next }  # 跳过原始索引
    /^[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/ {
        # 解析开始时间
        split($1, t1, ":");
        split(t1[3], t1_sec, ",");
        start_h = t1[1]; start_m = t1[2]; 
        start_s = t1_sec[1]; start_ms = t1_sec[2];
        
        # 解析结束时间  
        split($3, t2, ":");
        split(t2[3], t2_sec, ",");
        end_h = t2[1]; end_m = t2[2];
        end_s = t2_sec[1]; end_ms = t2_sec[2];
        
        # 转换为总秒数（加上段落偏移，减去第一个段落偏移）
        start_total = start_h*3600 + start_m*60 + start_s + start_ms/1000 + offset - first_offset;
        end_total = end_h*3600 + end_m*60 + end_s + end_ms/1000 + offset - first_offset;
        
        if (start_total < 0) start_total = 0;
        if (end_total < 0) end_total = 0;
        
        # 格式化新时间戳
        new_start_h = int(start_total/3600);
        new_start_m = int((start_total%3600)/60);
        new_start_s = int(start_total%60);
        new_start_ms = int((start_total - int(start_total))*1000);
        
        new_end_h = int(end_total/3600);
        new_end_m = int((end_total%3600)/60);
        new_end_s = int(end_total%60);
        new_end_ms = int((end_total - int(end_total))*1000);
        
        printf "%d\n", curr_idx++;
        printf "%02d:%02d:%02d,%03d --> %02d:%02d:%02d,%03d\n", 
            new_start_h, new_start_m, new_start_s, new_start_ms,
            new_end_h, new_end_m, new_end_s, new_end_ms;
        next;
    }
    /^$/ { print ""; next }
    { print }
    ' "$segment_srt" >> "$final_srt"
    
    # 统计索引增量（估算）
    line_count=$(wc -l < "$segment_srt")
    subtitle_index=$((subtitle_index + line_count/4 + 1))
done

# 清理临时文件
rm -f "$TMP_DIR/${filename}"_segment_*.srt

if [[ -f "$final_srt" ]]; then
    word_count=$(wc -m < "$final_srt" | tr -d ' ')
    echo "[$(date)] ✅ 转写完成: $final_srt (字数: $word_count)" | tee -a "$LOG_FILE"
    
    # 发送通知
    osascript -e "display notification \"$filename 转写完成，共 ${#valid_segments_start[@]} 个有效段落\" with title \"录制处理\"" 2>/dev/null || true
    
    echo "完成: $final_srt"
    echo "有效段落: ${#valid_segments_start[@]}"
    echo "原始视频开始: $(printf '%02d:%02d:%02d' $((first_valid_start/3600)) $((first_valid_start%3600/60)) $((first_valid_start%60)))"
else
    echo "[$(date)] 错误: 最终SRT文件未生成" | tee -a "$LOG_FILE"
    exit 1
fi
