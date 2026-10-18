import SwiftUI
import Combine
import PDFKit
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct CRMItem: Identifiable { let value:JSONValue;var id:String { value["id"].text } }
extension JSONValue { var crmItems:[CRMItem] { elements.map { CRMItem(value:$0) } }; var isNull:Bool { self == .null } }
enum CRMFields {
    static func money(_ value:Double)->String {value.formatted(.currency(code:"COP").precision(.fractionLength(value.rounded()==value ? 0:2)).locale(Locale(identifier:"es_CO")))}
    static let budgets=[("musicians","Músicos"),("technical","Técnica"),("drivers","Conductores y kilómetros"),("tickets","Tiquetes"),("hotels","Hoteles"),("food","Alimentación"),("other","Otros gastos")]
    static func matches(_ name:String,in contacts:[JSONValue],limit:Int=8) -> [JSONValue] { let q=name.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"es_CO")).trimmingCharacters(in:.whitespacesAndNewlines);return Array(contacts.filter { ($0["name"].text+" "+$0["company"].text).folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"es_CO")).contains(q) || q.isEmpty }.prefix(limit)) }
    static func showRecord(_ s:JSONValue) -> JSONValue { .object(["id":s["id"],"version":s["version"],"sale":s["sale"].isNull ? .number(0):s["sale"],"entrepreneur":s["entrepreneur"],"contactId":s["contactId"],"note":s["note"],"status":s["status"],"promotional":s["promotional"]]) }
    static func contactRecord(_ s:JSONValue) -> JSONValue { .object(Dictionary(uniqueKeysWithValues:["id","version","name","company","phone","email","city","note"].map { ($0,s[$0]) })) }
    static func blankContact() -> JSONValue { .object(["id":.string(UUID().uuidString.lowercased()),"version":.number(0),"name":.string(""),"company":.string(""),"phone":.string(""),"email":.string(""),"city":.string(""),"note":.string("")]) }
}
@MainActor final class CRMStore:ObservableObject {
    let client:PayrollClient
    @Published var feed:JSONValue = .null
    @Published var denied=false
    @Published var message:String?
    init(_ client:PayrollClient){ self.client=client }
    func cached(_ query:[String:String]) -> JSONValue? { client.cached(JSONValue.self,path:"api/crm",query:query.map { URLQueryItem(name:$0.key,value:$0.value) }) }
    func read(_ query:[String:String]) async throws -> JSONValue { do { return try await client.crm(query:query) } catch { reject(error);throw error } }
    func command(_ action:String,record:JSONValue? = nil,month:String? = nil) async throws -> JSONValue { do { return try await client.crmCommand(action,record:record,month:month) } catch { reject(error);throw error } }
    func reject(_ error:Error){ if let e=error as? APIError { switch e { case .forbidden,.unauthorized:denied=true;TemporaryDocuments.clear();default:break } };message=error.localizedDescription }
}
struct CRMHomeView:View {
    @EnvironmentObject private var store:PayrollStore
    @StateObject private var crm:CRMStore
    @State private var feed:JSONValue = .null
    @State private var section="shows"
    @State private var month=CalendarClock.month(Date())
    @State private var search=""
    @State private var editor:CRMEditorRequest?
    @State private var error:String?
    @State private var busy=false
    @State private var lastSync=Date.distantPast
    init(client:PayrollClient){ _crm=StateObject(wrappedValue:CRMStore(client)) }
    var body:some View {
        Group {
            if crm.denied || store.overview?.user.hasSection(.crm) != true { ContentUnavailableView("CRM no disponible",systemImage:"lock",description:Text(crm.message ?? "Solo administradores de JAC.")) }
            else { Group {
              if section == "contracts" { VStack(spacing:0) { sectionPicker.padding(.horizontal).padding(.vertical,10);CRMContractsHome() } }
              else { List {
                if let error { InlineError(message:error) }
                Section {
                    JACFeatureBanner(eyebrow:"JAC · CRM",title:"El show empieza aquí.",subtitle:"Ventas, abonos y preparación de cada fecha.",symbol:"briefcase",tone:.violet)
                    ViewThatFits(in:.horizontal) {
                        HStack(spacing:12) { quickPayment; moreActions }
                        VStack(spacing:12) { quickPayment; moreActions }
                    }.padding(.top,5)
                }.jacStandaloneRow()
                sectionPicker
                if section == "shows" { showList }
                else if section == "weekly" { CRMWeeklyView() }
                else { CRMContactsView() }
              } }
            }.jacSurface().navigationTitle(section == "contracts" ? "Contratos":"CRM").jacInlineTitle().jacConnectionStatus()
                .task { await load(sync:!store.isOffline);while !Task.isCancelled { do { try await Task.sleep(for:.seconds(30));if section != "contracts" {await load(sync:!store.isOffline && Date().timeIntervalSince(lastSync)>60)} } catch { break } } }
                .refreshable { await load(sync:!store.isOffline) }
                .sheet(item:$editor,onDismiss:{ Task { await load() } }) { CRMEditor(request:$0).environmentObject(crm) }
            }
        }.environmentObject(crm)
    }
    private var sectionPicker:some View {Picker("Sección",selection:$section) {Text("Shows").tag("shows");Text("Semana").tag("weekly");Text("Empresarios").tag("contacts");Text("Contratos").tag("contracts")}.pickerStyle(.segmented).accessibilityIdentifier("crm.sections")}
    private var quickPayment:some View {
        Button { editor=CRMEditorRequest(kind:.payment,record:.null,feed:feed) } label: { Label("Registrar abono",systemImage:"plus.circle").frame(maxWidth:.infinity) }
            .buttonStyle(JACPrimaryButtonStyle()).disabled(busy || store.isOffline || feed.isNull).accessibilityIdentifier("crm.quickPayment")
    }
    private var moreActions:some View {
        Menu {
            Button("Crear show") { editor=CRMEditorRequest(kind:.create,record:.null,feed:feed) }
            Button("Registrar abono") { editor=CRMEditorRequest(kind:.payment,record:.null,feed:feed) }
            Button("Actualizar shows de Calendar") { Task { await load(sync:true) } }
        } label: { Label("Más",systemImage:"ellipsis").frame(minWidth:48) }
            .buttonStyle(JACSecondaryButtonStyle(tone:.violet)).disabled(busy || store.isOffline || feed.isNull).accessibilityIdentifier("crm.add")
    }
    private var showList:some View {
        Group {
            Section { JACDatePicker("Desde el mes",selection:Binding(get:{ ReceiptParser.civilDate(month+"-01") ?? Date() },set:{ month=CalendarClock.month($0);Task { await load() } }),in:(ReceiptParser.civilDate(CalendarClock.month(Date())+"-01") ?? Date())...,displayedComponents:.date).disabled(busy).accessibilityIdentifier("crm.month")
                TextField("Buscar show o empresario",text:$search).accessibilityIdentifier("crm.search") }
            Section("Shows de hoy en adelante") {
                ForEach(feed["shows"].crmItems.filter { $0.value["status"].text != "ignored" && $0.value["showDate"].text >= BoardingClock.today() && (search.isEmpty || ($0.value["title"].text+" "+$0.value["entrepreneur"].text).localizedStandardContains(search)) }) { item in
                    NavigationLink { CRMShowView(id:item.id,contacts:feed["contacts"],feed:feed).environmentObject(crm) } label:{ CRMShowRow(show:item.value) }.accessibilityIdentifier("crm.show."+item.id)
                }
                if feed["shows"].elements.isEmpty { Text(feed.isNull ? "Consultando…":"No hay shows próximos en este rango.").foregroundStyle(.secondary) }
            }
            Section("Google Sheets") { Text(feed["sheets"]["ready"].flag ? "Control de abonos JAC conectado":"Configura la conexión desde el CRM web.").font(.footnote)
                if let url=URL(string:feed["sheets"]["url"].text),url.scheme == "https",url.host == "docs.google.com" { Link("Abrir hoja de abonos",destination:url) }
                Button("Sincronizar abonos pendientes") { Task { do { _ = try await crm.command("syncSheets");await load() } catch { self.error=error.localizedDescription } } }.disabled(store.isOffline || !feed["sheets"]["ready"].flag)
            }
        }
    }
    private func load(sync:Bool=false) async {
        guard !busy,!crm.denied else { return };busy=true;defer { busy=false }
        let q=["month":month];if feed.isNull,let saved=crm.cached(q){feed=saved;crm.feed=saved}
        do { if sync { lastSync=Date();for offset in 0..<6 { let date=CalendarClock.calendar.date(byAdding:.month,value:offset,to:ReceiptParser.civilDate(month+"-01") ?? Date())!;_ = try await crm.command("syncCalendar",month:CalendarClock.month(date)) } };let value=try await crm.read(q);feed=value;crm.feed=value;error=nil } catch { self.error=store.reportReadFailure(error) }
    }
}
struct CRMShowRow:View {
    let show:JSONValue
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top,spacing:12) {
                JACIcon(symbol:"music.mic",tone:.violet)
                VStack(alignment:.leading,spacing:6) { Text(show["title"].text).font(.system(.headline,design:.rounded));Text(show["showDate"].text).font(.caption).foregroundStyle(JACTone.violet.color) }
            }
            if !show["entrepreneur"].text.isEmpty { Text(show["entrepreneur"].text).font(.caption).foregroundStyle(.secondary) }
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4) { Text("VENTA").font(.caption2.weight(.semibold)).foregroundStyle(.secondary);Text(show["sale"].isNull ? "Sin precio":CRMFields.money(show["sale"].number)).font(.subheadline.weight(.semibold)) }
                Spacer(minLength:12)
                if !show["balance"].isNull { VStack(alignment:.trailing,spacing:4) { Text("PENDIENTE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary);Text(CRMFields.money(show["balance"].number)).font(.subheadline.weight(.semibold)).foregroundStyle(JACTone.violet.color) } }
            }.monospacedDigit()
        }.padding(.vertical,10)
    }
}
struct CRMEditorRequest:Identifiable {
    enum Kind { case price,create,payment,contact,contracts,void }
    let id=UUID();let kind:Kind;let record:JSONValue;var feed:JSONValue = .null
    var title:String { switch kind { case .price:return "Precio y empresario";case .create:return "Crear show";case .payment:return "Registrar abono";case .contact:return "Empresario";case .contracts:return "Contratos y documentos";case .void:return "Anular abono" } }
}
struct CRMShowView:View {
    @EnvironmentObject private var store:PayrollStore
    @EnvironmentObject private var crm:CRMStore
    let id:String;var contacts:JSONValue = .array([]);var feed:JSONValue = .null;var initialTab="account"
    @State private var planData:JSONValue = .null
    @State private var planDraft:JSONValue = .null
    @State private var detail:JSONValue = .null
    @State private var tab="account"
    @State private var error:String?
    @State private var busy=false
    @State private var editor:CRMEditorRequest?
    @State private var deletion:JSONValue?
    @State private var deleteTitle=""
    @State private var confirmDelete=false
    var body:some View {
        VStack(spacing:0) {
            Picker("Sección del show",selection:$tab) { Text("Cuenta").tag("account");Text("Rentabilidad").tag("profit");Text("Preparación").tag("tasks") }
                .pickerStyle(.segmented).accessibilityIdentifier("crm.show.sections").padding(.horizontal,18).padding(.vertical,10)
            List {
                if let error { InlineError(message:error) }
                if tab == "account" { account }
                else { CRMPlanView(id:id,show:detail["show"],tab:tab,data:$planData,draft:$planDraft) }
            }.scrollContentBackground(.hidden).refreshable { await load() }
        }.jacSurface()
            .navigationTitle(detail["show"]["title"].text.isEmpty ? "Show":detail["show"]["title"].text).jacInlineTitle().jacRefreshCommand { Task { await load() } }
            .task { tab=initialTab;await load();while !Task.isCancelled {do{try await Task.sleep(for:.seconds(30));await load()}catch{break}} }
            .sheet(item:$editor,onDismiss:{ Task { await load() } }) { CRMEditor(request:$0).environmentObject(crm) }
            .onChange(of:crm.denied) {_,denied in if denied {editor=nil;detail = .null;planData = .null;planDraft = .null;confirmDelete=false}}
            .confirmationDialog(deleteTitle,isPresented:$confirmDelete,titleVisibility:.visible) { Button("Eliminar evento",role:.destructive) { Task { await remove() } };Button("Cancelar",role:.cancel) {} } message:{ Text("Se quitará de Calendar, CRM y Agenda. Abonos y comprobantes se conservan como historial.") }
    }
    private var account:some View { Group {
        Section("Cuenta del show") { LabeledContent("Fecha",value:detail["show"]["showDate"].text);CRMMetric("Venta",detail["show"]["sale"]);CRMMetric("Abonos",detail["show"]["paid"]);CRMMetric("Saldo",detail["show"]["balance"])
            if !detail["show"]["entrepreneur"].text.isEmpty { Text(detail["show"]["entrepreneur"].text) }
            if !detail["show"]["note"].text.isEmpty { Text(detail["show"]["note"].text).font(.footnote) }
            if writable { Button("Editar precio y empresario") { editor=CRMEditorRequest(kind:.price,record:detail["show"],feed:.object(["contacts":contacts.elements.isEmpty ? crm.feed["contacts"]:contacts])) }.accessibilityIdentifier("crm.price")
                Button { editor=CRMEditorRequest(kind:.payment,record:detail["show"],feed:feed.isNull ? crm.feed:feed) } label:{ Label("Registrar abono",systemImage:"plus.circle").frame(maxWidth:.infinity) }.buttonStyle(JACPrimaryButtonStyle()).disabled(detail["show"]["sale"].isNull).accessibilityIdentifier("crm.payment") }
            else if !detail.isNull { Text("Historial · evento eliminado o pendiente de eliminación").font(.footnote) }
        }
        Section("Abonos y comprobantes") { ForEach(detail["payments"].crmItems) { item in VStack(alignment:.leading,spacing:9) {
            Text(CRMFields.money(item.value["amount"].number)).font(.headline);Text(item.value["paymentDate"].text+" · "+(item.value["status"].text == "recorded" ? "Registrado":"Anulado")).font(.caption);if !item.value["note"].text.isEmpty { Text(item.value["note"].text) }
            CRMFilesView(owner:item.id,files:item.value["files"],version:Int(item.value["version"].number),contact:false)
            if writable,item.value["status"].text == "recorded" { Button("Anular abono",role:.destructive) { editor=CRMEditorRequest(kind:.void,record:item.value) } }
        }.padding(.vertical,6) };if detail["payments"].elements.isEmpty { Text("Sin abonos registrados").foregroundStyle(.secondary) } }
        if detail["show"]["sourceState"].text != "deleted",!detail.isNull { Section { Button("Eliminar evento",role:.destructive) { Task { await prepareRemoval() } }.disabled(store.isOffline || busy).accessibilityIdentifier("crm.delete") } }
    } }
    private var writable:Bool { !store.isOffline && !detail.isNull && !["deleted","deleting"].contains(detail["show"]["sourceState"].text) }
    private func load() async { let q=["id":id];if detail.isNull,let saved=crm.cached(q){detail=saved};do { detail=try await crm.read(q);error=nil } catch { self.error=store.reportReadFailure(error) } }
    private func prepareRemoval() async { busy=true;defer { busy=false };do { let d=try await crm.command("prepareDeleteShow",record:.object(["id":.string(id),"version":detail["show"]["version"]]));deletion=d["record"];deleteTitle="¿Eliminar \(d["event"]["title"].text.isEmpty ? detail["show"]["title"].text:d["event"]["title"].text)?";confirmDelete=true } catch { self.error=error.localizedDescription } }
    private func remove() async { guard let deletion else{return};busy=true;defer{busy=false};do { _ = try await crm.command("deleteShow",record:deletion);await load() } catch { await load();self.error=error.localizedDescription } }
}
struct CRMMetric:View {
    let title:String;let value:JSONValue
    init(_ title:String,_ value:JSONValue){self.title=title;self.value=value}
    var body:some View { LabeledContent(title,value:value.isNull ? "Pendiente":CRMFields.money(value.number)) }
}
struct CRMContactInput:View {
    @Binding var name:String;@Binding var contactID:String
    let contacts:[JSONValue]
    var onFocusChanged:(Bool)->Void = {_ in}
    @FocusState private var focused:Bool
    var body:some View { VStack(alignment:.leading,spacing:10) {
        TextField("Empresario",text:Binding(get:{name},set:{name=$0;contactID=""})).textInputAutocapitalization(.words).focused($focused).accessibilityIdentifier("crm.entrepreneur")
        if focused { let matches=CRMFields.matches(name,in:contacts);ScrollView {VStack(alignment:.leading,spacing:4) {ForEach(matches.map { CRMItem(value:$0) }) { item in Button { name=item.value["name"].text;contactID=item.id;focused=false } label:{ VStack(alignment:.leading,spacing:4) { Text(item.value["name"].text);if !item.value["company"].text.isEmpty { Text(item.value["company"].text).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth:.infinity,alignment:.leading).padding(10).background(JACTheme.card,in:RoundedRectangle(cornerRadius:9)).foregroundStyle(JACTheme.ink) }.buttonStyle(.plain).accessibilityIdentifier("crm.suggestion."+item.id) }}}.frame(height:CGFloat(min(matches.count*66,198))) }
        if !contactID.isEmpty,let contact=contacts.first(where:{$0["id"].text==contactID}),!contact["company"].text.isEmpty { Label(contact["company"].text,systemImage:"checkmark").font(.caption).foregroundStyle(.secondary) }
    }.id("crm.contact.row").onChange(of:focused){_,value in onFocusChanged(value)} }
}
enum CRMMoney {
    static func edit(_ input:String) -> (text:String,value:Double)? {
        let raw=input.replacingOccurrences(of:".",with:"")
        guard raw.range(of:"^[0-9]*(,[0-9]{0,2})?$",options:.regularExpression) != nil else{return nil}
        if raw.isEmpty{return("",0)}
        let pieces=raw.components(separatedBy:","),integer=Double(pieces[0].isEmpty ? "0":pieces[0]) ?? 0
        guard let value=Double((pieces[0].isEmpty ? "0":pieces[0])+(pieces.count==2 ? "."+pieces[1]:"")),value.isFinite,value<=1e12 else{return nil}
        return(PayrollFormat.number(integer)+(pieces.count==2 ? ","+pieces[1]:""),value)
    }
}
struct CRMAmountField:View {
    let title:String;@Binding var value:Double
    @State private var text=""
    @FocusState private var focus:Bool
    var body:some View { TextField(title,text:Binding(get:{text},set:{ input in if let next=CRMMoney.edit(input){text=next.text;value=next.value} })).keyboardType(.decimalPad).focused($focus).accessibilityIdentifier("crm.amount."+title)
        .onAppear { text=value == 0 ? "":PayrollFormat.number(value) }.onChange(of:value){_,n in if !focus {text=n == 0 ? "":PayrollFormat.number(n)} }
    }
}
struct CRMEditor:View {
    @EnvironmentObject private var store:PayrollStore
    @EnvironmentObject private var crm:CRMStore
    @Environment(\.dismiss) private var dismiss
    let request:CRMEditorRequest
    @State private var draft:JSONValue = .null
    @State private var attempt:JSONValue?
    @State private var files:[NoticeUpload]=[]
    @State private var importing=false
    @State private var busy=false
    @State private var loaded=false
    @State private var withPayment=false
    @State private var allDay=true
    @State private var date=Date()
    @State private var paymentDate=Date()
    @State private var startTime=Date()
    @State private var endTime=Date()
    @State private var showID=""
    @State private var name=""
    @State private var contactID=""
    @State private var reason=""
    @State private var error:String?
    @State private var sale:Double=0
    @State private var paymentAmount:Double=0
    @State private var contactFocused=false
    @State private var requestID=UUID().uuidString.lowercased()
    private var locked:Bool { busy || attempt != nil }
    var body:some View {
        NavigationStack {
            ScrollViewReader {proxy in Form {
                if let error { InlineError(message:error) }
                if attempt != nil { Text("Se conservan los datos enviados. Reintenta la misma solicitud para evitar duplicados.").font(.footnote) }
                fields
                #if os(iOS)
                Section { Button(busy ? "Guardando…":attempt != nil ? "Reintentar guardado":"Guardar") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || importing || store.isOffline).accessibilityIdentifier("crm.editor.save") }
                #endif
            }.scrollDismissesKeyboard(.never).onChange(of:contactFocused){_,focused in if focused {withAnimation{proxy.scrollTo("crm.contact.row",anchor:.top)}}}.onReceive(NotificationCenter.default.publisher(for:JACPlatform.keyboardShown)){_ in if contactFocused{withAnimation{proxy.scrollTo("crm.contact.row",anchor:.top)}}}.jacSurface().navigationTitle(request.title).jacInlineTitle()
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cerrar") { dismiss() }.disabled(busy || importing) }
#if os(iOS)
ToolbarItemGroup(placement:.keyboard){Spacer();Button("Listo"){JACPlatform.endEditing()}.accessibilityIdentifier("crm.keyboard.done")}
#else
ToolbarItem(placement:.confirmationAction) {
    Button(busy ? "Guardando…":attempt != nil ? "Reintentar guardado":"Guardar") { Task { await save() } }
        .buttonStyle(.borderedProminent).tint(JACTheme.primary).disabled(busy || importing || store.isOffline).accessibilityIdentifier("crm.editor.save")
}
#endif
 }
                .onAppear { setup() }
            }
        }.interactiveDismissDisabled(busy || importing || attempt != nil)
    }
    @ViewBuilder private var fields:some View {
        switch request.kind {
        case .price:
            Section("Precio y empresario") { priceFields }
            Section { boolField("Show promocional","promotional");Picker("Estado",selection:text("status")){Text("Activo").tag("active");Text("Ignorar: no es un show").tag("ignored")} }.disabled(locked)
        case .create:
            Section("Evento compartido en Agenda") {
                TextField("Nombre del show o municipio",text:text("title")).accessibilityIdentifier("crm.create.title")
                JACDatePicker("Día del evento",selection:$date,in:CalendarClock.calendar.startOfDay(for:Date())...,displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone)
                Toggle("Todo el día",isOn:$allDay)
                if !allDay { JACDatePicker("Hora de inicio",selection:$startTime,displayedComponents:.hourAndMinute).environment(\.timeZone,CalendarClock.calendar.timeZone);JACDatePicker("Hora de fin",selection:$endTime,displayedComponents:.hourAndMinute).environment(\.timeZone,CalendarClock.calendar.timeZone) }
                TextField("Lugar",text:text("location"));TextField("Descripción compartida",text:text("description"),axis:.vertical).lineLimit(2...5)
            }.disabled(locked)
            Section("Datos privados del CRM") { priceFields;boolField("Show promocional","promotional");Text("El precio, empresario y abonos no se envían a Calendar.").font(.footnote).foregroundStyle(.secondary) }.disabled(locked)
            Section { Toggle("Registrar primer abono",isOn:$withPayment).accessibilityIdentifier("crm.firstPayment") }.disabled(locked || importing)
            if withPayment { paymentFields }
        case .payment:
            if request.record.isNull { Section("Show") { Picker("Show del abono",selection:$showID) { Text("Selecciona un show").tag("");ForEach(request.feed["shows"].crmItems.filter{ !$0.value["sale"].isNull && $0.value["status"].text == "active" && !["deleted","deleting"].contains($0.value["sourceState"].text) }) { Text($0.value["showDate"].text+" · "+$0.value["title"].text).tag($0.id) } }.accessibilityIdentifier("crm.payment.show") }.disabled(locked) }
            else { Section { Text(request.record["title"].text).font(.headline) } }
            paymentFields
        case .contact:
            Section("Empresario") { TextField("Nombre",text:text("name")).accessibilityIdentifier("crm.contact.name");TextField("Empresa",text:text("company"));TextField("Teléfono",text:text("phone")).keyboardType(.phonePad);TextField("Correo",text:text("email")).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress);TextField("Ciudad",text:text("city"));TextField("Observaciones",text:text("note"),axis:.vertical).lineLimit(2...5) }.disabled(locked)
        case .contracts:
            TravelAttachmentsPicker(files:$files,importing:$importing).disabled(locked)
        case .void:
            Section { Text("Anular "+CRMFields.money(request.record["amount"].number)+" del "+request.record["paymentDate"].text);TextField("Motivo de anulación",text:$reason,axis:.vertical).lineLimit(2...4);Text("El comprobante se conserva como historial.").font(.footnote) }.disabled(locked)
        }
    }
    private var priceFields:some View { Group {
        CRMAmountField(title:"Valor de venta (COP)",value:$sale)
        CRMContactInput(name:$name,contactID:$contactID,contacts:request.feed["contacts"].elements,onFocusChanged:{contactFocused=$0})
        TextField("Observaciones internas",text:text("note"),axis:.vertical).lineLimit(2...5)
    }.disabled(locked) }
    private var paymentFields:some View { Group {
        Section("Abono") { CRMAmountField(title:"Valor del abono (COP)",value:$paymentAmount);JACDatePicker("Fecha del abono",selection:$paymentDate,displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone);TextField("Observación del abono",text:text("paymentNote"),axis:.vertical).lineLimit(2...4) }.disabled(locked)
        TravelAttachmentsPicker(files:$files,importing:$importing).disabled(locked)
    } }
    private func text(_ key:String) -> Binding<String> { Binding(get:{draft[key].text},set:{draft[key] = .string($0)}) }
    private func boolField(_ title:String,_ key:String) -> some View { Toggle(title,isOn:Binding(get:{draft[key].flag},set:{draft[key] = .bool($0)})) }
    private func setup(){guard !loaded else{return};loaded=true
        switch request.kind {
        case .price:draft=CRMFields.showRecord(request.record);sale=request.record["sale"].number;name=request.record["entrepreneur"].text;contactID=request.record["contactId"].text
        case .contact:draft=CRMFields.contactRecord(request.record)
        case .create:draft = .object(["title":.string(""),"location":.string(""),"description":.string(""),"note":.string(""),"promotional":.bool(false)]);date=CalendarClock.calendar.startOfDay(for:Date());startTime=CalendarClock.calendar.date(bySettingHour:19,minute:0,second:0,of:date)!;endTime=CalendarClock.calendar.date(bySettingHour:21,minute:0,second:0,of:date)!
        default:draft = .object([:]);showID=request.record["id"].text
        }
    }
    private func payload() throws -> (String,JSONValue) {
        switch request.kind {
        case .price:var r=draft;r["sale"] = .number(sale);r["entrepreneur"] = .string(name);r["contactId"] = contactID.isEmpty ? .null:.string(contactID);return("updateShow",r)
        case .contact:guard !draft["name"].text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw APIError.invalid("Escribe el nombre del empresario.") };return("saveContact",draft)
        case .contracts:return("addContactFiles",.object(["id":.string(requestID),"contactId":request.record["id"],"version":request.record["version"],"files":try store.client.crmUploads(files)]))
        case .void:guard reason.trimmingCharacters(in:.whitespacesAndNewlines).count>=2 else { throw APIError.invalid("Escribe el motivo de anulación.") };return("voidPayment",.object(["id":request.record["id"],"version":request.record["version"],"reason":.string(reason)]))
        case .payment:guard !showID.isEmpty else {throw APIError.invalid("Selecciona un show.")};return("addPayment",try payment(showID:showID))
        case .create:
            guard !draft["title"].text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw APIError.invalid("Escribe el nombre del show.") }
            let day=BoardingClock.today(date),calendar=CalendarClock.calendar
            func instant(_ time:Date) -> Date { let c=calendar.dateComponents([.hour,.minute],from:time);return calendar.date(bySettingHour:c.hour!,minute:c.minute!,second:0,of:date)! }
            let start=instant(startTime),end=instant(endTime)
            guard allDay || end>start else { throw APIError.invalid("La hora de fin debe ser posterior al inicio en el mismo día.") }
            let event:JSONValue = .object(["title":draft["title"],"start":.string(allDay ? day:ISO8601DateFormatter().string(from:start)),"end":.string(allDay ? BoardingClock.today(calendar.date(byAdding:.day,value:1,to:date)!):ISO8601DateFormatter().string(from:end)),"allDay":.bool(allDay),"location":draft["location"],"description":draft["description"]])
            var r:JSONValue = .object(["id":.string(requestID),"revision":request.feed["calendar"]["revision"],"event":event,"sale":.number(sale),"entrepreneur":.string(name),"note":draft["note"],"promotional":draft["promotional"]]);if !contactID.isEmpty {r["contactId"] = .string(contactID)}
            if withPayment { let p=try payment(showID:"");r["firstPayment"] = .object(["amount":p["amount"],"paymentDate":p["paymentDate"],"note":p["note"],"files":p["files"]]) };return("createShow",r)
        }
    }
    private func payment(showID:String) throws -> JSONValue { guard paymentAmount>0 else {throw APIError.invalid("Registra un valor de abono positivo.")};return .object(["id":.string(requestID),"showId":.string(showID),"amount":.number(paymentAmount),"paymentDate":.string(BoardingClock.today(paymentDate)),"note":draft["paymentNote"].isNull ? .string(""):draft["paymentNote"],"files":try store.client.crmUploads(files)]) }
    private func save() async {
        guard !busy,!store.isOffline else{return};busy=true;defer{busy=false};error=nil
        do { let action:String,record:JSONValue;if let attempt {action=attempt["action"].text;record=attempt["record"]} else { (action,record)=try payload();attempt = .object(["action":.string(action),"record":record]) };_ = try await crm.command(action,record:record);dismiss() }
        catch { if let e=error as? APIError { switch e {case .invalid:attempt=nil;case .conflict:if request.kind != .create { attempt=nil };default:break} };self.error=error.localizedDescription }
    }
}
struct CRMFilesView:View {
    @EnvironmentObject private var store:PayrollStore
    @EnvironmentObject private var crm:CRMStore
    let owner:String;let files:JSONValue;let version:Int;let contact:Bool
    @State private var document:ExportedDocument?
    @State private var previous:ExportedDocument?
    @State private var busy=false
    @State private var error:String?
    var body:some View { Group {
        if let error { InlineError(message:error) }
        ForEach(files.crmItems) { item in Button { Task { busy=true;defer {busy=false};do {let file=try item.value.decoded(NoticeAttachment.self);let result=try await store.client.crmFile(owner:owner,file:file,version:version,contact:contact);previous=result;document=result} catch {crm.reject(error);self.error=store.reportReadFailure(error)} } } label:{ Label(item.value["filename"].text,systemImage:"doc.text") }.disabled(busy).accessibilityIdentifier("crm.file."+item.id) }
    }.onChange(of:crm.denied){_,denied in if denied {document=nil}}.sheet(item:$document,onDismiss:{if let previous {TemporaryDocuments.remove(previous);self.previous=nil}}) { file in NavigationStack { DocumentPreview(url:file.url).privacySensitive().ignoresSafeArea(edges:.bottom).navigationTitle("Documento").jacInlineTitle().toolbar {ToolbarItem(placement:.confirmationAction){Button("Listo"){document=nil}.accessibilityIdentifier("contracts.preview.close")}} } } }
}
struct CRMPlanView:View {
    @EnvironmentObject private var store:PayrollStore
    @EnvironmentObject private var crm:CRMStore
    let id:String,show:JSONValue,tab:String
    @Binding var data:JSONValue
    @Binding var draft:JSONValue
    @State private var busy=false
    @State private var error:String?
    @State private var link=""
    @State private var notice:String?
    var body:some View { Group {
        if let error { InlineError(message:error) };if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
        if !draft.isNull,data["version"] != draft["version"] {Text("Hay cambios de preparación o presupuesto. Recarga antes de guardar; tu borrador se conserva.").font(.footnote)}
        if draft.isNull { Section { Text("Consultando…") } }
        else if tab == "profit" { profit }
        else { preparation }
        Section { Button(tab == "profit" ? "Guardar presupuesto":"Guardar preparación") { Task { await save() } }.disabled(busy || store.isOffline || data["readOnly"].flag || draft.isNull).accessibilityIdentifier("crm.plan.save")
            Button("Recargar y descartar borrador") { Task { await load(discard:true) } }.disabled(busy) }
    }.task { await load();while !Task.isCancelled {do{try await Task.sleep(for:.seconds(30));if !busy {await load()}}catch{break}} } }
    private var profit:some View { Group {
        Section("Rentabilidad del show") { CRMMetric("Presupuesto",draft["budget"].isNull ? .null:.number(CRMFields.budgets.reduce(0){$0+draft["budget"][$1.0].number}));CRMMetric("Costos registrados",data["profit"]["actual"]["cost"]);CRMMetric("Resultado registrado",data["profit"]["actual"]["profit"])
            if !data["profit"]["issue"].text.isEmpty {Text(data["profit"]["issue"].text).font(.footnote)} }
        if !data["profit"]["actual"].isNull { Section(data["profit"]["actual"]["closed"].flag ? "Nómina cerrada · datos conservados":"Nómina abierta · costos en construcción") {
            CRMMetric("Venta en nómina",data["profit"]["actual"]["sale"])
            ForEach([("musicians","Músicos"),("technical","Técnica"),("drivers","Conductores y kilómetros"),("expenses","Gastos directos"),("variance","Diferencia frente al presupuesto")],id:\.0) { key,title in CRMMetric(title,data["profit"]["actual"][key]) }
            if data["profit"]["actual"]["sale"] != show["sale"] {Text("El precio actual del CRM difiere de la venta de nómina. Se conserva el valor de esa nómina.").font(.footnote)}
            if data["profit"]["actual"]["promotional"].flag {Text("Promocional: sus costos cuentan para rentabilidad y se excluyen de la comisión.").font(.footnote)}
            CRMMetric("Aporte a la base de comisión",data["profit"]["actual"]["commissionBase"])
            CRMMetric("Comisión de toda la quincena",data["profit"]["actual"]["periodCommission"])
            Text(data["profit"]["actual"]["start"].text+" a "+data["profit"]["actual"]["end"].text+". Mínimo cero por quincena; cálculo revisable, sin pago automático.").font(.footnote).foregroundStyle(.secondary)
        } }
        else if !data["profit"]["choices"].elements.isEmpty { Section("Vincular nómina existente") {
            Picker("Show de nómina",selection:$link) {Text("Selecciona un show").tag("");ForEach(Array(data["profit"]["choices"].elements.enumerated()),id:\.offset) {i,c in Text(c["label"].text).tag(String(i))} }
            Button("Vincular sin modificar nómina") { Task {guard let i=Int(link),data["profit"]["choices"].elements.indices.contains(i) else{return};let c=data["profit"]["choices"].elements[i];busy=true;defer{busy=false};do{_ = try await crm.command("linkPayroll",record:.object(["showId":.string(id),"version":data["version"],"periodId":c["periodId"],"payrollShowId":c["showId"]]));await load(discard:true)}catch{self.error=error.localizedDescription} } }.disabled(link.isEmpty || busy || store.isOffline || data["readOnly"].flag)
        } }
        Section("Presupuesto estimado") {
            Toggle("Definir presupuesto",isOn:Binding(get:{!draft["budget"].isNull},set:{ enabled in draft["budget"] = enabled ? .object(Dictionary(uniqueKeysWithValues:CRMFields.budgets.map{($0.0,.number(0))})):.null })).accessibilityIdentifier("crm.budget.enabled")
            if !draft["budget"].isNull { ForEach(CRMFields.budgets,id:\.0) {key,title in VStack(alignment:.leading,spacing:6){Text(title).font(.caption).foregroundStyle(.secondary);CRMAmountField(title:title,value:Binding(get:{draft["budget"][key].number},set:{draft["budget"][key] = .number($0)}))} };CRMMetric("Resultado estimado",show["sale"].isNull ? .null:.number(show["sale"].number-CRMFields.budgets.reduce(0){$0+draft["budget"][$1.0].number})) }
            Text("El presupuesto se compara con los costos; no modifica ni se suma a los gastos de nómina.").font(.footnote).foregroundStyle(.secondary)
        }.disabled(busy || store.isOffline || data["readOnly"].flag)
    } }
    private var preparation:some View { Group {
        Section("Anticipo recibido") { Label(data["advance"]["done"].flag ? "Listo":"Pendiente",systemImage:data["advance"]["done"].flag ? "checkmark.circle":"clock");CRMMetric("Abonos vigentes",data["advance"]["amount"]);Text("Se actualiza desde los pagos registrados.").font(.caption).foregroundStyle(.secondary) }
        ForEach(Array(draft["tasks"].elements.enumerated()),id:\.offset) { index,task in
            Section(task["title"].text) {
                if !["contract","hotel","transport","itinerary"].contains(task["id"].text) { TextField("Nombre de tarea",text:taskText(index,"title")) }
                Picker("Estado",selection:taskText(index,"status")){Text("Pendiente").tag("pending");Text("Listo").tag("done");Text("No aplica").tag("na")}.accessibilityIdentifier("crm.task."+task["id"].text)
                TextField("Responsable",text:taskText(index,"responsible"));TextField("Observación",text:taskText(index,"note"),axis:.vertical).lineLimit(2...4)
                Toggle("Fecha límite",isOn:Binding(get:{!task["dueDate"].text.isEmpty},set:{setTask(index,"dueDate",.string($0 ? show["showDate"].text:""))}))
                if !task["dueDate"].text.isEmpty {JACDatePicker("Día límite",selection:Binding(get:{ReceiptParser.civilDate(task["dueDate"].text) ?? Date()},set:{setTask(index,"dueDate",.string(BoardingClock.today($0)))}),displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone)}
                if !["contract","hotel","transport","itinerary"].contains(task["id"].text) {Button("Quitar tarea",role:.destructive){draft["tasks"] = .array(draft["tasks"].elements.filter{$0["id"] != task["id"]})}}
            }.disabled(busy || store.isOffline || data["readOnly"].flag)
        }
        Section { Button("Agregar tarea") { var tasks=draft["tasks"].elements;tasks.append(.object(["id":.string(UUID().uuidString.lowercased()),"title":.string("Nueva tarea"),"status":.string("pending"),"responsible":.string(""),"dueDate":.string(""),"note":.string("")]));draft["tasks"] = .array(tasks) }.disabled(busy || store.isOffline || data["readOnly"].flag || draft["tasks"].elements.count>=30) }
    } }
    private func setTask(_ i:Int,_ k:String,_ v:JSONValue){var tasks=draft["tasks"].elements;guard tasks.indices.contains(i) else{return};tasks[i][k]=v;draft["tasks"] = .array(tasks)}
    private func taskText(_ i:Int,_ k:String) -> Binding<String>{Binding(get:{draft["tasks"].elements.indices.contains(i) ? draft["tasks"].elements[i][k].text:""},set:{setTask(i,k,.string($0))})}
    private func load(discard:Bool=false) async { let q=["view":"workspace","id":id];if data.isNull,let saved=crm.cached(q){data=saved;if draft.isNull {draft=saved}};do {data=try await crm.read(q);if draft.isNull || discard {draft=data};error=nil} catch{self.error=store.reportReadFailure(error)} }
    private func save() async {busy=true;defer{busy=false};do{_ = try await crm.command("savePlan",record:.object(["showId":.string(id),"version":draft["version"],"budget":draft["budget"],"tasks":draft["tasks"]]));await load(discard:true);notice="Presupuesto y preparación guardados."}catch{self.error=error.localizedDescription}}
}
struct CRMWeeklyView:View {
    @EnvironmentObject private var store:PayrollStore
    @EnvironmentObject private var crm:CRMStore
    @State private var day=Date()
    @State private var data:JSONValue = .null
    @State private var error:String?
    var body:some View { Group {
        Section { HStack {Button {change(-7)} label:{Image(systemName:"chevron.left")}.accessibilityLabel("Semana anterior");Spacer();Button("Esta semana"){day=Date();Task{await load()}};Spacer();Button{change(7)}label:{Image(systemName:"chevron.right")}.accessibilityLabel("Semana siguiente")};Text(data["week"]["from"].text+" a "+data["week"]["to"].text+" · Colombia").font(.caption) }
        if let error {InlineError(message:error)}
        Section("Resumen semanal") {LabeledContent("Próximos shows",value:String(data["shows"].elements.count));CRMMetric("Por cobrar",data["pending"]);CRMMetric("Abonos recibidos",data["received"]);CRMMetric("Gastos por fecha de registro",data["expensesRegistered"]);CRMMetric("Costos de shows de la semana",data["costs"]);Text("\(Int(data["unpriced"].number)) shows sin precio · \(Int(data["unknownCosts"].number)) sin costos completos vinculados").font(.caption).foregroundStyle(.secondary)}
        Section("Próximos shows") {ForEach(data["shows"].crmItems){s in NavigationLink{CRMShowView(id:s.id).environmentObject(crm)}label:{CRMShowRow(show:s.value)}}}
        Section("Tareas por resolver") {ForEach(Array(data["tasks"].elements.enumerated()),id:\.offset){_,t in NavigationLink {CRMShowView(id:t["showId"].text,initialTab:"tasks").environmentObject(crm)} label:{VStack(alignment:.leading,spacing:5){Text(t["title"].text).font(.headline);Text(t["showTitle"].text);Text(t["dueDate"].text+(t["overdue"].flag ? " · Atrasada":"")+" · "+t["responsible"].text).font(.caption).foregroundStyle(.secondary)}}};if data["tasks"].elements.isEmpty{Text("Sin tareas pendientes para esta semana.").foregroundStyle(.secondary)}}
    }.task {await load();while !Task.isCancelled {do{try await Task.sleep(for:.seconds(30));await load()}catch{break}}} }
    private func change(_ n:Int){day=CalendarClock.calendar.date(byAdding:.day,value:n,to:day)!;Task{await load()}}
    private func load() async {let q=["view":"weekly","week":BoardingClock.today(day)];if let saved=crm.cached(q){data=saved};do{data=try await crm.read(q);error=nil}catch{self.error=store.reportReadFailure(error)}}
}
struct CRMContactsView:View {
    @EnvironmentObject private var store:PayrollStore
    @EnvironmentObject private var crm:CRMStore
    @State private var data:JSONValue = .null
    @State private var search=""
    @State private var error:String?
    @State private var editor:CRMEditorRequest?
    var body:some View {Group{
        Section {TextField("Buscar empresario",text:$search).accessibilityIdentifier("crm.contacts.search");Button("Nuevo empresario"){editor=CRMEditorRequest(kind:.contact,record:CRMFields.blankContact())}.disabled(store.isOffline).accessibilityIdentifier("crm.contacts.new")}
        if let error {InlineError(message:error)}
        Section("Empresarios") {ForEach(CRMFields.matches(search,in:data["contacts"].elements,limit:1001).map{CRMItem(value:$0)}){c in NavigationLink{CRMContactView(id:c.id).environmentObject(crm)}label:{VStack(alignment:.leading,spacing:6){Text(c.value["name"].text).font(.headline);Text(c.value["company"].text).font(.caption).foregroundStyle(.secondary)}}.accessibilityIdentifier("crm.contact."+c.id)}}
    }.task{await load()}.sheet(item:$editor,onDismiss:{Task{await load()}}){CRMEditor(request:$0).environmentObject(crm)} }
    private func load() async {let q=["view":"contacts"];if let saved=crm.cached(q){data=saved};do{data=try await crm.read(q);error=nil}catch{self.error=store.reportReadFailure(error)}}
}
struct CRMContactView:View {
    @EnvironmentObject private var store:PayrollStore
    @EnvironmentObject private var crm:CRMStore
    let id:String
    @State private var data:JSONValue = .null
    @State private var error:String?
    @State private var editor:CRMEditorRequest?
    var body:some View {List{
        if let error{InlineError(message:error)}
        Section("Empresario") {ForEach([("company","Empresa"),("phone","Teléfono"),("email","Correo"),("city","Ciudad")],id:\.0){k,t in LabeledContent(t,value:data["contact"][k].text.isEmpty ? "Sin registrar":data["contact"][k].text)};if !data["contact"]["note"].text.isEmpty{Text(data["contact"]["note"].text)};Button("Editar empresario"){editor=CRMEditorRequest(kind:.contact,record:data["contact"])}.disabled(store.isOffline || data.isNull).accessibilityIdentifier("crm.contact.edit")}
        Section("Shows y cuentas") {ForEach(data["shows"].crmItems){s in NavigationLink{CRMShowView(id:s.id).environmentObject(crm)}label:{CRMShowRow(show:s.value)}}}
        Section("Contratos y documentos") {CRMFilesView(owner:id,files:data["files"],version:Int(data["contact"]["version"].number),contact:true);Button("Adjuntar documentos"){editor=CRMEditorRequest(kind:.contracts,record:data["contact"])}.disabled(store.isOffline || data.isNull).accessibilityIdentifier("crm.contact.files")}
    }.onChange(of:crm.denied){_,denied in if denied {editor=nil;data = .null}}.jacSurface().navigationTitle(data["contact"]["name"].text.isEmpty ? "Empresario":data["contact"]["name"].text).jacInlineTitle().task{await load()}.refreshable{await load()}.sheet(item:$editor,onDismiss:{Task{await load()}}){CRMEditor(request:$0).environmentObject(crm)} }
    private func load() async {let q=["view":"contact","id":id];if data.isNull,let saved=crm.cached(q){data=saved};do{data=try await crm.read(q);error=nil}catch{self.error=store.reportReadFailure(error)}}
}

// Contracts reuse the private server template; the phone only keeps an editable
// draft in memory. Generated PDFs enter the private server archive. The RUT
// itself never leaves this device or enters the cache.
struct ContractDraft: Sendable {
    var company="",nit="",representative="",identity=""
    var eventDate=CalendarClock.day(CalendarClock.calendar.date(byAdding:.day,value:14,to:Date()) ?? Date())
    var venue="",municipality="",department="",showTime="23:00"
    var price:Double=0,deposited:Double=0
    var halfDeadline=CalendarClock.day(Date())
    var finalDate:String { CalendarClock.date(eventDate).flatMap { CalendarClock.calendar.date(byAdding:.day,value:-5,to:$0) }.map(CalendarClock.day) ?? "" }
    var filename:String {
        let town=municipality.precomposedStringWithCanonicalMapping.replacingOccurrences(of:"[^\\p{L}\\p{N} .-]",with:"",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
        let f=DateFormatter();f.locale=Locale(identifier:"es_CO");f.calendar=CalendarClock.calendar;f.timeZone=CalendarClock.calendar.timeZone;f.dateFormat="d 'de' MMMM yyyy"
        return "Contrato JAC - \(town) - \(CalendarClock.date(eventDate).map {f.string(from:$0)} ?? eventDate).pdf"
    }
    func payload() throws -> JSONValue {
        let fields=[("company",company,"la razón social",100),("nit",nit,"el NIT",25),("representative",representative,"el representante legal",90),("identity",identity,"la cédula",25),("venue",venue,"el sitio del evento",100),("municipality",municipality,"el municipio",60),("department",department,"el departamento",40)]
        var values:[String:JSONValue]=[:]
        for (key,value,label,limit) in fields {
            let text=value.trimmingCharacters(in:.whitespacesAndNewlines).precomposedStringWithCanonicalMapping
            guard !text.isEmpty else {throw APIError.invalid("Completa \(label).")}
            guard text.count <= limit else {throw APIError.invalid("\(label.capitalized): máximo \(limit) caracteres.")}
            guard text.range(of:"^[\\u0020-\\u007e\\u00a0-\\u00ff–—‘’“”€]+$",options:.regularExpression) != nil else {throw APIError.invalid("\(label.capitalized): usa letras, números y signos habituales en español.")}
            values[key] = .string(text)
        }
        for value in [eventDate,halfDeadline] { guard let date=CalendarClock.date(value),CalendarClock.day(date)==value,value >= "1900-01-01",value <= "2199-12-31" else {throw APIError.invalid("Introduce una fecha válida.")} }
        guard showTime.range(of:"^([01]\\d|2[0-3]):[0-5]\\d$",options:.regularExpression) != nil else {throw APIError.invalid("Introduce la hora del show.")}
        guard price.isFinite,price>0,price<=1e12,price.rounded()==price else {throw APIError.invalid("Introduce el precio en pesos enteros, mayor que cero y hasta un billón.")}
        guard deposited.isFinite,deposited>=0,deposited.rounded()==deposited,deposited<=price/2 else {throw APIError.invalid("El abono debe estar en pesos enteros y no superar el 50% del contrato.")}
        guard halfDeadline<=finalDate else {throw APIError.invalid("El plazo para completar el 50% debe ser anterior o igual al pago final, cinco días antes del show.")}
        for (key,value) in [("eventDate",eventDate),("halfDeadline",halfDeadline),("showTime",showTime)] { values[key] = .string(value) }
        values["price"] = .number(price);values["deposited"] = .number(deposited)
        return .object(values)
    }
    mutating func apply(_ rut:RutExtraction) {
        company=rut.company ?? "";nit=rut.nit ?? ""
        if let index=rut.automaticRepresentative { let person=rut.representatives[index];representative=person.name;identity=person.identity }
        else {representative="";identity=""}
    }
}

struct CRMContractSelection:Identifiable { let value:JSONValue;var id:String {value["id"].text} }

struct CRMContractsHome:View {
    @EnvironmentObject private var store:PayrollStore
    @EnvironmentObject private var crm:CRMStore
    @State private var contracts:[JSONValue]=[]
    @State private var next:Int?
    @State private var busy=false
    @State private var creating=false
    @State private var assigning:CRMContractSelection?
    @State private var document:ExportedDocument?
    @State private var ownedDocument:ExportedDocument?
    @State private var error:String?
    @State private var active=true
    @State private var operation:Task<Void,Never>?
    var body:some View {
        List {
            Section {
                Button {creating=true} label:{Label("Crear contrato",systemImage:"plus")}.buttonStyle(JACPrimaryButtonStyle()).disabled(store.isOffline).accessibilityIdentifier("contracts.create")
                Text("Los contratos generados se guardan aquí y se pueden asignar a un show del CRM.").font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Section {InlineError(message:error);Button("Reintentar"){Task{await load()}}} }
            Section("Contratos guardados") {
                if contracts.isEmpty {if busy {ProgressView("Consultando contratos…")} else {Text("Aquí aparecerán los contratos que generes a partir de ahora.").foregroundStyle(.secondary)}}
                ForEach(contracts.map{CRMContractSelection(value:$0)}) { item in
                    let row=item.value
                    VStack(alignment:.leading,spacing:10) {
                        Label(row["municipality"].text+" · "+CalendarClock.dayLabel(row["eventDate"].text),systemImage:"doc.text").font(.headline)
                        Text(row["company"].text).font(.subheadline)
                        Text(CRMFields.money(row["price"].number)).font(.subheadline).foregroundStyle(JACTheme.action)
                        Text(row["showTitle"].text.isEmpty ? (row["showId"].isNull ? "Sin show asignado":"Show retirado del CRM"):"Show: "+row["showTitle"].text).font(.caption).foregroundStyle(.secondary)
                        HStack {Button("Abrir PDF"){open(row)}.accessibilityIdentifier("contracts.open."+row["id"].text);Spacer();Button("Asignar show"){assigning=CRMContractSelection(value:row)}.disabled(store.isOffline).accessibilityIdentifier("contracts.assign."+row["id"].text)}.buttonStyle(.bordered)
                    }.padding(.vertical,8)
                }
                if next != nil {Button("Ver más contratos"){Task{await load(more:true)}}.disabled(busy)}
            }
        }.jacSurface().privacySensitive().task{active=true;await load()}.refreshable{await load()}
            .onDisappear{active=false;operation?.cancel();clearDocument()}
            .onChange(of:crm.denied){_,denied in if denied {contracts=[];document=nil;creating=false;assigning=nil;clearDocument()} }
            .sheet(isPresented:$creating,onDismiss:{Task{await load()}}){NavigationStack {CRMContractForm().navigationTitle("Crear contrato").jacInlineTitle().toolbar{ToolbarItem(placement:.jacLeading){Button("Listo"){creating=false}.accessibilityIdentifier("contracts.form.close")}}}.environmentObject(crm)
                #if os(macOS)
                .frame(minWidth:620,minHeight:700)
                #endif
            }
            .sheet(item:$assigning,onDismiss:{Task{await load()}}){CRMContractAssignment(contract:$0.value).environmentObject(crm)
                #if os(macOS)
                .frame(minWidth:520,minHeight:400)
                #endif
            }
            .sheet(item:$document,onDismiss:clearDocument){file in NavigationStack {DocumentPreview(url:file.url).privacySensitive().navigationTitle("Contrato JAC").jacInlineTitle().toolbar{ToolbarItem(placement:.jacLeading){Button("Listo"){document=nil}.accessibilityIdentifier("contracts.preview.close")};ToolbarItem(placement:.jacTrailing){ShareLink(item:file.url){Image(systemName:"square.and.arrow.up")}.accessibilityLabel("Compartir contrato")}}}}
    }
    private func load(more:Bool=false) async {
        guard !busy,!crm.denied else{return};if !more,contracts.isEmpty,let saved=store.client.cached(JSONValue.self,path:"api/mobile/contracts",query:[URLQueryItem(name:"offset",value:"0")]) {contracts=saved["contracts"].elements;next=saved["next"].isNull ? nil:Int(saved["next"].number)};busy=true;defer{busy=false}
        do{let data=try await store.client.contractArchive(query:["offset":String(more ? (next ?? 0):0)]);guard active,!Task.isCancelled else{return};contracts=more ? contracts+data["contracts"].elements:data["contracts"].elements;next=data["next"].isNull ? nil:Int(data["next"].number);error=nil}
        catch{guard active,!RutParser.cancelled(error) else{return};crm.reject(error);if crm.denied {contracts=[]};self.error=error.localizedDescription}
    }
    private func open(_ row:JSONValue){operation?.cancel();operation=Task{do{let file=try await store.client.archivedContract(id:row["id"].text,filename:row["filename"].text);guard active,!Task.isCancelled else{TemporaryDocuments.remove(file);return};clearDocument();ownedDocument=file;document=file}catch{if active,!RutParser.cancelled(error){crm.reject(error);self.error=error.localizedDescription}}}}
    private func clearDocument(){document=nil;if let ownedDocument {TemporaryDocuments.remove(ownedDocument);self.ownedDocument=nil}}
}

struct CRMContractShowPicker:View {
    @EnvironmentObject private var store:PayrollStore
    @State private var query=""
    @State private var shows:[JSONValue]=[]
    @State private var next:Int?
    @State private var error:String?
    @Binding var selection:String
    var body:some View {Group {
        TextField("Buscar show por nombre o fecha",text:$query).accessibilityIdentifier("contracts.show.search")
        Picker("Show del CRM",selection:$selection){Text("Sin asignar").tag("");if !selection.isEmpty && !shows.contains(where:{$0["id"].text==selection}) {Text("Show seleccionado").tag(selection)};ForEach(shows.map{CRMContractSelection(value:$0)}){item in let s=item.value;Text(s["title"].text+" · "+CalendarClock.dayLabel(s["showDate"].text)).tag(s["id"].text)}}.accessibilityIdentifier("contracts.show.picker")
        if next != nil {Button("Más shows"){Task{await load(more:true)}}}
        if let error {Text(error).font(.footnote).foregroundStyle(.red)}
    }.task(id:query){do{try await Task.sleep(for:.milliseconds(250));await load()}catch{}}
    }
    private func load(more:Bool=false) async {do{let data=try await store.client.contractArchive(query:["view":"shows","q":query,"offset":String(more ? (next ?? 0):0)]);guard !Task.isCancelled else{return};shows=more ? shows+data["shows"].elements:data["shows"].elements;next=data["next"].isNull ? nil:Int(data["next"].number);error=nil}catch{if !RutParser.cancelled(error){self.error=error.localizedDescription}}}
}

struct CRMContractAssignment:View {
    @EnvironmentObject private var store:PayrollStore
    @EnvironmentObject private var crm:CRMStore
    @Environment(\.dismiss) private var dismiss
    let contract:JSONValue
    @State private var showId=""
    @State private var busy=false
    @State private var error:String?
    var body:some View {NavigationStack {Form {Section {Text(contract["filename"].text).font(.headline);CRMContractShowPicker(selection:$showId);Text("La asignación no cambia el PDF ni los valores del show.").font(.footnote).foregroundStyle(.secondary)};if let error {InlineError(message:error)}}.disabled(busy).navigationTitle("Asignar show").jacInlineTitle().toolbar{ToolbarItem(placement:.jacLeading){Button("Cancelar"){dismiss()}.disabled(busy)};ToolbarItem(placement:.jacTrailing){Button("Guardar"){Task{await save()}}.disabled(busy || store.isOffline).accessibilityIdentifier("contracts.assign.save")}}.privacySensitive().onAppear{showId=contract["showId"].text}}}
    private func save() async {busy=true;defer{busy=false};do{try await store.client.linkContract(id:contract["id"].text,showId:showId.isEmpty ? nil:showId,version:Int(contract["version"].number));dismiss()}catch{crm.reject(error);self.error=error.localizedDescription}}
}

struct CRMContractForm:View {
    @EnvironmentObject private var store:PayrollStore
    @EnvironmentObject private var crm:CRMStore
    @State private var draft=ContractDraft()
    @State private var showId=""
    @State private var requestID=UUID().uuidString
    @State private var priorPayload=""
    @State private var importing=false
    @State private var busy=false
    @State private var error:String?
    @State private var reading=false
    @State private var rut:RutExtraction?
    @State private var selectedRepresentative=""
    @State private var document:ExportedDocument?
    @State private var ownedDocument:ExportedDocument?
    @State private var operation:Task<Void,Never>?
    @State private var active=true
    private let dateRange=CalendarClock.date("1900-01-01")!...CalendarClock.date("2199-12-31")!
    var body:some View {
        Form {
            Section {
                Button { importing=true } label: { HStack {Label(reading ? "Leyendo RUT…":"Subir RUT",systemImage:"doc.badge.plus");Spacer();if reading {ProgressView()} } }.buttonStyle(JACPrimaryButtonStyle()).disabled(reading || busy).accessibilityIdentifier("contracts.rut.upload")
                Text("Completa los datos del contratante desde un RUT PDF. También puedes escribirlos manualmente y modificar cualquier campo.").font(.footnote).foregroundStyle(.secondary)
                if let rut {
                    Text("RUT leído. Revisa los datos antes de generar el contrato.").font(.footnote).foregroundStyle(JACTheme.primary).accessibilityIdentifier("contracts.rut.ready")
                    ForEach(rut.warnings,id:\.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                    if rut.representatives.count>1 || rut.representatives.filter({$0.kind == .principal}).count != 1 {
                        Picker("Representante que firmará",selection:$selectedRepresentative) {
                            Text("Seleccionar o escribir manualmente").tag("")
                            ForEach(Array(rut.representatives.enumerated()),id:\.offset) { index,person in Text(person.name+" · "+person.kind.title).tag(String(index)).disabled(person.documentType != "Cédula de ciudadanía") }
                        }.accessibilityIdentifier("contracts.rut.representative")
                    }
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--uitest-payroll") { Button("Usar RUT ficticio") { useRut(RutExtraction(company:"EMPRESA FICTICIA JAC SAS",nit:"900000001-0",representatives:[RutRepresentative(name:"ANA MARÍA PRUEBA GÓMEZ",identity:"100000001",kind:.principal,documentType:"Cédula de ciudadanía")],warnings:[])) }.accessibilityIdentifier("contracts.rut.fixture") }
                #endif
            }
            if let error { Section {InlineError(message:error).accessibilityIdentifier("contracts.error")} }
            Section("Contratante") {
                TextField("Razón social",text:$draft.company).accessibilityIdentifier("contracts.company")
                TextField("NIT con dígito de verificación",text:$draft.nit).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("contracts.nit")
                TextField("Representante legal",text:$draft.representative).accessibilityIdentifier("contracts.representative")
                TextField("Cédula de ciudadanía",text:$draft.identity).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("contracts.identity")
            }.disabled(busy)
            Section("Show vinculado (opcional)") { CRMContractShowPicker(selection:$showId) }.disabled(busy)
            Section("Presentación") {
                JACDatePicker("Día del evento",selection:dateBinding("eventDate"),in:dateRange,displayedComponents:.date).accessibilityIdentifier("contracts.eventDate")
                TextField("Sitio exacto del evento",text:$draft.venue).accessibilityIdentifier("contracts.venue")
                TextField("Municipio",text:$draft.municipality).accessibilityIdentifier("contracts.municipality")
                TextField("Departamento",text:$draft.department).accessibilityIdentifier("contracts.department")
                JACDatePicker("Hora del show",selection:timeBinding,displayedComponents:.hourAndMinute).accessibilityIdentifier("contracts.showTime")
            }.disabled(busy)
            Section("Precio y forma de pago") {
                CRMAmountField(title:"Precio del contrato (COP)",value:$draft.price)
                CRMAmountField(title:"Consignado a la fecha (COP)",value:$draft.deposited)
                JACDatePicker("Plazo para completar el 50%",selection:dateBinding("halfDeadline"),in:dateRange,displayedComponents:.date).accessibilityIdentifier("contracts.halfDeadline")
                if draft.price>0 {
                    LabeledContent("Primer 50%",value:CRMFields.money(draft.price/2))
                    LabeledContent("Falta para ese 50%",value:CRMFields.money(max(0,draft.price/2-draft.deposited)))
                    LabeledContent("Pago final · 50%",value:CRMFields.money(draft.price/2))
                    LabeledContent("Pago final antes del",value:CalendarClock.dayLabel(draft.finalDate))
                }
            }.disabled(busy)
            Section {
                Button { generate() } label:{ HStack {Label(busy ? "Generando PDF…":"Crear contrato PDF",systemImage:"doc.text");Spacer();if busy {ProgressView()} } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || reading || store.isOffline).accessibilityIdentifier("contracts.generate")
                Text("El PDF se guarda en Contratos. Conserva la plantilla de JAC. Los importes se escriben en letras y números; el pago final es el 50%, cinco días antes del show.").font(.footnote).foregroundStyle(.secondary)
            }
        }.jacSurface().privacySensitive()
            .toolbar {
                #if os(iOS)
                ToolbarItemGroup(placement:.keyboard){Spacer();Button("Listo"){JACPlatform.endEditing()}.accessibilityIdentifier("crm.keyboard.done")}
                #endif
            }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.pdf],allowsMultipleSelection:false) { result in
                switch result {case .success(let urls):if let url=urls.first {readRut(url)};case .failure(let failure):if !RutParser.cancelled(failure) {error=failure.localizedDescription}}
            }
            .onChange(of:selectedRepresentative) {_,value in
                guard let rut,let index=Int(value),rut.representatives.indices.contains(index) else {return}
                let person=rut.representatives[index]
                guard person.documentType == "Cédula de ciudadanía" else {return}
                draft.representative=person.name;draft.identity=person.identity
            }
            .sheet(item:$document,onDismiss:clearDocument) { file in NavigationStack {
                DocumentPreview(url:file.url).privacySensitive().ignoresSafeArea(edges:.bottom).navigationTitle("Contrato JAC").jacInlineTitle()
                    .toolbar {ToolbarItem(placement:.jacLeading){Button("Listo"){document=nil}.accessibilityIdentifier("contracts.preview.close")};ToolbarItem(placement:.jacTrailing){ShareLink(item:file.url){Image(systemName:"square.and.arrow.up")}.accessibilityLabel("Compartir contrato").accessibilityIdentifier("contracts.share")}}
            } }
            .onAppear {active=true}
            .onDisappear {active=false;operation?.cancel();operation=nil;clearDocument()}
    }
    private func dateBinding(_ key:String)->Binding<Date> { Binding(get:{CalendarClock.date(key == "eventDate" ? draft.eventDate:draft.halfDeadline) ?? Date()},set:{if key == "eventDate" {draft.eventDate=CalendarClock.day($0)} else {draft.halfDeadline=CalendarClock.day($0)}}) }
    private var timeBinding:Binding<Date> { Binding(get:{let parts=draft.showTime.split(separator:":").compactMap{Int($0)};return CalendarClock.calendar.date(bySettingHour:parts.first ?? 23,minute:parts.last ?? 0,second:0,of:Date()) ?? Date()},set:{let c=CalendarClock.calendar.dateComponents([.hour,.minute],from:$0);draft.showTime=String(format:"%02d:%02d",c.hour ?? 23,c.minute ?? 0)}) }
    private func useRut(_ result:RutExtraction) {
        rut=result;draft.apply(result);error=nil
        selectedRepresentative=result.automaticRepresentative.map(String.init) ?? ""
    }
    private func readRut(_ url:URL) {
        reading=true;error=nil
        operation?.cancel();operation=Task {
            let scoped=url.startAccessingSecurityScopedResource();defer {if scoped {url.stopAccessingSecurityScopedResource()};reading=false}
            do {
                let worker=Task.detached(priority:.userInitiated){try RutParser.read(url)}
                let result=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                guard active,!Task.isCancelled else{return};useRut(result)
            } catch {if active,!RutParser.cancelled(error){self.error=error.localizedDescription}}
        }
    }
    private func generate() {
        JACPlatform.endEditing();busy=true;error=nil;operation?.cancel()
        operation=Task {
            defer{busy=false}
            do {let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let payload=String(decoding:try encoder.encode(draft.payload()),as:UTF8.self)+showId;if payload != priorPayload {requestID=UUID().uuidString;priorPayload=payload};let next=try await store.client.createContract(draft,id:requestID,showId:showId.isEmpty ? nil:showId);guard active,!Task.isCancelled else {TemporaryDocuments.remove(next);return};clearDocument();ownedDocument=next;document=next}
            catch {if active,!RutParser.cancelled(error){crm.reject(error);self.error=error.localizedDescription}}
        }
    }
    private func clearDocument() {document=nil;if let ownedDocument {TemporaryDocuments.remove(ownedDocument);self.ownedDocument=nil}}
}

struct RutRepresentative:Equatable,Sendable {
    enum Kind:String,Sendable {case principal,suplente,otro;var title:String {switch self {case .principal:"Principal";case .suplente:"Suplente";case .otro:"Otra representación"}}}
    let name:String,identity:String,kind:Kind,documentType:String
}
struct RutExtraction:Sendable {
    var company:String?,nit:String?;var representatives:[RutRepresentative]=[];var warnings:[String]=[]
    var automaticRepresentative:Int? {
        let principals=representatives.indices.filter{representatives[$0].kind == .principal}
        guard principals.count == 1,let index=principals.first else{return nil}
        let person=representatives[index]
        guard person.documentType == "Cédula de ciudadanía",!person.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,person.identity.range(of:"^[0-9]+$",options:.regularExpression) != nil,!warnings.contains(where:{$0.contains("nombre o identificación incompletos")}) else{return nil}
        return index
    }
}
struct RutTextItem:Sendable {let text:String,x:Double,y:Double,width:Double,height:Double}
struct RutPageLayout:Sendable {let width:Double,height:Double,items:[RutTextItem]}

enum RutParser {
    private struct Line {var y:Double,height:Double,items:[RutTextItem],text="",starts:[Int]=[]}
    private struct Anchor {let x:Double,y:Double,height:Double}
    static func cancelled(_ error:Error)->Bool {error is CancellationError || ((error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled)}
    private static func plain(_ s:String)->String {s.folding(options:.diacriticInsensitive,locale:Locale(identifier:"es_CO")).lowercased()}
    private static func tidy(_ s:String)->String {s.replacingOccurrences(of:"[\\u0000-\\u001f\\u007f]",with:" ",options:.regularExpression).replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)}
    private static func matches(_ pattern:String,_ text:String)->[NSTextCheckingResult] {guard let r=try? NSRegularExpression(pattern:pattern) else{return []};return r.matches(in:text,range:NSRange(location:0,length:(text as NSString).length))}
    static func read(_ url:URL) throws -> RutExtraction {
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size>0,size<=10*1024*1024 else {throw APIError.invalid("Selecciona un RUT en PDF de hasta 10 MB.")}
        let bytes=try Data(contentsOf:url,options:.mappedIfSafe)
        guard bytes.starts(with:Data("%PDF-".utf8)),let document=PDFDocument(data:bytes),!document.isLocked,document.pageCount>0,document.pageCount<=50 else {throw APIError.invalid("Selecciona un RUT PDF válido, sin contraseña y con un máximo de 50 páginas.")}
        return try extract(layouts(document))
    }
    static func layouts(_ document:PDFDocument) throws -> [RutPageLayout] {
        var pages:[RutPageLayout]=[]
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page=document.page(at:index),page.rotation%360 == 0 else {throw APIError.invalid("El RUT tiene páginas rotadas. Usa una copia vertical o completa los datos manualmente.")}
            let box=page.bounds(for:.mediaBox),text=(page.string ?? "") as NSString
            guard text.length<=300000 else {throw APIError.invalid("El RUT contiene demasiado texto para leerlo con seguridad.")}
            var items:[RutTextItem]=[]
            for (offset,match) in matches("\\S+",text as String).enumerated() {
                if offset%100==0 {try Task.checkCancellation()}
                guard items.count<30000 else {throw APIError.invalid("El RUT contiene demasiado texto para leerlo con seguridad.")}
                guard let selection=page.selection(for:match.range) else {continue}
                let bounds=selection.bounds(for:page)
                guard !bounds.isEmpty,!bounds.isNull else {continue}
                items.append(RutTextItem(text:text.substring(with:match.range),x:bounds.minX-box.minX,y:box.maxY-bounds.maxY,width:bounds.width,height:bounds.height))
            }
            pages.append(RutPageLayout(width:box.width,height:box.height,items:items))
        }
        return pages
    }
    private static func lines(_ page:RutPageLayout)->[Line] {
        var lines:[Line]=[]
        for item in page.items.sorted(by:{$0.y == $1.y ? $0.x<$1.x:$0.y<$1.y}) where !tidy(item.text).isEmpty {
            if let index=lines.lastIndex(where:{abs($0.y-item.y)<=3.5}) {lines[index].items.append(item);lines[index].height=max(lines[index].height,item.height)}
            else {lines.append(Line(y:item.y,height:item.height,items:[item]))}
        }
        for index in lines.indices {
            lines[index].items.sort{$0.x<$1.x}
            for item in lines[index].items {lines[index].starts.append((lines[index].text as NSString).length);lines[index].text += plain(tidy(item.text))+" "}
        }
        return lines
    }
    private static func anchors(_ lines:[Line],_ number:Int,_ caption:String)->[Anchor] {
        var result:[Anchor]=[]
        for line in lines {
            for match in matches("(?:^|\\s)\(number)\\s*\\.\\s*\(caption)",line.text) {
                let matched=(line.text as NSString).substring(with:match.range),at=match.range.location+(matched.hasPrefix(" ") ? 1:0)
                let index=line.starts.lastIndex(where:{$0<=at}) ?? 0,item=line.items[index]
                let offset=max(0,at-line.starts[index]),length=max(1,(plain(tidy(item.text)) as NSString).length)
                result.append(Anchor(x:item.x+item.width*min(1,Double(offset)/Double(length)),y:line.y,height:line.height))
            }
        }
        return result
    }
    private static func near(_ all:[Anchor],_ y:Double)->Anchor? {all.first{abs($0.y-y)<=4}}
    private static func below(_ all:[Anchor],_ start:Double,_ end:Double)->Anchor? {all.first{$0.y>start+4 && $0.y<end}}
    private static func cell(_ page:RutPageLayout,_ anchor:Anchor,_ right:Double,_ bottom:Double,_ left:Double?=nil)->String {
        let selected=page.items.filter {item in let center=item.x+item.width/2;return center >= (left ?? anchor.x-3) && center<right-1 && item.y>anchor.y+anchor.height+0.3 && item.y<bottom-1}
        return tidy(lines(RutPageLayout(width:page.width,height:page.height,items:selected)).map{$0.items.map(\.text).joined(separator:" ")}.joined(separator:" "))
    }
    private static func digits(_ value:String)->String? {guard !value.isEmpty,value.range(of:"^[0-9.\\s]+$",options:.regularExpression) != nil else{return nil};return value.replacingOccurrences(of:"[.\\s]",with:"",options:.regularExpression)}
    private static func checkDigit(_ nit:String)->Int {let weights=[71,67,59,53,47,43,41,37,29,23,19,17,13,7,3],value=String(repeating:"0",count:max(0,15-nit.count))+nit;let remainder=zip(value,weights).reduce(0){$0+(Int(String($1.0)) ?? 0)*$1.1}%11;return remainder>1 ? 11-remainder:remainder}
    static func extract(_ input:[RutPageLayout]) throws -> RutExtraction {
        guard !input.isEmpty,input.count<=50 else {throw APIError.invalid("Selecciona un RUT DIAN válido.")}
        var pages:[RutPageLayout]=[]
        for page in input {
            guard page.width.isFinite,page.height.isFinite,page.width>0,page.height>0,page.items.count<=30000 else {throw APIError.invalid("No se pudo leer la estructura del RUT.")}
            let sx=612/page.width,sy=792/page.height
            let items=page.items.filter{$0.text.count<=5000 && [$0.x,$0.y,$0.width,$0.height].allSatisfy(\.isFinite) && $0.width>=0 && $0.height>0}.map{RutTextItem(text:tidy($0.text),x:$0.x*sx,y:$0.y*sy,width:$0.width*sx,height:$0.height*sy)}
            pages.append(RutPageLayout(width:612,height:792,items:items))
        }
        let layouts=pages.map{($0,lines($0))}
        let identification=layouts.filter {_,lines in
            let text=lines.map(\.text).joined(separator:" ")
            return !matches("\\bdian\\b",text).isEmpty && !anchors(lines,5,"numero de identificacion tributaria").isEmpty && !anchors(lines,6,"dv\\b").isEmpty && !anchors(lines,24,"tipo de contribuyente").isEmpty && !anchors(lines,35,"razon social").isEmpty && (!anchors(lines,41,"direccion principal").isEmpty || !matches("responsabilidades,? calidades",text).isEmpty)
        }
        guard !identification.isEmpty else {throw APIError.invalid("No se reconoce un RUT DIAN con texto seleccionable. Revisa el archivo o completa los datos manualmente.")}
        var result=RutExtraction(),companies=Set<String>(),nits=Set<String>(),completeNits=Set<String>()
        for (page,lines) in identification {
            let label=anchors(lines,35,"razon social")[0],next=below(anchors(lines,36,"nombre comercial"),label.y,label.y+35)
            let company=cell(page,label,590,next?.y ?? label.y+24);if !company.isEmpty{companies.insert(company)}
        }
        guard companies.count<=1 else {throw APIError.invalid("El archivo contiene razones sociales distintas. Selecciona un solo RUT.")}
        result.company=companies.first
        if result.company==nil {result.warnings.append("No se encontró la razón social en la casilla 35. Complétala manualmente.")}
        for (page,lines) in layouts {
            guard let label=anchors(lines,5,"numero de identificacion tributaria").first,let dv=near(anchors(lines,6,"dv\\b"),label.y),dv.x>label.x else {continue}
            let end=near(anchors(lines,12,"direccion seccional"),label.y)?.x ?? dv.x+20,divider=dv.x+3
            let base=digits(cell(page,label,divider+1,label.y+24)),check=digits(cell(page,dv,end,label.y+24,divider))
            if let base,base.count>=5,base.count<=15 {nits.insert(base);if let check,check.count==1{completeNits.insert(base+"-"+check)}}
        }
        guard nits.count<=1,completeNits.count<=1 else {throw APIError.invalid("El archivo contiene NIT distintos. Selecciona un solo RUT.")}
        result.nit=completeNits.first ?? nits.first
        if let nit=result.nit {let parts=nit.split(separator:"-");if parts.count==1 {result.warnings.append("Falta el dígito de verificación del NIT. Revísalo antes de generar el contrato.")} else if Int(parts[1]) != checkDigit(String(parts[0])) {result.warnings.append("El dígito de verificación no coincide con el NIT leído. Revisa ambos datos; no se han corregido automáticamente.")}}
        else {result.warnings.append("No se pudo leer el NIT de las casillas 5 y 6. Complétalo manualmente.")}
        for (page,lines) in layouts {
            let rows=anchors(lines,98,"representacion")
            for (index,row) in rows.enumerated() {
                let end=index+1<rows.count ? rows[index+1].y:row.y+96
                guard let date=near(anchors(lines,99,"fecha inicio ejercicio representacion"),row.y),let type=below(anchors(lines,100,"tipo de documento"),row.y,end),let identity=near(anchors(lines,101,"numero de identificacion"),type.y),let firstSurname=below(anchors(lines,104,"primer apellido"),row.y,end),let secondSurname=near(anchors(lines,105,"segundo apellido"),firstSurname.y),let firstName=near(anchors(lines,106,"primer nombre"),firstSurname.y),let otherNames=near(anchors(lines,107,"otros nombres"),firstSurname.y) else {result.warnings.append("Una fila de representación tiene una estructura incompleta; revisa sus datos manualmente.");continue}
                let role=cell(page,row,date.x,type.y),documentRaw=cell(page,type,identity.x,firstSurname.y)
                let identityRight=near(anchors(lines,102,"dv\\b"),type.y)?.x ?? identity.x+260,identityRaw=cell(page,identity,identityRight,firstSurname.y)
                let bottom=below(anchors(lines,108,"numero de identificacion tributaria"),firstSurname.y,end)?.y ?? firstSurname.y+24
                let surnames=[cell(page,firstSurname,secondSurname.x,bottom),cell(page,secondSurname,firstName.x,bottom)],names=[cell(page,firstName,otherNames.x,bottom),cell(page,otherNames,590,bottom)]
                guard [role,documentRaw,identityRaw]+names+surnames != Array(repeating:"",count:7) else {continue}
                let name=tidy((names+surnames).filter{!$0.isEmpty}.joined(separator:" "))
                let codeMatch=matches("(?:^|\\s)((?:\\d\\s*){2})$",documentRaw).first
                let code=codeMatch.map{(documentRaw as NSString).substring(with:$0.range(at:1)).replacingOccurrences(of:"\\s",with:"",options:.regularExpression)}
                let documentLabel=tidy(documentRaw.replacingOccurrences(of:"(?:^|\\s)(?:\\d\\s*){2}$",with:"",options:.regularExpression)),citizen=plain(documentLabel).contains("cedula de ciudadan") && (code==nil || code=="13")
                let documentType=citizen ? "Cédula de ciudadanía":(!documentLabel.isEmpty ? documentLabel:code.map{"Documento tipo "+$0} ?? "No identificado")
                let normalizedRole=plain(role),kind:RutRepresentative.Kind = !matches("legal\\s+(?:prin(?:cipal)?)(?:\\b|\\s)",normalizedRole).isEmpty ? .principal:!matches("legal\\s+supl(?:ente)?(?:\\b|\\s)",normalizedRole).isEmpty ? .suplente:.otro
                let id=digits(identityRaw) ?? (identityRaw.range(of:"^[a-z0-9 .-]+$",options:[.regularExpression,.caseInsensitive]) != nil ? identityRaw.replacingOccurrences(of:"\\s",with:"",options:.regularExpression):"")
                let person=RutRepresentative(name:name,identity:id,kind:kind,documentType:documentType)
                if !result.representatives.contains(person){result.representatives.append(person)}
                if names[0].isEmpty || surnames[0].isEmpty || id.isEmpty {result.warnings.append("Un representante tiene nombre o identificación incompletos. Revisa esa fila del RUT.")}
                if !citizen {result.warnings.append("Un representante usa un documento distinto o no identificable como cédula de ciudadanía. Revisa su tipo antes de usar la plantilla.")}
            }
        }
        let principals=result.representatives.filter{$0.kind == .principal}
        if principals.count>1 {result.warnings.append("El RUT contiene varios representantes principales. Selecciona quién firmará; no se ha elegido automáticamente.")}
        if principals.isEmpty {result.warnings.append("No se encontró un representante legal principal. Selecciona o completa los datos manualmente.")}
        var seen=Set<String>();result.warnings=result.warnings.filter{seen.insert($0).inserted}
        return result
    }
}
