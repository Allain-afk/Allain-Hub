--// Allain Automation — Midnight Chasers: Highway Racing \\--
-- Keyless automation suite for Midnight Chasers: Highway Racing.
-- Features: Highway Road-Graph Auto-Drive, Traffic Cut-Up Weaving, Custom Route
-- Loop Auto-Drive, Auto-Farm Cash, Auto Collision Prevention, Cruise Control,
-- Auto Nitro/Boost, Auto-Shift Assist, Traffic & Player Car ESP, AFK Cash Tracker,
-- Anti-AFK, Low-Power/FPS Boost, Discord Alerts, and Built-in Data Scanner.
-- GameId: 4793836769 | PlaceId: 13822562292

local env = (getgenv and getgenv()) or shared
if env.__AllainMCLoading then
	return
end
env.__AllainMCLoading = true

if env.__AllainMCLibrary then
	pcall(function()
		env.__AllainMCLibrary:Unload()
	end)
	env.__AllainMCLibrary = nil
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local cloneref = (cloneref or clonereference or function(inst)
	return inst
end)

local Players = cloneref(game:GetService("Players"))
local Workspace = cloneref(game:GetService("Workspace"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local VirtualInputManager = cloneref(game:GetService("VirtualInputManager"))
local MarketplaceService = cloneref(game:GetService("MarketplaceService"))
local HttpService = cloneref(game:GetService("HttpService"))
local Lighting = cloneref(game:GetService("Lighting"))
local okVU, VirtualUser = pcall(function()
	return cloneref(game:GetService("VirtualUser"))
end)
if not okVU then
	VirtualUser = nil
end

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local repo = "https://raw.githubusercontent.com/Allain-afk/Allain-Hub/main/"
local okLib, Library = pcall(function()
	return loadstring(game:HttpGet(repo .. "Library.lua"))()
end)
if not okLib or not Library then
	env.__AllainMCLoading = false
	warn("[Allain MC] Failed to load UI library: " .. tostring(Library))
	return
end

env.__AllainMCLibrary = Library
env.__AllainMCLoading = false

local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

--// Window \\--
local Window = Library:CreateWindow({
	Title = "Allain Automation",
	Footer = "Midnight Chasers: Highway Racing",
	FooterLeft = "Midnight Chasers",
	FooterRight = "v0.1",
	Username = true,
	Badge = "Beta",
	NotifySide = "Right",
	Size = UDim2.fromOffset(640, 580),
	Center = true,
	AutoShow = true,
})

local Tabs = {
	AutoDrive = Window:AddTab("Auto-Drive", "car"),
	Assist = Window:AddTab("Assist", "shield"),
	Visuals = Window:AddTab("Visuals", "eye"),
	AFK = Window:AddTab("AFK & Farm", "clock"),
	Scanner = Window:AddTab("Scanner", "radar"),
	Settings = Window:AddTab("Settings", "settings"),
}

--============================================================================--
--// Core State & Cleanup Helpers
--============================================================================--
local Connections = {}
local Unloaded = false

-- Simulated input state
local HeldKeys = {}
local ControlKeys = {
	Throttle = Enum.KeyCode.W,
	Brake = Enum.KeyCode.S,
	SteerLeft = Enum.KeyCode.A,
	SteerRight = Enum.KeyCode.D,
	Nitro = Enum.KeyCode.LeftShift,
	ShiftUp = Enum.KeyCode.E,
	ShiftDown = Enum.KeyCode.Q,
	ToggleTransMode = Enum.KeyCode.M,
}

-- Driving / Sensor state
local SmoothedSteer = 0
local StuckTimer = 0
local ReverseUntil = 0
local ReverseSteerDir = 1
local LastShiftTime = 0
local PwmPhase = 0
local ActiveRayVisuals = {}
local DebugFolder = nil

-- Route Recorder / Loop state
local RecordingRoute = false
local RecordedPoints = {}
local LoadedRoutePoints = {}
local LoadedRouteName = ""
local RouteCursor = 1

-- Whole-Map Road Graph state
local MapRoadNodes = {}      -- { { pos = Vector3, neighbors = { idx, ... } }, ... }
local MapRoadGrid = {}       -- [cellKey] = { nodeIdx, ... }
local MapRoadBuilt = false
local MapRoadBuilding = false
local RecentRoadNodes = {}   -- ring buffer of recently passed node indices
local RecentRoadSet = {}
local LastRoadNodeIdx = nil

-- ESP state
local TrafficEspObjects = {}
local CarEspObjects = {}
local LastTrafficEspRefresh = 0

-- AFK / Cash Tracker state
local SessionStartTime = os.clock()
local StartCash = nil
local LastCash = 0
local LastCashTickTime = os.clock()
local LastCashTickAmount = 0
local DetectedCashName = "Cash"
local LastWebhookReportTime = 0

-- FPS Boost / Low Power state
local SavedLighting = nil
local LowPowerActive = false

-- Scanner state
local LastReportText = ""
local LastReportName = "mc_scan.txt"

local function trackConn(list, conn)
	if conn then
		table.insert(list, conn)
	end
	return conn
end

local function disconnectAll(list)
	for i = #list, 1, -1 do
		pcall(function()
			list[i]:Disconnect()
		end)
		list[i] = nil
	end
end

local function getRequestFunc()
	if type(request) == "function" then return request end
	if type(http_request) == "function" then return http_request end
	if type(syn) == "table" and type(syn.request) == "function" then return syn.request end
	if type(fluxus) == "table" and type(fluxus.request) == "function" then return fluxus.request end
	if type(http) == "table" and type(http.request) == "function" then return http.request end
	return nil
end

local function ensureFolders()
	if type(isfolder) ~= "function" or type(makefolder) ~= "function" then
		return
	end
	pcall(function()
		if not isfolder("AllainHub") then makefolder("AllainHub") end
		if not isfolder("AllainHub/scans") then makefolder("AllainHub/scans") end
		if not isfolder("AllainHub/routes") then makefolder("AllainHub/routes") end
		if not isfolder("AllainHub/routes/midnight-chasers") then makefolder("AllainHub/routes/midnight-chasers") end
	end)
end

--============================================================================--
--// Safe VirtualInputManager Driving Controls
--============================================================================--
local function setKey(keyCode, down)
	if not keyCode then return end
	local currentlyDown = HeldKeys[keyCode] == true
	if currentlyDown == down then
		return
	end
	HeldKeys[keyCode] = down
	pcall(function()
		VirtualInputManager:SendKeyEvent(down, keyCode, false, game)
	end)
end

local function tapKey(keyCode, holdTime)
	if not keyCode then return end
	task.spawn(function()
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
		end)
		task.wait(holdTime or 0.05)
		pcall(function()
			VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
		end)
	end)
end

local function releaseAllDrivingKeys()
	for kc, isDown in pairs(HeldKeys) do
		if isDown then
			HeldKeys[kc] = false
			pcall(function()
				VirtualInputManager:SendKeyEvent(false, kc, false, game)
			end)
		end
	end
end

-- Smooth PWM application: converts analog throttle [0..1], brake [0..1], steer [-1..1]
-- into responsive key holds/pulses for Roblox vehicle chassis.
local function applyDrivingInputs(throttle, brake, steer, dt, useNitro)
	PwmPhase = (PwmPhase + dt * 6) % 1

	-- Throttle & Brake (mutually exclusive)
	if brake > 0.08 then
		setKey(ControlKeys.Throttle, false)
		setKey(ControlKeys.Nitro, false)
		local brakeOn = brake >= 0.55 or (PwmPhase < brake)
		setKey(ControlKeys.Brake, brakeOn)
	elseif throttle > 0.08 then
		setKey(ControlKeys.Brake, false)
		local throttleOn = throttle >= 0.72 or (PwmPhase < throttle)
		setKey(ControlKeys.Throttle, throttleOn)
		setKey(ControlKeys.Nitro, useNitro == true and throttleOn)
	else
		setKey(ControlKeys.Throttle, false)
		setKey(ControlKeys.Brake, false)
		setKey(ControlKeys.Nitro, false)
	end

	-- Steering: negative = left, positive = right
	local absSteer = math.abs(steer)
	if absSteer < 0.08 then
		setKey(ControlKeys.SteerLeft, false)
		setKey(ControlKeys.SteerRight, false)
	else
		local duty = math.clamp(absSteer ^ 0.72, 0.22, 1.0)
		local steerOn = absSteer >= 0.52 or (PwmPhase < duty)
		if steer < 0 then
			setKey(ControlKeys.SteerRight, false)
			setKey(ControlKeys.SteerLeft, steerOn)
		else
			setKey(ControlKeys.SteerLeft, false)
			setKey(ControlKeys.SteerRight, steerOn)
		end
	end
end

--============================================================================--
--// Vehicle, Traffic & Currency Telemetry Helpers
--============================================================================--
local VEHICLE_FOLDER_NAMES = {
	"Vehicles", "VehiclesFolder", "Cars", "PlayerVehicles", "SpawnedVehicles", "SpawnedCars", "ActiveVehicles",
}
local TRAFFIC_FOLDER_NAMES = {
	"Traffic", "NPCTraffic", "NPC_Traffic", "AITraffic", "TrafficCars", "NPCVehicles", "ActiveTraffic", "TrafficFolder",
}

local function findWorkspaceFolders(names)
	local found = {}
	for _, name in ipairs(names) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(found, f)
		end
	end
	return found
end

local function isContainerFolder(inst)
	if not inst or inst == Workspace then return true end
	if inst:IsA("Folder") then return true end
	local l = inst.Name:lower()
	for _, name in ipairs(VEHICLE_FOLDER_NAMES) do
		if l == name:lower() then return true end
	end
	for _, name in ipairs(TRAFFIC_FOLDER_NAMES) do
		if l == name:lower() then return true end
	end
	return false
end

local function getSeatedVehicle()
	local char = LocalPlayer.Character
	if not char then
		return nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart or nil
	if not seat then
		return nil, nil
	end
	local cur = seat
	local bestModel = nil
	while cur and cur ~= Workspace do
		if cur:IsA("Model") and not isContainerFolder(cur) then
			bestModel = cur
		elseif isContainerFolder(cur) then
			break
		end
		cur = cur.Parent
	end
	return bestModel or seat.Parent, seat
end

local function getPlayerPos()
	local char = LocalPlayer.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
	return root and root.Position or nil
end

local function getVehicleKinematics(veh, seat)
	if not veh or not seat or not seat:IsA("BasePart") then
		return nil
	end
	local cf = seat.CFrame
	local look = cf.LookVector
	local up = cf.UpVector
	if up.Y < 0.3 then
		up = Vector3.new(0, 1, 0)
	end

	local pitchY = math.clamp(look.Y, -0.32, 0.32)
	local flatForward = Vector3.new(look.X, 0, look.Z)
	if flatForward.Magnitude < 0.01 then
		flatForward = Vector3.new(0, 0, -1)
	else
		flatForward = flatForward.Unit
	end
	local forward = Vector3.new(flatForward.X, pitchY, flatForward.Z).Unit
	local right = Vector3.new(-flatForward.Z, 0, flatForward.X)

	local vel = seat.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local forwardSpeed = flatVel:Dot(flatForward)
	local totalSpeed = flatVel.Magnitude
	local velDir = totalSpeed > 8 and Vector3.new(flatVel.Unit.X, pitchY, flatVel.Unit.Z).Unit or forward

	local frontOffset = 8.0
	local okBox, boxCF, boxSize = pcall(function()
		return veh:GetBoundingBox()
	end)
	if okBox and typeof(boxCF) == "CFrame" and typeof(boxSize) == "Vector3" then
		local halfLen = math.max(boxSize.Z, boxSize.X) * 0.5
		frontOffset = math.clamp(halfLen, 5.0, 15.0)
	end

	local bumperOrigin = seat.Position + forward * (frontOffset * 0.72) - up * 0.55
	local hoodOrigin = seat.Position + forward * (frontOffset * 0.65) + up * 0.85

	return {
		pos = seat.Position,
		bumperOrigin = bumperOrigin,
		hoodOrigin = hoodOrigin,
		sensorOrigin = hoodOrigin,
		forward = forward,
		flatForward = flatForward,
		right = right,
		up = up,
		velDir = velDir,
		forwardSpeed = forwardSpeed,
		totalSpeed = totalSpeed,
		frontOffset = frontOffset,
	}
end

local function getAChassisTelemetry()
	local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pgui then return nil end
	local iface = pgui:FindFirstChild("A-Chassis Interface")
	if not iface then return nil end
	local vals = iface:FindFirstChild("Values")
	if not vals then return nil end

	local function readNum(name)
		local v = vals:FindFirstChild(name)
		if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then
			return v.Value
		end
		return nil
	end
	local function readStr(name)
		local v = vals:FindFirstChild(name)
		if v and v:IsA("StringValue") then
			return v.Value
		end
		return nil
	end

	return {
		rpm = readNum("RPM"),
		gear = readNum("Gear"),
		throttle = readNum("Throttle"),
		brake = readNum("Brake"),
		transMode = readStr("TransmissionMode"),
	}
end

local CASH_STAT_NAMES = { "Cash", "Money", "Dollars", "Credits", "Coins", "Yen", "Bucks", "Balance" }

local function getCashValue()
	local containers = {
		LocalPlayer:FindFirstChild("leaderstats"),
		LocalPlayer:FindFirstChild("Stats"),
		LocalPlayer:FindFirstChild("Data"),
		LocalPlayer:FindFirstChild("PlayerData"),
	}
	for _, container in ipairs(containers) do
		if container then
			for _, statName in ipairs(CASH_STAT_NAMES) do
				local v = container:FindFirstChild(statName)
				if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then
					DetectedCashName = v.Name
					return v.Value
				end
			end
		end
	end
	-- Fallback: first numeric stat in leaderstats
	local ls = LocalPlayer:FindFirstChild("leaderstats")
	if ls then
		for _, child in ipairs(ls:GetChildren()) do
			if child:IsA("IntValue") or child:IsA("NumberValue") then
				DetectedCashName = child.Name
				return child.Value
			end
		end
	end
	return nil
end

local function formatNumber(n)
	local neg = n < 0
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local pos = #s % 3
	if pos == 0 then pos = 3 end
	local parts = { s:sub(1, pos) }
	for i = pos + 1, #s, 3 do
		table.insert(parts, s:sub(i, i + 2))
	end
	return (neg and "-" or "") .. table.concat(parts, ",")
end

--============================================================================--
--// 3D Sensor Raycast Engine (11-Ray Dense Fan + Spherecast + Traffic Aware)
--============================================================================--
local WHISKER_ANGLES = { -75, -55, -38, -24, -12, 0, 12, 24, 38, 55, 75 }
local CENTER_RAY_IDX = 6
local HAS_SPHERECAST = pcall(function()
	return type(Workspace.Spherecast) == "function"
end)

local function clearDebugRays()
	for i = #ActiveRayVisuals, 1, -1 do
		pcall(function()
			ActiveRayVisuals[i]:Destroy()
		end)
		ActiveRayVisuals[i] = nil
	end
	if DebugFolder then
		pcall(function()
			DebugFolder:Destroy()
		end)
		DebugFolder = nil
	end
end

local function ensureDebugFolder()
	if DebugFolder and DebugFolder.Parent then
		return DebugFolder
	end
	DebugFolder = Instance.new("Folder")
	DebugFolder.Name = "__AllainMCDebug"
	DebugFolder.Parent = Workspace
	return DebugFolder
end

local function setDebugRayPart(index, origin, targetPos, color)
	local folder = ensureDebugFolder()
	local part = ActiveRayVisuals[index]
	if not part or not part.Parent then
		part = Instance.new("Part")
		part.Name = "Ray_" .. tostring(index)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.Neon
		part.Transparency = 0.35
		part.Parent = folder
		ActiveRayVisuals[index] = part
	end
	local diff = targetPos - origin
	local dist = diff.Magnitude
	if dist < 0.1 then
		part.Transparency = 1
		return
	end
	part.Transparency = 0.35
	part.Color = color
	part.Size = Vector3.new(0.22, 0.22, dist)
	part.CFrame = CFrame.lookAt(origin + diff * 0.5, targetPos)
end

local function buildRaycastParams(veh)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	if LocalPlayer.Character then
		table.insert(ignore, LocalPlayer.Character)
	end
	if veh then
		table.insert(ignore, veh)
	end
	if DebugFolder then
		table.insert(ignore, DebugFolder)
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return params
end

local function isVehicleOrTrafficPart(inst, ownVeh)
	if not inst or not inst:IsA("BasePart") then
		return false
	end
	if ownVeh and inst:IsDescendantOf(ownVeh) then
		return false
	end
	-- Moving parts (traffic cars or other players' cars)
	if inst.AssemblyLinearVelocity.Magnitude > 6 then
		return true
	end
	-- Check known vehicle/traffic containers
	for _, folder in ipairs(findWorkspaceFolders(TRAFFIC_FOLDER_NAMES)) do
		if inst:IsDescendantOf(folder) then
			return true
		end
	end
	for _, folder in ipairs(findWorkspaceFolders(VEHICLE_FOLDER_NAMES)) do
		if inst:IsDescendantOf(folder) then
			return true
		end
	end
	return false
end

local function castObstacleRay(origin, dir, maxDist, params, useSphere)
	local traveled = 0
	local curOrigin = origin
	for _ = 1, 3 do
		local remaining = maxDist - traveled
		if remaining <= 1 then
			return maxDist, nil
		end
		local res
		if useSphere and HAS_SPHERECAST then
			res = Workspace:Spherecast(curOrigin, 1.05, dir * remaining, params)
		else
			res = Workspace:Raycast(curOrigin, dir * remaining, params)
		end
		if not res or not res.Instance then
			return maxDist, nil
		end
		local hit = res.Instance
		local isWall = hit.CanCollide and (res.Normal.Y < 0.62)
		if isWall then
			return traveled + res.Distance, hit
		end
		local step = res.Distance + 2.5
		traveled = traveled + step
		curOrigin = curOrigin + dir * step
	end
	return maxDist, nil
end

local function scanSensors(veh, kin, lookaheadMult)
	lookaheadMult = lookaheadMult or 1.0
	local speed = math.max(kin.forwardSpeed, 0)
	-- Highway lookahead: scales up to 440 studs for high-speed hypercars
	local centerRange = math.clamp((75 + speed * 2.35) * lookaheadMult, 75, 440)
	local params = buildRaycastParams(veh)
	local showDebug = Toggles.ShowSensorRays and Toggles.ShowSensorRays.Value

	local rays = {}
	local minForwardDist = math.huge
	local hitCarAhead = false

	for idx, deg in ipairs(WHISKER_ANGLES) do
		local rad = math.rad(deg)
		local dir = (kin.forward * math.cos(rad) + kin.right * math.sin(rad)).Unit
		local absDeg = math.abs(deg)
		local scale = (absDeg == 0) and 1.0
			or (absDeg <= 12 and 0.95
			or (absDeg <= 24 and 0.85
			or (absDeg <= 38 and 0.70
			or (absDeg <= 55 and 0.50 or 0.35))))
		local maxDist = centerRange * scale

		local useSphere = absDeg <= 24
		local distHood, hitHood = castObstacleRay(kin.hoodOrigin, dir, maxDist, params, useSphere)
		local dist = distHood
		local hitInst = hitHood

		if absDeg <= 38 then
			local distBumper, hitBumper = castObstacleRay(kin.bumperOrigin, dir, maxDist, params, false)
			if distBumper < dist then
				dist = distBumper
				hitInst = hitBumper
			end
		end

		local hitCar = (hitInst ~= nil) and isVehicleOrTrafficPart(hitInst, veh)
		local ratio = dist / maxDist
		rays[idx] = { deg = deg, dist = dist, maxDist = maxDist, ratio = ratio, hitCar = hitCar }

		if absDeg <= 12 and dist < minForwardDist then
			minForwardDist = dist
			if hitCar then
				hitCarAhead = true
			end
		end

		if showDebug then
			local col = hitCar and Color3.fromRGB(255, 130, 40)
				or (ratio > 0.65 and Color3.fromRGB(60, 230, 110)
				or (ratio > 0.32 and Color3.fromRGB(245, 200, 60) or Color3.fromRGB(240, 70, 70)))
			setDebugRayPart(idx, kin.bumperOrigin, kin.bumperOrigin + dir * dist, col)
		end
	end

	-- Velocity-vector ray
	local velDist, velHit = castObstacleRay(kin.bumperOrigin, kin.velDir, centerRange * 0.95, params, true)
	if velDist < minForwardDist then
		minForwardDist = velDist
		if velHit and isVehicleOrTrafficPart(velHit, veh) then
			hitCarAhead = true
		end
	end
	if showDebug then
		setDebugRayPart(12, kin.hoodOrigin, kin.hoodOrigin + kin.velDir * velDist, Color3.fromRGB(255, 110, 240))
	end

	-- Downward road-edge / cliff probes
	local edgeAhead = math.clamp(22 + speed * 0.45, 22, 85)
	local edgeSpread = 12
	local leftOrigin = kin.pos + kin.flatForward * edgeAhead - kin.right * edgeSpread + Vector3.new(0, 6, 0)
	local rightOrigin = kin.pos + kin.flatForward * edgeAhead + kin.right * edgeSpread + Vector3.new(0, 6, 0)
	local downVec = Vector3.new(0, -24, 0)

	local leftGround = Workspace:Raycast(leftOrigin, downVec, params)
	local rightGround = Workspace:Raycast(rightOrigin, downVec, params)
	local leftCliff = (not leftGround) or (leftGround.Distance > 13)
	local rightCliff = (not rightGround) or (rightGround.Distance > 13)

	if showDebug then
		setDebugRayPart(13, leftOrigin, leftGround and leftGround.Position or (leftOrigin + downVec),
			leftCliff and Color3.fromRGB(240, 70, 70) or Color3.fromRGB(80, 180, 255))
		setDebugRayPart(14, rightOrigin, rightGround and rightGround.Position or (rightOrigin + downVec),
			rightCliff and Color3.fromRGB(240, 70, 70) or Color3.fromRGB(80, 180, 255))
	else
		if #ActiveRayVisuals > 0 then
			clearDebugRays()
		end
	end

	return {
		rays = rays,
		centerDist = rays[CENTER_RAY_IDX].dist,
		centerRatio = rays[CENTER_RAY_IDX].ratio,
		velDist = velDist,
		minForwardDist = minForwardDist,
		hitCarAhead = hitCarAhead,
		leftCliff = leftCliff,
		rightCliff = rightCliff,
	}
end

--============================================================================--
--// Route Storage (Custom Highway Loop Auto-Drive)
--============================================================================--
local ROUTE_DIR = "AllainHub/routes/midnight-chasers"

local function listSavedRoutes()
	ensureFolders()
	if type(listfiles) ~= "function" then
		return {}
	end
	local ok, files = pcall(listfiles, ROUTE_DIR)
	if not ok or type(files) ~= "table" then
		return {}
	end
	local names = {}
	for _, f in ipairs(files) do
		local base = tostring(f):match("([^/\\]+)%.json$")
		if base then
			table.insert(names, base)
		end
	end
	table.sort(names)
	return names
end

local function saveRoute(name, points)
	if not name or name:match("^%s*$") then
		return false, "Enter a route name first."
	end
	if #points < 5 then
		return false, "Need at least 5 recorded waypoints."
	end
	if type(writefile) ~= "function" then
		return false, "writefile unavailable on this executor."
	end
	ensureFolders()
	local safeName = name:gsub("[^%w%-%_ ]", ""):gsub("%s+", "_")
	local path = ROUTE_DIR .. "/" .. safeName .. ".json"
	local ok, err = pcall(writefile, path, HttpService:JSONEncode(points))
	if not ok then
		return false, tostring(err)
	end
	return true, safeName
end

local function loadRoute(name)
	if not name or name == "" then
		return false, "Select a route first."
	end
	if type(readfile) ~= "function" then
		return false, "readfile unavailable on this executor."
	end
	local path = ROUTE_DIR .. "/" .. name .. ".json"
	local okRead, raw = pcall(readfile, path)
	if not okRead or type(raw) ~= "string" then
		return false, "Could not read " .. path
	end
	local okDec, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not okDec or type(data) ~= "table" or #data < 3 then
		return false, "Invalid route JSON."
	end
	LoadedRoutePoints = data
	LoadedRouteName = name
	RouteCursor = 1
	return true, string.format("Loaded %s (%d points)", name, #data)
end

local function findNearestRouteIndex(pos, points)
	local bestIdx = 1
	local bestDist = math.huge
	for i, pt in ipairs(points) do
		local dx = pt.x - pos.X
		local dz = pt.z - pos.Z
		local d = dx * dx + dz * dz
		if d < bestDist then
			bestDist = d
			bestIdx = i
		end
	end
	return bestIdx, math.sqrt(bestDist)
end

--============================================================================--
--// Whole-Map Highway Road Graph Builder & Path Follower
--============================================================================--
local ROAD_CELL_SIZE = 60
local ROAD_NAME_KEYWORDS = {
	"road", "asphalt", "highway", "street", "lane", "bridge", "ramp",
	"expressway", "track", "tarmac", "freeway", "wangan", "shutoko",
	"tunnel", "interchange", "overpass", "boulevard", "motorway", "deck",
}

local function nameLooksLikeRoad(str)
	if type(str) ~= "string" then return false end
	local l = str:lower()
	for _, kw in ipairs(ROAD_NAME_KEYWORDS) do
		if l:find(kw, 1, true) then
			return true
		end
	end
	return false
end

local function isRoadPart(part, ignoreFolders)
	if not part:IsA("BasePart") or not part.CanCollide then
		return false
	end
	if DebugFolder and part:IsDescendantOf(DebugFolder) then
		return false
	end
	for _, f in ipairs(ignoreFolders) do
		if part:IsDescendantOf(f) then
			return false
		end
	end
	if part.CFrame.UpVector.Y < 0.72 then
		return false
	end
	local sx, sy, sz = part.Size.X, part.Size.Y, part.Size.Z
	local maxH = math.max(sx, sz)
	local minH = math.min(sx, sz)
	if maxH < 12 or minH < 8 then
		return false
	end

	if nameLooksLikeRoad(part.Name) then
		return true
	end
	local p = part.Parent
	if p and nameLooksLikeRoad(p.Name) then
		return true
	end
	if part.Material == Enum.Material.Asphalt then
		return true
	end
	if part.Material == Enum.Material.Concrete and minH >= 14 and sy <= 6 then
		return true
	end
	return false
end

local function addRoadNodeDedup(pos)
	local cx = math.floor(pos.X / ROAD_CELL_SIZE)
	local cz = math.floor(pos.Z / ROAD_CELL_SIZE)
	for dx = -1, 1 do
		for dz = -1, 1 do
			local bucket = MapRoadGrid[string.format("%d,%d", cx + dx, cz + dz)]
			if bucket then
				for _, idx in ipairs(bucket) do
					local other = MapRoadNodes[idx].pos
					local ddx = other.X - pos.X
					local ddz = other.Z - pos.Z
					if (ddx * ddx + ddz * ddz) < (16 * 16) and math.abs(other.Y - pos.Y) < 8 then
						return nil
					end
				end
			end
		end
	end

	local idx = #MapRoadNodes + 1
	MapRoadNodes[idx] = { pos = pos, neighbors = {} }
	local key = string.format("%d,%d", cx, cz)
	local bucket = MapRoadGrid[key]
	if not bucket then
		bucket = {}
		MapRoadGrid[key] = bucket
	end
	table.insert(bucket, idx)
	return idx
end

local function buildMapRoadGraph(notifyUser)
	if MapRoadBuilding then return end
	MapRoadBuilding = true
	MapRoadNodes = {}
	MapRoadGrid = {}
	RecentRoadNodes = {}
	RecentRoadSet = {}
	LastRoadNodeIdx = nil

	local t0 = os.clock()
	local ignoreFolders = findWorkspaceFolders(VEHICLE_FOLDER_NAMES)
	for _, tf in ipairs(findWorkspaceFolders(TRAFFIC_FOLDER_NAMES)) do
		table.insert(ignoreFolders, tf)
	end

	local partsScanned = 0
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if isRoadPart(desc, ignoreFolders) then
			partsScanned = partsScanned + 1
			local cf = desc.CFrame
			local sx, sy, sz = desc.Size.X, desc.Size.Y, desc.Size.Z
			local topOffset = cf.UpVector * (sy * 0.5 + 0.6)

			local axisVec, length
			if sx >= sz then
				axisVec = cf.RightVector
				length = sx
			else
				axisVec = cf.LookVector
				length = sz
			end

			local steps = math.max(1, math.floor(length / 28))
			if steps == 1 then
				addRoadNodeDedup(cf.Position + topOffset)
			else
				local startOffset = -length * 0.5 + (length / (steps * 2))
				local stepLen = length / steps
				for s = 0, steps - 1 do
					local samplePos = cf.Position + axisVec * (startOffset + s * stepLen) + topOffset
					addRoadNodeDedup(samplePos)
				end
			end
		end
	end

	local maxLinkSq = 64 * 64
	for i, node in ipairs(MapRoadNodes) do
		local p = node.pos
		local cx = math.floor(p.X / ROAD_CELL_SIZE)
		local cz = math.floor(p.Z / ROAD_CELL_SIZE)
		local cands = {}
		for dx = -1, 1 do
			for dz = -1, 1 do
				local bucket = MapRoadGrid[string.format("%d,%d", cx + dx, cz + dz)]
				if bucket then
					for _, j in ipairs(bucket) do
						if j ~= i then
							local q = MapRoadNodes[j].pos
							local ddx = q.X - p.X
							local ddz = q.Z - p.Z
							local dSq = ddx * ddx + ddz * ddz
							if dSq <= maxLinkSq and dSq >= 4 and math.abs(q.Y - p.Y) < 12 then
								table.insert(cands, { idx = j, dSq = dSq })
							end
						end
					end
				end
			end
		end
		table.sort(cands, function(a, b) return a.dSq < b.dSq end)
		for k = 1, math.min(#cands, 6) do
			table.insert(node.neighbors, cands[k].idx)
		end
	end

	MapRoadBuilt = true
	MapRoadBuilding = false
	local elapsed = os.clock() - t0
	local msg = string.format("Road Graph: %d nodes (%d road parts) in %.2fs", #MapRoadNodes, partsScanned, elapsed)
	if Library.Labels and Library.Labels.RoadGraphStatus then
		Library.Labels.RoadGraphStatus:SetText(msg)
	end
	if notifyUser then
		Library:Notify({ Title = "Highway Roads Scanned", Description = msg, Time = 4 })
	end
end

local function findNearestRoadNode(pos, preferDir)
	if #MapRoadNodes == 0 then return nil, math.huge end
	local cx = math.floor(pos.X / ROAD_CELL_SIZE)
	local cz = math.floor(pos.Z / ROAD_CELL_SIZE)
	local bestIdx = nil
	local bestScore = math.huge

	for radius = 1, 2 do
		for dx = -radius, radius do
			for dz = -radius, radius do
				local bucket = MapRoadGrid[string.format("%d,%d", cx + dx, cz + dz)]
				if bucket then
					for _, idx in ipairs(bucket) do
						local p = MapRoadNodes[idx].pos
						if math.abs(p.Y - pos.Y) < 16 then
							local ddx = p.X - pos.X
							local ddz = p.Z - pos.Z
							local dist = math.sqrt(ddx * ddx + ddz * ddz)
							if dist < 120 then
								local score = dist
								if preferDir and dist > 4 then
									local dot = (ddx * preferDir.X + ddz * preferDir.Z) / dist
									if dot < -0.2 then
										score = score + 22
									end
								end
								if score < bestScore then
									bestScore = score
									bestIdx = idx
								end
							end
						end
					end
				end
			end
		end
		if bestIdx then break end
	end
	return bestIdx, bestScore
end

local function markRoadNodeVisited(idx)
	if not idx or idx == LastRoadNodeIdx then return end
	LastRoadNodeIdx = idx
	if not RecentRoadSet[idx] then
		RecentRoadSet[idx] = true
		table.insert(RecentRoadNodes, idx)
		if #RecentRoadNodes > 28 then
			local oldest = table.remove(RecentRoadNodes, 1)
			RecentRoadSet[oldest] = nil
		end
	end
end

local function computeMapRoadGuidance(kin, speed, lookaheadMult)
	if not MapRoadBuilt and not MapRoadBuilding then
		buildMapRoadGraph(false)
	end
	if #MapRoadNodes == 0 then
		return nil, 0, false
	end

	local startIdx = findNearestRoadNode(kin.pos, kin.flatForward)
	if not startIdx then
		return nil, 0, false
	end
	markRoadNodeVisited(startIdx)

	local chain = { startIdx }
	local inChain = { [startIdx] = true }
	local curIdx = startIdx
	local curDir = kin.flatForward

	for _ = 1, 12 do
		local node = MapRoadNodes[curIdx]
		local bestNext = nil
		local bestScore = -math.huge

		for _, nIdx in ipairs(node.neighbors) do
			if not inChain[nIdx] then
				local step = MapRoadNodes[nIdx].pos - node.pos
				local flatStep = Vector3.new(step.X, 0, step.Z)
				local len = flatStep.Magnitude
				if len > 2 then
					local dir = flatStep / len
					local dot = curDir:Dot(dir)
					if dot > 0.12 then
						local score = dot * 100
						if RecentRoadSet[nIdx] then
							score = score - 45
						end
						if #MapRoadNodes[nIdx].neighbors >= 2 then
							score = score + 12
						end
						if score > bestScore then
							bestScore = score
							bestNext = nIdx
						end
					end
				end
			end
		end

		if not bestNext then break end
		local step = MapRoadNodes[bestNext].pos - node.pos
		local flatStep = Vector3.new(step.X, 0, step.Z)
		if flatStep.Magnitude > 1 then
			curDir = flatStep.Unit
		end
		table.insert(chain, bestNext)
		inChain[bestNext] = true
		curIdx = bestNext
	end

	if #chain < 2 then
		return nil, 0, false
	end

	local showDebug = Toggles.ShowSensorRays and Toggles.ShowSensorRays.Value
	if showDebug then
		for k = 1, 11 do
			local segIdx = 20 + k
			if k < #chain then
				local pA = MapRoadNodes[chain[k]].pos + Vector3.new(0, 1.2, 0)
				local pB = MapRoadNodes[chain[k + 1]].pos + Vector3.new(0, 1.2, 0)
				setDebugRayPart(segIdx, pA, pB, Color3.fromRGB(0, 235, 255))
			elseif ActiveRayVisuals[segIdx] then
				ActiveRayVisuals[segIdx].Transparency = 1
			end
		end
	end

	local lookaheadDist = math.clamp((32 + math.max(speed, 0) * 0.52) * (lookaheadMult or 1.0), 28, 150)
	local walked = 0
	local aimPos = MapRoadNodes[chain[#chain]].pos
	for k = 1, #chain - 1 do
		local pA = MapRoadNodes[chain[k]].pos
		local pB = MapRoadNodes[chain[k + 1]].pos
		local seg = (Vector3.new(pB.X, 0, pB.Z) - Vector3.new(pA.X, 0, pA.Z)).Magnitude
		if walked + seg >= lookaheadDist then
			local t = (lookaheadDist - walked) / math.max(seg, 0.1)
			aimPos = pA:Lerp(pB, math.clamp(t, 0, 1))
			break
		end
		walked = walked + seg
	end

	local toAim = Vector3.new(aimPos.X - kin.pos.X, 0, aimPos.Z - kin.pos.Z)
	if toAim.Magnitude < 1 then
		return 0, 0, true
	end
	toAim = toAim.Unit
	local cross = kin.flatForward.X * toAim.Z - kin.flatForward.Z * toAim.X
	local dot = math.clamp(kin.flatForward:Dot(toAim), -1, 1)
	local angleErr = math.atan2(cross, dot)
	local roadSteer = math.clamp(angleErr * 1.55, -1, 1)

	local upcomingBend = 0
	if #chain >= 4 then
		local p0 = MapRoadNodes[chain[1]].pos
		local p1 = MapRoadNodes[chain[2]].pos
		local vNear = Vector3.new(p1.X - p0.X, 0, p1.Z - p0.Z)
		if vNear.Magnitude > 1 then
			vNear = vNear.Unit
			for k = 3, math.min(#chain - 1, 8) do
				local a = MapRoadNodes[chain[k]].pos
				local b = MapRoadNodes[chain[k + 1]].pos
				local vFar = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
				if vFar.Magnitude > 1 then
					local bend = math.acos(math.clamp(vNear:Dot(vFar.Unit), -1, 1))
					if bend > upcomingBend then
						upcomingBend = bend
					end
				end
			end
		end
	end

	return roadSteer, upcomingBend, true
end

--============================================================================--
--// Driving Controllers (Highway Cut-Up Weaving + Physics Braking + Assist)
--============================================================================--
local function computeObstacleAvoidance(sensors, aggressiveWeave)
	local r = sensors.rays
	local n = #r

	local bestAngle = 0
	local bestScore = -math.huge
	local leftTotal, rightTotal = 0, 0

	for i = 1, n do
		local prevD = r[math.max(1, i - 1)].dist
		local curD = r[i].dist
		local nextD = r[math.min(n, i + 1)].dist
		local corridorDist = aggressiveWeave
			and (curD * 0.62 + math.min(prevD, curD) * 0.19 + math.min(nextD, curD) * 0.19)
			or (curD * 0.50 + math.min(prevD, curD) * 0.25 + math.min(nextD, curD) * 0.25)
		local deg = r[i].deg

		local forwardBias = 1.0 - (math.abs(deg) / (aggressiveWeave and 125 or 145))
		local score = corridorDist * forwardBias

		if deg < 0 then
			leftTotal = leftTotal + curD
			if sensors.leftCliff then score = score * 0.35 end
		elseif deg > 0 then
			rightTotal = rightTotal + curD
			if sensors.rightCliff then score = score * 0.35 end
		end

		if r[i].hitCar then
			score = score * (aggressiveWeave and 0.35 or 0.45)
		end

		if score > bestScore then
			bestScore = score
			bestAngle = deg
		end
	end

	local steer = math.clamp(bestAngle / (aggressiveWeave and 28 or 34), -1, 1)

	-- Side wall-repulsion
	local closeLeft = math.min(r[1].dist, r[2].dist, r[3].dist)
	local closeRight = math.min(r[n].dist, r[n - 1].dist, r[n - 2].dist)
	local sideMargin = aggressiveWeave and 14 or 18
	if closeLeft < sideMargin then
		steer = steer + ((sideMargin - closeLeft) / sideMargin) * 0.70
	end
	if closeRight < sideMargin then
		steer = steer - ((sideMargin - closeRight) / sideMargin) * 0.70
	end

	if sensors.leftCliff and not sensors.rightCliff then
		steer = steer + 0.55
	elseif sensors.rightCliff and not sensors.leftCliff then
		steer = steer - 0.55
	end

	return math.clamp(steer, -1, 1), leftTotal, rightTotal, bestAngle
end

local function computeStoppingDistance(speed)
	local s = math.max(speed, 0)
	return (s * s) / 85 + 18
end

local function stepAutoDrive(veh, kin, dt)
	local mode = Options.AutoDriveMode and Options.AutoDriveMode.Value or "Highway Road Path"
	local targetSpeed = Options.TargetSpeed and Options.TargetSpeed.Value or 140
	local lookaheadMult = Options.LookaheadMult and Options.LookaheadMult.Value or 1.0
	local steerSens = Options.SteerSensitivity and Options.SteerSensitivity.Value or 1.0
	local stuckEnabled = Toggles.StuckRecovery and Toggles.StuckRecovery.Value
	local autoNitro = Toggles.AutoNitro and Toggles.AutoNitro.Value
	local isCutUp = (mode == "Highway Cut-Up (Weave)")

	local sensors = scanSensors(veh, kin, lookaheadMult)
	local now = os.clock()

	if now < ReverseUntil then
		applyDrivingInputs(0, 1.0, ReverseSteerDir, dt, false)
		if Library.Labels.DriveStatus then
			Library.Labels.DriveStatus:SetText("Status: reversing (recovery)")
		end
		return
	end

	local avoidSteer, leftTotal, rightTotal, bestAngle = computeObstacleAvoidance(sensors, isCutUp)
	local desiredSteer = avoidSteer
	local desiredSpeed = targetSpeed
	local usingRoadPath = false

	if mode == "Highway Road Path" or isCutUp then
		local roadSteer, upcomingBend, found = computeMapRoadGuidance(kin, kin.forwardSpeed, lookaheadMult)
		if found and roadSteer then
			usingRoadPath = true
			local obsWeight = 0
			local weaveTrigger = isCutUp and 75 or 42
			if sensors.minForwardDist < weaveTrigger or sensors.hitCarAhead then
				obsWeight = math.clamp((weaveTrigger - sensors.minForwardDist) / math.max(weaveTrigger * 0.65, 20), 0.30, 0.92)
				if sensors.hitCarAhead then
					obsWeight = math.max(obsWeight, isCutUp and 0.85 or 0.65)
				end
			end
			desiredSteer = roadSteer * (1 - obsWeight) + avoidSteer * obsWeight

			if upcomingBend > 0.28 then
				local bendSlow = math.clamp(1.0 - (upcomingBend / 1.65) * 0.65, 0.35, 0.90)
				desiredSpeed = math.min(desiredSpeed, math.max(40, targetSpeed * bendSlow))
			end
		end
	elseif mode == "Saved Route Loop" and #LoadedRoutePoints >= 5 then
		local n = #LoadedRoutePoints
		local curPt = LoadedRoutePoints[RouteCursor]
		local curDist = (Vector3.new(curPt.x, kin.pos.Y, curPt.z) - kin.pos).Magnitude
		if curDist > 180 then
			RouteCursor = findNearestRouteIndex(kin.pos, LoadedRoutePoints)
		end

		local lookaheadDist = math.clamp(30 + math.max(kin.forwardSpeed, 0) * 0.55, 30, 130)
		local targetIdx = RouteCursor
		local walked = 0
		for _ = 1, 40 do
			local pA = LoadedRoutePoints[targetIdx]
			local nextIdx = (targetIdx % n) + 1
			local pB = LoadedRoutePoints[nextIdx]
			walked = walked + math.sqrt((pB.x - pA.x) ^ 2 + (pB.z - pA.z) ^ 2)
			targetIdx = nextIdx
			if walked >= lookaheadDist then
				break
			end
		end
		if math.sqrt((curPt.x - kin.pos.X) ^ 2 + (curPt.z - kin.pos.Z) ^ 2) < 30 then
			RouteCursor = (RouteCursor % n) + 1
		end

		local aimPt = LoadedRoutePoints[targetIdx]
		local toAim = Vector3.new(aimPt.x - kin.pos.X, 0, aimPt.z - kin.pos.Z)
		if toAim.Magnitude > 1 then
			toAim = toAim.Unit
			local angleErr = math.atan2(
				kin.flatForward.X * toAim.Z - kin.flatForward.Z * toAim.X,
				math.clamp(kin.flatForward:Dot(toAim), -1, 1)
			)
			local routeSteer = math.clamp(angleErr * 1.45, -1, 1)
			local stopDist = computeStoppingDistance(kin.forwardSpeed)
			local obstacleWeight = 0
			if sensors.minForwardDist < stopDist * 1.25 or sensors.hitCarAhead or sensors.leftCliff or sensors.rightCliff then
				obstacleWeight = math.clamp(1.0 - (sensors.minForwardDist / math.max(stopDist * 1.25, 22)), 0.35, 0.90)
			end
			desiredSteer = routeSteer * (1 - obstacleWeight) + avoidSteer * obstacleWeight
			if math.abs(angleErr) > 0.35 then
				desiredSpeed = math.min(desiredSpeed, targetSpeed * math.clamp(1 - math.abs(angleErr) * 0.55, 0.40, 0.85))
			end
		end
	end

	desiredSteer = math.clamp(desiredSteer * steerSens, -1, 1)
	SmoothedSteer = SmoothedSteer + (desiredSteer - SmoothedSteer) * math.min(dt * 14, 1)

	local speed = kin.forwardSpeed
	local stopDist = computeStoppingDistance(speed)
	local fwdDist = sensors.minForwardDist

	local turnRatio = math.max(math.abs(SmoothedSteer), math.abs(bestAngle) / 75)
	if turnRatio > 0.28 then
		local cornerCap = math.max(40, targetSpeed * (1.0 - turnRatio * (isCutUp and 0.48 or 0.60)))
		desiredSpeed = math.min(desiredSpeed, cornerCap)
	end

	local throttle, brake = 0, 0
	if fwdDist < 16 then
		desiredSpeed = 0
		brake = 1.0
	elseif fwdDist < stopDist * (isCutUp and 0.78 or 0.95) then
		desiredSpeed = 0
		brake = 1.0
	elseif fwdDist < stopDist * 1.50 then
		local f = (fwdDist - stopDist * 0.85) / math.max(stopDist * 0.65, 10)
		desiredSpeed = math.min(desiredSpeed, math.max(30, targetSpeed * f))
	end

	if sensors.hitCarAhead and not isCutUp and fwdDist < stopDist * 1.35 then
		desiredSpeed = math.min(desiredSpeed, 30)
	end

	if brake == 0 then
		if speed < desiredSpeed - 3 then
			throttle = math.clamp((desiredSpeed - speed) / 22, 0.32, 1.0)
		elseif speed > desiredSpeed + 8 then
			brake = math.clamp((speed - desiredSpeed) / 30, 0.35, 1.0)
		end
	end

	if stuckEnabled then
		local wedgedClose = (fwdDist < 14 and speed < 10)
		local stalled = (throttle > 0.2 and math.abs(kin.totalSpeed) < 4)
		if wedgedClose or stalled then
			StuckTimer = StuckTimer + dt * (wedgedClose and 2.5 or 1.0)
			if StuckTimer >= 1.6 then
				StuckTimer = 0
				ReverseUntil = now + 1.75
				ReverseSteerDir = (leftTotal >= rightTotal) and 1 or -1
				return
			end
		else
			StuckTimer = math.max(0, StuckTimer - dt * 2.5)
		end
	end

	local useNitro = autoNitro and throttle > 0.75 and fwdDist > stopDist * 1.8 and math.abs(SmoothedSteer) < 0.25
	applyDrivingInputs(throttle, brake, SmoothedSteer, dt, useNitro)

	if Library.Labels.DriveStatus then
		local modeTag = mode == "Saved Route Loop" and ("Loop: " .. LoadedRouteName)
			or (isCutUp and "Cut-Up" or (usingRoadPath and "Highway" or "Sensors"))
		Library.Labels.DriveStatus:SetText(string.format(
			"Status: %s | %.0f/%.0f st/s | Ahead %.0fst | Steer %.2f",
			modeTag,
			speed,
			desiredSpeed,
			fwdDist,
			SmoothedSteer
		))
	end
end

local function stepCashFarm(veh, kin, dt)
	local farmMode = Options.CashFarmMode and Options.CashFarmMode.Value or "Highway Cut-Up (Fast)"
	local farmSpeed = Options.CashFarmSpeed and Options.CashFarmSpeed.Value or 145
	local lookaheadMult = Options.LookaheadMult and Options.LookaheadMult.Value or 1.0
	local watchdogOn = Toggles.CashStallWatchdog and Toggles.CashStallWatchdog.Value
	local isCutUp = (farmMode == "Highway Cut-Up (Fast)")

	local sensors = scanSensors(veh, kin, lookaheadMult)
	local now = os.clock()

	if now < ReverseUntil then
		applyDrivingInputs(0, 1.0, ReverseSteerDir, dt, false)
		if Library.Labels.FarmStatusLabel then
			Library.Labels.FarmStatusLabel:SetText("Farm: reversing (recovery)")
		end
		return
	end

	local avoidSteer, leftTotal, rightTotal, bestAngle = computeObstacleAvoidance(sensors, isCutUp)
	local speed = kin.forwardSpeed
	local stopDist = computeStoppingDistance(speed)
	local fwdDist = sensors.minForwardDist
	local desiredSteer = avoidSteer
	local desiredSpeed = farmSpeed

	if farmMode == "Highway Cruise (Safe)" or isCutUp then
		local roadSteer, upcomingBend, found = computeMapRoadGuidance(kin, speed, lookaheadMult)
		if found and roadSteer then
			local weaveTrigger = isCutUp and 75 or 42
			local obsW = 0
			if fwdDist < weaveTrigger or sensors.hitCarAhead then
				obsW = isCutUp and 0.85 or 0.70
			end
			desiredSteer = roadSteer * (1 - obsW) + avoidSteer * obsW
			if upcomingBend > 0.35 then
				desiredSpeed = math.min(desiredSpeed, math.max(45, farmSpeed * 0.72))
			end
		end
	elseif farmMode == "Saved Route Loop" and #LoadedRoutePoints >= 5 then
		local n = #LoadedRoutePoints
		local curPt = LoadedRoutePoints[RouteCursor]
		local curDist = (Vector3.new(curPt.x, kin.pos.Y, curPt.z) - kin.pos).Magnitude
		if curDist > 180 then
			RouteCursor = findNearestRouteIndex(kin.pos, LoadedRoutePoints)
		end
		local lookaheadDist = math.clamp(28 + math.max(speed, 0) * 0.5, 28, 120)
		local targetIdx = RouteCursor
		local walked = 0
		for _ = 1, 35 do
			local pA = LoadedRoutePoints[targetIdx]
			local nextIdx = (targetIdx % n) + 1
			local pB = LoadedRoutePoints[nextIdx]
			walked = walked + math.sqrt((pB.x - pA.x) ^ 2 + (pB.z - pA.z) ^ 2)
			targetIdx = nextIdx
			if walked >= lookaheadDist then break end
		end
		if math.sqrt((curPt.x - kin.pos.X) ^ 2 + (curPt.z - kin.pos.Z) ^ 2) < 30 then
			RouteCursor = (RouteCursor % n) + 1
		end
		local aimPt = LoadedRoutePoints[targetIdx]
		local toAim = Vector3.new(aimPt.x - kin.pos.X, 0, aimPt.z - kin.pos.Z)
		if toAim.Magnitude > 1 then
			toAim = toAim.Unit
			local angleErr = math.atan2(
				kin.flatForward.X * toAim.Z - kin.flatForward.Z * toAim.X,
				math.clamp(kin.flatForward:Dot(toAim), -1, 1)
			)
			local routeSteer = math.clamp(angleErr * 1.45, -1, 1)
			local obsW = (fwdDist < stopDist * 1.25 or sensors.hitCarAhead or sensors.leftCliff or sensors.rightCliff) and 0.80 or 0.15
			desiredSteer = routeSteer * (1 - obsW) + avoidSteer * obsW
		end
	end

	SmoothedSteer = SmoothedSteer + (math.clamp(desiredSteer, -1, 1) - SmoothedSteer) * math.min(dt * 14, 1)

	local turnRatio = math.max(math.abs(SmoothedSteer), math.abs(bestAngle) / 75)
	if turnRatio > 0.30 then
		desiredSpeed = math.min(desiredSpeed, math.max(40, farmSpeed * (1.0 - turnRatio * 0.45)))
	end

	local throttle, brake = 0, 0
	if fwdDist < 15 or fwdDist < stopDist * (isCutUp and 0.78 or 0.90) then
		desiredSpeed = 0
		brake = 1.0
	elseif fwdDist < stopDist * 1.40 then
		local f = (fwdDist - stopDist * 0.85) / math.max(stopDist * 0.55, 8)
		desiredSpeed = math.min(desiredSpeed, math.max(30, farmSpeed * f))
	end

	if brake == 0 then
		if speed < desiredSpeed - 3 then
			throttle = math.clamp((desiredSpeed - speed) / 20, 0.35, 1.0)
		elseif speed > desiredSpeed + 8 then
			brake = math.clamp((speed - desiredSpeed) / 28, 0.35, 1.0)
		end
	end

	local cashStalled = watchdogOn and (StartCash ~= nil) and (now - LastCashTickTime >= 12.0)
	local wedgedClose = (fwdDist < 14 and speed < 10)
	local stalled = (throttle > 0.2 and math.abs(kin.totalSpeed) < 5)
	if wedgedClose or stalled or cashStalled then
		StuckTimer = StuckTimer + dt * ((wedgedClose or cashStalled) and 2.5 or 1.0)
		if StuckTimer >= 1.6 then
			StuckTimer = 0
			LastCashTickTime = now
			ReverseUntil = now + 1.8
			ReverseSteerDir = (leftTotal >= rightTotal) and 1 or -1
			return
		end
	else
		StuckTimer = math.max(0, StuckTimer - dt * 2.5)
	end

	local useNitro = (Toggles.AutoNitro and Toggles.AutoNitro.Value) and throttle > 0.75 and fwdDist > stopDist * 1.8 and math.abs(SmoothedSteer) < 0.25
	applyDrivingInputs(throttle, brake, SmoothedSteer, dt, useNitro)

	if Library.Labels.FarmStatusLabel then
		Library.Labels.FarmStatusLabel:SetText(string.format(
			"Farm: %s | %.0f st/s | Last tick +$%s",
			farmMode,
			speed,
			formatNumber(LastCashTickAmount)
		))
	end
end

local function stepCollisionPrevention(veh, kin, dt)
	local minSpeed = Options.ColMinSpeed and Options.ColMinSpeed.Value or 35
	local ttcThreshold = Options.ColTTC and Options.ColTTC.Value or 0.9
	local colMode = Options.ColMode and Options.ColMode.Value or "Both (Brake + Steer)"

	local sensors = scanSensors(veh, kin, 1.0)
	local speed = kin.forwardSpeed
	if speed < minSpeed then
		releaseAllDrivingKeys()
		if Library.Labels.AssistStatus then
			Library.Labels.AssistStatus:SetText("Assist: standby (below min speed)")
		end
		return false
	end

	local stopDist = computeStoppingDistance(speed)
	local fwdDist = sensors.minForwardDist
	local ttc = fwdDist / math.max(speed, 1)
	local closeSideHazard = sensors.leftCliff or sensors.rightCliff
		or sensors.rays[2].dist < 11 or sensors.rays[10].dist < 11

	local dangerAhead = (ttc <= ttcThreshold) or (fwdDist <= stopDist * 0.90)
	if dangerAhead or closeSideHazard then
		local avoidSteer = computeObstacleAvoidance(sensors, true)
		local doBrake = (colMode == "Brake Only" or colMode == "Both (Brake + Steer)") and dangerAhead
		local doSteer = (colMode == "Steer Only" or colMode == "Both (Brake + Steer)")

		applyDrivingInputs(0, doBrake and 1.0 or 0, doSteer and avoidSteer or 0, dt, false)
		if Library.Labels.AssistStatus then
			Library.Labels.AssistStatus:SetText(string.format(
				"Assist: INTERVENING! TTC=%.2fs | Ahead %.0fst",
				ttc,
				fwdDist
			))
		end
		return true
	end

	releaseAllDrivingKeys()
	if Library.Labels.AssistStatus then
		Library.Labels.AssistStatus:SetText(string.format("Assist: clear (ahead %.0f st)", fwdDist))
	end
	return false
end

local function stepCruiseControl(kin, dt)
	if UserInputService:IsKeyDown(ControlKeys.Brake) then
		setKey(ControlKeys.Throttle, false)
		return
	end
	local target = Options.CruiseSpeed and Options.CruiseSpeed.Value or 140
	local speed = kin.forwardSpeed
	if speed < target - 2 then
		local thr = math.clamp((target - speed) / 22, 0.25, 1)
		PwmPhase = (PwmPhase + dt * 10) % 1
		setKey(ControlKeys.Throttle, thr >= 0.85 or PwmPhase < thr)
	else
		setKey(ControlKeys.Throttle, false)
	end
end

local function stepAutoShift()
	local tele = getAChassisTelemetry()
	if not tele or not tele.rpm or not tele.gear then
		return
	end
	if tele.transMode and tele.transMode:lower():find("auto", 1, true) then
		return
	end
	local now = os.clock()
	if now - LastShiftTime < 0.45 then
		return
	end
	local upRpm = Options.ShiftUpRPM and Options.ShiftUpRPM.Value or 7200
	local downRpm = Options.ShiftDownRPM and Options.ShiftDownRPM.Value or 3200
	if tele.gear >= 1 and tele.rpm >= upRpm then
		LastShiftTime = now
		tapKey(ControlKeys.ShiftUp, 0.05)
	elseif tele.gear > 1 and tele.rpm > 500 and tele.rpm <= downRpm then
		LastShiftTime = now
		tapKey(ControlKeys.ShiftDown, 0.05)
	end
end

--============================================================================--
--// Traffic & Player Car ESP + Performance Helpers
--============================================================================--
local function clearEspTable(tbl)
	for i = #tbl, 1, -1 do
		pcall(function()
			tbl[i]:Destroy()
		end)
		tbl[i] = nil
	end
end

local function makeBillboard(adornee, text, color, maxDist)
	local bb = Instance.new("BillboardGui")
	bb.Name = "__AllainMCEsp"
	bb.Adornee = adornee
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(170, 32)
	bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.MaxDistance = maxDist or 3000

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 0.35
	lbl.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.4
	lbl.Font = Enum.Font.GothamSemibold
	lbl.TextSize = 12
	lbl.Text = text
	lbl.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = lbl

	bb.Parent = Workspace
	return bb, lbl
end

local function findPrimaryBasePart(model)
	if not model then return nil end
	if model:IsA("BasePart") then return model end
	if model:IsA("Model") then
		if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
			return model.PrimaryPart
		end
		local seat = model:FindFirstChild("DriveSeat", true) or model:FindFirstChildOfClass("VehicleSeat")
		if seat and seat:IsA("BasePart") then
			return seat
		end
		return model:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function refreshTrafficEsp()
	clearEspTable(TrafficEspObjects)
	if not (Toggles.TrafficEsp and Toggles.TrafficEsp.Value) then
		return
	end
	local pPos = getPlayerPos()
	local maxRange = Options.TrafficEspRange and Options.TrafficEspRange.Value or 600
	local ownVeh = getSeatedVehicle()
	local count = 0

	for _, folder in ipairs(findWorkspaceFolders(TRAFFIC_FOLDER_NAMES)) do
		for _, car in ipairs(folder:GetChildren()) do
			if count >= 40 then break end
			if car ~= ownVeh then
				local part = findPrimaryBasePart(car)
				if part and (not pPos or (part.Position - pPos).Magnitude <= maxRange) then
					local bb = makeBillboard(part, "Traffic", Color3.fromRGB(255, 195, 75), maxRange + 150)
					bb:SetAttribute("BaseName", "Traffic")
					table.insert(TrafficEspObjects, bb)
					count = count + 1
				end
			end
		end
	end
end

local function refreshCarEsp()
	clearEspTable(CarEspObjects)
	if not (Toggles.CarEsp and Toggles.CarEsp.Value) then
		return
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and plr.Character then
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			local root = (hum and hum.SeatPart) or plr.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local label = plr.DisplayName ~= plr.Name and (plr.DisplayName .. " (@" .. plr.Name .. ")") or plr.Name
				local bb = makeBillboard(root, label, Color3.fromRGB(110, 210, 255), 8000)
				bb:SetAttribute("BaseName", plr.Name)
				table.insert(CarEspObjects, bb)
			end
		end
	end
end

local function setFpsBoost(enabled)
	if enabled then
		if not SavedLighting then
			SavedLighting = {
				GlobalShadows = Lighting.GlobalShadows,
				FogEnd = Lighting.FogEnd,
			}
		end
		pcall(function()
			Lighting.GlobalShadows = false
			Lighting.FogEnd = 1e6
		end)
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
				pcall(function() d.Enabled = false end)
			end
		end
	else
		if SavedLighting then
			pcall(function()
				Lighting.GlobalShadows = SavedLighting.GlobalShadows
				Lighting.FogEnd = SavedLighting.FogEnd
			end)
			SavedLighting = nil
		end
	end
end

local function setLowPower(enabled)
	LowPowerActive = enabled
	pcall(function()
		RunService:Set3dRenderingEnabled(not enabled)
	end)
	if enabled and type(setfpscap) == "function" then
		local cap = Options.LowPowerFpsCap and Options.LowPowerFpsCap.Value or 20
		pcall(setfpscap, cap)
	elseif not enabled and type(setfpscap) == "function" then
		pcall(setfpscap, 0)
	end
end

--============================================================================--
--// Webhook & Read-Only Game Data Scanner Helpers
--============================================================================--
local function sendWebhookText(webhookUrl, message)
	if type(webhookUrl) ~= "string" or webhookUrl:match("^%s*$") then
		return false, "Webhook URL is empty"
	end
	local req = getRequestFunc()
	if not req then
		return false, "HTTP request function unavailable"
	end
	local ok, res = pcall(req, {
		Url = webhookUrl,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = HttpService:JSONEncode({ content = message }),
	})
	if not ok then return false, tostring(res) end
	local status = type(res) == "table" and (res.StatusCode or res.Status) or nil
	if status and (status < 200 or status >= 300) then
		return false, "HTTP " .. tostring(status)
	end
	return true, "Sent"
end

local function sendReportToWebhook(webhookUrl, filename, content, summaryText)
	if type(webhookUrl) ~= "string" or webhookUrl:match("^%s*$") then
		return false, "Webhook URL is empty"
	end
	local req = getRequestFunc()
	if not req then
		return false, "Executor HTTP request function not available"
	end
	local boundary = "----AllainMCBoundary" .. tostring(math.random(100000, 999999))
	local payloadJson = HttpService:JSONEncode({
		content = summaryText or ("Midnight Chasers scan (`" .. filename .. "`)"),
	})
	local bodyParts = {
		"--" .. boundary .. "\r\n",
		'Content-Disposition: form-data; name="payload_json"\r\n',
		"Content-Type: application/json\r\n\r\n",
		payloadJson .. "\r\n",
		"--" .. boundary .. "\r\n",
		string.format('Content-Disposition: form-data; name="files[0]"; filename="%s"\r\n', filename),
		"Content-Type: text/plain; charset=utf-8\r\n\r\n",
		content .. "\r\n",
		"--" .. boundary .. "--\r\n",
	}
	local ok, res = pcall(req, {
		Url = webhookUrl,
		Method = "POST",
		Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
		Body = table.concat(bodyParts),
	})
	if not ok then return false, tostring(res) end
	local status = type(res) == "table" and (res.StatusCode or res.Status) or nil
	if status and (status < 200 or status >= 300) then
		return false, "HTTP " .. tostring(status)
	end
	return true, "Sent (" .. tostring(status or "OK") .. ")"
end

local function safeFullName(inst)
	if not inst then return "nil" end
	local ok, path = pcall(function() return inst:GetFullName() end)
	return ok and path or tostring(inst)
end

local function fmtVec3(v)
	if typeof(v) ~= "Vector3" then return tostring(v) end
	return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

local function fmtValue(v, depth)
	depth = depth or 0
	local t = typeof(v)
	if t == "Vector3" then return fmtVec3(v)
	elseif t == "CFrame" then return "CF" .. fmtVec3(v.Position)
	elseif t == "Color3" then return string.format("RGB(%d,%d,%d)", math.floor(v.R * 255), math.floor(v.G * 255), math.floor(v.B * 255))
	elseif t == "Instance" then return "<" .. v.ClassName .. ":" .. safeFullName(v) .. ">"
	elseif t == "string" then
		local clean = v:gsub("[\r\n]+", " ")
		if #clean > 120 then clean = clean:sub(1, 120) .. "..." end
		return string.format("%q", clean)
	elseif t == "table" then
		if depth >= 2 then return "{...}" end
		local parts, count = {}, 0
		for k, val in pairs(v) do
			count = count + 1
			if count > 8 then table.insert(parts, "...") break end
			table.insert(parts, tostring(k) .. "=" .. fmtValue(val, depth + 1))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

local function fmtAttributes(inst)
	local ok, attrs = pcall(function() return inst:GetAttributes() end)
	if not ok or type(attrs) ~= "table" then return "" end
	local parts = {}
	for k, v in pairs(attrs) do
		table.insert(parts, k .. "=" .. fmtValue(v, 1))
	end
	if #parts == 0 then return "" end
	table.sort(parts)
	return " [attrs: " .. table.concat(parts, ", ") .. "]"
end

local function dumpTree(lines, root, maxDepth, maxLines, indent, state)
	state = state or { count = 0, truncated = false }
	if state.count >= maxLines then state.truncated = true return end
	local ok, children = pcall(function() return root:GetChildren() end)
	if not ok or type(children) ~= "table" then return end
	table.sort(children, function(a, b) return a.Name < b.Name end)
	local pad = string.rep("  ", indent)
	for _, child in ipairs(children) do
		if state.count >= maxLines then state.truncated = true return end
		state.count = state.count + 1
		local extra = ""
		if child:IsA("ValueBase") then
			local okV, val = pcall(function() return child.Value end)
			if okV then extra = " = " .. fmtValue(val, 1) end
		end
		local gOk, gKids = pcall(function() return child:GetChildren() end)
		local gCount = (gOk and type(gKids) == "table") and #gKids or 0
		table.insert(lines, string.format("%s- %s [%s]%s%s%s", pad, child.Name, child.ClassName,
			gCount > 0 and (" (" .. gCount .. " children)") or "", extra, fmtAttributes(child)))
		if gCount > 0 and indent < maxDepth then
			dumpTree(lines, child, maxDepth, maxLines, indent + 1, state)
		end
	end
end

local function appendSection(lines, title)
	table.insert(lines, "")
	table.insert(lines, "====================================================================")
	table.insert(lines, "  " .. title)
	table.insert(lines, "====================================================================")
end

local function scanHeaderAndPlayer(lines)
	appendSection(lines, "GAME & LOCAL PLAYER")
	local okInfo, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
	local placeName = (okInfo and type(info) == "table" and info.Name) or "unknown"
	table.insert(lines, "Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S"))
	table.insert(lines, "PlaceName: " .. tostring(placeName))
	table.insert(lines, string.format("GameId: %d | PlaceId: %d", game.GameId, game.PlaceId))
	table.insert(lines, string.format("Player: %s | Pos: %s | %s: %s",
		LocalPlayer.Name, fmtVec3(getPlayerPos()), DetectedCashName, tostring(getCashValue())))
end

local function finalizeReport(prefix, lines)
	local content = table.concat(lines, "\n")
	local filename = string.format("%s_%s.txt", prefix, os.date("%Y%m%d_%H%M%S"))
	LastReportText = content
	LastReportName = filename
	ensureFolders()
	local savedMsg = ""
	if type(writefile) == "function" then
		local path = "AllainHub/scans/" .. filename
		if pcall(writefile, path, content) then
			savedMsg = " | saved: " .. path
		end
	end
	if Toggles.AutoSendWebhook and Toggles.AutoSendWebhook.Value then
		local url = Options.WebhookUrl and Options.WebhookUrl.Value or ""
		if url ~= "" then
			sendReportToWebhook(url, filename, content)
		end
	end
	local summary = string.format("%d lines (%.1f KB)%s", #lines, #content / 1024, savedMsg)
	if Library.Labels.ScanStatus then
		Library.Labels.ScanStatus:SetText("Status: " .. summary)
	end
	Library:Notify({ Title = "Scan Complete", Description = summary, Time = 4 })
end

--============================================================================--
--// UI: Tab 1 — Auto-Drive
--============================================================================--
local AutoDriveBox = Tabs.AutoDrive:AddGroupbox({
	Side = "Left",
	Name = "Highway Auto-Drive",
	IconName = "navigation",
	Description = "Sensor-guided highway driving & traffic weaving using real inputs.",
})

AutoDriveBox:AddToggle("AutoDriveEnabled", {
	Text = "Auto-Drive",
	Default = false,
	Tooltip = "Drives your seated car automatically while weaving through highway traffic.",
	Callback = function(Value)
		if not Value then
			releaseAllDrivingKeys()
			StuckTimer = 0
			ReverseUntil = 0
			if Library.Labels.DriveStatus then
				Library.Labels.DriveStatus:SetText("Status: idle")
			end
		else
			if Toggles.AutoFarmCash and Toggles.AutoFarmCash.Value then
				Toggles.AutoFarmCash:SetValue(false)
			end
			if Toggles.CruiseEnabled and Toggles.CruiseEnabled.Value then
				Toggles.CruiseEnabled:SetValue(false)
			end
		end
	end,
}):AddKeyPicker("AutoDriveKey", {
	Default = "H",
	Mode = "Toggle",
	SyncToggleState = true,
	Text = "Auto-Drive",
})

AutoDriveBox:AddDropdown("AutoDriveMode", {
	Text = "Drive Mode",
	Values = { "Highway Road Path", "Highway Cut-Up (Weave)", "Saved Route Loop", "Free-Roam (Sensors)" },
	Default = "Highway Road Path",
	Tooltip = "Highway Road Path cruises smoothly; Highway Cut-Up weaves aggressively through NPC traffic.",
})

AutoDriveBox:AddButton("Scan / Rebuild Highway Roads", function()
	task.spawn(function()
		buildMapRoadGraph(true)
	end)
end)

AutoDriveBox:AddLabel("RoadGraphStatus", {
	Text = "Road Graph: builds automatically on start",
	DoesWrap = true,
})

AutoDriveBox:AddSlider("TargetSpeed", {
	Text = "Target Speed",
	Default = 140,
	Min = 40,
	Max = 300,
	Rounding = 0,
	Suffix = " st/s",
})

AutoDriveBox:AddSlider("LookaheadMult", {
	Text = "Sensor Lookahead",
	Default = 1.0,
	Min = 0.6,
	Max = 2.0,
	Rounding = 2,
	Suffix = "x",
})

AutoDriveBox:AddSlider("SteerSensitivity", {
	Text = "Steer Sensitivity",
	Default = 1.0,
	Min = 0.5,
	Max = 1.8,
	Rounding = 2,
	Suffix = "x",
})

AutoDriveBox:AddToggle("AutoNitro", {
	Text = "Auto Boost / Nitro (LeftShift)",
	Default = false,
	Tooltip = "Holds LeftShift on clear straights during Auto-Drive / Auto-Farm.",
})

AutoDriveBox:AddToggle("StuckRecovery", {
	Text = "Auto Stuck / Reverse Recovery",
	Default = true,
	Tooltip = "Reverses and counter-steers automatically if blocked for ~1.6s.",
})

AutoDriveBox:AddDivider()
AutoDriveBox:AddLabel("DriveStatus", {
	Text = "Status: idle",
	DoesWrap = true,
})

-- Right side: Custom Route Recorder & Loop Player
local RouteBox = Tabs.AutoDrive:AddGroupbox({
	Side = "Right",
	Name = "Custom Route Loop",
	IconName = "route",
	Description = "Record a clean highway loop, then let Auto-Drive or Cash Farm follow it.",
})

RouteBox:AddInput("RouteNameInput", {
	Text = "Route Name",
	Default = "shutoko_loop",
	Placeholder = "e.g. shutoko_expressway",
	ClearTextOnFocus = false,
})

RouteBox:AddToggle("RecordRouteToggle", {
	Text = "Record Waypoints",
	Default = false,
	Tooltip = "Drive a clean loop while enabled. Samples a point every 20 studs.",
	Callback = function(Value)
		RecordingRoute = Value
		if Value then
			RecordedPoints = {}
			Library:Notify("Route recording started. Drive your loop, then turn off & Save.", 4)
		else
			Library:Notify(string.format("Recorded %d waypoints.", #RecordedPoints), 3)
		end
	end,
})

RouteBox:AddButton("Save Recorded Route", function()
	local name = Options.RouteNameInput and Options.RouteNameInput.Value or ""
	local ok, msg = saveRoute(name, RecordedPoints)
	Library:Notify({
		Title = ok and "Route Saved" or "Save Failed",
		Description = ok and ("Saved as " .. msg) or msg,
		Time = 4,
	})
	if ok and Options.SavedRouteDropdown then
		Options.SavedRouteDropdown:SetValues(listSavedRoutes())
		Options.SavedRouteDropdown:SetValue(msg)
	end
end)

RouteBox:AddDivider()

RouteBox:AddDropdown("SavedRouteDropdown", {
	Text = "Saved Routes",
	Values = listSavedRoutes(),
	Default = 1,
})

RouteBox:AddButton("Load Selected Route", function()
	local sel = Options.SavedRouteDropdown and Options.SavedRouteDropdown.Value
	local ok, msg = loadRoute(sel)
	Library:Notify({
		Title = ok and "Route Loaded" or "Load Failed",
		Description = msg,
		Time = 4,
	})
	if ok and Library.Labels.RouteStatus then
		Library.Labels.RouteStatus:SetText("Route: " .. msg)
	end
end):AddButton("Refresh List", function()
	if Options.SavedRouteDropdown then
		Options.SavedRouteDropdown:SetValues(listSavedRoutes())
	end
end)

RouteBox:AddLabel("RouteStatus", {
	Text = "Route: none loaded",
	DoesWrap = true,
})

--============================================================================--
--// UI: Tab 2 — Assist (Collision Prevention, Cruise Control, Auto-Shift)
--============================================================================--
local ColBox = Tabs.Assist:AddGroupbox({
	Side = "Left",
	Name = "Auto Collision Prevention",
	IconName = "shield-alert",
	Description = "Active traffic & barrier assist while you drive manually.",
})

ColBox:AddToggle("CollisionPrevent", {
	Text = "Collision Prevention",
	Default = false,
	Tooltip = "Automatically brakes and/or steers around traffic cars and barriers.",
	Callback = function(Value)
		if not Value then
			releaseAllDrivingKeys()
			if Library.Labels.AssistStatus then
				Library.Labels.AssistStatus:SetText("Assist: off")
			end
		end
	end,
}):AddKeyPicker("CollisionPreventKey", {
	Default = "J",
	Mode = "Toggle",
	SyncToggleState = true,
	Text = "Collision Prevention",
})

ColBox:AddDropdown("ColMode", {
	Text = "Intervention Mode",
	Values = { "Both (Brake + Steer)", "Brake Only", "Steer Only" },
	Default = "Both (Brake + Steer)",
})

ColBox:AddSlider("ColTTC", {
	Text = "Trigger Sensitivity (TTC)",
	Default = 0.9,
	Min = 0.3,
	Max = 2.0,
	Rounding = 2,
	Suffix = " s",
})

ColBox:AddSlider("ColMinSpeed", {
	Text = "Minimum Active Speed",
	Default = 35,
	Min = 10,
	Max = 100,
	Rounding = 0,
	Suffix = " st/s",
})

ColBox:AddDivider()
ColBox:AddLabel("AssistStatus", {
	Text = "Assist: off",
	DoesWrap = true,
})

local QoLBox = Tabs.Assist:AddGroupbox({
	Side = "Right",
	Name = "Driving QoL",
	IconName = "gauge",
})

QoLBox:AddToggle("CruiseEnabled", {
	Text = "Cruise Control",
	Default = false,
	Tooltip = "Holds your target highway speed while you steer (pauses when you brake).",
	Callback = function(Value)
		if not Value then
			setKey(ControlKeys.Throttle, false)
		elseif Toggles.AutoDriveEnabled and Toggles.AutoDriveEnabled.Value then
			Toggles.AutoDriveEnabled:SetValue(false)
		end
	end,
}):AddKeyPicker("CruiseKey", {
	Default = "C",
	Mode = "Toggle",
	SyncToggleState = true,
	Text = "Cruise Control",
})

QoLBox:AddSlider("CruiseSpeed", {
	Text = "Cruise Speed",
	Default = 140,
	Min = 30,
	Max = 300,
	Rounding = 0,
	Suffix = " st/s",
})

QoLBox:AddDivider("Transmission (A-Chassis)")

QoLBox:AddToggle("AutoShift", {
	Text = "Auto-Shift Assist (Manual/Semi)",
	Default = false,
	Tooltip = "Taps Shift Up/Down based on A-Chassis RPM if using manual mode.",
})

QoLBox:AddSlider("ShiftUpRPM", {
	Text = "Shift Up RPM",
	Default = 7200,
	Min = 4000,
	Max = 11000,
	Rounding = 0,
})

QoLBox:AddSlider("ShiftDownRPM", {
	Text = "Shift Down RPM",
	Default = 3200,
	Min = 1500,
	Max = 6500,
	Rounding = 0,
})

QoLBox:AddButton("Toggle Auto/Manual (M)", function()
	tapKey(ControlKeys.ToggleTransMode, 0.05)
end)

--============================================================================--
--// UI: Tab 3 — Visuals & Performance
--============================================================================--
local EspBox = Tabs.Visuals:AddGroupbox({
	Side = "Left",
	Name = "ESP & Debug Visuals",
	IconName = "eye",
})

EspBox:AddToggle("ShowSensorRays", {
	Text = "3D Sensor Ray Visualizer",
	Default = false,
	Tooltip = "Shows sensor rays in 3D (green=clear, orange=car, red=hazard, cyan=road).",
	Callback = function(Value)
		if not Value then
			clearDebugRays()
		end
	end,
})

EspBox:AddToggle("TrafficEsp", {
	Text = "Nearby Traffic ESP",
	Default = false,
	Tooltip = "Marks nearby NPC traffic cars with distance & speed.",
	Callback = function()
		refreshTrafficEsp()
	end,
})

EspBox:AddSlider("TrafficEspRange", {
	Text = "Traffic ESP Range",
	Default = 600,
	Min = 150,
	Max = 1500,
	Rounding = 0,
	Suffix = " st",
})

EspBox:AddToggle("CarEsp", {
	Text = "Other Players ESP",
	Default = false,
	Callback = function()
		refreshCarEsp()
	end,
})

EspBox:AddButton("Refresh ESP", function()
	refreshTrafficEsp()
	refreshCarEsp()
	Library:Notify("ESP refreshed.", 2)
end)

local PerfBox = Tabs.Visuals:AddGroupbox({
	Side = "Right",
	Name = "Performance",
	IconName = "zap",
})

PerfBox:AddToggle("FpsBoost", {
	Text = "FPS Boost (No Shadows/Particles)",
	Default = false,
	Callback = function(Value)
		setFpsBoost(Value)
	end,
})

PerfBox:AddToggle("LowPower", {
	Text = "Low Power Mode (Pause 3D Render)",
	Default = false,
	Tooltip = "Stops 3D rendering for overnight AFK Cash farming.",
	Callback = function(Value)
		setLowPower(Value)
	end,
}):AddKeyPicker("LowPowerKey", {
	Default = "L",
	Mode = "Toggle",
	SyncToggleState = true,
	Text = "Low Power",
})

PerfBox:AddSlider("LowPowerFpsCap", {
	Text = "Low Power FPS Cap",
	Default = 20,
	Min = 10,
	Max = 60,
	Rounding = 0,
	Suffix = " FPS",
})

--============================================================================--
--// UI: Tab 4 — AFK & Cash Farm
--============================================================================--
local CashFarmBox = Tabs.AFK:AddGroupbox({
	Side = "Left",
	Name = "Auto-Farm Cash",
	IconName = "banknote",
	Description = "Autonomously drives & weaves through highway traffic to farm Cash.",
})

CashFarmBox:AddToggle("AutoFarmCash", {
	Text = "Auto-Farm Cash",
	Default = false,
	Tooltip = "Drives at high speed with traffic avoidance & stall recovery.",
	Callback = function(Value)
		if Value then
			LastCashTickTime = os.clock()
			if Toggles.AutoDriveEnabled and Toggles.AutoDriveEnabled.Value then
				Toggles.AutoDriveEnabled:SetValue(false)
			end
			if Toggles.CruiseEnabled and Toggles.CruiseEnabled.Value then
				Toggles.CruiseEnabled:SetValue(false)
			end
			if Toggles.AntiAfk and not Toggles.AntiAfk.Value then
				Toggles.AntiAfk:SetValue(true)
			end
		else
			releaseAllDrivingKeys()
			StuckTimer = 0
			ReverseUntil = 0
			if Library.Labels.FarmStatusLabel then
				Library.Labels.FarmStatusLabel:SetText("Farm: idle")
			end
		end
	end,
}):AddKeyPicker("AutoFarmCashKey", {
	Default = "F",
	Mode = "Toggle",
	SyncToggleState = true,
	Text = "Auto-Farm Cash",
})

CashFarmBox:AddDropdown("CashFarmMode", {
	Text = "Farm Strategy",
	Values = { "Highway Cut-Up (Fast)", "Highway Cruise (Safe)", "Saved Route Loop" },
	Default = "Highway Cut-Up (Fast)",
})

CashFarmBox:AddSlider("CashFarmSpeed", {
	Text = "Farm Speed",
	Default = 145,
	Min = 40,
	Max = 280,
	Rounding = 0,
	Suffix = " st/s",
})

CashFarmBox:AddToggle("CashStallWatchdog", {
	Text = "Cash Stall Auto-Recovery",
	Default = true,
	Tooltip = "Reverses & turns if Cash stops increasing for 12+ seconds.",
})

CashFarmBox:AddLabel("FarmStatusLabel", {
	Text = "Farm: idle",
	DoesWrap = true,
})

local StatsBox = Tabs.AFK:AddGroupbox({
	Side = "Left",
	Name = "AFK Cash Farm Stats",
	IconName = "coins",
})

StatsBox:AddLabel("CashStatsLabel", {
	Text = "Cash: -- | Earned: +$0\nRate: $0/hr | Runtime: 0m 0s",
	DoesWrap = true,
})

StatsBox:AddLabel("TelemetryLabel", {
	Text = "Vehicle: not seated",
	DoesWrap = true,
})

StatsBox:AddButton("Reset Session Stats", function()
	SessionStartTime = os.clock()
	StartCash = getCashValue()
	Library:Notify("Session stats reset.", 2)
end)

StatsBox:AddDivider()

StatsBox:AddToggle("AntiAfk", {
	Text = "Anti-AFK (Prevent 20m Kick)",
	Default = true,
})

local AlertBox = Tabs.AFK:AddGroupbox({
	Side = "Right",
	Name = "Discord Webhook Alerts",
	IconName = "bell",
})

AlertBox:AddInput("WebhookUrl", {
	Text = "Discord Webhook URL",
	Placeholder = "https://discord.com/api/webhooks/...",
	ClearTextOnFocus = false,
	Finished = false,
})

AlertBox:AddToggle("WebhookReports", {
	Text = "Periodic Farm Summary",
	Default = false,
})

AlertBox:AddSlider("WebhookInterval", {
	Text = "Report Interval",
	Default = 15,
	Min = 5,
	Max = 60,
	Rounding = 0,
	Suffix = " min",
})

AlertBox:AddButton("Send Test Report Now", function()
	local url = Options.WebhookUrl and Options.WebhookUrl.Value or ""
	local curCash = getCashValue() or 0
	local earned = StartCash and (curCash - StartCash) or 0
	local elapsed = math.max(os.clock() - SessionStartTime, 1)
	local perHr = (earned / elapsed) * 3600
	local msg = string.format(
		"**Midnight Chasers Report** (%s)\n%s: $%s (+$%s | $%s/hr)\nRuntime: %dm %ds",
		LocalPlayer.Name,
		DetectedCashName,
		formatNumber(curCash),
		formatNumber(earned),
		formatNumber(perHr),
		math.floor(elapsed / 60),
		math.floor(elapsed % 60)
	)
	local ok, res = sendWebhookText(url, msg)
	Library:Notify({ Title = ok and "Webhook Sent" or "Webhook Failed", Description = res, Time = 4 })
end)

--============================================================================--
--// UI: Tab 5 — Scanner (Read-Only Inspector for Game Updates)
--============================================================================--
local ScanBox = Tabs.Scanner:AddGroupbox({
	Side = "Left",
	Name = "Game Data Scanner",
	IconName = "search",
	Description = "Inspect workspace, vehicle, and UI structure for future Midnight Chasers features.",
})

ScanBox:AddSlider("ScanDepth", {
	Text = "Tree Scan Depth",
	Default = 3,
	Min = 1,
	Max = 6,
	Rounding = 0,
})

ScanBox:AddButton("Workspace & Stats Snapshot", function()
	task.spawn(function()
		local lines = {}
		scanHeaderAndPlayer(lines)
		appendSection(lines, "WORKSPACE TOP-LEVEL")
		dumpTree(lines, Workspace, 2, 250, 0)
		local ls = LocalPlayer:FindFirstChild("leaderstats")
		if ls then
			appendSection(lines, "LEADERSTATS")
			dumpTree(lines, ls, 2, 100, 0)
		end
		finalizeReport("mc_workspace_snapshot", lines)
	end)
end)

ScanBox:AddButton("Vehicle & Telemetry Snapshot", function()
	task.spawn(function()
		local lines = {}
		scanHeaderAndPlayer(lines)
		appendSection(lines, "CURRENT VEHICLE")
		local veh, seat = getSeatedVehicle()
		if not veh then
			table.insert(lines, "Not seated in a vehicle.")
		else
			table.insert(lines, "Vehicle: " .. safeFullName(veh) .. fmtAttributes(veh))
			table.insert(lines, "Seat:    " .. safeFullName(seat))
			local tele = getAChassisTelemetry()
			if tele then
				table.insert(lines, string.format("A-Chassis: Gear=%s RPM=%s Mode=%s",
					tostring(tele.gear), tostring(tele.rpm), tostring(tele.transMode)))
			end
			dumpTree(lines, veh, Options.ScanDepth and Options.ScanDepth.Value or 3, 350, 0)
		end
		finalizeReport("mc_vehicle_snapshot", lines)
	end)
end)

ScanBox:AddToggle("AutoSendWebhook", {
	Text = "Auto-Send Scans to Webhook",
	Default = false,
})

ScanBox:AddButton("Copy Last Scan to Clipboard", function()
	if LastReportText == "" then
		Library:Notify("Run a scan first.", 3)
		return
	end
	if type(setclipboard) ~= "function" then
		Library:Notify("setclipboard unavailable.", 3)
		return
	end
	setclipboard(LastReportText)
	Library:Notify("Copied " .. LastReportName .. " to clipboard.", 3)
end)

ScanBox:AddLabel("ScanStatus", {
	Text = "Status: idle",
	DoesWrap = true,
})

--============================================================================--
--// UI: Tab 6 — Settings
--============================================================================--
local MenuGroup = Tabs.Settings:AddGroupbox({
	Side = "Left",
	Name = "Menu",
	IconName = "wrench",
})

MenuGroup:AddCheckbox("ShowToggleButton", {
	Text = "Toggle Button",
	Default = Library.IsMobile,
	Callback = function(Value)
		Library:SetToggleButtonVisible(Value)
	end,
})

MenuGroup:AddDropdown("NotificationSide", {
	Text = "Notification Side",
	Values = { "Left", "Right" },
	Default = "Right",
	Callback = function(Value)
		Library:SetNotifySide(Value)
	end,
})

MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
	Default = "RightShift",
	NoUI = true,
	Text = "Menu keybind",
})

MenuGroup:AddButton("Unload", function()
	Library:Unload()
end)

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind", "AutoDriveEnabled", "AutoFarmCash", "RecordRouteToggle", "LowPower" })
ThemeManager:SetFolder("AllainHub")
SaveManager:SetFolder("AllainHub/midnight-chasers")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

--============================================================================--
--// Main Loops (Heartbeat Driving + 1s UI/ESP/AFK Updater)
--============================================================================--
StartCash = getCashValue()

trackConn(Connections, LocalPlayer.Idled:Connect(function()
	if Unloaded then return end
	if Toggles.AntiAfk and Toggles.AntiAfk.Value then
		if VirtualUser then
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
			end)
		end
	end
end))

trackConn(Connections, RunService.Heartbeat:Connect(function(dt)
	if Unloaded then return end

	local veh, seat = getSeatedVehicle()
	local cashFarm = Toggles.AutoFarmCash and Toggles.AutoFarmCash.Value
	local autoDrive = Toggles.AutoDriveEnabled and Toggles.AutoDriveEnabled.Value
	local colPrevent = Toggles.CollisionPrevent and Toggles.CollisionPrevent.Value
	local cruise = Toggles.CruiseEnabled and Toggles.CruiseEnabled.Value
	local showRays = Toggles.ShowSensorRays and Toggles.ShowSensorRays.Value
	local autoShift = Toggles.AutoShift and Toggles.AutoShift.Value

	if not veh or not seat then
		if cashFarm or autoDrive or colPrevent or cruise then
			releaseAllDrivingKeys()
		end
		if #ActiveRayVisuals > 0 then
			clearDebugRays()
		end
		return
	end

	local kin = getVehicleKinematics(veh, seat)
	if not kin then return end

	if RecordingRoute then
		local last = RecordedPoints[#RecordedPoints]
		local needSample = not last
			or ((kin.pos.X - last.x) ^ 2 + (kin.pos.Z - last.z) ^ 2) >= (20 * 20)
		if needSample then
			table.insert(RecordedPoints, {
				x = math.floor(kin.pos.X * 10) / 10,
				y = math.floor(kin.pos.Y * 10) / 10,
				z = math.floor(kin.pos.Z * 10) / 10,
				speed = math.floor(math.max(kin.forwardSpeed, 25)),
			})
			if Library.Labels.RouteStatus then
				Library.Labels.RouteStatus:SetText(string.format("Recording: %d waypoints", #RecordedPoints))
			end
		end
	end

	if cashFarm then
		stepCashFarm(veh, kin, dt)
	elseif autoDrive then
		stepAutoDrive(veh, kin, dt)
	elseif colPrevent then
		local intervened = stepCollisionPrevention(veh, kin, dt)
		if not intervened and cruise then
			stepCruiseControl(kin, dt)
		end
	elseif cruise then
		if showRays then
			scanSensors(veh, kin, Options.LookaheadMult and Options.LookaheadMult.Value or 1.0)
		end
		stepCruiseControl(kin, dt)
	elseif showRays then
		scanSensors(veh, kin, Options.LookaheadMult and Options.LookaheadMult.Value or 1.0)
	end

	if autoShift then
		stepAutoShift()
	end
end))

task.spawn(function()
	while not Unloaded do
		task.wait(1)
		if Unloaded then break end

		local curCash = getCashValue()
		if curCash then
			if not StartCash then StartCash = curCash end
			if LastCash > 0 and curCash > LastCash then
				LastCashTickAmount = curCash - LastCash
				LastCashTickTime = os.clock()
			end
			LastCash = curCash
			local earned = curCash - StartCash
			local elapsed = math.max(os.clock() - SessionStartTime, 1)
			local perHr = (earned / elapsed) * 3600
			if Library.Labels.CashStatsLabel then
				Library.Labels.CashStatsLabel:SetText(string.format(
					"%s: $%s | Earned: +$%s\nRate: $%s/hr | Runtime: %dm %ds",
					DetectedCashName,
					formatNumber(curCash),
					formatNumber(earned),
					formatNumber(perHr),
					math.floor(elapsed / 60),
					math.floor(elapsed % 60)
				))
			end

			if Toggles.WebhookReports and Toggles.WebhookReports.Value then
				local interval = (Options.WebhookInterval and Options.WebhookInterval.Value or 15) * 60
				if os.clock() - LastWebhookReportTime >= interval then
					LastWebhookReportTime = os.clock()
					local url = Options.WebhookUrl and Options.WebhookUrl.Value or ""
					if url ~= "" then
						sendWebhookText(url, string.format(
							"**Midnight Chasers Auto-Report** (%s) | %s: $%s (+$%s | $%s/hr) | %dm",
							LocalPlayer.Name,
							DetectedCashName,
							formatNumber(curCash),
							formatNumber(earned),
							formatNumber(perHr),
							math.floor(elapsed / 60)
						))
					end
				end
			end
		end

		local veh, seat = getSeatedVehicle()
		if Library.Labels.TelemetryLabel then
			if veh and seat then
				local speed = seat.AssemblyLinearVelocity.Magnitude
				local tele = getAChassisTelemetry()
				local gearStr = tele and tele.gear and tostring(tele.gear) or "?"
				local rpmStr = tele and tele.rpm and tostring(math.floor(tele.rpm)) or "?"
				Library.Labels.TelemetryLabel:SetText(string.format(
					"Vehicle: %s | %.0f st/s | Gear %s | %s RPM",
					veh.Name,
					speed,
					gearStr,
					rpmStr
				))
			else
				Library.Labels.TelemetryLabel:SetText("Vehicle: not seated")
			end
		end

		-- Refresh traffic ESP periodically as NPC cars spawn/despawn
		if Toggles.TrafficEsp and Toggles.TrafficEsp.Value and (os.clock() - LastTrafficEspRefresh >= 3) then
			LastTrafficEspRefresh = os.clock()
			refreshTrafficEsp()
		end

		local pPos = getPlayerPos()
		if pPos then
			for _, bb in ipairs(TrafficEspObjects) do
				if bb and bb.Parent and bb.Adornee and bb.Adornee:IsA("BasePart") then
					local lbl = bb:FindFirstChildOfClass("TextLabel")
					if lbl then
						local d = (bb.Adornee.Position - pPos).Magnitude
						local spd = bb.Adornee.AssemblyLinearVelocity.Magnitude
						lbl.Text = string.format("Traffic (%.0f st | %.0f st/s)", d, spd)
					end
				end
			end
			for _, bb in ipairs(CarEspObjects) do
				if bb and bb.Parent and bb.Adornee and bb.Adornee:IsA("BasePart") then
					local lbl = bb:FindFirstChildOfClass("TextLabel")
					if lbl then
						local d = (bb.Adornee.Position - pPos).Magnitude
						local spd = bb.Adornee.AssemblyLinearVelocity.Magnitude
						lbl.Text = string.format("%s (%.0f st | %.0f st/s)", bb:GetAttribute("BaseName") or "", d, spd)
					end
				end
			end
		end
	end
end)

--// Unload Cleanup \\--
Library:OnUnload(function()
	Unloaded = true
	releaseAllDrivingKeys()
	clearDebugRays()
	clearEspTable(TrafficEspObjects)
	clearEspTable(CarEspObjects)
	if LowPowerActive then
		setLowPower(false)
	end
	if SavedLighting then
		setFpsBoost(false)
	end
	disconnectAll(Connections)
	if env.__AllainMCLibrary == Library then
		env.__AllainMCLibrary = nil
	end
end)

Library:Notify({
	Title = "Allain Automation",
	Description = "Midnight Chasers: Highway Racing v0.1 loaded! Press RightShift to toggle menu.",
	Time = 4,
})
