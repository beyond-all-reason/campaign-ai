#include "../../lua_msg.as"
#include "../manager/builder.as"


namespace Region {

enum ERegionParam {
	UNITDEF_ID  = 1,
	STRUCT_MASK = 2,
}

class Manager {
	private array<AIFloat3>@ ParseVerts(const string& in strPoints) {
		const array<string>@ points = strPoints.split(LuaMsg::SEP_SUBPARAM);
		array<AIFloat3>@ verts = array<AIFloat3>();
		for (uint i = 0; i < points.length() / 2; ++i) {
			const float x = parseFloat(points[i * 2 + 0]);
			const float z = parseFloat(points[i * 2 + 1]);
			verts.insertLast(AIFloat3(x, 0.f, z));
		}
		return verts;
	}

	bool AddBuildZone(const array<string>& in params) {
		// params contains ["<RegionID>=<x1>,<z1>,<x2>,<z2>,<x3>,<z3>"; "<UnitDefId>"; "<facing>"; "<simultaneous>"]
		const array<string>@ region_points = params[0].split(LuaMsg::SEP_KEY_VALUE);
		Id regionId = parseInt(region_points[0]);
		if (buildZones.contains(regionId))
			return false;

		buildZones.insert(regionId);
		const array<AIFloat3>@ verts = ParseVerts(region_points[1]);
		Id unitDefId = parseInt(params[1]);
		int facing = parseInt(params[2]);
		aiBuilderMgr.AddBuildZone(regionId, CPolygon(verts), Builder::MakeBuildRecord(unitDefId), facing);

		// NOTE: BuildZone can be instantly filled with BuildTasks: works for air, traps land constructors.
		//       Building a zone with only 1-5 tasks simultaneously helps to avoid land traps.
		const int simultaneous = (params.length() > 3) ? parseInt(params[3]) : 0;
		const bool isSimultaneous = simultaneous <= 0;
		aiBuilderMgr.FillBuildZone(regionId, isSimultaneous);

		if (!isSimultaneous) {  // Start build-chain that will be continued by Manager::BuildNextSlot
			for (int i = 0; i < simultaneous; ++i) {
				IBuilderTask@ task = aiBuilderMgr.EnqueueBuildTaskForZone(regionId);
				if (task !is null)
					taskToZone.insert(task.id, regionId);
				else
					break;
			}
		}

		return true;
	}

	void ClearBuildZones(const array<string>& in params) {
		// params contains "<zoneID1>;<zoneID2>;<zoneID3>" or empty
		if (params.isEmpty() || parseInt(params[0]) <= 0) {
			for (auto it = buildZones.begin(); it++;)
				aiBuilderMgr.DelBuildZone(it.current());
			buildZones.clear();
			return;
		}

		for (uint i = 0; i < params.length(); ++i) {
			Id regionId = parseInt(params[i]);
			aiBuilderMgr.DelBuildZone(regionId);
			buildZones.erase(regionId);
		}
	}

	private Id RemoveZoneBuildTask(Id taskId) {
		auto it = taskToZone.find_iterator(taskId);
		if (it == taskToZone.end())
			return -1;

		Id regionId = it.current_value();
		taskToZone.erase(it);
		return regionId;
	}

	private void CreateNewZoneBuildTask(Id regionId) {
		IBuilderTask@ task = aiBuilderMgr.EnqueueBuildTaskForZone(regionId);
		if (task !is null)
			taskToZone.insert(task.id, regionId);
	}

	// Invoked by Builder::AiTaskRemoved
	void BuildNextSlot(Id prevTaskId) {
		Id regionId = RemoveZoneBuildTask(prevTaskId);
		if (regionId <= 0)
			return;

		CreateNewZoneBuildTask(regionId);
	}

	bool AddReservedZone(const array<string>& in params) {
		// params contains "<RegionID>=<x1>,<z1>,<x2>,<z2>,<x3>,<z3>"
		const array<string>@ region_points = params[0].split(LuaMsg::SEP_KEY_VALUE);
		Id regionId = parseInt(region_points[0]);
		if (reservedZones.contains(regionId))
			return false;

		reservedZones.insert(regionId);
		const array<AIFloat3>@ verts = ParseVerts(region_points[1]);
		aiBuilderMgr.AddReservedZone(regionId, CPolygon(verts));

		return true;
	}

	void ClearReservedZones(const array<string>& in params) {
		// params contains "<zoneID1>;<zoneID2>;<zoneID3>" or empty
		if (params.isEmpty() || parseInt(params[0]) <= 0) {
			for (auto it = reservedZones.begin(); it++;)
				aiBuilderMgr.DelReservedZone(it.current());
			reservedZones.clear();
			return;
		}

		for (uint i = 0; i < params.length(); ++i) {
			Id regionId = parseInt(params[i]);
			aiBuilderMgr.DelReservedZone(regionId);
			reservedZones.erase(regionId);
		}
	}

	bool AddAllowedZone(const array<string>& in params) {
		// params contains ["<RegionID>=<x1>,<z1>,<x2>,<z2>,<x3>,<z3>"; "<ERegionParam>=<type1>,<type2>,<type3>"]
		const array<string>@ region_points = params[0].split(LuaMsg::SEP_KEY_VALUE);
		Id regionId = parseInt(region_points[0]);
		if (allowedZones.contains(regionId))
			return false;

		allowedZones.insert(regionId);
		const array<AIFloat3>@ verts = ParseVerts(region_points[1]);

		Mask mask = 0;
		if (params.length() > 1) {
			// params[1] contains "UNITDEF_ID=<id1>,<id2>,<id3>" or "STRUCT_MASK=<mask>"
			const array<string>@ paramType_values = params[1].split(LuaMsg::SEP_KEY_VALUE);
			switch (parseInt(paramType_values[0])) {
			case ERegionParam::UNITDEF_ID: {
				const array<string>@ buildMaskTypes = paramType_values[1].split(LuaMsg::SEP_SUBPARAM);
				for (uint i = 0; i < buildMaskTypes.length(); ++i) {
					const int unitDefId = parseInt(buildMaskTypes[i]);
					mask |= aiTerrainMgr.GetStructMask(unitDefId);
				}
			} break;
			case ERegionParam::STRUCT_MASK: {
				mask = parseInt(paramType_values[1]);
			} break;
			default: break;
			}
		}

		aiBuilderMgr.AddAllowedZone(regionId, CPolygon(verts), mask);

		return true;
	}

	void ClearAllowedZones(const array<string>& in params) {
		// params contains "<zoneID1>;<zoneID2>;<zoneID3>" or empty
		if (params.isEmpty() || parseInt(params[0]) <= 0) {
			for (auto it = allowedZones.begin(); it++;)
				aiBuilderMgr.DelAllowedZone(it.current());
			allowedZones.clear();
			return;
		}

		for (uint i = 0; i < params.length(); ++i) {
			Id regionId = parseInt(params[i]);
			aiBuilderMgr.DelAllowedZone(regionId);
			allowedZones.erase(regionId);
		}
	}

	void FillAllowedGrid(int mask) {
		aiTerrainMgr.FillAllowedGrid(mask);
	}

	bool AddTriggerZone(const string& in param) {
		// param contains "<RegionID>=<x1>,<z1>,<x2>,<z2>,<x3>,<z3>"
		const array<string>@ region_points = param.split(LuaMsg::SEP_KEY_VALUE);
		Id regionId = parseInt(region_points[0]);
		if (triggerZones.contains(regionId))
			return false;

		triggerZones.insert(regionId);
		const array<AIFloat3>@ verts = ParseVerts(region_points[1]);
		aiMilitaryMgr.AddTriggerZone(regionId, CPolygon(verts));

		return true;
	}

	void ClearTriggerZones(const array<string>& in params) {
		// params contains "<zoneID1>;<zoneID2>;<zoneID3>" or empty
		if (params.isEmpty() || parseInt(params[0]) <= 0) {
			for (auto it = triggerZones.begin(); it++;)
				aiMilitaryMgr.DelTriggerZone(it.current());
			triggerZones.clear();
			return;
		}

		for (uint i = 0; i < params.length(); ++i) {
			Id regionId = parseInt(params[i]);
			aiMilitaryMgr.DelTriggerZone(regionId);
			triggerZones.erase(regionId);
		}
	}

	private set<Id> buildZones;
	private set<Id> reservedZones;
	private set<Id> allowedZones;
	private set<Id> triggerZones;

	private map<Id, Id> taskToZone;  // IBuilderTask.id => region.id
}

Manager mgr;

}  // namespace Region
