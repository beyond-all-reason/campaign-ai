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


local aiMsg = VFS.Include("luarules/utilities/campaign_ai_msg.lua")


if gadgetHandler:IsSyncedCode() then

function gadget:RecvSkirmishAIMessage(teamID, dataStr)
-- 	Spring.Echo("gadget | teamID: " .. teamID .. " | dataStr: " .. dataStr)
	local prefix = aiMsg.Signal.PREFIX

	if dataStr:sub(1, #prefix) ~= prefix then
		return
	end

	SendToUnsynced("AiHandleCall", teamID, dataStr:sub(#prefix + 1))
end

-----------------------------------------
else  -- not gadgetHandler:IsSyncedCode()
-----------------------------------------

local triggers = {
	[tostring(aiMsg.Signal.SQUAD_FINISHED)] = function(teamID, dataStr)
		-- "ai_squad_finished:<squadID>"
		local squadID = tonumber(dataStr)
		Spring.Echo("Squad Finished: " .. squadID)

		local msg = aiMsg.MsgBuilder.new()
			:cmdValue(aiMsg.Topic.SQUAD_ID, squadID)
-- 			:cmdValue(aiMsg.Topic.SQUAD_TASK, aiMsg.Task.ATTACK)
			:cmdDictArray(aiMsg.Topic.SQUAD_PARAMS, aiMsg.Squad.POSITION, {881, 6507})
			:toString()
		Spring.SendSkirmishAIMessage(teamID, msg)
	end,

	[tostring(aiMsg.Signal.SQUAD_DESTROYED)] = function(teamID, dataStr)
		-- "ai_squad_destroyed:<squadID>"
		local squadID = tonumber(dataStr)
		Spring.Echo("Squad Destroyed: " .. squadID)
	end,
}

local function HandleAiCall(cmd, teamID, dataStr)
	local actName = dataStr:match("^([^:]*)")
-- 	Spring.Echo("HandleAiCall: " .. dataStr .. " | " .. actName)
	if triggers[actName] then
		triggers[actName](teamID, dataStr:sub(#actName + 2))
	end
end

function gadget:Initialize()
	Spring.Echo("Initialize AI Intent")
	gadgetHandler:AddSyncAction("AiHandleCall", HandleAiCall)
end

function gadget:Shutdown()
	Spring.Echo("Shutdown AI Intent")
	gadgetHandler:RemoveSyncAction("AiHandleCall")
end

end
