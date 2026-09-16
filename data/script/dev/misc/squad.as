namespace Squad {

// Has to be same as Lua's defines
enum ESquadParams {
	SQUAD_POS_X        = 1,
	SQUAD_POS_Z        = 2,
	SQUAD_GATHER_RANGE = 3,
	SQUAD_ATTACK_RANGE = 4,
	SQUAD_IS_REPEAT    = 5,
}

enum ESquadTasks {
	TASK_DEFEND  = 1,
	TASK_SCOUT   = 2,
	TASK_RAID    = 3,
	TASK_ATTACK  = 4,
	TASK_BOMB    = 5,
	TASK_ARTY    = 6,
	TASK_AA      = 7,
	TASK_SUPPORT = 8,
	TASK_RETREAT = 9,
}

string SIG_SQUAD_FINISHED ("ai_squad_finished:" );
string SIG_SQUAD_DESTROYED("ai_squad_destroyed:");


class Squad {
	Squad(Request@ p_req) {
		id = p_req.squadId;
		@req = p_req;
	}

	void SetPosition(const AIFloat3& in pos) {
		ISquadTask@ squadTask = cast<ISquadTask>(task);
		switch (squadTask.GetFightType()) {
		case Task::FightType::DEFEND: {
			CDefendTask@ defendTask = cast<CDefendTask>(task);
			defendTask.SetPosition(pos);
		} break;
		case Task::FightType::RAID: {
			// TODO: SetPosition for all ISquadTask's
		} break;
		case Task::FightType::ATTACK: {
			// TODO: SetPosition for all ISquadTask's
		} break;
		default: break;
		}
	}

	void SetAttackRange(float range) {
		if (cast<ISquadTask>(task).GetFightType() != Task::FightType::DEFEND)  // FIXME
			return;
		cast<CDefendTask>(task).range = range;
	}

	private void ChangeTask(SFightTask& in data) {
		IUnitTask@ newTask = aiMilitaryMgr.Enqueue(data);
		task.ReplaceBy(newTask);
		task.Abort();
		@task = newTask;

		IFighterTask@ fighterTask = cast<IFighterTask>(task);
		fighterTask.isScripted = true;
		fighterTask.SetPosition(req.pos);
	}

	void SetTask(int type) {
		switch (type) {
		case ESquadTasks::TASK_DEFEND: {
			ChangeTask(TaskF::Defend(Task::FightType::ATTACK, req.power));
			CDefendTask@ defendTask = cast<CDefendTask>(task);
			defendTask.range = req.attackRange;
			defendTask.isRetreat = false;
		} break;
		case ESquadTasks::TASK_SCOUT: {
			ChangeTask(TaskF::Common(Task::FightType::SCOUT));
		} break;
		case ESquadTasks::TASK_RAID: {
			ChangeTask(TaskF::Common(Task::FightType::RAID));
		} break;
		case ESquadTasks::TASK_ATTACK: {
			ChangeTask(TaskF::Common(Task::FightType::ATTACK));
		} break;
		case ESquadTasks::TASK_BOMB: {
			ChangeTask(TaskF::Common(Task::FightType::BOMB));
		} break;
		case ESquadTasks::TASK_ARTY: {
			ChangeTask(TaskF::Common(Task::FightType::ARTY));
		} break;
		case ESquadTasks::TASK_AA: {
			ChangeTask(TaskF::Common(Task::FightType::AA));
		} break;
		case ESquadTasks::TASK_SUPPORT: {
			ChangeTask(TaskF::Common(Task::FightType::SUPPORT));
		} break;
		case ESquadTasks::TASK_RETREAT: {
			IUnitTask@ newTask = aiMilitaryMgr.EnqueueRetreat();
			task.ReplaceBy(newTask);
			task.Abort();
			@task = newTask;
		} break;
		default: break;
		}
	}

	Id id;
	Request@ req;
	IUnitTask@ task = null;  // military ISquadTask
}


class Request {
	Request(Id p_id) {
		squadId = p_id;
// 		id = p_id;
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
		power = 0.f;
	}

	Id squadId;
// 	Id id;
// 	set<Id> squads;

	map<Id, Amount@> unitDefs;  // UnitDefId: amount
	set<Id> recruitTasks;  // IUnitTask.id for cleanup
	AIFloat3 pos;
	float gatherRange = 64.f;
	float attackRange = 300.f;
	float power = 0.f;  // FIXME: power or unit number?
	int unitNum = 0;

	bool isRepeat = false;  // re-create on squad killed
// 	bool isInfinite = false;  // constantly produce squads
}


class Amount {
	Amount(int n) {
		amount = n;
	}

	int amount;
	int assignedCount = 0;
}


class Manager {
	private void ParseRequestParams(const SIntent& in intent, Request@ req) {
		for (uint i = 0; i < intent.size; ++i) {
			switch (intent.GetKey(i)) {
			case ESquadParams::SQUAD_POS_X: { req.pos.x = intent.GetValue(i); } break;
			case ESquadParams::SQUAD_POS_Z: { req.pos.z = intent.GetValue(i); } break;
			case ESquadParams::SQUAD_GATHER_RANGE: {
				req.gatherRange = intent.GetValue(i);
			} break;
			case ESquadParams::SQUAD_ATTACK_RANGE: {
				req.attackRange = intent.GetValue(i);
			} break;
			case ESquadParams::SQUAD_IS_REPEAT: {
				req.isRepeat = intent.GetValue(i) != 0.f;
			} break;
			default: break;
			}
		}
	}

	// Invoked by Intent::Manager::HandleIntent
	bool CreateRequest(const SIntent& in intent) {
		if (squads.contains(intent.objId))
			return false;

		Request req(intent.objId);
		ParseRequestParams(intent, req);
		requests.insertLast(@req);

		Squad squad(req);
		squads.insert(squad.id, @squad);
		return true;
	}

	private void PlaceOrder(Request@ req, CCircuitDef@ cdef, int inum) {
		req.unitNum += inum;
		Task::Priority priority = Task::Priority::NORMAL;
		Task::RecruitType recruit = Task::RecruitType::FIREPOWER;
		for (int j = 0; j < inum; ++j) {
			IUnitTask@ task = aiFactoryMgr.Enqueue(TaskS::Recruit(recruit, priority, cdef, req.pos, req.gatherRange));
			cast<CRecruitTask>(task).isSingleBuilder = true;
			@buildTaskToReq[task.id] = req;
			req.recruitTasks.insert(task.id);
		}
	}

	// Invoked by Intent::Manager::HandleIntent
	bool ComposeRequest(const SIntent& in intent) {
		// intent has {unitDefIs: amount} dictionary
		bool success;
		Squad@ squad = squads.find(intent.objId, success);
		if (!success)
			return false;

		Request@ req = squad.req;
		req.ClearForCompose(buildTaskToReq);
		for (uint i = 0; i < intent.size; ++i) {
			CCircuitDef@ cdef = ai.GetCircuitDef(intent.GetKey(i));
			if (cdef is null)
				continue;
			float num = intent.GetValue(i);
			int inum = int(num);
			req.unitDefs.insert(cdef.id, Amount(inum));
			req.power += cdef.power * num;

			PlaceOrder(req, cdef, inum);
		}
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

	// Invoked by Military::AiMakeTask
	IUnitTask@ AssignToSquad(CCircuitUnit@ unit) {
		Request@ req = GetRequestToAssign(unit);
		if (req is null)
			return null;

		Squad@ squad = squads[req.squadId];
		if (squad.task is null) {
			@squad.task = aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::ATTACK, req.power));  // FIXME: power or unit number?
			CDefendTask@ defendTask = cast<CDefendTask>(squad.task);
			defendTask.isScripted = true;
			defendTask.SetPosition(req.pos);
			defendTask.range = req.attackRange;
			defendTask.isRetreat = false;
			@taskToSquad[defendTask.id] = squad;
		}

		if (req.unitNum == squad.task.GetUnitCount() + 1) {
			ai.CallRules(SIG_SQUAD_FINISHED + req.squadId);
		}

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

	// Invoked by Intent::Manager::HandleIntent
	bool DestroyRequest(int squadId) {
		bool success;
		Squad@ squad = squads.find(squadId, success);
		if (!success)
			return false;

		RemoveRequest(squad.req);
		RemoveSquad(squad);
		return true;
	}

	private void RepeatRequest(Squad@ squad) {
		Request@ req = squad.req;
		if (squad.task !is null) {
			taskToSquad.erase(squad.task.id);
			IUnitTask@ newTask = aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::ATTACK, req.power));
			squad.task.ReplaceBy(newTask);
			squad.task.Abort();
			@squad.task = null;
		}

		RemoveRequest(req);
		for (auto it = req.unitDefs.begin(); it++;) {
			Amount@ am = it.current_value();
			am.assignedCount = 0;

			CCircuitDef@ cdef = ai.GetCircuitDef(it.current_key());
			PlaceOrder(req, cdef, am.amount);
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

	// Invoked by Intent::Manager::HandleIntent
	bool DestroySquadId(int squadId) {
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

	// Invoked by Intent::Manager::HandleIntent
	bool SetRequestParams(const SIntent& in intent) {
		bool success;
		Squad@ squad = squads.find(intent.objId, success);
		if (!success)
			return false;

		ParseRequestParams(intent, squad.req);
		return true;
	}

	private void ParseSquadParams(const SIntent& in intent, Squad@ squad) {
		AIFloat3 pos(-RgtVector);

		for (uint i = 0; i < intent.size; ++i) {
			switch (intent.GetKey(i)) {
			case ESquadParams::SQUAD_POS_X: { pos.x = intent.GetValue(i); } break;
			case ESquadParams::SQUAD_POS_Z: { pos.z = intent.GetValue(i); } break;
			case ESquadParams::SQUAD_ATTACK_RANGE: {
				squad.SetAttackRange(intent.GetValue(i));
			} break;
			default: break;
			}
		}

		if (pos.x >= 0.f)
			squad.SetPosition(pos);
	}

	// Invoked by Intent::Manager::HandleIntent
	bool SetSquadParams(const SIntent& in intent) {
		bool success;
		Squad@ squad = squads.find(intent.objId, success);
		if (!success || squad.task is null)
			return false;

		ParseSquadParams(intent, squad);
		return true;
	}

	// Invoked by Intent::Manager::HandleIntent
	bool SetSquadTask(const SIntent& in intent) {
		bool success;
		Squad@ squad = squads.find(intent.objId, success);
		if (!success || squad.task is null)
			return false;

		taskToSquad.erase(squad.task.id);
		squad.SetTask(int(intent.value));
		@taskToSquad[squad.task.id] = squad;
		return true;
	}

	private map<Id, Squad@> squads;  // owner
	private array<Request@> requests;  // owner
	private map<Id, Request@> buildTaskToReq;  // CRecruitTask.id => Request
	private map<Id, Squad@> taskToSquad;  // ISquadTask.id => Squad
}

Manager mgr;

}  // namespace Squad
