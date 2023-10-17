function widget:GetInfo()
	return {
		name = "Top Bar 2",
		desc = "Shows Resources, wind speed, commander counter, and various options. RmlUi edition",
		author = "Floris & lov",
		date = "2023",
		license = "GNU GPL, v2 or later",
		layer = 0,
		handler = true,
		enabled = true
	}
end

local spGetSpectatingState = Spring.GetSpectatingState
local spGetTeamResources = Spring.GetTeamResources
local spGetMyTeamID = Spring.GetMyTeamID
local spGetMouseState = Spring.GetMouseState
local spGetWind = Spring.GetWind
local floor = math.floor
local sformat = string.format

local windMax = Game.windMax
local document
local context
local dm
local widgetList = {
}

local function togglewidget(ev, i)
	Spring.Echo("toggle", i, ev.type)
	widgetHandler:ToggleWidget(widgetList[i].name)
	local order = widgetHandler.orderList[widgetList[i].name]
	local enabled = (order and (order > 0)) == true
	widgetList[i].enabled = enabled
	widgetList[i].active = not widgetList[i].active
	-- ev.target_element:SetClass("enabled", widgetList[i].enabled)
end


local dataModel = {
	resources = {
		energy = {
			current = 0,
			storage = 0,
			pull = 0,
			income = 0,
			expense = 0
		},
		metal = {
			current = 0,
			storage = 0,
			pull = 0,
			income = 0,
			expense = 0
		},
		wind = {
			min = Game.windMin,
			max = windMax,
			current = 0
		},
		tidal = {
			current = Game.tidal
		}
	}
}

function widget:filterList(ev, elm)
	local inputText = elm:GetAttribute("value")
	local i
	Spring.Echo(inputText)
	for i = 1, #widgetList do
		local w = widgetList[i]
		local data = w.data
		w.filtered = not ((not inputText or inputText == '') or
			(data.name and string.find(string.lower(data.name), string.lower(inputText), nil, true) or
				(data.desc and string.find(string.lower(data.desc), string.lower(inputText), nil, true)) or
				(data.basename and string.find(string.lower(data.basename), string.lower(inputText), nil, true)) or
				(data.author and string.find(string.lower(data.author), string.lower(inputText), nil, true))))
	end
	dm:__SetDirty("widgets")
end

function widget:toggleWidget(index)
	Spring.Echo("toggle", index)
end

local myAllyTeamID
local myAllyTeamList
local myTeamID
local myPlayerID

local function checkSelfStatus()
	myAllyTeamID = Spring.GetMyAllyTeamID()
	myAllyTeamList = Spring.GetTeamList(myAllyTeamID)
	myTeamID = Spring.GetMyTeamID()
	myPlayerID = Spring.GetMyPlayerID()
	-- if myTeamID ~= gaiaTeamID and UnitDefs[Spring.GetTeamRulesParam(myTeamID, 'startUnit')] then
	-- 	comTexture = ':n:Icons/' .. UnitDefs[Spring.GetTeamRulesParam(myTeamID, 'startUnit')].name .. '.png'
	-- end
end
local metalbar
local energybar
local mmSlider
local blades
function widget:Initialize()
	checkSelfStatus()
	context = rmlui.GetContext("overlay")

	dm = context:OpenDataModel("data", dataModel)


	Spring.Echo("TESTDOCUMENT", document)
	local widgetsList = {}

	-- addWidgets()
	document = context:LoadDocument("luaui/rml/gui_top_bar2.rml", widget)
	metalbar = document:GetElementById("metalstorage")
	energybar = document:GetElementById("energystorage")
	mmSlider = document:GetElementById("energy")
	blades = document:GetElementById("blades")
	document:Show()
end

function widget:GameFrame(f)
	-- elem.inner_rml = "" .. f
end

function widget:Shutdown()
	if document then
		document:Close()
	end
	context:RemoveDataModel("data")
end

function widget:buttonPress(str)
	Spring.Echo("widgetbuttonpress", str)
end

function widget:adjustConversion(element, event)
	-- Spring.Echo("adjusting", event.parameters.value)
	local convValue = event.parameters.value
	Spring.SendLuaRulesMsg(sformat(string.char(137) .. '%i', convValue))
end

local function short(n, f)
	if f == nil then
		f = 0
	end
	if n > 9999999 then
		return sformat("%." .. f .. "fm", n / 1000000)
	elseif n > 9999 then
		return sformat("%." .. f .. "fk", n / 1000)
	else
		return sformat("%." .. f .. "f", n)
	end
end

local sec = 0
local sec2 = 0
local windspeed = 0
local bladerotation = 0
local lastbladetime = 0
function widget:Update(dt)
	local prevMyTeamID = myTeamID
	if spec and spGetMyTeamID() ~= prevMyTeamID then
		-- check if the team that we are spectating changed
		checkSelfStatus()
		init()
	end

	local mx, my = spGetMouseState()
	local speedFactor, _, isPaused = Spring.GetGameSpeed()
	-- if not isPaused then
	-- 	if blinkDirection then
	-- 		blinkProgress = blinkProgress + (dt * 9)
	-- 		if blinkProgress > 1 then
	-- 			blinkProgress = 1
	-- 			blinkDirection = false
	-- 		end
	-- 	else
	-- 		blinkProgress = blinkProgress - (dt / (blinkProgress * 1.5))
	-- 		if blinkProgress < 0 then
	-- 			blinkProgress = 0
	-- 			blinkDirection = true
	-- 		end
	-- 	end
	-- end

	-- now = os.clock()
	-- if now > nextGuishaderCheck and widgetHandler.orderList["GUI Shader"] ~= nil then
	-- 	nextGuishaderCheck = now + guishaderCheckUpdateRate
	-- 	if guishaderEnabled == false and widgetHandler.orderList["GUI Shader"] ~= 0 then
	-- 		guishaderEnabled = true
	-- 		init()
	-- 	elseif guishaderEnabled and (widgetHandler.orderList["GUI Shader"] == 0) then
	-- 		guishaderEnabled = false
	-- 	end
	-- end

	sec = sec + dt
	if sec > 0.033 then
		sec = 0
		local currentLevel, storage, pull, income, expense, share, sent, received = spGetTeamResources(myTeamID, 'metal')
		dm.resources.metal = {
			current = short(currentLevel),
			storage = short(storage),
			pull = short(pull),
			income = short(income),
			expense = short(expense)
		}
		metalbar:SetAttribute("max", "" .. storage)
		metalbar:SetAttribute("value", "" .. currentLevel)
		currentLevel, storage, pull, income, expense, share, sent, received = spGetTeamResources(myTeamID, 'energy')
		dm.resources.energy = {
			current = short(currentLevel),
			storage = short(storage),
			pull = short(pull),
			income = short(income),
			expense = short(expense)
		}
		energybar:SetAttribute("max", "" .. storage)
		energybar:SetAttribute("value", "" .. currentLevel)

		local mmLevel = Spring.GetTeamRulesParam(myTeamID, 'mmLevel')
		mmSlider:SetAttribute("value", "" .. (mmLevel * 100))

		windspeed                 = select(4, spGetWind())
		dm.resources.wind.current = sformat('%.1f', windspeed)
		-- windspeed                 = 19
		-- bladerotation             = (bladerotation + windspeed / 4) % 360
		-- blades.style.transform    = "rotate(" .. bladerotation .. "deg)";

		dm:__SetDirty("resources")
	end

	sec2 = sec2 + dt
	if sec2 >= lastbladetime then
		lastbladetime = floor((1 - (windspeed / windMax) + .05) * 14 + 3)
		if windspeed == 0 then
			lastbladetime = 1
			blades.style.animation = "1s linear infinite a";
		else
			blades.style.animation = lastbladetime .. "s linear infinite spin";
		end
		sec2 = 0
	end

	-- -- wind
	-- if gameFrame ~= lastFrame then
	-- end

	-- -- coms
	-- if displayComCounter then
	-- 	secComCount = secComCount + dt
	-- 	if secComCount > 0.5 then
	-- 		secComCount = 0
	-- 		countComs()
	-- 	end
	-- end

	-- -- rejoin
	-- if not isReplay and serverFrame then
	-- 	t = t - dt
	-- 	if t <= 0 then
	-- 		t = t + UPDATE_RATE_S

	-- 		-- update/estimate serverFrame (because widget:GameProgress(n) only happens every 150 frames)
	-- 		if gameStarted and not isPaused then
	-- 			serverFrame = serverFrame + math.ceil(speedFactor * UPDATE_RATE_F)
	-- 		end

	-- 		local framesLeft = serverFrame - gameFrame
	-- 		if framesLeft > CATCH_UP_THRESHOLD then
	-- 			userIsRejoining = true
	-- 			if widgetHandler.orderList["Rejoin progress"] < 1 then
	-- 				showRejoinUI = true
	-- 				updateRejoin()
	-- 			else
	-- 				showRejoinUI = false
	-- 			end
	-- 		elseif userIsRejoining then
	-- 			userIsRejoining = false
	-- 			local prevShowRejoinUI = showRejoinUI
	-- 			showRejoinUI = false
	-- 			if prevShowRejoinUI then
	-- 				updateRejoin()
	-- 				init()
	-- 			end
	-- 		end
	-- 	end
	-- end
end
