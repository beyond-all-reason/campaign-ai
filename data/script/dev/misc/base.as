#include "../../task.as"
#include "../../lua_msg.as"
#include "../manager/builder.as"


namespace Base {

// Must match the Lua definitions
enum EBaseParam {
	POSITION             =  1,
	METAL_POS            =  2,
	ENERGY_CHEAP_POS     =  3,
	ENERGY_MODERATE_POS  =  4,
	ENERGY_EXPENSIVE_POS =  5,

	RECLAIM_CONVERT      = 11,
	RECLAIM_ENERGY       = 12,
}

enum EPlanParam {
	UNITDEF  = 1,
	POSITION = 2,
	REBUILD  = 3,
}

class Base {
	Base(Id p_id) {
		id = p_id;
	}

	void adjustCenter(const AIFloat3& in pos) {
		const float weight = 1.0 / plans.length();
		center += (pos - center) * weight;
	}

	Id id;

	array<BuildTask@> plans;
	AIFloat3 center;  // nominal center
}

class BuildTask {
	bool opEquals(const BuildTask& in other) const {
		return (this.unitDefId == other.unitDefId && this.pos == other.pos);
	}

	Id unitDefId = -1;
	AIFloat3 pos;
	Base@ base = null;
	IBuilderTask@ task = null;
	bool isDone = false;
	bool isRebuild = false;
}

class Manager {
	private AIFloat3 ParsePosition(const string& in param) {
		// param contains "<posX>,<posZ>"
		const array<string>@ posStr = param.split(LuaMsg::SEP_SUBPARAM);
		return AIFloat3(parseFloat(posStr[0]), 0.f, parseFloat(posStr[1]));
	}

	private BuildTask@ ParseBasePlanParams(const array<string>& in params) {
		BuildTask bt;
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<EPlanParam>=<positional_values>" pairs
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			switch (parseInt(kv[0])) {  // kv[0]="<EPlanParam>"
			case EPlanParam::UNITDEF: {  // kv[1]="<unitDefId>"
				bt.unitDefId = parseInt(kv[1]);
			} break;
			case EPlanParam::POSITION: {  // kv[1]="<posX>,<posZ>"
				bt.pos = ParsePosition(kv[1]);
			} break;
			case EPlanParam::REBUILD: {  // kv[1]="<bool>"
				bt.isRebuild = kv[1] != "0";
			} break;
			default: break;
			}
		}
		return @bt;
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

		BuildTask@ bt = ParseBasePlanParams(params);
		@bt.base = selBase;
		selBase.plans.insertLast(@bt);
		selBase.adjustCenter(bt.pos);
		return true;
	}

	// Invoked by LuaMsg::Manager::BaseDelPlan
	bool DelBasePlan(const array<string>& in params) {
		if (selBase is null)
			return false;

		BuildTask@ bt = ParseBasePlanParams(params);
		for (uint i = 0; i < selBase.plans.length(); ++i)
			if (selBase.plans[i] == bt) {
				selBase.plans.removeAt(i);
				return true;
			}
		return false;
	}

	private Base@ GetNearestBase(const AIFloat3& in pos) {
		Base@ base = null;
		float sqLeastDist = BIG_FLOAT;
		for (auto it = bases.begin(); it++;) {
			Base@ checkBase = it.current_value();
			float sqDist = pos.SqDistance2D(checkBase.center);
			if (sqLeastDist <= sqDist)
				continue;
			sqLeastDist = sqDist;
			@base = checkBase;
		}
		return base;
	}

	// Invoked by Builder::AiMakeTask
	IBuilderTask@ GetTaskToBuild(CCircuitUnit@ unit) {
		// NOTE: Builder controller periodically re-evaluates assigned task.
		//       Return cached base one to save performance.
		if (taskToPlan.contains(unit.task.id))
			return cast<IBuilderTask>(unit.task);

		Base@ base = GetNearestBase(unit.GetPos(ai.frame));
		if (base is null)
			return null;

		for (uint i = 0; i < base.plans.length(); ++i) {
			BuildTask@ bt = base.plans[i];
			if (bt.isDone)
				continue;
			if (!unit.circuitDef.CanBuild(bt.unitDefId))
				continue;
			if (bt.task is null) {
				IUnitTask@ task = aiBuilderMgr.Enqueue(Builder::MakeBuildRecord(bt.unitDefId, bt.pos));
				taskToPlan.insert(task.id, @bt);
				@bt.task = cast<IBuilderTask>(task);
			}
			return bt.task;
		}
		return null;
	}

	// Invoked by Builder::AiTaskRemoved done=true
	void BaseTaskFinished(IBuilderTask@ task) {
		bool success;
		BuildTask@ bt = taskToPlan.find(task.id, success);
		if (!success)
			return;

		taskToPlan.erase(task.id);
		if (bt.isRebuild) {
			unitToPlan.insert(task.target.id, @bt);
			bt.isDone = true;
			@bt.task = null;
			return;
		}

		const int idx = bt.base.plans.findByRef(bt);
		bt.base.plans.removeAt(idx);
	}

	// Invoked by Builder::AiTaskRemoved done=false
	void BaseTaskCanceled(IBuilderTask@ task) {
		bool success;
		BuildTask@ bt = taskToPlan.find(task.id, success);
		if (!success)
			return;

		taskToPlan.erase(task.id);
		@bt.task = null;
	}

	// Invoked by Main::AiUnitDestroyed
	void UnitDestroyed(CCircuitUnit@ unit) {
		bool success;
		BuildTask@ bt = unitToPlan.find(unit.id, success);
		if (!success)
			return;

		bt.isDone = false;
	}

	// Invoked by LuaMsg::Manager::BaseCancel
	void FreeBase(Id baseId) {
		bool success;
		Base@ base = bases.find(baseId, success);
		if (!success)
			return;

		array<Id> remTasks;
		for (auto it = taskToPlan.begin(); it++;) {
			BuildTask@ bt = it.current_value();
			if (bt.base is base) {
				@bt.base = null;
				remTasks.insertLast(it.current_key());
			}
		}
		foreach (Id taskId : remTasks)
			taskToPlan.erase(taskId);

		bases.erase(baseId);
	}

	// Invoked by LuaMsg::Manager::BaseParams
	void SetBaseParams(const array<string>& in params) {
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<EBaseParam>=<values>" pairs
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			switch (parseInt(kv[0])) {
			case EBaseParam::POSITION: {  // kv[1]="<posX>,<posZ>"
				aiSetupMgr.SetBasePos(ParsePosition(kv[1]));
			} break;
			case EBaseParam::METAL_POS: {  // kv[1]="<posX>,<posZ>"
				aiSetupMgr.baseMetalPos = ParsePosition(kv[1]);
			} break;
			case EBaseParam::ENERGY_CHEAP_POS: {  // kv[1]="<posX>,<posZ>"
				aiSetupMgr.baseEnergy1Pos = ParsePosition(kv[1]);
			} break;
			case EBaseParam::ENERGY_MODERATE_POS: {  // kv[1]="<posX>,<posZ>"
				aiSetupMgr.baseEnergy2Pos = ParsePosition(kv[1]);
			} break;
			case EBaseParam::ENERGY_EXPENSIVE_POS: {  // kv[1]="<posX>,<posZ>"
				aiSetupMgr.baseEnergy3Pos = ParsePosition(kv[1]);
			} break;
			case EBaseParam::RECLAIM_CONVERT: {  // kv[1]="<ratio>"
				aiEconomyMgr.reclConvertEff = parseFloat(kv[1]);
			} break;
			case EBaseParam::RECLAIM_ENERGY: {  // kv[1]="<ratio>"
				aiEconomyMgr.reclEnergyEff = parseFloat(kv[1]);
			} break;
			default: break;
			}
		}
	}

	private map<Id, Base@> bases;  // owner
	private map<Id, BuildTask@> taskToPlan;  // IBuilderTask.id => BuildTask
	private map<Id, BuildTask@> unitToPlan;  // CCircuitUnit.id => BuildTask

	private Base@ selBase = null;  // Selected state
}

Manager mgr;

}  // namespace Base
