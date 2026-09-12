rm setup.sh
cat > setup.sh << 'EOF'
#!/usr/bin/env bash
set -e

echo "=== [1/7] Applying System & Low-Latency Network Tweaks ==="
mkdir -p /etc/apt/preferences.d
cat > /etc/apt/preferences.d/no-connman << 'CAT_PIN'
Package: connman connman-vpn
Pin: release *
Pin-Priority: -1
CAT_PIN
systemctl mask connman 2>/dev/null || true
export DEBIAN_FRONTEND=noninteractive

# Optimize network sockets for low-latency interactive streaming
sysctl -w net.ipv4.tcp_nodelay=1 2>/dev/null || true
sysctl -w net.core.rmem_max=16777216 2>/dev/null || true
sysctl -w net.core.wmem_max=16777216 2>/dev/null || true

echo "=== [2/7] Ensuring Core Dependencies ==="
apt-get update -y
apt-get install -y --no-install-recommends \
  openbox obconf tint2 lxpanel pcmanfm \
  tigervnc-standalone-server tigervnc-common \
  websockify nginx aria2 pulseaudio dbus-x11 \
  x11-xserver-utils git curl wget ca-certificates jq unzip

if ! command -v dufs >/dev/null 2>&1; then
  curl -fsSL https://github.com/sigoden/dufs/releases/download/v0.43.0/dufs-v0.43.0-x86_64-unknown-linux-musl.tar.gz | tar -xz -C /usr/local/bin
  chmod +x /usr/local/bin/dufs
fi

echo "=== [3/7] Verifying RFB Engine Bundle ==="
mkdir -p /var/www/jiopc /root/Downloads

if [ ! -f /var/www/jiopc/rfb.bundle.js ] || [ $(stat -c%s /var/www/jiopc/rfb.bundle.js) -lt 50000 ]; then
  rm -rf /tmp/novnc_src
  git clone --depth 1 https://github.com/novnc/noVNC.git /tmp/novnc_src
  cat > /tmp/novnc_src/entry.js << 'CAT_ENTRY'
import RFB from './core/rfb.js';
if (typeof window !== 'undefined') { window.RFB = RFB; }
export default RFB;
CAT_ENTRY
  npx esbuild /tmp/novnc_src/entry.js --bundle --minify --format=iife --global-name=RFBRaw --outfile=/var/www/jiopc/rfb.bundle.js
  echo ';if(typeof window!=="undefined"){window.RFB=(window.RFBRaw&&window.RFBRaw.default)?window.RFBRaw.default:(window.RFBRaw||window.RFB);}' >> /var/www/jiopc/rfb.bundle.js
fi

echo "=== [4/7] Deploying LinuxPC High-Performance Portal ==="
cat > /var/www/jiopc/index.html << 'CAT_INDEX'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>LinuxPC Cloud Desktop</title>
  <script src="/rfb.bundle.js"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
    body, html { width: 100%; height: 100%; overflow: hidden; background: #0b1120; color: #f8fafc; }
    
    #portal-view {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      width: 100%;
      height: 100%;
      background: radial-gradient(circle at center, #1e293b 0%, #0b1120 100%);
      padding: 24px;
      text-align: center;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 14px;
      border-radius: 9999px;
      background: rgba(16, 185, 129, 0.15);
      border: 1px solid rgba(16, 185, 129, 0.3);
      color: #34d399;
      font-size: 13px;
      font-weight: 600;
      margin-bottom: 20px;
    }
    .pulse-dot { width: 8px; height: 8px; border-radius: 50%; background: #10b981; box-shadow: 0 0 10px #10b981; }
    .hero-title { font-size: 44px; font-weight: 800; letter-spacing: -0.5px; margin-bottom: 12px; background: linear-gradient(135deg, #ffffff 0%, #94a3b8 100%); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
    .hero-subtitle { font-size: 16px; color: #94a3b8; max-width: 520px; margin-bottom: 36px; line-height: 1.5; }
    
    .actions-card {
      background: rgba(30, 41, 59, 0.7);
      backdrop-filter: blur(12px);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 16px;
      padding: 28px;
      max-width: 440px;
      width: 100%;
      box-shadow: 0 20px 40px rgba(0,0,0,0.5);
      display: flex;
      flex-direction: column;
      gap: 16px;
    }
    .btn-launch {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
      width: 100%;
      padding: 16px;
      font-size: 17px;
      font-weight: 700;
      color: #fff;
      background: linear-gradient(135deg, #0284c7 0%, #0369a1 100%);
      border: none;
      border-radius: 10px;
      cursor: pointer;
      box-shadow: 0 4px 20px rgba(2, 132, 199, 0.4);
      transition: all 0.2s ease;
    }
    .btn-launch:hover { transform: translateY(-2px); box-shadow: 0 6px 25px rgba(2, 132, 199, 0.6); }
    .btn-secondary {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      width: 100%;
      padding: 12px;
      font-size: 14px;
      font-weight: 600;
      color: #cbd5e1;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 10px;
      text-decoration: none;
      cursor: pointer;
      transition: all 0.2s ease;
    }
    .btn-secondary:hover { background: rgba(255, 255, 255, 0.1); color: #fff; }

    #desktop-view {
      display: none;
      position: fixed;
      inset: 0;
      width: 100vw;
      height: 100vh;
      background: #000;
      z-index: 100;
    }
    #screen-container {
      width: 100%;
      height: 100%;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #000;
    }
    #screen-container canvas {
      outline: none;
      transform: translateZ(0);
      backface-visibility: hidden;
      image-rendering: -webkit-optimize-contrast;
    }

    #floating-dock {
      position: absolute;
      top: 12px;
      left: 50%;
      transform: translateX(-50%);
      background: rgba(15, 23, 42, 0.85);
      backdrop-filter: blur(10px);
      border: 1px solid rgba(255, 255, 255, 0.15);
      border-radius: 30px;
      padding: 6px 16px;
      display: flex;
      align-items: center;
      gap: 12px;
      z-index: 200;
      box-shadow: 0 10px 25px rgba(0,0,0,0.5);
      opacity: 0.35;
      transition: opacity 0.25s ease;
    }
    #floating-dock:hover { opacity: 1; }
    .dock-btn {
      background: transparent;
      border: none;
      color: #94a3b8;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 4px 8px;
      border-radius: 6px;
    }
    .dock-btn:hover { color: #fff; background: rgba(255, 255, 255, 0.1); }
    .dock-btn.exit:hover { color: #ef4444; background: rgba(239, 68, 68, 0.15); }

    #status-overlay {
      display: none;
      position: absolute;
      inset: 0;
      background: rgba(11, 17, 32, 0.85);
      backdrop-filter: blur(8px);
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 14px;
      z-index: 150;
    }
    .spinner { width: 42px; height: 42px; border: 4px solid rgba(255, 255, 255, 0.1); border-top-color: #0284c7; border-radius: 50%; animation: spin 0.8s linear infinite; }
    @keyframes spin { to { transform: rotate(360deg); } }
  </style>
</head>
<body>

  <div id="portal-view">
    <div class="badge"><div class="pulse-dot"></div> LinuxPC Cloud Node Online</div>
    <h1 class="hero-title">LinuxPC Cloud Desktop</h1>
    <p class="hero-subtitle">Ultra-fast, low-latency cloud workspace with preconfigured browsers, dev tools, and 16-thread download manager.</p>
    
    <div class="actions-card">
      <button class="btn-launch" onclick="launchLinuxPC()">
        🚀 Launch LinuxPC Desktop
      </button>
      <a href="/aria2files/" target="_blank" class="btn-secondary">
        📁 Open File Manager (/aria2files/)
      </a>
    </div>
  </div>

  <div id="desktop-view">
    <div id="floating-dock">
      <button class="dock-btn" onclick="toggleFullscreen()">⛶ Fullscreen</button>
      <button class="dock-btn" onclick="sendCtrlAltDel()">⚡ Ctrl+Alt+Del</button>
      <button class="dock-btn" onclick="sendClipboard()">📋 Paste Text</button>
      <button class="dock-btn" onclick="window.open('/aria2files/', '_blank')">📁 Files</button>
      <button class="dock-btn exit" onclick="exitDesktop()">✕ Exit</button>
    </div>

    <div id="screen-container"></div>

    <div id="status-overlay">
      <div class="spinner"></div>
      <div id="status-text" style="font-size: 16px; font-weight: 600;">Connecting to LinuxPC Desktop...</div>
    </div>
  </div>

  <script>
    let rfbClient = null;

    function getRFBConstructor() {
      if (typeof window.RFB === 'function') return window.RFB;
      if (window.RFB && typeof window.RFB.default === 'function') return window.RFB.default;
      if (window.RFBRaw && typeof window.RFBRaw.default === 'function') return window.RFBRaw.default;
      if (window.RFBRaw && typeof window.RFBRaw === 'function') return window.RFBRaw;
      return null;
    }

    function showStatus(text, showSpinner = true) {
      const overlay = document.getElementById('status-overlay');
      const label = document.getElementById('status-text');
      const spinner = overlay.querySelector('.spinner');
      label.innerText = text;
      spinner.style.display = showSpinner ? 'block' : 'none';
      overlay.style.display = 'flex';
    }

    function hideStatus() {
      document.getElementById('status-overlay').style.display = 'none';
    }

    function launchLinuxPC() {
      const RFBCtor = getRFBConstructor();
      if (!RFBCtor) {
        alert("Launch Error: RFB Engine failed to initialize. Please refresh the page.");
        return;
      }

      document.getElementById('portal-view').style.display = 'none';
      document.getElementById('desktop-view').style.display = 'block';
      showStatus("Connecting to LinuxPC Cloud Desktop...");

      const container = document.getElementById('screen-container');
      container.innerHTML = '';

      const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
      const url = `${proto}//${location.host}/websockify`;

      try {
        rfbClient = new RFBCtor(container, url, {
          credentials: { password: 'jiopc1234' }
        });

        // Ultra-low latency optimization
        rfbClient.scaleViewport = true;
        rfbClient.resizeSession = true;
        rfbClient.clipViewport = true;
        rfbClient.qualityLevel = 6;
        rfbClient.compressionLevel = 2; // Drastically reduces CPU decode overhead for zero lag
        rfbClient.showDotCursor = true;  // Instant local cursor feedback

        rfbClient.addEventListener('connect', () => {
          hideStatus();
          rfbClient.focus();
        });

        rfbClient.addEventListener('disconnect', (e) => {
          showStatus(e.detail.clean ? "Session ended." : "Connection lost. Click to retry.", false);
        });

        rfbClient.addEventListener('credentialsrequired', () => {
          rfbClient.sendCredentials({ password: 'jiopc1234' });
        });

      } catch (err) {
        alert("Launch Failed: " + err.message);
        exitDesktop();
      }
    }

    function exitDesktop() {
      if (rfbClient) {
        try { rfbClient.disconnect(); } catch (e) {}
        rfbClient = null;
      }
      document.getElementById('desktop-view').style.display = 'none';
      document.getElementById('portal-view').style.display = 'flex';
      hideStatus();
    }

    function toggleFullscreen() {
      if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen();
      } else {
        document.exitFullscreen();
      }
    }

    function sendCtrlAltDel() {
      if (rfbClient) rfbClient.sendCtrlAltDel();
    }

    function sendClipboard() {
      const text = prompt("Paste text to send directly to Cloud Desktop:");
      if (text && rfbClient) {
        rfbClient.clipboardPasteFrom(text);
      }
    }
  </script>
</body>
</html>
CAT_INDEX

echo "=== [5/7] Configuring Optimized Direct Xvnc & Desktop ==="
mkdir -p /root/.vnc /root/.config/openbox /etc/tigervnc
echo ":1=root" > /etc/tigervnc/vncserver.users

echo "jiopc1234" | vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd

cat > /root/.vnc/xstartup << 'CAT_XSTART'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export DISPLAY=:1
export XKL_XMODMAP_DISABLE=1
export XDG_CURRENT_DESKTOP=LXDE
export LANG=en_US.UTF-8

xsetroot -solid "#0f172a" 2>/dev/null || true
pulseaudio --start --exit-idle-time=-1 2>/dev/null || true

openbox-session &
tint2 &
lxpanel &
pcmanfm --desktop &
wait
CAT_XSTART
chmod +x /root/.vnc/xstartup

cat > /root/.config/openbox/rc.xml << 'CAT_OB'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
  </theme>
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
</openbox_config>
CAT_OB

pkill -9 -f "Xvnc :1" 2>/dev/null || true
pkill -9 -f websockify 2>/dev/null || true
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

cat > /usr/local/bin/linuxpc-vnc.sh << 'CAT_VNCSTART'
#!/bin/bash
export USER=root
export HOME=/root
export DISPLAY=:1
export LANG=en_US.UTF-8

pkill -9 -f "Xvnc :1" 2>/dev/null || true
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Launch Direct Xvnc with optimized parameters
/usr/bin/Xvnc :1 \
  -geometry 1920x1080 \
  -depth 24 \
  -rfbauth /root/.vnc/passwd \
  -rfbport 5901 \
  -pn \
  -ac &
XVNC_PID=$!

for i in {1..30}; do
  if [ -e /tmp/.X11-unix/X1 ] || [ -S /tmp/.X11-unix/X1 ]; then
    break
  fi
  sleep 0.1
done

if [ -x /root/.vnc/xstartup ]; then
  /root/.vnc/xstartup &
fi

wait $XVNC_PID
CAT_VNCSTART
chmod +x /usr/local/bin/linuxpc-vnc.sh

cat > /etc/systemd/system/vncserver.service << 'CAT_VNC'
[Unit]
Description=LinuxPC Direct Xvnc Server
After=network.target

[Service]
Type=simple
User=root
Environment=USER=root
Environment=HOME=/root
ExecStart=/usr/local/bin/linuxpc-vnc.sh
ExecStop=/usr/bin/pkill -9 -f "Xvnc :1"
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
CAT_VNC

cat > /etc/systemd/system/websockify.service << 'CAT_WS'
[Unit]
Description=LinuxPC Websockify Bridge
After=network.target vncserver.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/websockify --web="" 6080 127.0.0.1:5901
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
CAT_WS

echo "=== [6/7] Configuring Aria2 & Dufs File Manager (/aria2files/) ==="
cat > /etc/systemd/system/aria2.service << 'CAT_A2'
[Unit]
Description=LinuxPC Aria2 Engine
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/aria2c --enable-rpc --rpc-listen-all=false --rpc-listen-port=6800 --dir=/root/Downloads --max-connection-per-server=16 --split=16 --min-split-size=1M --daemon=false
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
CAT_A2

cat > /etc/systemd/system/dufs.service << 'CAT_DUFS'
[Unit]
Description=LinuxPC Dufs File Manager
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dufs /root/Downloads -b 127.0.0.1 -p 8088 -A --render-index --render-try-index
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
CAT_DUFS

cat > /var/www/aria2files-login.html << 'CAT_LOGIN'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>LinuxPC File Manager Login</title>
  <style>
    body { background: #0b1120; color: #fff; font-family: sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .card { background: #1e293b; padding: 32px; border-radius: 12px; width: 340px; box-shadow: 0 10px 30px rgba(0,0,0,0.5); text-align: center; }
    input { width: 100%; padding: 12px; border-radius: 8px; border: 1px solid #334155; background: #0f172a; color: #fff; margin: 16px 0; box-sizing: border-box; }
    button { width: 100%; padding: 12px; background: #0284c7; border: none; color: #fff; font-weight: bold; border-radius: 8px; cursor: pointer; }
  </style>
</head>
<body>
  <div class="card">
    <h2>📁 LinuxPC Files</h2>
    <p style="color: #94a3b8; font-size: 14px;">Enter password to unlock</p>
    <input type="password" id="pass" placeholder="Password (default: jiopc1234)" autofocus>
    <button onclick="login()">Unlock Files</button>
  </div>
  <script>
    function login() {
      const p = document.getElementById('pass').value;
      if (p === 'jiopc1234') {
        document.cookie = "aria2_auth=" + p + "; path=/; max-age=2592000; SameSite=Lax";
        location.href = '/aria2files/';
      } else {
        alert("Invalid Password");
      }
    }
    document.getElementById('pass').addEventListener('keypress', (e) => { if (e.key === 'Enter') login(); });
  </script>
</body>
</html>
CAT_LOGIN

cat > /var/www/aria2files-upload.js << 'CAT_UPLOAD'
(function() {
  const btn = document.createElement('button');
  btn.innerHTML = '⚡ 16-Thread Remote Download';
  btn.style.cssText = 'position:fixed;bottom:20px;right:20px;padding:12px 20px;background:#0284c7;color:#fff;border:none;border-radius:30px;font-weight:bold;cursor:pointer;z-index:9999;box-shadow:0 4px 15px rgba(0,0,0,0.4);';
  document.body.appendChild(btn);

  btn.onclick = () => {
    const url = prompt("Enter Direct Download Link:");
    if (!url) return;
    fetch('/jsonrpc', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 'upload',
        method: 'aria2.addUri',
        params: [[url]]
      })
    }).then(r => r.json()).then(data => {
      if (data.result) {
        alert("Download started in background via 16-Thread Aria2!");
      } else {
        alert("Error starting download: " + JSON.stringify(data.error));
      }
    }).catch(err => alert("Network Error: " + err.message));
  };
})();
CAT_UPLOAD

echo "=== [7/7] Configuring High-Throughput Nginx Reverse Proxy ==="
cat > /etc/nginx/sites-available/default << 'CAT_NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    client_max_body_size 0;

    location / {
        root /var/www/jiopc;
        index index.html;
        try_files $uri $uri/ =404;
    }

    # Zero-buffering, low-latency WebSocket connection
    location /websockify {
        proxy_pass http://127.0.0.1:6080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_buffering off;
        proxy_request_buffering off;
        tcp_nodelay on;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location = /aria2files-login.html {
        root /var/www;
    }
    location = /aria2files-upload.js {
        root /var/www;
    }

    location /aria2files/ {
        if ($cookie_aria2_auth != "jiopc1234") {
            return 302 /aria2files-login.html;
        }
        proxy_pass http://127.0.0.1:8088/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        sub_filter '</body>' '<script src="/aria2files-upload.js"></script></body>';
        sub_filter_once on;
    }

    location /jsonrpc {
        proxy_pass http://127.0.0.1:6800/jsonrpc;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
}
CAT_NGINX

systemctl daemon-reload
systemctl enable --now vncserver websockify aria2 dufs nginx
systemctl restart vncserver websockify aria2 dufs nginx

sleep 2

# Check & Auto-fix VNC
if ! ss -tlpn | grep -q ':5901 '; then
  pkill -9 -f "Xvnc :1" 2>/dev/null || true
  rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
  systemctl restart vncserver
  sleep 2
fi

# Check & Auto-fix Websockify
if ! ss -tlpn | grep -q ':6080 '; then
  pkill -9 -f websockify 2>/dev/null || true
  systemctl restart websockify
  sleep 1
fi

echo ""
echo "================================================================"
echo "          🎉 LinuxPC Installation & Verification Complete!      "
echo "================================================================"
echo "  🌐 Main Desktop Portal:   http://<Your-IP-or-Domain>/"
echo "  📁 File Manager (/files): http://<Your-IP-or-Domain>/aria2files/"
echo "  ⚡ Aria2 JSON-RPC:        http://<Your-IP-or-Domain>/jsonrpc"
echo "----------------------------------------------------------------"
echo "  🔑 Master / Web Password: jiopc1234"
echo "  🔑 Desktop VNC Password:  jiopc1234 (Pre-authenticated on Launch)"
echo "  👤 User Account:          root"
echo "  ⚡ Engine Optimization:    Zero-lag / Low-latency streaming"
echo "================================================================"
echo ""
EOF
bash setup.sh
