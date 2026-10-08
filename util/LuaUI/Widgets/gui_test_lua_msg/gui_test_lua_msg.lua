-- luacheck: globals widget RmlUi CMD ---@type Widget
if not RmlUi then
    return
end

-- Cache Spring.* and CMD.* as local variables for optimization
local spGetAIInfo = Spring.GetAIInfo
local spGetGameRulesParam = Spring.GetGameRulesParam
local spGetTeamList = Spring.GetTeamList
local spGetTeamInfo = Spring.GetTeamInfo
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetMyTeamID = Spring.GetMyTeamID
local spGetViewGeometry = Spring.GetViewGeometry
local spSetConfigInt = Spring.SetConfigInt
local spGetConfigInt = Spring.GetConfigInt
local spGetMouseState = Spring.GetMouseState
local spTraceScreenRay = Spring.TraceScreenRay
local spSendCommands = Spring.SendCommands
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitStates = Spring.GetUnitStates

local CMD_WAIT = CMD and CMD.WAIT

local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name = "LuaMsg demo",
        desc = "LuaMsg showcase",
        author = "rlcevg",
        date = "2025-10-20",
        license = "My private v2 or later",
        layer = 0,
        enabled = true,
    }
end

-- Constants
local WIDGET_NAME = "gui_test_lua_msg"
local MODEL_NAME = "gui_test_lua_msg_model"
local RML_PATH = "LuaUI/Widgets/gui_test_lua_msg/gui_test_lua_msg.rml"

-- Widget state
local document
local dm_handle
local arePausing = true
local drawHandle = nil

--------------------------------------------------------------------------------
-- LuaMsg API parameters
--------------------------------------------------------------------------------

local teamID = 1
local squadID1 = 1
local squadID2 = 2
local squadID3 = 3
local zoneID1 = 1
local zoneID2 = 2
local zoneID = 10
local power = 5.2
local retreatThreshold = 2.2
local isRecruitScripted = false
local newRegion = false

local aiMsg = VFS.Include("luarules/utilities/campaign_ai_msg.lua")

--------------------------------------------------------------------------------

local nameToDefID = {}

for _, unitDef in ipairs(UnitDefs) do
    nameToDefID[unitDef.name] = unitDef.id
end

-- Initial data model
local init_model = {
    debugMode = false,
    selectedWave = false,
    selectedTeamID = spGetMyTeamID(),
    -- Window controls
    isCollapsed = false,
    toggleCollapse = function(ev)
        dm_handle.isCollapsed = not dm_handle.isCollapsed
    end,
    closeWidget = function(ev)
        if document then document:Close() end
        local ctx = RmlUi.GetContext("shared")
        if ctx and dm_handle then
            ctx:RemoveDataModel(MODEL_NAME)
        end
        widgetHandler:RemoveWidget(widget)
    end,
    sendCommand = function(ev, command)
        widget:SendCommand(command)
    end,
    updateTeam = function(ev)
        dm_handle.selectedTeamID = ev.parameters.value
        -- Don't send "team X" here — that moves you onto the team.
        -- selectedTeamID is used as the target for give commands only.
    end,
    onInputFocus = function()
        Spring.SDLStartTextInput()
    end,
    onInputBlur = function()
        Spring.SDLStopTextInput()
    end,
    sendIntent = function(ev, command)
        widget:SendIntent(command)
    end,
}

local function clearDrawHandles()
    if drawHandle then
        WG.StopDrawUnitShapeGL4(drawHandle)
        drawHandle = nil
    end
end

function widget:MousePress(x, y, button)
    if button == 3 then
        dm_handle.selectedWave = false
        clearDrawHandles()
        return false
    end

    if button == 2 then
        return false
    end

    local traceType, pos = Spring.TraceScreenRay(x, y)
    if traceType ~= 'ground' then
        -- Selected unit may go here?
        return false
    end
    local wx, wy, wz = pos[1], pos[2], pos[3]

    local alt, ctrl, meta, shift = Spring.GetModKeyState()

    local amount = 1
    if ctrl then
        amount = amount * 5
    end
    if shift then
        amount = amount * 10
    end

    if wx and wy and wz then
        Spring.Echo("x: "..wx.." y: "..wy.." z: "..wz)
        if dm_handle.selectedWave then
            local msg = aiMsg.MsgBuilder.new()
                :cmdValue(aiMsg.Topic.SQUAD_ID, dm_handle.selectedWave)
                :cmdDictArray(aiMsg.Topic.SQUAD_PARAMS, aiMsg.Param.POSITION, {wx, wz})
                :toString()
            Spring.SendSkirmishAIMessage(teamID, msg)
        elseif newRegion then
            newRegion[#newRegion + 1] = wx
            newRegion[#newRegion + 1] = wz
        end
    end
end

function widget:Initialize()
    if widget:GetInfo().enabled == false then
        return false
    end

    widget.rmlContext = RmlUi.GetContext("shared")
    if not widget.rmlContext then
        return false
    end

    dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, init_model)
    if not dm_handle then
        return false
    end

    document = widget.rmlContext:LoadDocument(RML_PATH, widget)
    if not document then
        widget:Shutdown()
        return false
    end

    document:AddEventListener("dragend", function() widget:SavePosition() end)

    document:ReloadStyleSheet()
    document:Show()
    widget:LoadPosition()

    return true
end

function widget:SavePosition()
    if not document then return end
    local element = document:GetElementById("gui_test_lua_msg-widget")
    if not element then return end
    local x = element.offset_left
    local y = element.offset_top
    if not x or not y then return end

    local vsx, vsy = spGetViewGeometry()
    if not vsx or not vsy then return end
    local relX = x / vsx
    local relY = y / vsy
    spSetConfigInt("testLuaMsg_RelativeX", math.floor(relX * 1000))
    spSetConfigInt("testLuaMsg_RelativeY", math.floor(relY * 1000))
end

function widget:LoadPosition()
    if not document then return end
    local element = document:GetElementById("gui_test_lua_msg-widget")
    if not element then return end
    local relX = spGetConfigInt("testLuaMsg_RelativeX", -1)
    local relY = spGetConfigInt("testLuaMsg_RelativeY", -1)
    if relX == -1 or relY == -1 then return end
    relX = relX / 1000
    relY = relY / 1000
    local vsx, vsy = spGetViewGeometry()
    if not vsx or not vsy then return end
    local x = math.floor(relX * vsx)
    local y = math.floor(relY * vsy)
    element.style.position = "absolute"
    element.style.left = x .. "px"
    element.style.top = y .. "px"
end

function widget:PauseAI()
    local allTeams = spGetTeamList()
    for _, teamID in ipairs(allTeams) do
        local _, _, _, isAI = spGetTeamInfo(teamID, false)
        if isAI then
            local units = spGetTeamUnits(teamID)
            for _, unitID in pairs(units) do
                local states = spGetUnitStates(unitID)
                if states then
                    if arePausing and states['active'] then
                        spGiveOrderToUnit(unitID, CMD_WAIT, {}, {})
                    elseif not arePausing and not states['active'] then
                        spGiveOrderToUnit(unitID, CMD_WAIT, {}, {})
                    end
                end
            end
        end
    end
    arePausing = not arePausing
end

function widget:KeyPress(key, mods, isRepeat, label, unicode)
    if key == 27 then -- ESC key
        clearDrawHandles()
        return true
    end
    return false
end

function widget:SendCommand(command)
    spSendCommands(command)
end

-- ["corck"]    = 0.0,
-- ["corak"]    = 0.0,
-- ["cornecro"] = 0.0,
-- ["corstorm"] = 0.5,
-- ["corthud"]  = 0.5,
-- ["corcrash"] = 0.0,

function CreateSquad(squadID, pos, range, composition)
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_REQUEST_ID, squadID)
        :cmdDict(aiMsg.Topic.SQUAD_REQUEST_PARAMS, {
            [aiMsg.Param.SQUAD_GATHER_RANGE] = range,
            [aiMsg.Param.SQUAD_ATTACK_RANGE] = 512,
            [aiMsg.Param.SQUAD_REBUILD] = false and 1 or 0,
            [aiMsg.Param.SQUAD_RETREAT] = -1,  -- -1 or 0 or (0.0..1.0]
        })
        :paramArray(aiMsg.Param.POSITION, pos)
        :cmdDict(aiMsg.Topic.SQUAD_REQUEST_COMPOSE, composition)
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end

function widget:SendNewSquad1()
    -- Between 2 corlabs: {4155, 1854}
    CreateSquad(squadID1, {4155, 1854}, 710, {
        [nameToDefID["corstorm"]] = 3,
        [nameToDefID["corthud"]]  = 10,
    })
end
function widget:SendNewSquad2()
    -- Map center: {3072, 3584}
    -- Off-center: {3844, 3300}
    CreateSquad(squadID2, {3844, 3300}, 8000, {
        [nameToDefID["corstorm"]] = 10,
        [nameToDefID["corthud"]]  = 3,
    })
end
function widget:SendNewSquad3()
    -- Only 1 corlab: {4500, 1800}, range=710
    CreateSquad(squadID3, {4500, 1800}, 7100, {
        [nameToDefID["corhurc"]]  = 10,
    })
end
function widget:SendSelectSquad1()
    dm_handle.selectedWave = squadID1
end
function widget:SendSelectSquad2()
    dm_handle.selectedWave = squadID2
end
function widget:SendSelectSquad3()
    dm_handle.selectedWave = squadID3
end
function widget:SendCancelReq1()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_REQUEST_CANCEL, squadID1)
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendCancelReq2()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_REQUEST_CANCEL, squadID2)
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendCancelReq3()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_REQUEST_CANCEL, squadID3)
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendCancelSquad1()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_DISBAND, squadID1)
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendCancelSquad2()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_DISBAND, squadID2)
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendCancelSquad3()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_DISBAND, squadID3)
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendCompose1Squad2()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_REQUEST_ID, squadID2)
        :cmdDict(aiMsg.Topic.SQUAD_REQUEST_COMPOSE, {
            [nameToDefID["corak"]] = 10,
        })
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendCompose2Squad2()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_REQUEST_ID, squadID2)
        :cmdDict(aiMsg.Topic.SQUAD_REQUEST_COMPOSE, {
            [nameToDefID["corgator"]] = 10,
        })
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendCompose3Squad2()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_REQUEST_ID, squadID2)
        :cmdDict(aiMsg.Topic.SQUAD_REQUEST_COMPOSE, {
            [nameToDefID["corstorm"]] =  3,
            [nameToDefID["corthud"]]  = 10,
        })
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end

function SetSquadTask(squad, task)
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_ID, squad)
        :cmdValue(aiMsg.Topic.SQUAD_TASK, task)
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end

function widget:SendTaskDefend()
    if dm_handle.selectedWave then
        SetSquadTask(dm_handle.selectedWave, aiMsg.Task.DEFEND)
    end
end
function widget:SendTaskScout()
    if dm_handle.selectedWave then
        SetSquadTask(dm_handle.selectedWave, aiMsg.Task.SCOUT)
    end
end
function widget:SendTaskRaid()
    if dm_handle.selectedWave then
        SetSquadTask(dm_handle.selectedWave, aiMsg.Task.RAID)
    end
end
function widget:SendTaskAttack()
    if dm_handle.selectedWave then
        SetSquadTask(dm_handle.selectedWave, aiMsg.Task.ATTACK)
    end
end
function widget:SendTaskBomb()
    if dm_handle.selectedWave then
        SetSquadTask(dm_handle.selectedWave, aiMsg.Task.BOMBER)
    end
end
function widget:SendTaskArty()
    if dm_handle.selectedWave then
        SetSquadTask(dm_handle.selectedWave, aiMsg.Task.ARTILLERY)
    end
end
function widget:SendTaskAA()
    if dm_handle.selectedWave then
        SetSquadTask(dm_handle.selectedWave, aiMsg.Task.ANTI_AIR)
    end
end
function widget:SendTaskSupport()
    if dm_handle.selectedWave then
        SetSquadTask(dm_handle.selectedWave, aiMsg.Task.SUPPORT)
    end
end

function widget:SetPathParamThreat()
    if dm_handle.selectedWave then
        local msg = aiMsg.MsgBuilder.new()
            :cmdValue(aiMsg.Topic.SQUAD_ID, dm_handle.selectedWave)
            :cmdDict(aiMsg.Topic.SQUAD_PATH_PARAMS, {
--                 [aiMsg.Path.GOAL_RANGE] = 1.0,
                [aiMsg.Path.IGNORE_THREAT] = 320.0,
--                 [aiMsg.Path.AVOID_THREAT] = 1000.0,
--                 [aiMsg.Path.USE_END_POS] = false and 1 or 0,
            })
            :toString()
        Spring.SendSkirmishAIMessage(teamID, msg)
    end
end
function widget:ClearPathParamThreat()
    if dm_handle.selectedWave then
        local msg = aiMsg.MsgBuilder.new()
            :cmdValue(aiMsg.Topic.SQUAD_ID, dm_handle.selectedWave)
            :cmdDict(aiMsg.Topic.SQUAD_PATH_PARAMS, {
--                 [aiMsg.Path.GOAL_RANGE] = -1.0,
                [aiMsg.Path.IGNORE_THREAT] = 0.0,
--                 [aiMsg.Path.AVOID_THREAT] = 1e38,
--                 [aiMsg.Path.USE_END_POS] = false and 1 or 0,
            })
            :toString()
        Spring.SendSkirmishAIMessage(teamID, msg)
    end
end

function widget:SendDozenSquads()
    local squadID = 10
    for i = 1, 10 do
        squadID = squadID + 1
        CreateSquad(squadID, {4155, 1854}, 710, {
            [nameToDefID["corstorm"]] = 3,
            [nameToDefID["corthud"]]  = 10,
        })
    end
end
function widget:CancelDozenSquads()
    local squadID = 10
    local msgBuilder = aiMsg.MsgBuilder.new()
    for i = 1, 10 do
        squadID = squadID + 1
        msgBuilder:cmdValue(aiMsg.Topic.SQUAD_REQUEST_CANCEL, squadID)
    end
    Spring.SendSkirmishAIMessage(teamID, msgBuilder:toString())
end

function widget:SendPriorityTarget()
    local units = Spring.GetSelectedUnits()
    if #units > 0 then
        local msg = aiMsg.MsgBuilder.new()
            :cmdValue(aiMsg.Topic.SQUAD_ID, dm_handle.selectedWave)
            :cmdDict(aiMsg.Topic.SQUAD_REQUEST_PARAMS, {
                [aiMsg.Param.SQUAD_PRIO_TARGET] = units[1],
            })
            :cmdDict(aiMsg.Topic.SQUAD_PARAMS, {
                [aiMsg.Param.SQUAD_PRIO_TARGET] = units[1],
            })
            :toString()
        Spring.SendSkirmishAIMessage(teamID, msg)
    end
end

function widget:SendUnitDefRetreat1Intent()
    local msg = aiMsg.MsgBuilder.new()
        :cmdDict(aiMsg.Topic.UNITDEF_RETREAT, {
            [nameToDefID["corstorm"]] = 0.5,
            [nameToDefID["corthud"]]  = 0.5,
        })
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendUnitDefRetreat2Intent()
    local msg = aiMsg.MsgBuilder.new()
        :cmdDict(aiMsg.Topic.UNITDEF_RETREAT, {
            [nameToDefID["corstorm"]] = 1.0,
            [nameToDefID["corthud"]]  = 1.0,
        })
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendDeactivateFactoryIntent()
    local units = Spring.GetSelectedUnits()
    if #units > 0 then
        local msg = aiMsg.MsgBuilder.new()
            :cmdDictArray(aiMsg.Topic.SET_FACTORY_ACTIVE, 0, units)
            :toString()
        Spring.SendSkirmishAIMessage(teamID, msg)
    end
end
function widget:SendActivateFactoryIntent()
    local units = Spring.GetSelectedUnits()
    if #units > 0 then
        local msg = aiMsg.MsgBuilder.new()
            :cmdDictArray(aiMsg.Topic.SET_FACTORY_ACTIVE, 1, units)
            :toString()
        Spring.SendSkirmishAIMessage(teamID, msg)
    end
end
function widget:SendEnableUnitsMsg()
--     tracy.ZoneBeginN("ENABLE_UNITDEFS")
    local msg = aiMsg.MsgBuilder.new()
        :cmdArray(aiMsg.Topic.ENABLE_UNITDEFS, {
            nameToDefID["corstorm"],
            nameToDefID["corthud"],
            nameToDefID["corck"],
            nameToDefID["cornecro"],
            nameToDefID["coravp"],
            nameToDefID["coralab"],
            nameToDefID["coradvsol"],
        })
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
--     tracy.ZoneEnd()
end
function widget:SendDisableUnitsMsg()
    local msg = aiMsg.MsgBuilder.new()
        :cmdArray(aiMsg.Topic.DISABLE_UNITDEFS, {
            nameToDefID["corstorm"],
            nameToDefID["corthud"],
            nameToDefID["corck"],
            nameToDefID["cornecro"],
            nameToDefID["coravp"],
            nameToDefID["coralab"],
            nameToDefID["coradvsol"],
        })
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:ToggleScriptedRectruit()
    isRecruitScripted = not isRecruitScripted
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SET_SCRIPTED_RECRUIT, isRecruitScripted and 1 or 0)
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end

function widget:SendEscortTask()
    local units = Spring.GetSelectedUnits()
    if #units > 0 then
        local msg = aiMsg.MsgBuilder.new()
            :cmdValue(aiMsg.Topic.SQUAD_ID, squadID1)
            :cmdValue(aiMsg.Topic.SQUAD_ESCORT, units[1])
            :toString()
        Spring.SendSkirmishAIMessage(teamID, msg)
    end
end
function widget:SendEscortRangeBig()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_ID, squadID1)
        :cmdDict(aiMsg.Topic.SQUAD_PARAMS, {
            [aiMsg.Param.SQUAD_ATTACK_RANGE] = 2000,
        })
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendEscortRangeSmall()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.SQUAD_ID, squadID1)
        :cmdDict(aiMsg.Topic.SQUAD_PARAMS, {
            [aiMsg.Param.SQUAD_ATTACK_RANGE] = 100,
        })
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end

function widget:SendRegion1()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.BUILD_REGION_ID, zoneID1)
        :paramArray(nameToDefID["cornanotc"], {1079, 2391, 1569, 2788, 1809, 2426, 1349, 2172})
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:SendRegion2()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.BUILD_REGION_ID, zoneID2)
        :paramArray(nameToDefID["corsolar"], {4514, 5271, 4860, 5047, 5266, 5255, 5235, 5631, 4738, 5617})
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:StartRegion()
    newRegion = {}
end
function widget:EndRegion()
    if newRegion and #newRegion >= 6 then
        zoneID = zoneID + 1
        local msg = aiMsg.MsgBuilder.new()
            :cmdValue(aiMsg.Topic.BUILD_REGION_ID, zoneID)
            :paramArray(nameToDefID["corwin"], newRegion)
            :toString()
        Spring.SendSkirmishAIMessage(teamID, msg)
    end
    newRegion = false
end
function widget:ClearRegions()
    local msg = aiMsg.MsgBuilder.new()
        :cmdValue(aiMsg.Topic.BUILD_REGION_CLEAR, 1)
        :toString()
    Spring.SendSkirmishAIMessage(teamID, msg)
    newRegion = false
end


function widget:Shutdown()
    Spring.SDLStopTextInput()
    if widget.rmlContext and dm_handle then
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
        dm_handle = nil
    end

    if document then
        document:Close()
        document = nil
    end

    widget.rmlContext = nil
    clearDrawHandles()
end

function widget:Update()
    if dm_handle then
        clearDrawHandles()
    end
end

function widget:SelectionChanged(selectedUnits)
    if not dm_handle then return end
    if selectedUnits and #selectedUnits > 0 then
        local teamID = Spring.GetUnitTeam(selectedUnits[1])
        if teamID then
            dm_handle.selectedTeamID = teamID
        end
    end
end

function widget:GameStart()
    ToggleScriptedRectruit()
end

function widget:RecvLuaMsg(message, playerID)
    if not document then return end
    if message:sub(1, 19) == 'LobbyOverlayActive1' then
        document:Hide()
    elseif message:sub(1, 19) == 'LobbyOverlayActive0' then
        document:Show()
    end
end

function widget:Reload()
    widget:Shutdown()
    widget:Initialize()
end

function widget:ToggleDebugger()
    if dm_handle then
        dm_handle.debugMode = not dm_handle.debugMode

        if dm_handle.debugMode then
            RmlUi.SetDebugContext('shared')
        else
            RmlUi.SetDebugContext(nil)
        end
    end
end
