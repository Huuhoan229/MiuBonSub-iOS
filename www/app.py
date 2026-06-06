"""
app.py â€“ MiuBon Vietsub Pipeline Server (Flask)
Full Auto: Douyin â†’ Download â†’ Demucs â†’ Whisper â†’ Translate â†’ TTS â†’ Render â†’ YouTube
"""
import os, sys, json, uuid, threading, time, re, shutil, tempfile, unicodedata, difflib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from flask import Flask, request, jsonify, send_file, send_from_directory, redirect
from flask_cors import CORS

# Prevent stale shell/session flags from forcing Hugging Face offline mode.
os.environ.pop('HF_HUB_OFFLINE', None)
os.environ.pop('TRANSFORMERS_OFFLINE', None)

from modules.helpers import (
    load_config, save_config, JOBS, BASE_DIR, FONTS_DIR,
    get_pipeline_logs as _get_logs, list_projects, get_media_duration,
    fix_mojibake_text, sync_gpu_heavy_limit_from_config, get_gpu_heavy_limiter_state,
    sync_download_limit_from_config, get_download_limiter_state
)
from modules.downloader import (
    launch_chromium_login, get_login_job, get_download_status,
    load_cookies, save_cookies
)
from modules.uploader import (
    check_auth_status, import_oauth_json,
    get_token_path_by_key, list_uploaded_videos, get_video_detail,
    delete_video, upload_video, sort_playlist
)
from modules.tiktok_uploader import (
    tiktok_auth_status, launch_tiktok_login, get_tiktok_login_job,
    split_video_for_tiktok, build_tiktok_caption, upload_tiktok_videos,
    import_tiktok_storage_from_browser, import_tiktok_storage_from_cookies_text
)
from modules.tiktok_open_api import (
    tiktok_api_status, tiktok_build_auth_url, tiktok_exchange_code, tiktok_disconnect_api,
    tiktok_direct_post_video, tiktok_query_creator_info, tiktok_get_valid_access_token, make_pkce_pair
)
from modules.facebook_reels import (
    facebook_reels_status, facebook_reels_check_access, facebook_upload_reel
)
from modules.gdrive import (
    check_auth_status as gdrive_check_auth, get_auth_url, handle_callback,
    upload_folder_to_drive, list_drive_projects, sync_projects_from_drive
)
from modules.profile_scraper import (
    start_scrape_job,
    get_scrape_job,
    translate_captions,
    group_videos_into_series,
    scrape_user_videos,
)
from pipeline import run_full_pipeline, resume_pipeline, get_youtube_upload_queue_status, upload_project_outputs

app = Flask(__name__, static_folder='static', static_url_path='/static')
CORS(app)

@app.after_request
def _add_no_cache_headers(response):
    """Prevent Vercel CDN and browsers from caching HTML/JS/CSS so updates appear immediately."""
    ct = response.content_type or ''
    if any(t in ct for t in ('text/html', 'javascript', 'text/css', 'application/json')):
        response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
    return response

# YouTube watchdog runtime state
_YT_WATCHDOG_LOCK = threading.Lock()
_YT_WATCHDOG_STATE = {
    'running': False,
    'last_run_at': None,
    'last_summary': '',
    'last_actions': [],
}

_DY_WATCHDOG_LOCK = threading.Lock()
_DY_WATCHDOG_STATE = {
    'running': False,
    'last_run_at': None,
    'last_summary': '',
    'last_actions': [],
}
_DY_WATCHDOG_FILE = BASE_DIR / 'douyin_watchdog_state.json'

_TIKTOK_UPLOAD_LOCK = threading.Lock()
_TIKTOK_UPLOAD_JOBS = {}
_FB_REELS_UPLOAD_LOCK = threading.Lock()
_FB_REELS_UPLOAD_JOBS = {}
# OAuth states are persisted to disk so code_verifier survives server restarts
_TIKTOK_OAUTH_STATES = {}  # in-memory cache; disk is authoritative
_TIKTOK_STATE_FILE = BASE_DIR / 'tiktok_oauth_states.json'
_TIKTOK_STATE_LOCK = threading.Lock()



def _tiktok_state_save(state: str, bundle: dict):
    """Persist OAuth state bundle to disk so code_verifier survives server restarts."""
    with _TIKTOK_STATE_LOCK:
        try:
            import json as _json
            data = {}
            if _TIKTOK_STATE_FILE.exists():
                try:
                    data = _json.loads(_TIKTOK_STATE_FILE.read_text(encoding='utf-8'))
                except Exception:
                    data = {}
            now = int(time.time())
            data = {k: v for k, v in data.items()
                    if isinstance(v, dict) and int(v.get('exp', 0)) > now}
            data[state] = bundle
            _TIKTOK_STATE_FILE.write_text(
                _json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
        except Exception:
            pass
        _TIKTOK_OAUTH_STATES[state] = bundle


def _tiktok_state_pop(state: str) -> dict:
    """Retrieve and delete an OAuth state bundle from disk+memory."""
    with _TIKTOK_STATE_LOCK:
        bundle = _TIKTOK_OAUTH_STATES.pop(state, None)
        try:
            import json as _json
            if _TIKTOK_STATE_FILE.exists():
                data = _json.loads(_TIKTOK_STATE_FILE.read_text(encoding='utf-8'))
                if state in data:
                    if not bundle:
                        bundle = data[state]
                    del data[state]
                    now = int(time.time())
                    data = {k: v for k, v in data.items()
                            if isinstance(v, dict) and int(v.get('exp', 0)) > now}
                    _TIKTOK_STATE_FILE.write_text(
                        _json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
        except Exception:
            pass
        if not isinstance(bundle, dict):
            return {}
        if int(bundle.get('exp', 0)) < int(time.time()):
            return {}
        return bundle



def _project_name_from_info(info: dict):
    return info.get('project_name') or os.path.basename(info.get('project_path', '') or '')


def _load_project_info_by_name(project_name: str):
    cfg = load_config()
    pdir = cfg.get('projects_dir', 'D:/anti-sub-projects')
    project_path = os.path.join(pdir, project_name)
    info_path = os.path.join(project_path, 'info.json')
    if not os.path.isfile(info_path):
        return None, None
    with open(info_path, 'r', encoding='utf-8') as f:
        info = json.load(f)
    return project_path, info


def _save_project_info(project_path: str, info: dict):
    info_path = os.path.join(project_path, 'info.json')
    with open(info_path, 'w', encoding='utf-8') as f:
        json.dump(info, f, ensure_ascii=False, indent=2)


def _find_project_by_video(video_id: str, channel_key: str = None):
    vid = (video_id or '').strip()
    if not vid:
        return None, None
    for info in list_projects():
        yt = info.get('youtube') or {}
        if yt.get('videoId') != vid:
            continue
        if channel_key and (yt.get('channel_key') or 'main') != channel_key:
            continue
        project_name = _project_name_from_info(info)
        if project_name:
            return project_name, info
    return None, None


def _extract_douyin_video_id(url_or_id: str) -> str:
    text = str(url_or_id or '').strip()
    if not text:
        return ''
    if re.fullmatch(r'\d{8,}', text):
        return text
    for pat in (
        r'/video/(\d{8,})',
        r'[?&](?:vid|group_id|from_gid)=([0-9]{8,})',
    ):
        m = re.search(pat, text)
        if m:
            return m.group(1)
    return ''


def _build_done_douyin_index():
    """Map Douyin video IDs already represented by local projects."""
    done = {}
    for p in list_projects():
        source_url = p.get('source_url') or ''
        vid = _extract_douyin_video_id(source_url)
        if not vid:
            continue
        project_name = _project_name_from_info(p)
        yt = p.get('youtube') or {}
        done[vid] = {
            'project_name': project_name or '',
            'source_url': source_url,
            'youtube_url': yt.get('url') or '',
            'youtube_video_id': yt.get('videoId') or '',
            'progress': p.get('progress', 0),
            'complete': bool(p.get('complete') or p.get('progress') == 100),
        }
    return done


def _annotate_scraped_videos_with_done(videos: list):
    done = _build_done_douyin_index()
    rows = []
    done_count = 0
    for v in videos or []:
        row = dict(v or {})
        vid = str(row.get('aweme_id') or '').strip() or _extract_douyin_video_id(row.get('url') or '')
        row['aweme_id'] = vid or row.get('aweme_id') or ''
        hit = done.get(vid) if vid else None
        if hit:
            row['local_done'] = True
            row['local_project'] = hit.get('project_name') or ''
            row['local_youtube_url'] = hit.get('youtube_url') or ''
            row['local_complete'] = bool(hit.get('complete'))
            done_count += 1
        else:
            row['local_done'] = False
        rows.append(row)
    return rows, {
        'done_count': done_count,
        'new_count': max(0, len(rows) - done_count),
        'done_source': 'local_projects',
    }


def _video_health(detail: dict, stuck_minutes: int):
    """Return (healthy, reason) based on YouTube status fields."""
    if not detail:
        return False, 'missing'
    up = (detail.get('upload_status') or '').lower()
    proc = (detail.get('processing_status') or '').lower()
    age = detail.get('age_minutes')
    if up in ('failed', 'rejected'):
        return False, up
    if proc in ('failed', 'terminated'):
        return False, proc
    if proc == 'processing' and isinstance(age, int) and age >= int(stuck_minutes):
        return False, f'stuck_processing_{age}m'
    return True, 'ok'


def _norm_text(s: str) -> str:
    s = (s or '').strip().lower()
    if not s:
        return ''
    s = unicodedata.normalize('NFKC', s)
    s = re.sub(r'\s+', ' ', s)
    s = re.sub(r'[^0-9a-zA-Z\u00C0-\u024F\u1E00-\u1EFF ]+', ' ', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def _text_similarity(a: str, b: str) -> float:
    aa = _norm_text(a)
    bb = _norm_text(b)
    return _text_similarity_normed(aa, bb)


def _text_similarity_normed(aa: str, bb: str) -> float:
    if not aa or not bb:
        return 0.0
    if aa == bb:
        return 1.0
    return difflib.SequenceMatcher(None, aa, bb).ratio()


def _best_project_match_for_video(v_title: str, v_desc: str):
    best = None
    best_score = 0.0
    for p in list_projects():
        pname = _project_name_from_info(p)
        meta = p.get('metadata') or {}
        p_title = meta.get('title') or ''
        p_desc = meta.get('description') or ''
        if not pname or (not p_title and not p_desc):
            continue
        tscore = _text_similarity(v_title, p_title)
        dscore = _text_similarity(v_desc[:400], p_desc[:400])
        score = (tscore * 0.75) + (dscore * 0.25)
        if score > best_score:
            best_score = score
            best = {'project_name': pname, 'score': round(score, 4), 'title_score': round(tscore, 4), 'desc_score': round(dscore, 4)}
    return best


def _build_youtube_project_match_index(projects=None, channel_key: str = None):
    """Build one in-memory index for YouTube manager scan-match.

    The old scan route called list_projects() for every YouTube video and again
    for every fuzzy pass. With hundreds of projects this easily exceeds the
    Vercel/Cloudflare tunnel request window.
    """
    items = list(projects if projects is not None else list_projects())
    by_video_id = {}
    fuzzy = []
    for p in items:
        pname = _project_name_from_info(p)
        if not pname:
            continue
        yt = p.get('youtube') or {}
        vid = (yt.get('videoId') or '').strip()
        if vid and (not channel_key or (yt.get('channel_key') or 'main') == channel_key):
            by_video_id[vid] = (pname, p)
        meta = p.get('metadata') or {}
        p_title = meta.get('title') or ''
        p_desc = meta.get('description') or ''
        if p_title or p_desc:
            fuzzy.append((pname, p, _norm_text(p_title), _norm_text((p_desc or '')[:400])))
    return by_video_id, fuzzy


def _best_project_match_for_video_indexed(v_title: str, v_desc: str, fuzzy_index):
    best = None
    best_score = 0.0
    title_norm = _norm_text(v_title)
    desc_norm = _norm_text((v_desc or '')[:400])
    for pname, _info, p_title_norm, p_desc_norm in fuzzy_index:
        tscore = _text_similarity_normed(title_norm, p_title_norm)
        dscore = _text_similarity_normed(desc_norm, p_desc_norm)
        score = (tscore * 0.75) + (dscore * 0.25)
        if score > best_score:
            best_score = score
            best = {
                'project_name': pname,
                'score': round(score, 4),
                'title_score': round(tscore, 4),
                'desc_score': round(dscore, 4),
            }
            if score >= 0.999:
                break
    return best


def _reupload_project_video(project_name: str, delete_old=True, old_video_id=None, channel_key=None, log_prefix=''):
    """
    Delete old YouTube video (optional) and reupload using project's rendered assets.
    Returns dict with new upload result.
    """
    project_path, info = _load_project_info_by_name(project_name)
    if not project_path or not info:
        raise Exception(f'Project not found: {project_name}')

    yt_prev = info.get('youtube') or {}
    meta = info.get('metadata') or {}
    final_video = info.get('final_video') or os.path.join(project_path, 'final_video.mp4')
    thumbnail = info.get('thumbnail') or os.path.join(project_path, 'thumbnail.jpg')
    if not os.path.exists(final_video):
        raise Exception(f'final_video missing: {final_video}')

    cfg = load_config()
    ck = (channel_key or yt_prev.get('channel_key') or 'main').strip() or 'main'
    tf = get_token_path_by_key(ck)
    if not tf:
        raise Exception(f'YouTube token not found for channel [{ck}]')

    old_id = (old_video_id or yt_prev.get('videoId') or '').strip()
    if delete_old and old_id:
        try:
            delete_video(old_id, token_file=tf, log_cb=lambda m: print(f'{log_prefix}{m}'))
        except Exception as e:
            # Continue upload even if delete failed; report in response.
            print(f'{log_prefix}Ã¢Å¡Â  delete old video failed: {e}')

    result = upload_video(
        final_video,
        title=(meta.get('title') or 'Untitled')[:100],
        description=meta.get('description', ''),
        thumbnail_path=thumbnail if os.path.exists(thumbnail) else None,
        tags=meta.get('tags', []),
        privacy=cfg.get('privacy', 'public'),
        log_cb=lambda m: print(f'{log_prefix}{m}'),
        token_file=tf
    )

    wd = info.get('youtube_watchdog') or {}
    wd['last_reupload_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
    wd['last_action'] = 'reupload'
    wd['last_status'] = 'reuploaded'
    wd['last_error'] = ''
    wd['reupload_attempts'] = int(wd.get('reupload_attempts', 0)) + 1
    info['youtube_watchdog'] = wd
    info['youtube'] = result
    if 'steps_completed' in info and 'upload' not in info['steps_completed']:
        info['steps_completed'].append('upload')
    _save_project_info(project_path, info)
    return result


def _run_youtube_watchdog_once():
    """Scan uploaded videos from projects, auto reupload unhealthy ones."""
    cfg = load_config()
    if not bool(cfg.get('youtube_watchdog_enabled', False)):
        return {'checked': 0, 'actions': [], 'skipped': 'disabled'}

    stuck_minutes = int(cfg.get('youtube_watchdog_stuck_minutes', 120) or 120)
    max_retries = int(cfg.get('youtube_watchdog_max_retries', 2) or 2)
    min_views_skip = int(cfg.get('youtube_watchdog_min_views_to_skip', 1) or 1)

    actions = []
    checked = 0
    for p in list_projects():
        pname = _project_name_from_info(p)
        yt = p.get('youtube') or {}
        vid = (yt.get('videoId') or '').strip()
        if not pname or not vid:
            continue
        channel_key = (yt.get('channel_key') or 'main').strip() or 'main'
        tf = get_token_path_by_key(channel_key)
        if not tf:
            continue

        checked += 1
        try:
            detail = get_video_detail(vid, token_file=tf)
            healthy, reason = _video_health(detail, stuck_minutes)
            project_path, info = _load_project_info_by_name(pname)
            if not project_path or not info:
                continue
            wd = info.get('youtube_watchdog') or {}
            wd['last_checked_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
            wd['last_reason'] = reason
            wd['last_upload_status'] = (detail or {}).get('upload_status', '')
            wd['last_processing_status'] = (detail or {}).get('processing_status', '')
            wd['last_error'] = ''

            attempts = int(wd.get('reupload_attempts', 0))
            views = int((detail or {}).get('views', 0) or 0)
            can_reupload = (not healthy and attempts < max_retries and views < min_views_skip)

            if can_reupload:
                new_up = _reupload_project_video(
                    pname, delete_old=True, old_video_id=vid,
                    channel_key=channel_key, log_prefix='[watchdog] '
                )
                actions.append({
                    'project': pname,
                    'action': 'reuploaded',
                    'old_video_id': vid,
                    'new_video_id': new_up.get('videoId'),
                    'reason': reason
                })

                # Reload after reupload to avoid clobbering fresh watchdog counters/videoId
                # with stale pre-reupload in-memory info.
                project_path2, info2 = _load_project_info_by_name(pname)
                if project_path2 and info2:
                    wd2 = info2.get('youtube_watchdog') or {}
                    wd2['last_checked_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
                    wd2['last_reason'] = reason
                    wd2['last_upload_status'] = (detail or {}).get('upload_status', '')
                    wd2['last_processing_status'] = (detail or {}).get('processing_status', '')
                    wd2['last_error'] = ''
                    if int(wd2.get('reupload_attempts', 0) or 0) <= attempts:
                        wd2['reupload_attempts'] = attempts + 1
                    info2['youtube_watchdog'] = wd2
                    info2['youtube'] = new_up or info2.get('youtube') or {}
                    _save_project_info(project_path2, info2)
                continue
            else:
                if not healthy:
                    wd['last_status'] = 'needs_manual_check'
                    if views >= min_views_skip:
                        wd['last_error'] = f'skip: views={views} >= {min_views_skip}'
                    elif attempts >= max_retries:
                        wd['last_error'] = f'skip: attempts={attempts} >= {max_retries}'
            info['youtube_watchdog'] = wd
            _save_project_info(project_path, info)
        except Exception as e:
            actions.append({'project': pname, 'action': 'error', 'error': str(e)[:300]})

    return {'checked': checked, 'actions': actions, 'stuck_minutes': stuck_minutes}


def _youtube_watchdog_loop():
    while True:
        try:
            cfg = load_config()
            interval_min = int(cfg.get('youtube_watchdog_interval_min', 15) or 15)
            if interval_min < 3:
                interval_min = 3
            if bool(cfg.get('youtube_watchdog_enabled', False)):
                if _YT_WATCHDOG_LOCK.acquire(blocking=False):
                    try:
                        _YT_WATCHDOG_STATE['running'] = True
                        result = _run_youtube_watchdog_once()
                        _YT_WATCHDOG_STATE['last_run_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
                        _YT_WATCHDOG_STATE['last_actions'] = result.get('actions', [])
                        _YT_WATCHDOG_STATE['last_summary'] = (
                            f"checked={result.get('checked',0)} actions={len(result.get('actions', []))}"
                        )
                    finally:
                        _YT_WATCHDOG_STATE['running'] = False
                        _YT_WATCHDOG_LOCK.release()
            time.sleep(interval_min * 60)
        except Exception as e:
            _YT_WATCHDOG_STATE['running'] = False
            _YT_WATCHDOG_STATE['last_summary'] = f'watchdog error: {str(e)[:200]}'
            time.sleep(60)

# Ã¢â€â‚¬Ã¢â€â‚¬ Serve index.html Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
@app.route('/')
def index():
    return send_from_directory('.', 'index.html')

@app.route('/favicon.ico')
def favicon():
    return '', 204


def _resolve_tts_ref_voice(ref_voice: str) -> str:
    """Resolve TTS reference voice path; relative paths are under project root."""
    ref_voice = (ref_voice or 'sample.WAV').strip() or 'sample.WAV'
    if os.path.isabs(ref_voice):
        return ref_voice
    return os.path.join(os.getcwd(), ref_voice)


def _default_tts_test_ref_voice() -> str:
    """Pick default clone sample for TTS test endpoint."""
    for name in ('ai_vy.wav', 'ai_vy.WAV', 'sample.WAV', 'sample.wav'):
        p = os.path.join(os.getcwd(), name)
        if os.path.exists(p):
            return p
    return _resolve_tts_ref_voice('sample.WAV')


def _load_tts_test_text() -> str:
    """Load test text from reftext.txt when available."""
    ref_txt = os.path.join(os.getcwd(), 'reftext.txt')
    if os.path.exists(ref_txt):
        try:
            content = Path(ref_txt).read_text(encoding='utf-8', errors='ignore').strip()
            if content:
                return content
        except Exception:
            pass
    return 'Xin chao, day la bai test giong noi. Minh la MiuBon.'


def _normalize_ref_voice_for_tts(ref_voice: str):
    """Convert reference voice to a temp 24k mono WAV for VieNeu/XTTS clone stability."""
    src = _resolve_tts_ref_voice(ref_voice)
    if not os.path.exists(src):
        return src, None

    fd, tmp_wav = tempfile.mkstemp(suffix='.wav')
    os.close(fd)
    try:
        from modules.helpers import run_cmd
        run_cmd([
            'ffmpeg', '-y', '-i', src,
            '-ar', '24000', '-ac', '1', '-acodec', 'pcm_s16le', tmp_wav
        ], capture_output=True, check=True)
        return tmp_wav, tmp_wav
    except Exception:
        try:
            if os.path.exists(tmp_wav):
                os.unlink(tmp_wav)
        except Exception:
            pass
        return src, None

# Ã¢â€â‚¬Ã¢â€â‚¬ Health Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
@app.route('/api/health')
def health():
    cfg = load_config()
    
    capcut_ok = False
    import urllib.request
    try:
        req = urllib.request.Request('http://localhost:8080/v2/speakers')
        with urllib.request.urlopen(req, timeout=0.5) as response:
            capcut_ok = response.status == 200
    except Exception:
        pass
        
    dl_status = get_download_status()
    yt_status = check_auth_status()
    tk_browser = tiktok_auth_status()
    tk_api = tiktok_api_status(cfg)
    tk_status = {
        **tk_browser,
        'browser': tk_browser,
        'api': tk_api,
        'ok': bool(tk_browser.get('ok') or tk_api.get('ok')),
    }
    fb_status = facebook_reels_status(cfg)
    yt_queue = get_youtube_upload_queue_status()
    return jsonify({
        'status': 'ok',
        'test_9router': True,
        'capcut_ok': capcut_ok,
        'ffmpeg_encoder': cfg.get('ffmpeg_encoder', 'GPU (NVENC)' if cfg.get('ffmpeg_encoder', 'h264_nvenc') == 'h264_nvenc' else 'CPU (libx264)'),
        'douyin': dl_status,
        'youtube': yt_status,
        'youtube_upload_queue': {
            'count': yt_queue.get('count', 0),
            'quota_block_seconds': yt_queue.get('quota_block_seconds', 0),
            'worker': yt_queue.get('worker', {}),
        },
        'tiktok': tk_status,
        'facebook': fb_status,
        'jobs': JOBS.stats(),
        'active_jobs': JOBS.active_jobs(),
        'gpu_limiter': get_gpu_heavy_limiter_state(),
        'download_limiter': get_download_limiter_state(),
    })


@app.route('/api/youtube/upload-queue/status')
def youtube_upload_queue_status():
    return jsonify(get_youtube_upload_queue_status())

# Ã¢â€â‚¬Ã¢â€â‚¬ Config Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
@app.route('/api/config', methods=['GET'])
def get_config():
    cfg = load_config()
    cfg.setdefault('batch_pipeline_concurrency', 2)
    cfg.setdefault('download_concurrency', 2)
    cfg.setdefault('gpu_heavy_concurrency', int(cfg.get('max_concurrent_gpu', 1) or 1))
    cfg.setdefault('upload_fifo_strict', True)
    cfg.setdefault('pipeline_retry_max', 2)
    cfg.setdefault('pipeline_skip_after_retry_exhausted', True)
    cfg.setdefault('auto_start_capcut_tts', True)
    cfg.setdefault('thumbnail_mode', 'smart_frame')
    cfg.setdefault('ai_thumbnail_provider', 'cloudflare')
    cfg.setdefault('ai_thumbnail_model', '@cf/runwayml/stable-diffusion-v1-5-img2img')
    cfg.setdefault('ai_thumbnail_timeout_sec', 90)
    cfg.setdefault('ai_thumbnail_style', '')
    cfg.setdefault('ai_thumbnail_api_key', '')
    cfg.setdefault('ai_thumbnail_cloudflare_account_id', '')
    cfg.setdefault('ai_thumbnail_cloudflare_api_token', '')
    cfg.setdefault('ai_thumbnail_cloudflare_mode', 'img2img')
    cfg.setdefault('ai_thumbnail_img2img_strength', 0.38)
    cfg.setdefault('ai_thumbnail_steps', 16)
    # Mask API key for security
    safe = dict(cfg)
    if safe.get('api_key'):
        k = safe['api_key']
        safe['api_key_masked'] = k[:8] + '...' + k[-4:] if len(k) > 12 else '***'
    if safe.get('ai_thumbnail_api_key'):
        aik = str(safe['ai_thumbnail_api_key'])
        safe['ai_thumbnail_api_key_masked'] = (aik[:4] + '...' + aik[-3:]) if len(aik) > 8 else '***'
        safe['ai_thumbnail_api_key'] = ''
    if safe.get('ai_thumbnail_cloudflare_api_token'):
        cft = str(safe['ai_thumbnail_cloudflare_api_token'])
        safe['ai_thumbnail_cloudflare_api_token_masked'] = (cft[:4] + '...' + cft[-3:]) if len(cft) > 8 else '***'
        safe['ai_thumbnail_cloudflare_api_token'] = ''
    if safe.get('tiktok_api_client_secret'):
        sk = str(safe['tiktok_api_client_secret'])
        safe['tiktok_api_client_secret_masked'] = (sk[:4] + '...' + sk[-3:]) if len(sk) > 8 else '***'
    if safe.get('facebook_app_secret'):
        fbs = str(safe['facebook_app_secret'])
        safe['facebook_app_secret_masked'] = (fbs[:4] + '...' + fbs[-3:]) if len(fbs) > 8 else '***'
    if safe.get('facebook_page_access_token'):
        fk = str(safe['facebook_page_access_token'])
        safe['facebook_page_access_token_masked'] = (fk[:4] + '...' + fk[-3:]) if len(fk) > 8 else '***'
    return jsonify(safe)

@app.route('/api/config', methods=['POST'])
def set_config():
    data = request.json
    cfg = load_config()
    cfg.update(data)
    save_config(cfg)
    sync_gpu_heavy_limit_from_config(cfg)
    sync_download_limit_from_config(cfg)
    return jsonify({'ok': True})

@app.route('/api/tts/test', methods=['POST'])
def test_tts():
    """Test TTS engine with sample text and return audio for preview."""
    import tempfile, os
    from modules.tts_engine import generate_tts_audio
    data = request.json or {}
    engine = data.get('engine', 'gemini')
    ref_voice = data.get('ref_voice', '')
    vieneu_voice = data.get('vieneu_voice', '')
    vieneu_mode = data.get('vieneu_mode', 'preset')
    capcut_voice = data.get('capcut_voice', '')
    auto_adjust_tts_speed = data.get('auto_adjust_tts_speed', None)
    api_key = data.get('api_key', '')
    tts_speed = data.get('tts_speed', 1.0)
    tts_pitch = data.get('tts_pitch', 1.0)
    tts_volume = data.get('tts_volume', 1.0)
    norm_ref_voice = None
    tmp_ref_cleanup = None

    # Test text in SRT format (prefer reftext.txt if present)
    sample_text = _load_tts_test_text()
    test_text = f"1\n00:00:00,000 --> 00:00:06,000\n{sample_text}\n"

    logs = []
    def log_cb(msg):
        logs.append(str(msg))

    try:
        if not (ref_voice or '').strip():
            ref_voice = _default_tts_test_ref_voice()
            log_cb(f'Test default sample: {ref_voice}')

        if engine in ('vieneu', 'xtts'):
            is_vieneu_preset = (engine == 'vieneu' and vieneu_mode == 'preset')
            if not is_vieneu_preset:
                norm_ref_voice, tmp_ref_cleanup = _normalize_ref_voice_for_tts(ref_voice)
                log_cb(f'ðŸ—£ï¸ Test clone sample: {norm_ref_voice}')
            else:
                log_cb('ðŸŽ¤ Testing VieNeu Preset voice')

        # Generate TTS
        with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as f:
            tmp_out = f.name
        
        ok = generate_tts_audio(
            srt_content=test_text,
            output_mp3=tmp_out,
            voice='Zephyr',
            api_key=api_key,
            log_cb=log_cb,
            batch_size=1,
            ref_voice=norm_ref_voice if (engine == 'xtts' or (engine == 'vieneu' and vieneu_mode == 'clone')) else None,
            engine=engine,
            tts_speed=tts_speed,
            tts_pitch=tts_pitch,
            tts_volume=tts_volume,
            vieneu_voice=vieneu_voice,
            vieneu_mode=vieneu_mode,
            auto_adjust_tts_speed=auto_adjust_tts_speed,
            capcut_voice=capcut_voice
        )
        
        if ok and os.path.exists(tmp_out):
            # Return audio file
            response = send_file(tmp_out, mimetype='audio/mpeg')
            # Schedule cleanup
            cleanup_files = [tmp_out]
            if tmp_ref_cleanup:
                cleanup_files.append(tmp_ref_cleanup)
            threading.Thread(
                target=lambda: (time.sleep(60), [os.unlink(p) for p in cleanup_files if os.path.exists(p)]),
                daemon=True
            ).start()
            return response
        else:
            return jsonify({'ok': False, 'error': 'TTS generation failed', 'logs': logs}), 500
    except Exception as e:
        if tmp_ref_cleanup and os.path.exists(tmp_ref_cleanup):
            try:
                os.unlink(tmp_ref_cleanup)
            except Exception:
                pass
        return jsonify({'ok': False, 'error': str(e), 'logs': logs}), 500

@app.route('/api/check-api-key', methods=['POST'])
def check_api_key():
    """Quick test a Gemini API key or ADC by making a lightweight API call."""
    data = request.json or {}
    key = data.get('api_key', '').strip()
    use_adc = data.get('use_adc', False)

    try:
        from modules.helpers import create_genai_client
        if use_adc:
            # Explicit ADC test Ã¢â‚¬â€ don't fall back to API key
            try:
                client = create_genai_client()
                resp = client.models.generate_content(
                    model='gemini-2.5-flash',
                    contents='Return the exact model identifier/name you are running as. Reply with only the model identifier.'
                )
                text = resp.text.strip()
                return jsonify({
                    'ok': True,
                    'response': text[:100],
                    'message': f'Ã¢Å“â€¦ Vertex AI (ADC) works! Using GCP credits (no rate limit)'
                })
            except Exception as adc_err:
                err_msg = str(adc_err)
                if '404' in err_msg or 'NOT_FOUND' in err_msg or 'Publisher Model' in err_msg:
                    hint = 'Ã¢â€ â€™ ADC Ã„â€˜ÃƒÂ£ OK nhÃ†Â°ng model khÃƒÂ´ng khÃ¡ÂºÂ£ dÃ¡Â»Â¥ng Ã¡Â»Å¸ region nÃƒÂ y. DÃƒÂ¹ng model `gemini-2.5-flash` (Ã„â€˜ÃƒÂ£ cÃ¡ÂºÂ­p nhÃ¡ÂºÂ­t) vÃƒÂ  thÃ¡Â»Â­ lÃ¡ÂºÂ¡i sau 1-2 phÃƒÂºt.'
                elif '403' in err_msg or 'PERMISSION_DENIED' in err_msg:
                    hint = 'Ã¢â€ â€™ BÃ¡ÂºÂ­t Vertex AI API: Google Cloud Console Ã¢â€ â€™ APIs & Services Ã¢â€ â€™ Enable "Vertex AI API"'
                elif 'Could not automatically determine' in err_msg or 'project' in err_msg.lower():
                    hint = 'Ã¢â€ â€™ ChÃ¡ÂºÂ¡y: gcloud config set project YOUR_PROJECT_ID'
                elif 'credentials' in err_msg.lower() or 'auth' in err_msg.lower():
                    hint = 'Ã¢â€ â€™ ChÃ¡ÂºÂ¡y: gcloud auth application-default login'
                else:
                    hint = f'Error: {err_msg[:150]}'
                return jsonify({
                    'ok': False,
                    'error': f'Ã¢ÂÅ’ ADC/Vertex AI failed!\n{hint}'
                })

        if not key:
            # No explicit key Ã¢â‚¬â€ try ADC first, then config key
            try:
                client = create_genai_client()
                resp = client.models.generate_content(
                    model='gemini-2.5-flash',
                    contents='Reply with only the word: OK'
                )
                return jsonify({
                    'ok': True,
                    'response': resp.text.strip()[:100],
                    'message': f'Ã¢Å“â€¦ Vertex AI (ADC) works! Using GCP credits'
                })
            except Exception:
                cfg = load_config()
                key = cfg.get('api_key', '')
                if not key:
                    return jsonify({'ok': False, 'error': 'Ã¢ÂÅ’ No API key and ADC not configured'})

        # Test with API key
        from google import genai
        client = genai.Client(api_key=key)
        resp = client.models.generate_content(
            model='gemini-2.5-flash',
            contents='Return the exact model identifier/name you are running as. Reply with only the model identifier.'
        )
        text = resp.text.strip()
        return jsonify({
            'ok': True,
            'response': text[:100],
            'message': f'Ã¢Å“â€¦ API key is valid! (tested with gemini-2.5-flash)'
        })
    except Exception as e:
        err = str(e)
        if '401' in err or 'UNAUTHENTICATED' in err:
            msg = 'Ã¢ÂÅ’ Invalid API key (401 Unauthorized)'
        elif '403' in err or 'PERMISSION_DENIED' in err:
            msg = 'Ã¢ÂÅ’ API key lacks permission (403 Forbidden)'
        elif '429' in err or 'RESOURCE_EXHAUSTED' in err:
            msg = 'Ã¢Å¡Â Ã¯Â¸Â API key is valid but rate-limited (429). Try again later.'
        elif '404' in err:
            msg = 'Ã¢Å¡Â Ã¯Â¸Â Model not found, but key may be valid. Check model access.'
        else:
            msg = f'Ã¢ÂÅ’ Error: {err[:150]}'
        return jsonify({'ok': False, 'error': msg})

# Ã¢â€â‚¬Ã¢â€â‚¬ Pipeline Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

@app.route('/api/translation/test', methods=['POST'])
def test_translation_api():
    """Quick test selected translation provider (including 9router)."""
    data = request.json or {}
    cfg = load_config()
    merged = dict(cfg)
    merged.update(data)

    try:
        from modules.translator import test_translation_provider
        result = test_translation_provider(
            translation_provider=merged.get('translation_provider', '9router'),
            api_key=merged.get('api_key', ''),
            gemini_model=merged.get('gemini_model', 'gemini-2.5-flash'),
            source_lang=merged.get('source_lang', 'zh'),
            target_lang=merged.get('target_lang', 'vi'),
            provider_order=merged.get('translation_provider_order', None),
            local_model=merged.get('local_translation_model', 'qwen3:8b'),
            local_api_url=merged.get('local_translation_api_url', 'http://127.0.0.1:11434/api/chat'),
            local_timeout=merged.get('local_translation_timeout', 60),
            azure_translator_key=merged.get('azure_translator_key', ''),
            azure_translator_endpoint=merged.get('azure_translator_endpoint', 'https://api.cognitive.microsofttranslator.com'),
            azure_translator_region=merged.get('azure_translator_region', ''),
            deepl_api_key=merged.get('deepl_api_key', ''),
            deepl_api_url=merged.get('deepl_api_url', 'https://api-free.deepl.com/v2/translate'),
            ninerouter_url=merged.get('ninerouter_url', 'http://127.0.0.1:20128'),
            ninerouter_key=merged.get('ninerouter_key', ''),
            ninerouter_model=merged.get('ninerouter_model', ''),
            ninerouter_timeout=merged.get('ninerouter_timeout', 60)
        )
        return jsonify(result)
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)[:300]})


@app.route('/api/douyin/preview', methods=['POST'])
def douyin_preview():
    data = request.json or {}
    urls = data.get('urls', [])
    previews = []
    
    # Check existing projects for these URLs
    existing_projects = {}
    if os.path.exists(PROJECTS_DIR):
        for p in os.listdir(PROJECTS_DIR):
            if not os.path.isdir(os.path.join(PROJECTS_DIR, p)): continue
            meta_path = os.path.join(PROJECTS_DIR, p, 'metadata.json')
            if os.path.exists(meta_path):
                try:
                    with open(meta_path, 'r', encoding='utf-8') as f:
                        meta = json.load(f)
                        url = meta.get('url', '').strip()
                        if url: existing_projects[url] = p
                except:
                    pass
                    
    for url in urls:
        p = existing_projects.get(url, None)
        previews.append({'url': url, 'project_name': p})
        
    return jsonify({'previews': previews})

@app.route('/api/pipeline/start', methods=['POST'])
def start_pipeline():
    data = request.json or {}
    raw_input = data.get('url', '').strip()
    if not raw_input:
        return jsonify({'error': 'URL or text required'}), 400
    cfg_overrides = data.get('config', None)
    job_id = run_full_pipeline(raw_input, cfg_overrides)
    return jsonify({'job_id': job_id})


def _wait_job_done_or_error(job_id, poll_sec=3):
    while True:
        sub = JOBS.get(job_id, {})
        if sub.get('status') in ('done', 'error'):
            return sub
        time.sleep(poll_sec)


def _load_retry_project_from_job(sub_job):
    try:
        result = sub_job.get('result') if isinstance(sub_job, dict) else None
        if not isinstance(result, dict):
            return None, None
        project_dir = str(result.get('project_dir') or '').strip()
        if not project_dir:
            return None, None
        info_path = os.path.join(project_dir, 'info.json')
        if not os.path.isfile(info_path):
            return None, None
        with open(info_path, 'r', encoding='utf-8') as f:
            info = json.load(f)
        return project_dir, info
    except Exception:
        return None, None



def _clean_series_context(ctx):
    """Keep only safe per-URL series metadata from the UI/grouping step."""
    if not isinstance(ctx, dict):
        return {}
    out = {}
    for key in ('series_name_vi', 'series_name', 'series_folder', 'episode_no', 'episode_min', 'episode_max', 'source'):
        val = ctx.get(key)
        if val is None:
            continue
        if key.startswith('episode_'):
            try:
                out[key] = int(val)
            except Exception:
                sval = str(val).strip()
                if sval:
                    out[key] = sval
        else:
            sval = str(val).strip()
            if sval:
                out[key] = sval[:240]
    return out


def _safe_episode_int(value):
    try:
        n = int(value)
        return n if n > 0 else None
    except Exception:
        return None


def _infer_episode_map_for_group(group):
    """
    Build {url: episode_no} from one saved AI group.
    Uses strict interpolation and strict head/tail extrapolation only when anchors are +1 continuous.
    """
    if not isinstance(group, dict):
        return {}
    ordered_urls = []
    for u in (group.get('urls') or []):
        su = str(u or '').strip()
        if su:
            ordered_urls.append(su)
    if not ordered_urls:
        return {}

    by_url_ep = {}
    videos = group.get('videos') or []
    if isinstance(videos, list):
        for v in videos:
            if not isinstance(v, dict):
                continue
            su = str(v.get('url') or '').strip()
            if not su:
                continue
            ep = _safe_episode_int(v.get('episode_no'))
            if ep is not None:
                by_url_ep[su] = ep

    known = []
    for i, su in enumerate(ordered_urls):
        ep = _safe_episode_int(by_url_ep.get(su))
        if ep is not None:
            known.append((i, ep))
    if len(known) < 2:
        return by_url_ep

    idx_to_ep = {i: ep for i, ep in known}

    # Interpolate between anchors only when strict +1 continuity holds.
    for (i1, e1), (i2, e2) in zip(known, known[1:]):
        idx_gap = i2 - i1
        ep_gap = e2 - e1
        if idx_gap <= 1 or ep_gap != idx_gap:
            continue
        for j in range(i1 + 1, i2):
            idx_to_ep.setdefault(j, e1 + (j - i1))

    # Head extrapolation with strict continuity.
    i0, e0 = known[0]
    i1, e1 = known[1]
    if i0 > 0 and (i1 - i0) > 0 and (e1 - e0) == (i1 - i0):
        for j in range(i0 - 1, -1, -1):
            cand = e0 - (i0 - j)
            if cand <= 0:
                break
            idx_to_ep.setdefault(j, cand)

    # Tail extrapolation with strict continuity.
    il0, el0 = known[-2]
    il1, el1 = known[-1]
    if il1 < (len(ordered_urls) - 1) and (il1 - il0) > 0 and (el1 - el0) == (il1 - il0):
        for j in range(il1 + 1, len(ordered_urls)):
            cand = el1 + (j - il1)
            if cand <= 0:
                continue
            idx_to_ep.setdefault(j, cand)

    out = {}
    for i, su in enumerate(ordered_urls):
        ep = _safe_episode_int(idx_to_ep.get(i))
        if ep is not None:
            out[su] = ep
    return out


def _load_contexts_from_latest_group(urls):
    """Fallback context resolver from latest_ai_group.json for URLs missing UI context."""
    targets = [str(u or '').strip() for u in (urls or []) if str(u or '').strip()]
    if not targets:
        return {}
    p = BASE_DIR / 'latest_ai_group.json'
    if not p.exists():
        return {}
    try:
        data = json.loads(p.read_text(encoding='utf-8'))
    except Exception:
        return {}
    groups = data.get('groups') or []
    if not isinstance(groups, list):
        return {}

    target_set = set(targets)
    out = {}
    for g in groups:
        if not isinstance(g, dict):
            continue
        urls_g = [str(u or '').strip() for u in (g.get('urls') or []) if str(u or '').strip()]
        if not urls_g:
            continue
        overlap = target_set.intersection(urls_g)
        if not overlap:
            continue

        ep_map = _infer_episode_map_for_group(g)
        base_ctx = _clean_series_context({
            'series_name_vi': g.get('series_name_vi') or g.get('series_name') or '',
            'series_name': g.get('series_name') or '',
            'series_folder': g.get('folder') or '',
            'episode_min': g.get('episode_min'),
            'episode_max': g.get('episode_max'),
            'source': 'latest_ai_group',
        })
        if not base_ctx:
            continue

        for u in overlap:
            ctx = dict(base_ctx)
            ep = _safe_episode_int(ep_map.get(u))
            if ep is not None:
                ctx['episode_no'] = ep
            prev = out.get(u)
            if not prev:
                out[u] = ctx
                continue
            # Prefer context carrying episode_no.
            if _safe_episode_int(ctx.get('episode_no')) is not None and _safe_episode_int(prev.get('episode_no')) is None:
                out[u] = ctx
    return out


def _normalize_queue_contexts(contexts, urls):
    """Return {url: context} for URLs that have series metadata."""
    out = {}
    if isinstance(contexts, dict):
        for url in urls:
            ctx = _clean_series_context(contexts.get(url))
            if ctx:
                out[url] = ctx
    elif isinstance(contexts, list):
        for item in contexts:
            if not isinstance(item, dict):
                continue
            url = str(item.get('url') or '').strip()
            if not url or url not in urls:
                continue
            ctx = _clean_series_context(item.get('context') or item)
            if ctx:
                out[url] = ctx

    # Backend fallback: if UI context is missing (page reload / manual queue),
    # try resolving series context from latest_ai_group.json by URL.
    auto_ctx_map = _load_contexts_from_latest_group(urls)
    for url in urls:
        fallback = _clean_series_context(auto_ctx_map.get(url))
        if not fallback:
            continue
        cur = _clean_series_context(out.get(url))
        if not cur:
            out[url] = fallback
            continue
        merged = dict(cur)
        for k, v in fallback.items():
            if k not in merged:
                merged[k] = v
                continue
            curv = merged.get(k)
            missing = (curv is None) or (isinstance(curv, str) and not curv.strip())
            if k.startswith('episode_'):
                missing = _safe_episode_int(curv) is None
            if missing:
                merged[k] = v
        out[url] = _clean_series_context(merged)
    return out


def _series_context_to_cfg_overrides(series_context):
    ctx = _clean_series_context(series_context)
    if not ctx:
        return None
    name = str(ctx.get('series_name_vi') or ctx.get('series_name') or '').strip()
    folder = str(ctx.get('series_folder') or '').strip()
    overrides = {'series_context': ctx}
    if name:
        overrides['youtube_title_mode'] = 'series_template'
        overrides['youtube_series_name'] = name
    if folder:
        overrides['youtube_series_folder'] = folder
    if ctx.get('episode_no') is not None:
        overrides['youtube_episode_no'] = ctx.get('episode_no')
    if ctx.get('episode_min') is not None:
        overrides['youtube_episode_min'] = ctx.get('episode_min')
    if ctx.get('episode_max') is not None:
        overrides['youtube_episode_max'] = ctx.get('episode_max')
    return overrides

def _run_pipeline_with_single_retry(
    url,
    series_context=None,
    on_job_start=None,
    max_attempts=2,
    run_mode='queued',
    disable_auto_upload=False,
):
    """
    Run pipeline with configurable retry count.
    On failure between attempts:
      1) Prefer resume on existing project.
      2) Otherwise fallback to rerun URL.
    """
    context_clean = _clean_series_context(series_context)
    cfg_overrides = _series_context_to_cfg_overrides(context_clean) or {}
    if disable_auto_upload:
        cfg_overrides.update({
            'auto_upload': False,
            'auto_upload_tiktok': False,
            'auto_upload_facebook_reels': False,
        })

    try:
        max_attempts = int(max_attempts or 2)
    except Exception:
        max_attempts = 2
    max_attempts = max(1, max_attempts)

    attempt_rows = []
    first_job_id = None
    first_error = None
    last_job_id = None
    last_error = None
    retry_mode = None

    def _should_rerun_url(prev_sub):
        err = str((prev_sub or {}).get('error') or (prev_sub or {}).get('message') or '')
        err_l = err.lower()
        markers = (
            'cannot download video',
            'download file failed',
            'no source url',
            'incompleteread',
            'host unreachable',
            'failed to establish a new connection',
            'connection broken',
        )
        return any(m in err_l for m in markers)

    for attempt in range(1, max_attempts + 1):
        if attempt == 1:
            job_id = run_full_pipeline(url, cfg_overrides, run_mode=run_mode)
            mode = None
        else:
            prev_sub = attempt_rows[-1]['sub']
            project_dir, info = (None, None) if _should_rerun_url(prev_sub) else _load_retry_project_from_job(prev_sub)
            if project_dir and info:
                mode = 'resume_project'
                job_id = resume_pipeline(project_dir, info, cfg_overrides, run_mode=run_mode)
            else:
                mode = 'rerun_url'
                job_id = run_full_pipeline(url, cfg_overrides, run_mode=run_mode)
            retry_mode = mode

        if attempt == 1:
            first_job_id = job_id
        if callable(on_job_start):
            on_job_start(job_id)

        sub = _wait_job_done_or_error(job_id)
        row = {'attempt': attempt, 'job_id': job_id, 'mode': mode, 'sub': sub}
        attempt_rows.append(row)

        if sub.get('status') == 'done':
            return {
                'ok': True,
                'job_id': job_id,
                'result': sub.get('result'),
                'series_context': context_clean,
                'retry_attempted': attempt > 1,
                'retry_mode': retry_mode,
                'first_job_id': first_job_id,
                'retry_job_id': job_id if attempt > 1 else None,
                'first_error': first_error,
                'retry_error': None,
                'attempts_used': attempt,
                'attempts': [
                    {
                        'attempt': r['attempt'],
                        'job_id': r['job_id'],
                        'mode': r['mode'],
                        'status': (r['sub'] or {}).get('status'),
                        'error': (r['sub'] or {}).get('error') or (r['sub'] or {}).get('message'),
                    } for r in attempt_rows
                ],
            }

        err = sub.get('error') or sub.get('message') or 'Unknown'
        if attempt == 1:
            first_error = err
        last_job_id = job_id
        last_error = err

    return {
        'ok': False,
        'job_id': last_job_id,
        'result': None,
        'series_context': context_clean,
        'retry_attempted': max_attempts > 1,
        'retry_mode': retry_mode,
        'first_job_id': first_job_id,
        'retry_job_id': last_job_id if max_attempts > 1 else None,
        'first_error': first_error,
        'retry_error': last_error,
        'error': last_error,
        'attempts_used': max_attempts,
        'attempts': [
            {
                'attempt': r['attempt'],
                'job_id': r['job_id'],
                'mode': r['mode'],
                'status': (r['sub'] or {}).get('status'),
                'error': (r['sub'] or {}).get('error') or (r['sub'] or {}).get('message'),
            } for r in attempt_rows
        ],
    }

def _queue_series_counts(contexts):
    counts = {}
    if not isinstance(contexts, dict):
        return counts
    for ctx in contexts.values():
        if not isinstance(ctx, dict):
            continue
        name = str(
            ctx.get('series_name_vi') or ctx.get('series_name') or
            ctx.get('series_title') or ''
        ).strip()
        if not name:
            continue
        counts[name] = counts.get(name, 0) + 1
    return counts


def _queue_summary(queue_id, job):
    q = (job or {}).get('queue') or {}
    urls = q.get('urls') or []
    projects = q.get('projects') or []
    items = urls or projects
    contexts = q.get('contexts') or {}
    runtime_items = q.get('runtime_items') or []
    total = int(q.get('total') or len(items) or 0)
    completed = int(q.get('completed') or 0)
    current_item = None
    if items and completed < len(items):
        current_item = items[completed]
    runtime_counts = {}
    for it in runtime_items:
        st = str((it or {}).get('status') or 'unknown')
        runtime_counts[st] = runtime_counts.get(st, 0) + 1
    return {
        'id': queue_id,
        'status': (job or {}).get('status'),
        'paused': bool((job or {}).get('paused')),
        'progress': int((job or {}).get('progress') or 0),
        'message': (job or {}).get('message') or '',
        'type': 'projects' if projects else 'urls',
        'total': total,
        'completed': completed,
        'remaining': max(0, total - completed),
        'current_job': q.get('current_job'),
        'current_item': current_item,
        'results_count': len(q.get('results') or []),
        'errors_count': len(q.get('errors') or []),
        'contexts_count': len(contexts) if isinstance(contexts, dict) else 0,
        'series_counts': _queue_series_counts(contexts),
        'runtime_counts': runtime_counts,
        'next_expected_upload': int(q.get('next_expected_upload', 0) or 0),
        'pipeline_concurrency': int(q.get('pipeline_concurrency', 1) or 1),
        'download_concurrency': int(q.get('download_concurrency', 2) or 2),
        'retry_max': int(q.get('retry_max', 2) or 2),
        'upload_fifo_strict': bool(q.get('upload_fifo_strict', True)),
        'created': (job or {}).get('_created', 0),
    }


def _list_pipeline_queue_summaries(include_done=False):
    statuses = {'running', 'queued', 'paused'}
    if include_done:
        statuses.update({'done', 'error'})
    rows = []
    for qid, job in list(JOBS._data.items()):
        if not isinstance(job, dict) or not job.get('queue'):
            continue
        if job.get('status') not in statuses:
            continue
        rows.append(_queue_summary(qid, job))
    rows.sort(key=lambda r: (r.get('status') != 'running', r.get('status') != 'paused', -float(r.get('created') or 0)))
    return rows



def _set_queue_cancelled(queue_id):
    job = JOBS.get(queue_id)
    if not job or not job.get('queue'):
        return None
    if job.get('status') in ('done', 'error'):
        return job
    job['paused'] = False
    job['status'] = 'cancelled'
    job['message'] = 'Queue cancelled by user'
    return job

@app.route('/api/pipeline/queue/<queue_id>/cancel', methods=['POST'])
def cancel_pipeline_queue(queue_id):
    job = _set_queue_cancelled(queue_id)
    if not job:
        return jsonify({'error': 'Queue not found'}), 404
    return jsonify({'ok': True, 'queue': _queue_summary(queue_id, job)})


def _set_queue_paused(queue_id, paused: bool):
    job = JOBS.get(queue_id)
    if not job or not job.get('queue'):
        return None
    if job.get('status') in ('done', 'error'):
        return job
    job['paused'] = bool(paused)
    if paused:
        job['status'] = 'paused'
        job['message'] = 'Queue paused - current item will finish, then queue will wait.'
    else:
        job['status'] = 'running'
        job['message'] = (job.get('message') or '').replace('Queue paused - ', '') or 'Queue resumed'
    return job


def _wait_queue_if_paused(queue_id, save_cb=None):
    marked = False
    while True:
        job = JOBS.get(queue_id)
        if not job or not job.get('paused'):
            if marked and job and job.get('status') == 'paused':
                job['status'] = 'running'
                job['message'] = 'Queue resumed'
                if callable(save_cb):
                    save_cb(queue_id)
            return
        job['status'] = 'paused'
        q = job.get('queue') or {}
        total = q.get('total') or 0
        completed = q.get('completed') or 0
        job['message'] = f'Queue paused at {completed}/{total}. Waiting to resume...'
        if callable(save_cb):
            save_cb(queue_id)
        marked = True
        time.sleep(2)


def _start_batch_pipeline_from_urls(urls: list, start_from: int = 0, contexts=None):
    seen = set()
    unique = []
    for raw in (urls or []):
        u = str(raw or '').strip()
        if not u or u in seen:
            continue
        unique.append(u)
        seen.add(u)
    if not unique:
        raise ValueError('No URLs to queue')
    try:
        start_from = int(start_from or 0)
    except Exception:
        start_from = 0
    if start_from < 0:
        start_from = 0

    cfg = load_config()
    sync_gpu_heavy_limit_from_config(cfg)
    download_concurrency = sync_download_limit_from_config(cfg)
    context_by_url = _normalize_queue_contexts(contexts, unique)
    pipeline_concurrency = max(1, int(cfg.get('batch_pipeline_concurrency', 2) or 2))
    retry_max = max(1, int(cfg.get('pipeline_retry_max', 2) or 2))
    skip_after_retry_exhausted = bool(cfg.get('pipeline_skip_after_retry_exhausted', True))
    strict_fifo = bool(cfg.get('upload_fifo_strict', True))
    queue_id = str(uuid.uuid4())[:8]
    runtime_items = []
    for idx, url in enumerate(unique):
        runtime_items.append({
            'index': idx,
            'url': url,
            'context': context_by_url.get(url) or {},
            'status': 'waiting',
            'status_text': 'Waiting',
            'attempts_used': 0,
            'job_id': None,
            'project_dir': None,
            'project_name': None,
            'upload_status': 'pending',
            'upload_result': None,
            'error': None,
            'updated_at': time.strftime('%Y-%m-%d %H:%M:%S'),
        })
    JOBS[queue_id] = {
        'status': 'running', 'progress': 0,
        'message': (
            f'Queue: 0/{len(unique)} done | pipeline x{pipeline_concurrency} | '
            f'download x{download_concurrency} | gpu x{sync_gpu_heavy_limit_from_config(cfg)}'
        ),
        'result': None, 'error': None, 'paused': False,
        'queue': {
            'urls': unique,
            'contexts': context_by_url,
            'total': len(unique),
            'completed': 0,
            'current_job': None,
            'results': [],
            'errors': [],
            'runtime_items': runtime_items,
            'next_expected_upload': max(0, start_from),
            'upload_fifo_strict': strict_fifo,
            'retry_max': retry_max,
            'pipeline_concurrency': pipeline_concurrency,
            'download_concurrency': download_concurrency,
            'skip_after_retry_exhausted': skip_after_retry_exhausted,
        }
    }

    def _save_queue_state(qid):
        try:
            job = JOBS.get(qid)
            if not job:
                return
            q = job.get('queue', {})
            state = {
                'queue_id': qid,
                'status': job.get('status'),
                'paused': bool(job.get('paused')),
                'progress': job.get('progress'),
                'message': job.get('message'),
                'urls': q.get('urls', []),
                'contexts': q.get('contexts', {}),
                'total': q.get('total', 0),
                'completed': q.get('completed', 0),
                'results': q.get('results', []),
                'errors': q.get('errors', []),
                'runtime_items': q.get('runtime_items', []),
                'next_expected_upload': q.get('next_expected_upload', 0),
                'upload_fifo_strict': bool(q.get('upload_fifo_strict', True)),
                'retry_max': int(q.get('retry_max', retry_max)),
                'pipeline_concurrency': int(q.get('pipeline_concurrency', pipeline_concurrency)),
                'skip_after_retry_exhausted': bool(q.get('skip_after_retry_exhausted', skip_after_retry_exhausted)),
                'saved_at': time.strftime('%Y-%m-%d %H:%M:%S'),
            }
            save_path = BASE_DIR / 'queue_state.json'
            save_path.write_text(
                json.dumps(state, ensure_ascii=False, indent=2),
                encoding='utf-8'
            )
        except Exception:
            pass

    qlock = threading.RLock()
    final_statuses = {'done', 'skipped', 'failed_final', 'upload_error'}
    upload_state_lock = threading.RLock()
    upload_drain_running = False

    def _refresh_job_progress_locked():
        q = JOBS[queue_id]['queue']
        items = q.get('runtime_items') or []
        finished = sum(1 for it in items if it.get('status') in final_statuses)
        q['completed'] = finished
        total = max(1, len(items))
        JOBS[queue_id]['progress'] = int((finished / total) * 100)
        if JOBS[queue_id].get('status') not in ('cancelled', 'done', 'error'):
            JOBS[queue_id]['status'] = 'running'
            JOBS[queue_id]['message'] = (
                f'Queue: {finished}/{len(items)} done | '
                f'pipeline x{pipeline_concurrency} | download x{download_concurrency} | '
                f'gpu x{sync_gpu_heavy_limit_from_config(cfg)}'
            )

    def _mark_item_locked(item, status, status_text='', **kwargs):
        item['status'] = status
        if status_text:
            item['status_text'] = status_text
        for k, v in kwargs.items():
            item[k] = v
        item['updated_at'] = time.strftime('%Y-%m-%d %H:%M:%S')

    def _run_upload_for_item(item):
        pdir = item.get('project_dir')
        if not pdir:
            raise RuntimeError('Missing project_dir for upload step')
        return upload_project_outputs(pdir, cfg_overrides=cfg, log_cb=lambda m: print(f"[FIFO {queue_id} #{item.get('index', 0)+1}] {m}"))

    def _should_drain_fifo_locked():
        q = JOBS.get(queue_id, {}).get('queue') or {}
        items = q.get('runtime_items') or []
        next_idx = int(q.get('next_expected_upload', 0) or 0)
        if next_idx >= len(items):
            return False
        st = str((items[next_idx] or {}).get('status') or '')
        return st in ('ready_waiting_upload', 'failed_final', 'skipped')

    def _drain_fifo_upload():
        while True:
            with qlock:
                q = JOBS.get(queue_id, {}).get('queue') or {}
                items = q.get('runtime_items') or []
                next_idx = int(q.get('next_expected_upload', 0) or 0)
                if next_idx >= len(items):
                    return
                item = items[next_idx]
                st = item.get('status')
                if st in ('failed_final', 'skipped'):
                    _mark_item_locked(item, st, 'Skipped before upload', upload_status='skipped')
                    q['next_expected_upload'] = next_idx + 1
                    _refresh_job_progress_locked()
                    _save_queue_state(queue_id)
                    continue
                if st != 'ready_waiting_upload':
                    return
                _mark_item_locked(item, 'uploading', f'Uploading FIFO #{next_idx+1}', upload_status='running')
                _save_queue_state(queue_id)
            try:
                up = _run_upload_for_item(item)
                with qlock:
                    q = JOBS.get(queue_id, {}).get('queue') or {}
                    items = q.get('runtime_items') or []
                    if next_idx < len(items):
                        item2 = items[next_idx]
                        _mark_item_locked(item2, 'done', 'Done', upload_status='done', upload_result=up)
                    q['next_expected_upload'] = next_idx + 1
                    _refresh_job_progress_locked()
                    _save_queue_state(queue_id)
            except Exception as ex:
                with qlock:
                    q = JOBS.get(queue_id, {}).get('queue') or {}
                    items = q.get('runtime_items') or []
                    if next_idx < len(items):
                        item2 = items[next_idx]
                        _mark_item_locked(item2, 'upload_error', f'Upload error: {ex}', upload_status='error', error=str(ex))
                        q['errors'].append({
                            'url': item2.get('url'),
                            'context': item2.get('context') or {},
                            'job_id': item2.get('job_id'),
                            'error': f'Upload failed: {ex}',
                            'stage': 'upload',
                        })
                    q['next_expected_upload'] = next_idx + 1
                    _refresh_job_progress_locked()
                    _save_queue_state(queue_id)

    def _schedule_fifo_drain():
        nonlocal upload_drain_running
        if not strict_fifo:
            return
        with upload_state_lock:
            if upload_drain_running:
                return
            upload_drain_running = True

        def _bg():
            nonlocal upload_drain_running
            try:
                _drain_fifo_upload()
            finally:
                rerun = False
                with qlock:
                    rerun = _should_drain_fifo_locked()
                with upload_state_lock:
                    upload_drain_running = False
                if rerun:
                    _schedule_fifo_drain()

        threading.Thread(target=_bg, daemon=True).start()

    def _process_one(item):
        idx = int(item.get('index', 0) or 0)
        url = str(item.get('url') or '').strip()
        context = _clean_series_context(item.get('context') or {})
        if not context and url:
            auto_one = _load_contexts_from_latest_group([url]).get(url) or {}
            context = _clean_series_context(auto_one)
            if context:
                with qlock:
                    item['context'] = context
                    _save_queue_state(queue_id)
        if idx < start_from:
            with qlock:
                _mark_item_locked(item, 'skipped', 'Skipped (already done before resume)', upload_status='skipped')
                JOBS[queue_id]['queue']['results'].append({
                    'url': url, 'context': context, 'job_id': None, 'result': 'skipped (already done)'
                })
                _refresh_job_progress_locked()
                _save_queue_state(queue_id)
            return

        while JOBS.get(queue_id, {}).get('paused'):
            if JOBS.get(queue_id, {}).get('status') == 'cancelled':
                return
            with qlock:
                _mark_item_locked(item, item.get('status') or 'waiting', f'Paused before URL #{idx+1}')
                _save_queue_state(queue_id)
            time.sleep(1.0)

        if JOBS.get(queue_id, {}).get('status') == 'cancelled':
            return

        with qlock:
            _mark_item_locked(item, 'running_pipeline', f'Running pipeline URL #{idx+1}')
            _refresh_job_progress_locked()
            _save_queue_state(queue_id)

        def _mark_current_job(job_id):
            with qlock:
                item['job_id'] = job_id
                JOBS[queue_id]['queue']['current_job'] = job_id
                _mark_item_locked(item, item.get('status') or 'running_pipeline', f'Pipeline job {job_id}')
                _save_queue_state(queue_id)

        try:
            run_out = _run_pipeline_with_single_retry(
                url,
                context,
                on_job_start=_mark_current_job,
                max_attempts=retry_max,
                run_mode='direct',
                disable_auto_upload=True,
            )
            with qlock:
                item['attempts_used'] = int(run_out.get('attempts_used') or 1)
            if run_out.get('ok'):
                result = run_out.get('result') or {}
                pdir = result.get('project_dir')
                pname = os.path.basename(pdir) if pdir else None
                with qlock:
                    JOBS[queue_id]['queue']['results'].append({
                        'url': url,
                        'context': context,
                        'job_id': run_out.get('job_id'),
                        'result': result,
                        'retry_attempted': bool(run_out.get('retry_attempted')),
                        'retry_mode': run_out.get('retry_mode'),
                        'first_job_id': run_out.get('first_job_id'),
                        'retry_job_id': run_out.get('retry_job_id'),
                        'attempts': run_out.get('attempts') or [],
                    })
                    _mark_item_locked(
                        item,
                        'ready_waiting_upload',
                        'Pipeline done, waiting FIFO upload',
                        project_dir=pdir,
                        project_name=pname,
                        upload_status='waiting',
                    )
                    _refresh_job_progress_locked()
                    _save_queue_state(queue_id)
                if strict_fifo:
                    _schedule_fifo_drain()
                else:
                    try:
                        up = _run_upload_for_item(item)
                        with qlock:
                            _mark_item_locked(item, 'done', 'Done', upload_status='done', upload_result=up)
                            _refresh_job_progress_locked()
                            _save_queue_state(queue_id)
                    except Exception as ex2:
                        with qlock:
                            _mark_item_locked(item, 'upload_error', f'Upload error: {ex2}', upload_status='error', error=str(ex2))
                            JOBS[queue_id]['queue']['errors'].append({
                                'url': url, 'context': context, 'job_id': run_out.get('job_id'),
                                'error': f'Upload failed: {ex2}', 'stage': 'upload'
                            })
                            _refresh_job_progress_locked()
                            _save_queue_state(queue_id)
            else:
                err_msg = run_out.get('error', 'Unknown')
                with qlock:
                    status = 'failed_final' if skip_after_retry_exhausted else 'error'
                    _mark_item_locked(item, status, f'Failed after retry: {err_msg}', error=err_msg, upload_status='skipped')
                    JOBS[queue_id]['queue']['errors'].append({
                        'url': url,
                        'context': context,
                        'job_id': run_out.get('job_id'),
                        'error': err_msg,
                        'retry_attempted': bool(run_out.get('retry_attempted')),
                        'retry_mode': run_out.get('retry_mode'),
                        'first_job_id': run_out.get('first_job_id'),
                        'retry_job_id': run_out.get('retry_job_id'),
                        'first_error': run_out.get('first_error'),
                        'retry_error': run_out.get('retry_error'),
                        'attempts': run_out.get('attempts') or [],
                    })
                    _refresh_job_progress_locked()
                    _save_queue_state(queue_id)
                if strict_fifo:
                    _schedule_fifo_drain()
        except Exception as ex:
            with qlock:
                _mark_item_locked(item, 'failed_final', f'Pipeline exception: {ex}', error=str(ex), upload_status='skipped')
                JOBS[queue_id]['queue']['errors'].append({'url': url, 'context': context, 'error': str(ex)})
                _refresh_job_progress_locked()
                _save_queue_state(queue_id)
            if strict_fifo:
                _schedule_fifo_drain()

    def _batch_worker():
        with ThreadPoolExecutor(max_workers=pipeline_concurrency) as ex:
            futures = [ex.submit(_process_one, it) for it in runtime_items]
            for f in futures:
                try:
                    f.result()
                except Exception:
                    pass
        if strict_fifo:
            _schedule_fifo_drain()
            while True:
                with qlock:
                    q = JOBS.get(queue_id, {}).get('queue') or {}
                    items = q.get('runtime_items') or []
                    done_count = sum(1 for it in items if it.get('status') in final_statuses)
                    still_has_items = bool(items)
                with upload_state_lock:
                    running_upload = bool(upload_drain_running)
                if (not still_has_items) or (done_count >= len(items) and not running_upload):
                    break
                _schedule_fifo_drain()
                time.sleep(0.4)

        with qlock:
            q = JOBS[queue_id]['queue']
            _refresh_job_progress_locked()
            JOBS[queue_id].update({
                'status': 'done' if JOBS[queue_id].get('status') != 'cancelled' else 'cancelled',
                'progress': 100 if JOBS[queue_id].get('status') != 'cancelled' else JOBS[queue_id].get('progress', 0),
                'message': (
                    f'Queue done: {len(q["results"])}/{len(unique)} success, {len(q["errors"])} failed'
                    if JOBS[queue_id].get('status') != 'cancelled'
                    else 'Queue cancelled by user'
                ),
                'result': q
            })
            _save_queue_state(queue_id)
        try:
            save_path = BASE_DIR / 'queue_state.json'
            if save_path.exists():
                done_path = BASE_DIR / f'queue_done_{queue_id}.json'
                save_path.rename(done_path)
        except Exception:
            pass

    t = threading.Thread(target=_batch_worker, daemon=True)
    t.start()
    return {
        'queue_id': queue_id,
        'total': len(unique),
        'urls': unique,
        'contexts_count': len(context_by_url),
        'pipeline_concurrency': pipeline_concurrency,
        'retry_max': retry_max,
        'upload_fifo_strict': strict_fifo,
    }

@app.route('/api/pipeline/batch', methods=['POST'])
def start_batch_pipeline():
    """Start batch pipeline: multiple URLs processed sequentially."""
    data = request.json or {}
    urls_text = data.get('urls', '').strip()
    start_from = data.get('start_from', 0)
    contexts = data.get('contexts') or {}
    if not urls_text:
        return jsonify({'error': 'URLs required'}), 400

    from modules.url_extractor import extract_all_urls
    urls = extract_all_urls(urls_text)
    if not urls:
        for line in urls_text.split('\n'):
            line = line.strip()
            if line and ('douyin.com' in line or 'tiktok.com' in line):
                urls.append(line)
    if not urls:
        return jsonify({'error': 'No Douyin URLs found in input'}), 400
    try:
        out = _start_batch_pipeline_from_urls(urls, start_from=start_from, contexts=contexts)
        return jsonify(out)
    except Exception as e:
        return jsonify({'error': str(e)}), 400

@app.route('/api/pipeline/queue/<queue_id>')
def get_queue_status(queue_id):
    job = JOBS.get(queue_id)
    if not job:
        return jsonify({'error': 'Queue not found'}), 404
    out = dict(job)
    out['summary'] = _queue_summary(queue_id, job) if job.get('queue') else None
    return jsonify(out)


@app.route('/api/pipeline/queues')
def list_pipeline_queues():
    include_done = str(request.args.get('include_done', '')).lower() in ('1', 'true', 'yes')
    return jsonify({'queues': _list_pipeline_queue_summaries(include_done=include_done)})


@app.route('/api/pipeline/queue/<queue_id>/pause', methods=['POST'])
def pause_pipeline_queue(queue_id):
    job = _set_queue_paused(queue_id, True)
    if not job:
        return jsonify({'error': 'Queue not found'}), 404
    return jsonify({'ok': True, 'queue': _queue_summary(queue_id, job)})


@app.route('/api/pipeline/queue/<queue_id>/resume', methods=['POST'])
def resume_pipeline_queue(queue_id):
    job = _set_queue_paused(queue_id, False)
    if not job:
        return jsonify({'error': 'Queue not found'}), 404
    return jsonify({'ok': True, 'queue': _queue_summary(queue_id, job)})


@app.route('/api/pipeline/queue/<queue_id>/skip', methods=['POST'])
def skip_pipeline_queue_item(queue_id):
    job = JOBS.get(queue_id)
    if not job or not job.get('queue'):
        return jsonify({'error': 'Queue not found'}), 404
    q = job.get('queue') or {}
    items = q.get('runtime_items') or []
    if not items:
        return jsonify({'error': 'No runtime items'}), 400
    target_idx = None
    for i, it in enumerate(items):
        st = str((it or {}).get('status') or '')
        if st in ('waiting', 'ready_waiting_upload'):
            target_idx = i
            break
    if target_idx is None:
        return jsonify({'error': 'No skippable item (running item cannot be force-skipped)'}), 400
    item = items[target_idx]
    item['status'] = 'skipped'
    item['status_text'] = 'Skipped by user'
    item['upload_status'] = 'skipped'
    item['updated_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
    q['errors'].append({
        'url': item.get('url'),
        'context': item.get('context') or {},
        'job_id': item.get('job_id'),
        'error': 'Skipped by user',
        'stage': 'manual_skip',
    })
    if int(q.get('next_expected_upload', 0) or 0) == target_idx:
        q['next_expected_upload'] = target_idx + 1
    q['completed'] = sum(1 for it in items if str((it or {}).get('status') or '') in ('done', 'skipped', 'failed_final', 'upload_error'))
    total = max(1, len(items))
    job['progress'] = int((q['completed'] / total) * 100)
    job['message'] = f'Queue: {q["completed"]}/{len(items)} done'
    return jsonify({'ok': True, 'skipped_index': target_idx, 'queue': _queue_summary(queue_id, job)})


@app.route('/api/pipeline/running')
def pipeline_running_snapshot():
    rows = []
    for qid, job in list(JOBS._data.items()):
        if not isinstance(job, dict) or not job.get('queue'):
            continue
        if job.get('status') not in ('running', 'paused', 'queued'):
            continue
        q = job.get('queue') or {}
        rows.append({
            'queue_id': qid,
            'status': job.get('status'),
            'paused': bool(job.get('paused')),
            'message': job.get('message'),
            'progress': int(job.get('progress') or 0),
            'summary': _queue_summary(qid, job),
            'items': q.get('runtime_items') or [],
        })
    rows.sort(key=lambda r: r.get('queue_id', ''))
    return jsonify({'queues': rows})


@app.route('/api/pipeline/queue/<queue_id>/item/<int:item_index>/logs')
def queue_item_logs(queue_id, item_index):
    job = JOBS.get(queue_id)
    if not job or not job.get('queue'):
        return jsonify({'error': 'Queue not found'}), 404
    q = job.get('queue') or {}
    items = q.get('runtime_items') or []
    if item_index < 0 or item_index >= len(items):
        return jsonify({'error': 'Item index out of range'}), 404
    item = items[item_index] or {}
    offset = int(request.args.get('offset', 0) or 0)
    job_id = item.get('job_id')
    project_dir = item.get('project_dir')
    if not job_id and not project_dir:
        return jsonify({'lines': [], 'total': offset, 'status': item.get('status')})
    lines = _get_logs(job_id or f'{queue_id}:{item_index}', offset, project_dir=project_dir)
    return jsonify({
        'queue_id': queue_id,
        'item_index': item_index,
        'job_id': job_id,
        'status': item.get('status'),
        'lines': lines,
        'total': offset + len(lines),
    })

# Ã¢â€â‚¬Ã¢â€â‚¬ Queue Export/Import Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
@app.route('/api/pipeline/export')
def export_queue():
    """Export current queue state (or last saved state from disk)."""
    for k, v in list(JOBS._data.items()):
        if v.get('queue') and v.get('status') == 'running':
            q = v['queue']
            state = {
                'queue_id': k,
                'status': v.get('status'),
                'paused': bool(v.get('paused')),
                'urls': q.get('urls', []),
                'contexts': q.get('contexts', {}),
                'total': q.get('total', 0),
                'completed': q.get('completed', 0),
                'results': q.get('results', []),
                'errors': q.get('errors', []),
                'saved_at': time.strftime('%Y-%m-%d %H:%M:%S'),
            }
            return jsonify(state)

    save_path = BASE_DIR / 'queue_state.json'
    if save_path.exists():
        try:
            data = json.loads(save_path.read_text(encoding='utf-8'))
            data['source'] = 'disk'
            return jsonify(data)
        except Exception as e:
            return jsonify({'error': f'Failed to read state: {e}'}), 500

    return jsonify({'error': 'No queue state found'}), 404

@app.route('/api/pipeline/import', methods=['POST'])
def import_queue():
    """Import a saved queue state and resume from where it left off."""
    data = request.json or {}
    urls = data.get('urls', [])
    start_from = data.get('start_from', 0)
    contexts = data.get('contexts') or {}

    if not urls:
        save_path = BASE_DIR / 'queue_state.json'
        if save_path.exists():
            try:
                saved = json.loads(save_path.read_text(encoding='utf-8'))
                urls = saved.get('urls', [])
                contexts = saved.get('contexts') or {}
                done_urls = set()
                for r in saved.get('results', []):
                    if r.get('result') and r.get('result') not in ('skipped (already done)', 'skipped (previously done)'):
                        done_urls.add(r.get('url'))
                start_from = len(done_urls)
            except Exception as e:
                return jsonify({'error': f'Failed to load state: {e}'}), 400
        else:
            return jsonify({'error': 'No saved queue state found on disk'}), 404

    if not urls:
        return jsonify({'error': 'No URLs to resume'}), 400

    remaining = len(urls) - start_from
    if remaining <= 0:
        return jsonify({'error': 'All URLs already completed', 'total': len(urls)}), 400

    queue_id = str(uuid.uuid4())[:8]
    unique = urls

    JOBS[queue_id] = {
        'status': 'running', 'progress': 0,
        'message': f'Resumed queue: {start_from}/{len(unique)} already done',
        'result': None, 'error': None, 'paused': False,
        'queue': {
            'urls': unique,
            'contexts': contexts if isinstance(contexts, dict) else {},
            'total': len(unique),
            'completed': start_from,
            'current_job': None,
            'results': [],
            'errors': []
        }
    }

    def _save_queue_state_inner(qid):
        try:
            job = JOBS.get(qid)
            if not job:
                return
            q = job.get('queue', {})
            state = {
                'queue_id': qid, 'status': job.get('status'),
                'paused': bool(job.get('paused')),
                'progress': job.get('progress'), 'message': job.get('message'),
                'urls': q.get('urls', []), 'contexts': q.get('contexts', {}), 'total': q.get('total', 0),
                'completed': q.get('completed', 0),
                'results': q.get('results', []), 'errors': q.get('errors', []),
                'saved_at': time.strftime('%Y-%m-%d %H:%M:%S'),
            }
            sp = BASE_DIR / 'queue_state.json'
            sp.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')
        except Exception:
            pass

    def _resume_worker():
        q = JOBS[queue_id]['queue']
        for idx, url in enumerate(unique):
            if idx < start_from:
                q['results'].append({'url': url, 'job_id': None, 'result': 'skipped (previously done)'})
                continue
            _wait_queue_if_paused(queue_id, _save_queue_state_inner)
            if JOBS.get(queue_id, {}).get('status') == 'cancelled': break
            q['completed'] = idx
            JOBS[queue_id]['status'] = 'running'
            JOBS[queue_id]['message'] = f'Queue: {idx}/{len(unique)} Ã¢â‚¬â€ Processing URL {idx+1}...'
            JOBS[queue_id]['progress'] = int(idx / len(unique) * 100)
            _save_queue_state_inner(queue_id)
            try:
                run_out = _run_pipeline_with_single_retry(url, (contexts or {}).get(url) if isinstance(contexts, dict) else None)
                q['current_job'] = run_out.get('job_id')
                _save_queue_state_inner(queue_id)
                if run_out.get('ok'):
                    q['results'].append({
                        'url': url,
                        'job_id': run_out.get('job_id'),
                        'result': run_out.get('result'),
                        'retry_attempted': bool(run_out.get('retry_attempted')),
                        'retry_mode': run_out.get('retry_mode'),
                        'first_job_id': run_out.get('first_job_id'),
                        'retry_job_id': run_out.get('retry_job_id'),
                    })
                else:
                    q['errors'].append({
                        'url': url,
                        'job_id': run_out.get('job_id'),
                        'error': run_out.get('error', 'Unknown'),
                        'retry_attempted': bool(run_out.get('retry_attempted')),
                        'retry_mode': run_out.get('retry_mode'),
                        'first_job_id': run_out.get('first_job_id'),
                        'retry_job_id': run_out.get('retry_job_id'),
                        'first_error': run_out.get('first_error'),
                        'retry_error': run_out.get('retry_error'),
                    })
            except Exception as ex:
                q['errors'].append({'url': url, 'error': str(ex)})
            _save_queue_state_inner(queue_id)

        q['completed'] = len(unique)
        JOBS[queue_id].update({
            'status': 'done', 'progress': 100,
            'message': f'Queue done: {len(q["results"])}/{len(unique)} success, {len(q["errors"])} failed',
            'result': q
        })
        _save_queue_state_inner(queue_id)
        try:
            sp = BASE_DIR / 'queue_state.json'
            if sp.exists():
                sp.rename(BASE_DIR / f'queue_done_{queue_id}.json')
        except Exception:
            pass

    t = threading.Thread(target=_resume_worker, daemon=True)
    t.start()
    return jsonify({
        'queue_id': queue_id, 'total': len(unique),
        'resumed_from': start_from, 'remaining': remaining, 'urls': unique
    })

@app.route('/api/pipeline/saved-state')
def check_saved_state():
    """Check if there's a saved queue state on disk."""
    save_path = BASE_DIR / 'queue_state.json'
    if save_path.exists():
        try:
            data = json.loads(save_path.read_text(encoding='utf-8'))
            completed = data.get('completed', 0)
            total = data.get('total', 0)
            remaining = total - completed
            done_count = len([r for r in data.get('results', [])
                             if r.get('result') and r.get('result') not in
                             ('skipped (already done)', 'skipped (previously done)')])
            return jsonify({
                'found': True, 'queue_id': data.get('queue_id'),
                'total': total, 'completed': completed,
                'done_count': done_count, 'remaining': remaining,
                'errors': len(data.get('errors', [])),
                'saved_at': data.get('saved_at'), 'status': data.get('status'),
            })
        except Exception as e:
            return jsonify({'found': False, 'error': str(e)})
    return jsonify({'found': False})

@app.route('/api/job/<job_id>')
def get_job(job_id):
    job = JOBS.get(job_id)
    if not job:
        return jsonify({'error': 'Job not found'}), 404
    return jsonify(job)

@app.route('/api/pipeline/logs/<job_id>')
def pipeline_logs(job_id):
    offset = int(request.args.get('offset', 0) or 0)
    project_dir = str(request.args.get('project_dir', '') or '').strip()
    project_name = str(request.args.get('project_name', '') or '').strip()
    if not project_dir and project_name:
        pdir, _ = _load_project_info_by_name(project_name)
        project_dir = pdir or ''
    logs = _get_logs(job_id, offset, project_dir=project_dir or None)
    return jsonify({'lines': logs, 'total': offset + len(logs)})

# Ã¢â€â‚¬Ã¢â€â‚¬ Projects Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
@app.route('/api/projects')
def get_projects():
    return jsonify({'projects': list_projects()})

@app.route('/api/project/<project_name>/detail')
def project_detail(project_name):
    """List all files in a project with sizes."""
    cfg = load_config()
    pdir = cfg.get('projects_dir', 'D:/anti-sub-projects')
    project_path = os.path.join(pdir, project_name)
    if not os.path.isdir(project_path):
        return jsonify({'error': 'Project not found'}), 404

    # Load project info
    info = {}
    info_path = os.path.join(project_path, 'info.json')
    if os.path.exists(info_path):
        with open(info_path, 'r', encoding='utf-8') as f:
            info = json.load(f)

    # List all files
    files = []
    for fn in sorted(os.listdir(project_path)):
        fp = os.path.join(project_path, fn)
        if os.path.isfile(fp):
            size = os.path.getsize(fp)
            ext = os.path.splitext(fn)[1].lower()
            ftype = 'video' if ext in ('.mp4','.mkv','.webm','.avi') else \
                    'audio' if ext in ('.mp3','.wav','.m4a','.flac') else \
                    'subtitle' if ext in ('.srt','.vtt','.ass') else \
                    'image' if ext in ('.jpg','.jpeg','.png','.webp') else \
                    'data' if ext in ('.json',) else 'other'
            files.append({
                'name': fn, 'size': size,
                'size_human': f'{size/1024/1024:.1f}MB' if size > 1024*1024 else f'{size/1024:.0f}KB',
                'type': ftype, 'ext': ext
            })

    return jsonify({
        'project_name': project_name,
        'project_path': project_path,
        'info': info,
        'files': files,
        'total_size': sum(f['size'] for f in files),
        'total_size_human': f"{sum(f['size'] for f in files)/1024/1024:.1f}MB"
    })

@app.route('/api/project/<project_name>', methods=['DELETE'])
def delete_project(project_name):
    """Delete a project and all its files."""
    if '..' in project_name:
        return jsonify({'error': 'invalid name'}), 400
    cfg = load_config()
    pdir = cfg.get('projects_dir', 'D:/anti-sub-projects')
    project_path = os.path.join(pdir, project_name)
    if not os.path.isdir(project_path):
        return jsonify({'error': 'Project not found'}), 404
    try:
        shutil.rmtree(project_path)
        return jsonify({'ok': True, 'deleted': project_name})
    except Exception as e:
        return jsonify({'error': str(e)}), 500




@app.route('/api/series/<folder>', methods=['DELETE'])
def delete_series(folder):
    projects = list_projects()
    deleted_count = 0
    for p in projects:
        meta = p.get('metadata', {}) or {}
        ctx = p.get('series_context', {}) or meta.get('series_context', {})
        if ctx.get('series_folder') == folder:
            path = p.get('project_path')
            if path and os.path.exists(path):
                try:
                    import shutil
                    shutil.rmtree(path)
                    deleted_count += 1
                except Exception as e:
                    print(f"Error deleting {path}: {e}")
    return jsonify({'ok': True, 'deleted': deleted_count})

@app.route('/api/series/<folder>', methods=['PUT'])
def rename_series(folder):
    data = request.json or {}
    new_name = data.get('new_name')
    if not new_name:
        return jsonify({'error': 'Missing new_name'}), 400
        
    projects = list_projects()
    updated_count = 0
    for p in projects:
        meta = p.get('metadata', {}) or {}
        ctx = p.get('series_context', {}) or meta.get('series_context', {})
        if ctx.get('series_folder') == folder:
            path = p.get('project_path')
            if path and os.path.exists(path):
                info_file = os.path.join(path, 'info.json')
                if os.path.exists(info_file):
                    try:
                        with open(info_file, 'r', encoding='utf-8') as f:
                            info = json.load(f)
                        
                        # Update inside info
                        if 'series_context' in info:
                            info['series_context']['series_name'] = new_name
                            info['series_context']['series_name_vi'] = new_name
                        if 'metadata' in info and 'series_context' in info['metadata']:
                            info['metadata']['series_context']['series_name'] = new_name
                            info['metadata']['series_context']['series_name_vi'] = new_name
                            
                        with open(info_file, 'w', encoding='utf-8') as f:
                            json.dump(info, f, indent=4, ensure_ascii=False)
                        updated_count += 1
                    except Exception as e:
                        print(f"Error updating {info_file}: {e}")
    return jsonify({'ok': True, 'updated': updated_count})

@app.route('/api/series/merge', methods=['POST'])
def merge_series():
    data = request.json or {}
    target_folder = data.get('target_folder')
    source_folders = data.get('source_folders', [])
    if not target_folder or not source_folders:
        return jsonify({'error': 'Missing target_folder or source_folders'}), 400
        
    projects = list_projects()
    updated_count = 0
    for p in projects:
        meta = p.get('metadata', {}) or {}
        ctx = p.get('series_context', {}) or meta.get('series_context', {})
        if ctx.get('series_folder') in source_folders and ctx.get('series_folder') != target_folder:
            path = p.get('project_path')
            if path and os.path.exists(path):
                info_file = os.path.join(path, 'info.json')
                if os.path.exists(info_file):
                    try:
                        with open(info_file, 'r', encoding='utf-8') as f:
                            info = json.load(f)
                        
                        # Update inside info
                        if 'series_context' in info:
                            info['series_context']['series_folder'] = target_folder
                        if 'metadata' in info and 'series_context' in info['metadata']:
                            info['metadata']['series_context']['series_folder'] = target_folder
                            
                        with open(info_file, 'w', encoding='utf-8') as f:
                            json.dump(info, f, indent=4, ensure_ascii=False)
                        updated_count += 1
                    except Exception as e:
                        print(f"Error updating {info_file}: {e}")
    return jsonify({'ok': True, 'merged': updated_count})

@app.route('/api/series')

def get_series_library():
    projects = list_projects()
    series_dict = {}
    standalones = []
    
    for p in projects:
        meta = p.get('metadata', {}) or {}
        ctx = p.get('series_context', {}) or meta.get('series_context', {})
        folder = ctx.get('series_folder')
        
        # If no folder or explicitly standalone
        if not folder:
            standalones.append(p)
            continue
            
        if folder not in series_dict:
            series_dict[folder] = {
                'series_folder': folder,
                'series_name': ctx.get('series_name_vi') or ctx.get('series_name') or folder,
                'episode_min': ctx.get('episode_min'),
                'episode_max': ctx.get('episode_max'),
                'episodes': []
            }
        series_dict[folder]['episodes'].append(p)
        
    final_series = []
    for folder, data in series_dict.items():
        episodes = data['episodes']
        # If AI said max episodes > 1, keep it as a series even if only 1 downloaded
        # Or if we have > 1 downloaded, it's definitely a series
        has_multiple_episodes = len(episodes) > 1
        ai_says_series = data.get('episode_max') and int(data.get('episode_max')) > 1
        
        if has_multiple_episodes or ai_says_series:
            # Sort episodes by episode_no or created_at
            # Episodes might lack episode_no, so fallback to created_at
            for ep in episodes:
                ctx = ep.get('series_context', {}) or (ep.get('metadata', {}) or {}).get('series_context', {})
                ep['_ep_no'] = ctx.get('episode_no', 0)
                
            data['episodes'] = sorted(episodes, key=lambda x: (x['_ep_no'], x.get('created_at', '')), reverse=True)
            
            # Compute stats
            data['total_downloaded'] = len(episodes)
            data['rendered_count'] = sum(1 for e in episodes if e.get('final_video'))
            data['uploaded_count'] = sum(1 for e in episodes if e.get('youtube', {}).get('videoId') or e.get('facebook_reels', {}).get('results'))
            data['latest_episode'] = data['episodes'][0]
            
            final_series.append(data)
        else:
            # Only 1 episode and no AI max indication -> standalone
            standalones.append(episodes[0])
            
    # Sort series by latest episode created_at
    final_series.sort(key=lambda x: x['latest_episode'].get('created_at', ''), reverse=True)
    
    return jsonify({
        'series': final_series,
        'standalones': standalones
    })

@app.route('/api/projects/bulk-delete', methods=['POST'])
def bulk_delete_projects():
    """Delete multiple projects at once."""
    data = request.json or {}
    project_names = data.get('projects', [])
    if not project_names:
        return jsonify({'error': 'No projects specified'}), 400

    cfg = load_config()
    pdir = cfg.get('projects_dir', 'D:/anti-sub-projects')

    deleted = []
    errors = []

    for pname in project_names:
        if '..' in pname:
            continue
        ppath = os.path.join(pdir, pname)
        if os.path.isdir(ppath):
            try:
                shutil.rmtree(ppath)
                deleted.append(pname)
            except Exception as e:
                errors.append({'project': pname, 'error': str(e)})

    return jsonify({'ok': True, 'deleted': deleted, 'errors': errors})


@app.route('/api/projects/duplicates', methods=['GET'])
def find_duplicate_projects():
    """Find projects that have the same Douyin source URL."""
    projects = list_projects()
    url_map = {}  # url -> list of project_infos

    for p in projects:
        url = p.get('source_url')
        if url:
            if url not in url_map:
                url_map[url] = []
            url_map[url].append(p)

    duplicates = []
    for url, p_list in url_map.items():
        if len(p_list) > 1:
            # Sort by created_at (newest first)
            p_list.sort(key=lambda x: x.get('created_at', ''), reverse=True)
            duplicates.append({
                'url': url,
                'projects': p_list
            })

    return jsonify({'duplicates': duplicates})

@app.route('/api/project/<project_name>/resume', methods=['POST'])
def resume_project(project_name):
    """Resume pipeline from last completed step."""
    cfg = load_config()
    pdir = cfg.get('projects_dir', 'D:/anti-sub-projects')
    project_path = os.path.join(pdir, project_name)
    if not os.path.isdir(project_path):
        return jsonify({'error': 'Project not found'}), 404

    info_path = os.path.join(project_path, 'info.json')
    if not os.path.exists(info_path):
        return jsonify({'error': 'No info.json found'}), 400

    with open(info_path, 'r', encoding='utf-8') as f:
        info = json.load(f)

    from pipeline import resume_pipeline
    job_id = resume_pipeline(project_path, info)
    return jsonify({'job_id': job_id, 'project': project_name})

@app.route('/api/pipeline/resume-batch', methods=['POST'])
def resume_batch():
    """Resume multiple incomplete projects sequentially in a queue."""
    data = request.json or {}
    project_names = data.get('projects', [])
    if not project_names:
        return jsonify({'error': 'No projects specified'}), 400

    cfg = load_config()
    pdir = cfg.get('projects_dir', 'D:/anti-sub-projects')

    # Validate all projects exist and have info.json
    valid = []
    for pname in project_names:
        if '..' in pname:
            continue
        pp = os.path.join(pdir, pname)
        ip = os.path.join(pp, 'info.json')
        if os.path.isdir(pp) and os.path.exists(ip):
            with open(ip, 'r', encoding='utf-8') as f:
                info = json.load(f)
            valid.append({'name': pname, 'path': pp, 'info': info})

    if not valid:
        return jsonify({'error': 'No valid projects found'}), 400

    queue_id = str(uuid.uuid4())[:8]
    JOBS[queue_id] = {
        'status': 'running', 'progress': 0,
        'message': f'Resume queue: 0/{len(valid)} done',
        'result': None, 'error': None, 'paused': False,
        'queue': {
            'projects': [v['name'] for v in valid],
            'total': len(valid),
            'completed': 0,
            'current_job': None,
            'results': [],
            'errors': []
        }
    }

    def _resume_batch_worker():
        from pipeline import resume_pipeline
        q = JOBS[queue_id]['queue']
        for idx, proj in enumerate(valid):
            _wait_queue_if_paused(queue_id)
            if JOBS.get(queue_id, {}).get('status') == 'cancelled': break
            q['completed'] = idx
            JOBS[queue_id]['status'] = 'running'
            JOBS[queue_id]['message'] = f'Resume queue: {idx}/{len(valid)} Ã¢â‚¬â€ Resuming {proj["name"]}...'
            JOBS[queue_id]['progress'] = int(idx / len(valid) * 100)
            try:
                job_id = resume_pipeline(proj['path'], proj['info'])
                q['current_job'] = job_id
                # Wait for this pipeline to finish
                while True:
                    sub = JOBS.get(job_id, {})
                    if sub.get('status') in ('done', 'error'):
                        break
                    time.sleep(3)
                sub = JOBS.get(job_id, {})
                if sub.get('status') == 'done':
                    q['results'].append({'project': proj['name'], 'job_id': job_id,
                                         'result': sub.get('result')})
                else:
                    q['errors'].append({'project': proj['name'], 'job_id': job_id,
                                        'error': sub.get('error', 'Unknown')})
            except Exception as ex:
                q['errors'].append({'project': proj['name'], 'error': str(ex)})

        q['completed'] = len(valid)
        JOBS[queue_id].update({
            'status': 'done', 'progress': 100,
            'message': f'Resume done: {len(q["results"])}/{len(valid)} success, '
                       f'{len(q["errors"])} failed',
            'result': q
        })

    t = threading.Thread(target=_resume_batch_worker, daemon=True)
    t.start()
    return jsonify({
        'queue_id': queue_id,
        'total': len(valid),
        'projects': [v['name'] for v in valid]
    })

@app.route('/api/project/<project_id>/file/<filename>')
def project_file(project_id, filename):
    """Download a file from a project."""
    if '..' in filename or '/' in filename or '\\' in filename:
        return jsonify({'error': 'invalid'}), 400
    cfg = load_config()
    pdir = cfg.get('projects_dir', 'D:/anti-sub-projects')
    # Find project folder by id
    for name in os.listdir(pdir):
        if project_id in name:
            fpath = os.path.join(pdir, name, filename)
            if os.path.isfile(fpath):
                return send_file(fpath, as_attachment=True)
    return jsonify({'error': 'not found'}), 404

# Ã¢â€â‚¬Ã¢â€â‚¬ Douyin Login Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
@app.route('/api/douyin/login', methods=['POST'])
def douyin_login():
    lid = launch_chromium_login()
    return jsonify({'login_id': lid})

@app.route('/api/douyin/login/<lid>')
def douyin_login_status(lid):
    return jsonify(get_login_job(lid))

@app.route('/api/douyin/cookies')
def douyin_cookies():
    return jsonify(load_cookies())

@app.route('/api/douyin/cookies', methods=['POST'])
def set_douyin_cookies():
    data = request.json or {}
    cookie_str = data.get('cookies', '')
    if isinstance(cookie_str, str):
        # Parse from string
        from modules.downloader import save_cookies as _sc
        result = {}
        for part in re.split(r'[;\n]+', cookie_str):
            part = part.strip()
            if '=' in part:
                k, _, v = part.partition('=')
                result[k.strip()] = v.strip()
        _sc(result)
    elif isinstance(cookie_str, dict):
        save_cookies(cookie_str)
    return jsonify({'ok': True})

# Ã¢â€â‚¬Ã¢â€â‚¬ Douyin Profile Scraper Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
@app.route('/api/douyin/scrape', methods=['POST'])
def scrape_douyin_user():
    data = request.json or {}
    user_url = data.get('url', '').strip()
    try:
        min_duration_sec = float(data.get('min_duration_sec', 60) or 60)
    except Exception:
        min_duration_sec = 60.0
    oldest_first = bool(data.get('oldest_first', True))
    if not user_url:
        return jsonify({'error': 'User URL required'}), 400
    # Accept various formats
    if 'douyin.com' not in user_url:
        return jsonify({'error': 'Must be a Douyin URL'}), 400
    min_duration_sec = max(0.0, min_duration_sec)
    job_id = start_scrape_job(user_url, min_duration_sec=min_duration_sec, oldest_first=oldest_first)
    return jsonify({'job_id': job_id})

@app.route('/api/douyin/scrape/<job_id>')
def scrape_status(job_id):
    job = get_scrape_job(job_id)
    if not job:
        return jsonify({'error': 'Job not found'}), 404
    out = dict(job)
    if out.get('status') == 'done' and isinstance(out.get('result'), dict):
        result = dict(out.get('result') or {})
        videos, summary = _annotate_scraped_videos_with_done(result.get('videos') or [])
        result['videos'] = videos
        result.update(summary)
        out['result'] = result
    return jsonify(out)

@app.route('/api/douyin/translate-captions', methods=['POST'])
def translate_douyin_captions():
    """Translate a list of captions to target language."""
    data = request.json or {}
    captions = data.get('captions', [])
    if not captions:
        return jsonify({'error': 'No captions'}), 400
    cfg = load_config()
    target_lang = cfg.get('target_lang', 'vi')
    model = cfg.get('ninerouter_model', '')
    try:
        results = translate_captions(
            captions,
            target_lang=target_lang,
            model=model,
            ninerouter_url=cfg.get('ninerouter_url', 'http://127.0.0.1:20128'),
            ninerouter_key=cfg.get('ninerouter_key', ''),
            timeout=cfg.get('ninerouter_timeout', 90)
        )
        return jsonify({'translations': results})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/douyin/group-series', methods=['POST'])
def group_douyin_series():
    """Group scraped Douyin videos into series using 9router AI."""
    data = request.json or {}
    videos = data.get('videos', [])
    if not isinstance(videos, list) or not videos:
        return jsonify({'error': 'No videos provided'}), 400
    cfg = load_config()
    try:
        grouped = group_videos_into_series(
            videos,
            ninerouter_url=cfg.get('ninerouter_url', 'http://127.0.0.1:20128'),
            ninerouter_key=cfg.get('ninerouter_key', ''),
            model=cfg.get('ninerouter_model', ''),
            timeout=max(300, int(cfg.get('ninerouter_timeout', 120) or 120)),
            log_cb=print,
        )
        groups = []
        projects_dir = cfg.get('projects_dir') or str(BASE_DIR / 'projects')
        for g in grouped.get('groups', []) or []:
            folder = (g.get('folder') or '').strip()
            groups.append({
                'series_name': g.get('series_name') or '',
                'series_name_vi': g.get('series_name_vi') or '',
                'folder': folder,
                'folder_path_suggested': str(Path(projects_dir) / folder) if folder else '',
                'reason': g.get('reason') or '',
                'confidence': g.get('confidence') or 0,
                'cover_clusters': g.get('cover_clusters') or [],
                'cover_cluster_count': g.get('cover_cluster_count') or 0,
                'count': g.get('count') or len(g.get('video_ids') or []),
                'video_ids': g.get('video_ids') or [],
                'urls': g.get('urls') or [],
                'unique_episode_urls': g.get('unique_episode_urls') or [],
                'unique_episode_count': g.get('unique_episode_count') or 0,
                'duplicate_episode_count': g.get('duplicate_episode_count') or 0,
                'episode_min': g.get('episode_min'),
                'episode_max': g.get('episode_max'),
                'videos': g.get('videos') or [],
            })
        res_data = {
            'ok': True,
            'groups': groups,
            'standalone_ids': grouped.get('standalone_ids') or [],
            'standalone_count': len(grouped.get('standalone_ids') or []),
            'cover_meta': grouped.get('cover_meta') or {},
            'total': len(videos),
        }
        try:
            (BASE_DIR / 'latest_ai_group.json').write_text(json.dumps(res_data, ensure_ascii=False, indent=2), encoding='utf-8')
        except Exception:
            pass
        return jsonify(res_data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500



@app.route('/api/douyin/load-group', methods=['GET'])
def load_douyin_group():
    try:
        p = BASE_DIR / 'latest_ai_group.json'
        if not p.exists():
            return jsonify({'error': 'No saved group found'}), 404
        data = json.loads(p.read_text(encoding='utf-8'))
        return jsonify(data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/projects/completed-urls', methods=['GET'])
def get_completed_urls():
    done_urls = set()
    cfg = load_config()
    
    # Check both normal and test project dirs
    dirs_to_check = [
        cfg.get('projects_dir') or str(BASE_DIR / 'projects'),
        r'E:nti-sub-projects',
        r'E:nti-sub-projects-test'
    ]
    checked = set()
    for d_path in dirs_to_check:
        if not d_path or d_path in checked:
            continue
        checked.add(d_path)
        d = Path(d_path)
        if not d.exists() or not d.is_dir():
            continue
            
        for proj in d.iterdir():
            if not proj.is_dir():
                continue
            info_file = proj / 'info.json'
            if info_file.exists():
                try:
                    info = json.loads(info_file.read_text(encoding='utf-8'))
                    url = info.get('source_url')
                    if url:
                        # Consider it done if it reached metadata step (or is fully done)
                        steps = info.get('steps_completed') or []
                        if 'metadata' in steps or 'translate' in steps or 'download' in steps:
                            # Actually, if the folder exists and has info.json, it's at least started. 
                            # To be safe, let's say if 'download' and 'translate' are done.
                            if 'download' in steps and 'translate' in steps:
                                done_urls.add(url)
                except Exception:
                    pass
                    
    return jsonify({'ok': True, 'completed': list(done_urls)})


from pipeline import get_youtube_upload_queue_status, _YT_UPLOAD_LOCK, _YT_UPLOAD_QUEUE, _save_youtube_upload_queue

@app.route('/api/youtube/queue', methods=['GET'])
def get_yt_queue():
    status = get_youtube_upload_queue_status()
    return jsonify(status)

@app.route('/api/youtube/queue/cancel', methods=['POST'])
def cancel_yt_item():
    data = request.json or {}
    proj_dir = data.get('project_dir')
    if not proj_dir:
        return jsonify({'error': 'Missing project_dir'}), 400
        
    with _YT_UPLOAD_LOCK:
        idx_to_remove = -1
        for i, item in enumerate(_YT_UPLOAD_QUEUE):
            if item.get('project_dir') == proj_dir:
                idx_to_remove = i
                break
        if idx_to_remove >= 0:
            del _YT_UPLOAD_QUEUE[idx_to_remove]
            try:
                _save_youtube_upload_queue()
            except Exception:
                pass
            return jsonify({'ok': True, 'message': 'Removed from upload queue'})
        else:
            return jsonify({'error': 'Project not found in upload queue'}), 404


@app.route('/api/youtube/queue/reupload', methods=['POST'])
def reupload_yt_item():
    data = request.json or {}
    proj_dir = data.get('project_dir')
    if not proj_dir:
        return jsonify({'error': 'Missing project_dir'}), 400
        
    with _YT_UPLOAD_LOCK:
        found = False
        for item in _YT_UPLOAD_QUEUE:
            if item.get('project_dir') == proj_dir:
                item['attempts'] = 0
                item['next_try_at'] = 0
                item['status'] = 'pending'
                item['last_error'] = None
                found = True
                break
        if found:
            try:
                _save_youtube_upload_queue()
            except Exception:
                pass
            return jsonify({'ok': True})
    return jsonify({'error': 'Item not found in queue'}), 404


def _yt_queue_episode_no(item):
    title = str((item or {}).get('title') or '')
    title_ascii = unicodedata.normalize('NFKD', title).encode('ascii', 'ignore').decode('ascii')
    m = re.search(r'\b(?:tap|ep|episode)\s*(\d{1,5})', title_ascii, re.IGNORECASE)
    if not m:
        m = re.search(r'第\s*(\d{1,5})\s*[集话話]', title)
    if not m:
        return 999999
    try:
        return int(m.group(1))
    except Exception:
        return 999999


def _yt_queue_series_key(item):
    title = str((item or {}).get('title') or '')
    parts = [p.strip() for p in title.split('|')]
    series = parts[1] if len(parts) >= 2 else title
    key = unicodedata.normalize('NFKD', series).encode('ascii', 'ignore').decode('ascii').lower()
    key = re.sub(r'\s+', ' ', key).strip()
    if 'ha vo danh' in key or 'ha vo' in key:
        return '00-ha-vo-danh'
    if 'than thu' in key or 'ky dam' in key or 'linh chung' in key:
        return '01-than-thu-ky-dam'
    return key or '99-unknown'


@app.route('/api/youtube/queue/sort', methods=['POST'])
def sort_yt_queue():
    data = request.json or {}
    mode = str(data.get('mode') or 'episode_asc').strip().lower()
    if mode not in ('episode_asc', 'episode_desc', 'created_asc', 'created_desc'):
        return jsonify({'error': 'Invalid mode. Use episode_asc, episode_desc, created_asc, created_desc'}), 400

    def is_locked(item):
        return str((item or {}).get('status') or '').lower() == 'uploading'

    with _YT_UPLOAD_LOCK:
        before = [str(x.get('title') or '') for x in _YT_UPLOAD_QUEUE]
        locked = {i: item for i, item in enumerate(_YT_UPLOAD_QUEUE) if is_locked(item)}
        movable = [item for item in _YT_UPLOAD_QUEUE if not is_locked(item)]
        if mode in ('episode_asc', 'episode_desc'):
            reverse = mode == 'episode_desc'
            movable.sort(
                key=lambda item: (
                    _yt_queue_series_key(item),
                    _yt_queue_episode_no(item),
                    str(item.get('created_at') or ''),
                    str(item.get('project_dir') or ''),
                ),
                reverse=reverse
            )
        elif mode == 'created_asc':
            movable.sort(key=lambda item: (str(item.get('created_at') or ''), str(item.get('project_dir') or '')))
        elif mode == 'created_desc':
            movable.sort(key=lambda item: (str(item.get('created_at') or ''), str(item.get('project_dir') or '')), reverse=True)

        new_queue = []
        mov_iter = iter(movable)
        for i in range(len(_YT_UPLOAD_QUEUE)):
            if i in locked:
                new_queue.append(locked[i])
            else:
                new_queue.append(next(mov_iter))
        _YT_UPLOAD_QUEUE[:] = new_queue
        try:
            _save_youtube_upload_queue()
        except Exception:
            pass
        after = [str(x.get('title') or '') for x in _YT_UPLOAD_QUEUE]

    return jsonify({'ok': True, 'mode': mode, 'changed': before != after, 'count': len(after), 'locked': len(locked), 'items': after})


@app.route('/api/youtube/queue/reorder', methods=['POST'])
def reorder_yt_queue():
    data = request.json or {}
    proj_dir = str(data.get('project_dir') or '').strip()
    if not proj_dir:
        return jsonify({'error': 'Missing project_dir'}), 400
    try:
        to_index = int(data.get('to_index'))
    except Exception:
        return jsonify({'error': 'Missing/invalid to_index'}), 400

    def is_locked(item):
        return str((item or {}).get('status') or '').lower() == 'uploading'

    with _YT_UPLOAD_LOCK:
        n = len(_YT_UPLOAD_QUEUE)
        if n <= 1:
            return jsonify({'ok': True, 'changed': False, 'count': n})
        from_index = -1
        for i, item in enumerate(_YT_UPLOAD_QUEUE):
            if str(item.get('project_dir') or '') == proj_dir:
                from_index = i
                break
        if from_index < 0:
            return jsonify({'error': 'Project not found in upload queue'}), 404
        if is_locked(_YT_UPLOAD_QUEUE[from_index]):
            return jsonify({'error': 'Cannot move the item currently uploading'}), 409

        to_index = max(0, min(to_index, n))
        locked = {i: item for i, item in enumerate(_YT_UPLOAD_QUEUE) if is_locked(item)}
        movable_positions = [i for i in range(n) if i not in locked]
        movable = [_YT_UPLOAD_QUEUE[i] for i in movable_positions]
        from_slot = None
        for slot, item in enumerate(movable):
            if str(item.get('project_dir') or '') == proj_dir:
                from_slot = slot
                break
        if from_slot is None:
            return jsonify({'error': 'Project not movable'}), 409

        target_slot = sum(1 for pos in movable_positions if pos < to_index)
        if from_slot < target_slot:
            target_slot -= 1
        target_slot = max(0, min(target_slot, len(movable) - 1))
        if from_slot == target_slot:
            return jsonify({'ok': True, 'changed': False, 'from_index': from_index, 'to_index': to_index, 'count': n, 'locked': len(locked)})

        item = movable.pop(from_slot)
        movable.insert(target_slot, item)
        mov_iter = iter(movable)
        new_queue = []
        for i in range(n):
            if i in locked:
                new_queue.append(locked[i])
            else:
                new_queue.append(next(mov_iter))
        before = [str(x.get('project_dir') or '') for x in _YT_UPLOAD_QUEUE]
        _YT_UPLOAD_QUEUE[:] = new_queue
        try:
            _save_youtube_upload_queue()
        except Exception:
            pass
        after = [str(x.get('project_dir') or '') for x in _YT_UPLOAD_QUEUE]

    return jsonify({'ok': True, 'changed': before != after, 'from_index': from_index, 'to_index': to_index, 'count': len(after), 'locked': len(locked)})

def _douyin_watchdog_normalize_urls(raw) -> list:
    """Return deduped Douyin profile URLs from textarea/list config."""
    if isinstance(raw, list):
        candidates = raw
    else:
        candidates = re.split(r'[\r\n]+', str(raw or ''))
    urls = []
    seen = set()
    for item in candidates:
        s = str(item or '').strip()
        if not s:
            continue
        found = re.findall(r'https?://[^\s]+', s) or [s]
        for u in found:
            u = str(u or '').strip().strip('"\'<> ,;')
            if 'douyin.com' not in u:
                continue
            if u not in seen:
                seen.add(u)
                urls.append(u)
    return urls


def _douyin_watchdog_config_urls(cfg: dict) -> list:
    urls = _douyin_watchdog_normalize_urls(cfg.get('douyin_watchdog_user_urls'))
    if not urls:
        urls = _douyin_watchdog_normalize_urls(cfg.get('douyin_watchdog_user_url'))
    return urls


def _douyin_watchdog_user_key(user_url: str) -> str:
    m = re.search(r'/user/([^?&#/]+)', str(user_url or ''))
    raw = m.group(1) if m else str(user_url or '')
    key = re.sub(r'[^A-Za-z0-9_-]+', '_', raw).strip('_')[:120]
    return key or uuid.uuid5(uuid.NAMESPACE_URL, str(user_url or '')).hex[:16]


def _douyin_watchdog_load_cache() -> dict:
    try:
        if _DY_WATCHDOG_FILE.exists():
            data = json.loads(_DY_WATCHDOG_FILE.read_text(encoding='utf-8'))
            if isinstance(data, dict):
                return data
    except Exception:
        pass
    return {'users': {}}


def _douyin_watchdog_save_cache(data: dict):
    try:
        _DY_WATCHDOG_FILE.write_text(
            json.dumps(data or {}, ensure_ascii=False, indent=2),
            encoding='utf-8'
        )
    except Exception:
        pass


def _run_douyin_watchdog_once(force: bool = False):
    cfg = load_config()
    enabled = bool(cfg.get('douyin_watchdog_enabled', False))
    if not force and not enabled:
        return {'ok': True, 'skipped': True, 'reason': 'watchdog_disabled'}

    user_urls = _douyin_watchdog_config_urls(cfg)
    if not user_urls:
        return {'ok': False, 'error': 'douyin_watchdog_user_urls is empty/invalid'}

    try:
        min_duration_sec = float(cfg.get('douyin_watchdog_min_duration_sec', 60) or 60)
    except Exception:
        min_duration_sec = 60.0
    min_duration_sec = max(0.0, min_duration_sec)

    cache = _douyin_watchdog_load_cache()
    users_cache = cache.setdefault('users', {})
    all_queue_urls = []
    all_series_groups = []
    user_results = []
    total_new = 0

    for user_url in user_urls:
        user_key = _douyin_watchdog_user_key(user_url)
        user_cache = users_cache.setdefault(user_key, {})
        # Migrate old single-user cache without losing known ids.
        if cache.get('known_ids') and not user_cache.get('known_ids') and len(user_urls) == 1:
            user_cache['known_ids'] = cache.get('known_ids') or []
            cache.pop('known_ids', None)

        try:
            scan = scrape_user_videos(
                user_url,
                log_cb=lambda *_args, **_kwargs: None,
                min_duration_sec=min_duration_sec,
                oldest_first=True,
            )
        except Exception as ex:
            user_results.append({'user_url': user_url, 'ok': False, 'error': str(ex)[:300]})
            continue

        videos = list(scan.get('videos') or [])
        author = scan.get('author') or ''
        if not videos:
            user_results.append({'user_url': user_url, 'author': author, 'ok': True, 'new_count': 0, 'queued': 0, 'reason': 'no_videos'})
            continue

        known_ids = set(str(x) for x in (user_cache.get('known_ids') or []))
        id_to_video = {}
        for v in videos:
            vid = str(v.get('aweme_id') or '')
            if vid:
                id_to_video[vid] = v
        new_ids = [vid for vid in id_to_video.keys() if vid not in known_ids]
        user_cache['known_ids'] = list(id_to_video.keys())[-12000:]
        user_cache['last_author'] = author
        user_cache['last_scan_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
        user_cache['last_total'] = len(id_to_video)

        if not new_ids:
            user_results.append({'user_url': user_url, 'author': author, 'ok': True, 'new_count': 0, 'queued': 0, 'total': len(id_to_video)})
            continue

        grouped = group_videos_into_series(
            videos,
            ninerouter_url=cfg.get('ninerouter_url', 'http://127.0.0.1:20128'),
            ninerouter_key=cfg.get('ninerouter_key', ''),
            model=cfg.get('ninerouter_model', ''),
            timeout=max(300, int(cfg.get('ninerouter_timeout', 120) or 120)),
            log_cb=lambda *_args, **_kwargs: None,
        )
        folder_map = {}
        for g in grouped.get('groups', []) or []:
            folder = str(g.get('folder') or '').strip() or 'series_unknown'
            series_name = str(g.get('series_name_vi') or g.get('series_name') or folder).strip()
            for vid in (g.get('video_ids') or []):
                folder_map[str(vid)] = {'folder': folder, 'series_name': series_name}

        new_videos = [id_to_video[vid] for vid in new_ids if vid in id_to_video]
        new_videos.sort(key=lambda x: float(x.get('create_time') or 0))
        queue_urls = [v.get('url') for v in new_videos if v.get('url')]
        total_new += len(new_videos)
        all_queue_urls.extend(queue_urls)

        by_folder = {}
        for v in new_videos:
            vid = str(v.get('aweme_id') or '')
            meta = folder_map.get(vid) or {'folder': 'standalone', 'series_name': 'Standalone'}
            item = by_folder.setdefault(meta['folder'], {
                'user_url': user_url,
                'author': author,
                'folder': meta['folder'],
                'series_name': meta['series_name'],
                'count': 0,
                'urls': [],
            })
            item['count'] += 1
            if v.get('url'):
                item['urls'].append(v.get('url'))

        # Save per-series manifest folders so user can track continuous series buckets.
        try:
            series_root = BASE_DIR / 'series_watchdog' / user_key
            series_root.mkdir(parents=True, exist_ok=True)
            for fg in by_folder.values():
                folder = str(fg.get('folder') or 'standalone').strip() or 'standalone'
                sdir = series_root / folder
                sdir.mkdir(parents=True, exist_ok=True)
                (sdir / 'series_name.txt').write_text(str(fg.get('series_name') or folder), encoding='utf-8')
                (sdir / 'source_user.txt').write_text(str(user_url), encoding='utf-8')
                links_path = sdir / 'links.txt'
                existing = []
                if links_path.exists():
                    existing = [ln.strip() for ln in links_path.read_text(encoding='utf-8').splitlines() if ln.strip()]
                merged = existing + [u for u in (fg.get('urls') or []) if u and u not in existing]
                links_path.write_text('\n'.join(merged), encoding='utf-8')
        except Exception:
            pass

        groups = list(by_folder.values())
        all_series_groups.extend(groups)
        user_results.append({
            'user_url': user_url,
            'author': author,
            'ok': True,
            'new_count': len(new_videos),
            'queued': len(queue_urls),
            'total': len(id_to_video),
            'series_groups': groups[:10],
        })

    cache['user_urls'] = user_urls
    _douyin_watchdog_save_cache(cache)

    queue_out = {}
    if all_queue_urls:
        queue_out = _start_batch_pipeline_from_urls(all_queue_urls, start_from=0)

    return {
        'ok': True,
        'user_count': len(user_urls),
        'new_count': total_new,
        'queued': len(all_queue_urls),
        'queue_id': queue_out.get('queue_id'),
        'series_groups': all_series_groups[:20],
        'users': user_results,
    }

def _douyin_watchdog_loop():
    while True:
        try:
            cfg = load_config()
            interval_min = int(cfg.get('douyin_watchdog_interval_min', 15) or 15)
            interval_min = max(2, interval_min)
            if bool(cfg.get('douyin_watchdog_enabled', False)):
                with _DY_WATCHDOG_LOCK:
                    if not _DY_WATCHDOG_STATE['running']:
                        _DY_WATCHDOG_STATE['running'] = True
                        _DY_WATCHDOG_STATE['last_run_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
                if _DY_WATCHDOG_STATE['running']:
                    try:
                        out = _run_douyin_watchdog_once(force=False)
                        _DY_WATCHDOG_STATE['last_summary'] = (
                            f"new={out.get('new_count', 0)} queued={out.get('queued', 0)} "
                            f"queue={out.get('queue_id') or '-'}"
                        )
                        _DY_WATCHDOG_STATE['last_actions'] = (out.get('series_groups') or [])[:10]
                    except Exception as ex:
                        _DY_WATCHDOG_STATE['last_summary'] = f'watchdog error: {str(ex)[:200]}'
                    finally:
                        with _DY_WATCHDOG_LOCK:
                            _DY_WATCHDOG_STATE['running'] = False
            time.sleep(interval_min * 60)
        except Exception as ex:
            _DY_WATCHDOG_STATE['last_summary'] = f'watchdog loop error: {str(ex)[:200]}'
            time.sleep(60)

@app.route('/api/douyin/watchdog/state')
def douyin_watchdog_state():
    cfg = load_config()
    user_urls = _douyin_watchdog_config_urls(cfg)
    return jsonify({
        'running': _DY_WATCHDOG_STATE['running'],
        'last_run_at': _DY_WATCHDOG_STATE['last_run_at'],
        'last_summary': _DY_WATCHDOG_STATE['last_summary'],
        'last_actions': _DY_WATCHDOG_STATE.get('last_actions', []),
        'enabled': bool(cfg.get('douyin_watchdog_enabled', False)),
        'user_url': user_urls[0] if user_urls else '',
        'user_urls': user_urls,
        'user_count': len(user_urls),
        'interval_min': int(cfg.get('douyin_watchdog_interval_min', 15) or 15),
        'min_duration_sec': float(cfg.get('douyin_watchdog_min_duration_sec', 60) or 60),
    })

@app.route('/api/douyin/watchdog/config', methods=['POST'])
def douyin_watchdog_config():
    data = request.json or {}
    cfg = load_config()
    cfg['douyin_watchdog_enabled'] = bool(data.get('enabled', cfg.get('douyin_watchdog_enabled', False)))
    user_urls = _douyin_watchdog_normalize_urls(
        data.get('user_urls', data.get('user_url', cfg.get('douyin_watchdog_user_urls', cfg.get('douyin_watchdog_user_url', ''))))
    )
    cfg['douyin_watchdog_user_urls'] = user_urls
    cfg['douyin_watchdog_user_url'] = user_urls[0] if user_urls else ''
    try:
        cfg['douyin_watchdog_interval_min'] = max(2, int(data.get('interval_min', cfg.get('douyin_watchdog_interval_min', 15) or 15)))
    except Exception:
        cfg['douyin_watchdog_interval_min'] = 15
    try:
        cfg['douyin_watchdog_min_duration_sec'] = max(0.0, float(data.get('min_duration_sec', cfg.get('douyin_watchdog_min_duration_sec', 60) or 60)))
    except Exception:
        cfg['douyin_watchdog_min_duration_sec'] = 60.0
    save_config(cfg)
    return jsonify({'ok': True})

@app.route('/api/douyin/watchdog/run-once', methods=['POST'])
def douyin_watchdog_run_once():
    with _DY_WATCHDOG_LOCK:
        if _DY_WATCHDOG_STATE['running']:
            return jsonify({'ok': False, 'error': 'watchdog is already running'}), 409
        _DY_WATCHDOG_STATE['running'] = True
        _DY_WATCHDOG_STATE['last_run_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
    try:
        out = _run_douyin_watchdog_once(force=True)
        _DY_WATCHDOG_STATE['last_summary'] = (
            f"manual users={out.get('user_count', 0)} new={out.get('new_count', 0)} queued={out.get('queued', 0)} "
            f"queue={out.get('queue_id') or '-'}"
        )
        _DY_WATCHDOG_STATE['last_actions'] = (out.get('series_groups') or [])[:10]
        return jsonify({'ok': True, 'result': out})
    except Exception as ex:
        _DY_WATCHDOG_STATE['last_summary'] = f'manual error: {str(ex)[:200]}'
        return jsonify({'ok': False, 'error': str(ex)}), 500
    finally:
        with _DY_WATCHDOG_LOCK:
            _DY_WATCHDOG_STATE['running'] = False

@app.route('/api/proxy/image')
def proxy_image():
    """Proxy external images to avoid CORS issues with Douyin CDN."""
    img_url = request.args.get('url', '')
    if not img_url:
        return '', 404
    try:
        import requests as req
        r = req.get(img_url, timeout=10, headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                          'AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36',
            'Referer': 'https://www.douyin.com/'
        })
        from flask import Response
        return Response(r.content,
                       content_type=r.headers.get('content-type', 'image/jpeg'),
                       headers={'Cache-Control': 'public, max-age=86400'})
    except Exception:
        return '', 502

# Ã¢â€â‚¬Ã¢â€â‚¬ YouTube Auth Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
@app.route('/api/youtube/auth')
def youtube_auth():
    return jsonify(check_auth_status())

@app.route('/api/youtube/login', methods=['POST'])
def youtube_login():
    """Trigger OAuth flow Ã¢â‚¬â€ opens browser."""
    data = request.json or {}
    name = data.get('name', '').strip()
    token_file = None
    if name:
        name = re.sub(r'[^a-zA-Z0-9_-]', '', name)
        from modules.uploader import TOKEN_DIR
        token_file = str(TOKEN_DIR / f'youtube_token_{name}.pkl')
    try:
        from modules.uploader import get_youtube_service
        get_youtube_service(token_file=token_file)
        return jsonify({'ok': True})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 400

@app.route('/api/youtube/import-secrets', methods=['POST'])
def youtube_import():
    data = request.json or {}
    content = data.get('json', '')
    result = import_oauth_json(content)
    return jsonify(result)


@app.route('/api/youtube/logout', methods=['POST'])
def youtube_logout():
    """Logout a specific channel or the main one."""
    data = request.json or {}
    key = data.get('key', 'main').strip()
    from modules.uploader import TOKEN_FILE, get_token_path_by_key
    if key == 'main':
        tf = TOKEN_FILE
    else:
        tf = get_token_path_by_key(key)
    if not tf:
        return jsonify({'ok': True, 'message': 'Already removed'})
    if tf.exists():
        tf.unlink()
        cfg = load_config()
        channels_cfg = cfg.get('youtube_channels', {})
        channels_cfg.pop(key, None)
        cfg['youtube_channels'] = channels_cfg
        save_config(cfg)
        return jsonify({'ok': True, 'message': f'Removed channel [{key}]'})
    return jsonify({'ok': True, 'message': 'Already removed'})

@app.route('/api/youtube/toggle', methods=['POST'])
def youtube_toggle():
    """Enable/disable a YouTube channel."""
    data = request.json or {}
    key = data.get('key', '').strip()
    enabled = data.get('enabled', True)
    if not key:
        return jsonify({'error': 'Channel key required'}), 400
    cfg = load_config()
    channels_cfg = cfg.get('youtube_channels', {})
    if key not in channels_cfg:
        channels_cfg[key] = {}
    channels_cfg[key]['enabled'] = enabled
    cfg['youtube_channels'] = channels_cfg
    save_config(cfg)
    return jsonify({'ok': True, 'key': key, 'enabled': enabled})


def _safe_int(v, default=0, min_v=None, max_v=None):
    try:
        out = int(v)
    except Exception:
        out = int(default)
    if min_v is not None:
        out = max(min_v, out)
    if max_v is not None:
        out = min(max_v, out)
    return out


def _collect_uploaded_videos(token_file, max_results=25):
    """
    Collect multiple pages from YouTube uploads playlist so max_results can exceed 50.
    """
    target = _safe_int(max_results, default=25, min_v=1, max_v=2000)
    token = None
    pages = 0
    items = []
    channel_key = 'main'

    while len(items) < target and pages < 120:
        per_page = min(50, target - len(items))
        data = list_uploaded_videos(token_file=token_file, max_results=per_page, page_token=token)
        pages += 1
        channel_key = data.get('channel_key', channel_key)
        batch = data.get('items', []) or []
        if not batch:
            break
        items.extend(batch)
        token = data.get('next_page_token')
        if not token:
            break

    return {
        'items': items[:target],
        'next_page_token': token,
        'channel_key': channel_key,
        'pages': pages,
        'fetched': min(len(items), target),
    }


@app.route('/api/youtube/videos')
def youtube_videos_list():
    """List uploaded videos for a channel key."""
    key = (request.args.get('key') or request.args.get('channel_key') or 'main').strip() or 'main'
    max_results = _safe_int(request.args.get('max_results', 25), default=25, min_v=1, max_v=2000)
    page_token = request.args.get('page_token') or None
    tf = get_token_path_by_key(key)
    if not tf:
        return jsonify({'error': f'Token not found for channel [{key}]'}), 404
    try:
        if page_token:
            data = list_uploaded_videos(token_file=tf, max_results=min(max_results, 50), page_token=page_token)
        else:
            data = _collect_uploaded_videos(token_file=tf, max_results=max_results)
        return jsonify({'ok': True, 'channel_key': key, **data})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/youtube/playlist/sort', methods=['POST'])
def youtube_playlist_sort():
    """Sort a YouTube playlist for the selected channel token."""
    data = request.json or {}
    key = (data.get('key') or 'main').strip() or 'main'
    playlist_name = (data.get('playlist_name') or '').strip()
    playlist_id = (data.get('playlist_id') or '').strip()
    mode = (data.get('mode') or 'episode_asc').strip().lower()
    dry_run = bool(data.get('dry_run', False))
    if not playlist_name and not playlist_id:
        return jsonify({'ok': False, 'error': 'playlist_name or playlist_id is required'}), 400
    tf = get_token_path_by_key(key)
    if not tf:
        return jsonify({'ok': False, 'error': f'Token not found for channel [{key}]'}), 404
    try:
        out = sort_playlist(
            token_file=tf,
            playlist_name=playlist_name or None,
            playlist_id=playlist_id or None,
            mode=mode,
            dry_run=dry_run,
            log_cb=print,
        )
        return jsonify({'ok': True, 'channel_key': key, **out})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/youtube/videos/scan-match')
def youtube_videos_scan_match():
    """
    Scan uploaded YouTube videos and match with local projects.
    Priority: exact by saved youtube.videoId, else fuzzy by title+description.
    """
    key = (request.args.get('key') or request.args.get('channel_key') or 'main').strip() or 'main'
    max_results = _safe_int(request.args.get('max_results', 25), default=25, min_v=1, max_v=2000)
    tf = get_token_path_by_key(key)
    if not tf:
        return jsonify({'error': f'Token not found for channel [{key}]'}), 404
    try:
        data = _collect_uploaded_videos(token_file=tf, max_results=max_results)
        by_video_id, fuzzy_index = _build_youtube_project_match_index(channel_key=key)
        rows = []
        matched = 0
        for v in data.get('items', []):
            vid = (v.get('video_id') or '').strip()
            match = None
            source = 'none'

            # 1) exact match by saved youtube.videoId
            exact = by_video_id.get(vid)
            if exact:
                pname, info = exact
                ppath = info.get('project_path') or os.path.dirname(info.get('info_path', '') or '')
                match = {
                    'project_name': pname,
                    'score': 1.0,
                    'title_score': 1.0,
                    'desc_score': 1.0,
                    'has_final_video': bool(info and os.path.exists(info.get('final_video', os.path.join(ppath or '', 'final_video.mp4')))),
                    'has_metadata': bool(info and info.get('metadata')),
                    'youtube_saved': bool(info and info.get('youtube')),
                }
                source = 'video_id'
            else:
                # 2) fuzzy by title/description
                best = _best_project_match_for_video_indexed(v.get('title', ''), v.get('description', ''), fuzzy_index)
                if best and best['score'] >= 0.72:
                    ppath, info = _load_project_info_by_name(best['project_name'])
                    best['has_final_video'] = bool(info and os.path.exists(info.get('final_video', os.path.join(ppath or '', 'final_video.mp4'))))
                    best['has_metadata'] = bool(info and info.get('metadata'))
                    best['youtube_saved'] = bool(info and info.get('youtube'))
                    match = best
                    source = 'fuzzy'

            if match:
                matched += 1
            rows.append({
                'video': v,
                'match': match,
                'match_source': source
            })
        return jsonify({
            'ok': True,
            'channel_key': key,
            'total_videos': len(rows),
            'matched': matched,
            'pages': data.get('pages', 1),
            'rows': rows
        })
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/youtube/videos/delete', methods=['POST'])
def youtube_video_delete():
    data = request.json or {}
    key = (data.get('key') or 'main').strip() or 'main'
    video_id = (data.get('video_id') or '').strip()
    if not video_id:
        return jsonify({'error': 'video_id required'}), 400
    tf = get_token_path_by_key(key)
    if not tf:
        return jsonify({'error': f'Token not found for channel [{key}]'}), 404
    try:
        res = delete_video(video_id, token_file=tf)
        pname, pinfo = _find_project_by_video(video_id, channel_key=key)
        if pname and pinfo:
            ppath, info = _load_project_info_by_name(pname)
            if ppath and info:
                wd = info.get('youtube_watchdog') or {}
                wd['last_action'] = 'deleted'
                wd['last_status'] = 'deleted'
                wd['last_error'] = ''
                wd['last_checked_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
                info['youtube_watchdog'] = wd
                _save_project_info(ppath, info)
        return jsonify({'ok': True, **res})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/youtube/videos/reupload', methods=['POST'])
def youtube_video_reupload():
    """
    Reupload by project.
    Body: {project_name, key?, delete_old?, old_video_id?}
    """
    data = request.json or {}
    project_name = (data.get('project_name') or '').strip()
    video_id = (data.get('video_id') or '').strip()
    key = (data.get('key') or '').strip() or None
    delete_old = bool(data.get('delete_old', True))
    old_video_id = (data.get('old_video_id') or '').strip() or None
    if not project_name and not video_id:
        return jsonify({'error': 'project_name or video_id required'}), 400
    if not project_name and video_id:
        found_name, _ = _find_project_by_video(video_id, channel_key=key)
        if not found_name:
            return jsonify({'error': f'No project found for video_id={video_id}'}), 404
        project_name = found_name
    try:
        up = _reupload_project_video(
            project_name=project_name,
            delete_old=delete_old,
            old_video_id=old_video_id or video_id,
            channel_key=key,
            log_prefix='[manual-reupload] '
        )
        return jsonify({'ok': True, 'project_name': project_name, 'upload': up})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/youtube/watchdog/state')
def youtube_watchdog_state():
    cfg = load_config()
    return jsonify({
        'ok': True,
        'enabled': bool(cfg.get('youtube_watchdog_enabled', False)),
        'interval_min': int(cfg.get('youtube_watchdog_interval_min', 15) or 15),
        'stuck_minutes': int(cfg.get('youtube_watchdog_stuck_minutes', 120) or 120),
        'max_retries': int(cfg.get('youtube_watchdog_max_retries', 2) or 2),
        'min_views_to_skip': int(cfg.get('youtube_watchdog_min_views_to_skip', 1) or 1),
        'running': _YT_WATCHDOG_STATE.get('running', False),
        'last_run_at': _YT_WATCHDOG_STATE.get('last_run_at'),
        'last_summary': _YT_WATCHDOG_STATE.get('last_summary', ''),
        'last_actions': _YT_WATCHDOG_STATE.get('last_actions', []),
    })


@app.route('/api/youtube/watchdog/run-once', methods=['POST'])
def youtube_watchdog_run_once():
    if not _YT_WATCHDOG_LOCK.acquire(blocking=False):
        return jsonify({'ok': False, 'error': 'watchdog is already running'}), 409
    try:
        _YT_WATCHDOG_STATE['running'] = True
        result = _run_youtube_watchdog_once()
        _YT_WATCHDOG_STATE['last_run_at'] = time.strftime('%Y-%m-%d %H:%M:%S')
        _YT_WATCHDOG_STATE['last_actions'] = result.get('actions', [])
        _YT_WATCHDOG_STATE['last_summary'] = f"checked={result.get('checked',0)} actions={len(result.get('actions', []))}"
        return jsonify({'ok': True, **result})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500
    finally:
        _YT_WATCHDOG_STATE['running'] = False
        _YT_WATCHDOG_LOCK.release()

# Ã¢â€â‚¬Ã¢â€â‚¬ Upload intro Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
@app.route('/api/tiktok/auth')
def tiktok_auth():
    cfg = load_config()
    browser = tiktok_auth_status()
    api_st = tiktok_api_status(cfg)
    return jsonify({
        **browser,
        'browser': browser,
        'api': api_st,
        'ok': bool(browser.get('ok') or api_st.get('ok')),
    })


@app.route('/api/tiktok/oauth/start')
def tiktok_oauth_start():
    cfg = load_config()
    try:
        state = str(uuid.uuid4())
        # Most new TikTok developer apps require PKCE. Default to True to prevent 'code_challenge' error.
        use_pkce = bool(cfg.get('tiktok_api_use_pkce', True))
        pkce_mode = str(cfg.get('tiktok_api_pkce_challenge_format') or 'hex').strip().lower()
        if pkce_mode not in ('hex', 'base64url'):
            pkce_mode = 'hex'
        bundle = {'exp': int(time.time()) + 900, 'pkce_mode': pkce_mode}
        code_challenge = None
        if use_pkce:
            code_verifier, code_challenge = make_pkce_pair(mode=pkce_mode)
            bundle['code_verifier'] = code_verifier
        
        # Persist to disk so code_verifier survives server restarts
        _tiktok_state_save(state, bundle)
        auth_url = tiktok_build_auth_url(cfg, state, code_challenge=code_challenge)
        if request.args.get('redirect') == '1':
            return redirect(auth_url)
        return jsonify({'ok': True, 'auth_url': auth_url, 'state': state, 'pkce': use_pkce, 'pkce_mode': pkce_mode})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/tiktok/oauth/callback')
def tiktok_oauth_callback():
    code = (request.args.get('code') or '').strip()
    state = (request.args.get('state') or '').strip()
    err = (request.args.get('error') or '').strip()
    err_desc = (request.args.get('error_description') or '').strip()

    if err:
        return f"<h3>TikTok OAuth failed</h3><p>{err}: {err_desc}</p>", 400
    if not code:
        return "<h3>TikTok OAuth failed</h3><p>Missing authorization code.</p>", 400
    if not state:
        return "<h3>TikTok OAuth failed</h3><p>Missing state parameter.</p>", 400

    bundle = _tiktok_state_pop(state)
    if not bundle:
        return "<h3>TikTok OAuth failed</h3><p>Invalid or expired state Ã¢â‚¬â€ please start the OAuth flow again.</p>", 400

    code_verifier = bundle.get('code_verifier')
    pkce_mode = bundle.get('pkce_mode') or 'hex'

    try:
        cfg = load_config()
        tok = tiktok_exchange_code(cfg, code, code_verifier=code_verifier)
        return (
            "<html><body style='font-family:sans-serif;padding:20px'>"
            "<h3>TikTok API connected</h3>"
            f"<p>open_id: {tok.get('open_id','?')}</p>"
            "<p>You can close this tab and return to app.</p>"
            "<script>setTimeout(function(){window.close();},1200);</script>"
            "</body></html>"
        )
    except Exception as e:
        # Debugging info to diagnose 'Code verifier or code challenge is invalid'
        cv_preview = code_verifier[:10] + "..." if code_verifier else "None"
        debug_msg = f"State: {state}<br>PKCE mode: {pkce_mode}<br>Code Verifier used: {cv_preview}<br>Error: {str(e)}"
        return f"<h3>TikTok OAuth token exchange failed</h3><pre>{debug_msg}</pre>", 500


@app.route('/api/tiktok/api/status')
def tiktok_api_status_route():
    cfg = load_config()
    out = tiktok_api_status(cfg)
    if out.get('ok'):
        # Run the network-dependent creator_info call in a background thread so
        # the endpoint always responds quickly even when open.tiktokapis.com is
        # geo-blocked / slow (would otherwise freeze the Flask thread for 60s).
        result_box = [None]
        error_box = [None]

        def _fetch():
            try:
                access_token = tiktok_get_valid_access_token(cfg)
                creator = tiktok_query_creator_info(access_token)
                result_box[0] = creator
            except Exception as ex:
                error_box[0] = str(ex)

        t = threading.Thread(target=_fetch, daemon=True)
        t.start()
        t.join(timeout=15)   # wait up to 15 s; return immediately if timed out

        if result_box[0] is not None:
            creator = result_box[0]
            out['creator'] = {
                'username': creator.get('creator_username'),
                'nickname': creator.get('creator_nickname'),
                'privacy_level_options': creator.get('privacy_level_options') or [],
                'max_video_post_duration_sec': creator.get('max_video_post_duration_sec'),
            }
        else:
            out['creator_error'] = error_box[0] or 'Timeout fetching creator info (open.tiktokapis.com unreachable Ã¢â‚¬â€ enable proxy in Settings)'
    return jsonify({'ok': True, **out})



@app.route('/api/tiktok/api/disconnect', methods=['POST'])
def tiktok_api_disconnect():
    try:
        return jsonify(tiktok_disconnect_api())
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/tiktok/login', methods=['POST'])
def tiktok_login():
    try:
        lid = launch_tiktok_login(log_cb=print)
        return jsonify({'ok': True, 'login_id': lid})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/tiktok/login/<login_id>')
def tiktok_login_status(login_id):
    job = get_tiktok_login_job(login_id)
    if not job:
        return jsonify({'error': 'login job not found'}), 404
    return jsonify(job)


@app.route('/api/tiktok/import-browser', methods=['POST'])
def tiktok_import_browser():
    data = request.json or {}
    browser = (data.get('browser') or 'edge').strip().lower()
    profile = (data.get('profile') or '').strip() or None
    try:
        res = import_tiktok_storage_from_browser(browser=browser, profile=profile, log_cb=print)
        return jsonify({'ok': True, **res})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/tiktok/import-cookies-text', methods=['POST'])
def tiktok_import_cookies_text():
    data = request.json or {}
    cookies_text = data.get('cookies_text') or ''
    try:
        res = import_tiktok_storage_from_cookies_text(cookies_text)
        return jsonify({'ok': True, **res})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


def _prepare_tiktok_parts_and_captions(final_video: str, metadata: dict, cfg: dict, project_dir: str):
    max_minutes = int(cfg.get('tiktok_max_minutes', 10) or 10)
    max_minutes = max(1, max_minutes)
    auto_split = bool(cfg.get('tiktok_auto_split', True))
    cap_limit = int(cfg.get('tiktok_caption_max_chars', 255) or 255)
    cap_limit = max(60, min(cap_limit, 255))

    if auto_split:
        parts = split_video_for_tiktok(final_video, project_dir, max_minutes=max_minutes, log_cb=print)
    else:
        parts = [{
            'path': final_video,
            'part_index': 1,
            'total_parts': 1,
            'duration_sec': float(get_media_duration(final_video) or 0)
        }]

    title = (metadata or {}).get('title', 'Untitled')
    desc = (metadata or {}).get('description', '')
    tags = (metadata or {}).get('tags', []) or []
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
    return parts, captions, max_minutes, auto_split


def _run_tiktok_upload_payload(data: dict, progress_cb=None, log_cb=print):
    cfg = load_config()

    project_name = (data.get('project_name') or '').strip()
    video_path = (data.get('video_path') or '').strip()
    dry_run = bool(data.get('dry_run', False))

    info = {}
    project_dir = None
    if project_name:
        project_dir, info = _load_project_info_by_name(project_name)
        if not project_dir or not info:
            raise RuntimeError(f'Project not found: {project_name}')
        final_video = info.get('final_video') or os.path.join(project_dir, 'final_video.mp4')
        metadata = info.get('metadata') or {}
    else:
        final_video = video_path
        metadata = data.get('metadata') or {}
        if not final_video or not os.path.exists(final_video):
            raise RuntimeError('video_path not found')
        project_dir = os.path.dirname(final_video)

    local_cfg = dict(cfg)
    if data.get('max_minutes') is not None:
        local_cfg['tiktok_max_minutes'] = int(data.get('max_minutes') or 10)
    if data.get('auto_split') is not None:
        local_cfg['tiktok_auto_split'] = bool(data.get('auto_split'))
    if data.get('caption_max_chars') is not None:
        local_cfg['tiktok_caption_max_chars'] = int(data.get('caption_max_chars') or 255)
    if data.get('headless') is not None:
        local_cfg['tiktok_headless'] = bool(data.get('headless'))
    if data.get('provider'):
        local_cfg['tiktok_upload_provider'] = str(data.get('provider')).strip()

    if not os.path.exists(final_video):
        raise RuntimeError(f'Final video missing: {final_video}')

    parts, captions, max_minutes, auto_split = _prepare_tiktok_parts_and_captions(
        final_video=final_video,
        metadata=metadata,
        cfg=local_cfg,
        project_dir=project_dir
    )
    if dry_run:
        return {
            'ok': True,
            'mode': 'dry_run',
            'provider': str(local_cfg.get('tiktok_upload_provider') or 'official_api').strip().lower(),
            'project_name': project_name or None,
            'part_count': len(parts),
            'max_minutes': max_minutes,
            'auto_split': auto_split,
            'parts': [{
                'path': p.get('path'),
                'part_index': p.get('part_index'),
                'total_parts': p.get('total_parts'),
                'duration_sec': p.get('duration_sec'),
                'caption_preview': captions[i][:255]
            } for i, p in enumerate(parts)]
        }

    provider = str(local_cfg.get('tiktok_upload_provider') or 'official_api').strip().lower()
    timeout_sec = int(local_cfg.get('tiktok_upload_timeout_sec', 240) or 240)
    results = []
    try:
        log_cb(f"[TikTok] Provider={provider} | parts={len(parts)} | project={project_name or '-'}")
    except Exception:
        pass
    if provider == 'official_api':
        total = len(parts)
        for i, part in enumerate(parts):
            part_label = f"{part.get('part_index', i+1)}/{part.get('total_parts', total)}"
            part_path = part.get('path')
            cap = captions[i] if i < len(captions) else ''
            try:
                log_cb(f"[TikTok] Upload part {part_label} start: {os.path.basename(part_path or '')}")
            except Exception:
                pass

            def _part_progress(p: dict):
                if not progress_cb:
                    return
                phase_pct = int((p or {}).get('pct') or 0)
                overall_pct = int(((i + (phase_pct / 100.0)) / max(total, 1)) * 100)
                msg = (p or {}).get('message') or f'Uploading part {part_label}'
                progress_cb({
                    'done': i,
                    'total': total,
                    'pct': overall_pct,
                    'status': (p or {}).get('phase') or 'uploading',
                    'message': f'[{part_label}] {msg}',
                })

            try:
                out = tiktok_direct_post_video(
                    cfg=local_cfg,
                    video_path=part_path,
                    caption=cap,
                    progress_cb=_part_progress,
                    log_cb=log_cb,
                )
                results.append({
                    'ok': out.get('status') in ('PUBLISH_COMPLETE', 'SEND_TO_USER_INBOX'),
                    'part': part_label,
                    'file': part_path,
                    'mode': out.get('mode'),
                    'publish_id': out.get('publish_id'),
                    'status': out.get('status'),
                    'fail_reason': out.get('fail_reason'),
                    'public_post_ids': out.get('public_post_ids') or [],
                })
                try:
                    log_cb(
                        f"[TikTok] Upload part {part_label} done"
                        f" | mode={out.get('mode') or 'direct_post'}"
                        f" | status={out.get('status') or '-'}"
                        f" | publish_id={out.get('publish_id') or '-'}"
                    )
                except Exception:
                    pass
                if progress_cb:
                    progress_cb({
                        'done': i + 1,
                        'total': total,
                        'pct': int(((i + 1) / max(total, 1)) * 100),
                        'status': 'done_part',
                        'message': f'Uploaded part {part_label}',
                    })
            except Exception as ex:
                results.append({
                    'ok': False,
                    'part': part_label,
                    'file': part_path,
                    'error': str(ex),
                })
                try:
                    log_cb(f"[TikTok] Upload part {part_label} failed: {ex}")
                except Exception:
                    pass
                if progress_cb:
                    progress_cb({
                        'done': i + 1,
                        'total': total,
                        'pct': int(((i + 1) / max(total, 1)) * 100),
                        'status': 'failed_part',
                        'message': f'Part {part_label} failed',
                        'error': str(ex),
                    })
    else:
        headless = bool(local_cfg.get('tiktok_headless', False))
        try:
            log_cb(f"[TikTok] Browser automation mode | headless={headless}")
        except Exception:
            pass
        results = upload_tiktok_videos(
            parts,
            captions,
            log_cb=log_cb,
            progress_cb=progress_cb,
            headless=headless,
            upload_timeout_sec=timeout_sec
        )
    ok_count = sum(1 for r in results if r.get('ok'))
    try:
        log_cb(f"[TikTok] Upload summary: {ok_count}/{len(parts)} part(s) success")
    except Exception:
        pass

    if project_name and project_dir and info is not None:
        tk = info.get('tiktok') or {}
        tk.update({
            'uploaded_at': time.strftime('%Y-%m-%d %H:%M:%S'),
            'source_video': final_video,
            'max_minutes': max_minutes,
            'auto_split': auto_split,
            'part_count': len(parts),
            'ok_count': ok_count,
            'results': results,
        })
        info['tiktok'] = tk
        if 'steps_completed' in info and ok_count == len(parts):
            if 'upload_tiktok' not in info['steps_completed']:
                info['steps_completed'].append('upload_tiktok')
        _save_project_info(project_dir, info)

    return {
        'ok': True,
        'provider': provider,
        'source_video': final_video,
        'project_name': project_name or None,
        'part_count': len(parts),
        'ok_count': ok_count,
        'results': results
    }


@app.route('/api/tiktok/upload', methods=['POST'])
def tiktok_upload():
    data = request.json or {}
    try:
        out = _run_tiktok_upload_payload(data)
        return jsonify(out)
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/tiktok/upload/start', methods=['POST'])
def tiktok_upload_start():
    data = request.json or {}
    job_id = str(uuid.uuid4())[:8]

    with _TIKTOK_UPLOAD_LOCK:
        _TIKTOK_UPLOAD_JOBS[job_id] = {
            'job_id': job_id,
            'status': 'queued',
            'created_at': time.strftime('%Y-%m-%d %H:%M:%S'),
            'progress': {'done': 0, 'total': 0, 'pct': 0, 'status': 'queued', 'message': 'Queued...'},
            'logs': [],
            'result': None,
            'error': None,
        }

    def _worker():
        def _log(msg: str):
            with _TIKTOK_UPLOAD_LOCK:
                job = _TIKTOK_UPLOAD_JOBS.get(job_id)
                if not job:
                    return
                job['logs'].append(fix_mojibake_text(msg))
                if len(job['logs']) > 500:
                    job['logs'] = job['logs'][-500:]

        def _progress(p: dict):
            with _TIKTOK_UPLOAD_LOCK:
                job = _TIKTOK_UPLOAD_JOBS.get(job_id)
                if not job:
                    return
                job['progress'] = dict(p or {})

        with _TIKTOK_UPLOAD_LOCK:
            if job_id in _TIKTOK_UPLOAD_JOBS:
                _TIKTOK_UPLOAD_JOBS[job_id]['status'] = 'running'

        try:
            out = _run_tiktok_upload_payload(data, progress_cb=_progress, log_cb=_log)
            with _TIKTOK_UPLOAD_LOCK:
                job = _TIKTOK_UPLOAD_JOBS.get(job_id)
                if job:
                    job['status'] = 'done'
                    job['result'] = out
                    if not job.get('progress'):
                        job['progress'] = {'done': out.get('part_count', 0), 'total': out.get('part_count', 0), 'pct': 100, 'status': 'finished', 'message': 'Done'}
        except Exception as ex:
            with _TIKTOK_UPLOAD_LOCK:
                job = _TIKTOK_UPLOAD_JOBS.get(job_id)
                if job:
                    job['status'] = 'error'
                    job['error'] = str(ex)

    threading.Thread(target=_worker, daemon=True).start()
    return jsonify({'ok': True, 'job_id': job_id})


@app.route('/api/tiktok/upload/<job_id>')
def tiktok_upload_status(job_id):
    with _TIKTOK_UPLOAD_LOCK:
        job = _TIKTOK_UPLOAD_JOBS.get(job_id)
        if not job:
            return jsonify({'ok': False, 'error': 'job not found'}), 404
        return jsonify(job)


def _run_facebook_reels_upload_payload(data: dict, progress_cb=None, log_cb=print):
    cfg = load_config()

    project_name = (data.get('project_name') or '').strip()
    video_path = (data.get('video_path') or '').strip()
    dry_run = bool(data.get('dry_run', False))

    info = {}
    project_dir = None
    if project_name:
        project_dir, info = _load_project_info_by_name(project_name)
        if not project_dir or not info:
            raise RuntimeError(f'Project not found: {project_name}')
        tiktok_video = info.get('final_video_tiktok') or os.path.join(project_dir, 'final_video_tiktok.mp4')
        final_video_default = info.get('final_video') or os.path.join(project_dir, 'final_video.mp4')
        final_video = tiktok_video if os.path.exists(tiktok_video) else final_video_default
        metadata = info.get('metadata') or {}
    else:
        final_video = video_path
        metadata = data.get('metadata') or {}
        if not final_video or not os.path.exists(final_video):
            raise RuntimeError('video_path not found')
        project_dir = os.path.dirname(final_video)

    if not os.path.exists(final_video):
        raise RuntimeError(f'Final video missing: {final_video}')

    local_cfg = dict(cfg)
    if data.get('max_minutes') is not None:
        local_cfg['facebook_reels_max_minutes'] = int(data.get('max_minutes') or 10)
    if data.get('auto_split') is not None:
        local_cfg['facebook_reels_auto_split'] = bool(data.get('auto_split'))
    if data.get('caption_max_chars') is not None:
        local_cfg['facebook_reels_caption_max_chars'] = int(data.get('caption_max_chars') or 255)
    if data.get('video_state'):
        local_cfg['facebook_reels_video_state'] = str(data.get('video_state')).strip().upper()

    split_cfg = dict(local_cfg)
    split_cfg['tiktok_max_minutes'] = int(local_cfg.get('facebook_reels_max_minutes') or local_cfg.get('tiktok_max_minutes') or 10)
    split_cfg['tiktok_auto_split'] = bool(local_cfg.get('facebook_reels_auto_split', local_cfg.get('tiktok_auto_split', True)))
    split_cfg['tiktok_caption_max_chars'] = int(
        local_cfg.get('facebook_reels_caption_max_chars')
        or local_cfg.get('tiktok_caption_max_chars')
        or 255
    )

    parts, captions, max_minutes, auto_split = _prepare_tiktok_parts_and_captions(
        final_video=final_video,
        metadata=metadata,
        cfg=split_cfg,
        project_dir=project_dir
    )
    # Facebook rule: if there is no real split (single part), do not keep "Tap 1/1" prefix.
    for i, part in enumerate(parts):
        total_parts = int(part.get('total_parts') or len(parts) or 1)
        if total_parts <= 1 and i < len(captions):
            captions[i] = re.sub(r'^\s*Tap\s+\d+/\d+\s*\|\s*', '', str(captions[i] or ''), flags=re.IGNORECASE).strip()

    if dry_run:
        return {
            'ok': True,
            'mode': 'dry_run',
            'project_name': project_name or None,
            'part_count': len(parts),
            'max_minutes': max_minutes,
            'auto_split': auto_split,
            'video_state': str(local_cfg.get('facebook_reels_video_state') or 'PUBLISHED').upper(),
            'parts': [{
                'path': p.get('path'),
                'part_index': p.get('part_index'),
                'total_parts': p.get('total_parts'),
                'duration_sec': p.get('duration_sec'),
                'caption_preview': captions[i][:255],
            } for i, p in enumerate(parts)]
        }

    results = []
    total = len(parts)
    for i, part in enumerate(parts):
        part_label = f"{part.get('part_index', i + 1)}/{part.get('total_parts', total)}"
        part_path = part.get('path')
        cap = captions[i] if i < len(captions) else ''

        try:
            log_cb(f"[Facebook] Upload part {part_label} start: {os.path.basename(part_path or '')}")
        except Exception:
            pass

        def _part_progress(p: dict):
            if not progress_cb:
                return
            phase_pct = int((p or {}).get('pct') or 0)
            overall_pct = int(((i + (phase_pct / 100.0)) / max(total, 1)) * 100)
            msg = (p or {}).get('message') or f'Uploading part {part_label}'
            progress_cb({
                'done': i,
                'total': total,
                'pct': overall_pct,
                'status': (p or {}).get('phase') or 'uploading',
                'message': f'[{part_label}] {msg}',
            })

        try:
            out = facebook_upload_reel(
                video_path=part_path,
                caption=cap,
                cfg=local_cfg,
                title=(metadata or {}).get('title') or '',
                progress_cb=_part_progress,
                log_cb=log_cb,
            )
            status_obj = out.get('status') or {}
            status_text = ''
            if isinstance(status_obj, dict):
                publishing = ((status_obj.get('publishing_phase') or {}).get('status') or '').strip()
                processing = ((status_obj.get('processing_phase') or {}).get('status') or '').strip()
                video_st = (status_obj.get('video_status') or '').strip()
                status_text = '/'.join([s for s in [publishing, processing, video_st] if s]) or ''
            results.append({
                'ok': bool(out.get('ok')),
                'part': part_label,
                'file': part_path,
                'video_id': out.get('video_id'),
                'timeout': bool(out.get('timeout')),
                'status': status_text,
                'raw_status': status_obj,
            })
            if progress_cb:
                progress_cb({
                    'done': i + 1,
                    'total': total,
                    'pct': int(((i + 1) / max(total, 1)) * 100),
                    'status': 'done_part',
                    'message': f'Uploaded part {part_label}',
                })
        except Exception as ex:
            results.append({
                'ok': False,
                'part': part_label,
                'file': part_path,
                'error': str(ex),
            })
            if progress_cb:
                progress_cb({
                    'done': i + 1,
                    'total': total,
                    'pct': int(((i + 1) / max(total, 1)) * 100),
                    'status': 'failed_part',
                    'message': f'Part {part_label} failed',
                    'error': str(ex),
                })
            try:
                log_cb(f"[Facebook] Upload part {part_label} failed: {ex}")
            except Exception:
                pass

    ok_count = sum(1 for r in results if r.get('ok'))

    if project_name and project_dir and info is not None:
        fb = info.get('facebook_reels') or {}
        fb.update({
            'uploaded_at': time.strftime('%Y-%m-%d %H:%M:%S'),
            'max_minutes': max_minutes,
            'auto_split': auto_split,
            'part_count': len(parts),
            'ok_count': ok_count,
            'results': results,
        })
        info['facebook_reels'] = fb
        if 'steps_completed' in info and ok_count == len(parts):
            if 'upload_facebook_reels' not in info['steps_completed']:
                info['steps_completed'].append('upload_facebook_reels')
        _save_project_info(project_dir, info)

    return {
        'ok': True,
        'project_name': project_name or None,
        'part_count': len(parts),
        'ok_count': ok_count,
        'results': results,
    }


@app.route('/api/facebook/reels/status')
def facebook_reels_status_route():
    cfg = load_config()
    out = facebook_reels_status(cfg)
    want_check = str(request.args.get('check') or '0').strip().lower() in ('1', 'true', 'yes')
    if want_check:
        check = facebook_reels_check_access(cfg)
        out['check'] = check
        out['ok'] = bool(out.get('configured') and check.get('ok'))
    return jsonify({'ok': True, **out})


@app.route('/api/facebook/reels/fetch-pages-with-token', methods=['POST'])
def facebook_reels_fetch_pages_with_token():
    data = request.json or {}
    user_token = (data.get('user_token') or '').strip()
    app_id = (data.get('app_id') or '').strip()
    app_secret = (data.get('app_secret') or '').strip()

    if not user_token:
        return jsonify({'ok': False, 'error': 'Missing user_token'}), 400

    cfg = load_config()
    graph_ver = str(cfg.get('facebook_graph_version') or 'v22.0').strip() or 'v22.0'
    actual_token = user_token

    try:
        import requests as _req

        if app_id and app_secret:
            exchange_url = f'https://graph.facebook.com/{graph_ver}/oauth/access_token'
            params = {
                'grant_type': 'fb_exchange_token',
                'client_id': app_id,
                'client_secret': app_secret,
                'fb_exchange_token': user_token,
            }
            resp = _req.get(exchange_url, params=params, timeout=30)
            if resp.status_code == 200:
                actual_token = (resp.json() or {}).get('access_token') or user_token
            else:
                return jsonify({'ok': False, 'error': f'Long-lived token exchange failed: {resp.text[:400]}'}), 400

        pages_url = f'https://graph.facebook.com/{graph_ver}/me/accounts'
        pages_resp = _req.get(pages_url, params={'access_token': actual_token}, timeout=30)
        if pages_resp.status_code != 200:
            err = ''
            try:
                err = (pages_resp.json() or {}).get('error', {}).get('message') or ''
            except Exception:
                pass
            return jsonify({'ok': False, 'error': err or pages_resp.text[:400]}), 400

        pages_data = (pages_resp.json() or {}).get('data') or []
        return jsonify({
            'ok': True,
            'graph_version': graph_ver,
            'pages': pages_data,
            'long_lived_token': actual_token if actual_token != user_token else None,
        })
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/facebook/reels/upload', methods=['POST'])
def facebook_reels_upload():
    data = request.json or {}
    try:
        out = _run_facebook_reels_upload_payload(data)
        return jsonify(out)
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/facebook/reels/upload/start', methods=['POST'])
def facebook_reels_upload_start():
    data = request.json or {}
    job_id = str(uuid.uuid4())[:8]

    with _FB_REELS_UPLOAD_LOCK:
        _FB_REELS_UPLOAD_JOBS[job_id] = {
            'job_id': job_id,
            'status': 'queued',
            'created_at': time.strftime('%Y-%m-%d %H:%M:%S'),
            'progress': {'done': 0, 'total': 0, 'pct': 0, 'status': 'queued', 'message': 'Queued...'},
            'logs': [],
            'result': None,
            'error': None,
        }

    def _worker():
        def _log(msg: str):
            with _FB_REELS_UPLOAD_LOCK:
                job = _FB_REELS_UPLOAD_JOBS.get(job_id)
                if not job:
                    return
                job['logs'].append(fix_mojibake_text(msg))
                if len(job['logs']) > 500:
                    job['logs'] = job['logs'][-500:]

        def _progress(p: dict):
            with _FB_REELS_UPLOAD_LOCK:
                job = _FB_REELS_UPLOAD_JOBS.get(job_id)
                if not job:
                    return
                job['progress'] = dict(p or {})

        with _FB_REELS_UPLOAD_LOCK:
            if job_id in _FB_REELS_UPLOAD_JOBS:
                _FB_REELS_UPLOAD_JOBS[job_id]['status'] = 'running'

        try:
            out = _run_facebook_reels_upload_payload(data, progress_cb=_progress, log_cb=_log)
            with _FB_REELS_UPLOAD_LOCK:
                job = _FB_REELS_UPLOAD_JOBS.get(job_id)
                if job:
                    job['status'] = 'done'
                    job['result'] = out
                    if not job.get('progress'):
                        job['progress'] = {'done': out.get('part_count', 0), 'total': out.get('part_count', 0), 'pct': 100, 'status': 'finished', 'message': 'Done'}
        except Exception as ex:
            with _FB_REELS_UPLOAD_LOCK:
                job = _FB_REELS_UPLOAD_JOBS.get(job_id)
                if job:
                    job['status'] = 'error'
                    job['error'] = str(ex)

    threading.Thread(target=_worker, daemon=True).start()
    return jsonify({'ok': True, 'job_id': job_id})


@app.route('/api/facebook/reels/upload/<job_id>')
def facebook_reels_upload_status(job_id):
    with _FB_REELS_UPLOAD_LOCK:
        job = _FB_REELS_UPLOAD_JOBS.get(job_id)
        if not job:
            return jsonify({'ok': False, 'error': 'job not found'}), 404
        return jsonify(job)


@app.route('/api/intro/upload', methods=['POST'])
def upload_intro():
    if 'file' not in request.files:
        return jsonify({'error': 'No file'}), 400
    f = request.files['file']
    intro_dir = str(BASE_DIR / 'intros')
    os.makedirs(intro_dir, exist_ok=True)
    dst = os.path.join(intro_dir, f.filename)
    f.save(dst)
    # Update config
    cfg = load_config()
    cfg['intro_path'] = dst
    cfg['use_intro'] = True
    save_config(cfg)
    return jsonify({'ok': True, 'path': dst})

# Ã¢â€â‚¬Ã¢â€â‚¬ Fonts Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
@app.route('/api/fonts')
def list_fonts():
    fonts = []
    if FONTS_DIR.exists():
        for f in FONTS_DIR.iterdir():
            if f.suffix.lower() in ('.ttf', '.otf'):
                fonts.append({'name': f.name, 'path': str(f)})
    return jsonify({'fonts': fonts})

@app.route('/api/fonts/upload', methods=['POST'])
def upload_font():
    if 'file' not in request.files:
        return jsonify({'error': 'No file'}), 400
    f = request.files['file']
    dst = str(FONTS_DIR / f.filename)
    f.save(dst)
    return jsonify({'ok': True, 'name': f.filename})


# Ã¢â€â‚¬Ã¢â€â‚¬ WARP Proxy Test Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
@app.route('/api/warp/test', methods=['POST'])
def test_warp_proxy():
    """
    Test WARP SOCKS5 proxy connectivity.
    Connects via proxy to httpbin.org/ip and returns the external IP seen.
    Requires: pip install requests[socks]  (installs PySocks automatically)
    """
    data = request.json or {}
    proxy_url = data.get('proxy', 'socks5://127.0.0.1:40000').strip()
    if not proxy_url:
        proxy_url = 'socks5://127.0.0.1:40000'

    try:
        import requests as _req
        proxies = {'http': proxy_url, 'https': proxy_url}
        t0 = time.time()
        resp = _req.get(
            'https://api.ipify.org?format=json',
            proxies=proxies,
            timeout=10,
            headers={'User-Agent': 'curl/7.88.1'}
        )
        latency_ms = int((time.time() - t0) * 1000)
        if resp.status_code == 200:
            ip = resp.json().get('ip', '?')
            return jsonify({'ok': True, 'ip': ip, 'latency_ms': latency_ms, 'proxy': proxy_url})
        else:
            return jsonify({'ok': False, 'error': f'HTTP {resp.status_code} from api.ipify.org'})
    except Exception as e:
        err = str(e)
        err_lower = err.lower()
        if isinstance(e, (ImportError, ModuleNotFoundError)) or 'no module named' in err_lower:
            hint = 'Chua cai PySocks: chay pip install requests[socks]'
        elif 'connection refused' in err_lower or '10061' in err:
            hint = 'WARP proxy bi tu choi ket noi Ã¢â€ â€™ WARP app Ã¢â€ â€™ Settings Ã¢â€ â€™ Advanced Ã¢â€ â€™ bat "WARP as local proxy"'
        elif 'timed out' in err_lower or 'timeout' in err_lower:
            hint = 'Timeout Ã¢â‚¬â€ kiem tra WARP dang chay va proxy mode da bat'
        elif 'general socks server failure' in err_lower:
            hint = 'WARP proxy loi SOCKS Ã¢â‚¬â€ tat/bat lai WARP app'
        else:
            hint = err[:300]
        return jsonify({'ok': False, 'error': hint, 'raw': err[:200]})



# Google Drive API
_GDRIVE_JOBS = {}
_GDRIVE_JOBS_LOCK = threading.Lock()
_GDRIVE_RUN_LOCK = threading.Lock()


_GDRIVE_OAUTH_LOCK = threading.Lock()
_GDRIVE_OAUTH_SERVER = None


def _gdrive_redirect_uri():
    # Fallback route for direct local callback. Do not use this for browser login on port 2209.
    port = int(os.environ.get('MIUBON_PORT', 2209))
    return f'http://localhost:{port}/api/gdrive/callback'


def _start_gdrive_loopback_callback():
    """Start a short-lived OAuth callback server on a browser-safe localhost port."""
    global _GDRIVE_OAUTH_SERVER
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from urllib.parse import urlsplit, parse_qs

    class _Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            return

        def do_GET(self):
            parsed = urlsplit(self.path)
            if parsed.path not in ('', '/'):
                self.send_response(404)
                self.end_headers()
                return
            redirect_uri = f'http://localhost:{self.server.server_port}/'
            full_url = redirect_uri.rstrip('/') + self.path
            state = parse_qs(parsed.query).get('state', [None])[0]
            try:
                os.environ['OAUTHLIB_INSECURE_TRANSPORT'] = '1'
                handle_callback(state, full_url, redirect_uri)
                body = b'Dang nhap Google Drive thanh cong. Ban co the dong tab nay va quay lai tool.'
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain; charset=utf-8')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except Exception as ex:
                msg = ('Loi dang nhap Google Drive: ' + str(ex)).encode('utf-8', 'replace')
                self.send_response(500)
                self.send_header('Content-Type', 'text/plain; charset=utf-8')
                self.send_header('Content-Length', str(len(msg)))
                self.end_headers()
                self.wfile.write(msg)
            finally:
                threading.Thread(target=self.server.shutdown, daemon=True).start()

    with _GDRIVE_OAUTH_LOCK:
        if _GDRIVE_OAUTH_SERVER:
            try:
                _GDRIVE_OAUTH_SERVER.shutdown()
                _GDRIVE_OAUTH_SERVER.server_close()
            except Exception:
                pass
            _GDRIVE_OAUTH_SERVER = None

        preferred = [8765, 8766, 8767, 8768, 8769, 8770]
        last_error = None
        for port in preferred:
            try:
                server = ThreadingHTTPServer(('127.0.0.1', port), _Handler)
                _GDRIVE_OAUTH_SERVER = server
                threading.Thread(target=server.serve_forever, daemon=True).start()
                return f'http://localhost:{port}/'
            except OSError as ex:
                last_error = ex
        raise Exception(f'Cannot start Google Drive OAuth loopback server: {last_error}')


def _gdrive_job_snapshot(job_id):
    with _GDRIVE_JOBS_LOCK:
        job = _GDRIVE_JOBS.get(job_id)
        return dict(job) if job else None


def _gdrive_set_job(job_id, **updates):
    with _GDRIVE_JOBS_LOCK:
        job = _GDRIVE_JOBS.get(job_id)
        if not job:
            return
        job.update(updates)
        job['updated_at'] = time.time()


def _gdrive_start_job(kind, label, fn):
    if not _GDRIVE_RUN_LOCK.acquire(blocking=False):
        return None, {'ok': False, 'error': 'Google Drive job is already running'}
    job_id = uuid.uuid4().hex[:8]
    with _GDRIVE_JOBS_LOCK:
        if len(_GDRIVE_JOBS) > 100:
            old_ids = sorted(_GDRIVE_JOBS, key=lambda k: _GDRIVE_JOBS[k].get('created_at', 0))
            for old_id in old_ids[:50]:
                if _GDRIVE_JOBS.get(old_id, {}).get('status') not in ('queued', 'running'):
                    _GDRIVE_JOBS.pop(old_id, None)
        _GDRIVE_JOBS[job_id] = {
            'ok': True,
            'id': job_id,
            'kind': kind,
            'label': label,
            'status': 'queued',
            'message': 'Queued',
            'created_at': time.time(),
            'updated_at': time.time(),
            'result': None,
            'error': None,
        }

    def _worker():
        try:
            _gdrive_set_job(job_id, status='running', message='Running')
            result = fn()
            _gdrive_set_job(job_id, status='done', message='Done', result=result)
        except Exception as ex:
            _gdrive_set_job(job_id, status='error', message='Error', error=str(ex))
        finally:
            try:
                _GDRIVE_RUN_LOCK.release()
            except RuntimeError:
                pass

    threading.Thread(target=_worker, daemon=True).start()
    return job_id, None


@app.route('/api/gdrive/job/<job_id>')
def gdrive_job_status(job_id):
    job = _gdrive_job_snapshot(job_id)
    if not job:
        return jsonify({'ok': False, 'error': 'job not found'}), 404
    return jsonify(job)




@app.route('/api/gdrive/import-secrets', methods=['POST'])
def gdrive_import_secrets():
    data = request.json or {}
    content = (data.get('json') or '').strip()
    reset_token = bool(data.get('reset_token', True))
    if not content:
        return jsonify({'ok': False, 'error': 'Google Drive OAuth JSON is required'}), 400
    try:
        parsed = json.loads(content)
        if not isinstance(parsed, dict) or not (parsed.get('installed') or parsed.get('web')):
            return jsonify({'ok': False, 'error': 'Invalid OAuth client JSON: missing installed/web block'}), 400
        target = BASE_DIR / 'gdrive_client_secrets.json'
        target.write_text(json.dumps(parsed, ensure_ascii=False, indent=2), encoding='utf-8')
        token_path = BASE_DIR / 'gdrive_token.pkl'
        token_reset = False
        if reset_token and token_path.exists():
            token_path.unlink()
            token_reset = True
        return jsonify({
            'ok': True,
            'message': 'Google Drive OAuth JSON imported',
            'path': str(target),
            'token_reset': token_reset,
        })
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 400


@app.route('/api/gdrive/status')
def gdrive_status():
    status = gdrive_check_auth()
    with _GDRIVE_JOBS_LOCK:
        active = [j for j in _GDRIVE_JOBS.values() if j.get('status') in ('queued', 'running')]
    status['active_job'] = active[-1] if active else None
    return jsonify(status)


@app.route('/api/gdrive/login')
def gdrive_login():
    try:
        redirect_uri = _start_gdrive_loopback_callback()
        url, state = get_auth_url(redirect_uri)
        return redirect(url)
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)})


@app.route('/api/gdrive/callback')
def gdrive_callback():
    state = request.args.get('state')
    try:
        os.environ['OAUTHLIB_INSECURE_TRANSPORT'] = '1'
        handle_callback(state, request.url, _gdrive_redirect_uri())
        return 'Dang nhap Google Drive thanh cong. Ban co the dong tab nay va quay lai tool.'
    except Exception as e:
        return f'Loi dang nhap Google Drive: {e}'


@app.route('/api/gdrive/projects')
def gdrive_projects():
    try:
        limit = request.args.get('limit', type=int)
        return jsonify({'ok': True, 'projects': list_drive_projects(limit=limit)})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)})


def _gdrive_sync_payload(data):
    cfg = load_config()
    projects_dir = data.get('projects_dir') or cfg.get('projects_dir') or str(BASE_DIR / 'projects')
    overwrite = bool(data.get('overwrite', False))
    limit = data.get('limit')
    if limit is not None:
        limit = int(limit)
    result = sync_projects_from_drive(projects_dir, overwrite=overwrite, limit=limit)
    return {'projects_dir': projects_dir, 'result': result}


@app.route('/api/gdrive/sync_projects', methods=['POST'])
def gdrive_sync_projects():
    data = request.json or {}
    job_id, err = _gdrive_start_job(
        'sync_projects',
        'Sync projects from Google Drive',
        lambda: _gdrive_sync_payload(data),
    )
    if err:
        return jsonify(err), 409
    return jsonify({'ok': True, 'job_id': job_id, 'status_url': f'/api/gdrive/job/{job_id}'})


@app.route('/api/gdrive/sync_projects_async', methods=['POST'])
def gdrive_sync_projects_async():
    return gdrive_sync_projects()


def _gdrive_upload_payload(project_name):
    project_path, info = _load_project_info_by_name(project_name)
    if not project_path:
        raise Exception('Project not found')
    result = upload_folder_to_drive(project_path)
    return {'project': project_name, 'result': result}


@app.route('/api/project/<project_name>/upload_gdrive', methods=['POST'])
def project_upload_gdrive(project_name):
    job_id, err = _gdrive_start_job(
        'upload_project',
        f'Upload {project_name} to Google Drive',
        lambda: _gdrive_upload_payload(project_name),
    )
    if err:
        return jsonify(err), 409
    return jsonify({'ok': True, 'job_id': job_id, 'status_url': f'/api/gdrive/job/{job_id}'})


@app.route('/api/project/<project_name>/upload_gdrive_async', methods=['POST'])
def project_upload_gdrive_async(project_name):
    return project_upload_gdrive(project_name)

# Background watchdog for YouTube stuck processing / failed uploads.
_YT_WATCHDOG_THREAD = threading.Thread(target=_youtube_watchdog_loop, daemon=True)
_YT_WATCHDOG_THREAD.start()

# Background watchdog for Douyin user new-video auto queue.
_DY_WATCHDOG_THREAD = threading.Thread(target=_douyin_watchdog_loop, daemon=True)
_DY_WATCHDOG_THREAD.start()


if __name__ == '__main__':
    print('Ã°Å¸Å½Â¬ MiuBon Vietsub Pipeline Server starting...')
    print(f'Ã°Å¸â€œ  Base: {BASE_DIR}')
    port = int(os.environ.get('MIUBON_PORT', 2209))
    print(f'ðŸŒ http://localhost:{port}')
    app.run(host='0.0.0.0', port=port, debug=False, threaded=True)


