#include "squad.as"
#include "../../intent.as"


namespace Intent {

class Manager {
	/*
	 * Intent handlers
	 */
	void HandleIntent(const SIntent& in intent) {
		switch (intent.topic) {

		case AI_ENABLE: {  // SFloatIntent
			AiLog("SFloatIntent: AI_ENABLE, objID: " + intent.objId + ", Value: " + intent.value);
		} break;

		case AI_BASE_CREATE: {  // SDictFloatIntent
			AiLog("SDictFloatIntent: AI_BASE_CREATE, BaseID: " + intent.objId + ", Size: " + intent.size + ", Key[0]: " + intent.GetKey(0) + ", Value[0]: " + intent.GetValue(0));
		} break;

		case AI_BASE_REBUILD: {  // SFloatIntent
			AiLog("SFloatIntent: AI_BASE_REBUILD, BaseID: " + intent.objId + ", Value: " + intent.value);
		} break;

		case AI_UNIT_WEIGHTS: {  // SArrayFloatIntent
// 			ChangeWeights(intent);
		} break;

		case AI_SQUAD_CREATE: {  // SDictFloatIntent
			Squad::mgr.CreateRequest(intent);
		} break;

		case AI_SQUAD_COMPOSE: {  // SDictFloatIntent
			Squad::mgr.ComposeRequest(intent);
		} break;

		case AI_SQUAD_DESTROY: {  // SFloatIntent
			Squad::mgr.DestroySquad(intent.objId);
		} break;

		case AI_SQUAD_POSITION: {  // SArrayFloatIntent
			Squad::mgr.SetSquadPosition(intent);
		} break;

		case AI_REGION_AVOID: {  // SArrayFloatIntent
			AiLog("SArrayFloatIntent: AI_REGION_AVOID, RegionID: " + intent.objId + ", Size: " + intent.size + ", Value[0]: " + intent[0]);
		} break;

		case AI_FACTORY_ENABLE: {  // SArrayFloatIntent
			for (uint i = 0; i < intent.size; ++i)
				aiFactoryMgr.SetIsActiveFactory(Id(intent[i]), intent.objId != 0);
		} break;

		case AI_ENABLED_UNITS: {  // SDictFloatIntent
			for (uint i = 0; i < intent.size; ++i)
				UpdateEnabledUnits(intent.GetKey(i), intent.GetValue(i) != 0.0);
		} break;

		case AI_EXEC_ORDER_66: {  // SFloatIntent
			ExecOrder66();
		} break;

		default:
			AiLog("Unhandled intent topic: " + intent.topic);
			break;
		}
	}

	/*
	 * Handler helpers
	 */
// 	void ChangeWeights(const SIntent& in intent) {
// 		bool success = false;
// 		Squad::Squad@ squad = squads.find(intent.objId, success);
// 		if (!success) {
//             AiLog("Error: Squad " + intent.objId + " not found");
// 			return;
// 		}
// 		array<float>@ weights = aiFactoryMgr.GetTierWeights(squad.facDef, Unit::SurfType::LAND, 0);
// 		if (intent.size != weights.length()) {
//             AiLog("Error: Weights size must be equal to factory.json content");
// 			return;
//         }
// 		for (uint i = 0; i < weights.length(); ++i)
// 			weights[i] = intent[i];
// 		aiFactoryMgr.SetTierWeights(squad.facDef, Unit::SurfType::LAND, 0, weights);
// 		aiFactoryMgr.SetTierWeights(squad.facDef, Unit::SurfType::LAND, 1, weights);
// 		aiFactoryMgr.SetTierWeights(squad.facDef, Unit::SurfType::LAND, 2, weights);
// 		aiFactoryMgr.SetTierWeights(squad.facDef, Unit::SurfType::LAND, 3, weights);
// 	}

	void UpdateEnabledUnits(Id unitDefId, bool isEnabled) {
		CCircuitDef@ cdef = ai.GetCircuitDef(unitDefId);
		if (cdef is null)
			return;
		if (isEnabled) {
			bool success = false;
			int limit = prevUnitLimits.find(cdef.id, success);
			cdef.maxThisUnit = success ? limit : 32000;  // magic numbers
			// prevUnitLimits.erase(cdef.id);
		} else {
			prevUnitLimits[cdef.id] = cdef.maxThisUnit;
			cdef.maxThisUnit = 0;
		}
	}

	void ExecOrder66() {
		int num = 0;
		for (auto it = Main::units.begin(); it++;) {
			CCircuitUnit@ unit = it.current_value();
			unit.SelfDestruct(true);
			if (++num >= 66)
				return;
		}
	}

	/*
	 * Properties
	 */
	private map<Id, int> prevUnitLimits;  // behaviour.json may have other than 32000 value
}

Manager mgr;

}  // namespace Intent
