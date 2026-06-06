"""
pipeline.py â€” Full Auto Pipeline orchestrator
URL Douyin â†’ Download â†’ Demucs â†’ Whisper â†’ Translate â†’ GeminiTTS â†’ Render â†’ Upload
"""
import os, json, time, shutil, traceback, uuid, re
from modules.helpers import (
    load_config, create_project, update_project_info,
    JOBS, pipeline_log, run_cmd, get_media_duration, BASE_DIR,
    bind_job_project_log, sync_gpu_heavy_limit_from_config,
    sync_download_limit_from_config, download_slot
)
from modules.url_extractor import extract_douyin_url
from modules.downloader import download_video
from modules.separator import separate
from modules.transcriber import transcribe
from modules.translator import translate_srt
from modules.tts_engine import generate_tts_audio
from modules.renderer import render_video, render_video_tiktok_vertical
from modules.metadata_gen import generate_metadata, create_thumbnail
from modules.uploader import upload_video
from modules.tiktok_uploader import split_video_for_tiktok, build_tiktok_caption, upload_tiktok_videos
from modules.tiktok_open_api import tiktok_direct_post_video
from modules.facebook_reels import facebook_upload_reel, facebook_upload_page_video
import queue
import threading

# HÃ ng chá» global cho táº¥t cáº£ pipeline (chá»‰ cháº¡y 1 pipeline táº¡i 1 thá»i Ä‘iá»ƒm)
_PIPELINE_QUEUE = queue.Queue()

def _global_pipeline_worker():
    while True:
        task = _PIPELINE_QUEUE.get()
        if task is None:
            break
        func, args, kwargs = task
        try:
            func(*args, **kwargs)
        except Exception as e:
            print(f"Global worker error: {e}")
        _PIPELINE_QUEUE.task_done()

_worker_thread = threading.Thread(target=_global_pipeline_worker, daemon=True)
_worker_thread.start()

# YouTube deferred upload queue (quota-aware)
_YT_UPLOAD_QUEUE_FILE = BASE_DIR / 'youtube_upload_queue.json'
_YT_UPLOAD_FAILED_FILE = BASE_DIR / 'youtube_upload_queue_failed.json'
_YT_UPLOAD_LOCK = threading.RLock()
_YT_UPLOAD_QUEUE = []
_YT_QUOTA_BLOCK_UNTIL = 0.0
_YT_WORKER_STATE = {
    'running': False,
    'last_run_at': None,
    'last_error': '',
    'last_action': '',
}


def _now_ts():
    return time.time()


def _now_text():
    return time.strftime('%Y-%m-%d %H:%M:%S')


def _read_json(path, default):
    try:
        if os.path.exists(path):
            with open(path, 'r', encoding='utf-8') as f:
                return json.load(f)
    except Exception:
        pass
    return default


def _write_json(path, data):
    tmp = str(path) + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def _save_youtube_upload_queue():
    with _YT_UPLOAD_LOCK:
        _write_json(_YT_UPLOAD_QUEUE_FILE, _YT_UPLOAD_QUEUE)


def _load_youtube_upload_queue():
    global _YT_UPLOAD_QUEUE
    data = _read_json(_YT_UPLOAD_QUEUE_FILE, [])
    if not isinstance(data, list):
        data = []
    normalized = []
    for item in data:
        if not isinstance(item, dict):
            continue
        if not item.get('project_dir') or not item.get('final_video'):
            continue
        item.setdefault('id', str(uuid.uuid4())[:8])
        item.setdefault('status', 'pending')
        item.setdefault('attempts', 0)
        item.setdefault('next_try_at', 0)
        item.setdefault('created_at', _now_text())
        item.setdefault('updated_at', _now_text())
        normalized.append(item)
    with _YT_UPLOAD_LOCK:
        _YT_UPLOAD_QUEUE = normalized


def _youtube_upload_queue_count():
    with _YT_UPLOAD_LOCK:
        return len(_YT_UPLOAD_QUEUE)


def _youtube_upload_queue_has_items():
    return _youtube_upload_queue_count() > 0


def _youtube_error_text(err) -> str:
    parts = [str(err or '')]
    content = getattr(err, 'content', None)
    if content:
        try:
            if isinstance(content, bytes):
                parts.append(content.decode('utf-8', errors='replace'))
            else:
                parts.append(str(content))
        except Exception:
            pass
    return '\n'.join(parts)


def _is_youtube_quota_error(err) -> bool:
    t = _youtube_error_text(err).lower()
    quota_markers = (
        'uploadlimitexceeded',
        'quotaexceeded',
        'youtube.quota',
        'exceeded your quota',
        'quota exceeded',
        'daily limit exceeded',
        'userrate',
        'ratelimitexceeded',
        'quota',
    )
    return any(m in t for m in quota_markers)


def get_youtube_upload_queue_status():
    with _YT_UPLOAD_LOCK:
        items = list(_YT_UPLOAD_QUEUE)
    now = _now_ts()
    return {
        'count': len(items),
        'quota_block_until': _YT_QUOTA_BLOCK_UNTIL,
        'quota_block_seconds': max(0, int(_YT_QUOTA_BLOCK_UNTIL - now)),
        'worker': dict(_YT_WORKER_STATE),
        'items': items,
    }


def _append_youtube_upload_failed(task, error_text):
    try:
        rows = _read_json(_YT_UPLOAD_FAILED_FILE, [])
        if not isinstance(rows, list):
            rows = []
        rows.append({
            'task': task,
            'error': str(error_text or ''),
            'failed_at': _now_text(),
        })
        rows = rows[-200:]
        _write_json(_YT_UPLOAD_FAILED_FILE, rows)
    except Exception:
        pass


def enqueue_youtube_upload_task(project_dir, final_video, meta, thumbnail_path, cfg, reason='deferred', error_text=''):
    cfg = cfg or {}
    series_context = None
    if isinstance(cfg.get('series_context'), dict):
        series_context = dict(cfg.get('series_context') or {})
    elif isinstance((meta or {}).get('series_context'), dict):
        series_context = dict((meta or {}).get('series_context') or {})

    task = {
        'id': str(uuid.uuid4())[:8],
        'project_dir': str(project_dir),
        'final_video': str(final_video),
        'thumbnail_path': str(thumbnail_path or ''),
        'title': str((meta or {}).get('title') or 'Untitled')[:100],
        'description': str((meta or {}).get('description') or '')[:5000],
        'tags': list((meta or {}).get('tags') or []),
        'privacy': str((cfg or {}).get('privacy') or 'public'),
        'language': str((cfg or {}).get('target_lang') or 'vi'),
        'category_id': '22',
        'reason': str(reason or 'deferred'),
        'last_error': str(error_text or ''),
        'status': 'pending',
        'attempts': 0,
        'next_try_at': 0,
        'created_at': _now_text(),
        'updated_at': _now_text(),
    }
    if series_context:
        task['cfg'] = {'series_context': series_context}

    with _YT_UPLOAD_LOCK:
        for old in _YT_UPLOAD_QUEUE:
            if (
                str(old.get('project_dir') or '') == task['project_dir']
                and str(old.get('final_video') or '') == task['final_video']
            ):
                old['reason'] = task['reason']
                if series_context:
                    old['cfg'] = {'series_context': series_context}
                if task['last_error']:
                    old['last_error'] = task['last_error']
                old['updated_at'] = _now_text()
                _save_youtube_upload_queue()
                return {'queued': True, 'id': old.get('id'), 'dedup': True}
        _YT_UPLOAD_QUEUE.append(task)
        _save_youtube_upload_queue()

    try:
        update_project_info(project_dir, {
            'youtube_pending': True,
            'youtube_deferred_reason': task['reason'],
            'youtube_pending_at': _now_text(),
        })
    except Exception:
        pass
    return {'queued': True, 'id': task['id'], 'dedup': False}


def _read_project_series_context(project_dir):
    """Fallback for old upload queue rows created before cfg.series_context was stored."""
    if not project_dir:
        return None
    for name in ('info.json', 'metadata.json'):
        try:
            p = os.path.join(str(project_dir), name)
            if not os.path.exists(p):
                continue
            with open(p, 'r', encoding='utf-8') as f:
                data = json.load(f)
            ctx = data.get('series_context')
            if isinstance(ctx, dict) and ctx:
                return ctx
            meta_ctx = (data.get('metadata') or {}).get('series_context') if isinstance(data.get('metadata'), dict) else None
            if isinstance(meta_ctx, dict) and meta_ctx:
                return meta_ctx
        except Exception:
            continue
    return None


def _youtube_task_playlist_name(task):
    cfg = task.get('cfg') if isinstance(task, dict) else {}
    series_ctx = cfg.get('series_context') if isinstance(cfg, dict) else None
    if not isinstance(series_ctx, dict) or not series_ctx:
        series_ctx = _read_project_series_context((task or {}).get('project_dir'))
    if not isinstance(series_ctx, dict):
        return None
    return series_ctx.get('series_name_vi') or series_ctx.get('series_name') or None


def _pick_next_youtube_upload_task(now_ts):
    with _YT_UPLOAD_LOCK:
        for idx, item in enumerate(_YT_UPLOAD_QUEUE):
            if item.get('status') == 'pending' and float(item.get('next_try_at') or 0) <= now_ts:
                item['status'] = 'uploading'
                item['updated_at'] = _now_text()
                _save_youtube_upload_queue()
                return idx, dict(item)
    return None, None


def _update_queue_item(index, new_item):
    with _YT_UPLOAD_LOCK:
        if index is None or index < 0 or index >= len(_YT_UPLOAD_QUEUE):
            return
        _YT_UPLOAD_QUEUE[index] = new_item
        _save_youtube_upload_queue()


def _remove_queue_item(index):
    with _YT_UPLOAD_LOCK:
        if index is None or index < 0 or index >= len(_YT_UPLOAD_QUEUE):
            return None
        task = _YT_UPLOAD_QUEUE.pop(index)
        _save_youtube_upload_queue()
        return task


def _mark_project_uploaded_from_queue(project_dir, upload_result):
    try:
        info_path = os.path.join(project_dir, 'info.json')
        info = {}
        if os.path.exists(info_path):
            with open(info_path, 'r', encoding='utf-8') as f:
                info = json.load(f)
        steps = info.get('steps_completed', []) if isinstance(info.get('steps_completed'), list) else []
        if 'upload' not in steps:
            steps.append('upload')
        update_project_info(project_dir, {
            'youtube': upload_result,
            'youtube_pending': False,
            'youtube_deferred_reason': '',
            'youtube_uploaded_via_queue': True,
            'steps_completed': steps,
        })
    except Exception:
        pass


def _youtube_upload_worker_loop():
    global _YT_QUOTA_BLOCK_UNTIL
    while True:
        time.sleep(15)
        _YT_WORKER_STATE['running'] = True
        _YT_WORKER_STATE['last_run_at'] = _now_text()
        try:
            now_ts = _now_ts()
            if now_ts < float(_YT_QUOTA_BLOCK_UNTIL or 0):
                _YT_WORKER_STATE['last_action'] = 'quota_backoff'
                continue

            cfg = load_config()
            if not bool(cfg.get('auto_upload', False)):
                _YT_WORKER_STATE['last_action'] = 'auto_upload_off'
                continue

            idx, task = _pick_next_youtube_upload_task(now_ts)
            if task is None:
                _YT_WORKER_STATE['last_action'] = 'idle'
                continue
            from modules.uploader import get_next_upload_token

            token_path, channel_key, _ = get_next_upload_token(log_cb=lambda *_: None)
            if not token_path:
                raise RuntimeError('No enabled YouTube channels')

            playlist_name = _youtube_task_playlist_name(task)

            out = upload_video(
                task.get('final_video'),
                title=task.get('title') or 'Untitled',
                description=task.get('description') or '',
                thumbnail_path=task.get('thumbnail_path') or None,
                tags=task.get('tags') or [],
                category_id=str(task.get('category_id') or '22'),
                privacy=str(task.get('privacy') or cfg.get('privacy', 'public')),
                language=str(task.get('language') or cfg.get('target_lang', 'vi')),
                log_cb=lambda *_: None,
                token_file=token_path,
                playlist_name=playlist_name
            )
            if isinstance(out, dict) and channel_key and not out.get('channel_key'):
                out['channel_key'] = channel_key
            _remove_queue_item(idx)
            _mark_project_uploaded_from_queue(task.get('project_dir'), out)
            _YT_WORKER_STATE['last_action'] = f"uploaded:{task.get('id')}"
            _YT_WORKER_STATE['last_error'] = ''
        except Exception as ex:
            err_text = _youtube_error_text(ex)
            _YT_WORKER_STATE['last_error'] = err_text[:300]
            _YT_WORKER_STATE['last_action'] = 'retry_later'

            if task is None:
                continue

            cfg = load_config()
            quota_wait = int(cfg.get('youtube_quota_retry_sec', 1800) or 1800)
            retry_wait = int(cfg.get('youtube_upload_retry_sec', 300) or 300)
            max_attempts = int(cfg.get('youtube_upload_queue_max_attempts', 20) or 20)
            is_quota = _is_youtube_quota_error(ex)

            no_enabled_channels = 'No enabled YouTube channels' in err_text

            if no_enabled_channels:
                # No usable upload token is available right now. Do not burn attempts
                # or move queue items to failed; just wait for token/quota recovery.
                next_try_offset = max(300, retry_wait)
            elif is_quota:
                from modules.uploader import mark_token_exhausted, get_enabled_tokens
                # Mark this specific token as exhausted
                if token_path:
                    mark_token_exhausted(token_path, log_cb=lambda *_: None)
                
                # Check if we still have surviving tokens
                surviving_tokens = get_enabled_tokens()
                if len(surviving_tokens) == 0:
                    # All tokens are dead, we must globally block
                    _YT_QUOTA_BLOCK_UNTIL = _now_ts() + max(60, quota_wait)
                    next_try_offset = max(60, quota_wait)
                else:
                    # We have other tokens, don't block globally. Retry very soon.
                    next_try_offset = 10
            else:
                next_try_offset = max(30, retry_wait)

            with _YT_UPLOAD_LOCK:
                if idx is not None and 0 <= idx < len(_YT_UPLOAD_QUEUE):
                    row = _YT_UPLOAD_QUEUE[idx]
                    row['status'] = 'pending'
                    if not no_enabled_channels:
                        row['attempts'] = int(row.get('attempts') or 0) + 1
                    row['last_error'] = err_text[:2000]
                    row['updated_at'] = _now_text()
                    row['next_try_at'] = _now_ts() + next_try_offset

                    if row['attempts'] >= max_attempts and not is_quota and not no_enabled_channels:
                        failed_task = dict(row)
                        _YT_UPLOAD_QUEUE.pop(idx)
                        _save_youtube_upload_queue()
                        _append_youtube_upload_failed(failed_task, err_text)
                        try:
                            update_project_info(failed_task.get('project_dir'), {
                                'youtube_pending': False,
                                'youtube_deferred_reason': '',
                                'youtube_upload_queue_failed': True,
                                'youtube_upload_queue_failed_error': err_text[:300],
                            })
                        except Exception:
                            pass
                    else:
                        _save_youtube_upload_queue()
        finally:
            _YT_WORKER_STATE['running'] = False


_load_youtube_upload_queue()
_yt_upload_worker_thread = threading.Thread(target=_youtube_upload_worker_loop, daemon=True)
_yt_upload_worker_thread.start()


def _ensure_tiktok_vertical_video(project_dir, final_video, cfg, log):
    """Create (or reuse) a 9:16 TikTok render from final_video."""
    tiktok_video = os.path.join(project_dir, 'final_video_tiktok.mp4')
    if os.path.exists(tiktok_video):
        return tiktok_video
    if not os.path.exists(final_video):
        return final_video
    try:
        render_video_tiktok_vertical(
            input_video_path=final_video,
            output_path=tiktok_video,
            width=int(cfg.get('tiktok_vertical_width', 1080) or 1080),
            height=int(cfg.get('tiktok_vertical_height', 1920) or 1920),
            blur_sigma=int(cfg.get('tiktok_vertical_blur_sigma', 36) or 36),
            log_cb=log
        )
        return tiktok_video if os.path.exists(tiktok_video) else final_video
    except Exception as ex:
        log(f'  ⚠️ TikTok vertical render failed, fallback 16:9: {ex}')
        return final_video


def _auto_upload_tiktok(project_dir, final_video, meta, cfg, log, tiktok_video=None):
    """Best-effort TikTok upload. Never raises to break main pipeline."""
    try:
        if not cfg.get('auto_upload_tiktok', False):
            return None
        log('ðŸ“± Step 11: Uploading to TikTok...')
        upload_source = tiktok_video if (tiktok_video and os.path.exists(tiktok_video)) else final_video
        if upload_source != final_video:
            log(f'  TikTok source: vertical render ({os.path.basename(upload_source)})')
        else:
            log(f'  TikTok source: default render ({os.path.basename(upload_source)})')
        max_minutes = max(1, int(cfg.get('tiktok_max_minutes', 10) or 10))
        auto_split = bool(cfg.get('tiktok_auto_split', True))
        cap_limit = int(cfg.get('tiktok_caption_max_chars', 2200) or 2200)
        headless = bool(cfg.get('tiktok_headless', False))
        timeout_sec = int(cfg.get('tiktok_upload_timeout_sec', 240) or 240)
        provider = str(cfg.get('tiktok_upload_provider') or 'official_api').strip().lower()
        if provider not in ('official_api', 'playwright'):
            provider = 'official_api'

        if auto_split:
            parts = split_video_for_tiktok(final_video, project_dir, max_minutes=max_minutes, log_cb=log)
        else:
            parts = [{
                'path': final_video,
                'part_index': 1,
                'total_parts': 1,
                'duration_sec': float(get_media_duration(final_video) or 0)
            }]

        title = (meta or {}).get('title', 'Untitled')
        desc = (meta or {}).get('description', '')
        tags = (meta or {}).get('tags', []) or []
        captions = []
        for part in parts:
            captions.append(build_tiktok_caption(
                title=title,
                description=desc,
                tags=tags,
                part_index=part.get('part_index', 1),
                total_parts=part.get('total_parts', 1),
                max_chars=cap_limit
            ))

        results = []
        log(f'  TikTok provider: {provider}')
        if provider == 'official_api':
            total = len(parts)
            for i, part in enumerate(parts):
                part_label = f"{part.get('part_index', i+1)}/{part.get('total_parts', total)}"
                try:
                    log(f'[TikTok] Upload part {part_label} start: {os.path.basename(part.get("path", ""))}')
                    out = tiktok_direct_post_video(
                        cfg=cfg,
                        video_path=part.get('path'),
                        caption=captions[i] if i < len(captions) else '',
                        log_cb=log,
                    )
                    status = str(out.get('status') or '').upper()
                    results.append({
                        'ok': status in ('PUBLISH_COMPLETE', 'SEND_TO_USER_INBOX'),
                        'part': part_label,
                        'file': part.get('path'),
                        'mode': out.get('mode'),
                        'publish_id': out.get('publish_id'),
                        'status': status,
                        'fail_reason': out.get('fail_reason'),
                    })
                    log(
                        f"[TikTok] Upload part {part_label} done"
                        f" | mode={out.get('mode') or '-'}"
                        f" | status={status or '-'}"
                        f" | publish_id={out.get('publish_id') or '-'}"
                    )
                except Exception as ex_part:
                    results.append({
                        'ok': False,
                        'part': part_label,
                        'file': part.get('path'),
                        'error': str(ex_part),
                    })
                    log(f'[TikTok] Upload part {part_label} failed: {ex_part}')
        else:
            results = upload_tiktok_videos(
                parts,
                captions,
                log_cb=log,
                headless=headless,
                upload_timeout_sec=timeout_sec
            )
        ok_count = sum(1 for r in results if r.get('ok'))
        log(f'  TikTok summary: {ok_count}/{len(parts)} part(s) success')
        if ok_count < len(parts):
            for r in results:
                if not r.get('ok'):
                    log(f"  TikTok failed part {r.get('part','-')}: {r.get('error') or r.get('fail_reason') or r.get('status') or 'unknown'}")
        return {
            'provider': provider,
            'source_video': upload_source,
            'part_count': len(parts),
            'ok_count': ok_count,
            'max_minutes': max_minutes,
            'auto_split': auto_split,
            'results': results,
            'uploaded_at': time.strftime('%Y-%m-%d %H:%M:%S'),
        }
    except Exception as ex:
        log(f'âš ï¸ TikTok auto-upload failed: {ex}')
        return {'error': str(ex)}


def _facebook_caption(meta, part_index=1, total_parts=1, max_chars=255):
    title = (meta or {}).get('title', 'Untitled')
    desc = (meta or {}).get('description', '')
    tags = (meta or {}).get('tags', []) or []
    cap = build_tiktok_caption(
        title=title,
        description=desc,
        tags=tags,
        part_index=part_index,
        total_parts=total_parts,
        max_chars=max_chars
    )
    if int(total_parts or 1) <= 1:
        cap = re.sub(r'^\s*Tap\s+\d+/\d+\s*\|\s*', '', str(cap or ''), flags=re.IGNORECASE).strip()
    return cap


def _facebook_status_text(status_obj):
    if not isinstance(status_obj, dict):
        return ''
    pub_st = (status_obj.get('publishing_phase') or {}).get('status') if isinstance(status_obj.get('publishing_phase'), dict) else ''
    proc_st = (status_obj.get('processing_phase') or {}).get('status') if isinstance(status_obj.get('processing_phase'), dict) else ''
    video_st = status_obj.get('video_status') or ''
    return '/'.join([str(s) for s in [pub_st, proc_st, video_st] if s])


def _auto_upload_facebook_reels(project_dir, final_video, meta, cfg, log):
    """Best-effort Facebook upload. Auto mode: short video -> Reels, long video -> Page Video."""
    try:
        if not cfg.get('auto_upload_facebook_reels', False):
            return None

        log('ðŸ“˜ Step 12: Uploading to Facebook...')
        upload_mode = str(cfg.get('facebook_upload_mode') or 'auto').strip().lower()
        if upload_mode not in ('auto', 'reels', 'video'):
            upload_mode = 'auto'

        duration_sec = float(get_media_duration(final_video) or 0)
        short_threshold = int(cfg.get('facebook_reels_short_threshold_sec') or 90)
        short_threshold = max(15, min(short_threshold, 3600))
        resolved_mode = upload_mode
        if upload_mode == 'auto':
            resolved_mode = 'reels' if duration_sec <= short_threshold else 'video'

        log(f'  Facebook mode: {resolved_mode} (duration={duration_sec:.1f}s, short<= {short_threshold}s)')

        title = (meta or {}).get('title', 'Untitled')
        if resolved_mode == 'video':
            cap_limit = int(cfg.get('facebook_caption_max_chars') or cfg.get('tiktok_caption_max_chars') or 2200)
            cap_limit = max(60, min(cap_limit, 2200))
            caption = _facebook_caption(meta, 1, 1, cap_limit)
            try:
                out = facebook_upload_page_video(
                    video_path=final_video,
                    caption=caption,
                    cfg=cfg,
                    title=title,
                    log_cb=log
                )
                result = {
                    'ok': bool(out.get('ok')),
                    'part': '1/1',
                    'file': final_video,
                    'video_id': out.get('video_id'),
                    'post_id': out.get('post_id'),
                    'timeout': bool(out.get('timeout')),
                    'status': _facebook_status_text(out.get('status') or {}),
                    'raw_status': out.get('status') or {},
                }
            except Exception as part_ex:
                result = {'ok': False, 'part': '1/1', 'file': final_video, 'error': str(part_ex)}
                log(f'  âš ï¸ Facebook video upload failed: {part_ex}')
            return {
                'mode': 'video',
                'requested_mode': upload_mode,
                'short_threshold_sec': short_threshold,
                'duration_sec': duration_sec,
                'part_count': 1,
                'ok_count': 1 if result.get('ok') else 0,
                'auto_split': False,
                'results': [result],
                'uploaded_at': time.strftime('%Y-%m-%d %H:%M:%S'),
            }

        max_minutes = max(1, int(cfg.get('facebook_reels_max_minutes', cfg.get('tiktok_max_minutes', 10)) or 10))
        auto_split = bool(cfg.get('facebook_reels_auto_split', cfg.get('tiktok_auto_split', True)))
        cap_limit = int(cfg.get('tiktok_caption_max_chars', 2200) or 2200)
        cap_limit = max(60, min(cap_limit, 255))
        upload_source = final_video

        if auto_split:
            parts = split_video_for_tiktok(upload_source, project_dir, max_minutes=max_minutes, log_cb=log)
        else:
            parts = [{
                'path': upload_source,
                'part_index': 1,
                'total_parts': 1,
                'duration_sec': float(get_media_duration(upload_source) or 0)
            }]

        captions = []
        for part in parts:
            captions.append(_facebook_caption(
                meta,
                part_index=part.get('part_index', 1),
                total_parts=part.get('total_parts', 1),
                max_chars=cap_limit
            ))

        results = []
        for i, part in enumerate(parts):
            part_label = f"{part.get('part_index', i+1)}/{part.get('total_parts', len(parts))}"
            try:
                log(f'  ðŸ“¤ Facebook part {part_label}: {os.path.basename(part.get("path", ""))}')
                out = facebook_upload_reel(
                    video_path=part.get('path'),
                    caption=captions[i] if i < len(captions) else '',
                    cfg=cfg,
                    title=title,
                    log_cb=log
                )
                status_obj = out.get('status') or {}
                status_text = _facebook_status_text(status_obj)
                results.append({
                    'ok': bool(out.get('ok')),
                    'part': part_label,
                    'file': part.get('path'),
                    'video_id': out.get('video_id'),
                    'timeout': bool(out.get('timeout')),
                    'status': status_text,
                    'raw_status': status_obj,
                })
            except Exception as part_ex:
                results.append({
                    'ok': False,
                    'part': part_label,
                    'file': part.get('path'),
                    'error': str(part_ex),
                })
                log(f'  âš ï¸ Facebook part {part_label} failed: {part_ex}')

        ok_count = sum(1 for r in results if r.get('ok'))
        return {
            'mode': 'reels',
            'requested_mode': upload_mode,
            'short_threshold_sec': short_threshold,
            'duration_sec': duration_sec,
            'part_count': len(parts),
            'ok_count': ok_count,
            'max_minutes': max_minutes,
            'auto_split': auto_split,
            'results': results,
            'uploaded_at': time.strftime('%Y-%m-%d %H:%M:%S'),
        }
    except Exception as ex:
        log(f'âš ï¸ Facebook Reels auto-upload failed: {ex}')
        return {'error': str(ex)}




def _series_context_from_cfg(cfg):
    """Extract per-URL series metadata injected by a grouped queue."""
    if not isinstance(cfg, dict):
        return {}
    ctx = cfg.get('series_context') if isinstance(cfg.get('series_context'), dict) else {}
    out = dict(ctx or {})
    direct_map = {
        'series_name_vi': 'youtube_series_name',
        'series_folder': 'youtube_series_folder',
        'episode_no': 'youtube_episode_no',
        'episode_min': 'youtube_episode_min',
        'episode_max': 'youtube_episode_max',
    }
    for dst, src in direct_map.items():
        val = cfg.get(src)
        if val is not None and str(val).strip() != '':
            out[dst] = val
    return {k: v for k, v in out.items() if v is not None and str(v).strip() != ''}


def upload_project_outputs(project_dir, cfg_overrides=None, log_cb=print):
    cfg = load_config()
    if cfg_overrides:
        cfg.update(cfg_overrides)
    sync_gpu_heavy_limit_from_config(cfg)
    sync_download_limit_from_config(cfg)

    info_path = os.path.join(project_dir, 'info.json')
    if not os.path.exists(info_path):
        raise FileNotFoundError(f'info.json missing in project: {project_dir}')
    with open(info_path, 'r', encoding='utf-8') as f:
        info = json.load(f)

    final_video = info.get('final_video') or os.path.join(project_dir, 'final_video.mp4')
    if not os.path.exists(final_video):
        raise FileNotFoundError(f'final_video missing: {final_video}')
    meta = info.get('metadata') or {}
    thumb_path = info.get('thumbnail') or os.path.join(project_dir, 'thumbnail.jpg')
    if not os.path.exists(thumb_path):
        thumb_path = ''
    final_video_tiktok = info.get('final_video_tiktok')
    if final_video_tiktok and not os.path.exists(final_video_tiktok):
        final_video_tiktok = None

    upload_result = None
    if cfg.get('auto_upload', False):
        log_cb('📤 Upload stage: YouTube...')
        if _youtube_upload_queue_has_items():
            q = enqueue_youtube_upload_task(
                project_dir=project_dir,
                final_video=final_video,
                meta=meta,
                thumbnail_path=thumb_path,
                cfg=cfg,
                reason='pending_queue_not_empty',
                error_text='deferred because pending upload queue has items',
            )
            upload_result = {
                'queued': True,
                'queue_id': q.get('id'),
                'reason': 'pending_queue_not_empty',
            }
            log_cb(f"  ⏸️ Deferred YouTube upload (queue busy): task={q.get('id')}")
        else:
            from modules.uploader import get_next_upload_token
            token_path, channel_key, _ = get_next_upload_token(log_cb=log_cb)
            if not token_path:
                log_cb('⚠️ No enabled YouTube channels. Deferring to Queue.')
                q = enqueue_youtube_upload_task(
                    project_dir=project_dir,
                    final_video=final_video,
                    meta=meta,
                    thumbnail_path=thumb_path,
                    cfg=cfg,
                    reason='no_enabled_channels',
                    error_text='deferred because no enabled channels (or all exhausted)',
                )
                upload_result = {
                    'queued': True,
                    'queue_id': q.get('id'),
                    'reason': 'no_enabled_channels',
                }
            else:
                try:
                    series_ctx = info.get('series_context') or cfg.get('series_context')
                    playlist_name = None
                    if isinstance(series_ctx, dict):
                        playlist_name = series_ctx.get('series_name_vi') or series_ctx.get('series_name')
                    upload_result = upload_video(
                        final_video,
                        title=meta.get('title', 'Untitled'),
                        description=meta.get('description', ''),
                        thumbnail_path=thumb_path if thumb_path else None,
                        tags=meta.get('tags', []),
                        privacy=cfg.get('privacy', 'public'),
                        log_cb=log_cb,
                        token_file=token_path,
                        playlist_name=playlist_name
                    )
                except Exception as ue:
                    if _is_youtube_quota_error(ue):
                        q = enqueue_youtube_upload_task(
                            project_dir=project_dir,
                            final_video=final_video,
                            meta=meta,
                            thumbnail_path=thumb_path,
                            cfg=cfg,
                            reason='quota_exceeded',
                            error_text=_youtube_error_text(ue),
                        )
                        upload_result = {
                            'queued': True,
                            'queue_id': q.get('id'),
                            'reason': 'quota_exceeded',
                            'channel_key': channel_key,
                        }
                        log_cb(f"  ⚠️ YouTube quota exceeded. Deferred to queue: task={q.get('id')}")
                    else:
                        upload_result = {'channel_key': channel_key, 'error': str(ue)}
                        log_cb(f'⚠️ Upload to [{channel_key}] failed: {ue}')
    else:
        log_cb('ℹ️ Auto-upload YouTube disabled in config.')

    tiktok_result = _auto_upload_tiktok(project_dir, final_video, meta, cfg, log_cb, tiktok_video=final_video_tiktok)
    facebook_reels_result = _auto_upload_facebook_reels(project_dir, final_video, meta, cfg, log_cb)

    steps_done = list(info.get('steps_completed') or [])
    if upload_result and not upload_result.get('error') and 'upload' not in steps_done:
        steps_done.append('upload')
    if tiktok_result and not tiktok_result.get('error') and 'upload_tiktok' not in steps_done:
        steps_done.append('upload_tiktok')
    if facebook_reels_result and not facebook_reels_result.get('error') and 'upload_facebook' not in steps_done:
        steps_done.append('upload_facebook')

    payload = {'steps_completed': steps_done}
    if upload_result is not None:
        payload['youtube'] = upload_result
    if tiktok_result is not None:
        payload['tiktok'] = tiktok_result
    if facebook_reels_result is not None:
        payload['facebook_reels'] = facebook_reels_result
    update_project_info(project_dir, payload)

    return {
        'project_dir': project_dir,
        'youtube': upload_result,
        'tiktok': tiktok_result,
        'facebook_reels': facebook_reels_result,
    }


def run_full_pipeline(raw_input, cfg_overrides=None, run_mode='queued'):
    """
    Run the complete pipeline from URL text to YouTube upload.
    Returns job_id for tracking progress.
    """
    job_id = str(uuid.uuid4())[:8]
    JOBS[job_id] = {
        'status': 'queued', 'progress': 0,
        'message': 'Đang chờ tới lượt...', 'result': None, 'error': None
    }

    if str(run_mode or 'queued').lower() == 'direct':
        threading.Thread(
            target=_pipeline_worker,
            args=(job_id, raw_input, cfg_overrides),
            daemon=True
        ).start()
    else:
        _PIPELINE_QUEUE.put((_pipeline_worker, (job_id, raw_input, cfg_overrides), {}))
    return job_id


def _pipeline_worker(job_id, raw_input, cfg_overrides=None):
    """Background worker for the full pipeline."""
    job = JOBS[job_id]
    log = lambda msg: pipeline_log(job_id, msg)
    cfg = load_config()
    if cfg_overrides:
        cfg.update(cfg_overrides)
    sync_gpu_heavy_limit_from_config(cfg)
    sync_download_limit_from_config(cfg)
    project_id = None
    project_dir = None

    try:
        job.update({'status': 'running', 'progress': 1, 'message': 'Extracting URL...'})

        # â”€â”€ Step 1: Extract URL â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        log('ðŸ“‹ Step 1: Extracting Douyin URL...')
        url = extract_douyin_url(raw_input)
        if not url:
            raise Exception(f'No Douyin URL found in: {raw_input[:100]}')
        log(f'  âœ… URL: {url}')
        job.update({'progress': 3, 'message': f'URL: {url}'})

        # â”€â”€ Step 2: Create Project â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        log('ðŸ“ Step 2: Creating project...')
        project_id, project_dir = create_project(cfg.get('projects_dir'))
        bind_job_project_log(job_id, project_dir)
        log(f'  âœ… Project: {project_dir}')
        series_context = _series_context_from_cfg(cfg)
        if series_context:
            update_project_info(project_dir, {'series_context': series_context})
            log(f'  Series context: {series_context.get("series_name_vi") or series_context.get("series_name") or ""} | episode {series_context.get("episode_no", "?")} ({series_context.get("episode_min", "?")}-{series_context.get("episode_max", "?")})')
        job.update({'progress': 5, 'message': 'Downloading video...'})

        # â”€â”€ Step 3: Download Video â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        log('â¬‡ï¸ Step 3: Downloading video...')
        with download_slot(log, 'Download'):
            dl_result = download_video(url, project_dir, log_cb=log)
        video_path = dl_result['path']
        douyin_meta = dl_result.get('douyin_meta', {})
        if not douyin_meta.get('douyin_title') and series_context.get('series_folder'):
            # Fallback to series_folder
            sf = series_context.get('series_folder')
            formatted_title = sf.replace('_', ' ').replace('-', ' ').title()
            douyin_meta['douyin_title'] = formatted_title

        if douyin_meta:
            log(f'  ðŸ“ Douyin info: {douyin_meta.get("douyin_title", "N/A")[:60]}')
        # Rename to video.mp4
        video_dst = os.path.join(project_dir, 'video.mp4')
        if video_path != video_dst:
            shutil.move(video_path, video_dst)
            video_path = video_dst
        update_project_info(project_dir, {
            'source_url': url,
            'video_path': video_path,
            'douyin_meta': douyin_meta,
            'steps_completed': ['download']
        })
        log(f'  âœ… Video: {video_path}')
        job.update({'progress': 15, 'message': 'Separating vocals...'})

        # â”€â”€ Step 4: Vocal Separation (Demucs) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        log('ðŸŽµ Step 4: Demucs vocal separation...')
        sep_result = separate(video_path, project_dir,
                              model=cfg.get('demucs_model', 'htdemucs'),
                              fmt='mp3', log_cb=log)
        vocals_path = sep_result['vocals']
        no_vocals_path = sep_result['no_vocals']
        update_project_info(project_dir, {
            'vocals': vocals_path,
            'no_vocals': no_vocals_path,
            'steps_completed': ['download', 'separate']
        })
        log(f'  âœ… Vocals: {vocals_path}')
        job.update({'progress': 30, 'message': 'Transcribing (Whisper)...'})

        # â”€â”€ Step 5: STT (Whisper) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        log('ðŸ“ Step 5: Whisper STT...')
        srt_orig_path = os.path.join(project_dir, 'srt_goc.srt')
        srt_original = transcribe(
            video_path, srt_orig_path,
            model_size=cfg.get('whisper_model', 'medium'),
            language=cfg.get('source_lang', 'zh'),
            log_cb=log
        )
        update_project_info(project_dir, {
            'srt_original': srt_orig_path,
            'steps_completed': ['download', 'separate', 'stt']
        })
        job.update({'progress': 50, 'message': 'Translating...'})

        # â”€â”€ Step 6: Translate â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        translation_provider = cfg.get('translation_provider', '9router')
        log(f'ðŸŒ Step 6: Translation ({translation_provider})...')
        api_key = cfg.get('api_key', '')
        if translation_provider == 'gemini' and not api_key:
            raise Exception('Missing Gemini API key in config')
        srt_translated = translate_srt(
            srt_original,
            target_lang=cfg.get('target_lang', 'vi'),
            api_key=api_key,
            gemini_model=cfg.get('gemini_model', 'gemini-2.5-flash'),
            log_cb=log,
            style=cfg.get('translation_style', 'Máº·c Ä‘á»‹nh'),
            translation_provider=translation_provider,
            local_model=cfg.get('local_translation_model', 'qwen3:8b'),
            local_api_url=cfg.get('local_translation_api_url', 'http://127.0.0.1:11434/api/chat'),
            local_timeout=cfg.get('local_translation_timeout', 180),
            name_overrides=cfg.get('name_overrides', None),
            source_lang=cfg.get('source_lang', 'zh'),
            provider_order=cfg.get('translation_provider_order', None),
            azure_translator_key=cfg.get('azure_translator_key', ''),
            azure_translator_endpoint=cfg.get('azure_translator_endpoint', 'https://api.cognitive.microsofttranslator.com'),
            azure_translator_region=cfg.get('azure_translator_region', ''),
            deepl_api_key=cfg.get('deepl_api_key', ''),
            deepl_api_url=cfg.get('deepl_api_url', 'https://api-free.deepl.com/v2/translate'),
            ninerouter_url=cfg.get('ninerouter_url', 'http://127.0.0.1:20128'),
            ninerouter_key=cfg.get('ninerouter_key', ''),
            ninerouter_model=cfg.get('ninerouter_model', ''),
            ninerouter_timeout=cfg.get('ninerouter_timeout', 180)
        )
        srt_tr_path = os.path.join(project_dir, 'srt_dadich.srt')
        with open(srt_tr_path, 'w', encoding='utf-8') as f:
            f.write(srt_translated)
        update_project_info(project_dir, {
            'srt_translated': srt_tr_path,
            'steps_completed': ['download', 'separate', 'stt', 'translate']
        })
        job.update({'progress': 60, 'message': 'Generating TTS...'})

        # â”€â”€ Step 7: Gemini TTS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        log('ðŸŽ¤ Step 7: Gemini TTS dubbing...')

        def _tts_progress(done, total, g_ok, v_ok, x_ok, failed):
            # Map TTS sub-progress to 60-78% of full pipeline
            sub_pct = int(done / total * 18)
            job.update({'progress': 60 + sub_pct, 'message': f'TTS: {done}/{total}'})

        tts_output = os.path.join(project_dir, 'tts_dubbed.mp3')
        generate_tts_audio(
            srt_translated, tts_output,
            voice=cfg.get('tts_voice', 'Zephyr'),
            api_key=api_key,
            log_cb=log,
            batch_size=10,
            engine=cfg.get('tts_engine'),
            tts_speed=cfg.get('tts_speed'),
            tts_pitch=cfg.get('tts_pitch'),
            tts_volume=cfg.get('tts_volume'),
            vieneu_voice=cfg.get('vieneu_voice'),
            vieneu_mode=cfg.get('vieneu_mode'),
            auto_adjust_tts_speed=cfg.get('auto_adjust_tts_speed'),
            on_batch_done=_tts_progress
        )
        update_project_info(project_dir, {
            'tts_output': tts_output,
            'steps_completed': ['download','separate','stt','translate','tts']
        })
        job.update({'progress': 78, 'message': 'Rendering video...'})

        # â”€â”€ Step 8: Render Video â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        log('ðŸŽ¬ Step 8: Rendering video...')
        final_video = os.path.join(project_dir, 'final_video.mp4')
        final_video_tiktok = None
        intro_path = cfg.get('intro_path', '')
        if not intro_path or not os.path.exists(intro_path):
            intro_path = None
        render_video(
            video_path, srt_tr_path, no_vocals_path, final_video,
            blur_sigma=cfg.get('blur_sigma', 20),
            mask_h=cfg.get('mask_h', 100),
            mask_y_pct=cfg.get('mask_y_pct', 83.5),
            font_name=cfg.get('font_name', 'UTM_Bebas.ttf'),
            font_size=cfg.get('font_size', 28),
            font_color=cfg.get('font_color', '#FFFFFF'),
            font_outline_color=cfg.get('font_outline_color', '#000000'),
            font_outline_width=cfg.get('font_outline_width', 2),
            margin_v=cfg.get('margin_v', 16),
            rotate_deg=cfg.get('rotate_deg', 0.5),
            mirror=cfg.get('mirror', True),
            intro_path=intro_path,
            tts_path=tts_output,
            log_cb=log
        )
        if cfg.get('auto_upload_tiktok', False):
            final_video_tiktok = _ensure_tiktok_vertical_video(project_dir, final_video, cfg, log)
        update_payload = {
            'final_video': final_video,
            'steps_completed': ['download','separate','stt','translate','tts','render']
        }
        if final_video_tiktok:
            update_payload['final_video_tiktok'] = final_video_tiktok
        update_project_info(project_dir, update_payload)
        job.update({'progress': 88, 'message': 'Generating metadata...'})

        # â”€â”€ Step 9: Generate Metadata + Thumbnail â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        log('ðŸ“ Step 9: AI metadata + thumbnail...')
        # Get video duration for title logic
        try:
            dur_result = run_cmd(['ffprobe','-v','error','-show_entries','format=duration',
                                  '-of','default=noprint_wrappers=1:nokey=1', video_path],
                                 capture_output=True, text=True)
            video_duration = float(dur_result.stdout.strip())
        except Exception:
            video_duration = 0
        meta = generate_metadata(
            srt_translated, api_key,
            channel_name=cfg.get('channel_name', 'MiuBonVietsub'),
            gemini_model=cfg.get('gemini_model', 'gemini-2.5-pro'),
            douyin_meta=douyin_meta,
            video_duration=video_duration,
            log_cb=log,
            cfg_overrides=cfg
        )
        # Save metadata
        meta_path = os.path.join(project_dir, 'metadata.json')
        with open(meta_path, 'w', encoding='utf-8') as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)

        thumb_path = os.path.join(project_dir, 'thumbnail.jpg')
        font_path_thumb = str(os.path.join(
            os.path.dirname(os.path.abspath(__file__)), 'Fonts',
            cfg.get('font_name_thumb', 'FS Boom Boom.ttf')
        ))
        create_thumbnail(
            video_path, srt_translated, meta, thumb_path,
            font_path=font_path_thumb, cfg=cfg, douyin_meta=douyin_meta, log_cb=log
        )

        update_project_info(project_dir, {
            'metadata': meta,
            'thumbnail': thumb_path,
            'steps_completed': ['download','separate','stt','translate','tts','render','metadata']
        })
        job.update({'progress': 93, 'message': 'Uploading to YouTube...'})

        # ─ Step 10: Upload to YouTube (round-robin) ─────────────────────────────────────────
        upload_result = None
        if cfg.get('auto_upload', False):
            log('📤 Step 10: Uploading to YouTube...')
            if _youtube_upload_queue_has_items():
                q = enqueue_youtube_upload_task(
                    project_dir=project_dir,
                    final_video=final_video,
                    meta=meta,
                    thumbnail_path=thumb_path,
                    cfg=cfg,
                    reason='pending_queue_not_empty',
                    error_text='deferred because pending upload queue has items',
                )
                upload_result = {
                    'queued': True,
                    'queue_id': q.get('id'),
                    'reason': 'pending_queue_not_empty',
                }
                log(f"  ⏸️ Deferred YouTube upload (queue busy): task={q.get('id')}")
            else:
                from modules.uploader import get_next_upload_token
                token_path, channel_key, _ = get_next_upload_token(log_cb=log)
                if not token_path:
                    log('⚠️ No enabled YouTube channels. Skipping upload.')
                    upload_result = {'error': 'No enabled channels'}
                else:
                    try:
                        series_ctx = cfg.get('series_context')
                        playlist_name = series_ctx.get('series_name_vi') or series_ctx.get('series_name') if isinstance(series_ctx, dict) else None

                        upload_result = upload_video(
                            final_video,
                            title=meta.get('title', 'Untitled'),
                            description=meta.get('description', ''),
                            thumbnail_path=thumb_path,
                            tags=meta.get('tags', []),
                            privacy=cfg.get('privacy', 'public'),
                            log_cb=log,
                            token_file=token_path,
                            playlist_name=playlist_name
                        )
                        update_project_info(project_dir, {
                            'youtube': upload_result,
                            'steps_completed': ['download','separate','stt','translate',
                                                'tts','render','metadata','upload']
                        })
                    except Exception as ue:
                        if _is_youtube_quota_error(ue):
                            q = enqueue_youtube_upload_task(
                                project_dir=project_dir,
                                final_video=final_video,
                                meta=meta,
                                thumbnail_path=thumb_path,
                                cfg=cfg,
                                reason='quota_exceeded',
                                error_text=_youtube_error_text(ue),
                            )
                            upload_result = {
                                'queued': True,
                                'queue_id': q.get('id'),
                                'reason': 'quota_exceeded',
                                'channel_key': channel_key,
                            }
                            log(f"  ⚠️ YouTube quota exceeded. Deferred to queue: task={q.get('id')}")
                        else:
                            log(f'âš ï¸ Upload to [{channel_key}] failed: {ue}')
                            upload_result = {'channel_key': channel_key, 'error': str(ue)}
        else:
            log('â„¹ï¸ Auto-upload disabled. Video ready for manual upload.')

        tiktok_result = _auto_upload_tiktok(project_dir, final_video, meta, cfg, log, tiktok_video=final_video_tiktok)
        if tiktok_result:
            update_project_info(project_dir, {'tiktok': tiktok_result})
        facebook_reels_result = _auto_upload_facebook_reels(project_dir, final_video, meta, cfg, log)
        if facebook_reels_result:
            update_project_info(project_dir, {'facebook_reels': facebook_reels_result})

        # â”€â”€ Done â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        result = {
            'project_id': project_id,
            'project_dir': project_dir,
            'video': video_path,
            'no_vocals': no_vocals_path,
            'srt_original': srt_orig_path,
            'srt_translated': srt_tr_path,
            'tts_output': tts_output,
            'final_video': final_video,
            'final_video_tiktok': final_video_tiktok,
            'metadata': meta,
            'thumbnail': thumb_path,
            'youtube': upload_result,
            'tiktok': tiktok_result,
            'facebook_reels': facebook_reels_result,
        }
        job.update({
            'status': 'done', 'progress': 100,
            'message': f'âœ… Pipeline complete! Project: {project_dir}',
            'result': result
        })
        log(f'ðŸŽ‰ PIPELINE COMPLETE! Project: {project_dir}')

    except Exception as exc:
        tb = traceback.format_exc()
        log(f'âŒ PIPELINE ERROR:\n{tb}')
        partial_result = {}
        if project_id:
            partial_result['project_id'] = project_id
        if project_dir:
            partial_result['project_dir'] = project_dir
        if partial_result:
            partial_result['partial'] = True
        job.update({
            'status': 'error', 'progress': 0,
            'message': str(exc), 'error': str(exc),
            'result': partial_result or None
        })


def resume_pipeline(project_dir, info, cfg_overrides=None, run_mode='queued'):
    """
    Resume pipeline from last completed step.
    Returns job_id for tracking progress.
    """
    job_id = str(uuid.uuid4())[:8]
    JOBS[job_id] = {
        'status': 'queued', 'progress': 0,
        'message': 'Đang chờ tới lượt...', 'result': None, 'error': None
    }

    if str(run_mode or 'queued').lower() == 'direct':
        threading.Thread(
            target=_resume_worker,
            args=(job_id, project_dir, info, cfg_overrides),
            daemon=True
        ).start()
    else:
        _PIPELINE_QUEUE.put((_resume_worker, (job_id, project_dir, info, cfg_overrides), {}))
    return job_id


def _resume_worker(job_id, project_dir, info, cfg_overrides=None):
    """Background worker that resumes from last completed step."""
    job = JOBS[job_id]
    log = lambda msg: pipeline_log(job_id, msg)
    cfg = load_config()
    if cfg_overrides:
        cfg.update(cfg_overrides)
    sync_gpu_heavy_limit_from_config(cfg)
    sync_download_limit_from_config(cfg)
    project_id = info.get('project_id', os.path.basename(project_dir)[:8]) if isinstance(info, dict) else None
    bind_job_project_log(job_id, project_dir)

    try:
        job.update({'status': 'running', 'progress': 1, 'message': 'Resuming...'})
        steps_done = info.get('steps_completed', [])
        url = info.get('source_url', '')
        project_id = info.get('project_id', os.path.basename(project_dir)[:8])
        douyin_meta = info.get('douyin_meta', {})
        series_context = _series_context_from_cfg(cfg) or (info.get('series_context') if isinstance(info, dict) else {})
        if series_context:
            cfg['series_context'] = series_context
            update_project_info(project_dir, {'series_context': series_context})

        log(f'ðŸ”„ Resuming project: {os.path.basename(project_dir)}')
        log(f'  Steps done: {", ".join(steps_done) or "none"}')

        # â”€â”€ Paths â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        video_path = os.path.join(project_dir, 'video.mp4')
        
        # Check if video.mp4 exists and is not corrupted
        if os.path.exists(video_path):
            try:
                # Try to get duration as a simple integrity check
                dur = get_media_duration(video_path)
                if dur <= 0:
                    log('  âš ï¸ video.mp4 is present but seems corrupted (0 duration). Forcing re-download.')
                    if 'download' in steps_done: steps_done.remove('download')
            except Exception:
                log('  âš ï¸ video.mp4 is corrupted or unreadable. Forcing re-download.')
                if 'download' in steps_done: steps_done.remove('download')
        else:
            if 'download' in steps_done:
                log('  âš ï¸ video.mp4 missing although marked as downloaded. Forcing re-download.')
                steps_done.remove('download')

        vocals_path = info.get('vocals', os.path.join(project_dir, 'vocals.mp3'))
        no_vocals_path = info.get('no_vocals', os.path.join(project_dir, 'no_vocals.mp3'))
        srt_orig_path = os.path.join(project_dir, 'srt_goc.srt')
        srt_tr_path = os.path.join(project_dir, 'srt_dadich.srt')
        tts_output = os.path.join(project_dir, 'tts_dubbed.mp3')
        final_video = os.path.join(project_dir, 'final_video.mp4')
        final_video_tiktok = info.get('final_video_tiktok')

        # â”€â”€ Step 3: Download â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if 'download' not in steps_done:
            log('â¬‡ï¸ Step 3: Downloading video...')
            if url:
                with download_slot(log, 'Download'):
                    dl_result = download_video(url, project_dir, log_cb=log)
                vp = dl_result['path']
                douyin_meta = dl_result.get('douyin_meta', {})
                if not douyin_meta.get('douyin_title') and series_context.get('series_folder'):
                    # Fallback to series_folder
                    sf = series_context.get('series_folder')
                    formatted_title = sf.replace('_', ' ').replace('-', ' ').title()
                    douyin_meta['douyin_title'] = formatted_title

                video_dst = os.path.join(project_dir, 'video.mp4')
                if vp != video_dst:
                    shutil.move(vp, video_dst)
                update_project_info(project_dir, {
                    'source_url': url, 'video_path': video_dst,
                    'douyin_meta': douyin_meta,
                    'steps_completed': ['download']
                })
                log(f'  âœ… Video: {video_dst}')
            else:
                raise Exception('No source URL to download')
        else:
            log('  â­ï¸ Download: already done')
        job.update({'progress': 15, 'message': 'Separating vocals...'})

        # â”€â”€ Step 4: Separate â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if 'separate' not in steps_done:
            log('ðŸŽµ Step 4: Demucs vocal separation...')
            sep_result = separate(video_path, project_dir,
                                  model=cfg.get('demucs_model', 'htdemucs'),
                                  fmt='mp3', log_cb=log)
            vocals_path = sep_result['vocals']
            no_vocals_path = sep_result['no_vocals']
            update_project_info(project_dir, {
                'vocals': vocals_path, 'no_vocals': no_vocals_path,
                'steps_completed': ['download', 'separate']
            })
            log(f'  âœ… Vocals: {vocals_path}')
        else:
            log('  â­ï¸ Separate: already done')
        job.update({'progress': 30, 'message': 'Transcribing...'})

        # â”€â”€ Step 5: STT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if 'stt' not in steps_done:
            log('ðŸ“ Step 5: Whisper STT...')
            srt_original = transcribe(
                video_path, srt_orig_path,
                model_size=cfg.get('whisper_model', 'medium'),
                language=cfg.get('source_lang', 'zh'), log_cb=log
            )
            update_project_info(project_dir, {
                'srt_original': srt_orig_path,
                'steps_completed': ['download', 'separate', 'stt']
            })
        else:
            log('  â­ï¸ STT: already done')
            if os.path.exists(srt_orig_path):
                srt_original = open(srt_orig_path, 'r', encoding='utf-8').read()
            else:
                srt_original = ''
        job.update({'progress': 50, 'message': 'Translating...'})

        # â”€â”€ Step 6: Translate â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        translation_provider = cfg.get('translation_provider', '9router')
        api_key = cfg.get('api_key', '')
        if translation_provider == 'gemini' and not api_key:
            raise Exception('Missing Gemini API key in config')

        if 'translate' not in steps_done:
            log(f'ðŸŒ Step 6: Translation ({translation_provider})...')
            srt_translated = translate_srt(
                srt_original, target_lang=cfg.get('target_lang', 'vi'),
                api_key=api_key,
                gemini_model=cfg.get('gemini_model', 'gemini-2.5-flash'),
                log_cb=log,
                style=cfg.get('translation_style', 'Máº·c Ä‘á»‹nh'),
                translation_provider=translation_provider,
                local_model=cfg.get('local_translation_model', 'qwen3:8b'),
                local_api_url=cfg.get('local_translation_api_url', 'http://127.0.0.1:11434/api/chat'),
                local_timeout=cfg.get('local_translation_timeout', 180),
                name_overrides=cfg.get('name_overrides', None),
                source_lang=cfg.get('source_lang', 'zh'),
                provider_order=cfg.get('translation_provider_order', None),
                azure_translator_key=cfg.get('azure_translator_key', ''),
                azure_translator_endpoint=cfg.get('azure_translator_endpoint', 'https://api.cognitive.microsofttranslator.com'),
                azure_translator_region=cfg.get('azure_translator_region', ''),
                deepl_api_key=cfg.get('deepl_api_key', ''),
                deepl_api_url=cfg.get('deepl_api_url', 'https://api-free.deepl.com/v2/translate'),
                ninerouter_url=cfg.get('ninerouter_url', 'http://127.0.0.1:20128'),
                ninerouter_key=cfg.get('ninerouter_key', ''),
                ninerouter_model=cfg.get('ninerouter_model', ''),
                ninerouter_timeout=cfg.get('ninerouter_timeout', 180)
            )
            with open(srt_tr_path, 'w', encoding='utf-8') as f:
                f.write(srt_translated)
            update_project_info(project_dir, {
                'srt_translated': srt_tr_path,
                'steps_completed': ['download', 'separate', 'stt', 'translate']
            })
        else:
            log('  â­ï¸ Translate: already done')
            if os.path.exists(srt_tr_path):
                srt_translated = open(srt_tr_path, 'r', encoding='utf-8').read()
            else:
                srt_translated = ''
        job.update({'progress': 60, 'message': 'Generating TTS...'})

        # â”€â”€ Step 7: TTS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if 'tts' not in steps_done:
            log('ðŸŽ¤ Step 7: Gemini TTS dubbing...')

            def _tts_progress(done, total, g_ok, v_ok, x_ok, failed):
                sub_pct = int(done / total * 18)
                job.update({'progress': 60 + sub_pct, 'message': f'TTS: {done}/{total}'})

            generate_tts_audio(
                srt_translated, tts_output,
                voice=cfg.get('tts_voice', 'Zephyr'),
                api_key=api_key, log_cb=log, batch_size=10,
                engine=cfg.get('tts_engine'),
                tts_speed=cfg.get('tts_speed'),
                tts_pitch=cfg.get('tts_pitch'),
                tts_volume=cfg.get('tts_volume'),
                vieneu_voice=cfg.get('vieneu_voice'),
                vieneu_mode=cfg.get('vieneu_mode'),
                auto_adjust_tts_speed=cfg.get('auto_adjust_tts_speed'),
                on_batch_done=_tts_progress
            )
            update_project_info(project_dir, {
                'tts_output': tts_output,
                'steps_completed': ['download','separate','stt','translate','tts']
            })
        else:
            log('  â­ï¸ TTS: already done')
        job.update({'progress': 78, 'message': 'Rendering video...'})

        # â”€â”€ Step 8: Render â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if 'render' not in steps_done:
            log('ðŸŽ¬ Step 8: Rendering video...')
            intro_path = cfg.get('intro_path', '')
            if not intro_path or not os.path.exists(intro_path):
                intro_path = None
            render_video(
                video_path, srt_tr_path, no_vocals_path, final_video,
                blur_sigma=cfg.get('blur_sigma', 20),
                mask_h=cfg.get('mask_h', 100),
                mask_y_pct=cfg.get('mask_y_pct', 83.5),
                font_name=cfg.get('font_name', 'UTM_Bebas.ttf'),
                font_size=cfg.get('font_size', 28),
                font_color=cfg.get('font_color', '#FFFFFF'),
                font_outline_color=cfg.get('font_outline_color', '#000000'),
                font_outline_width=cfg.get('font_outline_width', 2),
                margin_v=cfg.get('margin_v', 16),
                rotate_deg=cfg.get('rotate_deg', 0.5),
                mirror=cfg.get('mirror', True),
                intro_path=intro_path,
                tts_path=tts_output,
                log_cb=log
            )
            if cfg.get('auto_upload_tiktok', False):
                final_video_tiktok = _ensure_tiktok_vertical_video(project_dir, final_video, cfg, log)
            update_payload = {
                'final_video': final_video,
                'steps_completed': ['download','separate','stt','translate','tts','render']
            }
            if final_video_tiktok:
                update_payload['final_video_tiktok'] = final_video_tiktok
            update_project_info(project_dir, update_payload)
        else:
            log('  â­ï¸ Render: already done')
            if cfg.get('auto_upload_tiktok', False):
                final_video_tiktok = _ensure_tiktok_vertical_video(project_dir, final_video, cfg, log)
                update_project_info(project_dir, {'final_video_tiktok': final_video_tiktok})
        job.update({'progress': 88, 'message': 'Generating metadata...'})

        # â”€â”€ Step 9: Metadata â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if 'metadata' not in steps_done:
            log('ðŸ“ Step 9: AI metadata + thumbnail...')
            
            # Determine target channel name for metadata consistency (Round-robin peek)
            target_channel_name = cfg.get('channel_name', 'MiuBonVietsub')
            if cfg.get('auto_upload', False):
                from modules.uploader import get_next_upload_token
                _, _, real_name = get_next_upload_token(peek=True)
                if real_name:
                    target_channel_name = real_name
                    log(f'  ðŸ·ï¸ Using real channel name for metadata: {target_channel_name}')

            # Get video duration for title logic
            try:
                dur_result = run_cmd(['ffprobe','-v','error','-show_entries','format=duration',
                                      '-of','default=noprint_wrappers=1:nokey=1', video_path],
                                     capture_output=True, text=True)
                video_duration = float(dur_result.stdout.strip())
            except Exception:
                video_duration = 0
            meta = generate_metadata(
                srt_translated, api_key,
                channel_name=target_channel_name,
                gemini_model=cfg.get('gemini_model', 'gemini-2.5-pro'),
                douyin_meta=douyin_meta,
                video_duration=video_duration,
                log_cb=log,
                cfg_overrides=cfg
            )
            meta_path = os.path.join(project_dir, 'metadata.json')
            with open(meta_path, 'w', encoding='utf-8') as f:
                json.dump(meta, f, ensure_ascii=False, indent=2)
            thumb_path = os.path.join(project_dir, 'thumbnail.jpg')
            font_path_thumb = str(os.path.join(
            os.path.dirname(os.path.abspath(__file__)), 'Fonts',
            cfg.get('font_name_thumb', 'FS Boom Boom.ttf')
        ))
            create_thumbnail(
                video_path, srt_translated, meta, thumb_path,
                font_path=font_path_thumb, cfg=cfg, douyin_meta=douyin_meta, log_cb=log
            )
            update_project_info(project_dir, {
                'metadata': meta, 'thumbnail': thumb_path,
                'steps_completed': ['download','separate','stt','translate','tts','render','metadata']
            })
        else:
            log('  â­ï¸ Metadata: already done')
            meta_path = os.path.join(project_dir, 'metadata.json')
            meta = {}
            if os.path.exists(meta_path):
                with open(meta_path, 'r', encoding='utf-8') as f:
                    meta = json.load(f)
            thumb_path = os.path.join(project_dir, 'thumbnail.jpg')
        job.update({'progress': 93, 'message': 'Uploading to YouTube...'})

        # â”€â”€ Step 10: Upload (round-robin) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        upload_result = None
        if cfg.get('auto_upload', False) and 'upload' not in steps_done:
            log('ðŸ“¤ Step 10: Uploading to YouTube...')
            if _youtube_upload_queue_has_items():
                q = enqueue_youtube_upload_task(
                    project_dir=project_dir,
                    final_video=final_video,
                    meta=meta,
                    thumbnail_path=thumb_path,
                    cfg=cfg,
                    reason='pending_queue_not_empty',
                    error_text='deferred because pending upload queue has items',
                )
                upload_result = {
                    'queued': True,
                    'queue_id': q.get('id'),
                    'reason': 'pending_queue_not_empty',
                }
                log(f"  ⏸️ Deferred YouTube upload (queue busy): task={q.get('id')}")
            else:
                from modules.uploader import get_next_upload_token
                token_path, channel_key, _ = get_next_upload_token(log_cb=log)
                if not token_path:
                    log('âš ï¸ No enabled YouTube channels. Skipping upload.')
                    upload_result = {'error': 'No enabled channels'}
                else:
                    try:
                        series_ctx = cfg.get('series_context')
                        playlist_name = series_ctx.get('series_name_vi') or series_ctx.get('series_name') if isinstance(series_ctx, dict) else None

                        upload_result = upload_video(
                            final_video,
                            title=meta.get('title', 'Untitled'),
                            description=meta.get('description', ''),
                            thumbnail_path=thumb_path,
                            tags=meta.get('tags', []),
                            privacy=cfg.get('privacy', 'public'),
                            log_cb=log,
                            token_file=token_path,
                            playlist_name=playlist_name
                        )
                        update_project_info(project_dir, {
                            'youtube': upload_result,
                            'steps_completed': ['download','separate','stt','translate',
                                                'tts','render','metadata','upload']
                        })
                    except Exception as ue:
                        if _is_youtube_quota_error(ue):
                            q = enqueue_youtube_upload_task(
                                project_dir=project_dir,
                                final_video=final_video,
                                meta=meta,
                                thumbnail_path=thumb_path,
                                cfg=cfg,
                                reason='quota_exceeded',
                                error_text=_youtube_error_text(ue),
                            )
                            upload_result = {
                                'queued': True,
                                'queue_id': q.get('id'),
                                'reason': 'quota_exceeded',
                                'channel_key': channel_key,
                            }
                            log(f"  ⚠️ YouTube quota exceeded. Deferred to queue: task={q.get('id')}")
                        else:
                            log(f'âš ï¸ Upload to [{channel_key}] failed: {ue}')
                            upload_result = {'channel_key': channel_key, 'error': str(ue)}
        else:
            log('â„¹ï¸ Upload skipped (already done or auto-upload disabled).')
        if cfg.get('auto_upload_tiktok', False) and not (info.get('tiktok') or {}).get('ok_count'):
            tiktok_result = _auto_upload_tiktok(project_dir, final_video, meta, cfg, log, tiktok_video=final_video_tiktok)
            if tiktok_result:
                update_project_info(project_dir, {'tiktok': tiktok_result})
        else:
            tiktok_result = info.get('tiktok')
        if cfg.get('auto_upload_facebook_reels', False) and not (info.get('facebook_reels') or {}).get('ok_count'):
            facebook_reels_result = _auto_upload_facebook_reels(project_dir, final_video, meta, cfg, log)
            if facebook_reels_result:
                update_project_info(project_dir, {'facebook_reels': facebook_reels_result})
        else:
            facebook_reels_result = info.get('facebook_reels')


        # â”€â”€ Done â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        result = {
            'project_id': project_id,
            'project_dir': project_dir,
            'video': video_path,
            'no_vocals': no_vocals_path,
            'srt_original': srt_orig_path,
            'srt_translated': srt_tr_path,
            'tts_output': tts_output,
            'final_video': final_video,
            'final_video_tiktok': final_video_tiktok,
            'metadata': meta,
            'thumbnail': thumb_path,
            'youtube': upload_result,
            'tiktok': tiktok_result,
            'facebook_reels': facebook_reels_result,
        }
        job.update({
            'status': 'done', 'progress': 100,
            'message': f'âœ… Pipeline resumed & complete! Project: {project_dir}',
            'result': result
        })
        log(f'ðŸŽ‰ RESUME COMPLETE! Project: {project_dir}')

    except Exception as exc:
        tb = traceback.format_exc()
        log(f'âŒ RESUME ERROR:\n{tb}')
        partial_result = {}
        if project_id:
            partial_result['project_id'] = project_id
        if project_dir:
            partial_result['project_dir'] = project_dir
        if partial_result:
            partial_result['partial'] = True
        job.update({
            'status': 'error', 'progress': 0,
            'message': str(exc), 'error': str(exc),
            'result': partial_result or None
        })




