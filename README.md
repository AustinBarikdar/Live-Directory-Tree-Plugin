# 🌲 Live Directory Tree for Roblox

A real-time project structure sync system that connects Roblox Studio to VS Code, giving AI assistants live context about your codebase.

## Components

This system has 2 parts:

1. **Roblox Studio Plugin** - Monitors your game and sends tree updates
2. **VS Code Extension** - Displays the live tree with built-in server & copy button for AI

```
┌─────────────────┐      HTTP POST      ┌─────────────────┐
│  Roblox Studio  │  ───────────────▶  │     VS Code     │
│     Plugin      │     /sync           │   (built-in     │
│                 │                     │    server)      │
└─────────────────┘                     └─────────────────┘
```

## Quick Start

### 1. Install the VS Code Extension

```bash
cd vscode-extension
npm install
```

Then press `F5` in VS Code to run the extension in development mode.

**To package for permanent install:**
```bash
npm install -g vsce
vsce package
code --install-extension roblox-live-directory-tree-1.0.0.vsix
```

### 2. Install the Roblox Plugin

**Option A: Build with Rojo**
```bash
cd roblox-plugin

# Windows
rojo build default.project.json -o "%LOCALAPPDATA%/Roblox/Plugins/LiveDirectoryTree.rbxmx"

# macOS
rojo build default.project.json -o ~/Documents/Roblox/Plugins/LiveDirectoryTree.rbxmx
```

**Option B: Manual Install**
1. Open Roblox Studio
2. Go to Plugins → Manage Plugins → Create New Plugin
3. Paste the contents of `roblox-plugin/LiveDirectoryTree.lua`
4. Save the plugin

### 3. Connect!

1. **In VS Code:** Click the **▶ Start Server** button in the Roblox Directory sidebar
2. **In Roblox Studio:** Click "Connect" in the Live Directory Tree widget
3. The tree appears in VS Code - click **📋 Copy** to copy for AI!

## Usage

### VS Code Sidebar Buttons

| Button | Action |
|--------|--------|
| **▶** | Start the server |
| **⏹** | Stop the server |
| **🔄** | Refresh the tree |
| **📋** | Copy entire tree to clipboard |

### In Roblox Studio

- **Connect Button** - Opens widget and connects to server
- **Sync Now Button** - Forces an immediate sync
- **Auto-sync Toggle** - Enable/disable automatic syncing

### For AI Assistants

Click the **📋 Copy** button in VS Code and paste into your AI chat:

```
=====================================
  PROJECT DIRECTORY TREE
  Game: MyAwesomeGame
  For AI Assistant Context
=====================================

ReplicatedStorage [ReplicatedStorage]
├── Shared [Folder]
│   ├── Constants [ModuleScript] (45 lines)
│   └── Utils [Folder]
│       ├── Math [ModuleScript] (120 lines)
│       └── String [ModuleScript] (85 lines)
└── Remotes [Folder]
    ├── PlayerJoined [RemoteEvent]
    └── GetData [RemoteFunction]

ServerScriptService [ServerScriptService]
├── Services [Folder]
│   ├── DataService [ModuleScript] (250 lines)
│   └── GameService [ModuleScript] (180 lines)
└── Main [Script] (30 lines)
```

## Configuration

### VS Code Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `robloxDirectoryTree.serverPort` | `21326` | Port for the built-in server |
| `robloxDirectoryTree.autoRefresh` | `true` | Auto-refresh the tree view |
| `robloxDirectoryTree.refreshInterval` | `3000` | Refresh interval (ms) |
| `robloxDirectoryTree.autoStartServer` | `false` | Start server when VS Code opens |

### Plugin Filters

In the Roblox plugin, customize which services are scanned by modifying the `CONFIG` table:

```lua
CONFIG.SCAN_CONTAINERS = {
    game:GetService("ReplicatedStorage"),
    game:GetService("ServerScriptService"),
    -- Add or remove services as needed
}
```

## Troubleshooting

### "Connection failed" in Roblox Studio

1. Make sure the server is running in VS Code (click ▶)
2. Check that HttpService is enabled in Game Settings → Security
3. Verify the URL is correct (default: `http://localhost:21326`)

### VS Code shows "Waiting for connection"

1. Make sure you clicked ▶ to start the server
2. Make sure Roblox Studio plugin is connected
3. Try clicking the refresh button

### Port already in use

Change the port in VS Code settings:
1. Open Settings (Ctrl+,)
2. Search "robloxDirectoryTree.serverPort"
3. Change to a different port (e.g., 21327)
4. Update the URL in the Roblox plugin to match

## Standalone Server (Optional)

If you prefer to run the server separately (e.g., for debugging), there's also a standalone Node.js server in the `server/` folder:

```bash
cd server
node server.js
```

## License

MIT - Feel free to modify and share!
