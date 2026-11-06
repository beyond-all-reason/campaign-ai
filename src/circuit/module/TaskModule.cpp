/*
 * TaskModule.cpp
 *
 *  Created on: Jan 20, 2015
 *      Author: rlcevg
 */

#include "module/TaskModule.h"
#include "scheduler/Scheduler.h"
#include "script/TaskModuleScript.h"
#include "task/NilTask.h"
#include "task/IdleTask.h"
#include "task/PlayerTask.h"
#include "task/RetreatTask.h"
#include "unit/CircuitUnit.h"
#include "CircuitAI.h"
#include "util/Profiler.h"
#include "util/Utils.h"

namespace circuit {

ITaskModule::ITaskModule(CCircuitAI* circuit, IScript* script)
		: IModule(circuit, script)
		, nilTask(nullptr)
		, idleTask(nullptr)
		, playerTask(nullptr)
		, updateIterator(0)
		, taskId(0)
		, metalPull(0.f)
{
	Init();
}

ITaskModule::~ITaskModule()
{
	delete nilTask;
	delete idleTask;
	delete playerTask;

	for (IUnitTask* task : updateTasks) {
		task->ClearRelease();
	}
}

void ITaskModule::Init()
{
	nilTask = new CNilTask(this);
	idleTask = new CIdleTask(this);
	playerTask = new CPlayerTask(this);
}

void ITaskModule::Release()
{
	// NOTE: Release expected to be called on CCircuit::Release.
	//       It doesn't stop scheduled GameTasks for that reason.
	for (IUnitTask* task : updateTasks) {
		AbortTask(task);
		// NOTE: Do not delete task as other AbortTask may ask for it
	}
	for (IUnitTask* task : updateTasks) {
		task->ClearRelease();
	}
	updateTasks.clear();
}

void ITaskModule::AssignTask(CCircuitUnit* unit, IUnitTask* task)
{
	unit->GetTask()->RemoveAssignee(unit);
	task->AssignTo(unit);
	task->Start(unit);
}

void ITaskModule::AssignTask(CCircuitUnit* unit)
{
	IUnitTask* task = MakeTask(unit);
	if (task != nullptr) {
		task->AssignTo(unit);
	}
}

void ITaskModule::ReplaceTask(IUnitTask* src, IUnitTask* dst)
{
	std::set<CCircuitUnit*> tmpUnits = src->GetAssignees();
	for (CCircuitUnit* unit : tmpUnits) {
		AssignTask(unit, dst);
	}
}

void ITaskModule::DequeueTask(IUnitTask* task, bool done)
{
	task->Dead();
	TaskRemoved(task, done);
	task->Stop(done);
}

IUnitTask* ITaskModule::MakeTask(CCircuitUnit* unit)
{
	return static_cast<ITaskModuleScript*>(script)->MakeTask(unit);  // DefaultMakeTask
}

void ITaskModule::TaskAdded(IUnitTask* task)
{
	static_cast<ITaskModuleScript*>(script)->TaskAdded(task);
}

void ITaskModule::TaskRemoved(IUnitTask* task, bool done)
{
	static_cast<ITaskModuleScript*>(script)->TaskRemoved(task, done);
}

IUnitTask* ITaskModule::GetTaskById(int taskId) const
{
	for (IUnitTask* task : updateTasks) {
		if (task->GetId() == taskId) {
			return task;
		}
	}
	return nullptr;
}

void ITaskModule::AssignPlayerTask(CCircuitUnit* unit)
{
	AssignTask(unit, playerTask);
}

void ITaskModule::Resurrected(CCircuitUnit* unit)
{
	CRetreatTask* task = EnqueueRetreat();
	if (task != nullptr) {
		AssignTask(unit, task);
	}
}

void ITaskModule::EnableJob(std::shared_ptr<IMainJob>& job, std::function<void ()> method,
		int interval, int offset)
{
	if (job == nullptr) {
		job = CScheduler::GameJob(method);
		circuit->GetScheduler()->RunJobEvery(job, interval, offset);
	}
}

void ITaskModule::DisableJob(std::shared_ptr<IMainJob>& job)
{
	if (job != nullptr) {
		circuit->GetScheduler()->RemoveJob(job);
		job = nullptr;
	}
}

void ITaskModule::EnableUpdateIdle(int interval, int offset)
{
	// TODO: adjust frameOffset according to current frame and interval
	const int shift = circuit->GetSkirmishAIId() % interval;
	EnableJob(updateIdleJob, [this]() { UpdateIdle(); }, interval, shift + offset);
}

void ITaskModule::DisableUpdateIdle()
{
	DisableJob(updateIdleJob);
}

void ITaskModule::EnableUpdate(int interval, int offset)
{
	const int shift = circuit->GetSkirmishAIId() % interval;
	EnableJob(updateJob, [this]() { Update(); }, interval, shift + offset);
}

void ITaskModule::DisableUpdate()
{
	DisableJob(updateJob);
}

void ITaskModule::EnableWatchdog(int interval, int offset)
{
	const int shift = circuit->GetSkirmishAIId() * WATCHDOG_COUNT;
	EnableJob(watchdogJob, [this]() { Watchdog(); }, interval, shift + offset);
}

void ITaskModule::DisableWatchdog()
{
	DisableJob(watchdogJob);
}

void ITaskModule::UpdateIdle()
{
	ZoneScoped;

	idleTask->Update();
}

void ITaskModule::Update()
{
	ZoneScoped;

	if (updateIterator >= updateTasks.size()) {
		updateIterator = 0;
	}

	const int lastFrame = GetCircuit()->GetLastFrame();
	// stagger the Update's
	unsigned int n = (updateTasks.size() / TEAM_SLOWUPDATE_RATE) + 1;

	while ((updateIterator < updateTasks.size()) && (n != 0)) {
		IUnitTask* task = updateTasks[updateIterator];
		if (task->IsDead()) {
			updateTasks[updateIterator] = updateTasks.back();
			updateTasks.pop_back();
			task->ClearRelease();  // delete task;
		} else {
			// NOTE: IFighterTask.timeout = 0
			int frame = task->GetLastTouched();
			int timeout = task->GetTimeout();
			if ((frame != -1) && (timeout > 0) && (lastFrame - frame >= timeout)) {
				AbortTask(task);
			} else {
				task->Update();
			}
			++updateIterator;
			n--;
		}
	}
}

void ITaskModule::Load(std::istream& is)
{
	IModule::Load(is);
	utils::binary_read(is, taskId);
}

void ITaskModule::Save(std::ostream& os) const
{
	IModule::Save(os);
	utils::binary_write(os, taskId);
}

} // namespace circuit
