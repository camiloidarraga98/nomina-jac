import SwiftUI
import AppKit

@main @MainActor struct JACMacApp:App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var store=Self.makeStore()
    @StateObject private var connectivity=AgendaConnectivity()
    @Environment(\.scenePhase) private var phase
    @State private var section:MacSection = .payroll
    @FocusedValue(\.macRefresh) private var refreshAction
    var body:some Scene {
        Window("JAC Music",id:"jac-main") {
            Group {
                if Self.testing {Color.clear}
                else if let overview=store.overview {MacWorkspace(overview:overview,section:$section)}
                else if store.restoring {ProgressView("Conectando…").frame(maxWidth:.infinity,maxHeight:.infinity)}
                else if store.hasSavedSession {OfflineStartView()}
                else {LoginView().frame(maxWidth:560).frame(maxWidth:.infinity,maxHeight:.infinity)}
            }.environmentObject(store).tint(JACTheme.action).background(JACTheme.canvas)
                .frame(minWidth:1000,minHeight:700)
                .background(MacPrivacyShield())
                .task {
                    guard !Self.testing else{return};await store.restore()
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--uitest-payroll"),ProcessInfo.processInfo.arguments.contains("--uitest-compact-window") || ProcessInfo.processInfo.arguments.contains("--uitest-wide-window") {
                        await Task.yield()
                        if let window=NSApp.windows.first(where:{$0.isVisible && $0.canBecomeMain}) {
                            let compact=ProcessInfo.processInfo.arguments.contains("--uitest-compact-window")
                            window.setContentSize(NSSize(width:compact ? 1000:1240,height:compact ? 700:798))
                            window.center()
                        }
                    }
                    #endif
                    while !Task.isCancelled {do{try await Task.sleep(for:.seconds(30))}catch{return};if NSApp.isActive && store.hasSavedSession {try? await store.refreshAutomatically()}}
                }
                .onChange(of:phase){_,value in if value == .active && store.hasSavedSession && !Self.testing {Task{try? await store.refreshAutomatically()}}}
                .onChange(of:connectivity.connected){old,new in guard store.hasSavedSession && !Self.testing else{return};if new == false {store.client.beginOfflineRestore()};if old == false && new == true {Task{try? await store.refreshAutomatically()}}}
        }.defaultSize(width:1240,height:850).windowResizability(.contentMinSize)
            .commands {
                CommandGroup(replacing:.newItem) {}
                CommandMenu("JAC") {
                    ForEach(Array(MacSection.allCases.enumerated()),id:\.element) {index,item in
                        if let user=store.overview?.user,item.allowed(user) {Button(item.title){guard !NSApp.windows.contains(where:{$0.attachedSheet != nil}) else{return};section=item}.keyboardShortcut(KeyEquivalent(Character(String(index+1))),modifiers:.command)}
                    }
                    Divider()
                    if let user=store.overview?.user,user.isOwner,user.itinerariesOnly != true {
                        Button("Servicios conectados en la web…"){NSWorkspace.shared.open(PayrollClient.productionURL.appendingPathComponent("configuracion/conexiones"))}
                        Button("Autorización de Sheets en la web…"){NSWorkspace.shared.open(PayrollClient.productionURL.appendingPathComponent("crm"))}
                        Divider()
                    }
                    Button("Actualizar información"){if let refreshAction {refreshAction()} else {Task{try? await store.refresh()}}}.keyboardShortcut("r",modifiers:.command).disabled(!store.hasSavedSession || store.busy)
                }
            }
        Settings {NotificationSettingsView().environmentObject(store).frame(width:680,height:500)}
    }
    private static var testing:Bool {Bundle.allBundles.contains{$0.bundleURL.lastPathComponent == "JACMacTests.xctest"}}
    private static func makeStore()->PayrollStore {
        #if DEBUG
        let a=ProcessInfo.processInfo.arguments
        if testing || a.contains("--uitest-payroll"){return PayrollStore(client:UITestBackend.client(reader:a.contains("--uitest-reader"),conflict:a.contains("--uitest-conflict"),offline:a.contains("--uitest-offline"),persistentAgenda:a.contains("--uitest-agenda-cache"),resetAgenda:a.contains("--uitest-reset-agenda")))}
        #endif
        return PayrollStore()
    }
}
@MainActor final class MacAppDelegate:NSObject,NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification) {
        #if DEBUG
        let arguments=ProcessInfo.processInfo.arguments
        if arguments.contains("--uitest-payroll"),arguments.contains("--uitest-dark") {NSApp.appearance=NSAppearance(named:.darkAqua)}
        #endif
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
}
enum MacSection:String,CaseIterable,Identifiable {
    case payroll,agenda,itineraries,account,management,crm,alerts
    var id:String{rawValue}
    var title:String{switch self {case .payroll:"Quincena";case .agenda:"Agenda";case .itineraries:"Itinerarios";case .account:"Mi cuenta";case .management:"Configuración";case .crm:"CRM";case .alerts:"Alertas"}}
    var icon:String{switch self {case .payroll:"wallet.pass";case .agenda:"calendar.badge.clock";case .itineraries:"airplane";case .account:"person.crop.circle";case .management:"slider.horizontal.3";case .crm:"briefcase";case .alerts:"bell.badge"}}
    static let primary: [MacSection] = [.crm, .payroll, .agenda, .itineraries]
    static let personal: [MacSection] = [.account, .management]
    static func sidebar(for user:PayrollUser)->[MacSection] { (primary+personal).filter{$0.allowed(user)} }
    func allowed(_ user:PayrollUser)->Bool {switch self{case .payroll:user.itinerariesOnly != true;case .crm:user.isOwner && user.itinerariesOnly != true;default:true}}
}
private struct MacWorkspace:View {
    @EnvironmentObject private var store:PayrollStore
    let overview:PayrollOverview
    @Binding var section:MacSection
    private var selected:MacSection{section.allowed(overview.user) ? section:.itineraries}
    private var sidebarSelection: Binding<MacSection> {
        Binding(get:{section},set:{next in guard !NSApp.windows.contains(where:{$0.attachedSheet != nil}) else{return};section=next})
    }
    var body:some View {
        NavigationSplitView {
            VStack(spacing:0) {
                BrandView().frame(width:136).padding(.top,16).padding(.bottom,18)
                List(selection:sidebarSelection) {
                    Section("JAC Music") {
                        ForEach(MacSection.primary.filter{$0.allowed(overview.user)}) { item in sidebarRow(item) }
                    }
                    Section("Personal") {
                        ForEach(MacSection.personal) { item in sidebarRow(item) }
                    }
                }.listStyle(.sidebar)
                Divider().padding(.horizontal,16)
                HStack(spacing:10) {
                    Image(systemName:"person.crop.circle.fill").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment:.leading,spacing:4) {
                        Text(overview.user.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                        Label(store.isOffline ? "Copia sin conexión":"JAC Music",systemImage:store.isOffline ? "wifi.slash":"checkmark.shield").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength:0)
                }.padding(16)
            }.navigationSplitViewColumnWidth(min:210,ideal:235,max:290)
        } detail: {
            Group {
                if store.isAgendaOnly && selected != .agenda && selected != .account {
                    VStack(spacing:16) {
                        ContentUnavailableView("Esta sección todavía no está descargada",systemImage:"wifi.slash",description:Text("Puedes consultar tu Agenda guardada. Conéctate para descargar el resto de JAC."))
                        Button("Reintentar conexión"){Task{try? await store.refresh()}}.buttonStyle(.borderedProminent)
                    }
                } else {
                    switch selected {
                    case .payroll:PeriodsView(overview:overview)
                    case .agenda:CalendarView(user:overview.user,initialMonth:store.preferredAgendaMonth)
                    case .itineraries:NavigationStack{NoticesView(user:overview.user)}
                    case .account:NavigationStack{AccountView(user:overview.user)}
                    case .management:MacManagementView(user:overview.user)
                    case .crm:NavigationStack{MacCRMHomeView(client:store.client)}
                    case .alerts:NavigationStack{NoticesView(user:overview.user,kind:"alert")}
                    }
                }
            }.id(selected).toolbar {
                if selected != .crm && selected != .agenda {
                    ToolbarItem { Button {Task{try? await store.refresh()}} label:{Image(systemName:"arrow.clockwise")}.help("Actualizar información (⌘R)").disabled(store.busy) }
                }
            }
        }.onAppear{if !section.allowed(overview.user){section = .itineraries}}
    }
    private func sidebarRow(_ item:MacSection)->some View {
        Label(item.title,systemImage:item.icon).font(.body.weight(.medium)).padding(.vertical,4).tag(item).accessibilityIdentifier("mac.nav."+item.rawValue)
    }
}

// Covers every app window, including editor/document sheets, before deactivation.
// NSOpenPanel and authentication windows remain usable while JAC is active.
struct MacPrivacyShield:NSViewRepresentable {
    func makeNSView(context:Context)->PrivacyAnchor{PrivacyAnchor()}
    func updateNSView(_ view:PrivacyAnchor,context:Context){}
    static func dismantleNSView(_ view:PrivacyAnchor,coordinator:()){view.stop()}
}
final class PrivacyAnchor:NSView {
    private var observers:[NSObjectProtocol]=[]
    private var covers:[NSView]=[]
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();stop();guard window != nil else{return}
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.willResignActiveNotification,object:nil,queue:.main){[weak self]_ in MainActor.assumeIsolated{self?.conceal()}})
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main){[weak self]_ in MainActor.assumeIsolated{self?.reveal()}})
        if !NSApp.isActive {conceal()}
    }
    func conceal(){reveal();for window in NSApp.windows where window.isVisible && window.canBecomeKey {
        guard let content=window.contentView else{continue}
        let shade=NSHostingView(rootView:ZStack{JACTheme.canvas;BrandView().frame(width:220).accessibilityIdentifier("privacy.cover")});shade.frame=content.bounds;shade.autoresizingMask=[.width,.height];content.addSubview(shade,positioned:.above,relativeTo:nil);covers.append(shade)
    }}
    func reveal(){covers.forEach{$0.removeFromSuperview()};covers=[]}
    func stop(){observers.forEach{NotificationCenter.default.removeObserver($0)};observers=[];reveal()}
}
