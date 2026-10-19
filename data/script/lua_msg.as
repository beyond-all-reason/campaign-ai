namespace LuaMsg {

/*
 * Message format:
 * "<version>|<cmd1>:<val1>;<val2>;<val3>|<cmd2>:<param1>=<val1.1>,<val1.2>,<val1.3>;<param2>=<val2>;<param3>=<val3>;"
 */
string SEP_PACKET("|");
string SEP_COMMAND(":");
string SEP_PARAM(";");
string SEP_KEY_VALUE("=");
string SEP_SUBPARAM(",");

string VERSION("1");

string SIG_PREFIX("ai_");

// Has to be same as Lua's defines
enum ELuaMsg {
	SET_AI_ACTIVE                    =   1,  // boolean
	ENABLE_UNITDEFS                  =   2,  // array of unitDefIDs
	DISABLE_UNITDEFS                 =   3,  // array of unitDefIDs
	ENABLE_UNITS_CONTROL             =   4,  // array of unitIDs
	DISABLE_UNITS_CONTROL            =   5,  // array of unitIDs

	SET_UNITDEF_RETREAT_HP           =  11,

	REGION_AVOID                     =  12,

	SET_FACTORY_ACTIVE               =  13,

	SCRIPT_CONSTRUCTION_PARAMS       =  15,
	SET_SCRIPT_RECRUIT               =  16,  // boolean

	// Base starts at 100
	BASE_ID                          = 101,
	BASE_ADD_PLAN                    = 102,
	BASE_DEL_PLAN                    = 103,
	BASE_CANCEL                      = 104,
	BASE_PARAMS                      = 105,

	// Squad Request starts at 200
	SQUAD_REQUEST_ID                 = 201,
	SQUAD_REQUEST_COMPOSE            = 202,
	SQUAD_REQUEST_CANCEL             = 203,
	SQUAD_REQUEST_PARAMS             = 204,
	// Squad starts at 210
	SQUAD_ID                         = 211,
	SQUAD_DISBAND                    = 212,
	SQUAD_TASK                       = 213,
	SQUAD_PARAMS                     = 214,
	SQUAD_PATH_PARAMS                = 215,
	SQUAD_ESCORT                     = 216,

	BUILD_REGION_ID                  = 301,
	BUILD_REGION_CLEAR               = 302,
	RESERVED_REGION_ID               = 303,
	RESERVED_REGION_CLEAR            = 304,
	ALLOWED_REGION_ID                = 305,
	TRIGGER_REGION_ID                = 321,
	TRIGGER_REGION_CLEAR             = 322,
}

enum ESignal {
	SQUAD_FINISHED                   = 201,
	SQUAD_DESTROYED                  = 202,
	REGION_ENTER                     = 301,
	REGION_EXIT                      = 302,
}

void Signal(ESignal sig, Id paramId) {
	ai.CallRules(SIG_PREFIX + sig + SEP_COMMAND + paramId);
}

void Signal(ESignal sig, Id paramId, Id detailId) {
	ai.CallRules(SIG_PREFIX + sig + SEP_COMMAND + paramId + SEP_PARAM + detailId);
}

}  // namespace LuaMsg
