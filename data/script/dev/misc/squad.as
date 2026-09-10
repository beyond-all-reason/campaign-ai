namespace Squad {

// Has to be same as Lua's defines
enum ESquadParams {
	SQUAD_CREATE_RANGE = 1,
	SQUAD_POS_X        = 2,
	SQUAD_POS_Z        = 3,
	SQUAD_ATTACK_RANGE = 4,
	SQUAD_REPEAT       = 5,
	SQUAD_TASK         = 6,
}

enum ESquadTasks {
	TASK_DEFEND  = 1,
	TASK_RAID    = 2,
	TASK_ATTACK  = 3,
	TASK_RETREAT = 4,
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

	void SetTask(int type) {
		switch (type) {
		case ESquadTasks::TASK_DEFEND: {
			// TODO;
		} break;
		case ESquadTasks::TASK_RAID: {
			// TODO;
		} break;
		case ESquadTasks::TASK_ATTACK: {
			// TODO;
		} break;
		case ESquadTasks::TASK_RETREAT: {
			// TODO;
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
AiLog("Request.ClearForRepeat 0: " + recruitTasks.size());
		unitNum = 0;  // TODO: also power?
		for (auto it = recruitTasks.begin(); it++;) {
AiLog("Request.ClearForRepeat 1");
			buildTaskToReq.erase(it.current());
			aiFactoryMgr.GetTaskById(it.current()).Abort();
		}
		recruitTasks.clear();
AiLog("Request.ClearForRepeat 2");
	}

	void ClearForCompose(map<Id, Request@>& buildTaskToReq) {
AiLog("Request.ClearForCompose 0");
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
	float factoryRange = 64.f;
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
	private void ParseCreation(const SIntent& in intent, Request@ req) {
		for (uint i = 0; i < intent.size; ++i) {
			switch (intent.GetKey(i)) {
			case ESquadParams::SQUAD_CREATE_RANGE: {
				req.factoryRange = intent.GetValue(i);
			} break;
			case ESquadParams::SQUAD_POS_X: { req.pos.x = intent.GetValue(i); } break;
			case ESquadParams::SQUAD_POS_Z: { req.pos.z = intent.GetValue(i); } break;
			case ESquadParams::SQUAD_ATTACK_RANGE: {
				req.attackRange = intent.GetValue(i);
			} break;
			case ESquadParams::SQUAD_REPEAT: {
				req.isRepeat = intent.GetValue(i) != 0.f;
			} break;
			default: break;
			}
		}
	}

	// Invoked by Intent::Manager::HandleIntent
	bool CreateRequest(const SIntent& in intent) {
AiLog("CreateRequest");
		if (squads.contains(intent.objId))
			return false;

		Request req(intent.objId);
		ParseCreation(intent, req);
		requests.insertLast(@req);

		Squad squad(req);
		squads.insert(squad.id, @squad);
		return true;
	}

	private void PlaceOrder(Request@ req, CCircuitDef@ cdef, int inum) {
AiLog("PlaceOrder");
		req.unitNum += inum;
		Task::Priority priority = Task::Priority::NORMAL;
		Task::RecruitType recruit = Task::RecruitType::FIREPOWER;
		for (int j = 0; j < inum; ++j) {
			IUnitTask@ task = aiFactoryMgr.Enqueue(TaskS::Recruit(recruit, priority, cdef, req.pos, req.factoryRange));
			cast<CRecruitTask>(task).isSingleBuilder = true;
			@buildTaskToReq[task.id] = req;
			req.recruitTasks.insert(task.id);
		}
	}

	// Invoked by Intent::Manager::HandleIntent
	bool ComposeRequest(const SIntent& in intent) {
AiLog("ComposeRequest");
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
AiLog("GetRequestToAssign");
		Id defId = unit.circuitDef.id;
		for (uint i = 0; i < requests.length(); ++i) {
			Request@ req = requests[i];
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
AiLog("AssignToSquad");
		Request@ req = GetRequestToAssign(unit);
		if (req is null)
			return null;

		Squad@ squad = squads[req.squadId];
		if (squad.task is null) {
			@squad.task = aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::ATTACK, req.power));  // FIXME: power or unit number?
			CDefendTask@ defendTask = cast<CDefendTask>(squad.task);
			defendTask.isScripted = true;
			defendTask.range = req.attackRange;
			defendTask.isRetreat = false;
			defendTask.SetPosition(req.pos);
			@taskToSquad[defendTask.id] = squad;
		}

		if (req.unitNum == squad.task.GetUnitCount() + 1) {
			ai.CallRules(SIG_SQUAD_FINISHED + req.squadId);
		}

		return squad.task;
	}

	private void RemoveRequest(Request@ req) {
AiLog("RemoveRequest");
		int idx = requests.findByRef(req);
		if (idx < 0)
			return;

		req.ClearForRepeat(buildTaskToReq);
		requests.removeAt(idx);

		ai.CallRules(SIG_SQUAD_DESTROYED + req.squadId);
	}

	// Invoked by Intent::Manager::HandleIntent
	void DestroyRequest(int squadId) {
AiLog("DestroyRequest");
		if (!squads.contains(squadId))
			return;

		Squad@ squad = squads[squadId];
		RemoveRequest(squad.req);
		squads.erase(squadId);
		if (squad.task !is null) {
			taskToSquad.erase(squad.task.id);
			squad.task.Abort();
		}
	}

	private void RepeatRequest(Request@ req) {
AiLog("RepeatRequest");
		RemoveRequest(req);
		for (auto it = req.unitDefs.begin(); it++;) {
			Amount@ am = it.current_value();
			am.assignedCount = 0;

			CCircuitDef@ cdef = ai.GetCircuitDef(it.current_key());
			PlaceOrder(req, cdef, am.amount);
		}
		requests.insertLast(req);
	}

	// Invoked by Factory::AiTaskRemoved done=false
	void OrderCanceled(IUnitTask@ task) {
AiLog("OrderCanceled 0");
		bool success;
		Request@ req = buildTaskToReq.find(task.id, success);
		if (!success)
			return;

		buildTaskToReq.erase(task.id);
		req.recruitTasks.erase(task.id);
		// NOTE: Alternative is to re-create task; Not invoked on exit.
		req.unitNum--;
AiLog("OrderCanceled 1");
	}

	// Invoked by Factory::AiTaskRemoved done=true
	void OrderFinished(IUnitTask@ task) {
AiLog("OrderFinished");
		bool success;
		Request@ req = buildTaskToReq.find(task.id, success);
		if (!success)
			return;

		buildTaskToReq.erase(task.id);
		req.recruitTasks.erase(task.id);
	}

	// Invoked by Military::AiTaskRemoved
	bool SquadTaskDestroyed(IUnitTask@ task) {
AiLog("SquadTaskDestroyed");
		bool success;
		Squad@ squad = taskToSquad.find(task.id, success);
		if (!success)
			return false;

		taskToSquad.erase(task.id);
		if (squad.req.isRepeat) {
			RepeatRequest(squad.req);
			@squad.task = null;
		} else {
			RemoveRequest(squad.req);
			squads.erase(squad.id);
		}
		return true;
	}

	// Invoked by Intent::Manager::HandleIntent
	bool SetSquadPosition(const SIntent& in intent) {
		bool success;
		Squad@ squad = squads.find(intent.objId, success);
		if (!success || squad.task is null)
			return false;

		squad.SetPosition(AIFloat3(intent[0], 0, intent[1]));
		return true;
	}

	// Invoked by Intent::Manager::HandleIntent
	bool SetSquadParams(const SIntent& in intent) {
		bool success;
		Squad@ squad = squads.find(intent.objId, success);
		if (!success || squad.task is null)
			return false;

		for (uint i = 0; i < intent.size; ++i) {
			switch (intent.GetKey(i)) {
			case ESquadParams::SQUAD_ATTACK_RANGE: {
				squad.SetAttackRange(intent.GetValue(i));
			} break;
			case ESquadParams::SQUAD_TASK: {
				squad.SetTask(int(intent.GetValue(i)));
			} break;
			// TODO
			default: break;
			}
		}
		return true;
	}

	private map<Id, Squad@> squads;  // owner
	private array<Request@> requests;  // owner
	private map<Id, Request@> buildTaskToReq;  // CRecruitTask.id => Request
	private map<Id, Squad@> taskToSquad;  // ISquadTask.id => Squad
}

Manager mgr;

}  // namespace Squad
