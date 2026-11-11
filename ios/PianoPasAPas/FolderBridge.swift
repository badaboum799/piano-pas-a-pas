import UIKit
import UniformTypeIdentifiers
import WebKit

/// Dossier de partitions lié (par exemple dans iCloud Drive ou « Sur mon iPad »).
/// L'app garde un « signet » vers le dossier : la synchronisation relit son contenu
/// sans avoir à le choisir de nouveau, et envoie les partitions à la page web une par une.
final class FolderBridge: NSObject, UIDocumentPickerDelegate {
    private weak var webView: WKWebView?
    private weak var presenter: UIViewController?
    private let bookmarkKey = "folderBookmark"
    private let extensions: Set<String> = ["mxl", "musicxml", "xml", "mid", "midi"]

    init(webView: WKWebView, presenter: UIViewController) {
        self.webView = webView
        self.presenter = presenter
    }

    func handle(_ command: String) {
        switch command {
        case "pick": pick()
        case "sync":
            if let url = resolveBookmark() { sync(url) } else { pick() }
        default: break
        }
    }

    // MARK: choix du dossier
    private func pick() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter?.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
        sync(url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        call("__folderCancel", nil)
    }

    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    // MARK: synchronisation
    // Les fichiers récemment ajoutés dans iCloud Drive ne sont souvent pas encore téléchargés sur l'iPad :
    // on les liste, on demande leur téléchargement, puis on lit chacun « en coordination »,
    // ce qui attend que le fichier soit réellement disponible au lieu de l'ignorer.
    private var syncing = false
    private func sync(_ folder: URL) {
        if syncing { return }
        syncing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }
            let root = folder.resolvingSymlinksInPath().standardizedFileURL
            var candidates: [URL] = []
            var listError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &listError) { dir in
                guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return }
                for case let url as URL in walker {
                    var name = url.lastPathComponent
                    var real = url
                    // ancien format iCloud : « .Morceau.mxl.icloud » = fichier pas encore téléchargé
                    if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                        name = String(name.dropFirst().dropLast(7))
                        real = url.deletingLastPathComponent().appendingPathComponent(name)
                    } else if name.hasPrefix(".") { continue }
                    if self.extensions.contains(real.pathExtension.lowercased()) { candidates.append(real) }
                }
            }
            if let listError {
                DispatchQueue.main.async { self.syncing = false; self.call("__folderError", listError.localizedDescription) }
                return
            }
            // 1) demander le téléchargement de tout ce qui n'est pas encore sur l'iPad
            for url in candidates {
                let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                if v?.isUbiquitousItem == true && v?.ubiquitousItemDownloadingStatus != .current {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                }
            }
            // 2) lire chaque fichier (la lecture coordonnée attend la fin du téléchargement)
            var files: [[String: Any]] = []
            var failed = 0
            for url in candidates {
                var data: Data?
                var err: NSError?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in data = try? Data(contentsOf: u) }
                var tries = 0
                while data == nil && tries < 20 { // jusqu'à 10 s de plus si le fichier arrive encore
                    Thread.sleep(forTimeInterval: 0.5); tries += 1
                    data = try? Data(contentsOf: url)
                }
                guard let data else { failed += 1; continue }
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                let parts = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                let rel = parts.count > root.pathComponents.count ? parts.dropFirst(root.pathComponents.count).joined(separator: "/") : url.lastPathComponent
                files.append(["path": rel, "name": url.lastPathComponent, "mod": Int(mod.timeIntervalSince1970 * 1000), "b64": data.base64EncodedString()])
            }
            DispatchQueue.main.async {
                self.call("__folderBegin", folder.lastPathComponent)
                for f in files { self.call("__folderFile", f) }
                self.call("__folderEnd", ["failed": failed])
                self.syncing = false
            }
        }
    }

    private func call(_ fn: String, _ arg: Any?) {
        var json = "null"
        if let arg {
            if let data = try? JSONSerialization.data(withJSONObject: [arg], options: [.fragmentsAllowed]),
               let s = String(data: data, encoding: .utf8) { json = String(s.dropFirst().dropLast()) }
        }
        webView?.evaluateJavaScript("window.\(fn)&&window.\(fn)(\(json))")
    }
}
