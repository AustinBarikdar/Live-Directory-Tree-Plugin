const vscode = require('vscode');
const http = require('http');

// ============================================
// EMBEDDED SERVER
// ============================================

class EmbeddedServer {
    constructor() {
        this.server = null;
        this.port = 21326;
        this.currentTree = {
            name: "Waiting for Roblox Studio...",
            timestamp: 0,
            containers: []
        };
        this.lastUpdateTime = 0;
        this.onDataReceived = null;
    }

    start(port) {
        return new Promise((resolve, reject) => {
            if (this.server) {
                resolve(true);
                return;
            }

            this.port = port || vscode.workspace.getConfiguration('robloxDirectoryTree').get('serverPort') || 21326;

            this.server = http.createServer((req, res) => this.handleRequest(req, res));

            this.server.on('error', (err) => {
                if (err.code === 'EADDRINUSE') {
                    reject(new Error(`Port ${this.port} is already in use`));
                } else {
                    reject(err);
                }
            });

            this.server.listen(this.port, () => {
                console.log(`Server started on port ${this.port}`);
                resolve(true);
            });
        });
    }

    stop() {
        return new Promise((resolve) => {
            if (this.server) {
                this.server.close(() => {
                    this.server = null;
                    resolve(true);
                });
            } else {
                resolve(true);
            }
        });
    }

    isRunning() {
        return this.server !== null;
    }

    handleRequest(req, res) {
        const url = new URL(req.url, `http://localhost:${this.port}`);
        const pathname = url.pathname;

        // CORS headers
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

        if (req.method === 'OPTIONS') {
            res.writeHead(204);
            res.end();
            return;
        }

        // Routes
        if (pathname === '/ping' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ status: 'ok', server: 'LiveDirectoryTree-VSCode', version: '1.0.0' }));
            return;
        }

        if (pathname === '/sync' && req.method === 'POST') {
            let body = '';
            req.on('data', chunk => body += chunk);
            req.on('end', () => {
                try {
                    this.currentTree = JSON.parse(body);
                    this.lastUpdateTime = Date.now();
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ status: 'ok', received: true }));

                    // Notify that we got new data
                    if (this.onDataReceived) {
                        this.onDataReceived(this.currentTree);
                    }
                } catch (e) {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: 'Invalid JSON' }));
                }
            });
            return;
        }

        if (pathname === '/tree' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(this.currentTree));
            return;
        }

        if (pathname === '/status' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                connected: Date.now() - this.lastUpdateTime < 30000,
                lastUpdate: this.lastUpdateTime,
                gameName: this.currentTree.name
            }));
            return;
        }

        // Simple web UI
        if (pathname === '/' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'text/html' });
            res.end(this.getDebugHTML());
            return;
        }

        res.writeHead(404);
        res.end('Not found');
    }

    getDebugHTML() {
        return `<!DOCTYPE html>
<html>
<head>
    <title>Live Directory Tree</title>
    <style>
        body { font-family: system-ui; background: #1e1e1e; color: #d4d4d4; padding: 20px; }
        h1 { color: #569cd6; }
        .status { padding: 8px 16px; border-radius: 4px; display: inline-block; margin: 10px 0; }
        .connected { background: #2d5a2d; color: #90EE90; }
        .disconnected { background: #5a2d2d; color: #ff9090; }
        pre { background: #2d2d2d; padding: 15px; border-radius: 6px; overflow: auto; max-height: 70vh; }
        button { background: #0e639c; color: white; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer; margin-right: 10px; }
        button:hover { background: #1177bb; }
    </style>
</head>
<body>
    <h1>🌲 Live Directory Tree Server</h1>
    <p>Running inside VS Code on port ${this.port}</p>
    <div id="status" class="status disconnected">Checking...</div>
    <p><button onclick="copyTree()">Copy Tree</button></p>
    <pre id="tree">Loading...</pre>
    <script>
        async function refresh() {
            try {
                const status = await (await fetch('/status')).json();
                const statusEl = document.getElementById('status');
                statusEl.className = 'status ' + (status.connected ? 'connected' : 'disconnected');
                statusEl.textContent = status.connected ? '✓ Connected: ' + status.gameName : '✗ Waiting for Roblox Studio...';
                
                const tree = await (await fetch('/tree')).json();
                document.getElementById('tree').textContent = JSON.stringify(tree, null, 2);
            } catch(e) {
                document.getElementById('status').textContent = 'Error: ' + e.message;
            }
        }
        async function copyTree() {
            const tree = document.getElementById('tree').textContent;
            await navigator.clipboard.writeText(tree);
            alert('Copied!');
        }
        refresh();
        setInterval(refresh, 2000);
    </script>
</body>
</html>`;
    }

    getTree() {
        return this.currentTree;
    }
}

// ============================================
// TREE VIEW PROVIDER
// ============================================

class RobloxTreeItem extends vscode.TreeItem {
    constructor(node, collapsibleState) {
        super(node.name, collapsibleState);
        this.node = node;
        this.tooltip = `${node.path || node.name}\nClass: ${node.className}`;
        this.description = this.getDescription();
        this.iconPath = this.getIcon();
        this.contextValue = 'robloxItem';
    }

    getDescription() {
        if (this.node.lineCount) return `${this.node.lineCount} lines`;
        if (this.node.childCount) return `${this.node.childCount} items`;
        return this.node.className;
    }

    getIcon() {
        const icons = {
            'module': 'symbol-module',
            'script': 'file-code',
            'localscript': 'device-desktop',
            'folder': 'folder',
            'service': 'package',
            'remoteevent': 'broadcast',
            'remotefunction': 'call-outgoing',
            'bindableevent': 'pulse',
            'bindablefunction': 'call-incoming',
            'screengui': 'browser',
            'frame': 'layout',
            'textlabel': 'text-size',
            'textbutton': 'inspect',
            'model': 'symbol-structure',
            'tool': 'tools',
            'sound': 'unmute',
        };
        const iconName = icons[this.node.icon] || 'circle-outline';
        return new vscode.ThemeIcon(iconName);
    }
}

class RobloxDirectoryTreeProvider {
    constructor(server) {
        this._onDidChangeTreeData = new vscode.EventEmitter();
        this.onDidChangeTreeData = this._onDidChangeTreeData.event;
        this.server = server;
        this.refreshInterval = null;

        // Status bar
        this.statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
        this.statusBarItem.command = 'robloxDirectoryTree.refresh';
        this.updateStatusBar();
        this.statusBarItem.show();

        // Listen for server data
        this.server.onDataReceived = () => {
            this.refresh();
        };
    }

    updateStatusBar() {
        const tree = this.server.getTree();
        const hasData = tree.containers && tree.containers.length > 0;

        if (this.server.isRunning()) {
            if (hasData) {
                this.statusBarItem.text = `$(check) Roblox: ${tree.name || 'Connected'}`;
                this.statusBarItem.backgroundColor = undefined;
            } else {
                this.statusBarItem.text = `$(radio-tower) Roblox: Waiting for Studio...`;
                this.statusBarItem.backgroundColor = undefined;
            }
        } else {
            this.statusBarItem.text = `$(circle-slash) Roblox: Server stopped`;
            this.statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
        }
    }

    refresh() {
        this.updateStatusBar();
        this._onDidChangeTreeData.fire();
    }

    getTreeItem(element) {
        return element;
    }

    getChildren(element) {
        const tree = this.server.getTree();

        if (!element) {
            // Root level
            if (!this.server.isRunning()) {
                const item = new vscode.TreeItem('Click ▶ Start Server to begin');
                item.iconPath = new vscode.ThemeIcon('play');
                item.description = 'Server is stopped';
                return [item];
            }

            if (!tree.containers || tree.containers.length === 0) {
                const item = new vscode.TreeItem('Waiting for Roblox Studio...');
                item.description = 'Connect from Studio plugin';
                item.iconPath = new vscode.ThemeIcon('loading~spin');
                return [item];
            }

            return tree.containers.map(container => {
                const hasChildren = container.children && container.children.length > 0;
                return new RobloxTreeItem(
                    container,
                    hasChildren ? vscode.TreeItemCollapsibleState.Expanded : vscode.TreeItemCollapsibleState.None
                );
            });
        }

        // Children
        if (element.node && element.node.children) {
            return element.node.children.map(child => {
                const hasChildren = child.children && child.children.length > 0;
                return new RobloxTreeItem(
                    child,
                    hasChildren ? vscode.TreeItemCollapsibleState.Collapsed : vscode.TreeItemCollapsibleState.None
                );
            });
        }

        return [];
    }

    startAutoRefresh() {
        const config = vscode.workspace.getConfiguration('robloxDirectoryTree');
        if (!config.get('autoRefresh')) return;

        this.stopAutoRefresh();
        const interval = config.get('refreshInterval') || 3000;
        this.refreshInterval = setInterval(() => this.refresh(), interval);
    }

    stopAutoRefresh() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
            this.refreshInterval = null;
        }
    }

    getTreeAsText() {
        const tree = this.server.getTree();
        if (!tree.containers || tree.containers.length === 0) {
            return 'No data available. Make sure:\n1. Server is running (click ▶ button)\n2. Roblox Studio plugin is connected';
        }

        let result = `=====================================\n`;
        result += `  PROJECT DIRECTORY TREE\n`;
        result += `  Game: ${tree.name || 'Unknown'}\n`;
        result += `  For AI Assistant Context\n`;
        result += `=====================================\n\n`;

        tree.containers.forEach((container, i) => {
            result += this.nodeToText(container, '', i === tree.containers.length - 1);
            result += '\n';
        });

        return result;
    }

    nodeToText(node, prefix = '', isLast = true) {
        const connector = prefix ? (isLast ? '└── ' : '├── ') : '';
        const childPrefix = prefix + (isLast ? '    ' : '│   ');

        let line = prefix + connector + node.name + ` [${node.className}]`;
        if (node.lineCount) line += ` (${node.lineCount} lines)`;
        if (node.childCount) line += ` (${node.childCount} children)`;

        let result = line + '\n';

        if (node.children && node.children.length > 0) {
            node.children.forEach((child, i) => {
                result += this.nodeToText(child, childPrefix, i === node.children.length - 1);
            });
        }

        return result;
    }

    dispose() {
        this.stopAutoRefresh();
        this.statusBarItem.dispose();
    }
}

// ============================================
// EXTENSION ACTIVATION
// ============================================

function activate(context) {
    console.log('Roblox Live Directory Tree activated');

    // Create embedded server
    const server = new EmbeddedServer();

    // Create tree provider
    const treeProvider = new RobloxDirectoryTreeProvider(server);

    // Register tree view
    const treeView = vscode.window.createTreeView('robloxDirectoryTree', {
        treeDataProvider: treeProvider,
        showCollapseAll: true,
    });

    // Track server state for menu visibility
    const updateServerContext = () => {
        vscode.commands.executeCommand('setContext', 'robloxDirectoryTree.serverRunning', server.isRunning());
    };

    // Commands
    const startServerCmd = vscode.commands.registerCommand('robloxDirectoryTree.startServer', async () => {
        try {
            const port = vscode.workspace.getConfiguration('robloxDirectoryTree').get('serverPort') || 21326;
            await server.start(port);
            updateServerContext();
            treeProvider.startAutoRefresh();
            treeProvider.refresh();
            vscode.window.showInformationMessage(`🌲 Server started on http://localhost:${port}`);
        } catch (err) {
            vscode.window.showErrorMessage(`Failed to start server: ${err.message}`);
        }
    });

    const stopServerCmd = vscode.commands.registerCommand('robloxDirectoryTree.stopServer', async () => {
        await server.stop();
        updateServerContext();
        treeProvider.stopAutoRefresh();
        treeProvider.refresh();
        vscode.window.showInformationMessage('Server stopped');
    });

    const refreshCmd = vscode.commands.registerCommand('robloxDirectoryTree.refresh', () => {
        treeProvider.refresh();
    });

    const copyPathCmd = vscode.commands.registerCommand('robloxDirectoryTree.copyPath', (item) => {
        if (item && item.node && item.node.path) {
            vscode.env.clipboard.writeText(item.node.path);
            vscode.window.setStatusBarMessage(`Copied: ${item.node.path}`, 2000);
        }
    });

    const copyTreeCmd = vscode.commands.registerCommand('robloxDirectoryTree.copyTree', () => {
        const text = treeProvider.getTreeAsText();
        vscode.env.clipboard.writeText(text);
        vscode.window.showInformationMessage(' Directory tree copied to clipboard!');
    });

    const setUrlCmd = vscode.commands.registerCommand('robloxDirectoryTree.setServerUrl', async () => {
        const port = await vscode.window.showInputBox({
            prompt: 'Enter server port',
            value: String(vscode.workspace.getConfiguration('robloxDirectoryTree').get('serverPort') || 21326),
            placeHolder: '21326'
        });

        if (port) {
            await vscode.workspace.getConfiguration('robloxDirectoryTree').update('serverPort', parseInt(port), true);
            vscode.window.showInformationMessage(`Port set to ${port}. Restart server to apply.`);
        }
    });

    // Auto-setup MCP for Claude Desktop and Claude Code
    const setupMCPCmd = vscode.commands.registerCommand('robloxDirectoryTree.setupMCP', async () => {
        const os = process.platform;
        const path = require('path');
        const fs = require('fs');

        // Get the MCP server script path
        const mcpServerPath = path.join(__dirname, 'mcp-server.js');
        const mcpEntry = { command: 'node', args: [mcpServerPath] };

        // Ask user which service(s) to configure
        const selection = await vscode.window.showQuickPick(
            [
                { label: 'Both (Recommended)', value: 'both', description: 'Configure Claude Desktop and Claude Code' },
                { label: 'Claude Desktop', value: 'desktop', description: 'Claude Desktop app' },
                { label: 'Claude Code', value: 'code', description: 'Claude Code CLI' },
            ],
            { placeHolder: 'Which Claude service(s) to configure?' }
        );

        if (!selection) return;

        const results = [];

        // --- Claude Desktop config ---
        if (selection.value === 'both' || selection.value === 'desktop') {
            let configPath;
            if (os === 'win32') {
                configPath = path.join(process.env.APPDATA, 'Claude', 'claude_desktop_config.json');
            } else if (os === 'darwin') {
                configPath = path.join(process.env.HOME, 'Library', 'Application Support', 'Claude', 'claude_desktop_config.json');
            } else {
                configPath = path.join(process.env.HOME, '.config', 'Claude', 'claude_desktop_config.json');
            }

            try {
                let config = { mcpServers: {} };
                const configDir = path.dirname(configPath);
                if (!fs.existsSync(configDir)) {
                    fs.mkdirSync(configDir, { recursive: true });
                }
                if (fs.existsSync(configPath)) {
                    try {
                        const existing = fs.readFileSync(configPath, 'utf8');
                        config = JSON.parse(existing);
                        if (!config.mcpServers) config.mcpServers = {};
                    } catch (e) {
                        const backupPath = configPath + '.backup';
                        fs.copyFileSync(configPath, backupPath);
                        vscode.window.showWarningMessage(`Backed up invalid config to ${backupPath}`);
                    }
                }
                config.mcpServers['roblox-directory-tree'] = mcpEntry;
                fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
                results.push('Claude Desktop');
            } catch (error) {
                vscode.window.showErrorMessage(`Failed to setup Claude Desktop MCP: ${error.message}`);
            }
        }

        // --- Claude Code config (.mcp.json in home directory) ---
        if (selection.value === 'both' || selection.value === 'code') {
            const homedir = os === 'win32' ? process.env.USERPROFILE : process.env.HOME;
            const mcpJsonPath = path.join(homedir, '.mcp.json');

            try {
                let config = { mcpServers: {} };
                if (fs.existsSync(mcpJsonPath)) {
                    try {
                        const existing = fs.readFileSync(mcpJsonPath, 'utf8');
                        config = JSON.parse(existing);
                        if (!config.mcpServers) config.mcpServers = {};
                    } catch (e) {
                        const backupPath = mcpJsonPath + '.backup';
                        fs.copyFileSync(mcpJsonPath, backupPath);
                        vscode.window.showWarningMessage(`Backed up invalid .mcp.json to ${backupPath}`);
                    }
                }
                config.mcpServers['roblox-directory-tree'] = mcpEntry;
                fs.writeFileSync(mcpJsonPath, JSON.stringify(config, null, 2));
                results.push('Claude Code');
            } catch (error) {
                vscode.window.showErrorMessage(`Failed to setup Claude Code MCP: ${error.message}`);
            }
        }

        if (results.length > 0) {
            const msg = results.join(' and ') + ' configured! Restart to enable.';
            const action = await vscode.window.showInformationMessage(
                msg,
                'OK'
            );
        }
    });

    // Auto-start server if configured
    const autoStart = vscode.workspace.getConfiguration('robloxDirectoryTree').get('autoStartServer');
    if (autoStart) {
        vscode.commands.executeCommand('robloxDirectoryTree.startServer');
    }

    // Initial context
    updateServerContext();

    // First-time setup prompt (async IIFE)
    (async () => {
        const hasPrompted = context.globalState.get('mcpSetupPrompted');
        if (!hasPrompted) {
            const setup = await vscode.window.showInformationMessage(
                '🌲 Roblox Directory Tree installed! Want to enable Claude AI integration?',
                'Setup Claude Integration',
                'Later'
            );

            if (setup === 'Setup Claude Integration') {
                vscode.commands.executeCommand('robloxDirectoryTree.setupMCP');
            }

            context.globalState.update('mcpSetupPrompted', true);
        }
    })();

    // Register all disposables
    context.subscriptions.push(
        treeView,
        treeProvider,
        startServerCmd,
        stopServerCmd,
        refreshCmd,
        copyPathCmd,
        copyTreeCmd,
        setUrlCmd,
        setupMCPCmd,
        { dispose: () => server.stop() }
    );
}

function deactivate() {
    console.log('Roblox Live Directory Tree deactivated');
}

module.exports = { activate, deactivate };