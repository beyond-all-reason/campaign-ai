#include "../../unit.as"
#include "../misc/base.as"
#include "../misc/region.as"


namespace Builder {

CCircuitUnit@ energizer1 = null;
CCircuitUnit@ energizer2 = null;
bool isConstructionScripted = false;

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	IUnitTask@ task = Base::mgr.GetTaskToBuild(unit);
	if (task !is null || isConstructionScripted)
		return task;
	return aiBuilderMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	if (task.GetType() != Task::Type::BUILDER)
		return;
	IBuilderTask@ taskB = cast<IBuilderTask>(task);
	done ? Base::mgr.BaseTaskFinished(taskB) : Base::mgr.BaseTaskCanceled(taskB);
	Region::mgr.BuildNextSlot(task.id);
}

void AiTaskAssigned(CCircuitUnit@ unit)
{
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	const CCircuitDef@ cdef = unit.circuitDef;
	if (usage != Unit::UseAs::BUILDER || cdef.IsRoleAny(Unit::Role::COMM.mask))
		return;

	// constructor with BASE attribute is assigned to tasks near base
	if (cdef.costM < 200.f) {
		if (energizer1 is null
			&& (uint(cdef.count) > aiMilitaryMgr.GetGuardTaskNum() || cdef.IsAbleToFly()))
		{
			@energizer1 = unit;
			unit.AddAttribute(Unit::Attr::BASE.type);
		}
	} else {
		if (energizer2 is null) {
			@energizer2 = unit;
			unit.AddAttribute(Unit::Attr::BASE.type);
		}
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (energizer1 is unit)
		@energizer1 = null;
	else if (energizer2 is unit)
		@energizer2 = null;
}

void AiLoad(IStream& istream)
{
	Id e1id = -1, e2id = -1;
	istream >> e1id >> e2id;
	@energizer1 = ai.GetTeamUnit(e1id);
	@energizer2 = ai.GetTeamUnit(e2id);
	if (energizer1 !is null)
		energizer1.AddAttribute(Unit::Attr::BASE.type);
	if (energizer2 !is null)
		energizer2.AddAttribute(Unit::Attr::BASE.type);
}

void AiSave(OStream& ostream)
{
	ostream << Id(energizer1 !is null ? energizer1.id : -1)
			<< Id(energizer2 !is null ? energizer2.id : -1);
}

/*
 * Utilities
 */
SBuildTask MakeBuildRecord(Id unitDefId, AIFloat3 pos = -RgtVector)
{
	Task::BuildType buildType = Task::BuildType(aiEconomyMgr.GetBuildType(unitDefId));
	Task::Priority priority = Task::Priority::HIGH;
	CCircuitDef@ cdef = ai.GetCircuitDef(unitDefId);
	switch (buildType) {
	case Task::BuildType::FACTORY:
		return TaskB::Factory(priority, cdef, pos, null, 0.f, false, true, -1);
	case Task::BuildType::MEX:
	case Task::BuildType::GEO:
		return TaskB::Spot(buildType, priority, cdef, pos, -1, true, -1);
	default:
		return TaskB::Common(buildType, priority, cdef, pos, 0.f, true, -1);
	}
}

}  // namespace Builder
