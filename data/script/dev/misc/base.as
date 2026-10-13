#include "../../task.as"
#include "../../lua_msg.as"


namespace Base {

// Must match the Lua definitions
enum EPlanParam {
	UNITDEF  = 1,
	POSITION = 2,
	ZONE     = 3,
	REBUILD  = 4,
}

class Base {
	Base(Id p_id) {
		id = p_id;
	}

	Id id;

	// array<BuildPlan@> plans;
	map<Id, array<BuildPlan@>@> udToPlan;  // UnitDefId: BuildPlan
	set<Id> tasks;  // IBuilderTask.id for cleanup

	AIFloat3 pos;  // nominal center
	set<Id> buildings;  // UnitID
}

class BuildPlan {
	Id unitDefId = -1;
	bool isDone = false;
	AIFloat3 pos;  // either single position
	Id zoneId = -1;  // or dedicated zone
	bool isRebuild = false;
}

class Manager {
	private void ParseBasePlanParams(const array<string>& in params, Base@ base) {
		BuildPlan bp;
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<EPlanParam>=<positional_values>" pairs
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			switch (parseInt(kv[0])) {  // kv[0]="<EPlanParam>"
			case EPlanParam::UNITDEF: {  // kv[1]="<unitDefId>"
				bp.unitDefId = parseInt(kv[1]);
				if (!base.udToPlan.contains(bp.unitDefId))
					base.udToPlan.insert(bp.unitDefId, {});
			} break;
			case EPlanParam::POSITION: {  // kv[1]="<posX>,<posZ>"
				const array<string>@ posStr = kv[1].split(LuaMsg::SEP_SUBPARAM);
				bp.pos.x = parseFloat(posStr[0]);
				bp.pos.z = parseFloat(posStr[1]);
			} break;
			case EPlanParam::ZONE: {  // kv[1]="<regionId>"
				// TODO
				bp.zoneId = parseInt(kv[1]);
			} break;
			case EPlanParam::REBUILD: {  // kv[1]="<bool>"
				bp.isRebuild = kv[1] != "0";
			} break;
			default: break;
			}
		}
		base.udToPlan[bp.unitDefId].insertLast(@bp);
		// base.plans.insertLast(@bp);
	}

	// Invoked by LuaMsg::Manager::SelectBaseId
	void SelectBase(Id baseId) {
		bool success;
		Base@ base = bases.find(baseId, success);
		if (!success) {
			@base = Base(baseId);
			bases.insert(base.id, @base);
		}
		@selBase = base;
	}

	// Invoked by LuaMsg::Manager::BaseAddPlan
	bool AddBasePlan(const array<string>& in params) {
		if (selBase is null)
			return false;

		ParseBasePlanParams(params, selBase);

		return true;
	}

	// Invoked by LuaMsg::Manager::BaseDelPlan
	bool DelBasePlan(const array<string>& in params) {
		if (selBase is null)
			return false;
		return true;
	}

	private map<Id, Base@> bases;  // owner
	private map<Id, Base@> taskToBase;  // IBuilderTask.id => Base

	private Base@ selBase = null;  // Selected state
}

Manager mgr;

}  // namespace Base
