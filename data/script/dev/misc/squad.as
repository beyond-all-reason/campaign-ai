namespace Squad {

// Has to be same as Lua's defines
enum ESquadParams {
	SQUAD_CREATE_RANGE = 1,
	SQUAD_POS_X        = 2,
	SQUAD_POS_Z        = 3,
	SQUAD_ATTACK_RANGE = 4,
	SQUAD_POWER        = 5,
	SQUAD_REPEAT       = 6,
}

enum ESquadState { CREATE, IDLE, TASK }

class Squad {
	Squad(Request@ p_req) {
		id = p_req.squadId;
		@req = p_req;
	}

	Id id;
	Request@ req;
	ESquadState state = ESquadState::CREATE;
	IUnitTask@ task = null;

	void SetPosition(const AIFloat3& in pos) {
		// FIXME: Check which task is it
		CDefendTask@ defendTask = cast<CDefendTask>(task);
		defendTask.SetPosition(pos);
	}
}

/*
 * May act as wave: on related squad destroyed - repeat
 */
class Request {
	Request(Id p_id) {
		squadId = p_id;
		pos = AiTerrainCenter();
	}

	Id squadId;
	map<Id, Amount@> unitDefs;  // UnitDefId: amount
	AIFloat3 pos;
	float factoryRange = 64.f;
	float attackRange = 300.f;
	float power = 0.f;  // FIXME: power or unit number?
	int unitNum = 0;
	bool isRepeat = false;

	// HAX: instead of having separate "Result<Request, Id>" struct
	//      as function result - pass values as part of Request
	Id unitDefId;
}

class Amount {
	Amount(int n) {
		amount = n;
	}

	int amount;
	int orderedCount = 0;
	int assignedCount = 0;
}

class Manager {
	private map<Id, Squad@> squads;
	private array<Request@> requests;

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
			case ESquadParams::SQUAD_POWER: {
				req.power = intent.GetValue(i);
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

		// FIXME: TEST
// 			Task::Priority priority = Task::Priority::NORMAL;
// 			Task::RecruitType recruit = Task::RecruitType::FIREPOWER;
// 			for (int j = 0; j < int(num); ++j) {
// 				IUnitTask@ task = aiFactoryMgr.Enqueue(TaskS::Recruit(recruit, priority, cdef, req.pos, req.factoryRange));
// 				cast<CRecruitTask>(task).isSingle = true;
// 			}
		// FIXME: TEST
		}
		return true;
	}

	private Request@ GetUnitDefToBuild(const CCircuitDef@ facDef, const AIFloat3& in pos) {
		for (uint i = 0; i < requests.length(); ++i) {
			Request@ req = requests[i];
			if (!pos.IsInRange(req.pos, req.factoryRange))
				continue;
			for (auto it = req.unitDefs.begin(); it++;) {
				Amount@ am = it.current_value();
				if (am.amount <= am.orderedCount)
					continue;
				Id unitDefId = it.current_key();
				if (!facDef.CanBuild(unitDefId))
					continue;

				am.orderedCount++;  // TODO: Correction on unit destruction
				req.unitDefId = unitDefId;
				return req;
			}
		}
		return null;
	}

	IUnitTask@ GetTaskToBuild(CCircuitUnit@ factory) {
		Request@ req = GetUnitDefToBuild(factory.circuitDef, factory.GetPos(ai.frame));
		if (req is null)
			return null;
		CCircuitDef@ buildDef = ai.GetCircuitDef(req.unitDefId);
		Task::Priority priority = Task::Priority::NORMAL;
		Task::RecruitType recruit = Task::RecruitType::FIREPOWER;
		return aiFactoryMgr.Enqueue(TaskS::Recruit(recruit, priority, buildDef, req.pos, req.factoryRange));
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
		}

		if (req.unitNum == squad.task.GetUnitCount() + 1) {
			ai.CallRules("ai_squad_finished:" + req.squadId);
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
		requests.removeAt(idx);
		ai.CallRules("ai_squad_destroyed:" + req.squadId);
	}

	void DestroyRequest(int squadId) {
		if (!squads.contains(squadId))
			return;
		Squad@ squad = squads[squadId];
		RemoveRequest(squad.req);
		squads.erase(squadId);
		if (squad.task !is null)
			squad.task.Abort();
	}

	void RepeatRequest(Request@ req) {
		for (auto it = req.unitDefs.begin(); it++;) {
			Amount@ am = it.current_value();
			am.orderedCount = 0;
			am.assignedCount = 0;
		}
		RemoveRequest(req);
		requests.insertLast(req);
	}

	bool DestroySquad(IUnitTask@ task) {
		Id squadId = -1;
		// TODO: {task: squad} dictionary instead of next for-loop
		for (auto it = squads.begin(); it++;) {
			Squad@ squad = it.current_value();
			if (squad.task is task) {
				squadId = squad.id;
				break;
			}
		}
		if (squadId < 0)
			return false;
		Squad@ squad = squads[squadId];
		if (squad.req.isRepeat) {
			RepeatRequest(squad.req);
			@squad.task = null;
		} else {
			RemoveRequest(squad.req);
			squads.erase(squadId);
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
}

Manager mgr;

}  // namespace Squad
