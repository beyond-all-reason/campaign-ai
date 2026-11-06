#include "../../task.as"
#include "../../lua_msg.as"
#include "../manager/builder.as"
#include "lua_msg_manager.as"


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

	REGION_STATE         = 21,
}

enum EPlanParam {
	UNITDEF  = 1,
	POSITION = 2,
	REBUILD  = 3,
}

enum EBaseState {
	ACTIVE = 1,
	INACTIVE = 2,
	MAINTENANCE = 3,
}

class BaseRegion {
	BaseRegion(Id p_id) {
		id = p_id;
		@plan.region = this;
	}

	void Clear() {
		@plan.region = null;
	}

	Id id;
	Id ownerId;  // teamId
	EBaseState state;
	// optional plan
	BuildPlan plan;
	// optional region config
	CPolygon@ poly;  // border
	uint16 allowedMask;
}

class BuildPlan {
	void adjustCenter(const AIFloat3& in pos) {
		const float weight = 1.0 / buildTasks.length();
		center += (pos - center) * weight;
	}

	array<BuildTask@> buildTasks;
	AIFloat3 center;  // nominal center
	BaseRegion@ region;
	int unfinishedCount = 0;
	bool isDone = true;  // Manager::unfinishedPlans.contains(region) shortcut
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

	// Invoked by LuaMsg::Manager::SelectBaseRegionId
	void SelectBaseRegion(Id regionId) {
		bool success;
		BaseRegion@ region = regions.find(regionId, success);
		if (!success) {
			@region = BaseRegion(regionId);
			regions.insert(region.id, @region);
		}
		@selBaseRegion = region;
	}

	// Invoked by LuaMsg::Manager::AddBuildTask
	bool AddToBuildPlan(const array<string>& in params) {
		if (selBaseRegion is null)
			return false;

		BuildTask@ bt = ParseBuildTaskParams(params);
		BuildPlan@ plan = selBaseRegion.plan;
		@bt.plan = plan;
		plan.buildTasks.insertLast(@bt);
		plan.adjustCenter(bt.pos);
		++plan.unfinishedCount;
		if (plan.isDone) {
			plan.isDone = false;
			if (selBaseRegion.state != EBaseState::INACTIVE)
				unfinishedPlans.insert(@selBaseRegion);
		}
		return true;
	}

	// Invoked by LuaMsg::Manager::DelBuildTask
	bool RemoveFromBuildPlan(const array<string>& in params) {
		if (selBaseRegion is null)
			return false;

		BuildTask@ bt = ParseBuildTaskParams(params);
		BuildPlan@ plan = selBaseRegion.plan;
		for (uint i = 0; i < plan.buildTasks.length(); ++i)
			if (plan.buildTasks[i] == bt) {
				plan.buildTasks.removeAt(i);
				if (!plan.isDone)
					AdjustPlanFinished(plan);
				return true;
			}
		return false;
	}

	private BuildPlan@ GetNearestBuildPlan(const AIFloat3& in pos) {
		BuildPlan@ plan = null;
		float sqLeastDist = BIG_FLOAT;
		// NOTE: unfinishedPlans has only ACTIVE regions with non-empty plan.buildTasks
		for (auto it = unfinishedPlans.begin(); it++;) {
			BaseRegion@ region = it.current();
			BuildPlan@ checkPlan = region.plan;
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

	private void AdjustPlanFinished(BuildPlan @plan) {
		if (--plan.unfinishedCount == 0) {
			unfinishedPlans.erase(plan.region);
			plan.isDone = true;
			LuaMsg::mgr.SigBasePlanFinished(plan.region.id);
		}
	}

	// Invoked by Builder::AiTaskRemoved done=true
	void BuildTaskFinished(IBuilderTask@ task) {
		bool success;
		BuildTask@ bt = taskToBuildTask.find(task.id, success);
		if (!success)
			return;

		AdjustPlanFinished(bt.plan);

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

		AdjustPlanFinished(bt.plan);

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
		bt.plan.isDone = false;
		++bt.plan.unfinishedCount;
		if (selBaseRegion.state != EBaseState::INACTIVE)
			unfinishedPlans.insert(@bt.plan.region);
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
	void FreeBuildPlan(Id regionId) {
		bool success;
		BaseRegion@ region = regions.find(regionId, success);
		if (!success)
			return;

		ClearBuildPlan(region.plan);
	}

	// Invoked by LuaMsg::Manager::BaseRegionCancel
	void FreeBaseRegion(Id regionId) {
		bool success;
		BaseRegion@ region = regions.find(regionId, success);
		if (!success)
			return;

		ClearBuildPlan(region.plan);
		region.Clear();
		regions.erase(regionId);
	}

	private void SetRegionState(EBaseState state) {
		switch (state) {
		case EBaseState::ACTIVE: {
			selBaseRegion.state = state;
			if (!selBaseRegion.plan.isDone)
				unfinishedPlans.insert(@selBaseRegion);
		} break;
		case EBaseState::INACTIVE: {
			selBaseRegion.state = state;
			unfinishedPlans.erase(@selBaseRegion);
		} break;
		case EBaseState::MAINTENANCE: {
			selBaseRegion.state = state;
			if (!selBaseRegion.plan.isDone)
				unfinishedPlans.insert(@selBaseRegion);
		} break;
		default: break;
		}
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
			case EBaseParam::REGION_STATE: {  // kv[1]="<EBaseState>"
				if (selBaseRegion !is null)
					SetRegionState(EBaseState(parseInt(kv[1])));
			} break;
			default: break;
			}
		}
	}

	private map<Id, BaseRegion@> regions;  // owner
	private set<BaseRegion@> unfinishedPlans;  // regions with unfinished BuildPlan
	private map<Id, BuildTask@> taskToBuildTask;  // IBuilderTask.id => BuildTask
	private map<Id, BuildTask@> unitToBuildTask;  // CCircuitUnit.id => BuildTask

	private BaseRegion@ selBaseRegion = null;  // Selected state
}

Manager mgr;

}  // namespace Base
