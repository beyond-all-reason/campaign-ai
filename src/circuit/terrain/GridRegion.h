/*
 * GridRegion.h
 *
 *  Created on: Oct 5, 2026
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TERRAIN_GRIDREGION_H_
#define SRC_CIRCUIT_TERRAIN_GRIDREGION_H_

#include "terrain/BlockingMap.h"  // Test only
#include "util/math/Region.h"

#include <vector>

namespace circuit {

class CGridRegion final {
public:
	explicit CGridRegion(geom::CPolygon* poly, int cols, int rows, float cellSize);
	~CGridRegion();

	void TestBlockRegion(SBlockingMap& blockingMap);

private:
	void Rasterize();

	geom::CPolygon* polygon;
	std::vector<bool> grid;
	int gridCols;
	int gridRows;
	float cellSize;
};

} // namespace circuit

#endif /* SRC_CIRCUIT_TERRAIN_GRIDREGION_H_ */
