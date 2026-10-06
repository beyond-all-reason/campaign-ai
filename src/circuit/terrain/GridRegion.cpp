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

CGridRegion::CGridRegion(geom::CPolygon* poly, int cols, int rows, float cellSize)
		: polygon(poly)
		, gridCols(cols)
		, gridRows(rows)
		, cellSize(cellSize)
{
	polygon->AddRef();
	grid.resize(cols * rows, false);
	Rasterize();
}

CGridRegion::~CGridRegion()
{
	polygon->Release();
}

void CGridRegion::TestBlockRegion(SBlockingMap& blockingMap)
{
	for (int x = 0; x < gridCols; ++x) {
		for (int z = 0; z < gridRows; ++z) {
			if (grid[z * gridCols + x]) {
				blockingMap.AddBlocker(x, z, SBlockingMap::StructType::TERRA);
			}
		}
	}
}

void CGridRegion::Rasterize() {
	// 1. Find the bounding box of the polygon in world coordinates
	float minY = polygon->GetBox().top, maxY = polygon->GetBox().bottom;

	// 2. Convert bounding box to grid boundaries (row/col indices)
	int minRow = static_cast<int>(std::floor(minY / cellSize));
	int maxRow = static_cast<int>(std::floor(maxY / cellSize));

	// 3. Scanline algorithm: Iterate through each row from bottom to top
	for (int row = minRow; row <= maxRow; ++row) {
		// Find the Y center of the current grid row to test intersections
		float scanY = (row + 0.5) * cellSize;
		std::vector<float> intersections;

		// Find all intersections of the scanline with polygon edges
		const F3Vec& verts = polygon->GetVerts();
		for (size_t i = 0; i < verts.size(); ++i) {
			AIFloat3 p1 = verts[i];
			AIFloat3 p2 = verts[(i + 1) % verts.size()]; // Next vertex (wrap around)

			// Check if the edge crosses the scanline Y
			if ((p1.z <= scanY && p2.z > scanY) || (p2.z <= scanY && p1.z > scanY)) {
				// Calculate the exact X intersection point using linear interpolation
				float t = (scanY - p1.z) / (p2.z - p1.z);
				float intersectX = p1.x + t * (p2.x - p1.x);
				intersections.push_back(intersectX);
			}
		}

		// Sort intersections from left to right
		std::sort(intersections.begin(), intersections.end());

		// 4. Fill cells between pairs of intersections (even-odd rule)
		for (size_t i = 0; i < intersections.size(); i += 2) {
			if (i + 1 >= intersections.size()) break; // Malformed polygon safety check

			int startCol = static_cast<int>(std::floor(intersections[i] / cellSize));
			int endCol = static_cast<int>(std::floor(intersections[i + 1] / cellSize));

			for (int col = startCol; col <= endCol; ++col) {
				grid[row * gridCols + col] = true;
			}
		}
	}
}

} // namespace circuit
