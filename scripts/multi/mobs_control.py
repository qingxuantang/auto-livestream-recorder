#!/usr/bin/env python3
"""Multi-live OBS WebSocket v5 controller (独立于现有 obs_control.py)。

给「多直播录制 skill」专用的那台 OBS 副本（OBS-Multi，portable，默认 websocket 端口
4466）做控制。跟 screen-recording-pipeline/scripts/obs_control.py 完全独立、互不影响：
不同端口、不同源名、不同场景。

核心差异：多直播用「单实例 + 多音轨」——一个场景里放 N 个 App 采集源（Chrome/Safari/…
各占一块画面），每个源的**音频路由到独立音轨**（源1→音轨1，源2→音轨2…）。录出的
mkv 有 N 条独立音轨，事后用 ffmpeg 拆轨分别转写，音频天然分开。

用法:
  mobs_control.py start   [host] [port] [password]
  mobs_control.py stop    [host] [port] [password]
  mobs_control.py status  [host] [port] [password]
  mobs_control.py bind <source_name> <match> <track> [host] [port] [password]
      把 <source_name> 这个 macOS 采集源绑到 <match> 对应的应用(Application Capture,
      bundle id 稳定)，并把它的音频只路由到第 <track> 号音轨。
      match 例: "[Google Chrome]" / "[Safari]"; track: 1..6
  mobs_control.py meters  <source_name> <seconds> [host] [port] [password]
      采样某源的音频电平峰值(dB)若干秒，用于静音判定(v2 用)。

默认: host=localhost port=4466 password=(空，从 ~/.multi-recording/obs_ws_pass 读)
"""
import asyncio
import base64
import hashlib
import json
import os
import sys
import uuid

# match 串 → 应用 bundle id（Application Capture 按 bundle id 绑定，稳定不变）
APP_BUNDLES = {
    "[Google Chrome]": "com.google.Chrome",
    "[Safari]": "com.apple.Safari",
    "[Microsoft Edge]": "com.microsoft.edgemac",
    "[Firefox]": "org.mozilla.firefox",
    "[SunBrowser]": "com.adspower.SunBrowser",
}

# 共享同一份 OBS 配置(macOS 无法给 OBS 配置隔离)，因此复用主 OBS 的 websocket:
# 端口 4455、密码从共享配置读取。多流与单流不会同时跑，共用一个 websocket 无冲突。
DEFAULT_PORT = 4455
WS_CONFIG = os.path.expanduser(
    "~/Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json")


def _default_password():
    try:
        with open(WS_CONFIG) as f:
            return json.load(f).get("server_password", "")
    except (OSError, ValueError):
        return ""


async def _connect(host, port, password):
    import websockets
    ws = await websockets.connect(f"ws://{host}:{port}", open_timeout=5)
    hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
    if hello["op"] != 0:
        raise RuntimeError(f"Expected Hello (op 0), got op {hello['op']}")
    identify_data = {"rpcVersion": 1}
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
        "d": {"requestType": req_type, "requestId": str(uuid.uuid4())[:8],
              "requestData": req_data or {}},
    }))
    resp = json.loads(await asyncio.wait_for(ws.recv(), timeout=8))
    return resp["d"]


async def _resolve_bundle(ws, source_name, match):
    """match 不在表里时，把源切到 application 模式让属性列表填充，再按名字/值模糊匹配。"""
    await _obs_call(ws, "SetInputSettings", {
        "inputName": source_name, "inputSettings": {"type": 2},
    })
    await asyncio.sleep(1.0)
    d = await _obs_call(ws, "GetInputPropertiesListPropertyItems", {
        "inputName": source_name, "propertyName": "application",
    })
    want = match.strip("[]").strip().lower()
    for item in d.get("responseData", {}).get("propertyItems", []):
        name = str(item.get("itemName", "")).lower()
        val = str(item.get("itemValue", ""))
        if want and (want in name or want in val.lower()):
            return val
    return None


async def _bind(ws, source_name, match, track):
    """绑源到 App + 把音频只放到指定音轨。"""
    bundle = APP_BUNDLES.get(match) or await _resolve_bundle(ws, source_name, match)
    if not bundle:
        print(f"❌ 无法解析 {match} 的 bundle id", file=sys.stderr)
        sys.exit(1)
    # 1) 绑应用（Application Capture, type=2）。overlay 默认合并，保留 display_uuid。
    d = await _obs_call(ws, "SetInputSettings", {
        "inputName": source_name,
        "inputSettings": {"type": 2, "application": bundle},
    })
    if not d.get("requestStatus", {}).get("result", False):
        print(f"❌ 绑应用失败: {d.get('requestStatus', {})}", file=sys.stderr)
        sys.exit(1)
    # 2) 音频只路由到第 track 号音轨（其余全关），实现每路一条独立音轨。
    tracks = {str(i): (i == int(track)) for i in range(1, 7)}
    d2 = await _obs_call(ws, "SetInputAudioTracks", {
        "inputName": source_name, "inputAudioTracks": tracks,
    })
    if not d2.get("requestStatus", {}).get("result", False):
        # 有的采集源本身不产音频(纯视频)，此时 SetInputAudioTracks 会报错，提示但不致命。
        print(f"⚠️  设音轨失败(源可能无音频): {d2.get('requestStatus', {}).get('comment')}",
              file=sys.stderr)
    print(f"✅ {source_name} → {match} ({bundle})  音频=音轨{track}")


async def _meters(ws, source_name, seconds):
    """订阅高频音量事件，采样峰值 dB。"""
    # 重新以带 InputVolumeMeters(高频) 订阅位的方式识别
    peak = -200.0
    import time
    # 简易实现：轮询 GetInputVolumeMeters 不存在，改为读事件流
    end = None
    got = 0
    while True:
        try:
            raw = await asyncio.wait_for(ws.recv(), timeout=float(seconds) + 2)
        except asyncio.TimeoutError:
            break
        msg = json.loads(raw)
        if msg.get("op") == 5 and msg["d"].get("eventType") == "InputVolumeMeters":
            for inp in msg["d"]["eventData"].get("inputs", []):
                if inp.get("inputName") == source_name:
                    for ch in inp.get("inputLevelsMul", []):
                        for v in ch:
                            if v > 0:
                                import math
                                db = 20 * math.log10(v)
                                peak = max(peak, db)
                    got += 1
        if end is None:
            end = time.monotonic() + float(seconds)
        if time.monotonic() >= end and got > 0:
            break
    print(f"{peak:.1f}")


async def _request(argv):
    action = argv[1] if len(argv) > 1 else "status"
    password_default = _default_password()

    if action == "bind":
        source_name = argv[2]
        match = argv[3]
        track = argv[4]
        host = argv[5] if len(argv) > 5 else "localhost"
        port = int(argv[6]) if len(argv) > 6 else DEFAULT_PORT
        password = argv[7] if len(argv) > 7 else password_default
        async with await _connect(host, port, password) as ws:
            await _bind(ws, source_name, match, track)
        return

    if action == "meters":
        source_name = argv[2]
        seconds = argv[3] if len(argv) > 3 else "3"
        host = argv[4] if len(argv) > 4 else "localhost"
        port = int(argv[5]) if len(argv) > 5 else DEFAULT_PORT
        password = argv[6] if len(argv) > 6 else password_default
        import websockets
        ws = await websockets.connect(f"ws://{host}:{port}", open_timeout=5)
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        identify = {"rpcVersion": 1, "eventSubscriptions": (1 << 16)}  # InputVolumeMeters(高频)
        if "authentication" in hello["d"] and password:
            auth = hello["d"]["authentication"]
            secret = base64.b64encode(hashlib.sha256((password + auth["salt"]).encode()).digest()).decode()
            identify["authentication"] = base64.b64encode(
                hashlib.sha256((secret + auth["challenge"]).encode()).digest()).decode()
        await ws.send(json.dumps({"op": 1, "d": identify}))
        await asyncio.wait_for(ws.recv(), timeout=5)
        await _meters(ws, source_name, seconds)
        await ws.close()
        return

    host = argv[2] if len(argv) > 2 else "localhost"
    port = int(argv[3]) if len(argv) > 3 else DEFAULT_PORT
    password = argv[4] if len(argv) > 4 else password_default

    async with await _connect(host, port, password) as ws:
        type_map = {"start": "StartRecord", "stop": "StopRecord", "status": "GetRecordStatus"}
        request_type = type_map.get(action)
        if not request_type:
            print(f"❌ 未知操作: {action}", file=sys.stderr)
            sys.exit(1)
        d = await _obs_call(ws, request_type)
        ok = d.get("requestStatus", {}).get("result", False)
        if action == "status":
            active = d.get("responseData", {}).get("outputActive", False)
            print(f'录制状态: {"录制中 🔴" if active else "未录制 ⬛"}')
        elif ok:
            print("✅ OBS-Multi 录制已开始" if action == "start" else "✅ OBS-Multi 录制已停止")
        else:
            comment = d.get("requestStatus", {}).get("comment", "未知错误")
            print(f"❌ OBS 返回错误: {comment}", file=sys.stderr)
            sys.exit(1)


def main():
    try:
        asyncio.run(_request(sys.argv))
    except ConnectionRefusedError:
        print("❌ 无法连接 OBS WebSocket(端口 4455)。确认 OBS 已启动、"
              "工具→WebSocket 服务器设置已启用。", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ 错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
