/*
 * UnitTask.cpp
 *
 *  Created on: Sep 2, 2014
 *      Author: rlcevg
 */

#include "task/UnitTask.h"
#include "task/IdleTask.h"
#include "module/TaskModule.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathQuery.h"
#include "unit/CircuitUnit.h"
#include "unit/action/AntiCapAction.h"
#include "CircuitAI.h"
#include "util/Utils.h"

namespace circuit {

using namespace springai;

IUnitTask::IUnitTask(ITaskModule* mgr, Priority priority, Type type, int timeout)
		: manager(mgr)
		, id(mgr->GenerateTaskId())
		, type(type)
		, priority(priority)
		, state(State::ROAM)
		, timeout(timeout)
		, updCount(0)
		, isDead(false)
{
	lastTouched = manager->GetCircuit()->GetLastFrame();
}

IUnitTask::IUnitTask(ITaskModule* mgr, Type type)
		: manager(mgr)
		, id(0)
		, type(type)
		, priority(Priority::LOW)
		, state(State::ROAM)
		, lastTouched(-1)
		, timeout(-1)
		, updCount(0)
		, isDead(false)
{
}

IUnitTask::~IUnitTask()
{
}

void IUnitTask::ClearRelease()
{
	pathQueries.clear();
	Release();
}

bool IUnitTask::CanAssignTo(CCircuitUnit* unit) const
{
	return true;
}

void IUnitTask::AssignTo(CCircuitUnit* unit)
{
	lastTouched = -1;

	manager->GetIdleTask()->RemoveAssignee(unit);
	unit->SetTask(this);
	units.insert(unit);

	TRY_UNIT(manager->GetCircuit(), unit,
		unit->RemoveWait();
	)

	if (!unit->GetCircuitDef()->IsMobile() && manager->GetCircuit()->GetSetupManager()->IsAntiCap()) {
		unit->PushBack(new CAntiCapAction(unit));
	}
}

void IUnitTask::RemoveAssignee(CCircuitUnit* unit)
{
	pathQueries.erase(unit);
	units.erase(unit);
	unit->ClearAct();

	manager->GetIdleTask()->AssignTo(unit);

	if (units.empty()) {
		lastTouched = manager->GetCircuit()->GetLastFrame();
	}
}

bool IUnitTask::ReplaceBy(IUnitTask* task)
{
	// NOTE: CBuilderManager works with CCombatTask::type == FIGHTER
	if (manager != task->GetManager()) {
		return false;
	}
	manager->ReplaceTask(this, task);
	return true;
}

void IUnitTask::Stop(bool done)
{
	if (done) {
		Finish();
	} else {
		Cancel();
	}

	CIdleTask* idleTask = manager->GetIdleTask();
	for (CCircuitUnit* unit : units) {
		unit->ClearAct();
		idleTask->AssignTo(unit);
	}
	units.clear();
	pathQueries.clear();
}

void IUnitTask::Finish()
{
}

void IUnitTask::Cancel()
{
}

void IUnitTask::OnUnitMoveFailed(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	AIFloat3 pos = geom::get_radial_pos(unit->GetPos(frame), SQUARE_SIZE * 32);
	CTerrainManager::CorrectPosition(pos);
	TRY_UNIT(circuit, unit,
		unit->CmdMoveTo(pos, UNIT_CMD_OPTION, frame + FRAMES_PER_SEC);
	)
}

void IUnitTask::OnTravelEnd(CCircuitUnit* unit)
{
}

void IUnitTask::OnRearmStart(CCircuitUnit* unit)
{
}

void IUnitTask::Dead()
{
	isDead = true;
	pathQueries.clear();  // free queries
}

void IUnitTask::Abort()
{
	if (!isDead) {
		manager->AbortTask(this);
	}
}

void IUnitTask::Done()
{
	if (!isDead) {
		manager->DoneTask(this);
	}
}

bool IUnitTask::IsQueryReady(CCircuitUnit* unit) const
{
	const auto it = pathQueries.find(unit);
	std::shared_ptr<IPathQuery> query = (it == pathQueries.end()) ? nullptr : it->second;
	return (query == nullptr) || (IPathQuery::State::READY == query->GetState());
}

#define SERIALIZE(stream, func)	\
	utils::binary_##func(stream, id);			\
	utils::binary_##func(stream, priority);		\
	utils::binary_##func(stream, state);		\
	utils::binary_##func(stream, lastTouched);	\
	utils::binary_##func(stream, timeout);		\
	utils::binary_##func(stream, updCount);		\
	utils::binary_##func(stream, isDead);		\
	utils::binary_##func(stream, tag);

bool IUnitTask::Load(std::istream& is)
{
	SERIALIZE(is, read)
#ifdef DEBUG_SAVELOAD
	manager->GetCircuit()->LOG("%s | id=%i | priority=%i | state=%i | lastTouched=%i | timeout=%i | updCount=%i | isDead=%i | tag=%i",
			__PRETTY_FUNCTION__, id, priority, state, lastTouched, timeout, updCount, isDead, tag);
#endif
	return true;
}

void IUnitTask::Save(std::ostream& os) const
{
	SERIALIZE(os, write)
#ifdef DEBUG_SAVELOAD
	manager->GetCircuit()->LOG("%s | id=%i | priority=%i | state=%i | lastTouched=%i | timeout=%i | updCount=%i | isDead=%i | tag=%i",
			__PRETTY_FUNCTION__, id, priority, state, lastTouched, timeout, updCount, isDead, tag);
#endif
}

#ifdef DEBUG_VIS
void IUnitTask::Log()
{
	CCircuitAI* circuit = manager->GetCircuit();
	circuit->LOG("task: %p | id: %i | type: %i | state: %i | tag: %i", this, id, type, state, tag);
}
#endif

} // namespace circuit
