#!/bin/bash
# setup-nina-robust.sh
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"

NINA_DEMO_DIR="$HOME/stewart-core/services/nina-demo"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "=== Nina Robust Auto-Start Setup ==="
NODE_BIN=$(which node)
NVM_NODE_BIN_DIR=$(dirname "$NODE_BIN")
echo "Node: $NODE_BIN"

echo "[1] npm install + build..."
cd "$NINA_DEMO_DIR"
npm install
npm run build
echo "Build done."

echo "[2] Writing kiosk launcher..."
cat > "$HOME/nina-kiosk.sh" << 'KIOSK'
#!/bin/bash
LOGFILE="/tmp/nina-kiosk.log"
echo "[kiosk] $(date): Starting..." >> "$LOGFILE"
READY=0
for i in $(seq 1 90); do
  if curl -s --max-time 2 http://localhost:4100/health > /dev/null 2>&1; then
    echo "[kiosk] Server ready after ${i}s." >> "$LOGFILE"
    READY=1
    break
  fi
  sleep 1
done
if [ "$READY" -eq 0 ]; then
  echo "[kiosk] WARNING: timeout, launching anyway." >> "$LOGFILE"
fi
pkill -f "Google Chrome" 2>/dev/null || true
sleep 2
echo "[kiosk] Launching Chrome kiosk..." >> "$LOGFILE"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --kiosk \
  --no-first-run \
  --disable-infobars \
  --disable-translate \
  --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required \
  "http://localhost:4100" >> "$LOGFILE" 2>&1
KIOSK
chmod +x "$HOME/nina-kiosk.sh"
echo "Kiosk script written."

echo "[3] Writing LaunchAgent plists..."
mkdir -p "$LAUNCH_AGENTS_DIR"

cat > "$LAUNCH_AGENTS_DIR/com.stewart.nina-demo.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.stewart.nina-demo</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NODE_BIN}</string>
        <string>dist/server.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${NINA_DEMO_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>/tmp/nina-server.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/nina-server.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${NVM_NODE_BIN_DIR}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>NODE_ENV</key>
        <string>production</string>
    </dict>
</dict>
</plist>
PLIST

cat > "$LAUNCH_AGENTS_DIR/com.stewart.nina-kiosk.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.stewart.nina-kiosk</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${HOME}/nina-kiosk.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/nina-kiosk.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/nina-kiosk.log</string>
</dict>
</plist>
PLIST

echo "Plists written."

echo "[4] Loading LaunchAgents..."
launchctl unload "$LAUNCH_AGENTS_DIR/com.stewart.nina-demo.plist" 2>/dev/null || true
launchctl unload "$LAUNCH_AGENTS_DIR/com.stewart.nina-kiosk.plist" 2>/dev/null || true
launchctl load -w "$LAUNCH_AGENTS_DIR/com.stewart.nina-demo.plist"
echo "Server agent loaded."
launchctl load -w "$LAUNCH_AGENTS_DIR/com.stewart.nina-kiosk.plist"
echo "Kiosk agent loaded."

echo "[5] Verifying server (up to 20s)..."
for i in $(seq 1 20); do
  if curl -s --max-time 2 http://localhost:4100/health > /dev/null 2>&1; then
    echo "SUCCESS: Server is running at http://localhost:4100"
    break
  fi
  sleep 1
  if [ "$i" -eq 20 ]; then
    echo "Server not ready. Logs:"
    tail -30 /tmp/nina-server.log 2>/dev/null || echo "No log found."
  fi
done
echo "=== DONE ==="
echo "Node: $NODE_BIN"
echo "Server: $NINA_DEMO_DIR/dist/server.js"
