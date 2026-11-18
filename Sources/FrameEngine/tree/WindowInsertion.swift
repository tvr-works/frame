import Common
import Foundation

extension Window {
    /// Inserts at a slot in the destination's current child list, before removing this window.
    @MainActor
    @discardableResult
    package func insert(into column: Column, at slot: Int) -> Bool {
        guard self.column != nil, column.isColumn,
              (0 ... column.children.count).contains(slot)
        else { return false }
        let sameColumn = parent === column
        let index = slot - (sameColumn && ownIndex.orDie() < slot ? 1 : 0)
        if sameColumn && index == ownIndex { return true }
        let previous = unbindFromParent()
        bind(to: column, adaptiveWeight: sameColumn ? previous.adaptiveWeight : WEIGHT_AUTO, index: index)
        return true
    }
}
