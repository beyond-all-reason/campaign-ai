#include "../../define.as"
#include "../../lua_msg.as"
#include "../manager/factory.as"
#include "squad.as"


namespace LuaMsg {

class Manager {
	void InitHandlers() {
		luaMsgHandlers = {
			{formatInt(ELuaMsg::ENABLE_UNITDEFS), LuaMsgFunc(this.EnableUnitDefs)},
			{formatInt(ELuaMsg::DISABLE_UNITDEFS), LuaMsgFunc(this.DisableUnitDefs)},
			{formatInt(ELuaMsg::ENABLE_UNITS_CONTROL), LuaMsgFunc(this.EnableUnitsControl)},
			{formatInt(ELuaMsg::DISABLE_UNITS_CONTROL), LuaMsgFunc(this.DisableUnitsControl)},
			{formatInt(ELuaMsg::REQUEST_SQUAD), LuaMsgFunc(this.RequestSquad)},
			{formatInt(ELuaMsg::SET_SCRIPTED_RECRUIT), LuaMsgFunc(this.SetScriptedRecruit)}
		};
	}

	void HandleLuaMsg(const string& in message) {
		array<string>@ command = message.split(SEP_COMMAND);
		LuaMsgFunc@ func = null;
		if (!luaMsgHandlers.get(command[0], @func))
			return;
		array<string>@ params = command[1].split(SEP_PARAM);
		if (!params.isEmpty() && params[params.length() - 1].isEmpty())
			params.removeLast();  // ignore trailing SEP_PARAM
		func(params);
	}

	/*
	 * LuaMsg handlers
	 */
	void EnableUnitDefs(const array<string>& in unitDefIds) {
		for (uint i = 0; i < unitDefIds.length(); ++i) {
			CCircuitDef@ cdef = ai.GetCircuitDef(parseInt(unitDefIds[i]));
			if (cdef is null)
				return;
			bool success = false;
			int limit = prevUnitLimits.find(cdef.id, success);
			cdef.maxThisUnit = success ? limit : MAX_UNITS;
			prevUnitLimits.erase(cdef.id);
		}
	}
	void DisableUnitDefs(const array<string>& in unitDefIds) {
		for (uint i = 0; i < unitDefIds.length(); ++i) {
			CCircuitDef@ cdef = ai.GetCircuitDef(parseInt(unitDefIds[i]));
			if (cdef is null)
				return;
			prevUnitLimits[cdef.id] = cdef.maxThisUnit;
			cdef.maxThisUnit = 0;
		}
	}

	void EnableUnitsControl(const array<string>& in unitIds) {
		UnitsControl(unitIds, true);
	}
	void DisableUnitsControl(const array<string>& in unitIds) {
		UnitsControl(unitIds, false);
	}

	void RequestSquad(const array<string>& in params) {
		// TODO
	}

	void SetScriptedRecruit(const array<string>& in params) {
		Factory::isRecruitScripted = params[0] != "0";
	}

	/*
	 * Helpers
	 */
	private void UnitsControl(const array<string>@ ids, bool isEnable) {
		for (uint i = 0; i < ids.length(); ++i)
			ai.UnitControl(parseInt(ids[i]), isEnable);
	}

	/*
	 * Properties
	 */
	funcdef void LuaMsgFunc(const array<string>& in params);
	private dictionary luaMsgHandlers;

	private map<Id, int> prevUnitLimits;  // behaviour.json may have other than MAX_UNITS value
}

Manager mgr;

}  // namespace LuaMsg
