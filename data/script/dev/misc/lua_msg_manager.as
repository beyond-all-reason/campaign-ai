#include "../../define.as"
#include "../../lua_msg.as"
#include "../manager/factory.as"
#include "base.as"
#include "squad.as"
#include "region.as"


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

			{formatInt(ELuaMsg::BASE_ID), LuaMsgFunc(this.SelectBaseId)},
			{formatInt(ELuaMsg::BASE_ADD_PLAN), LuaMsgFunc(this.BaseAddPlan)},
			{formatInt(ELuaMsg::BASE_DEL_PLAN), LuaMsgFunc(this.BaseDelPlan)},

			{formatInt(ELuaMsg::SQUAD_REQUEST_ID), LuaMsgFunc(this.SelectSquadRequestId)},
			{formatInt(ELuaMsg::SQUAD_REQUEST_COMPOSE), LuaMsgFunc(this.SquadRequestCompose)},
			{formatInt(ELuaMsg::SQUAD_REQUEST_CANCEL), LuaMsgFunc(this.SquadRequestCancel)},
			{formatInt(ELuaMsg::SQUAD_REQUEST_PARAMS), LuaMsgFunc(this.SquadRequestParams)},

			{formatInt(ELuaMsg::SQUAD_ID), LuaMsgFunc(this.SelectSquadId)},
			{formatInt(ELuaMsg::SQUAD_DISBAND), LuaMsgFunc(this.SquadDisband)},
			{formatInt(ELuaMsg::SQUAD_TASK), LuaMsgFunc(this.SquadTask)},
			{formatInt(ELuaMsg::SQUAD_PARAMS), LuaMsgFunc(this.SquadParams)},
			{formatInt(ELuaMsg::SQUAD_PATH_PARAMS), LuaMsgFunc(this.SquadPathParams)},
			{formatInt(ELuaMsg::SQUAD_ESCORT), LuaMsgFunc(this.SquadEscort)},

			{formatInt(ELuaMsg::BUILD_REGION_ID), LuaMsgFunc(this.MakeBuildRegion)},
			{formatInt(ELuaMsg::BUILD_REGION_CLEAR), LuaMsgFunc(this.BuildRegionClear)},
			{formatInt(ELuaMsg::TRIGGER_REGION_ID), LuaMsgFunc(this.MakeTriggerRegion)},
			{formatInt(ELuaMsg::TRIGGER_REGION_CLEAR), LuaMsgFunc(this.TriggerRegionClear)}
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
			const array<string>@ unitDef_retreat = params[i].split(SEP_KEY_VALUE);
			CCircuitDef@ cdef = ai.GetCircuitDef(parseInt(unitDef_retreat[0]));
			if (cdef is null)
				continue;
			cdef.retreat = parseFloat(unitDef_retreat[1]);
		}
	}

	void SetFactoryActive(const array<string>& in params) {
		// params is "<isActive>=<unitId1>,<unitId2>,<unitId3>,..."
		const array<string>@ active_units = params[0].split(SEP_KEY_VALUE);
		const array<string>@ unitIds = active_units[1].split(SEP_SUBPARAM);
		bool isActive = active_units[0] != "0";
		for (uint i = 0; i < unitIds.length(); ++i)
			aiFactoryMgr.SetIsActiveFactory(parseInt(unitIds[i]), isActive);
	}

	void SetScriptedRecruit(const array<string>& in params) {
		Factory::isRecruitScripted = params[0] != "0";
	}

	// Base
	void SelectBaseId(const array<string>& in params) {
		Base::mgr.SelectBase(parseInt(params[0]));
	}

	void BaseAddPlan(const array<string>& in params) {
		Base::mgr.AddBasePlan(params);
	}

	void BaseDelPlan(const array<string>& in params) {
		Base::mgr.DelBasePlan(params);
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
		Squad::mgr.DisbandSquadId(parseInt(params[0]));
	}

	void SquadTask(const array<string>& in params) {
		Squad::mgr.SetSquadTask(parseInt(params[0]));
	}

	void SquadParams(const array<string>& in params) {
		Squad::mgr.SetSquadParams(params);
	}

	void SquadPathParams(const array<string>& in params) {
		Squad::mgr.SetSquadPathParams(params);
	}

	void SquadEscort(const array<string>& in params) {
		Squad::mgr.SetSquadEscort(params);
	}

	// Region
	void MakeBuildRegion(const array<string>& in params) {
		Region::mgr.AddBuildZone(params);
	}

	void BuildRegionClear(const array<string>& in params) {
		Region::mgr.ClearBuildZones();
	}

	void MakeTriggerRegion(const array<string>& in params) {
		Region::mgr.AddTriggerZone(params[0]);
	}

	void TriggerRegionClear(const array<string>& in params) {
		Region::mgr.ClearTriggerZones();
	}

	/*
	 * Signals
	 */
	void SigSquadFinished(Id squadId) {
		Signal(ESignal::SQUAD_FINISHED, squadId);
	}

	void SigSquadDestroyed(Id squadId) {
		Signal(ESignal::SQUAD_DESTROYED, squadId);
	}

	void SigRegionEnter(Id regionId, Id squadId) {
		Signal(ESignal::REGION_ENTER, regionId, squadId);
	}

	void SigRegionExit(Id regionId, Id squadId) {
		Signal(ESignal::REGION_EXIT, regionId, squadId);
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
