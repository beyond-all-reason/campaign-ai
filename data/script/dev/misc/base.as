#include "../../task.as"
#include "../../lua_msg.as"
#include "../manager/builder.as"


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

	array<BuildTask@> plans;
	map<Id, array<BuildTask@>@> udToPlan;  // UnitDefId: BuildTask
	set<Id> tasks;  // IBuilderTask.id for cleanup

	AIFloat3 pos;  // nominal center
	set<Id> buildings;  // UnitID
}

class BuildTask {
	Id unitDefId = -1;
	AIFloat3 pos;  // either single position
	Id zoneId = -1;  // or dedicated zone
	Base@ base = null;
	IBuilderTask@ task = null;
	bool isDone = false;
	bool isRebuild = false;
}

class Manager {
	private void ParseBasePlanParams(const array<string>& in params, Base@ base) {
		BuildTask bt;
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<EPlanParam>=<positional_values>" pairs
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			switch (parseInt(kv[0])) {  // kv[0]="<EPlanParam>"
			case EPlanParam::UNITDEF: {  // kv[1]="<unitDefId>"
				bt.unitDefId = parseInt(kv[1]);
				if (!base.udToPlan.contains(bt.unitDefId))
					base.udToPlan.insert(bt.unitDefId, {});
			} break;
			case EPlanParam::POSITION: {  // kv[1]="<posX>,<posZ>"
				const array<string>@ posStr = kv[1].split(LuaMsg::SEP_SUBPARAM);
				bt.pos.x = parseFloat(posStr[0]);
				bt.pos.z = parseFloat(posStr[1]);
			} break;
			case EPlanParam::ZONE: {  // kv[1]="<regionId>"
				// TODO
				bt.zoneId = parseInt(kv[1]);
			} break;
			case EPlanParam::REBUILD: {  // kv[1]="<bool>"
				bt.isRebuild = kv[1] != "0";
			} break;
			default: break;
			}
		}
		@bt.base = base;
		base.udToPlan[bt.unitDefId].insertLast(@bt);
		base.plans.insertLast(@bt);
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

	private Base@ GetNearestBase(const AIFloat3& in pos) {
		Base@ base = null;
		float sqLeastDist = BIG_FLOAT;
		for (auto it = bases.begin(); it++;) {
			Base@ checkBase = it.current_value();
			float sqDist = pos.SqDistance2D(checkBase.pos);
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

		bt.isDone = true;
		// TODO: Remove BuildTask out of plan if isRebuild=false
		taskToPlan.erase(task.id);
	}

	// Invoked by Builder::AiTaskRemoved done=false
	void BaseTaskCanceled(IBuilderTask@ task) {
		taskToPlan.erase(task.id);
		// TODO: Repeat if isRebuild
	}

	private map<Id, Base@> bases;  // owner
	private map<Id, BuildTask@> taskToPlan;  // IBuilderTask.id => BuildTask

	private Base@ selBase = null;  // Selected state
}

Manager mgr;

}  // namespace Base
