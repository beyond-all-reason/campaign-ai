namespace Squad {

// Has to be same as Lua's defines
enum ESquadParams {
	SQUAD_CREATE_RANGE = 1,
	SQUAD_POS_X        = 2,
	SQUAD_POS_Z        = 3,
	SQUAD_ATTACK_RANGE = 4,
	SQUAD_REPEAT       = 5,
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

	Id id;
	Request@ req;
	IUnitTask@ task = null;  // ISquadTask task
}

class Request {
	Request(Id p_id) {
		squadId = p_id;
		pos = AiTerrainCenter();
	}

	void Clear() {
		for (auto it = recruitTasks.begin(); it++;) {
			aiFactoryMgr.GetTaskById(it.current()).Abort();
		}
		recruitTasks.clear();
	}

	Id squadId;
	map<Id, Amount@> unitDefs;  // UnitDefId: amount
	set<Id> recruitTasks;  // IUnitTask.id for cleanup
	AIFloat3 pos;
	float factoryRange = 64.f;
	float attackRange = 300.f;
	float power = 0.f;  // FIXME: power or unit number?
	int unitNum = 0;
	bool isRepeat = false;
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

	bool CreateRequest(const SIntent& in intent) {
		if (squads.contains(intent.objId))
			return false;

		Request req(intent.objId);
		ParseCreation(intent, req);
		requests.insertLast(@req);

		Squad squad(req);
		squads.insert(squad.id, @squad);
		return true;
	}

	bool ComposeRequest(const SIntent& in intent) {
		// intent has {unitDefIs: amount} dictionary
		bool success;
		Squad@ squad = squads.find(intent.objId, success);
		if (!success)
			return false;

		Request@ req = squad.req;
		for (uint i = 0; i < intent.size; ++i) {
			CCircuitDef@ cdef = ai.GetCircuitDef(intent.GetKey(i));
			if (cdef is null)
				continue;
			float num = intent.GetValue(i);
			req.unitDefs.insert(cdef.id, Amount(int(num)));
			req.power += cdef.power * num;
			req.unitNum += int(num);

			// Recruit-tasks creation and tracking
			Task::Priority priority = Task::Priority::NORMAL;
			Task::RecruitType recruit = Task::RecruitType::FIREPOWER;
			for (int j = 0; j < int(num); ++j) {
				IUnitTask@ task = aiFactoryMgr.Enqueue(TaskS::Recruit(recruit, priority, cdef, req.pos, req.factoryRange));
				cast<CRecruitTask>(task).isSingleBuilder = true;
				@buildTaskToReq[task.id] = req;
				req.recruitTasks.insert(task.id);
			}
		}
		return true;
	}

	private Request@ GetRequestToAssign(CCircuitUnit@ unit) {
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

	void OrderCanceled(IUnitTask@ task) {
		bool success;
		Request@ req = buildTaskToReq.find(task.id, success);
		if (!success)
			return;

		buildTaskToReq.erase(task.id);
		req.recruitTasks.erase(task.id);
		// NOTE: Alternative is to re-create task; Not invoked on exit.
		req.unitNum--;
	}

	void OrderFinished(IUnitTask@ task) {
		bool success;
		Request@ req = buildTaskToReq.find(task.id, success);
		if (!success)
			return;

		buildTaskToReq.erase(task.id);
		req.recruitTasks.erase(task.id);
	}

	IUnitTask@ AssignToSquad(CCircuitUnit@ unit) {
		Request@ req = GetRequestToAssign(unit);
		if (req is null)
			return null;

		Squad@ squad = squads[req.squadId];
		if (squad.task is null) {
			@squad.task = aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::ATTACK, req.power));  // FIXME: power or unit number?
			CDefendTask@ defendTask = cast<CDefendTask>(squad.task);
			defendTask.isScripted = true;
			defendTask.range = req.attackRange;
			defendTask.SetPosition(req.pos);
			@taskToSquad[defendTask.id] = squad;
		}

		if (req.unitNum == squad.task.GetUnitCount() + 1) {
			ai.CallRules(SIG_SQUAD_FINISHED + req.squadId);
		}

		return squad.task;
	}

	Squad@ GetSquad(Id squadId) {
		bool success;
		Squad@ squad = squads.find(squadId, success);
		return success ? squad : null;
	}

	private void RemoveRequest(Request@ req) {
		int idx = requests.findByRef(req);
		if (idx < 0)
			return;

		req.Clear();
		requests.removeAt(idx);

		ai.CallRules(SIG_SQUAD_DESTROYED + req.squadId);
	}

	void DestroyRequest(int squadId) {
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

	void RepeatRequest(Request@ req) {
		for (auto it = req.unitDefs.begin(); it++;) {
			Amount@ am = it.current_value();
			am.assignedCount = 0;
		}
		RemoveRequest(req);
		requests.insertLast(req);
	}

	bool DestroySquad(IUnitTask@ task) {
		bool success;
		Squad@ squad = taskToSquad.find(task.id, success);
		if (!success)
			return false;

		if (squad.task !is null) {
			taskToSquad.erase(squad.task.id);
			squad.task.Abort();
		}
		if (squad.req.isRepeat) {
			RepeatRequest(squad.req);
			@squad.task = null;
		} else {
			RemoveRequest(squad.req);
			squads.erase(squad.id);
		}
		return true;
	}

	bool SetSquadPosition(const SIntent& in intent) {
		bool success;
		Squad@ squad = squads.find(intent.objId, success);
		if (!success || squad.task is null)
			return false;
		squad.SetPosition(AIFloat3(intent[0], 0, intent[1]));
		return true;
	}

	private map<Id, Squad@> squads;  // owner
	private array<Request@> requests;  // owner
	private map<Id, Request@> buildTaskToReq;  // IUnitTask.id => Request
	private map<Id, Squad@> taskToSquad;  // IUnitTask.id => Squad
}

Manager mgr;

}  // namespace Squad
