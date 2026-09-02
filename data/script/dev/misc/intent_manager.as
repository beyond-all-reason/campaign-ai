#include "wave.as"
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
			ChangeWeights(intent);
		} break;

		case AI_WAVE_CREATE: {  // SDictFloatIntent
			@waves[intent.objId] = Wave::Create(intent);
		} break;

		case AI_WAVE_DESTROY: {  // SFloatIntent
			waves.erase(intent.objId);
		} break;

		case AI_WAVE_COMPOSE: {  // SDictFloatIntent
			ComposeWave(intent);
		} break;

		case AI_WAVE_DEFEND: {  // SArrayFloatIntent
			AIFloat3 pos(intent[0], intent[1], intent[2]);
			AiLog("defend at " + pos);
			DefendPosition(intent.objId, pos);
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
	void ComposeWave(const SIntent& in intent) {
		bool success = false;
		Wave::Wave@ wave = waves.find(intent.objId, success);
		if (!success) {
			AiLog("Error: Wave " + intent.objId + " not found");
			return;
		}
		for (uint i = 0; i < intent.size; ++i) {
			Id unitDefId = intent.GetKey(i);
			CCircuitDef@ cdef = ai.GetCircuitDef(unitDefId);
			if (cdef is null) {
				AiLog("Error: Wave " + intent.objId + ", UnitDefID " + unitDefId + " not found");
				continue;
			}
			wave.orderList.insertLast(Wave::UnitNum(unitDefId, int(intent.GetValue(i))));
		}
	}

	void ChangeWeights(const SIntent& in intent) {
		bool success = false;
		Wave::Wave@ wave = waves.find(intent.objId, success);
		if (!success) {
            AiLog("Error: Wave " + intent.objId + " not found");
			return;
		}
		array<float>@ weights = aiFactoryMgr.GetTierWeights(wave.facDef, Unit::SurfType::LAND, 0);
		if (intent.size != weights.length()) {
            AiLog("Error: Weights size must be equal to factory.json content");
			return;
        }
		for (uint i = 0; i < weights.length(); ++i)
			weights[i] = intent[i];
		aiFactoryMgr.SetTierWeights(wave.facDef, Unit::SurfType::LAND, 0, weights);
		aiFactoryMgr.SetTierWeights(wave.facDef, Unit::SurfType::LAND, 1, weights);
		aiFactoryMgr.SetTierWeights(wave.facDef, Unit::SurfType::LAND, 2, weights);
		aiFactoryMgr.SetTierWeights(wave.facDef, Unit::SurfType::LAND, 3, weights);
	}

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

	void DefendPosition(Id unitId, const AIFloat3& in pos) {
		bool success = false;
		CCircuitUnit@ unit = Main::units.find(unitId, success);
		if (!success || unit.task.GetType() != Task::Type::FIGHTER)
			return;
		IFighterTask@ taskF = cast<IFighterTask>(unit.task);
		if (taskF.GetFightType() != Task::FightType::DEFEND)
			return;
		CDefendTask@ defendTask = cast<CDefendTask>(taskF);
		defendTask.SetTargetPos(pos);
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
	 * Property accessors
	 */
	Wave::Wave@ GetWaveForFactory(CCircuitUnit@ unit) {
		for (auto it = waves.begin(); it++;) {
			Wave::Wave@ wave = it.current_value();
			if (wave.facDef.id == unit.circuitDef.id)
				return wave;
		}
		return null;
	}

	void RemoveWave(int waveId) {
		waves.erase(waveId);
	}

	/*
	 * Properties
	 */
	private map<int, Wave::Wave@> waves;  // waveID: Wave@
	private map<Id, int> prevUnitLimits;  // behaviour.json may have other than 32000 value
}

}  // namespace Intent
