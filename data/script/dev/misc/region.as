#include "../../lua_msg.as"


namespace Region {

class Manager {
	bool AddBuildZone(const array<string>& in params) {
		// params contains ["<RegionID>", "<UnitDefId>=<x1>,<z1>,<x2>,<z2>,<x3>,<z3>"]
		Id regionId = parseInt(params[0]);
		if (buildZones.contains(regionId))
			return false;

		buildZones.insert(regionId);
		const array<string>@ unitDef_points = params[1].split(LuaMsg::SEP_KEY_VALUE);
		const array<string>@ points = unitDef_points[1].split(LuaMsg::SEP_SUBPARAM);
		array<AIFloat3> verts;
		for (uint i = 0; i < points.length() / 2; ++i) {
			const float x = parseFloat(points[i * 2 + 0]);
			const float z = parseFloat(points[i * 2 + 1]);
			verts.insertLast(AIFloat3(x, 0.f, z));
		}
		Id unitDefId = parseInt(unitDef_points[0]);
		aiBuilderMgr.AddBuildZone(regionId, CPolygon(verts), ai.GetCircuitDef(unitDefId));

		for (uint i = 0; i < verts.length(); ++i)
			AiAddLine(verts[i], verts[(i+1) % verts.length()]);
		return true;
	}

	void ClearBuildZones() {
		for (auto it = buildZones.begin(); it++;)
			aiBuilderMgr.DelBuildZone(it.current());
		buildZones.clear();
	}

	private set<Id> buildZones;
}

Manager mgr;

}  // namespace Region
