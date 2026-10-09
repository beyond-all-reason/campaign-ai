/*
 * GridRegion.h
 *
 *  Created on: Oct 5, 2026
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_TERRAIN_GRIDREGION_H_
#define SRC_CIRCUIT_TERRAIN_GRIDREGION_H_

#include "util/math/Region.h"

#include <vector>

#define NULL_ZONE	0

namespace circuit {

class CGridRegion final {
public:
	using Id = int;

	CGridRegion() = delete;
	explicit CGridRegion(Id id, geom::CPolygon* poly, float cellSize);
	~CGridRegion();

	Id GetId() const { return id; }

	template <typename Visitor>
	void ProcessRegion(Visitor visitor) const;

private:
	void Rasterize();

	Id id;
	geom::CPolygon* polygon;
	struct SColumnSpan {
		short startCol;
		short endCol;
	};
	struct SRow {
		short row;
		std::vector<SColumnSpan> cols;
	};
	std::vector<SRow> rows;
	float cellSize;
};

template <typename Visitor>
void CGridRegion::ProcessRegion(Visitor visitor) const
{
	for (const SRow& row : rows) {
		for (const SColumnSpan& span : row.cols) {
			for (short col = span.startCol; col <= span.endCol; ++col) {
				visitor(col, row.row);
			}
		}
	}
}

} // namespace circuit

#endif /* SRC_CIRCUIT_TERRAIN_GRIDREGION_H_ */
