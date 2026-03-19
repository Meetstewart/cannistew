#!/bin/bash
# Nina LaunchAgent Setup - v26.16.0
set -e
NODE_BIN="/Users/apple/.nvm/versions/node/v26.16.0/bin/node"
NINA_DIR="/Users/apple/stewart-core/services/nina-demo"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
SCRIPTS_DIR="$NINA_DIR/scripts"

echo "=== Nina LaunchAgent Setup ==="
mkdir -p "$LAUNCH_AGENTS" "$SCRIPTS_DIR"

# --- Kiosk launcher script ---
cat > "$SCRIPTS_DIR/kiosk-launcher.sh" << 'KIOSK'
#!/bin/bash
echo "[kiosk] Waiting for Nina server..."
for i in $(seq 1 30); do
  if curl -s http://localhost:4100/health > /dev/null 2>&1; then
    echo "[kiosk] Server ready, launching Chrome"
    break
  fi
  sleep 2
done
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --kiosk \
  --no-first-run \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-translate \
  http://localhost:4100
KIOSK
chmod +x "$SCRIPTS_DIR/kiosk-launcher.sh"
echo "✓ kiosk-launcher.sh created"

# --- Server LaunchAgent ---
cat > "$LAUNCH_AGENTS/com.nina.server.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.nina.server</string>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE_BIN</string>
    <string>$NINA_DIR/dist/server.js</string>
  </array>
  <key>WorkingDirectory</key><string>$NINA_DIR</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>OPENROUTER_API_KEY</key><string>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</string>
    <key>ELEVENLABS_API_KEY</key><string>sk_69ca5f0d54a48ca9353f954bd648d474b4ed7238de9ef7bf</string>
    <key>PORT</key><string>4100</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/nina-server.log</string>
  <key>StandardErrorPath</key><string>/tmp/nina-server.log</string>
</dict>
</plist>
PLIST
echo "✓ com.nina.server.plist created"

# --- Kiosk LaunchAgent ---
cat > "$LAUNCH_AGENTS/com.nina.kiosk.plist" << PLIST2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.nina.kiosk</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$SCRIPTS_DIR/kiosk-launcher.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>StandardOutPath</key><string>/tmp/nina-kiosk.log</string>
  <key>StandardErrorPath</key><string>/tmp/nina-kiosk.log</string>
</dict>
</plist>
PLIST2
echo "✓ com.nina.kiosk.plist created"

# --- Unload existing (ignore errors) ---
launchctl unload "$LAUNCH_AGENTS/com.nina.server.plist" 2>/dev/null || true
launchctl unload "$LAUNCH_AGENTS/com.nina.kiosk.plist" 2>/dev/null || true

# --- Load new agents ---
launchctl load "$LAUNCH_AGENTS/com.nina.server.plist" && echo "✓ Server LaunchAgent loaded"
launchctl load "$LAUNCH_AGENTS/com.nina.kiosk.plist" && echo "✓ Kiosk LaunchAgent loaded"

echo ""
echo "=== LaunchAgent Setup Complete ==="
echo "Server will auto-start on boot with node $NODE_BIN"
echo "Kiosk will open Chrome at localhost:4100 after server is ready"
