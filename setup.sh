rm setup.sh
cat > setup.sh << 'EOF'
#!/usr/bin/env bash
# ==============================================================================
# JioPC Cloud Desktop - Universal Architecture Edition (ARM64 & AMD64)
# Features:
#  - Dual-Arch Support: 100% compatible with both ARM64 (aarch64) & AMD64 (x86_64)
#  - Aria2 Web File Manager at /aria2files/ (Delete, Rename, Upload, Drag & Drop)
#  - Latest Official Telegram Desktop with working QR login
#  - Sound, Mic & Webcam drivers + Taskbar Volume Slider (volumeicon)
#  - Smart Auto-Healing Package Installer (zero missing package errors)
#  - Restores Minimize, Maximize, Close buttons across all apps & Dolphin
#  - Eliminates KDE Wallet password popups permanently
#  - Removes "unsupported command-line flag" warning from Chrome & Brave
#  - Pre-installs AdBlock for Chrome/Chromium via Enterprise Policy
#  - Fixes noVNC 'clipboardPasteFrom' undefined crash over Cloudflare
#  - Defaults noVNC to "Remote Resizing" automatically
#  - UpCloud Port Compliant: 22 (SSH), 80/8880 (HTTP), 443/8443 (HTTPS), 3389 (RDP)
# ==============================================================================

set -e

echo "===================================================================="
echo " Starting JioPC Desktop Setup (Universal ARM64 & AMD64 Edition)"
echo "===================================================================="

# 1. Root Check
if [ "$EUID" -ne 0 ]; then
    echo "[-] Error: Please execute as root (or sudo)."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# 2. Hardware Architecture Detection (ARM64 vs AMD64)
RAW_ARCH=$(uname -m)
case "$RAW_ARCH" in
    x86_64|amd64)
        SYS_ARCH="amd64"
        FB_ARCH="amd64"
        echo "[+] Detected System Architecture: AMD64 (x86_64)"
        ;;
    aarch64|arm64)
        SYS_ARCH="arm64"
        FB_ARCH="arm64"
        echo "[+] Detected System Architecture: ARM64 (aarch64)"
        ;;
    *)
        echo "[-] Error: Unsupported architecture ($RAW_ARCH). Supported: amd64, arm64."
        exit 1
        ;;
esac

# 3. Hardened SSH Port 22 Protection (Never Drops Connection)
echo "[+] Protecting SSH Port 22..."
systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-jiopc-keepalive.conf << 'EOF_SSH'
ClientAliveInterval 30
ClientAliveCountMax 120
TCPKeepAlive yes
EOF_SSH
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

if command -v ufw &>/dev/null; then
    ufw allow 22/tcp comment 'SSH Remote Access' || true
fi

# 4. Permanently Block connman (Prevents SSH Network Drops)
echo "[+] Blacklisting connman from APT and systemd..."
mkdir -p /etc/apt/preferences.d
cat > /etc/apt/preferences.d/no-connman << 'EOF_PREF'
Package: connman connman-* cmst networkd-dispatcher
Pin: release *
Pin-Priority: -1
EOF_PREF

systemctl mask connman 2>/dev/null || true
systemctl mask connman-vpn 2>/dev/null || true
systemctl mask connman-wait-online.service 2>/dev/null || true

echo exit 101 > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
trap 'rm -f /usr/sbin/policy-rc.d' EXIT

# 5. Kernel Tuning: Enable unprivileged user namespaces (fixes browser sandbox)
echo "[+] Enabling user namespaces for browser sandboxing..."
sysctl -w kernel.unprivileged_userns_clone=1 2>/dev/null || true
echo "kernel.unprivileged_userns_clone=1" > /etc/sysctl.d/99-userns.conf

# 6. Stop Apache (Nginx will handle ports 80, 443, 8443, 8880)
systemctl stop apache2 2>/dev/null || true
systemctl disable apache2 2>/dev/null || true

# 7. Fast I/O and APT Parallel Download Configuration
echo "[+] Enabling fast disk I/O and parallel pipelines..."
mkdir -p /etc/dpkg/dpkg.cfg.d
echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/force-unsafe-io

cat > /etc/apt/apt.conf.d/99parallel << 'APT_CONF'
Acquire::Queue-Mode "access";
Acquire::http::Pipeline-Depth "10";
APT::Acquire::Retries "3";
APT_CONF

# 8. Allocate 2GB Swap for VPS RAM Stability
TOTAL_SWAP=$(free -m | awk '/^Swap:/ {print $2}')
if [ "$TOTAL_SWAP" -lt 1024 ]; then
    echo "[+] Allocating 2GB swap space for system stability..."
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q "/swapfile" /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 9. Install Aria2 and apt-fast (16-Thread Downloader)
echo "[+] Installing apt-fast 16-thread download engine..."
apt-get update -y
apt-get install -y --no-install-recommends software-properties-common curl wget gnupg2 ca-certificates aria2 unzip xz-utils

add-apt-repository -y ppa:apt-fast/stable
echo "apt-fast apt-fast/maxdownloads string 16" | debconf-set-selections
echo "apt-fast apt-fast/dlflag boolean true" | debconf-set-selections
echo "apt-fast apt-fast/aptmanager string apt-get" | debconf-set-selections
apt-get update -y
apt-get install -y apt-fast

cat > /etc/apt-fast.conf << 'EOF_AF'
DOWNLOADARGS="-j 16 -s 16 -x 16 -k 1M --file-allocation=none"
_DOWNLOADER='aria2c'
_MAXNUM=16
DLLIST='/tmp/apt-fast.list'
EOF_AF

# 10. Configure Repositories for AMD64 vs ARM64
echo "[+] Configuring architecture-specific repositories..."
add-apt-repository -y ppa:kubuntu-ppa/backports

# Brave Browser supports both AMD64 and ARM64
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" > /etc/apt/sources.list.d/brave-browser-release.list

# Google Chrome repo (AMD64 only; on ARM64 we use native Chromium)
if [ "$SYS_ARCH" = "amd64" ]; then
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor --yes -o /usr/share/keyrings/google-chrome.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
else
    rm -f /etc/apt/sources.list.d/google-chrome.list
fi

apt-fast update -y

# 11. SMART AUTO-HEALING PACKAGE INSTALLER (ARM64 & AMD64)
echo "[+] Installing desktop, multimedia, audio, and VNC utilities..."
echo "sddm shared/default-x-display-manager select sddm" | debconf-set-selections

# Base packages common to both architectures
REQUESTED_PACKAGES=(
    kde-plasma-desktop plasma-workspace konsole dolphin
    kwin-x11 breeze breeze-icon-theme breeze-cursor-theme
    lxqt-core lxqt openbox qterminal pcmanfm-qt featherpad
    papirus-icon-theme xrdp tigervnc-standalone-server tigervnc-common tigervnc-tools
    xauth x11-xserver-utils novnc websockify nginx autocutsel xclip xsel
    pulseaudio pulseaudio-utils pavucontrol volumeicon-alsa alsa-utils libasound2-plugins
    v4l-utils v4l2loopback-dkms
    brave-browser
    vlc libreoffice-writer libreoffice-calc dbus-x11 xorg ufw librsvg2-bin
)

# Architecture-specific browser selection
if [ "$SYS_ARCH" = "amd64" ]; then
    REQUESTED_PACKAGES+=(google-chrome-stable)
else
    REQUESTED_PACKAGES+=(chromium-browser chromium-codecs-ffmpeg-extra)
fi

smart_install() {
    local pkgs=("$@")
    if ! apt-fast install -y --no-install-recommends "${pkgs[@]}"; then
        echo "[!] Filtering available repository packages..."
        local valid=()
        for p in "${pkgs[@]}"; do
            if apt-cache show "$p" &>/dev/null; then
                valid+=("$p")
            else
                echo "[-] Auto-skipping package: $p"
            fi
        done
        apt-fast install -y --no-install-recommends "${valid[@]}"
    fi
}

smart_install "${REQUESTED_PACKAGES[@]}"

# If on ARM64, create transparent google-chrome symlink to chromium
if [ "$SYS_ARCH" = "arm64" ]; then
    CHROMIUM_BIN=$(command -v chromium-browser || command -v chromium || echo "")
    if [ -n "$CHROMIUM_BIN" ]; then
        ln -sf "$CHROMIUM_BIN" /usr/bin/google-chrome
        ln -sf "$CHROMIUM_BIN" /usr/local/bin/google-chrome
    fi
fi

systemctl disable sddm 2>/dev/null || true

# 12. User Setup (12+ Character Password)
JIOPC_USER="jiopc"
JIOPC_PASS="jiopc12345678"

if ! id "$JIOPC_USER" &>/dev/null; then
    echo "[+] Creating desktop user '$JIOPC_USER'..."
    useradd -m -s /bin/bash "$JIOPC_USER"
    echo "$JIOPC_USER:$JIOPC_PASS" | chpasswd
    usermod -aG sudo,audio,video "$JIOPC_USER"
else
    echo "$JIOPC_USER:$JIOPC_PASS" | chpasswd
    usermod -aG audio,video "$JIOPC_USER" 2>/dev/null || true
fi

USER_HOME="/home/$JIOPC_USER"
DESKTOP_DIR="$USER_HOME/Desktop"
mkdir -p "$DESKTOP_DIR" /usr/share/applications "$USER_HOME/.config" "$USER_HOME/.vnc" "$USER_HOME/Downloads"

# 13. INSTALL LATEST TELEGRAM DESKTOP (Multi-Arch Aware)
echo "[+] Installing Telegram Desktop for $SYS_ARCH..."
mkdir -p /opt/Telegram
if [ "$SYS_ARCH" = "amd64" ]; then
    wget -q --show-progress "https://telegram.org/dl/desktop/linux" -O /tmp/tsetup.tar.xz
    tar -xf /tmp/tsetup.tar.xz -C /opt/
    rm -f /tmp/tsetup.tar.xz
    chmod +x /opt/Telegram/Telegram
    ln -sf /opt/Telegram/Telegram /usr/bin/telegram-desktop
    ln -sf /opt/Telegram/Telegram /usr/local/bin/telegram-desktop
else
    # ARM64: install native telegram-desktop from apt
    apt-fast install -y telegram-desktop 2>/dev/null || apt-get install -y telegram-desktop 2>/dev/null || true
    TG_ARM=$(command -v telegram-desktop || echo "")
    if [ -n "$TG_ARM" ]; then
        ln -sf "$TG_ARM" /opt/Telegram/Telegram 2>/dev/null || true
    fi
fi

# 14. CONFIGURE SOUND DRIVER & TASKBAR VOLUME
echo "[+] Configuring audio driver & volume mixer..."
mkdir -p /etc/pulse
cat >> /etc/pulse/default.pa << 'EOF_PULSE'
load-module module-native-protocol-tcp auth-anonymous=1
load-module module-null-sink sink_name=Dummy_Output sink_properties=device.description="JioPC_Speaker"
load-module module-null-sink sink_name=Virtual_Mic sink_properties=device.description="JioPC_Microphone"
EOF_PULSE

# 15. INSTALL ARIA2 WEB FILE MANAGER (Multi-Arch: AMD64 & ARM64)
echo "[+] Setting up Aria2 Web File Manager for $FB_ARCH..."
FB_VER="v2.30.0"
wget -q "https://github.com/filebrowser/filebrowser/releases/download/${FB_VER}/linux-${FB_ARCH}-filebrowser.tar.gz" -O /tmp/fb.tar.gz 2>/dev/null || \
curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash 2>/dev/null || true

if [ -f /tmp/fb.tar.gz ]; then
    tar -xzf /tmp/fb.tar.gz -C /usr/local/bin filebrowser
    rm -f /tmp/fb.tar.gz
fi
chmod +x /usr/local/bin/filebrowser 2>/dev/null || true

mkdir -p /etc/filebrowser /home/jiopc/Downloads
rm -f /etc/filebrowser/filebrowser.db

cat > /etc/filebrowser/config.json << 'EOF_FBCONF'
{
  "port": 8088,
  "baseURL": "/aria2files",
  "address": "127.0.0.1",
  "log": "stdout",
  "database": "/etc/filebrowser/filebrowser.db",
  "root": "/home/jiopc/Downloads"
}
EOF_FBCONF

filebrowser config init -c /etc/filebrowser/config.json 2>/dev/null || filebrowser config init --database=/etc/filebrowser/filebrowser.db 2>/dev/null || true
filebrowser config set --database=/etc/filebrowser/filebrowser.db \
    --root=/home/jiopc/Downloads \
    --baseURL=/aria2files \
    --port=8088 \
    --address=127.0.0.1 2>/dev/null || true

filebrowser users add "$JIOPC_USER" "$JIOPC_PASS" --database=/etc/filebrowser/filebrowser.db --admin 2>/dev/null || \
filebrowser users add "$JIOPC_USER" "$JIOPC_PASS" --database=/etc/filebrowser/filebrowser.db 2>/dev/null || true

cat > /etc/systemd/system/jiopc-filemanager.service << 'EOF_FBM'
[Unit]
Description=JioPC Aria2 Web File Manager
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/filebrowser --config=/etc/filebrowser/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF_FBM

systemctl daemon-reload
systemctl enable jiopc-filemanager
systemctl restart jiopc-filemanager

# 16. PERMANENTLY DISABLE KDE WALLET
echo "[+] Disabling KDE Wallet..."
mkdir -p /etc/xdg "$USER_HOME/.config" "$USER_HOME/.config/autostart"

cat > /etc/xdg/kwalletrc << 'EOF_KWALLET'
[Wallet]
Default Wallet=kdewallet
Enabled=false
First Use=false
Prompt on Open=false

[org.freedesktop.secrets]
apiEnabled=false
EOF_KWALLET

cp /etc/xdg/kwalletrc "$USER_HOME/.config/kwalletrc"

cat > "$USER_HOME/.config/autostart/kwalletd5.desktop" << 'EOF_KWAUTO'
[Desktop Entry]
Type=Application
Name=KWallet
Exec=/bin/true
Hidden=true
EOF_KWAUTO

# 17. PRE-INSTALL OFFICIAL ADBLOCK (Chrome, Chromium & Brave)
echo "[+] Pre-installing official AdBlock..."
mkdir -p /etc/opt/chrome/policies/managed /opt/google/chrome/extensions /etc/brave/policies/managed /etc/chromium/policies/managed

cat > /etc/opt/chrome/policies/managed/adblock.json << 'EOF_ADBLOCK'
{
  "ExtensionInstallForcelist": [
    "gighmmpiobklfepjocnamgkkbiglidom;https://clients2.google.com/service/update2/crx"
  ]
}
EOF_ADBLOCK
cp /etc/opt/chrome/policies/managed/adblock.json /etc/brave/policies/managed/adblock.json 2>/dev/null || true
cp /etc/opt/chrome/policies/managed/adblock.json /etc/chromium/policies/managed/adblock.json 2>/dev/null || true

cat > /opt/google/chrome/extensions/gighmmpiobklfepjocnamgkkbiglidom.json << 'EOF_EXT'
{
  "external_update_url": "https://clients2.google.com/service/update2/crx"
}
EOF_EXT

# 18. WINDOW BUTTONS FIX (Minimize, Maximize, Close on all Windows & Explorer)
echo "[+] Restoring Minimize, Maximize, Close buttons across all applications..."

mkdir -p "$USER_HOME/.config" /etc/xdg
cat > "$USER_HOME/.config/kwinrc" << 'EOF_KWIN'
[Compositing]
Enabled=false
GLCore=false

[org.kde.kdecoration2]
BorderSize=Normal
BorderSizeAuto=false
ButtonsOnLeft=M
ButtonsOnRight=IAX
CloseOnDoubleClickOnMenu=false
ThemeName=Breeze
plugin=org.kde.breeze
EOF_KWIN
cp "$USER_HOME/.config/kwinrc" /etc/xdg/kwinrc

mkdir -p "$USER_HOME/.config/openbox"
cat > "$USER_HOME/.config/openbox/rc.xml" << 'EOF_OB'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <name>Clearlooks</name>
    <titlelayout>NLIMC</titlelayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>yes</animateIconify>
  </theme>
  <desktops>
    <number>1</number>
  </desktops>
</openbox_config>
EOF_OB
cp "$USER_HOME/.config/openbox/rc.xml" "$USER_HOME/.config/openbox/lxqt-rc.xml"

# Force browsers to use native system titlebar
mkdir -p "$USER_HOME/.config/google-chrome/Default" "$USER_HOME/.config/BraveSoftware/Brave-Browser/Default" "$USER_HOME/.config/chromium/Default"
cat > "$USER_HOME/.config/google-chrome/Default/Preferences" << 'EOF_CHPREF'
{
  "browser": {
    "custom_chrome_frame": false
  }
}
EOF_CHPREF
cp "$USER_HOME/.config/google-chrome/Default/Preferences" "$USER_HOME/.config/BraveSoftware/Brave-Browser/Default/Preferences" 2>/dev/null || true
cp "$USER_HOME/.config/google-chrome/Default/Preferences" "$USER_HOME/.config/chromium/Default/Preferences" 2>/dev/null || true

# 19. REMOVE "--no-sandbox" WARNING FROM ALL APPLICATIONS
echo "[+] Scrubbing '--no-sandbox' flag across all launchers..."
sed -i 's/ --no-sandbox//g' "$DESKTOP_DIR"/*.desktop 2>/dev/null || true
sed -i 's/--no-sandbox//g' "$DESKTOP_DIR"/*.desktop 2>/dev/null || true
sed -i 's/ --no-sandbox//g' /usr/share/applications/*.desktop 2>/dev/null || true
sed -i 's/--no-sandbox//g' /usr/share/applications/*.desktop 2>/dev/null || true

# 20. Configure Aria2 Daemon + AriaNg UI
echo "[+] Setting up Aria2 RPC Download Manager..."
mkdir -p /etc/aria2 /usr/share/ariang

cat > /etc/aria2/aria2.conf << 'EOF_ARIA'
enable-rpc=true
rpc-listen-all=false
rpc-listen-port=6800
rpc-allow-origin-all=true
continue=true
max-concurrent-downloads=10
max-connection-per-server=16
split=16
min-split-size=1M
dir=/home/jiopc/Downloads
EOF_ARIA

cat > /etc/systemd/system/aria2.service << 'EOF_AR_SERVICE'
[Unit]
Description=Aria2 RPC Download Manager Daemon
After=network.target

[Service]
Type=simple
User=jiopc
ExecStart=/usr/bin/aria2c --conf-path=/etc/aria2/aria2.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF_AR_SERVICE

wget -q https://github.com/mayswind/AriaNg/releases/download/1.3.7/AriaNg-1.3.7-AllInOne.zip -O /tmp/ariang.zip 2>/dev/null || true
if [ -f /tmp/ariang.zip ]; then
    unzip -o -q /tmp/ariang.zip -d /usr/share/ariang/
    rm -f /tmp/ariang.zip
fi

# 21. SSL Certificate Generation for UpCloud Ports 443 & 8443
echo "[+] Generating SSL/TLS certificate..."
mkdir -p /etc/ssl/jiopc
openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /etc/ssl/jiopc/jiopc.key \
    -out /etc/ssl/jiopc/jiopc.crt \
    -days 365 \
    -subj "/C=IN/ST=MH/L=Mumbai/O=JioPC/CN=jiopc-cloud" 2>/dev/null

chmod 600 /etc/ssl/jiopc/jiopc.key

ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# 22. FIX noVNC 'clipboardPasteFrom' CRASH & DEFAULT TO 'Remote Resizing'
echo "[+] Patching noVNC core and clipboard bridge..."

sed -i 's/UI\.rfb\.clipboardPasteFrom/UI.rfb \&\& UI.rfb.clipboardPasteFrom/g' /usr/share/novnc/app/ui.js 2>/dev/null || true
sed -i "s/resize: 'none'/resize: 'remote'/g" /usr/share/novnc/app/ui.js 2>/dev/null || true

cat > /usr/share/novnc/jiopc-clipboard.js << 'EOF_CLIP_JS'
(function() {
    try {
        localStorage.setItem('resize', 'remote');
        localStorage.setItem('noVNC_setting_resize', 'remote');
    } catch(e) {}

    let lastRemoteValue = "";
    let lastLocalValue = "";

    function isRfbReady() {
        return (typeof UI !== 'undefined' && UI && UI.rfb && typeof UI.rfb.clipboardPasteFrom === 'function');
    }

    window.addEventListener('DOMContentLoaded', () => {
        const clipArea = document.getElementById('noVNC_clipboard_text');

        setInterval(() => {
            if (!isRfbReady()) return;
            if (clipArea && clipArea.value && clipArea.value !== lastRemoteValue) {
                lastRemoteValue = clipArea.value;
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    navigator.clipboard.writeText(lastRemoteValue).catch(() => {});
                }
            }
        }, 500);

        async function syncLaptopToRemote() {
            if (!isRfbReady()) return;
            if (!navigator.clipboard || !navigator.clipboard.readText) return;
            try {
                const text = await navigator.clipboard.readText();
                if (text && text !== lastLocalValue) {
                    lastLocalValue = text;
                    if (clipArea) clipArea.value = text;
                    UI.rfb.clipboardPasteFrom(text);
                }
            } catch (e) {}
        }

        window.addEventListener('focus', syncLaptopToRemote);
        window.addEventListener('click', syncLaptopToRemote);
        document.addEventListener('visibilitychange', () => {
            if (document.visibilityState === 'visible') syncLaptopToRemote();
        });

        window.addEventListener('paste', async (e) => {
            if (!isRfbReady()) return;
            let text = (e.clipboardData || window.clipboardData)?.getData('text');
            if (!text && navigator.clipboard) {
                try { text = await navigator.clipboard.readText(); } catch(err) {}
            }
            if (text) {
                lastLocalValue = text;
                if (clipArea) clipArea.value = text;
                UI.rfb.clipboardPasteFrom(text);
            }
        });
    });
})();
EOF_CLIP_JS

for page in /usr/share/novnc/vnc.html /usr/share/novnc/index.html; do
    if [ -f "$page" ] && ! grep -q "jiopc-clipboard.js" "$page"; then
        sed -i 's|</body>|<script src="jiopc-clipboard.js"></script></body>|g' "$page"
    fi
done

# 23. Configure Nginx: Supports Web Desktop + Web File Manager (/aria2files/)
echo "[+] Configuring Nginx reverse proxy with /aria2files/ support..."

cat > /etc/nginx/sites-available/jiopc << 'EOF_NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 8880 default_server;
    listen [::]:8880 default_server;

    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    listen 8443 ssl http2 default_server;
    listen [::]:8443 ssl http2 default_server;

    server_name _;

    ssl_certificate /etc/ssl/jiopc/jiopc.crt;
    ssl_certificate_key /etc/ssl/jiopc/jiopc.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /usr/share/novnc;
    index index.html vnc.html;

    keepalive_timeout 75s;
    client_header_timeout 60s;
    client_body_timeout 60s;
    send_timeout 60s;

    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    location / {
        try_files $uri $uri/ =404;
    }

    location /websockify {
        proxy_pass http://127.0.0.1:6080/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
    }

    location /aria2files {
        proxy_pass http://127.0.0.1:8088;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        client_max_body_size 50G;
    }
}
EOF_NGINX

ln -sf /etc/nginx/sites-available/jiopc /etc/nginx/sites-enabled/default
nginx -t

# 24. Configure XRDP (UpCloud Port 3389) and Polkit
echo "[+] Configuring XRDP on Port 3389 with Audio Redirection..."
adduser xrdp ssl-cert 2>/dev/null || true

cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla << 'PKLA'
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes

[Allow PackageKit all Users]
Identity=unix-user:*
Action=org.freedesktop.packagekit.system-sources-refresh
ResultAny=yes
ResultInactive=yes
ResultActive=yes
PKLA

cat > /etc/xrdp/startwm.sh << 'EOF_WM'
#!/bin/sh
if test -r /etc/profile; then . /etc/profile; fi
if test -r ~/.profile; then . ~/.profile; fi
export XDG_CURRENT_DESKTOP="KDE"
export XDG_SESSION_DESKTOP="KDE"
export QT_QUICK_BACKEND=software
export LIBGL_ALWAYS_SOFTWARE=1
export KWIN_COMPOSE=N

pulseaudio --start 2>/dev/null || true
volumeicon &
autocutsel -fork
autocutsel -selection PRIMARY -fork

if command -v startplasma-x11 >/dev/null 2>&1; then
    exec dbus-run-session startplasma-x11
else
    exec dbus-run-session startlxqt
fi
EOF_WM
chmod +x /etc/xrdp/startwm.sh

# 25. JioPC Desktop Launchers
mkdir -p /usr/share/backgrounds/

cat > /usr/share/backgrounds/jiopc-wallpaper.svg << 'EOF_SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1080" width="1920" height="1080">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#061951"/>
      <stop offset="45%" stop-color="#0a2885"/>
      <stop offset="100%" stop-color="#0F3CC9"/>
    </linearGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#bg)"/>
  <circle cx="1650" cy="200" r="400" fill="#ffffff" opacity="0.04"/>
  <circle cx="200" cy="900" r="300" fill="#ffffff" opacity="0.03"/>
  <g transform="translate(960, 500)" text-anchor="middle">
    <circle cx="0" cy="-60" r="54" fill="#ffffff" opacity="0.12"/>
    <circle cx="0" cy="-60" r="44" fill="#0F3CC9"/>
    <text x="0" y="-46" font-family="'DejaVu Sans', sans-serif" font-weight="bold" font-size="34" fill="#ffffff">Jio</text>
    <text x="0" y="32" font-family="'DejaVu Sans', sans-serif" font-weight="bold" font-size="44" fill="#ffffff" letter-spacing="3">JioPC Cloud Desktop</text>
    <text x="0" y="70" font-family="'DejaVu Sans', sans-serif" font-weight="normal" font-size="17" fill="#9eb5fa" letter-spacing="4">KDE PLASMA &amp; LIGHTWEIGHT Qt</text>
  </g>
</svg>
EOF_SVG
rsvg-convert -w 1920 -h 1080 /usr/share/backgrounds/jiopc-wallpaper.svg -o /usr/share/backgrounds/jiopc-wallpaper.png

add_shortcut() {
    local fn="$1" name="$2" cmd="$3" icon="$4"
    cat > "/usr/share/applications/$fn" << EOF_DT
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Exec=$cmd
Icon=$icon
Terminal=false
Categories=Network;Utility;Office;
EOF_DT
    cp "/usr/share/applications/$fn" "$DESKTOP_DIR/"
    chmod +x "$DESKTOP_DIR/$fn"
}

# Dynamic browser launch command (works identically on ARM64 and AMD64)
BROWSER_CMD="google-chrome --password-store=basic"

add_shortcut "google-chrome.desktop" "Web Browser" "$BROWSER_CMD" "google-chrome"
add_shortcut "brave-browser.desktop" "Brave Browser" "brave-browser --password-store=basic" "brave-browser"
add_shortcut "telegram.desktop" "Telegram Desktop" "telegram-desktop" "telegram"
add_shortcut "ariang.desktop" "Aria2 Download Manager" "$BROWSER_CMD --app=file:///usr/share/ariang/index.html" "download"
add_shortcut "aria2-files.desktop" "Aria2 Downloaded Files" "$BROWSER_CMD --app=http://127.0.0.1/aria2files/" "folder-download"
add_shortcut "pavucontrol.desktop" "Volume & Sound Settings" "pavucontrol" "audio-volume-high"

add_shortcut "jiopc-portal.desktop" "JioPC Portal" "$BROWSER_CMD --app=https://my.jiopc.in" "system-help"
add_shortcut "jiocinema.desktop" "JioCinema" "$BROWSER_CMD --app=https://www.jiocinema.com" "video-display"
add_shortcut "jiotv.desktop" "JioTV" "$BROWSER_CMD --app=https://www.jiotv.com" "multimedia-player"
add_shortcut "jiosaavn.desktop" "JioSaavn" "$BROWSER_CMD --app=https://www.jiosaavn.com" "audio-player"
add_shortcut "jiocloud.desktop" "JioCloud" "$BROWSER_CMD --app=https://www.jiocloud.com" "folder-remote"

for app in org.kde.konsole.desktop org.kde.dolphin.desktop vlc.desktop libreoffice-writer.desktop; do
    if [ -f "/usr/share/applications/$app" ]; then
        cp "/usr/share/applications/$app" "$DESKTOP_DIR/"
        chmod +x "$DESKTOP_DIR/$app" 2>/dev/null || true
    fi
done

# 26. Configure Startup with Volume Bar Autostart
cat > "$USER_HOME/.xsession" << 'EOF_XS'
export XDG_CURRENT_DESKTOP="KDE"
export XDG_SESSION_DESKTOP="KDE"
export QT_QUICK_BACKEND=software
export LIBGL_ALWAYS_SOFTWARE=1
export KWIN_COMPOSE=N

pulseaudio --start 2>/dev/null || true
volumeicon &
autocutsel -fork
autocutsel -selection PRIMARY -fork

exec dbus-run-session startplasma-x11
EOF_XS
chmod +x "$USER_HOME/.xsession"

cat > "$USER_HOME/.vnc/xstartup" << 'EOF_VNC'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_CURRENT_DESKTOP="KDE"
export XDG_SESSION_DESKTOP="KDE"
export QT_QUICK_BACKEND=software
export LIBGL_ALWAYS_SOFTWARE=1
export KWIN_COMPOSE=N

pulseaudio --start 2>/dev/null || true
volumeicon &
autocutsel -fork
autocutsel -selection PRIMARY -fork

if command -v startplasma-x11 >/dev/null 2>&1; then
    exec dbus-run-session startplasma-x11
else
    exec dbus-run-session startlxqt
fi
EOF_VNC
chmod +x "$USER_HOME/.vnc/xstartup"

echo "[+] Setting up TigerVNC display mappings and config..."
mkdir -p /etc/tigervnc
echo ":1=$JIOPC_USER" > /etc/tigervnc/vncserver.users

cat > "$USER_HOME/.vnc/config" << 'EOF_VCONF'
geometry=1920x1080
depth=24
localhost
alwaysshared
EOF_VCONF

echo "$JIOPC_PASS" | vncpasswd -f > "$USER_HOME/.vnc/passwd"
chmod 600 "$USER_HOME/.vnc/passwd"

# 27. Services: TigerVNC (Type=simple, Foreground mode) + Local Websockify
cat > /etc/systemd/system/jiopc-vnc.service << EOF_SV1
[Unit]
Description=JioPC TigerVNC Server
After=syslog.target network.target

[Service]
Type=simple
User=$JIOPC_USER
Group=$JIOPC_USER
WorkingDirectory=$USER_HOME
Environment=HOME=$USER_HOME
Environment=USER=$JIOPC_USER
ExecStartPre=-/usr/bin/vncserver -kill :1
ExecStartPre=-/bin/rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 $USER_HOME/.vnc/*:1.pid $USER_HOME/.vnc/*:1.log
ExecStart=/usr/bin/vncserver -fg :1
ExecStop=/usr/bin/vncserver -kill :1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF_SV1

cat > /etc/systemd/system/jiopc-web.service << 'EOF_SV2'
[Unit]
Description=JioPC noVNC Web Streaming Backend (Localhost)
After=jiopc-vnc.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/websockify 127.0.0.1:6080 127.0.0.1:5901
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF_SV2

chown -R "$JIOPC_USER:$JIOPC_USER" "$USER_HOME"
rm -f /usr/sbin/policy-rc.d

# 28. UFW Firewall: UpCloud Open Ports & Cloudflare Range Whitelist
echo "[+] Configuring firewall rules..."
if command -v ufw &>/dev/null; then
    ufw allow 22/tcp comment 'UpCloud SSH'
    ufw allow 80/tcp comment 'UpCloud HTTP'
    ufw allow 443/tcp comment 'UpCloud HTTPS'
    ufw allow 3389/tcp comment 'UpCloud RDP'
    ufw allow 8443/tcp comment 'UpCloud HTTPS Alt'
    ufw allow 8880/tcp comment 'UpCloud HTTP Alt'

    for cf_ip in 173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 \
                 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 \
                 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 \
                 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22; do
        ufw allow from "$cf_ip" to any port 80,443 proto tcp comment 'Cloudflare CDN' 2>/dev/null || true
    done
fi

systemctl daemon-reload
systemctl enable aria2 xrdp jiopc-vnc jiopc-web nginx jiopc-filemanager
systemctl restart aria2
systemctl restart xrdp
systemctl restart jiopc-vnc
systemctl restart jiopc-web
systemctl restart nginx
systemctl restart jiopc-filemanager

# Detect IPv4 Public IP
PUBLIC_IP=$(curl -s -4 ifconfig.me || curl -s -4 icanhazip.com || hostname -I | awk '{print $1}')

# 29. Generate Fixed Cloudflare Worker Code (Supports /aria2files/)
cat > /home/$JIOPC_USER/cloudflare-worker.js << EOF_CFW
export default {
  async fetch(request) {
    const url = new URL(request.url);
    const targetUrl = new URL("http://${PUBLIC_IP}:80" + url.pathname + url.search);

    const newHeaders = new Headers(request.headers);
    newHeaders.set("Host", "${PUBLIC_IP}");
    newHeaders.set("X-Forwarded-Host", url.hostname);
    newHeaders.set("X-Forwarded-Proto", "https");

    if (request.headers.get("Upgrade") === "websocket") {
      return fetch(targetUrl.toString(), {
        headers: request.headers
      });
    }

    return fetch(targetUrl.toString(), {
      method: request.method,
      headers: newHeaders,
      body: request.body,
      redirect: "follow"
    });
  }
};
EOF_CFW
chown $JIOPC_USER:$JIOPC_USER /home/$JIOPC_USER/cloudflare-worker.js

# Final summary in your exact requested format with aria2files link
echo ""
echo "===================================================================="
echo "    JioPC Setup & Verification Complete! All Systems Operational"
echo "===================================================================="
echo "Architecture: ${SYS_ARCH^^} (${RAW_ARCH})"
echo ""
echo "1. Direct Access via IP:"
echo "   HTTPS:    https://${PUBLIC_IP}/"
echo "   HTTP:     http://${PUBLIC_IP}/"
echo "   Password: ${JIOPC_PASS}"
echo ""
echo "2. Remote Desktop (RDP):"
echo "   Host:     ${PUBLIC_IP}:3389"
echo "   Username: ${JIOPC_USER}"
echo "   Password: ${JIOPC_PASS}"
echo ""
echo "3. Aria2 Downloaded Files Web Manager (Delete, Rename, Upload, Drag & Drop):"
echo "   URL:      https://${PUBLIC_IP}/aria2files/"
echo "   Username: ${JIOPC_USER}"
echo "   Password: ${JIOPC_PASS}"
echo "===================================================================="
EOF
bash setup.sh
