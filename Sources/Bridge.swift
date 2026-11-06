import AppKit
import WebKit

enum BridgeEvent {
    case ready
    case panelDidShow
    case height(CGFloat)
    case refresh
    case openSettings(String?)
    case showDetail(Bool)
    case exportCSV
    case relogin
    case browserLogin
    case embeddedLogin
    case importSession
    case logout
    case quit
    case setPref(String, Any)
    case setWorkspace(String)
    case saveAccount(baseUrl: String, token: String)
    case checkUpdate
    case openLink(String)
    case unknown(String)
}

final class Bridge: NSObject, WKScriptMessageHandler {
    var handler: ((BridgeEvent) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let event: BridgeEvent
        switch type {
        case "ready": event = .ready
        case "height": event = .height(CGFloat((body["height"] as? NSNumber)?.doubleValue ?? 0))
        case "refresh": event = .refresh
        case "openSettings": event = .openSettings(body["pane"] as? String)
        case "showDetail": event = .showDetail((body["show"] as? Bool) ?? true)
        case "exportCSV": event = .exportCSV
        case "relogin": event = .browserLogin
        case "browserLogin": event = .browserLogin
        case "embeddedLogin": event = .embeddedLogin
        case "importSession": event = .importSession
        case "logout": event = .logout
        case "quit": event = .quit
        case "setWorkspace":
            event = .setWorkspace(body["id"] as? String ?? "")
        case "setPref":
            if let key = body["key"] as? String { event = .setPref(key, body["value"] ?? NSNull()) }
            else { event = .unknown(type) }
        case "saveAccount":
            event = .saveAccount(baseUrl: body["baseUrl"] as? String ?? "",
                                 token: body["token"] as? String ?? "")
        case "checkUpdate": event = .checkUpdate
        case "openLink": event = .openLink(body["url"] as? String ?? "")
        default: event = .unknown(type)
        }
        handler?(event)
    }

    static func attach(to config: WKWebViewConfiguration, bridge: Bridge) {
        config.userContentController.add(bridge, name: "bridge")
        // 禁用选中/拖拽/右键菜单，让它更像原生面板
        let css = "html, body { -webkit-user-select: none; user-select: none; cursor: default; }"
            + "input, textarea, select { -webkit-user-select: auto; user-select: auto; }"
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = WKUserScript(source: """
        (function(){
          const style = document.createElement('style');
          style.textContent = "\(escaped)";
          document.documentElement.appendChild(style);
          document.addEventListener('contextmenu', e => e.preventDefault());
        })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
    }

    static func makeWebView(bridge: Bridge) -> WKWebView {
        let config = WKWebViewConfiguration()
        attach(to: config, bridge: bridge)
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        if web.responds(to: NSSelectorFromString("underPageBackgroundColor")) {
            web.underPageBackgroundColor = .clear
        }
        web.allowsMagnification = false
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        return web
    }

    static func push<T: Encodable>(_ state: T, function: String, into web: WKWebView, log: Bool = false) {
        guard let data = try? JSONEncoder().encode(state),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("\(function)(\(json))") { _, error in
            if log, let error { NSLog("margin.js \(function) failed: \(error)") }
        }
    }

    static func call(_ js: String, on web: WKWebView) {
        web.evaluateJavaScript(js, completionHandler: nil)
    }
}
