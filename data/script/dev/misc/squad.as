#include "../../task.as"
#include "../../lua_msg.as"


namespace Squad {

// Has to be same as Lua's defines
enum ESquadParam {
	POSITION           = 1,
	SQUAD_GATHER_RANGE = 2,
	SQUAD_ATTACK_RANGE = 3,
	SQUAD_REBUILD      = 4,
	SQUAD_RETREAT      = 5,
	SQUAD_PRIO_TARGET  = 6,
}

enum ESquadTask {
	DEFEND    = 1,
	SCOUT     = 2,
	RAID      = 3,
	ATTACK    = 4,
	BOMBER    = 5,
	ARTILLERY = 6,
	ANTI_AIR  = 7,
	SUPPORT   = 8,
}

enum ESquadState {CREATED, FINISHED}

string SIG_SQUAD_FINISHED ("ai_squad_finished:" );
string SIG_SQUAD_DESTROYED("ai_squad_destroyed:");

const int TASK_NO_TAG = 0;
const int TASK_SQUAD_TAG = 42;


class Squad {
	Squad(Request@ p_req) {
		id = p_req.squadId;
		@req = p_req;
	}

	private void ChangeTask(SFightTask& in data) {
		IUnitTask@ newTask = aiMilitaryMgr.Enqueue(data);
		newTask.tag = TASK_SQUAD_TAG;
		task.ReplaceBy(newTask);
		task.Abort();
		@task = newTask;

		IFighterTask@ fighterTask = cast<IFighterTask>(newTask);
		fighterTask.isScripted = true;
		fighterTask.isMergeAllowed = false;
		fighterTask.isRegroupAllowed = true;
		fighterTask.SetTargetPos(req.pos);
		fighterTask.range = req.attackRange;
		fighterTask.retreat = req.retreat;
	}

	void SetTask(int type) {
		switch (type) {
		case ESquadTask::DEFEND: {
			ChangeTask(TaskF::Defend(Task::FightType::ATTACK, MAX_POWER));
		} break;
		case ESquadTask::SCOUT: {
			ChangeTask(TaskF::Common(Task::FightType::SCOUT));
		} break;
		case ESquadTask::RAID: {
			ChangeTask(TaskF::Common(Task::FightType::RAID));
		} break;
		case ESquadTask::ATTACK: {
			ChangeTask(TaskF::Common(Task::FightType::ATTACK));
		} break;
		case ESquadTask::BOMBER: {
			ChangeTask(TaskF::Common(Task::FightType::BOMB));
		} break;
		case ESquadTask::ARTILLERY: {
			ChangeTask(TaskF::Common(Task::FightType::ARTY));
		} break;
		case ESquadTask::ANTI_AIR: {
			ChangeTask(TaskF::Common(Task::FightType::AA));
		} break;
		case ESquadTask::SUPPORT: {
			ChangeTask(TaskF::Common(Task::FightType::SUPPORT));
		} break;
		default: break;
		}
	}

	void SetPosition(const AIFloat3& in pos) {
		if (task.GetType() == Task::Type::FIGHTER)
			cast<IFighterTask>(task).SetTargetPos(pos);
	}

	void SetAttackRange(float range) {
		if (task.GetType() == Task::Type::FIGHTER)
			cast<IFighterTask>(task).range = range;
	}

	void SetRetreat(float value) {
		if (task.GetType() == Task::Type::FIGHTER)
			cast<IFighterTask>(task).retreat = value;
	}

	void SetPriorityTarget(Id enemyId) {
		if (task.GetType() == Task::Type::FIGHTER && state == ESquadState::FINISHED)
			cast<IFighterTask>(task).vipTargetId = enemyId;
	}

	Id id;
	Request@ req;
	IUnitTask@ task = null;  // military IFighterTask
	ESquadState state = ESquadState::CREATED;
}


class Request {
	Request(Id p_id) {
		squadId = p_id;
		pos = AiTerrainCenter();
	}

	void ClearForRepeat(map<Id, Request@>& buildTaskToReq) {
		unitNum = 0;  // TODO: also power?
		for (auto it = recruitTasks.begin(); it++;) {
			buildTaskToReq.erase(it.current());
			aiFactoryMgr.GetTaskById(it.current()).Abort();
		}
		recruitTasks.clear();
	}

	void ClearForCompose(map<Id, Request@>& buildTaskToReq) {
		ClearForRepeat(buildTaskToReq);
		unitDefs.clear();
		// power = 0.f;
	}

	IUnitTask@ InitialTask() {
		IUnitTask@ task = aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::ATTACK, MAX_POWER));  // NOTE: ignore power
		task.tag = TASK_SQUAD_TAG;
		CDefendTask@ defendTask = cast<CDefendTask>(task);
		defendTask.isScripted = true;
		defendTask.isMergeAllowed = false;
		defendTask.isRegroupAllowed = false;
		defendTask.SetTargetPos(this.pos);
		defendTask.vipTargetId = -1;
		defendTask.range = this.attackRange;
		defendTask.retreat = this.retreat;
		return task;
	}

	Id squadId;

	map<Id, Amount@> unitDefs;  // UnitDefId: amount
	set<Id> recruitTasks;  // CRecruitTask.id for cleanup
	AIFloat3 pos;
	Id vipTargetId = -1;
	float gatherRange = 64.f;
	float attackRange = 300.f;
	float retreat = 0.f;
	// float power = 0.f;  // FIXME: power or unit number?
	int unitNum = 0;

	bool isRepeat = false;  // re-create on squad killed
	// bool isInfinite = false;  // constantly produce squads
}


class Amount {
	Amount(int n) {
		amount = n;
	}

	int amount;
	int assignedCount = 0;
}


class Manager {
	private void ParseRequestParams(const array<string>& in params, Request@ req) {
		for (uint i = 0; i < params.length(); ++i) {
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			switch (parseInt(kv[0])) {
			case ESquadParam::POSITION: {
				const array<string>@ values = kv[1].split(LuaMsg::SEP_SUBPARAM);
				req.pos.x = parseFloat(values[0]);
				req.pos.z = parseFloat(values[1]);
			} break;
			case ESquadParam::SQUAD_GATHER_RANGE: {
				req.gatherRange = parseFloat(kv[1]);
			} break;
			case ESquadParam::SQUAD_ATTACK_RANGE: {
				req.attackRange = parseFloat(kv[1]);
			} break;
			case ESquadParam::SQUAD_REBUILD: {
				req.isRepeat = kv[1] != "0";
			} break;
			case ESquadParam::SQUAD_RETREAT: {
				req.retreat = parseFloat(kv[1]);
			} break;
			case ESquadParam::SQUAD_PRIO_TARGET: {
				req.vipTargetId = parseInt(kv[1]);
			} break;
			default: break;
			}
		}
	}

	// Invoked by LuaMsg::Manager::SelectSquadRequestId / SelectSquadId
	void SelectSquad(Id squadId) {
		bool success;
		Squad@ squad = squads.find(squadId, success);
		if (!success) {
			Request req(squadId);
			requests.insertLast(@req);
			@squad = Squad(req);
			squads.insert(squad.id, @squad);
		}
		@selSquad = squad;
	}

	// Check for existing units. Place build-order if not enough found.
	private void PlaceOrder(Squad@ squad, CCircuitDef@ cdef, Amount@ am) {
		Request@ req = squad.req;
		req.unitNum += am.amount;
		// req.power += cdef.power * am.amount;

		Task::Priority priority = Task::Priority::NORMAL;
		Task::RecruitType recruit = Task::RecruitType::FIREPOWER;
		for (int j = 0; j < am.amount; ++j) {
			CCircuitUnit@ freeUnit = ai.GetUnitInRange(req.pos, req.gatherRange,
					cdef.id, Task::Type::FIGHTER, TASK_NO_TAG);
			if (freeUnit !is null) {
				UpdateSquadTask(squad);
				aiMilitaryMgr.AssignTask(freeUnit, squad.task);
				am.assignedCount++;
				continue;
			}

			IUnitTask@ task = aiFactoryMgr.Enqueue(TaskS::Recruit(recruit, priority, cdef, req.pos, req.gatherRange));
			cast<CRecruitTask>(task).isSingleBuilder = true;
			@buildTaskToReq[task.id] = req;
			req.recruitTasks.insert(task.id);
		}
	}

	// Invoked by LuaMsg::Manager::SquadRequestCompose
	bool ComposeRequest(const array<string>& in params) {
		// message contains {unitDefId: amount} dictionary
		if (selSquad is null)
			return false;

		Request@ req = selSquad.req;
		req.ClearForCompose(buildTaskToReq);
		if (selSquad.task !is null)
			DestroySquad(selSquad);
		for (uint i = 0; i < params.length(); ++i) {
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			CCircuitDef@ cdef = ai.GetCircuitDef(parseInt(kv[0]));
			if (cdef is null)
				continue;
			Amount@ am = Amount(parseInt(kv[1]));
			req.unitDefs.insert(cdef.id, am);

			PlaceOrder(selSquad, cdef, am);
		}
		if (selSquad.task !is null)
			CheckSquadFinished(selSquad, selSquad.task.GetUnitCount());
		return true;
	}

	private Request@ GetRequestToAssign(CCircuitUnit@ unit) {
		Id defId = unit.circuitDef.id;
		AIFloat3 unitPos = unit.GetPos(ai.frame);
		for (uint i = 0; i < requests.length(); ++i) {
			Request@ req = requests[i];
			if (!unitPos.IsInRange(req.pos, req.gatherRange))
				continue;
			bool success;
			Amount@ am = req.unitDefs.find(defId, success);
			if (!success)
				continue;
			if (am.amount > am.assignedCount) {
				// NOTE: Actual assignment takes place in C++ after return from AiMakeTask
				am.assignedCount++;
				return req;
			}
		}
		return null;
	}

	private void UpdateSquadTask(Squad@ squad) {
		if (squad.task is null) {
			squad.state = ESquadState::CREATED;
			@squad.task = squad.req.InitialTask();
			@taskToSquad[squad.task.id] = squad;
		}
	}

	private void CheckSquadFinished(Squad@ squad, int taskUnitNum) {
		if (squad.req.unitNum == taskUnitNum && squad.state == ESquadState::CREATED) {
			IFighterTask@ fighterTask = cast<IFighterTask>(squad.task);
			fighterTask.isRegroupAllowed = true;
			fighterTask.vipTargetId = squad.req.vipTargetId;
			squad.state = ESquadState::FINISHED;
			ai.CallRules(SIG_SQUAD_FINISHED + squad.req.squadId);
		}
	}

	// Invoked by Military::AiMakeTask
	IUnitTask@ AssignToRequest(CCircuitUnit@ unit) {
		Request@ req = GetRequestToAssign(unit);
		if (req is null)
			return null;

		Squad@ squad = squads[req.squadId];
		UpdateSquadTask(squad);
		CheckSquadFinished(squad, squad.task.GetUnitCount() + 1);

		return squad.task;
	}

	private void RemoveRequest(Request@ req) {
		int idx = requests.findByRef(req);
		if (idx < 0)
			return;

		req.ClearForRepeat(buildTaskToReq);
		requests.removeAt(idx);

		ai.CallRules(SIG_SQUAD_DESTROYED + req.squadId);
	}

	private void RemoveSquad(Squad@ squad) {
		squads.erase(squad.id);
		if (squad.task !is null) {
			taskToSquad.erase(squad.task.id);
			squad.task.Abort();
		}
	}

	private void DestroyRequest(Squad@ squad) {
		RemoveRequest(squad.req);
		RemoveSquad(squad);
	}

	// Invoked by LuaMsg::Manager::SquadRequestCancel
	bool DestroyRequest(Id squadId) {
		bool success;
		Squad@ squad = squads.find(squadId, success);
		if (!success)
			return false;

		DestroyRequest(squad);
		return true;
	}

	private void RepeatRequest(Squad@ squad) {
		Request@ req = squad.req;
		if (squad.task !is null) {
			taskToSquad.erase(squad.task.id);
			squad.task.Abort();
			@squad.task = null;
		}

		RemoveRequest(req);
		for (auto it = req.unitDefs.begin(); it++;) {
			Amount@ am = it.current_value();
			am.assignedCount = 0;

			CCircuitDef@ cdef = ai.GetCircuitDef(it.current_key());
			PlaceOrder(squad, cdef, am);
		}
		requests.insertLast(req);
	}

	private void DestroySquad(Squad@ squad) {
		if (squad.req.isRepeat) {
			RepeatRequest(squad);
		} else {
			RemoveSquad(squad);
		}
	}

	// Invoked by LuaMsg::Manager::SquadDisband
	bool DestroySquadId(Id squadId) {
		bool success;
		Squad@ squad = squads.find(squadId, success);
		if (!success)
			return false;

		DestroySquad(squad);
		return true;
	}

	// Invoked by Factory::AiTaskRemoved done=false
	void BuildOrderCanceled(IUnitTask@ task) {
		bool success;
		Request@ req = buildTaskToReq.find(task.id, success);
		if (!success)
			return;

		buildTaskToReq.erase(task.id);
		req.recruitTasks.erase(task.id);

		// NOTE: Alternative is to re-create task; Not invoked on exit.
		req.unitNum--;
		req.unitDefs[cast<IBuilderTask>(task).buildDef.id].assignedCount++;
		Squad@ squad = squads[req.squadId];
		if (squad.task is null) {
			if (req.unitNum == 0)
				DestroyRequest(squad);
		} else
			CheckSquadFinished(squad, squad.task.GetUnitCount());
	}

	// Invoked by Factory::AiTaskRemoved done=true
	void BuildOrderFinished(IUnitTask@ task) {
		bool success;
		Request@ req = buildTaskToReq.find(task.id, success);
		if (!success)
			return;

		buildTaskToReq.erase(task.id);
		req.recruitTasks.erase(task.id);
	}

	// Invoked by Military::AiTaskRemoved
	bool SquadTaskDestroyed(IUnitTask@ task) {
		bool success;
		Squad@ squad = taskToSquad.find(task.id, success);
		if (!success)
			return false;

		taskToSquad.erase(task.id);
		@squad.task = null;
		DestroySquad(squad);
		return true;
	}

	// Invoked by Military::AiUnitRemoved
	bool SquadUnitDestroyed(CCircuitUnit@ unit) {
		bool success;
		Squad@ squad = taskToSquad.find(unit.task.id, success);
		if (!success)
			return false;

		// NOTE: Alternative is to create build-task; and decrease am.assignedCount
		squad.req.unitNum--;
		return true;
	}

	// Invoked by LuaMsg::Manager::SquadRequestParams
	bool SetRequestParams(const array<string>& in params) {
		if (selSquad is null)
			return false;

		ParseRequestParams(params, selSquad.req);
		return true;
	}

	private void ParsESquadParam(const array<string>& in params, Squad@ squad) {
		for (uint i = 0; i < params.length(); ++i) {
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			switch (parseInt(kv[0])) {
			case ESquadParam::POSITION: {
				const array<string>@ values = kv[1].split(LuaMsg::SEP_SUBPARAM);
				AIFloat3 pos;
				pos.x = parseFloat(values[0]);
				pos.z = parseFloat(values[1]);
				squad.SetPosition(pos);
			} break;
			case ESquadParam::SQUAD_ATTACK_RANGE: {
				squad.SetAttackRange(parseFloat(kv[1]));
			} break;
			case ESquadParam::SQUAD_RETREAT: {
				squad.SetRetreat(parseFloat(kv[1]));
			} break;
			case ESquadParam::SQUAD_PRIO_TARGET: {
				squad.SetPriorityTarget(parseInt(kv[1]));
			} break;
			default: break;
			}
		}
	}

	// Invoked by LuaMsg::Manager::SquadParams
	bool SetSquadParams(const array<string>& in params) {
		if (selSquad is null)
			return false;

		ParsESquadParam(params, selSquad);
		return true;
	}

	// Invoked by LuaMsg::Manager::SquadTask
	bool SetSquadTask(int type) {
		if (selSquad is null || selSquad.task is null)
			return false;

		taskToSquad.erase(selSquad.task.id);
		selSquad.SetTask(type);
		@taskToSquad[selSquad.task.id] = selSquad;
		return true;
	}

	private map<Id, Squad@> squads;  // owner
	private array<Request@> requests;  // owner
	private map<Id, Request@> buildTaskToReq;  // CRecruitTask.id => Request
	private map<Id, Squad@> taskToSquad;  // ISquadTask.id => Squad

	private Squad@ selSquad;  // Selected state
}

Manager mgr;

}  // namespace Squad
