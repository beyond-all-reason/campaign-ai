namespace Intent {

// Has to be same as Lua's defines
enum EIntents {
	AI_ENABLE          =  1,

	AI_BASE_CREATE     =  2,
	AI_BASE_REBUILD    =  3,

	AI_UNIT_WEIGHTS    =  4,

	AI_SQUAD_CREATE    =  5,
	AI_SQUAD_COMPOSE   =  6,
	AI_SQUAD_DESTROY   =  7,
	AI_SQUAD_POSITION  =  8,
	AI_SQUAD_PARAMS    =  9,

	AI_REGION_AVOID    = 10,

	AI_FACTORY_ENABLE  = 11,
	AI_ENABLED_UNITS   = 12,

	AI_EXEC_ORDER_66   = 13,
	AI_RECRUIT_SCRIPT  = 100,
}

}  // namespace Intent
