/*
 * MilitaryScript.h
 *
 *  Created on: Apr 4, 2019
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_SCRIPT_MILITARYSCRIPT_H_
#define SRC_CIRCUIT_SCRIPT_MILITARYSCRIPT_H_

#include "script/TaskModuleScript.h"
#include "module/MilitaryManager.h"

namespace springai {
	class AIFloat3;
}

namespace circuit {

class CMilitaryScript final: public ITaskModuleScript {
public:
	CMilitaryScript(CScriptManager* scr, CMilitaryManager* mgr);
	virtual ~CMilitaryScript();

	virtual bool Init() override;

public:
	void MakeDefence(int cluster, const springai::AIFloat3& pos);
	void TaskResigned(CCircuitUnit* unit);
	void TaskZoneChanged(CCircuitUnit* unit, int srcZoneId, int dstZoneId);

private:
	static CMilitaryManager::SRoleInfo::SVsInfo* GetVsInfo(CMilitaryManager::SRoleInfo* info, CCircuitDef::RoleT vsType);

	struct SScriptInfo {
		asIScriptFunction* makeDefence = nullptr;
		asIScriptFunction* taskResigned = nullptr;
		asIScriptFunction* taskZoneChanged = nullptr;
	} militaryInfo;
};

} // namespace circuit

#endif // SRC_CIRCUIT_SCRIPT_MILITARYSCRIPT_H_
