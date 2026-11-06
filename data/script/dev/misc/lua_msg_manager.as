#include "../../define.as"
#include "../../lua_msg.as"
#include "../manager/builder.as"
#include "../manager/factory.as"
#include "base.as"
#include "squad.as"
#include "region.as"


namespace LuaMsg {

// Must match the Lua definitions
enum EAIStateParam {
	PASSIVE    = 1,
	DEFENSIVE  = 2,
	NORMAL     = 3,
	AGGRESSIVE = 4,
}

enum EUpdateLoopParam {
	MILITARY_UPDATE_IDLE   =  1,
	MILITARY_UPDATE        =  2,
	MILITARY_WATCHDOG      =  3,
	MILITARY_DEFENCE_TASKS =  4,
	MILITARY_TRIGGERS_STEP =  5,
	BUILDER_UPDATE_IDLE    =  6,
	BUILDER_UPDATE         =  7,
	BUILDER_WATCHDOG       =  8,
	FACTORY_UPDATE_IDLE    =  9,
	FACTORY_UPDATE         = 10,
	FACTORY_WATCHDOG       = 11,
	SCRIPT_UPDATE          = 12,
	UNIT_ACTIONS           = 13,
}

enum EConstructParam {
	RECRUIT    = 1,
	BUILD_TASK = 2,
	FACTORY    = 3,
	STORAGE    = 4,
	METAL      = 5,
	ENERGY     = 6,
	ECONOMY    = 7,
	DEFENCE    = 8,
}

enum EMilitaryParam {
	SCOUTS_COUNT = 1,
	ATTACK_POWER = 2,
	RAID_POWER   = 3,
}

class Manager {
	void InitHandlers() {
		luaMsgHandlers = {
			{formatInt(ELuaMsg::SET_AI_ACTIVE), LuaMsgFunc(this.SetAiActive)},
			{formatInt(ELuaMsg::ENABLE_UNITDEFS), LuaMsgFunc(this.EnableUnitDefs)},
			{formatInt(ELuaMsg::DISABLE_UNITDEFS), LuaMsgFunc(this.DisableUnitDefs)},
			{formatInt(ELuaMsg::ENABLE_UNITS_CONTROL), LuaMsgFunc(this.EnableUnitsControl)},
			{formatInt(ELuaMsg::DISABLE_UNITS_CONTROL), LuaMsgFunc(this.DisableUnitsControl)},
			{formatInt(ELuaMsg::SET_AI_STATE), LuaMsgFunc(this.SetAiState)},

			{formatInt(ELuaMsg::SET_UNITDEF_RETREAT_HP), LuaMsgFunc(this.SetUnitDefRetreat)},
			{formatInt(ELuaMsg::SET_FACTORY_ACTIVE), LuaMsgFunc(this.SetFactoryActive)},
			{formatInt(ELuaMsg::SET_MEX_CAP), LuaMsgFunc(this.SetMexCap)},
			{formatInt(ELuaMsg::SET_ENGINE_EVENTS_ACTIVE), LuaMsgFunc(this.SetEngineEventsActive)},
			{formatInt(ELuaMsg::AI_UPDATE_LOOP_PARAMS), LuaMsgFunc(this.SetUpdateLoopParams)},
			{formatInt(ELuaMsg::AI_CONSTRUCTION_PARAMS), LuaMsgFunc(this.SetConstructionParams)},
			{formatInt(ELuaMsg::AI_MILITARY_PARAMS), LuaMsgFunc(this.SetMilitaryParams)},

			{formatInt(ELuaMsg::BASE_REGION_ID), LuaMsgFunc(this.SelectBaseRegionId)},
			{formatInt(ELuaMsg::BASE_REGION_CANCEL), LuaMsgFunc(this.BaseRegionCancel)},
			{formatInt(ELuaMsg::BASE_ADD_BUILDTASK), LuaMsgFunc(this.AddBuildTask)},
			{formatInt(ELuaMsg::BASE_DEL_BUILDTASK), LuaMsgFunc(this.DelBuildTask)},
			{formatInt(ELuaMsg::BASE_PLAN_CANCEL), LuaMsgFunc(this.BuildPlanCancel)},
			{formatInt(ELuaMsg::BASE_PARAMS), LuaMsgFunc(this.BaseParams)},

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
			{formatInt(ELuaMsg::RESERVED_REGION_ID), LuaMsgFunc(this.MakeReservedRegion)},
			{formatInt(ELuaMsg::RESERVED_REGION_CLEAR), LuaMsgFunc(this.ReservedRegionClear)},
			{formatInt(ELuaMsg::ALLOWED_REGION_ID), LuaMsgFunc(this.MakeAllowedRegion)},
			{formatInt(ELuaMsg::ALLOWED_REGION_CLEAR), LuaMsgFunc(this.AllowedRegionClear)},
			{formatInt(ELuaMsg::ALLOWED_GRID_FILL), LuaMsgFunc(this.AllowedGridFill)},
			{formatInt(ELuaMsg::TRIGGER_REGION_ID), LuaMsgFunc(this.MakeTriggerRegion)},
			{formatInt(ELuaMsg::TRIGGER_REGION_CLEAR), LuaMsgFunc(this.TriggerRegionClear)}
		};

		cfgMexCap = aiEconomyMgr.GetMexCap();
		cfgIsAllyMexCap = aiEconomyMgr.isAllyMexCap;
		cfgScoutsCount = aiMilitaryMgr.quota.scout;
		cfgAttackPower = aiMilitaryMgr.quota.attack;
		cfgRaidPower = aiMilitaryMgr.quota.raid.min;
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
		ai.SetEngineEventsActive(params[0] != "0");
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

	void SetAiState(const array<string>& in params) {
		switch (parseInt(params[0])) {
		case EAIStateParam::PASSIVE: {
			BatchSetUpdateLoopEnabled(false);

			Factory::isRecruitScripted = true;
			Builder::isConstructionScripted = true;
			aiEconomyMgr.isScriptFactory = true;
			aiEconomyMgr.isScriptStorage = true;
			aiEconomyMgr.isScriptMetal = true;
			aiEconomyMgr.isScriptEnergy = true;
			aiEconomyMgr.isScriptEconomy = true;
			aiMilitaryMgr.isScriptDefence = true;

			// all modules are disabled, its params - irrelevant
		} break;
		case EAIStateParam::DEFENSIVE: {
			BatchSetUpdateLoopEnabled(true);

			Factory::isRecruitScripted = true;
			Builder::isConstructionScripted = false;
			aiEconomyMgr.isScriptFactory = true;
			aiEconomyMgr.isScriptStorage = false;
			aiEconomyMgr.isScriptMetal = true;
			aiEconomyMgr.isScriptEnergy = false;
			aiEconomyMgr.isScriptEconomy = true;
			aiMilitaryMgr.isScriptDefence = false;

			// no expand
			aiEconomyMgr.SetMexCap(0.f, cfgIsAllyMexCap);
			aiMilitaryMgr.quota.scout = 0;
			aiMilitaryMgr.quota.attack = BIG_FLOAT;
			aiMilitaryMgr.quota.raid.min = BIG_FLOAT;
		} break;
		case EAIStateParam::NORMAL: {
			BatchSetUpdateLoopEnabled(true);

			Factory::isRecruitScripted = true;
			Builder::isConstructionScripted = false;
			aiEconomyMgr.isScriptFactory = false;
			aiEconomyMgr.isScriptStorage = false;
			aiEconomyMgr.isScriptMetal = true;
			aiEconomyMgr.isScriptEnergy = false;
			aiEconomyMgr.isScriptEconomy = false;
			aiMilitaryMgr.isScriptDefence = false;

			// no expand, but restore current percent of mexes
			aiEconomyMgr.SetMexCap(-1.f, cfgIsAllyMexCap);
			aiMilitaryMgr.quota.scout = cfgScoutsCount;
			aiMilitaryMgr.quota.attack = cfgAttackPower;
			aiMilitaryMgr.quota.raid.min = cfgRaidPower;
		} break;
		case EAIStateParam::AGGRESSIVE: {
			BatchSetUpdateLoopEnabled(true);

			Factory::isRecruitScripted = true;
			Builder::isConstructionScripted = false;
			aiEconomyMgr.isScriptFactory = false;
			aiEconomyMgr.isScriptStorage = false;
			aiEconomyMgr.isScriptMetal = false;
			aiEconomyMgr.isScriptEnergy = false;
			aiEconomyMgr.isScriptEconomy = false;
			aiMilitaryMgr.isScriptDefence = false;

			aiEconomyMgr.SetMexCap(cfgMexCap, cfgIsAllyMexCap);
			aiMilitaryMgr.quota.scout = cfgScoutsCount;
			aiMilitaryMgr.quota.attack = cfgAttackPower;
			aiMilitaryMgr.quota.raid.min = cfgRaidPower;
		} break;
		default: break;
		}
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
		const bool isActive = active_units[0] != "0";
		for (uint i = 0; i < unitIds.length(); ++i)
			aiFactoryMgr.SetIsActiveFactory(parseInt(unitIds[i]), isActive);
	}

	void SetMexCap(const array<string>& in params) {
		// params contains "<mex_percent>;<is_allyteam>"
		aiEconomyMgr.SetMexCap(parseFloat(params[0]), params[1] != "0");
	}

	void SetEngineEventsActive(const array<string>& in params) {
		ai.SetEngineEventsActive(params[0] != "0");
	}

	void SetUpdateLoopParams(const array<string>& in params) {
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<EUpdateLoopParam>=<bool>" pairs
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			const bool isEnabled = kv[1] != "0";
			switch (parseInt(kv[0])) {
			case EUpdateLoopParam::MILITARY_UPDATE_IDLE: {
				aiMilitaryMgr.SetUpdateIdleEnabled(isEnabled);
			} break;
			case EUpdateLoopParam::MILITARY_UPDATE: {
				aiMilitaryMgr.SetUpdateEnabled(isEnabled);
			} break;
			case EUpdateLoopParam::MILITARY_WATCHDOG: {
				aiMilitaryMgr.SetWatchdogEnabled(isEnabled);
			} break;
			case EUpdateLoopParam::MILITARY_DEFENCE_TASKS: {
				aiMilitaryMgr.SetDefenceTasksEnabled(isEnabled);
			} break;
			case EUpdateLoopParam::MILITARY_TRIGGERS_STEP: {
				aiMilitaryMgr.SetTriggersStepEnabled(isEnabled);
			} break;
			case EUpdateLoopParam::BUILDER_UPDATE_IDLE: {
				aiBuilderMgr.SetUpdateIdleEnabled(isEnabled);
			} break;
			case EUpdateLoopParam::BUILDER_UPDATE: {
				aiBuilderMgr.SetUpdateEnabled(isEnabled);
			} break;
			case EUpdateLoopParam::BUILDER_WATCHDOG: {
				aiBuilderMgr.SetWatchdogEnabled(isEnabled);
			} break;
			case EUpdateLoopParam::FACTORY_UPDATE_IDLE: {
				aiFactoryMgr.SetUpdateIdleEnabled(isEnabled);
			} break;
			case EUpdateLoopParam::FACTORY_UPDATE: {
				aiFactoryMgr.SetUpdateEnabled(isEnabled);
			} break;
			case EUpdateLoopParam::FACTORY_WATCHDOG: {
				aiFactoryMgr.SetWatchdogEnabled(isEnabled);
			} break;
			case EUpdateLoopParam::SCRIPT_UPDATE: {
				ai.isScriptUpdateEnabled = isEnabled;
			} break;
			case EUpdateLoopParam::UNIT_ACTIONS: {
				ai.isUnitActionsEnabled = isEnabled;
			} break;
			default: break;
			}
		}
	}

	void SetConstructionParams(const array<string>& in params) {
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<EConstructParam>=<bool>" pairs
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			const bool isScripted = kv[1] == "0";
			switch (parseInt(kv[0])) {
			case EConstructParam::RECRUIT: {
				Factory::isRecruitScripted = isScripted;
			} break;
			case EConstructParam::BUILD_TASK: {
				Builder::isConstructionScripted = isScripted;
			} break;
			case EConstructParam::FACTORY: {
				aiEconomyMgr.isScriptFactory = isScripted;
			} break;
			case EConstructParam::STORAGE: {
				aiEconomyMgr.isScriptStorage = isScripted;
			} break;
			case EConstructParam::METAL: {
				aiEconomyMgr.isScriptMetal = isScripted;
			} break;
			case EConstructParam::ENERGY: {
				aiEconomyMgr.isScriptEnergy = isScripted;
			} break;
			case EConstructParam::ECONOMY: {
				aiEconomyMgr.isScriptEconomy = isScripted;
			} break;
			case EConstructParam::DEFENCE: {
				aiMilitaryMgr.isScriptDefence = isScripted;
			} break;
			default: break;
			}
		}
	}

	void SetMilitaryParams(const array<string>& in params) {
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<EMilitaryParam>=<value>" pairs
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			switch (parseInt(kv[0])) {
			case EMilitaryParam::SCOUTS_COUNT: {
				aiMilitaryMgr.quota.scout = parseInt(kv[1]);
			} break;
			case EMilitaryParam::ATTACK_POWER: {
				aiMilitaryMgr.quota.attack = parseFloat(kv[1]);
			} break;
			case EMilitaryParam::RAID_POWER: {
				aiMilitaryMgr.quota.raid.min = parseFloat(kv[1]);
			} break;
			default: break;
			}
		}
	}

	// Base
	void SelectBaseRegionId(const array<string>& in params) {
		Base::mgr.SelectBaseRegion(parseInt(params[0]));
	}

	void BaseRegionCancel(const array<string>& in params) {
		Base::mgr.FreeBaseRegion(parseInt(params[0]));
	}

	void AddBuildTask(const array<string>& in params) {
		Base::mgr.AddToBuildPlan(params);
	}

	void DelBuildTask(const array<string>& in params) {
		Base::mgr.RemoveFromBuildPlan(params);
	}

	void BuildPlanCancel(const array<string>& in params) {
		Base::mgr.FreeBuildPlan(parseInt(params[0]));
	}

	void BaseParams(const array<string>& in params) {
		Base::mgr.SetBaseParams(params);
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
		Region::mgr.ClearBuildZones(params);
	}

	void MakeReservedRegion(const array<string>& in params) {
		Region::mgr.AddReservedZone(params);
	}

	void ReservedRegionClear(const array<string>& in params) {
		Region::mgr.ClearReservedZones(params);
	}

	void MakeAllowedRegion(const array<string>& in params) {
		Region::mgr.AddAllowedZone(params);
	}

	void AllowedRegionClear(const array<string>& in params) {
		Region::mgr.ClearAllowedZones(params);
	}

	void AllowedGridFill(const array<string>& in params) {
		Region::mgr.FillAllowedGrid(parseInt(params[0]));
	}

	void MakeTriggerRegion(const array<string>& in params) {
		Region::mgr.AddTriggerZone(params[0]);
	}

	void TriggerRegionClear(const array<string>& in params) {
		Region::mgr.ClearTriggerZones(params);
	}

	/*
	 * Signals
	 */
	void SigBasePlanFinished(Id regionId) {
		Signal(ESignal::BASE_PLAN_FINISHED, regionId);
	}

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

	private void BatchSetUpdateLoopEnabled(bool isEnabled) {
		aiMilitaryMgr.SetUpdateIdleEnabled(isEnabled);
		aiMilitaryMgr.SetUpdateEnabled(isEnabled);
		aiMilitaryMgr.SetWatchdogEnabled(isEnabled);
		aiMilitaryMgr.SetDefenceTasksEnabled(isEnabled);
		aiMilitaryMgr.SetTriggersStepEnabled(isEnabled);

		aiBuilderMgr.SetUpdateIdleEnabled(isEnabled);
		aiBuilderMgr.SetUpdateEnabled(isEnabled);
		aiBuilderMgr.SetWatchdogEnabled(isEnabled);

		aiFactoryMgr.SetUpdateIdleEnabled(isEnabled);
		aiFactoryMgr.SetUpdateEnabled(isEnabled);
		aiFactoryMgr.SetWatchdogEnabled(isEnabled);

		ai.isScriptUpdateEnabled = isEnabled;
		ai.isUnitActionsEnabled = isEnabled;
	}

	/*
	 * Properties
	 */
	funcdef void LuaMsgFunc(const array<string>& in params);
	private dictionary luaMsgHandlers;

	private map<Id, int> prevUnitLimits;  // behaviour.json may have other than MAX_UNITS value
	private float cfgMexCap;
	private bool cfgIsAllyMexCap;
	private uint cfgScoutsCount;
	private float cfgAttackPower;
	private float cfgRaidPower;
}

Manager mgr;

}  // namespace LuaMsg
