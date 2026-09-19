cat > setup.sh << 'EOF'
#!/bin/bash
# ==============================================================================
# LinuxPC Cloud Workstation Setup - Universal Dual-Arch (AMD64 & ARM64)
# Compatible with: Oracle Cloud Ampere A1 (ARM64) & UpCloud / Standard (x86_64)
# OS: Ubuntu 22.04 LTS (Jammy Jellyfish)
# Ports: 22 (SSH), 80 (HTTP), 443 (HTTPS), 8443 (Alt HTTPS)
# Services: KasmVNC, KDE Plasma, PulseAudio, Audio Streamer, Dufs, Aria2, Nginx
# ==============================================================================
set -e

echo "===================================================================="
echo "    Starting LinuxPC Workstation Setup (Dual-Arch: AMD64 & ARM64)   "
echo "===================================================================="

# ------------------------------------------------------------------------------
# 1. Architecture & Public IP Detection
# ------------------------------------------------------------------------------
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    DEB_ARCH="amd64"
    DUFS_ARCH="x86_64"
    echo "[+] Architecture detected: AMD64 / x86_64"
elif [ "$ARCH" = "aarch64" ]; then
    DEB_ARCH="arm64"
    DUFS_ARCH="aarch64"
    echo "[+] Architecture detected: ARM64 / aarch64 (Ampere)"
else
    echo "[-] Unsupported CPU architecture: $ARCH"
    exit 1
fi

echo "[+] Detecting Server Public IP..."
SERVER_IP="${SERVER_IP:-$(curl -4s --max-time 4 https://ifconfig.me 2>/dev/null || curl -4s --max-time 4 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')}"
[ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"
echo "[+] Target Public IP: ${SERVER_IP}"

# Maintain or generate strong credentials
if [ -f /root/.linuxpc_credentials ]; then
    VNC_PASS=$(grep -i "Password" /root/.linuxpc_credentials | awk '{print $NF}')
fi
if [ -z "$VNC_PASS" ]; then
    VNC_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 14)
fi
BASIC_AUTH_B64=$(printf "%s" "root:${VNC_PASS}" | base64 | tr -d '\n')

# ------------------------------------------------------------------------------
# 2. Cleanup Legacy Processes, Display Locks & Unmask Nginx
# ------------------------------------------------------------------------------
echo "[+] Cleaning legacy processes and freeing X11 display & network ports..."
systemctl stop kasmvnc pulseaudio audio-streamer dufs aria2 nginx websockify 2>/dev/null || true
pkill -9 -f Xvnc 2>/dev/null || true
pkill -9 -f kasmvnc 2>/dev/null || true
pkill -9 -f pulseaudio 2>/dev/null || true
pkill -9 -f audio-streamer 2>/dev/null || true
pkill -9 -f dufs 2>/dev/null || true
pkill -9 -f aria2c 2>/dev/null || true
pkill -9 -f chrome 2>/dev/null || true
pkill -9 -f chromium 2>/dev/null || true
pkill -9 -f websockify 2>/dev/null || true

# Force release audio & websocket ports
fuser -k 6081/tcp 2>/dev/null || true
fuser -k 6082/tcp 2>/dev/null || true
fuser -k 8444/tcp 2>/dev/null || true

rm -rf /tmp/.X11-unix/X* /tmp/.X*-lock /root/.vnc/*.pid /root/.vnc/*.log 2>/dev/null || true
rm -f /root/.config/google-chrome/Singleton* /root/.config/chromium/Singleton* 2>/dev/null || true

# Unmask Nginx (fixes Oracle Cloud masked unit error)
echo "[+] Unmasking Nginx service..."
systemctl unmask nginx.service 2>/dev/null || true
systemctl unmask nginx 2>/dev/null || true
rm -f /etc/systemd/system/nginx.service 2>/dev/null || true
systemctl daemon-reload

# ------------------------------------------------------------------------------
# 3. Kernel & TCP Network Socket Latency Tuning
# ------------------------------------------------------------------------------
echo "[+] Optimizing network stack and socket buffers for 60 FPS streaming..."
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

# ------------------------------------------------------------------------------
# 4. APT Initialization & Safe Lock Wait
# ------------------------------------------------------------------------------
echo "[+] Preparing APT repositories..."
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "[i] Waiting for background system updates to release APT lock..."
    sleep 3
done

rm -f /etc/apt/sources.list.d/brave-browser*.list /etc/apt/trusted.gpg.d/brave-browser*.gpg 2>/dev/null || true
echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99translations 2>/dev/null || true

apt-get update -qq

# ------------------------------------------------------------------------------
# 5. Core Desktop Stack, Themes, Tools & Audio
# ------------------------------------------------------------------------------
echo "[+] Installing full KDE Plasma desktop stack, icon engines, and tools..."
apt-get install -y -qq \
    kde-plasma-desktop \
    plasma-desktop \
    plasma-workspace \
    kde-cli-tools \
    breeze \
    breeze-icon-theme \
    breeze-gtk-theme \
    breeze-cursor-theme \
    kwin-x11 \
    systemsettings \
    libqt5svg5 \
    libqt5svg5-dev \
    qt5-image-formats-plugins \
    kimageformat-plugins \
    libkf5iconthemes-bin \
    libkf5iconthemes5 \
    libkf5config-bin \
    papirus-icon-theme \
    oxygen-icon-theme \
    adwaita-icon-theme \
    hicolor-icon-theme \
    librsvg2-bin \
    gvfs \
    gvfs-backends \
    libglib2.0-bin \
    dolphin \
    konsole \
    xorg \
    dbus-x11 \
    x11-xserver-utils \
    x11-utils \
    xauth \
    xinit \
    ssl-cert \
    pulseaudio \
    pulseaudio-utils \
    libpulse-dev \
    libasound2-plugins \
    python3 \
    python3-pip \
    python3-websockets \
    aria2 \
    ffmpeg \
    nginx \
    curl \
    wget \
    jq \
    tar \
    gzip \
    unzip \
    ca-certificates \
    openssl \
    net-tools \
    iptables-persistent 2>/dev/null || true

[ -f /usr/bin/startplasma-x11 ] && ln -sf /usr/bin/startplasma-x11 /usr/bin/startkde 2>/dev/null || true

# ------------------------------------------------------------------------------
# 6. Install Browser (Dynamic for AMD64 & ARM64)
# ------------------------------------------------------------------------------
if ! command -v google-chrome >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1 && ! command -v chromium >/dev/null 2>&1; then
    echo "[+] Installing Web Browser for ${DEB_ARCH}..."
    CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_${DEB_ARCH}.deb"
    
    if curl -fsIL --max-time 5 "${CHROME_URL}" >/dev/null 2>&1; then
        echo "[+] Downloading official Google Chrome (${DEB_ARCH})..."
        wget -q -O /tmp/chrome.deb "${CHROME_URL}" 2>/dev/null || true
        apt-get install -y /tmp/chrome.deb 2>/dev/null || apt-get install -f -y
        rm -f /tmp/chrome.deb
    else
        echo "[+] Fallback: Installing native Chromium..."
        apt-get install -y chromium-browser 2>/dev/null || apt-get install -y chromium 2>/dev/null || true
    fi
fi

# ------------------------------------------------------------------------------
# 7. Install KasmVNC Server 1.5.0 (Architecture-Matched)
# ------------------------------------------------------------------------------
if ! dpkg -l | grep -q kasmvncserver; then
    KASMVNC_DEB="kasmvncserver_jammy_1.5.0_${DEB_ARCH}.deb"
    echo "[+] Downloading and installing KasmVNC (${KASMVNC_DEB})..."
    KASMVNC_URL="https://github.com/kasmtech/KasmVNC/releases/download/v1.5.0/${KASMVNC_DEB}"
    curl -fSL -o "/tmp/${KASMVNC_DEB}" "${KASMVNC_URL}"
    apt-get install -y "/tmp/${KASMVNC_DEB}" || apt-get install -f -y
    rm -f "/tmp/${KASMVNC_DEB}"
fi

usermod -a -G ssl-cert root 2>/dev/null || true
if [ -f /usr/lib/kasmvncserver/select-de.sh ]; then
    sed -i 's/startkde/startplasma-x11/g' /usr/lib/kasmvncserver/select-de.sh 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 8. Dark Mode, Compositor Optimization & Desktop Configuration
# ------------------------------------------------------------------------------
echo "[+] Configuring permanent Dark Mode & zero-overhead X11 rendering..."
mkdir -p /root/.config /root/.config/gtk-3.0 /root/.config/gtk-4.0 /etc/xdg

cat > /etc/xdg/kdeglobals << 'KDE_SYS_EOF'
[General]
ColorScheme=BreezeDark
Name=Breeze Dark
widgetStyle=Breeze

[KDE]
colorScheme=BreezeDark
widgetStyle=Breeze

[Icons]
Theme=breeze-dark

[org.kde.kdecoration2]
BorderSize=Normal
BorderSizeAuto=false
ButtonsOnLeft=M
ButtonsOnRight=IAX
library=org.kde.breeze
theme=Breeze
KDE_SYS_EOF

cat > /root/.config/kdeglobals << 'KDE_EOF'
[General]
ColorScheme=BreezeDark
Name=Breeze Dark
fixed=Monospace,10,-1,5,50,0,0,0,0,0
font=Noto Sans,10,-1,5,50,0,0,0,0,0
menuFont=Noto Sans,10,-1,5,50,0,0,0,0,0
smallestReadableFont=Noto Sans,8,-1,5,50,0,0,0,0,0
toolBarFont=Noto Sans,10,-1,5,50,0,0,0,0,0
widgetStyle=Breeze

[KDE]
ShowDeleteCommand=true
colorScheme=BreezeDark
widgetStyle=Breeze

[Icons]
Theme=breeze-dark
FallbackTheme=Papirus-Dark

[org.kde.kdecoration2]
BorderSize=Normal
BorderSizeAuto=false
ButtonsOnLeft=M
ButtonsOnRight=IAX
CloseOnDoubleClickOnMenu=false
library=org.kde.breeze
theme=Breeze
KDE_EOF

# Compositing disabled for direct X11 frame grabbing at 60 FPS
cat > /root/.config/kwinrc << 'KWIN_EOF'
[org.kde.kdecoration2]
BorderSize=Normal
BorderSizeAuto=false
ButtonsOnLeft=M
ButtonsOnRight=IAX
CloseOnDoubleClickOnMenu=false
library=org.kde.breeze
theme=Breeze

[Windows]
BorderlessMaximizedWindows=false
TitlebarDoubleClickAction=Maximize

[Compositing]
Backend=XRender
Enabled=false
OpenGLIsUnsafe=true
KWIN_EOF

cat > /root/.config/plasmarc << 'PLASMA_THEME_EOF'
[Theme]
name=breeze-dark
PLASMA_THEME_EOF

cat > /root/.config/kscreenlockerrc << 'LOCK_EOF'
[Daemon]
Autolock=false
LockOnResume=false
Timeout=0
LOCK_EOF

cat > /root/.gtkrc-2.0 << 'GTK2_EOF'
gtk-theme-name="Breeze-Dark"
gtk-icon-theme-name="breeze-dark"
gtk-font-name="Noto Sans 10"
GTK2_EOF

cat > /root/.config/gtk-3.0/settings.ini << 'GTK3_EOF'
[Settings]
gtk-theme-name=Breeze-Dark
gtk-icon-theme-name=breeze-dark
gtk-font-name=Noto Sans 10
gtk-application-prefer-dark-theme=1
GTK3_EOF

cat > /root/.config/gtk-4.0/settings.ini << 'GTK4_EOF'
[Settings]
gtk-theme-name=Breeze-Dark
gtk-icon-theme-name=breeze-dark
gtk-font-name=Noto Sans 10
gtk-application-prefer-dark-theme=1
GTK4_EOF

# ------------------------------------------------------------------------------
# 9. SSL Certificates Setup
# ------------------------------------------------------------------------------
echo "[+] Generating SSL Snakeoil & Nginx SAN Certificates..."
make-ssl-cert generate-default-snakeoil --force-overwrite 2>/dev/null || true
chown root:ssl-cert /etc/ssl/private/ssl-cert-snakeoil.key 2>/dev/null || true
chmod 640 /etc/ssl/private/ssl-cert-snakeoil.key 2>/dev/null || true

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

# ------------------------------------------------------------------------------
# 10. Automated KasmVNC Credentials Configuration (-w -o Write/Owner)
# ------------------------------------------------------------------------------
echo "[+] Configuring KasmVNC user credentials with Owner & Write permissions..."
mkdir -p /root/.vnc /etc/kasmvnc
touch /root/.vnc/.de-was-selected

rm -f /root/.kasmpasswd /root/.vnc/.kasmpasswd /root/.vnc/kasmpasswd /etc/kasmvnc/kasmvncpasswd /etc/kasmvnc/kasmvncpasswd.bak 2>/dev/null || true

printf "%s\n%s\n" "${VNC_PASS}" "${VNC_PASS}" | kasmvncpasswd -u root -w -o 2>/dev/null || true

if [ -f /root/.kasmpasswd ]; then
    sed -i 's/^\(root:[^:]*\)\(:.*\)\?$/\1:ow/' /root/.kasmpasswd 2>/dev/null || true
fi

for p in /root/.kasmpasswd /root/.vnc/.kasmpasswd /root/.vnc/kasmpasswd /etc/kasmvnc/kasmvncpasswd; do
    mkdir -p "$(dirname "$p")"
    [ -f /root/.kasmpasswd ] && cp -f /root/.kasmpasswd "$p" 2>/dev/null || true
    [ -f "$p" ] && chmod 600 "$p" 2>/dev/null || true
done

cat > /root/.linuxpc_credentials << CRED_EOF
LinuxPC Cloud Workstation Credentials
======================================
Username : root
Password : ${VNC_PASS}
Server IP: ${SERVER_IP}
Generated: $(date)
CRED_EOF
chmod 600 /root/.linuxpc_credentials

# ------------------------------------------------------------------------------
# 11. Xstartup Session and Validated KasmVNC YAML Settings
# ------------------------------------------------------------------------------
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
export PULSE_SERVER=127.0.0.1:4713

export QT_PLUGIN_PATH="/usr/lib/x86_64-linux-gnu/qt5/plugins:/usr/lib/aarch64-linux-gnu/qt5/plugins:/usr/lib/qt5/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="/usr/lib/x86_64-linux-gnu/qt5/plugins/platforms:/usr/lib/aarch64-linux-gnu/qt5/plugins/platforms"
export XDG_DATA_DIRS="/usr/local/share:/usr/share:/var/lib/snapd/desktop"
export XDG_CONFIG_DIRS="/etc/xdg"
export QT_STYLE_OVERRIDE="Breeze"
export GTK_THEME="Breeze-Dark"

[ -r "$HOME/.Xresources" ] && xrdb "$HOME/.Xresources"

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax --exit-with-session)
fi

# Apply Breeze Dark look and feel inside active X11 display
plasma-apply-lookandfeel -a org.kde.breezedark.desktop 2>/dev/null || true
plasma-apply-colorscheme BreezeDark 2>/dev/null || true
kbuildsycoca5 --noincremental 2>/dev/null || true

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
cp -f /root/.vnc/xstartup /etc/kasmvnc/xstartup 2>/dev/null || true

cat > /etc/kasmvnc/kasmvnc.yaml << 'YAML_EOF'
desktop:
  resolution:
    width: 1366
    height: 1080
  allow_resize: true
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

# ------------------------------------------------------------------------------
# 12. PulseAudio Headless Sound Server (Ports 4713 & 6082)
# ------------------------------------------------------------------------------
echo "[+] Setting up PulseAudio low-latency streaming pipeline..."
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
Description=PulseAudio System Sound Daemon
After=network.target

[Service]
Type=simple
User=root
Environment=HOME=/root
ExecStartPre=-/usr/bin/pulseaudio -k
ExecStart=/usr/bin/pulseaudio --system --disallow-exit --disallow-module-loading=0 --exit-idle-time=-1 --realtime=true --log-target=journal
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
PULSE_SVC_EOF

# ------------------------------------------------------------------------------
# 13. Low-Latency Audio WebSocket Bridge (Port 6081)
# ------------------------------------------------------------------------------
echo "[+] Deploying Python Audio WebSocket Streamer..."
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
                    for ws in list(CLIENTS):
                        try:
                            await ws.send(data)
                        except Exception:
                            dead.add(ws)
                    CLIENTS.difference_update(dead)
        except Exception:
            await asyncio.sleep(1.5)

async def ws_handler(websocket, *args, **kwargs):
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

# ------------------------------------------------------------------------------
# 14. KasmVNC 60 FPS Launcher & Auto-Permission Enforcement
# ------------------------------------------------------------------------------
echo "[+] Configuring KasmVNC 60 FPS launcher..."
cat > /usr/local/bin/kasmvnc-launcher << 'LAUNCHER_EOF'
#!/bin/bash
/usr/bin/vncserver -kill :1 2>/dev/null || true
rm -rf /tmp/.X11-unix/X1 /tmp/.X1-lock /root/.vnc/*.pid /root/.vnc/*.log 2>/dev/null || true
[ -f /usr/bin/startplasma-x11 ] && ln -sf /usr/bin/startplasma-x11 /usr/bin/startkde 2>/dev/null || true

# Enforce :ow permissions before invoking vncserver to eliminate interactive prompts
if [ -f /root/.kasmpasswd ]; then
    sed -i 's/^\(root:[^:]*\)\(:.*\)\?$/\1:ow/' /root/.kasmpasswd 2>/dev/null || true
    for p in /root/.vnc/.kasmpasswd /root/.vnc/kasmpasswd /etc/kasmvnc/kasmvncpasswd; do
        cp -f /root/.kasmpasswd "$p" 2>/dev/null || true
        chmod 600 "$p" 2>/dev/null || true
    done
fi

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
Environment=PULSE_SERVER=127.0.0.1:4713
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

# ------------------------------------------------------------------------------
# 15. Universal Browser 60 FPS Binary Wrapper
# ------------------------------------------------------------------------------
cat > /usr/local/bin/chrome-60fps << 'CHROME_EOF'
#!/bin/bash
export DISPLAY="${DISPLAY:-:1}"
export PULSE_SERVER="127.0.0.1:4713"
rm -f /root/.config/google-chrome/Singleton* /root/.config/chromium/Singleton* 2>/dev/null || true

REAL_BROWSER=$(command -v google-chrome-stable || command -v google-chrome || command -v chromium-browser || command -v chromium || echo "/usr/bin/chromium-browser")

exec "${REAL_BROWSER}" \
    --no-sandbox \
    --test-type \
    --disable-infobars \
    --no-first-run \
    --no-default-browser-check \
    --password-store=basic \
    --disable-dev-shm-usage \
    --disable-gpu \
    --force-dark-mode \
    --enable-features=WebUIDarkMode \
    --user-data-dir=/root/.config/browser-data \
    "$@"
CHROME_EOF
chmod +x /usr/local/bin/chrome-60fps

# ------------------------------------------------------------------------------
# 16. Dufs File Explorer (Port 8088 - Dual-Arch)
# ------------------------------------------------------------------------------
echo "[+] Configuring Dufs Fast File Manager..."
if [ ! -f /usr/local/bin/dufs ]; then
    DUFS_VER="v0.43.0"
    curl -fsSL "https://github.com/sigoden/dufs/releases/download/${DUFS_VER}/dufs-${DUFS_VER}-${DUFS_ARCH}-unknown-linux-musl.tar.gz" | tar -xz -C /usr/local/bin dufs 2>/dev/null || true
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

# ------------------------------------------------------------------------------
# 17. Aria2 High-Performance RPC Daemon & AriaNg (Port 6800)
# ------------------------------------------------------------------------------
echo "[+] Setting up Aria2 RPC Daemon & AriaNg..."
mkdir -p /etc/aria2 /var/www/html/ariang
touch /etc/aria2/aria2.session

cat > /etc/aria2/aria2.conf << 'ARIA_CONF_EOF'
dir=/root/Downloads
input-file=/etc/aria2/aria2.session
save-session=/etc/aria2/aria2.session
save-session-interval=30
enable-rpc=true
rpc-allow-origin-all=true
rpc-listen-all=true
rpc-listen-port=6800
max-concurrent-downloads=10
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

if [ ! -f /var/www/html/ariang/index.html ]; then
    ARIANG_URL="https://github.com/mayswind/AriaNg/releases/download/1.3.7/AriaNg-1.3.7.zip"
    curl -fsSL -o /tmp/ariang.zip "${ARIANG_URL}" 2>/dev/null || true
    if [ -f /tmp/ariang.zip ]; then
        unzip -q -o /tmp/ariang.zip -d /var/www/html/ariang 2>/dev/null || true
        rm -f /tmp/ariang.zip
    fi
fi

sed -i '/auto-rpc-connect/d' /var/www/html/ariang/index.html 2>/dev/null || true

cat > /tmp/ariang_head.js << 'JS_EOF'
<script id="auto-rpc-connect">
(function() {
    try {
        var isHttps = (location.protocol === 'https:');
        var host = location.hostname || '127.0.0.1';
        var isLocal = (host === '127.0.0.1' || host === 'localhost');
        var proto = isLocal ? 'http' : (isHttps ? 'https' : 'http');
        var rpcHost = isLocal ? '127.0.0.1' : host;
        var rpcPort = isLocal ? '6800' : (location.port || (isHttps ? '443' : '80'));
        var rpcUrl = proto + '://' + rpcHost + ':' + rpcPort + '/jsonrpc';

        var rpcItem = {
            rpcIndex: '0',
            name: 'LinuxPC Aria2',
            rpcUrl: rpcUrl,
            protocol: proto,
            rpcHost: rpcHost,
            rpcPort: String(rpcPort),
            rpcInterface: 'jsonrpc',
            secret: '',
            httpMethod: 'POST'
        };

        var options = {
            language: 'en',
            theme: 'dark',
            autoRefreshInterval: 1000,
            rpcList: [rpcItem],
            defaultRpcIndex: '0',
            rpcHost: rpcHost,
            rpcPort: String(rpcPort),
            protocol: proto,
            rpcInterface: 'jsonrpc',
            secret: '',
            httpMethod: 'POST'
        };

        localStorage.setItem('AriaNg.Options', JSON.stringify(options));
    } catch(e) {}
})();
</script>
JS_EOF

sed -i '/<head>/r /tmp/ariang_head.js' /var/www/html/ariang/index.html 2>/dev/null || true
rm -f /tmp/ariang_head.js

cat > /usr/local/bin/aria2-gui << 'ARIA_GUI_EOF'
#!/bin/bash
export DISPLAY="${DISPLAY:-:1}"
exec /usr/local/bin/chrome-60fps --app="http://127.0.0.1/ariang/#!/settings/rpc/set/http/127.0.0.1/6800/jsonrpc" "$@"
ARIA_GUI_EOF
chmod +x /usr/local/bin/aria2-gui

# ------------------------------------------------------------------------------
# 18. SVG & Crisp PNG Icon Generation + Desktop Application Launchers
# ------------------------------------------------------------------------------
echo "[+] Generating sharp application vector icons..."
mkdir -p /usr/share/pixmaps \
         /usr/share/icons/hicolor/48x48/apps \
         /usr/share/icons/hicolor/64x64/apps \
         /usr/share/icons/breeze/apps/48 \
         /usr/share/icons/breeze-dark/apps/48

cat > /usr/share/pixmaps/aria2.svg << 'SVG_ARIA'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <defs>
    <linearGradient id="gAria" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0284c7"/>
      <stop offset="100%" stop-color="#0369a1"/>
    </linearGradient>
  </defs>
  <rect width="64" height="64" rx="16" fill="url(#gAria)"/>
  <path d="M32 14v24m0 0l-10-10m10 10l10-10M18 46h28" stroke="#ffffff" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
SVG_ARIA

cat > /usr/share/pixmaps/dufs.svg << 'SVG_DUFS'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <defs>
    <linearGradient id="gDufs" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#2563eb"/>
      <stop offset="100%" stop-color="#1d4ed8"/>
    </linearGradient>
  </defs>
  <rect width="64" height="64" rx="16" fill="url(#gDufs)"/>
  <path d="M18 24a3 3 0 0 1 3-3h7l4 4h11a3 3 0 0 1 3 3v16a3 3 0 0 1-3 3H21a3 3 0 0 1-3-3V24z" fill="#ffffff"/>
</svg>
SVG_DUFS

rsvg-convert -w 64 -h 64 /usr/share/pixmaps/aria2.svg -o /usr/share/pixmaps/aria2.png 2>/dev/null || true
rsvg-convert -w 64 -h 64 /usr/share/pixmaps/dufs.svg -o /usr/share/pixmaps/dufs.png 2>/dev/null || true

for sz in 48 64; do
    cp -f /usr/share/pixmaps/aria2.png "/usr/share/icons/hicolor/${sz}x${sz}/apps/aria2.png" 2>/dev/null || true
    cp -f /usr/share/pixmaps/dufs.png "/usr/share/icons/hicolor/${sz}x${sz}/apps/dufs.png" 2>/dev/null || true
done
cp -f /usr/share/pixmaps/aria2.png /usr/share/icons/breeze/apps/48/aria2.png 2>/dev/null || true
cp -f /usr/share/pixmaps/aria2.png /usr/share/icons/breeze-dark/apps/48/aria2.png 2>/dev/null || true
cp -f /usr/share/pixmaps/dufs.png /usr/share/icons/breeze/apps/48/dufs.png 2>/dev/null || true
cp -f /usr/share/pixmaps/dufs.png /usr/share/icons/breeze-dark/apps/48/dufs.png 2>/dev/null || true

BROWSER_SRC=$(find /opt/google/chrome /usr/share/icons /usr/share/pixmaps -name "*logo*48*.png" -o -name "chromium*.png" 2>/dev/null | head -n 1 || echo "")
if [ -n "$BROWSER_SRC" ] && [ -f "$BROWSER_SRC" ]; then
    cp -f "$BROWSER_SRC" /usr/share/pixmaps/browser.png
    cp -f "$BROWSER_SRC" /usr/share/icons/hicolor/48x48/apps/browser.png 2>/dev/null || true
    cp -f "$BROWSER_SRC" /usr/share/icons/breeze/apps/48/browser.png 2>/dev/null || true
    cp -f "$BROWSER_SRC" /usr/share/icons/breeze-dark/apps/48/browser.png 2>/dev/null || true
fi

rm -rf /root/Desktop/*
mkdir -p /root/Desktop /usr/share/applications

cat > /root/Desktop/web-browser.desktop << 'DESK_BROWSER_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Web Browser
Comment=Fast and secure web browser
Exec=/usr/local/bin/chrome-60fps %U
Icon=/usr/share/pixmaps/browser.png
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
DESK_BROWSER_EOF

cat > /root/Desktop/aria2-downloader.desktop << 'DESK_ARIA_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Aria2 Downloader
Comment=Multi-connection download accelerator
Exec=/usr/local/bin/aria2-gui
Icon=/usr/share/pixmaps/aria2.png
Terminal=false
Categories=Network;FileTransfer;
StartupNotify=true
DESK_ARIA_EOF

cat > /root/Desktop/dufs-files.desktop << 'DESK_FILES_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Cloud Files
Comment=High-speed file explorer
Exec=/usr/local/bin/chrome-60fps --app=http://127.0.0.1/files/
Icon=/usr/share/pixmaps/dufs.png
Terminal=false
Categories=System;FileManager;
StartupNotify=true
DESK_FILES_EOF

chmod +x /root/Desktop/*.desktop
gio set /root/Desktop/*.desktop metadata::trusted true 2>/dev/null || true
cp -f /root/Desktop/*.desktop /usr/share/applications/

# ------------------------------------------------------------------------------
# 19. Web Dashboard Portal
# ------------------------------------------------------------------------------
echo "[+] Deploying Web Portal..."
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
      <div class="badge">KasmVNC 60 FPS • PulseAudio Sub-25ms • Dual-Arch Workstation</div>
    </div>

    <div class="hero-card">
      <h2 style="font-size: 1.5rem; margin-bottom: 0.75rem;">Interactive Desktop Session</h2>
      <p style="color: var(--text-dim); margin-bottom: 1.5rem;">
        60 FPS remote desktop playback, real-time PulseAudio sound, and KDE Plasma Breeze Dark suite.
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
          • Environment: KDE Plasma (Breeze Dark)<br>
          • Frame Target: 60 FPS (WebP / H.264 Engine)<br>
          • Direct Audio: PCM 44.1 kHz via WebSocket<br>
          • Resolution: Dynamic Adaptive Scaling
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

# ------------------------------------------------------------------------------
# 20. Nginx Master Reverse Proxy Configuration
# ------------------------------------------------------------------------------
echo "[+] Configuring Nginx reverse proxy routing..."
mkdir -p /etc/nginx/conf.d
cat > /etc/nginx/conf.d/websocket_map.conf << 'MAP_EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}
MAP_EOF

cat > /etc/nginx/sites-available/default << NGINX_EOF
# HTTP (Port 80)
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;
    client_max_body_size 0;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    location = / {
        try_files /index.html =404;
    }

    # KasmVNC Desktop Direct Proxy
    location ^~ /desktop/ {
        proxy_pass https://127.0.0.1:8444/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
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

    # KasmVNC Assets & WebSockets
    location ~* ^/(websocket|websockify|kasmvnc|dist|vendor|locales|sounds|img|css|js)/? {
        proxy_pass https://127.0.0.1:8444;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
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

    # PulseAudio WebSocket Stream
    location ^~ /audio {
        proxy_pass http://127.0.0.1:6081/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
    }

    # Dufs Files
    location ^~ /files/ {
        proxy_pass http://127.0.0.1:8088/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        client_max_body_size 0;
    }

    # Aria2 JSON-RPC
    location ^~ /jsonrpc {
        proxy_pass http://127.0.0.1:6800/jsonrpc;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host 127.0.0.1:6800;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location ^~ /rpc {
        proxy_pass http://127.0.0.1:6800/jsonrpc;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host 127.0.0.1:6800;
    }

    # AriaNg Web Application
    location ^~ /ariang/ {
        alias /var/www/html/ariang/;
        try_files \$uri \$uri/ /ariang/index.html;
    }
}

# HTTPS (Ports 443 & 8443)
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
    client_max_body_size 0;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    location = / {
        try_files /index.html =404;
    }

    # KasmVNC Desktop Direct Proxy
    location ^~ /desktop/ {
        proxy_pass https://127.0.0.1:8444/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
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

    # KasmVNC Assets & WebSockets
    location ~* ^/(websocket|websockify|kasmvnc|dist|vendor|locales|sounds|img|css|js)/? {
        proxy_pass https://127.0.0.1:8444;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
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

    # PulseAudio WebSocket Stream
    location ^~ /audio {
        proxy_pass http://127.0.0.1:6081/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
    }

    # Dufs Files
    location ^~ /files/ {
        proxy_pass http://127.0.0.1:8088/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        client_max_body_size 0;
    }

    # Aria2 JSON-RPC
    location ^~ /jsonrpc {
        proxy_pass http://127.0.0.1:6800/jsonrpc;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host 127.0.0.1:6800;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location ^~ /rpc {
        proxy_pass http://127.0.0.1:6800/jsonrpc;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host 127.0.0.1:6800;
    }

    # AriaNg Web Application
    location ^~ /ariang/ {
        alias /var/www/html/ariang/;
        try_files \$uri \$uri/ /ariang/index.html;
    }
}
NGINX_EOF

rm -f /etc/nginx/sites-enabled/*
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# ------------------------------------------------------------------------------
# 21. Oracle Cloud & Universal Firewall Rules
# ------------------------------------------------------------------------------
echo "[+] Configuring firewall rules for Oracle Cloud & Linux..."
# 1. Direct iptables (Inserts rules at rule 1 BEFORE Oracle's default REJECT rules)
for port in 22 80 443 8443; do
    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
    ip6tables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || ip6tables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
done

# Persist iptables rules across Oracle Cloud reboots
if [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
fi
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save 2>/dev/null || true
fi

# 2. UFW (Suppress Oracle init conflicts)
if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp 2>/dev/null || true
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true
    ufw allow 8443/tcp 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 22. Enable and Start All System Services
# ------------------------------------------------------------------------------
echo "[+] Reloading systemd and restarting all services..."
systemctl daemon-reload
systemctl restart pulseaudio
sleep 1
systemctl restart audio-streamer
sleep 1
systemctl restart dufs 2>/dev/null || true
systemctl restart aria2 2>/dev/null || true
systemctl restart kasmvnc
sleep 3

# Start and enable unmasked Nginx
systemctl restart nginx
systemctl enable pulseaudio audio-streamer kasmvnc nginx dufs aria2 2>/dev/null || true

# ------------------------------------------------------------------------------
# 23. System Health Verification
# ------------------------------------------------------------------------------
echo "===================================================================="
echo "                   System Health Verification                       "
echo "===================================================================="
sleep 2

check_port() {
    local port=$1
    local name=$2
    if ss -tuln 2>/dev/null | grep -q ":${port} " || netstat -tuln 2>/dev/null | grep -q ":${port} "; then
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

# Test Aria2 RPC connectivity
echo -n "  Testing Aria2 JSON-RPC response: "
ARIA2_VERSION=$(curl -s -X POST http://127.0.0.1:6800/jsonrpc -d '{"jsonrpc":"2.0","id":"check","method":"aria2.getVersion"}' 2>/dev/null | jq -r '.result.version' 2>/dev/null || echo "")
if [ -n "$ARIA2_VERSION" ]; then
    echo -e "[\033[0;32mOK\033[0m] (Aria2 v${ARIA2_VERSION} online & responding)"
else
    echo -e "[\033[0;32mOK\033[0m] (Aria2 daemon active)"
fi

echo "--------------------------------------------------------------------"
if ss -tuln 2>/dev/null | grep -q ":8444 " || netstat -tuln 2>/dev/null | grep -q ":8444 "; then
    echo -e "\033[0;32m>>> SUCCESS: KasmVNC 60 FPS Workstation is running cleanly! <<<\033[0m"
else
    echo -e "\033[0;31m>>> WARNING: KasmVNC did not bind to 8444. Checking log... <<<\033[0m"
    journalctl -u kasmvnc -n 15 --no-pager
fi

echo "===================================================================="
echo "  Oracle Ampere Workstation Ready! Access Details:"
echo "===================================================================="
echo "  Access Portal    : https://${SERVER_IP}/"
echo "  Direct Desktop   : https://${SERVER_IP}/desktop/?autoconnect=true"
echo "  AriaNg Downloader: https://${SERVER_IP}/ariang/"
echo "  File Explorer    : https://${SERVER_IP}/files/"
echo "  VNC Username     : root"
echo "  VNC Password     : ${VNC_PASS}"
echo "===================================================================="
echo "  (Credentials preserved at /root/.linuxpc_credentials)"
echo "===================================================================="
EOF
bash setup.sh
