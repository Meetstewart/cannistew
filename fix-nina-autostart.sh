#!/bin/bash
# fix-nina-autostart.sh — Dynamic node path fix
# Finds actual node binary, fixes LaunchAgent plist, starts server

echo "=== Nina Auto-Start Fix ==="

# 1. Find the actual node binary
NODE=$(find /Users/apple/.nvm/versions/node -name 'node' -type f 2>/dev/null | sort | tail -1)
if [ -z "$NODE" ]; then
    echo "ERROR: No node binary found in ~/.nvm"
    exit 1
fi
echo "Found node: $NODE"
$NODE --version

# 2. Navigate to nina-demo
NINA_DIR="/Users/apple/stewart-core/services/nina-demo"
if [ ! -d "$NINA_DIR" ]; then
    echo "ERROR: Nina dir not found at $NINA_DIR"
    exit 1
fi
cd "$NINA_DIR"

# 3. Install deps if needed
if [ ! -d "node_modules" ]; then
    echo "Installing npm deps..."
    NPM="$(dirname $NODE)/npm"
    $NPM install 2>&1 | tail -5
fi

# 4. Build TypeScript
echo "Building TypeScript..."
NPM="$(dirname $NODE)/npm"
$NPM run build 2>&1 | tail -10

# Verify dist/server.js exists
if [ ! -f "dist/server.js" ]; then
    echo "ERROR: dist/server.js not found after build"
    ls dist/ 2>/dev/null || echo "dist/ dir missing"
    exit 1
fi
echo "Build OK: dist/server.js exists"

# 5. Unload any existing LaunchAgents
launchctl unload ~/Library/LaunchAgents/com.stewart.nina-server.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.stewart.nina-kiosk.plist 2>/dev/null || true
sleep 2

# 6. Kill any lingering node processes on port 4100
lsof -ti:4100 | xargs kill -9 2>/dev/null || true
sleep 1

# 7. Get node dir for PATH
NODE_DIR="$(dirname $NODE)"

# 8. Write server LaunchAgent plist with CORRECT dynamic node path
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.stewart.nina-server.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.stewart.nina-server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$NODE</string>
        <string>$NINA_DIR/dist/server.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$NINA_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/nina-server.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/nina-server-err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>/Users/apple</string>
        <key>PATH</key>
        <string>$NODE_DIR:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
PLIST
echo "Server plist written with node: $NODE"

# 9. Write kiosk launcher script
KIOSK_SCRIPT="$NINA_DIR/scripts/auto-start/launch-kiosk.sh"
mkdir -p "$NINA_DIR/scripts/auto-start"
cat > "$KIOSK_SCRIPT" << 'KIOSK'
#!/bin/bash
# Wait for nina server to be healthy
MAX_WAIT=60
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    if curl -s http://localhost:4100/health > /dev/null 2>&1; then
        break
    fi
    sleep 1
    COUNT=$((COUNT + 1))
done
# Open Chrome in kiosk mode at localhost
open -a "Google Chrome" --args \
    --kiosk \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --no-first-run \
    "http://localhost:4100"
KIOSK
chmod +x "$KIOSK_SCRIPT"

# 10. Write kiosk LaunchAgent plist
cat > ~/Library/LaunchAgents/com.stewart.nina-kiosk.plist << PLIST2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.stewart.nina-kiosk</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$KIOSK_SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/nina-kiosk.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/nina-kiosk-err.log</string>
</dict>
</plist>
PLIST2
echo "Kiosk plist written"

# 11. Load LaunchAgents
launchctl load ~/Library/LaunchAgents/com.stewart.nina-server.plist && echo "Server LaunchAgent loaded OK"
launchctl load ~/Library/LaunchAgents/com.stewart.nina-kiosk.plist && echo "Kiosk LaunchAgent loaded OK"

# 12. Wait for server to start (up to 30s)
echo "Waiting for server on :4100..."
for i in $(seq 1 30); do
    if curl -s http://localhost:4100/health > /dev/null 2>&1; then
        echo "SERVER_UP after ${i}s"
        break
    fi
    sleep 1
    if [ $i -eq 30 ]; then
        echo "SERVER_TIMEOUT"
        echo "--- server log ---"
        cat /tmp/nina-server.log 2>/dev/null | tail -20
        echo "--- error log ---"
        cat /tmp/nina-server-err.log 2>/dev/null | tail -20
    fi
done

# 13. Final verification
HEALTH=$(curl -s http://localhost:4100/health 2>/dev/null)
if [ -n "$HEALTH" ]; then
    echo "=== SUCCESS: $HEALTH ==="
else
    echo "=== FAILED: server not responding ==="
fi

echo "=== DONE ==="
