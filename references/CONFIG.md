# CONFIG — 配置项（全部可选，环境变量）

本技能开箱即用（默认本地 Whisper、不发外部通知、不建 RAG）。要调整就设对应环境变量
（写进技能运行环境，或在运行脚本前 `export`）。**技能本身不内置任何凭证**。

| 变量 | 默认 | 作用 |
|------|------|------|
| `TRANSCRIBE_ENGINE` | `local` | 转写引擎：`local`=本地 Whisper（无需 key）；`openai`=用 OpenAI API（需下一行 key） |
| `OPENAI_API_KEY` | 空 | 仅当 `TRANSCRIBE_ENGINE=openai` 时需要；填**你自己的** key。API 失败会自愈回本地 Whisper |
| `WHISPER_MODEL` | `~/.cache/whisper/ggml-medium.bin` | 本地 Whisper 模型路径 |
| `RAG_ENABLED` | `0` | `1` = 每次转写完自动把文字稿入本地 RAG（`~/Recordings/rag/`）。检索：`scripts/rag_index.py query "…"` |
| `RAG_DIR` | `~/Recordings/rag` | RAG 索引存放目录 |
| `GLOSSARY_PATH` | `scripts/user_glossary.json` | 可选术语纠正词表；文件不存在则不纠正 |
| `RAW_RETENTION_HOURS` | `48` | 原始录像保留小时数（超期且已转写才删） |
| `NOTIFY_TELEGRAM_TOKEN` + `NOTIFY_TELEGRAM_CHAT_ID` | 空 | 配了就把进度/结果发到**你自己的** Telegram；不配只写本地日志 |
| `NOTIFY_WEBHOOK_URL` | 空 | 配了就把通知 POST 到你自己的 webhook（`{"text": "..."}`） |

## 术语纠正词表（可选）
在 `scripts/user_glossary.json` 放：
```json
{"entries": [
  {"right": "正确词", "wrong": ["常被听错成1", "常被听错成2"]}
]}
```
转写后自动把 wrong→right 确定性替换（提升领域专有名词/人名的准确率与可检索性）。不放文件则跳过。

## RAG 检索
```bash
export RAG_ENABLED=1
scripts/rag_index.py index ~/Recordings/transcripts/2026-10-31/*.txt   # 手动补建
scripts/rag_index.py query "某主题讲了什么" --k 5                        # 问答检索
scripts/rag_index.py stats
```
有 `OPENAI_API_KEY` → 语义向量检索；没有 → 零依赖本地词法检索。
