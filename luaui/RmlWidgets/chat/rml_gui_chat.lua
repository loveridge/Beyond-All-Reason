local widget = widget ---@type Widget

if not RmlUi then
	return
end

function widget:GetInfo()
	return {
		name = "Chat RML Example",
		desc = "RmlUI rewrite of the chat/console widget",
		author = "OpenAI",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = -95000,
		enabled = true,
		handler = true,
	}
end

local mathFloor = math.floor
local mathMin = math.min
local mathMax = math.max
local mathClamp = math.clamp or function(v, mn, mx)
	if v < mn then return mn end
	if v > mx then return mx end
	return v
end

local spGetMyTeamID = Spring.GetMyTeamID
local spGetMouseState = Spring.GetMouseState
local spEcho = Spring.Echo
local spGetSpectatingState = Spring.GetSpectatingState
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetTeamColor = Spring.GetTeamColor
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spPlaySoundFile = Spring.PlaySoundFile
local spGetClipboard = Spring.GetClipboard
local spSetClipboard = Spring.SetClipboard

local utf8 = VFS.Include('common/luaUtilities/utf8.lua')
local badWords = VFS.Include('luaui/configs/badwords.lua')

local L_DEPRECATED = LOG and LOG.DEPRECATED
local isDevSingle = Spring.Utilities and Spring.Utilities.IsDevMode and Spring.Utilities.Gametype and Spring.Utilities.Gametype.IsSinglePlayer and (Spring.Utilities.IsDevMode() and Spring.Utilities.Gametype.IsSinglePlayer())

local LineTypes = {
	Console = -1,
	Player = 1,
	Spectator = 2,
	Mapmark = 3,
	Battleroom = 4,
	System = 5,
}

local vsx, vsy = Spring.GetViewGeometry()
local config = {
	showHistoryWhenChatInput = true,
	showHistoryWhenCtrlShift = true,
	enableShortcutClick = true,
	posY = 0.81,
	posX = 0.3,
	posX2 = 0.74,
	charSize = 21 - (3.5 * ((vsx / vsy) - 1.78)),
	consoleFontSizeMult = 0.85,
	maxLines = 5,
	maxConsoleLines = 2,
	maxLinesScrollFull = 16,
	maxLinesScrollChatInput = 9,
	lineHeightMult = 1.36,
	lineTTL = 40,
	consoleLineCleanupTarget = Spring.Utilities and Spring.Utilities.IsDevMode and Spring.Utilities.IsDevMode() and 1200 or 400,
	orgLineCleanupTarget = Spring.Utilities and Spring.Utilities.IsDevMode and Spring.Utilities.IsDevMode() and 1400 or 600,
	backgroundOpacity = 0.25,
	handleTextInput = true,
	maxTextInputChars = 127,
	inputButton = true,
	allowMultiAutocomplete = true,
	allowMultiAutocompleteMax = 10,
	soundErrorsLimit = Spring.Utilities and Spring.Utilities.IsDevMode and Spring.Utilities.IsDevMode() and 999 or 10,
	ui_scale = Spring.GetConfigFloat("ui_scale", 1),
	ui_opacity = Spring.GetConfigFloat("ui_opacity", 0.7),
	fontsizeMult = 1,
	hide = false,
	hideSpecChat = (Spring.GetConfigInt('HideSpecChat', 0) == 1),
	hideSpecChatPlayer = (Spring.GetConfigInt('HideSpecChatPlayer', 1) == 1),
	playSound = true,
	sndChatFile = 'beep4',
	sndChatFileVolume = 0.55,
}

local maxConsoleLines = config.maxConsoleLines
local fontsizeMult = config.fontsizeMult
local backgroundOpacity = config.backgroundOpacity
local handleTextInput = config.handleTextInput
local inputButton = config.inputButton
local hide = config.hide
local showHistoryWhenChatInput = config.showHistoryWhenChatInput
local showHistoryWhenCtrlShift = config.showHistoryWhenCtrlShift
local enableShortcutClick = config.enableShortcutClick
local hideSpecChat = config.hideSpecChat
local hideSpecChatPlayer = config.hideSpecChatPlayer
local playSound = config.playSound
local sndChatFile = config.sndChatFile
local sndChatFileVolume = config.sndChatFileVolume

local usedFontSize = config.charSize * fontsizeMult
local usedConsoleFontSize = usedFontSize * config.consoleFontSizeMult
local posY, posX, posX2 = config.posY, config.posX, config.posX2
local maxLines = config.maxLines
local maxLinesScrollFull = config.maxLinesScrollFull
local maxLinesScrollChatInput = config.maxLinesScrollChatInput
local maxLinesScroll = maxLinesScrollFull
local lineTTL = config.lineTTL
local consoleLineCleanupTarget = config.consoleLineCleanupTarget
local orgLineCleanupTarget = config.orgLineCleanupTarget
local maxTextInputChars = config.maxTextInputChars
local allowMultiAutocomplete = config.allowMultiAutocomplete
local allowMultiAutocompleteMax = config.allowMultiAutocompleteMax

local document
local context
local dm
local modelName = "chat_rml_data"

local I18N = {}
local orgLines = {}
local chatLines = {}
local consoleLines = {}
local ignoredAccounts = {}
local currentChatLine = 0
local currentConsoleLine = 0
local historyMode = false
local lastMapmarkCoords
local lastUnitShare
local lastLineUnitShare
local myName = Spring.GetPlayerInfo(Spring.GetMyPlayerID(), false)
local mySpec = spGetSpectatingState()
local myTeamID = spGetMyTeamID()
local myAllyTeamID = Spring.GetMyAllyTeamID()
local chobbyInterface
local showTextInput = false
local inputText = ''
local inputTextPosition = 0
local inputSelectionStart = nil
local cursorBlinkTimer = 0
local cursorBlinkDuration = 1
local inputMode = nil
local inputTextInsertActive = false
local inputHistory = {}
local inputHistoryCurrent = 0
local autocompleteWords = {}
local autocompleteText
local prevAutocompleteLetters
local lastMessage
local activationArea = {0, 0, 0, 0}
local consoleActivationArea = {0, 0, 0, 0}
local topbarArea
local scrollingPosY = 0.66
local consolePosY = 0.9
local lineHeight = mathFloor(usedFontSize * config.lineHeightMult)
local consoleLineHeight = mathFloor(usedConsoleFontSize * config.lineHeightMult)
local backgroundPadding = 10
local playernames = {}
local teamColorKeys = {}
local teamNames = {}
local soundErrors = {}
local chatProcessors = {}
local unitTranslatedHumanName = {}
local autocompletePlayernames = {}
local autocompleteUnitNames = {}
local autocompleteUnitCodename = {}
local addedOptionsList = false
local needsUiRefresh = true
local uiSec = 0
local prevHoveredHistory = false
local anonymousMode = Spring.GetModOptions().teamcolors_anonymous_mode
local anonymousTeamColor = {Spring.GetConfigInt("anonymousColorR", 255) / 255, Spring.GetConfigInt("anonymousColorG", 0) / 255, Spring.GetConfigInt("anonymousColorB", 0) / 255}

local colorOther = {1, 1, 1}
local colorAlly = {0, 1, 0}
local colorSpec = {1, 1, 0}
local colorSpecName = {1, 1, 1}
local colorOtherAlly = {1, 0.7, 0.45}
local colorGame = {0.4, 1, 1}
local colorConsole = {0.85, 0.85, 0.85}
local msgColor = '\255\180\180\180'
local msgHighlightColor = '\255\215\215\215'
local metalColor = '\255\233\233\233'
local metalValueColor = '\255\255\255\255'
local energyColor = '\255\255\255\180'
local energyValueColor = '\255\255\255\140'

local ColorString = Spring.Utilities and Spring.Utilities.Color and Spring.Utilities.Color.ToString
local ColorIsDark = Spring.Utilities and Spring.Utilities.Color and Spring.Utilities.Color.ColorIsDark

local function stripColorCodes(text)
	local result = text or ""
	result = result:gsub("\255...", "")
	result = result:gsub("\255", "")
	result = result:gsub("ÿ", "")
	result = result:gsub("\254........", "")
	result = result:gsub("\254", "")
	result = result:gsub("þ", "")
	result = result:gsub("\008", "")
	result = result:gsub("\001...", "")
	result = result:gsub("\001", "")
	return result
end

local function cleanupLineTable(prevTable, maxEntries)
	local newTable = {}
	local start = #prevTable - maxEntries
	for i = 1, maxEntries do
		newTable[i] = prevTable[start + i]
	end
	return newTable
end

local function shallowCopyTable(t)
	local out = {}
	for k, v in pairs(t or {}) do
		out[k] = v
	end
	return out
end

local autocompleteCommands = {
	'advmapshading', 'aicontrol', 'aikill', 'ailist', 'aireload', 'airmesh', 'allmapmarks', 'ally', 'atm', 'buffertext',
	'chat', 'chatall', 'chatally', 'chatspec', 'cheat', 'clearmapmarks', 'cmdcolors', 'commandhelp', 'commandlist', 'console',
	'controlunit', 'crash', 'createvideo', 'cross', 'ctrlpanel', 'debug', 'debugcolvol', 'debugdrawai', 'debuggl',
	'debugglerrors', 'debuginfo', 'debugpath', 'debugtraceray', 'decguiopacity', 'decreaseviewradius', 'deselect', 'destroy',
	'devlua', 'distdraw', 'disticon', 'divbyzero', 'drawinmap', 'drawlabel', 'drawtrees', 'dumpstate', 'dynamicsky', 'echo',
	'editdefs', 'endgraph', 'exception', 'font', 'fps', 'fpshud', 'fullscreen', 'gameinfo', 'gathermode', 'give', 'globallos',
	'godmode', 'grabinput', 'grounddecals', 'grounddetail', 'group', 'group0', 'group1', 'group2', 'group3', 'group4', 'group5',
	'group6', 'group7', 'group8', 'group9', 'hardwarecursor', 'hideinterface', 'incguiopacity', 'increaseviewradius', 'info',
	'inputtextgeo', 'keyreload', 'lastmsgpos', 'lessclouds', 'lesstrees', 'lodscale', 'luagaia', 'luarules', 'luasave', 'luaui',
	'mapborder', 'mapmarks', 'mapmeshdrawer', 'mapshadowpolyoffset', 'maxnanoparticles', 'maxparticles', 'minimap', 'moreclouds',
	'moretrees', 'mouse1', 'mouse2', 'mouse3', 'mouse4', 'mouse5', 'moveback', 'movedown', 'movefast', 'moveforward', 'moveleft',
	'moveright', 'moveslow', 'moveup', 'mutesound', 'nocost', 'nohelp', 'noluadraw', 'nospecdraw', 'nospectatorchat', 'pastetext',
	'pause', 'quitforce', 'quitmenu', 'quitmessage', 'reloadcegs', 'reloadcob', 'reloadforce', 'reloadgame', 'reloadshaders',
	'reloadtextures', 'resbar', 'resync', 'safegl', 'save', 'say', 'screenshot', 'select', 'selectcycle', 'selectunits', 'send',
	'set', 'shadows', 'sharedialog', 'showelevation', 'showmetalmap', 'showpathcost', 'showpathflow', 'showpathheat',
	'showpathtraversability', 'showpathtype', 'showstandard', 'skip', 'slowdown', 'soundchannelenablec', 'sounddevice',
	'specfullview', 'spectator', 'specteam', 'speedcontrol', 'speedup', 'take', 'team', 'teamhighlight', 'toggleinfo', 'togglelos',
	'tooltip', 'track', 'trackmode', 'trackoff', 'tset', 'viewselection', 'vsync', 'water', 'wbynum', 'wiremap', 'wiremodel',
	'wiresky', 'wiretree', 'wirewater', 'widgetselector',
	'luarules battleroyaledebug', 'luarules buildicon', 'luarules cmd', 'luarules clearwrecks', 'luarules reducewrecks',
	'luarules destroyunits', 'luarules disablecusgl4', 'luarules fightertest', 'luarules give', 'luarules givecat',
	'luarules halfhealth', 'luarules kill_profiler', 'luarules loadmissiles', 'luarules profile', 'luarules reclaimunits',
	'luarules reloadcus', 'luarules reloadcusgl4', 'luarules removeunits', 'luarules removeunitdef', 'luarules removenearbyunits',
	'luarules spawnceg', 'luarules spawnunitexplosion', 'luarules undo', 'luarules unitcallinsgadget', 'luarules updatesun',
	'luarules waterlevel', 'luarules wreckunits', 'luarules xp', 'luarules transferunits', 'luarules playertoteam',
	'luarules killteam', 'luarules globallos', 'luarules zombiesetallgaia', 'luarules zombiequeueallcorpses',
	'luarules zombieautospawn 0', 'luarules zombieclearspawns', 'luarules zombiepacify 0', 'luarules zombiesuspendorders 0',
	'luarules zombieaggroteam 0', 'luarules zombieaggroally 0', 'luarules zombiekillall', 'luarules zombieclearallorders',
	'luarules zombiedebug 0', 'luarules zombiemode normal', 'luarules buildblock all default_reason',
	'luarules buildunblock all default_reason', 'luaui reload', 'luaui disable', 'luaui enable', 'addmessage', 'radarpulse',
	'ecostatstext', 'defrange ally air', 'defrange ally nuke', 'defrange ally ground', 'defrange enemy air', 'defrange enemy nuke',
	'defrange enemy ground',
}

local dataModel = {
	rootVisible = false,
	showConsoleStack = false,
	showChatStack = false,
	showHistoryPanel = false,
	isHistoryChat = false,
	isHistoryConsole = false,
	showTextInput = false,
	showInputButton = true,
	showAutocomplete = false,
	showAutocompleteList = false,
	showNewChatNotice = false,
	noHistory = false,
	historyTitle = "",
	shortcutText = "",
	modeLabel = "",
	inputText = "",
	autocompleteTail = "",
	newChatNotice = "",
	chatRows = {},
	consoleRows = {},
	historyRows = {},
	autocompleteRows = {},
	toggleInputMode = function()
		if inputMode == 'a:' then
			inputMode = ''
		elseif inputMode == 's:' then
			inputMode = mySpec and '' or 'a:'
		else
			inputMode = 's:'
		end
		needsUiRefresh = true
	end,
		setHistoryMode = function(mode)
			if mode == 'chat' or mode == 'console' then
				historyMode = mode
				if mode == 'chat' then
					maxLinesScroll = maxLinesScrollFull
				end
				needsUiRefresh = true
			end
		end,
		clearHistoryMode = function()
			historyMode = false
			if currentChatLine > 0 then
				local i = #chatLines
				while i > 0 do
					if not chatLines[i].ignore then
						currentChatLine = i
						break
					end
					i = i - 1
				end
			end
			needsUiRefresh = true
		end,
		scrollHistory = function(delta)
			delta = tonumber(delta) or 0
			if delta == 0 then
				return
			end
			widget:ScrollHistory(delta < 0, math.abs(delta))
		end,
		activateChatLine = function(index)
			widget:ActivateChatLine(tonumber(index) or 0)
		end,
		acceptAutocomplete = function(index)
			widget:AcceptAutocomplete(tonumber(index) or 1)
		end,
		beginInput = function()
			widget:OpenInput(false, false, false)
		end,
}

local function setCurrentChatLine(line)
	local i = line
	while i > 0 do
		if not chatLines[i].ignore then
			currentChatLine = i
			break
		end
		i = i - 1
	end
end

local function formatGameTime(gameFrame)
	if not gameFrame then
		return ""
	end
	local minutes = mathFloor((gameFrame / 30 / 60))
	local seconds = mathFloor((gameFrame - ((minutes * 60) * 30)) / 30)
	if seconds == 0 then
		seconds = '00'
	elseif seconds < 10 then
		seconds = '0' .. seconds
	end
	return tostring(minutes) .. ':' .. tostring(seconds)
end

local function getAIName(teamID)
	local _, _, _, name, _, options = Spring.GetAIInfo(teamID)
	local niceName = Spring.GetGameRulesParam('ainame_' .. teamID)
	if niceName then
		name = niceName
		if Spring.Utilities and Spring.Utilities.ShowDevUI and Spring.Utilities.ShowDevUI() and options and options.profile then
			name = name .. " [" .. options.profile .. "]"
		end
	end
	return Spring.I18N('ui.playersList.aiName', { name = name })
end

local function refreshUnitDefs()
	autocompleteUnitNames = {}
	autocompleteUnitCodename = {}
	local uniqueHumanNames = {}
	unitTranslatedHumanName = {}
	for unitDefID, unitDef in pairs(UnitDefs) do
		if not uniqueHumanNames[unitDef.translatedHumanName] then
			uniqueHumanNames[unitDef.translatedHumanName] = true
			autocompleteUnitNames[#autocompleteUnitNames + 1] = unitDef.translatedHumanName
		end
		if not string.find(unitDef.name, "_scav", nil, true) then
			autocompleteUnitCodename[#autocompleteUnitCodename + 1] = unitDef.name:lower()
		end
		unitTranslatedHumanName[unitDefID] = unitDef.translatedHumanName
	end
	for _, featureDef in pairs(FeatureDefs) do
		autocompleteUnitCodename[#autocompleteUnitCodename + 1] = featureDef.name:lower()
	end
end

function widget:LanguageChanged()
	I18N = {
		energy = Spring.I18N('ui.topbar.resources.energy'):lower(),
		metal = Spring.I18N('ui.topbar.resources.metal'):lower(),
		everyone = Spring.I18N('ui.chat.everyone'),
		allies = Spring.I18N('ui.chat.allies'),
		spectators = Spring.I18N('ui.chat.spectators'),
		cmd = Spring.I18N('ui.chat.cmd'),
		shortcut = Spring.I18N('ui.chat.shortcut'),
		nohistory = Spring.I18N('ui.chat.nohistory'),
		scroll = Spring.I18N('ui.chat.scroll', { textColor = "\255\255\255\255", highlightColor = "\255\255\255\001" }),
		historyChat = Spring.I18N('ui.chat.allies'),
		historyConsole = "Console",
	}
	refreshUnitDefs()
	needsUiRefresh = true
end
widget:LanguageChanged()

local function findBadWords(str)
	str = string.lower(str)
	for w in str:gmatch("%w+") do
		for _, bw in ipairs(badWords) do
			if string.find(w, bw) then
				return w
			end
		end
	end
end

local function cleanUserText(text)
	if string.sub(text, 1, 1) == ' ' then
		text = string.sub(text, 2)
	end
	return stripColorCodes(text)
end

local function shouldHideSpecMessage()
	local currentHideSpecChat = (Spring.GetConfigInt('HideSpecChat', 0) == 1)
	local currentHideSpecChatPlayer = (Spring.GetConfigInt('HideSpecChatPlayer', 1) == 1)
	return currentHideSpecChat and (not currentHideSpecChatPlayer or not mySpec)
end

local function extractChannelPrefix(text)
	if string.find(text, 'Allies: ', 1, true) == 1 then
		return string.sub(text, 9), 'allies'
	elseif string.find(text, 'Spectators: ', 1, true) == 1 then
		return string.sub(text, 13), 'spectators'
	end
	return text, 'all'
end

local function getPlayerColorString(playername, gameFrame)
	if not ColorString then
		return ''
	end
	local color
	if playernames[playername] then
		if playernames[playername][5] and (not gameFrame or not playernames[playername][8] or gameFrame < playernames[playername][8]) then
			if not mySpec and anonymousMode ~= "disabled" then
				color = ColorString(anonymousTeamColor[1], anonymousTeamColor[2], anonymousTeamColor[3])
			else
				local c = playernames[playername][5]
				color = ColorString(c[1], c[2], c[3])
			end
		else
			color = ColorString(colorSpecName[1], colorSpecName[2], colorSpecName[3])
		end
	else
		color = ColorString(0.7, 0.7, 0.7)
	end
	return color or ''
end

local function getDisplayName(name)
	return (playernames[name] and playernames[name][7]) or name
end

local function getColoredPlayerName(name, gameFrame, isSpectator)
	local displayName = getDisplayName(name)
	if isSpectator then
		return '(s) ' .. displayName
	end
	return displayName
end

local function formatSystemMessage(i18nKey, playername, gameFrame, extraParams)
	local params = extraParams or {}
	params.name = getDisplayName(playername)
	local ok, value = pcall(Spring.I18N, i18nKey, params)
	if ok and type(value) == 'string' then
		return value
	end
	return params.name
end

local function commonUnitName(unitIDs)
	local commonUnitDefID = nil
	for _, unitID in pairs(unitIDs) do
		local unitDefID = Spring.GetUnitDefID(unitID)
		if not unitDefID or (commonUnitDefID and unitDefID ~= commonUnitDefID) then
			return #unitIDs > 1 and "units" or "unit"
		end
		commonUnitDefID = unitDefID
	end
	return unitTranslatedHumanName[commonUnitDefID] or (#unitIDs > 1 and "units" or "unit")
end

local function addConsoleLine(gameFrame, lineType, text, orgLineID)
	if not text or text == '' then
		return
	end
	consoleLines[#consoleLines + 1] = {
		startTime = os.clock(),
		gameFrame = gameFrame,
		lineType = lineType,
		text = stripColorCodes(text),
		orgLineID = orgLineID,
	}
	if historyMode ~= 'console' then
		currentConsoleLine = #consoleLines
	end
end

local function addChatLine(gameFrame, lineType, name, nameText, text, orgLineID, ignore, noProcessors)
	if not noProcessors then
		for _, processor in pairs(chatProcessors) do
			if text == nil then
				break
			end
			text = processor(gameFrame, lineType, name, nameText, text, orgLineID, ignore, #chatLines + 1)
		end
	end
	if not text or text == '' then
		return
	end
	local entry = {
		startTime = os.clock(),
		gameFrame = gameFrame,
		lineType = lineType,
		playerName = name,
		playerNameText = stripColorCodes(nameText or ''),
		text = stripColorCodes(text),
		orgLineID = orgLineID,
		ignore = ignore,
	}
	if lineType == LineTypes.Mapmark and lastMapmarkCoords then
		entry.coords = lastMapmarkCoords
		lastMapmarkCoords = nil
		entry.clickable = true
	end
	if lineType == LineTypes.System and lastLineUnitShare and lastLineUnitShare.newTeamID == myTeamID then
		entry.selectUnits = lastLineUnitShare.unitIDs
		entry.clickable = true
		lastLineUnitShare = nil
	end
	chatLines[#chatLines + 1] = entry
	if historyMode ~= 'chat' and not ignore then
		setCurrentChatLine(#chatLines)
	end
	if not ignore and #orgLines == orgLineID and (lineType == LineTypes.Player or lineType == LineTypes.Spectator) and playSound and not Spring.IsGUIHidden() then
		spPlaySoundFile(sndChatFile, sndChatFileVolume, nil, "ui")
	end
end

local function processAddConsoleLine(gameFrame, line, orgLineID)
	local orgLine = line
	local name = ''
	local nameText = ''
	local text = ''
	local lineType = 0
	local bypassThisMessage = false
	local skipThisMessage = false

	local playerChatEnd = string.find(line, "> ", 1, true)
	local specChatEnd = string.find(line, "] ", 1, true)
	local replaySpecEnd = string.find(line, " (replay)] ", 1, true)
	local mapPointPos = string.find(line, " added point: ", 1, true)
	local unitSharePos = string.find(line, " shared units to ", 1, true)

	if string.sub(line, 1, 1) == '<' and playerChatEnd and playernames[string.sub(line, 2, playerChatEnd - 1)] ~= nil then
		lineType = LineTypes.Player
		name = string.sub(line, 2, playerChatEnd - 1)
		text = string.sub(line, #name + 4)
		local channel
		text, channel = extractChannelPrefix(text)
		text = cleanUserText(text)
		nameText = getColoredPlayerName(name, gameFrame, false)
		if channel == 'spectators' then
			lineType = LineTypes.Spectator
		elseif channel == 'allies' then
			lineType = LineTypes.Player
		end
	elseif string.sub(line, 1, 1) == '[' and ((specChatEnd and playernames[string.sub(line, 2, specChatEnd - 1)] ~= nil) or (replaySpecEnd and playernames[string.sub(line, 2, replaySpecEnd - 1)] ~= nil)) then
		lineType = LineTypes.Spectator
		if specChatEnd and playernames[string.sub(line, 2, specChatEnd - 1)] ~= nil then
			name = string.sub(line, 2, specChatEnd - 1)
			text = string.sub(line, #name + 4)
		else
			name = string.sub(line, 2, replaySpecEnd - 1)
			text = string.sub(line, #name + 13)
		end
		skipThisMessage = shouldHideSpecMessage()
		local channel
		text, channel = extractChannelPrefix(text)
		text = cleanUserText(text)
		nameText = getColoredPlayerName(name, gameFrame, true)
	elseif mapPointPos and playernames[string.sub(line, 1, mapPointPos - 1)] ~= nil then
		lineType = LineTypes.Mapmark
		name = string.sub(line, 1, mapPointPos - 1)
		text = cleanUserText(string.sub(line, #(name .. " added point: ") + 1))
		if text == '' then
			text = 'Look here!'
		end
		local spectator = playernames[name] and playernames[name][2] or false
		if spectator then
			skipThisMessage = shouldHideSpecMessage()
		end
		nameText = getColoredPlayerName(name, gameFrame, spectator)
	elseif string.sub(line, 1, 1) == '>' then
		lineType = LineTypes.Spectator
		text = string.sub(line, 3)
		if string.sub(line, 1, 3) == "> <" then
			local idx = string.find(string.sub(line, 4), ">", 1, true)
			if idx then
				name = string.sub(line, 4, idx + 2)
				text = string.sub(line, idx + 5)
			else
				name = "unknown"
			end
		else
			bypassThisMessage = true
		end
		local spectator = playernames[name] and playernames[name][2] or false
		skipThisMessage = hideSpecChat and (not playernames[name] or spectator) and (not hideSpecChatPlayer or not mySpec)
		text = cleanUserText(text)
		nameText = '<' .. ((playernames[name] and playernames[name][7]) or name) .. '>'
	elseif unitSharePos and playernames[string.sub(line, 1, unitSharePos - 1)] ~= nil then
		lineType = LineTypes.System
		local oldTeamName, newTeamName, shareDesc = string.match(line, "(.+) shared units to (.+): (.+)")
		if newTeamName and newTeamName ~= '' and shareDesc and shareDesc ~= '' then
			text = Spring.I18N('ui.unitShare.shared', {
				units = shareDesc,
				name = getDisplayName(newTeamName),
			})
			if type(text) ~= 'string' then
				text = shareDesc .. ' -> ' .. getDisplayName(newTeamName)
			end
		end
		name = oldTeamName
		nameText = getColoredPlayerName(oldTeamName, gameFrame, false)
	else
		lineType = LineTypes.Console
		text = stripColorCodes(line)
		local bypassPatterns = {
			"Input grabbing is ", " to access the quit menu", "VSync::SetInterval", " now spectating team ",
			"TotalHideLobbyInterface, ", "HandleLobbyOverlay", "Chobby]", "liblobby]", "[LuaMenu", "ClientMessage]",
			"ServerMessage]", "->", "-> Version", "ClientReadNet", "Address", 'self%-destruct in ',
		}
		for _, pattern in ipairs(bypassPatterns) do
			if string.find(text, pattern, 1, true) then
				bypassThisMessage = true
				break
			end
		end
		if not bypassThisMessage then
			if string.find(text, "server=[0-9a-z][0-9a-z][0-9a-z][0-9a-z]") or string.find(text, "client=[0-9a-z][0-9a-z][0-9a-z][0-9a-z]") then
				bypassThisMessage = true
			elseif string.find(text, "could not load sound", 1, true) then
				if soundErrors[text] or #soundErrors > config.soundErrorsLimit then
					bypassThisMessage = true
				else
					soundErrors[text] = true
				end
			elseif string.find(text, ' paused the game', 1, true) then
				local playername = string.sub(text, 1, string.find(text, ' paused the game', 1, true) - 1)
				text = formatSystemMessage('ui.chat.pausedthegame', playername, gameFrame, {})
			elseif string.find(text, ' unpaused the game', 1, true) then
				local playername = string.sub(text, 1, string.find(text, ' unpaused the game', 1, true) - 1)
				text = formatSystemMessage('ui.chat.unpausedthegame', playername, gameFrame, {})
			elseif string.find(text, 'Sync error for', 1, true) then
				local framePos = string.find(text, ' in frame', 1, true)
				if framePos then
					local playername = string.sub(text, 16, framePos - 1)
					text = formatSystemMessage('ui.chat.syncerrorfor', playername, gameFrame, {})
				end
			elseif string.find(text, ' is lagging behind', 1, true) then
				local playername = string.sub(text, 1, string.find(text, ' is lagging behind', 1, true) - 1)
				text = formatSystemMessage('ui.chat.laggingbehind', playername, gameFrame, {})
			end
		end
	end

	if not bypassThisMessage then
		if ((string.sub(text, 1, 1) == '!' and string.sub(text, 1, 2) ~= '!!') or string.find(text, 'My player ID is', 1, true)) then
			bypassThisMessage = true
		end
		if not bypassThisMessage and text ~= '' then
			if ignoredAccounts[name] then
				skipThisMessage = true
			end
			if not orgLineID then
				orgLineID = #orgLines + 1
				orgLines[orgLineID] = { gameFrame, orgLine }
				if lineType > 0 and WG.logo and string.find(text, myName or '', 1, true) then
					WG.logo.mention()
				end
			end
			if lineType < 1 then
				addConsoleLine(gameFrame, lineType, text, orgLineID)
			else
				addChatLine(gameFrame, lineType, name, nameText, text, orgLineID, skipThisMessage)
			end
		end
	end
end

local function addLastUnitShareMessage()
	if not lastUnitShare then
		return
	end
	for _, unitShare in pairs(lastUnitShare) do
		local oldTeamName = teamNames[unitShare.oldTeamID]
		local newTeamName = teamNames[unitShare.newTeamID]
		if oldTeamName and newTeamName then
			local shareDescription = commonUnitName(unitShare.unitIDs)
			if #unitShare.unitIDs > 1 then
				shareDescription = #unitShare.unitIDs .. ' ' .. shareDescription
			end
			lastLineUnitShare = unitShare
			spEcho(oldTeamName .. ' shared units to ' .. newTeamName .. ': ' .. shareDescription)
		end
	end
	lastUnitShare = nil
end

local function cancelChatInput()
	showTextInput = false
	if showHistoryWhenChatInput then
		historyMode = false
		setCurrentChatLine(#chatLines)
	end
	inputText = ''
	inputTextPosition = 0
	inputSelectionStart = nil
	inputTextInsertActive = false
	inputHistoryCurrent = #inputHistory
	autocompleteText = nil
	autocompleteWords = {}
	Spring.SDLStopTextInput()
	widgetHandler.textOwner = nil
	needsUiRefresh = true
end

local function clearChatInput()
	inputText = ''
	inputTextPosition = 0
	inputSelectionStart = nil
	inputTextInsertActive = false
	autocompleteText = nil
	autocompleteWords = {}
	prevAutocompleteLetters = nil
	needsUiRefresh = true
end

local function runAutocompleteSet(wordsSet, searchStr, multi, lower)
	autocompleteWords = {}
	local charCount = #searchStr
	for _, word in ipairs(wordsSet) do
		local compareWord = lower and word:lower() or word
		local compareStr = lower and searchStr:lower() or searchStr
		if #word > charCount and compareStr == string.sub(compareWord, 1, charCount) then
			autocompleteWords[#autocompleteWords + 1] = word
			if not autocompleteText then
				autocompleteText = string.sub(word, charCount + 1)
				if not multi then
					return true
				end
			end
		end
	end
	return autocompleteText ~= nil
end

local loadedAutocompleteCommands = false
local function autocomplete(text, fresh)
	if not loadedAutocompleteCommands then
		loadedAutocompleteCommands = true
		for textAction in pairs(widgetHandler.actionHandler.textActions) do
			if type(textAction) == 'string' then
				local found = false
				for _, cmd in ipairs(autocompleteCommands) do
					if cmd == textAction then
						found = true
						break
					end
				end
				if not found then
					autocompleteCommands[#autocompleteCommands + 1] = textAction
				end
			end
		end
	end

	autocompleteText = nil
	if fresh then
		autocompleteWords = {}
	end
	if text == '' then
		return
	end
	local letters = ''
	local isCmd = string.sub(text, 1, 1) == '/'
	local words = {}
	for word in (string.sub(text, isCmd and 2 or 1)):gmatch("%S+") do
		words[#words + 1] = word
		letters = word
	end
	if string.sub(inputText, #text) == ' ' then
		letters = letters .. ' '
		if autocompleteWords[1] then
			prevAutocompleteLetters = letters
		end
	else
		if prevAutocompleteLetters and autocompleteWords[1] then
			letters = prevAutocompleteLetters .. letters
			if isCmd then
				words = { letters }
			end
		else
			prevAutocompleteLetters = nil
		end
	end
	if autocompleteWords[2] then
		runAutocompleteSet(autocompleteWords, letters, allowMultiAutocomplete, true)
	else
		if #letters >= 2 then
			runAutocompleteSet(autocompletePlayernames, letters)
		end
		if not autocompleteWords[1] then
			if isCmd then
				if #words <= 1 then
					runAutocompleteSet(autocompleteCommands, letters, allowMultiAutocomplete)
				else
					runAutocompleteSet(autocompleteUnitCodename, letters, allowMultiAutocomplete)
				end
			else
				if #letters >= 2 then
					runAutocompleteSet(autocompleteUnitNames, letters, allowMultiAutocomplete, true)
				end
			end
		end
	end
	if prevAutocompleteLetters and not autocompleteWords[1] then
		prevAutocompleteLetters = nil
		autocomplete(text, true)
	end
end

function widget:ActivateChatLine(index)
	local line = chatLines[index]
	if not line then
		return
	end
	if line.coords then
		Spring.SetCameraTarget(line.coords[1], line.coords[2], line.coords[3])
	elseif line.selectUnits then
		Spring.SelectUnitArray(line.selectUnits)
		Spring.SendCommands("viewselection")
	end
end

function widget:AcceptAutocomplete(index)
	index = tonumber(index) or 1
	if not autocompleteWords[index] then
		return
	end
	local word = autocompleteWords[index]
	local letters = ''
	local isCmd = string.sub(inputText, 1, 1) == '/'
	for piece in (isCmd and string.sub(inputText, 2) or inputText):gmatch("%S+") do
		letters = piece
	end
	if string.sub(inputText, #inputText) == ' ' then
		letters = letters .. ' '
	elseif prevAutocompleteLetters then
		letters = prevAutocompleteLetters .. letters
	end
	local replaceLen = #letters
	if replaceLen > 0 then
		inputText = string.sub(inputText, 1, #inputText - replaceLen) .. word
	else
		inputText = inputText .. word
	end
	inputTextPosition = utf8.len(inputText)
	inputHistory[#inputHistory] = inputText
	autocompleteText = nil
	autocompleteWords = {}
	prevAutocompleteLetters = nil
	needsUiRefresh = true
end

function widget:OpenInput(ctrl, alt, shift)
	if showTextInput then
		return
	end
	cancelChatInput()
	showTextInput = true
	if showHistoryWhenChatInput then
		historyMode = 'chat'
		maxLinesScroll = maxLinesScrollChatInput
	end
	widgetHandler.textOwner = self
	if not inputHistory[inputHistoryCurrent] or inputHistory[inputHistoryCurrent] ~= '' then
		if inputHistoryCurrent == 1 or inputHistory[inputHistoryCurrent] ~= inputHistory[inputHistoryCurrent - 1] then
			inputHistoryCurrent = inputHistoryCurrent + 1
		end
		inputHistory[inputHistoryCurrent] = ''
	end
	if ctrl then
		inputMode = ''
	elseif alt then
		inputMode = mySpec and 's:' or 'a:'
	elseif shift then
		inputMode = 's:'
	elseif inputMode == nil then
		inputMode = mySpec and 's:' or 'a:'
	end
	Spring.SDLStartTextInput()
	needsUiRefresh = true
end

local function sliceRows(source, startIndex, count, predicate)
	local rows = {}
	local i = startIndex
	local collected = 0
	while i > 0 do
		local row = source[i]
		if row and (not predicate or predicate(row)) then
			rows[#rows + 1] = row
			collected = collected + 1
			if collected >= count then
				break
			end
		end
		i = i - 1
	end
	local ordered = {}
	for idx = #rows, 1, -1 do
		ordered[#ordered + 1] = rows[idx]
	end
	return ordered
end

local function chatRowToView(index, row, history)
	local isSystem = row.lineType == LineTypes.System
	local isMapmark = row.lineType == LineTypes.Mapmark
	local isSpectator = row.lineType == LineTypes.Spectator
	local isConsole = row.lineType == LineTypes.Console
	local speaker = row.playerNameText or ''
	local separator = (isMapmark and '*') or (isSystem and '') or ((speaker ~= '' and ':') or '')
	return {
		sourceIndex = index,
		timestamp = history and formatGameTime(row.gameFrame) or "",
		showTimestamp = history and row.gameFrame ~= nil,
		speaker = speaker,
		separator = separator,
		text = row.text or '',
		clickable = row.clickable and true or false,
		isPlayer = row.lineType == LineTypes.Player,
		isSpectator = isSpectator,
		isMapmark = isMapmark,
		isSystem = isSystem,
		isConsole = isConsole,
	}
end

local function consoleRowToView(index, row, history)
	return {
		sourceIndex = index,
		timestamp = history and formatGameTime(row.gameFrame) or "",
		showTimestamp = history and row.gameFrame ~= nil,
		speaker = "",
		separator = "",
		text = row.text or '',
		clickable = false,
		isPlayer = false,
		isSpectator = false,
		isMapmark = false,
		isSystem = false,
		isConsole = true,
	}
end

local function currentModeLabel()
	local isCmd = string.sub(inputText, 1, 1) == '/'
	if isCmd then
		return I18N.cmd
	elseif inputMode == 'a:' then
		return I18N.allies
	elseif inputMode == 's:' then
		return I18N.spectators
	end
	return I18N.everyone
end

local function buildAutocompleteRows()
	local rows = {}
	if not autocompleteText or not autocompleteWords[2] then
		return rows
	end
	local letters = ''
	local isCmd = string.sub(inputText, 1, 1) == '/'
	for word in (isCmd and string.sub(inputText, 2) or inputText):gmatch("%S+") do
		letters = word
	end
	if string.sub(inputText, #inputText) == ' ' then
		letters = letters .. ' '
	elseif prevAutocompleteLetters then
		letters = prevAutocompleteLetters .. letters
	end
	local letterCount = #letters
	for i, word in ipairs(autocompleteWords) do
		if i > 1 then
			rows[#rows + 1] = {
				index = i,
				prefix = letters,
				suffix = string.sub(word, letterCount + 1),
			}
			if #rows >= allowMultiAutocompleteMax then
				break
			end
		end
	end
	return rows
end

local function refreshRootStyle()
	if not document then
		return
	end
	local root = document:GetElementById("chat-root")
	if not root then
		return
	end
	root.style.left = tostring(activationArea[1]) .. "px"
	root.style.top = tostring(activationArea[2]) .. "px"
	root.style.width = tostring(activationArea[3] - activationArea[1]) .. "px"
	root.style.height = tostring(activationArea[4] - activationArea[2]) .. "px"
end

local function refreshDocumentModel()
	if not dm then
		return
	end
	local now = os.clock()
	local chatRows = {}
	local consoleRows = {}
	local historyRows = {}

	if not historyMode and currentConsoleLine < #consoleLines then
		currentConsoleLine = #consoleLines
	end
	if not historyMode then
		setCurrentChatLine(#chatLines)
	end

	if not historyMode then
		local visibleConsole = sliceRows(consoleLines, #consoleLines, maxConsoleLines, function(row)
			return now - row.startTime < lineTTL
		end)
		for _, row in ipairs(visibleConsole) do
			consoleRows[#consoleRows + 1] = consoleRowToView(row.orgLineID or 0, row, false)
		end
		local visibleChat = sliceRows(chatLines, currentChatLine, maxLines, function(row)
			return not row.ignore and (now - row.startTime < lineTTL)
		end)
		for i, row in ipairs(visibleChat) do
			local sourceIndex = 0
			for j = #chatLines, 1, -1 do
				if chatLines[j] == row then
					sourceIndex = j
					break
				end
			end
			chatRows[i] = chatRowToView(sourceIndex, row, false)
		end
	else
		local count = maxLinesScroll
		if historyMode == 'console' then
			local visibleConsole = sliceRows(consoleLines, currentConsoleLine, count)
			for _, row in ipairs(visibleConsole) do
				local sourceIndex = 0
				for j = #consoleLines, 1, -1 do
					if consoleLines[j] == row then
						sourceIndex = j
						break
					end
				end
				historyRows[#historyRows + 1] = consoleRowToView(sourceIndex, row, true)
			end
		else
			local visibleChat = sliceRows(chatLines, currentChatLine, count, function(row)
				return not row.ignore
			end)
			for _, row in ipairs(visibleChat) do
				local sourceIndex = 0
				for j = #chatLines, 1, -1 do
					if chatLines[j] == row then
						sourceIndex = j
						break
					end
				end
				historyRows[#historyRows + 1] = chatRowToView(sourceIndex, row, true)
			end
		end
	end

	local lastUnignoredChatLineID = #chatLines
	for i = #chatLines, 1, -1 do
		if not chatLines[i].ignore then
			lastUnignoredChatLineID = i
			break
		end
	end
	local showNewChatNotice = false
	local newChatNotice = ""
	if historyMode and chatLines[lastUnignoredChatLineID] and not chatLines[lastUnignoredChatLineID].ignore then
		if currentChatLine < lastUnignoredChatLineID and (now - chatLines[lastUnignoredChatLineID].startTime < lineTTL) then
			showNewChatNotice = true
			newChatNotice = (chatLines[lastUnignoredChatLineID].playerNameText or '') .. ": " .. (chatLines[lastUnignoredChatLineID].text or '')
		end
	end

	dm.rootVisible = (not hide and (#chatRows > 0 or #consoleRows > 0 or showTextInput)) or historyMode
	dm.showConsoleStack = (not historyMode and not hide and #consoleRows > 0)
	dm.showChatStack = (not hide and (#chatRows > 0 or showTextInput)) and not historyMode
	dm.showHistoryPanel = historyMode and true or false
	dm.isHistoryChat = historyMode == 'chat'
	dm.isHistoryConsole = historyMode == 'console'
	dm.showTextInput = showTextInput and handleTextInput
	dm.showInputButton = inputButton and handleTextInput
	dm.showAutocomplete = showTextInput and autocompleteText ~= nil
	dm.showAutocompleteList = showTextInput and autocompleteText ~= nil and autocompleteWords[2] ~= nil
	dm.showNewChatNotice = showNewChatNotice
	dm.noHistory = (#historyRows == 0)
	dm.historyTitle = historyMode == 'console' and 'Console' or 'Chat'
	dm.shortcutText = I18N.shortcut or ''
	dm.modeLabel = currentModeLabel()
	dm.inputText = inputText
	dm.autocompleteTail = autocompleteText or ''
	dm.newChatNotice = newChatNotice
	dm.chatRows = chatRows
	dm.consoleRows = consoleRows
	dm.historyRows = historyRows
	dm.autocompleteRows = buildAutocompleteRows()
	refreshRootStyle()
	needsUiRefresh = false
end

local function clearconsoleCmd()
	orgLines = {}
	chatLines = {}
	consoleLines = {}
	currentChatLine = 0
	currentConsoleLine = 0
	needsUiRefresh = true
end

local function hidespecchatCmd(_, _, params)
	if params[1] then
		hideSpecChat = (params[1] == '1')
	else
		hideSpecChat = not hideSpecChat
	end
	Spring.SetConfigInt('HideSpecChat', hideSpecChat and 1 or 0)
	if hideSpecChat then
		spEcho("Hiding all spectator chat")
	else
		spEcho("Showing all spectator chat again")
	end
	needsUiRefresh = true
end

local function hidespecchatplayerCmd(_, _, params)
	if params[1] then
		hideSpecChatPlayer = (params[1] == '1')
	else
		hideSpecChatPlayer = not hideSpecChatPlayer
	end
	Spring.SetConfigInt('HideSpecChatPlayer', hideSpecChatPlayer and 1 or 0)
	if hideSpecChat then
		spEcho("Hiding all spectator chat when player")
	else
		spEcho("Showing all spectator chat when player again")
	end
	needsUiRefresh = true
end

local function preventhistorymodeCmd()
	showHistoryWhenCtrlShift = not showHistoryWhenCtrlShift
	enableShortcutClick = not enableShortcutClick
	if not showHistoryWhenCtrlShift then
		spEcho("Preventing toggling historymode via CTRL+SHIFT")
	else
		spEcho("Enabled toggling historymode via CTRL+SHIFT")
	end
	needsUiRefresh = true
end

function widget:ScrollHistory(up, amount)
	amount = amount or 1
	if historyMode == 'chat' then
		local scrollCount = 0
		local i = currentChatLine
		while i > 0 and i <= #chatLines do
			i = i + (up and -1 or 1)
			if chatLines[i] and not chatLines[i].ignore then
				currentChatLine = i
				scrollCount = scrollCount + 1
				if scrollCount == amount then
					break
				end
			end
		end
		if currentChatLine < maxLinesScroll then
			currentChatLine = maxLinesScroll
		end
	else
		if up then
			currentConsoleLine = currentConsoleLine - amount
			if currentConsoleLine < maxLinesScroll then
				currentConsoleLine = maxLinesScroll
				if currentConsoleLine > #consoleLines then
					currentConsoleLine = #consoleLines
				end
			end
		else
			currentConsoleLine = currentConsoleLine + amount
			if currentConsoleLine > #consoleLines then
				currentConsoleLine = #consoleLines
			end
			currentChatLine = currentChatLine + amount
			if currentChatLine > #chatLines then
				currentChatLine = #chatLines
			end
		end
	end
	needsUiRefresh = true
end

function widget:UnitTaken(unitID, _, oldTeamID, newTeamID)
	local oldAllyTeamID = select(6, spGetTeamInfo(oldTeamID))
	local newAllyTeamID = select(6, spGetTeamInfo(newTeamID))
	local allyTeamShare = (oldAllyTeamID == myAllyTeamID and newAllyTeamID == myAllyTeamID)
	local selfShare = (oldTeamID == newTeamID)
	local _, _, _, captureProgress = Spring.GetUnitHealth(unitID)
	local captured = (captureProgress == 1)
	if (not mySpec and not allyTeamShare) or selfShare or captured then
		return
	end
	lastUnitShare = lastUnitShare or {}
	local key = oldTeamID .. 'to' .. newTeamID
	if not lastUnitShare[key] then
		lastUnitShare[key] = {
			oldTeamID = oldTeamID,
			newTeamID = newTeamID,
			unitIDs = {},
		}
	end
	lastUnitShare[key].unitIDs[#lastUnitShare[key].unitIDs + 1] = unitID
end

function widget:Update(dt)
	addLastUnitShareMessage()
	cursorBlinkTimer = cursorBlinkTimer + dt
	if cursorBlinkTimer > cursorBlinkDuration then
		cursorBlinkTimer = 0
	end

	uiSec = uiSec + dt
	if uiSec > 1 then
		uiSec = 0
		local changeDetected = false
		local changedPlayers = {}
		local teams = Spring.GetTeamList()
		for _, teamID in ipairs(teams) do
			local r, g, b = spGetTeamColor(teamID)
			local key = r .. '_' .. g .. '_' .. b
			if teamColorKeys[teamID] ~= key then
				teamColorKeys[teamID] = key
				changeDetected = true
				for _, playerID in ipairs(Spring.GetPlayerList(teamID)) do
					local name = spGetPlayerInfo(playerID, false)
					name = ((WG.playernames and WG.playernames.getPlayername) and WG.playernames.getPlayername(playerID)) or name
					changedPlayers[name] = true
				end
			end
		end
		if changeDetected then
			for i = 1, #chatLines do
				if changedPlayers[chatLines[i].playerName] then
					chatLines[i].playerNameText = getColoredPlayerName(chatLines[i].playerName, chatLines[i].gameFrame, chatLines[i].lineType == LineTypes.Spectator)
				end
			end
			needsUiRefresh = true
		end
		if WG.ignoredAccounts then
			for accountID_or_name, _ in pairs(ignoredAccounts) do
				if not WG.ignoredAccounts[accountID_or_name] then
					for i = 1, #chatLines do
						if chatLines[i].playerName == accountID_or_name then
							chatLines[i].ignore = nil
						end
					end
				end
			end
			for accountID_or_name, _ in pairs(WG.ignoredAccounts) do
				if not ignoredAccounts[accountID_or_name] then
					for i = 1, #chatLines do
						if chatLines[i].playerName == accountID_or_name then
							chatLines[i].ignore = true
						end
					end
				end
			end
			ignoredAccounts = shallowCopyTable(WG.ignoredAccounts)
			needsUiRefresh = true
		end
		if not addedOptionsList and WG['options'] and WG['options'].getOptionsList then
			local optionsList = WG['options'].getOptionsList()
			if optionsList and #optionsList > 0 then
				addedOptionsList = true
				for _, option in ipairs(optionsList) do
					autocompleteCommands[#autocompleteCommands + 1] = 'option ' .. option
				end
			end
		end
		if hideSpecChat ~= (Spring.GetConfigInt('HideSpecChat', 0) == 1) or hideSpecChatPlayer ~= (Spring.GetConfigInt('HideSpecChatPlayer', 1) == 1) then
			hideSpecChat = (Spring.GetConfigInt('HideSpecChat', 0) == 1)
			hideSpecChatPlayer = (Spring.GetConfigInt('HideSpecChatPlayer', 1) == 1)
			for i = 1, #chatLines do
				if chatLines[i].lineType == LineTypes.Spectator then
					if shouldHideSpecMessage() then
						chatLines[i].ignore = true
					else
						chatLines[i].ignore = WG.ignoredAccounts and WG.ignoredAccounts[chatLines[i].playerName] and true or nil
					end
				elseif chatLines[i].lineType == LineTypes.Mapmark then
					local spectator = playernames[chatLines[i].playerName] and playernames[chatLines[i].playerName][2] or false
					if spectator then
						if shouldHideSpecMessage() then
							chatLines[i].ignore = true
						else
							chatLines[i].ignore = WG.ignoredAccounts and WG.ignoredAccounts[chatLines[i].playerName] and true or nil
						end
					end
				end
			end
			needsUiRefresh = true
		end
	end

	local x, y = spGetMouseState()
	local hoveredHistory = false
	if WG['topbar'] and WG['topbar'].showingQuit() then
		historyMode = false
		setCurrentChatLine(#chatLines)
	elseif x >= activationArea[1] and y >= activationArea[2] and x <= activationArea[3] and y <= activationArea[4] then
		local alt, ctrl, meta, shift = Spring.GetModKeyState()
		if showHistoryWhenCtrlShift and ctrl and shift then
			if x >= consoleActivationArea[1] and y >= consoleActivationArea[2] and x <= consoleActivationArea[3] and y <= consoleActivationArea[4] then
				historyMode = 'console'
			else
				historyMode = 'chat'
			end
			maxLinesScroll = maxLinesScrollFull
		end
		hoveredHistory = historyMode and true or false
	elseif historyMode then
		if not showHistoryWhenChatInput or not showTextInput then
			historyMode = false
			setCurrentChatLine(#chatLines)
		end
	end
	if hoveredHistory ~= prevHoveredHistory then
		needsUiRefresh = true
		prevHoveredHistory = hoveredHistory
	end

	if #consoleLines > consoleLineCleanupTarget * 1.15 then
		consoleLines = cleanupLineTable(consoleLines, consoleLineCleanupTarget)
		currentConsoleLine = #consoleLines
		needsUiRefresh = true
	end
	if #orgLines > orgLineCleanupTarget * 1.15 then
		orgLines = cleanupLineTable(orgLines, orgLineCleanupTarget)
		needsUiRefresh = true
	end
	if needsUiRefresh or (historyMode and mathFloor(os.clock() * 4) % 4 == 0) then
		refreshDocumentModel()
	end
end

function widget:RecvLuaMsg(msg)
	if msg:sub(1, 18) == 'LobbyOverlayActive' then
		chobbyInterface = (msg:sub(1, 19) == 'LobbyOverlayActive1')
		if document then
			if chobbyInterface then
				document:Hide()
			else
				document:Show()
				Spring.SDLStartTextInput()
			end
		end
	end
end

function widget:TextInput(char)
	if handleTextInput and not chobbyInterface and not Spring.IsGUIHidden() and showTextInput then
		if inputSelectionStart and inputSelectionStart ~= inputTextPosition then
			local selStart = mathMin(inputSelectionStart, inputTextPosition)
			local selEnd = mathMax(inputSelectionStart, inputTextPosition)
			inputText = utf8.sub(inputText, 1, selStart) .. utf8.sub(inputText, selEnd + 1)
			inputTextPosition = selStart
			inputSelectionStart = nil
		end
		if inputTextInsertActive then
			inputText = utf8.sub(inputText, 1, inputTextPosition) .. char .. utf8.sub(inputText, inputTextPosition + 2)
			if inputTextPosition <= utf8.len(inputText) then
				inputTextPosition = inputTextPosition + 1
			end
		else
			inputText = utf8.sub(inputText, 1, inputTextPosition) .. char .. utf8.sub(inputText, inputTextPosition + 1)
			inputTextPosition = inputTextPosition + 1
		end
		if string.len(inputText) > maxTextInputChars then
			inputText = string.sub(inputText, 1, maxTextInputChars)
			if inputTextPosition > maxTextInputChars then
				inputTextPosition = maxTextInputChars
			end
		end
		inputHistory[#inputHistory] = inputText
		cursorBlinkTimer = 0
		autocomplete(inputText)
		needsUiRefresh = true
		if WG['limitidlefps'] and WG['limitidlefps'].update then
			WG['limitidlefps'].update()
		end
		return true
	end
end

function widget:KeyRelease()
	return false
end

function widget:KeyPress(key)
	if Spring.IsGUIHidden() or not handleTextInput then
		return
	end
	local alt, ctrl, _, shift = Spring.GetModKeyState()
	if key == 13 then
		if showTextInput then
			if ctrl or alt or shift then
				if ctrl then
					inputMode = ''
				elseif alt and not mySpec then
					inputMode = (inputMode == 'a:' and '' or 'a:')
				else
					inputMode = (inputMode == 's:' and '' or 's:')
				end
			else
				if inputText ~= '' then
					if string.sub(inputText, 1, 1) == '/' then
						Spring.SendCommands(string.sub(inputText, 2))
					else
						local badWord = findBadWords(inputText)
						if badWord ~= nil and inputText ~= lastMessage then
							addChatLine(Spring.GetGameFrame(), LineTypes.System, "Moderation", Spring.I18N('ui.chat.moderation.prefix'), Spring.I18N('ui.chat.moderation.blocked', { badWord = badWord }), nil, false, true)
						else
							Spring.SendCommands("say " .. (inputMode or '') .. inputText)
						end
						lastMessage = inputText
					end
					for i = #inputHistory - 1, 1, -1 do
						if inputHistory[i] == inputText then
							table.remove(inputHistory, i)
							break
						end
					end
				end
				cancelChatInput()
			end
		else
			widget:OpenInput(ctrl, alt, shift)
		end
		needsUiRefresh = true
		return true
	end
	if not showTextInput then
		return false
	end
	if ctrl and key == 118 then
		if inputSelectionStart and inputSelectionStart ~= inputTextPosition then
			local selStart = mathMin(inputSelectionStart, inputTextPosition)
			local selEnd = mathMax(inputSelectionStart, inputTextPosition)
			inputText = utf8.sub(inputText, 1, selStart) .. utf8.sub(inputText, selEnd + 1)
			inputTextPosition = selStart
			inputSelectionStart = nil
		end
		local clipboardText = spGetClipboard() or ''
		inputText = utf8.sub(inputText, 1, inputTextPosition) .. clipboardText .. utf8.sub(inputText, inputTextPosition + 1)
		inputTextPosition = inputTextPosition + utf8.len(clipboardText)
		if string.len(inputText) > maxTextInputChars then
			inputText = string.sub(inputText, 1, maxTextInputChars)
			if inputTextPosition > maxTextInputChars then
				inputTextPosition = maxTextInputChars
			end
		end
		inputHistory[#inputHistory] = inputText
		cursorBlinkTimer = 0
		autocomplete(inputText, true)
	elseif ctrl and key == 99 then
		if inputSelectionStart and inputSelectionStart ~= inputTextPosition then
			local selStart = mathMin(inputSelectionStart, inputTextPosition)
			local selEnd = mathMax(inputSelectionStart, inputTextPosition)
			local selectedText = utf8.sub(inputText, selStart + 1, selEnd)
			spSetClipboard(selectedText)
		end
	elseif ctrl and key == 120 then
		if inputSelectionStart and inputSelectionStart ~= inputTextPosition then
			local selStart = mathMin(inputSelectionStart, inputTextPosition)
			local selEnd = mathMax(inputSelectionStart, inputTextPosition)
			local selectedText = utf8.sub(inputText, selStart + 1, selEnd)
			spSetClipboard(selectedText)
			inputText = utf8.sub(inputText, 1, selStart) .. utf8.sub(inputText, selEnd + 1)
			inputTextPosition = selStart
			inputSelectionStart = nil
			inputHistory[#inputHistory] = inputText
			cursorBlinkTimer = 0
			autocomplete(inputText, true)
		end
	elseif ctrl and key == 97 then
		inputSelectionStart = 0
		inputTextPosition = utf8.len(inputText)
		cursorBlinkTimer = 0
	elseif ctrl and key == 276 then
		if shift then
			if not inputSelectionStart then
				inputSelectionStart = inputTextPosition
			end
		else
			inputSelectionStart = nil
		end
		local pos = inputTextPosition
		while pos > 0 and utf8.sub(inputText, pos, pos):match("%s") do
			pos = pos - 1
		end
		while pos > 0 and not utf8.sub(inputText, pos, pos):match("%s") do
			pos = pos - 1
		end
		inputTextPosition = pos
		cursorBlinkTimer = 0
	elseif ctrl and key == 275 then
		if shift then
			if not inputSelectionStart then
				inputSelectionStart = inputTextPosition
			end
		else
			inputSelectionStart = nil
		end
		local textLen = utf8.len(inputText)
		local pos = inputTextPosition
		while pos < textLen and not utf8.sub(inputText, pos + 1, pos + 1):match("%s") do
			pos = pos + 1
		end
		while pos < textLen and utf8.sub(inputText, pos + 1, pos + 1):match("%s") do
			pos = pos + 1
		end
		inputTextPosition = pos
		cursorBlinkTimer = 0
	elseif not alt and not ctrl then
		if key == 27 then
			cancelChatInput()
		elseif key == 8 then
			if inputSelectionStart and inputSelectionStart ~= inputTextPosition then
				local selStart = mathMin(inputSelectionStart, inputTextPosition)
				local selEnd = mathMax(inputSelectionStart, inputTextPosition)
				inputText = utf8.sub(inputText, 1, selStart) .. utf8.sub(inputText, selEnd + 1)
				inputTextPosition = selStart
				inputSelectionStart = nil
				inputHistory[#inputHistory] = inputText
				prevAutocompleteLetters = nil
			elseif inputTextPosition > 0 then
				inputText = utf8.sub(inputText, 1, inputTextPosition - 1) .. utf8.sub(inputText, inputTextPosition + 1)
				inputTextPosition = inputTextPosition - 1
				inputHistory[#inputHistory] = inputText
				if not (prevAutocompleteLetters and inputTextPosition == #inputText and string.sub(inputText, #inputText) ~= ' ') then
					prevAutocompleteLetters = nil
				end
			end
			cursorBlinkTimer = 0
			autocomplete(inputText, not prevAutocompleteLetters)
		elseif key == 127 then
			if inputSelectionStart and inputSelectionStart ~= inputTextPosition then
				local selStart = mathMin(inputSelectionStart, inputTextPosition)
				local selEnd = mathMax(inputSelectionStart, inputTextPosition)
				inputText = utf8.sub(inputText, 1, selStart) .. utf8.sub(inputText, selEnd + 1)
				inputTextPosition = selStart
				inputSelectionStart = nil
				inputHistory[#inputHistory] = inputText
			elseif inputTextPosition < utf8.len(inputText) then
				inputText = utf8.sub(inputText, 1, inputTextPosition) .. utf8.sub(inputText, inputTextPosition + 2)
				inputHistory[#inputHistory] = inputText
			end
			cursorBlinkTimer = 0
			autocomplete(inputText, true)
		elseif key == 277 then
			inputTextInsertActive = not inputTextInsertActive
		elseif key == 276 then
			if shift then
				if not inputSelectionStart then
					inputSelectionStart = inputTextPosition
				end
			else
				inputSelectionStart = nil
			end
			inputTextPosition = mathMax(0, inputTextPosition - 1)
			cursorBlinkTimer = 0
		elseif key == 275 then
			if shift then
				if not inputSelectionStart then
					inputSelectionStart = inputTextPosition
				end
			else
				inputSelectionStart = nil
			end
			inputTextPosition = mathMin(utf8.len(inputText), inputTextPosition + 1)
			cursorBlinkTimer = 0
		elseif key == 278 or key == 280 then
			if shift then
				if not inputSelectionStart then
					inputSelectionStart = inputTextPosition
				end
			else
				inputSelectionStart = nil
			end
			inputTextPosition = 0
			cursorBlinkTimer = 0
		elseif key == 279 or key == 281 then
			if shift then
				if not inputSelectionStart then
					inputSelectionStart = inputTextPosition
				end
			else
				inputSelectionStart = nil
			end
			inputTextPosition = utf8.len(inputText)
			cursorBlinkTimer = 0
		elseif key == 273 then
			inputSelectionStart = nil
			inputHistoryCurrent = inputHistoryCurrent - 1
			if inputHistoryCurrent < 1 then
				inputHistoryCurrent = 1
			end
			if inputHistory[inputHistoryCurrent] then
				inputText = inputHistory[inputHistoryCurrent]
				inputHistory[#inputHistory] = inputText
			end
			inputTextPosition = utf8.len(inputText)
			cursorBlinkTimer = 0
			autocomplete(inputText, true)
		elseif key == 274 then
			inputSelectionStart = nil
			inputHistoryCurrent = inputHistoryCurrent + 1
			if inputHistoryCurrent >= #inputHistory then
				inputHistoryCurrent = #inputHistory
			end
			inputText = inputHistory[inputHistoryCurrent] or ''
			inputTextPosition = utf8.len(inputText)
			cursorBlinkTimer = 0
			autocomplete(inputText, true)
		elseif key == 9 then
			inputSelectionStart = nil
			if autocompleteText then
				inputText = utf8.sub(inputText, 1, inputTextPosition) .. autocompleteText .. utf8.sub(inputText, inputTextPosition + 1)
				inputTextPosition = inputTextPosition + utf8.len(autocompleteText)
				inputHistory[#inputHistory] = inputText
				autocompleteText = nil
				autocompleteWords = {}
			end
		end
	end
	needsUiRefresh = true
	return true
end

function widget:MouseWheel(up)
	if historyMode and not Spring.IsGUIHidden() then
		local _, ctrl, _, shift = Spring.GetModKeyState()
		local amount = (shift and maxLinesScroll or (ctrl and 3 or 1))
		widget:ScrollHistory(up, amount)
		return true
	end
	return false
end

function widget:WorldTooltip()
	local x, y = spGetMouseState()
	if #chatLines > 0 and x >= activationArea[1] and y >= activationArea[2] and x <= activationArea[3] and y <= activationArea[4] then
		return I18N.scroll
	end
end

function widget:MapDrawCmd(playerID, cmdType, x, y, z)
	if cmdType == 'point' then
		lastMapmarkCoords = { x, y, z }
	end
end

function widget:AddConsoleLine(lines, priority)
	if priority and priority == L_DEPRECATED and not isDevSingle then
		return
	end
	lines = lines:match('^%[f=[0-9]+%] (.*)$') or lines
	for line in lines:gmatch("[^\n]+") do
		processAddConsoleLine(spGetGameFrame(), line)
	end
	needsUiRefresh = true
end

function widget:ViewResize()
	vsx, vsy = Spring.GetViewGeometry()
	local widgetScale = vsy * 0.00075 * config.ui_scale
	local charSize = 21 * mathClamp(1 + ((1 - (vsy / 1200)) * 0.5), 1, 1.2)
	usedFontSize = charSize * fontsizeMult * widgetScale
	usedConsoleFontSize = usedFontSize * config.consoleFontSizeMult
	lineHeight = mathFloor(usedFontSize * config.lineHeightMult)
	consoleLineHeight = mathFloor(usedConsoleFontSize * config.lineHeightMult)
	backgroundPadding = mathMax(8, mathFloor(lineHeight * 0.5))
	local posY2 = 0.94
	if WG['topbar'] and WG['topbar'].GetPosition then
		topbarArea = WG['topbar'].GetPosition()
		posY2 = mathFloor(topbarArea[2] - 4) / vsy
		posX = topbarArea[1] / vsx
		scrollingPosY = mathFloor(topbarArea[2] - 4 - backgroundPadding - backgroundPadding - (lineHeight * maxLinesScroll)) / vsy
	end
	consolePosY = mathFloor((vsy * posY2) - backgroundPadding - (maxConsoleLines * consoleLineHeight)) / vsy
	posY = mathFloor((consolePosY * vsy) - (backgroundPadding * 1.5) - ((lineHeight * maxLines))) / vsy
	activationArea = {
		mathFloor(vsx * posX),
		mathFloor(vsy * posY),
		mathFloor(vsx * posX2),
		mathFloor(vsy * posY2),
	}
	consoleActivationArea = {
		mathFloor(vsx * posX),
		mathFloor(vsy * consolePosY),
		mathFloor(vsx * posX2),
		mathFloor(vsy * posY2),
	}
	needsUiRefresh = true
	refreshRootStyle()
end

function widget:PlayerChanged(playerID)
	mySpec = spGetSpectatingState()
	myTeamID = spGetMyTeamID()
	myAllyTeamID = Spring.GetMyAllyTeamID()
	if mySpec and inputMode == 'a:' then
		inputMode = 's:'
	end
	local name, _, isSpec = spGetPlayerInfo(playerID, false)
	if not playernames[name] then
		widget:PlayerAdded(playerID)
	else
		if isSpec ~= playernames[name].isSpec then
			playernames[name][2] = isSpec
			if isSpec then
				playernames[name][8] = Spring.GetGameFrame()
			end
		end
	end
	needsUiRefresh = true
end

function widget:PlayerAdded(playerID)
	local name, _, isSpec, teamID, allyTeamID = spGetPlayerInfo(playerID, false)
	local historyName = ((WG.playernames and WG.playernames.getPlayername) and WG.playernames.getPlayername(playerID)) or name
	playernames[name] = { allyTeamID, isSpec, teamID, playerID, not isSpec and { spGetTeamColor(teamID) }, ColorIsDark and ColorIsDark(spGetTeamColor(teamID)) or false, historyName }
	autocompletePlayernames[#autocompletePlayernames + 1] = name
	if historyName ~= name then
		autocompletePlayernames[#autocompletePlayernames + 1] = historyName
	end
	needsUiRefresh = true
end

function widget:Initialize()
	Spring.SDLStartTextInput()
	if not ColorString and Spring.Utilities and Spring.Utilities.Color then
		ColorString = Spring.Utilities.Color.ToString
		ColorIsDark = Spring.Utilities.Color.ColorIsDark
	end
	if WG.ignoredAccounts then
		ignoredAccounts = shallowCopyTable(WG.ignoredAccounts)
	end
	local gaiaTeamID = Spring.GetGaiaTeamID()
	local teams = Spring.GetTeamList()
	for _, teamID in ipairs(teams) do
		local r, g, b = spGetTeamColor(teamID)
		local _, playerID, _, isAiTeam, _, allyTeamID = spGetTeamInfo(teamID, false)
		teamColorKeys[teamID] = r .. '_' .. g .. '_' .. b
		local aiName
		if isAiTeam then
			aiName = getAIName(teamID)
			playernames[aiName] = { allyTeamID, false, teamID, playerID, { r, g, b }, ColorIsDark and ColorIsDark(r, g, b) or false, aiName }
		end
		if teamID == gaiaTeamID then
			teamNames[teamID] = "Gaia"
		else
			if isAiTeam then
				teamNames[teamID] = aiName
			else
				local name, _, spec = spGetPlayerInfo(playerID, false)
				name = ((WG.playernames and WG.playernames.getPlayername) and WG.playernames.getPlayername(playerID)) or name
				if not spec then
					teamNames[teamID] = name
				end
			end
		end
	end
	for _, playerID in ipairs(Spring.GetPlayerList()) do
		widget:PlayerAdded(playerID)
	end
	widget:PlayerChanged(Spring.GetMyPlayerID())
	widget:ViewResize()
	Spring.SendCommands("console 0")

	context = RmlUi.GetContext("shared")
	dm = context:OpenDataModel(modelName, dataModel)
	if not dm then
		spEcho("RmlUi: failed to open data model", modelName)
		return
	end
	document = context:LoadDocument("LuaUi/RmlWidgets/chat/chat.rml", widget)
	if not document then
		spEcho("RmlUi: failed to load chat document")
		context:RemoveDataModel(modelName)
		dm = nil
		return
	end
	document:Show()
	refreshRootStyle()

	WG['chat'] = {}
	WG['chat'].isInputActive = function() return showTextInput end
	WG['chat'].getInputButton = function() return inputButton end
	WG['chat'].setHide = function(value) hide = value; needsUiRefresh = true end
	WG['chat'].getHide = function() return hide end
	WG['chat'].setChatInputHistory = function(value) showHistoryWhenChatInput = value; needsUiRefresh = true end
	WG['chat'].getChatInputHistory = function() return showHistoryWhenChatInput end
	WG['chat'].setInputButton = function(value) inputButton = value; needsUiRefresh = true end
	WG['chat'].getHandleInput = function() return handleTextInput end
	WG['chat'].setHandleInput = function(value)
		handleTextInput = value
		if not handleTextInput then
			cancelChatInput()
		end
		Spring.SDLStartTextInput()
		needsUiRefresh = true
	end
	WG['chat'].getChatVolume = function() return sndChatFileVolume end
	WG['chat'].setChatVolume = function(value) sndChatFileVolume = value; needsUiRefresh = true end
	WG['chat'].getBackgroundOpacity = function() return backgroundOpacity end
	WG['chat'].setBackgroundOpacity = function(value) backgroundOpacity = value; needsUiRefresh = true end
	WG['chat'].getMaxLines = function() return maxLines end
	WG['chat'].setMaxLines = function(value) maxLines = value; widget:ViewResize() end
	WG['chat'].getMaxConsoleLines = function() return maxConsoleLines end
	WG['chat'].setMaxConsoleLines = function(value) maxConsoleLines = value; widget:ViewResize() end
	WG['chat'].getFontsize = function() return fontsizeMult end
	WG['chat'].setFontsize = function(value) fontsizeMult = value; widget:ViewResize() end
	WG['chat'].addChatLine = function(gameFrame, lineType, name, nameText, text, orgLineID, ignore)
		addChatLine(gameFrame, lineType, name, nameText, text, orgLineID, ignore, true)
		needsUiRefresh = true
	end
	WG['chat'].addChatProcessor = function(id, func)
		if type(func) == 'function' then
			chatProcessors[id] = func
		end
	end
	WG['chat'].removeChatProcessor = function(id)
		chatProcessors[id] = nil
	end

	for orgLineID, params in ipairs(orgLines) do
		processAddConsoleLine(params[1], params[2], orgLineID)
	end

	widgetHandler.actionHandler:AddAction(self, "clearconsole", clearconsoleCmd, nil, 't')
	widgetHandler.actionHandler:AddAction(self, "hidespecchat", hidespecchatCmd, nil, 't')
	widgetHandler.actionHandler:AddAction(self, "hidespecchatplayer", hidespecchatplayerCmd, nil, 't')
	widgetHandler.actionHandler:AddAction(self, "preventhistorymode", preventhistorymodeCmd, nil, 't')

	refreshDocumentModel()
end

function widget:Shutdown()
	WG['chat'] = nil
	if document then
		document:Close()
		document = nil
	end
	if context and dm then
		context:RemoveDataModel(modelName)
		dm = nil
	end
	widgetHandler.actionHandler:RemoveAction(self, "clearconsole")
	widgetHandler.actionHandler:RemoveAction(self, "hidespecchat")
	widgetHandler.actionHandler:RemoveAction(self, "hidespecchatplayer")
	widgetHandler.actionHandler:RemoveAction(self, "preventhistorymode")
end

function widget:GameOver()
end

function widget:GetConfigData()
	local inputHistoryLimited = {}
	for k, v in ipairs(inputHistory) do
		if k >= (#inputHistory - 50) then
			inputHistoryLimited[#inputHistoryLimited + 1] = v
		end
	end
	local maxOrgLines = orgLineCleanupTarget
	if #orgLines > maxOrgLines then
		local prunedOrgLines = {}
		for i = 1, maxOrgLines do
			prunedOrgLines[i] = orgLines[(#orgLines - maxOrgLines) + i]
		end
		orgLines = prunedOrgLines
	end
	return {
		gameFrame = Spring.GetGameFrame(),
		gameID = Game.gameID and Game.gameID or Spring.GetGameRulesParam("GameID"),
		orgLines = orgLines,
		inputHistory = inputHistoryLimited,
		maxLines = maxLines,
		maxConsoleLines = maxConsoleLines,
		fontsizeMult = fontsizeMult,
		chatBackgroundOpacity = backgroundOpacity,
		sndChatFileVolume = sndChatFileVolume,
		shutdownTime = os.clock(),
		handleTextInput = handleTextInput,
		inputButton = inputButton,
		hide = hide,
		showHistoryWhenChatInput = showHistoryWhenChatInput,
		showHistoryWhenCtrlShift = showHistoryWhenCtrlShift,
		enableShortcutClick = enableShortcutClick,
		soundErrors = soundErrors,
		playernames = playernames,
		version = 2,
	}
end

function widget:SetConfigData(data)
	if data.orgLines ~= nil then
		if Spring.GetGameFrame() > 0 or (data.gameID and data.gameID == (Game.gameID and Game.gameID or Spring.GetGameRulesParam("GameID"))) then
			if data.playernames then
				playernames = data.playernames
			end
			orgLines = data.orgLines
			if data.soundErrors then
				soundErrors = data.soundErrors
			end
		end
	end
	if data.inputHistory ~= nil then
		inputHistory = data.inputHistory
		inputHistoryCurrent = #inputHistory
	end
	if data.sndChatFileVolume ~= nil then sndChatFileVolume = data.sndChatFileVolume end
	if data.showHistoryWhenCtrlShift ~= nil then showHistoryWhenCtrlShift = data.showHistoryWhenCtrlShift end
	if data.enableShortcutClick ~= nil then enableShortcutClick = data.enableShortcutClick end
	if data.chatBackgroundOpacity ~= nil then backgroundOpacity = data.chatBackgroundOpacity end
	if data.hide ~= nil then hide = data.hide end
	if data.showHistoryWhenChatInput ~= nil then showHistoryWhenChatInput = data.showHistoryWhenChatInput end
	if data.maxLines ~= nil then maxLines = data.maxLines end
	if data.maxConsoleLines ~= nil then maxConsoleLines = data.maxConsoleLines end
	if data.fontsizeMult ~= nil then fontsizeMult = data.fontsizeMult end
	if data.inputButton ~= nil then inputButton = data.inputButton end
	if data.version ~= nil and data.handleTextInput ~= nil then handleTextInput = data.handleTextInput end
	needsUiRefresh = true
end
