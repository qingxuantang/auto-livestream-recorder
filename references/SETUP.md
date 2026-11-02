# SETUP — 首次安装（macOS，一次性）

本技能跑在**你自己的 Mac 本地**。首次用前装好依赖并建一次 OBS 场景；之后每次录制都无需再配。

## 1. 安装依赖（Homebrew）
```bash
# OBS（录制）
brew install --cask obs
# 音频路由：BlackHole 2ch（把系统声音喂给 OBS 录音）
brew install blackhole-2ch
# 切换默认音频输出 + 媒体处理 + 自动点击
brew install switchaudio-osx ffmpeg cliclick
# 本地转写：whisper.cpp（提供 whisper-cli）
brew install whisper-cpp
```

## 2. 下载本地 Whisper 模型（默认转写引擎，无需任何 API key）
```bash
mkdir -p ~/.cache/whisper
# 中英通用 medium 模型（约 1.5GB）
curl -L -o ~/.cache/whisper/ggml-medium.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin
```
> 想换模型：设 `WHISPER_MODEL` 指向其它 ggml 文件。想用 OpenAI 转写：见 `CONFIG.md`。

## 3. 建一次 OBS 场景「网页直播录制」
1. 打开 OBS → 场景面板右键「添加场景」→ 命名 **网页直播录制**（名字必须一致，脚本按名切换）。
2. 来源面板 `+` → **macOS Screen Capture**。
3. Method 选 **Application Capture**；Application 选 **你的浏览器**（如 Google Chrome）；Display 选你平时看直播那块主显示器。
   - ⚠️ 用 Application Capture，不要用 Window Capture（macOS 上抓浏览器会黑屏）。
   - ⚠️ 直播页必须留在所绑的那块显示器上，拖到别的屏会黑。
4. 关掉 OBS。以后由技能自动启动/切场景/绑定。

## 4. 授权（macOS 隐私）
首次运行会弹权限请求，请允许：**屏幕录制**（OBS）、**辅助功能/Accessibility**（cliclick 自动点击、osascript 控制窗口）、**麦克风/音频**。

## 5. 自检
```bash
bash scripts/verify_env.sh     # 逐项检查 OBS/BlackHole/ffmpeg/whisper/模型/磁盘
```

## 6. 多直播并发（可选，撞车多场同时录）
一次性安装多路配置（单实例 OBS + 每路独立音轨）：
```bash
bash scripts/multi/install_multi_config.sh     # 装多路 OBS 配置/场景
# 部署并发录制见：
bash scripts/multi/deploy_multi.sh             # 按脚本内提示传入多场链接/时间
```
多路写盘快且要拆轨，内置磁盘守护（录前 <15GB 不录 / 录中 <12GB 强停 / 拆轨前空间不足则保留母带不拆）。

## 常见问题
- **录到黑屏**：采集源用了 Window Capture，或直播页被拖到别的显示器 → 改回 Application Capture、页面留在绑定屏。
- **到点没开录**：确认已授予 OBS 屏幕录制 + 辅助功能权限；`scripts/verify_env.sh` 复查。
- **录到未登录空页**：开录前没登录 → 技能会提前提醒，请尽早登录并把要录的页面放到最前。
