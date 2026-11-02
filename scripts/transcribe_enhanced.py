#!/usr/bin/env python3
"""
Enhanced transcription module for screen-recording-pipeline.
Dual-engine: local Whisper (default, no key needed) + optional OpenAI API (set TRANSCRIBE_ENGINE=openai + OPENAI_API_KEY).
Outputs SRT format with intelligent deduplication.
"""

import os
import sys
import json
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Optional, List, Tuple

def get_openai_key():
    """OpenAI API key from environment only (optional; local whisper is the default engine)."""
    return os.environ.get("OPENAI_API_KEY", "")

# Configuration - lazy load
OPENAI_API_KEY = get_openai_key()
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "~/.cache/whisper/ggml-medium.bin")
# 转写引擎：默认本地 Whisper（零外部凭据、数据不出本机）。
# 仅当 TRANSCRIBE_ENGINE=openai 且提供 OPENAI_API_KEY 时才走 OpenAI API。
TRANSCRIBE_ENGINE = os.environ.get("TRANSCRIBE_ENGINE", "local").strip().lower()
SILENCE_THRESHOLD = -50  # dB
MIN_SILENCE_DURATION = 60  # seconds
MIN_SEGMENT_DURATION = 3  # seconds
MAX_REPEAT_COUNT = 5  # max allowed repeats before marking as hallucination


def log(msg: str):
    """Print timestamped log."""
    from datetime import datetime
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)


def extract_audio(video_path: str, output_wav: str) -> bool:
    """Extract audio from video using ffmpeg."""
    log(f"Extracting audio from {os.path.basename(video_path)}...")
    try:
        subprocess.run([
            'ffmpeg', '-hide_banner', '-loglevel', 'error',
            '-i', video_path,
            '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le',
            '-y', output_wav
        ], check=True, capture_output=True)
        log(f"Audio extracted: {output_wav}")
        return True
    except subprocess.CalledProcessError as e:
        log(f"Error extracting audio: {e}")
        return False


def detect_silence(audio_path: str) -> List[Tuple[float, float]]:
    """Detect silence segments in audio."""
    log(f"Detecting silence (threshold: {SILENCE_THRESHOLD}dB, min_duration: {MIN_SILENCE_DURATION}s)...")
    
    try:
        result = subprocess.run([
            'ffmpeg', '-i', audio_path,
            '-af', f'silencedetect=noise={SILENCE_THRESHOLD}dB:d={MIN_SILENCE_DURATION}',
            '-f', 'null', '-'
        ], capture_output=True, text=True)
        
        stderr = result.stderr
        
        # Parse silence_start and silence_end
        silence_starts = []
        silence_ends = []
        
        for line in stderr.split('\n'):
            if 'silence_start:' in line:
                match = re.search(r'silence_start:\s*([\d\.]+)', line)
                if match:
                    silence_starts.append(float(match.group(1)))
            elif 'silence_end:' in line:
                match = re.search(r'silence_end:\s*([\d\.]+)', line)
                if match:
                    silence_ends.append(float(match.group(1)))
        
        # Get audio duration
        duration_result = subprocess.run([
            'ffprobe', '-v', 'error',
            '-show_entries', 'format=duration',
            '-of', 'default=noprint_wrappers=1:nokey=1',
            audio_path
        ], capture_output=True, text=True)
        
        total_duration = float(duration_result.stdout.strip())
        
        # Calculate valid segments
        valid_segments = []
        current_pos = 0.0
        
        for i, silence_start in enumerate(silence_starts):
            silence_end = silence_ends[i] if i < len(silence_ends) else total_duration
            
            segment_duration = silence_start - current_pos
            if segment_duration >= MIN_SEGMENT_DURATION:
                valid_segments.append((current_pos, silence_start))
                log(f"Valid segment: {current_pos:.1f}s - {silence_start:.1f}s ({segment_duration:.1f}s)")
            
            current_pos = silence_end
        
        # Add final segment
        if total_duration - current_pos >= MIN_SEGMENT_DURATION:
            valid_segments.append((current_pos, total_duration))
            log(f"Valid segment (end): {current_pos:.1f}s - {total_duration:.1f}s ({total_duration - current_pos:.1f}s)")
        
        log(f"Found {len(valid_segments)} valid segments")
        return valid_segments
        
    except Exception as e:
        log(f"Error detecting silence: {e}")
        # Return whole audio as one segment
        return [(0.0, 999999.0)]  # Will be clamped to actual duration


def transcribe_with_openai(audio_path: str, start_time: float = 0) -> Optional[List[dict]]:
    """Transcribe using OpenAI Whisper API with chunking support for large files."""
    from openai import OpenAI
    
    MAX_SIZE = 25 * 1024 * 1024  # 25MB limit
    CHUNK_DURATION = 600  # 10 minutes per chunk
    
    file_size = os.path.getsize(audio_path)
    
    if file_size <= MAX_SIZE:
        # Small file, transcribe directly
        return _transcribe_openai_single(audio_path, start_time)
    else:
        # Large file, split and transcribe chunks
        log(f"Audio {file_size // (1024*1024)}MB > 25MB, splitting...")
        return _transcribe_openai_chunks(audio_path, start_time, CHUNK_DURATION)


def _transcribe_openai_single(audio_path: str, start_time: float) -> Optional[List[dict]]:
    """Transcribe a single audio file with OpenAI API."""
    try:
        from openai import OpenAI
        client = OpenAI()
        
        log(f"Transcribing with OpenAI API (single file)...")
        
        with open(audio_path, "rb") as f:
            result = client.audio.transcriptions.create(
                model="whisper-1",
                file=f,
                response_format="verbose_json",
                timestamp_granularities=["segment"]
            )
        
        # Convert to our format
        segments = []
        for seg in result.segments:
            segments.append({
                'start': seg.start + start_time,
                'end': seg.end + start_time,
                'text': seg.text.strip()
            })
        
        log(f"OpenAI transcription: {len(segments)} segments")
        return segments
        
    except Exception as e:
        log(f"OpenAI API error: {e}")
        return None


def _transcribe_openai_chunks(audio_path: str, start_time: float, chunk_duration: int) -> Optional[List[dict]]:
    """Split large audio and transcribe chunk by chunk with OpenAI API."""
    import subprocess
    
    try:
        from openai import OpenAI
        client = OpenAI()
    except Exception as e:
        log(f"OpenAI client init error: {e}")
        return None
    
    work_dir = os.path.dirname(audio_path)
    base_name = os.path.splitext(os.path.basename(audio_path))[0]
    chunk_pattern = os.path.join(work_dir, f"{base_name}_chunk_%03d.wav")
    
    # Split into chunks using ffmpeg
    log(f"Splitting audio into {chunk_duration}s chunks...")
    try:
        subprocess.run([
            'ffmpeg', '-hide_banner', '-loglevel', 'error',
            '-i', audio_path,
            '-f', 'segment', '-segment_time', str(chunk_duration),
            '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le',
            '-y', chunk_pattern
        ], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        log(f"Error splitting audio: {e}")
        return None
    
    # Find and transcribe chunks
    chunks = sorted(Path(work_dir).glob(f"{base_name}_chunk_*.wav"))
    if not chunks:
        log("No chunks generated")
        return None
    
    log(f"Transcribing {len(chunks)} chunks...")
    all_segments = []
    
    for i, chunk in enumerate(chunks):
        chunk_start = start_time + (i * chunk_duration)
        log(f"  Chunk {i+1}/{len(chunks)}...")
        
        try:
            with open(chunk, "rb") as f:
                result = client.audio.transcriptions.create(
                    model="whisper-1",
                    file=f,
                    response_format="verbose_json",
                    timestamp_granularities=["segment"]
                )
            
            # Adjust timestamps
            for seg in result.segments:
                all_segments.append({
                    'start': seg.start + chunk_start,
                    'end': seg.end + chunk_start,
                    'text': seg.text.strip()
                })
            
            # Clean up chunk
            os.remove(chunk)
            
        except Exception as e:
            log(f"Error transcribing chunk {i+1}: {e}")
            continue
    
    log(f"OpenAI chunked transcription: {len(all_segments)} segments")
    return all_segments


def transcribe_with_whisper(audio_path: str, model_path: str, start_time: float = 0) -> Optional[List[dict]]:
    """Transcribe using local whisper-cli. Returns segments."""
    log(f"Transcribing with local whisper...")
    
    # Expand model path
    model_path = os.path.expanduser(model_path)
    
    if not os.path.exists(model_path):
        log(f"Model not found: {model_path}")
        return None
    
    # Create temp output
    with tempfile.NamedTemporaryFile(mode='w', suffix='.srt', delete=False) as f:
        temp_srt = f.name
    
    try:
        subprocess.run([
            'whisper-cli',
            '--model', model_path,
            '--file', audio_path,
            '--output-srt',
            '--output-file', temp_srt.replace('.srt', ''),
            '--language', 'zh'
        ], check=True, capture_output=True)
        
        # Parse SRT
        segments = []
        with open(temp_srt, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Parse SRT entries
        entries = re.split(r'\n\n+', content.strip())
        for entry in entries:
            lines = entry.strip().split('\n')
            if len(lines) >= 3:
                # Parse time line
                time_match = re.match(r'(\d+):(\d+):(\d+),(\d+)\s*-->\s*(\d+):(\d+):(\d+),(\d+)', lines[1])
                if time_match:
                    start_h, start_m, start_s, start_ms = map(int, time_match.groups()[:4])
                    end_h, end_m, end_s, end_ms = map(int, time_match.groups()[4:])
                    
                    start = start_h * 3600 + start_m * 60 + start_s + start_ms / 1000 + start_time
                    end = end_h * 3600 + end_m * 60 + end_s + end_ms / 1000 + start_time
                    text = '\n'.join(lines[2:])
                    
                    segments.append({
                        'start': start,
                        'end': end,
                        'text': text.strip()
                    })
        
        log(f"Local whisper transcription: {len(segments)} segments")
        return segments
        
    except Exception as e:
        log(f"Local whisper error: {e}")
        return None
    finally:
        if os.path.exists(temp_srt):
            os.remove(temp_srt)


def transcribe_segment(audio_path: str, segment_start: float, segment_end: float, 
                       work_dir: str) -> List[dict]:
    """Transcribe a single segment using dual-engine."""
    # Extract segment audio
    segment_wav = os.path.join(work_dir, f"segment_{int(segment_start)}.wav")
    
    try:
        subprocess.run([
            'ffmpeg', '-hide_banner', '-loglevel', 'error',
            '-i', audio_path,
            '-ss', str(segment_start),
            '-to', str(segment_end),
            '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le',
            '-y', segment_wav
        ], check=True, capture_output=True)
        
        if not os.path.exists(segment_wav):
            log(f"Error: Segment audio not created")
            return []
        
        # Get file size
        file_size = os.path.getsize(segment_wav)
        log(f"Segment size: {file_size // (1024*1024)}MB")
        
        segments = None

        # 默认本地 Whisper（无需 key）；仅当用户显式选 openai 且配了 key 才走 API
        if TRANSCRIBE_ENGINE == "openai" and OPENAI_API_KEY:
            segments = transcribe_with_openai(segment_wav, start_time=segment_start)
            if not segments:   # API 失败/空结果 → 自愈回本地（见 dual-engine 自愈教训）
                log("OpenAI returned empty, falling back to local whisper...")
                segments = transcribe_with_whisper(segment_wav, WHISPER_MODEL, start_time=segment_start)
        else:
            segments = transcribe_with_whisper(segment_wav, WHISPER_MODEL, start_time=segment_start)

        return segments or []
        
    except Exception as e:
        log(f"Error transcribing segment: {e}")
        return []
    finally:
        if os.path.exists(segment_wav):
            os.remove(segment_wav)


def detect_repeats(segments: List[dict]) -> List[dict]:
    """Detect and mark hallucination repeats in segments."""
    if not segments:
        return segments
    
    log("Detecting repeats...")
    
    # Count consecutive repeats
    filtered = []
    repeat_count = 1
    last_text = ""
    
    for seg in segments:
        text = seg['text']
        
        # Check if this is a repeat
        if text == last_text:
            repeat_count += 1
        else:
            repeat_count = 1
            last_text = text
        
        if repeat_count <= MAX_REPEAT_COUNT:
            filtered.append(seg)
        elif repeat_count == MAX_REPEAT_COUNT + 1:
            # First time we see excess repeats, add marker
            log(f"Detected repeat hallucination at {seg['start']:.1f}s: '{text[:30]}...'")
            filtered.append({
                'start': seg['start'],
                'end': seg['end'],
                'text': '[检测到重复内容，已跳过]'
            })
    
    log(f"Filtered {len(segments) - len(filtered)} repeat segments")
    return filtered


def format_time(seconds: float) -> str:
    """Format seconds to SRT time format."""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int((seconds % 1) * 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def write_srt(segments: List[dict], output_path: str, first_valid_start: float = 0):
    """Write segments to SRT file with time offset."""
    log(f"Writing SRT: {output_path}")
    
    with open(output_path, 'w', encoding='utf-8') as f:
        # Write header marker
        f.write("1\n")
        f.write("00:00:00,000 --> 00:00:03,000\n")
        if first_valid_start > 0:
            marker_time = format_time(first_valid_start)
            f.write(f"[直播实际开始于原始视频 {marker_time}]\n")
        else:
            f.write("[直播开始]\n")
        f.write("\n")
        
        # Write segments
        idx = 2
        for seg in segments:
            start = seg['start'] - first_valid_start
            end = seg['end'] - first_valid_start
            
            if start < 0:
                start = 0
            if end < 0:
                end = 0
            
            f.write(f"{idx}\n")
            f.write(f"{format_time(start)} --> {format_time(end)}\n")
            f.write(f"{seg['text']}\n")
            f.write("\n")
            
            idx += 1
    
    log(f"SRT written: {idx-1} entries")


def transcribe_video(video_path: str, output_srt: str) -> bool:
    """Main transcription function."""
    log(f"Starting transcription: {video_path}")
    
    # Create temp directory
    with tempfile.TemporaryDirectory() as work_dir:
        # Step 1: Extract full audio
        audio_path = os.path.join(work_dir, "audio.wav")
        if not extract_audio(video_path, audio_path):
            log("Failed to extract audio")
            return False
        
        # Step 2: Detect silence and get valid segments
        valid_segments = detect_silence(audio_path)
        
        if not valid_segments:
            log("No valid segments found")
            return False
        
        first_valid_start = valid_segments[0][0]
        
        # Step 3: Transcribe each segment
        all_segments = []
        for seg_start, seg_end in valid_segments:
            log(f"Transcribing segment: {seg_start:.1f}s - {seg_end:.1f}s")
            segments = transcribe_segment(audio_path, seg_start, seg_end, work_dir)
            all_segments.extend(segments)
        
        if not all_segments:
            log("No transcription produced")
            return False
        
        # Step 4: Detect and filter repeats
        filtered_segments = detect_repeats(all_segments)
        
        # Step 5: Write SRT
        write_srt(filtered_segments, output_srt, first_valid_start)
        
        log(f"Transcription complete: {len(filtered_segments)} segments")
        return True


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 transcribe_enhanced.py <video_path> <output_srt>")
        sys.exit(1)
    
    video_path = sys.argv[1]
    output_srt = sys.argv[2]
    
    success = transcribe_video(video_path, output_srt)
    sys.exit(0 if success else 1)
