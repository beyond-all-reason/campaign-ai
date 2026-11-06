/*
 * GridRegion.cpp
 *
 *  Created on: Oct 5, 2026
 *	  Author: rlcevg
 */

#include "terrain/GridRegion.h"

#include <algorithm>

namespace circuit {

using namespace springai;

CGridRegion::CGridRegion(Id id, geom::CPolygon* poly, float cellSize)
		: id(id)
		, polygon(poly)
		, cellSize(cellSize)
{
	polygon->AddRef();
	Rasterize();
}

CGridRegion::~CGridRegion()
{
	polygon->Release();
}

void CGridRegion::Rasterize()
{
	// 1. Find the bounding box of the polygon in world coordinates
	float minZ = polygon->GetBox().top, maxZ = polygon->GetBox().bottom;

	// 2. Convert bounding box to grid boundaries (row/col indices)
	short minRow = static_cast<short>(std::floor(minZ / cellSize));
	short maxRow = static_cast<short>(std::floor(maxZ / cellSize));

	// 3. Scanline algorithm: Iterate through each row from bottom to top
	for (short row = minRow; row <= maxRow; ++row) {
		// Find the Z center of the current grid row to test intersections
		float scanZ = (row + 0.5) * cellSize;
		std::vector<float> intersections;

		// Find all intersections of the scanline with polygon edges
		const F3Vec& verts = polygon->GetVerts();
		for (size_t i = 0; i < verts.size(); ++i) {
			AIFloat3 p1 = verts[i];
			AIFloat3 p2 = verts[(i + 1) % verts.size()]; // Next vertex (wrap around)

			// Check if the edge crosses the scanline Z
			if ((p1.z <= scanZ && p2.z > scanZ) || (p2.z <= scanZ && p1.z > scanZ)) {
				// Calculate the exact X intersection point using linear interpolation
				float t = (scanZ - p1.z) / (p2.z - p1.z);
				float intersectX = p1.x + t * (p2.x - p1.x);
				intersections.push_back(intersectX);
			}
		}

		// Sort intersections from left to right
		std::sort(intersections.begin(), intersections.end());

		SRow rowSpan;
		// 4. Fill cells between pairs of intersections (even-odd rule)
		for (size_t i = 0; i < intersections.size(); i += 2) {
			if (i + 1 >= intersections.size()) break; // Malformed polygon safety check

			short startCol = static_cast<short>(std::ceil((intersections[i] / cellSize) - 0.5f));
			short endCol = static_cast<short>(std::floor((intersections[i + 1] / cellSize) - 0.5f));

			if (startCol <= endCol) {
				SColumnSpan colSpan = {startCol, endCol};
				rowSpan.cols.push_back(colSpan);
			}
		}
		if (!rowSpan.cols.empty()) {
			rowSpan.row = row;
			rows.push_back(rowSpan);
		}
	}
}

} // namespace circuit
