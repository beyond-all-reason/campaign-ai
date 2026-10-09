#include "../../lua_msg.as"


namespace Region {

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
		// params contains ["<RegionID>", "<UnitDefId>=<x1>,<z1>,<x2>,<z2>,<x3>,<z3>"]
		Id regionId = parseInt(params[0]);
		if (buildZones.contains(regionId))
			return false;

		buildZones.insert(regionId);
		const array<string>@ unitDef_points = params[1].split(LuaMsg::SEP_KEY_VALUE);
		const array<AIFloat3>@ verts = ParseVerts(unitDef_points[1]);
		Id unitDefId = parseInt(unitDef_points[0]);
		aiBuilderMgr.AddBuildZone(regionId, CPolygon(verts), ai.GetCircuitDef(unitDefId));

		for (uint i = 0; i < verts.length(); ++i)  // FIXME: DEBUG
			AiAddLine(verts[i], verts[(i+1) % verts.length()]);
		return true;
	}

	void ClearBuildZones() {
		for (auto it = buildZones.begin(); it++;)
			aiBuilderMgr.DelBuildZone(it.current());
		buildZones.clear();
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

		for (uint i = 0; i < verts.length(); ++i)  // FIXME: DEBUG
			AiAddLine(verts[i], verts[(i+1) % verts.length()]);
		return true;
	}

	void ClearTriggerZones() {
		for (auto it = triggerZones.begin(); it++;)
			aiMilitaryMgr.DelTriggerZone(it.current());
		triggerZones.clear();
	}

	private set<Id> buildZones;
	private set<Id> triggerZones;
}

Manager mgr;

}  // namespace Region
