import UIKit
import WebKit

/// Affiche l'app web Piano Pas à Pas en plein écran et lui fournit le MIDI natif de l'iPad.
final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    /// Adresse de l'app : les mises à jour publiées sur le site arrivent sans réinstaller l'app.
    static let appURL = URL(string: "https://badaboum799.github.io/piano-pas-a-pas/")!

    private var webView: WKWebView!
    private let midi = MIDIBridge()
    private var folder: FolderBridge?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()   // garde réglages, imports et clé d'une ouverture à l'autre

        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: Self.webMIDIShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.add(self, name: "midi")
        content.add(self, name: "folder")
        config.userContentController = content

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0x0f / 255, green: 0x12 / 255, blue: 0x20 / 255, alpha: 1)
        if #available(iOS 16.4, *) { webView.isInspectable = true }   // inspection possible depuis Safari sur Mac
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        folder = FolderBridge(webView: webView, presenter: self)
        midi.onDevicesChanged = { [weak self] devices in self?.sendDevices(devices) }
        midi.onMessage = { [weak self] id, bytes in
            self?.webView.evaluateJavaScript("window.__midiIn&&window.__midiIn(\(id),[\(bytes.map(String.init).joined(separator: ","))])")
        }
        load()
    }

    private func load() {
        // la page est toujours rechargée depuis le site (les mises à jour arrivent tout de suite) ;
        // les sons, eux, restent en cache
        webView.load(URLRequest(url: Self.appURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
    }

    private func sendDevices(_ devices: [MIDIBridge.Device]) {
        let list = devices.map { device -> String in
            let name = device.name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "{\"id\":\(device.id),\"name\":\"\(name)\"}"
        }.joined(separator: ",")
        webView.evaluateJavaScript("window.__midiDevices&&window.__midiDevices([\(list)])")
    }

    // La page demande l'accès MIDI : on lui envoie la liste des claviers.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "midi" { midi.refresh(); sendDevices(midi.devices) }
        if message.name == "folder", let command = message.body as? String { folder?.handle(command) }
    }

    // Pas de connexion : petite page d'erreur avec un bouton pour réessayer.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let html = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="background:#0f1220;color:#e8eaf6;font:17px -apple-system;display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center">
        <div style="font-size:48px">🎹</div><h2>Pas de connexion Internet</h2>
        <p style="color:#9aa1c7">Piano Pas à Pas a besoin d'Internet pour s'ouvrir.</p>
        <a href="\(Self.appURL.absoluteString)" style="margin-top:12px;background:#7c8cff;color:#0b0e1c;padding:12px 22px;border-radius:12px;text-decoration:none;font-weight:700">Réessayer</a>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // Liens externes (crédits, sites de partitions…) : ouverts dans Safari, pas dans l'app.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, action.navigationType == .linkActivated,
           url.host != Self.appURL.host, url.scheme?.hasPrefix("http") == true {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // Fenêtres alert() / confirm() de la page (par exemple « Supprimer cette partition ? »).
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .destructive) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    /// Remplace l'API Web MIDI (absente des navigateurs iOS) : la page croit parler à un
    /// navigateur compatible, et les messages viennent en réalité de CoreMIDI.
    static let webMIDIShim = """
    (function(){
      if (window.__nativeMIDI) return; window.__nativeMIDI = true; window.__nativeFolder = true;
      var inputs = new Map(), access = null;
      function makeInput(id, name){
        var p = {id:id, name:name, manufacturer:'', type:'input', state:'connected', connection:'open', onmidimessage:null};
        p.addEventListener = function(t, f){ if (t === 'midimessage') p.onmidimessage = f; };
        return p;
      }
      function notify(port){ if (access && access.onstatechange) access.onstatechange({port:port}); }
      window.__midiDevices = function(list){
        var ids = new Set(list.map(function(d){ return String(d.id); }));
        inputs.forEach(function(inp, id){ if (!ids.has(id)) { inp.state = 'disconnected'; inputs.delete(id); notify(inp); } });
        list.forEach(function(d){ var id = String(d.id); if (!inputs.has(id)) { var inp = makeInput(id, d.name); inputs.set(id, inp); notify(inp); } });
      };
      window.__midiIn = function(id, bytes){
        var inp = inputs.get(String(id));
        if (inp && inp.onmidimessage) inp.onmidimessage({data:new Uint8Array(bytes), target:inp, timeStamp:performance.now()});
      };
      Object.defineProperty(navigator, 'requestMIDIAccess', {configurable:true, value:function(){
        if (!access) access = {inputs:inputs, outputs:new Map(), sysexEnabled:false, onstatechange:null};
        window.webkit.messageHandlers.midi.postMessage('ready');
        return Promise.resolve(access);
      }});
    })();
    """
}
