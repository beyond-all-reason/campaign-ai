namespace Intent {

// Has to be same as Lua's defines
enum EIntents {
	AI_ENABLE          =   1,

	AI_BASE_CREATE     = 101,  // Base starts at 100
	AI_BASE_REBUILD    = 102,

	AI_UNIT_WEIGHTS    =   4,

	AI_REQUEST_SQUAD   = 201,  // Squad Request starts at 200
	AI_REQ_COMPOSE     = 202,
	AI_REQ_CANCEL      = 203,
	AI_REQ_PARAMS      = 204,
	AI_SQUAD_ASSEMBLE  = 211,  // Squad starts at 210
	AI_SQUAD_DISBAND   = 212,
	AI_SQUAD_TASK      = 213,
	AI_SQUAD_PARAMS    = 214,

	AI_UNITDEF_RETREAT =  11,

	AI_REGION_AVOID    =  12,

	AI_FACTORY_ENABLE  =  13,
	AI_ENABLED_UNITS   =  14,

	AI_EXEC_ORDER_66   =  15,
	AI_RECRUIT_SCRIPT  =  16,
}

}  // namespace Intent
