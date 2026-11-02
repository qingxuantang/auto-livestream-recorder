#!/bin/bash
# 验证录制环境

ERRORS=0

# 检查 OBS
if [[ ! -d "/Applications/OBS.app" ]]; then
    echo "❌ OBS Studio 未安装"
    ERRORS=$((ERRORS+1))
else
    echo "✅ OBS Studio"
fi

# 检查 ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "❌ ffmpeg 未安装"
    ERRORS=$((ERRORS+1))
else
    echo "✅ ffmpeg"
fi

# 检查 whisper-cli
if ! command -v whisper-cli &> /dev/null; then
    echo "❌ whisper-cli 未安装"
    ERRORS=$((ERRORS+1))
else
    echo "✅ whisper-cli"
fi

# 检查 BlackHole
if ! system_profiler SPAudioDataType | grep -q "BlackHole 2ch"; then
    echo "❌ BlackHole 2ch 未安装"
    ERRORS=$((ERRORS+1))
else
    echo "✅ BlackHole 2ch"
fi

# 检查 SwitchAudioSource
if ! command -v SwitchAudioSource &> /dev/null; then
    echo "❌ SwitchAudioSource 未安装"
    ERRORS=$((ERRORS+1))
else
    echo "✅ SwitchAudioSource"
fi

# 检查模型文件
if [[ ! -f "$HOME/.cache/whisper/ggml-medium.bin" ]]; then
    echo "❌ Whisper medium 模型未下载"
    ERRORS=$((ERRORS+1))
else
    echo "✅ Whisper medium 模型"
fi

# 检查磁盘空间
AVAILABLE=$(df -h / | tail -1 | awk '{print $4}' | sed 's/Gi//')
if (( $(echo "$AVAILABLE < 10" | bc -l) )); then
    echo "⚠️ 磁盘空间不足: ${AVAILABLE}GB (建议 >10GB)"
else
    echo "✅ 磁盘空间: ${AVAILABLE}GB"
fi

# 检查录制目录
if [[ ! -d "$HOME/Recordings/raw" ]]; then
    echo "❌ 录制目录不存在，正在创建..."
    mkdir -p "$HOME/Recordings"/{raw,.tmp,transcripts}
fi
echo "✅ 录制目录"

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo "发现 $ERRORS 个错误，请先安装依赖"
    exit 1
else
    echo ""
    echo "✅ 环境验证通过"
    exit 0
fi
