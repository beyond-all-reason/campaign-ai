local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "AI intent",
		desc = "Intent showcase",
		author = "rlcevg",
		date = "Aug 2026",
		license = "GNU GPL, v2 or later",
		layer = 999,
		enabled = true,
	}
end


if gadgetHandler:IsSyncedCode() then

function gadget:RecvSkirmishAIMessage(teamID, dataStr)
	Spring.Echo("gadget | teamID: " .. teamID .. " | dataStr: " .. dataStr)
	local prefix = "ai_"

	if dataStr:sub(1, #prefix) ~= prefix then
		return
	end

	SendToUnsynced("AiHandleCall", teamID, dataStr)
end

-----------------------------------------
else  -- not gadgetHandler:IsSyncedCode()
-----------------------------------------

local intent = VFS.Include("luarules/utilities/ai_lib/intent.lua")

local actions = {
	["ai_squad_finished"] = function(teamID, dataStr)
		-- "ai_squad_finished:<squadID>"
		local squadID = tonumber(dataStr)
		Spring.Echo("Squad Finished: " .. squadID)
		Spring.AiIntentFloat(teamID, intent.topic.AI_SQUAD_TASK, squadID, intent.task.TASK_ATTACK)
		Spring.AiIntentDict(teamID, intent.topic.AI_SQUAD_PARAMS, squadID, {
			[intent.param.SQUAD_POS_X] = 881,
			[intent.param.SQUAD_POS_Z] = 6507,
		})
	end,
	["ai_squad_destroyed"] = function(teamID, dataStr)
		-- "ai_squad_destroyed:<squadID>"
		local squadID = tonumber(dataStr)
		Spring.Echo("Squad Destroyed: " .. squadID)
	end,
}

local function HandleAiCall(cmd, teamID, dataStr)
	local actName = dataStr:match("^([^:]*)")
	if actions[actName] then
		actions[actName](teamID, dataStr:sub(#actName + 2))
	end
end

-- function gadget:GameFrame(gameFrame)
-- end

function gadget:Initialize()
	Spring.Echo("Initialize AI Intent")
	gadgetHandler:AddSyncAction("AiHandleCall", HandleAiCall)
end

function gadget:Shutdown()
	Spring.Echo("Shutdown AI Intent")
	gadgetHandler:RemoveSyncAction("AiHandleCall")
end

end
