#!/usr/bin/env python3
"""可选的转写术语纠正（通用）。

Whisper 对特定领域的专有名词/人名/术语有时会听错。你可以准备一份**自己的**词表，
对转写文本做确定性 find-replace，让关键词检索/阅读更准。**默认不启用**：
词表文件（user_glossary.json）不存在时本模块为 no-op，不改动任何文本。

词表格式（user_glossary.json）：
  {"entries": [{"right": "正确词", "wrong": ["常见错听1", "常见错听2"]}, ...]}

用法：
  · 作为库：from glossary_correct import correct_text; new, hits = correct_text(s)
  · 预览某文件会改什么（不落盘）：python3 glossary_correct.py --preview <file>
  · 就地纠正文件（会备份 .bak）：python3 glossary_correct.py --apply <file>
"""
import json
import os
import sys

# 用户自备词表（可选）；不存在则本模块为 no-op。可用 GLOSSARY_PATH 环境变量覆盖路径。
GLOSSARY_PATH = os.environ.get(
    "GLOSSARY_PATH",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "user_glossary.json"),
)


def load_glossary(path=GLOSSARY_PATH):
    """返回 [(wrong, right), ...]，按 wrong 长度降序（先长后短，避免子串先被换掉）。
    词表文件不存在 → 返回空（no-op）。"""
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    pairs = []
    for e in data.get("entries", []):
        right = e["right"]
        for w in e.get("wrong", []):
            if w and w != right:
                pairs.append((w, right))
    pairs.sort(key=lambda p: len(p[0]), reverse=True)
    return pairs


def correct_text(text, pairs=None):
    """对 text 做确定性替换。返回 (new_text, hits)；hits=[(wrong, right, count), ...]。"""
    if pairs is None:
        pairs = load_glossary()
    hits = []
    for wrong, right in pairs:
        c = text.count(wrong)
        if c:
            text = text.replace(wrong, right)
            hits.append((wrong, right, c))
    return text, hits


def _fmt_hits(hits):
    return "；".join(f"{w}→{r}×{c}" for w, r, c in hits) if hits else "(无命中)"


def main(argv):
    if len(argv) < 3 or argv[1] not in ("--preview", "--apply"):
        print("用法: glossary_correct.py --preview|--apply <file>")
        return 2
    mode, path = argv[1], argv[2]
    if not os.path.exists(path):
        print(f"文件不存在: {path}")
        return 1
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()
    new, hits = correct_text(text)
    print(f"{os.path.basename(path)}: {_fmt_hits(hits)}")
    if mode == "--apply" and hits:
        with open(path + ".bak", "w", encoding="utf-8") as f:
            f.write(text)
        with open(path, "w", encoding="utf-8") as f:
            f.write(new)
        print(f"  已就地纠正（原文件备份为 {os.path.basename(path)}.bak）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
