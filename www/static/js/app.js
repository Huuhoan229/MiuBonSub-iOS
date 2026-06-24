// --- AUTO INJECTED API ROUTING FOR STATIC HOSTING ---
(function() {
    const host = window.location.hostname;
    const isLocal = host === 'localhost' || host === '127.0.0.1' || host === '';
    const isVercel = host.includes('vercel.app');
    
    // Nếu chạy trên localhost hoặc Vercel, dùng đường dẫn tương đối (để Vercel tự proxy)
    // Nếu chạy trên host khác (miubon.xyz), trỏ thẳng về Backend nhà
    const apiBase = (isLocal || isVercel) ? '' : 'https://api-mbvietsub.miubon.xyz';
    
    if (apiBase !== '') {
        const originalFetch = window.fetch;
        window.fetch = function(input, init) {
            if (typeof input === 'string' && input.startsWith('/api/')) {
                input = apiBase + input;
            } else if (input instanceof URL && input.pathname.startsWith('/api/')) {
                input = new URL(apiBase + input.pathname + input.search, window.location.origin);
            }
            return originalFetch.call(this, input, init);
        };
    }
})();
// ----------------------------------------------------

const IS_CAPACITOR_APP = window.location.protocol === 'capacitor:' || window.location.protocol === 'ionic:' || window.location.protocol === 'file:' || !!window.Capacitor;
const IS_IOS_REMOTE_MODE = IS_CAPACITOR_APP || window.location.pathname.startsWith('/ios') || window.location.search.includes('ios=1');
let API = IS_IOS_REMOTE_MODE ? (localStorage.getItem('MIUBON_API_BASE') || '') : '';
if (IS_IOS_REMOTE_MODE && !API) {
    setTimeout(() => {
        let input = prompt("Welcome to MiuBon Vietsub iOS App!\n\nPlease enter your Backend PC IP Address and Port (e.g. http://192.168.1.10:2209):", "http://");
        if (input) {
            API = input.replace(/\/+$/, '');
            localStorage.setItem('MIUBON_API_BASE', API);
            window.location.reload();
        }
    }, 500);
}

window.changeBackendUrl = function() {
    let current = localStorage.getItem('MIUBON_API_BASE') || 'http://';
    let input = prompt("Nhập Backend PC IP/Port (ví dụ http://192.168.1.10:5060):", current);
    if (input !== null) {
        localStorage.setItem('MIUBON_API_BASE', input.replace(/\/+$/, ''));
        window.location.reload();
    }
};

const safeStr = (s) => String(s || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');

let currentTab = 'pipeline';
let pollTimer = null;
let logOffset = 0;
let currentJobId = null;
let workerPollTimer = null;

function safeHtml(str) {
  if (str === null || str === undefined) return '';
  return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

// ═══ DEMO & SANDBOX STATE MANAGEMENT ═══
let isDemoMode = (window.location.hostname === 'huuhoan229.github.io' || 
                  window.location.hostname.includes('github.io') ||
                  new URLSearchParams(window.location.search).get('demo') === 'true');

const MOCK_STATE_KEY = 'miubon_demo_state_v1';

function getMockState() {
  let state = localStorage.getItem(MOCK_STATE_KEY);
  if (state) {
    try { return JSON.parse(state); } catch (e) {}
  }
  
  // Default sandbox state
  const defaultState = {
    config: {
      demucs_model: "htdemucs",
      tiktok_headless: false,
      tiktok_auto_split: true,
      tiktok_max_minutes: 10,
      tiktok_caption_max_chars: 255,
      tiktok_upload_timeout_sec: 240,
      tiktok_api_client_key: "mock_client_key_123",
      tiktok_api_client_secret: "mock_client_secret_xyz",
      tiktok_api_redirect_uri: "https://huuhoan229.github.io/anti-sub/",
      tiktok_api_scopes: "user.info.basic,video.upload,video.publish",
      tiktok_api_pkce_challenge_format: "hex",
      tiktok_api_privacy_level: "SELF_ONLY",
      tiktok_api_poll_timeout_sec: 900,
      tiktok_api_poll_interval_sec: 5,
      facebook_page_access_token: "mock_fb_access_token_abc123xyz",
      facebook_app_id: "mock_app_id_987",
      facebook_app_secret: "mock_app_secret_654",
      facebook_reels_actor_id: "me",
      facebook_graph_version: "v22.0",
      facebook_upload_mode: "auto",
      facebook_reels_short_threshold_sec: 90,
      facebook_reels_video_state: "PUBLISHED",
      facebook_reels_poll_timeout_sec: 600,
      facebook_reels_poll_interval_sec: 5,
      facebook_reels_request_timeout_sec: 60,
      facebook_api_proxy: "",
      facebook_reels_max_minutes: 10,
      facebook_reels_auto_split: "true",
      tts_engine: "gemini",
      tts_voice: "Zephyr",
      tts_speed: 1.0,
      tts_pitch: 1.0,
      tts_volume: 1.0,
      auto_adjust_tts_speed: false,
      api_keys: "AIzaSyDemoKey1\nAIzaSyDemoKey2",
      blur_sigma: 20,
      mask_h: 100,
      mask_y_pct: 83.5,
      font_name: "UTM_Bebas.ttf",
      font_size: 28,
      margin_v: 16,
      rotate_deg: 0.5,
      privacy: "public",
      projects_dir: "D:/anti-sub-projects",
      mirror: true,
      use_intro: true,
      auto_upload: true,
      auto_upload_tiktok: true,
      auto_upload_facebook_reels: true,
      douyin_warp_enabled: false,
      douyin_warp_proxy: "socks5://127.0.0.1:40000"
    },
    tiktok: {
      connected: false,
      account_name: "",
      avatar_url: ""
    },
    facebook: {
      connected: false,
      pages: []
    },
    projects: [
      { project_name: "Demo_Project_01", created_at: "2026-05-28", steps_completed: ["download", "separate", "stt", "translate", "tts", "render"] },
      { project_name: "Demo_Project_02", created_at: "2026-05-28", steps_completed: ["download", "separate", "stt"] }
    ],
    jobs: {}
  };
  
  localStorage.setItem(MOCK_STATE_KEY, JSON.stringify(defaultState));
  return defaultState;
}

function saveMockState(state) {
  localStorage.setItem(MOCK_STATE_KEY, JSON.stringify(state));
}

function resetDemoModeData() {
  localStorage.removeItem(MOCK_STATE_KEY);
  toast("Sandbox state reset successfully. Reloading...", "success");
  setTimeout(() => window.location.reload(), 1000);
}

function updateDemoBanner() {
  const banner = document.getElementById('demo-banner');
  if (banner) {
    if (isDemoMode) banner.classList.remove('hidden');
    else banner.classList.add('hidden');
  }
}

// Global hook functions for the HTML buttons
window.closeDemoOAuthModal = function() {
  const modal = document.getElementById('demo-oauth-modal');
  if (modal) modal.classList.add('hidden');
};

window.confirmDemoOAuth = function(platform) {
  const state = getMockState();
  if (platform === 'tiktok') {
    state.tiktok.connected = true;
    state.tiktok.account_name = "MiuBon Creator Simulator";
    state.tiktok.avatar_url = "https://www.tiktok.com/favicon.ico";
    saveMockState(state);
    window.closeDemoOAuthModal();
    toast("Simulated TikTok OAuth successful!", "success");
    checkTikTokApiStatus();
    loadTikTokStatus();
  }
};

window.resetDemoModeData = resetDemoModeData;

// Simulated API routing logic
function mockApi(path, opts = {}) {
  const state = getMockState();
  
  if (path === '/api/health') {
    return Promise.resolve({
      has_api_key: true,
      douyin: { playwright_ok: true, cookies_valid: true },
      youtube: { ok: true, enabled_count: 1, accounts: [{ key: 'mbv', channel: 'MiuBon Vietsub', ok: true, enabled: true }] },
      tiktok: { ok: state.tiktok.connected },
      facebook: { configured: state.config.facebook_page_access_token ? true : false, ok: state.config.facebook_page_access_token ? true : false }
    });
  }
  
  if (path === '/api/config') {
    if (opts.method === 'POST') {
      const payload = typeof opts.body === 'string' ? JSON.parse(opts.body) : (opts.body || {});
      Object.assign(state.config, payload);
      saveMockState(state);
      return Promise.resolve({ ok: true });
    }
    return Promise.resolve(state.config);
  }
  
  if (path === '/api/projects') {
    return Promise.resolve({ projects: state.projects });
  }
  
  if (path === '/api/tiktok/auth') {
    return Promise.resolve({
      playwright_ok: true,
      ok: state.tiktok.connected,
      has_storage: state.tiktok.connected,
      storage_age_min: 5
    });
  }
  
  if (path === '/api/tiktok/api/status') {
    return Promise.resolve({
      ok: state.tiktok.connected,
      configured: true,
      has_token: state.tiktok.connected,
      access_expires_in_sec: 86400,
      creator: {
        nickname: "MiuBon Creator Simulator",
        username: "miubon_simulator",
        privacy_level_options: ["PUBLIC_TO_EVERYONE", "MUTUAL_FOLLOW_FRIENDS", "FOLLOWER_OF_CREATOR", "SELF_ONLY"]
      },
      open_id: "mock_open_id_666"
    });
  }
  
  if (path === '/api/tiktok/api/disconnect') {
    state.tiktok.connected = false;
    saveMockState(state);
    return Promise.resolve({ ok: true });
  }
  
  if (path === '/api/tiktok/oauth/start') {
    setTimeout(() => {
      const modal = document.getElementById('demo-oauth-modal');
      if (modal) modal.classList.remove('hidden');
    }, 100);
    return Promise.resolve({ ok: true, auth_url: '#' });
  }
  
  if (path === '/api/tiktok/upload/start') {
    const jobId = 'tk_upload_sim_' + Date.now();
    state.jobs[jobId] = {
      pct: 0,
      status: 'running',
      logs: ['[00:00:01] Starting TikTok Content Posting API publish flow...'],
      created: Date.now()
    };
    saveMockState(state);
    return Promise.resolve({ ok: true, job_id: jobId });
  }
  
  if (path.startsWith('/api/tiktok/upload/')) {
    const jobId = path.split('/').pop();
    const job = state.jobs[jobId];
    if (!job) {
      return Promise.resolve({ status: 'error', error: 'Job not found' });
    }
    
    if (job.status === 'running') {
      job.pct += 25;
      if (job.pct === 25) {
        job.logs.push('[00:00:04] Project video file verified: final_video.mp4');
        job.logs.push('[00:00:06] Initializing video upload session with TikTok Creator API...');
      } else if (job.pct === 50) {
        job.logs.push('[00:00:08] Uploading video payload chunk 1/1 (100% completed)...');
      } else if (job.pct === 75) {
        job.logs.push('[00:00:12] TikTok returned upload code 200 (Success).');
        job.logs.push('[00:00:15] Creating publish request with caption, privacy: SELF_ONLY...');
      } else if (job.pct >= 100) {
        job.pct = 100;
        job.status = 'done';
        job.logs.push('[00:00:18] TikTok publish request succeeded. Share ID: share_tiktok_sim_9876');
        job.logs.push('[00:00:20] Upload process completed successfully.');
      }
      state.jobs[jobId] = job;
      saveMockState(state);
    }
    
    return Promise.resolve({
      status: job.status,
      progress: { pct: job.pct, message: job.pct === 100 ? 'Done' : 'Uploading...' },
      logs: job.logs,
      result: job.status === 'done' ? {
        ok_count: 1,
        part_count: 1,
        parts: [{ part_index: 1, total_parts: 1, duration_sec: 120, path: 'final_video.mp4', caption_preview: 'Vietsub Video #fyp' }],
        results: [{ part: 1, ok: true, status: 'PUBLISHED', publish_id: 'share_tiktok_sim_9876' }]
      } : null
    });
  }

  if (path === '/api/tiktok/upload') {
    return Promise.resolve({
      ok: true,
      part_count: 1,
      parts: [{ part_index: 1, total_parts: 1, duration_sec: 120, path: 'final_video.mp4', caption_preview: 'Vietsub Video #fyp' }],
      results: [{ part: 1, ok: true, status: 'dry_run_success' }]
    });
  }
  
  if (path.startsWith('/api/facebook/reels/status')) {
    return Promise.resolve({
      ok: true,
      configured: state.config.facebook_page_access_token ? true : false,
      actor_id: state.config.facebook_reels_actor_id || "1000987654321",
      graph_version: state.config.facebook_graph_version || "v22.0",
      check: state.config.facebook_page_access_token ? {
        ok: true,
        name: "MiuBon Entertainment (Demo)",
        id: "1000987654321"
      } : null
    });
  }
  
  if (path === '/api/facebook/reels/fetch-pages-with-token') {
    return Promise.resolve({
      ok: true,
      pages: [
        {
          name: "MiuBon Entertainment (Demo)",
          id: "1000987654321",
          access_token: "mock_page_token_miubon_ent"
        },
        {
          name: "Vietsub Reels Sandbox (Demo)",
          id: "1000123456789",
          access_token: "mock_page_token_reels_sb"
        }
      ],
      graph_version: "v22.0",
      long_lived_token: "mock_long_lived_user_token_abc"
    });
  }
  
  if (path === '/api/facebook/reels/upload/start') {
    const jobId = 'fb_upload_sim_' + Date.now();
    state.jobs[jobId] = {
      pct: 0,
      status: 'running',
      logs: ['[00:00:01] Fetching Facebook Graph API credentials...'],
      created: Date.now()
    };
    saveMockState(state);
    return Promise.resolve({ ok: true, job_id: jobId });
  }
  
  if (path.startsWith('/api/facebook/reels/upload/')) {
    const jobId = path.split('/').pop();
    const job = state.jobs[jobId];
    if (!job) {
      return Promise.resolve({ status: 'error', error: 'Job not found' });
    }
    
    if (job.status === 'running') {
      job.pct += 25;
      if (job.pct === 25) {
        job.logs.push('[00:00:04] Uploading video to Facebook Graph API: /v22.0/me/reels_videos');
        job.logs.push('[00:00:06] Video upload session established. Session ID: upload_fb_sim_123');
      } else if (job.pct === 50) {
        job.logs.push('[00:00:09] Streaming video payload... (100% complete)');
      } else if (job.pct === 75) {
        job.logs.push('[00:00:13] Video upload verified. Processing video thumbnail...');
        job.logs.push('[00:00:16] Publishing Reel to Page ID: ' + (state.config.facebook_reels_actor_id || '1000987654321') + ' with state: PUBLISHED');
      } else if (job.pct >= 100) {
        job.pct = 100;
        job.status = 'done';
        job.logs.push('[00:00:18] Facebook Reel published successfully. Reel ID: fb_reel_sim_4567');
        job.logs.push('[00:00:20] Reel upload process completed.');
      }
      state.jobs[jobId] = job;
      saveMockState(state);
    }
    
    return Promise.resolve({
      status: job.status,
      progress: { pct: job.pct, message: job.pct === 100 ? 'Done' : 'Uploading...' },
      logs: job.logs,
      result: job.status === 'done' ? {
        ok_count: 1,
        part_count: 1,
        parts: [{ part_index: 1, total_parts: 1, duration_sec: 120, path: 'final_video.mp4', caption_preview: 'Vietsub Reels #fyp' }],
        results: [{ part: 1, ok: true, video_id: 'fb_reel_sim_4567', status: 'PUBLISHED' }]
      } : null
    });
  }

  if (path === '/api/facebook/reels/upload') {
    return Promise.resolve({
      ok: true,
      part_count: 1,
      parts: [{ part_index: 1, total_parts: 1, duration_sec: 120, path: 'final_video.mp4', caption_preview: 'Vietsub Reels #fyp' }],
      results: [{ part: 1, ok: true, video_id: 'fb_reel_sim_4567', status: 'dry_run_success' }]
    });
  }
  
  return Promise.resolve({ ok: true, message: 'Simulated response' });
}

// ── API Helpers ──

let ytAccountsCache = [];

function syncYtManagerKeyFromAccounts(accounts) {
  const ytmgrKey = document.getElementById('ytmgr-key');
  if (!ytmgrKey || !accounts?.length) return;
  const current = (ytmgrKey.value || '').trim();
  const currentAcc = accounts.find(acc => acc.key === current);
  const currentUsable = currentAcc && currentAcc.ok && currentAcc.enabled !== false;
  const firstUsable = accounts.find(acc => acc.ok && acc.enabled !== false) || accounts.find(acc => acc.ok) || accounts[0];
  if ((!current || current === 'main' || !currentUsable) && firstUsable?.key) {
    ytmgrKey.value = firstUsable.key;
  }
}

async function ensureYtManagerKey() {
  const el = document.getElementById('ytmgr-key');
  if (!el) return 'main';
  syncYtManagerKeyFromAccounts(ytAccountsCache);
  let key = (el.value || '').trim();
  const known = ytAccountsCache.some(acc => acc.key === key && acc.ok && acc.enabled !== false);
  if (key && key !== 'main' && known) return key;
  try {
    const d = await api('/api/youtube/auth', { timeoutMs: 30000 });
    ytAccountsCache = d.accounts || [];
    syncYtManagerKeyFromAccounts(ytAccountsCache);
  } catch (e) {
    console.warn('Cannot refresh YouTube accounts:', e);
  }
  return (el.value || 'main').trim() || 'main';
}

async function api(path, opts = {}) {
  if (isDemoMode) {
    return mockApi(path, opts);
  }
  
  const { timeoutMs = 45000, ...fetchOpts } = opts;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const headers = { 'Content-Type': 'application/json' };
    const token = localStorage.getItem('miubon_token');
    if (token) headers['Authorization'] = 'Bearer ' + token;
    
    const r = await fetch(API + path, {
      headers,
      signal: controller.signal,
      ...fetchOpts,
      body: fetchOpts.body ? JSON.stringify(fetchOpts.body) : undefined
    });
    clearTimeout(timeout);
    const text = await r.text();
    let data = {};
    if (text) {
      try {
        data = JSON.parse(text);
      } catch (parseErr) {
        const preview = text.replace(/\s+/g, ' ').slice(0, 300);
        throw new Error(`HTTP ${r.status}: backend returned non-JSON: ${preview}`);
      }
    }
    if (!r.ok && !data.error) data.error = `HTTP ${r.status}`;
    return data;
  } catch (e) {
    clearTimeout(timeout);
    if (e.name === 'AbortError') {
      throw new Error(`Timeout - server khong phan hoi sau ${Math.round(timeoutMs / 1000)} giay`);
    }
    if (!isDemoMode && (e.name === 'TypeError' || e.message?.includes('fetch'))) {
      console.warn("API request failed. Staying in live mode instead of switching to Sandbox.", e);
      throw new Error('Khong ket noi duoc backend/tunnel. Thu reload sau vai giay, khong can Reset Sandbox.');
    }
    throw e;
  }
}

// ── Notification (Toast) ──
function toast(msg, type = 'success') {
  const el = document.createElement('div');
  el.className = `toast toast-${type}`;
  el.textContent = msg;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 4000);
}

// ── Tabs ──
function switchTab(tab) {
  currentTab = tab;
  document.querySelectorAll('.tab[data-tab]').forEach(t => t.classList.toggle('active', t.dataset.tab === tab));
  document.querySelectorAll('.tab-content').forEach(c => c.classList.toggle('hidden', c.id !== `tab-${tab}`));
  if (tab === 'projects') loadProjects();
    if (tab === 'series') loadSeriesLibrary();
    if (tab === 'home') loadScrapeHistory();
  if (tab === 'glossary') { loadGlossary(); }
  if (tab === 'auth') { checkHealth(); checkGDriveStatus(); }
  if (tab === 'ytmanager') { checkHealth(); loadYoutubeWatchdogState(); loadYoutubeVideos(); }
  if (tab === 'tiktok') { loadTikTokStatus(); loadTikTokProjects(); loadTikTokQuickConfig(); }
  if (tab === 'facebook') { loadFacebookReelsStatus(); loadFacebookReelsProjects(); loadFacebookQuickConfig(); }
  if (tab === 'vpn') { pollVpnStatus(); if (!vpnPollTimer) vpnPollTimer = setInterval(pollVpnStatus, 3000); }
  if (tab !== 'vpn' && vpnPollTimer) { clearInterval(vpnPollTimer); vpnPollTimer = null; }
  if (tab === 'settings') loadConfig();
  if (tab === 'running') {
    loadRunningTab();
    if (runningTabTimer) clearInterval(runningTabTimer);
    runningTabTimer = setInterval(loadRunningTab, 2000);
  } else {
    if (runningTabTimer) {
      clearInterval(runningTabTimer);
      runningTabTimer = null;
    }
    if (runningItemLogTimer) {
      clearInterval(runningItemLogTimer);
      runningItemLogTimer = null;
    }
  }
  
  if (tab === 'workers') {
    fetchWorkers();
    if (!workerPollTimer) workerPollTimer = setInterval(fetchWorkers, 3000);
  } else {
    if (workerPollTimer) {
      clearInterval(workerPollTimer);
      workerPollTimer = null;
    }
  }
  
  if (tab === 'ytqueue') {
    loadYTQueue();
    if (typeof ytQueuePollTimer !== 'undefined' && !ytQueuePollTimer) ytQueuePollTimer = setInterval(loadYTQueue, 5000);
  } else {
    if (typeof ytQueuePollTimer !== 'undefined' && ytQueuePollTimer) {
      clearInterval(ytQueuePollTimer);
      ytQueuePollTimer = null;
    }
  }
}
// ── Health Check ──
async function checkHealth() {
  try {
    const d = await api('/api/health', { timeoutMs: 45000 });
    const el = document.getElementById('health-status');
    el.innerHTML = `
      <div class="status-row"><span class="status-dot ${d.test_9router ? 'yellow' : 'red'}" id="status-9router-dot"></span>9Router API: <span id="status-9router-text">${d.test_9router ? 'Checking...' : 'Disabled'}</span></div>
      <div class="status-row"><span class="status-dot ${d.capcut_ok ? 'green' : 'red'}"></span>CapCut Server: ${d.capcut_ok ? 'Online' : 'Offline'}</div>
      <div class="status-row"><span class="status-dot green"></span>FFmpeg: ${d.ffmpeg_encoder}</div>
      <div class="status-row"><span class="status-dot ${d.douyin?.playwright_ok ? 'green' : 'red'}"></span>Playwright: ${d.douyin?.playwright_ok ? 'OK' : 'Not installed'}</div>
      <div class="status-row"><span class="status-dot ${d.douyin?.cookies_valid ? 'green' : 'yellow'}"></span>Douyin Cookies: ${d.douyin?.cookies_valid ? 'Valid' : 'Not set'}</div>
      <div class="status-row"><span class="status-dot ${d.youtube?.ok ? 'green' : 'yellow'}"></span>YouTube: ${d.youtube?.ok ? `${d.youtube.enabled_count} kênh bật` : 'Not connected'}</div>
      <div class="status-row"><span class="status-dot ${d.tiktok?.ok ? 'green' : 'yellow'}"></span>TikTok: ${d.tiktok?.ok ? 'Ready' : 'Not logged in'}</div>
      <div class="status-row"><span class="status-dot ${d.facebook?.ok ? 'green' : 'yellow'}"></span>Facebook Reels: ${d.facebook?.configured ? 'Configured' : 'Not configured'}</div>
      <div class="status-row"><span class="status-dot ${d.vpn?.enabled ? 'green' : 'yellow'}"></span>VPN Rotate: ${d.vpn?.enabled ? '🟢 ON — IP: ' + (d.vpn.current_ip || '...') + (d.vpn.current_server ? ' (' + d.vpn.current_server + ')' : '') : 'OFF'}</div>
    `;

    if (d.test_9router) {
      api('/api/translation/test', {
        method: 'POST',
        body: { translation_provider: '9router' }
      }).then(res => {
        const dot = document.getElementById('status-9router-dot');
        const txt = document.getElementById('status-9router-text');
        if (dot && txt) {
          if (res.ok) {
            dot.className = 'status-dot green';
            txt.innerText = 'OK (' + res.time_ms + 'ms)';
          } else {
            dot.className = 'status-dot red';
            txt.innerText = 'Error';
          }
        }
      }).catch(err => {
        const dot = document.getElementById('status-9router-dot');
        const txt = document.getElementById('status-9router-text');
        if (dot && txt) {
          dot.className = 'status-dot red';
          txt.innerText = 'Network Error';
        }
      });
    }
    // Update Auth tab accounts list
    const list = document.getElementById('yt-accounts-list');
    if (list && d.youtube?.accounts) {
      list.innerHTML = d.youtube.accounts.map(acc => {
        const isEnabled = acc.enabled !== false;
        return `
        <div class="status-row" style="font-size:0.82rem; padding:8px 12px; background:rgba(255,255,255,0.04); border-radius:6px; margin-bottom:6px; display:flex; align-items:center; gap:10px; border:1px solid ${isEnabled ? 'rgba(0,255,136,0.15)' : 'rgba(255,255,255,0.06)'}; opacity:${isEnabled ? '1' : '0.5'}">
          <span class="status-dot ${acc.ok ? (isEnabled ? 'green' : 'yellow') : 'red'}"></span>
          <strong style="min-width:60px">${acc.key}</strong>
          <span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${acc.channel || acc.error || '?'}</span>
          <label style="display:flex;align-items:center;gap:4px;cursor:pointer;font-size:.75rem;white-space:nowrap" title="${isEnabled ? 'Bật — video sẽ được up lên kênh này' : 'Tắt — bỏ qua kênh này'}">
            <input type="checkbox" ${isEnabled ? 'checked' : ''} onchange="toggleYtChannel('${acc.key}', this.checked)" />
            ${isEnabled ? '🟢 Bật' : '⚫ Tắt'}
          </label>
          <button class="btn btn-outline btn-sm" style="padding:2px 8px;font-size:.7rem;color:#f66" onclick="removeYtChannel('${acc.key}')" title="Xóa kênh này">🗑</button>
        </div>`;
      }).join('');
    } else if (list) {
      list.innerHTML = '<p style="color:var(--text-dim);font-size:.82rem">Chưa có kênh YouTube nào. Nhấn "Login Main Channel" để bắt đầu.</p>';
    }
    const badge = document.getElementById('yt-enabled-badge');
    if (badge && d.youtube) {
      badge.textContent = `${d.youtube.enabled_count || 0} kênh bật`;
    }

    // YT Manager should use an existing enabled channel key, not hardcoded `main`.
    if (d.youtube?.accounts?.length) {
      ytAccountsCache = d.youtube.accounts || [];
      syncYtManagerKeyFromAccounts(ytAccountsCache);
    }

    // Restore active jobs/queues if page reloaded
    if (d.active_jobs && Object.keys(d.active_jobs).length > 0) {
      const jobIds = Object.keys(d.active_jobs);
      const activeQueues = [];
      let activeQueueId = null;
      let activePipelineId = null;
      
      for (const jid of jobIds) {
        if (d.active_jobs[jid].queue) {
          const q = d.active_jobs[jid].queue || {};
          const count = Number(q.total || (q.urls || q.projects || []).length || 0);
          activeQueues.push({ id: jid, count, created: Number(d.active_jobs[jid]._created || 0) });
        } else {
          activePipelineId = jid;
        }
      }
      if (activeQueues.length) {
        activeQueues.sort((a, b) => (b.count - a.count) || (b.created - a.created));
        activeQueueId = activeQueues[0].id;
      }

      // Restore Queue
      if (activeQueueId && !queueTimer) {
        const q = d.active_jobs[activeQueueId].queue;
        const items = q.urls || q.projects || [];
        const msg = document.getElementById('queue-msg');
        if (msg && activeQueues.length > 1) {
          msg.textContent = `Multiple active queues: ${activeQueues.map(x => `${x.id}:${x.count}`).join(' | ')}. Showing ${activeQueueId}.`;
        }
        document.getElementById('queue-monitor').classList.remove('hidden');
        document.getElementById('queue-items').innerHTML = items.map((u, i) => `
          <div class="queue-item" id="qi-${i}">
            <span class="queue-idx">${i+1}</span>
            <span class="queue-url">${u.length > 50 ? u.substring(0,50)+'...' : u}</span>
            <span class="queue-item-status badge badge-default" id="qi-status-${i}">⏳ Waiting</span>
          </div>
        `).join('');
        queueTimer = setInterval(() => q.urls ? pollQueue(activeQueueId, items) : pollResumeQueue(activeQueueId, items), 3000);
        selectedQueueId = activeQueueId;
      }

      // Restore Single Pipeline (if no queue is handling it)
      if (activePipelineId && !pollTimer && !queueTimer) {
        currentJobId = activePipelineId;
        logOffset = 0;
        document.getElementById('pipeline-monitor').classList.remove('hidden');
        pollTimer = setInterval(() => pollJob(activePipelineId), 2000);
      }
    }
    refreshActiveQueues();
  } catch (e) {
    document.getElementById('health-status').innerHTML = `<div class="status-row"><span class="status-dot red"></span>Server offline</div>`;
  }
}

// ── Pipeline ──
async function startPipeline() {
  const url = document.getElementById('input-url').value.trim();
  if (!url) return toast('Please enter URL or text', 'error');
  const btn = document.getElementById('btn-start');
  btn.disabled = true;
  try {
    const d = await api('/api/pipeline/start', { method: 'POST', body: { url } });
    if (d.error) { toast(d.error, 'error'); btn.disabled = false; return; }
    currentJobId = d.job_id;
    logOffset = 0;
    document.getElementById('pipeline-monitor').classList.remove('hidden');
    document.getElementById('log-box').innerHTML = '';
    pollTimer = setInterval(() => pollJob(d.job_id), 2000);
    toast('Pipeline started!');
  } catch (e) { toast('Error: ' + e.message, 'error'); }
  btn.disabled = false;
}

function previewUrls() {
  const text = document.getElementById('input-url').value.trim();
  if (!text) return toast('Paste URLs first', 'error');
  const urlPattern = /https?:\/\/(?:(?:www\.)?douyin\.com\/video\/\d+|v\.douyin\.com\/[^\s\/]+\/?|(?:vm\.|vt\.)?tiktok\.com\/[^\s]+)/gi;
  const found = [...new Set(text.match(urlPattern) || [])];
  const el = document.getElementById('url-preview');
  if (!found.length) {
    el.innerHTML = '<div class="url-preview-empty">⚠️ No Douyin URLs detected</div>';
  } else {
    el.innerHTML = `<div class="url-preview-header">🔍 Found ${found.length} URL(s):</div>` +
      found.map((u, i) => `<div class="url-preview-item"><span class="url-num">${i+1}</span><span class="url-text">${u}</span></div>`).join('');
  }
  el.classList.remove('hidden');
}

function enqueueUrlsToPipelineInput(urls, sourceLabel = 'queue', contextByUrl = null) {
  const clean = [...new Set((urls || []).map(u => (u || '').trim()).filter(Boolean))];
  if (!clean.length) return 0;
  if (contextByUrl && typeof contextByUrl === 'object') {
    clean.forEach((u) => {
      const ctx = contextByUrl[u];
      if (ctx && typeof ctx === 'object') pipelineUrlContexts[u] = ctx;
    });
  }
  const input = document.getElementById('input-url');
  const existing = (input?.value || '')
    .split(/\r?\n/)
    .map(s => s.trim())
    .filter(Boolean);
  const merged = [...new Set([...existing, ...clean])];
  if (input) input.value = merged.join('\n');
  switchTab('pipeline');
  previewUrls();
  toast(`Added ${clean.length} URL(s) to Pipeline queue (${sourceLabel}). Press "Start Queue (Batch)" to run.`);
  return clean.length;
}

let queueTimer = null;
let activeQueuesTimer = null;
let selectedQueueId = null;
let lastQueueErrors = [];
let lastQueueUrls = [];
let pipelineUrlContexts = {};
let scrapeSeriesSelected = new Set();
let runningTabTimer = null;
let runningItemLogTimer = null;
let runningSelectedQueueId = null;
let runningSelectedItemIndex = null;
let runningLogOffset = 0;

function queueStatusBadgeClass(status) {
  if (status === 'done') return 'badge-success';
  if (status === 'error') return 'badge-error';
  if (status === 'paused') return 'badge-warning';
  return 'badge-info';
}

function renderActiveQueues(queues) {
  const card = document.getElementById('active-queues-card');
  const list = document.getElementById('active-queues-list');
  const count = document.getElementById('active-queues-count');
  if (!card || !list || !count) return;
  const rows = (queues || []).filter(q => ['running', 'queued', 'paused'].includes(q.status));
  count.textContent = rows.length;
  if (!rows.length) {
    card.classList.add('hidden');
    list.innerHTML = '';
    return;
  }
  card.classList.remove('hidden');
  list.innerHTML = rows.map((q) => {
    const series = q.series_counts && Object.keys(q.series_counts).length
      ? Object.entries(q.series_counts).slice(0, 4).map(([name, n]) => `${safeHtml(name)}:${n}`).join(' | ')
      : 'No series context';
    const skipAction = `<button class="btn btn-outline btn-sm" onclick="skipPipelineQueueItem('${q.id}')">Bỏ qua URL</button>`;
    const action = q.status === 'paused'
      ? `<button class="btn btn-primary btn-sm" onclick="resumePipelineQueue('${q.id}')">&#9654; Resume</button> ${skipAction} <button class=\"btn btn-error btn-sm\" onclick=\"cancelQueue('${q.id}')\">&#10006; H?y Queue</button>`
      : `<button class="btn btn-outline btn-sm" onclick="pauseQueue('${q.id}')">&#9208; Pause</button> ${skipAction} <button class=\"btn btn-error btn-sm\" onclick=\"cancelQueue('${q.id}')\">&#10006; H?y Queue</button>`;
    return `
      <div class="queue-item active-queue-row ${q.id === selectedQueueId ? 'active' : ''}">
        <span class="queue-idx">${safeHtml(q.id)}</span>
        <div class="active-queue-main">
          <div class="active-queue-title">
            <span class="badge ${queueStatusBadgeClass(q.status)}">${safeHtml(String(q.status || '').toUpperCase())}</span>
            <strong>${q.completed || 0}/${q.total || 0}</strong>
            <span>${safeHtml(q.type || 'urls')}</span>
            ${q.contexts_count ? `<span class="badge badge-default">ctx ${q.contexts_count}</span>` : ''}
          </div>
          <div class="active-queue-sub">${safeHtml(q.message || '')}</div>
          <div class="active-queue-sub">Series: ${series}</div>
        </div>
        <div class="active-queue-actions">
          <button class="btn btn-outline btn-sm" onclick="showQueueDetails('${q.id}')">Xem</button>
          ${action}
        </div>
      </div>`;
  }).join('');
}

async function refreshActiveQueues() {
  try {
    const d = await api('/api/pipeline/queues');
    renderActiveQueues(d.queues || []);
  } catch (e) {
    console.warn('refreshActiveQueues failed', e);
  }
}

// ── Worker Manager ──
async function fetchWorkers() {
  try {
    const d = await api('/api/workers');
    const list = document.getElementById('workers-list');
    if (!list) return;
    const workers = d.workers || [];
    if (workers.length === 0) {
      list.innerHTML = '<div style="padding:15px;text-align:center;color:var(--text-dim);background:rgba(255,255,255,0.02);border-radius:8px;">Không có Thợ nào đang chạy.</div>';
      return;
    }
    list.innerHTML = workers.map(w => `
      <div style="display:flex; justify-content:space-between; align-items:center; padding:12px 16px; background:rgba(255,255,255,0.04); border-radius:8px; border:1px solid var(--border);">
        <div style="display:flex; flex-direction:column; gap:4px;">
          <strong style="color:var(--text-light); font-size:1.05rem;">👷‍♂️ Thợ #${w.pid}</strong>
          <span style="font-size:0.85rem; color:var(--text-dim);">Uptime: ${w.uptime_seconds}s | Status: ${safeHtml(w.status)}</span>
        </div>
        <button class="btn btn-error btn-sm" onclick="killWorker(${w.pid})">🛑 Tắt (Kill)</button>
      </div>
    `).join('');
  } catch (e) {
    console.warn('fetchWorkers error', e);
  }
}

async function killWorker(pid) {
  if (!confirm(`Bạn có chắc muốn tắt Thợ #${pid} không?`)) return;
  try {
    const d = await api(`/api/workers/${pid}/kill`, { method: 'POST' });
    if (d.ok) {
      toast(`Đã tắt Thợ #${pid}`, 'success');
      fetchWorkers();
    } else {
      toast(d.message || 'Lỗi khi tắt Thợ', 'error');
    }
  } catch (e) {
    toast('Error: ' + e.message, 'error');
  }
}

async function cancelQueue(queueId) {
  if (!confirm('Are you sure you want to cancel this queue?')) return;
  try {
    const d = await api(`/api/pipeline/queue/${queueId}/cancel`, { method: 'POST' });
    if (d.error) return toast(d.error, 'error');
    toast(`Cancelled queue ${queueId}`);
    await refreshActiveQueues();
  } catch (e) { toast('Cancel failed: ' + e.message, 'error'); }
}

async function pauseQueue(queueId) {
  try {
    const d = await api(`/api/pipeline/queue/${queueId}/pause`, { method: 'POST' });
    if (d.error) return toast(d.error, 'error');
    toast(`Paused queue ${queueId}. Current URL will finish first.`);
    await refreshActiveQueues();
    if (selectedQueueId === queueId) await showQueueDetails(queueId, false);
  } catch (e) { toast('Pause failed: ' + e.message, 'error'); }
}

async function resumePipelineQueue(queueId) {
  try {
    const d = await api(`/api/pipeline/queue/${queueId}/resume`, { method: 'POST' });
    if (d.error) return toast(d.error, 'error');
    toast(`Resumed queue ${queueId}`);
    await refreshActiveQueues();
    if (selectedQueueId === queueId) await showQueueDetails(queueId, false);
  } catch (e) { toast('Resume failed: ' + e.message, 'error'); }
}

async function skipPipelineQueueItem(queueId) {
  if (!confirm('Bỏ qua item đang chờ/đang chờ upload tiếp theo trong queue này? Job đang render/dịch sẽ không bị cắt ngang.')) return;
  try {
    const d = await api(`/api/pipeline/queue/${queueId}/skip`, { method: 'POST' });
    if (d.error) return toast(d.error, 'error');
    toast(`Skipped URL #${Number(d.skipped_index || 0) + 1}`);
    await refreshActiveQueues();
    if (selectedQueueId === queueId) await showQueueDetails(queueId, false);
    if (typeof loadRunningTab === 'function') await loadRunningTab();
  } catch (e) { toast('Skip failed: ' + e.message, 'error'); }
}

async function showQueueDetails(queueId, switchToPipeline = true) {
  try {
    const d = await api(`/api/pipeline/queue/${queueId}`);
    if (d.error) return toast(d.error, 'error');
    const q = d.queue || {};
    const itemsArr = q.urls || q.projects || [];
    selectedQueueId = queueId;
    if (switchToPipeline) switchTab('pipeline');
    document.getElementById('queue-monitor').classList.remove('hidden');
    document.getElementById('queue-items').innerHTML = itemsArr.map((u, i) => `
      <div class="queue-item" id="qi-${i}">
        <span class="queue-idx">${i+1}</span>
        <span class="queue-url">${safeHtml(String(u).length > 70 ? String(u).substring(0,70)+'...' : u)}</span>
        <span class="queue-item-status badge badge-default" id="qi-status-${i}">Waiting</span>
      </div>
    `).join('');
    if (queueTimer) clearInterval(queueTimer);
    queueTimer = setInterval(() => q.urls ? pollQueue(queueId, itemsArr) : pollResumeQueue(queueId, itemsArr), 3000);
    if (q.urls) await pollQueue(queueId, itemsArr);
    else await pollResumeQueue(queueId, itemsArr);
    renderActiveQueues((await api('/api/pipeline/queues')).queues || []);
  } catch (e) {
    toast('Load queue failed: ' + e.message, 'error');
  }
}

async function startBatchPipeline() {
  const text = document.getElementById('input-url').value.trim();
  if (!text) return toast('Paste URLs first', 'error');
  const urls = text.split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  const contextByUrl = {};
  urls.forEach((u) => {
    if (pipelineUrlContexts[u]) contextByUrl[u] = pipelineUrlContexts[u];
  });
  await startQueueFromUrls(
    urls,
    'manual',
    document.getElementById('btn-batch'),
    contextByUrl
  );
}

async function startQueueFromUrls(urls, sourceLabel = 'queue', btnEl = null, contextByUrl = null) {
  const clean = [...new Set((urls || []).map(u => (u || '').trim()).filter(Boolean))];
  if (!clean.length) {
    toast('No URLs to queue', 'error');
    return null;
  }
  const mergedContexts = {};
  const sourceContexts = (contextByUrl && typeof contextByUrl === 'object') ? contextByUrl : {};
  clean.forEach((u) => {
    const ctx = sourceContexts[u] || pipelineUrlContexts[u];
    if (ctx && typeof ctx === 'object') mergedContexts[u] = ctx;
  });
  if (btnEl) btnEl.disabled = true;
  try {
    const body = { urls: clean.join('\n') };
    if (Object.keys(mergedContexts).length) body.contexts = mergedContexts;
    const d = await api('/api/pipeline/batch', { method: 'POST', body });
    if (d.error) {
      toast(d.error, 'error');
      return null;
    }
    toast(`Queue started from ${sourceLabel}: ${d.total} URLs`);
    selectedQueueId = d.queue_id;
    switchTab('pipeline');
    document.getElementById('queue-monitor').classList.remove('hidden');
    const items = document.getElementById('queue-items');
    items.innerHTML = d.urls.map((u, i) => `
      <div class="queue-item" id="qi-${i}">
        <span class="queue-idx">${i+1}</span>
        <span class="queue-url">${u.length > 50 ? u.substring(0,50)+'...' : u}</span>
        <span class="queue-item-status badge badge-default" id="qi-status-${i}">Waiting</span>
      </div>
    `).join('');
    if (queueTimer) clearInterval(queueTimer);
    queueTimer = setInterval(() => pollQueue(d.queue_id, d.urls), 3000);
    refreshActiveQueues();
    return d;
  } catch (e) {
    toast('Error: ' + e.message, 'error');
    return null;
  } finally {
    if (btnEl) btnEl.disabled = false;
  }
}

function _queueItemStatusView(item, queueStatus, fallbackCurrent = false) {
  const st = String((item || {}).status || '');
  if (st === 'running_pipeline') return { cls: 'badge-info', text: 'Processing...' };
  if (st === 'uploading') return { cls: 'badge-info', text: 'Uploading...' };
  if (st === 'ready_waiting_upload') return { cls: 'badge-warning', text: 'Pending upload' };
  if (st === 'done') return { cls: 'badge-success', text: 'Done' };
  if (st === 'failed_final' || st === 'upload_error' || st === 'error') return { cls: 'badge-error', text: 'Failed' };
  if (st === 'skipped') return { cls: 'badge-warning', text: 'Skipped' };
  if (fallbackCurrent && (queueStatus === 'running' || queueStatus === 'paused')) {
    if (queueStatus === 'paused') return { cls: 'badge-warning', text: 'Paused' };
    return { cls: 'badge-info', text: 'Processing...' };
  }
  return { cls: 'badge-default', text: 'Waiting' };
}

async function pollQueue(queueId, urls) {
  try {
    const d = await api(`/api/pipeline/queue/${queueId}`);
    const q = d.queue || {};
    const pct = d.progress || 0;
    document.getElementById('queue-progress-fill').style.width = pct + '%';
    document.getElementById('queue-pct').textContent = pct + '%';
    document.getElementById('queue-msg').textContent = `[${queueId}] ${d.message || ''}`;
    // Update status badge
    const badge = document.getElementById('queue-status');
    badge.className = 'badge ' + queueStatusBadgeClass(d.status);
    badge.textContent = d.status?.toUpperCase();
    // Update individual items
    const completed = q.completed || 0;
    const results = q.results || [];
    const errors = q.errors || [];
    const total = q.total || urls.length;
    const runtimeItems = Array.isArray(q.runtime_items) ? q.runtime_items : [];
    for (let i = 0; i < total; i++) {
      const st = document.getElementById(`qi-status-${i}`);
      if (!st) continue;
      const view = _queueItemStatusView(runtimeItems[i], d.status, i === completed);
      st.className = `badge ${view.cls}`;
      st.textContent = view.text;
    }

    // Show logs for one currently-running pipeline job.
    const runningItem = runtimeItems.find(it => String((it || {}).status || '') === 'running_pipeline' && (it || {}).job_id);
    const activeJobId = (runningItem && runningItem.job_id) || q.current_job || null;
    if (activeJobId && activeJobId !== currentJobId) {
      currentJobId = activeJobId;
      logOffset = 0;
      document.getElementById('pipeline-monitor').classList.remove('hidden');
      document.getElementById('log-box').innerHTML = '';
      if (pollTimer) clearInterval(pollTimer);
      pollTimer = setInterval(() => pollJob(activeJobId), 2000);
    }
    if (d.status === 'done' || d.status === 'error') {
      clearInterval(queueTimer);
      refreshActiveQueues();
      // Mark all items final status
      for (let i = 0; i < total; i++) {
        const st = document.getElementById(`qi-status-${i}`);
        if (!st) continue;
        const wasError = errors.find(e => e.url === urls[i]);
        if (wasError) {
          st.className = 'badge badge-error'; st.textContent = '❌ Failed';
        } else {
          st.className = 'badge badge-success'; st.textContent = '✅ Done';
        }
      }
      if (d.status === 'done') {
        toast(`Queue complete: ${results.length}/${total} success${errors.length ? `, ${errors.length} failed` : ''}`);
      }
      // Show failed section if there are errors
      if (errors.length > 0) {
        lastQueueErrors = errors;
        lastQueueUrls = urls;
        showFailedSection(errors);
      }
    }
  } catch (e) { console.error(e); }
}


function _isRunningTabItemVisible(item) {
  const st = String((item || {}).status || '');
  return st === 'running_pipeline' || st === 'uploading' || st === 'ready_waiting_upload';
}

function _runningTabBadge(item) {
  const st = String((item || {}).status || '');
  if (st === 'running_pipeline') return { cls: 'badge-info', text: 'running' };
  if (st === 'uploading') return { cls: 'badge-info', text: 'uploading' };
  if (st === 'ready_waiting_upload') return { cls: 'badge-warning', text: 'pending_upload' };
  return { cls: 'badge-default', text: st || 'unknown' };
}

async function loadRunningTab() {
  const listEl = document.getElementById('running-queues-list');
  if (!listEl) return;
  try {
    const d = await api('/api/pipeline/running');
    const queues = Array.isArray(d.queues) ? d.queues : [];
    const rows = [];
    let selectedStillVisible = false;

    queues.forEach((q) => {
      const qid = String(q.queue_id || '');
      const items = (Array.isArray(q.items) ? q.items : [])
        .filter(_isRunningTabItemVisible)
        .sort((a, b) => Number(a.index || 0) - Number(b.index || 0));
      items.forEach((item) => {
        const idx = Number(item.index || 0);
        const active = (runningSelectedQueueId === qid && runningSelectedItemIndex === idx);
        if (active) selectedStillVisible = true;
        const badge = _runningTabBadge(item);
        const statusText = safeHtml(String(item.status_text || item.status || ''));
        rows.push(`
          <div class="queue-item active-queue-row ${active ? 'active' : ''}" onclick="selectRunningItem('${qid}', ${idx})">
            <span class="queue-idx">${idx + 1}</span>
            <div class="active-queue-main">
              <div class="active-queue-title">
                <strong>#${idx + 1}</strong>
                <span>[${safeHtml(String(item.status || ''))}]</span>
              </div>
              <div class="active-queue-sub">${statusText}</div>
              <div class="active-queue-sub">${safeHtml(String(item.url || ''))}</div>
            </div>
            <div class="active-queue-actions">
              <span class="badge ${badge.cls}">${badge.text}</span>
            </div>
          </div>
        `);
      });
    });

    if (!rows.length) {
      listEl.innerHTML = '<div class="status-row" style="color:var(--text-dim)">No active running item.</div>';
      const metaEl = document.getElementById('running-item-meta');
      if (metaEl) metaEl.textContent = 'Chọn 1 item ở trên để xem chi tiết.';
      const logsEl = document.getElementById('running-item-logs');
      if (logsEl) logsEl.innerHTML = '';
      if (runningItemLogTimer) {
        clearInterval(runningItemLogTimer);
        runningItemLogTimer = null;
      }
      runningSelectedQueueId = null;
      runningSelectedItemIndex = null;
      runningLogOffset = 0;
      return;
    }

    listEl.innerHTML = rows.join('');

    if (runningSelectedQueueId && runningSelectedItemIndex != null && selectedStillVisible) {
      if (!runningItemLogTimer) {
        runningItemLogTimer = setInterval(_pollRunningItemLogs, 1000);
      }
      await _pollRunningItemLogs();
    }
  } catch (e) {
    listEl.innerHTML = `<div class="status-row" style="color:var(--error)">Running tab error: ${safeHtml(e.message || String(e))}</div>`;
  }
}

window.selectRunningItem = async function(queueId, itemIndex) {
  runningSelectedQueueId = String(queueId || '');
  runningSelectedItemIndex = Number(itemIndex || 0);
  runningLogOffset = 0;
  const logsEl = document.getElementById('running-item-logs');
  if (logsEl) logsEl.innerHTML = '';
  await _pollRunningItemLogs();
  if (runningItemLogTimer) clearInterval(runningItemLogTimer);
  runningItemLogTimer = setInterval(_pollRunningItemLogs, 1000);
  await loadRunningTab();
};

async function _pollRunningItemLogs() {
  if (!runningSelectedQueueId || runningSelectedItemIndex == null) return;
  try {
    const d = await api(`/api/pipeline/queue/${runningSelectedQueueId}/item/${runningSelectedItemIndex}/logs?offset=${runningLogOffset}`);
    const lines = Array.isArray(d.lines) ? d.lines : [];
    const metaEl = document.getElementById('running-item-meta');
    if (metaEl) {
      const st = String(d.status || '').trim();
      metaEl.textContent = `Queue ${runningSelectedQueueId} | URL #${runningSelectedItemIndex + 1}${st ? ' | ' + st : ''}`;
    }
    if (lines.length) {
      const box = document.getElementById('running-item-logs');
      if (box) {
        box.innerHTML += lines.map(x => safeHtml(String(x))).join('<br>') + '<br>';
        box.scrollTop = box.scrollHeight;
      }
    }
    runningLogOffset = Number(d.total || (runningLogOffset + lines.length));
  } catch (e) {
    const metaEl = document.getElementById('running-item-meta');
    if (metaEl) metaEl.textContent = `Log error: ${e.message || e}`;
  }
}

function showFailedSection(errors) {
  const section = document.getElementById('queue-failed-section');
  section.classList.remove('hidden');
  document.getElementById('queue-failed-count').textContent = errors.length;
  const list = document.getElementById('queue-failed-list');
  list.innerHTML = errors.map((e, i) => {
    const shortUrl = e.url?.length > 55 ? e.url.substring(0, 55) + '...' : (e.url || 'Unknown URL');
    const errorMsg = (e.error || 'Unknown error').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const hasJobId = !!e.job_id;
    return `
    <div class="queue-failed-item" id="qfi-${i}">
      <div class="queue-failed-header">
        <span style="color:var(--error);font-weight:700;font-size:.85rem">${i+1}</span>
        <span class="queue-failed-url" title="${e.url || ''}">${shortUrl}</span>
        <div class="queue-failed-actions">
          <button class="btn btn-outline btn-sm" onclick="toggleErrorDetail(${i})" title="Xem lý do lỗi">👁 Lý do</button>
          ${hasJobId ? `<button class="btn btn-outline btn-sm" onclick="viewFailedLogs('${e.job_id}')" title="Xem logs chi tiết">📋 Logs</button>` : ''}
        </div>
      </div>
      <div class="queue-failed-error" id="qfe-${i}">${errorMsg}</div>
    </div>`;
  }).join('');
}

function toggleErrorDetail(idx) {
  const el = document.getElementById(`qfe-${idx}`);
  if (el) el.classList.toggle('show');
}

async function viewFailedLogs(jobId) {
  // Show the pipeline monitor with logs from the failed job
  document.getElementById('pipeline-monitor').classList.remove('hidden');
  document.getElementById('log-box').innerHTML = '<div class="log-line log-info"><span class="log-dot"></span><span class="log-msg">Loading logs...</span></div>';
  document.getElementById('progress-msg').textContent = 'Viewing failed job logs';
  document.getElementById('progress-fill').style.width = '0%';
  document.getElementById('progress-pct').textContent = '';
  const badge = document.getElementById('job-status');
  badge.className = 'badge badge-error'; badge.textContent = 'FAILED';
  try {
    const logs = await api(`/api/pipeline/logs/${jobId}?offset=0`);
    const box = document.getElementById('log-box');
    box.innerHTML = '';
    if (logs.lines?.length) {
      logs.lines.forEach(l => {
        const el = formatLogLine(l);
        box.appendChild(el);
      });
      box.scrollTop = box.scrollHeight;
    } else {
      box.innerHTML = '<div class="log-line log-warning"><span class="log-dot"></span><span class="log-msg">No logs available for this job</span></div>';
    }
  } catch (e) {
    document.getElementById('log-box').innerHTML = `<div class="log-line log-error"><span class="log-dot"></span><span class="log-msg">Error loading logs: ${e.message}</span></div>`;
  }
}

async function retryFailedQueue() {
  if (!lastQueueErrors.length) return toast('No failed items to retry', 'error');
  const failedUrls = lastQueueErrors.map(e => e.url).filter(u => u);
  if (!failedUrls.length) return toast('No valid URLs to retry', 'error');
  if (!confirm(`Retry ${failedUrls.length} failed URL(s)?`)) return;

  // Hide the failed section
  document.getElementById('queue-failed-section').classList.add('hidden');
  lastQueueErrors = [];

  // Start a new batch with only the failed URLs
  const btn = document.getElementById('btn-retry-failed');
  btn.disabled = true;
  btn.textContent = '⏳ Starting...';
  try {
    const d = await api('/api/pipeline/batch', { method: 'POST', body: { urls: failedUrls.join('\n') } });
    if (d.error) { toast(d.error, 'error'); btn.disabled = false; btn.textContent = '🔄 Retry All Failed'; return; }
    toast(`Retry queue started: ${d.total} URLs`);
    // Reset queue monitor
    const items = document.getElementById('queue-items');
    items.innerHTML = d.urls.map((u, i) => `
      <div class="queue-item" id="qi-${i}">
        <span class="queue-idx">${i+1}</span>
        <span class="queue-url">${u.length > 50 ? u.substring(0,50)+'...' : u}</span>
        <span class="queue-item-status badge badge-default" id="qi-status-${i}">⏳ Waiting</span>
      </div>
    `).join('');
    document.getElementById('queue-progress-fill').style.width = '0%';
    document.getElementById('queue-pct').textContent = '0%';
    const badge = document.getElementById('queue-status');
    badge.className = 'badge badge-info'; badge.textContent = 'RUNNING';
    if (queueTimer) clearInterval(queueTimer);
    queueTimer = setInterval(() => pollQueue(d.queue_id, d.urls), 3000);
  } catch (e) { toast('Error: ' + e.message, 'error'); }
  btn.disabled = false;
  btn.textContent = '🔄 Retry All Failed';
}

async function pollJob(jobId) {
  try {
    const [job, logs] = await Promise.all([
      api(`/api/job/${jobId}`),
      api(`/api/pipeline/logs/${jobId}?offset=${logOffset}`)
    ]);
    // Progress
    const pct = job.progress || 0;
    document.getElementById('progress-fill').style.width = pct + '%';
    document.getElementById('progress-pct').textContent = pct + '%';
    document.getElementById('progress-msg').textContent = job.message || '';
    // Status badge
    const badge = document.getElementById('job-status');
    badge.className = 'badge badge-' + (job.status === 'done' ? 'success' : job.status === 'error' ? 'error' : 'info');
    badge.textContent = job.status?.toUpperCase();
    // Logs
    if (logs.lines?.length) {
      const box = document.getElementById('log-box');
      logs.lines.forEach(l => {
        const el = formatLogLine(l);
        box.appendChild(el);
      });
      box.scrollTop = box.scrollHeight;
      logOffset = logs.total;
    }
    // Done/Error
    if (job.status === 'done' || job.status === 'error') {
      clearInterval(pollTimer);
      if (job.status === 'done') {
        toast('Pipeline complete!');
        showResult(job.result);
      } else {
        toast('Pipeline failed: ' + job.message, 'error');
      }
    }
  } catch (e) { console.error(e); }
}

function showResult(r) {
  if (!r) return;
  const el = document.getElementById('pipeline-result');
  el.classList.remove('hidden');
  el.innerHTML = `
    <h2><span>🎉</span> Pipeline Complete</h2>
    <div class="grid-2">
      <div class="status-row">📁 Project: ${r.project_dir}</div>
      <div class="status-row">🎬 Video: ${r.final_video?.split(/[\\/]/).pop()}</div>
      <div class="status-row">📝 Title: ${r.metadata?.title || 'N/A'}</div>
      <div class="status-row">📤 YouTube: ${r.youtube?.url || 'Not uploaded'}</div>
    </div>
    <div class="btn-group">
      ${r.final_video ? `<a href="/api/project/${r.project_id}/file/final_video.mp4" class="btn btn-primary btn-sm">⬇ Download Video</a>` : ''}
      ${r.youtube?.url ? `<a href="${r.youtube.url}" target="_blank" class="btn btn-accent btn-sm">â–¶ Watch on YouTube</a>` : ''}
    </div>
  `;
}

// ── Projects ──
let currentProjectName = null;
let allProjectsData = [];
const ALL_STEPS = ['download','separate','stt','translate','tts','render','metadata','upload'];

function isProjectComplete(p) {
  const stepsArr = p.steps_completed || [];
  return stepsArr.length >= ALL_STEPS.length;
}

function hasYoutubeUploadSuccess(p) {
  const yt = p?.youtube || {};
  return !!(yt.videoId || yt.url);
}

async function loadProjects() {
  try {
    const d = await api('/api/projects');
    allProjectsData = d.projects || [];
    const filter = document.getElementById('project-filter')?.value || 'all';
    let filtered = [...allProjectsData];

    // Helper to get pct
    const getPct = (p) => Math.round((p.steps_completed || []).length / ALL_STEPS.length * 100);

    if (filter === 'completed') {
      filtered = allProjectsData.filter(p => isProjectComplete(p));
    } else if (filter === 'incomplete') {
      filtered = allProjectsData.filter(p => !isProjectComplete(p));
    } else if (filter === 'partial') {
      filtered = allProjectsData.filter(p => {
        const pct = getPct(p);
        return pct > 0 && pct < 100;
      });
    } else if (filter === 'yt-uploaded') {
      filtered = allProjectsData.filter(p => hasYoutubeUploadSuccess(p));
    } else if (filter === 'sort-pct-desc') {
      filtered.sort((a, b) => getPct(b) - getPct(a));
    } else if (filter === 'sort-pct-asc') {
        filtered.sort((a, b) => getPct(a) - getPct(b));
      } else if (filter.startsWith('custom_')) {
        const q = filter.replace('custom_', '').toLowerCase();
        filtered = allProjectsData.filter(p => {
           const ctx = p.series_context || (p.metadata || {}).series_context || {};
           const sf = (ctx.series_folder || '').toLowerCase();
           const sn = (ctx.series_name || '').toLowerCase();
           const pn = (p.project_name || '').toLowerCase();
           const title = ((p.metadata || {}).title || '').toLowerCase();
           return sf.includes(q) || sn.includes(q) || pn.includes(q) || title.includes(q);
        });
      }

    const el = document.getElementById('projects-list');
    const countBadge = document.getElementById('projects-count-badge');
    if (countBadge) countBadge.textContent = `${filtered.length} / ${allProjectsData.length} projects`;

    // Reset select-all checkbox
    const selectAllCb = document.getElementById('projects-select-all-cb');
    if (selectAllCb) selectAllCb.checked = false;
    updateProjectsSelectedCount();

    if (!filtered.length) {
      el.innerHTML = `<p style="color:var(--text-dim)">${
        filter === 'all' ? 'No projects yet'
        : filter === 'completed' ? 'Không có project nào đã hoàn thành'
        : filter === 'partial' ? 'Không có project nào đang dở dang'
        : filter === 'yt-uploaded' ? 'Không có project nào upload YouTube thành công'
        : 'Không có project nào chưa hoàn thành'
      }</p>`;
      return;
    }
    el.innerHTML = filtered.map((p, idx) => {
      const pname = p.project_name || 'Unknown';
      const aiTitle = (p.metadata || {}).title || '';
      const stepsArr = p.steps_completed || [];
      const pct = Math.round(stepsArr.length / ALL_STEPS.length * 100);
      const complete = isProjectComplete(p);
      const statusBadge = complete
        ? '<span class="badge badge-success" style="margin-left:auto;font-size:.65rem">✅ Done</span>'
        : '<span class="badge badge-info" style="margin-left:auto;font-size:.65rem">⏳ ' + pct + '%</span>';
      const checkboxHtml = !complete ? `
        <label class="project-checkbox" onclick="event.stopPropagation()">
          <input type="checkbox" class="project-cb" data-project="${pname}" onchange="updateProjectsSelectedCount()" />
        </label>` : '';
      const titleHtml = aiTitle
        ? `<h3 title="${aiTitle.replace(/"/g, '&quot;')}">🎬 ${aiTitle.length > 60 ? aiTitle.substring(0, 57) + '...' : aiTitle}</h3>
           <p style="margin:2px 0 0;font-size:.72rem;color:var(--text-dim);opacity:.8">📁 ${pname}</p>`
        : `<h3>📁 ${pname}</h3>`;
      return `
      <div class="project-card ${complete ? 'project-complete' : 'project-incomplete'}" onclick="openProjectDetail('${pname}')">
        <div class="project-card-header">
          ${checkboxHtml}
          <div style="flex:1;min-width:0">${titleHtml}</div>
          ${statusBadge}
        </div>
        <p>Created: ${p.created_at || 'N/A'}</p>
        <div class="steps-indicator">
          ${ALL_STEPS.map(s => `<div class="step-dot ${stepsArr.includes(s)?'done':''}"></div>`).join('')}
        </div>
        <p style="margin-top:4px;font-size:.7rem;color:var(--text-dim)">${pct}% — ${stepsArr.join(' → ') || 'no steps'}</p>
      </div>`;
    }).join('');
  } catch (e) { console.error(e); }
}

function toggleSelectAllProjects(checked) {
  document.querySelectorAll('.project-cb').forEach(cb => { cb.checked = checked; });
  updateProjectsSelectedCount();
}

function updateProjectsSelectedCount() {
  const cbs = document.querySelectorAll('.project-cb');
  let count = 0;
  cbs.forEach(cb => { if (cb.checked) count++; });
  
  const infoEl = document.getElementById('projects-selected-info');
  const countEl = document.getElementById('batch-resume-count');
  const deleteCountEl = document.getElementById('batch-delete-count');
  const btnResume = document.getElementById('btn-batch-resume');
  const btnDelete = document.getElementById('btn-batch-delete');
  
  if (infoEl) infoEl.textContent = `${count} đã chọn`;
  if (countEl) countEl.textContent = count;
  if (deleteCountEl) deleteCountEl.textContent = count;
  if (btnResume) btnResume.disabled = count === 0;
  if (btnDelete) btnDelete.disabled = count === 0;

  // Update select-all checkbox state
  const selectAllCb = document.getElementById('projects-select-all-cb');
  if (selectAllCb && cbs.length > 0) {
    selectAllCb.checked = count === cbs.length;
    selectAllCb.indeterminate = count > 0 && count < cbs.length;
  }
}

async function batchResumeProjects() {
  const selected = [];
  document.querySelectorAll('.project-cb:checked').forEach(cb => {
    selected.push(cb.dataset.project);
  });
  if (!selected.length) return toast('Chọn ít nhất 1 project', 'error');
  if (!confirm(`Resume pipeline cho ${selected.length} project?\n\n${selected.join('\n')}`)) return;

  toast(`Đang resume ${selected.length} projects...`);
  try {
    const d = await api('/api/pipeline/resume-batch', {
      method: 'POST',
      body: { projects: selected }
    });
    if (d.error) { toast(d.error, 'error'); return; }

    // Switch to pipeline tab and show queue
    switchTab('pipeline');
    document.getElementById('queue-monitor').classList.remove('hidden');
    const items = document.getElementById('queue-items');
    items.innerHTML = d.projects.map((name, i) => `
      <div class="queue-item" id="qi-${i}">
        <span class="queue-idx">${i+1}</span>
        <span class="queue-url" style="font-family:inherit;font-size:.85rem">📁 ${name}</span>
        <span class="queue-item-status badge badge-default" id="qi-status-${i}">⏳ Waiting</span>
      </div>
    `).join('');

    // Hide failed section from previous runs
    document.getElementById('queue-failed-section').classList.add('hidden');

    if (queueTimer) clearInterval(queueTimer);
    queueTimer = setInterval(() => pollResumeQueue(d.queue_id, d.projects), 3000);
    toast(`Batch resume started: ${selected.length} projects`);
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

async function batchDeleteProjects() {
  const selected = [];
  document.querySelectorAll('.project-cb:checked').forEach(cb => {
    selected.push(cb.dataset.project);
  });
  if (!selected.length) return toast('Chọn ít nhất 1 project', 'error');
  if (!confirm(`⚠️ XOÁ VĨNH VIỄN ${selected.length} project đã chọn?\n\nHành động này không thể hoàn tác!`)) return;

  toast(`Đang xoá ${selected.length} projects...`);
  try {
    const d = await api('/api/projects/bulk-delete', {
      method: 'POST',
      body: { projects: selected }
    });
    if (d.error) { toast(d.error, 'error'); return; }
    
    toast(`Đã xoá ${d.deleted.length} project thành công.`);
    if (d.errors?.length) {
      toast(`Có ${d.errors.length} lỗi khi xoá.`, 'error');
    }
    
    // Clear selection and refresh
    const selectAllCb = document.getElementById('projects-select-all-cb');
    if (selectAllCb) selectAllCb.checked = false;
    loadProjects();
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

async function scanDuplicates() {
  const btn = document.getElementById('btn-scan-duplicates');
  btn.disabled = true;
  btn.textContent = '⏳ Đang quét...';
  try {
    const d = await api('/api/projects/duplicates');
    if (d.error) { toast(d.error, 'error'); return; }
    
    if (!d.duplicates || !d.duplicates.length) {
      toast('Không tìm thấy project nào bị trùng URL.');
      return;
    }
    
    // Render duplicates modal
    const list = document.getElementById('duplicates-list');
    list.innerHTML = d.duplicates.map((group, gIdx) => {
      return `
      <div class="duplicate-group">
        <div class="duplicate-group-header">
          <strong>🔗 URL:</strong> <a href="${group.url}" target="_blank">${group.url.substring(0, 60)}...</a>
          <span class="badge badge-info">${group.projects.length} bản trùng</span>
        </div>
        <div class="duplicate-items">
          ${group.projects.map((p, pIdx) => {
            const isFirst = pIdx === 0; // Newest one
            const pct = Math.round((p.steps_completed || []).length / ALL_STEPS.length * 100);
            return `
            <label class="duplicate-item ${isFirst ? 'suggest-keep' : ''}">
              <input type="checkbox" class="dup-cb" data-project="${p.project_name}" ${!isFirst ? 'checked' : ''}>
              <div class="dup-info">
                <span class="dup-name">📁 ${p.project_name}</span>
                <span class="dup-meta">${p.created_at || 'N/A'} — ${pct}% hoàn thành</span>
                ${isFirst ? '<span class="badge badge-success" style="font-size:.6rem">Giữ lại (Mới nhất)</span>' : ''}
              </div>
            </label>`;
          }).join('')}
        </div>
      </div>`;
    }).join('');
    
    document.getElementById('duplicates-modal').classList.remove('hidden');
  } catch (e) { toast('Error: ' + e.message, 'error'); }
  btn.disabled = false;
  btn.textContent = '🔍 Quét trùng';
}

function closeDuplicatesModal() {
  document.getElementById('duplicates-modal').classList.add('hidden');
}

async function deleteSelectedDuplicates() {
  const selected = [];
  document.querySelectorAll('.dup-cb:checked').forEach(cb => {
    selected.push(cb.dataset.project);
  });
  
  if (!selected.length) return toast('Chọn ít nhất 1 project để xoá', 'error');
  if (!confirm(`Xoá vĩnh viễn ${selected.length} project đã chọn?`)) return;
  
  const btn = document.getElementById('btn-delete-duplicates');
  btn.disabled = true;
  btn.textContent = '⏳ Đang xoá...';
  
  try {
    const d = await api('/api/projects/bulk-delete', {
      method: 'POST',
      body: { projects: selected }
    });
    
    if (d.error) { toast(d.error, 'error'); }
    else {
      toast(`Đã xoá ${d.deleted.length} project.`);
      closeDuplicatesModal();
      loadProjects();
    }
  } catch (e) { toast('Error: ' + e.message, 'error'); }
  
  btn.disabled = false;
  btn.textContent = '🗑 Xoá các mục đã chọn';
}


async function openProjectDetail(projectName) {
  currentProjectName = projectName;
  try {
    const d = await api(`/api/project/${projectName}/detail`);
    if (d.error) { toast(d.error, 'error'); return; }
    const info = d.info || {};
    const steps = info.steps_completed || [];
    const allSteps = ['download','separate','stt','translate','tts','render','metadata','upload'];
    const stepLabels = ['DL','Sep','STT','Trans','TTS','Render','Meta','Upload'];

    // Header
    document.getElementById('modal-project-name').textContent = projectName;

    // Info grid
    document.getElementById('modal-project-info').innerHTML = `
      <div class="info-item"><span>Created</span>${info.created_at || 'N/A'}</div>
      <div class="info-item"><span>Total Size</span>${d.total_size_human}</div>
      <div class="info-item"><span>Files</span>${d.files.length} files</div>
      <div class="info-item"><span>Source URL</span>${info.source_url ? info.source_url.substring(0,40) + '...' : 'N/A'}</div>
    `;

    // Steps bar
    document.getElementById('modal-project-steps').innerHTML = allSteps.map((s, i) =>
      `<div class="step ${steps.includes(s) ? 'done' : 'pending'}">${stepLabels[i]}</div>`
    ).join('');

    // File type icons
    const icons = {video:'🎬', audio:'🎵', subtitle:'📝', image:'🖼️', data:'📋', other:'📄'};

    // File list
    const pid = info.project_id || projectName;
    document.getElementById('modal-project-files').innerHTML = d.files.map(f => `
      <div class="file-item">
        <div class="file-icon">${icons[f.type] || '📄'}</div>
        <div class="file-name" title="${f.name}">${f.name}</div>
        <div class="file-size">${f.size_human}</div>
        <a class="file-dl" href="/api/project/${pid}/file/${f.name}" download>⬇</a>
      </div>
    `).join('') || '<p style="color:var(--text-dim);padding:12px">No files</p>';

    // Show/hide resume button based on completion
    const isComplete = steps.length >= allSteps.length;
    document.getElementById('btn-resume').style.display = isComplete ? 'none' : '';
    const btnQueue = document.getElementById('btn-add-queue');
    if (isComplete) {
      btnQueue.style.display = 'none';
    } else {
      btnQueue.style.display = '';
      const inQueue = resumeQueue.includes(projectName);
      btnQueue.disabled = inQueue;
      btnQueue.textContent = inQueue ? '✅ In Queue' : '➕ Add to Queue';
    }

    // Show/hide watch video button
    const hasVideo = d.files.some(f => f.type === 'video');
    document.getElementById('btn-watch-video').style.display = hasVideo ? '' : 'none';

    // Show modal
    document.getElementById('project-modal').classList.remove('hidden');
  } catch (e) {
    toast('Error loading project: ' + e.message, 'error');
  }
}

function closeProjectModal() {
  document.getElementById('project-modal').classList.add('hidden');
}

function watchProjectVideo() {
  if (!currentProjectName) return;
  // Assume final_video.mp4 is the main output. If not, open any video.
  const url = `/api/project/${currentProjectName}/stream/preview`;
  window.open(url, '_blank');
}

async function resumeProject() {
  if (!currentProjectName) return;
  if (!confirm(`Resume pipeline for "${currentProjectName}"?`)) return;
  closeProjectModal();

  try {
    const d = await api(`/api/project/${currentProjectName}/resume`, { method: 'POST' });
    if (d.error) { toast(d.error, 'error'); return; }

    // Switch to pipeline tab and start monitoring
    switchTab('pipeline');
    currentJobId = d.job_id;
    logOffset = 0;
    document.getElementById('pipeline-monitor').classList.remove('hidden');
    document.getElementById('log-box').innerHTML = '';
    pollTimer = setInterval(() => pollJob(d.job_id), 2000);
    toast('Pipeline resuming!');
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

async function deleteProject() {
  if (!currentProjectName) return;
  if (!confirm(`⚠️ DELETE "${currentProjectName}" and ALL its files?\n\nThis cannot be undone!`)) return;

  try {
    const d = await api(`/api/project/${currentProjectName}`, { method: 'DELETE' });
    if (d.ok) {
      toast('Project deleted!');
      closeProjectModal();
      // Also remove from resume queue if present
      resumeQueue = resumeQueue.filter(p => p !== currentProjectName);
      renderResumeQueue();
      loadProjects();
    } else {
      toast(d.error || 'Delete failed', 'error');
    }
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

// ── Resume Queue ──
let resumeQueue = [];

function addToResumeQueue() {
  if (!currentProjectName) return;
  if (resumeQueue.includes(currentProjectName)) {
    toast('Already in queue!', 'error');
    return;
  }
  resumeQueue.push(currentProjectName);
  renderResumeQueue();
  toast(`âž• ${currentProjectName} added to resume queue`);
  closeProjectModal();
}

function removeFromResumeQueue(name) {
  resumeQueue = resumeQueue.filter(p => p !== name);
  renderResumeQueue();
}

function clearResumeQueue() {
  resumeQueue = [];
  renderResumeQueue();
  toast('Resume queue cleared');
}

function renderResumeQueue() {
  const card = document.getElementById('resume-queue-card');
  const list = document.getElementById('resume-queue-list');
  const count = document.getElementById('resume-queue-count');
  if (!resumeQueue.length) {
    card.classList.add('hidden');
    return;
  }
  card.classList.remove('hidden');
  count.textContent = resumeQueue.length;
  list.innerHTML = resumeQueue.map((name, i) => `
    <div class="queue-item">
      <span class="queue-idx">${i+1}</span>
      <span class="queue-url" style="font-family:inherit;font-size:.85rem">📁 ${name}</span>
      <button class="btn btn-outline btn-sm" onclick="removeFromResumeQueue('${name}')" style="padding:3px 8px;font-size:.7rem">✕</button>
    </div>
  `).join('');
}

async function startResumeQueue() {
  if (!resumeQueue.length) return toast('Queue is empty', 'error');
  if (!confirm(`Resume ${resumeQueue.length} project(s)?\n\n${resumeQueue.join('\n')}`)) return;

  const btn = document.getElementById('btn-start-resume-queue');
  btn.disabled = true;
  btn.textContent = '⏳ Starting...';

  try {
    const d = await api('/api/pipeline/resume-batch', {
      method: 'POST',
      body: { projects: resumeQueue }
    });
    if (d.error) { toast(d.error, 'error'); btn.disabled = false; btn.textContent = 'â–¶ Start Resume Queue'; return; }

    toast(`Resume queue started: ${d.total} projects`);

    // Switch to pipeline tab and show queue monitor
    switchTab('pipeline');
    document.getElementById('queue-monitor').classList.remove('hidden');
    const items = document.getElementById('queue-items');
    items.innerHTML = d.projects.map((name, i) => `
      <div class="queue-item" id="qi-${i}">
        <span class="queue-idx">${i+1}</span>
        <span class="queue-url" style="font-family:inherit;font-size:.85rem">📁 ${name}</span>
        <span class="queue-item-status badge badge-default" id="qi-status-${i}">⏳ Waiting</span>
      </div>
    `).join('');

    // Hide failed section from previous runs
    document.getElementById('queue-failed-section').classList.add('hidden');

    // Poll using the same queue polling mechanism
    // We need to adapt pollQueue for project-based queue (uses 'projects' instead of 'urls')
    selectedQueueId = d.queue_id;
    if (queueTimer) clearInterval(queueTimer);
    queueTimer = setInterval(() => pollResumeQueue(d.queue_id, d.projects), 3000);
    refreshActiveQueues();

    // Clear local queue
    resumeQueue = [];
    renderResumeQueue();
  } catch (e) { toast('Error: ' + e.message, 'error'); }
  btn.disabled = false;
  btn.textContent = 'â–¶ Start Resume Queue';
}

async function pollResumeQueue(queueId, projects) {
  try {
    const d = await api(`/api/pipeline/queue/${queueId}`);
    const q = d.queue || {};
    const pct = d.progress || 0;
    document.getElementById('queue-progress-fill').style.width = pct + '%';
    document.getElementById('queue-pct').textContent = pct + '%';
    document.getElementById('queue-msg').textContent = d.message || '';
    // Update status badge
    const badge = document.getElementById('queue-status');
    badge.className = 'badge ' + queueStatusBadgeClass(d.status);
    badge.textContent = d.status?.toUpperCase();
    // Update individual items
    const completed = q.completed || 0;
    const results = q.results || [];
    const errors = q.errors || [];
    const total = q.total || projects.length;
    for (let i = 0; i < total; i++) {
      const st = document.getElementById(`qi-status-${i}`);
      if (!st) continue;
      if (i < completed) {
        const wasError = errors.find(e => e.project === projects[i]);
        if (wasError) {
          st.className = 'badge badge-error'; st.textContent = '❌ Failed';
        } else {
          st.className = 'badge badge-success'; st.textContent = '✅ Done';
        }
      } else if (i === completed && (d.status === 'running' || d.status === 'paused')) {
        if (d.status === 'paused') {
          st.className = 'badge badge-warning';
          st.textContent = q.current_job ? 'Finishing...' : 'Paused';
        } else {
          st.className = 'badge badge-info';
          st.textContent = '🔄 Resuming...';
        }
        if (q.current_job && !currentJobId) {
          currentJobId = q.current_job;
          logOffset = 0;
          document.getElementById('pipeline-monitor').classList.remove('hidden');
          document.getElementById('log-box').innerHTML = '';
          if (pollTimer) clearInterval(pollTimer);
          pollTimer = setInterval(() => pollJob(q.current_job), 2000);
        } else if (q.current_job && q.current_job !== currentJobId) {
          currentJobId = q.current_job;
          logOffset = 0;
          document.getElementById('log-box').innerHTML = '';
          if (pollTimer) clearInterval(pollTimer);
          pollTimer = setInterval(() => pollJob(q.current_job), 2000);
        }
      }
    }
    if (d.status === 'done' || d.status === 'error') {
      clearInterval(queueTimer);
      refreshActiveQueues();
      for (let i = 0; i < total; i++) {
        const st = document.getElementById(`qi-status-${i}`);
        if (!st) continue;
        const wasError = errors.find(e => e.project === projects[i]);
        if (wasError) {
          st.className = 'badge badge-error'; st.textContent = '❌ Failed';
        } else {
          st.className = 'badge badge-success'; st.textContent = '✅ Done';
        }
      }
      if (d.status === 'done') {
        toast(`Resume queue complete: ${results.length}/${total} success${errors.length ? `, ${errors.length} failed` : ''}`);
      }
      // Show failed section if errors
      if (errors.length > 0) {
        lastQueueErrors = errors.map(e => ({ url: e.project, job_id: e.job_id, error: e.error }));
        showFailedSection(lastQueueErrors);
      }
    }
  } catch (e) { console.error(e); }
}

// ── Settings ──
async function loadConfig() {
  try {
    const d = await api('/api/config');
    const fields = ['channel_name','youtube_title_mode','youtube_upload_strategy','whisper_model','source_lang',
      'target_lang','translation_style','translation_provider','translation_provider_order',
      'ninerouter_url','ninerouter_key','ninerouter_model','ninerouter_timeout',
      'webai_url','webai_model',
      'tiktok_upload_provider','tiktok_api_client_key','tiktok_api_client_secret','tiktok_api_redirect_uri',
      'tiktok_api_scopes','tiktok_api_pkce_challenge_format','tiktok_api_privacy_level','tiktok_api_poll_timeout_sec','tiktok_api_poll_interval_sec',
      'facebook_app_id','facebook_app_secret',
      'facebook_page_access_token','facebook_reels_actor_id','facebook_graph_version','facebook_reels_video_state',
      'facebook_reels_poll_timeout_sec','facebook_reels_poll_interval_sec','facebook_reels_request_timeout_sec',
      'facebook_api_proxy','facebook_upload_mode','facebook_reels_short_threshold_sec','facebook_reels_max_minutes','facebook_reels_auto_split',
      'tts_engine','vieneu_voice','vieneu_mode','vieneu_ref_voice','capcut_voice','capcut_tts_workers','capcut_tts_pipeline_limit','tts_speed','tts_pitch','tts_volume','demucs_model',
      'tiktok_max_minutes','tiktok_caption_max_chars','tiktok_upload_timeout_sec',
      'blur_sigma','mask_h','mask_y_pct',
      'thumbnail_mode','ai_thumbnail_provider','ai_thumbnail_model','ai_thumbnail_timeout_sec','ai_thumbnail_style','ai_thumbnail_api_key','ai_thumbnail_cloudflare_account_id','ai_thumbnail_cloudflare_api_token','ai_thumbnail_cloudflare_mode','ai_thumbnail_img2img_strength','ai_thumbnail_steps',
      'font_name','font_name_thumb','font_size','margin_v','rotate_deg','projects_dir','privacy',
      'douyin_warp_proxy', 'batch_pipeline_concurrency', 'download_concurrency', 'gpu_heavy_concurrency', 'pipeline_retry_max', 'operation_mode'];
    fields.forEach(f => {
      const el = document.getElementById('cfg-' + f);
      if (el) {
        if (f === 'vieneu_ref_voice' && !d[f]) {
          el.value = 'sample.WAV';
        } else if (f === 'youtube_title_mode' && !d[f]) {
          el.value = 'ai';
        } else if (f === 'facebook_upload_mode' && !d[f]) {
          el.value = 'auto';
        } else if (f === 'facebook_reels_short_threshold_sec' && !d[f]) {
          el.value = '90';
        } else if (f === 'facebook_reels_auto_split' && typeof d[f] === 'boolean') {
          el.value = d[f] ? 'true' : 'false';
        } else if (f === 'ai_thumbnail_api_key') {
          el.value = '';
          el.placeholder = d.ai_thumbnail_api_key_masked ? `Saved: ${d.ai_thumbnail_api_key_masked}` : 'Leave blank to keep saved key';
        } else if (f === 'ai_thumbnail_cloudflare_api_token') {
          el.value = '';
          el.placeholder = d.ai_thumbnail_cloudflare_api_token_masked ? `Saved: ${d.ai_thumbnail_cloudflare_api_token_masked}` : 'Leave blank to keep saved token';
        } else {
          el.value = d[f] ?? '';
        }
      }
    });
    const cb = ['mirror','use_intro','auto_upload','auto_adjust_tts_speed','auto_upload_tiktok','auto_upload_facebook_reels','tiktok_auto_split','tiktok_headless','upload_fifo_strict','pipeline_skip_after_retry_exhausted','enable_webai_fallback','auto_mask_position'];
    cb.forEach(f => {
      const el = document.getElementById('cfg-' + f);
      if (el) el.checked = !!d[f];
    });
    // WARP checkbox
    const warpCb = document.getElementById('cfg-douyin_warp_enabled');
    if (warpCb) {
      warpCb.checked = !!d.douyin_warp_enabled;
      _updateWarpUI(!!d.douyin_warp_enabled);
    }

    toggleTtsOptions();
    toggleWorkerTab();
  } catch (e) { console.error(e); }
}

function toggleWorkerTab() {
  const opModeEl = document.getElementById('cfg-operation_mode');
  const workerTabBtn = document.querySelector('.tab[data-tab="workers"]');
  if (workerTabBtn && opModeEl) {
    if (opModeEl.value === 'master_worker') {
      workerTabBtn.style.display = 'inline-block';
    } else {
      workerTabBtn.style.display = 'none';
      if (currentTab === 'workers') switchTab('pipeline');
    }
  }
}

async function saveConfig() {
  const fields = ['channel_name','youtube_title_mode','youtube_upload_strategy','whisper_model','source_lang',
    'target_lang','translation_style','translation_provider','translation_provider_order',
    'ninerouter_url','ninerouter_key','ninerouter_model','ninerouter_timeout',
    'webai_url','webai_model',
    'tiktok_upload_provider','tiktok_api_client_key','tiktok_api_client_secret','tiktok_api_redirect_uri',
    'tiktok_api_scopes','tiktok_api_pkce_challenge_format','tiktok_api_privacy_level','tiktok_api_poll_timeout_sec','tiktok_api_poll_interval_sec',
    'facebook_app_id','facebook_app_secret',
    'facebook_page_access_token','facebook_reels_actor_id','facebook_graph_version','facebook_reels_video_state',
    'facebook_reels_poll_timeout_sec','facebook_reels_poll_interval_sec','facebook_reels_request_timeout_sec',
    'facebook_api_proxy','facebook_upload_mode','facebook_reels_short_threshold_sec','facebook_reels_max_minutes','facebook_reels_auto_split',
    'tts_engine','vieneu_voice','vieneu_mode','vieneu_ref_voice','capcut_voice','capcut_tts_workers','capcut_tts_pipeline_limit','tts_speed','tts_pitch','tts_volume','demucs_model',
    'tiktok_max_minutes','tiktok_caption_max_chars','tiktok_upload_timeout_sec',
    'ffmpeg_encoder','blur_sigma','mask_h','mask_y_pct',
    'thumbnail_mode','ai_thumbnail_provider','ai_thumbnail_model','ai_thumbnail_timeout_sec','ai_thumbnail_style','ai_thumbnail_api_key','ai_thumbnail_cloudflare_account_id','ai_thumbnail_cloudflare_api_token','ai_thumbnail_cloudflare_mode','ai_thumbnail_img2img_strength','ai_thumbnail_steps',
    'font_name','font_name_thumb','font_size','margin_v','rotate_deg','projects_dir','privacy',
    'douyin_warp_proxy', 'batch_pipeline_concurrency', 'download_concurrency', 'gpu_heavy_concurrency', 'pipeline_retry_max', 'operation_mode'];
  const cfg = {};
  fields.forEach(f => {
    const el = document.getElementById('cfg-' + f);
    if (el) {
      const v = el.value;
      if (f === 'ai_thumbnail_api_key' && !String(v || '').trim()) return;
      if (f === 'ai_thumbnail_cloudflare_api_token' && !String(v || '').trim()) return;
      cfg[f] = ['blur_sigma','mask_h','font_size','margin_v','ninerouter_timeout','tiktok_max_minutes','tiktok_caption_max_chars','tiktok_upload_timeout_sec','tiktok_api_poll_timeout_sec','tiktok_api_poll_interval_sec','facebook_reels_poll_timeout_sec','facebook_reels_poll_interval_sec','facebook_reels_request_timeout_sec','facebook_reels_short_threshold_sec','facebook_reels_max_minutes', 'batch_pipeline_concurrency', 'download_concurrency', 'gpu_heavy_concurrency', 'pipeline_retry_max','ai_thumbnail_timeout_sec','ai_thumbnail_steps'].includes(f) ? parseInt(v) || 0
        : ['mask_y_pct','rotate_deg','tts_speed','tts_pitch','tts_volume','ai_thumbnail_img2img_strength'].includes(f) ? parseFloat(v) || 0 : v;
      if (f === 'facebook_reels_auto_split') cfg[f] = String(v) === 'true';
    }
  });
  ['mirror','use_intro','auto_upload','auto_adjust_tts_speed','auto_upload_tiktok','auto_upload_facebook_reels','tiktok_auto_split','tiktok_headless','upload_fifo_strict','pipeline_skip_after_retry_exhausted','enable_webai_fallback','auto_mask_position'].forEach(f => {
    const el = document.getElementById('cfg-' + f);
    if (el) cfg[f] = el.checked;
  });
  // WARP boolean
  const warpEl = document.getElementById('cfg-douyin_warp_enabled');
  if (warpEl) cfg.douyin_warp_enabled = warpEl.checked;

  await api('/api/config', { method: 'POST', body: cfg });
  toast('Settings saved!');
}

function toggleTtsOptions() {
  const engine = document.getElementById('cfg-tts_engine')?.value || 'vieneu';
  const mode = document.getElementById('cfg-vieneu_mode')?.value || 'preset';
  
  const vieneuModeGroup = document.getElementById('vieneu-mode-group');
  const vieneuVoiceGroup = document.getElementById('vieneu-voice-group');
  const vnRef = document.getElementById('vieneu-ref-group');
  const capcutGroup = document.getElementById('capcut-voice-group');
  const capcutWorkersGroup = document.getElementById('capcut-workers-group');
  
  if (vieneuModeGroup) vieneuModeGroup.style.display = engine === 'vieneu' ? '' : 'none';
  if (vieneuVoiceGroup) vieneuVoiceGroup.style.display = (engine === 'vieneu' && mode === 'preset') ? '' : 'none';
  if (vnRef) vnRef.style.display = (engine === 'vieneu' && mode === 'clone') ? '' : 'none';
  if (capcutGroup) capcutGroup.style.display = (engine === 'capcut' || engine === 'capcut_native') ? '' : 'none';
  if (capcutWorkersGroup) capcutWorkersGroup.style.display = (engine === 'capcut' || engine === 'capcut_native') ? '' : 'none';
}

// ── WARP Proxy UI ──
function _updateWarpUI(enabled) {
    const badge = document.getElementById('warp-status-badge');
    const label = document.getElementById('warp-label');
    const fLabel = document.getElementById('floating-warp-label');
    const fToggle = document.getElementById('floating-warp-toggle');
    const mToggle = document.getElementById('cfg-douyin_warp_enabled');
    
    if (badge) {
      badge.textContent = enabled ? 'Bật' : 'Tắt';
      badge.style.background = enabled ? 'rgba(255,127,0,.2)' : 'rgba(136,136,168,.12)';
      badge.style.color = enabled ? '#ff7f00' : 'var(--text-dim)';
    }
    if (label) {
      label.textContent = enabled ? '⚡ WARP đang bật — Douyin traffic sẽ đi qua WARP' : 'Tắt';
      label.style.color = enabled ? '#ff7f00' : 'var(--text-dim)';
    }
    if (fLabel) {
      fLabel.textContent = enabled ? 'WARP ON' : 'OFF';
      fLabel.style.color = enabled ? '#ff7f00' : 'var(--text-dim)';
      const widget = document.getElementById('floating-proxy-widget');
      if (widget) {
          widget.style.borderColor = enabled ? 'rgba(255,127,0,0.8)' : 'rgba(255,127,0,0.4)';
          widget.style.boxShadow = enabled ? '0 8px 24px rgba(255,127,0,0.3)' : '0 8px 24px rgba(0,0,0,0.5)';
      }
    }
    if (fToggle && fToggle.checked !== enabled) fToggle.checked = enabled;
    if (mToggle && mToggle.checked !== enabled) mToggle.checked = enabled;
  }

  // Bind the floating toggle
  document.addEventListener('DOMContentLoaded', () => {
      const fToggle = document.getElementById('floating-warp-toggle');
      if (fToggle) {
          fToggle.addEventListener('change', (e) => {
              e.stopPropagation();
              onWarpToggle(e.target);
          });
      }
  });

function onWarpToggle(cb) {
  _updateWarpUI(cb.checked);
  if (cb.checked) {
    const proxy = document.getElementById('cfg-douyin_warp_proxy')?.value?.trim() || 'socks5://127.0.0.1:40000';
    toast(`🛡 WARP bật! Douyin sẽ đi qua ${proxy}`, 'success');
  } else {
    toast('WARP tắt — Douyin dùng kết nối trực tiếp');
  }
}

async function testWarpProxy() {
  const btn = event.target;
  const resultEl = document.getElementById('warp-test-result');
  const proxy = document.getElementById('cfg-douyin_warp_proxy')?.value?.trim() || 'socks5://127.0.0.1:40000';
  btn.disabled = true;
  btn.textContent = '⏳ Testing...';
  resultEl.innerHTML = '<span style="color:var(--text-dim)">Connecting...</span>';
  try {
    const d = await api('/api/warp/test', { method: 'POST', body: { proxy } });
    if (d.ok) {
      resultEl.innerHTML = `<span style="color:#4ade80">✅ OK — IP: ${d.ip || '?'} (${d.latency_ms || '?'}ms)</span>`;
      toast('🛡 WARP proxy hoạt động!', 'success');
    } else {
      resultEl.innerHTML = `<span style="color:#f87171">❌ ${d.error || 'Không kết nối được'}</span><br><span style="font-size:.72rem;color:var(--text-dim)">Setup: WARP app → Settings → Advanced → bật "WARP as local proxy"</span>`;
      toast('WARP test thất bại: ' + (d.error || ''), 'error');
    }
  } catch (e) {
    resultEl.innerHTML = `<span style="color:#f87171">❌ Lỗi: ${e.message}</span>`;
  }
  btn.disabled = false;
  btn.textContent = '🔌 Test';
}

async function checkApiKey() {
  const keyInput = document.getElementById('cfg-api_key');
  const key = keyInput?.value?.trim();
  const btn = document.getElementById('btn-check-api');
  const statusEl = document.getElementById('api-key-status');
  if (!key) { toast('Enter an API key first', 'error'); return; }
  btn.disabled = true;
  btn.textContent = '⏳ Checking...';
  statusEl.innerHTML = '<span style="color:var(--text-dim)">Testing API key...</span>';
  try {
    const d = await api('/api/check-api-key', { method: 'POST', body: { api_key: key } });
    if (d.ok) {
      statusEl.innerHTML = `<span style="color:#4ade80">${d.message}</span>`;
      toast('API key is valid!');
    } else {
      statusEl.innerHTML = `<span style="color:#f87171">${d.error}</span>`;
      toast(d.error, 'error');
    }
  } catch (e) {
    statusEl.innerHTML = `<span style="color:#f87171">❌ Connection error: ${e.message}</span>`;
    toast('Check failed: ' + e.message, 'error');
  }
  btn.disabled = false;
  btn.textContent = '🔑 Check';
}

async function checkADC() {
  const btn = document.getElementById('btn-check-adc');
  const statusEl = document.getElementById('api-key-status');
  btn.disabled = true;
  btn.textContent = '⏳ Checking...';
  statusEl.innerHTML = '<span style="color:var(--text-dim)">Testing Vertex AI (ADC)...</span>';
  try {
    const d = await api('/api/check-api-key', { method: 'POST', body: { use_adc: true } });
    if (d.ok) {
      statusEl.innerHTML = `<span style="color:#4ade80">${d.message}</span>`;
      toast('ADC works! Using GCP credits');
    } else {
      statusEl.innerHTML = `<span style="color:#f87171">${d.error}</span>`;
      toast(d.error, 'error');
    }
  } catch (e) {
    statusEl.innerHTML = `<span style="color:#f87171">❌ Connection error: ${e.message}</span>`;
    toast('ADC check failed: ' + e.message, 'error');
  }
  btn.disabled = false;
  btn.textContent = '☁️ Check ADC';
}

// ── Douyin Login ──

async function checkGDriveStatus() {
  const el = document.getElementById('gdrive-status');
  if (el) el.textContent = 'Google Drive: checking...';
  try {
    const d = await api('/api/gdrive/status');
    if (d.authenticated) {
      if (el) el.textContent = 'Google Drive: connected';
      return true;
    }
    if (el) el.textContent = `Google Drive: not connected (${d.reason || 'need login'})`;
    return false;
  } catch (e) {
    if (el) el.textContent = 'Google Drive: backend route not available. Restart server after current queue finishes.';
    return false;
  }
}


function gdriveLogin() {
  window.open(`${API}/api/gdrive/login`, '_blank');
  toast('Opened Google Drive login. After consent, click Check Drive.');
}

function pollGDriveJob(jobId, onDone, statusEl) {
  let ticks = 0;
  const timer = setInterval(async () => {
    ticks += 1;
    try {
      const job = await api(`/api/gdrive/job/${jobId}`, { timeoutMs: 10000 });
      if (!job.ok) throw new Error(job.error || 'job not found');
      if (statusEl) statusEl.textContent = `Google Drive ${job.kind}: ${job.status} - ${job.message || ''}`;
      if (job.status === 'done') {
        clearInterval(timer);
        onDone?.(job.result, job);
      } else if (job.status === 'error') {
        clearInterval(timer);
        toast(job.error || 'Google Drive job failed', 'error');
        if (statusEl) statusEl.textContent = `Google Drive error: ${job.error || 'unknown error'}`;
      }
      if (ticks > 1800) {
        clearInterval(timer);
        if (statusEl) statusEl.textContent = 'Google Drive job still running in background. Refresh status later.';
      }
    } catch (e) {
      clearInterval(timer);
      toast('Google Drive job status error: ' + e.message, 'error');
      if (statusEl) statusEl.textContent = 'Google Drive job status error: ' + e.message;
    }
  }, 2000);
}

async function syncProjectsFromGDrive() {
  const el = document.getElementById('gdrive-sync-status');
  if (el) el.textContent = 'Starting Google Drive sync...';
  try {
    const d = await api('/api/gdrive/sync_projects', {
      method: 'POST',
      body: { overwrite: false },
      timeoutMs: 15000
    });
    if (!d.ok) {
      if (el) el.textContent = 'Sync failed: ' + (d.error || 'unknown error');
      toast(d.error || 'Google Drive sync failed', 'error');
      return;
    }
    if (el) el.textContent = `Google Drive sync started: ${d.job_id}`;
    pollGDriveJob(d.job_id, (payload) => {
      const r = payload?.result || {};
      const msg = `Drive sync done: ${r.synced?.length || 0} synced, ${r.skipped?.length || 0} skipped, ${r.errors?.length || 0} errors.`;
      if (el) el.textContent = msg;
      toast(msg);
      if (typeof loadProjects === 'function') loadProjects();
    }, el);
  } catch (e) {
    if (el) el.textContent = 'Sync start error: ' + e.message;
    toast('Google Drive sync start error: ' + e.message, 'error');
  }
}

async function massUploadVideosGDrive() {
  const el = document.getElementById('gdrive-sync-status');
  if (el) el.textContent = 'Starting Mass Upload to Drive...';
  try {
    const d = await api('/api/gdrive/mass_upload_videos', { method: 'POST', timeoutMs: 15000 });
    if (!d.ok) {
      if (el) el.textContent = 'Mass upload failed: ' + (d.error || 'unknown error');
      toast(d.error || 'Mass upload failed', 'error');
      return;
    }
    if (el) el.textContent = `Mass upload started: ${d.job_id}`;
    pollGDriveJob(d.job_id, (payload) => {
      const r = payload || {};
      const msg = `Drive Mass Upload done: ${r.uploaded_projects || 0} projects uploaded.`;
      if (el) el.textContent = msg;
      toast(msg);
      if (typeof loadProjects === 'function') loadProjects();
    }, el);
  } catch (e) {
    if (el) el.textContent = 'Mass upload start error: ' + e.message;
    toast('Mass upload start error: ' + e.message, 'error');
  }
}

async function uploadProjectGDrive() {
  if (!currentProjectName) return;
  const btn = document.getElementById('btn-gdrive-upload');
  const oldText = btn ? btn.textContent : '';
  if (btn) {
    btn.disabled = true;
    btn.textContent = 'Starting Drive job...';
  }
  try {
    const d = await api(`/api/project/${currentProjectName}/upload_gdrive`, {
      method: 'POST',
      timeoutMs: 15000
    });
    if (!d.ok) {
      toast(d.error || 'Google Drive upload failed', 'error');
      return;
    }
    toast(`Google Drive upload started: ${d.job_id}`);
    pollGDriveJob(d.job_id, (payload) => {
      const result = payload?.result || {};
      const uploaded = result.uploaded?.length ?? result.result?.uploaded?.length ?? 0;
      const skipped = result.skipped?.length ?? result.result?.skipped?.length ?? 0;
      toast(`Google Drive uploaded ${uploaded} files, skipped ${skipped}`);
      if (btn) btn.textContent = oldText || 'Upload Drive';
    });
  } catch (e) {
    toast('Google Drive upload start error: ' + e.message, 'error');
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = oldText || 'Upload Drive';
    }
  }
}

async function testTranslationApi() {
  const btn = document.getElementById('btn-test-translation');
  const statusEl = document.getElementById('translation-test-status');
  if (!btn || !statusEl) return;

  const payload = {
    source_lang: document.getElementById('cfg-source_lang')?.value?.trim() || 'zh',
    target_lang: document.getElementById('cfg-target_lang')?.value?.trim() || 'vi',
    translation_provider: document.getElementById('cfg-translation_provider')?.value || '9router',
    translation_provider_order: document.getElementById('cfg-translation_provider_order')?.value || '',
    ninerouter_url: document.getElementById('cfg-ninerouter_url')?.value || 'http://127.0.0.1:20128',
    ninerouter_key: document.getElementById('cfg-ninerouter_key')?.value || '',
    ninerouter_model: document.getElementById('cfg-ninerouter_model')?.value || '',
    ninerouter_timeout: parseInt(document.getElementById('cfg-ninerouter_timeout')?.value || '60', 10) || 60,
    webai_url: document.getElementById('cfg-webai_url')?.value || 'http://127.0.0.1:6969',
    webai_model: document.getElementById('cfg-webai_model')?.value || 'gemini-3-flash',
    enable_webai_fallback: !!document.getElementById('cfg-enable_webai_fallback')?.checked
  };

  btn.disabled = true;
  btn.textContent = '\u23f3 Testing...';
  statusEl.innerHTML = '<span style="color:var(--text-dim)">\u0110ang test provider d\u1ecbch...</span>';
  try {
    const d = await api('/api/translation/test', { method: 'POST', body: payload });
    if (d.ok) {
      const isComboAlias = d.provider === '9router' && d.model === 'a';
      const modelLabel = isComboAlias ? 'combo alias' : 'model th\u1eadt';
      const model = d.model ? ` | ${modelLabel}: ${d.model}${isComboAlias ? ' - restart backend \u0111\u1ec3 l\u1ea5y model th\u1eadt' : ''}` : '';
      const sample = d.sample_output ? `<br><span style="color:var(--text-dim)">Output: ${d.sample_output}</span>` : '';
      statusEl.innerHTML = `<span style="color:#4ade80">\u2705 OK: ${d.provider}${model} (${d.latency_ms}ms)</span>${sample}`;
      toast(`Translation API OK: ${d.provider}${d.model ? ' | ' + d.model : ''}`);
    } else {
      const attempts = Array.isArray(d.attempts) && d.attempts.length
        ? d.attempts.map(a => `${a.provider}: ${a.error}`).join(' | ')
        : (d.error || 'Unknown error');
      statusEl.innerHTML = `<span style="color:#f87171">\u274c ${attempts}</span>`;
      toast('Translation test failed', 'error');
    }
  } catch (e) {
    statusEl.innerHTML = `<span style="color:#f87171">\u274c Connection error: ${e.message}</span>`;
    toast('Translation test failed: ' + e.message, 'error');
  }
  btn.disabled = false;
  btn.textContent = 'Test Translation API';
}

async function douyinLogin() {
  const d = await api('/api/douyin/login', { method: 'POST' });
  if (d.login_id) {
    toast('Chromium opened — login to Douyin');
    const poll = setInterval(async () => {
      const s = await api(`/api/douyin/login/${d.login_id}`);
      if (s.status === 'done') { clearInterval(poll); toast('Douyin cookies saved!'); checkHealth(); }
      if (s.status === 'error' || s.status === 'timeout') { clearInterval(poll); toast('Login failed', 'error'); }
    }, 3000);
  }
}

// ── YouTube Auth ──
async function youtubeLogin() {
  const d = await api('/api/youtube/login', { method: 'POST' });
  if (d.ok) { toast('YouTube connected!'); checkHealth(); }
  else toast(d.error || 'Failed', 'error');
}

async function addYoutubeChannel() {
  const name = document.getElementById('yt-new-name').value.trim();
  if (!name) return toast('Nhập tên gợi nhớ (vd: Kenh2)', 'error');
  if (!/^[a-zA-Z0-9_-]+$/.test(name)) return toast('Tên chỉ chứa chữ, số, dấu gạch', 'error');
  toast(`Đang mở trình duyệt cho kênh "${name}"...`);
  try {
    const d = await api('/api/youtube/login', { method: 'POST', body: { name } });
    if (d.ok) {
      toast('Đã thêm kênh mới!');
      document.getElementById('yt-new-name').value = '';
      checkHealth();
    } else toast(d.error || 'L?i', 'error');
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

async function toggleYtChannel(key, enabled) {
  try {
    const d = await api('/api/youtube/toggle', { method: 'POST', body: { key, enabled } });
    if (d.ok) {
      toast(`Kênh [${key}]: ${enabled ? 'BẬT ✅' : 'TẮT ⚫'}`);
      checkHealth();
    } else toast(d.error || 'L?i', 'error');
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

async function removeYtChannel(key) {
  if (!confirm(`⚠️ Xóa kênh "${key}"? Token sẽ bị xóa và cần login lại nếu muốn dùng.`)) return;
  try {
    const d = await api('/api/youtube/logout', { method: 'POST', body: { key } });
    if (d.ok) { toast(d.message); checkHealth(); }
    else toast(d.error || 'L?i', 'error');
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

async function importYTSecrets() {
  const v = document.getElementById('yt-secrets-json').value.trim();
  if (!v) return toast('Paste JSON first', 'error');
  const d = await api('/api/youtube/import-secrets', { method: 'POST', body: { json: v } });
  if (d.ok) toast('Secrets imported!');
  else toast(d.error, 'error');
}


function loadGDriveSecretsFile(input) {
  const file = input?.files?.[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => {
    const el = document.getElementById('gdrive-secrets-json');
    if (el) el.value = String(reader.result || '').trim();
    toast(`Loaded ${file.name}`);
  };
  reader.onerror = () => toast('Cannot read Google Drive JSON file', 'error');
  reader.readAsText(file, 'utf-8');
}

async function importGDriveSecrets() {
  const el = document.getElementById('gdrive-secrets-json');
  const v = (el?.value || '').trim();
  if (!v) return toast('Choose or paste Google Drive OAuth JSON first', 'error');
  const d = await api('/api/gdrive/import-secrets', { method: 'POST', body: { json: v, reset_token: true } });
  if (d.ok) {
    toast('Google Drive JSON imported. Login Drive again.');
    if (el) el.value = '';
    const file = document.getElementById('gdrive-secrets-file');
    if (file) file.value = '';
    checkGDriveStatus();
  } else {
    toast(d.error || 'Google Drive JSON import failed', 'error');
  }
}

async function loadYoutubeWatchdogState() {
  const statusEl = document.getElementById('ytwd-status');
  if (!statusEl) return;
  try {
    const d = await api('/api/youtube/watchdog/state', { timeoutMs: 60000 });
    if (!d.ok) { statusEl.textContent = d.error || 'Watchdog state error'; return; }
    const enabled = !!d.enabled;
    const setNum = (id, v) => {
      const el = document.getElementById(id);
      if (el) el.value = String(v ?? '');
    };
    const cben = document.getElementById('ytwd-enabled');
    if (cben) cben.checked = enabled;
    setNum('ytwd-interval', d.interval_min);
    setNum('ytwd-stuck', d.stuck_minutes);
    setNum('ytwd-retries', d.max_retries);
    setNum('ytwd-minviews', d.min_views_to_skip);
    statusEl.textContent = `Watchdog: ${enabled ? 'ON' : 'OFF'} | Running: ${d.running ? 'YES' : 'NO'} | Last run: ${d.last_run_at || 'N/A'} | ${d.last_summary || ''}`;
  } catch (e) {
    statusEl.textContent = `Watchdog state error: ${e.message}`;
  }
}

async function saveYoutubeWatchdogConfig() {
  const payload = {
    youtube_watchdog_enabled: !!document.getElementById('ytwd-enabled')?.checked,
    youtube_watchdog_interval_min: parseInt(document.getElementById('ytwd-interval')?.value || '15', 10) || 15,
    youtube_watchdog_stuck_minutes: parseInt(document.getElementById('ytwd-stuck')?.value || '120', 10) || 120,
    youtube_watchdog_max_retries: parseInt(document.getElementById('ytwd-retries')?.value || '2', 10) || 2,
    youtube_watchdog_min_views_to_skip: parseInt(document.getElementById('ytwd-minviews')?.value || '1', 10) || 1,
  };
  try {
    const d = await api('/api/config', { method: 'POST', body: payload });
    if (d.ok) {
      toast('Watchdog config saved');
      await loadYoutubeWatchdogState();
    } else {
      toast(d.error || 'Save failed', 'error');
    }
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

function _ytStatusText(v) {
  const up = (v.upload_status || '').toLowerCase();
  const ps = (v.processing_status || '').toLowerCase();
  if (up === 'failed' || up === 'rejected' || ps === 'failed' || ps === 'terminated') return `FAILED ${up || ps}`;
  if (ps === 'processing' || up === 'uploaded') return `PROCESSING ${ps || up}`;
  return `OK ${ps || up || 'ok'}`;
}

let ytmgrRows = [];
let ytmgrLastMode = 'plain'; // plain | match

function _ytmgrEsc(s) {
  return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function _ytmgrEscJs(s) {
  return String(s || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function _ytMatchCell(row) {
  const m = row?.match;
  if (!m) return '<span style="color:var(--text-dim)">-</span>';
  const source = row.match_source === 'video_id' ? 'ID map' : 'Fuzzy';
  const scorePct = typeof m.score === 'number' ? Math.round(m.score * 100) : 0;
  const finalTag = m.has_final_video ? '🎬 final' : '⚠ no-final';
  const score = row.match_source === 'video_id' ? '' : ` (${scorePct}%)`;
  return `
    <div style="line-height:1.35">
      <div style="font-weight:600">${_ytmgrEsc(m.project_name || '-')}</div>
      <div style="font-size:.75rem;color:var(--text-dim)">${source}${score} • ${finalTag}</div>
    </div>
  `;
}

function _ytStatusKey(v) {
  const up = String(v?.upload_status || '').toLowerCase();
  const ps = String(v?.processing_status || '').toLowerCase();
  if (up === 'failed' || up === 'rejected' || ps === 'failed' || ps === 'terminated') return 'failed';
  if (ps === 'processing' || up === 'uploaded') return 'processing';
  if (ps === 'succeeded') return 'succeeded';
  return 'other';
}

function _renderYoutubeRows(rows, mode = 'plain') {
  const body = document.getElementById('ytmgr-table-body');
  const matchStatus = document.getElementById('ytmgr-match-status');
  if (!body) return;
  if (!rows || !rows.length) {
    body.innerHTML = '<tr><td colspan="6" style="padding:10px;color:var(--text-dim)">No videos</td></tr>';
    if (matchStatus && mode !== 'match') matchStatus.textContent = '';
    return;
  }
  body.innerHTML = rows.map(row => {
    const v = row.video || {};
    const title = _ytmgrEsc(v.title || '');
    const age = typeof v.age_minutes === 'number' ? `${v.age_minutes}m` : '-';
    const views = Number(v.views || 0);
    const videoId = _ytmgrEscJs(v.video_id || '');
    const projectName = _ytmgrEscJs(row?.match?.project_name || '');
    const matchCell = mode === 'match' ? _ytMatchCell(row) : '<span style="color:var(--text-dim)">-</span>';
    const reuploadProjectBtn = row?.match?.project_name
      ? `<button class="btn btn-outline btn-sm" onclick="youtubeReuploadProject('${projectName}', '${videoId}')">Reupload Project</button>`
      : '';
    return `<tr style="border-top:1px solid var(--border)">
      <td style="padding:8px;max-width:420px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${title}"><a href="${v.url}" target="_blank">${title || _ytmgrEsc(v.video_id)}</a></td>
      <td style="padding:8px">${_ytStatusText(v)}</td>
      <td style="padding:8px">${matchCell}</td>
      <td style="padding:8px">${age}</td>
      <td style="padding:8px">${views}</td>
      <td style="padding:8px;display:flex;gap:6px;flex-wrap:wrap">
        <button class="btn btn-outline btn-sm" onclick="youtubeDeleteVideo('${videoId}')">Delete</button>
        <button class="btn btn-outline btn-sm" onclick="youtubeReuploadVideo('${videoId}')">Reupload</button>
        ${reuploadProjectBtn}
      </td>
    </tr>`;
  }).join('');
}

function applyYoutubeStatusFilter() {
  const filter = (document.getElementById('ytmgr-status-filter')?.value || 'all').toLowerCase();
  const mode = ytmgrLastMode || 'plain';
  let rows = [...ytmgrRows];
  if (filter === 'processing') {
    rows = rows.filter(r => _ytStatusKey(r.video || {}) === 'processing');
  } else if (filter === 'failed') {
    rows = rows.filter(r => _ytStatusKey(r.video || {}) === 'failed');
  } else if (filter === 'succeeded') {
    rows = rows.filter(r => _ytStatusKey(r.video || {}) === 'succeeded');
  } else if (filter === 'matched') {
    rows = rows.filter(r => !!r.match);
  } else if (filter === 'unmatched') {
    rows = rows.filter(r => !r.match);
  }
  _renderYoutubeRows(rows, mode);
}

function renderYoutubeVideos(rows, mode = 'plain') {
  const normalizedRows = (rows || []).map(r => (r && r.video) ? r : ({ video: r, match: null, match_source: 'none' }));
  ytmgrRows = normalizedRows;
  ytmgrLastMode = mode;
  applyYoutubeStatusFilter();
}

async function loadYoutubeVideos() {
  const max = parseInt(document.getElementById('ytmgr-max')?.value || '25', 10) || 25;
  const body = document.getElementById('ytmgr-table-body');
  const matchStatus = document.getElementById('ytmgr-match-status');
  if (matchStatus) matchStatus.textContent = '';
  if (body) body.innerHTML = '<tr><td colspan="6" style="padding:10px;color:var(--text-dim)">Loading...</td></tr>';
  try {
    const key = await ensureYtManagerKey();
    const d = await api(`/api/youtube/videos?key=${encodeURIComponent(key)}&max_results=${max}`, {
      timeoutMs: Math.max(120000, Math.min(600000, max * 1000))
    });
    if (!d.ok) {
      if (body) body.innerHTML = `<tr><td colspan="6" style="padding:10px;color:var(--text-dim)">${_ytmgrEsc(d.error || 'Load videos failed')}</td></tr>`;
      return;
    }
    renderYoutubeVideos(d.items || [], 'plain');
    if (matchStatus) matchStatus.textContent = `Loaded ${d.items?.length || 0} video(s).`;
  } catch (e) {
    if (body) body.innerHTML = `<tr><td colspan="6" style="padding:10px;color:var(--text-dim)">Error: ${_ytmgrEsc(e.message)}</td></tr>`;
  }
}

async function scanYoutubeVideoMatch() {
  const max = parseInt(document.getElementById('ytmgr-max')?.value || '25', 10) || 25;
  const body = document.getElementById('ytmgr-table-body');
  const matchStatus = document.getElementById('ytmgr-match-status');
  if (body) body.innerHTML = '<tr><td colspan="6" style="padding:10px;color:var(--text-dim)">Scanning match...</td></tr>';
  if (matchStatus) matchStatus.textContent = 'Đang quét đối chiếu YouTube ↔ local project...';
  try {
    const key = await ensureYtManagerKey();
    const d = await api(`/api/youtube/videos/scan-match?key=${encodeURIComponent(key)}&max_results=${max}`, {
      timeoutMs: Math.max(180000, Math.min(600000, max * 1000))
    });
    if (!d.ok) {
      if (body) body.innerHTML = `<tr><td colspan="6" style="padding:10px;color:var(--text-dim)">${_ytmgrEsc(d.error || 'Scan failed')}</td></tr>`;
      if (matchStatus) matchStatus.textContent = 'Quét đối chiếu thất bại.';
      return;
    }
    const rows = d.rows || [];
    renderYoutubeVideos(rows, 'match');
    if (matchStatus) {
      matchStatus.textContent = `Matched ${d.matched || 0}/${d.total_videos || rows.length} video(s) v?i project local (pages=${d.pages || 1}).`;
    }
    toast(`Scan done: matched ${d.matched || 0}/${d.total_videos || rows.length}`);
  } catch (e) {
    if (body) body.innerHTML = `<tr><td colspan="6" style="padding:10px;color:var(--text-dim)">Error: ${_ytmgrEsc(e.message)}</td></tr>`;
    if (matchStatus) matchStatus.textContent = 'Quét đối chiếu lỗi.';
  }
}

async function sortYoutubePlaylist() {
  const key = (document.getElementById('ytmgr-key')?.value || 'main').trim() || 'main';
  const defaultName = (document.getElementById('cfg-youtube_series_name')?.value || '').trim();
  const playlistInput = prompt('Playlist name (or playlist ID) to sort:', defaultName || '');
  if (playlistInput === null) return;
  const playlistRaw = (playlistInput || '').trim();
  if (!playlistRaw) return toast('Playlist name/ID required', 'error');
  const modeInput = prompt('Sort mode: episode_asc | episode_desc | newest | oldest', 'episode_asc');
  if (modeInput === null) return;
  const mode = (modeInput || 'episode_asc').trim().toLowerCase();
  if (!['episode_asc', 'episode_desc', 'newest', 'oldest'].includes(mode)) {
    return toast('Invalid mode. Use: episode_asc, episode_desc, newest, oldest', 'error');
  }

  const matchStatus = document.getElementById('ytmgr-match-status');
  if (matchStatus) matchStatus.textContent = `Sorting playlist "${playlistRaw}"...`;
  try {
    const body = { key, mode };
    if (/^(PL|UU|LL|FL|RD|OLAK)/i.test(playlistRaw)) body.playlist_id = playlistRaw;
    else body.playlist_name = playlistRaw;

    const d = await api('/api/youtube/playlist/sort', { method: 'POST', body });
    if (!d.ok) {
      if (matchStatus) matchStatus.textContent = `Sort failed: ${d.error || 'Unknown error'}`;
      return toast(d.error || 'Sort playlist failed', 'error');
    }
    const label = d.playlist_name || d.playlist_id || playlistRaw;
    const msg = `Sorted "${label}": moved ${d.moved || 0}/${d.total || 0} items (${d.mode || mode})`;
    if (matchStatus) matchStatus.textContent = msg;
    toast(msg);
  } catch (e) {
    if (matchStatus) matchStatus.textContent = `Sort failed: ${e.message}`;
    toast('Error: ' + e.message, 'error');
  }
}

async function youtubeDeleteVideo(videoId) {
  const key = (document.getElementById('ytmgr-key')?.value || 'main').trim() || 'main';
  if (!confirm(`Delete video ${videoId}?`)) return;
  try {
    const d = await api('/api/youtube/videos/delete', {
      method: 'POST',
      body: { key, video_id: videoId }
    });
    if (d.ok) {
      toast(`Deleted: ${videoId}`);
      loadYoutubeVideos();
    } else {
      toast(d.error || 'Delete failed', 'error');
    }
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

async function youtubeReuploadVideo(videoId) {
  const key = (document.getElementById('ytmgr-key')?.value || 'main').trim() || 'main';
  if (!confirm(`Reupload video ${videoId}? This can delete old video first.`)) return;
  try {
    const d = await api('/api/youtube/videos/reupload', {
      method: 'POST',
      body: { key, video_id: videoId, delete_old: true }
    });
    if (d.ok) {
      toast(`Reuploaded: ${d.upload?.videoId || ''}`);
      loadYoutubeVideos();
    } else {
      toast(d.error || 'Reupload failed', 'error');
    }
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

async function youtubeReuploadProject(projectName, oldVideoId = '') {
  const key = (document.getElementById('ytmgr-key')?.value || 'main').trim() || 'main';
  if (!projectName) return toast('Project name missing', 'error');
  if (!confirm(`Reupload from project "${projectName}"?`)) return;
  try {
    const d = await api('/api/youtube/videos/reupload', {
      method: 'POST',
      body: { key, project_name: projectName, old_video_id: oldVideoId, delete_old: true }
    });
    if (d.ok) {
      toast(`Reuploaded from project: ${projectName}`);
      if (ytmgrLastMode === 'match') {
        await scanYoutubeVideoMatch();
      } else {
        await loadYoutubeVideos();
      }
    } else {
      toast(d.error || 'Reupload project failed', 'error');
    }
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}


async function sortYoutubePlaylistFromManager(dryRun = false) {
  const key = (document.getElementById('ytmgr-key')?.value || 'main').trim() || 'main';
  const playlistName = (document.getElementById('ytmgr-playlist-name')?.value || '').trim();
  const playlistId = (document.getElementById('ytmgr-playlist-id')?.value || '').trim();
  const mode = (document.getElementById('ytmgr-playlist-mode')?.value || 'episode_asc').trim();
  const status = document.getElementById('ytmgr-playlist-sort-status');
  if (!playlistName && !playlistId) {
    toast('Playlist name or Playlist ID is required', 'error');
    return;
  }
  if (status) status.textContent = dryRun ? 'Dry run sorting...' : 'Sorting playlist...';
  try {
    const d = await api('/api/youtube/playlist/sort', {
      method: 'POST',
      timeoutMs: 300000,
      body: {
        key,
        playlist_name: playlistName,
        playlist_id: playlistId,
        mode,
        dry_run: !!dryRun
      }
    });
    if (!d.ok) {
      if (status) status.textContent = d.error || 'Sort failed';
      toast(d.error || 'Sort failed', 'error');
      return;
    }
    const msg = `${dryRun ? 'Dry run' : 'Sorted'} playlist: total=${d.total || 0}, moved=${d.moved || 0}`;
    if (status) status.textContent = msg;
    toast(msg);
  } catch (e) {
    if (status) status.textContent = 'Sort error: ' + e.message;
    toast('Sort playlist error: ' + e.message, 'error');
  }
}

async function runYoutubeWatchdogOnce() {
  try {
    const d = await api('/api/youtube/watchdog/run-once', { method: 'POST', body: {} });
    if (d.ok) {
      toast(`Watchdog done: checked=${d.checked}, actions=${(d.actions || []).length}`);
      await loadYoutubeWatchdogState();
      if (ytmgrLastMode === 'match') await scanYoutubeVideoMatch();
      else await loadYoutubeVideos();
    } else {
      toast(d.error || 'Watchdog failed', 'error');
    }
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

// ── TikTok ──
let tiktokLoginTimer = null;
let tiktokUploadPollTimer = null;

async function loadTikTokStatus() {
  const el = document.getElementById('tiktok-auth-status');
  if (!el) return;
  try {
    const d = await api('/api/tiktok/auth');
    const b = d.browser || d;
    const pw = b.playwright_ok ? 'Playwright OK' : 'Playwright missing';
    const auth = b.ok ? 'Browser session ready' : (b.has_storage ? 'Storage exists (need re-login?)' : 'Browser session not logged');
    const age = (typeof b.storage_age_min === 'number') ? ` | storage age: ${b.storage_age_min}m` : '';
    el.textContent = `Browser Status: ${auth} | ${pw}${age}`;
    await checkTikTokApiStatus();
  } catch (e) {
    el.textContent = `TikTok status error: ${e.message}`;
  }
}

async function loadTikTokQuickConfig() {
  try {
    const d = await api('/api/config');
    const mm = document.getElementById('tk-max-minutes');
    const split = document.getElementById('tk-auto-split');
    const headless = document.getElementById('tk-headless');
    const provider = document.getElementById('tk-provider');
    if (mm && d.tiktok_max_minutes != null) mm.value = String(d.tiktok_max_minutes);
    if (split) split.checked = d.tiktok_auto_split !== false;
    if (headless) headless.checked = !!d.tiktok_headless;
    if (provider) provider.value = d.tiktok_upload_provider || 'official_api';
  } catch (_) {
    // ignore
  }
}

async function saveTikTokTabConfig() {
  const payload = {};
  
  const mm = document.getElementById('tk-max-minutes');
  const split = document.getElementById('tk-auto-split');
  const headless = document.getElementById('tk-headless');
  const provider = document.getElementById('tk-provider');
  
  if (mm) payload.tiktok_max_minutes = parseInt(mm.value || '10', 10);
  if (split) payload.tiktok_auto_split = split.checked;
  if (headless) payload.tiktok_headless = headless.checked;
  if (provider) payload.tiktok_upload_provider = provider.value;
  
  try {
    const d = await api('/api/config', { method: 'POST', body: payload });
    if (d.ok) toast('✅ Đã lưu cấu hình mặc định (Max phút, Auto split, Headless) !');
    else toast(d.error || 'Lỗi khi lưu', 'error');
  } catch (e) {
    toast('Error: ' + e.message, 'error');
  }
}

async function connectTikTokApi() {
  try {
    const d = await api('/api/tiktok/oauth/start');
    if (!d.ok || !d.auth_url) return toast(d.error || 'Cannot start TikTok OAuth', 'error');
    window.open(d.auth_url, '_blank');
    toast('Opened TikTok OAuth page. Complete consent, then click Check TikTok API.');
  } catch (e) {
    toast('OAuth start failed: ' + e.message, 'error');
  }
}

async function checkTikTokApiStatus() {
  const el = document.getElementById('tiktok-api-status');
  if (!el) return;
  try {
    const d = await api('/api/tiktok/api/status');
    if (!d.ok) {
      el.textContent = `TikTok API: ${d.error || 'error'}`;
      return;
    }
    if (!d.configured) {
      el.textContent = 'TikTok API: chưa cấu hình client key/secret/redirect.';
      return;
    }
    if (!d.has_token) {
      el.textContent = 'TikTok API: chưa connect OAuth token.';
      return;
    }
    const exp = (typeof d.access_expires_in_sec === 'number') ? `${Math.max(0, d.access_expires_in_sec)}s` : 'n/a';
    const cr = d.creator || {};
    const who = cr.nickname || cr.username || d.open_id || '?';
    el.textContent = `TikTok API: connected (${who}) | access exp: ${exp} | privacy options: ${(cr.privacy_level_options || []).join(', ') || 'n/a'}`;
  } catch (e) {
    el.textContent = `TikTok API status error: ${e.message}`;
  }
}

async function disconnectTikTokApi() {
  if (!confirm('Disconnect TikTok API token?')) return;
  try {
    const d = await api('/api/tiktok/api/disconnect', { method: 'POST', body: {} });
    if (!d.ok) return toast(d.error || 'Disconnect failed', 'error');
    await checkTikTokApiStatus();
    toast('TikTok API disconnected');
  } catch (e) {
    toast('Disconnect failed: ' + e.message, 'error');
  }
}

async function tiktokLogin() {
  const out = document.getElementById('tiktok-upload-result');
  if (out) out.innerHTML = '<div class="log-line log-info"><span class="log-msg">Starting TikTok login...</span></div>';
  try {
    const d = await api('/api/tiktok/login', { method: 'POST', body: {} });
    if (!d.ok) return toast(d.error || 'TikTok login start failed', 'error');
    const loginId = d.login_id;
    toast('TikTok browser opened. Complete login + CAPTCHA.');
    if (tiktokLoginTimer) clearInterval(tiktokLoginTimer);
    tiktokLoginTimer = setInterval(() => pollTikTokLogin(loginId), 3000);
  } catch (e) {
    toast('Error: ' + e.message, 'error');
  }
}

async function importTikTokFromBrowser() {
  const browser = (document.getElementById('tk-import-browser')?.value || 'edge').trim();
  const profile = (document.getElementById('tk-import-profile')?.value || '').trim();
  const out = document.getElementById('tiktok-upload-result');
  if (out) out.innerHTML = '<div class="log-line log-info"><span class="log-msg">Importing session from browser...</span></div>';
  try {
    const d = await api('/api/tiktok/import-browser', {
      method: 'POST',
      body: { browser, profile }
    });
    if (!d.ok) {
      if (out) out.innerHTML = `<div class="log-line log-error"><span class="log-msg">${String(d.error || 'Import failed').replace(/</g,'&lt;').replace(/>/g,'&gt;')}</span></div>`;
      return toast(d.error || 'Import browser session failed', 'error');
    }
    if (out) out.innerHTML = `<div class="log-line log-success"><span class="log-msg">✅ Imported ${d.cookie_count || 0} TikTok cookies from ${d.browser || browser}.</span></div>`;
    await loadTikTokStatus();
    toast(`Imported browser session (${d.cookie_count || 0} cookies)`);
  } catch (e) {
    if (out) out.innerHTML = `<div class="log-line log-error"><span class="log-msg">${String(e.message || e).replace(/</g,'&lt;').replace(/>/g,'&gt;')}</span></div>`;
    toast('Import failed: ' + e.message, 'error');
  }
}

async function importTikTokCookiesTextFile(input) {
  const out = document.getElementById('tiktok-upload-result');
  const file = input?.files?.[0];
  if (!file) return;
  try {
    if (out) out.innerHTML = '<div class="log-line log-info"><span class="log-msg">Reading cookies.txt...</span></div>';
    const text = await file.text();
    const d = await api('/api/tiktok/import-cookies-text', {
      method: 'POST',
      body: { cookies_text: text }
    });
    if (!d.ok) {
      if (out) out.innerHTML = `<div class="log-line log-error"><span class="log-msg">${String(d.error || 'Import cookies.txt failed').replace(/</g,'&lt;').replace(/>/g,'&gt;')}</span></div>`;
      return toast(d.error || 'Import cookies.txt failed', 'error');
    }
    if (out) out.innerHTML = `<div class="log-line log-success"><span class="log-msg">✅ Imported ${d.cookie_count || 0} TikTok cookies from cookies.txt.</span></div>`;
    await loadTikTokStatus();
    toast(`Imported cookies.txt (${d.cookie_count || 0} cookies)`);
  } catch (e) {
    if (out) out.innerHTML = `<div class="log-line log-error"><span class="log-msg">${String(e.message || e).replace(/</g,'&lt;').replace(/>/g,'&gt;')}</span></div>`;
    toast('Import cookies.txt failed: ' + e.message, 'error');
  } finally {
    if (input) input.value = '';
  }
}

async function pollTikTokLogin(loginId) {
  const out = document.getElementById('tiktok-upload-result');
  try {
    const d = await api(`/api/tiktok/login/${encodeURIComponent(loginId)}`);
    const logs = d.logs || [];
    if (out) {
      out.innerHTML = logs.map(l => `<div class="log-line log-info"><span class="log-msg">${String(l).replace(/</g, '&lt;').replace(/>/g, '&gt;')}</span></div>`).join('');
      out.scrollTop = out.scrollHeight;
    }
    if (d.status === 'done' || d.status === 'timeout' || d.status === 'error') {
      clearInterval(tiktokLoginTimer);
      tiktokLoginTimer = null;
      await loadTikTokStatus();
      if (d.status === 'done') toast('TikTok login saved.');
      else toast(`TikTok login ${d.status}`, 'error');
    }
  } catch (e) {
    clearInterval(tiktokLoginTimer);
    tiktokLoginTimer = null;
    toast('Login poll error: ' + e.message, 'error');
  }
}

function _projName(p) {
  return p.project_name || (p.project_path ? p.project_path.split(/[\\/]/).pop() : '');
}

async function loadTikTokProjects() {
  const sel = document.getElementById('tk-project');
  if (!sel) return;
  sel.innerHTML = '<option>Loading...</option>';
  try {
    const d = await api('/api/projects');
    const rows = (d.projects || []).filter(p => p.final_video || (p.steps_completed || []).includes('render'));
    if (!rows.length) {
      sel.innerHTML = '<option value="">No rendered project</option>';
      return;
    }
    sel.innerHTML = rows.map(p => {
      const pn = _projName(p);
      const title = p.metadata?.title || pn;
      return `<option value="${pn}">${pn} | ${String(title).replace(/</g,'&lt;').replace(/>/g,'&gt;')}</option>`;
    }).join('');
  } catch (e) {
    sel.innerHTML = `<option value="">Error: ${e.message}</option>`;
  }
}

function _tkPayload(dryRun) {
  const capInput = document.getElementById('cfg-tiktok_caption_max_chars');
  let capMax = parseInt(capInput?.value || '255', 10) || 255;
  capMax = Math.max(60, Math.min(255, capMax));
  return {
    project_name: (document.getElementById('tk-project')?.value || '').trim(),
    provider: (document.getElementById('tk-provider')?.value || 'official_api').trim(),
    max_minutes: parseInt(document.getElementById('tk-max-minutes')?.value || '10', 10) || 10,
    auto_split: !!document.getElementById('tk-auto-split')?.checked,
    headless: !!document.getElementById('tk-headless')?.checked,
    caption_max_chars: capMax,
    dry_run: !!dryRun
  };
}

function _setTikTokProgress(pct = 0, msg = 'Waiting...') {
  const wrap = document.getElementById('tiktok-progress-wrap');
  const fill = document.getElementById('tiktok-progress-fill');
  const pctEl = document.getElementById('tiktok-progress-pct');
  const msgEl = document.getElementById('tiktok-progress-msg');
  if (!wrap || !fill || !pctEl || !msgEl) return;
  wrap.style.display = 'block';
  const v = Math.max(0, Math.min(100, parseInt(pct || 0, 10) || 0));
  fill.style.width = `${v}%`;
  pctEl.textContent = `${v}%`;
  msgEl.textContent = msg || 'Uploading...';
}

function _hideTikTokProgress() {
  const wrap = document.getElementById('tiktok-progress-wrap');
  if (wrap) wrap.style.display = 'none';
}

function _renderTikTokResult(d, title = 'TikTok Result') {
  const out = document.getElementById('tiktok-upload-result');
  if (!out) return;
  const safe = (s) => String(s ?? '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  let html = `<div class="log-line log-info"><span class="log-msg"><strong>${safe(title)}</strong></span></div>`;
  if (d.error) {
    html += `<div class="log-line log-error"><span class="log-msg">${safe(d.error)}</span></div>`;
    out.innerHTML = html;
    return;
  }
  if (Array.isArray(d.parts)) {
    html += d.parts.map(p => `<div class="log-line log-info"><span class="log-msg">Part ${p.part_index}/${p.total_parts} • ${Math.round(Number(p.duration_sec || 0))}s • ${safe(p.path)}<br><span style="opacity:.8">${safe(p.caption_preview || '')}</span></span></div>`).join('');
  }
  if (Array.isArray(d.results)) {
    html += d.results.map(r => `<div class="log-line ${r.ok ? 'log-success' : 'log-error'}"><span class="log-msg">${r.ok ? '✅' : '❌'} Part ${safe(r.part)}${r.status ? ' • '+safe(r.status) : ''}${r.publish_id ? ' • '+safe(r.publish_id) : ''}${r.error ? ' • '+safe(r.error) : ''}</span></div>`).join('');
  }
  out.innerHTML = html;
  out.scrollTop = out.scrollHeight;
}

async function tiktokDryRun() {
  const payload = _tkPayload(true);
  if (!payload.project_name) return toast('Chọn project đã render', 'error');
  try {
    const d = await api('/api/tiktok/upload', { method: 'POST', body: payload });
    if (!d.ok) return toast(d.error || 'Dry run failed', 'error');
    _renderTikTokResult(d, `Preview: ${d.part_count || 0} part(s)`);
    toast('Dry run done');
  } catch (e) {
    toast('Error: ' + e.message, 'error');
  }
}

async function tiktokUploadNow() {
  const payload = _tkPayload(false);
  if (!payload.project_name) return toast('Chọn project đã render', 'error');
  if (!confirm(`Upload TikTok project "${payload.project_name}"?`)) return;
  try {
    _setTikTokProgress(0, 'Queued...');
    const start = await api('/api/tiktok/upload/start', { method: 'POST', body: payload });
    if (!start.ok || !start.job_id) {
      _hideTikTokProgress();
      _renderTikTokResult(start, 'TikTok Upload Error');
      return toast(start.error || 'TikTok upload start failed', 'error');
    }

    const out = document.getElementById('tiktok-upload-result');
    if (out) out.innerHTML = '<div class="log-line log-info"><span class="log-msg">TikTok upload started...</span></div>';

    if (tiktokUploadPollTimer) clearInterval(tiktokUploadPollTimer);
    tiktokUploadPollTimer = setInterval(async () => {
      try {
        const st = await api(`/api/tiktok/upload/${encodeURIComponent(start.job_id)}`);
        const prog = st.progress || {};
        _setTikTokProgress(prog.pct || 0, prog.message || st.status || 'Uploading...');

        if (out && Array.isArray(st.logs)) {
          out.innerHTML = st.logs.map(l => `<div class="log-line log-info"><span class="log-msg">${String(l).replace(/</g,'&lt;').replace(/>/g,'&gt;')}</span></div>`).join('');
          out.scrollTop = out.scrollHeight;
        }

        if (st.status === 'done') {
          clearInterval(tiktokUploadPollTimer);
          tiktokUploadPollTimer = null;
          _setTikTokProgress(100, 'Done');
          const res = st.result || {};
          _renderTikTokResult(res, `Upload done: ${res.ok_count || 0}/${res.part_count || 0}`);
          toast(`TikTok upload: ${res.ok_count || 0}/${res.part_count || 0}`);
        } else if (st.status === 'error') {
          clearInterval(tiktokUploadPollTimer);
          tiktokUploadPollTimer = null;
          _setTikTokProgress(100, 'Failed');
          const errObj = { ok: false, error: st.error || 'TikTok upload failed' };
          _renderTikTokResult(errObj, 'TikTok Upload Error');
          toast(st.error || 'TikTok upload failed', 'error');
        }
      } catch (pollErr) {
        clearInterval(tiktokUploadPollTimer);
        tiktokUploadPollTimer = null;
        _hideTikTokProgress();
        toast('Upload poll failed: ' + pollErr.message, 'error');
      }
    }, 2000);
  } catch (e) {
    _hideTikTokProgress();
    toast('Error: ' + e.message, 'error');
  }
}

// ── Upload ──
// ── Facebook Reels ──
let fbUploadPollTimer = null;
let fbFetchedPages = [];

async function loadFacebookReelsStatus() {
  const el = document.getElementById('facebook-reels-status');
  if (!el) return;
  try {
    const d = await api('/api/facebook/reels/status?check=1');
    if (!d.ok) {
      el.textContent = `Facebook Reels status error: ${d.error || 'unknown error'}`;
      return;
    }
    if (!d.configured) {
      el.textContent = 'Facebook Reels: missing facebook_page_access_token in Settings.';
      return;
    }
    if (d.check?.ok) {
      const who = d.check?.name || d.check?.id || d.actor_id || 'me';
      el.textContent = `Facebook Reels: connected (${who}) | actor=${d.actor_id} | graph=${d.graph_version}`;
    } else {
      el.textContent = `Facebook Reels: configured, but check failed (${d.check?.error || 'unknown'})`;
    }
  } catch (e) {
    el.textContent = `Facebook Reels status error: ${e.message}`;
  }
}

async function loadFacebookQuickConfig() {
  try {
    const d = await api('/api/config');
    const mm = document.getElementById('fb-max-minutes');
    const split = document.getElementById('fb-auto-split');
    const state = document.getElementById('fb-video-state');
    const appId = document.getElementById('fb-app-id');
    const appSecret = document.getElementById('fb-app-secret');
    const pageSel = document.getElementById('fb-pages-select');
    const fetchStatus = document.getElementById('fb-token-fetch-status');
    const savedPageId = String(d.facebook_reels_actor_id || '').trim();
    const savedPageName = String(d.facebook_selected_page_name || '').trim();
    if (mm) mm.value = String(d.facebook_reels_max_minutes ?? d.tiktok_max_minutes ?? 10);
    if (split) split.checked = d.facebook_reels_auto_split !== false;
    if (state) state.value = d.facebook_reels_video_state || 'PUBLISHED';
    if (appId) appId.value = d.facebook_app_id || '';
    if (appSecret) appSecret.value = d.facebook_app_secret || '';
    if (pageSel && savedPageId && !fbFetchedPages.length) {
      const label = `${savedPageName || 'Saved page'} (${savedPageId})`;
      pageSel.innerHTML = `<option value="-1" selected>${label.replace(/</g, '&lt;').replace(/>/g, '&gt;')}</option>`;
    }
    if (fetchStatus && savedPageId) {
      fetchStatus.textContent = `Saved page: ${savedPageName || savedPageId}`;
    }
  } catch (_) {
    // ignore
  }
}

async function saveFacebookTabConfig() {
  const payload = {};
  const mm = document.getElementById('fb-max-minutes');
  const split = document.getElementById('fb-auto-split');
  const state = document.getElementById('fb-video-state');
  const appId = document.getElementById('fb-app-id');
  const appSecret = document.getElementById('fb-app-secret');
  if (mm) payload.facebook_reels_max_minutes = parseInt(mm.value || '10', 10);
  if (split) payload.facebook_reels_auto_split = split.checked;
  if (state) payload.facebook_reels_video_state = state.value || 'PUBLISHED';
  if (appId) payload.facebook_app_id = appId.value || '';
  if (appSecret) payload.facebook_app_secret = appSecret.value || '';
  try {
    const d = await api('/api/config', { method: 'POST', body: payload });
    if (d.ok) toast('Saved Facebook Reels defaults.');
    else toast(d.error || 'Save failed', 'error');
  } catch (e) {
    toast('Error: ' + e.message, 'error');
  }
}

async function loadFacebookReelsProjects() {
  const sel = document.getElementById('fb-project');
  if (!sel) return;
  sel.innerHTML = '<option>Loading...</option>';
  try {
    const d = await api('/api/projects');
    const rows = (d.projects || []).filter(p => p.final_video || (p.steps_completed || []).includes('render'));
    if (!rows.length) {
      sel.innerHTML = '<option value="">No rendered project</option>';
      return;
    }
    sel.innerHTML = rows.map(p => {
      const pn = _projName(p);
      const title = p.metadata?.title || pn;
      return `<option value="${pn}">${pn} | ${String(title).replace(/</g,'&lt;').replace(/>/g,'&gt;')}</option>`;
    }).join('');
  } catch (e) {
    sel.innerHTML = `<option value="">Error: ${e.message}</option>`;
  }
}

async function fetchFacebookPagesWithToken() {
  const userToken = (document.getElementById('fb-user-token')?.value || '').trim();
  const appId = (document.getElementById('fb-app-id')?.value || '').trim();
  const appSecret = (document.getElementById('fb-app-secret')?.value || '').trim();
  const out = document.getElementById('fb-token-fetch-status');
  const sel = document.getElementById('fb-pages-select');
  if (!userToken) return toast('Paste user access token first', 'error');
  if (out) out.textContent = 'Fetching pages/token...';
  if (sel) sel.innerHTML = '<option>Loading...</option>';
  try {
    const d = await api('/api/facebook/reels/fetch-pages-with-token', {
      method: 'POST',
      body: { user_token: userToken, app_id: appId, app_secret: appSecret }
    });
    if (!d.ok) {
      if (out) out.textContent = `Error: ${d.error || 'unknown'}`;
      if (sel) sel.innerHTML = '<option value="">No page</option>';
      return toast(d.error || 'Fetch pages failed', 'error');
    }
    fbFetchedPages = Array.isArray(d.pages) ? d.pages : [];
    if (d.long_lived_token && document.getElementById('fb-user-token')) {
      document.getElementById('fb-user-token').value = d.long_lived_token;
    }
    if (!fbFetchedPages.length) {
      if (out) out.textContent = 'No managed pages found in this token.';
      if (sel) sel.innerHTML = '<option value="">No page</option>';
      return toast('No managed pages found', 'error');
    }
    if (sel) {
      sel.innerHTML = fbFetchedPages.map((p, i) => `<option value="${i}">${String(p.name || 'Page')} (${String(p.id || '-')})</option>`).join('');
      try {
        const cfg = await api('/api/config');
        const savedPageId = String(cfg.facebook_reels_actor_id || '').trim();
        if (savedPageId) {
          const idx = fbFetchedPages.findIndex(p => String(p?.id || '') === savedPageId);
          if (idx >= 0) sel.value = String(idx);
        }
      } catch (_) {
        // ignore
      }
    }
    if (out) {
      out.textContent = `OK: ${fbFetchedPages.length} page(s) | graph=${d.graph_version}${d.long_lived_token ? ' | long-lived token ready' : ''}`;
    }
    if (d.long_lived_token) toast('Converted to long-lived user token.');
    toast(`Fetched ${fbFetchedPages.length} page(s).`);
  } catch (e) {
    if (out) out.textContent = `Error: ${e.message}`;
    if (sel) sel.innerHTML = '<option value="">No page</option>';
    toast('Fetch pages failed: ' + e.message, 'error');
  }
}

async function applySelectedFacebookPageToken() {
  const sel = document.getElementById('fb-pages-select');
  if (!sel || !fbFetchedPages.length) return toast('No fetched page to apply', 'error');
  const idx = parseInt(sel.value || '0', 10);
  const p = fbFetchedPages[idx];
  if (!p) return toast('Invalid page selected', 'error');

  const pageToken = p.access_token || '';
  const pageId = p.id || '';
  if (!pageToken || !pageId) return toast('Selected page has no token/id', 'error');

  const cfgToken = document.getElementById('cfg-facebook_page_access_token');
  const cfgActor = document.getElementById('cfg-facebook_reels_actor_id');
  if (cfgToken) cfgToken.value = pageToken;
  if (cfgActor) cfgActor.value = pageId;

  try {
    const payload = {
      facebook_page_access_token: pageToken,
      facebook_reels_actor_id: pageId,
      facebook_selected_page_id: pageId,
      facebook_selected_page_name: (p.name || '')
    };
    const appId = document.getElementById('fb-app-id');
    const appSecret = document.getElementById('fb-app-secret');
    if (appId) payload.facebook_app_id = appId.value || '';
    if (appSecret) payload.facebook_app_secret = appSecret.value || '';
    const d = await api('/api/config', { method: 'POST', body: payload });
    if (!d.ok) return toast(d.error || 'Cannot save selected page token', 'error');
    toast(`Applied page token: ${p.name || pageId}`);
    await loadFacebookReelsStatus();
  } catch (e) {
    toast('Apply token failed: ' + e.message, 'error');
  }
}

function _fbPayload(dryRun) {
  const capInput = document.getElementById('cfg-tiktok_caption_max_chars');
  let capMax = parseInt(capInput?.value || '255', 10) || 255;
  capMax = Math.max(60, Math.min(255, capMax));
  return {
    project_name: (document.getElementById('fb-project')?.value || '').trim(),
    max_minutes: parseInt(document.getElementById('fb-max-minutes')?.value || '10', 10) || 10,
    auto_split: !!document.getElementById('fb-auto-split')?.checked,
    video_state: (document.getElementById('fb-video-state')?.value || 'PUBLISHED').trim(),
    caption_max_chars: capMax,
    dry_run: !!dryRun,
  };
}

function _setFbProgress(pct = 0, msg = 'Waiting...') {
  const wrap = document.getElementById('fb-progress-wrap');
  const fill = document.getElementById('fb-progress-fill');
  const pctEl = document.getElementById('fb-progress-pct');
  const msgEl = document.getElementById('fb-progress-msg');
  if (!wrap || !fill || !pctEl || !msgEl) return;
  wrap.style.display = 'block';
  const v = Math.max(0, Math.min(100, parseInt(pct || 0, 10) || 0));
  fill.style.width = `${v}%`;
  pctEl.textContent = `${v}%`;
  msgEl.textContent = msg || 'Uploading...';
}

function _hideFbProgress() {
  const wrap = document.getElementById('fb-progress-wrap');
  if (wrap) wrap.style.display = 'none';
}

function _renderFbResult(d, title = 'Facebook Reels Result') {
  const out = document.getElementById('fb-upload-result');
  if (!out) return;
  const safe = (s) => String(s ?? '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  let html = `<div class="log-line log-info"><span class="log-msg"><strong>${safe(title)}</strong></span></div>`;
  if (d.error) {
    html += `<div class="log-line log-error"><span class="log-msg">${safe(d.error)}</span></div>`;
    out.innerHTML = html;
    return;
  }
  if (Array.isArray(d.parts)) {
    html += d.parts.map(p => `<div class="log-line log-info"><span class="log-msg">Part ${p.part_index}/${p.total_parts} • ${Math.round(Number(p.duration_sec || 0))}s • ${safe(p.path)}<br><span style="opacity:.8">${safe(p.caption_preview || '')}</span></span></div>`).join('');
  }
  if (Array.isArray(d.results)) {
    html += d.results.map(r => `<div class="log-line ${r.ok ? 'log-success' : 'log-error'}"><span class="log-msg">${r.ok ? '✅' : '❌'} Part ${safe(r.part)}${r.video_id ? ' • '+safe(r.video_id) : ''}${r.status ? ' • '+safe(r.status) : ''}${r.error ? ' • '+safe(r.error) : ''}</span></div>`).join('');
  }
  out.innerHTML = html;
  out.scrollTop = out.scrollHeight;
}

async function facebookReelsDryRun() {
  const payload = _fbPayload(true);
  if (!payload.project_name) return toast('Choose rendered project', 'error');
  try {
    const d = await api('/api/facebook/reels/upload', { method: 'POST', body: payload });
    if (!d.ok) return toast(d.error || 'Dry run failed', 'error');
    _renderFbResult(d, `Preview: ${d.part_count || 0} part(s)`);
    toast('Dry run done');
  } catch (e) {
    toast('Error: ' + e.message, 'error');
  }
}

async function facebookReelsUploadNow() {
  const payload = _fbPayload(false);
  if (!payload.project_name) return toast('Choose rendered project', 'error');
  if (!confirm(`Upload Facebook Reels project "${payload.project_name}"?`)) return;
  try {
    _setFbProgress(0, 'Queued...');
    const start = await api('/api/facebook/reels/upload/start', { method: 'POST', body: payload });
    if (!start.ok || !start.job_id) {
      _hideFbProgress();
      _renderFbResult(start, 'Facebook Reels Upload Error');
      return toast(start.error || 'Facebook upload start failed', 'error');
    }

    const out = document.getElementById('fb-upload-result');
    if (out) out.innerHTML = '<div class="log-line log-info"><span class="log-msg">Facebook upload started...</span></div>';

    if (fbUploadPollTimer) clearInterval(fbUploadPollTimer);
    fbUploadPollTimer = setInterval(async () => {
      try {
        const st = await api(`/api/facebook/reels/upload/${encodeURIComponent(start.job_id)}`);
        const prog = st.progress || {};
        _setFbProgress(prog.pct || 0, prog.message || st.status || 'Uploading...');

        if (out && Array.isArray(st.logs)) {
          out.innerHTML = st.logs.map(l => `<div class="log-line log-info"><span class="log-msg">${String(l).replace(/</g,'&lt;').replace(/>/g,'&gt;')}</span></div>`).join('');
          out.scrollTop = out.scrollHeight;
        }

        if (st.status === 'done') {
          clearInterval(fbUploadPollTimer);
          fbUploadPollTimer = null;
          _setFbProgress(100, 'Done');
          const res = st.result || {};
          _renderFbResult(res, `Upload done: ${res.ok_count || 0}/${res.part_count || 0}`);
          toast(`Facebook upload: ${res.ok_count || 0}/${res.part_count || 0}`);
        } else if (st.status === 'error') {
          clearInterval(fbUploadPollTimer);
          fbUploadPollTimer = null;
          _setFbProgress(100, 'Failed');
          const errObj = { ok: false, error: st.error || 'Facebook upload failed' };
          _renderFbResult(errObj, 'Facebook Reels Upload Error');
          toast(st.error || 'Facebook upload failed', 'error');
        }
      } catch (pollErr) {
        clearInterval(fbUploadPollTimer);
        fbUploadPollTimer = null;
        _hideFbProgress();
        toast('Upload poll failed: ' + pollErr.message, 'error');
      }
    }, 2000);
  } catch (e) {
    _hideFbProgress();
    toast('Error: ' + e.message, 'error');
  }
}

async function uploadIntro() {
  const inp = document.getElementById('intro-file');
  if (!inp.files.length) return toast('Select file', 'error');
  const fd = new FormData();
  fd.append('file', inp.files[0]);
  const r = await fetch('/api/intro/upload', { method: 'POST', body: fd });
  const d = await r.json();
  if (d.ok) toast('Intro uploaded!');
  else toast(d.error, 'error');
}

async function uploadFont() {
  const inp = document.getElementById('font-file');
  if (!inp.files.length) return toast('Select font', 'error');
  const fd = new FormData();
  fd.append('file', inp.files[0]);
  const r = await fetch('/api/fonts/upload', { method: 'POST', body: fd });
  const d = await r.json();
  if (d.ok) toast('Font uploaded: ' + d.name);
  else toast(d.error, 'error');
}


// YouTube Queue
let ytQueuePollTimer = null;
let ytQueueDragProjectDir = null;

function _ytQueueProjectName(projectDir) {
  return String(projectDir || '').split(/\\|\//).pop() || 'Unknown';
}

async function loadYTQueue() {
  const tbody = document.getElementById('ytqueue-tbody');
  const statusEl = document.getElementById('ytqueue-status');
  if (!tbody) return;

  try {
    const d = await api('/api/youtube/queue');
    if (statusEl) {
      const lockedText = d.items?.some(x => String(x.status || '').toLowerCase() === 'uploading')
        ? ' | uploading item locked'
        : '';
      statusEl.innerHTML = `
        Total items: ${d.count || 0} | Quota block: ${d.quota_block_seconds > 0 ? (d.quota_block_seconds/60).toFixed(1) + ' min' : 'None'} | Worker: ${d.worker?.running ? 'Running' : 'Stopped'}${lockedText}
        <button class="btn btn-outline btn-sm" style="margin-left:10px;" onclick="sortYTQueue('episode_asc')">Sort episodes</button>
        <button class="btn btn-outline btn-sm" onclick="sortYTQueue('created_asc')">Sort oldest</button>
        <button class="btn btn-outline btn-sm" onclick="sortYTQueue('created_desc')">Sort newest</button>
      `;
    }

    if (!d.items || d.items.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" style="padding:10px; text-align:center; color:var(--text-dim);">No videos in upload queue</td></tr>';
      return;
    }

    tbody.innerHTML = d.items.map((item, idx) => {
      const titleMeta = item.title || item.metadata?.title || 'Unknown Title';
      const projectName = _ytQueueProjectName(item.project_dir);
      const channel = item.channel_key || 'Default';
      const status = item.status || 'pending';
      const attempts = item.attempts || 0;
      const error = item.last_error || '';
      const encodedProject = encodeURIComponent(item.project_dir || '');
      const isUploading = String(status).toLowerCase() === 'uploading';

      let statusHtml = safeStr(status);
      if (isUploading) statusHtml = '<span class="badge badge-info">Uploading</span>';
      else if (status === 'pending') statusHtml = '<span class="badge badge-default">Pending</span>';
      else if (status === 'failed') statusHtml = '<span class="badge badge-error">Failed</span>';

      const dragAttrs = isUploading
        ? ''
        : `draggable="true" ondragstart="ytQueueDragStart(event, '${encodedProject}')" ondragend="ytQueueDragEnd(event)"`;
      const rowStyle = isUploading ? 'opacity:.92;' : 'cursor:grab;';

      return `
        <tr ${dragAttrs} ondragover="ytQueueDragOver(event)" ondrop="ytQueueDrop(event, ${idx})" style="border-bottom:1px solid var(--border);${rowStyle}" data-project-dir="${safeStr(item.project_dir || '')}">
          <td style="padding:10px;">
            <div style="font-weight:600; margin-bottom:4px; max-width:350px; white-space:normal; line-height:1.4;">
              <span title="Drag to reorder" style="color:var(--text-dim);margin-right:6px;">::</span>${safeStr(titleMeta)}
            </div>
            <div style="font-size:0.85rem; color:var(--text-dim);">#${idx + 1} ${safeStr(projectName)}</div>
          </td>
          <td style="padding:10px;"><code>${safeStr(channel)}</code></td>
          <td style="padding:10px;">${statusHtml}</td>
          <td style="padding:10px; max-width:300px; word-break:break-word; font-size:0.85rem;" title="${safeStr(error)}">${safeStr(error)}</td>
          <td style="padding:10px;">${attempts}</td>
          <td style="padding:10px;display:flex;gap:6px;flex-wrap:wrap;align-items:center;">
            <button class="btn btn-outline btn-sm" ${idx <= 0 || isUploading ? 'disabled' : ''} onclick="moveYTItem('${encodedProject}', ${idx - 1})">Up</button>
            <button class="btn btn-outline btn-sm" ${idx >= d.items.length - 1 || isUploading ? 'disabled' : ''} onclick="moveYTItem('${encodedProject}', ${idx + 2})">Down</button>
            <input type="number" min="1" max="${d.items.length}" value="${idx + 1}" title="Move to position" style="width:58px;padding:5px" ${isUploading ? 'disabled' : ''} onchange="moveYTItem('${encodedProject}', (parseInt(this.value,10)||1)-1)">
            <button class="btn btn-outline btn-sm" onclick="reuploadYTItem('${encodedProject}')">Re-upload</button>
            <button class="btn btn-error btn-sm" onclick="cancelYTItem('${encodedProject}')">Cancel</button>
          </td>
        </tr>
      `;
    }).join('');

  } catch (e) {
    if (tbody) tbody.innerHTML = `<tr><td colspan="6" style="padding:10px; text-align:center; color:red;">Load queue error: ${safeStr(e.message)}</td></tr>`;
  }
}

async function sortYTQueue(mode = 'episode_asc') {
  try {
    const d = await api('/api/youtube/queue/sort', {
      method: 'POST',
      body: { mode }
    });
    if (d.error) {
      toast(d.error, 'error');
    } else {
      toast(`Sorted YouTube queue: ${d.count || 0} items${d.locked ? ` (${d.locked} locked)` : ''}`);
      loadYTQueue();
    }
  } catch (e) {
    toast('Sort queue error: ' + e.message, 'error');
  }
}

async function moveYTItem(projDirEncoded, toIndex) {
  const projDir = decodeURIComponent(projDirEncoded);
  try {
    const d = await api('/api/youtube/queue/reorder', {
      method: 'POST',
      body: { project_dir: projDir, to_index: toIndex }
    });
    if (d.error) {
      toast(d.error, 'error');
    } else {
      toast(d.changed ? 'Queue order updated' : 'Queue order unchanged');
      loadYTQueue();
    }
  } catch (e) {
    toast('Reorder queue error: ' + e.message, 'error');
  }
}

function ytQueueDragStart(ev, projDirEncoded) {
  ytQueueDragProjectDir = projDirEncoded;
  ev.dataTransfer.effectAllowed = 'move';
  ev.dataTransfer.setData('text/plain', projDirEncoded);
  ev.currentTarget.style.opacity = '.55';
}

function ytQueueDragOver(ev) {
  ev.preventDefault();
  ev.dataTransfer.dropEffect = 'move';
}

function ytQueueDrop(ev, toIndex) {
  ev.preventDefault();
  const proj = ev.dataTransfer.getData('text/plain') || ytQueueDragProjectDir;
  if (!proj) return;
  moveYTItem(proj, toIndex);
}

function ytQueueDragEnd(ev) {
  ytQueueDragProjectDir = null;
  if (ev.currentTarget) ev.currentTarget.style.opacity = '';
}


async function cancelYTItem(projDirEncoded) {
  if (!confirm('Are you sure you want to cancel this upload?')) return;
  const projDir = decodeURIComponent(projDirEncoded);
  try {
    const d = await api('/api/youtube/queue/cancel', {
      method: 'POST',
      body: { project_dir: projDir }
    });
    if (d.error) {
      toast(d.error, 'error');
    } else {
      toast('Đã hủy tải lên thành công!');
      loadYTQueue();
    }
  } catch (e) {
    toast('Error: ' + e.message, 'error');
  }
}

async function reuploadYTItem(projDirEncoded) {
  const projDir = decodeURIComponent(projDirEncoded);
  try {
    const d = await api('/api/youtube/queue/reupload', {
      method: 'POST',
      body: { project_dir: projDir }
    });
    if (d.error) {
      toast(d.error, 'error');
    } else {
      toast('Đã đặt lại trạng thái re-upload thành công!');
      loadYTQueue();
    }
  } catch (e) {
    toast('Error: ' + e.message, 'error');
  }
}


// ── Log Formatting ──
function formatLogLine(raw) {
  const line = document.createElement('div');
  line.className = 'log-line';

  // Extract timestamp [HH:MM:SS]
  const tsMatch = raw.match(/^\[(\d{2}:\d{2}:\d{2})\]\s*/);
  let rest = raw;
  if (tsMatch) {
    const ts = document.createElement('span');
    ts.className = 'log-ts';
    ts.textContent = tsMatch[1];
    line.appendChild(ts);
    rest = raw.slice(tsMatch[0].length);
  }

  // Detect log type from emoji/keyword patterns
  let type = 'default';
  if (/^(📥|🎬|📝|🌐|🎤|🔧|💾|📤|🔗)\s*Step\s+\d/i.test(rest) || /^⏭️/.test(rest)) {
    type = 'step';
  } else if (/^✅/.test(rest) || /done|complete|success|saved/i.test(rest)) {
    type = 'success';
  } else if (/^❌|ERROR|PIPELINE ERROR|RESUME ERROR/i.test(rest)) {
    type = 'error';
  } else if (/^⚠️|WARN/i.test(rest)) {
    type = 'warning';
  } else if (/^(🔄|⏳|🔑|🏠|📊|🎧|🤖|🎵|⏱|🔀)/.test(rest)) {
    type = 'info';
  } else if (/^\s{2,}/.test(rest)) {
    type = 'detail';  // indented sub-info
  }

  line.classList.add('log-' + type);

  // Type indicator dot
  const dot = document.createElement('span');
  dot.className = 'log-dot';
  line.appendChild(dot);

  // Message
  const msg = document.createElement('span');
  msg.className = 'log-msg';
  msg.textContent = rest;
  line.appendChild(msg);

  return line;
}

// ── Scraper ──
let scrapeVideos = [];
let scrapeSeriesGroups = [];
let scrapeCompletedUrls = new Set();

function scrapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

async function startScrape() {
  const url = document.getElementById('scrape-url').value.trim();
  const minDurationEl = document.getElementById('scrape-min-duration');
  const sortOrderEl = document.getElementById('scrape-sort-order');
  const minDuration = parseFloat(minDurationEl?.value || '60') || 0;
  const oldestFirst = (sortOrderEl?.value || 'oldest') !== 'newest';
  if (!url) return toast('Paste user profile URL', 'error');
  const btn = document.getElementById('btn-scrape');
  btn.disabled = true;
  document.getElementById('scrape-progress').classList.remove('hidden');
  document.getElementById('scrape-results').classList.add('hidden');
  document.getElementById('scrape-logs').innerHTML = '';
  scrapeSeriesGroups = [];
  scrapeSeriesSelected = new Set();
  const seriesBox = document.getElementById('scrape-series-results');
  if (seriesBox) {
    seriesBox.classList.add('hidden');
    seriesBox.innerHTML = '';
  }

  try {
    const d = await api('/api/douyin/scrape', {
      method: 'POST',
      body: {
        url,
        min_duration_sec: minDuration,
        oldest_first: oldestFirst,
        skip_premium: document.getElementById('scrape-skip-premium')?.checked ?? true
      }
    });
    if (d.error) { toast(d.error, 'error'); btn.disabled = false; return; }
    toast('Scanning started...');
    const pollId = setInterval(async () => {
      const s = await api(`/api/douyin/scrape/${d.job_id}`);
      // Update logs
      const logBox = document.getElementById('scrape-logs');
      logBox.innerHTML = (s.logs || []).map(l => `<div class="log-line log-default"><span class="log-msg">${l}</span></div>`).join('');
      logBox.scrollTop = logBox.scrollHeight;
      const badge = document.getElementById('scrape-status-badge');

      if (s.status === 'done') {
        clearInterval(pollId);
        badge.className = 'badge badge-success'; badge.textContent = 'DONE';
        btn.disabled = false;
        if (s.result) {
          scrapeVideos = s.result.videos || [];
          renderScrapeResults(s.result);
          
          // AUTO-GROUP SERIES AFTER RENDER
          setTimeout(() => { 
            groupSeriesByAI(); 
          }, 1500);
        }
        toast(`Found ${scrapeVideos.length} videos! Grouping series...`);
      } else if (s.status === 'error') {
        clearInterval(pollId);
        badge.className = 'badge badge-error'; badge.textContent = 'ERROR';
        btn.disabled = false;
        toast('Scrape failed: ' + (s.error || ''), 'error');
      }
    }, 3000);
  } catch (e) { toast('Error: ' + e.message, 'error'); btn.disabled = false; }
}

function renderScrapeResults(result) {
    try {
        localStorage.setItem('latest_scrape_result', JSON.stringify(result));
    } catch(e) {}
  document.getElementById('scrape-results').classList.remove('hidden');
  document.getElementById('scrape-author').textContent = result.author || 'Unknown';
  const doneCount = Number(result.done_count || 0);
  const newCount = Number(result.new_count ?? Math.max(0, scrapeVideos.length - doneCount));
  document.getElementById('scrape-count').textContent = `${result.total} videos | new ${newCount} | done ${doneCount}`;

  const list = document.getElementById('scrape-video-list');
  list.innerHTML = scrapeVideos.map((v, i) => {
    const dur = v.duration_s ? `${Math.floor(v.duration_s/60)}:${String(Math.floor(v.duration_s%60)).padStart(2,'0')}` : '';
    const plays = v.play_count ? (v.play_count > 10000 ? (v.play_count/10000).toFixed(1)+'w' : v.play_count) : '';
    const date = v.create_time ? new Date(v.create_time * 1000).toLocaleDateString('vi-VN') : '';
    const isDone = !!v.local_done;
    const localProject = scrapeHtml(v.local_project || '');
    const doneBadge = isDone
      ? `<span class="video-done-badge" title="${localProject ? `Project: ${localProject}` : 'Already exists in local projects'}">DONE</span>`
      : `<span class="video-new-badge">NEW</span>`;
    return `
    <div class="video-card ${isDone ? 'video-card-done' : 'video-card-new'}" id="vc-${i}">
      <label class="video-checkbox">
        <input type="checkbox" id="vcb-${i}" onchange="updateSelectedCount()" />
        <span class="checkmark"></span>
      </label>
      <div class="video-thumb" onclick="document.getElementById('vcb-${i}').click()">
        <img src="/api/proxy/image?url=${encodeURIComponent(v.thumbnail || v.dynamic_cover || '')}" alt="" loading="lazy" onerror="this.style.display='none'" />
        ${dur ? `<span class="video-dur">${dur}</span>` : ''}
        ${doneBadge}
      </div>
      <div class="video-info">
        <div class="video-caption" title="${scrapeHtml(v.desc || '')}">${scrapeHtml(v.desc || 'No caption')}</div>
        ${isDone && localProject ? `<div class="video-local-project">Local: <a href="javascript:void(0)" onclick="jumpToProject('${localProject}')" style="color: #64ffda; text-decoration: underline; font-weight: bold;">${localProject}</a></div>` : ''}
        <div class="video-translation" id="vt-${i}"></div>
        <div class="video-meta">
          ${plays ? `<span>â–¶ ${plays}</span>` : ''}
          ${v.digg_count ? `<span>❤ ${v.digg_count}</span>` : ''}
          ${date ? `<span>📅 ${date}</span>` : ''}
        </div>
      </div>
    </div>`;
  }).join('');

  updateSelectedCount();
}

function selectAllVideos(checked) {
  scrapeVideos.forEach((_, i) => {
    const cb = document.getElementById(`vcb-${i}`);
    if (cb) cb.checked = checked;
  });
  updateSelectedCount();
}

function selectNewVideos() {
  scrapeVideos.forEach((v, i) => {
    const cb = document.getElementById(`vcb-${i}`);
    if (cb) cb.checked = !!v.url && !v.local_done;
  });
  updateSelectedCount();
}

function updateSelectedCount() {
  let count = 0;
  let newCount = 0;
  scrapeVideos.forEach((v, i) => {
    const cb = document.getElementById(`vcb-${i}`);
    if (cb && cb.checked) {
      count++;
      if (!v.local_done) newCount++;
    }
  });
  const el = document.getElementById('selected-count');
  if (el) el.textContent = count;
  const newEl = document.getElementById('selected-new-count');
  if (newEl) newEl.textContent = newCount;
}

async function translateAllCaptions() {
  const captions = scrapeVideos.map(v => v.desc || '');
  if (!captions.length) return toast('No captions to translate', 'error');
  toast('Translating captions...');
  try {
    const d = await api('/api/douyin/translate-captions', {
      method: 'POST',
      body: { captions },
      timeoutMs: 300000
    });
    if (d.error) { toast(d.error, 'error'); return; }
    const translations = d.translations || [];
    translations.forEach((t, i) => {
      const el = document.getElementById(`vt-${i}`);
      if (el) {
        el.textContent = t;
        el.classList.add('has-translation');
      }
    });
    toast('Captions translated!');
  } catch (e) { toast('Translation error: ' + e.message, 'error'); }
}

async function startScrapeBatch() {
  const selected = [];
  scrapeVideos.forEach((v, i) => {
    const cb = document.getElementById(`vcb-${i}`);
    if (cb && cb.checked && v.url) selected.push(v.url);
  });
  if (!selected.length) return toast('Select at least one video', 'error');
  if (!confirm(`Add ${selected.length} selected videos to Pipeline queue?`)) return;
  enqueueUrlsToPipelineInput(selected, 'scraper');
}

async function startScrapeNewBatch() {
  const urls = scrapeVideos.filter(v => v.url && !v.local_done).map(v => v.url);
  if (!urls.length) return toast('No new videos found. All scraped videos already have local projects.', 'error');
  if (!confirm(`Add ${urls.length} NEW videos to Pipeline queue?`)) return;
  enqueueUrlsToPipelineInput(urls, 'scraper-new-only');
}


async function loadSavedAIGroup() {
  try {
    toast('Loading saved AI group...');
    const d = await api('/api/douyin/load-group');
    if (d.error) {
      toast(d.error, 'error');
      return;
    }
    scrapeSeriesGroups = d.groups || [];
    await renderSeriesGroups(d);
    toast(`Loaded ${scrapeSeriesGroups.length} series, standalone: ${d.standalone_count || 0}`);
  } catch (e) {
    toast('Error: ' + e.message, 'error');
  }
}

async function groupSeriesByAI() {
  if (!scrapeVideos.length) {
    toast('No scraped videos to group', 'error');
    return;
  }
  const btn = document.getElementById('btn-group-series');
  if (btn) btn.disabled = true;
  toast('Grouping series with 9router...');
  try {
    const d = await api('/api/douyin/group-series', {
      method: 'POST',
      body: { videos: scrapeVideos },
      timeoutMs: 30000
    });
    if (d.error) {
      toast(d.error, 'error');
      if (btn) btn.disabled = false;
      return;
    }
    
    if (!d.job_id) {
      toast('Failed to start group series job', 'error');
      if (btn) btn.disabled = false;
      return;
    }

    const pollId = setInterval(async () => {
      try {
        const s = await api(`/api/douyin/group-series/${d.job_id}`);
        if (s.status === 'done') {
          clearInterval(pollId);
          scrapeSeriesGroups = s.result?.groups || [];
          await renderSeriesGroups(s.result);
          toast(`Grouped ${scrapeSeriesGroups.length} series, standalone: ${s.result?.standalone_count || 0}`);
          if (btn) btn.disabled = false;
        } else if (s.status === 'error') {
          clearInterval(pollId);
          toast('Group series error: ' + (s.error || ''), 'error');
          if (btn) btn.disabled = false;
        }
      } catch (pollErr) {
        // keep polling on transient error unless it's repeated
        console.warn('Poll error:', pollErr);
      }
    }, 3000);
  } catch (e) {
    toast('Group series error: ' + e.message, 'error');
    if (btn) btn.disabled = false;
  }
}

async function renderSeriesGroups(payload) {
  const box = document.getElementById('scrape-series-results');
  if (!box) return;
  const groups = payload?.groups || [];
  const standaloneCount = payload?.standalone_count || 0;
  const coverMeta = payload?.cover_meta || {};
  const coverLine = coverMeta.covered
    ? `Cover clusters: ${coverMeta.clusters || 0} from ${coverMeta.covered} covers`
    : 'Cover clusters: unavailable';
    
  // FETCH COMPLETED URLS
  scrapeCompletedUrls = new Set();
  try {
    const doneRes = await api('/api/projects/completed-urls');
    if (doneRes.ok && Array.isArray(doneRes.completed)) {
      scrapeCompletedUrls = new Set(doneRes.completed);
    }
  } catch(e) {}
  const completedUrls = scrapeCompletedUrls;

  // Fetch existing projects for datalist
  let existingFolders = [];
  try {
    const projData = await api('/api/projects');
    if (projData && projData.projects) {
      existingFolders = projData.projects.map(p => p.name);
    }
  } catch (e) { console.error('Failed to load existing projects for datalist', e); }

  scrapeSeriesSelected = new Set();
  if (!groups.length) {
    box.innerHTML = `
      <div class="card">
        <h3>Series Grouping</h3>
        <p>No multi-episode series detected. Standalone videos: ${standaloneCount}. ${coverLine}</p>
      </div>
    `;
    box.classList.remove('hidden');
    return;
  }

  box.innerHTML = `
    <datalist id="existing-folders">
      ${existingFolders.map(f => `<option value="${safeStr(f)}">`).join('')}
    </datalist>
    <div class="card">
      <h3>Series Grouping (AI)</h3>
      <p>Detected ${groups.length} series. Standalone videos: ${standaloneCount}. ${coverLine}</p>
      <div class="btn-group" style="margin-bottom:8px">
        <button class="btn btn-outline btn-sm" onclick="selectAllSeriesGroups(true)">☑ Select All Series</button>
        <button class="btn btn-outline btn-sm" onclick="selectAllSeriesGroups(false)">☐ Clear</button>
        <button class="btn btn-primary btn-sm" onclick="addSelectedSeriesToQueue(false)">+ Add Selected (All)</button>
        <button class="btn btn-primary btn-sm" onclick="addSelectedSeriesToQueue(true)">+ Add Selected (New)</button>
        <button class="btn btn-primary btn-sm" onclick="startSelectedSeriesQueue()">â–¶ Start Selected (New Only)</button>
        <span id="series-selected-count" class="badge badge-default">0 selected</span>
      </div>
      <div class="queue-items">
        ${groups.map((g, idx) => {
          const name = g.series_name_vi || g.series_name || `Series ${idx + 1}`;
          const reason = (g.reason || '').trim();
          const conf = Number(g.confidence || 0);
          const urls = Array.isArray(g.urls) ? g.urls : [];
          const uniqueUrls = Array.isArray(g.unique_episode_urls) ? g.unique_episode_urls : [];
          const duplicateCount = Number(g.duplicate_episode_count || 0);
          const coverClusterCount = Number(g.cover_cluster_count || 0);
          const episodeStats = g.episode_min && g.episode_max
            ? ` | Episodes: <code>${g.episode_min}-${g.episode_max}</code> | Unique: <code>${g.unique_episode_count || uniqueUrls.length}</code>`
            : '';
          let hasDone = false;
          let allDone = urls.length > 0;
          urls.forEach(u => {
              if (completedUrls.has(u)) hasDone = true;
              else allDone = false;
          });

          const sample = urls.slice(0, 3).map((u) => {
            const isDone = completedUrls.has(u);
            return `<div class="url-preview-item"><span class="url-text" style="${isDone ? 'color: #4ade80; text-decoration: line-through;' : ''}">${u} ${isDone ? '<span class="badge badge-success">DONE</span>' : ''}</span></div>`;
          }).join('');
          return `
            <div class="queue-item" style="display:block; padding:12px; margin-bottom:10px;">
              <div style="display:flex; gap:10px; align-items:center; justify-content:space-between; margin-bottom:8px;">
                <div style="display:flex; align-items:center; flex-wrap:wrap; gap:8px">
                  <label style="cursor:pointer">
                    <input type="checkbox" id="sg-cb-${idx}" onchange="toggleSeriesGroupSelect(${idx}, this.checked)" ${allDone ? '' : 'checked'} />
                  </label>
                  <input type="text" class="input input-bordered input-sm" style="font-weight:bold; min-width:200px; flex-grow:1; max-width:400px" value="${name.replace(/"/g, '&quot;')}" onchange="updateSeriesName(${idx}, this.value)" />
                  <span class="badge badge-info">${g.count || urls.length} videos</span>
                  <span class="badge badge-default">conf ${(conf * 100).toFixed(0)}%</span>
                </div>
                <div style="display:flex; gap:8px; flex-wrap:wrap; justify-content:flex-end">
                  ${duplicateCount > 0 && uniqueUrls.length ? `<button class="btn btn-outline btn-sm" onclick="addSeriesUniqueEpisodesToQueue(${idx})">+ Add Unique Episodes</button>` : ''}
                  <button class="btn btn-primary btn-sm" onclick="addSeriesToQueue(${idx}, false)">+ Add (All)</button>
                  <button class="btn btn-primary btn-sm" onclick="addSeriesToQueue(${idx}, true)">+ Add (New)</button>
                </div>
              </div>
              <div style="font-size:.82rem; color:var(--text-dim); margin-bottom:6px;">
                Folder: <code>${g.folder || ''}</code>
                ${g.folder_path_suggested ? ` | Path: <code>${g.folder_path_suggested}</code>` : ''}
                ${episodeStats}
                ${duplicateCount > 0 ? ` | Duplicates: <code>${duplicateCount}</code>` : ''}
                ${coverClusterCount > 0 ? ` | Cover clusters: <code>${coverClusterCount}</code>` : ''}
              </div>
              ${reason ? `<div style="font-size:.8rem; color:var(--text-dim); margin-bottom:6px;">Reason: ${reason}</div>` : ''}
              <div>${sample}</div>
              ${urls.length > 3 ? `<div style="font-size:.8rem; color:var(--text-dim); margin-top:4px;">+${urls.length - 3} more links...</div>` : ''}
            </div>
          `;
        }).join('')}
      </div>
    </div>
  `;
  box.classList.remove('hidden');

  // Auto-select checkboxes that are checked by default
  setTimeout(() => {
    (groups || []).forEach((_, idx) => {
      const cb = document.getElementById(`sg-cb-${idx}`);
      if (cb && cb.checked) {
        toggleSeriesGroupSelect(idx, true);
      }
    });
  }, 100);
}

function _toEpisodeInt(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const out = Math.floor(n);
  return out > 0 ? out : null;
}

function buildSeriesContextMap(group, urls) {
  const contextMap = {};
  const videos = Array.isArray(group?.videos) ? group.videos : [];
  const byUrl = {};
  videos.forEach((v) => {
    const u = (v?.url || '').trim();
    if (u) byUrl[u] = v;
  });

  const orderedUrls = (Array.isArray(group?.urls) ? group.urls : videos.map(v => v?.url))
    .map(u => (u || '').trim())
    .filter(Boolean);
  const idxByUrl = {};
  orderedUrls.forEach((u, i) => { if (idxByUrl[u] == null) idxByUrl[u] = i; });

  const known = [];
  orderedUrls.forEach((u, i) => {
    const ep = _toEpisodeInt(byUrl[u]?.episode_no);
    if (ep != null) known.push({ i, ep });
  });
  const knownByIdx = new Map(known.map(k => [k.i, k.ep]));

  const canHeadExtrapolate = known.length >= 2
    && (known[1].i - known[0].i) > 0
    && (known[1].ep - known[0].ep) === (known[1].i - known[0].i);
  const canTailExtrapolate = known.length >= 2
    && (known[known.length - 1].i - known[known.length - 2].i) > 0
    && (known[known.length - 1].ep - known[known.length - 2].ep) === (known[known.length - 1].i - known[known.length - 2].i);

  function inferEpisodeByIndex(idx) {
    if (!Number.isFinite(idx) || idx < 0 || !known.length) return null;
    const direct = knownByIdx.get(idx);
    if (direct != null) return direct;

    let left = null;
    let right = null;
    for (const k of known) {
      if (k.i < idx) {
        left = k;
        continue;
      }
      if (k.i > idx) {
        right = k;
        break;
      }
    }

    if (left && right) {
      const idxGap = right.i - left.i;
      const epGap = right.ep - left.ep;
      if (idxGap > 0 && epGap === idxGap) {
        const cand = left.ep + (idx - left.i);
        return cand > 0 ? cand : null;
      }
      return null;
    }
    if (!left && right && canHeadExtrapolate) {
      const cand = right.ep - (right.i - idx);
      return cand > 0 ? cand : null;
    }
    if (left && !right && canTailExtrapolate) {
      const cand = left.ep + (idx - left.i);
      return cand > 0 ? cand : null;
    }
    return null;
  }

  (urls || []).forEach((url) => {
    const v = byUrl[url] || {};
    const idx = idxByUrl[url];
    const episodeNo = _toEpisodeInt(v.episode_no) ?? inferEpisodeByIndex(idx);
    contextMap[url] = {
      series_name_vi: group?.series_name_vi || group?.series_name || '',
      series_name: group?.series_name || '',
      series_folder: group?.folder || '',
      episode_no: episodeNo ?? null,
      episode_min: group?.episode_min ?? null,
      episode_max: group?.episode_max ?? null,
      source: 'douyin_series_group'
    };
  });
  return contextMap;
}



async function addSeriesUniqueEpisodesToQueue(idx) {
  const group = scrapeSeriesGroups[idx];
  if (!group) {
    toast('Series not found', 'error');
    return;
  }
  let urls = Array.isArray(group.unique_episode_urls) ? group.unique_episode_urls.filter(Boolean) : [];
  
  if (scrapeCompletedUrls instanceof Set) {
    urls = urls.filter(u => !scrapeCompletedUrls.has(u));
  }
  
  if (!urls.length) {
    toast('No remaining unique URLs in this series', 'error');
    return;
  }
  
  const folderInput = document.querySelector(`.series-folder-input[data-idx="${idx}"]`);
  const finalFolder = folderInput ? folderInput.value.trim() : group.folder;
  group.folder = finalFolder;
  
  if (urls.length && finalFolder) {
      api('/api/series/save-urls', { method: 'POST', body: { series_folder: finalFolder, urls: urls } }).catch(e => console.warn('save-urls optional:', e));
  }
  
  const groupContexts = buildSeriesContextMap(group, urls);
  urls.forEach(u => { if (groupContexts[u]) groupContexts[u].series_folder = finalFolder; });

  enqueueUrlsToPipelineInput(urls, `series-unique:${finalFolder || idx}`, groupContexts);
}

async function loadDouyinWatchdogState() {
  try {
    const d = await api('/api/douyin/watchdog/state');
    document.getElementById('dywd-enabled').checked = !!d.enabled;
    const userUrls = Array.isArray(d.user_urls) && d.user_urls.length ? d.user_urls : (d.user_url ? [d.user_url] : []);
    const urlsEl = document.getElementById('dywd-user-urls') || document.getElementById('dywd-user-url');
    if (urlsEl) urlsEl.value = userUrls.join('\n');
    document.getElementById('dywd-interval').value = d.interval_min ?? 15;
    document.getElementById('dywd-min-duration').value = d.min_duration_sec ?? 60;
    const status = document.getElementById('dywd-status-line');
    if (status) {
      status.textContent = `Watchdog: ${d.enabled ? 'ON' : 'OFF'} | Users: ${userUrls.length} | Running: ${d.running ? 'YES' : 'NO'} | Last run: ${d.last_run_at || 'N/A'} | ${d.last_summary || ''}`;
    }
  } catch (e) {
    toast('Watchdog state error: ' + e.message, 'error');
  }
}

async function saveDouyinWatchdogConfig() {
  const rawUrls = (document.getElementById('dywd-user-urls') || document.getElementById('dywd-user-url'))?.value || '';
  const userUrls = rawUrls.split(/\r?\n/).map(x => x.trim()).filter(Boolean);
  const payload = {
    enabled: !!document.getElementById('dywd-enabled')?.checked,
    user_urls: userUrls,
    user_url: userUrls[0] || '',
    interval_min: parseInt(document.getElementById('dywd-interval')?.value || '15', 10) || 15,
    min_duration_sec: parseFloat(document.getElementById('dywd-min-duration')?.value || '60') || 60,
  };
  try {
    const d = await api('/api/douyin/watchdog/config', { method: 'POST', body: payload });
    if (d.error) {
      toast(d.error, 'error');
      return;
    }
    toast('Douyin watchdog saved');
    await loadDouyinWatchdogState();
  } catch (e) {
    toast('Save watchdog error: ' + e.message, 'error');
  }
}

async function runDouyinWatchdogNow() {
  try {
    const d = await api('/api/douyin/watchdog/run-once', { method: 'POST', body: {}, timeoutMs: 600000 });
    if (d.error || d.ok === false) {
      toast(d.error || 'Watchdog run failed', 'error');
      return;
    }
    const out = d.result || {};
    toast(`Watchdog done: new ${out.new_count || 0}, queued ${out.queued || 0}`);
    await loadDouyinWatchdogState();
  } catch (e) {
    toast('Run watchdog error: ' + e.message, 'error');
  }
}

// ── TTS Engine Toggle ──
function toggleTtsOptions() {
  const engine = document.getElementById('cfg-tts_engine')?.value || 'vieneu';
  const mode = document.getElementById('cfg-vieneu_mode')?.value || 'preset';
  
  const vieneuModeGroup = document.getElementById('vieneu-mode-group');
  const vieneuVoiceGroup = document.getElementById('vieneu-voice-group');
  const vnRef = document.getElementById('vieneu-ref-group');
  const capcutGroup = document.getElementById('capcut-voice-group');
  const capcutWorkersGroup = document.getElementById('capcut-workers-group');
  const capcutPipelineLimitGroup = document.getElementById('capcut-pipeline-limit-group');
  
  if (vieneuModeGroup) vieneuModeGroup.style.display = engine === 'vieneu' ? '' : 'none';
  if (vieneuVoiceGroup) vieneuVoiceGroup.style.display = (engine === 'vieneu' && mode === 'preset') ? '' : 'none';
  if (vnRef) vnRef.style.display = (engine === 'vieneu' && mode === 'clone') ? '' : 'none';
  if (capcutGroup) capcutGroup.style.display = (engine === 'capcut' || engine === 'capcut_native') ? '' : 'none';
  if (capcutWorkersGroup) capcutWorkersGroup.style.display = (engine === 'capcut' || engine === 'capcut_native') ? '' : 'none';
  if (capcutPipelineLimitGroup) capcutPipelineLimitGroup.style.display = (engine === 'capcut' || engine === 'capcut_native') ? '' : 'none';
}

// ── TTS Test ──
async function testTts() {
  const btn = document.getElementById('btn-test-tts');
  const status = document.getElementById('tts-test-status');
  const audio = document.getElementById('tts-test-audio');
  btn.disabled = true;
  status.textContent = '⏳ Generating...';
  audio.style.display = 'none';
  
  try {
    const engine = document.getElementById('cfg-tts_engine')?.value || 'vieneu';
    let refVoice = document.getElementById('cfg-vieneu_ref_voice')?.value;
    if (!refVoice) refVoice = 'sample.WAV';
    
    const reqBody = {
      engine: engine,
      ref_voice: refVoice,
      vieneu_voice: document.getElementById('cfg-vieneu_voice')?.value,
      vieneu_mode: document.getElementById('cfg-vieneu_mode')?.value,
      capcut_voice: document.getElementById('cfg-capcut_voice')?.value,
      capcut_tts_workers: parseInt(document.getElementById('cfg-capcut_tts_workers')?.value) || 2,
      capcut_tts_pipeline_limit: parseInt(document.getElementById('cfg-capcut_tts_pipeline_limit')?.value) || 2,
      auto_adjust_tts_speed: !!document.getElementById('cfg-auto_adjust_tts_speed')?.checked,
      tts_speed: parseFloat(document.getElementById('cfg-tts_speed')?.value || '1') || 1,
      tts_pitch: parseFloat(document.getElementById('cfg-tts_pitch')?.value || '1') || 1,
      tts_volume: parseFloat(document.getElementById('cfg-tts_volume')?.value || '1') || 1,
    };
    
    const res = await fetch('/api/tts/test', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(reqBody)
    });
    
    if (res.ok) {
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      audio.src = url;
      audio.style.display = 'inline-block';
      status.textContent = '✅ Done!';
      toast('TTS generated! Listen to preview.', 'success');
    } else {
      const err = await res.json();
      status.textContent = '❌ Error';
      toast('TTS failed: ' + (err.error || 'Unknown error'), 'error');
    }
  } catch (e) {
    status.textContent = '❌ Error';
    toast('TTS test error: ' + e.message, 'error');
  }
  btn.disabled = false;
}

// ── Queue Export/Import ──
async function exportQueue() {
  try {
    const d = await api('/api/pipeline/export');
    if (d.error) { toast(d.error, 'error'); return; }
    const filename = `queue_${d.queue_id || 'state'}_${new Date().toISOString().slice(0,10)}.json`;
    const content = JSON.stringify(d, null, 2);

    // Prefer native Save As dialog when available (Chromium File System Access API)
    if (window.showSaveFilePicker) {
      const handle = await window.showSaveFilePicker({
        suggestedName: filename,
        types: [{
          description: 'JSON files',
          accept: { 'application/json': ['.json'] }
        }]
      });
      const writable = await handle.createWritable();
      await writable.write(content);
      await writable.close();
      toast('Queue exported!');
      return;
    }

    // Fallback: normal browser download
    const blob = new Blob([content], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
    toast('Queue exported!');
  } catch (e) {
    if (e?.name === 'AbortError') return; // User canceled save dialog
    toast('Error: ' + e.message, 'error');
  }
}

async function exportQueueToFile() {
  return exportQueue();
}

async function pickQueueImportFile() {
  if (window.showOpenFilePicker) {
    const [handle] = await window.showOpenFilePicker({
      multiple: false,
      types: [{
        description: 'JSON files',
        accept: { 'application/json': ['.json'] }
      }]
    });
    if (!handle) return null;
    const file = await handle.getFile();
    return await file.text();
  }

  return await new Promise((resolve, reject) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json,application/json';
    input.style.display = 'none';
    document.body.appendChild(input);
    input.onchange = async () => {
      try {
        const f = input.files && input.files[0];
        document.body.removeChild(input);
        if (!f) return resolve(null);
        resolve(await f.text());
      } catch (e) {
        reject(e);
      }
    };
    input.click();
  });
}

function buildImportPayloadFromState(state) {
  if (!state || !Array.isArray(state.urls) || !state.urls.length) {
    throw new Error('Invalid queue file: missing urls');
  }
  const urls = state.urls;

  let startFrom = Number(state.start_from);
  if (!Number.isFinite(startFrom) || startFrom < 0) {
    startFrom = Number(state.completed);
  }
  if (!Number.isFinite(startFrom) || startFrom < 0) {
    const done = new Set();
    for (const r of (state.results || [])) {
      const ok = r && r.result && !String(r.result).includes('skipped');
      if (ok && r.url) done.add(r.url);
    }
    startFrom = done.size;
  }
  startFrom = Math.min(Math.max(0, Math.floor(startFrom)), urls.length);

  return { urls, start_from: startFrom, contexts: state.contexts || {} };
}

async function importQueueFromFile() {
  try {
    const content = await pickQueueImportFile();
    if (!content) return;
    let parsed = null;
    try {
      parsed = JSON.parse(content);
    } catch {
      toast('Invalid JSON file', 'error');
      return;
    }
    const payload = buildImportPayloadFromState(parsed);
    const remaining = payload.urls.slice(payload.start_from);
    if (!remaining.length) {
      toast('No remaining URLs in this JSON (already completed).', 'error');
      return;
    }
    enqueueUrlsToPipelineInput(remaining, 'import-json', payload.contexts);
  } catch (e) {
    if (e?.name === 'AbortError') return;
    toast('Error: ' + e.message, 'error');
  }
}
async function importQueue() {
  try {
    const d = await api('/api/pipeline/import', { method: 'POST', body: {} });
    if (d.error) { toast(d.error, 'error'); return; }
    toast(`Queue resumed! ${d.remaining} URLs còn lại`);
    document.getElementById('saved-state-banner').classList.add('hidden');
    document.getElementById('queue-monitor').classList.remove('hidden');
    const items = document.getElementById('queue-items');
    items.innerHTML = d.urls.map((u, i) => `
      <div class="queue-item" id="qi-${i}">
        <span class="queue-idx">${i+1}</span>
        <span class="queue-url">${u.length > 50 ? u.substring(0,50)+'...' : u}</span>
        <span class="queue-item-status badge ${i < d.resumed_from ? 'badge-success' : 'badge-default'}" id="qi-status-${i}">${i < d.resumed_from ? '✅ Done (trước đó)' : '⏳ Waiting'}</span>
      </div>
    `).join('');
    selectedQueueId = d.queue_id;
    queueTimer = setInterval(() => pollQueue(d.queue_id, d.urls), 3000);
    refreshActiveQueues();
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

async function checkSavedState() {
  try {
    const d = await api('/api/pipeline/saved-state');
    if (d.found && d.remaining > 0) {
      const banner = document.getElementById('saved-state-banner');
      const info = document.getElementById('saved-state-info');
      const badge = document.getElementById('saved-state-badge');
      info.textContent = `Queue "${d.queue_id}" — ${d.done_count}/${d.total} đã xong, ${d.remaining} còn lại, ${d.errors} lỗi. Lưu lúc: ${d.saved_at}`;
      badge.textContent = `${d.remaining} chưa xong`;
      banner.classList.remove('hidden');
    }
  } catch (e) { /* no saved state */ }
}

function dismissSavedState() {
  document.getElementById('saved-state-banner').classList.add('hidden');
}

// ── Init ──
document.addEventListener('DOMContentLoaded', () => {
    try {
        const saved = localStorage.getItem('latest_scrape_result');
        if (saved) {
            const parsed = JSON.parse(saved);
            if (parsed && parsed.videos && parsed.videos.length > 0) {
                window.scrapeVideos = parsed.videos;
                renderScrapeResults(parsed);
            }
        }
    } catch(e) {}
  loadScrapeHistory();
  updateDemoBanner();
  checkHealth();
  checkSavedState();
  refreshActiveQueues();
  loadDouyinWatchdogState();
  setInterval(checkHealth, 30000);
  activeQueuesTimer = setInterval(refreshActiveQueues, 5000);
  setInterval(loadDouyinWatchdogState, 45000);
  document.querySelectorAll('.tab[data-tab]').forEach(t => t.addEventListener('click', () => switchTab(t.dataset.tab)));
  toggleTtsOptions();
});






// ─── Jump To Project ─────────────────────────────────────────────────────────
function jumpToProject(projectName) {
  const tabProjects = document.querySelector('[data-tab="projects"]');
  if (tabProjects) {
    tabProjects.click();
    setTimeout(() => {
      openProjectDetail(projectName);
    }, 300);
  }
}

// ═══ NEW AI GROUP LOGIC ═══
window.toggleSeriesGroupSelect = function(idx, checked) {
    if (!scrapeSeriesSelected) scrapeSeriesSelected = new Set();
    if (checked) scrapeSeriesSelected.add(idx);
    else scrapeSeriesSelected.delete(idx);
    const countEl = document.getElementById('series-selected-count');
    if (countEl) countEl.innerText = `${scrapeSeriesSelected.size} selected`;
};

window.selectAllSeriesGroups = function(state) {
    if (!scrapeSeriesSelected) scrapeSeriesSelected = new Set();
    scrapeSeriesSelected.clear();
    if (state && scrapeSeriesGroups) {
        scrapeSeriesGroups.forEach((g, idx) => scrapeSeriesSelected.add(idx));
    }
    document.querySelectorAll('[id^="sg-cb-"]').forEach(cb => {
        cb.checked = state;
    });
    const countEl = document.getElementById('series-selected-count');
    if (countEl) countEl.innerText = `${scrapeSeriesSelected.size} selected`;
};

window.addSeriesToQueue = function(idx, newOnly) {
    return addSeriesToQueueLocal(idx, !!newOnly);
};

window.addSelectedSeriesToQueue = function(newOnly) {
    return addSelectedSeriesToQueueLocal(!!newOnly);
};

window.startSelectedSeriesQueue = function() {
    return startSelectedSeriesQueueLocal();
};

async function _queueSeriesGroups(indices, newOnly) {
    let completedUrls = new Set();
    if (newOnly) {
        try {
            const h = await api('/api/projects/completed-urls');
            if (h.ok && Array.isArray(h.completed)) completedUrls = new Set(h.completed);
        } catch(e) {}
    }
    
    let totalAdded = 0;
    
    for (const idx of indices) {
        const g = scrapeSeriesGroups[idx];
        if (!g) continue;
        
        let urlsToQueue = g.urls || [];
        if (newOnly) {
            urlsToQueue = urlsToQueue.filter(u => !completedUrls.has(u));
        }
        if (urlsToQueue.length === 0) continue; 
        
        const payload = {
            urls: urlsToQueue,
            settings: window.currentScrapeSettings || {},
            priority: 5,
            group_series: true,
            series_name: g.series_name_vi || g.series_name || '',
            folder_name: g.folder_name || '',
            episodes_range: `${g.episode_min || ''}-${g.episode_max || ''}`
        };
        await api('/api/pipeline/queue', { method: 'POST', body: payload });
        totalAdded += urlsToQueue.length;
    }
    return totalAdded;
}



// ═══ SERIES LIBRARY ═══
function switchSeriesSubTab(subtab) {
    document.querySelectorAll('.series-sub-tab').forEach(t => t.classList.toggle('active', t.dataset.subtab === subtab));
    document.querySelectorAll('.series-sub-content').forEach(c => c.classList.toggle('hidden', c.id !== subtab));
}

async function loadSeriesLibrary() {
    const listSeries = document.getElementById('series-list');
    const listStandalones = document.getElementById('standalone-list');
    if (!listSeries || !listStandalones) return;
    
    listSeries.innerHTML = '<div style="color:var(--text-dim)">Loading series...</div>';
    listStandalones.innerHTML = '<div style="color:var(--text-dim)">Loading standalones...</div>';
    
    try {
        const res = await api('/api/series');
        if (!res || res.error) throw new Error(res?.error || 'Failed to load series');
        
        const series = res.series || [];
        const standalones = res.standalones || [];
        
        const badgeSeries = document.getElementById('series-count-badge');
        const badgeStandalone = document.getElementById('standalone-count-badge');
        if (badgeSeries) badgeSeries.innerText = series.length;
        if (badgeStandalone) badgeStandalone.innerText = standalones.length;
        
        if (series.length === 0) {
            listSeries.innerHTML = '<div style="color:var(--text-dim)">No series found.</div>';
        } else {
            listSeries.innerHTML = series.map(s => renderSeriesCard(s)).join('');
        }
        
        if (standalones.length === 0) {
            listStandalones.innerHTML = '<div style="color:var(--text-dim)">No standalone movies found.</div>';
        } else {
            listStandalones.innerHTML = standalones.map(p => renderStandaloneCard(p)).join('');
        }
        
    } catch (e) {
        listSeries.innerHTML = `<div style="color:var(--error)">Error: ${e.message}</div>`;
        listStandalones.innerHTML = `<div style="color:var(--error)">Error: ${e.message}</div>`;
    }
}

function renderSeriesCard(s) {
    const total = s.total_downloaded || 0;
    const rendered = s.rendered_count || 0;
    const uploaded = s.uploaded_count || 0;
    
    const ep_min = s.episode_min || '?';
    const ep_max = s.episode_max || '?';
    
    const latest = s.latest_episode || {};
    const thumb = latest.thumbnail ? `/api/project/${encodeURIComponent(latest.project_name)}/file/thumbnail.jpg` : '';
    
    const renderPct = total > 0 ? Math.round((rendered / total) * 100) : 0;
    const uploadPct = total > 0 ? Math.round((uploaded / total) * 100) : 0;
    
    
      const hasSavedUrls = s.reg_info && Array.isArray(s.reg_info.urls) && s.reg_info.urls.length > 0;
      
      return `
      <div class="project-card" style="cursor:pointer; display:flex; flex-direction:column; justify-content:space-between;" onclick="openSeriesInProjects('${safeStr(s.series_folder)}')">
        <div style="display:flex; gap:12px; margin-bottom:12px;">
          <div style="width:100px; height:140px; border-radius:6px; background:#1e1e1e; overflow:hidden; flex-shrink:0;">
              ${thumb ? `<img src="${thumb}" style="width:100%; height:100%; object-fit:cover;">` : `<div style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;color:#666;font-size:2rem">🎬</div>`}
          </div>
          <div style="flex:1; overflow:hidden;">
              <h3 style="margin:0 0 6px; font-size:1rem; overflow:hidden; text-overflow:ellipsis; display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical;">${safeStr(s.series_name)}</h3>
              <div style="font-size:0.8rem; color:var(--text-dim); margin-bottom:4px;">Folder: <code>${safeStr(s.series_folder)}</code></div>
              <div style="font-size:0.8rem; color:var(--text-dim); margin-bottom:4px;">Episodes: <span class="badge badge-default">${total} downloaded</span> (Max: ${ep_max})</div>
              <div style="font-size:0.8rem; color:var(--text-dim);">Latest update: ${safeStr(latest.created_at || '')}</div>
          </div>
        </div>
        
        <div>
            <div style="display:flex; justify-content:space-between; font-size:0.75rem; margin-bottom:4px;">
                <span>Rendered: ${rendered}/${total}</span>
                <span>${renderPct}%</span>
            </div>
            <div class="progress-bar" style="height:6px; margin-bottom:8px;"><div class="progress-fill" style="width:${renderPct}%; background:var(--accent);"></div></div>
            
            <div style="display:flex; justify-content:space-between; font-size:0.75rem; margin-bottom:4px;">
                <span>Uploaded: ${uploaded}/${total}</span>
                <span>${uploadPct}%</span>
            </div>
            <div class="progress-bar" style="height:6px;"><div class="progress-fill" style="width:${uploadPct}%; background:var(--primary);"></div></div>
            <div style="margin-top: 12px; text-align: right; display:flex; gap:8px; justify-content:flex-end;">
               ${hasSavedUrls ? `<button class="btn btn-primary btn-sm" onclick="event.stopPropagation(); resumeSavedSeriesQueue('${safeStr(s.series_folder)}')">▶ Resume Series</button>` : ''}
               <button class="btn btn-outline btn-sm" onclick="event.stopPropagation(); openSeriesGlossaryModal('${safeStr(s.series_folder)}', '${safeStr(s.series_name).replace(/'/g, "\\'")}')">📖 Từ Điển (Glossary)</button>
            </div>
        </div>
      </div>
      `;
}

function renderStandaloneCard(p) {
    const meta = p.metadata || {};
    const title = meta.title || p.douyin_meta?.douyin_title || p.project_name;
    const thumb = p.thumbnail ? `/api/project/${encodeURIComponent(p.project_name)}/file/thumbnail.jpg` : '';
    
    let statusText = 'Downloaded';
    let statusColor = 'var(--text-dim)';
    if (p.final_video) { statusText = 'Rendered'; statusColor = 'var(--accent)'; }
    if (p.youtube?.videoId || p.facebook_reels?.results) { statusText = 'Uploaded'; statusColor = 'var(--primary)'; }
    
    return `
    <div class="project-card" style="cursor:pointer; display:flex; gap:12px; align-items:center;" onclick="openSeriesInProjects('${safeStr(p.project_name)}')">
        <div style="width:80px; height:80px; border-radius:6px; background:#1e1e1e; overflow:hidden; flex-shrink:0;">
            ${thumb ? `<img src="${thumb}" style="width:100%; height:100%; object-fit:cover;">` : `<div style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;color:#666;font-size:1.5rem">🎬</div>`}
        </div>
        <div style="flex:1; overflow:hidden;">
            <h3 style="margin:0 0 6px; font-size:0.95rem; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${safeStr(title)}</h3>
            <div style="font-size:0.8rem; color:var(--text-dim); margin-bottom:4px;">Project: <code>${safeStr(p.project_name)}</code></div>
            <div style="font-size:0.8rem; font-weight:600; color:${statusColor}">${statusText}</div>
        </div>
    </div>
    `;
}

function openSeriesInProjects(filterText) {
    // Switch to projects tab
    const tabProjects = document.querySelector('[data-tab="projects"]');
    if (tabProjects) tabProjects.click();
    
    // Set custom filter
    setTimeout(() => {
        const filterSelect = document.getElementById('project-filter');
        if (filterSelect) {
            // Check if there is an option for custom, if not add it
            let opt = filterSelect.querySelector(`option[value="custom_${filterText}"]`);
            if (!opt) {
                opt = document.createElement('option');
                opt.value = `custom_${filterText}`;
                opt.innerText = `🔍 Tìm: ${filterText}`;
                filterSelect.appendChild(opt);
            }
            filterSelect.value = opt.value;
            loadProjects();
        }
    }, 100);
}


function updateSeriesName(idx, val) {
  if (scrapeSeriesGroups[idx]) {
    scrapeSeriesGroups[idx].series_name_vi = val;
    scrapeSeriesGroups[idx].series_name = val;
  }
}

async function addSeriesToQueueLocal(idx, newOnly = false) {
  const group = scrapeSeriesGroups[idx];
  if (!group) {
    toast('Series not found', 'error');
    return;
  }
  let urls = Array.isArray(group.urls) ? group.urls.filter(Boolean) : [];
  if (newOnly && scrapeCompletedUrls instanceof Set) {
    urls = urls.filter(u => !scrapeCompletedUrls.has(u));
  }
  if (!urls.length) {
    toast('No remaining URLs to add for this series', 'error');
    return;
  }
  
  const folderInput = document.querySelector(`.series-folder-input[data-idx="${idx}"]`);
  const finalFolder = folderInput ? folderInput.value.trim() : group.folder;
  group.folder = finalFolder;
  
  if (urls.length && finalFolder) {
      api('/api/series/save-urls', { method: 'POST', body: { series_folder: finalFolder, urls: urls } }).catch(e => console.warn('save-urls optional:', e));
  }
  
  const groupContexts = buildSeriesContextMap(group, urls);
  urls.forEach(u => { if (groupContexts[u]) groupContexts[u].series_folder = finalFolder; });

  enqueueUrlsToPipelineInput(urls, `series:${finalFolder || idx}`, groupContexts);
}

function toggleSeriesGroupSelect(idx, checked) {
  if (checked) scrapeSeriesSelected.add(idx);
  else scrapeSeriesSelected.delete(idx);
  const cb = document.getElementById(`sg-cb-${idx}`);
  if (cb) cb.checked = checked;
  const badge = document.getElementById('series-selected-count');
  if (badge) badge.innerText = `${scrapeSeriesSelected.size} selected`;
}

function selectAllSeriesGroups(checked) {
  (scrapeSeriesGroups || []).forEach((_, idx) => toggleSeriesGroupSelect(idx, checked));
}

async function addSelectedSeriesToQueueLocal(newOnly = false) {
  if (!scrapeSeriesSelected.size) {
    toast('No series selected', 'error');
    return;
  }
  let totalAdded = 0;
  for (let idx of Array.from(scrapeSeriesSelected)) {
    const group = scrapeSeriesGroups[idx];
    if (!group) continue;
    let urls = Array.isArray(group.urls) ? group.urls.filter(Boolean) : [];
    
    const folderInput = document.querySelector(`.series-folder-input[data-idx="${idx}"]`);
    const finalFolder = folderInput ? folderInput.value.trim() : group.folder;
    group.folder = finalFolder;
    
    if (urls.length && finalFolder) {
       api('/api/series/save-urls', { method: 'POST', body: { series_folder: finalFolder, urls: urls } }).catch(e => console.warn('save-urls optional:', e));
    }

    if (newOnly && scrapeCompletedUrls instanceof Set) {
      urls = urls.filter(u => !scrapeCompletedUrls.has(u));
    }
    if (!urls.length) continue;
    
    const groupContexts = buildSeriesContextMap(group, urls);
    urls.forEach(u => { if (groupContexts[u]) groupContexts[u].series_folder = finalFolder; });

    const addedCount = enqueueUrlsToPipelineInput(urls, `series:${finalFolder || idx}`, groupContexts);
    totalAdded += addedCount;
  }
  if (totalAdded > 0) {
    toast(`Added total ${totalAdded} URLs from ${scrapeSeriesSelected.size} series`);
  } else {
    toast('No remaining new URLs in selected series', 'error');
  }
}

async function startSelectedSeriesQueueLocal() {
  if (!scrapeSeriesSelected.size) {
    toast('No series selected', 'error');
    return;
  }
  await addSelectedSeriesToQueueLocal(true);
  await startBatchPipeline();
}

// --- MiuBon Watch Progress ---
let miubonWatchProgress = {};

async function miubonLogin() {
  const user = document.getElementById('miubon-username').value;
  const pass = document.getElementById('miubon-password').value;
  if (!user || !pass) return alert('Vui lòng nhập Username và Password!');
  try {
    const r = await api('/api/auth/login', { method: 'POST', body: { username: user, password: pass } });
    if (!r.ok) return alert(r.error || 'Login failed');
    localStorage.setItem('miubon_token', r.token);
    localStorage.setItem('miubon_user', r.username);
    miubonCheckAuth();
    miubonLoadProgress();
    loadScrapeHistory();
    alert('Đăng nhập thành công!');
  } catch (e) {
    alert(e.message);
  }
}

function miubonLogout() {
  localStorage.removeItem('miubon_token');
  localStorage.removeItem('miubon_user');
  miubonWatchProgress = {};
  miubonCheckAuth();
}

let isLoginMode = true;
function switchLoginTab(mode) {
  isLoginMode = mode === 'login';
  document.getElementById('btn-tab-login').className = isLoginMode ? 'btn btn-primary' : 'btn btn-outline';
  document.getElementById('btn-tab-login').style.border = isLoginMode ? '' : 'none';
  document.getElementById('btn-tab-login').style.background = isLoginMode ? '' : 'transparent';
  
  document.getElementById('btn-tab-register').className = !isLoginMode ? 'btn btn-primary' : 'btn btn-outline';
  document.getElementById('btn-tab-register').style.border = !isLoginMode ? '' : 'none';
  document.getElementById('btn-tab-register').style.background = !isLoginMode ? '' : 'transparent';

  document.getElementById('btn-wall-action').innerText = isLoginMode ? 'Đăng Nhập' : 'Đăng Ký';
  document.getElementById('wall-error').innerText = '';
}

async function wallAction() {
  const user = document.getElementById('wall-username').value;
  const pass = document.getElementById('wall-password').value;
  const errEl = document.getElementById('wall-error');
  if (!user || !pass) {
    errEl.innerText = 'Vui lòng nhập Username và Password!';
    return;
  }
  
  errEl.innerText = 'Đang xử lý...';
  try {
    const endpoint = isLoginMode ? '/api/auth/login' : '/api/auth/register';
    const r = await api(endpoint, { method: 'POST', body: { username: user, password: pass } });
    if (!r.ok) {
      errEl.innerText = r.error || 'Có lỗi xảy ra!';
      return;
    }
    
    localStorage.setItem('miubon_token', r.token);
    localStorage.setItem('miubon_user', r.username);
    miubonCheckAuth();
    miubonLoadProgress();
    loadScrapeHistory();
  } catch(e) {
    errEl.innerText = e.message;
  }
}

function miubonCheckAuth() {
  const u = localStorage.getItem('miubon_user');
  const token = localStorage.getItem('miubon_token');
  const el = document.getElementById('miubon-auth-status');
  if (el) {
    el.innerText = u ? `Xin chào, ${u}` : 'Chưa đăng nhập.';
  }
  
  const wall = document.getElementById('login-wall');
  const main = document.getElementById('main-app-content');
  if (wall && main) {
    if (token) {
      wall.style.display = 'none';
      main.style.display = 'block';
    } else {
      wall.style.display = 'flex';
      main.style.display = 'none';
    }
  }
}

async function miubonLoadProgress() {
  const token = localStorage.getItem('miubon_token');
  if (!token) return;
  try {
    const r = await api('/api/user/progress');
    if (r.ok) {
      miubonWatchProgress = r.progress || {};
    }
  } catch (e) {
    console.warn('Failed to load watch progress', e);
  }
}

function miubonSaveProgress(folder, epIndex, timeSec) {
  const token = localStorage.getItem('miubon_token');
  if (!token || !folder) return;
  if (!miubonWatchProgress[folder]) miubonWatchProgress[folder] = {};
  miubonWatchProgress[folder] = { ep_index: epIndex, time: timeSec };
  
  api('/api/user/progress', {
    method: 'POST',
    body: { folder, ep_index: epIndex, time: timeSec }
  }).catch(e => console.warn('Failed to save progress', e));
}

// Hooks
document.addEventListener('DOMContentLoaded', () => {
  miubonCheckAuth();
  miubonLoadProgress();
    loadScrapeHistory();
  
  let lastSaveTime = 0;
  const vid = document.getElementById('watch-video-element');
  if (!vid) return;
  vid.addEventListener('timeupdate', () => {
    if (!currentWatchSeries) return;
    const now = Date.now();
    if (now - lastSaveTime > 5000) { // save every 5s
      lastSaveTime = now;
      let folder = currentWatchSeries.series_folder;
      if (currentEpIndex >= 0) {
        miubonSaveProgress(folder, currentEpIndex, vid.currentTime);
      }
    }
  });
});

async function previewUrls() {
    const el = document.getElementById('pipeline-preview');
    const input = document.getElementById('input-url');
    if (!el || !input) return;
    const urls = input.value.split(/\r?\n/).map(s => s.trim()).filter(Boolean);
    if (!urls.length) {
        el.innerHTML = '<div class="url-preview-empty">⚠️ No Douyin URLs detected</div>';
        return;
    }
    try {
        const res = await api('/api/douyin/preview', { method: 'POST', body: { urls } });
        if (res.error) throw new Error(res.error);
        


        const found = res.previews || [];
        if (!found.length) {
            el.innerHTML = '<div class="url-preview-empty">❌ No valid Douyin URLs recognized</div>';
            return;
        }
        el.innerHTML = `<div class="url-preview-header">🔍 Found ${found.length} URL(s):</div>` +
            found.map(p => `
            <div class="url-preview-item">
                <span class="url-text">${p.url}</span>
                ${p.project_name ? `<span class="badge badge-success">Folder: ${p.project_name}</span>` : '<span class="badge badge-default">New</span>'}
            </div>
            `).join('');
    } catch (e) {
        el.innerHTML = `<div class="url-preview-empty" style="color:var(--error)">Error previewing: ${e.message}</div>`;
    }
}



/* =========================================

/* =========================================
   WATCH VIDEO UI LOGIC
========================================= */
let currentWatchSeries = null;
let watchLibraryData = null;
let currentEpIndex = -1;
let currentPlayableEps = [];

async function loadWatchLibrary() {
  document.getElementById('watch-grid-view').classList.remove('hidden');
  document.getElementById('watch-player-view').classList.add('hidden');
  
  const seriesGrid = document.getElementById('watch-series-grid');
  const standaloneGrid = document.getElementById('watch-standalone-grid');
  seriesGrid.innerHTML = '<div style="color:var(--text-dim);">Đang tải dữ liệu...</div>';
  if(standaloneGrid) standaloneGrid.innerHTML = '';
  
  try {
    let res = await api('/api/series');
    watchLibraryData = res.series || [];
    
    let standaloneEps = [];
    try {
        let pRes = await api('/api/projects');
        let projects = pRes.projects || [];
        standaloneEps = projects.filter(p => (p.final_video || (p.steps_completed && p.steps_completed.includes('render'))) && !p.series_name);
    } catch(e) {
        console.error('Error fetching standalone projects for watch UI', e);
    }

    if(document.getElementById('watch-series-count')) document.getElementById('watch-series-count').innerText = watchLibraryData.length;
    if(document.getElementById('watch-standalone-count')) document.getElementById('watch-standalone-count').innerText = standaloneEps.length;
    
    if (watchLibraryData.length === 0) {
      seriesGrid.innerHTML = '<div style="color:var(--text-dim);">Không có Phim Bộ nào.</div>';
    } else {
      seriesGrid.innerHTML = '';
      for (let s of watchLibraryData) {
        let thumbUrl = '/static/placeholder.jpg';
        let latestEp = s.episodes[0];
        if (latestEp && latestEp.thumbnail) {
          thumbUrl = '/api/project/' + latestEp.project_id + '/stream/thumbnail.jpg';
        } else if (latestEp && latestEp.youtube && latestEp.youtube.videoId) {
          thumbUrl = 'https://img.youtube.com/vi/' + latestEp.youtube.videoId + '/maxresdefault.jpg';
        }
        
        let maxEp = s.episode_max ? s.episode_max : '??';
        let rendered = s.rendered_count || 0;
        let badgeText = rendered + '/' + maxEp;
        
        let card = document.createElement('div');
        card.className = 'watch-series-card';
        card.onclick = () => openSeriesPlayer(s.series_folder);
        
        card.innerHTML = `<div class="watch-series-cover-wrapper">
            <img class="watch-series-cover" src="${thumbUrl}" onerror="this.src='/static/placeholder.jpg'">
            <div class="watch-series-badge">${badgeText}</div>
          </div>
          <div class="watch-series-info">
            <div class="watch-series-title" title="${s.series_name.replace(/"/g, '&quot;')}">${s.series_name}</div>
          </div>`;
        seriesGrid.appendChild(card);
      }
    }

    if(standaloneGrid) {
      if (standaloneEps.length === 0) {
        standaloneGrid.innerHTML = '<div style="color:var(--text-dim);">Không có Phim Lẻ nào.</div>';
      } else {
        standaloneGrid.innerHTML = '';
        standaloneEps.forEach((p, index) => {
          let thumbUrl = '/api/project/' + p.project_name + '/stream/thumbnail.jpg';
          let title = p.metadata && p.metadata.title ? p.metadata.title : p.project_name;
          
          let card = document.createElement('div');
          card.className = 'watch-series-card';
          // We can treat standalone eps directly in openSeriesPlayer by passing a mock series_folder
          // or we can reuse openSeriesPlayer by adding them dynamically to watchLibraryData, BUT ONLY for the player!
          // Actually, openSeriesPlayer looks up watchLibraryData by series_folder.
          let mockSeriesFolder = 'standalone_' + p.project_name;
          let mockSeries = {
              series_name: title,
              series_folder: mockSeriesFolder,
              episode_max: 1,
              rendered_count: 1,
              episodes: [{
                  _ep_no: 1,
                  project_id: p.project_name,
                  final_video: true,
                  thumbnail: true,
                  title: title
              }]
          };
          // Push it so openSeriesPlayer works!
          watchLibraryData.push(mockSeries);
          
          card.onclick = () => openSeriesPlayer(mockSeriesFolder);
          
          card.innerHTML = `<div class="watch-series-cover-wrapper">
              <img class="watch-series-cover" src="${thumbUrl}" onerror="this.src='/static/placeholder.jpg'">
              <div class="watch-series-badge">1/1</div>
            </div>
            <div class="watch-series-info">
              <div class="watch-series-title" title="${title.replace(/"/g, '&quot;')}">${title}</div>
            </div>`;
          standaloneGrid.appendChild(card);
        });
      }
    }
    
  } catch (err) {
    console.error(err);
    seriesGrid.innerHTML = '<div style="color:var(--error);">Lỗi khi tải thư viện: ' + err.message + '</div>';
  }
}

function openSeriesPlayer(folder) {
  if (!watchLibraryData) return;
  let series = watchLibraryData.find(s => s.series_folder === folder);
  if (!series) return;
  
  currentWatchSeries = series;
  
  document.getElementById('watch-grid-view').classList.add('hidden');
  document.getElementById('watch-player-view').classList.remove('hidden');
  document.getElementById('watch-player-title').innerText = series.series_name;
  
  const epGrid = document.getElementById('watch-episodes-grid');
  epGrid.innerHTML = '';
  document.getElementById('watch-search-ep').value = '';
  
  let sortedEps = [...series.episodes].sort((a,b) => (a._ep_no || 0) - (b._ep_no || 0));
  currentPlayableEps = sortedEps.filter(ep => ep.final_video);
  
  for (let i = 0; i < currentPlayableEps.length; i++) {
    let ep = currentPlayableEps[i];
    let btn = document.createElement('div');
    btn.className = 'watch-ep-btn ep-item-btn';
    let epNum = ep._ep_no || '?';
    btn.innerText = epNum;
    btn.setAttribute('data-index', i);
    btn.onclick = () => playEpisodeByIndex(i);
    epGrid.appendChild(btn);
  }
  
  if (currentPlayableEps.length === 0) {
    epGrid.innerHTML = '<div style="grid-column: 1/-1; color: var(--text-dim);">Chưa có tập nào được render video.</div>';
    document.getElementById('watch-video-element').src = '';
    updatePrevNextButtons();
  } else {
    let targetIndex = 0;
    if (miubonWatchProgress && miubonWatchProgress[folder]) {
      let savedIndex = miubonWatchProgress[folder].ep_index;
      if (savedIndex !== undefined && savedIndex < currentPlayableEps.length) {
        targetIndex = savedIndex;
      }
    }
    playEpisodeByIndex(targetIndex);
  }
}

function playEpisodeByIndex(index) {
  if (index < 0 || index >= currentPlayableEps.length) return;
  currentEpIndex = index;
  let ep = currentPlayableEps[index];
  
  document.querySelectorAll('.watch-ep-btn').forEach(b => {
    b.classList.toggle('active', parseInt(b.getAttribute('data-index')) === index);
  });
  
  let videoEl = document.getElementById('watch-video-element');
  videoEl.src = '/api/project/' + ep.project_id + '/stream/preview?v=faststart';
  
  // Seek to saved time if applicable
  videoEl.onloadedmetadata = () => {
    if (miubonWatchProgress && currentWatchSeries) {
      let folder = currentWatchSeries.series_folder;
      if (miubonWatchProgress[folder] && miubonWatchProgress[folder].ep_index === index) {
        let st = miubonWatchProgress[folder].time;
        if (st && st > 0) {
          videoEl.currentTime = st;
        }
      }
    }
    videoEl.onloadedmetadata = null; // Clear handler
  };

  videoEl.play().catch(e => console.log('Auto-play blocked:', e));

  updatePrevNextButtons();
}

function playPrevEpisode() {
  playEpisodeByIndex(currentEpIndex - 1);
}

function playNextEpisode() {
  playEpisodeByIndex(currentEpIndex + 1);
}

function updatePrevNextButtons() {
  const btnPrev = document.getElementById('watch-btn-prev');
  const btnNext = document.getElementById('watch-btn-next');
  
  if (!btnPrev || !btnNext) return;
  
  if (currentEpIndex <= 0) {
    btnPrev.disabled = true;
  } else {
    btnPrev.disabled = false;
  }
  
  if (currentEpIndex >= currentPlayableEps.length - 1 || currentEpIndex === -1) {
    btnNext.disabled = true;
  } else {
    btnNext.disabled = false;
  }
}

function filterEpisodes() {
  let q = document.getElementById('watch-search-ep').value.toLowerCase();
  document.querySelectorAll('.ep-item-btn').forEach(b => {
    let text = b.innerText.toLowerCase();
    b.style.display = text.includes(q) ? 'block' : 'none';
  });
}

function closeWatchPlayer() {
  let videoEl = document.getElementById('watch-video-element');
  videoEl.pause();
  videoEl.src = '';
  currentWatchSeries = null;
  currentPlayableEps = [];
  currentEpIndex = -1;
  
  document.getElementById('watch-player-view').classList.add('hidden');
  document.getElementById('watch-grid-view').classList.remove('hidden');
} 

function switchWatchSubTab(tabId) {
  document.querySelectorAll('.watch-sub-tab').forEach(t => t.classList.remove('active'));
  document.querySelector('.watch-sub-tab[data-subtab="' + tabId + '"]').classList.add('active');
  document.querySelectorAll('.watch-sub-content').forEach(c => c.classList.add('hidden'));
  document.getElementById(tabId).classList.remove('hidden');
}



// Global GDrive Watchdog
setInterval(async () => {
  try {
    const d = await api('/api/gdrive/status');
    const el = document.getElementById('gdrive-sync-status');
    if (d && d.active && d.job) {
      if (el && !el.textContent.includes('Starting')) {
        el.textContent = `[GDrive Watchdog] ${d.job.kind} (${d.job.status}): ${d.job.message || ''}`;
      }
    } else {
      if (el && el.textContent.includes('[GDrive Watchdog]')) {
        el.textContent = '';
      }
    }
  } catch (e) {}
}, 5000);

async function fetchWebAIModels() {
  const urlBase = document.getElementById('cfg-webai_url')?.value || '';
  if (!urlBase) {
    toast('Vui lòng nhập WebAI URL trước!', 'warning');
    return;
  }
  const btn = event.currentTarget;
  const oldText = btn.textContent;
  btn.textContent = '⏳...';
  btn.disabled = true;
  try {
    const res = await api(`/api/proxy/models?url=${encodeURIComponent(urlBase)}`);
    if (res.error) throw new Error(res.error);
    const models = res.data || [];
    const list = document.getElementById('webai-model-list');
    list.innerHTML = '';
    models.forEach(m => {
      const opt = document.createElement('option');
      opt.value = m.id;
      list.appendChild(opt);
    });
    toast(`Lấy thành công ${models.length} models từ WebAI`);
    const input = document.getElementById('cfg-webai_model');
    if (models.length > 0) input.focus();
  } catch (e) {
    toast('Lỗi khi lấy models: ' + e.message, 'error');
  } finally {
    btn.textContent = oldText;
    btn.disabled = false;
  }
}

// ═══ SERIES GLOSSARY LOGIC ═══
let currentGlossaryFolder = '';

async function openSeriesGlossaryModal(folder, name) {
  currentGlossaryFolder = folder;
  document.getElementById('glossary-series-name').innerText = name || folder;
  const tbody = document.getElementById('glossary-table-body');
  tbody.innerHTML = '<tr><td colspan="3" style="text-align:center;color:var(--text-dim)">Đang tải...</td></tr>';
  document.getElementById('series-glossary-modal').classList.remove('hidden');

  try {
    const res = await api(`/api/series/${encodeURIComponent(folder)}/glossary`);
    const glossary = res.glossary || {};
    tbody.innerHTML = '';
    
    let count = 0;
    for (const [orig, trans] of Object.entries(glossary)) {
      addGlossaryRow(orig, trans);
      count++;
    }
    
    if (count === 0) {
      addGlossaryRow('', '');
    }
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="3" style="color:var(--error);text-align:center">Lỗi: ${e.message}</td></tr>`;
  }
}

function closeSeriesGlossaryModal() {
  document.getElementById('series-glossary-modal').classList.add('hidden');
  currentGlossaryFolder = '';
}

function addGlossaryRow(orig = '', trans = '', isAiSuggested = false) {
  const tbody = document.getElementById('glossary-table-body');
  const tr = document.createElement('tr');
  if (isAiSuggested) {
    tr.style.backgroundColor = 'rgba(255, 215, 0, 0.1)';
  }
  tr.innerHTML = `
    <td style="padding: 4px;"><input type="text" class="glossary-orig" value="${safeStr(orig)}" placeholder="Ví dụ: Xiaosuke" style="width: 100%;"></td>
    <td style="padding: 4px;"><input type="text" class="glossary-trans" value="${safeStr(trans)}" placeholder="Ví dụ: Tiểu Túc" style="width: 100%;"></td>
    <td style="padding: 4px; text-align: center;"><button class="btn btn-danger btn-sm" onclick="this.closest('tr').remove()" style="padding: 4px 8px;">✕</button></td>
  `;
  tbody.appendChild(tr);
}

async function saveSeriesGlossary() {
  if (!currentGlossaryFolder) return;
  
  const rows = document.querySelectorAll('#glossary-table-body tr');
  const newGlossary = {};
  
  rows.forEach(tr => {
    const orig = tr.querySelector('.glossary-orig')?.value?.trim();
    const trans = tr.querySelector('.glossary-trans')?.value?.trim();
    if (orig && trans) {
      newGlossary[orig] = trans;
    }
  });

  try {
    const res = await api(`/api/series/${encodeURIComponent(currentGlossaryFolder)}/glossary`, {
      method: 'POST',
      body: { glossary: newGlossary }
    });
    
    if (res.ok) {
      toast(`Đã lưu ${Object.keys(newGlossary).length} từ vựng!`, 'success');
      closeSeriesGlossaryModal();
    } else {
      toast(res.error || 'Lỗi lưu từ điển', 'error');
    }
  } catch (e) {
    toast(`Lỗi: ${e.message}`, 'error');
  }
}

async function extractGlossaryAI() {
  if (!currentGlossaryFolder) return;
  
  const btn = document.getElementById('btn-extract-glossary');
  const oldText = btn.innerText;
  btn.innerText = '⏳ Đang nhờ AI quét phụ đề...';
  btn.disabled = true;
  
  try {
    const res = await api(`/api/series/${encodeURIComponent(currentGlossaryFolder)}/glossary/extract`, {
      method: 'POST',
      timeoutMs: 300000 // 5 mins max
    });
    
    if (res.ok) {
      const extracted = res.extracted || [];
      if (extracted.length === 0) {
        toast('AI không tìm thấy tên riêng nào mới.', 'info');
      } else {
        // Collect current origins to avoid duplicates
        const currentOrigs = Array.from(document.querySelectorAll('.glossary-orig')).map(i => i.value.trim());
        let addedCount = 0;
        
        extracted.forEach(item => {
            if (item.orig && item.trans && !currentOrigs.includes(item.orig)) {
                addGlossaryRow(item.orig, item.trans, true);
                currentOrigs.push(item.orig);
                addedCount++;
            }
        });
        
        if (addedCount > 0) {
            toast(`AI đã gợi ý thêm ${addedCount} từ vựng! (Tô màu vàng)`, 'success');
            // Remove empty row if any
            const firstOrig = document.querySelector('.glossary-orig');
            if (firstOrig && !firstOrig.value) {
                firstOrig.closest('tr').remove();
            }
        } else {
            toast('Các từ AI gợi ý đều đã có sẵn trong bảng.', 'info');
        }
      }
    } else {
      toast(res.error || 'Lỗi trích xuất từ vựng', 'error');
    }
  } catch (e) {
    toast(`Lỗi: ${e.message}`, 'error');
  } finally {
    btn.innerText = oldText;
    btn.disabled = false;
  }
}


// ═══ GLOSSARY MANAGEMENT ═══
async function loadGlossary() {
  try {
    const res = await api('/api/series');
    if (!res || res.error) throw new Error(res?.error || 'Failed to load series');
    
    const series = res.series || [];
    const sel = document.getElementById('glos-series-select');
    if (!sel) return;
    
    const currentVal = sel.value;
    sel.innerHTML = '<option value="">-- Vui lòng chọn Series --</option>' + 
      series.map(s => `<option value="${safeStr(s.folder)}">${safeStr(s.title || s.folder)}</option>`).join('');
    
    if (currentVal && series.find(s => s.folder === currentVal)) {
      sel.value = currentVal;
    }
  } catch (e) {
    console.error('loadGlossary series fetch error:', e);
  }
}

async function loadGlossaryForSelectedSeries() {
  const sel = document.getElementById('glos-series-select');
  const ws = document.getElementById('glos-workspace');
  if (!sel || !ws) return;
  
  const folder = sel.value;
  if (!folder) {
    ws.classList.add('hidden');
    return;
  }
  
  ws.classList.remove('hidden');
  const tbody = document.getElementById('glossary-tbody');
  tbody.innerHTML = `<tr><td colspan="3" style="padding:15px;text-align:center;color:var(--text-dim)">Đang tải từ điển...</td></tr>`;
  
  try {
    const d = await api(`/api/series/${encodeURIComponent(folder)}/glossary`);
    window.glossaryData = d.glossary || {};
    renderGlossary();
  } catch (e) {
    toast('Lỗi tải từ điển: ' + e.message, 'error');
  }
}

function renderGlossary(filterText = '') {
  const tbody = document.getElementById('glossary-tbody');
  if (!tbody || !window.glossaryData) return;
  
  let entries = Object.entries(window.glossaryData);
  if (filterText) {
    filterText = filterText.toLowerCase();
    entries = entries.filter(([src, tgt]) => src.toLowerCase().includes(filterText) || tgt.toLowerCase().includes(filterText));
  }
  
  if (entries.length === 0) {
    tbody.innerHTML = `<tr><td colspan="3" style="padding:15px;text-align:center;color:var(--text-dim)">Không có từ vựng nào.</td></tr>`;
    return;
  }
  
  tbody.innerHTML = entries.map(([src, tgt]) => `
    <tr style="border-bottom:1px solid rgba(255,255,255,0.05)">
      <td style="padding:10px; font-weight:bold; color:var(--accent)">${safeHtml(src)}</td>
      <td style="padding:10px;">${safeHtml(tgt)}</td>
      <td style="padding:10px; text-align:center;">
        <button class="btn btn-danger btn-sm" onclick="deleteGlossaryItem('${safeHtml(src).replace(/'/g, "\\'")}')">Xóa</button>
      </td>
    </tr>
  `).join('');
}

function filterGlossary() {
  const term = document.getElementById('glos-search').value.trim();
  renderGlossary(term);
}

async function addGlossaryItem() {
  const sel = document.getElementById('glos-series-select');
  const srcInput = document.getElementById('glos-source');
  const tgtInput = document.getElementById('glos-target');
  if (!sel || !sel.value) return toast('Vui lòng chọn Series trước', 'error');
  
  const src = srcInput.value.trim();
  const tgt = tgtInput.value.trim();
  const folder = sel.value;
  
  if (!src || !tgt) return toast('Vui lòng nhập cả tiếng Trung và tiếng Việt', 'error');
  
  try {
    if (!window.glossaryData) window.glossaryData = {};
    window.glossaryData[src] = tgt;
    
    const d = await api(`/api/series/${encodeURIComponent(folder)}/glossary`, { 
      method: 'POST', 
      body: { glossary: window.glossaryData } 
    });
    
    if (d.ok) {
      toast('Đã lưu vào từ điển!', 'success');
      srcInput.value = '';
      tgtInput.value = '';
      loadGlossaryForSelectedSeries();
    } else {
      toast('Lỗi: ' + d.error, 'error');
    }
  } catch (e) {
    toast('Lỗi: ' + e.message, 'error');
  }
}

async function deleteGlossaryItem(src) {
  const sel = document.getElementById('glos-series-select');
  if (!sel || !sel.value) return;
  const folder = sel.value;
  
  if (!confirm(`Bạn có chắc muốn xóa từ "${src}" khỏi từ điển không?`)) return;
  
  try {
    if (window.glossaryData && window.glossaryData[src]) {
      delete window.glossaryData[src];
    }
    
    const d = await api(`/api/series/${encodeURIComponent(folder)}/glossary`, { 
      method: 'POST', 
      body: { glossary: window.glossaryData } 
    });
    
    if (d.ok) {
      toast('Đã xóa thành công', 'success');
      loadGlossaryForSelectedSeries();
    } else {
      toast('Lỗi: ' + d.error, 'error');
    }
  } catch (e) {
    toast('Lỗi: ' + e.message, 'error');
  }
}









async function loadScrapeHistory() {
  const box = document.getElementById('scrape-history');
  if (!box) return;
  box.innerHTML = '<div style="color:var(--text-dim);">Đang tải lịch sử...</div>';
  try {
    const data = await api('/api/douyin/scrape/history');
    // data is a list
    if (!data || data.length === 0) {
      box.innerHTML = '<div style="color:var(--text-dim);">Không có lịch sử quét nào.</div>';
      return;
    }
    
    // Sort by start_time descending
    data.sort((a, b) => (b.start_time || 0) - (a.start_time || 0));

    let html = '';
    data.forEach(job => {
      const ts = new Date((job.start_time || 0) * 1000).toLocaleString('vi-VN');
      const author = job.author || job.url || 'Unknown';
      const count = job.total_videos || 0;
      let statusHtml = '';
      if (job.status === 'done') statusHtml = '<span class="badge badge-success" style="padding: 4px 8px; border-radius: 4px;">Done</span>';
      else if (job.status === 'error') statusHtml = '<span class="badge badge-error" style="padding: 4px 8px; border-radius: 4px;">Error</span>';
      else statusHtml = '<span class="badge badge-info" style="padding: 4px 8px; border-radius: 4px;">' + job.status + '</span>';
      
      html += `
        <div style="padding:12px; border-bottom:1px solid var(--border); display:flex; justify-content:space-between; align-items:center; transition: background 0.2s;">
          <div style="flex:1">
            <div style="font-weight:bold; font-size: 1.05rem; margin-bottom: 4px; color: var(--accent);">${author}</div>
            <div style="font-size:0.85rem; color:var(--text-dim); display:flex; align-items:center; gap:10px;">
                <span>🕒 ${ts}</span> 
                <span>🎞️ ${count} videos</span> 
                ${statusHtml}
            </div>
          </div>
          <div style="display:flex; gap:8px;">
            <button class="btn btn-sm btn-outline" onclick="deleteScrapeJob('${job.job_id}')" style="color:var(--error); border-color:var(--error);">🗑 Xóa</button>
            <button class="btn btn-sm btn-primary" onclick="resumeScrapeJob('${job.job_id}', '${job.status}')">▶ Xem / Resume</button>
          </div>
        </div>
      `;
    });
    box.innerHTML = html;
  } catch (e) {
    box.innerHTML = '<div style="color:var(--error);">Lỗi: ' + e.message + '</div>';
  }
}

async function deleteScrapeJob(jobId) {
  if (!confirm('Bạn có chắc muốn xóa lịch sử này?')) return;
  try {
    const res = await api(`/api/douyin/scrape/history/${jobId}`, { method: 'DELETE' });
    if (res.ok) {
      toast('Đã xóa lịch sử!');
      loadScrapeHistory();
    } else {
      toast('Lỗi: ' + (res.error || 'Unknown'), 'error');
    }
  } catch(e) { toast('Lỗi: ' + e.message, 'error'); }
}

async function clearScrapeHistory() {
  if (!confirm('Bạn có chắc muốn XÓA TOÀN BỘ lịch sử quét? Không thể hoàn tác!')) return;
  try {
    const res = await api('/api/douyin/scrape/history', { method: 'DELETE' });
    if (res.ok) {
      toast('Đã xóa toàn bộ lịch sử!');
      loadScrapeHistory();
    } else {
      toast('Lỗi: ' + (res.error || 'Unknown'), 'error');
    }
  } catch(e) { toast('Lỗi: ' + e.message, 'error'); }
}

async function resumeScrapeJob(jobId, status) {
  const btn = document.getElementById('btn-scrape');
  if(btn) btn.disabled = true;
  document.getElementById('scrape-progress').classList.remove('hidden');
  document.getElementById('scrape-results').classList.add('hidden');
  document.getElementById('scrape-logs').innerHTML = '';
  scrapeSeriesGroups = [];
  scrapeSeriesSelected = new Set();
  const seriesBox = document.getElementById('scrape-series-results');
  if (seriesBox) {
    seriesBox.classList.add('hidden');
    seriesBox.innerHTML = '';
  }
  
  toast('Loading job data...');
  
  if (status !== 'running') {
    const s = await api(`/api/douyin/scrape/${jobId}`);
    const logBox = document.getElementById('scrape-logs');
    logBox.innerHTML = (s.logs || []).map(l => `<div class="log-line log-default"><span class="log-msg">${l}</span></div>`).join('');
    logBox.scrollTop = logBox.scrollHeight;
    const badge = document.getElementById('scrape-status-badge');
    
    if (s.status === 'done') {
      badge.className = 'badge badge-success'; badge.textContent = 'DONE';
      if (s.result) {
        scrapeVideos = s.result.videos || [];
        renderScrapeResults(s.result);
      }
      toast('Loaded completed job.');
    } else {
      badge.className = 'badge badge-error'; badge.textContent = 'ERROR';
      toast('Job failed: ' + (s.error || ''), 'error');
    }
    if(btn) btn.disabled = false;
    return;
  }
  
  const pollId = setInterval(async () => {
    try {
      const s = await api(`/api/douyin/scrape/${jobId}`);
      const logBox = document.getElementById('scrape-logs');
      logBox.innerHTML = (s.logs || []).map(l => `<div class="log-line log-default"><span class="log-msg">${l}</span></div>`).join('');
      logBox.scrollTop = logBox.scrollHeight;
      const badge = document.getElementById('scrape-status-badge');
      
      if (s.status === 'done') {
        clearInterval(pollId);
        badge.className = 'badge badge-success'; badge.textContent = 'DONE';
        if(btn) btn.disabled = false;
        if (s.result) {
          scrapeVideos = s.result.videos || [];
          renderScrapeResults(s.result);
          setTimeout(() => { groupSeriesByAI(); }, 1500);
        }
        toast(`Found ${scrapeVideos.length} videos!`);
        loadScrapeHistory();
      } else if (s.status === 'error') {
        clearInterval(pollId);
        badge.className = 'badge badge-error'; badge.textContent = 'ERROR';
        if(btn) btn.disabled = false;
        toast('Scrape failed: ' + (s.error || ''), 'error');
        loadScrapeHistory();
      }
    } catch(e) {
      clearInterval(pollId);
      if(btn) btn.disabled = false;
      toast('Error polling: ' + e.message, 'error');
    }
  }, 3000);
}

async function resumeSavedSeriesQueue(folder) {
    if (!confirm(`Bạn có muốn đẩy các tập chưa làm của Series [${folder}] vào Hàng đợi không?`)) return;
    try {
        const res = await api('/api/series');
        const watchLibraryData = res.series || [];
        const s = watchLibraryData.find(x => x.series_folder === folder);
        if (!s || !s.reg_info || !s.reg_info.urls) return toast('Không tìm thấy danh sách link đã lưu của series này!', 'error');
        
        let urls = s.reg_info.urls;
        // filter out completed
        if (scrapeCompletedUrls instanceof Set) {
            urls = urls.filter(u => !scrapeCompletedUrls.has(u));
        } else {
            // try fetching it
            const doneRes = await api('/api/projects/completed-urls');
            if (doneRes.ok && Array.isArray(doneRes.completed)) {
                scrapeCompletedUrls = new Set(doneRes.completed);
                urls = urls.filter(u => !scrapeCompletedUrls.has(u));
            }
        }
        
        if (!urls.length) return toast('Tất cả các tập của Series này đã hoàn thành!', 'error');
        
        enqueueUrlsToPipelineInput(urls, `series:${folder}`, {});
        await startBatchPipeline();
        toast(`Đã thêm ${urls.length} tập vào Hàng đợi!`);
    } catch(e) {
        toast('Lỗi: ' + e.message, 'error');
    }
}

async function restartServer() {
    if(!confirm("Bạn có chắc muốn khởi động lại server không?")) return;
    try {
        let res = await fetch('/api/restart', {method: 'POST'});
        let data = await res.json();
        toast("Đang khởi động lại server...", "info");
        setTimeout(() => window.location.reload(), 3000);
    } catch(e) {
        toast('Lỗi: ' + e.message, 'error');
    }
}

async function shutdownServer() {
    if(!confirm("Bạn có chắc muốn tắt server không?")) return;
    try {
        let res = await fetch('/api/shutdown', {method: 'POST'});
        let data = await res.json();
        toast("Đang tắt server...", "info");
    } catch(e) {
        toast('Lỗi: ' + e.message, 'error');
    }
}

// ══════════════════════════════════════════════════════════════
// VPN IP Rotation Controls
// ══════════════════════════════════════════════════════════════
let vpnPollTimer = null;

async function vpnToggle(enabled) {
  const toggle = document.getElementById('vpn-toggle');
  const btn = document.getElementById('vpn-btn-rotate');
  try {
    if (enabled) {
      const interval = parseInt(document.getElementById('vpn-interval').value) || 10;
      const d = await api('/api/vpn/start', { method: 'POST', body: { interval_minutes: interval } });
      if (d.error) {
        toast(d.error, 'error');
        toggle.checked = false;
        return;
      }
      toast(`VPN rotation started! Interval: ${interval} min, ${d.total_configs} servers`);
      btn.disabled = false;
      updateVpnToggleUI(true);
    } else {
      await api('/api/vpn/stop', { method: 'POST' });
      toast('VPN rotation stopping...');
      btn.disabled = true;
      updateVpnToggleUI(false);
    }
  } catch (e) {
    toast('VPN error: ' + e.message, 'error');
    toggle.checked = !enabled;
  }
}

function updateVpnToggleUI(enabled) {
  const text = document.getElementById('vpn-toggle-text');
  const sub = document.getElementById('vpn-toggle-sub');
  if (text) {
    text.textContent = enabled ? 'VPN BẬT' : 'VPN TẮT';
    text.style.color = enabled ? '#00ff88' : 'var(--text-light)';
  }
  if (sub) sub.textContent = enabled ? 'Đang xoay vòng IP tự động' : 'Bấm để bật xoay vòng IP';
}

async function vpnRotateNow() {
  try {
    const d = await api('/api/vpn/rotate-now', { method: 'POST' });
    if (d.error) return toast(d.error, 'error');
    toast('Đang đổi IP...', 'info');
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

async function vpnCheckIp() {
  try {
    const d = await api('/api/vpn/check-ip');
    const el = document.getElementById('vpn-current-ip');
    if (el) el.textContent = d.ip || 'N/A';
    toast('IP hiện tại: ' + (d.ip || 'N/A'), 'info');
  } catch (e) { toast('Error: ' + e.message, 'error'); }
}

async function pollVpnStatus() {
  try {
    const d = await api('/api/vpn/status');
    // Update toggle
    const toggle = document.getElementById('vpn-toggle');
    if (toggle && toggle.checked !== d.enabled) {
      toggle.checked = d.enabled;
      updateVpnToggleUI(d.enabled);
    }
    const btn = document.getElementById('vpn-btn-rotate');
    if (btn) btn.disabled = !d.enabled;

    // Update stats
    const ip = document.getElementById('vpn-current-ip');
    const server = document.getElementById('vpn-current-server');
    const next = document.getElementById('vpn-next-rotate');
    const count = document.getElementById('vpn-rotate-count');
    const total = document.getElementById('vpn-total-servers');
    if (ip) ip.textContent = d.current_ip || '—';
    if (server) server.textContent = d.current_server || '—';
    if (next) next.textContent = d.next_rotate_at || '—';
    if (count) count.textContent = d.rotate_count || 0;
    if (total) total.textContent = d.total_servers || 0;

    // Update logs
    const logBox = document.getElementById('vpn-log-box');
    if (logBox && d.logs && d.logs.length) {
      const wasAtBottom = logBox.scrollTop + logBox.clientHeight >= logBox.scrollHeight - 30;
      logBox.innerHTML = d.logs.map(l => {
        let cls = '';
        if (l.includes('CONNECTED') || l.includes('THANH CONG')) cls = 'style="color:#00ff88"';
        else if (l.includes('ERROR') || l.includes('WARNING')) cls = 'style="color:#ff6b6b"';
        else if (l.includes('Manual rotate') || l.includes('Stopping') || l.includes('Watchdog')) cls = 'style="color:#ffd93d"';
        return `<div ${cls}>${l.replace(/</g,'&lt;')}</div>`;
      }).join('');
      if (wasAtBottom) logBox.scrollTop = logBox.scrollHeight;
    }

    // Also poll watchdog
    pollWatchdogStatus();
  } catch (e) { console.warn('VPN poll error', e); }
}

// ══════════════════════════════════════════════════════════════
// IP Watchdog Controls
// ══════════════════════════════════════════════════════════════

async function watchdogToggle(enabled) {
  const toggle = document.getElementById('watchdog-toggle');
  try {
    if (enabled) {
      const defaultIp = document.getElementById('watchdog-default-ip').value.trim();
      if (!defaultIp) {
        toast('Cần nhập IP mặc định trước!', 'error');
        toggle.checked = false;
        return;
      }
      const triggerMin = parseInt(document.getElementById('watchdog-trigger-min').value) || 15;
      const d = await api('/api/vpn/watchdog', { method: 'POST', body: { action: 'start', default_ip: defaultIp, trigger_minutes: triggerMin } });
      if (d.error) {
        toast(d.error, 'error');
        toggle.checked = false;
        return;
      }
      toast(`Watchdog đã bật! IP gốc: ${defaultIp}, trigger: ${triggerMin} phút`);
      updateWatchdogToggleUI(true);
    } else {
      await api('/api/vpn/watchdog', { method: 'POST', body: { action: 'stop' } });
      toast('Watchdog đã tắt');
      updateWatchdogToggleUI(false);
    }
  } catch (e) {
    toast('Watchdog error: ' + e.message, 'error');
    toggle.checked = !enabled;
  }
}

function updateWatchdogToggleUI(enabled) {
  const text = document.getElementById('watchdog-toggle-text');
  const sub = document.getElementById('watchdog-toggle-sub');
  const badge = document.getElementById('watchdog-status-badge');
  if (text) {
    text.textContent = enabled ? 'Watchdog BẬT' : 'Watchdog TẮT';
    text.style.color = enabled ? '#ffd93d' : 'var(--text)';
  }
  if (sub) sub.textContent = enabled ? 'Đang giám sát IP...' : 'Bấm để bật';
  if (badge) {
    badge.textContent = enabled ? 'ĐANG CHẠY' : 'TẮT';
    badge.className = enabled ? 'badge badge-warning' : 'badge badge-error';
  }
}

async function pollWatchdogStatus() {
  try {
    const d = await api('/api/vpn/watchdog');
    const toggle = document.getElementById('watchdog-toggle');
    if (toggle && toggle.checked !== d.enabled) {
      toggle.checked = d.enabled;
      updateWatchdogToggleUI(d.enabled);
    }

    // Populate default IP if we have it from server and field is empty
    const ipInput = document.getElementById('watchdog-default-ip');
    if (ipInput && !ipInput.value && d.default_ip) ipInput.value = d.default_ip;

    // Update stats
    const lastCheck = document.getElementById('watchdog-last-check');
    const lastIp = document.getElementById('watchdog-last-ip');
    const elapsed = document.getElementById('watchdog-elapsed');

    if (lastCheck) lastCheck.textContent = d.last_check || '—';
    if (lastIp) lastIp.textContent = d.last_ip || '—';
    if (elapsed) {
      if (d.same_ip_elapsed_sec > 0) {
        const min = Math.floor(d.same_ip_elapsed_sec / 60);
        const sec = d.same_ip_elapsed_sec % 60;
        elapsed.textContent = `${min}p ${sec}s`;
        elapsed.style.color = min >= 10 ? '#ff6b6b' : '#ffd93d';
      } else {
        elapsed.textContent = '—';
        elapsed.style.color = '';
      }
    }
  } catch (e) { /* silent */ }
}

