#include "../../define.as"
#include "../../unit.as"
#include "../misc/squad.as"


namespace Military {

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	IUnitTask@ task = Squad::mgr.AssignToRequest(unit);
	if (task !is null)
		return task;
	return aiMilitaryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	done ? Squad::mgr.SquadTaskFinished(task) : Squad::mgr.SquadTaskCanceled(task);
}

void AiTaskResigned(CCircuitUnit@ unit)
{
	Squad::mgr.SquadUnitDestroyed(unit);
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
}

void AiLoad(IStream& istream)
{
	// TODO: Squad::Save()
}

void AiSave(OStream& ostream)
{
	// TODO: Squad::Load()
}

void AiMakeDefence(int cluster, const AIFloat3& in pos)
{
	if ((ai.frame > 5 * MINUTE)
		|| (aiEconomyMgr.metal.income > 10.f)
		|| (aiEnemyMgr.mobileThreat > 0.f))
	{
		aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
	}
}

}  // namespace Military
