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

// Has to be same as Lua's defines
enum ELuaMsg {
	SET_AI_ACTIVE                    =   1,  // boolean
	ENABLE_UNITDEFS                  =   2,  // array of unitDefIDs
	DISABLE_UNITDEFS                 =   3,  // array of unitDefIDs
	ENABLE_UNIT_CONTROL              =   4,  // array of unitIDs
	DISABLE_UNIT_CONTROL             =   5,  // array of unitIDs

	// Base starts at 100
	BASE_CREATE                      = 101,
	BASE_REBUILD                     = 102,

	UNIT_WEIGHTS                     =   9,

	// Squad Request starts at 200
	REQUEST_SQUAD                    = 201,
	REQUEST_COMPOSE                  = 202,
	REQUEST_CANCEL                   = 203,
	REQUEST_PARAMS                   = 204,
	// Squad starts at 210
	SQUAD_ASSEMBLE                   = 211,
	SQUAD_DISBAND                    = 212,
	SQUAD_TASK                       = 213,
	SQUAD_PARAMS                     = 214,

	UNITDEF_RETREAT                  =  11,

	REGION_AVOID                     =  12,

	FACTORY_ENABLE                   =  13,

	EXEC_ORDER_66                    =  15,
	SET_SCRIPTED_RECRUIT             =  16,  // boolean
}

}  // namespace LuaMsg
