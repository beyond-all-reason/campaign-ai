/*
 * BuilderScript.h
 *
 *  Created on: Apr 4, 2019
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_SCRIPT_BUILDERSCRIPT_H_
#define SRC_CIRCUIT_SCRIPT_BUILDERSCRIPT_H_

#include "script/TaskModuleScript.h"

namespace circuit {

class CBuilderManager;

class CBuilderScript final: public ITaskModuleScript {
public:
	CBuilderScript(CScriptManager* scr, CBuilderManager* mgr);
	virtual ~CBuilderScript();

	virtual bool Init() override;

public:
	void TaskAssigned(CCircuitUnit* unit);
	springai::AIFloat3 FindBuildSite(CCircuitDef* buildDef,  CCircuitUnit* unit, const springai::AIFloat3& position);

private:
	struct SScriptInfo {
		asIScriptFunction* taskAssigned = nullptr;
		asIScriptFunction* findBuildSite = nullptr;
	} builderInfo;
};

} // namespace circuit

#endif // SRC_CIRCUIT_SCRIPT_BUILDERSCRIPT_H_
