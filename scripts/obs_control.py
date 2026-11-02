#!/usr/bin/env python3
"""OBS WebSocket v5 controller.

Usage:
  obs_control.py <start|stop|status|fix_chrome> [host] [port] [password]
  obs_control.py fix_window "<窗口匹配串>" [host] [port] [password]

fix_window 是 fix_chrome 的通用版（2026-07-15 加）：原来 _fix_chrome_source 把
"[Google Chrome]" 硬编码在里面，只能绑 Chrome。录 AdsPower 里的 Zoom 时才发现——
**网页并不在 AdsPower 里**：AdsPower Global 只是 Electron 管理端，真正渲染网页的是它
自带的 Chromium 分支 SunBrowser.app (com.adspower.SunBrowser)，OBS 窗口列表里显示为
"[SunBrowser] xxx"。硬编码 Chrome 的话永远找不到它，只会默默绑回 Chrome 窗口录错东西。
  fix_chrome  == fix_window "[Google Chrome]"（行为完全不变，夜间任务照常用）

⚠️ 2026-07-25 改为 Application Capture（type=2）绑定，不再用 Window Capture（type=1）：
macOS 上 Window Capture 抓 Chrome 经常黑屏——Chrome 的视频/硬件加速层走独立 IOSurface
合成，ScreenCaptureKit 的单窗口采集常抓不到这层；且窗口 id 每次重开都变。改成按**应用
bundle id** 绑定整个 app（type=2）后：①绕过黑屏；②bundle id 永不变，Chrome 重开后无需
重绑，fix_chrome 变幂等。注意：Application Capture 绑在某块显示器（display_uuid）上，
直播页必须留在那块屏，拖到别的显示器会黑。
"""
import asyncio
import base64
import hashlib
import json
import sys
import uuid

SOURCE_NAME = "chrome mark"
# OBS 窗口列表里的匹配串 → 应用 bundle id（Application Capture 按 bundle id 绑定，稳定不变）
APP_BUNDLES = {
    "[Google Chrome]": "com.google.Chrome",
    "[SunBrowser]": "com.adspower.SunBrowser",
}


async def _connect(host, port, password):
    import websockets
    ws = await websockets.connect(f"ws://{host}:{port}", open_timeout=5)
    hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
    if hello["op"] != 0:
        raise RuntimeError(f"Expected Hello (op 0), got op {hello['op']}")
    identify_data: dict = {"rpcVersion": 1}
    if "authentication" in hello["d"] and password:
        auth = hello["d"]["authentication"]
        secret = base64.b64encode(
            hashlib.sha256((password + auth["salt"]).encode()).digest()
        ).decode()
        auth_response = base64.b64encode(
            hashlib.sha256((secret + auth["challenge"]).encode()).digest()
        ).decode()
        identify_data["authentication"] = auth_response
    await ws.send(json.dumps({"op": 1, "d": identify_data}))
    identified = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
    if identified["op"] != 2:
        raise RuntimeError(f"Expected Identified (op 2), got op {identified['op']}")
    return ws


async def _obs_call(ws, req_type, req_data=None):
    await ws.send(json.dumps({
        "op": 6,
        "d": {"requestType": req_type, "requestId": str(uuid.uuid4())[:8], "requestData": req_data or {}}
    }))
    resp = json.loads(await asyncio.wait_for(ws.recv(), timeout=8))
    return resp["d"]


async def _request(action, host, port, password, match=None):
    import websockets

    async with await _connect(host, port, password) as ws:
        if action == "fix_chrome":
            await _bind_app_source(ws, "[Google Chrome]")
            return
        if action == "fix_window":
            if not match:
                print("❌ fix_window 需要窗口匹配串，例: fix_window \"[SunBrowser]\"", file=sys.stderr)
                sys.exit(1)
            await _bind_app_source(ws, match)
            return
        if action == "ensure_single_profile":
            # 单流录制必须用 Untitled profile（Simple 单音轨，录 ~/Recordings/raw）。
            # multi-live 会切到 multi profile（录 ~/Recordings/multi-raw）；若上一场多直播没还原、
            # 或 OBS 被留在 multi profile，单流录制会写进 multi-raw → 后处理守护只扫 raw/ → 录了却没转写/入库
            # （2026-09-04 实锤：9-2/9-3 两场直播录成功但整条转写→RAG 没触发，就是这个坑）。开录前强制切回。
            # ⚠️ OBS 刚 open 起来那几秒 profile 可能短暂是 multi 且拒绝切换 → 重试+核验（2026-09-04 实测）。
            ok = False; cur = "?"
            for attempt in range(5):
                d = await _obs_call(ws, "GetProfileList")
                cur = d.get("responseData", {}).get("currentProfileName", "")
                if cur == "Untitled":
                    ok = True
                    break
                await _obs_call(ws, "SetCurrentProfile", {"profileName": "Untitled"})
                await asyncio.sleep(3)  # 给 OBS 时间完成切换/初始化
                d2 = await _obs_call(ws, "GetProfileList")
                if d2.get("responseData", {}).get("currentProfileName", "") == "Untitled":
                    ok = True; cur = "Untitled"
                    break
            if ok:
                print("✅ OBS profile = 单流 Untitled（录制→~/Recordings/raw）")
            else:
                print(f"❌ OBS profile 仍是 {cur}（≠Untitled），切换 5 次未成 → 会录进 multi-raw！请手动在 OBS 选 Untitled profile", file=sys.stderr)
                sys.exit(1)
            return

        if action == "ensure_single_collection":
            # 单流录制必须用 Untitled **场景集合**（含源 "chrome mark" / 场景「网页直播录制」）。
            # multi-live 集合只有 cap1/cap2、没有 chrome mark → fix_chrome 会报「No source chrome mark」
            # 且会录到 multi-live 场景（2026-09-11 实锤：OBS 被留在 multi-live 集合，单流开录前 fix_chrome 失败）。
            # 注意 profile 与 scene collection 是两回事：ensure_single_profile 只切 profile，切不了集合。
            # SetCurrentSceneCollection 会让 OBS 重载并**断开当前 ws** → 切换后必须重连核验。
            TARGET = "Untitled"
            d = await _obs_call(ws, "GetSceneCollectionList")
            cur = d.get("responseData", {}).get("currentSceneCollectionName", "")
            if cur == TARGET:
                print(f"✅ OBS 场景集合 = {TARGET}")
                return
            try:
                await _obs_call(ws, "SetCurrentSceneCollection", {"sceneCollectionName": TARGET})
            except Exception:
                pass  # 切换会断开 ws，异常忽略，靠下面重连核验
            ok = False
            for _ in range(5):
                await asyncio.sleep(2)
                try:
                    async with await _connect(host, port, password) as ws2:
                        d2 = await _obs_call(ws2, "GetSceneCollectionList")
                        if d2.get("responseData", {}).get("currentSceneCollectionName", "") == TARGET:
                            ok = True
                            break
                except Exception:
                    continue
            if ok:
                print(f"✅ OBS 场景集合 = {TARGET}（已从 {cur!r} 切回）")
            else:
                print(f"❌ OBS 场景集合仍是 {cur!r}（≠{TARGET}），切换未成 → fix_chrome 会失败/录错场景。请手动在 OBS 选 Untitled 集合", file=sys.stderr)
                sys.exit(1)
            return

        type_map = {"start": "StartRecord", "stop": "StopRecord", "status": "GetRecordStatus"}
        request_type = type_map.get(action)
        if not request_type:
            print(f"❌ 未知操作: {action}", file=sys.stderr)
            sys.exit(1)

        d = (await _obs_call(ws, request_type))
        ok = d.get("requestStatus", {}).get("result", False)

        if action == "status":
            active = d.get("responseData", {}).get("outputActive", False)
            print(f'录制状态: {"录制中 🔴" if active else "未录制 ⬛"}')
        elif ok:
            print("✅ OBS 录制已开始" if action == "start" else "✅ OBS 录制已停止")
        else:
            comment = d.get("requestStatus", {}).get("comment", "未知错误")
            print(f"❌ OBS 返回错误: {comment}", file=sys.stderr)
            sys.exit(1)


async def _bind_app_source(ws, match="[Google Chrome]"):
    """Bind the OBS macOS Screen Capture source to an *application* (type=2) by its
    bundle id, instead of a single window (type=1).

    See module docstring for why: Window Capture renders Chrome black on macOS, and
    window ids drift on every reopen. Application Capture binds by a stable bundle id.

    We set only type + application; SetInputSettings defaults to overlay=true (merge),
    so the pre-configured `display_uuid` (which display to capture) is preserved. No
    retry loop needed — the bundle id is static and does not depend on a window being
    open at this instant.
    """
    bundle = APP_BUNDLES.get(match)
    if bundle is None:
        # Unknown match string: resolve bundle id from OBS's "application" dropdown by name.
        bundle = await _resolve_bundle(ws, match)
    if not bundle:
        print(f"❌ 无法解析 {match} 对应的应用 bundle id", file=sys.stderr)
        sys.exit(1)

    d = await _obs_call(ws, "SetInputSettings", {
        "inputName": SOURCE_NAME,
        "inputSettings": {"type": 2, "application": bundle},
    })
    ok = d.get("requestStatus", {}).get("result", False)
    if ok:
        print(f"✅ Application Capture 已绑定 → {match} ({bundle})")
    else:
        print(f"❌ SetInputSettings failed: {d.get('requestStatus', {})}", file=sys.stderr)
        sys.exit(1)


async def _resolve_bundle(ws, match):
    """Fallback for match strings not in APP_BUNDLES: switch the source to application
    mode so the 'application' property list populates, then return the bundle id whose
    display name (or value) contains `match` (brackets stripped)."""
    await _obs_call(ws, "SetInputSettings", {
        "inputName": SOURCE_NAME, "inputSettings": {"type": 2},
    })
    await asyncio.sleep(1.0)  # give OBS time to reload the property list
    d = await _obs_call(ws, "GetInputPropertiesListPropertyItems", {
        "inputName": SOURCE_NAME, "propertyName": "application",
    })
    want = match.strip("[]").strip().lower()
    for item in d.get("responseData", {}).get("propertyItems", []):
        name = str(item.get("itemName", "")).lower()
        val = str(item.get("itemValue", ""))
        if want and (want in name or want in val.lower()):
            return val
    return None


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    # fix_window 多吃一个位置参数(匹配串)，其余参数顺延；其它动作的调用方式完全不变
    if action == "fix_window":
        match    = sys.argv[2] if len(sys.argv) > 2 else None
        host     = sys.argv[3] if len(sys.argv) > 3 else "localhost"
        port     = int(sys.argv[4]) if len(sys.argv) > 4 else 4455
        password = sys.argv[5] if len(sys.argv) > 5 else ""
    else:
        match    = None
        host     = sys.argv[2] if len(sys.argv) > 2 else "localhost"
        port     = int(sys.argv[3]) if len(sys.argv) > 3 else 4455
        password = sys.argv[4] if len(sys.argv) > 4 else ""

    try:
        asyncio.run(_request(action, host, port, password, match))
    except ConnectionRefusedError:
        print("❌ 无法连接 OBS WebSocket，请确认：", file=sys.stderr)
        print("   1. OBS 已启动", file=sys.stderr)
        print("   2. 工具 → WebSocket 服务器设置 → 已启用（端口 4455）", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ 错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
