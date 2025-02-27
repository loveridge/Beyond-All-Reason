-- zoomto keybind will zoom into the mouse position, unless the mouse button movement is activated
-- Example:
-- bind  Any+sc_;  zoomto 300
-- bind  Any+sc_'  zoomto 10000

function widget:GetInfo()
	return {
		name = "Zoom Keybinds",
		desc = "Adds keybinds for zoom",
		author = "lov",
		date = "February 2025",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
		handler = true,
	}
end

local smoothnessBoost = 1

local function zoomTo(_, _, args, alwaysCenter)
	local distance = args and tonumber(args[1])
	if not distance then
		return
	end

	local newState = {dist=distance, height=distance}

	local cs = Spring.GetCameraState()
	local height = cs.height
	if not height then
		height = cs.dist
	end
	if height > distance then
		local mx, my, lmbp, mmbp, rmbp, offscreen, mmbscroll = Spring.GetMouseState()
		if not mmbscroll and not mmbp and not alwaysCenter then
			local _, pos = Spring.TraceScreenRay(mx,my,true)
			if not pos or not pos[1] then
				return
			end
			newState.px = pos[1]
			newState.py = pos[2]
			newState.pz = pos[3]
		end
	end
	local transitionTime = .1
	if WG['options'] and WG['options'].getCameraSmoothness then
		transitionTime = WG['options'].getCameraSmoothness() * smoothnessBoost
	end
	Spring.SetCameraState(newState, transitionTime)
	return true
end

local function zoomToCenter(_, _, args)
	return zoomTo(_, _, args, true)
end

function widget:Initialize()
	widgetHandler.actionHandler:AddAction(self, "zoomto", zoomTo, nil, "p")
	widgetHandler.actionHandler:AddAction(self, "zoomtocenter", zoomToCenter, nil, "p")
end
