import AppKit

extension NSLayoutConstraint {
    @discardableResult func identified(_ identifier: String) -> Self {
        self.identifier = identifier
        return self
    }
    static func activateOwned(_ constraints: [NSLayoutConstraint], owner: String) {
        for (index, constraint) in constraints.enumerated() where constraint.identifier == nil {
            constraint.identifier = "\(owner).\(index)"
        }
        activate(constraints)
    }
}
