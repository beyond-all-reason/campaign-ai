/*
 * GuardTask.cpp
 *
 *  Created on: Jan 28, 2015
 *      Author: rlcevg
 */

#include "task/fighter/GuardTask.h"
#include "module/MilitaryManager.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringCallback.h"

namespace circuit {

using namespace springai;

CFGuardTask::CFGuardTask(ITaskModule* mgr, ICoreUnit::Id vipId, float maxPower)
		: IFighterTask(mgr, FightType::GUARD, 1.f)
		, vipId(vipId)
		, maxPower(maxPower)
{
	// NOTE: Guard marker was initially designed for own units only, remains as such
	CCircuitUnit* vip = manager->GetCircuit()->GetTeamUnit(vipId);
	if (vip != nullptr) {
		static_cast<CMilitaryManager*>(mgr)->MarkGuardUnit(vipId, this);
	}
}

CFGuardTask::~CFGuardTask()
{
}

bool CFGuardTask::CanAssignTo(CCircuitUnit* unit) const
{
	CCircuitAI* circuit = manager->GetCircuit();
	unsigned int guardsNum = circuit->GetMilitaryManager()->GetGuardsNum();
	if (unit->GetCircuitDef()->IsRoleRiot()) {
		guardsNum /= 2;
	}
	if (units.size() >= guardsNum) {
		return false;
	}
	CCircuitUnit* vip = circuit->GetTeamUnit(vipId);
	if (vip == nullptr) {
		return false;
	}
	if (((unit->GetCircuitDef()->IsAmphibious() || unit->GetCircuitDef()->IsSurfer())
			&& (vip->GetCircuitDef()->IsAbleToDive() || vip->GetCircuitDef()->IsSurfer()))
		|| (vip->GetCircuitDef()->IsSubmarine() && unit->GetCircuitDef()->IsSubmarine())
		|| (vip->GetCircuitDef()->IsAbleToFly() && unit->GetCircuitDef()->IsAbleToFly())
		|| (vip->GetCircuitDef()->IsLander() && unit->GetCircuitDef()->IsLander())
		|| (vip->GetCircuitDef()->IsFloater() && unit->GetCircuitDef()->IsFloater()))
	{
		return true;
	}
	return false;
}

void CFGuardTask::RemoveAssignee(CCircuitUnit* unit)
{
	IFighterTask::RemoveAssignee(unit);
	if (isScripted && units.empty()) {
		manager->AbortTask(this);
	}
}

void CFGuardTask::Start(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CAllyUnit* vip = circuit->GetFriendlyUnit(vipId);
	if (vip != nullptr) {
		TRY_UNIT(circuit, unit,
			unit->GetUnit()->Guard(vip->GetUnit());
			unit->CmdWantedSpeed(NO_SPEED_LIMIT);
		)
	} else {
		manager->DoneTask(this);
	}
}

void CFGuardTask::Update()
{
//	if (updCount++ % 2 != 0) {
//		return;
//	}

	CCircuitAI* circuit = manager->GetCircuit();
	CAllyUnit* vip = circuit->GetFriendlyUnit(vipId);
	if (vip == nullptr) {
		manager->DoneTask(this);
		return;
	}

	CEnemyInfo* target = nullptr;
	const int frame = circuit->GetLastFrame();
	const AIFloat3& pos = vip->GetPos(frame);
	const float guardRange = (attackRange < 0.f)
			? vip->GetCircuitDef()->GetLosRadius() + 500.f
			: attackRange;
	const std::vector<ICoreUnit::Id>& enemyIds = circuit->GetCallback()->GetEnemyUnitIdsIn(pos, guardRange);
	for (ICoreUnit::Id enemyId : enemyIds) {
		CEnemyInfo* ei = circuit->GetEnemyInfo(enemyId);
		if (ei != nullptr) {
			target = ei;
			break;
		}
	}

	if (target != nullptr) {
		if (frame < attackFrame + FRAMES_PER_SEC * 3) {
			return;
		}
		attackFrame = frame;
		state = State::ENGAGE;
		const bool isGroundAttack = target->GetUnit()->IsCloaked();
		for (CCircuitUnit* unit : units) {
			unit->Attack(target, isGroundAttack, frame + FRAMES_PER_SEC * 60);
		}
	} else if (State::ENGAGE == state) {
		state = State::ROAM;
		for (CCircuitUnit* unit : units) {
			TRY_UNIT(circuit, unit,
				unit->GetUnit()->Guard(vip->GetUnit());
			)
		}
	}
}

void CFGuardTask::OnUnitIdle(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CAllyUnit* vip = circuit->GetFriendlyUnit(vipId);
	if (vip != nullptr) {
		TRY_UNIT(circuit, unit,
			unit->GetUnit()->Guard(vip->GetUnit());
		)
	} else {
		manager->DoneTask(this);
	}
}

void CFGuardTask::Cancel()
{
	IFighterTask::Cancel();

	CCircuitUnit* vip = manager->GetCircuit()->GetTeamUnit(vipId);
	if (vip != nullptr) {
		static_cast<CMilitaryManager*>(manager)->UnmarkGuardUnit(vipId);
	}
}

} // namespace circuit
