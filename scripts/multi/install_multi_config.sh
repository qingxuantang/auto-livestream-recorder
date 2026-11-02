#!/bin/bash
# install_multi_config.sh —— 一次性安装/重装(幂等)。把多流那套装进共享 OBS 配置，
# 并建立单流基线快照 + 加载崩溃守护。不改动单流的任何文件。
# macOS 版 OBS 无法做配置隔离(portable/$HOME/--portable 均实测失败)，故采用「共享同一
# OBS 配置目录、只新增 multi-live 场景集合 + multi 多音轨配置」+ global.ini 快照/还原 +
# 崩溃守护 的方案。详见 SKILL.md。
set -u
SK="$(cd "$(dirname "$0")" && pwd)"
OBS_CFG="$HOME/Library/Application Support/obs-studio"
STATE="$HOME/.multi-recording"
BK="$STATE/backup-main-obs"
PY=python3
mkdir -p "$STATE" "$BK" "$HOME/Recordings/multi-raw"

echo "=== 0) 安全检查: 不能有 OBS 在跑(要写配置文件) ==="
if pgrep -f "OBS.app/Contents/MacOS/OBS" >/dev/null; then echo "❌ 请先退出 OBS 再装" >&2; exit 1; fi

echo "=== 1) 备份单流关键配置(若尚无备份, 用固定短名) ==="
[ -f "$BK/global.ini.bak" ]                  || cp -a "$OBS_CFG/global.ini" "$BK/global.ini.bak"
[ -f "$BK/websocket.config.json.bak" ]       || cp -a "$OBS_CFG/plugin_config/obs-websocket/config.json" "$BK/websocket.config.json.bak"
[ -f "$BK/Untitled.json.bak" ]               || cp -a "$OBS_CFG/basic/scenes/Untitled.json" "$BK/Untitled.json.bak"
[ -f "$BK/Untitled-profile-basic.ini.bak" ]  || cp -a "$OBS_CFG/basic/profiles/Untitled/basic.ini" "$BK/Untitled-profile-basic.ini.bak"
echo "  已确保备份存在于 $BK"

echo "=== 2) 装多流场景集合 + 多音轨配置(仅新增) ==="
"$PY" "$SK/gen_scene.py"

echo "=== 3) 建单流基线 [Basic] 快照(守护/停录的还原目标) ==="
cat > "$STATE/global_basic.snapshot" <<'EOF'
[Basic]
Profile=Untitled
ProfileDir=Untitled
SceneCollection=Untitled
SceneCollectionFile=Untitled
EOF
echo "  快照: $STATE/global_basic.snapshot"

echo "=== 4) 把 global.ini 显式钉定到单流那套(消除两集合的默认歧义) ==="
"$PY" "$SK/global_basic.py" restore
echo "  current = $("$PY" "$SK/global_basic.py" current)"

echo "=== 5) 加载崩溃兜底守护(每 60s: OBS没跑且global.ini=multi-live→自动还原) ==="
PLIST="$HOME/Library/LaunchAgents/com.mark.mrec-guard.plist"
if [ -f "$PLIST" ]; then
    launchctl bootout "gui/$(id -u)/com.mark.mrec-guard" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST" && echo "  ✅ 守护已加载" || echo "  ⚠️ 守护加载失败，请手动 launchctl bootstrap"
else
    echo "  ⚠️ 未找到 $PLIST"
fi

echo "=== 完成。多流那套已就绪，单流零影响(可用 verify_no_impact.sh 复核)。 ==="
