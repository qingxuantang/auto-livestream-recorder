---
name: auto-livestream-recorder
display_name: 全自动直播录制大师
display_name_en: Fully-Automatic Livestream Recorder
version: 1.0.0
author: Mark
description_zh: >-
  全自动网页直播 / 会议 / 课程录制 + 转写技能（macOS）。你只需告诉它哪天、几点、
  直播链接，之后全程无人值守：提前打开页面并提示你登录 → 到点自动开录 → 用静音判定
  智能停录（直播拖堂也不会被截断）→ 录完自动用本地 Whisper 转成字幕(SRT)和文字稿，
  产物全部留在你本地。更支持多场直播同时并发录制，各路音轨完全隔离、互不串音。
  中途唯一可能需要你动手的，只是打开页面登录（部分直播需登录才能看）。
  可选开启本地 RAG，把大量转写文本变成可随时检索的知识库。
description_en: >-
  Fully automated macOS skill to record and transcribe web livestreams / meetings /
  online courses. Just tell it the date, time, and stream URL — then it runs
  unattended: opens the page early and reminds you to log in, auto-starts at the
  scheduled time, stops intelligently by silence detection (never cut off when a
  stream runs long), and transcribes locally with Whisper into subtitles (SRT) and
  a text transcript, all kept on your own machine. It can even record multiple
  concurrent livestreams at once, with fully isolated, non-interfering audio tracks.
  The only step that may need you is logging into the page (some streams require
  login). Optional local RAG turns your growing transcripts into a searchable knowledge base.
allowed-tools: Bash
examples_zh:
  - 帮我录个直播，链接 https://… ，今晚 8 点开始，录 2 小时
  - 明天下午 3 点有个线上课，帮我录下来并转成文字
  - 这两场直播时间撞了，帮我同时录，音轨别混
examples_en:
  - Record this livestream https://… tonight at 8pm for 2 hours
  - There's an online class tomorrow 3pm, record it and transcribe to text
  - These two streams overlap — record both at once with separate audio tracks
---

# 全自动直播录制大师 (Fully-Automatic Livestream Recorder)

把「网页直播 / 会议 / 课程」自动录下来并转成字幕+文字稿，**全程无人值守**。你只给
「日期 + 时间 + 链接」，剩下交给它。首次使用需按 `references/SETUP.md` 装一次依赖、建一次 OBS 场景。

> ⚠️ 平台：目前 **macOS 专用**（依赖 OBS + BlackHole 音频路由 + 本地 Whisper）。
> 合规：仅录制你**有权录制**的内容（自办会议/直播/授权课程），见 `references/COMPLIANCE.md`。

## 最大卖点
- **只说一句就够**：哪天、几点、哪个链接——之后自动开录、智能停录、自动转写。
- **唯一可能要你动手的**：打开页面**登录**（部分直播要登录才能看）。技能会提前把页面打开并提醒你，给足登录时间。
- **智能停录**：到计划时长后不硬切，靠声音静默判定直播是否真结束，拖堂自动延长，不丢尾巴。
- **多直播并发**：撞车的多场可**同时录**，各路**音轨完全隔离、互不串音**（见「多直播并发」）。
- **数据留本地**：录像、字幕、文字稿全部只在你自己机器上。转写默认用**本地 Whisper**，无需任何 API key。

## 完整流程（单场）
1. **预约**：你说「录个直播」+ URL + 时长 + 开始时间（如「今晚 20:00，录 2 小时」）。
2. **立即准备（收到就做）**：打开直播页（多链接各开一个标签）→ 启动 OBS → 切「网页直播录制」场景 → 绑定采集源 → **提醒你现在就去登录**。音频此刻不切，不影响你日常用机。
3. **录前 30 分钟自检**：确认 OBS/页面/采集源就绪，再提醒确认登录。
4. **到点自动开录**：切到 BlackHole 采音 → 开录 → （小鹅通类）自动点播放 → 校验并通知。
5. **智能停录**：到时长后每 3 分钟测声音，整段静音判直播结束才真停；有声自动延长（最多 +3h / 磁盘<5GB 强停）。
6. **收尾**：停录 → OBS 干净退出（避免下次 safe-mode 弹窗）→ 切回扬声器。
7. **自动转写**：本地 Whisper 出 SRT + 纯文字稿 → `~/Recordings/transcripts/<日期>/`。可选术语纠正、可选入 RAG、可选通知。超期 raw 48h 后自动清理（已转写才删）。

## 触发关键词
- 开始：开始录制 / 帮我录个直播 / 录制直播 / 录屏 / 准备录制 / record this livestream
- 提供链接：https://… / "链接是…" / "地址…"
- 时长：预计 1 小时 / 大概 2 小时 / 90 分钟
- 时间：8点 / 20:00 / 半小时后 / 现在就录
- 确认已登录：准备好了 / 登录好了 / ok
- 结束：结束录制 / 停 / done
- 多场同时：这几场时间撞了 / 同时录 / 两场一起录

## 脚本
```bash
# 单场预约（解析时间→建定时任务）
scripts/schedule_recording.sh "<URL>" "<时长 2h/90m>" "<开始 20:00/+30m/now>"
# 分步
scripts/verify_env.sh                 # 环境自检
scripts/prepare.sh "<URL>"            # 立即准备：开页面+OBS+绑采集+提醒登录
scripts/start_recording.sh            # 开录（到点自动调用）
scripts/stop_recording.sh             # 停录（干净退出 OBS）
scripts/postprocess.sh                # 转写未处理的 raw + 可选RAG + 清理（停录后自动/可手动）
scripts/check_status.sh               # 查看预约/录制状态
```

## 多直播并发（撞车的多场同时录，音轨隔离）
用 `scripts/multi/` 下的多路方案（单实例 OBS + 每路独立音轨，完全隔离）：
```bash
scripts/multi/deploy_multi.sh         # 部署多场并发录制（见脚本内用法与 install_multi_config.sh）
```
多路录制对磁盘更敏感，内置录前硬闸 + 录制中监控 + 拆轨前校验（空间不足保母带不拆）。详见 `references/SETUP.md`「多直播并发」。

## 转写引擎（默认本地，无需 key）
- 默认 **本地 Whisper**（`whisper-cli` + `ggml-medium`），零外部凭据、数据不出本机。
- 想用 OpenAI：设 `TRANSCRIBE_ENGINE=openai` 且提供你自己的 `OPENAI_API_KEY`；API 失败会自愈回本地。

## 可选：本地 RAG 知识库
转写文本越积越多时，可开一个**纯本地** RAG 对历史转写做检索问答：
```bash
export RAG_ENABLED=1                        # 开启后，postprocess 自动把新转写入库
scripts/rag_index.py query "某个主题讲了什么" # 检索，返回相关段落+出处
```
有 `OPENAI_API_KEY` 走语义向量；没有则用零依赖本地词法检索。索引在 `~/Recordings/rag/`。

## 配置（部署时一次性）
见 `references/SETUP.md` 与 `references/CONFIG.md`。关键开关（环境变量）：
- `TRANSCRIBE_ENGINE`（local / openai）、`OPENAI_API_KEY`（选 openai 时）
- `RAG_ENABLED`（0/1）
- 通知（可选，用户自备）：`NOTIFY_TELEGRAM_TOKEN`+`NOTIFY_TELEGRAM_CHAT_ID`，或 `NOTIFY_WEBHOOK_URL`；都不设则只写本地日志。

## 输出
- 录像：`~/Recordings/raw/`（48h 自动清理，已转写才删）
- 字幕+文字稿：`~/Recordings/transcripts/<日期>/`
- 日志：`~/Recordings/process.log`
