/**
 * Nina Demo Server — Stewart AI
 * ElevenLabs TTS only, no OpenAI dependency
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 4100;
const ELEVENLABS_API_KEY = 'sk_69ca5f0d54a48ca9353f954bd648d474b4ed7238de9ef7bf';
const VOICE_ID = 'iP95p4xoKVk53GoZ742B'; // Chris

// Simple canned responses for demo
const GREETINGS = [
  "Hey, I'm Stewart — your AI cannabis operator. Whether you're shopping, learning, or growing, I'm here to guide you. What can I help you with today?",
  "Welcome! I'm Stewart, the AI that knows cannabis inside and out. Strains, compliance, cultivation — ask me anything.",
  "Stewart here. Your go-to AI for everything cannabis. Ready when you are.",
];

let greetingIndex = 0;

const publicDir = path.join(__dirname, 'public');

const MIME = {
  '.html': 'text/html',
  '.js':   'application/javascript',
  '.css':  'text/css',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.ico':  'image/x-icon',
  '.mp3':  'audio/mpeg',
  '.json': 'application/json',
};

async function textToSpeech(text) {
  const body = JSON.stringify({
    text,
    model_id: 'eleven_monolingual_v1',
    voice_settings: { stability: 0.5, similarity_boost: 0.75 },
  });

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.elevenlabs.io',
      path: `/v1/text-to-speech/${VOICE_ID}`,
      method: 'POST',
      headers: {
        'xi-api-key': ELEVENLABS_API_KEY,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
        'Accept': 'audio/mpeg',
      },
    };

    const https = require('https');
    const req = https.request(options, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => {
        if (res.statusCode === 200) {
          resolve(Buffer.concat(chunks));
        } else {
          const errText = Buffer.concat(chunks).toString();
          reject(new Error(`ElevenLabs ${res.statusCode}: ${errText}`));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => (data += chunk));
    req.on('end', () => {
      try { resolve(JSON.parse(data)); }
      catch (e) { resolve({}); }
    });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  // API: chat (POST /api/chat)
  if (req.method === 'POST' && req.url === '/api/chat') {
    try {
      const body = await readBody(req);
      const text = greetingIndex < GREETINGS.length
        ? GREETINGS[greetingIndex++ % GREETINGS.length]
        : GREETINGS[0];

      console.log(`[nina-demo] /api/chat → speaking: "${text.substring(0, 60)}..."`);

      const audioBuffer = await textToSpeech(text);
      const audioBase64 = audioBuffer.toString('base64');

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ text, audio: audioBase64 }));
    } catch (err) {
      console.error('[nina-demo] TTS error:', err.message);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: err.message }));
    }
    return;
  }

  // API: health
  if (req.url === '/health' || req.url === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', service: 'nina-demo' }));
    return;
  }

  // Static files
  let filePath = path.join(publicDir, req.url === '/' ? 'index.html' : req.url);
  const ext = path.extname(filePath);

  fs.readFile(filePath, (err, data) => {
    if (err) {
      // Fallback to index.html for SPA
      fs.readFile(path.join(publicDir, 'index.html'), (err2, data2) => {
        if (err2) { res.writeHead(404); res.end('Not found'); return; }
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(data2);
      });
      return;
    }
    const mime = MIME[ext] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': mime });
    res.end(data);
  });
});

server.listen(PORT, () => {
  console.log(`[nina-demo] Server running on http://localhost:${PORT}`);
});
