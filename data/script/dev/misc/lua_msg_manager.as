#include "../../define.as"
#include "../../lua_msg.as"
#include "../manager/factory.as"
#include "squad.as"


namespace LuaMsg {

class Manager {
	void InitHandlers() {
		luaMsgHandlers = {
			{formatInt(ELuaMsg::SET_AI_ACTIVE), LuaMsgFunc(this.SetAiActive)},
			{formatInt(ELuaMsg::ENABLE_UNITDEFS), LuaMsgFunc(this.EnableUnitDefs)},
			{formatInt(ELuaMsg::DISABLE_UNITDEFS), LuaMsgFunc(this.DisableUnitDefs)},
			{formatInt(ELuaMsg::ENABLE_UNITS_CONTROL), LuaMsgFunc(this.EnableUnitsControl)},
			{formatInt(ELuaMsg::DISABLE_UNITS_CONTROL), LuaMsgFunc(this.DisableUnitsControl)},

			{formatInt(ELuaMsg::SET_UNITDEF_RETREAT_HP), LuaMsgFunc(this.SetUnitDefRetreat)},
			{formatInt(ELuaMsg::SET_FACTORY_ACTIVE), LuaMsgFunc(this.SetFactoryActive)},
			{formatInt(ELuaMsg::SET_SCRIPTED_RECRUIT), LuaMsgFunc(this.SetScriptedRecruit)},

			{formatInt(ELuaMsg::SQUAD_REQUEST_ID), LuaMsgFunc(this.SelectSquadRequestId)},
			{formatInt(ELuaMsg::SQUAD_REQUEST_COMPOSE), LuaMsgFunc(this.SquadRequestCompose)},
			{formatInt(ELuaMsg::SQUAD_REQUEST_CANCEL), LuaMsgFunc(this.SquadRequestCancel)},
			{formatInt(ELuaMsg::SQUAD_REQUEST_PARAMS), LuaMsgFunc(this.SquadRequestParams)},

			{formatInt(ELuaMsg::SQUAD_ID), LuaMsgFunc(this.SelectSquadId)},
			{formatInt(ELuaMsg::SQUAD_DISBAND), LuaMsgFunc(this.SquadDisband)},
			{formatInt(ELuaMsg::SQUAD_TASK), LuaMsgFunc(this.SquadTask)},
			{formatInt(ELuaMsg::SQUAD_PARAMS), LuaMsgFunc(this.SquadParams)}
		};
	}

	void HandleLuaMsg(const string& in message) {
		array<string>@ command = message.split(SEP_COMMAND);
		LuaMsgFunc@ func = null;
		if (!luaMsgHandlers.get(command[0], @func))
			return;
		array<string>@ params = command[1].split(SEP_PARAM);
		func(params);
	}

	/*
	 * LuaMsg handlers
	 */
	void SetAiActive(const array<string>& in params) {
		// TODO
	}

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

	void SetUnitDefRetreat(const array<string>& in params) {
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<unitDefId>=<retreat_HP_percent>" pairs
			const array<string>@ kv = params[i].split(SEP_KEY_VALUE);
			CCircuitDef@ cdef = ai.GetCircuitDef(parseInt(kv[0]));
			if (cdef is null)
				continue;
			cdef.retreat = parseFloat(kv[1]);
		}
	}

	void SetFactoryActive(const array<string>& in params) {
		// params is "<isActive>=<unitId1>,<unitId2>,<unitId3>,..."
		const array<string>@ kv = params[0].split(SEP_KEY_VALUE);
		const array<string>@ unitIds = kv[1].split(SEP_SUBPARAM);
		bool isActive = kv[0] != "0";
		for (uint i = 0; i < unitIds.length(); ++i)
			aiFactoryMgr.SetIsActiveFactory(parseInt(unitIds[i]), isActive);
	}

	void SetScriptedRecruit(const array<string>& in params) {
		Factory::isRecruitScripted = params[0] != "0";
	}

	// Squad Request
	void SelectSquadRequestId(const array<string>& in params) {
		Squad::mgr.SelectSquad(parseInt(params[0]));
	}

	void SquadRequestCompose(const array<string>& in params) {
		Squad::mgr.ComposeRequest(params);
	}

	void SquadRequestCancel(const array<string>& in params) {
		Squad::mgr.DestroyRequest(parseInt(params[0]));
	}

	void SquadRequestParams(const array<string>& in params) {
		Squad::mgr.SetRequestParams(params);
	}

	// Squad
	void SelectSquadId(const array<string>& in params) {
		Squad::mgr.SelectSquad(parseInt(params[0]));
	}

	void SquadDisband(const array<string>& in params) {
		Squad::mgr.DestroySquadId(parseInt(params[0]));
	}

	void SquadTask(const array<string>& in params) {
		Squad::mgr.SetSquadTask(parseInt(params[0]));
	}

	void SquadParams(const array<string>& in params) {
		Squad::mgr.SetSquadParams(params);
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
