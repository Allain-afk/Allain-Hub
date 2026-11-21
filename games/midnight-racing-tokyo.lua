--// Allain Automation — Midnight Racing: Tokyo \\--
-- Keyless automation suite for Midnight Racing: Tokyo (A-Chassis 6).
-- Features: Free-Roam Auto-Drive, Custom Route Loop Auto-Drive, Auto Collision
-- Prevention, Cruise Control, Auto-Shift Assist, Event/Car ESP, AFK Yen Tracker,
-- Anti-AFK, Low-Power/FPS Boost, Discord Alerts, and Built-in Data Scanner.
-- GameId: 1198533421 | PlaceId: 7444724537

local env = (getgenv and getgenv()) or shared
if env.__AllainMRTLoading then
	return
end
env.__AllainMRTLoading = true

if env.__AllainMRTLibrary then
	pcall(function()
		env.__AllainMRTLibrary:Unload()
	end)
	env.__AllainMRTLibrary = nil
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
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local ReplicatedFirst = cloneref(game:GetService("ReplicatedFirst"))
local StarterGui = cloneref(game:GetService("StarterGui"))
local StarterPack = cloneref(game:GetService("StarterPack"))
local StarterPlayer = cloneref(game:GetService("StarterPlayer"))
local CollectionService = cloneref(game:GetService("CollectionService"))
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
	env.__AllainMRTLoading = false
	warn("[Allain MRT] Failed to load UI library: " .. tostring(Library))
	return
end

env.__AllainMRTLibrary = Library
env.__AllainMRTLoading = false

local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

--// Window \\--
local Window = Library:CreateWindow({
	Title = "Allain Automation",
	Footer = "Midnight Racing: Tokyo",
	FooterLeft = "MR:T Automation",
	FooterRight = "v0.2",
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
	Visuals = Window:AddTab("Events & Visuals", "eye"),
	AFK = Window:AddTab("AFK & Alerts", "clock"),
	Scanner = Window:AddTab("Scanner", "radar"),
	Settings = Window:AddTab("Settings", "settings"),
}

--============================================================================--
--// Core State & Cleanup Helpers
--============================================================================--
local Connections = {}
local CaptureConnections = {}
local Unloaded = false

-- Simulated input state
local HeldKeys = {}
local ControlKeys = {
	Throttle = Enum.KeyCode.W,
	Brake = Enum.KeyCode.S,
	SteerLeft = Enum.KeyCode.A,
	SteerRight = Enum.KeyCode.D,
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

-- ESP state
local EventEspObjects = {}
local CarEspObjects = {}

-- AFK / Yen Tracker state
local SessionStartTime = os.clock()
local StartYen = nil
local LastYen = 0
local LastWebhookReportTime = 0

-- FPS Boost / Low Power state
local SavedLighting = nil
local LowPowerActive = false

-- Scanner state
local IsCapturing = false
local CaptureEvents = {}
local CaptureStartTime = 0
local LastReportText = ""
local LastReportName = "mrt_scan.txt"
local OldNamecall = nil
local RemoteHookActive = false

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
	end)
end

--============================================================================--
--// Control Key Resolution & Safe VirtualInputManager Driving
--============================================================================--
local function resolveKeyCode(str, fallback)
	if type(str) ~= "string" or str == "" then
		return fallback
	end
	local ok, kc = pcall(function()
		return Enum.KeyCode[str]
	end)
	if ok and typeof(kc) == "EnumItem" then
		return kc
	end
	return fallback
end

local function refreshControlKeys()
	local cc = LocalPlayer:FindFirstChild("CustomControls")
	if not cc then
		return
	end
	local function pick(primary, secondary, fallback)
		local v1 = cc:FindFirstChild(primary)
		if v1 and v1:IsA("StringValue") and v1.Value ~= "" then
			local kc = resolveKeyCode(v1.Value, nil)
			if kc then return kc end
		end
		local v2 = cc:FindFirstChild(secondary)
		if v2 and v2:IsA("StringValue") and v2.Value ~= "" then
			local kc = resolveKeyCode(v2.Value, nil)
			if kc then return kc end
		end
		return fallback
	end
	ControlKeys.Throttle = pick("Throttle2", "Throttle", Enum.KeyCode.W)
	ControlKeys.Brake = pick("Brake2", "Brake", Enum.KeyCode.S)
	ControlKeys.SteerLeft = pick("SteerLeft2", "SteerLeft", Enum.KeyCode.A)
	ControlKeys.SteerRight = pick("SteerRight2", "SteerRight", Enum.KeyCode.D)
	ControlKeys.ShiftUp = pick("ShiftUp", "ShiftUp", Enum.KeyCode.E)
	ControlKeys.ShiftDown = pick("ShiftDown", "ShiftDown", Enum.KeyCode.Q)
	ControlKeys.ToggleTransMode = pick("ToggleTransMode", "ToggleTransMode", Enum.KeyCode.M)
end
refreshControlKeys()

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
-- into clean key holds/pulses so A-Chassis steers smoothly without harsh snapping.
local function applyDrivingInputs(throttle, brake, steer, dt)
	PwmPhase = (PwmPhase + dt * 10) % 1 -- 10 Hz PWM cycle

	-- Throttle & Brake (mutually exclusive)
	if brake > 0.05 then
		setKey(ControlKeys.Throttle, false)
		local brakeOn = brake >= 0.85 or (PwmPhase < brake)
		setKey(ControlKeys.Brake, brakeOn)
	elseif throttle > 0.05 then
		setKey(ControlKeys.Brake, false)
		local throttleOn = throttle >= 0.85 or (PwmPhase < throttle)
		setKey(ControlKeys.Throttle, throttleOn)
	else
		setKey(ControlKeys.Throttle, false)
		setKey(ControlKeys.Brake, false)
	end

	-- Steering: negative = left, positive = right
	local absSteer = math.abs(steer)
	if absSteer < 0.07 then
		setKey(ControlKeys.SteerLeft, false)
		setKey(ControlKeys.SteerRight, false)
	elseif steer < 0 then
		setKey(ControlKeys.SteerRight, false)
		local leftOn = absSteer >= 0.82 or (PwmPhase < absSteer)
		setKey(ControlKeys.SteerLeft, leftOn)
	else
		setKey(ControlKeys.SteerLeft, false)
		local rightOn = absSteer >= 0.82 or (PwmPhase < absSteer)
		setKey(ControlKeys.SteerRight, rightOn)
	end
end

--============================================================================--
--// Vehicle & A-Chassis Telemetry Helpers
--============================================================================--
local function getOwnVehicleFolder()
	local vf = Workspace:FindFirstChild("VehiclesFolder")
	return vf and vf:FindFirstChild(LocalPlayer.Name) or nil
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
	local ownFolder = getOwnVehicleFolder()
	local cur = seat
	local bestModel = nil
	while cur and cur ~= Workspace and cur ~= ownFolder do
		if cur:IsA("Model") then
			bestModel = cur
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
	local forward = cf.LookVector
	local flatForward = Vector3.new(forward.X, 0, forward.Z)
	if flatForward.Magnitude < 0.01 then
		flatForward = Vector3.new(0, 0, -1)
	else
		flatForward = flatForward.Unit
	end
	local flatRight = Vector3.new(-flatForward.Z, 0, flatForward.X)

	local vel = seat.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local forwardSpeed = flatVel:Dot(flatForward)
	local totalSpeed = flatVel.Magnitude

	-- Estimate front bumper origin from vehicle bounding box
	local frontOffset = 7.5
	local okBox, boxCF, boxSize = pcall(function()
		return veh:GetBoundingBox()
	end)
	if okBox and typeof(boxCF) == "CFrame" and typeof(boxSize) == "Vector3" then
		local halfLen = math.max(boxSize.Z, boxSize.X) * 0.5
		frontOffset = math.clamp(halfLen, 5, 13)
	end

	local sensorOrigin = seat.Position + flatForward * (frontOffset * 0.65) + Vector3.new(0, 1.4, 0)
	return {
		pos = seat.Position,
		sensorOrigin = sensorOrigin,
		forward = flatForward,
		right = flatRight,
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

local function getYenValue()
	local ls = LocalPlayer:FindFirstChild("leaderstats")
	if not ls then return nil end
	local yen = ls:FindFirstChild("Yen")
	if yen and (yen:IsA("IntValue") or yen:IsA("NumberValue")) then
		return yen.Value
	end
	return nil
end

local function formatNumber(n)
	local s = tostring(math.floor(n + 0.5))
	local pos = #s % 3
	if pos == 0 then pos = 3 end
	local parts = { s:sub(1, pos) }
	for i = pos + 1, #s, 3 do
		table.insert(parts, s:sub(i, i + 2))
	end
	return table.concat(parts, ",")
end

--============================================================================--
--// 3D Sensor Raycast Engine & Debug Visualizer
--============================================================================--
local WHISKER_ANGLES = { -65, -35, -15, 0, 15, 35, 65 }

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
	DebugFolder.Name = "__AllainMRTDebug"
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
	part.Size = Vector3.new(0.18, 0.18, dist)
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
	local ownFolder = getOwnVehicleFolder()
	if ownFolder and ownFolder ~= veh then
		table.insert(ignore, ownFolder)
	end
	if DebugFolder then
		table.insert(ignore, DebugFolder)
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return params
end

local function isOtherPlayerVehicle(inst)
	local vf = Workspace:FindFirstChild("VehiclesFolder")
	if not vf or not inst:IsDescendantOf(vf) then
		return false
	end
	local ownFolder = getOwnVehicleFolder()
	if ownFolder and inst:IsDescendantOf(ownFolder) then
		return false
	end
	return true
end

local function scanSensors(veh, kin, lookaheadMult)
	lookaheadMult = lookaheadMult or 1.0
	local speed = math.max(kin.forwardSpeed, 0)
	local centerRange = math.clamp((32 + speed * 0.65) * lookaheadMult, 26, 175)
	local params = buildRaycastParams(veh)
	local showDebug = Toggles.ShowSensorRays and Toggles.ShowSensorRays.Value
	local vf = Workspace:FindFirstChild("VehiclesFolder")

	local rays = {}
	local minForwardDist = math.huge
	local hitOtherCarAhead = false

	for idx, deg in ipairs(WHISKER_ANGLES) do
		local rad = math.rad(deg)
		local dir = (kin.forward * math.cos(rad) + kin.right * math.sin(rad)).Unit
		-- Side rays are shorter than forward rays
		local scale = (deg == 0) and 1.0 or (math.abs(deg) <= 15 and 0.88 or (math.abs(deg) <= 35 and 0.65 or 0.42))
		local maxDist = centerRange * scale

		local res = Workspace:Raycast(kin.sensorOrigin, dir * maxDist, params)
		local dist = maxDist
		local hitCar = false
		if res and res.Instance and res.Instance.CanCollide then
			dist = res.Distance
			if vf and isOtherPlayerVehicle(res.Instance) then
				hitCar = true
			end
		elseif res and res.Instance and not res.Instance.CanCollide then
			-- Re-cast past non-collidable trigger/decoration if needed
			local res2 = Workspace:Raycast(res.Position + dir * 1.5, dir * math.max(maxDist - res.Distance - 1.5, 1), params)
			if res2 and res2.Instance and res2.Instance.CanCollide then
				dist = res.Distance + 1.5 + res2.Distance
				if vf and isOtherPlayerVehicle(res2.Instance) then
					hitCar = true
				end
			end
		end

		local ratio = dist / maxDist
		rays[idx] = { deg = deg, dist = dist, maxDist = maxDist, ratio = ratio, hitCar = hitCar }

		if math.abs(deg) <= 15 and dist < minForwardDist then
			minForwardDist = dist
			if hitCar then
				hitOtherCarAhead = true
			end
		end

		if showDebug then
			local col = ratio > 0.65 and Color3.fromRGB(60, 230, 110)
				or (ratio > 0.35 and Color3.fromRGB(245, 200, 60) or Color3.fromRGB(240, 70, 70))
			setDebugRayPart(idx, kin.sensorOrigin, kin.sensorOrigin + dir * dist, col)
		end
	end

	-- Downward road-edge / cliff probes (ahead-left and ahead-right)
	local edgeAhead = math.clamp(16 + speed * 0.28, 16, 48)
	local edgeSpread = 10
	local leftOrigin = kin.pos + kin.forward * edgeAhead - kin.right * edgeSpread + Vector3.new(0, 4, 0)
	local rightOrigin = kin.pos + kin.forward * edgeAhead + kin.right * edgeSpread + Vector3.new(0, 4, 0)
	local downVec = Vector3.new(0, -18, 0)

	local leftGround = Workspace:Raycast(leftOrigin, downVec, params)
	local rightGround = Workspace:Raycast(rightOrigin, downVec, params)
	local leftCliff = (not leftGround) or (leftGround.Distance > 9.5)
	local rightCliff = (not rightGround) or (rightGround.Distance > 9.5)

	if showDebug then
		setDebugRayPart(8, leftOrigin, leftGround and leftGround.Position or (leftOrigin + downVec),
			leftCliff and Color3.fromRGB(240, 70, 70) or Color3.fromRGB(80, 180, 255))
		setDebugRayPart(9, rightOrigin, rightGround and rightGround.Position or (rightOrigin + downVec),
			rightCliff and Color3.fromRGB(240, 70, 70) or Color3.fromRGB(80, 180, 255))
	else
		if #ActiveRayVisuals > 0 then
			clearDebugRays()
		end
	end

	return {
		rays = rays,
		centerDist = rays[4].dist,
		centerRatio = rays[4].ratio,
		minForwardDist = minForwardDist,
		hitOtherCarAhead = hitOtherCarAhead,
		leftCliff = leftCliff,
		rightCliff = rightCliff,
	}
end

--============================================================================--
--// Route Storage (Custom Loop Auto-Drive)
--============================================================================--
local function listSavedRoutes()
	ensureFolders()
	if type(listfiles) ~= "function" then
		return {}
	end
	local ok, files = pcall(listfiles, "AllainHub/routes")
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
	local path = "AllainHub/routes/" .. safeName .. ".json"
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
	local path = "AllainHub/routes/" .. name .. ".json"
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
--// Driving Controllers (Auto-Drive, Collision Prevention, Cruise, Auto-Shift)
--============================================================================--
local function computeObstacleAvoidance(sensors)
	local r = sensors.rays
	-- Left clearance: rays 1 (-65), 2 (-35), 3 (-15)
	-- Right clearance: rays 5 (+15), 6 (+35), 7 (+65)
	local leftScore = r[1].ratio * 0.22 + r[2].ratio * 0.36 + r[3].ratio * 0.42
	local rightScore = r[7].ratio * 0.22 + r[6].ratio * 0.36 + r[5].ratio * 0.42

	if sensors.leftCliff then leftScore = leftScore - 0.45 end
	if sensors.rightCliff then rightScore = rightScore - 0.45 end

	-- Positive steer = turn right (away from left obstacles)
	local steer = (rightScore - leftScore) * 1.45

	-- If dead ahead is blocked, bias firmly toward the more open side
	if sensors.centerRatio < 0.55 then
		local urgency = (0.55 - sensors.centerRatio) / 0.55
		local dir = (rightScore >= leftScore) and 1 or -1
		steer = steer + dir * urgency * 0.95
	end

	return math.clamp(steer, -1, 1), leftScore, rightScore
end

local function stepAutoDrive(veh, kin, dt)
	local mode = Options.AutoDriveMode and Options.AutoDriveMode.Value or "Free-Roam (Sensors)"
	local targetSpeed = Options.TargetSpeed and Options.TargetSpeed.Value or 95
	local lookaheadMult = Options.LookaheadMult and Options.LookaheadMult.Value or 1.0
	local steerSens = Options.SteerSensitivity and Options.SteerSensitivity.Value or 1.0
	local stuckEnabled = Toggles.StuckRecovery and Toggles.StuckRecovery.Value

	local sensors = scanSensors(veh, kin, lookaheadMult)
	local now = os.clock()

	-- Stuck / Reverse recovery
	if now < ReverseUntil then
		applyDrivingInputs(0, 0.95, ReverseSteerDir * 0.9, dt)
		if Library.Labels.DriveStatus then
			Library.Labels.DriveStatus:SetText("Status: reversing (stuck recovery)")
		end
		return
	end

	local avoidSteer, leftScore, rightScore = computeObstacleAvoidance(sensors)
	local desiredSteer = avoidSteer
	local desiredSpeed = targetSpeed

	if mode == "Saved Route Loop" and #LoadedRoutePoints >= 5 then
		-- Pure-Pursuit along recorded loop
		local n = #LoadedRoutePoints
		-- Advance cursor if close to current point
		local curPt = LoadedRoutePoints[RouteCursor]
		local curDist = (Vector3.new(curPt.x, kin.pos.Y, curPt.z) - kin.pos).Magnitude
		if curDist > 160 then
			RouteCursor = findNearestRouteIndex(kin.pos, LoadedRoutePoints)
		end

		local lookaheadDist = math.clamp(22 + math.max(kin.forwardSpeed, 0) * 0.38, 22, 75)
		local targetIdx = RouteCursor
		local walked = 0
		for _ = 1, 30 do
			local pA = LoadedRoutePoints[targetIdx]
			local nextIdx = (targetIdx % n) + 1
			local pB = LoadedRoutePoints[nextIdx]
			local seg = math.sqrt((pB.x - pA.x) ^ 2 + (pB.z - pA.z) ^ 2)
			walked = walked + seg
			targetIdx = nextIdx
			if walked >= lookaheadDist then
				break
			end
		end
		-- Advance RouteCursor when we pass near it
		local dToCur = math.sqrt((curPt.x - kin.pos.X) ^ 2 + (curPt.z - kin.pos.Z) ^ 2)
		if dToCur < 26 then
			RouteCursor = (RouteCursor % n) + 1
		end

		local aimPt = LoadedRoutePoints[targetIdx]
		local toAim = Vector3.new(aimPt.x - kin.pos.X, 0, aimPt.z - kin.pos.Z)
		if toAim.Magnitude > 1 then
			toAim = toAim.Unit
			local cross = kin.forward.X * toAim.Z - kin.forward.Z * toAim.X
			local dot = math.clamp(kin.forward:Dot(toAim), -1, 1)
			local angleErr = math.atan2(cross, dot) -- positive = target is to the right
			local routeSteer = math.clamp(angleErr * 1.35, -1, 1)

			-- Blend with obstacle avoidance when something is close
			local obstacleWeight = 0
			if sensors.minForwardDist < 38 or sensors.leftCliff or sensors.rightCliff then
				obstacleWeight = math.clamp((38 - sensors.minForwardDist) / 28, 0.25, 0.85)
			end
			desiredSteer = routeSteer * (1 - obstacleWeight) + avoidSteer * obstacleWeight

			-- Slow for sharp route turns
			if math.abs(angleErr) > 0.45 then
				desiredSpeed = math.min(desiredSpeed, targetSpeed * 0.6)
			end
		end
	end

	-- Apply steering sensitivity and smoothing
	desiredSteer = math.clamp(desiredSteer * steerSens, -1, 1)
	SmoothedSteer = SmoothedSteer + (desiredSteer - SmoothedSteer) * math.min(dt * 9, 1)

	-- Speed modulation for corners & obstacles
	local turnSlowdown = 1 - math.abs(SmoothedSteer) * 0.42
	desiredSpeed = desiredSpeed * math.clamp(turnSlowdown, 0.45, 1)

	if sensors.minForwardDist < 22 then
		desiredSpeed = 0
	elseif sensors.minForwardDist < 48 then
		local f = (sensors.minForwardDist - 22) / 26
		desiredSpeed = math.min(desiredSpeed, targetSpeed * math.max(f, 0.25))
	end

	if sensors.hitOtherCarAhead and sensors.minForwardDist < 40 then
		desiredSpeed = math.min(desiredSpeed, 20)
	end

	-- Compute throttle / brake
	local speed = kin.forwardSpeed
	local throttle, brake = 0, 0
	if speed < desiredSpeed - 4 then
		throttle = math.clamp((desiredSpeed - speed) / 25, 0.25, 1)
	elseif speed > desiredSpeed + 10 then
		brake = math.clamp((speed - desiredSpeed) / 35, 0.2, 1)
	elseif desiredSpeed == 0 and speed > 2 then
		brake = 1
	end

	-- Stuck detection
	if stuckEnabled and throttle > 0.2 and math.abs(kin.totalSpeed) < 4 then
		StuckTimer = StuckTimer + dt
		if StuckTimer >= 2.0 then
			StuckTimer = 0
			ReverseUntil = now + 1.6
			ReverseSteerDir = (leftScore >= rightScore) and 1 or -1
			return
		end
	else
		StuckTimer = math.max(0, StuckTimer - dt * 2)
	end

	applyDrivingInputs(throttle, brake, SmoothedSteer, dt)

	if Library.Labels.DriveStatus then
		Library.Labels.DriveStatus:SetText(string.format(
			"Status: %s | %.0f/%.0f st/s | Steer %.2f",
			mode == "Saved Route Loop" and ("Loop: " .. LoadedRouteName) or "Free-Roam",
			speed,
			desiredSpeed,
			SmoothedSteer
		))
	end
end

local function stepCollisionPrevention(veh, kin, dt)
	local minSpeed = Options.ColMinSpeed and Options.ColMinSpeed.Value or 25
	local ttcThreshold = Options.ColTTC and Options.ColTTC.Value or 0.9
	local colMode = Options.ColMode and Options.ColMode.Value or "Both (Brake + Steer)"

	local sensors = scanSensors(veh, kin, 1.0)
	local speed = kin.forwardSpeed
	if speed < minSpeed then
		-- Release only keys we might have been holding
		releaseAllDrivingKeys()
		if Library.Labels.AssistStatus then
			Library.Labels.AssistStatus:SetText("Assist: standby (below min speed)")
		end
		return false
	end

	local ttc = sensors.minForwardDist / math.max(speed, 1)
	local closeSideHazard = sensors.leftCliff or sensors.rightCliff or sensors.rays[2].dist < 10 or sensors.rays[6].dist < 10

	if ttc <= ttcThreshold or closeSideHazard then
		local avoidSteer = computeObstacleAvoidance(sensors)
		local doBrake = (colMode == "Brake Only" or colMode == "Both (Brake + Steer)") and (ttc <= ttcThreshold)
		local doSteer = (colMode == "Steer Only" or colMode == "Both (Brake + Steer)")

		local brakeAmt = doBrake and math.clamp(1.2 - (ttc / math.max(ttcThreshold, 0.1)), 0.45, 1) or 0
		local steerAmt = doSteer and avoidSteer or 0

		applyDrivingInputs(0, brakeAmt, steerAmt, dt)
		if Library.Labels.AssistStatus then
			Library.Labels.AssistStatus:SetText(string.format(
				"Assist: INTERVENING! TTC=%.2fs (%.0f st)",
				ttc,
				sensors.minForwardDist
			))
		end
		return true
	end

	releaseAllDrivingKeys()
	if Library.Labels.AssistStatus then
		Library.Labels.AssistStatus:SetText(string.format("Assist: clear (ahead %.0f st)", sensors.minForwardDist))
	end
	return false
end

local function stepCruiseControl(kin, dt)
	-- Pause if user manually holds Brake
	if UserInputService:IsKeyDown(ControlKeys.Brake) then
		setKey(ControlKeys.Throttle, false)
		return
	end
	local target = Options.CruiseSpeed and Options.CruiseSpeed.Value or 90
	local speed = kin.forwardSpeed
	if speed < target - 2 then
		local thr = math.clamp((target - speed) / 20, 0.25, 1)
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
--// Events, ESP & Vehicle QoL Helpers
--============================================================================--
local function getEventsList()
	local list = {}
	local triggers = Workspace:FindFirstChild("Proximity Triggers")
	if not triggers then return list end

	local pPos = getPlayerPos()
	for _, child in ipairs(triggers:GetChildren()) do
		local focus = child:FindFirstChild("Focus")
		local eventName = (focus and focus:GetAttribute("EventName")) or nil
		if eventName then
			local pos = focus.Position
			local dist = pPos and (pos - pPos).Magnitude or 0
			table.insert(list, { name = tostring(eventName), inst = focus, pos = pos, dist = dist, kind = "Event" })
		elseif child.Name == "Bodykits" or child.Name == "Tuner" or child.Name == "VehicleDealership" then
			if child:IsA("BasePart") then
				local dist = pPos and (child.Position - pPos).Magnitude or 0
				table.insert(list, { name = child.Name, inst = child, pos = child.Position, dist = dist, kind = "Shop" })
			end
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

local function clearEspTable(tbl)
	for i = #tbl, 1, -1 do
		pcall(function()
			tbl[i]:Destroy()
		end)
		tbl[i] = nil
	end
end

local function makeBillboard(adornee, text, color)
	local bb = Instance.new("BillboardGui")
	bb.Name = "__AllainMRTEsp"
	bb.Adornee = adornee
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(180, 36)
	bb.StudsOffset = Vector3.new(0, 6, 0)
	bb.MaxDistance = 8000

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

local function refreshEventEsp()
	clearEspTable(EventEspObjects)
	if not (Toggles.EventEsp and Toggles.EventEsp.Value) then
		return
	end
	for _, ev in ipairs(getEventsList()) do
		local col = ev.kind == "Event" and Color3.fromRGB(100, 210, 255) or Color3.fromRGB(255, 200, 90)
		local bb, lbl = makeBillboard(ev.inst, ev.name, col)
		bb:SetAttribute("BaseName", ev.name)
		table.insert(EventEspObjects, bb)
	end
end

local function refreshCarEsp()
	clearEspTable(CarEspObjects)
	if not (Toggles.CarEsp and Toggles.CarEsp.Value) then
		return
	end
	local vf = Workspace:FindFirstChild("VehiclesFolder")
	if not vf then return end
	for _, playerFolder in ipairs(vf:GetChildren()) do
		if playerFolder.Name ~= LocalPlayer.Name then
			for _, car in ipairs(playerFolder:GetChildren()) do
				if car:IsA("Model") then
					local seat = car:FindFirstChild("DriveSeat") or car.PrimaryPart
					if seat and seat:IsA("BasePart") then
						local bb = makeBillboard(seat, playerFolder.Name .. " | " .. car.Name, Color3.fromRGB(255, 130, 130))
						bb:SetAttribute("BaseName", playerFolder.Name .. " · " .. car.Name)
						table.insert(CarEspObjects, bb)
					end
				end
			end
		end
	end
end

local function enterOwnCar()
	local ownFolder = getOwnVehicleFolder()
	if not ownFolder then
		Library:Notify("No spawned car found in VehiclesFolder.", 3)
		return
	end
	for _, car in ipairs(ownFolder:GetChildren()) do
		local seat = car:FindFirstChild("DriveSeat")
		local att = seat and seat:FindFirstChild("Attachment")
		local prompt = att and att:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			if type(fireproximityprompt) == "function" then
				pcall(fireproximityprompt, prompt)
				Library:Notify("Triggered driver seat prompt for " .. car.Name, 3)
			else
				Library:Notify("Walk near your " .. car.Name .. " (fireproximityprompt unavailable).", 3)
			end
			return
		end
	end
	Library:Notify("Could not find DriveSeat prompt on your car.", 3)
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
--// Webhook Helper (Shared by Alerts & Scanner)
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
	local boundary = "----AllainMRTBoundary" .. tostring(math.random(100000, 999999))
	local payloadJson = HttpService:JSONEncode({
		content = summaryText or ("Midnight Racing: Tokyo scan (`" .. filename .. "`)"),
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

--============================================================================--
--// Scanner Helpers (Preserved from v0.1)
--============================================================================--
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
	table.insert(lines, string.format("Player: %s | Pos: %s | Yen: %s", LocalPlayer.Name, fmtVec3(getPlayerPos()), tostring(getYenValue())))
end

local function scanVehicle(lines, maxDepth)
	appendSection(lines, "CURRENT VEHICLE")
	local veh, seat = getSeatedVehicle()
	if not veh then
		table.insert(lines, "Not seated in a vehicle.")
		return
	end
	table.insert(lines, "Vehicle: " .. safeFullName(veh) .. fmtAttributes(veh))
	table.insert(lines, "Seat:    " .. safeFullName(seat))
	local tele = getAChassisTelemetry()
	if tele then
		table.insert(lines, string.format("A-Chassis: Gear=%s RPM=%s Mode=%s", tostring(tele.gear), tostring(tele.rpm), tostring(tele.transMode)))
	end
	dumpTree(lines, veh, maxDepth or 3, 350, 0)
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
	Name = "Auto-Drive",
	IconName = "navigation",
	Description = "Sensor-guided autonomous driving using real A-Chassis inputs.",
})

AutoDriveBox:AddToggle("AutoDriveEnabled", {
	Text = "Auto-Drive",
	Default = false,
	Tooltip = "Drives your seated car automatically while avoiding walls, cliffs, and other cars.",
	Callback = function(Value)
		if not Value then
			releaseAllDrivingKeys()
			StuckTimer = 0
			ReverseUntil = 0
			if Library.Labels.DriveStatus then
				Library.Labels.DriveStatus:SetText("Status: idle")
			end
		else
			refreshControlKeys()
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
	Values = { "Free-Roam (Sensors)", "Saved Route Loop" },
	Default = "Free-Roam (Sensors)",
	Tooltip = "Free-Roam uses live rays; Saved Route Loop follows a recorded loop with obstacle avoidance.",
})

AutoDriveBox:AddSlider("TargetSpeed", {
	Text = "Target Speed",
	Default = 90,
	Min = 30,
	Max = 180,
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

AutoDriveBox:AddToggle("StuckRecovery", {
	Text = "Auto Stuck / Reverse Recovery",
	Default = true,
	Tooltip = "Reverses and counter-steers automatically if blocked for 2 seconds.",
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
	Description = "Record a clean highway/touge loop, then let Auto-Drive follow it forever.",
})

RouteBox:AddInput("RouteNameInput", {
	Text = "Route Name",
	Default = "ichikawa_loop",
	Placeholder = "e.g. ichikawa_highway",
	ClearTextOnFocus = false,
})

RouteBox:AddToggle("RecordRouteToggle", {
	Text = "Record Waypoints",
	Default = false,
	Tooltip = "Drive a clean loop while enabled. Samples a point every 18 studs.",
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
--// UI: Tab 2 — Assist (Collision Prevention, Cruise Control, Auto-Shift, QoL)
--============================================================================--
local ColBox = Tabs.Assist:AddGroupbox({
	Side = "Left",
	Name = "Auto Collision Prevention",
	IconName = "shield-alert",
	Description = "Active driver assist while you drive manually.",
})

ColBox:AddToggle("CollisionPrevent", {
	Text = "Collision Prevention",
	Default = false,
	Tooltip = "Automatically brakes and/or steers away when approaching a wall, cliff, or car.",
	Callback = function(Value)
		if not Value then
			releaseAllDrivingKeys()
			if Library.Labels.AssistStatus then
				Library.Labels.AssistStatus:SetText("Assist: off")
			end
		else
			refreshControlKeys()
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
	Tooltip = "Higher = intervenes earlier before impact.",
})

ColBox:AddSlider("ColMinSpeed", {
	Text = "Minimum Active Speed",
	Default = 25,
	Min = 10,
	Max = 80,
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
	Tooltip = "Holds your target speed smoothly while you steer (pauses when you brake).",
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
	Default = 90,
	Min = 25,
	Max = 200,
	Rounding = 0,
	Suffix = " st/s",
})

QoLBox:AddDivider("Transmission")

QoLBox:AddToggle("AutoShift", {
	Text = "Auto-Shift Assist (Manual/Semi)",
	Default = false,
	Tooltip = "Taps Shift Up/Down based on A-Chassis RPM when not in Auto mode.",
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

QoLBox:AddDivider("Actions")

QoLBox:AddButton("Auto-Enter My Car", enterOwnCar):AddButton("Toggle Auto/Manual (M)", function()
	tapKey(ControlKeys.ToggleTransMode, 0.05)
end)

--============================================================================--
--// UI: Tab 3 — Events & Visuals
--============================================================================--
local EspBox = Tabs.Visuals:AddGroupbox({
	Side = "Left",
	Name = "ESP & Debug Visuals",
	IconName = "eye",
})

EspBox:AddToggle("ShowSensorRays", {
	Text = "3D Sensor Ray Visualizer",
	Default = false,
	Tooltip = "Shows Auto-Drive / Collision Prevention rays in 3D (green=clear, yellow=caution, red=hazard).",
	Callback = function(Value)
		if not Value then
			clearDebugRays()
		end
	end,
})

EspBox:AddToggle("EventEsp", {
	Text = "Race Event & Shop ESP",
	Default = false,
	Callback = function()
		refreshEventEsp()
	end,
})

EspBox:AddToggle("CarEsp", {
	Text = "Other Players' Cars ESP",
	Default = false,
	Callback = function()
		refreshCarEsp()
	end,
})

EspBox:AddButton("Refresh ESP", function()
	refreshEventEsp()
	refreshCarEsp()
	Library:Notify("ESP refreshed.", 2)
end)

local PerfBox = Tabs.Visuals:AddGroupbox({
	Side = "Right",
	Name = "Performance & Weather",
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
	Tooltip = "Stops 3D rendering for overnight AFK Yen farming.",
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

PerfBox:AddButton("Toggle Client Rain", function()
	local rem = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local toggleRain = rem and rem:FindFirstChild("ToggleRain")
	if toggleRain and toggleRain:IsA("RemoteEvent") then
		pcall(function() toggleRain:FireServer() end)
		Library:Notify("Toggled rain.", 2)
	else
		Library:Notify("ToggleRain remote not found.", 3)
	end
end)

--============================================================================--
--// UI: Tab 4 — AFK & Alerts
--============================================================================--
local YenBox = Tabs.AFK:AddGroupbox({
	Side = "Left",
	Name = "AFK Yen Farm Stats",
	IconName = "coins",
})

YenBox:AddLabel("YenStatsLabel", {
	Text = "Yen: -- | Earned: +¥0\nRate: ¥0/hr | Runtime: 0m 0s",
	DoesWrap = true,
})

YenBox:AddLabel("TelemetryLabel", {
	Text = "Vehicle: not seated",
	DoesWrap = true,
})

YenBox:AddButton("Reset Session Stats", function()
	SessionStartTime = os.clock()
	StartYen = getYenValue()
	Library:Notify("Session stats reset.", 2)
end)

YenBox:AddDivider()

YenBox:AddToggle("AntiAfk", {
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
	local curYen = getYenValue() or 0
	local earned = StartYen and (curYen - StartYen) or 0
	local elapsed = math.max(os.clock() - SessionStartTime, 1)
	local perHr = (earned / elapsed) * 3600
	local msg = string.format(
		"**MR:T Session Report** (%s)\nYen: ¥%s (+¥%s | ¥%s/hr)\nRuntime: %dm %ds",
		LocalPlayer.Name,
		formatNumber(curYen),
		formatNumber(earned),
		formatNumber(perHr),
		math.floor(elapsed / 60),
		math.floor(elapsed % 60)
	)
	local ok, res = sendWebhookText(url, msg)
	Library:Notify({ Title = ok and "Webhook Sent" or "Webhook Failed", Description = res, Time = 4 })
end)

--============================================================================--
--// UI: Tab 5 — Scanner (Kept for Future Map/Event Discovery)
--============================================================================--
local ScanBox = Tabs.Scanner:AddGroupbox({
	Side = "Left",
	Name = "Game Data Scanner",
	IconName = "search",
	Description = "Inspect vehicle/map data for new MR:T regions or updates.",
})

ScanBox:AddSlider("ScanDepth", {
	Text = "Tree Scan Depth",
	Default = 3,
	Min = 1,
	Max = 6,
	Rounding = 0,
})

ScanBox:AddButton("Vehicle & Telemetry Snapshot", function()
	task.spawn(function()
		local lines = {}
		scanHeaderAndPlayer(lines)
		scanVehicle(lines, Options.ScanDepth and Options.ScanDepth.Value or 3)
		finalizeReport("mrt_vehicle_snapshot", lines)
	end)
end)

ScanBox:AddButton("Scan Events & Triggers", function()
	task.spawn(function()
		local lines = {}
		scanHeaderAndPlayer(lines)
		appendSection(lines, "PROXIMITY TRIGGERS & EVENTS")
		for _, ev in ipairs(getEventsList()) do
			table.insert(lines, string.format("- [%s] %s | %s (%.1f st)", ev.kind, ev.name, fmtVec3(ev.pos), ev.dist))
		end
		finalizeReport("mrt_events", lines)
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
SaveManager:SetIgnoreIndexes({ "MenuKeybind", "AutoDriveEnabled", "RecordRouteToggle", "LowPower" })
ThemeManager:SetFolder("AllainHub")
SaveManager:SetFolder("AllainHub/midnight-racing-tokyo")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

--============================================================================--
--// Main Loops (Heartbeat Driving + 1s UI/ESP/AFK Updater)
--============================================================================--
StartYen = getYenValue()

-- Anti-AFK listener
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

-- Main driving / sensor loop
trackConn(Connections, RunService.Heartbeat:Connect(function(dt)
	if Unloaded then return end

	local veh, seat = getSeatedVehicle()
	local autoDrive = Toggles.AutoDriveEnabled and Toggles.AutoDriveEnabled.Value
	local colPrevent = Toggles.CollisionPrevent and Toggles.CollisionPrevent.Value
	local cruise = Toggles.CruiseEnabled and Toggles.CruiseEnabled.Value
	local showRays = Toggles.ShowSensorRays and Toggles.ShowSensorRays.Value
	local autoShift = Toggles.AutoShift and Toggles.AutoShift.Value

	if not veh or not seat then
		if autoDrive or colPrevent or cruise then
			releaseAllDrivingKeys()
		end
		if #ActiveRayVisuals > 0 then
			clearDebugRays()
		end
		return
	end

	local kin = getVehicleKinematics(veh, seat)
	if not kin then return end

	-- Route recording
	if RecordingRoute then
		local last = RecordedPoints[#RecordedPoints]
		local needSample = not last
			or ((kin.pos.X - last.x) ^ 2 + (kin.pos.Z - last.z) ^ 2) >= (18 * 18)
		if needSample then
			table.insert(RecordedPoints, {
				x = math.floor(kin.pos.X * 10) / 10,
				y = math.floor(kin.pos.Y * 10) / 10,
				z = math.floor(kin.pos.Z * 10) / 10,
				speed = math.floor(math.max(kin.forwardSpeed, 20)),
			})
			if Library.Labels.RouteStatus then
				Library.Labels.RouteStatus:SetText(string.format("Recording: %d waypoints", #RecordedPoints))
			end
		end
	end

	-- Priority: Auto-Drive > Collision Prevention > Cruise Control
	if autoDrive then
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

-- 1-second stats, ESP distance, and webhook timer loop
task.spawn(function()
	while not Unloaded do
		task.wait(1)
		if Unloaded then break end

		-- Yen & Telemetry HUD
		local curYen = getYenValue()
		if curYen then
			if not StartYen then StartYen = curYen end
			LastYen = curYen
			local earned = curYen - StartYen
			local elapsed = math.max(os.clock() - SessionStartTime, 1)
			local perHr = (earned / elapsed) * 3600
			if Library.Labels.YenStatsLabel then
				Library.Labels.YenStatsLabel:SetText(string.format(
					"Yen: ¥%s | Earned: +¥%s\nRate: ¥%s/hr | Runtime: %dm %ds",
					formatNumber(curYen),
					formatNumber(earned),
					formatNumber(perHr),
					math.floor(elapsed / 60),
					math.floor(elapsed % 60)
				))
			end

			-- Periodic webhook summary
			if Toggles.WebhookReports and Toggles.WebhookReports.Value then
				local interval = (Options.WebhookInterval and Options.WebhookInterval.Value or 15) * 60
				if os.clock() - LastWebhookReportTime >= interval then
					LastWebhookReportTime = os.clock()
					local url = Options.WebhookUrl and Options.WebhookUrl.Value or ""
					if url ~= "" then
						sendWebhookText(url, string.format(
							"**MR:T Auto-Report** (%s) | Yen: ¥%s (+¥%s | ¥%s/hr) | %dm",
							LocalPlayer.Name,
							formatNumber(curYen),
							formatNumber(earned),
							formatNumber(perHr),
							math.floor(elapsed / 60)
						))
					end
				end
			end
		end

		-- Vehicle telemetry readout
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

		-- Update ESP distance labels
		local pPos = getPlayerPos()
		if pPos then
			for _, bb in ipairs(EventEspObjects) do
				if bb and bb.Parent and bb.Adornee and bb.Adornee:IsA("BasePart") then
					local lbl = bb:FindFirstChildOfClass("TextLabel")
					if lbl then
						local d = (bb.Adornee.Position - pPos).Magnitude
						lbl.Text = string.format("%s (%.0f st)", bb:GetAttribute("BaseName") or "", d)
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
	clearEspTable(EventEspObjects)
	clearEspTable(CarEspObjects)
	if LowPowerActive then
		setLowPower(false)
	end
	if SavedLighting then
		setFpsBoost(false)
	end
	disconnectAll(Connections)
	disconnectAll(CaptureConnections)
	if env.__AllainMRTLibrary == Library then
		env.__AllainMRTLibrary = nil
	end
end)

Library:Notify({
	Title = "Allain Automation",
	Description = "Midnight Racing: Tokyo v0.2 loaded! Press RightShift to toggle menu.",
	Time = 4,
})
