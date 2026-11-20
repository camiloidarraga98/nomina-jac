#if os(iOS)
import SwiftUI
import WebKit

struct TeamAttendanceView: UIViewRepresentable {
    @EnvironmentObject private var store: PayrollStore
    /// nil is the restricted, signed-out device. The admin interface is tied to one JAC user.
    let administrator: String?
    func makeCoordinator() -> Coordinator { Coordinator(store:store, administrator:administrator) }
    func makeUIView(context:Context) -> WKWebView {
        let config=WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addScriptMessageHandler(context.coordinator,contentWorld:.page,name:"teamAttendance")
        let web=WKWebView(frame:.zero,configuration:config)
        web.navigationDelegate=context.coordinator
        if let file=Coordinator.file {web.loadFileURL(file,allowingReadAccessTo:file.deletingLastPathComponent())}
        return web
    }
    func updateUIView(_ web:WKWebView,context:Context) {}
    static func dismantleUIView(_ web:WKWebView,coordinator:Coordinator) {
        coordinator.active=false
        var presenter=web.window?.rootViewController
        while let next=presenter?.presentedViewController {presenter=next}
        (presenter as? AttendanceFaceCamera)?.cancelCapture()
        web.stopLoading();web.configuration.userContentController.removeScriptMessageHandler(forName:"teamAttendance",contentWorld:.page)
    }

    @MainActor final class Coordinator:NSObject,WKNavigationDelegate,WKScriptMessageHandlerWithReply {
        let store:PayrollStore
        let administrator:String?
        var active=true
        static var file:URL? {Bundle.main.url(forResource:"team",withExtension:"html",subdirectory:"attendance")}
        init(store:PayrollStore,administrator:String?) {self.store=store;self.administrator=administrator}
        private var allowed:Bool {
            guard active,!store.client.isAttendancePilot,store.client.baseURL==PayrollClient.productionURL else {return false}
            if let administrator {
                guard let user=store.overview?.user, user.id==administrator,user.isOwner,user.hasSection(.crm) else {return false}
                return (try? store.client.hasSession()) == true
            }
            return (try? store.client.hasSession()) == false && TeamAttendanceDevice.shared.isPaired
        }
        func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
            decisionHandler(Self.file != nil && action.request.url?.standardizedFileURL==Self.file?.standardizedFileURL ? .allow:.cancel)
        }
        func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage,replyHandler:@escaping(Any?,String?)->Void) {
            guard allowed,message.frameInfo.isMainFrame, Self.file != nil, message.frameInfo.request.url?.standardizedFileURL==Self.file?.standardizedFileURL,
                  let body=message.body as? [String:Any], let action=body["action"] as? String else {replyHandler(nil,"Acceso no disponible.");return}
            Task { @MainActor in
                do {
                    guard self.allowed else {throw APIError.unauthorized}
                    let device=TeamAttendanceDevice.shared, result:Any
                    switch (administrator != nil, action) {
                    case (_, "mode"): result=administrator == nil ? "kiosk":"admin"
                    case (true, "admin"):
                        let payload=body["payload"] as? [String:Any]
                        if let command=payload?["action"] as? String, ["enroll","pair"].contains(command) {throw APIError.forbidden("Usa la inscripción presencial en el kiosco.")}
                        let data=try await store.client.sharedAttendanceAdmin(payload,filters:body["params"] as? [String:String] ?? [:])
                        result=try JSONSerialization.jsonObject(with:data)
                    case (true, "pair"):
                        guard let name=body["name"] as? String else {throw APIError.invalid("Indica el nombre del kiosco.")}
                        try await device.pair(name:name,client:store.client);result=true
                    case (true, "info"):result=try await device.info()
                    case (false, "status"):result=try await device.status()
                    case (true, "enroll"),(true, "verify"),(false, "mark"):
                        guard let web=message.webView, let root=web.window?.rootViewController else {throw APIError.message("Vuelve a abrir Asistencia.")}
                        var presenter=root
                        while let next=presenter.presentedViewController {presenter=next}
                        let employee=body["employee"] as? String, movement=body["movement"] as? String
                        guard action=="mark" ? (employee==nil && ["entry","exit"].contains(movement ?? "")) : (movement==nil && UUID(uuidString:employee ?? "") != nil) else {throw APIError.invalid("Solicitud no válida.")}
                        result=try await device.capture(employee:employee,claimedCode:action=="mark" ? body["code"] as? String : nil,movement:movement,enroll:action=="enroll",client:store.client,presenter:presenter,allowed:{self.allowed && web.window != nil})
                    default:throw APIError.forbidden("Esta acción requiere otra autorización.")
                    }
                    guard self.allowed else {throw APIError.unauthorized}
                    replyHandler(result,nil)
                } catch {replyHandler(nil,error.localizedDescription)}
            }
        }
    }
}
#endif
