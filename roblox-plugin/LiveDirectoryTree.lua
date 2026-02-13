--[[
	Live Directory Tree Plugin
	Syncs your project structure to VS Code in real-time
	
	Works with the LiveDirectoryTree server and VS Code extension
	
	Version: 2.0.0 - Now with service selection!
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
	"rbxassetid://111621702308897"
)

local syncButton = toolbar:CreateButton(
	"Sync Now",
	"Manually sync directory tree",
	"rbxassetid://6031082533"
)

-- All available services that can be synced
local ALL_SERVICES = {
	{ name = "ReplicatedStorage", service = game:GetService("ReplicatedStorage"), default = true },
	{ name = "ServerScriptService", service = game:GetService("ServerScriptService"), default = true },
	{ name = "ServerStorage", service = game:GetService("ServerStorage"), default = true },
	{ name = "StarterGui", service = game:GetService("StarterGui"), default = true },
	{ name = "StarterPlayer", service = game:GetService("StarterPlayer"), default = true },
	{ name = "StarterPack", service = game:GetService("StarterPack"), default = true },
	{ name = "Workspace", service = game:GetService("Workspace"), default = false },
	{ name = "Lighting", service = game:GetService("Lighting"), default = false },
	{ name = "SoundService", service = game:GetService("SoundService"), default = false },
	{ name = "ReplicatedFirst", service = game:GetService("ReplicatedFirst"), default = false },
	{ name = "Chat", service = game:GetService("Chat"), default = false },
	{ name = "LocalizationService", service = game:GetService("LocalizationService"), default = false },
	{ name = "TestService", service = game:GetService("TestService"), default = false },
}

-- Configuration
local CONFIG = {
	SERVER_URL = "http://localhost:21326",
	SYNC_INTERVAL = 3,
	AUTO_SYNC = true,

	-- This will be populated by checkboxes
	ENABLED_SERVICES = {},

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

-- Initialize enabled services from defaults
for _, svc in ipairs(ALL_SERVICES) do
	CONFIG.ENABLED_SERVICES[svc.name] = svc.default
end

-- State
local isConnected = false
local lastTreeHash = ""
local changeConnections = {}
local syncLoop = nil
local serviceCheckboxes = {}

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
	320,
	550,
	280,
	400
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

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1, 0, 1, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 800)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = mainFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = scrollFrame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scrollFrame

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 25)
	title.BackgroundTransparency = 1
	title.Text = "🌲 Live Directory Tree"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.LayoutOrder = 1
	title.Parent = scrollFrame

	-- Status indicator
	local statusFrame = Instance.new("Frame")
	statusFrame.Size = UDim2.new(1, 0, 0, 30)
	statusFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	statusFrame.BorderSizePixel = 0
	statusFrame.LayoutOrder = 2
	statusFrame.Parent = scrollFrame

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
	urlLabel.Parent = scrollFrame

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
	urlInput.Parent = scrollFrame

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
		btn.Size = UDim2.new(1, 0, 0, 32)
		btn.BackgroundColor3 = color
		btn.BorderSizePixel = 0
		btn.Text = text
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.TextSize = 13
		btn.Font = Enum.Font.GothamSemibold
		btn.LayoutOrder = order
		btn.AutoButtonColor = true
		btn.Parent = scrollFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn

		return btn
	end

	-- Buttons
	local connectBtn = createButton("🔌 Connect", Color3.fromRGB(0, 120, 215), 5)
	local syncBtn = createButton("🔄 Sync Now", Color3.fromRGB(80, 160, 80), 6)
	local disconnectBtn = createButton("⏹ Disconnect", Color3.fromRGB(180, 60, 60), 7)

	-- ========================================
	-- SERVICES SELECTION SECTION
	-- ========================================

	local servicesLabel = Instance.new("TextLabel")
	servicesLabel.Size = UDim2.new(1, 0, 0, 25)
	servicesLabel.BackgroundTransparency = 1
	servicesLabel.Text = "📁 Select Services to Sync:"
	servicesLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	servicesLabel.TextSize = 13
	servicesLabel.Font = Enum.Font.GothamBold
	servicesLabel.TextXAlignment = Enum.TextXAlignment.Left
	servicesLabel.LayoutOrder = 8
	servicesLabel.Parent = scrollFrame

	-- Select All / Deselect All buttons
	local selectAllFrame = Instance.new("Frame")
	selectAllFrame.Size = UDim2.new(1, 0, 0, 28)
	selectAllFrame.BackgroundTransparency = 1
	selectAllFrame.LayoutOrder = 9
	selectAllFrame.Parent = scrollFrame

	local selectAllBtn = Instance.new("TextButton")
	selectAllBtn.Size = UDim2.new(0.48, 0, 1, 0)
	selectAllBtn.Position = UDim2.new(0, 0, 0, 0)
	selectAllBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	selectAllBtn.BorderSizePixel = 0
	selectAllBtn.Text = "Select All"
	selectAllBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
	selectAllBtn.TextSize = 11
	selectAllBtn.Font = Enum.Font.Gotham
	selectAllBtn.Parent = selectAllFrame

	local selectAllCorner = Instance.new("UICorner")
	selectAllCorner.CornerRadius = UDim.new(0, 4)
	selectAllCorner.Parent = selectAllBtn

	local deselectAllBtn = Instance.new("TextButton")
	deselectAllBtn.Size = UDim2.new(0.48, 0, 1, 0)
	deselectAllBtn.Position = UDim2.new(0.52, 0, 0, 0)
	deselectAllBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	deselectAllBtn.BorderSizePixel = 0
	deselectAllBtn.Text = "Deselect All"
	deselectAllBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
	deselectAllBtn.TextSize = 11
	deselectAllBtn.Font = Enum.Font.Gotham
	deselectAllBtn.Parent = selectAllFrame

	local deselectAllCorner = Instance.new("UICorner")
	deselectAllCorner.CornerRadius = UDim.new(0, 4)
	deselectAllCorner.Parent = deselectAllBtn

	-- Create checkbox for each service
	local function createServiceCheckbox(svc, order)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 26)
		frame.BackgroundTransparency = 1
		frame.LayoutOrder = order
		frame.Parent = scrollFrame

		local checkbox = Instance.new("TextButton")
		checkbox.Size = UDim2.new(0, 22, 0, 22)
		checkbox.Position = UDim2.new(0, 0, 0.5, -11)
		checkbox.BackgroundColor3 = CONFIG.ENABLED_SERVICES[svc.name] and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(60, 60, 60)
		checkbox.BorderSizePixel = 0
		checkbox.Text = CONFIG.ENABLED_SERVICES[svc.name] and "✓" or ""
		checkbox.TextColor3 = Color3.fromRGB(255, 255, 255)
		checkbox.TextSize = 14
		checkbox.Font = Enum.Font.GothamBold
		checkbox.Parent = frame

		local checkCorner = Instance.new("UICorner")
		checkCorner.CornerRadius = UDim.new(0, 4)
		checkCorner.Parent = checkbox

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -30, 1, 0)
		label.Position = UDim2.new(0, 30, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = svc.name
		label.TextColor3 = Color3.fromRGB(200, 200, 200)
		label.TextSize = 12
		label.Font = Enum.Font.Gotham
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = frame

		-- Toggle function
		local function updateCheckbox()
			local enabled = CONFIG.ENABLED_SERVICES[svc.name]
			checkbox.BackgroundColor3 = enabled and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(60, 60, 60)
			checkbox.Text = enabled and "✓" or ""
		end

		checkbox.MouseButton1Click:Connect(function()
			CONFIG.ENABLED_SERVICES[svc.name] = not CONFIG.ENABLED_SERVICES[svc.name]
			updateCheckbox()
		end)

		-- Store reference for select all/deselect all
		serviceCheckboxes[svc.name] = {
			checkbox = checkbox,
			update = updateCheckbox
		}

		return frame
	end

	-- Create checkboxes for all services
	for i, svc in ipairs(ALL_SERVICES) do
		createServiceCheckbox(svc, 9 + i)
	end

	-- Select All / Deselect All handlers
	selectAllBtn.MouseButton1Click:Connect(function()
		for _, svc in ipairs(ALL_SERVICES) do
			CONFIG.ENABLED_SERVICES[svc.name] = true
			if serviceCheckboxes[svc.name] then
				serviceCheckboxes[svc.name].update()
			end
		end
	end)

	deselectAllBtn.MouseButton1Click:Connect(function()
		for _, svc in ipairs(ALL_SERVICES) do
			CONFIG.ENABLED_SERVICES[svc.name] = false
			if serviceCheckboxes[svc.name] then
				serviceCheckboxes[svc.name].update()
			end
		end
	end)

	-- ========================================
	-- AUTO-SYNC AND FILTERS
	-- ========================================

	local optionsLabel = Instance.new("TextLabel")
	optionsLabel.Size = UDim2.new(1, 0, 0, 25)
	optionsLabel.BackgroundTransparency = 1
	optionsLabel.Text = "⚙️ Options:"
	optionsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	optionsLabel.TextSize = 13
	optionsLabel.Font = Enum.Font.GothamBold
	optionsLabel.TextXAlignment = Enum.TextXAlignment.Left
	optionsLabel.LayoutOrder = 50
	optionsLabel.Parent = scrollFrame

	-- Auto-sync toggle
	local autoSyncFrame = Instance.new("Frame")
	autoSyncFrame.Size = UDim2.new(1, 0, 0, 26)
	autoSyncFrame.BackgroundTransparency = 1
	autoSyncFrame.LayoutOrder = 51
	autoSyncFrame.Parent = scrollFrame

	local autoSyncCheckbox = Instance.new("TextButton")
	autoSyncCheckbox.Size = UDim2.new(0, 22, 0, 22)
	autoSyncCheckbox.Position = UDim2.new(0, 0, 0.5, -11)
	autoSyncCheckbox.BackgroundColor3 = CONFIG.AUTO_SYNC and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(60, 60, 60)
	autoSyncCheckbox.BorderSizePixel = 0
	autoSyncCheckbox.Text = CONFIG.AUTO_SYNC and "✓" or ""
	autoSyncCheckbox.TextColor3 = Color3.fromRGB(255, 255, 255)
	autoSyncCheckbox.TextSize = 14
	autoSyncCheckbox.Font = Enum.Font.GothamBold
	autoSyncCheckbox.Parent = autoSyncFrame

	local autoSyncCorner = Instance.new("UICorner")
	autoSyncCorner.CornerRadius = UDim.new(0, 4)
	autoSyncCorner.Parent = autoSyncCheckbox

	local autoSyncLabel = Instance.new("TextLabel")
	autoSyncLabel.Size = UDim2.new(1, -30, 1, 0)
	autoSyncLabel.Position = UDim2.new(0, 30, 0, 0)
	autoSyncLabel.BackgroundTransparency = 1
	autoSyncLabel.Text = "Auto-sync enabled"
	autoSyncLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	autoSyncLabel.TextSize = 12
	autoSyncLabel.Font = Enum.Font.Gotham
	autoSyncLabel.TextXAlignment = Enum.TextXAlignment.Left
	autoSyncLabel.Parent = autoSyncFrame

	autoSyncCheckbox.MouseButton1Click:Connect(function()
		CONFIG.AUTO_SYNC = not CONFIG.AUTO_SYNC
		autoSyncCheckbox.BackgroundColor3 = CONFIG.AUTO_SYNC and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(60, 60, 60)
		autoSyncCheckbox.Text = CONFIG.AUTO_SYNC and "✓" or ""
	end)

	-- Use filters toggle
	local filtersFrame = Instance.new("Frame")
	filtersFrame.Size = UDim2.new(1, 0, 0, 26)
	filtersFrame.BackgroundTransparency = 1
	filtersFrame.LayoutOrder = 52
	filtersFrame.Parent = scrollFrame

	local filtersCheckbox = Instance.new("TextButton")
	filtersCheckbox.Size = UDim2.new(0, 22, 0, 22)
	filtersCheckbox.Position = UDim2.new(0, 0, 0.5, -11)
	filtersCheckbox.BackgroundColor3 = CONFIG.USE_FILTERS and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(60, 60, 60)
	filtersCheckbox.BorderSizePixel = 0
	filtersCheckbox.Text = CONFIG.USE_FILTERS and "✓" or ""
	filtersCheckbox.TextColor3 = Color3.fromRGB(255, 255, 255)
	filtersCheckbox.TextSize = 14
	filtersCheckbox.Font = Enum.Font.GothamBold
	filtersCheckbox.Parent = filtersFrame

	local filtersCorner = Instance.new("UICorner")
	filtersCorner.CornerRadius = UDim.new(0, 4)
	filtersCorner.Parent = filtersCheckbox

	local filtersLabel = Instance.new("TextLabel")
	filtersLabel.Size = UDim2.new(1, -30, 1, 0)
	filtersLabel.Position = UDim2.new(0, 30, 0, 0)
	filtersLabel.BackgroundTransparency = 1
	filtersLabel.Text = "Filter non-code items"
	filtersLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	filtersLabel.TextSize = 12
	filtersLabel.Font = Enum.Font.Gotham
	filtersLabel.TextXAlignment = Enum.TextXAlignment.Left
	filtersLabel.Parent = filtersFrame

	filtersCheckbox.MouseButton1Click:Connect(function()
		CONFIG.USE_FILTERS = not CONFIG.USE_FILTERS
		filtersCheckbox.BackgroundColor3 = CONFIG.USE_FILTERS and Color3.fromRGB(0, 150, 80) or Color3.fromRGB(60, 60, 60)
		filtersCheckbox.Text = CONFIG.USE_FILTERS and "✓" or ""
	end)

	-- ========================================
	-- LOG AREA
	-- ========================================

	local logLabel = Instance.new("TextLabel")
	logLabel.Size = UDim2.new(1, 0, 0, 20)
	logLabel.BackgroundTransparency = 1
	logLabel.Text = "📋 Activity Log:"
	logLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	logLabel.TextSize = 11
	logLabel.Font = Enum.Font.GothamBold
	logLabel.TextXAlignment = Enum.TextXAlignment.Left
	logLabel.LayoutOrder = 60
	logLabel.Parent = scrollFrame

	local logFrame = Instance.new("ScrollingFrame")
	logFrame.Size = UDim2.new(1, 0, 0, 100)
	logFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	logFrame.BorderSizePixel = 0
	logFrame.ScrollBarThickness = 4
	logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	logFrame.LayoutOrder = 61
	logFrame.Parent = scrollFrame

	local logCorner = Instance.new("UICorner")
	logCorner.CornerRadius = UDim.new(0, 4)
	logCorner.Parent = logFrame

	local logLayout = Instance.new("UIListLayout")
	logLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logLayout.Padding = UDim.new(0, 2)
	logLayout.Parent = logFrame

	local logPadding = Instance.new("UIPadding")
	logPadding.PaddingTop = UDim.new(0, 4)
	logPadding.PaddingLeft = UDim.new(0, 4)
	logPadding.PaddingRight = UDim.new(0, 4)
	logPadding.Parent = logFrame

	local logIndex = 0

	return {
		statusDot = statusDot,
		statusLabel = statusLabel,
		urlInput = urlInput,
		connectBtn = connectBtn,
		syncBtn = syncBtn,
		disconnectBtn = disconnectBtn,
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
	entry.TextSize = 9
	entry.Font = Enum.Font.Code
	entry.TextXAlignment = Enum.TextXAlignment.Left
	entry.TextWrapped = true
	entry.LayoutOrder = ui.logIndex()
	entry.Parent = ui.logFrame

	-- Auto-scroll
	ui.logFrame.CanvasPosition = Vector2.new(0, ui.logFrame.AbsoluteCanvasSize.Y)

	print("[LiveDirectoryTree]", message)
end

-- Update connection status
local function updateStatus(connected, message)
	isConnected = connected
	ui.statusDot.BackgroundColor3 = connected and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
	ui.statusLabel.Text = message or (connected and "Connected" or "Disconnected")
	ui.connectBtn.Text = connected and "✓ Connected" or "🔌 Connect"
	ui.connectBtn.BackgroundColor3 = connected and Color3.fromRGB(60, 140, 60) or Color3.fromRGB(0, 120, 215)
end

-- Get list of enabled services
local function getEnabledServices()
	local services = {}
	for _, svc in ipairs(ALL_SERVICES) do
		if CONFIG.ENABLED_SERVICES[svc.name] then
			table.insert(services, svc.service)
		end
	end
	return services
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

-- Build tree data structure
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

	-- Add script line count
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
		node.childCount = #instance:GetChildren()
	end

	return node
end

-- Build full tree from enabled services only
local function buildFullTree()
	local enabledServices = getEnabledServices()

	local tree = {
		name = game.Name ~= "" and game.Name or "Game",
		timestamp = os.time(),
		containers = {},
	}

	for _, container in ipairs(enabledServices) do
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

	local enabledCount = 0
	for _, enabled in pairs(CONFIG.ENABLED_SERVICES) do
		if enabled then enabledCount = enabledCount + 1 end
	end

	if enabledCount == 0 then
		log("No services selected!", Color3.fromRGB(255, 150, 100))
		return false
	end

	local tree = buildFullTree()
	local json = HttpService:JSONEncode(tree)

	-- Simple hash to detect changes
	local hash = #json .. "-" .. (tree.timestamp or 0)
	if hash == lastTreeHash then
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
		log("Synced " .. enabledCount .. " services (" .. #json .. " bytes)", Color3.fromRGB(100, 255, 100))
		return true
	else
		log("Sync failed: " .. tostring(result), Color3.fromRGB(255, 100, 100))
		return false
	end
end

-- Test connection
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

-- Setup change listeners for enabled services only
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

	-- Listen to enabled services only
	for _, svc in ipairs(ALL_SERVICES) do
		if CONFIG.ENABLED_SERVICES[svc.name] and svc.service then
			table.insert(changeConnections, svc.service.DescendantAdded:Connect(function(desc)
				log("+ " .. desc.Name, Color3.fromRGB(100, 200, 100))
				onChanged()
			end))

			table.insert(changeConnections, svc.service.DescendantRemoving:Connect(function(desc)
				log("- " .. desc.Name, Color3.fromRGB(200, 100, 100))
				onChanged()
			end))
		end
	end

	log("Watching " .. #changeConnections / 2 .. " services", Color3.fromRGB(150, 150, 255))
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
		syncToServer()
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

ui.urlInput.FocusLost:Connect(function(enterPressed)
	CONFIG.SERVER_URL = ui.urlInput.Text
	if enterPressed and not isConnected then
		connect()
	end
end)

-- Toolbar handlers
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
		log("Connect first", Color3.fromRGB(255, 200, 100))
	end
end)

-- Initialize
widget.Enabled = false
log("Plugin loaded. Select services and connect!", Color3.fromRGB(150, 200, 255))
print("[LiveDirectoryTree] Plugin loaded!")