import SwiftUI
import Combine
import UIKit

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
            if crm.denied || store.overview?.user.isOwner != true || store.overview?.user.itinerariesOnly == true { ContentUnavailableView("CRM no disponible",systemImage:"lock",description:Text(crm.message ?? "Solo administradores de JAC.")) }
            else { List {
                if let error { InlineError(message:error) }
                if store.isOffline { Text("Sin conexión · última información descargada. Los cambios necesitan internet.").font(.footnote).foregroundStyle(.secondary) }
                Picker("Sección",selection:$section) { Text("Shows").tag("shows");Text("Semana").tag("weekly");Text("Empresarios").tag("contacts") }.pickerStyle(.segmented).accessibilityIdentifier("crm.sections")
                if section == "shows" { showList }
                else if section == "weekly" { CRMWeeklyView() }
                else { CRMContactsView() }
            }.jacSurface().navigationTitle("CRM").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.primaryAction) { Menu { Button("Crear show") { editor=CRMEditorRequest(kind:.create,record:.null,feed:feed) };Button("Registrar abono") { editor=CRMEditorRequest(kind:.payment,record:.null,feed:feed) };Button("Actualizar shows de Calendar") { Task { await load(sync:true) } } } label:{ Image(systemName:"plus") }.disabled(busy || store.isOffline || feed.isNull).accessibilityIdentifier("crm.add") } }
                .task { await load(sync:!store.isOffline);while !Task.isCancelled { do { try await Task.sleep(for:.seconds(30));await load(sync:!store.isOffline && Date().timeIntervalSince(lastSync)>60) } catch { break } } }
                .refreshable { await load(sync:!store.isOffline) }
                .sheet(item:$editor,onDismiss:{ Task { await load() } }) { CRMEditor(request:$0).environmentObject(crm) }
            }
        }.environmentObject(crm)
    }
    private var showList:some View {
        Group {
            Section { DatePicker("Desde el mes",selection:Binding(get:{ ReceiptParser.civilDate(month+"-01") ?? Date() },set:{ month=CalendarClock.month($0);Task { await load() } }),in:(ReceiptParser.civilDate(CalendarClock.month(Date())+"-01") ?? Date())...,displayedComponents:.date).disabled(busy).accessibilityIdentifier("crm.month")
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
    var body:some View { VStack(alignment:.leading,spacing:8) { Text(show["title"].text).font(.headline);Text(show["showDate"].text+(show["entrepreneur"].text.isEmpty ? "":" · "+show["entrepreneur"].text)).font(.caption).foregroundStyle(.secondary)
        HStack { Text(show["sale"].isNull ? "Sin precio":CRMFields.money(show["sale"].number));Spacer();Text(show["balance"].isNull ? "":"Pendiente "+CRMFields.money(show["balance"].number)).font(.caption) }
    }.padding(.vertical,7) }
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
        List {
            if let error { InlineError(message:error) }
            Picker("Sección del show",selection:$tab) { Text("Cuenta").tag("account");Text("Rentabilidad").tag("profit");Text("Preparación").tag("tasks") }.pickerStyle(.segmented).accessibilityIdentifier("crm.show.sections")
            if tab == "account" { account }
            else { CRMPlanView(id:id,show:detail["show"],tab:tab,data:$planData,draft:$planDraft) }
        }.jacSurface().navigationTitle(detail["show"]["title"].text.isEmpty ? "Show":detail["show"]["title"].text).navigationBarTitleDisplayMode(.inline)
            .task { tab=initialTab;await load();while !Task.isCancelled {do{try await Task.sleep(for:.seconds(30));await load()}catch{break}} }.refreshable { await load() }
            .sheet(item:$editor,onDismiss:{ Task { await load() } }) { CRMEditor(request:$0).environmentObject(crm) }
            .onChange(of:crm.denied) {_,denied in if denied {editor=nil;detail = .null;planData = .null;planDraft = .null;confirmDelete=false}}
            .confirmationDialog(deleteTitle,isPresented:$confirmDelete,titleVisibility:.visible) { Button("Eliminar evento",role:.destructive) { Task { await remove() } };Button("Cancelar",role:.cancel) {} } message:{ Text("Se quitará de Calendar, CRM y Agenda. Abonos y comprobantes se conservan como historial.") }
    }
    private var account:some View { Group {
        Section("Cuenta del show") { LabeledContent("Fecha",value:detail["show"]["showDate"].text);CRMMetric("Venta",detail["show"]["sale"]);CRMMetric("Abonos",detail["show"]["paid"]);CRMMetric("Saldo",detail["show"]["balance"])
            if !detail["show"]["entrepreneur"].text.isEmpty { Text(detail["show"]["entrepreneur"].text) }
            if !detail["show"]["note"].text.isEmpty { Text(detail["show"]["note"].text).font(.footnote) }
            if writable { Button("Editar precio y empresario") { editor=CRMEditorRequest(kind:.price,record:detail["show"],feed:.object(["contacts":contacts.elements.isEmpty ? crm.feed["contacts"]:contacts])) }.accessibilityIdentifier("crm.price")
                Button("Registrar abono") { editor=CRMEditorRequest(kind:.payment,record:detail["show"],feed:feed.isNull ? crm.feed:feed) }.disabled(detail["show"]["sale"].isNull).accessibilityIdentifier("crm.payment") }
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
        if focused { let matches=CRMFields.matches(name,in:contacts);ScrollView {VStack(alignment:.leading,spacing:4) {ForEach(matches.map { CRMItem(value:$0) }) { item in Button { name=item.value["name"].text;contactID=item.id;focused=false } label:{ VStack(alignment:.leading,spacing:4) { Text(item.value["name"].text);if !item.value["company"].text.isEmpty { Text(item.value["company"].text).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth:.infinity,alignment:.leading).padding(10).background(Color.white,in:RoundedRectangle(cornerRadius:9)) }.buttonStyle(.plain).accessibilityIdentifier("crm.suggestion."+item.id) }}}.frame(height:CGFloat(min(matches.count*66,198))) }
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
                Section { Button(busy ? "Guardando…":attempt != nil ? "Reintentar guardado":"Guardar") { Task { await save() } }.buttonStyle(JACPrimaryButtonStyle()).disabled(busy || importing || store.isOffline).accessibilityIdentifier("crm.editor.save") }
            }.scrollDismissesKeyboard(.never).onChange(of:contactFocused){_,focused in if focused {withAnimation{proxy.scrollTo("crm.contact.row",anchor:.top)}}}.onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardDidShowNotification)){_ in if contactFocused{withAnimation{proxy.scrollTo("crm.contact.row",anchor:.top)}}}.jacSurface().navigationTitle(request.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cerrar") { dismiss() }.disabled(busy || importing) };ToolbarItemGroup(placement:.keyboard){Spacer();Button("Listo"){UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)}.accessibilityIdentifier("crm.keyboard.done")} }
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
                DatePicker("Día del evento",selection:$date,in:CalendarClock.calendar.startOfDay(for:Date())...,displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone)
                Toggle("Todo el día",isOn:$allDay)
                if !allDay { DatePicker("Hora de inicio",selection:$startTime,displayedComponents:.hourAndMinute).environment(\.timeZone,CalendarClock.calendar.timeZone);DatePicker("Hora de fin",selection:$endTime,displayedComponents:.hourAndMinute).environment(\.timeZone,CalendarClock.calendar.timeZone) }
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
        Section("Abono") { CRMAmountField(title:"Valor del abono (COP)",value:$paymentAmount);DatePicker("Fecha del abono",selection:$paymentDate,displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone);TextField("Observación del abono",text:text("paymentNote"),axis:.vertical).lineLimit(2...4) }.disabled(locked)
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
    }.onChange(of:crm.denied){_,denied in if denied {document=nil}}.sheet(item:$document,onDismiss:{if let previous {TemporaryDocuments.remove(previous);self.previous=nil}}) { file in NavigationStack { DocumentPreview(url:file.url).privacySensitive().ignoresSafeArea(edges:.bottom).navigationTitle("Documento").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.confirmationAction){Button("Listo"){document=nil}}} } } }
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
                if !task["dueDate"].text.isEmpty {DatePicker("Día límite",selection:Binding(get:{ReceiptParser.civilDate(task["dueDate"].text) ?? Date()},set:{setTask(index,"dueDate",.string(BoardingClock.today($0)))}),displayedComponents:.date).environment(\.timeZone,CalendarClock.calendar.timeZone)}
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
    }.onChange(of:crm.denied){_,denied in if denied {editor=nil;data = .null}}.jacSurface().navigationTitle(data["contact"]["name"].text.isEmpty ? "Empresario":data["contact"]["name"].text).navigationBarTitleDisplayMode(.inline).task{await load()}.refreshable{await load()}.sheet(item:$editor,onDismiss:{Task{await load()}}){CRMEditor(request:$0).environmentObject(crm)} }
    private func load() async {let q=["view":"contact","id":id];if data.isNull,let saved=crm.cached(q){data=saved};do{data=try await crm.read(q);error=nil}catch{self.error=store.reportReadFailure(error)}}
}
