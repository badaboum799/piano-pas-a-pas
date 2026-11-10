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

    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    // MARK: synchronisation : lecture du dossier (et de ses sous-dossiers) en arrière-plan
    private func sync(_ folder: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }
            var files: [[String: Any]] = []
            var notDownloaded = 0
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
            let coordinator = NSFileCoordinator()
            var coordError: NSError?
            coordinator.coordinate(readingItemAt: folder, options: [], error: &coordError) { dir in
                guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
                for case let url as URL in walker {
                    // fichier iCloud pas encore téléchargé : on demande le téléchargement pour la prochaine fois
                    if url.pathExtension == "icloud" {
                        notDownloaded += 1
                        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                        continue
                    }
                    guard self.extensions.contains(url.pathExtension.lowercased()),
                          let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                          let data = try? Data(contentsOf: url) else { continue }
                    let path = url.path.replacingOccurrences(of: dir.path + "/", with: "")
                    let mod = Int((values.contentModificationDate ?? Date()).timeIntervalSince1970 * 1000)
                    files.append(["path": path, "name": url.lastPathComponent, "mod": mod, "b64": data.base64EncodedString()])
                }
            }
            DispatchQueue.main.async {
                if let coordError { self.call("__folderError", coordError.localizedDescription); return }
                self.call("__folderBegin", folder.lastPathComponent)
                for f in files { self.call("__folderFile", f) }
                self.call("__folderEnd", nil)
                if notDownloaded > 0 {
                    self.webView?.evaluateJavaScript("toast&&toast('\(notDownloaded) fichier(s) iCloud pas encore téléchargé(s) : relance la synchronisation dans un moment.',6000)")
                }
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
