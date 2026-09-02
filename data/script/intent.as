namespace Intent {

// Has to be same as Lua's defines
enum EIntents {
	AI_ENABLE          =  1,

	AI_BASE_CREATE     =  2,
	AI_BASE_REBUILD    =  3,

	AI_UNIT_WEIGHTS    =  4,

	AI_WAVE_CREATE     =  5,
	AI_WAVE_DESTROY    =  6,
	AI_WAVE_COMPOSE    =  7,
	AI_WAVE_DEFEND     =  8,

	AI_REGION_AVOID    =  9,

	AI_FACTORY_ENABLE  = 10,
	AI_ENABLED_UNITS   = 11,

	AI_EXEC_ORDER_66   = 12,
}

}  // namespace Intent
