-- Campaign AI messaging system.
-- boolean is forbidden; accepted values: 1 as true, 0 as false.
-- Message format:
-- "<version>|<cmd1>:<val1>;<val2>;<val3>|<cmd2>:<param1>=<val1>;<param2>=<val2>;<param3>=<val3.1>,<val3.2>,<val3.3>"

local version = "1"

local delimiter = {
	SEP_PACKET = "|",
	SEP_COMMAND = ":",
	SEP_PARAM = ";",
	SEP_KEY_VALUE = "=",
	SEP_SUBPARAM = ",",
}

local topic = { -- Message topic
	SET_AI_ACTIVE = 1, -- boolean
	ENABLE_UNITDEFS = 2, -- array of unitDefIDs
	DISABLE_UNITDEFS = 3, -- array of unitDefIDs
	ENABLE_UNITS_CONTROL = 4, -- array of unitIDs
	DISABLE_UNITS_CONTROL = 5, -- array of unitIDs

	SET_UNITDEF_RETREAT_HP = 11,

	REGION_AVOID = 12,

	SET_FACTORY_ACTIVE = 13,

	SCRIPT_CONSTRUCTION_PARAMS = 15, -- construct params
	SET_SCRIPT_RECRUIT = 16, -- boolean

	-- Base starts at 100
	BASE_ID = 101,
	BASE_ADD_PLAN = 102,
	BASE_DEL_PLAN = 103,
	BASE_CANCEL = 104,
	BASE_PARAMS = 105,

	-- Squad Request starts at 200
	SQUAD_REQUEST_ID = 201,
	SQUAD_REQUEST_COMPOSE = 202,
	SQUAD_REQUEST_CANCEL = 203,
	SQUAD_REQUEST_PARAMS = 204,
	-- Squad starts at 210
	SQUAD_ID = 211,
	SQUAD_DISBAND = 212,
	SQUAD_TASK = 213,
	SQUAD_PARAMS = 214,
	SQUAD_PATH_PARAMS = 215,
	SQUAD_ESCORT = 216,

	BUILD_REGION_ID = 301,
	BUILD_REGION_CLEAR = 302,
	RESERVED_REGION_ID = 303,
	RESERVED_REGION_CLEAR = 304,
	TRIGGER_REGION_ID = 321,
	TRIGGER_REGION_CLEAR = 322,
}

local signal = { -- Trigger signal
	PREFIX = "ai_", -- signal message prefix
	SQUAD_FINISHED = 201,
	SQUAD_DESTROYED = 202,
	REGION_ENTER = 301,
	REGION_EXIT = 302,
}

local construct = {
	ASSIGNMENT = 1,
	FACTORY = 2,
	STORAGE = 3,
	METAL = 4,
	ENERGY = 5,
	ECONOMY = 6,
	DEFENCE = 7,
}

local plan = { -- Build plan params
	UNITDEF = 1,
	POSITION = 2,
	ZONE = 3,
	REBUILD = 4,
}

local squad = { -- Squad params
	POSITION = 1,
	GATHER_RANGE = 2,
	ATTACK_RANGE = 3,
	REBUILD = 4,
	RETREAT = 5,
	PRIO_TARGET = 6,
}

local task = { -- Task types
	DEFEND = 1,
	SCOUT = 2,
	RAID = 3,
	ATTACK = 4,
	BOMBER = 5,
	ARTILLERY = 6,
	ANTI_AIR = 7,
	SUPPORT = 8,
}

local pathing = { -- Pathing params
	GOAL_RANGE = 1,
	IGNORE_THREAT = 2,
	AVOID_THREAT = 3,
	USE_END_POS = 4,
}

local MsgBuilder = {}

function MsgBuilder.new()
	local self = setmetatable({}, MsgBuilder)
	self.buffer = { version }
	return self
end

function MsgBuilder:append(value)
	table.insert(self.buffer, value)
	return self
end

function MsgBuilder:cmdValue(cmd, param)
	self:append(cmd .. delimiter.SEP_COMMAND .. param)
	return self
end

function MsgBuilder:cmdArray(cmd, params)
	self:append(cmd .. delimiter.SEP_COMMAND .. table.concat(params, delimiter.SEP_PARAM))
	return self
end

function MsgBuilder:cmdDict(cmd, params)
	local arrayKV = {}
	for key, value in pairs(params) do
		table.insert(arrayKV, key .. delimiter.SEP_KEY_VALUE .. value)
	end
	self:append(cmd .. delimiter.SEP_COMMAND .. table.concat(arrayKV, delimiter.SEP_PARAM))
	return self
end

function MsgBuilder:cmdDictArray(cmd, key, values)
	self:append(
		cmd .. delimiter.SEP_COMMAND .. key .. delimiter.SEP_KEY_VALUE .. table.concat(values, delimiter.SEP_SUBPARAM)
	)
	return self
end

function MsgBuilder:addValue(value)
	self.buffer[#self.buffer] = self.buffer[#self.buffer] .. delimiter.SEP_PARAM .. value
	return self
end

function MsgBuilder:paramArray(param, values)
	self.buffer[#self.buffer] = self.buffer[#self.buffer]
		.. delimiter.SEP_PARAM
		.. param
		.. delimiter.SEP_KEY_VALUE
		.. table.concat(values, delimiter.SEP_SUBPARAM)
	return self
end

function MsgBuilder:toString()
	return table.concat(self.buffer, delimiter.SEP_PACKET)
end

MsgBuilder.__index = MsgBuilder
MsgBuilder.__tostring = MsgBuilder.toString

return {
	Topic = topic,
	Signal = signal,
	Construct = construct,
	Plan = plan,
	Squad = squad,
	Task = task,
	Path = pathing,
	MsgBuilder = MsgBuilder,
}
