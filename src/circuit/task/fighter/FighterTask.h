/*
 * FighterTask.h
 *
 *  Created on: Aug 31, 2015
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TASK_FIGHTER_FIGHTERTASK_H_
#define SRC_CIRCUIT_TASK_FIGHTER_FIGHTERTASK_H_

#include "task/UnitTask.h"
#include "unit/CoreUnit.h"
#include "util/Defines.h"

namespace circuit {

#define RANGE_MOD	0.8f

class CEnemyInfo;

class IFighterTask: public IUnitTask {
public:
	friend class CInitScript;

	enum class FightType: char {RALLY = 0, GUARD, DEFEND, SCOUT, RAID, ATTACK, BOMB, MELEE, ARTY, AA, AH, SUPPORT, SUPER, _SIZE_};
	using FT = std::underlying_type<FightType>::type;

protected:
	IFighterTask(ITaskModule* mgr, FightType type, float powerMod, int timeout = 0);
public:
	virtual ~IFighterTask();

	virtual void AssignTo(CCircuitUnit* unit) override;
	virtual void RemoveAssignee(CCircuitUnit* unit) override;

	virtual void Update() override;

	virtual void OnUnitIdle(CCircuitUnit* unit) override;
	virtual void OnUnitDamaged(CCircuitUnit* unit, CEnemyInfo* attacker) override;
	virtual void OnUnitDestroyed(CCircuitUnit* unit, CEnemyInfo* attacker) override;

	FightType GetFightType() const { return fightType; }
	const springai::AIFloat3& GetPosition() const { return position; }

	// Script API
	const springai::AIFloat3& GetTargetPos() const { return targetPos; }
	virtual void SetTargetPos(const springai::AIFloat3& pos) { targetPos = pos; }

	float GetAttackPower() const { return attackPower; }
	CEnemyInfo* GetTarget() const { return target; }
	void ClearTarget() { target = nullptr; }  // Only for ~CEnemyUnit

	const std::set<CCircuitUnit*>& GetShields() const { return shields; }

protected:
	void SetTarget(CEnemyInfo* enemy);
	void Attack(CCircuitUnit* unit, const int frame);

	FightType fightType;
	springai::AIFloat3 position;  // attack/scout position

	float attackPower;
	float powerMod;

	std::set<CCircuitUnit*> cowards;
	std::set<CCircuitUnit*> shields;

	static F3Vec urgentPositions;  // NOTE: micro-opt
	static F3Vec enemyPositions;  // NOTE: micro-opt

	int attackFrame;

	// Script API
	float range = 0.f;  // direct attack range
	float retreat = -1.f;  // -1: default; 0: disabled; >0.f: unit's HP percent
	bool isScripted = false;
	bool isMergeAllowed = true;
	bool isRegroupAllowed = true;
	springai::AIFloat3 targetPos;
	ICoreUnit::Id vipTargetId = -1;
	float goalRange = -1.f; // Pathing: acceptable end distance to goal position
	float ignoreThreat = 0.f;  // Pathing: ignore threat up to this level ~ minThreat
	float avoidThreat = std::numeric_limits<float>::max();  // Pathing: avoid threat starting from this level ~ maxThreat
	bool isEndPosOnly = false;  // Pathing: use only end position

private:  // NOTE: Never assign directly, use SetTarget() to avoid access to a dead target
	CEnemyInfo* target;

#ifdef DEBUG_VIS
public:
	virtual void Log() override;
#endif
};

} // namespace circuit

#endif // SRC_CIRCUIT_TASK_FIGHTER_FIGHTERTASK_H_
