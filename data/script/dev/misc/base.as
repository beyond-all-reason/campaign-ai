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

class BuildPlan {
	BuildPlan(Id p_id) {
		id = p_id;
	}

	void adjustCenter(const AIFloat3& in pos) {
		const float weight = 1.0 / buildTasks.length();
		center += (pos - center) * weight;
	}

	Id id;

	array<BuildTask@> buildTasks;
	AIFloat3 center;  // nominal center
}

class BuildTask {
	bool opEquals(const BuildTask& in other) const {
		return (this.unitDefId == other.unitDefId && this.pos == other.pos);
	}

	Id unitDefId = -1;
	AIFloat3 pos;
	BuildPlan@ plan = null;
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

	private BuildTask@ ParseBuildTaskParams(const array<string>& in params) {
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

	// Invoked by LuaMsg::Manager::SelectBuildPlanId
	void SelectBuildPlan(Id planId) {
		bool success;
		BuildPlan@ plan = plans.find(planId, success);
		if (!success) {
			@plan = BuildPlan(planId);
			plans.insert(plan.id, @plan);
		}
		@selBuildPlan = plan;
	}

	// Invoked by LuaMsg::Manager::AddBuildTask
	bool AddToBuildPlan(const array<string>& in params) {
		if (selBuildPlan is null)
			return false;

		BuildTask@ bt = ParseBuildTaskParams(params);
		@bt.plan = selBuildPlan;
		selBuildPlan.buildTasks.insertLast(@bt);
		selBuildPlan.adjustCenter(bt.pos);
		return true;
	}

	// Invoked by LuaMsg::Manager::DelBuildTask
	bool RemoveFromBuildPlan(const array<string>& in params) {
		if (selBuildPlan is null)
			return false;

		BuildTask@ bt = ParseBuildTaskParams(params);
		for (uint i = 0; i < selBuildPlan.buildTasks.length(); ++i)
			if (selBuildPlan.buildTasks[i] == bt) {
				selBuildPlan.buildTasks.removeAt(i);
				return true;
			}
		return false;
	}

	private BuildPlan@ GetNearestBuildPlan(const AIFloat3& in pos) {
		BuildPlan@ plan = null;
		float sqLeastDist = BIG_FLOAT;
		for (auto it = plans.begin(); it++;) {
			BuildPlan@ checkPlan = it.current_value();
			if (checkPlan.buildTasks.isEmpty())
				continue;
			float sqDist = pos.SqDistance2D(checkPlan.center);
			if (sqLeastDist <= sqDist)
				continue;
			sqLeastDist = sqDist;
			@plan = checkPlan;
		}
		return plan;
	}

	// Invoked by Builder::AiMakeTask
	IBuilderTask@ GetTaskToBuild(CCircuitUnit@ unit) {
		// NOTE: Builder controller periodically re-evaluates assigned task.
		//       Return cached task to save performance.
		if (taskToBuildTask.contains(unit.task.id))
			return cast<IBuilderTask>(unit.task);

		BuildPlan@ plan = GetNearestBuildPlan(unit.GetPos(ai.frame));
		if (plan is null)
			return null;

		for (uint i = 0; i < plan.buildTasks.length(); ++i) {
			BuildTask@ bt = plan.buildTasks[i];
			if (bt.isDone)
				continue;
			if (!unit.circuitDef.CanBuild(bt.unitDefId))
				continue;
			if (bt.task is null) {
				IUnitTask@ task = aiBuilderMgr.Enqueue(Builder::MakeBuildRecord(bt.unitDefId, bt.pos));
				taskToBuildTask.insert(task.id, @bt);
				@bt.task = cast<IBuilderTask>(task);
			}
			return bt.task;
		}
		return null;
	}

	// Invoked by Builder::AiTaskRemoved done=true
	void BuildTaskFinished(IBuilderTask@ task) {
		bool success;
		BuildTask@ bt = taskToBuildTask.find(task.id, success);
		if (!success)
			return;

		taskToBuildTask.erase(task.id);
		if (bt.isRebuild) {
			unitToBuildTask.insert(task.target.id, @bt);
			bt.isDone = true;
			@bt.task = null;
			return;
		}

		const int idx = bt.plan.buildTasks.findByRef(bt);
		bt.plan.buildTasks.removeAt(idx);
	}

	// Invoked by Builder::AiTaskRemoved done=false
	void BuildTaskCanceled(IBuilderTask@ task) {
		bool success;
		BuildTask@ bt = taskToBuildTask.find(task.id, success);
		if (!success)
			return;

		taskToBuildTask.erase(task.id);
		@bt.task = null;
	}

	// Invoked by Main::AiUnitDestroyed
	void OnUnitDestroyed(CCircuitUnit@ unit) {
		bool success;
		BuildTask@ bt = unitToBuildTask.find(unit.id, success);
		if (!success)
			return;

		bt.isDone = false;
	}

	private void ClearBuildPlan(BuildPlan@ plan) {
		array<Id> remTasks;
		for (auto it = taskToBuildTask.begin(); it++;) {
			BuildTask@ bt = it.current_value();
			if (bt.plan is plan) {
				@bt.plan = null;
				remTasks.insertLast(it.current_key());
			}
		}
		foreach (Id taskId : remTasks)
			taskToBuildTask.erase(taskId);
	}

	// Invoked by LuaMsg::Manager::BuildPlanCancel
	void FreeBuildPlan(Id buildPlanId) {
		bool success;
		BuildPlan@ plan = plans.find(buildPlanId, success);
		if (!success)
			return;

		ClearBuildPlan(plan);

		plans.erase(buildPlanId);
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

	private map<Id, BuildPlan@> plans;  // owner
	private map<Id, BuildTask@> taskToBuildTask;  // IBuilderTask.id => BuildTask
	private map<Id, BuildTask@> unitToBuildTask;  // CCircuitUnit.id => BuildTask

	private BuildPlan@ selBuildPlan = null;  // Selected state
}

Manager mgr;

}  // namespace Base
