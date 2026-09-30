/*
 * DefendTask.cpp
 *
 *  Created on: Feb 12, 2016
 *      Author: rlcevg
 */

#include "task/fighter/DefendTask.h"
#include "map/InfluenceMap.h"
#include "map/ThreatMap.h"
#include "module/MilitaryManager.h"
#include "setup/SetupManager.h"
#include "terrain/TerrainManager.h"
#include "terrain/path/PathFinder.h"
#include "terrain/path/QueryPathSingle.h"
#include "terrain/path/QueryPathMulti.h"
#include "unit/action/FightAction.h"
#include "unit/action/MoveAction.h"
#include "unit/action/SupportAction.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "spring/SpringMap.h"

#include "OOAICallback.h"
#include "AISCommands.h"

namespace circuit {

using namespace springai;
using namespace terrain;

CDefendTask::CDefendTask(ITaskModule* mgr, const AIFloat3& position,
						 FightType check, FightType promote, float maxPower, float powerMod)
		: ISquadTask(mgr, FightType::DEFEND, powerMod)
		, check(check)
		, promote(promote)
		, maxPower(maxPower * powerMod)
		, foundPos(position)
{
	this->position = position;
	isRegroupAllowed = false;
}

CDefendTask::~CDefendTask()
{
}

bool CDefendTask::CanAssignTo(CCircuitUnit* unit) const
{
	return (attackPower < maxPower) && (static_cast<CDefendTask*>(unit->GetTask())->GetPromote() == promote);
}

void CDefendTask::AssignTo(CCircuitUnit* unit)
{
	ISquadTask::AssignTo(unit);
	CCircuitDef* cdef = unit->GetCircuitDef();
	highestRange = std::max(highestRange, cdef->GetLosRadius());

	if (cdef->IsRoleSupport() && (leader != unit)) {
		unit->PushBack(new CSupportAction(unit));
	}

	int squareSize = manager->GetCircuit()->GetPathfinder()->GetSquareSize();
	ITravelAction* travelAction;
	if (cdef->IsAttrSiege()) {
		travelAction = new CFightAction(unit, squareSize);
	} else {
		travelAction = new CMoveAction(unit, squareSize);
	}
	unit->PushTravelAct(travelAction);
	travelAction->StateWait();
	unit->SetAllowedToJump(cdef->IsAbleToJump() && cdef->IsAttrJump());
}

void CDefendTask::RemoveAssignee(CCircuitUnit* unit)
{
	ISquadTask::RemoveAssignee(unit);
	if (leader == nullptr) {
		manager->AbortTask(this);
	}
}

void CDefendTask::Start(CCircuitUnit* unit)
{
	CCircuitAI* circuit = manager->GetCircuit();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	AIFloat3 pos = geom::get_radial_pos(position, SQUARE_SIZE * 32);
	CTerrainManager::CorrectPosition(pos);
	AIFloat3 freePos = terrainMgr->FindBuildSite(unit->GetCircuitDef(), pos, 300.0f, UNIT_NO_FACING, true);
//	AIFloat3 freePos = terrainMgr->FindSpringBuildSite(unit->GetCircuitDef(), pos, 300.0f, UNIT_NO_FACING);
	pos = geom::is_valid(freePos) ? freePos : pos;

	TRY_UNIT(circuit, unit,
		unit->CmdFightTo(pos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, circuit->GetLastFrame() + FRAMES_PER_SEC * 60);
		unit->CmdWantedSpeed(NO_SPEED_LIMIT);
	)
}

void CDefendTask::Update()
{
	if (leader == nullptr) {  // possible due to AS creation
		return;
	}

	++updCount;

	/*
	 * Promote task if possible
	 */
	if (!isScripted && (updCount % 32 == 1)) {
		CMilitaryManager* militaryMgr = static_cast<CMilitaryManager*>(manager);
		if ((attackPower >= maxPower) || !militaryMgr->GetTasks(check).empty())
		{
			IFighterTask* task = militaryMgr->Enqueue(TaskF::Common(promote));
			manager->ReplaceTask(this, task);
//			manager->DoneTask(this);  // NOTE: CDefendTask::RemoveAssignee() will abort task
			return;
		}
	}

	/*
	 * Merge tasks if possible
	 */
	ISquadTask* task = GetMergeTask();
	if (task != nullptr) {
		task->Merge(this);
		units.clear();
		manager->AbortTask(this);
		return;
	}

	/*
	 * Regroup if required
	 */
	bool wasRegroup = (State::REGROUP == state);
	bool mustRegroup = IsMustRegroup();
	if (State::REGROUP == state) {
		if (mustRegroup) {
			CCircuitAI* circuit = manager->GetCircuit();
			int frame = circuit->GetLastFrame() + FRAMES_PER_SEC * 60;
			for (CCircuitUnit* unit : units) {
				unit->GetTravelAct()->StateWait();
				unit->Gather(groupPos, frame);
			}
		}
		return;
	}

	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	bool isExecute = (updCount % 16 == 2);
	if (!isExecute) {
		for (CCircuitUnit* unit : units) {
			isExecute |= unit->IsForceUpdate(frame);
		}
		if (!isExecute) {
			if (wasRegroup && !pPath->posPath.empty()) {
				ActivePath(lowestSpeed);
			}
			return;
		}
	} else {
		ISquadTask::Update();
		if (leader == nullptr) {  // task aborted
			return;
		}
	}

	/*
	 * Update target
	 */
	const bool isTargetsFound = isScripted ? FindTargetVIP() : FindTarget();

	const AIFloat3& startPos = leader->GetPos(frame);
	state = State::ROAM;
	if ((GetTarget() != nullptr) || isTargetsFound) {
		const float slack = (circuit->GetInflMap()->GetAllyDefendInflAt(foundPos) > INFL_EPS) ? 500.f : 300.f;
		if (geom::is_in_range(foundPos, startPos, highestRange + slack)) {
			state = State::ENGAGE;
			Attack(frame);
			return;
		}
	}

	if (!IsQueryReady(leader)) {
		return;
	}

	if (!isTargetsFound) {  // enemyPositions.empty()
		isScripted ? FallbackBasePos() : FallbackFrontPos();
		return;
	}

	CThreatMap* threatMap = circuit->GetThreatMap();
	const float eps = threatMap->GetSquareSize() * 2.f;
	const float pathRange = (goalRange >= 0.f)
			? std::max<float>(goalRange, threatMap->GetSquareSize())
			: std::max(highestRange - eps, eps);

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathMultiQuery(
			leader, threatMap,
			startPos, pathRange, enemyPositions,
			nullptr, false, ignoreThreat, avoidThreat, isEndPosOnly);
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyTargetPath(static_cast<const CQueryPathMulti*>(query));
	});
}

void CDefendTask::SetTargetPos(const AIFloat3& pos)
{
	targetPos = pos;
	position = pos;
}

void CDefendTask::Merge(ISquadTask* task)
{
	CCircuitAI* circuit = manager->GetCircuit();
	int frame = circuit->GetLastFrame();
	const AIFloat3& leadPos = leader->GetPos(frame);
	frame += FRAMES_PER_SEC * 60;

	const std::set<CCircuitUnit*>& rookies = task->GetAssignees();
	for (CCircuitUnit* unit : rookies) {
		unit->SetTask(this);

		TRY_UNIT(circuit, unit,
			unit->CmdFightTo(leadPos, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame);
		)
	}
	units.insert(rookies.begin(), rookies.end());
	maxPower = std::max(maxPower, static_cast<CDefendTask*>(task)->GetMaxPower());
	attackPower += task->GetAttackPower();
	const std::set<CCircuitUnit*>& sh = task->GetShields();
	shields.insert(sh.begin(), sh.end());

	const std::map<float, std::set<CCircuitUnit*>>& rangers = task->GetRangeUnits();
	for (const auto& kv : rangers) {
		rangeUnits[kv.first].insert(kv.second.begin(), kv.second.end());
	}
}

bool CDefendTask::CanAttackTarget(CCircuitDef* cdef, CEnemyInfo* enemy, CMap* map, float weaponRange, int canTargetCat) const
{
	CCircuitDef* edef = enemy->GetCircuitDef();

	if (edef != nullptr) {
		if ((edef->GetCategory() & canTargetCat) == 0) {
			return false;
		}

		const AIFloat3& ePos = enemy->GetPos();
		const float elevation = map->GetElevationAt(ePos.x, ePos.z);
		const bool isInWater = cdef->IsPredictInWater(elevation);

		const bool hasAntiAir = isInWater ? cdef->HasSubToAir() : cdef->HasSurfToAir();
		if (edef->IsAbleToFly() && !hasAntiAir) {
			return false;
		}

		if (edef->IsInWater(elevation, ePos.y)) {
			const bool hasAntiWater = isInWater ? cdef->HasSubToWater() : cdef->HasSurfToWater();
			if (!hasAntiWater) {
				return false;
			}
		} else {
			const bool hasAntiLand = isInWater ? cdef->HasSubToLand() : cdef->HasSurfToLand();
			if (!hasAntiLand) {
				return false;
			}
		}

		if (ePos.y - elevation > weaponRange) {
			return false;
		}
	} else {
		const AIFloat3& ePos = enemy->GetPos();
		if (ePos.y < -SQUARE_SIZE * 5) {
			const float elevation = map->GetElevationAt(ePos.x, ePos.z);
			const bool isInWater = cdef->IsPredictInWater(elevation);
			const bool hasAntiWater = isInWater ? cdef->HasSubToWater() : cdef->HasSurfToWater();
			if (!hasAntiWater) {
				return false;
			}
		}
	}

	return true;
}

bool CDefendTask::FindTarget()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CMap* map = circuit->GetMap();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	CThreatMap* threatMap = circuit->GetThreatMap();
	CInfluenceMap* inflMap = circuit->GetInflMap();
	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	SArea* area = leader->GetArea();
	CCircuitDef* cdef = leader->GetCircuitDef();
	const float maxPower = attackPower * powerMod;
	const float weaponRange = cdef->GetMaxRange() * 0.9f;
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();

	const AIFloat3& basePos = circuit->GetSetupManager()->GetBasePos();
	const float baseRange = circuit->GetMilitaryManager()->GetBaseDefRange();
	const float sqBaseRange = SQUARE(baseRange);
	const float invSqBaseRange = 1.0f / sqBaseRange;

	CEnemyInfo* bestTarget = nullptr;
	float minSqDist = std::numeric_limits<float>::max();

	SetTarget(nullptr);  // make adequate enemy->GetTasks().size()
	enemyPositions.clear();
	threatMap->SetThreatType(leader);
	const CCircuitAI::EnemyInfos& enemies = circuit->GetEnemyInfos();
	for (const auto& kv : enemies) {
		CEnemyInfo* enemy = kv.second;
		if (enemy->IsHidden() || (enemy->GetTasks().size() > 2)) {
			continue;
		}

		const AIFloat3& ePos = enemy->GetPos();
		if ((inflMap->GetAllyDefendInflAt(ePos) < INFL_EPS)
			|| !terrainMgr->CanMoveToPos(area, ePos))
		{
			continue;
		}

		const float sqEBDist = basePos.SqDistance2D(ePos);
		float checkPower = maxPower;
		if (sqEBDist < sqBaseRange) {
			// Approximates the curve using sqEBDist/sqBaseRange. Non-linear.
			// At center (0): 4.0 - 0.0 = 4.0 (400%)
			// At edge (sqBaseRange): 4.0 - 3.0 = 1.0 (100%)
			checkPower *= 4.0f - 3.0f * (sqEBDist * invSqBaseRange);
		}
		if (checkPower <= threatMap->GetThreatAt(ePos)) {
			continue;
		}

		CCircuitDef* edef = enemy->GetCircuitDef();
		if (edef != nullptr) {
			if (((edef->GetCategory() & noChaseCat) != 0)
				|| circuit->GetCircuitDef(edef->GetId())->IsIgnore())
			{
				continue;
			}
		}

		if (!CanAttackTarget(cdef, enemy, map, weaponRange, canTargetCat)) {
			continue;
		}

		enemyPositions.push_back(ePos);

		float sqDist = pos.SqDistance2D(ePos);
		if (minSqDist > sqDist) {
			minSqDist = sqDist;
			bestTarget = enemy;
		}
	}

	if (bestTarget != nullptr) {
		SetTarget(bestTarget);
		foundPos = GetTarget()->GetPos();
	}

	return !enemyPositions.empty();
	// Return: target, startPos=leader->pos, enemyPositions
}

bool CDefendTask::FindTargetScripted()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CMap* map = circuit->GetMap();
	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	SArea* area = leader->GetArea();
	CCircuitDef* cdef = leader->GetCircuitDef();

	const AIFloat3& pos = leader->GetPos(circuit->GetLastFrame());
	const float sqRange = SQUARE(range);
	const float weaponRange = cdef->GetMaxRange() * 0.9f;
	const int canTargetCat = cdef->GetTargetCategory();
	const int noChaseCat = cdef->GetNoChaseCategory();

	const AIFloat3& basePos = circuit->GetSetupManager()->GetBasePos();
	const float sqBaseRange = SQUARE(circuit->GetMilitaryManager()->GetBaseDefRange());

	CEnemyInfo* bestTarget = nullptr;
	float minSqDist = std::numeric_limits<float>::max();

	SetTarget(nullptr);  // make adequate enemy->GetTasks().size()
	enemyPositions.clear();
	circuit->GetThreatMap()->SetThreatType(leader);

	for (const auto& [id, enemy] : circuit->GetEnemyInfos()) {
		if (enemy->IsHidden() || enemy->GetTasks().size() > 2) {
			continue;
		}

		const AIFloat3& ePos = enemy->GetPos();
		if ((!geom::is_in_sqrange(ePos, basePos, sqBaseRange) && !geom::is_in_sqrange(ePos, pos, sqRange))
			|| !terrainMgr->CanMoveToPos(area, ePos))
		{
			continue;
		}

		CCircuitDef* edef = enemy->GetCircuitDef();
		if (edef != nullptr) {
			if (((edef->GetCategory() & noChaseCat) != 0)
				|| circuit->GetCircuitDef(edef->GetId())->IsIgnore())
			{
				continue;
			}
		}

		if (!CanAttackTarget(cdef, enemy, map, weaponRange, canTargetCat)) {
			continue;
		}

		enemyPositions.push_back(ePos);

		const float sqDist = pos.SqDistance2D(ePos);
		if (sqDist < minSqDist) {
			minSqDist = sqDist;
			bestTarget = enemy;
		}
	}

	if (bestTarget != nullptr) {
		SetTarget(bestTarget);
		foundPos = bestTarget->GetPos();
	}

	return !enemyPositions.empty();
	// Return: target, startPos=leader->pos, enemyPositions
}

bool CDefendTask::FindTargetVIP()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CEnemyInfo* enemy = (vipTargetId >= 0) ? circuit->GetEnemyInfo(vipTargetId) : nullptr;

	if ((enemy == nullptr) || enemy->IsHidden()) {
		return FindTargetScripted();
	}

	CTerrainManager* terrainMgr = circuit->GetTerrainManager();
	SArea* area = leader->GetArea();
	const AIFloat3& ePos = enemy->GetPos();

	if (!terrainMgr->CanMoveToPos(area, ePos)) {
		return FindTargetScripted();
	}

	CMap* map = circuit->GetMap();
	CCircuitDef* cdef = leader->GetCircuitDef();
	const float weaponRange = cdef->GetMaxRange() * 0.9f;
	const int canTargetCat = cdef->GetTargetCategory();

	if (!CanAttackTarget(cdef, enemy, map, weaponRange, canTargetCat)) {
		return FindTargetScripted();
	}

	enemyPositions.clear();
	enemyPositions.push_back(ePos);

	SetTarget(enemy);
	foundPos = ePos;

	circuit->GetThreatMap()->SetThreatType(leader);
	return true;
	// Return: target, startPos=leader->pos, enemyPositions
}

void CDefendTask::ApplyTargetPath(const CQueryPathMulti* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->posPath.empty()) {
		ActivePath(lowestSpeed);
	} else {
		Fallback();
	}
}

void CDefendTask::FallbackFrontPos()
{
	CCircuitAI* circuit = manager->GetCircuit();
	circuit->GetMilitaryManager()->FillFrontPos(leader, urgentPositions);
	if (urgentPositions.empty()) {
		FallbackBasePos();
		return;
	}

	const AIFloat3& startPos = leader->GetPos(circuit->GetLastFrame());
	const float pathRange = DEFAULT_SLACK * 4;

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathMultiQuery(
			leader, circuit->GetThreatMap(),
			startPos, pathRange, urgentPositions);
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyFrontPos(static_cast<const CQueryPathMulti*>(query));
	});
}

void CDefendTask::ApplyFrontPos(const CQueryPathMulti* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->path.empty()) {
		if (pPath->path.size() > 2) {
			ActivePath();
		}
	} else {
		FallbackBasePos();
	}
}

void CDefendTask::FallbackBasePos()
{
	CCircuitAI* circuit = manager->GetCircuit();
	CSetupManager* setupMgr = circuit->GetSetupManager();
	CThreatMap* threatMap = circuit->GetThreatMap();

	const AIFloat3& startPos = leader->GetPos(circuit->GetLastFrame());
	const AIFloat3& endPos = isScripted ? position : setupMgr->GetBasePos();
	const float pathRange = (goalRange >= 0.f)
			? std::max<float>(goalRange, threatMap->GetSquareSize())
			: DEFAULT_SLACK * 4;

	CPathFinder* pathfinder = circuit->GetPathfinder();
	std::shared_ptr<IPathQuery> query = pathfinder->CreatePathSingleQuery(
			leader, threatMap,
			startPos, endPos, pathRange,
			nullptr, ignoreThreat, avoidThreat, isEndPosOnly);
	pathQueries[leader] = query;

	pathfinder->RunQuery(circuit->GetScheduler().get(), query, [this](const IPathQuery* query) {
		this->ApplyBasePos(static_cast<const CQueryPathSingle*>(query));
	});
}

void CDefendTask::ApplyBasePos(const CQueryPathSingle* query)
{
	pPath = query->GetPathInfo();

	if (!pPath->path.empty()) {
		if (pPath->path.size() > 2) {
			ActivePath();
		}
	} else {
		Fallback();
	}
}

void CDefendTask::Fallback()
{
	// should never happen
	CCircuitAI* circuit = manager->GetCircuit();
	const int frame = circuit->GetLastFrame();
	for (CCircuitUnit* unit : units) {
		unit->GetTravelAct()->StateWait();
		TRY_UNIT(circuit, unit,
			unit->CmdFightTo(position, UNIT_COMMAND_OPTION_RIGHT_MOUSE_KEY, frame + FRAMES_PER_SEC * 60);
			unit->CmdWantedSpeed(lowestSpeed);
		)
	}
}

} // namespace circuit
