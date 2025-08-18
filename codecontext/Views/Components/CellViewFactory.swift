import AppKit

/// Factory for creating outline view cell views
struct CellViewFactory {
    func createCellView(
        for columnId: String,
        node: FileNode,
        target: AnyObject? = nil,
        action: Selector? = nil
    ) -> NSView? {
        let container = NSView()

        switch columnId {
        case "checkbox":
            createCheckboxCell(in: container, node: node, target: target, action: action)
        case "name":
            createNameCell(in: container, node: node)
        case "tokens":
            createTokenCell(in: container, node: node)
        default:
            return nil
        }

        return container
    }

    private func createCheckboxCell(
        in container: NSView,
        node: FileNode,
        target: AnyObject?,
        action: Selector?
    ) {
        let checkbox = NSButton(checkboxWithTitle: "", target: target, action: action)
        checkbox.state = node.isSelected ? .on : .off
        checkbox.tag = node.id.hashValue
        container.applyTrailingConstraints(to: checkbox)
    }

    private func createNameCell(in container: NSView, node: FileNode) {
        let imageView = NSImageView()
        imageView.image = node.isDirectory ?
            NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder") :
            NSImage(systemSymbolName: "doc", accessibilityDescription: "File")
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let textField = NSTextField(labelWithString: node.name)
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail

        // Add views and constraints
        imageView.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        container.addSubview(textField)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }

    private func createTokenCell(in container: NSView, node: FileNode) {
        let textField = NSTextField(
            labelWithString: AppConfiguration.formatTokenCount(node.aggregateTokenCount)
        )
        textField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        textField.alignment = .right
        textField.textColor = .secondaryLabelColor
        container.applyStandardConstraints(to: textField)
    }
}
