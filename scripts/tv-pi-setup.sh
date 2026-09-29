#!/usr/bin/env bash
# Sets up the lab TV Pi as a kiosk: Chromium full screen on the TV page, Pi 3 tuning, HDMI-CEC on/off. Safe to run again. See docs/edge-node.md.
#   scripts/tv-pi-setup.sh ['http://192.168.1.131/tv/?room=…']
set -euo pipefail
URL=${1:-http://192.168.1.131/tv/}
step() { echo; echo "== $*"; }

step "1/5 Install packages"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends cage chromium cec-utils

step "2/5 Enable autologin"
sudo raspi-config nonint do_boot_behaviour B2

step "3/5 Create kiosk script and profile"
cat > ~/kiosk.sh <<EOF
#!/bin/sh
exec chromium --kiosk --noerrdialogs --disable-infobars --autoplay-policy=no-user-gesture-required --enable-gpu-rasterization --ignore-gpu-blocklist --no-first-run --disable-session-crashed-bubble --check-for-update-interval=31536000 --password-store=basic "$URL"
EOF
chmod +x ~/kiosk.sh

cat > ~/.bash_profile <<'EOF'
if [ "$(tty)" = /dev/tty1 ]; then exec cage -d -- ~/kiosk.sh; fi
EOF

step "4/5 Tune Pi 3"
if ! grep -q "dtoverlay=vc4-kms-v3d,cma-256" /boot/firmware/config.txt; then
    sudo sed -i 's/^dtoverlay=vc4-kms-v3d$/dtoverlay=vc4-kms-v3d,cma-256/' /boot/firmware/config.txt
fi

if ! grep -q "dtoverlay=disable-bt" /boot/firmware/config.txt; then
    echo "dtoverlay=disable-bt" | sudo tee -a /boot/firmware/config.txt >/dev/null  # the file ends in [all]
fi

# the Pi sends 720p and the TV scales it up: a Pi 3 can't draw 1080p smoothly
for arg in consoleblank=0 video=HDMI-A-1:1280x720@60; do
    grep -q "$arg" /boot/firmware/cmdline.txt || sudo sed -i "1s/\$/ $arg/" /boot/firmware/cmdline.txt
done

for svc in hciuart bluetooth triggerhappy ModemManager; do
    sudo systemctl disable --now "$svc" 2>/dev/null || true
done

step "5/5 Setup CEC cron jobs"
sudo tee /etc/cron.d/tv-kiosk >/dev/null <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

30 7 * * * root echo 'on 0' | cec-client -s -d 1
0 23 * * * root echo 'standby 0' | cec-client -s -d 1
30 4 * * * root /sbin/reboot
EOF

echo "done: reboot to start the kiosk (sudo reboot)"

