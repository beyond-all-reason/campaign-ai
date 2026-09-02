namespace Wave {

// Has to be same as Lua's defines
enum EWaveParams {
	WAVE_FACTORY = 1,
	WAVE_POWER   = 2,
	WAVE_RETREAT = 3,
}

enum EWaveState { CREATE, IDLE, TASK }

class UnitNum {
	UnitNum(Id defId, int n) {
		unitDefId = defId;
		num = n;
	}
	UnitNum() {}

	Id unitDefId;
	int num;
}

class Wave {
	Wave(int p_id) { id = p_id; }

	int id;
	EWaveState state = EWaveState::CREATE;
	CCircuitDef@ facDef;
	IUnitTask@ task;
	float power = 0.f;
	float retreat = 0.f;
	array<UnitNum> orderList;
}

Wave@ Create(const SIntent& in intent)
{
	Wave wave(intent.objId);
	for (uint i = 0; i < intent.size; ++i) {
		switch (intent.GetKey(i)) {
		case EWaveParams::WAVE_FACTORY: { @wave.facDef = ai.GetCircuitDef(Id(intent.GetValue(i))); } break;
		case EWaveParams::WAVE_POWER:   { wave.power   = intent.GetValue(i); } break;
		case EWaveParams::WAVE_RETREAT: { wave.retreat = intent.GetValue(i); } break;
		default: break;
		}
	}
	return wave;
}

}  // namespace Wave
