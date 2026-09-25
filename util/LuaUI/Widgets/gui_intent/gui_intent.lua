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
        name = "AiIntent demo",
        desc = "AiIntent showcase",
        author = "rlcevg",
        date = "2025-10-20",
        license = "My private v2 or later",
        layer = 0,
        enabled = true,
    }
end

-- Constants
local WIDGET_NAME = "gui_intent"
local MODEL_NAME = "gui_intent_model"
local RML_PATH = "LuaUI/Widgets/gui_intent/gui_intent.rml"

-- Widget state
local document
local dm_handle
local arePausing = true
local drawHandle = nil

--------------------------------------------------------------------------------
-- Intent API parameters
--------------------------------------------------------------------------------

local teamID = 1
local squadID1 = 1
local squadID2 = 2
local squadID3 = 3
local power = 5.2
local retreatThreshold = 2.2
local isRecruitScripted = false

local intent = VFS.Include("luarules/utilities/ai_lib/intent.lua")
local luaMsg = VFS.Include("luarules/utilities/ai_lib/lua_msg.lua")

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

    local type, pos = Spring.TraceScreenRay(x, y)
    if type ~= 'ground' then
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
            Spring.AiIntentDict(teamID, intent.topic.AI_SQUAD_PARAMS, dm_handle.selectedWave, {
                [intent.param.SQUAD_POS_X] = wx,
                [intent.param.SQUAD_POS_Z] = wz,
            })
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
    local element = document:GetElementById("gui_intent-widget")
    if not element then return end
    local x = element.offset_left
    local y = element.offset_top
    if not x or not y then return end

    local vsx, vsy = spGetViewGeometry()
    if not vsx or not vsy then return end
    local relX = x / vsx
    local relY = y / vsy
    spSetConfigInt("intent_RelativeX", math.floor(relX * 1000))
    spSetConfigInt("intent_RelativeY", math.floor(relY * 1000))
end

function widget:LoadPosition()
    if not document then return end
    local element = document:GetElementById("gui_intent-widget")
    if not element then return end
    local relX = spGetConfigInt("intent_RelativeX", -1)
    local relY = spGetConfigInt("intent_RelativeY", -1)
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



function widget:SendIntent(command)
    if command == "order_66" then
        Spring.AiIntentFloat(teamID, intent.topic.AI_EXEC_ORDER_66);
    end
end

function CreateSquad(squadID, pos, range, composition)
--     tracy.ZoneBeginN("AI_REQUEST_SQUAD")
    Spring.AiIntentDict(teamID, intent.topic.AI_REQUEST_SQUAD, squadID, {
        [intent.param.SQUAD_POS_X] = pos[1],
        [intent.param.SQUAD_POS_Z] = pos[2],
        [intent.param.SQUAD_GATHER_RANGE] = range,
        [intent.param.SQUAD_ATTACK_RANGE] = 512,
        [intent.param.SQUAD_IS_REPEAT] = true,
        [intent.param.SQUAD_RETREAT] = -1,  -- -1 or 0 or (0.0..1.0]
    })
    Spring.AiIntentUnitDefs(teamID, intent.topic.AI_REQ_COMPOSE, squadID, composition)
--     tracy.ZoneEnd()
end

function widget:SendNewSquad1()
    -- Between 2 corlabs: {4155, 1854}
    CreateSquad(squadID1, {4155, 1854}, 710, {
        ["corstorm"] = 3,
        ["corthud"]  = 10,
    })
end
function widget:SendNewSquad2()
    -- Map center: {3072, 3584}
    -- Off-center: {3844, 3300}
    CreateSquad(squadID2, {3844, 3300}, 8000, {
        ["corstorm"] = 10,
        ["corthud"]  = 3,
    })
end
function widget:SendNewSquad3()
    -- Only 1 corlab: {4500, 1800}, range=710
    CreateSquad(squadID3, {4500, 1800}, 7100, {
        ["corhurc"]  = 10,
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
    Spring.AiIntentFloat(teamID, intent.topic.AI_REQ_CANCEL, squadID1);
end
function widget:SendCancelReq2()
    Spring.AiIntentFloat(teamID, intent.topic.AI_REQ_CANCEL, squadID2);
end
function widget:SendCancelReq3()
    Spring.AiIntentFloat(teamID, intent.topic.AI_REQ_CANCEL, squadID3);
end
function widget:SendCancelSquad1()
    Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_DISBAND, squadID1);
end
function widget:SendCancelSquad2()
    Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_DISBAND, squadID2);
end
function widget:SendCancelSquad3()
    Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_DISBAND, squadID3);
end
function widget:SendCompose1Squad2()
    Spring.AiIntentUnitDefs(teamID, intent.topic.AI_REQ_COMPOSE, squadID2, {
        ["corak"] = 10,
    });
end
function widget:SendCompose2Squad2()
    Spring.AiIntentUnitDefs(teamID, intent.topic.AI_REQ_COMPOSE, squadID2, {
        ["corgator"] = 10,
    });
end
function widget:SendCompose3Squad2()
    Spring.AiIntentUnitDefs(teamID, intent.topic.AI_REQ_COMPOSE, squadID2, {
        ["corstorm"] = 3,
        ["corthud"]  = 10,
    });
end

function widget:SendTaskDefend()
    if dm_handle.selectedWave then
        Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_TASK, dm_handle.selectedWave, intent.task.TASK_DEFEND);
    end
end
function widget:SendTaskScout()
    if dm_handle.selectedWave then
        Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_TASK, dm_handle.selectedWave, intent.task.TASK_SCOUT);
    end
end
function widget:SendTaskRaid()
    if dm_handle.selectedWave then
        Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_TASK, dm_handle.selectedWave, intent.task.TASK_RAID);
    end
end
function widget:SendTaskAttack()
    if dm_handle.selectedWave then
        Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_TASK, dm_handle.selectedWave, intent.task.TASK_ATTACK);
    end
end
function widget:SendTaskBomb()
    if dm_handle.selectedWave then
        Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_TASK, dm_handle.selectedWave, intent.task.TASK_BOMB);
    end
end
function widget:SendTaskArty()
    if dm_handle.selectedWave then
        Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_TASK, dm_handle.selectedWave, intent.task.TASK_ARTY);
    end
end
function widget:SendTaskAA()
    if dm_handle.selectedWave then
        Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_TASK, dm_handle.selectedWave, intent.task.TASK_AA);
    end
end
function widget:SendTaskSupport()
    if dm_handle.selectedWave then
        Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_TASK, dm_handle.selectedWave, intent.task.TASK_SUPPORT);
    end
end

function widget:SendDozenSquads()
    local squadID = 11
    for i = 1, 10 do
        squadID = squadID + 1
        CreateSquad(squadID, {4155, 1854}, 710, {
            ["corstorm"] = 3,
            ["corthud"]  = 10,
        })
    end
end

function widget:SendPriorityTarget()
    local units = Spring.GetSelectedUnits()
    if #units > 0 then
        Spring.AiIntentDict(teamID, intent.topic.AI_REQ_PARAMS, dm_handle.selectedWave, {
            [intent.param.SQUAD_PRIO_TARGET] = units[1],
        });
        Spring.AiIntentDict(teamID, intent.topic.AI_SQUAD_PARAMS, dm_handle.selectedWave, {
            [intent.param.SQUAD_PRIO_TARGET] = units[1],
        });
    end
end

-- function widget:SendArmyAAIntent()
--     -- FIXME: According corlab's array in factory.json
--     Spring.AiIntentArray(teamID, intent.topic.AI_UNIT_WEIGHTS, squadID1, {
--         0, 0, 0, 0, 0, 1
--     })
-- end
-- function widget:SendArmySquadIntent()
--     -- FIXME: According corlab's array in factory.json
--     Spring.AiIntentArray(teamID, intent.topic.AI_UNIT_WEIGHTS, squadID1, {
--         0, 0, 0, 0.5, 0.5, 0
--     })
-- end
-- function widget:SendArmyRaidIntent()
--     -- FIXME: According corlab's array in factory.json
--     Spring.AiIntentArray(teamID, intent.topic.AI_UNIT_WEIGHTS, squadID1, {
--         0, 1, 0, 0, 0, 0
--     })
-- end
function widget:SendUnitDefRetreat1Intent()
    Spring.AiIntentUnitDefs(teamID, intent.topic.AI_UNITDEF_RETREAT, -1, {
        ["corstorm"] = 0.5,
        ["corthud"] = 0.5,
    })
end
function widget:SendUnitDefRetreat2Intent()
    Spring.AiIntentUnitDefs(teamID, intent.topic.AI_UNITDEF_RETREAT, -1, {
        ["corstorm"] = 1.0,
        ["corthud"] = 1.0,
    })
end
function widget:SendDeactivateFactoryIntent()
    local units = Spring.GetSelectedUnits()
    if #units > 0 then
        Spring.AiIntentArray(teamID, intent.topic.AI_FACTORY_ENABLE, 0, units)
    end
end
function widget:SendActivateFactoryIntent()
    local units = Spring.GetSelectedUnits()
    if #units > 0 then
        Spring.AiIntentArray(teamID, intent.topic.AI_FACTORY_ENABLE, 1, units)
    end
end
function widget:SendEnableUnitsMsg()
--     tracy.ZoneBeginN("ENABLE_UNITDEFS")
    local msg = luaMsg.BuildArray(luaMsg.topic.ENABLE_UNITDEFS, {
        nameToDefID["corthud"],
        nameToDefID["corck"],
        nameToDefID["cornecro"],
        nameToDefID["coravp"],
        nameToDefID["coralab"],
        nameToDefID["coradvsol"],
    })
    Spring.SendSkirmishAIMessage(teamID, msg)
--     tracy.ZoneEnd()
end
function widget:SendDisableUnitsMsg()
    local msg = luaMsg.BuildArray(luaMsg.topic.DISABLE_UNITDEFS, {
        nameToDefID["corthud"],
        nameToDefID["corck"],
        nameToDefID["cornecro"],
        nameToDefID["coravp"],
        nameToDefID["coralab"],
        nameToDefID["coradvsol"],
    })
    Spring.SendSkirmishAIMessage(teamID, msg)
end
function widget:ToggleScriptedRectruit()
    isRecruitScripted = not isRecruitScripted
    local msg = luaMsg.BuildValue(luaMsg.topic.SET_SCRIPTED_RECRUIT, isRecruitScripted and 1 or 0)
    Spring.SendSkirmishAIMessage(teamID, msg)
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
