rm -f setup.sh
cat > setup.sh << 'EOF'
#!/bin/bash
# ==============================================================================
# LinuxPC Cloud Workstation Setup - KasmVNC 60 FPS & WebSocket Bridge Fix
# Strict UpCloud Open Firewall Ports (80, 443, 8443, 22, 3389)
# ==============================================================================
set -e

SERVER_IP="95.111.195.58"

# 1. Maintain or generate strong credentials
if [ -f /root/.linuxpc_credentials ]; then
    VNC_PASS=$(grep -i "Password" /root/.linuxpc_credentials | awk '{print $NF}')
fi
if [ -z "$VNC_PASS" ]; then
    VNC_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 14)
fi
BASIC_AUTH_B64=$(echo -n "root:${VNC_PASS}" | base64)

echo "===================================================================="
echo "  Starting LinuxPC Cloud Setup (WebSocket & 60 FPS Stream Fix)     "
echo "===================================================================="

# 2. Terminate legacy VNC and audio processes
echo "[+] Cleaning legacy VNC and audio processes..."
systemctl stop kasmvnc tigervnc websockify audio-streamer dufs aria2 2>/dev/null || true
pkill -9 -f Xvnc 2>/dev/null || true
pkill -9 -f kasmvnc 2>/dev/null || true
pkill -9 -f websockify 2>/dev/null || true
rm -rf /tmp/.X11-unix/X* /tmp/.X*-lock /root/.vnc/*.pid /root/.vnc/*.log 2>/dev/null || true

# 3. Kernel & TCP network buffer tuning for zero-latency 60 FPS streaming
echo "[+] Optimizing network stack and socket buffers..."
cat > /etc/sysctl.d/99-linuxpc-latency.conf << 'SYSCTL_EOF'
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_notsent_lowat = 16384
SYSCTL_EOF
sysctl -p /etc/sysctl.d/99-linuxpc-latency.conf >/dev/null 2>&1 || true

# 4. Install core packages
echo "[+] Verifying core packages and desktop environment..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    kde-plasma-desktop plasma-nm dolphin konsole \
    xorg dbus-x11 x11-xserver-utils xauth xinit \
    ssl-cert pulseaudio pulseaudio-utils libpulse-dev \
    nginx curl wget jq tar gzip ca-certificates openssl net-tools \
    python3 python3-pip python3-websockets aria2 ffmpeg

# 5. Fix KDE Plasma executable discovery
echo "[+] Ensuring startplasma-x11 compatibility symlinks..."
if [ -f /usr/bin/startplasma-x11 ]; then
    ln -sf /usr/bin/startplasma-x11 /usr/bin/startkde
fi

# 6. Install KasmVNC 1.5.0
echo "[+] Verifying KasmVNC installation..."
if ! dpkg -l | grep -q kasmvncserver; then
    KASMVNC_DEB="kasmvncserver_jammy_1.5.0_amd64.deb"
    KASMVNC_URL="https://github.com/kasmtech/KasmVNC/releases/download/v1.5.0/${KASMVNC_DEB}"
    echo "[+] Downloading ${KASMVNC_DEB}..."
    curl -fSL -o "/tmp/${KASMVNC_DEB}" "${KASMVNC_URL}"
    apt-get install -y "/tmp/${KASMVNC_DEB}" || apt-get install -f -y
    rm -f "/tmp/${KASMVNC_DEB}"
fi

if [ -f /usr/lib/kasmvncserver/select-de.sh ]; then
    sed -i 's/startkde/startplasma-x11/g' /usr/lib/kasmvncserver/select-de.sh 2>/dev/null || true
fi

if [ -f /usr/share/perl5/KasmVNC/TextUI.pm ]; then
    sed -i 's/my \$userInput = <STDIN>;/my \$userInput = <STDIN>; \$userInput \/\/= "1";/g' /usr/share/perl5/KasmVNC/TextUI.pm 2>/dev/null || true
fi

# 7. SSL certificates setup
echo "[+] Generating and securing SSL certificates..."
make-ssl-cert generate-default-snakeoil --force-overwrite
usermod -a -G ssl-cert root
chown root:ssl-cert /etc/ssl/private/ssl-cert-snakeoil.key
chmod 640 /etc/ssl/private/ssl-cert-snakeoil.key

mkdir -p /etc/nginx/ssl
cat > /tmp/openssl_san.cnf << SAN_EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = SG
ST = Singapore
L = Singapore
O = LinuxPC
CN = ${SERVER_IP}

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
IP.1 = ${SERVER_IP}
IP.2 = 127.0.0.1
DNS.1 = localhost
SAN_EOF

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/server.key \
    -out /etc/nginx/ssl/server.crt \
    -config /tmp/openssl_san.cnf 2>/dev/null || true
rm -f /tmp/openssl_san.cnf

# 8. Automated Non-interactive VNC Credentials Generation via PTY
echo "[+] Setting up VNC security credentials..."
mkdir -p /root/.vnc /etc/kasmvnc
touch /root/.vnc/.de-was-selected

python3 - << PY_AUTH_EOF
import os, pty, select, subprocess, time, sys

password = "${VNC_PASS}"
username = "root"

master, slave = pty.openpty()
proc = subprocess.Popen(
    ["kasmvncpasswd", "-u", username],
    stdin=slave, stdout=slave, stderr=slave, close_fds=True
)
os.close(slave)

buf = ""
start = time.time()
passwords_sent = 0

while proc.poll() is None and (time.time() - start) < 6:
    r, _, _ = select.select([master], [], [], 0.3)
    if r:
        try:
            chunk = os.read(master, 1024).decode("utf-8", errors="ignore")
            buf += chunk
            if ("password" in chunk.lower() or "verify" in chunk.lower()) and passwords_sent < 2:
                time.sleep(0.1)
                os.write(master, (password + "\n").encode())
                passwords_sent += 1
            elif "select" in chunk.lower() or "action" in chunk.lower() or "access" in chunk.lower():
                time.sleep(0.1)
                os.write(master, b"1\n")
        except OSError:
            break

try:
    os.close(master)
except Exception:
    pass

proc.wait(timeout=3)
PY_AUTH_EOF

for p in /root/.kasmpasswd /root/.vnc/.kasmpasswd /etc/kasmvnc/kasmvncpasswd; do
    if [ -f /root/.kasmpasswd ] && [ "$p" != "/root/.kasmpasswd" ]; then
        cp -f /root/.kasmpasswd "$p" 2>/dev/null || true
    fi
    [ -f "$p" ] && chmod 600 "$p"
done

cat > /root/.linuxpc_credentials << CRED_EOF
LinuxPC Cloud Workstation Credentials
======================================
Username : root
Password : ${VNC_PASS}
Generated: $(date)
CRED_EOF
chmod 600 /root/.linuxpc_credentials

# Bulletproof xstartup
cat > /root/.vnc/xstartup << 'XSTARTUP_EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=KDE
export DESKTOP_SESSION=plasma
export KDE_FULL_SESSION=true
export QT_QPA_PLATFORM=xcb
export DISPLAY=:1

[ -r "$HOME/.Xresources" ] && xrdb "$HOME/.Xresources"

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax --exit-with-session)
fi

if [ -x /usr/bin/startplasma-x11 ]; then
    exec /usr/bin/startplasma-x11
elif [ -x /usr/bin/startkde ]; then
    exec /usr/bin/startkde
elif [ -x /usr/bin/xfce4-session ]; then
    exec /usr/bin/xfce4-session
else
    exec x-window-manager
fi
XSTARTUP_EOF
chmod +x /root/.vnc/xstartup

# Configure KasmVNC YAML with strict schema compliance
cat > /etc/kasmvnc/kasmvnc.yaml << 'YAML_EOF'
desktop:
  resolution:
    width: 1366
    height: 1080
network:
  interface: 127.0.0.1
  websocket_port: 8444
  ssl:
    require_ssl: true
    pem_certificate: /etc/ssl/certs/ssl-cert-snakeoil.pem
    pem_key: /etc/ssl/private/ssl-cert-snakeoil.key
encoding:
  max_frame_rate: 60
YAML_EOF
cp -f /etc/kasmvnc/kasmvnc.yaml /root/.vnc/kasmvnc.yaml 2>/dev/null || true

# 9. PulseAudio System Configuration
echo "[+] Configuring PulseAudio system daemon..."
cat > /etc/pulse/system.pa << 'PULSE_EOF'
load-module module-null-sink sink_name=VirtualSink sink_properties=device.description="LinuxPC_Virtual_Sink"
set-default-sink VirtualSink
load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 port=4713
load-module module-simple-protocol-tcp rate=44100 format=s16le channels=2 source=VirtualSink.monitor record=true port=6082 listen=127.0.0.1
load-module module-always-sink
PULSE_EOF

cat > /etc/pulse/client.conf << 'PULSE_CLIENT_EOF'
default-server = 127.0.0.1:4713
autospawn = no
PULSE_CLIENT_EOF

cat > /etc/systemd/system/pulseaudio.service << 'PULSE_SVC_EOF'
[Unit]
Description=PulseAudio System Sound Daemon (Low Latency)
After=network.target

[Service]
Type=simple
User=root
Environment=HOME=/root
ExecStartPre=-/usr/bin/pulseaudio -k
ExecStart=/usr/bin/pulseaudio --system --disallow-exit --disallow-module-loading=0 --exit-idle-time=-1 --realtime=true
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
PULSE_SVC_EOF

# 10. Python Low-Latency Audio WebSocket Streamer
echo "[+] Setting up Audio Streamer Service..."
cat > /usr/local/bin/audio-streamer.py << 'PY_AUDIO_EOF'
#!/usr/bin/env python3
import asyncio
import websockets
import logging

logging.basicConfig(level=logging.INFO)
CLIENTS = set()

async def pulse_reader():
    while True:
        try:
            reader, writer = await asyncio.open_connection('127.0.0.1', 6082)
            logging.info("Connected to PulseAudio raw PCM stream on port 6082")
            while True:
                data = await reader.read(1764)
                if not data:
                    break
                if CLIENTS:
                    dead = set()
                    for ws in CLIENTS:
                        try:
                            await ws.send(data)
                        except Exception:
                            dead.add(ws)
                    CLIENTS.difference_update(dead)
        except Exception:
            await asyncio.sleep(1.5)

async def ws_handler(websocket):
    CLIENTS.add(websocket)
    try:
        await websocket.wait_closed()
    finally:
        CLIENTS.discard(websocket)

async def main():
    asyncio.create_task(pulse_reader())
    server = await websockets.serve(ws_handler, "127.0.0.1", 6081)
    logging.info("Audio WebSocket server running on 127.0.0.1:6081")
    await server.wait_closed()

if __name__ == "__main__":
    asyncio.run(main())
PY_AUDIO_EOF
chmod +x /usr/local/bin/audio-streamer.py

cat > /etc/systemd/system/audio-streamer.service << 'AUDIO_SVC_EOF'
[Unit]
Description=LinuxPC Low-Latency Audio WebSocket Streamer
After=pulseaudio.service
Wants=pulseaudio.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/audio-streamer.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
AUDIO_SVC_EOF

# 11. KasmVNC Startup Launcher
echo "[+] Configuring KasmVNC 60 FPS foreground service..."
cat > /usr/local/bin/kasmvnc-launcher << 'LAUNCHER_EOF'
#!/bin/bash
/usr/bin/vncserver -kill :1 2>/dev/null || true
rm -rf /tmp/.X11-unix/X1 /tmp/.X1-lock /root/.vnc/*.pid /root/.vnc/*.log 2>/dev/null || true
[ -f /usr/bin/startplasma-x11 ] && ln -sf /usr/bin/startplasma-x11 /usr/bin/startkde

exec /usr/bin/vncserver -fg :1 \
    -geometry 1366x1080 \
    -depth 24 \
    -select-de manual \
    -FrameRate 60 \
    -VideoTime 0 \
    -VideoArea 5 \
    -RectThreads 4
LAUNCHER_EOF
chmod +x /usr/local/bin/kasmvnc-launcher

cat > /etc/systemd/system/kasmvnc.service << 'KASMVNC_SVC_EOF'
[Unit]
Description=KasmVNC 60 FPS Remote Desktop Server
After=network.target pulseaudio.service
Wants=pulseaudio.service

[Service]
Type=simple
User=root
Environment=HOME=/root
Environment=USER=root
Environment=DISPLAY=:1
WorkingDirectory=/root
ExecStartPre=-/bin/rm -rf /tmp/.X11-unix/X1 /tmp/.X1-lock /root/.vnc/*.pid /root/.vnc/*.log
ExecStart=/usr/local/bin/kasmvnc-launcher
ExecStop=/usr/bin/vncserver -kill :1
Restart=on-failure
RestartSec=3
KillMode=mixed
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
KASMVNC_SVC_EOF

# 12. Google Chrome 60 FPS Configuration
echo "[+] Configuring Google Chrome with 60 FPS optimization..."
if ! command -v google-chrome-stable &>/dev/null; then
    wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg 2>/dev/null || true
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
    apt-get update -y && apt-get install -y google-chrome-stable || true
fi

cat > /usr/local/bin/chrome-60fps << 'CHROME_EOF'
#!/bin/bash
exec /usr/bin/google-chrome-stable \
    --no-sandbox \
    --disable-dev-shm-usage \
    --enable-features=VaapiVideoDecoder,CanvasOopRasterization,UseSkiaRenderer \
    --enable-gpu-rasterization \
    --enable-zero-copy \
    --ignore-gpu-blocklist \
    --use-gl=swiftshader \
    --enable-accelerated-video-decode \
    --disable-background-timer-throttling \
    --disable-backgrounding-occluded-windows \
    --disable-renderer-backgrounding \
    --autoplay-policy=no-user-gesture-required \
    "$@"
CHROME_EOF
chmod +x /usr/local/bin/chrome-60fps

mkdir -p /root/Desktop
cat > /root/Desktop/Google-Chrome.desktop << 'DESK_CHROME_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Google Chrome (60 FPS)
Comment=Butter-smooth 60 FPS video playback
Exec=/usr/local/bin/chrome-60fps %U
Icon=google-chrome
Terminal=false
Categories=Network;WebBrowser;
DESK_CHROME_EOF
chmod +x /root/Desktop/Google-Chrome.desktop

# 13. Dufs File Manager (Internal 127.0.0.1:8088)
echo "[+] Configuring Dufs Fast File Manager..."
if [ ! -f /usr/local/bin/dufs ]; then
    DUFS_VER="v0.43.0"
    curl -fsSL "https://github.com/sigoden/dufs/releases/download/${DUFS_VER}/dufs-${DUFS_VER}-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /usr/local/bin dufs 2>/dev/null || true
    chmod +x /usr/local/bin/dufs 2>/dev/null || true
fi

mkdir -p /root/Downloads
cat > /etc/systemd/system/dufs.service << 'DUFS_SVC_EOF'
[Unit]
Description=Dufs Fast File Manager
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dufs /root/Downloads -b 127.0.0.1 -p 8088 --allow-all --render-spa
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
DUFS_SVC_EOF

# 14. Aria2 RPC (Internal 127.0.0.1:6800)
mkdir -p /etc/aria2
cat > /etc/aria2/aria2.conf << 'ARIA_CONF_EOF'
dir=/root/Downloads
enable-rpc=true
rpc-allow-origin-all=true
rpc-listen-all=false
rpc-listen-port=6800
max-connection-per-server=16
split=16
min-split-size=1M
continue=true
max-overall-download-limit=0
max-overall-upload-limit=0
ARIA_CONF_EOF

cat > /etc/systemd/system/aria2.service << 'ARIA_SVC_EOF'
[Unit]
Description=Aria2 RPC Download Manager
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/aria2c --conf-path=/etc/aria2/aria2.conf
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
ARIA_SVC_EOF

# 15. Web Dashboard with Direct Desktop Link
echo "[+] Deploying Web Portal..."
mkdir -p /var/www/html
cat > /var/www/html/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>LinuxPC Workstation - 60 FPS KasmVNC Edition</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;800&family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #090d16;
      --card-bg: rgba(16, 24, 40, 0.85);
      --border: rgba(56, 189, 248, 0.25);
      --neon-blue: #38bdf8;
      --neon-cyan: #06b6d4;
      --neon-green: #10b981;
      --text: #f1f5f9;
      --text-dim: #94a3b8;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: radial-gradient(circle at 50% 10%, #1e293b 0%, var(--bg) 80%);
      color: var(--text);
      font-family: 'Inter', sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 2.5rem 1rem;
    }
    .container { width: 100%; max-width: 1080px; }
    .header { text-align: center; margin-bottom: 2rem; }
    .title {
      font-size: 2.5rem;
      font-weight: 800;
      letter-spacing: -0.03em;
      background: linear-gradient(135deg, #fff 30%, var(--neon-blue) 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .badge {
      display: inline-block;
      padding: 0.25rem 0.75rem;
      background: rgba(56, 189, 248, 0.15);
      border: 1px solid var(--border);
      border-radius: 999px;
      color: var(--neon-blue);
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.8rem;
      margin-top: 0.5rem;
    }
    .hero-card {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 2.5rem 2rem;
      backdrop-filter: blur(12px);
      text-align: center;
      box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6);
      margin-bottom: 2rem;
    }
    .btn-launch {
      display: inline-block;
      padding: 1.25rem 3rem;
      background: linear-gradient(135deg, #0284c7, #06b6d4);
      color: #fff;
      text-decoration: none;
      font-weight: 700;
      font-size: 1.25rem;
      border-radius: 12px;
      box-shadow: 0 0 25px rgba(6, 182, 212, 0.4);
      transition: all 0.25s ease;
      cursor: pointer;
      border: none;
    }
    .btn-launch:hover {
      transform: translateY(-2px);
      box-shadow: 0 0 35px rgba(6, 182, 212, 0.7);
    }
    .audio-card {
      background: rgba(15, 23, 42, 0.8);
      border: 1px solid rgba(16, 185, 129, 0.3);
      border-radius: 12px;
      padding: 1.5rem;
      margin-top: 1.5rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 1rem;
    }
    .audio-status {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.95rem;
    }
    .status-dot {
      width: 10px;
      height: 10px;
      border-radius: 50%;
      background: #ef4444;
      box-shadow: 0 0 10px #ef4444;
    }
    .status-dot.active {
      background: var(--neon-green);
      box-shadow: 0 0 10px var(--neon-green);
    }
    .btn-audio {
      padding: 0.75rem 1.5rem;
      background: #1e293b;
      border: 1px solid var(--border);
      color: #fff;
      font-weight: 600;
      border-radius: 8px;
      cursor: pointer;
      transition: all 0.2s;
    }
    .btn-audio:hover { background: #334155; }
    .btn-audio.active { background: #059669; border-color: var(--neon-green); }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 1.5rem;
      margin-top: 1rem;
    }
    .card {
      background: var(--card-bg);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 12px;
      padding: 1.5rem;
      backdrop-filter: blur(8px);
    }
    .card h3 {
      font-size: 1.15rem;
      margin-bottom: 0.75rem;
      color: var(--neon-blue);
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }
    .card a {
      color: var(--neon-cyan);
      text-decoration: none;
      display: inline-block;
      margin-top: 0.75rem;
      font-size: 0.9rem;
      font-weight: 600;
    }
    .card a:hover { text-decoration: underline; }
    .telemetry {
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.85rem;
      color: var(--text-dim);
      margin-top: 0.5rem;
    }
    .footer {
      margin-top: 3rem;
      font-size: 0.85rem;
      color: var(--text-dim);
      text-align: center;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1 class="title">LinuxPC Cloud Workstation</h1>
      <div class="badge">KasmVNC 60 FPS • PulseAudio Sub-25ms • UpCloud Singapore</div>
    </div>

    <div class="hero-card">
      <h2 style="font-size: 1.5rem; margin-bottom: 0.75rem;">Interactive Desktop Session</h2>
      <p style="color: var(--text-dim); margin-bottom: 1.5rem;">
        Zero-lag 60 FPS video playback in Google Chrome, real-time PulseAudio sound, and KDE Plasma 5 suite.
      </p>
      
      <a href="/desktop/?autoconnect=true" target="_blank" class="btn-launch">
        🚀 Launch LinuxPC Desktop
      </a>

      <div class="audio-card">
        <div class="audio-status">
          <div id="audioDot" class="status-dot"></div>
          <span id="audioText">Audio Bridge: Idle (Click to Enable)</span>
          <span id="audioLatency" style="color: var(--neon-green); font-size: 0.8rem; margin-left: 0.5rem;"></span>
        </div>
        <button id="toggleAudioBtn" class="btn-audio" onclick="toggleAudio()">🔊 Turn Audio On</button>
      </div>
    </div>

    <div class="grid">
      <div class="card">
        <h3>⚡ Desktop Specs</h3>
        <div class="telemetry">
          • Environment: KDE Plasma 5<br>
          • Architecture: 4 CPU Cores / 8 GB RAM<br>
          • Resolution: 1366 x 1080 (Dynamic)<br>
          • Frame Target: 60 FPS (H.264/WebP Engine)
        </div>
      </div>

      <div class="card">
        <h3>📁 Storage & Files</h3>
        <div class="telemetry">
          High-speed file explorer for uploading and downloading media files to VPS storage.
        </div>
        <a href="/files/" target="_blank">Open File Explorer →</a>
      </div>

      <div class="card">
        <h3>⬇️ Aria2 Downloader</h3>
        <div class="telemetry">
          High-throughput multi-connection background download client with Web UI.
        </div>
        <a href="/ariang/" target="_blank">Open AriaNg Interface →</a>
      </div>
    </div>

    <div class="footer">
      LinuxPC Cloud Engine • Accessible via Ports 80, 443 & 8443 (Full Cloudflare Support).
    </div>
  </div>

  <script>
    let audioCtx = null;
    let audioWs = null;
    let nextAudioTime = 0;
    let isAudioPlaying = false;

    function toggleAudio() {
      const btn = document.getElementById('toggleAudioBtn');
      const dot = document.getElementById('audioDot');
      const txt = document.getElementById('audioText');
      const lat = document.getElementById('audioLatency');

      if (isAudioPlaying) {
        if (audioWs) audioWs.close();
        if (audioCtx) audioCtx.close();
        audioCtx = null;
        isAudioPlaying = false;
        btn.classList.remove('active');
        btn.innerText = '🔊 Turn Audio On';
        dot.classList.remove('active');
        txt.innerText = 'Audio Bridge: Idle';
        lat.innerText = '';
        return;
      }

      try {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 44100 });
        if (audioCtx.state === 'suspended') audioCtx.resume();

        const wsProtocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
        audioWs = new WebSocket(`${wsProtocol}//${location.host}/audio`);
        audioWs.binaryType = 'arraybuffer';

        audioWs.onopen = () => {
          isAudioPlaying = true;
          btn.classList.add('active');
          btn.innerText = '🔇 Mute Audio';
          dot.classList.add('active');
          txt.innerText = 'Audio Bridge: Streaming (Synced)';
          lat.innerText = '[~20ms PCM]';
        };

        audioWs.onmessage = (event) => {
          if (!audioCtx) return;
          const int16Array = new Int16Array(event.data);
          const numFrames = int16Array.length / 2;
          const audioBuffer = audioCtx.createBuffer(2, numFrames, 44100);
          const left = audioBuffer.getChannelData(0);
          const right = audioBuffer.getChannelData(1);

          for (let i = 0; i < numFrames; i++) {
            left[i] = int16Array[i * 2] / 32768.0;
            right[i] = int16Array[i * 2 + 1] / 32768.0;
          }

          const source = audioCtx.createBufferSource();
          source.buffer = audioBuffer;
          source.connect(audioCtx.destination);

          const curTime = audioCtx.currentTime;
          if (nextAudioTime < curTime) {
            nextAudioTime = curTime + 0.02;
          }
          source.start(nextAudioTime);
          nextAudioTime += audioBuffer.duration;
        };

        audioWs.onerror = () => {
          txt.innerText = 'Audio Connection Error (PulseAudio restarting)';
        };

        audioWs.onclose = () => {
          if (isAudioPlaying) {
            txt.innerText = 'Audio Bridge: Disconnected';
            dot.classList.remove('active');
          }
        };
      } catch (err) {
        alert('Web Audio initialization error: ' + err.message);
      }
    }
  </script>
</body>
</html>
HTML_EOF

# 16. AriaNg Client Setup
if [ ! -d /var/www/html/ariang ]; then
    mkdir -p /var/www/html/ariang
    ARIANG_URL="https://github.com/mayswind/AriaNg/releases/download/1.3.7/AriaNg-1.3.7.zip"
    curl -fsSL -o /tmp/ariang.zip "${ARIANG_URL}" 2>/dev/null || true
    if command -v unzip &>/dev/null && [ -f /tmp/ariang.zip ]; then
        unzip -q -o /tmp/ariang.zip -d /var/www/html/ariang 2>/dev/null || true
        rm -f /tmp/ariang.zip
    fi
fi

# 17. Configure Nginx Master Reverse Proxy with Full WebSocket Route Coverage
echo "[+] Configuring Nginx reverse proxy with complete WebSocket support..."
cat > /etc/nginx/sites-available/default << NGINX_EOF
# HTTP Listener
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;
    client_max_body_size 10240M;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    location = / {
        try_files /index.html =404;
    }

    # KasmVNC Desktop Direct Proxy
    location /desktop/ {
        proxy_pass https://127.0.0.1:8444/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host 127.0.0.1:8444;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization "Basic ${BASIC_AUTH_B64}";
        proxy_ssl_verify off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
        proxy_redirect / /desktop/;
    }

    # Global WebSocket & Asset Handler for KasmVNC
    location ~* ^/(websocket|websockify|kasmvnc|dist|vendor|locales|sounds|img|css|js)/? {
        proxy_pass https://127.0.0.1:8444;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host 127.0.0.1:8444;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization "Basic ${BASIC_AUTH_B64}";
        proxy_ssl_verify off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
    }

    # PulseAudio WebSocket Bridge
    location /audio {
        proxy_pass http://127.0.0.1:6081/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
    }

    location /files/ {
        proxy_pass http://127.0.0.1:8088/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /jsonrpc {
        proxy_pass http://127.0.0.1:6800/jsonrpc;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
    }

    location /ariang/ {
        alias /var/www/html/ariang/;
        try_files \$uri \$uri/ /ariang/index.html;
    }
}

# HTTPS Listener (Ports 443 & 8443)
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    listen 8443 ssl;
    listen [::]:8443 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/html;
    index index.html;
    client_max_body_size 10240M;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    location = / {
        try_files /index.html =404;
    }

    # KasmVNC Desktop Direct Proxy
    location /desktop/ {
        proxy_pass https://127.0.0.1:8444/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host 127.0.0.1:8444;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization "Basic ${BASIC_AUTH_B64}";
        proxy_ssl_verify off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
        proxy_redirect / /desktop/;
    }

    # Global WebSocket & Asset Handler for KasmVNC
    location ~* ^/(websocket|websockify|kasmvnc|dist|vendor|locales|sounds|img|css|js)/? {
        proxy_pass https://127.0.0.1:8444;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host 127.0.0.1:8444;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Authorization "Basic ${BASIC_AUTH_B64}";
        proxy_ssl_verify off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
    }

    # PulseAudio WebSocket Bridge
    location /audio {
        proxy_pass http://127.0.0.1:6081/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
    }

    location /files/ {
        proxy_pass http://127.0.0.1:8088/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /jsonrpc {
        proxy_pass http://127.0.0.1:6800/jsonrpc;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
    }

    location /ariang/ {
        alias /var/www/html/ariang/;
        try_files \$uri \$uri/ /ariang/index.html;
    }
}
NGINX_EOF

# 18. Reload and Start All Services
echo "[+] Starting and enabling all system services..."
systemctl daemon-reload

systemctl restart pulseaudio
sleep 1
systemctl restart audio-streamer
sleep 1
systemctl restart dufs 2>/dev/null || true
systemctl restart aria2 2>/dev/null || true
systemctl restart kasmvnc
sleep 3
systemctl restart nginx

systemctl enable pulseaudio audio-streamer kasmvnc nginx dufs aria2 2>/dev/null || true

# 19. Port Health Verification
echo "===================================================================="
echo "                   System Health Verification                       "
echo "===================================================================="
sleep 2

check_port() {
    local port=$1
    local name=$2
    if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        echo -e "  [\033[0;32mOK\033[0m] Port ${port} (${name}) is active"
    else
        echo -e "  [\033[0;31mFAIL\033[0m] Port ${port} (${name}) is NOT listening"
    fi
}

check_port 80 "Nginx HTTP"
check_port 443 "Nginx HTTPS"
check_port 8443 "Nginx Alt HTTPS"
check_port 8444 "KasmVNC Core"
check_port 6081 "Audio WebSocket"
check_port 6082 "PulseAudio Monitor"
check_port 8088 "Dufs Files"
check_port 6800 "Aria2 RPC"

echo "--------------------------------------------------------------------"
if netstat -tuln | grep -q ":8444 "; then
    echo -e "\033[0;32m>>> SUCCESS: KasmVNC 60 FPS Workstation is running cleanly! <<<\033[0m"
else
    echo -e "\033[0;31m>>> WARNING: KasmVNC did not bind to 8444. Checking log... <<<\033[0m"
    journalctl -u kasmvnc -n 15 --no-pager
fi

echo "===================================================================="
echo "  UpCloud Workstation Ready! Access Details:"
echo "===================================================================="
echo "  Access Portal   : https://${SERVER_IP}/"
echo "  Direct Desktop  : https://${SERVER_IP}/desktop/?autoconnect=true"
echo "  VNC Username    : root"
echo "  VNC Password    : ${VNC_PASS}"
echo "===================================================================="
echo "  (Password saved to /root/.linuxpc_credentials)"
echo "===================================================================="
EOF
bash setup.sh
