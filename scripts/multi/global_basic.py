#!/usr/bin/env python3
"""对 OBS 共享配置 global.ini 的 [Basic] 段做「快照 / 还原」。
[Basic] 段记录「当前用哪套场景集合+配置」。多流开录前 snapshot、停录后 restore，
保证单流 skill 每次启动看到的都是它自己的那套。只动 [Basic] 段，其余段逐行原样保留。

用法:
  global_basic.py snapshot           # 把当前 [Basic] 段存到快照
  global_basic.py restore            # 用快照覆盖当前 [Basic] 段
  global_basic.py current            # 打印当前 SceneCollection 值(供守护判断)
"""
import os
import sys

GLOBAL_INI = os.path.expanduser("~/Library/Application Support/obs-studio/global.ini")
SNAP = os.path.expanduser("~/.multi-recording/global_basic.snapshot")


def _read(path):
    with open(path, "r") as f:
        return f.read()


def _extract_basic(text):
    """返回 (before, basic_block, after)。basic_block 含 '[Basic]' 行到下一个 '[' 前。"""
    lines = text.splitlines(keepends=True)
    start = None
    for i, ln in enumerate(lines):
        if ln.strip() == "[Basic]":
            start = i
            break
    if start is None:
        return text, None, ""
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].lstrip().startswith("["):
            end = j
            break
    return "".join(lines[:start]), "".join(lines[start:end]), "".join(lines[end:])


def snapshot():
    _, basic, _ = _extract_basic(_read(GLOBAL_INI))
    if basic is None:
        print("⚠️ 当前 global.ini 无 [Basic] 段，快照记为空", file=sys.stderr)
        basic = ""
    with open(SNAP, "w") as f:
        f.write(basic)
    print(f"✅ 已快照 [Basic] 段 → {SNAP} ({len(basic)}B)")


def restore():
    if not os.path.exists(SNAP):
        print(f"❌ 无快照 {SNAP}，跳过还原", file=sys.stderr)
        sys.exit(1)
    snap_basic = _read(SNAP)
    before, cur_basic, after = _extract_basic(_read(GLOBAL_INI))
    if cur_basic is None:
        # 当前没有 [Basic] 段：把快照 [Basic] 追加到文件末尾(INI 段顺序无关)。
        base = before  # 无 [Basic] 时 before=整个文件, after=""
        if base and not base.endswith("\n"):
            base += "\n"
        new = base + snap_basic
    else:
        new = before + snap_basic + after
    tmp = GLOBAL_INI + ".mrec.tmp"
    with open(tmp, "w") as f:
        f.write(new)
    os.replace(tmp, GLOBAL_INI)  # 原子替换
    print("✅ 已用快照还原 global.ini 的 [Basic] 段")


def current():
    _, basic, _ = _extract_basic(_read(GLOBAL_INI))
    val = ""
    for ln in (basic or "").splitlines():
        if ln.startswith("SceneCollection="):
            val = ln.split("=", 1)[1].strip()
            break
    print(val)


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "current"
    {"snapshot": snapshot, "restore": restore, "current": current}.get(
        action, current)()
