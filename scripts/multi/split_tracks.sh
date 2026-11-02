#!/bin/bash
# split_tracks.sh —— 把「单实例多音轨」录出的合并 mkv 按音轨拆成 N 个单流文件，
# 每个文件 = 合并视频 + 该路自己的那条音轨，命名为各场直播名，投放到现有转写守护
# 进程的 raw 目录，让它像普通单流录制一样自动转写。
#
# 为什么这样拆而不是直接把多音轨文件丢给守护进程：现有守护进程只会转写「第一条/
# 混音」音频，多音轨丢进去会把两路混着转 → 失去分离意义。拆成每个文件一条音轨后，
# 每个文件转出来就是各自干净的字幕。
#
# 用法:
#   split_tracks.sh <合并mkv路径> <名称1> <名称2> [名称3 ...]
# 名称顺序 = 音轨顺序(名称1→音轨1/a:0, 名称2→音轨2/a:1, ...)。
#
# 输出: ~/Recordings/raw/<YYYY-MM-DD>_<名称K>.mkv  (投放给现有守护进程)
# 成功拆出全部音轨且每个文件 > 1MB 后，删除原合并 mkv。

set -u
SK="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:?用法: split_tracks.sh <合并mkv> <名称1> <名称2> ...}"
shift
if [[ ! -f "$SRC" ]]; then echo "❌ 找不到源文件: $SRC" >&2; exit 1; fi
if [[ $# -lt 1 ]]; then echo "❌ 至少给一个音轨名称" >&2; exit 1; fi

FFMPEG=/opt/homebrew/bin/ffmpeg
FFPROBE=/opt/homebrew/bin/ffprobe
RAW_DIR="$HOME/Recordings/raw"
mkdir -p "$RAW_DIR"
DATE=$(date +%Y-%m-%d)

# ── P-003 拆轨前磁盘校验：每个输出≈源大小(全视频+一条音轨)，需 源×名称数 + 5GB 边际。
#    不够则跳过拆轨、保留母带待人工，绝不拆一半留截断残件（2026-10-24 学废菌被截断的坑）。
free_gb(){ df -g "$HOME/Recordings" 2>/dev/null | awk 'NR==2{print $4+0}'; }
SRC_GB=$(du -g "$SRC" 2>/dev/null | cut -f1); SRC_GB=${SRC_GB:-0}
NEED=$(( SRC_GB * $# + 5 ))
FREE=$(free_gb)
echo "拆轨磁盘校验: 剩余 ${FREE}GB, 需约 ${NEED}GB (源 ${SRC_GB}GB × $# 路 + 5GB 边际)"
if [[ "${FREE:-0}" -lt "$NEED" ]]; then
    echo "❌ 磁盘不足拆轨(剩 ${FREE}GB < 需 ${NEED}GB)，保留母带待人工: $SRC" >&2
    bash "$SK/send_telegram.sh" "❌ 多路拆轨已跳过：磁盘仅剩 ${FREE}GB < 拆轨所需约 ${NEED}GB。母带已保留在 ~/Recordings/multi-raw/，清理空间后可手动跑 split_tracks.sh 重拆，不会丢录制。" 2>/dev/null || true
    exit 1
fi

# 实际音轨数(校验名称数量不超过音轨数)
NA=$("$FFPROBE" -v error -select_streams a -show_entries stream=index -of csv=p=0 "$SRC" 2>/dev/null | wc -l | tr -d ' ')
echo "源音轨数: $NA ; 待拆名称数: $#"

idx=0
ok=0
declare -a OUTS=()
for name in "$@"; do
    # 清洗文件名里的危险字符
    safe=$(printf '%s' "$name" | tr '/:\\' '___' | tr -d '\r\n')
    out="$RAW_DIR/${DATE}_${safe}.mkv"
    echo "→ 拆音轨 a:$idx → $out"
    if "$FFMPEG" -y -loglevel error -i "$SRC" -map 0:v:0 -map 0:a:$idx -c copy "$out"; then
        sz=$(stat -f%z "$out" 2>/dev/null || echo 0)
        if [[ "$sz" -gt 1000000 ]]; then
            echo "  ✅ $(du -h "$out" | cut -f1)"
            OUTS+=("$out"); ok=$((ok+1))
        else
            echo "  ⚠️ 输出过小($sz B)，可能该音轨无声/拆分异常，保留待查" >&2
        fi
    else
        echo "  ❌ ffmpeg 拆分失败 (a:$idx)" >&2
    fi
    idx=$((idx+1))
done

echo "成功拆出 $ok / $# 条"
# 全部成功才删原合并文件；否则保留原始多音轨 mkv 供人工处理
if [[ "$ok" -eq "$#" ]]; then
    echo "全部成功 → 删除原合并文件 $SRC"
    rm -f "$SRC"
else
    echo "⚠️ 未全部成功，保留原合并文件: $SRC" >&2
fi
exit 0
