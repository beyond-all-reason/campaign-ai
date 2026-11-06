/*
 * BuilderScript.cpp
 *
 *  Created on: Apr 4, 2019
 *      Author: rlcevg
 */

#include "script/BuilderScript.h"
#include "script/ScriptManager.h"
#include "module/BuilderManager.h"
#include "util/ExtAS.h"
#include "angelscript/include/angelscript.h"

namespace circuit {

using namespace springai;

static void ConstructSResourceVal(SResource* mem, float m, float e)
{
	new(mem) SResource{m, e};
}

CBuilderScript::CBuilderScript(CScriptManager* scr, CBuilderManager* mgr)
		: ITaskModuleScript(scr, mgr)
{
	asIScriptEngine* engine = script->GetEngine();

	int r = engine->RegisterObjectType("SResource", sizeof(SResource), asOBJ_VALUE | asOBJ_POD | asGetTypeTraits<SResource>()); ASSERT(r >= 0);
	r = engine->RegisterObjectBehaviour("SResource", asBEHAVE_CONSTRUCT, "void f(float, float)", asFUNCTION(ConstructSResourceVal), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SResource", "float metal", asOFFSET(SResource, metal)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SResource", "float energy", asOFFSET(SResource, energy)); ASSERT(r >= 0);

	r = engine->RegisterObjectType("SBuildTask", sizeof(TaskB::SBuildTask), asOBJ_VALUE | asOBJ_POD); ASSERT(r >= 0);
	static_assert(sizeof(TaskB::SBuildTask::type) == sizeof(char), "IBuilderTask::BuildType is not uint8!");
	r = engine->RegisterObjectProperty("SBuildTask", "uint8 type", asOFFSET(TaskB::SBuildTask, type)); ASSERT(r >= 0);  // Task::BuildType
	static_assert(sizeof(TaskB::SBuildTask::priority) == sizeof(char), "IBuilderTask::Priority is not uint8!");
	r = engine->RegisterObjectProperty("SBuildTask", "uint8 priority", asOFFSET(TaskB::SBuildTask, priority)); ASSERT(r >= 0);  // Task::Priority
	r = engine->RegisterObjectProperty("SBuildTask", "CCircuitDef@ buildDef", asOFFSET(TaskB::SBuildTask, buildDef)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "AIFloat3 position", asOFFSET(TaskB::SBuildTask, position)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "SResource cost", asOFFSET(TaskB::SBuildTask, cost)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "CCircuitDef@ reprDef", asOFFSET(TaskB::SBuildTask, ref.reprDef)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "CCircuitUnit@ target", asOFFSET(TaskB::SBuildTask, ref.target)); ASSERT(r >= 0);
//	r = engine->RegisterObjectProperty("SBuildTask", "IGridLink@ link", asOFFSET(TaskB::SBuildTask, ref.link)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "int pointId", asOFFSET(TaskB::SBuildTask, i.pointId)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "int spotId", asOFFSET(TaskB::SBuildTask, i.spotId)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "float shake", asOFFSET(TaskB::SBuildTask, f.shake)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "float radius", asOFFSET(TaskB::SBuildTask, f.radius)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "bool isPlop", asOFFSET(TaskB::SBuildTask, b.isPlop)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "bool isMetal", asOFFSET(TaskB::SBuildTask, b.isMetal)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "bool isActive", asOFFSET(TaskB::SBuildTask, isActive)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SBuildTask", "int timeout", asOFFSET(TaskB::SBuildTask, timeout)); ASSERT(r >= 0);

	r = engine->RegisterObjectType("SServBTask", sizeof(TaskB::SServBTask), asOBJ_VALUE | asOBJ_POD); ASSERT(r >= 0);
	static_assert(sizeof(TaskB::SServBTask::type) == sizeof(char), "IBuilderTask::BuildType is not uint8!");
	r = engine->RegisterObjectProperty("SServBTask", "uint8 type", asOFFSET(TaskB::SServBTask, type)); ASSERT(r >= 0);  // Task::BuildType
	static_assert(sizeof(TaskB::SServBTask::priority) == sizeof(char), "IBuilderTask::Priority is not uint8!");
	r = engine->RegisterObjectProperty("SServBTask", "uint8 priority", asOFFSET(TaskB::SServBTask, priority)); ASSERT(r >= 0);  // Task::Priority
	r = engine->RegisterObjectProperty("SServBTask", "AIFloat3 position", asOFFSET(TaskB::SServBTask, position)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SServBTask", "CCircuitUnit@ target", asOFFSET(TaskB::SServBTask, target)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SServBTask", "float powerMod", asOFFSET(TaskB::SServBTask, powerMod)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SServBTask", "bool isInterrupt", asOFFSET(TaskB::SServBTask, isInterrupt)); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("SServBTask", "int timeout", asOFFSET(TaskB::SServBTask, timeout)); ASSERT(r >= 0);

	r = engine->RegisterObjectType("CBuilderManager", 0, asOBJ_REF | asOBJ_NOHANDLE); ASSERT(r >= 0);
	r = engine->RegisterGlobalProperty("CBuilderManager aiBuilderMgr", manager); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "IUnitTask@+ DefaultMakeTask(CCircuitUnit@)", asMETHOD(CBuilderManager, DefaultMakeTask), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "IUnitTask@+ Enqueue(const SBuildTask& in)", asMETHODPR(CBuilderManager, Enqueue, (const TaskB::SBuildTask&), IBuilderTask*), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "IUnitTask@+ Enqueue(const SServBTask& in)", asMETHODPR(CBuilderManager, Enqueue, (const TaskB::SServBTask&), IUnitTask*), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "IUnitTask@+ EnqueueRetreat()", asMETHOD(CBuilderManager, EnqueueRetreat), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "uint GetWorkerCount() const", asMETHOD(CBuilderManager, GetWorkerCount), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectProperty("CBuilderManager", "int dangerHysteresis", asOFFSET(CBuilderManager, dangerHysteresis)); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "void SetUpdateIdleEnabled(bool)", asMETHOD(CBuilderManager, SetUpdateIdleEnabled), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "void SetUpdateEnabled(bool)", asMETHOD(CBuilderManager, SetUpdateEnabled), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "void SetWatchdogEnabled(bool)", asMETHOD(CBuilderManager, SetWatchdogEnabled), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "IUnitTask@+ GetTaskById(Id) const", asMETHOD(CBuilderManager, GetTaskById), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "void AssignTask(CCircuitUnit@, IUnitTask@+)", asMETHODPR(CBuilderManager, AssignTask, (CCircuitUnit*, IUnitTask*), void), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "void AddBuildZone(Id, CPolygon@+, SBuildTask& in, int)", asMETHOD(CBuilderManager, AddBuildZone), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "void DelBuildZone(Id)", asMETHOD(CBuilderManager, DelBuildZone), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "void FillBuildZone(Id, bool)", asMETHOD(CBuilderManager, FillBuildZone), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "IBuilderTask@+ EnqueueBuildTaskForZone(Id)", asMETHOD(CBuilderManager, EnqueueBuildTaskForZone), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "void AddReservedZone(Id, CPolygon@+)", asMETHOD(CBuilderManager, AddReservedZone), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "void DelReservedZone(Id)", asMETHOD(CBuilderManager, DelReservedZone), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "void AddAllowedZone(Id, CPolygon@+, int)", asMETHOD(CBuilderManager, AddAllowedZone), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "void DelAllowedZone(Id)", asMETHOD(CBuilderManager, DelAllowedZone), asCALL_THISCALL); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CBuilderManager", "AIFloat3 DefaultFindBuildSite(CCircuitDef@, CCircuitUnit@, const AIFloat3& in)", asMETHOD(CBuilderManager, DefaultFindBuildSite), asCALL_THISCALL); ASSERT(r >= 0);
}

CBuilderScript::~CBuilderScript()
{
}

bool CBuilderScript::Init()
{
	asIScriptModule* mod = script->GetEngine()->GetModule(CScriptManager::mainName.c_str());
	int r = mod->SetDefaultNamespace("Builder"); ASSERT(r >= 0);
	InitModule(mod);
	builderInfo.taskAssigned = script->GetFunc(mod, "void AiTaskAssigned(CCircuitUnit@)");
	builderInfo.findBuildSite = script->GetFunc(mod, "AIFloat3 FindBuildSite(CCircuitDef@, CCircuitUnit@, const AIFloat3& in)");
	return true;
}

void CBuilderScript::TaskAssigned(CCircuitUnit* unit)
{
	if (builderInfo.taskAssigned == nullptr) {
		return;
	}
	asIScriptContext* ctx = script->PrepareContext(builderInfo.taskAssigned);
	ctx->SetArgObject(0, unit);
	script->Exec(ctx);
	script->ReturnContext(ctx);
}

AIFloat3 CBuilderScript::FindBuildSite(CCircuitDef* buildDef, CCircuitUnit* unit, const AIFloat3& position)
{
	if (builderInfo.findBuildSite == nullptr) {
		return static_cast<CBuilderManager*>(manager)->DefaultFindBuildSite(buildDef, unit, position);
	}
	asIScriptContext* ctx = script->PrepareContext(builderInfo.findBuildSite);
	ctx->SetArgObject(0, buildDef);
	ctx->SetArgObject(1, unit);
	ctx->SetArgAddress(2, &const_cast<AIFloat3&>(position));
	AIFloat3* result = script->Exec(ctx) ? (AIFloat3*)ctx->GetReturnAddress() : nullptr;
	script->ReturnContext(ctx);
	return (result != nullptr) ? *result : -RgtVector;
}

} // namespace circuit
