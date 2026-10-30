/// The page a phone opens. Live picture via MJPEG <img>, state polled from /state,
/// every button is a GET to /cmd.
enum PhonePage {
    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <title>Sony Log Monitor</title>
    <style>
      :root { --bg:#000; --panel:#141414; --chip:#262626; --text:#f2f2f2; --muted:#8a8a8a;
              --accent:#4c8dff; --salmon:#fa8072; --rec:#ff3b30; }
      * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
      html, body { margin:0; background:var(--bg); color:var(--text);
                   font:15px -apple-system, system-ui, sans-serif; }
      body { padding:env(safe-area-inset-top) 0 env(safe-area-inset-bottom); }
      .view { position:relative; width:100%; background:#000; aspect-ratio:16/9; }
      .view img { width:100%; height:100%; object-fit:contain; display:block; }
      .badge { position:absolute; top:8px; left:8px; padding:3px 8px; border-radius:6px;
               background:rgba(0,0,0,.55); font-size:12px; color:var(--muted); }
      .badge.rec { color:#fff; background:var(--rec); }
      .bar { display:flex; gap:8px; padding:10px 12px; overflow-x:auto; }
      .chip { flex:1 0 auto; min-height:44px; padding:0 14px; border:0; border-radius:22px;
              background:var(--chip); color:var(--text); font-weight:600; font-size:15px; }
      .chip.on { background:var(--accent); color:#000; }
      .chip.skin.on { background:var(--salmon); }
      .rec-row { display:flex; align-items:center; gap:14px; padding:4px 12px 12px; }
      .rec-btn { min-height:56px; flex:1; border:0; border-radius:28px; background:var(--chip);
                 color:#fff; font-size:18px; font-weight:700; display:flex; align-items:center;
                 justify-content:center; gap:10px; }
      .rec-btn .dot { width:18px; height:18px; border-radius:9px; background:var(--rec); }
      .rec-btn.recording .dot { border-radius:4px; }
      .rec-btn.recording { background:#3a1110; }
      .time { font:600 20px ui-monospace, Menlo, monospace; color:var(--muted); min-width:96px; text-align:right; }
      .time.recording { color:var(--rec); }
      .settings { display:grid; grid-template-columns:1fr 1fr; gap:8px; padding:0 12px 16px; }
      label { display:flex; flex-direction:column; gap:4px; background:var(--panel);
              border-radius:12px; padding:8px 10px; font-size:12px; color:var(--muted); }
      select { font-size:17px; color:var(--text); background:transparent; border:0; padding:2px 0;
               -webkit-appearance:none; appearance:none; width:100%; }
      select:disabled { color:var(--muted); }
      .status { padding:0 12px 16px; font-size:12px; color:var(--muted); }
    </style>
    </head>
    <body>
      <div class="view">
        <img id="live" src="/stream" alt="Live view">
        <div class="badge" id="badge">Connecting…</div>
      </div>
      <div class="bar">
        <button class="chip" data-t="view709">Rec.709</button>
        <button class="chip" data-t="zebra">Zebra</button>
        <button class="chip" data-t="falseColor">False Color</button>
        <button class="chip skin" data-t="skin">Skin</button>
      </div>
      <div class="rec-row">
        <button class="rec-btn" id="rec"><span class="dot"></span><span id="recLabel">Record</span></button>
        <div class="time" id="time">00:00:00</div>
      </div>
      <div class="settings" id="settings"></div>
      <div class="status" id="status"></div>
    <script>
      const $ = (id) => document.getElementById(id);
      const cmd = (params) => fetch('/cmd?' + new URLSearchParams(params)).then(refresh).catch(() => {});
      let editing = null;

      document.querySelectorAll('[data-t]').forEach((b) =>
        b.addEventListener('click', () => cmd({ op: 'toggle', name: b.dataset.t })));
      $('rec').addEventListener('click', () => cmd({ op: 'record' }));

      // The MJPEG stream can stall when the phone sleeps or Wi-Fi blips; reattach.
      const live = $('live');
      live.addEventListener('error', () => setTimeout(() => { live.src = '/stream?' + Date.now(); }, 1000));
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden) live.src = '/stream?' + Date.now();
      });

      function fmt(s) {
        const p = (n) => String(n).padStart(2, '0');
        return p(Math.floor(s / 3600)) + ':' + p(Math.floor(s / 60) % 60) + ':' + p(s % 60);
      }

      function renderSettings(list) {
        const box = $('settings');
        list.forEach((s) => {
          let sel = box.querySelector('select[data-id="' + s.id + '"]');
          if (!sel) {
            const label = document.createElement('label');
            label.textContent = s.id;
            sel = document.createElement('select');
            sel.dataset.id = s.id;
            sel.addEventListener('focus', () => { editing = s.id; });
            sel.addEventListener('blur', () => { editing = null; });
            sel.addEventListener('change', () => { editing = null; cmd({ op: 'set', id: s.id, value: sel.value }); });
            label.appendChild(sel);
            box.appendChild(label);
          }
          if (editing === s.id) return;  // don't yank the picker while it's open
          const opts = s.options.join('\n');
          if (sel.dataset.opts !== opts) {
            sel.innerHTML = '';
            s.options.forEach((o) => sel.add(new Option(o, o)));
            sel.dataset.opts = opts;
          }
          sel.value = s.value;
          sel.disabled = !s.writable;
        });
      }

      async function refresh() {
        try {
          const s = await (await fetch('/state')).json();
          document.querySelectorAll('[data-t]').forEach((b) => b.classList.toggle('on', !!s[b.dataset.t]));
          $('rec').classList.toggle('recording', s.recording);
          $('recLabel').textContent = s.recording ? 'Stop' : 'Record';
          $('time').textContent = fmt(s.elapsed || 0);
          $('time').classList.toggle('recording', s.recording);
          const badge = $('badge');
          badge.textContent = s.recording ? '● REC' : (s.connected ? (s.view709 ? 'Rec.709' : 'Log') : 'Camera not connected');
          badge.classList.toggle('rec', s.recording);
          $('status').textContent = s.status || '';
          renderSettings(s.settings || []);
        } catch (e) {
          $('badge').textContent = 'Mac app not reachable';
        }
      }
      refresh();
      setInterval(refresh, 800);
    </script>
    </body>
    </html>
    """#
}
