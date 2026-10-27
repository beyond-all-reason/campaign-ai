/*
 * TaskModule.h
 *
 *  Created on: Jan 20, 2015
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_MODULE_TASKMODULE_H_
#define SRC_CIRCUIT_MODULE_TASKMODULE_H_

#include "module/Module.h"

#include <vector>

namespace circuit {

class IUnitTask;
class CCircuitAI;
class CCircuitUnit;
class CNilTask;
class CIdleTask;
class CPlayerTask;
class CRetreatTask;

class ITaskModule: public IModule {  // CActionList; UnitManager and TaskManager
protected:
	ITaskModule(CCircuitAI* circuit, IScript* script);
public:
	virtual ~ITaskModule();

	void Init();
	void Release();

	int GenerateTaskId() { return ++taskId; }
	virtual void AssignTask(CCircuitUnit* unit, IUnitTask* task);
	virtual void AssignTask(CCircuitUnit* unit);
	virtual void ResignTask(CCircuitUnit* unit) {}
	void ReplaceTask(IUnitTask* src, IUnitTask* dst);  // unsafe replacement
protected:
	virtual void DequeueTask(IUnitTask* task, bool done = false);

public:
	virtual void FallbackTask(CCircuitUnit* unit) {}
	void AbortTask(IUnitTask* task) { DequeueTask(task, false); }
	void DoneTask(IUnitTask* task) { DequeueTask(task, true); }

public:
	// Script hooks
	virtual IUnitTask* MakeTask(CCircuitUnit* unit);
	void TaskAdded(IUnitTask* task);
	void TaskRemoved(IUnitTask* task, bool done);

	// Script API
	IUnitTask* GetTaskById(int taskId) const;
	virtual IUnitTask* DefaultMakeTask(CCircuitUnit* unit) = 0;

public:
	CIdleTask* GetIdleTask() const { return idleTask; }
	virtual CRetreatTask* EnqueueRetreat() { return nullptr; }

	void AssignPlayerTask(CCircuitUnit* unit);
	void Resurrected(CCircuitUnit* unit);

	void AddMetalPull(float value) { metalPull += value; }
	void DelMetalPull(float value) { metalPull -= value; }
	float GetMetalPull() const { return metalPull; }

protected:
	void SetUpdateIdleEnabled(bool isEnabled, int interval, int offset);
	void SetUpdateEnabled(bool isEnabled, int interval, int offset);
	void SetWatchdogEnabled(bool isEnabled, int interval, int offset);

	void UpdateIdle();
	void Update();
	virtual void Watchdog() = 0;

	virtual void Load(std::istream& is) override;
	virtual void Save(std::ostream& os) const override;

	CNilTask* nilTask;
	CIdleTask* idleTask;
	CPlayerTask* playerTask;

	std::shared_ptr<IMainJob> updateIdleJob;
	std::shared_ptr<IMainJob> updateJob;
	std::shared_ptr<IMainJob> watchdogJob;

	std::vector<IUnitTask*> updateTasks;  // owner
	unsigned int updateIterator;
	int taskId;  // generator

	float metalPull;
};

} // namespace circuit

#endif // SRC_CIRCUIT_MODULE_TASKMODULE_H_
