#!/usr/bin/env python3
"""把「多流场景集合 multi-live + 多音轨配置 multi」作为**新增文件**写进 OBS 共享配置。
只写这两个新文件，绝不触碰 global.ini / websocket 配置 / 单流的 Untitled 场景与配置。

- scenes/multi-live.json : 场景 multi-live，含 cap1(Chrome,音轨1) + cap2(Safari,音轨2)，
  各 macOS 屏幕采集源开启 capture_audio、用 mixers 位掩码把音频只送进各自音轨。
- profiles/multi/basic.ini : Advanced 输出 + mkv + 多音轨(RecTracks=3=轨1+轨2) + ~/Recordings/multi-raw。
"""
import json
import os

OBS_CFG = os.path.expanduser("~/Library/Application Support/obs-studio")
DISPLAY_UUID = "F806370E-E308-4E1D-A9AE-3E7BAD5EB37C"  # UGREEN 主屏，抄自单流 chrome mark 源
REC_DIR = os.path.expanduser("~/Recordings/multi-raw")

SCENES = f"{OBS_CFG}/basic/scenes"
PROFILE = f"{OBS_CFG}/basic/profiles/multi"
os.makedirs(SCENES, exist_ok=True)
os.makedirs(PROFILE, exist_ok=True)

# 安全闸：绝不覆盖单流的 Untitled 场景/配置或 global.ini
assert not os.path.basename(SCENES + "/multi-live.json").startswith("Untitled")

# ---------- profile: Advanced 输出 + 多音轨 mkv ----------
basic_ini = f"""[General]
Name=multi

[Output]
Mode=Advanced

[AdvOut]
RecType=Standard
RecFilePath={REC_DIR}
RecFormat2=mkv
RecEncoder=obs_x264
RecRescale=false
RecTracks=3
RecAudioEncoder=CoreAudio_AAC
FLVTrack=1
Track1Bitrate=160
Track2Bitrate=160
Track3Bitrate=160
Track4Bitrate=160
Track5Bitrate=160
Track6Bitrate=160
RecRB=false
RecSplitFile=false

[Video]
BaseCX=1920
BaseCY=1080
OutputCX=1920
OutputCY=1080
FPSType=0
FPSCommon=30
ScaleType=bicubic
ColorFormat=NV12
ColorSpace=709
ColorRange=Partial

[Audio]
MonitoringDeviceId=default
MonitoringDeviceName=Default
SampleRate=48000
ChannelSetup=Stereo
"""
with open(f"{PROFILE}/basic.ini", "w") as f:
    f.write(basic_ini)


def cap_source(name, uuid, bundle, mixers):
    return {
        "prev_ver": 536936449, "name": name, "uuid": uuid,
        "id": "screen_capture", "versioned_id": "screen_capture",
        "settings": {
            "application": bundle, "display_uuid": DISPLAY_UUID,
            "type": 2, "capture_audio": True, "show_hidden_windows": False,
        },
        "mixers": mixers,  # 1=只进音轨1, 2=只进音轨2
        "sync": 0, "flags": 0, "volume": 1.0, "balance": 0.5,
        "enabled": True, "muted": False,
        "push-to-mute": False, "push-to-mute-delay": 0,
        "push-to-talk": False, "push-to-talk-delay": 0,
        "hotkeys": {"libobs.mute": [], "libobs.unmute": [],
                    "libobs.push-to-mute": [], "libobs.push-to-talk": []},
        "deinterlace_mode": 0, "deinterlace_field_order": 0,
        "monitoring_type": 0, "private_settings": {},
    }


def scene_item(name, uuid, item_id, pos_x, bounds_x):
    return {
        "name": name, "source_uuid": uuid,
        "visible": True, "locked": False, "rot": 0.0,
        "scale_ref": {"x": 1920.0, "y": 1080.0},
        "align": 5, "bounds_type": 2, "bounds_align": 0, "bounds_crop": False,
        "crop_left": 0, "crop_top": 0, "crop_right": 0, "crop_bottom": 0,
        "id": item_id, "group_item_backup": False,
        "pos": {"x": float(pos_x), "y": 0.0},
        "scale": {"x": 1.0, "y": 1.0},
        "bounds": {"x": float(bounds_x), "y": 1080.0},
        "scale_filter": "disable", "blend_method": "default", "blend_type": "normal",
        "show_transition": {"duration": 300}, "hide_transition": {"duration": 300},
        "private_settings": {},
    }


CAP1_UUID = "11111111-1111-4111-8111-111111111111"
CAP2_UUID = "22222222-2222-4222-8222-222222222222"

collection = {
    "name": "multi-live",
    "sources": [
        cap_source("cap1", CAP1_UUID, "com.google.Chrome", 1),  # 左半屏, 音轨1
        cap_source("cap2", CAP2_UUID, "com.apple.Safari", 2),   # 右半屏, 音轨2
        {
            "prev_ver": 536936449, "name": "multi-live",
            "uuid": "33333333-3333-4333-8333-333333333333",
            "id": "scene", "versioned_id": "scene",
            "settings": {"id_counter": 3, "custom_size": False, "items": [
                scene_item("cap1", CAP1_UUID, 1, 0, 960),
                scene_item("cap2", CAP2_UUID, 2, 960, 960),
            ]},
            "mixers": 0, "sync": 0, "flags": 0, "volume": 1.0, "balance": 0.5,
            "enabled": True, "muted": False,
            "push-to-mute": False, "push-to-mute-delay": 0,
            "push-to-talk": False, "push-to-talk-delay": 0,
            "hotkeys": {}, "deinterlace_mode": 0, "deinterlace_field_order": 0,
            "monitoring_type": 0, "private_settings": {},
        },
    ],
    "groups": [],
    "scene_order": [{"name": "multi-live"}],
    "current_scene": "multi-live", "current_program_scene": "multi-live",
    "canvases": [], "current_transition": "Fade", "transition_duration": 300,
    "transitions": [], "saved_projectors": [], "preview_locked": False,
    "scaling_enabled": False, "scaling_level": -11,
    "scaling_off_x": 0.0, "scaling_off_y": 0.0,
    "virtual-camera": {"type2": 3}, "modules": {},
    "resolution": {"x": 1920, "y": 1080}, "version": 2,
}
with open(f"{SCENES}/multi-live.json", "w") as f:
    json.dump(collection, f, indent=4, ensure_ascii=False)

print("✅ 已写入(仅新增, 未碰 global.ini/websocket/Untitled):")
print(f"   {SCENES}/multi-live.json")
print(f"   {PROFILE}/basic.ini")
