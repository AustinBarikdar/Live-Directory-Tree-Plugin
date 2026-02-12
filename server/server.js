/**
 * Live Directory Tree Server
 * 
 * Receives directory tree updates from Roblox Studio plugin
 * and serves them to the VS Code extension
 * 
 * Usage: node server.js [port]
 * Default port: 21326
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.argv[2] || 21326;
const DATA_FILE = path.join(__dirname, 'tree-data.json');

// Current tree data
let currentTree = {
    name: "Not connected",
    timestamp: 0,
    containers: []
};

// Connected VS Code clients (for potential WebSocket upgrade later)
let lastUpdateTime = Date.now();

// CORS headers for local development
const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
};

// Parse JSON body from request
function parseBody(req) {
    return new Promise((resolve, reject) => {
        let body = '';
        req.on('data', chunk => {
            body += chunk.toString();
            // Limit body size to 10MB
            if (body.length > 10 * 1024 * 1024) {
                reject(new Error('Body too large'));
            }
        });
        req.on('end', () => {
            try {
                resolve(JSON.parse(body));
            } catch (e) {
                reject(e);
            }
        });
        req.on('error', reject);
    });
}

// Save tree to file for persistence
function saveTree() {
    try {
        fs.writeFileSync(DATA_FILE, JSON.stringify(currentTree, null, 2));
    } catch (e) {
        console.error('Failed to save tree:', e.message);
    }
}

// Load tree from file
function loadTree() {
    try {
        if (fs.existsSync(DATA_FILE)) {
            const data = fs.readFileSync(DATA_FILE, 'utf8');
            currentTree = JSON.parse(data);
            console.log('Loaded existing tree data');
        }
    } catch (e) {
        console.error('Failed to load tree:', e.message);
    }
}

// Create HTTP server
const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, `http://localhost:${PORT}`);
    const pathname = url.pathname;
    
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        res.writeHead(204, corsHeaders);
        res.end();
        return;
    }
    
    // Set CORS headers for all responses
    Object.entries(corsHeaders).forEach(([key, value]) => {
        res.setHeader(key, value);
    });
    
    try {
        // Health check / ping endpoint
        if (pathname === '/ping' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ 
                status: 'ok', 
                server: 'LiveDirectoryTree',
                version: '1.0.0',
                timestamp: Date.now()
            }));
            return;
        }
        
        // Receive sync from Roblox plugin
        if (pathname === '/sync' && req.method === 'POST') {
            const data = await parseBody(req);
            currentTree = data;
            lastUpdateTime = Date.now();
            saveTree();
            
            console.log(`[${new Date().toLocaleTimeString()}] Received sync: ${data.name || 'Game'} (${JSON.stringify(data).length} bytes)`);
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ status: 'ok', received: true }));
            return;
        }
        
        // Get current tree (for VS Code extension)
        if (pathname === '/tree' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(currentTree));
            return;
        }
        
        // Get tree as plain text (for debugging)
        if (pathname === '/tree/text' && req.method === 'GET') {
            const text = treeToText(currentTree);
            res.writeHead(200, { 'Content-Type': 'text/plain' });
            res.end(text);
            return;
        }
        
        // Status endpoint
        if (pathname === '/status' && req.method === 'GET') {
            const timeSinceUpdate = Date.now() - lastUpdateTime;
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                connected: timeSinceUpdate < 30000, // Consider connected if updated in last 30s
                lastUpdate: lastUpdateTime,
                timeSinceUpdate: timeSinceUpdate,
                gameName: currentTree.name || 'Unknown',
                containerCount: currentTree.containers?.length || 0
            }));
            return;
        }
        
        // Simple web UI for debugging
        if (pathname === '/' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'text/html' });
            res.end(getDebugHTML());
            return;
        }
        
        // 404 for unknown routes
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Not found' }));
        
    } catch (e) {
        console.error('Error handling request:', e);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
    }
});

// Convert tree to plain text
function treeToText(tree, prefix = '', isLast = true) {
    let result = `=====================================\n`;
    result += `  PROJECT DIRECTORY TREE\n`;
    result += `  Game: ${tree.name || 'Unknown'}\n`;
    result += `  Updated: ${new Date(tree.timestamp * 1000).toLocaleString()}\n`;
    result += `=====================================\n\n`;
    
    if (tree.containers) {
        tree.containers.forEach((container, i) => {
            result += nodeToText(container, '', i === tree.containers.length - 1);
            result += '\n';
        });
    }
    
    return result;
}

function nodeToText(node, prefix = '', isLast = true) {
    const connector = isLast ? '└── ' : '├── ';
    const childPrefix = prefix + (isLast ? '    ' : '│   ');
    
    let line = prefix + connector + node.name + ` [${node.className}]`;
    if (node.lineCount) {
        line += ` (${node.lineCount} lines)`;
    }
    if (node.childCount) {
        line += ` (${node.childCount} children)`;
    }
    
    let result = line + '\n';
    
    if (node.children && node.children.length > 0) {
        node.children.forEach((child, i) => {
            result += nodeToText(child, childPrefix, i === node.children.length - 1);
        });
    }
    
    return result;
}

// Debug HTML page
function getDebugHTML() {
    return `<!DOCTYPE html>
<html>
<head>
    <title>Live Directory Tree Server</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #1e1e1e;
            color: #d4d4d4;
            padding: 20px;
            margin: 0;
        }
        h1 { color: #569cd6; }
        .status { 
            padding: 10px 15px;
            border-radius: 6px;
            margin: 10px 0;
            display: inline-block;
        }
        .connected { background: #2d5a2d; color: #90EE90; }
        .disconnected { background: #5a2d2d; color: #ff9090; }
        pre {
            background: #2d2d2d;
            padding: 15px;
            border-radius: 6px;
            overflow: auto;
            max-height: 70vh;
            font-family: 'Consolas', 'Monaco', monospace;
            font-size: 12px;
            line-height: 1.4;
        }
        .info { color: #888; font-size: 14px; }
        button {
            background: #0e639c;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 4px;
            cursor: pointer;
            margin-right: 10px;
        }
        button:hover { background: #1177bb; }
    </style>
</head>
<body>
    <h1>🌲 Live Directory Tree Server</h1>
    <div id="status" class="status disconnected">Checking...</div>
    <p class="info">Port: ${PORT} | <a href="/tree" style="color:#569cd6">JSON</a> | <a href="/tree/text" style="color:#569cd6">Plain Text</a></p>
    <button onclick="refresh()">Refresh</button>
    <button onclick="copyTree()">Copy Tree</button>
    <h3>Current Tree:</h3>
    <pre id="tree">Loading...</pre>
    
    <script>
        async function refresh() {
            try {
                const statusRes = await fetch('/status');
                const status = await statusRes.json();
                
                const statusEl = document.getElementById('status');
                if (status.connected) {
                    statusEl.className = 'status connected';
                    statusEl.textContent = '✓ Connected - ' + status.gameName;
                } else {
                    statusEl.className = 'status disconnected';
                    statusEl.textContent = '✗ Waiting for Roblox Studio...';
                }
                
                const treeRes = await fetch('/tree/text');
                const tree = await treeRes.text();
                document.getElementById('tree').textContent = tree;
            } catch (e) {
                document.getElementById('status').textContent = 'Error: ' + e.message;
            }
        }
        
        async function copyTree() {
            const tree = document.getElementById('tree').textContent;
            await navigator.clipboard.writeText(tree);
            alert('Copied to clipboard!');
        }
        
        refresh();
        setInterval(refresh, 3000);
    </script>
</body>
</html>`;
}

// Load existing data and start server
loadTree();

server.listen(PORT, () => {
    console.log(`
╔════════════════════════════════════════════════════╗
║       🌲 Live Directory Tree Server                ║
╠════════════════════════════════════════════════════╣
║  Server running on: http://localhost:${PORT}         ║
║                                                    ║
║  Endpoints:                                        ║
║    GET  /ping      - Health check                  ║
║    POST /sync      - Receive tree from Roblox      ║
║    GET  /tree      - Get tree as JSON              ║
║    GET  /tree/text - Get tree as plain text        ║
║    GET  /status    - Connection status             ║
║    GET  /          - Debug web UI                  ║
║                                                    ║
║  Waiting for Roblox Studio connection...           ║
╚════════════════════════════════════════════════════╝
`);
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\nShutting down server...');
    saveTree();
    server.close(() => {
        console.log('Server closed.');
        process.exit(0);
    });
});
