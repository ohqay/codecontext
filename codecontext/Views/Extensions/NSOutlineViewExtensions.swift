import AppKit

extension NSView {
    /// Apply standard constraints for a centered subview with padding
    func applyStandardConstraints(
        to subview: NSView,
        leading: CGFloat = 4,
        trailing: CGFloat = -4,
        centerY: Bool = true
    ) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subview)

        var constraints = [
            subview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leading),
            subview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: trailing),
        ]

        if centerY {
            constraints.append(subview.centerYAnchor.constraint(equalTo: centerYAnchor))
        }

        NSLayoutConstraint.activate(constraints)
    }

    /// Apply constraints for a trailing-aligned control (like checkbox)
    func applyTrailingConstraints(to subview: NSView, padding: CGFloat = -2) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subview)
        NSLayoutConstraint.activate([
            subview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: padding),
            subview.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

extension NSOutlineView {
    /// Configure standard outline view settings
    func configureStandardSettings() {
        headerView = nil
        rowSizeStyle = .medium
        autoresizesOutlineColumn = false
        indentationPerLevel = 24
        columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        intercellSpacing = NSSize(width: 0, height: 2)
    }

    /// Iterate through all visible nodes
    func forEachVisibleNode<T>(_ action: (Int, T) -> Bool) where T: Any {
        for row in 0 ..< numberOfRows {
            guard let node = item(atRow: row) as? T else { continue }
            if action(row, node) { break }
        }
    }
}
