--[[
	Live Directory Tree Plugin
	Syncs your project structure to VS Code in real-time
	
	Works with the LiveDirectoryTree server and VS Code extension
	
	Version: 1.0.0
]]

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")

-- Plugin Setup
local Plugin = script:FindFirstAncestorWhichIsA("Plugin")
local toolbar = Plugin:CreateToolbar("Live Directory Tree")

local connectButton = toolbar:CreateButton(
	"Connect",
	"Connect to Live Directory Tree server",
	"rbxassetid://6031091004"
)

local syncButton = toolbar:CreateButton(
	"Sync Now",
	"Manually sync directory tree",
	"rbxassetid://6031082533"
)

-- Configuration
local CONFIG = {
	SERVER_URL = "http://localhost:21326", -- Default port (ROBLOX in numbers: 21326)
	SYNC_INTERVAL = 3, -- Seconds between auto-syncs
	AUTO_SYNC = true,
	
	-- Containers to scan
	SCAN_CONTAINERS = {
		game:GetService("ReplicatedStorage"),
		game:GetService("ServerScriptService"),
		game:GetService("ServerStorage"),
		game:GetService("StarterGui"),
		game:GetService("StarterPlayer"),
		game:GetService("StarterPack"),
		-- game:GetService("Workspace"), -- Usually too large
	},
	
	-- Classes to skip
	SKIP_CLASSES = {
		"Terrain", "Camera", "Attachment", "Weld", "WeldConstraint",
		"Motor6D", "ParticleEmitter", "PointLight", "SpotLight",
		"SurfaceLight", "Beam", "Trail", "Texture", "Decal",
		"SpecialMesh", "BlockMesh", "CylinderMesh",
	},
	
	-- Don't recurse into these
	SHALLOW_CLASSES = {
		"Model", "Part", "MeshPart", "UnionOperation", "BasePart",
		"Accessory", "Humanoid",
	},
	
	USE_FILTERS = true,
}

-- State
local isConnected = false
local lastTreeHash = ""
local changeConnections = {}
local syncLoop = nil

-- Class indicators for the tree
local CLASS_ICONS = {
	ModuleScript = "module",
	Script = "script",
	LocalScript = "localscript",
	Folder = "folder",
	Model = "model",
	Part = "part",
	MeshPart = "meshpart",
	UnionOperation = "union",
	ScreenGui = "screengui",
	Frame = "frame",
	TextLabel = "textlabel",
	TextButton = "textbutton",
	ImageLabel = "imagelabel",
	ImageButton = "imagebutton",
	ScrollingFrame = "scrollingframe",
	RemoteEvent = "remoteevent",
	RemoteFunction = "remotefunction",
	BindableEvent = "bindableevent",
	BindableFunction = "bindablefunction",
	StringValue = "stringvalue",
	NumberValue = "numbervalue",
	BoolValue = "boolvalue",
	ObjectValue = "objectvalue",
	Tool = "tool",
	Sound = "sound",
	Animation = "animation",
	Animator = "animator",
}

-- Widget for settings/status
local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false,
	false,
	300,
	400,
	250,
	300
)

local widget = Plugin:CreateDockWidgetPluginGui("LiveDirectoryTreeWidget", widgetInfo)
widget.Title = "Live Directory Tree"

-- Build Widget UI
local function createUI()
	local mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(46, 46, 46)
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = widget
	
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = mainFrame
	
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = mainFrame
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 25)
	title.BackgroundTransparency = 1
	title.Text = "🌲 Live Directory Tree"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.LayoutOrder = 1
	title.Parent = mainFrame
	
	-- Status indicator
	local statusFrame = Instance.new("Frame")
	statusFrame.Size = UDim2.new(1, 0, 0, 30)
	statusFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	statusFrame.BorderSizePixel = 0
	statusFrame.LayoutOrder = 2
	statusFrame.Parent = mainFrame
	
	local statusCorner = Instance.new("UICorner")
	statusCorner.CornerRadius = UDim.new(0, 6)
	statusCorner.Parent = statusFrame
	
	local statusDot = Instance.new("Frame")
	statusDot.Size = UDim2.new(0, 12, 0, 12)
	statusDot.Position = UDim2.new(0, 10, 0.5, -6)
	statusDot.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
	statusDot.BorderSizePixel = 0
	statusDot.Parent = statusFrame
	
	local statusDotCorner = Instance.new("UICorner")
	statusDotCorner.CornerRadius = UDim.new(1, 0)
	statusDotCorner.Parent = statusDot
	
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -35, 1, 0)
	statusLabel.Position = UDim2.new(0, 30, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Disconnected"
	statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	statusLabel.TextSize = 12
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = statusFrame
	
	-- Server URL input
	local urlLabel = Instance.new("TextLabel")
	urlLabel.Size = UDim2.new(1, 0, 0, 20)
	urlLabel.BackgroundTransparency = 1
	urlLabel.Text = "Server URL:"
	urlLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	urlLabel.TextSize = 11
	urlLabel.Font = Enum.Font.Gotham
	urlLabel.TextXAlignment = Enum.TextXAlignment.Left
	urlLabel.LayoutOrder = 3
	urlLabel.Parent = mainFrame
	
	local urlInput = Instance.new("TextBox")
	urlInput.Size = UDim2.new(1, 0, 0, 30)
	urlInput.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	urlInput.BorderSizePixel = 0
	urlInput.Text = CONFIG.SERVER_URL
	urlInput.TextColor3 = Color3.fromRGB(220, 220, 220)
	urlInput.PlaceholderText = "http://localhost:21326"
	urlInput.TextSize = 12
	urlInput.Font = Enum.Font.Code
	urlInput.ClearTextOnFocus = false
	urlInput.LayoutOrder = 4
	urlInput.Parent = mainFrame
	
	local urlCorner = Instance.new("UICorner")
	urlCorner.CornerRadius = UDim.new(0, 4)
	urlCorner.Parent = urlInput
	
	local urlPadding = Instance.new("UIPadding")
	urlPadding.PaddingLeft = UDim.new(0, 8)
	urlPadding.PaddingRight = UDim.new(0, 8)
	urlPadding.Parent = urlInput
	
	-- Button helper
	local function createButton(text, color, order)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 35)
		btn.BackgroundColor3 = color
		btn.BorderSizePixel = 0
		btn.Text = text
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.TextSize = 13
		btn.Font = Enum.Font.GothamSemibold
		btn.LayoutOrder = order
		btn.AutoButtonColor = true
		btn.Parent = mainFrame
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn
		
		return btn
	end
	
	-- Buttons
	local connectBtn = createButton("🔌 Connect", Color3.fromRGB(0, 120, 215), 5)
	local syncBtn = createButton("🔄 Sync Now", Color3.fromRGB(80, 160, 80), 6)
	local disconnectBtn = createButton("⏹ Disconnect", Color3.fromRGB(180, 60, 60), 7)
	
	-- Auto-sync toggle
	local autoSyncFrame = Instance.new("Frame")
	autoSyncFrame.Size = UDim2.new(1, 0, 0, 30)
	autoSyncFrame.BackgroundTransparency = 1
	autoSyncFrame.LayoutOrder = 8
	autoSyncFrame.Parent = mainFrame
	
	local autoSyncLabel = Instance.new("TextLabel")
	autoSyncLabel.Size = UDim2.new(0.7, 0, 1, 0)
	autoSyncLabel.BackgroundTransparency = 1
	autoSyncLabel.Text = "Auto-sync enabled"
	autoSyncLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	autoSyncLabel.TextSize = 12
	autoSyncLabel.Font = Enum.Font.Gotham
	autoSyncLabel.TextXAlignment = Enum.TextXAlignment.Left
	autoSyncLabel.Parent = autoSyncFrame
	
	local autoSyncToggle = Instance.new("TextButton")
	autoSyncToggle.Size = UDim2.new(0, 50, 0, 24)
	autoSyncToggle.Position = UDim2.new(1, -50, 0.5, -12)
	autoSyncToggle.BackgroundColor3 = CONFIG.AUTO_SYNC and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(100, 100, 100)
	autoSyncToggle.BorderSizePixel = 0
	autoSyncToggle.Text = CONFIG.AUTO_SYNC and "ON" or "OFF"
	autoSyncToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	autoSyncToggle.TextSize = 11
	autoSyncToggle.Font = Enum.Font.GothamBold
	autoSyncToggle.Parent = autoSyncFrame
	
	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 12)
	toggleCorner.Parent = autoSyncToggle
	
	-- Sync interval
	local intervalLabel = Instance.new("TextLabel")
	intervalLabel.Size = UDim2.new(1, 0, 0, 20)
	intervalLabel.BackgroundTransparency = 1
	intervalLabel.Text = "Sync interval: " .. CONFIG.SYNC_INTERVAL .. "s"
	intervalLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	intervalLabel.TextSize = 11
	intervalLabel.Font = Enum.Font.Gotham
	intervalLabel.TextXAlignment = Enum.TextXAlignment.Left
	intervalLabel.LayoutOrder = 9
	intervalLabel.Parent = mainFrame
	
	-- Log area
	local logLabel = Instance.new("TextLabel")
	logLabel.Size = UDim2.new(1, 0, 0, 20)
	logLabel.BackgroundTransparency = 1
	logLabel.Text = "Activity Log:"
	logLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	logLabel.TextSize = 11
	logLabel.Font = Enum.Font.Gotham
	logLabel.TextXAlignment = Enum.TextXAlignment.Left
	logLabel.LayoutOrder = 10
	logLabel.Parent = mainFrame
	
	local logFrame = Instance.new("ScrollingFrame")
	logFrame.Size = UDim2.new(1, 0, 1, -280)
	logFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	logFrame.BorderSizePixel = 0
	logFrame.ScrollBarThickness = 6
	logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	logFrame.LayoutOrder = 11
	logFrame.Parent = mainFrame
	
	local logCorner = Instance.new("UICorner")
	logCorner.CornerRadius = UDim.new(0, 4)
	logCorner.Parent = logFrame
	
	local logLayout = Instance.new("UIListLayout")
	logLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logLayout.Padding = UDim.new(0, 2)
	logLayout.Parent = logFrame
	
	local logPadding = Instance.new("UIPadding")
	logPadding.PaddingTop = UDim.new(0, 5)
	logPadding.PaddingLeft = UDim.new(0, 5)
	logPadding.PaddingRight = UDim.new(0, 5)
	logPadding.Parent = logFrame
	
	local logIndex = 0
	
	return {
		statusDot = statusDot,
		statusLabel = statusLabel,
		urlInput = urlInput,
		connectBtn = connectBtn,
		syncBtn = syncBtn,
		disconnectBtn = disconnectBtn,
		autoSyncToggle = autoSyncToggle,
		autoSyncLabel = autoSyncLabel,
		logFrame = logFrame,
		logIndex = function()
			logIndex = logIndex + 1
			return logIndex
		end,
	}
end

local ui = createUI()

-- Logging function
local function log(message, color)
	color = color or Color3.fromRGB(180, 180, 180)
	
	local entry = Instance.new("TextLabel")
	entry.Size = UDim2.new(1, -10, 0, 0)
	entry.AutomaticSize = Enum.AutomaticSize.Y
	entry.BackgroundTransparency = 1
	entry.Text = os.date("[%H:%M:%S] ") .. message
	entry.TextColor3 = color
	entry.TextSize = 10
	entry.Font = Enum.Font.Code
	entry.TextXAlignment = Enum.TextXAlignment.Left
	entry.TextWrapped = true
	entry.LayoutOrder = ui.logIndex()
	entry.Parent = ui.logFrame
	
	-- Auto-scroll to bottom
	ui.logFrame.CanvasPosition = Vector2.new(0, ui.logFrame.AbsoluteCanvasSize.Y)
	
	print("[LiveDirectoryTree]", message)
end

-- Update connection status UI
local function updateStatus(connected, message)
	isConnected = connected
	ui.statusDot.BackgroundColor3 = connected and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
	ui.statusLabel.Text = message or (connected and "Connected" or "Disconnected")
	ui.connectBtn.Text = connected and "✓ Connected" or "🔌 Connect"
	ui.connectBtn.BackgroundColor3 = connected and Color3.fromRGB(60, 140, 60) or Color3.fromRGB(0, 120, 215)
end

-- Check if class should be skipped
local function shouldSkipClass(instance)
	if not CONFIG.USE_FILTERS then return false end
	for _, className in ipairs(CONFIG.SKIP_CLASSES) do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

-- Check if we should recurse
local function shouldRecurse(instance)
	if not CONFIG.USE_FILTERS then return true end
	for _, className in ipairs(CONFIG.SHALLOW_CLASSES) do
		if instance:IsA(className) and not instance:IsA("Folder") and not instance:IsA("LuaSourceContainer") then
			return false
		end
	end
	return true
end

-- Build tree data structure (JSON-friendly)
local function buildTreeNode(instance, depth)
	if depth > 50 then return nil end
	if shouldSkipClass(instance) then return nil end
	
	local node = {
		name = instance.Name,
		className = instance.ClassName,
		icon = CLASS_ICONS[instance.ClassName] or "default",
		path = instance:GetFullName(),
		children = {},
	}
	
	-- Add script info if applicable
	if instance:IsA("LuaSourceContainer") then
		local success, lineCount = pcall(function()
			local source = instance.Source
			local _, count = source:gsub("\n", "\n")
			return count + 1
		end)
		if success then
			node.lineCount = lineCount
		end
	end
	
	-- Recurse into children
	if shouldRecurse(instance) then
		local children = instance:GetChildren()
		table.sort(children, function(a, b)
			local aIsFolder = a:IsA("Folder")
			local bIsFolder = b:IsA("Folder")
			local aIsScript = a:IsA("LuaSourceContainer")
			local bIsScript = b:IsA("LuaSourceContainer")
			
			if aIsFolder ~= bIsFolder then return aIsFolder end
			if aIsScript ~= bIsScript then return aIsScript end
			return a.Name < b.Name
		end)
		
		for _, child in ipairs(children) do
			local childNode = buildTreeNode(child, depth + 1)
			if childNode then
				table.insert(node.children, childNode)
			end
		end
	else
		-- Show child count for shallow classes
		node.childCount = #instance:GetChildren()
	end
	
	return node
end

-- Build full tree
local function buildFullTree()
	local tree = {
		name = game.Name ~= "" and game.Name or "Game",
		timestamp = os.time(),
		containers = {},
	}
	
	for _, container in ipairs(CONFIG.SCAN_CONTAINERS) do
		if container then
			local containerNode = {
				name = container.Name,
				className = container.ClassName,
				icon = "service",
				path = container:GetFullName(),
				children = {},
			}
			
			for _, child in ipairs(container:GetChildren()) do
				local childNode = buildTreeNode(child, 1)
				if childNode then
					table.insert(containerNode.children, childNode)
				end
			end
			
			table.insert(tree.containers, containerNode)
		end
	end
	
	return tree
end

-- Send tree to server
local function syncToServer()
	if not isConnected then
		log("Not connected", Color3.fromRGB(255, 150, 100))
		return false
	end
	
	local tree = buildFullTree()
	local json = HttpService:JSONEncode(tree)
	
	-- Simple hash to detect changes
	local hash = #json .. "-" .. (tree.timestamp or 0)
	if hash == lastTreeHash then
		-- No changes
		return true
	end
	
	local success, result = pcall(function()
		return HttpService:PostAsync(
			CONFIG.SERVER_URL .. "/sync",
			json,
			Enum.HttpContentType.ApplicationJson,
			false
		)
	end)
	
	if success then
		lastTreeHash = hash
		log("Synced (" .. #json .. " bytes)", Color3.fromRGB(100, 255, 100))
		return true
	else
		log("Sync failed: " .. tostring(result), Color3.fromRGB(255, 100, 100))
		return false
	end
end

-- Test connection to server
local function testConnection()
	CONFIG.SERVER_URL = ui.urlInput.Text
	
	log("Connecting to " .. CONFIG.SERVER_URL .. "...")
	
	local success, result = pcall(function()
		return HttpService:GetAsync(CONFIG.SERVER_URL .. "/ping")
	end)
	
	if success then
		local data = HttpService:JSONDecode(result)
		if data.status == "ok" then
			updateStatus(true, "Connected to server")
			log("Connected!", Color3.fromRGB(100, 255, 100))
			return true
		end
	end
	
	updateStatus(false, "Connection failed")
	log("Failed: " .. tostring(result), Color3.fromRGB(255, 100, 100))
	return false
end

-- Setup change listeners
local function setupChangeListeners()
	-- Clean up old connections
	for _, conn in ipairs(changeConnections) do
		conn:Disconnect()
	end
	changeConnections = {}
	
	local function onChanged()
		if CONFIG.AUTO_SYNC and isConnected then
			task.defer(syncToServer)
		end
	end
	
	-- Listen to each container
	for _, container in ipairs(CONFIG.SCAN_CONTAINERS) do
		if container then
			table.insert(changeConnections, container.DescendantAdded:Connect(function(desc)
				log("+ " .. desc.Name, Color3.fromRGB(100, 200, 100))
				onChanged()
			end))
			
			table.insert(changeConnections, container.DescendantRemoving:Connect(function(desc)
				log("- " .. desc.Name, Color3.fromRGB(200, 100, 100))
				onChanged()
			end))
		end
	end
	
	log("Change listeners active", Color3.fromRGB(150, 150, 255))
end

-- Start sync loop
local function startSyncLoop()
	if syncLoop then return end
	
	syncLoop = task.spawn(function()
		while isConnected do
			task.wait(CONFIG.SYNC_INTERVAL)
			if CONFIG.AUTO_SYNC and isConnected then
				syncToServer()
			end
		end
	end)
end

-- Stop sync loop
local function stopSyncLoop()
	if syncLoop then
		task.cancel(syncLoop)
		syncLoop = nil
	end
end

-- Connect
local function connect()
	if testConnection() then
		setupChangeListeners()
		startSyncLoop()
		syncToServer() -- Initial sync
	end
end

-- Disconnect
local function disconnect()
	stopSyncLoop()
	for _, conn in ipairs(changeConnections) do
		conn:Disconnect()
	end
	changeConnections = {}
	updateStatus(false, "Disconnected")
	log("Disconnected", Color3.fromRGB(255, 200, 100))
end

-- UI Event Handlers
ui.connectBtn.MouseButton1Click:Connect(function()
	if isConnected then
		-- Already connected, do nothing or reconnect
		syncToServer()
	else
		connect()
	end
end)

ui.syncBtn.MouseButton1Click:Connect(function()
	if isConnected then
		lastTreeHash = "" -- Force sync
		syncToServer()
	else
		log("Connect first!", Color3.fromRGB(255, 200, 100))
	end
end)

ui.disconnectBtn.MouseButton1Click:Connect(function()
	disconnect()
end)

ui.autoSyncToggle.MouseButton1Click:Connect(function()
	CONFIG.AUTO_SYNC = not CONFIG.AUTO_SYNC
	ui.autoSyncToggle.Text = CONFIG.AUTO_SYNC and "ON" or "OFF"
	ui.autoSyncToggle.BackgroundColor3 = CONFIG.AUTO_SYNC and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(100, 100, 100)
	log("Auto-sync: " .. (CONFIG.AUTO_SYNC and "enabled" or "disabled"))
end)

ui.urlInput.FocusLost:Connect(function(enterPressed)
	CONFIG.SERVER_URL = ui.urlInput.Text
	if enterPressed and not isConnected then
		connect()
	end
end)

-- Toolbar button handlers
connectButton.Click:Connect(function()
	widget.Enabled = true
	if not isConnected then
		connect()
	end
end)

syncButton.Click:Connect(function()
	if isConnected then
		lastTreeHash = ""
		syncToServer()
	else
		widget.Enabled = true
		log("Connect to server first", Color3.fromRGB(255, 200, 100))
	end
end)

-- Initialize
widget.Enabled = false
log("Plugin loaded. Click Connect to start.", Color3.fromRGB(150, 200, 255))
print("[LiveDirectoryTree] Plugin loaded! Click the toolbar button to open.")
