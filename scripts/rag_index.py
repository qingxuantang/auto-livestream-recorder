#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rag_index.py — 可选的「本地转写知识库」（去私有版，通用）。

把转写文字稿切块存成本地索引，之后可对历史转写做语义/关键词检索问答。
**纯本地**：索引落在 ~/Recordings/rag/，不连任何外部/第三方库。默认不启用
（postprocess 仅在 RAG_ENABLED=1 时调用本模块）。

检索模式自动选择：
  · 有 OPENAI_API_KEY → 语义向量（text-embedding-3-small, dim 512，更准）
  · 没有 key          → 纯本地词法检索（零依赖，开箱即用）

用法：
  python3 rag_index.py index <txt/srt 文件...>     # 入库（增量）
  python3 rag_index.py query "你的问题" [--k 5]      # 检索，打印相关段落+出处
  python3 rag_index.py stats
"""
import os, re, sys, json, math, glob

RAG_DIR = os.path.expanduser(os.environ.get("RAG_DIR", "~/Recordings/rag"))
INDEX = os.path.join(RAG_DIR, "index.json")
CHUNK = 600          # 每块约 600 字
OVERLAP = 100
EMBED_MODEL = "text-embedding-3-small"
EMBED_DIM = 512


def _key(): return os.environ.get("OPENAI_API_KEY", "").strip()


def _load():
    if os.path.exists(INDEX):
        try: return json.load(open(INDEX, encoding="utf-8"))
        except Exception: pass
    return {"mode": "openai" if _key() else "lexical", "chunks": []}


def _save(d):
    os.makedirs(RAG_DIR, exist_ok=True)
    json.dump(d, open(INDEX, "w", encoding="utf-8"), ensure_ascii=False)


def _chunks(text):
    text = re.sub(r"\s+", " ", text).strip()
    out, i = [], 0
    while i < len(text):
        out.append(text[i:i + CHUNK])
        i += CHUNK - OVERLAP
    return [c for c in out if c.strip()]


def _embed(texts):
    import openai
    cli = openai.OpenAI()
    r = cli.embeddings.create(model=EMBED_MODEL, input=texts, dimensions=EMBED_DIM)
    return [d.embedding for d in r.data]


def _cos(a, b):
    s = sum(x * y for x, y in zip(a, b)); na = math.sqrt(sum(x * x for x in a)); nb = math.sqrt(sum(y * y for y in b))
    return s / (na * nb) if na and nb else 0.0


_TOK = re.compile(r"[\w一-鿿]+")
def _toks(s):  # 词法检索：英文按词、中文按 2-gram
    out = []
    for t in _TOK.findall(s.lower()):
        if re.search(r"[一-鿿]", t):
            out += [t[i:i+2] for i in range(len(t)-1)] or [t]
        else:
            out.append(t)
    return out


def cmd_index(files):
    d = _load(); seen = {(c["source"], c["idx"]) for c in d["chunks"]}
    use_openai = d["mode"] == "openai" and _key()
    added, pending = 0, []
    for f in files:
        f = os.path.expanduser(f)
        if not os.path.exists(f): print(f"skip (missing): {f}"); continue
        src = os.path.basename(f)
        for idx, ch in enumerate(_chunks(open(f, encoding="utf-8", errors="ignore").read())):
            if (src, idx) in seen: continue
            rec = {"source": src, "idx": idx, "text": ch}
            if use_openai: pending.append(rec)
            else: rec["toks"] = _toks(ch)
            d["chunks"].append(rec); added += 1
    if use_openai and pending:
        for i in range(0, len(pending), 96):
            batch = pending[i:i+96]
            for rec, v in zip(batch, _embed([r["text"] for r in batch])): rec["vec"] = v
    _save(d); print(f"✅ 入库 {added} 块（mode={d['mode']}，共 {len(d['chunks'])} 块）")


def cmd_query(q, k=5):
    d = _load()
    if not d["chunks"]: print("（索引为空）"); return
    if d["mode"] == "openai" and _key():
        qv = _embed([q])[0]
        scored = sorted(((_cos(qv, c.get("vec", [])), c) for c in d["chunks"]), key=lambda t: -t[0])
    else:
        qt = _toks(q); qs = set(qt)
        def sc(c):
            ct = c.get("toks") or _toks(c["text"])
            inter = sum(1 for t in ct if t in qs)
            return inter / (1 + math.log(1 + len(ct)))
        scored = sorted(((sc(c), c) for c in d["chunks"]), key=lambda t: -t[0])
    print(f"🔎 「{q}」 top-{k}（mode={d['mode']}）：\n")
    for s, c in scored[:k]:
        print(f"— 出处 {c['source']} #块{c['idx']}  (score {s:.3f})")
        print(f"  {c['text'][:220]}…\n")


def main(a):
    if not a: print(__doc__); return
    if a[0] == "index": cmd_index(a[1:])
    elif a[0] == "query":
        rest = a[1:]; k = 5
        if "--k" in rest: i = rest.index("--k"); k = int(rest[i+1]); rest = rest[:i] + rest[i+2:]
        cmd_query(" ".join(rest), k)
    elif a[0] == "stats":
        d = _load(); print(f"mode={d['mode']} chunks={len(d['chunks'])} sources={len({c['source'] for c in d['chunks']})}")
    else: print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
