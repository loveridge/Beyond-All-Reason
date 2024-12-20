function widget:GetInfo()
	return {
		name = "Curve Editor",
		desc = "",
		author = "lov",
		date = "2024",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = false
	}
end

local msx = Game.mapSizeX
local msz = Game.mapSizeZ

local GetTeamColor = Spring.GetTeamColor

local luaShaderDir = "LuaUI/Widgets/Include/"
local LuaShader = VFS.Include(luaShaderDir .. "LuaShader.lua")
VFS.Include(luaShaderDir .. "instancevbotable.lua")

GL.KEEP = 0x1E00
GL.INCR_WRAP = 0x8507
GL.DECR_WRAP = 0x8508
GL.INCR = 0x1E02
GL.DECR = 0x1E03
GL.INVERT = 0x150A
local abs = math.abs

local coopStartPoints = {} -- will contain data passed through by coop gadget

local startposShader
local startposVS = [[
  #version 420
  #line 10000
  //__DEFINES__
  layout (location = 0) in vec4 pos;
  layout (location = 1) in vec3 normals;
  layout (location = 2) in vec2 uvs;
  layout (location = 3) in vec4 teamcolor;
  layout (location = 4) in vec3 wpos;

  layout (location = 5) in vec3 forward;
  //layout (location = 6) in vec3 right;
  //layout (location = 7) in vec3 up;


  uniform sampler2D heightmapTex;
  out DataVS {
    vec3 objPos;
	vec3 worldPos;
    vec4 color;
  };
  //__ENGINEUNIFORMBUFFERDEFS__
  #line 11000
  float heightAtWorldPos(vec2 w){
    vec2 uvhm = vec2(clamp(w.x,8.0,mapSize.x-8.0),clamp(w.y,8.0, mapSize.y-8.0))/ mapSize.xy;
    return textureLod(heightmapTex, uvhm, 0.0).x;
  }
  void main() {
	objPos = pos.xyz;
    worldPos = wpos;
	color = teamcolor;
	vec3 newpos = vec3(pos.x, -pos.z, pos.y);
	vec3 nforward = normalize(forward);
	vec3 right = normalize(cross(nforward, vec3(0, -1, 0)));
	vec3 up = cross(right, nforward);
	mat3 rotation = mat3(right, up, nforward);
	gl_Position = cameraViewProj * vec4(wpos.xyz + rotation * newpos.xyz, 1.0);
  }
]]
local startposFS = [[
#version 330
  #extension GL_ARB_uniform_buffer_object : require
  #extension GL_ARB_shading_language_420pack: require
  #line 20000
  in vec4 gl_FragCoord;
  uniform sampler2D heightmapTex;
  uniform float elatime;
  uniform float height;
  //__ENGINEUNIFORMBUFFERDEFS__
  //__DEFINES__
  in DataVS {
    vec3 objPos;
	vec3 worldPos;
    vec4 color;
  };
  out vec4 fragColor;
  float heightAtWorldPos(vec2 w){
    vec2 uvhm = vec2(clamp(w.x,8.0,mapSize.x-8.0),clamp(w.y,8.0, mapSize.y-8.0))/ mapSize.xy;
    return textureLod(heightmapTex, uvhm, 0.0).x;
  }
  void main() {
	float range = 400.0 - sin(elatime) * 100.0;
	float height01 = 1.0 - objPos.y / height;
	float heightfade = height01 * height01;// * height01;
	float scaler = heightfade + heightfade * ((sin(elatime + objPos.y / 100.0)) + 0.3) * 0.5;
	float cutzero = sign(objPos.y);
	fragColor = vec4(color.xyzw);//scaler * cutzero);
  }
]]

local defaultInterval = {
	name = "default",
	runtime = 10000,
	dollymode = 1,
	relativemode = 1,
	lookmode = 1,
	position = { 600, 600, 600 },
	curve = {
		degree = 3,
		controlPoints = { 5681.79736, 740.087708, 5024.29248, 1, 4687.32471, 582.756775, 3214.92188, 1, 7622.63623, 521.41449, 1362.89307, 1, 9532.92773, 705.304077, 3649.56982, 1, 7732.88379, 445.317993, 5839.67432, 1 },
		knots = { 0, 0, 0, 0, .5, 1, 1, 1, 1 }
	},
	lookPosition = { 400, 400, 400 },
	lookUnit = 1,
	lookCurve = {
		degree = 3,
		controlPoints = { 4925.31641, 238.964325, 8935.6123, 1, 6268.80273, 101.809639, 8370.02539, 1, 5690.72412, 125.194092, 6273.99219, 1, 5481.41943, 149.17244, 3295.37158, 1, 7315.03369, 237.346451, 2228.64331, 1 },
		knots = { 0, 0, 0, 0, .5, 1, 1, 1, 1 }
	}
}
local dollyIntervals = { defaultInterval }

local curvepointData = {}
local camconeData = {}
local curvelineData = {}
local context
local document
local updateInstanceData
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function shutdownVAOs()
	if startposShader then
		startposShader:Delete()
	end
	if curvepointData.vao then
		curvepointData.vao:Delete()
	end
end

local function goodbye(reason)
	Spring.Echo("DefenseRange GL4 widget exiting with reason: " .. reason)
	widgetHandler:RemoveWidget()
end

local currentInterval = 1
local curveControlPoints = dollyIntervals[1].curve.controlPoints
local nurbsKnots = dollyIntervals[1].curve.knots
local lookCPoints = dollyIntervals[1].lookCurve.controlPoints
local lookKnots = dollyIntervals[1].lookCurve.knots

local segments = 20
local relativeMode = 1
local cameraMode = 2
local cameraLookMode = 3
local lookUnitID = 21640
Spring.SetDollyCameraMode(cameraMode)
Spring.SetDollyCameraRelativeMode(relativeMode)
local points = Spring.SolveNURBSCurve(3, curveControlPoints, nurbsKnots, segments)
local lookPoints = Spring.SolveNURBSCurve(3, lookCPoints, lookKnots, segments)
Spring.SetDollyCameraCurve(3, curveControlPoints, nurbsKnots)
Spring.SetDollyCameraLookCurve(3, lookCPoints, lookKnots)
-- Spring.SetDollyCameraLookUnit(21640)
-- Spring.SetDollyCameraPosition(200, 200, 200)
-- Spring.SetDollyCameraLookPosition(200,400,200)
-- Spring.Debug.TableEcho(points)
local cpRad = 150
local hitindex = -1

local function split(s, delimiter)
	local result = {}
	for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
		table.insert(result, match)
	end
	return result
end

function widget:SetCamMode()
	local m = document:GetElementById('setdollymode'):GetAttribute("value")
	if m == '' then return end
	Spring.SetDollyCameraMode(m)
end

function widget:SetRunTime()
	local m = document:GetElementById('setruntime'):GetAttribute("value")
	if m == '' then return end
	dollyIntervals[currentInterval].runtime = tonumber(m)
end

function widget:SetCamRelativeMode()
	local m = document:GetElementById('setrelmode'):GetAttribute("value")
	if m == '' then return end
	Spring.Echo("relmode", m)
	cameraMode = m
	Spring.SetDollyCameraRelativeMode(m)
		points = Spring.SolveNURBSCurve(3, curveControlPoints, nurbsKnots, segments)
	updateInstanceData()
end

function widget:SetCamLookUnit()
	local id = document:GetElementById('setlookunit'):GetAttribute("value")
	if id == '' then return end
	Spring.SetDollyCameraLookUnit(tonumber(id))
end

function widget:SetCamLookPosition()
	local xyz = document:GetElementById('setlookpos'):GetAttribute("value")
	if xyz == '' then return end
	local s = split(xyz, ",")
	Spring.SetDollyCameraLookPosition(tonumber(s[1]), tonumber(s[2]), tonumber(s[3]))
end

local function addTo(vector, ...)
	for i = 1, select("#", ...) do
		local item = select(i, ...)
		if type(item) == "table" then
			for j = 1, #item do
				vector[#vector + 1] = item[j]
			end
		else
			vector[#vector + 1] = item
		end
	end
end


local dm
local dataModel = {
	changeCP = function(ev, curvename, index)
		local v = ev.current_element:GetAttribute("value")
		Spring.Echo("change", v, index)
		if v == '' then return end
		dollyIntervals[currentInterval].curve[curvename][index + 1] = tonumber(v)
		points = Spring.SolveNURBSCurve(3, curveControlPoints, nurbsKnots, segments)
		updateInstanceData()
	end,
	currentInterval = defaultInterval,
	allIntervals = dollyIntervals
}
local startboxInstanceData = {}
local coneData = {}
local lineData = {}
local spcount = 0
local linecount = 0
local conecount = 0
updateInstanceData = function()
	dm.currentInterval = defaultInterval
	startboxInstanceData = {}
	coneData = {}
	lineData = {}
	spcount = 0
	conecount = 0
	for i = 1, #points, 3 do
		spcount = spcount + 1
		addTo(startboxInstanceData, 0, 0, 1, .5)
		addTo(startboxInstanceData, points[i], points[i + 1], points[i + 2])
		addTo(startboxInstanceData, 1, 0, 0)
		conecount = conecount + 1
		addTo(coneData, 0, 0, 0, 1, 1)
		addTo(coneData, 1, 1, 1, 1)
		addTo(coneData, points[i], points[i + 1], points[i + 2])
		local x = points[i] - lookPoints[i]
		local y = points[i + 1] - lookPoints[i + 1]
		local z = points[i + 2] - lookPoints[i + 2]
		if cameraLookMode == 2 then
			local ux, uy, uz = Spring.GetUnitPosition(lookUnitID)
			if ux then
				x = points[i] - ux
				y = points[i + 1] - uy
				z = points[i + 2] - uz
			end
		end
		if x == 0 and y == 0 and z == 0 then z = -1 end
		addTo(coneData, -x, -y, -z)
		addTo(lineData, 0, 0, 0)
		addTo(lineData, 1, 1, 1)
		addTo(lineData, 1, 1)
		addTo(lineData, 1, 1, 1, 1)
		addTo(lineData, points[i], points[i + 1], points[i + 2])
		addTo(lineData, 1, 0, 0)
	end
	for i = 1, #lookPoints, 3 do
		spcount = spcount + 1
		addTo(startboxInstanceData, 0, 1, 0, .5)
		addTo(startboxInstanceData, lookPoints[i], lookPoints[i + 1], lookPoints[i + 2])
		addTo(startboxInstanceData, 1, 0, 0)
	end
	for i = 1, #curveControlPoints, 4 do
		spcount = spcount + 1
		local color = { 1, 0, 0, .5 }
		if i == 1 then
			color[2] = 1
		elseif i == #curveControlPoints - 3 then
			color[3] = 1
		end
		addTo(startboxInstanceData, color)
		addTo(startboxInstanceData, curveControlPoints[i], curveControlPoints[i + 1], curveControlPoints[i + 2])
		addTo(startboxInstanceData, 1, 0, 0)
	end
	for i = 1, #lookCPoints, 4 do
		spcount = spcount + 1
		local color = { 0, 1, 0, .5 }
		if i == 1 then
			color[3] = .5
		elseif i == #lookCPoints - 3 then
			color[3] = 1
		end
		addTo(startboxInstanceData, color)
		addTo(startboxInstanceData, lookCPoints[i], lookCPoints[i + 1], lookCPoints[i + 2])
		addTo(startboxInstanceData, 1, 0, 0)
	end
	curvepointData.instanceVBO:Upload(startboxInstanceData)
	camconeData.instanceVBO:Upload(coneData)
	curvelineData.vbo:Upload(lineData)
end


function widget:Initialize()
	local coneHeight = 900
	local engineUniformBufferDefs = LuaShader.GetEngineUniformBufferDefs()
	startposShader = LuaShader(
		{
			vertex = startposVS:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs),
			fragment = startposFS:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs),
			uniformInt = {
				heightmapTex = 0,
			},
			uniformFloat = {
				elatime = 0,
				height = coneHeight
			}
		}
	)
	local success = startposShader:Initialize()
	if not success then
		goodbye("Failed to compile startpos GL4 ")
		return false
	end


	curvepointData.vao = gl.GetVAO()
	local sphereVBO, numVerts, sphereIndexVBO, numIndex = makeSphereVBO(32, 16, cpRad)
	-- {id = 0, name = "position", size = 4},
	-- {id = 1, name = "normals", size = 3},
	-- {id = 2, name = "uvs", size = 2},
	curvepointData.vao:AttachVertexBuffer(sphereVBO)
	curvepointData.vao:AttachIndexBuffer(sphereIndexVBO)

	curvepointData.instanceVBO = gl.GetVBO(GL.ARRAY_BUFFER, true)
	-- curvepointData.instanceVBO:Define((segments + 1 + (#curveControlPoints / 4) * 2) * 7, {
	curvepointData.instanceVBO:Define((segments + 1 + (40 / 4) * 2) * 7, {
		{ id = 3, name = "color",   size = 4 },
		{ id = 4, name = "wpos",    size = 3 },
		{ id = 5, name = "forward", size = 3 },
	})

	curvepointData.vao:AttachInstanceBuffer(curvepointData.instanceVBO)
	curvepointData.vertCount = numIndex

	camconeData.vao = gl.GetVAO()
	local coneVBO, numVertices = makeConeVBO(32, 100, 50)

	camconeData.vao:AttachVertexBuffer(coneVBO)
	local indxVBO = gl.GetVBO(GL.ELEMENT_ARRAY_BUFFER, false)

	indxVBO:Define(numVertices, GL.UNSIGNED_INT)
	local indices = {}
	for i = 1, numVertices do
		indices[i] = i - 1
	end
	indxVBO:Upload(indices)
	camconeData.vao:AttachIndexBuffer(indxVBO)

	camconeData.instanceVBO = gl.GetVBO(GL.ARRAY_BUFFER, true)
	camconeData.instanceVBO:Define(segments * 7, {
		{ id = 1, name = "normals", size = 3 },
		{ id = 2, name = "uvs",     size = 2 },
		{ id = 3, name = "color",   size = 4 },
		{ id = 4, name = "wpos",    size = 3 },
		{ id = 5, name = "forward", size = 3 },
	})

	camconeData.vao:AttachInstanceBuffer(camconeData.instanceVBO)
	camconeData.vertCount = numVertices

	curvelineData.vao = gl.GetVAO()
	local linevbo = gl.GetVBO(GL.ARRAY_BUFFER, true)
	linevbo:Define(#points, {
		{ id = 0, name = "localpos_progress", size = 3 },
		{ id = 1, name = "normals",           size = 3 },
		{ id = 2, name = "uvs",               size = 2 },
		{ id = 3, name = "color",             size = 4 },
		{ id = 4, name = "wpos",              size = 3 },
		{ id = 5, name = "forward",           size = 3 }, })
	curvelineData.vao:AttachVertexBuffer(linevbo)
	indxVBO = gl.GetVBO(GL.ELEMENT_ARRAY_BUFFER, false)
	indxVBO:Define(#points, GL.UNSIGNED_INT)
	indices = {}
	for i = 1, #points do
		indices[i] = i - 1
	end
	indxVBO:Upload(indices)
	curvelineData.vao:AttachIndexBuffer(indxVBO)
	curvelineData.vbo = linevbo
	curvelineData.vertCount = #points

	context = RmlUi.GetContext("shared")
	dm = context:OpenDataModel("mm_dm", dataModel)
	document = context:LoadDocument("LuaUi/Widgets/rml_widget_assets/curves.rml", widget)
	document:Show()
	updateInstanceData()
end

function widget:Shutdown()
	shutdownVAOs()
	if document then
		document:Close()
	end
	if context then
		context:RemoveDataModel("mm_dm")
	end
end

function widget:AddCP()
	curveControlPoints[#curveControlPoints + 1] = curveControlPoints[#curveControlPoints - 3] + 100
	curveControlPoints[#curveControlPoints + 1] = curveControlPoints[#curveControlPoints - 3] + 100
	curveControlPoints[#curveControlPoints + 1] = curveControlPoints[#curveControlPoints - 3] + 100
	curveControlPoints[#curveControlPoints + 1] = 1
	local total = #nurbsKnots + 1
	for i = 1, total, 1 do
		nurbsKnots[i] = (i - 1) / (total - 1)
	end
	points = Spring.SolveNURBSCurve(3, curveControlPoints, nurbsKnots, segments)
	Spring.Echo(points, total, nurbsKnots)
	updateInstanceData()
end

local paused = false
function widget:RunCam()
	Spring.RunDollyCamera(dollyIntervals[currentInterval].runtime)
	paused = false
end

function widget:PauseCam()
	if paused then
		Spring.ResumeDollyCamera()
	else
		Spring.PauseDollyCamera()
	end
	paused = not paused
end

local draw = true
function widget:ToggleDraw()
	draw = not draw
end

local fadeFromBlack = false
function widget:KeyPress(key, modifier, isRepeat)
	-- Spring.Echo(key)
	if key == 111 then
		draw = not draw
		if not draw then
			Spring.RunDollyCamera(10000)
		end
	end
	if key == 112 then
		if paused then
			Spring.ResumeDollyCamera()
		else
			Spring.PauseDollyCamera()
		end
		paused = not paused
	end
	if not draw then
		fadeFromBlack = true
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local lastPathPos = { 0, 0, 0 }
local startDrag = { 0, 0 }
local heightDrag = false
local lookHit = false
local hitPoints
function widget:MousePress(x, y, button)
	if button == 2 or not draw then
		return
	end
	local mx, my = Spring.GetMouseState()
	for i = 2, #curveControlPoints, 4 do
		local sx, sy = Spring.WorldToScreenCoords(curveControlPoints[i - 1], curveControlPoints[i],
			curveControlPoints[i + 1])
		-- Spring.Echo(mx, my, sx, sy)
		-- if abs(sx - mx) < cpRad and abs(sy - my) < cpRad then
		local _, pos = Spring.TraceScreenRay(mx, my, true, false, true, false, curveControlPoints[i])
		if not pos then return end
		-- Spring.Echo(curveControlPoints[i - 1], curveControlPoints[i], curveControlPoints[i + 1], pos[1], pos[2], pos[3], pos[4], pos[5], pos[6])
		if abs(curveControlPoints[i - 1] - pos[4]) < cpRad and abs(curveControlPoints[i] - pos[5]) < cpRad and abs(curveControlPoints[i + 1] - pos[6]) < cpRad then
			Spring.Echo("hit", curveControlPoints[i - 1], curveControlPoints[i], curveControlPoints[i + 1])
			hitindex = i - 1
			lastPathPos[1] = curveControlPoints[i - 1]
			lastPathPos[2] = curveControlPoints[i]
			lastPathPos[3] = curveControlPoints[i + 1]
			startDrag[1] = mx
			startDrag[2] = my
			-- lastPathPos[1] = pos[4]
			-- lastPathPos[2] = pos[5]
			-- lastPathPos[3] = pos[6]
			hitPoints = curveControlPoints
		end
	end
	for i = 2, #lookCPoints, 4 do
		local sx, sy = Spring.WorldToScreenCoords(lookCPoints[i - 1], lookCPoints[i], lookCPoints[i + 1])
		-- Spring.Echo(mx, my, sx, sy)
		-- if abs(sx - mx) < cpRad and abs(sy - my) < cpRad then
		local _, pos = Spring.TraceScreenRay(mx, my, true, false, true, false, lookCPoints[i])
		if not pos then return end
		-- Spring.Echo(curveControlPoints[i - 1], curveControlPoints[i], curveControlPoints[i + 1], pos[1], pos[2], pos[3], pos[4], pos[5], pos[6])
		if abs(lookCPoints[i - 1] - pos[4]) < cpRad and abs(lookCPoints[i] - pos[5]) < cpRad and abs(lookCPoints[i + 1] - pos[6]) < cpRad then
			Spring.Echo("hit", curveControlPoints[i - 1], curveControlPoints[i], curveControlPoints[i + 1])
			hitindex = i - 1
			lastPathPos[1] = lookCPoints[i - 1]
			lastPathPos[2] = lookCPoints[i]
			lastPathPos[3] = lookCPoints[i + 1]
			startDrag[1] = mx
			startDrag[2] = my
			lookHit = true
			hitPoints = lookCPoints
			-- lastPathPos[1] = pos[4]
			-- lastPathPos[2] = pos[5]
			-- lastPathPos[3] = pos[6]
		end
	end
	if hitindex < 0 then
		return
	end
	return true
end

local function sign(val)
	if val == 0 then return 1 end
	return val / math.abs(val)
end

function widget:MouseMove(mx, my, dx, dy, mButton)
	if hitindex < 0 then
		return
	end
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	if ctrl then heightDrag = true else heightDrag = false end
	local _, pos = Spring.TraceScreenRay(mx, my, true, false, true, false, lastPathPos[2])
	if not pos then return end
	local mapy = Spring.GetGroundHeight(hitPoints[hitindex], hitPoints[hitindex + 2])
	local dx, dz = pos[4] - lastPathPos[1], pos[6] - lastPathPos[3]
	-- dx = mx - startDrag[1]
	-- dz = startDrag[2] - my
	-- Spring.Echo("moving", dx, dz, dx, dy)
	if heightDrag then
		hitPoints[hitindex + 1] = hitPoints[hitindex + 1] +
			math.sqrt(dx * dx + dz * dz) * sign(dy)
	else
		hitPoints[hitindex] = hitPoints[hitindex] + dx
		hitPoints[hitindex + 2] = hitPoints[hitindex + 2] + dz
	end
	if hitPoints[hitindex + 1] < mapy then hitPoints[hitindex + 1] = mapy + 5 end
	if lookHit then
		lookPoints = Spring.SolveNURBSCurve(3, lookCPoints, lookKnots, segments)
	else
		points = Spring.SolveNURBSCurve(3, curveControlPoints, nurbsKnots, segments)
	end


	lastPathPos[1] = pos[4]
	lastPathPos[2] = pos[5]
	lastPathPos[3] = pos[6]
	startDrag[1] = mx
	startDrag[2] = my
	updateInstanceData()
end

function widget:MouseRelease(x, y, button)
	if button == 2 then
		return
	end
	if hitindex < 0 then return end
	hitindex = -1
	if lookHit then
		lookPoints = Spring.SolveNURBSCurve(3, lookCPoints, lookKnots, segments)
		Spring.SetDollyCameraLookCurve(3, lookCPoints, lookKnots)
	else
		points = Spring.SolveNURBSCurve(3, curveControlPoints, nurbsKnots, segments)
		Spring.SetDollyCameraCurve(3, curveControlPoints, nurbsKnots)
	end
	Spring.Echo("set")
	local str = ""
	for index, value in ipairs(curveControlPoints) do
		str = str .. value .. ","
	end
	Spring.Echo(str)
	lookHit = false
	updateInstanceData()
end

function widget:DrawWorld()
	if not draw then return end
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)


	-- Spring.Debug.TableEcho(startboxInstanceData)
	if #startboxInstanceData > 1 then
		startposShader:Activate()
		gl.Culling(GL.FRONT)
		-- startposShader:SetUniformFloat("elatime", os.clock())
		curvelineData.vao:DrawArrays(GL.LINE_STRIP, curvelineData.vertCount, 0, conecount)
		camconeData.vao:DrawElements(GL.TRIANGLES, camconeData.vertCount, 0, conecount)
		curvepointData.vao:DrawElements(GL.TRIANGLES, curvepointData.vertCount, 0, spcount)
		-- gl.Culling(false)
		startposShader:Deactivate()
	end
end

-- local function DoSepia()
-- 	gl.CopyToTexture(screenCopyTex, 0, 0, vpx, vpy, vsx, vsy)
-- 	if screenCopyTex == nil then return end
-- 	gl.Texture(0, screenCopyTex)
-- 	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
-- 	sepiaShader:Activate()
-- 	sepiaShader:SetUniform("params", params.gamma, params.saturation, params.contrast, params.sepia)
-- 	fullTexQuad:DrawArrays(GL.TRIANGLES, 3)
-- 	sepiaShader:Deactivate()
-- 	gl.Blending(true)
-- 	gl.Texture(0, false)
-- end


-- function widget:DrawScreenEffects()
-- 	if params.shadeUI == false then DoSepia() end
-- end

-- function widget:Update(delta)
-- end
