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
    /// Share extensions run under a tight memory budget (~120 MB); reading
    /// a large shared file wholesale gets the extension jetsam-killed.
    /// Cap the in-memory payload well below that (review 2026-11-24).
    private static let maxShareBytes = 50 * 1024 * 1024

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
        provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] item, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.showLoadError("Couldn't load the shared item: \(error.localizedDescription)")
                    return
                }
                if let url = item as? URL {
                    let secured = url.startAccessingSecurityScopedResource()
                    defer { if secured { url.stopAccessingSecurityScopedResource() } }
                    // Check the size before reading: an oversized file must
                    // never be loaded into extension memory.
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    guard size <= Self.maxShareBytes else {
                        self.showLoadError("This file is too large to share into Knowledge (limit 50 MB). Add it from the Files app instead.")
                        return
                    }
                    if let data = try? Data(contentsOf: url) {
                        self.sharedFile = (data, url.lastPathComponent)
                    } else {
                        self.showLoadError("Couldn't read the shared file.")
                    }
                } else if let data = item as? Data {
                    guard data.count <= Self.maxShareBytes else {
                        self.showLoadError("This item is too large to share into Knowledge (limit 50 MB).")
                        return
                    }
                    self.sharedFile = (data, "Shared file")
                }
                self.isContentValid()
            }
        }
    }

    /// Surface a load failure in the compose area and keep Post disabled.
    private func showLoadError(_ message: String) {
        sharedFile = nil
        placeholder = message
        isContentValid()
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
            // G3 (review 2026-11-24): validate the name and only select the
            // base when it was actually created.
            guard let raw = alert?.textFields?.first?.text,
                  let name = ShareImport.sanitizedBaseName(raw) else { return }
            do {
                try ShareImport.createBase(name)
            } catch {
                self?.showLoadError("Couldn't create “\(name)”: \(error.localizedDescription)")
                return
            }
            self?.bases = ShareImport.availableBases()
            self?.selectedBase = name
            self?.reloadConfigurationItems()
            self?.isContentValid()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    override func didSelectPost() {
        guard let file = sharedFile, let base = selectedBase else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }
        do {
            try ShareImport.importFile(file.data, fileName: file.name, intoBase: base)
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            // Review 2026-11-24: a failed import used to complete as success
            // and silently lose the shared file. Keep the sheet open instead.
            let alert = UIAlertController(
                title: "Couldn't add the file",
                message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}
#endif
