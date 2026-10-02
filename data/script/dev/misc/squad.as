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

enum ESquadPath {
	GOAL_RANGE    = 1,
	IGNORE_THREAT = 2,
	AVOID_THREAT  = 3,
	USE_END_POS   = 4,
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
		mgr.ClearTaskToSquad(task.id);
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
		fighterTask.attackRange = req.attackRange;
		fighterTask.retreat = req.retreat;
		mgr.SetTaskToSquad(task.id, this);
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

	void SetInitialTask() {
		mgr.ClearTaskToSquad(task.id);
		IUnitTask@ newTask = req.InitialTask();
		task.ReplaceBy(newTask);
		task.Abort();
		@task = newTask;
		mgr.SetTaskToSquad(task.id, this);
	}

	void SetEscort(Id vipId) {
 		ChangeTask(TaskF::Guard(vipId));
	}

	void SetPosition(const AIFloat3& in pos) {
		if (task.GetType() == Task::Type::FIGHTER)
			cast<IFighterTask>(task).SetTargetPos(pos);
	}

	void SetAttackRange(float range) {
		if (task.GetType() == Task::Type::FIGHTER)
			cast<IFighterTask>(task).attackRange = range;
	}

	void SetRetreat(float value) {
		if (task.GetType() == Task::Type::FIGHTER)
			cast<IFighterTask>(task).retreat = value;
	}

	void SetPriorityTarget(Id enemyId) {
		if (task.GetType() == Task::Type::FIGHTER && state == ESquadState::FINISHED)
			cast<IFighterTask>(task).vipTargetId = enemyId;
	}

	void ApplyPathingParams() {
		if (task.GetType() != Task::Type::FIGHTER)
			return;
		IFighterTask@ taskF = cast<IFighterTask>(task);
		taskF.goalRange = pathParams.goalRange;
		taskF.ignoreThreat = pathParams.ignoreThreat;
		taskF.avoidThreat = pathParams.avoidThreat;
		taskF.isEndPosOnly = pathParams.useEndPos;
	}

	Id id;
	Request@ req;
	IUnitTask@ task = null;  // military IFighterTask
	ESquadState state = ESquadState::CREATED;
	Pathing pathParams;
}


class Request {
	Request(Id p_id) {
		squadId = p_id;
		pos = AiTerrainCenter();
	}

	void ClearForRepeat() {
		unitNum = 0;
		for (auto it = recruitTasks.begin(); it++;) {
			mgr.ClearBuildTaskToReq(it.current());
			aiFactoryMgr.GetTaskById(it.current()).Abort();
		}
		recruitTasks.clear();
	}

	void ClearForCompose() {
		ClearForRepeat();
		unitDefs.clear();
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
		defendTask.attackRange = this.attackRange;
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
	int unitNum = 0;

	bool isRepeat = false;  // re-create on squad killed
}


class Amount {
	Amount(int n) {
		amount = n;
	}

	int amount;
	int assignedCount = 0;
}


class Pathing {
	float goalRange = -1.f;
	float ignoreThreat = 0.f;
	float avoidThreat = MAX_POWER;
	bool useEndPos = false;
}


class Manager {
	private void ParseRequestParams(const array<string>& in params, Request@ req) {
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<ESquadParam>=<values>" pairs
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			switch (parseInt(kv[0])) {
			case ESquadParam::POSITION: {  // "<posX>,<posZ>"
				const array<string>@ posStr = kv[1].split(LuaMsg::SEP_SUBPARAM);
				req.pos.x = parseFloat(posStr[0]);
				req.pos.z = parseFloat(posStr[1]);
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
		if (selSquad is null)
			return false;

		Request@ req = selSquad.req;
		req.ClearForCompose();
		bool isNewReq = selSquad.task is null;
		// NOTE: SQUAD_REQUEST_COMPOSE is a standalone message and can arrive multiple times at any time.
		//       If squad is in the middle of compositing - disband and start anew.
		if (!isNewReq && selSquad.state != ESquadState::FINISHED) {
			DestroySquad(selSquad);
			isNewReq = true;
		}
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<unitDefId>=<amount>" pairs
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			CCircuitDef@ cdef = ai.GetCircuitDef(parseInt(kv[0]));
			if (cdef is null)
				continue;
			Amount@ am = Amount(parseInt(kv[1]));
			req.unitDefs.insert(cdef.id, am);

			if (isNewReq)
				PlaceOrder(selSquad, cdef, am);
		}
		if (selSquad.task !is null)  // PlaceOrder could add existing unit and a task
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
		if (squad.req.unitNum <= taskUnitNum && squad.state == ESquadState::CREATED) {
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

		req.ClearForRepeat();
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
			DestroyRequest(squad);
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

	// Invoked by Military::AiTaskRemoved done=false
	bool SquadTaskCanceled(IUnitTask@ task) {
		bool success;
		Squad@ squad = taskToSquad.find(task.id, success);
		if (!success)
			return false;

		DestroySquad(squad);
		return true;
	}

	// Invoked by Military::AiTaskRemoved done=true
	bool SquadTaskFinished(IUnitTask@ task) {
		bool success;
		Squad@ squad = taskToSquad.find(task.id, success);
		if (!success)
			return false;

		if (cast<IFighterTask>(task).GetFightType() == Task::FightType::GUARD) {
			// Guard target was destroyed
			squad.SetInitialTask();
		} else
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

	private void ParseSquadParam(const array<string>& in params, Squad@ squad) {
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<ESquadParam>=<values>" pairs
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			switch (parseInt(kv[0])) {
			case ESquadParam::POSITION: {
				const array<string>@ posStr = kv[1].split(LuaMsg::SEP_SUBPARAM);
				AIFloat3 pos;
				pos.x = parseFloat(posStr[0]);
				pos.z = parseFloat(posStr[1]);
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

		ParseSquadParam(params, selSquad);
		return true;
	}

	// Invoked by LuaMsg::Manager::SquadTask
	bool SetSquadTask(int type) {
		if (selSquad is null || selSquad.task is null)
			return false;

		selSquad.SetTask(type);
		return true;
	}

	private void ParseSquadPathParam(const array<string>& in params, Squad@ squad) {
		for (uint i = 0; i < params.length(); ++i) {
			// params contains "<ESquadPath>=<values>" pairs
			const array<string>@ kv = params[i].split(LuaMsg::SEP_KEY_VALUE);
			switch (parseInt(kv[0])) {
			case ESquadPath::GOAL_RANGE: {
				squad.pathParams.goalRange = parseFloat(kv[1]);
			} break;
			case ESquadPath::IGNORE_THREAT: {
				squad.pathParams.ignoreThreat = parseFloat(kv[1]);
			} break;
			case ESquadPath::AVOID_THREAT: {
				squad.pathParams.avoidThreat = parseFloat(kv[1]);
			} break;
			case ESquadPath::USE_END_POS: {
				squad.pathParams.useEndPos = kv[1] != "0";
			}
			default: break;
			}
		}
		squad.ApplyPathingParams();
	}

	// Invoked by LuaMsg::Manager::SquadPathParams
	bool SetSquadPathParams(const array<string>& in params) {
		if (selSquad is null)
			return false;

		ParseSquadPathParam(params, selSquad);
		return true;
	}

	// Invoked by LuaMsg::Manager::SquadEscort
	bool SetSquadEscort(const array<string>& in params) {
		if (selSquad is null)
			return false;

		selSquad.SetEscort(parseInt(params[0]));
		return true;
	}

	void ClearBuildTaskToReq(Id taskId) {
		buildTaskToReq.erase(taskId);
	}

	void ClearTaskToSquad(Id taskId) {
		taskToSquad.erase(taskId);
	}

	void SetTaskToSquad(Id taskId, Squad@ squad) {
		@taskToSquad[taskId] = squad;
	}

	private map<Id, Squad@> squads;  // owner
	private array<Request@> requests;  // owner
	private map<Id, Request@> buildTaskToReq;  // CRecruitTask.id => Request
	private map<Id, Squad@> taskToSquad;  // ISquadTask.id => Squad

	private Squad@ selSquad;  // Selected state
}

Manager mgr;

}  // namespace Squad
