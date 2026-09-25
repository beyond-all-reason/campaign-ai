local topic = {
	AI_ENABLE          =   1,
	AI_BASE_CREATE     = 101,  -- Base starts at 100
	AI_BASE_REBUILD    = 102,
	AI_UNIT_WEIGHTS    =   4,

	AI_REQUEST_SQUAD   = 201,  -- Squad Request starts at 200
	AI_REQ_COMPOSE     = 202,
	AI_REQ_CANCEL      = 203,
	AI_REQ_PARAMS      = 204,
	AI_SQUAD_ASSEMBLE  = 211,  -- Squad starts at 210
	AI_SQUAD_DISBAND   = 212,
	AI_SQUAD_TASK      = 213,
	AI_SQUAD_PARAMS    = 214,

	AI_UNITDEF_RETREAT =  11,
	AI_REGION_AVOID    =  12,
	AI_FACTORY_ENABLE  =  13,
	AI_ENABLED_UNITS   =  14,
	AI_EXEC_ORDER_66   =  15,  -- Attack allies not implemented
	AI_RECRUIT_SCRIPT  =  16,
}

local param = {
	SQUAD_POS_X        = 1,
	SQUAD_POS_Z        = 2,
	SQUAD_GATHER_RANGE = 3,
	SQUAD_ATTACK_RANGE = 4,
	SQUAD_IS_REPEAT    = 5,
	SQUAD_RETREAT      = 6,
	SQUAD_PRIO_TARGET  = 7,

	BASE_POS_X = 101,
	BASE_POS_Z = 102,
}

local task = {
	TASK_DEFEND  = 1,
	TASK_SCOUT   = 2,
	TASK_RAID    = 3,
	TASK_ATTACK  = 4,
	TASK_BOMB    = 5,
	TASK_ARTY    = 6,
	TASK_AA      = 7,
	TASK_SUPPORT = 8,
	TASK_RETREAT = 9,
}

return {
	topic = topic,
	param = param,
	task  = task,
}
