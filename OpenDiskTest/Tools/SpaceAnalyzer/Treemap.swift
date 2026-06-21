import Foundation
import CoreGraphics

// MARK: - Squarified treemap
//
// Bruls–Huizing–van Wijk squarified layout: greedily packs rows of rectangles
// keeping aspect ratios near 1:1, which reads far better than slice-and-dice.
// Pure geometry — the view renders the returned tiles in a Canvas.

struct TreemapTile {
    let node: ScanNode
    let rect: CGRect
}

enum Treemap {
    static func layout(_ items: [ScanNode], in rect: CGRect) -> [TreemapTile] {
        let positive = items.filter { $0.size > 0 }
        guard rect.width > 1, rect.height > 1, !positive.isEmpty else { return [] }

        let totalSize = positive.reduce(0.0) { $0 + Double($1.size) }
        let scale = Double(rect.width * rect.height) / totalSize
        let areas = positive.map { Double($0.size) * scale }

        var tiles: [TreemapTile] = []
        var current = rect
        var i = 0

        while i < positive.count {
            let side = Double(min(current.width, current.height))
            guard side > 0 else { break }

            var row: [Double] = []
            var rowNodes: [ScanNode] = []
            var j = i
            while j < positive.count {
                let candidate = row + [areas[j]]
                if row.isEmpty || worst(candidate, side) <= worst(row, side) {
                    row = candidate
                    rowNodes.append(positive[j])
                    j += 1
                } else {
                    break
                }
            }

            current = layoutRow(row, rowNodes, in: current, into: &tiles)
            i = j
        }
        return tiles
    }

    /// Worst aspect ratio in a row laid along a side of length `w`.
    private static func worst(_ row: [Double], _ w: Double) -> Double {
        guard !row.isEmpty else { return .infinity }
        let s = row.reduce(0, +)
        guard s > 0 else { return .infinity }
        let rMax = row.max() ?? 0
        let rMin = row.min() ?? 0
        guard rMin > 0 else { return .infinity }
        return max((w * w * rMax) / (s * s), (s * s) / (w * w * rMin))
    }

    /// Places a row as a strip along the shorter side; returns the remaining rect.
    private static func layoutRow(_ row: [Double], _ nodes: [ScanNode],
                                  in rect: CGRect, into tiles: inout [TreemapTile]) -> CGRect {
        let rowSum = row.reduce(0, +)
        guard rowSum > 0 else { return rect }

        let horizontal = rect.width <= rect.height
        if horizontal {
            // Strip spans full width at the top; thickness downward.
            let thickness = CGFloat(rowSum) / rect.width
            var x = rect.minX
            for (node, area) in zip(nodes, row) {
                let w = CGFloat(area) / thickness
                tiles.append(TreemapTile(node: node, rect: CGRect(x: x, y: rect.minY, width: w, height: thickness)))
                x += w
            }
            return CGRect(x: rect.minX, y: rect.minY + thickness,
                          width: rect.width, height: rect.height - thickness)
        } else {
            // Strip spans full height on the left; thickness rightward.
            let thickness = CGFloat(rowSum) / rect.height
            var y = rect.minY
            for (node, area) in zip(nodes, row) {
                let h = CGFloat(area) / thickness
                tiles.append(TreemapTile(node: node, rect: CGRect(x: rect.minX, y: y, width: thickness, height: h)))
                y += h
            }
            return CGRect(x: rect.minX + thickness, y: rect.minY,
                          width: rect.width - thickness, height: rect.height)
        }
    }
}
