//
//  ShareViewController.swift
//  MoltenShare
//
//  Molten 2.0 — K-U3/K-S4. "Add to Molten Knowledge" share extension with a
//  base picker. Writes the file directly into the chosen base folder through
//  the shared iCloud container; no copy is kept.
//

import UniformTypeIdentifiers

#if os(macOS)
import Cocoa

/// macOS placeholder: the share-sheet flow (K-U3) is iOS-only per the PRD.
/// The extension exists on macOS so the universal app can embed it; it
/// points users at the shared Finder folder instead.
class ShareViewController: NSViewController {
    override func loadView() {
        let label = NSTextField(wrappingLabelWithString: "To add files to Molten Knowledge, drop them into the Molten folder in Finder, or use Add files… in the app.")
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        view = container
    }
}
#else
import UIKit
import Social

class ShareViewController: SLComposeServiceViewController {
    private var bases: [String] = []
    private var selectedBase: String?
    private var sharedFile: (data: Data, name: String)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Molten Knowledge"
        placeholder = "Add to a knowledge base"
        bases = ShareImport.availableBases()
        loadAttachment()
    }

    private func loadAttachment() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else { return }
        let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            ? UTType.fileURL.identifier : UTType.data.identifier
        provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] item, _ in
            DispatchQueue.main.async {
                if let url = item as? URL {
                    let secured = url.startAccessingSecurityScopedResource()
                    let data = try? Data(contentsOf: url)
                    if secured { url.stopAccessingSecurityScopedResource() }
                    if let data {
                        self?.sharedFile = (data, url.lastPathComponent)
                    }
                } else if let data = item as? Data {
                    self?.sharedFile = (data, "Shared file")
                }
                self?.isContentValid()
            }
        }
    }

    override func isContentValid() -> Bool {
        let valid = selectedBase != nil && sharedFile != nil
        navigationItem.rightBarButtonItem?.isEnabled = valid
        return valid
    }

    override func configurationItems() -> [Any]! {
        guard let item = SLComposeSheetConfigurationItem() else { return [] }
        item.title = "Knowledge base"
        item.value = selectedBase ?? "Choose…"
        item.tapHandler = { [weak self] in self?.chooseBase() }
        return [item]
    }

    private func chooseBase() {
        let alert = UIAlertController(title: "Choose a base", message: nil, preferredStyle: .actionSheet)
        for base in bases {
            alert.addAction(UIAlertAction(title: base, style: .default) { [weak self] _ in
                self?.selectedBase = base
                self?.reloadConfigurationItems()
                self?.isContentValid()
            })
        }
        alert.addAction(UIAlertAction(title: "New base…", style: .default) { [weak self] _ in
            self?.promptNewBase()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func promptNewBase() {
        let alert = UIAlertController(title: "New knowledge base", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Name" }
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            guard let name = alert?.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            try? ShareImport.createBase(name)
            self?.bases = ShareImport.availableBases()
            self?.selectedBase = name
            self?.reloadConfigurationItems()
            self?.isContentValid()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    override func didSelectPost() {
        if let file = sharedFile, let base = selectedBase {
            try? ShareImport.importFile(file.data, fileName: file.name, intoBase: base)
        }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
#endif
