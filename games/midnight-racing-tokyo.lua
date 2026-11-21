--// Allain Automation — Midnight Racing: Tokyo (Data Scanner) \\--
-- Scan-only utility to inspect game structure, vehicles, races, checkpoints,
-- remotes, UI, and live events for building Midnight Racing: Tokyo automation.
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
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local ReplicatedFirst = cloneref(game:GetService("ReplicatedFirst"))
local StarterGui = cloneref(game:GetService("StarterGui"))
local StarterPack = cloneref(game:GetService("StarterPack"))
local StarterPlayer = cloneref(game:GetService("StarterPlayer"))
local CollectionService = cloneref(game:GetService("CollectionService"))
local MarketplaceService = cloneref(game:GetService("MarketplaceService"))
local HttpService = cloneref(game:GetService("HttpService"))

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
	Footer = "Midnight Racing: Tokyo · Scanner",
	FooterLeft = "Scan Only",
	FooterRight = "v0.1",
	Username = true,
	Badge = "Beta",
	NotifySide = "Right",
	Size = UDim2.fromOffset(600, 560),
	Center = true,
	AutoShow = true,
})

local Tabs = {
	Scan = Window:AddTab("Scan", "radar"),
	Settings = Window:AddTab("Settings", "settings"),
}

--// State & Cleanup \\--
local Connections = {}
local CaptureConnections = {}
local IsCapturing = false
local CaptureEvents = {}
local CaptureStartTime = 0
local LastReportText = ""
local LastReportName = "mrt_scan.txt"
local OldNamecall = nil
local RemoteHookActive = false
local Unloaded = false

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

--// Helpers \\--
local function getRequestFunc()
	if type(request) == "function" then
		return request
	end
	if type(http_request) == "function" then
		return http_request
	end
	if type(syn) == "table" and type(syn.request) == "function" then
		return syn.request
	end
	if type(fluxus) == "table" and type(fluxus.request) == "function" then
		return fluxus.request
	end
	if type(http) == "table" and type(http.request) == "function" then
		return http.request
	end
	return nil
end

local function safeFullName(inst)
	if not inst then
		return "nil"
	end
	local ok, path = pcall(function()
		return inst:GetFullName()
	end)
	return ok and path or tostring(inst)
end

local function fmtVec3(v)
	if typeof(v) ~= "Vector3" then
		return tostring(v)
	end
	return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

local function fmtValue(v, depth)
	depth = depth or 0
	local t = typeof(v)
	if t == "Vector3" then
		return fmtVec3(v)
	elseif t == "CFrame" then
		return "CF" .. fmtVec3(v.Position)
	elseif t == "Color3" then
		return string.format("RGB(%d,%d,%d)", math.floor(v.R * 255), math.floor(v.G * 255), math.floor(v.B * 255))
	elseif t == "Instance" then
		return "<" .. v.ClassName .. ":" .. safeFullName(v) .. ">"
	elseif t == "string" then
		local clean = v:gsub("[\r\n]+", " ")
		if #clean > 120 then
			clean = clean:sub(1, 120) .. "..."
		end
		return string.format("%q", clean)
	elseif t == "table" then
		if depth >= 2 then
			return "{...}"
		end
		local parts = {}
		local count = 0
		for k, val in pairs(v) do
			count = count + 1
			if count > 8 then
				table.insert(parts, "...")
				break
			end
			table.insert(parts, tostring(k) .. "=" .. fmtValue(val, depth + 1))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

local function fmtAttributes(inst)
	local ok, attrs = pcall(function()
		return inst:GetAttributes()
	end)
	if not ok or type(attrs) ~= "table" then
		return ""
	end
	local parts = {}
	for k, v in pairs(attrs) do
		table.insert(parts, k .. "=" .. fmtValue(v, 1))
	end
	if #parts == 0 then
		return ""
	end
	table.sort(parts)
	return " [attrs: " .. table.concat(parts, ", ") .. "]"
end

local function getInstPosition(inst)
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Attachment") then
		return inst.WorldPosition
	elseif inst:IsA("Model") then
		local ok, cf = pcall(function()
			return inst:GetPivot()
		end)
		if ok and typeof(cf) == "CFrame" then
			return cf.Position
		end
	end
	local parent = inst.Parent
	if parent then
		if parent:IsA("BasePart") then
			return parent.Position
		elseif parent:IsA("Attachment") then
			return parent.WorldPosition
		elseif parent:IsA("Model") then
			local ok, cf = pcall(function()
				return parent:GetPivot()
			end)
			if ok and typeof(cf) == "CFrame" then
				return cf.Position
			end
		end
	end
	return nil
end

local function getPlayerPos()
	local char = LocalPlayer.Character
	if not char then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
	return root and root.Position or nil
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
		if cur:IsA("Model") then
			bestModel = cur
		end
		cur = cur.Parent
	end
	return bestModel or seat.Parent, seat
end

local RACE_KEYWORDS = {
	"race", "checkpoint", "check", "finish", "start", "lap", "track", "circuit",
	"touge", "highway", "drift", "time", "trial", "sprint", "event", "lobby",
	"queue", "pad", "trigger", "gate", "beacon", "marker", "waypoint", "zone",
	"dealer", "garage", "tune", "shop", "car", "vehicle", "chassis", "spawn",
	"delivery", "job", "mission", "quest", "money", "yen", "cash", "reward",
}

local function matchesKeyword(str)
	if type(str) ~= "string" then
		return false
	end
	local lower = str:lower()
	for _, kw in ipairs(RACE_KEYWORDS) do
		if lower:find(kw, 1, true) then
			return true
		end
	end
	return false
end

local function dumpTree(lines, root, maxDepth, maxLines, indent, state)
	state = state or { count = 0, truncated = false }
	if state.count >= maxLines then
		state.truncated = true
		return
	end
	local ok, children = pcall(function()
		return root:GetChildren()
	end)
	if not ok or type(children) ~= "table" then
		return
	end

	table.sort(children, function(a, b)
		if a.Name == b.Name then
			return a.ClassName < b.ClassName
		end
		return a.Name < b.Name
	end)

	local pad = string.rep("  ", indent)
	for _, child in ipairs(children) do
		if state.count >= maxLines then
			state.truncated = true
			return
		end
		state.count = state.count + 1

		local extra = ""
		if child:IsA("ValueBase") then
			local okV, val = pcall(function()
				return child.Value
			end)
			if okV then
				extra = " = " .. fmtValue(val, 1)
			end
		elseif child:IsA("ProximityPrompt") then
			extra = string.format(
				" [Action=%q Object=%q Hold=%.2f Dist=%.1f]",
				child.ActionText,
				child.ObjectText,
				child.HoldDuration,
				child.MaxActivationDistance
			)
		elseif child:IsA("VehicleSeat") then
			extra = string.format(
				" [MaxSpeed=%.1f Torque=%.1f Turn=%.2f]",
				child.MaxSpeed,
				child.Torque,
				child.TurnSpeed
			)
		end

		local grandOk, grandChildren = pcall(function()
			return child:GetChildren()
		end)
		local grandCount = (grandOk and type(grandChildren) == "table") and #grandChildren or 0
		local countTag = grandCount > 0 and (" (" .. grandCount .. " children)") or ""

		table.insert(lines, string.format("%s- %s [%s]%s%s%s", pad, child.Name, child.ClassName, countTag, extra, fmtAttributes(child)))

		if grandCount > 0 and indent < maxDepth then
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

--// Scanner Sections \\--
local function scanHeaderAndPlayer(lines)
	appendSection(lines, "GAME & LOCAL PLAYER")
	local okInfo, info = pcall(function()
		return MarketplaceService:GetProductInfo(game.PlaceId)
	end)
	local placeName = (okInfo and type(info) == "table" and info.Name) or "unknown"

	table.insert(lines, string.format("Timestamp:    %s", os.date("%Y-%m-%d %H:%M:%S")))
	table.insert(lines, string.format("PlaceName:    %s", tostring(placeName)))
	table.insert(lines, string.format("GameId:       %d", game.GameId))
	table.insert(lines, string.format("PlaceId:      %d", game.PlaceId))
	table.insert(lines, string.format("PlaceVersion: %d", game.PlaceVersion))
	table.insert(lines, string.format("JobId:        %s", tostring(game.JobId)))
	table.insert(lines, string.format("Player:       %s (UserId %d)", LocalPlayer.Name, LocalPlayer.UserId))
	table.insert(lines, string.format("Team:         %s", LocalPlayer.Team and LocalPlayer.Team.Name or "none"))
	table.insert(lines, string.format("PlayerPos:    %s", fmtVec3(getPlayerPos())))
	table.insert(lines, "PlayerAttrs: " .. (fmtAttributes(LocalPlayer) ~= "" and fmtAttributes(LocalPlayer) or " none"))

	table.insert(lines, "")
	table.insert(lines, "-- LocalPlayer children (leaderstats / data folders) --")
	for _, child in ipairs(LocalPlayer:GetChildren()) do
		if child.Name ~= "PlayerGui" and child.Name ~= "PlayerScripts" and child.Name ~= "Backpack" and child.Name ~= "StarterGear" then
			table.insert(lines, string.format("- %s [%s]%s", child.Name, child.ClassName, fmtAttributes(child)))
			if child:IsA("Folder") or child:IsA("Configuration") or child:IsA("Model") then
				dumpTree(lines, child, 3, 200, 1)
			elseif child:IsA("ValueBase") then
				local okV, val = pcall(function() return child.Value end)
				if okV then
					lines[#lines] = lines[#lines] .. " = " .. fmtValue(val, 1)
				end
			end
		end
	end
end

local function scanVehicle(lines, maxDepth)
	appendSection(lines, "CURRENT VEHICLE & SEATED STATE")
	local veh, seat = getSeatedVehicle()
	if not veh then
		table.insert(lines, "Player is NOT currently seated in a vehicle.")
	else
		table.insert(lines, "Vehicle: " .. safeFullName(veh) .. " [" .. veh.ClassName .. "]" .. fmtAttributes(veh))
		if seat then
			table.insert(lines, "Seat:    " .. safeFullName(seat) .. " [" .. seat.ClassName .. "]" .. fmtAttributes(seat))
			if seat:IsA("VehicleSeat") then
				table.insert(lines, string.format(
					"SeatPhysics: MaxSpeed=%.1f Torque=%.1f TurnSpeed=%.2f Throttle=%.2f Steer=%.2f Speed=%.1f",
					seat.MaxSpeed, seat.Torque, seat.TurnSpeed, seat.ThrottleFloat, seat.SteerFloat,
					seat.AssemblyLinearVelocity.Magnitude
				))
			end
		end
		if veh:IsA("Model") then
			table.insert(lines, "PrimaryPart: " .. (veh.PrimaryPart and veh.PrimaryPart.Name or "none"))
			local okP, cf = pcall(function() return veh:GetPivot() end)
			if okP then
				table.insert(lines, "PivotPos:    " .. fmtVec3(cf.Position))
			end
		end
		table.insert(lines, "")
		table.insert(lines, "-- Vehicle Hierarchy --")
		local st = { count = 0, truncated = false }
		dumpTree(lines, veh, maxDepth or 3, 350, 0, st)
		if st.truncated then
			table.insert(lines, "  ... (truncated at 350 lines)")
		end
	end

	-- Also check for vehicle containers in Workspace
	table.insert(lines, "")
	table.insert(lines, "-- Workspace Vehicle/Car Containers --")
	local foundVehFolder = false
	for _, child in ipairs(Workspace:GetChildren()) do
		local n = child.Name:lower()
		if n:find("veh", 1, true) or n:find("car", 1, true) or n:find("chassis", 1, true) then
			foundVehFolder = true
			local kids = child:GetChildren()
			table.insert(lines, string.format("- %s [%s] (%d children)%s", child.Name, child.ClassName, #kids, fmtAttributes(child)))
			for i = 1, math.min(#kids, 25) do
				local k = kids[i]
				table.insert(lines, string.format("    * %s [%s]%s", k.Name, k.ClassName, fmtAttributes(k)))
			end
			if #kids > 25 then
				table.insert(lines, string.format("    ... (+%d more)", #kids - 25))
			end
		end
	end
	if not foundVehFolder then
		table.insert(lines, "(No top-level Workspace folder matched veh/car/chassis)")
	end
end

local function scanWorkspaceOverview(lines, maxDepth)
	appendSection(lines, "WORKSPACE TOP-LEVEL & RACE/TRACK OBJECTS")
	local top = Workspace:GetChildren()
	table.sort(top, function(a, b) return a.Name < b.Name end)
	table.insert(lines, string.format("Top-level children (%d):", #top))
	for _, child in ipairs(top) do
		local kids = child:GetChildren()
		table.insert(lines, string.format("- %s [%s] (%d children)%s", child.Name, child.ClassName, #kids, fmtAttributes(child)))
	end

	table.insert(lines, "")
	table.insert(lines, "-- Keyword-Matched Workspace Trees (race/checkpoint/track/dealer/garage/etc.) --")
	local state = { count = 0, truncated = false }
	for _, child in ipairs(top) do
		if matchesKeyword(child.Name) and not Players:FindFirstChild(child.Name) then
			table.insert(lines, string.format("\n[%s] (%s):", child.Name, child.ClassName))
			dumpTree(lines, child, maxDepth or 3, 500, 1, state)
			if state.truncated then
				table.insert(lines, "  ... (workspace keyword dump cap reached)")
				break
			end
		end
	end
end

local function scanPromptsAndTriggers(lines, maxDist)
	appendSection(lines, "PROXIMITY PROMPTS, CLICK DETECTORS & RACE TRIGGERS")
	local pPos = getPlayerPos()
	local prompts = {}
	local clicks = {}
	local touchParts = {}

	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			local pos = getInstPosition(desc)
			local dist = (pPos and pos) and (pos - pPos).Magnitude or math.huge
			if not maxDist or dist <= maxDist then
				table.insert(prompts, { inst = desc, pos = pos, dist = dist })
			end
		elseif desc:IsA("ClickDetector") then
			local pos = getInstPosition(desc)
			local dist = (pPos and pos) and (pos - pPos).Magnitude or math.huge
			if not maxDist or dist <= maxDist then
				table.insert(clicks, { inst = desc, pos = pos, dist = dist })
			end
		elseif desc:IsA("TouchTransmitter") and desc.Parent and desc.Parent:IsA("BasePart") then
			local part = desc.Parent
			if matchesKeyword(part.Name) or (part.Parent and matchesKeyword(part.Parent.Name)) then
				local pos = part.Position
				local dist = pPos and (pos - pPos).Magnitude or math.huge
				if not maxDist or dist <= maxDist then
					table.insert(touchParts, { inst = part, pos = pos, dist = dist })
				end
			end
		end
	end

	table.sort(prompts, function(a, b) return a.dist < b.dist end)
	table.sort(clicks, function(a, b) return a.dist < b.dist end)
	table.sort(touchParts, function(a, b) return a.dist < b.dist end)

	table.insert(lines, string.format("ProximityPrompts found: %d", #prompts))
	for i = 1, math.min(#prompts, 120) do
		local item = prompts[i]
		local p = item.inst
		local distStr = item.dist < math.huge and string.format("%.1f studs", item.dist) or "?"
		table.insert(lines, string.format(
			"  [%d] %s | Action=%q Object=%q Hold=%.2f Enabled=%s | %s (%s)",
			i, safeFullName(p), p.ActionText, p.ObjectText, p.HoldDuration, tostring(p.Enabled), fmtVec3(item.pos), distStr
		))
	end

	table.insert(lines, "")
	table.insert(lines, string.format("ClickDetectors found: %d", #clicks))
	for i = 1, math.min(#clicks, 60) do
		local item = clicks[i]
		local distStr = item.dist < math.huge and string.format("%.1f studs", item.dist) or "?"
		table.insert(lines, string.format("  [%d] %s | %s (%s)", i, safeFullName(item.inst), fmtVec3(item.pos), distStr))
	end

	table.insert(lines, "")
	table.insert(lines, string.format("Keyword-matched TouchTransmitter parts found: %d", #touchParts))
	for i = 1, math.min(#touchParts, 120) do
		local item = touchParts[i]
		local distStr = item.dist < math.huge and string.format("%.1f studs", item.dist) or "?"
		table.insert(lines, string.format(
			"  [%d] %s | Size=%s | %s (%s)%s",
			i, safeFullName(item.inst), fmtVec3(item.inst.Size), fmtVec3(item.pos), distStr, fmtAttributes(item.inst)
		))
	end
end

local function scanRemotes(lines)
	appendSection(lines, "REMOTES & BINDABLES")
	local containers = {
		{ name = "ReplicatedStorage", inst = ReplicatedStorage },
		{ name = "ReplicatedFirst", inst = ReplicatedFirst },
		{ name = "Workspace", inst = Workspace },
		{ name = "StarterGui", inst = StarterGui },
		{ name = "StarterPack", inst = StarterPack },
		{ name = "StarterPlayer", inst = StarterPlayer },
		{ name = "LocalPlayer", inst = LocalPlayer },
	}

	local total = 0
	for _, entry in ipairs(containers) do
		local found = {}
		local ok, descs = pcall(function()
			return entry.inst:GetDescendants()
		end)
		if ok and type(descs) == "table" then
			for _, d in ipairs(descs) do
				if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent")
					or d:IsA("BindableEvent") or d:IsA("BindableFunction") then
					table.insert(found, string.format("  [%s] %s", d.ClassName, safeFullName(d)))
				end
			end
		end
		if #found > 0 then
			table.sort(found)
			total = total + #found
			table.insert(lines, string.format("-- %s (%d) --", entry.name, #found))
			for _, line in ipairs(found) do
				table.insert(lines, line)
			end
		end
	end
	table.insert(lines, string.format("Total remotes/bindables: %d", total))
end

local function scanReplicatedStorage(lines, maxDepth)
	appendSection(lines, "REPLICATED STORAGE TREE")
	local state = { count = 0, truncated = false }
	dumpTree(lines, ReplicatedStorage, maxDepth or 4, 800, 0, state)
	if state.truncated then
		table.insert(lines, "... (truncated at 800 lines)")
	end
end

local function scanPlayerGui(lines)
	appendSection(lines, "PLAYER GUI (SCREENGUIS & VISIBLE TEXT)")
	local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pgui then
		table.insert(lines, "PlayerGui not found.")
		return
	end
	local guis = pgui:GetChildren()
	table.sort(guis, function(a, b) return a.Name < b.Name end)
	for _, gui in ipairs(guis) do
		if gui:IsA("ScreenGui") then
			table.insert(lines, string.format("- %s [Enabled=%s, Children=%d]", gui.Name, tostring(gui.Enabled), #gui:GetChildren()))
			if gui.Enabled then
				local texts = {}
				for _, d in ipairs(gui:GetDescendants()) do
					if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
						local txt = (d.Text or ""):gsub("[\r\n]+", " "):match("^%s*(.-)%s*$")
						if txt ~= "" and #texts < 40 then
							table.insert(texts, string.format("    [%s] %s = %q", d.ClassName, d.Name, txt:sub(1, 100)))
						end
					end
				end
				for _, t in ipairs(texts) do
					table.insert(lines, t)
				end
			end
		else
			table.insert(lines, string.format("- %s [%s]", gui.Name, gui.ClassName))
		end
	end
end

local function scanCollectionTags(lines)
	appendSection(lines, "COLLECTION SERVICE TAGS")
	local ok, tags = pcall(function()
		return CollectionService:GetAllTags()
	end)
	if not ok or type(tags) ~= "table" then
		table.insert(lines, "(CollectionService:GetAllTags unavailable)")
		return
	end
	table.sort(tags)
	table.insert(lines, string.format("Tags (%d):", #tags))
	for _, tag in ipairs(tags) do
		local okT, tagged = pcall(function()
			return CollectionService:GetTagged(tag)
		end)
		local count = (okT and type(tagged) == "table") and #tagged or 0
		local sample = (count > 0) and safeFullName(tagged[1]) or "none"
		table.insert(lines, string.format("  - %s (%d) | sample: %s", tag, count, sample))
	end
end

--// Export Helpers \\--
local function saveReportToFile(filename, content)
	if type(writefile) ~= "function" then
		return false, "writefile not available on this executor"
	end
	pcall(function()
		if type(isfolder) == "function" and type(makefolder) == "function" then
			if not isfolder("AllainHub") then makefolder("AllainHub") end
			if not isfolder("AllainHub/scans") then makefolder("AllainHub/scans") end
		end
	end)
	local path = "AllainHub/scans/" .. filename
	local ok, err = pcall(writefile, path, content)
	if not ok then
		return false, tostring(err)
	end
	return true, path
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
		Headers = {
			["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
		},
		Body = table.concat(bodyParts),
	})
	if not ok then
		return false, tostring(res)
	end
	local status = type(res) == "table" and (res.StatusCode or res.Status) or nil
	if status and (status < 200 or status >= 300) then
		return false, "HTTP " .. tostring(status)
	end
	return true, "Sent (" .. tostring(status or "OK") .. ")"
end

local function updateStatus(msg)
	if Library.Labels and Library.Labels.ScanStatus then
		Library.Labels.ScanStatus:SetText("Status: " .. msg)
	end
end

local function finalizeReport(prefix, lines)
	local content = table.concat(lines, "\n")
	local stamp = os.date("%Y%m%d_%H%M%S")
	local filename = string.format("%s_%s.txt", prefix, stamp)
	LastReportText = content
	LastReportName = filename

	local kb = #content / 1024
	local statusParts = { string.format("%d lines (%.1f KB)", #lines, kb) }

	local savedOk, savedInfo = saveReportToFile(filename, content)
	if savedOk then
		table.insert(statusParts, "saved: " .. savedInfo)
	end

	if Toggles.AutoSendWebhook and Toggles.AutoSendWebhook.Value then
		local url = Options.WebhookUrl and Options.WebhookUrl.Value or ""
		if url ~= "" then
			local whOk, whMsg = sendReportToWebhook(
				url,
				filename,
				content,
				string.format("**Midnight Racing: Tokyo** — `%s` (%d lines, %.1f KB)", filename, #lines, kb)
			)
			table.insert(statusParts, whOk and "webhook sent" or ("webhook err: " .. whMsg))
		end
	end

	local summary = table.concat(statusParts, " | ")
	updateStatus(summary)
	Library:Notify({
		Title = "Scan Complete",
		Description = summary,
		Time = 5,
	})
end

--// Live Capture \\--
local function logCapture(tag, msg)
	if not IsCapturing then
		return
	end
	local dt = os.clock() - CaptureStartTime
	table.insert(CaptureEvents, string.format("[+%06.2fs] [%s] %s", dt, tag, msg))
	if Library.Labels and Library.Labels.CaptureStatus then
		Library.Labels.CaptureStatus:SetText(string.format("Capture: RECORDING (%d events)", #CaptureEvents))
	end
end

local function stopRemoteHook()
	if RemoteHookActive and OldNamecall and type(hookmetamethod) == "function" then
		pcall(function()
			hookmetamethod(game, "__namecall", OldNamecall)
		end)
	end
	RemoteHookActive = false
	OldNamecall = nil
end

local function startRemoteHook()
	if RemoteHookActive then
		return
	end
	if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
		logCapture("WARN", "Remote hook unavailable (executor lacks hookmetamethod/getnamecallmethod)")
		return
	end
	local ok = pcall(function()
		OldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
			local method = getnamecallmethod()
			if IsCapturing and not Unloaded and (method == "FireServer" or method == "InvokeServer") then
				if typeof(self) == "Instance" and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction") or self:IsA("UnreliableRemoteEvent")) then
					local args = { ... }
					local argStrs = {}
					for i = 1, math.min(#args, 6) do
						argStrs[i] = fmtValue(args[i], 1)
					end
					if #args > 6 then
						table.insert(argStrs, "...(" .. #args .. " args)")
					end
					logCapture("REMOTE", string.format("%s:%s(%s)", safeFullName(self), method, table.concat(argStrs, ", ")))
				end
			end
			return OldNamecall(self, ...)
		end)
	end)
	if ok and OldNamecall then
		RemoteHookActive = true
		logCapture("INFO", "Outgoing remote hook active")
	end
end

local function stopLiveCapture(exportNow)
	if not IsCapturing then
		return
	end
	IsCapturing = false
	disconnectAll(CaptureConnections)
	stopRemoteHook()

	if Library.Labels and Library.Labels.CaptureStatus then
		Library.Labels.CaptureStatus:SetText(string.format("Capture: stopped (%d events)", #CaptureEvents))
	end

	if exportNow then
		local lines = {}
		scanHeaderAndPlayer(lines)
		appendSection(lines, string.format("LIVE CAPTURE LOG (%d events)", #CaptureEvents))
		for _, ev in ipairs(CaptureEvents) do
			table.insert(lines, ev)
		end
		finalizeReport("mrt_live_capture", lines)
	end
end

local function startLiveCapture()
	if IsCapturing then
		return
	end
	CaptureEvents = {}
	CaptureStartTime = os.clock()
	IsCapturing = true
	logCapture("START", "Live capture started at pos " .. fmtVec3(getPlayerPos()))

	-- Watch seat changes
	local function bindChar(char)
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		if hum then
			trackConn(CaptureConnections, hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
				local seat = hum.SeatPart
				if seat then
					local veh = getSeatedVehicle()
					logCapture("SEAT", "Entered " .. safeFullName(seat) .. " | Vehicle=" .. safeFullName(veh))
				else
					logCapture("SEAT", "Exited seat at " .. fmtVec3(getPlayerPos()))
				end
			end))
		end
	end
	bindChar(LocalPlayer.Character)
	trackConn(CaptureConnections, LocalPlayer.CharacterAdded:Connect(bindChar))

	-- Watch Workspace keyword objects added/removed (checkpoints, race markers, vehicles)
	trackConn(CaptureConnections, Workspace.DescendantAdded:Connect(function(inst)
		if matchesKeyword(inst.Name) or inst:IsA("ProximityPrompt") then
			local pos = getInstPosition(inst)
			logCapture("WS+", string.format("%s [%s] %s", safeFullName(inst), inst.ClassName, pos and fmtVec3(pos) or ""))
		end
	end))
	trackConn(CaptureConnections, Workspace.DescendantRemoving:Connect(function(inst)
		if matchesKeyword(inst.Name) or inst:IsA("ProximityPrompt") then
			logCapture("WS-", string.format("%s [%s]", safeFullName(inst), inst.ClassName))
		end
	end))

	-- Watch PlayerGui ScreenGui toggles
	local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pgui then
		local function watchGui(gui)
			if not gui:IsA("ScreenGui") then return end
			trackConn(CaptureConnections, gui:GetPropertyChangedSignal("Enabled"):Connect(function()
				logCapture("GUI", string.format("%s Enabled=%s", gui.Name, tostring(gui.Enabled)))
			end))
		end
		for _, g in ipairs(pgui:GetChildren()) do
			watchGui(g)
		end
		trackConn(CaptureConnections, pgui.ChildAdded:Connect(function(g)
			logCapture("GUI+", g.Name .. " [" .. g.ClassName .. "]")
			watchGui(g)
		end))
	end

	-- Watch LocalPlayer ValueBase & attribute changes (currency/XP/stats)
	trackConn(CaptureConnections, LocalPlayer.AttributeChanged:Connect(function(attr)
		logCapture("ATTR", attr .. " = " .. fmtValue(LocalPlayer:GetAttribute(attr), 1))
	end))
	local ls = LocalPlayer:FindFirstChild("leaderstats")
	for _, desc in ipairs(LocalPlayer:GetDescendants()) do
		if desc:IsA("ValueBase") and (not pgui or not desc:IsDescendantOf(pgui)) and (not ls or not desc:IsDescendantOf(ls)) then
			trackConn(CaptureConnections, desc.Changed:Connect(function(newVal)
				logCapture("STAT", safeFullName(desc) .. " = " .. fmtValue(newVal, 1))
			end))
		end
	end
	if ls then
		for _, stat in ipairs(ls:GetChildren()) do
			if stat:IsA("ValueBase") then
				trackConn(CaptureConnections, stat.Changed:Connect(function(newVal)
					logCapture("LEADERSTAT", stat.Name .. " = " .. fmtValue(newVal, 1))
				end))
			end
		end
	end

	-- Optional outgoing remote hook
	if Toggles.CaptureRemotes and Toggles.CaptureRemotes.Value then
		startRemoteHook()
	end

	-- Optional position breadcrumbs while moving
	task.spawn(function()
		local lastPos = getPlayerPos()
		while IsCapturing and not Unloaded do
			task.wait(1.5)
			if not IsCapturing or Unloaded then break end
			if Toggles.CaptureBreadcrumbs and Toggles.CaptureBreadcrumbs.Value then
				local pos = getPlayerPos()
				if pos and (not lastPos or (pos - lastPos).Magnitude >= 25) then
					local _, seat = getSeatedVehicle()
					local speed = (seat and seat:IsA("BasePart")) and seat.AssemblyLinearVelocity.Magnitude or 0
					logCapture("POS", string.format("%s | speed=%.1f", fmtVec3(pos), speed))
					lastPos = pos
				end
			end
		end
	end)

	Library:Notify({
		Title = "Live Capture",
		Description = "Recording started. Drive, start a race, hit checkpoints, then stop to export.",
		Time = 4,
	})
end

--// UI: Scan Tab \\--
local ScanBox = Tabs.Scan:AddGroupbox({
	Side = "Left",
	Name = "Game Data Scan",
	IconName = "search",
	Description = "Inspect Midnight Racing: Tokyo structure, vehicles, races, prompts & remotes.",
})

ScanBox:AddSlider("ScanDepth", {
	Text = "Tree Scan Depth",
	Default = 3,
	Min = 1,
	Max = 6,
	Rounding = 0,
	Tooltip = "How deep to traverse Workspace/ReplicatedStorage/Vehicle trees.",
})

ScanBox:AddButton({
	Text = "Run Full Game Scan",
	Tooltip = "Scans player, vehicle, Workspace, prompts, triggers, remotes, ReplicatedStorage, UI, and tags.",
	Func = function()
		updateStatus("running full scan...")
		task.spawn(function()
			local depth = Options.ScanDepth and Options.ScanDepth.Value or 3
			local lines = {}
			scanHeaderAndPlayer(lines)
			scanVehicle(lines, depth)
			scanWorkspaceOverview(lines, depth)
			scanPromptsAndTriggers(lines, nil)
			scanRemotes(lines)
			scanReplicatedStorage(lines, math.max(depth, 4))
			scanPlayerGui(lines)
			scanCollectionTags(lines)
			finalizeReport("mrt_full_scan", lines)
		end)
	end,
})

ScanBox:AddButton({
	Text = "Quick Vehicle & Race Snapshot",
	Tooltip = "Fast snapshot of your current vehicle, nearby prompts/triggers (250 studs), and active UI.",
	Func = function()
		updateStatus("running vehicle/race snapshot...")
		task.spawn(function()
			local depth = Options.ScanDepth and Options.ScanDepth.Value or 3
			local lines = {}
			scanHeaderAndPlayer(lines)
			scanVehicle(lines, math.max(depth, 4))
			scanPromptsAndTriggers(lines, 250)
			scanPlayerGui(lines)
			finalizeReport("mrt_vehicle_snapshot", lines)
		end)
	end,
})

ScanBox:AddButton({
	Text = "Scan Remotes Only",
	Tooltip = "Dumps all RemoteEvents, RemoteFunctions, and Bindables across the game.",
	Func = function()
		updateStatus("scanning remotes...")
		task.spawn(function()
			local lines = {}
			scanHeaderAndPlayer(lines)
			scanRemotes(lines)
			finalizeReport("mrt_remotes", lines)
		end)
	end,
})

ScanBox:AddDivider()

ScanBox:AddLabel("ScanStatus", {
	Text = "Status: idle",
	DoesWrap = true,
})

--// UI: Live Capture \\--
local CaptureBox = Tabs.Scan:AddGroupbox({
	Side = "Left",
	Name = "Live Capture",
	IconName = "radio",
	Description = "Record seats, race checkpoints, GUI changes, stats, and optional remotes while playing.",
})

CaptureBox:AddToggle("LiveCaptureToggle", {
	Text = "Live Capture Recording",
	Default = false,
	Tooltip = "Turn on, do actions in-game (enter car, start race, pass checkpoints), then turn off to export.",
	Callback = function(Value)
		if Value then
			startLiveCapture()
		else
			stopLiveCapture(true)
		end
	end,
})

CaptureBox:AddToggle("CaptureBreadcrumbs", {
	Text = "Record Position Breadcrumbs",
	Default = true,
	Tooltip = "Logs your coordinates & speed every ~25 studs moved.",
})

CaptureBox:AddToggle("CaptureRemotes", {
	Text = "Capture Outgoing Remotes (Hook)",
	Default = false,
	Risky = true,
	Tooltip = "Hooks FireServer/InvokeServer during Live Capture (requires hookmetamethod).",
})

CaptureBox:AddLabel("CaptureStatus", {
	Text = "Capture: idle",
	DoesWrap = true,
})

--// UI: Export & Webhook \\--
local ExportBox = Tabs.Scan:AddGroupbox({
	Side = "Right",
	Name = "Export & Webhook",
	IconName = "send",
	Description = "Save locally, copy to clipboard, or upload scan .txt files to Discord.",
})

ExportBox:AddInput("WebhookUrl", {
	Text = "Discord Webhook URL",
	Placeholder = "https://discord.com/api/webhooks/...",
	ClearTextOnFocus = false,
	Finished = false,
})

ExportBox:AddToggle("AutoSendWebhook", {
	Text = "Auto-Send Scans to Webhook",
	Default = false,
	Tooltip = "Automatically uploads each completed scan/capture .txt to the webhook above.",
})

ExportBox:AddButton({
	Text = "Send Last Scan to Webhook",
	Func = function()
		if LastReportText == "" then
			Library:Notify("Run a scan first.", 3)
			return
		end
		local url = Options.WebhookUrl and Options.WebhookUrl.Value or ""
		local ok, msg = sendReportToWebhook(url, LastReportName, LastReportText)
		Library:Notify({
			Title = ok and "Webhook Sent" or "Webhook Failed",
			Description = msg,
			Time = 4,
		})
	end,
})

ExportBox:AddButton({
	Text = "Copy Last Scan to Clipboard",
	Func = function()
		if LastReportText == "" then
			Library:Notify("Run a scan first.", 3)
			return
		end
		if type(setclipboard) ~= "function" then
			Library:Notify("setclipboard is not available on this executor.", 3)
			return
		end
		setclipboard(LastReportText)
		Library:Notify(string.format("Copied %s (%.1f KB) to clipboard.", LastReportName, #LastReportText / 1024), 4)
	end,
})

ExportBox:AddDivider()
ExportBox:AddLabel(
	"Scans are automatically saved to AllainHub/scans/ in your executor workspace folder when writefile is available.",
	true
)

--// UI: Settings Tab \\--
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
SaveManager:SetIgnoreIndexes({ "MenuKeybind", "LiveCaptureToggle" })

ThemeManager:SetFolder("AllainHub")
SaveManager:SetFolder("AllainHub/midnight-racing-tokyo")

SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

Library:OnUnload(function()
	Unloaded = true
	stopLiveCapture(false)
	disconnectAll(Connections)
	if env.__AllainMRTLibrary == Library then
		env.__AllainMRTLibrary = nil
	end
end)

Library:Notify({
	Title = "Allain Automation",
	Description = "Midnight Racing: Tokyo scanner loaded. Press RightShift to toggle menu.",
	Time = 4,
})
