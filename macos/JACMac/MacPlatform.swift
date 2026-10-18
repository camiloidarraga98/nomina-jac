import SwiftUI
import AppKit
import Quartz
import PDFKit
import AVFoundation

// Calendar selection preserves the original time and the field's date limits.
enum MacDateSelection {
    static func parse(_ text:String, calendar:Calendar)->Date? {
        let input=text.trimmingCharacters(in:.whitespacesAndNewlines)
        let parts=input.split(separator:"/",omittingEmptySubsequences:false)
        guard parts.count==3,(1...2).contains(parts[0].count),(1...2).contains(parts[1].count),parts[2].count==4,
              parts.allSatisfy({$0.allSatisfy({$0.isASCII && $0.isNumber})}),let day=Int(parts[0]),let month=Int(parts[1]),let year=Int(parts[2]),year>0 else{return nil}
        let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.calendar=calendar;f.timeZone=calendar.timeZone;f.dateFormat="d/M/yyyy";f.isLenient=false
        guard let date=f.date(from:input),calendar.component(.day,from:date)==day,calendar.component(.month,from:date)==month,calendar.component(.year,from:date)==year else{return nil};return date
    }
    static func permits(_ day:Date, range:ClosedRange<Date>, calendar:Calendar) -> Bool {
        guard let interval=calendar.dateInterval(of:.day,for:day) else{return false}
        return interval.start <= range.upperBound && interval.end > range.lowerBound
    }
    static func select(_ day:Date, preserving original:Date, range:ClosedRange<Date>, calendar:Calendar) -> Date {
        let time=calendar.dateComponents([.hour,.minute,.second],from:original)
        let date=calendar.date(bySettingHour:time.hour ?? 0,minute:time.minute ?? 0,second:time.second ?? 0,of:day) ?? day
        return min(max(date,range.lowerBound),range.upperBound)
    }
    static func days(in month:Date, calendar:Calendar)->[Date] {
        guard let first=calendar.dateInterval(of:.month,for:month)?.start else{return []}
        let offset=(calendar.component(.weekday,from:first)+5)%7
        return (0..<42).compactMap {calendar.date(byAdding:.day,value:$0-offset,to:first)}
    }
}

struct MacDatePicker:View {
    let title:String
    @Binding var selection:Date
    var range:ClosedRange<Date>
    var components:DatePickerComponents
    var monthOnly:Bool
    @Environment(\.calendar) private var systemCalendar
    @Environment(\.timeZone) private var timeZone
    @State private var open=false
    private var calendar:Calendar {var c=systemCalendar;c.timeZone=timeZone;return c}
    init(_ title:String, selection:Binding<Date>, in range:ClosedRange<Date> = Date.distantPast...Date.distantFuture, displayedComponents:DatePickerComponents = [.date,.hourAndMinute], monthOnly:Bool=false) {
        self.title=title;_selection=selection;self.range=range;components=displayedComponents;self.monthOnly=monthOnly
    }
    init(_ title:String, selection:Binding<Date>, in range:PartialRangeFrom<Date>, displayedComponents:DatePickerComponents = [.date,.hourAndMinute]) {
        self.init(title,selection:selection,in:range.lowerBound...Date.distantFuture,displayedComponents:displayedComponents)
    }
    var body:some View {
        LabeledContent(title) {
            HStack(spacing:8) {
                if components.contains(.date) {
                    Button {open.toggle()} label: {
                        HStack(spacing:8) {
                            Image(systemName:"calendar").foregroundStyle(JACTheme.action)
                            Text(label).monospacedDigit().foregroundStyle(JACTheme.ink)
                            Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold)).foregroundStyle(.secondary)
                        }.padding(.horizontal,10).frame(minHeight:32)
                            .background(JACTheme.action.opacity(0.07),in:RoundedRectangle(cornerRadius:8))
                            .overlay(RoundedRectangle(cornerRadius:8).stroke(JACTheme.action.opacity(0.18),lineWidth:1))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(label).accessibilityIdentifier("date.open."+title)
                        .popover(isPresented:$open,arrowEdge:.bottom) {
                            MacDateCalendar(selection:$selection,range:range,calendar:calendar) {open=false}.padding(16)
                        }
                }
                if components.contains(.hourAndMinute) {
                    SwiftUI.DatePicker("Hora",selection:$selection,in:range,displayedComponents:.hourAndMinute).labelsHidden()
                }
            }
        }
    }
    private var label:String {
        let f=DateFormatter();f.locale=Locale(identifier:"es_CO");f.calendar=calendar;f.timeZone=timeZone;f.dateFormat=monthOnly ? "MMMM yyyy":"d MMM yyyy"
        return f.string(from:selection).capitalized
    }
}

private struct MacDateCalendar:View {
    @Binding var selection:Date
    let range:ClosedRange<Date>
    let calendar:Calendar
    let close:()->Void
    @State private var month:Date
    @State private var typedDate=""
    @State private var inputError:String?
    init(selection:Binding<Date>,range:ClosedRange<Date>,calendar:Calendar,close:@escaping ()->Void) {
        _selection=selection;self.range=range;self.calendar=calendar;self.close=close
        _month=State(initialValue:calendar.dateInterval(of:.month,for:min(max(selection.wrappedValue,range.lowerBound),range.upperBound))?.start ?? selection.wrappedValue)
    }
    var body:some View {
        VStack(spacing:14) {
            HStack {
                Button {shift(-1)} label:{Image(systemName:"chevron.left").frame(width:28,height:28).contentShape(Rectangle())}.disabled(!canShift(-1)).accessibilityLabel("Mes anterior")
                Spacer();Text(monthTitle).font(.headline);Spacer()
                Button {shift(1)} label:{Image(systemName:"chevron.right").frame(width:28,height:28).contentShape(Rectangle())}.disabled(!canShift(1)).accessibilityLabel("Mes siguiente")
            }.buttonStyle(.plain)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:7),spacing:4) {
                ForEach(["L","M","X","J","V","S","D"],id:\.self){Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(height:22)}
                ForEach(MacDateSelection.days(in:month,calendar:calendar),id:\.self){date in
                    let selected=calendar.isDate(date,inSameDayAs:selection)
                    let current=calendar.isDate(date,equalTo:month,toGranularity:.month)
                    Button {choose(date)} label: {
                        Text("\(calendar.component(.day,from:date))").font(.body.weight(selected ? .semibold:.regular))
                            .frame(maxWidth:.infinity,minHeight:36)
                            .background(selected ? JACTheme.primary:Color.clear,in:RoundedRectangle(cornerRadius:9))
                            .foregroundStyle(selected ? Color.white:current ? JACTheme.ink:Color.secondary)
                            .overlay(RoundedRectangle(cornerRadius:9).stroke(calendar.isDateInToday(date) ? JACTheme.action.opacity(0.6):.clear,lineWidth:1))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!MacDateSelection.permits(date,range:range,calendar:calendar))
                        .accessibilityLabel(dayLabel(date)).accessibilityAddTraits(selected ? .isSelected:[])
                        .accessibilityIdentifier("date.day."+iso(date))
                }
            }
            Divider()
            HStack(spacing:8) {
                TextField("dd/mm/aaaa",text:$typedDate).textFieldStyle(.roundedBorder).frame(width:118).accessibilityIdentifier("date.input").onSubmit{applyTypedDate()}
                Button("Usar fecha"){applyTypedDate()}.disabled(typedDate.isEmpty).accessibilityIdentifier("date.apply")
                Spacer()
            }
            if let inputError {Text(inputError).font(.caption).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
            HStack {
                Button("Hoy"){choose(Date())}.disabled(!MacDateSelection.permits(Date(),range:range,calendar:calendar))
                Spacer();Button("Cerrar",action:close).accessibilityIdentifier("date.close")
            }.buttonStyle(.bordered)
        }.frame(width:316).foregroundStyle(JACTheme.ink)
    }
    private func choose(_ date:Date){selection=MacDateSelection.select(date,preserving:selection,range:range,calendar:calendar);close()}
    private func applyTypedDate() {
        guard let date=MacDateSelection.parse(typedDate,calendar:calendar) else{inputError="Escribe una fecha válida: día/mes/año.";return}
        guard MacDateSelection.permits(date,range:range,calendar:calendar) else{inputError="Esa fecha está fuera del rango permitido.";return}
        choose(date)
    }
    private func shift(_ value:Int){if let next=calendar.date(byAdding:.month,value:value,to:month){month=next}}
    private func canShift(_ value:Int)->Bool {
        guard let next=calendar.date(byAdding:.month,value:value,to:month),let interval=calendar.dateInterval(of:.month,for:next) else{return false}
        return interval.start<=range.upperBound && interval.end>range.lowerBound
    }
    private var monthTitle:String {let f=formatter("MMMM yyyy");return f.string(from:month).capitalized}
    private func formatter(_ format:String)->DateFormatter {let f=DateFormatter();f.locale=Locale(identifier:"es_CO");f.calendar=calendar;f.timeZone=calendar.timeZone;f.dateFormat=format;return f}
    private func iso(_ date:Date)->String {formatter("yyyy-MM-dd").string(from:date)}
    private func dayLabel(_ date:Date)->String {formatter("EEEE d 'de' MMMM yyyy").string(from:date)}
}

// Software keyboard hints have no equivalent on a Mac hardware keyboard.
enum MacKeyboardHint { case decimalPad, numberPad, numbersAndPunctuation, emailAddress, phonePad }
enum MacCapitalizationHint { case never, words, sentences }
extension View {
    func keyboardType(_ hint:MacKeyboardHint) -> some View { self }
    func textInputAutocapitalization(_ hint:MacCapitalizationHint) -> some View { self }
}
extension NSImage {
    func jpegData(compressionQuality:CGFloat) -> Data? {
        guard let cg = cgImage(forProposedRect:nil,context:nil,hints:nil) else {return nil}
        return NSBitmapImageRep(cgImage:cg).representation(using:.jpeg,properties:[.compressionFactor:compressionQuality])
    }
}

struct DocumentPreview: View {
    let url:URL
    var body:some View {
        VStack(spacing:0) {
            MacQuickLook(url:url).frame(minWidth:650,minHeight:480)
            HStack {
                Button("Guardar una copia…") {MacDocumentActions.save(url)}
                if url.pathExtension.lowercased() == "pdf" {Button("Imprimir…") {MacDocumentActions.printDocument(url)}}
                Spacer()
                ShareLink(item:url) {Label("Compartir",systemImage:"square.and.arrow.up")}
            }.padding(14).background(.bar)
        }
    }
}
private struct MacQuickLook:NSViewRepresentable {
    let url:URL
    func makeNSView(context:Context) -> QLPreviewView {let view=QLPreviewView(frame:.zero,style:.normal)!;view.autostarts=true;view.previewItem=url as NSURL;return view}
    func updateNSView(_ view:QLPreviewView,context:Context) {if (view.previewItem as? NSURL) != url as NSURL {view.previewItem=url as NSURL}}
    static func dismantleNSView(_ view:QLPreviewView,coordinator:()) {view.close()}
}
@MainActor enum MacDocumentActions {
    static func save(_ url:URL) {
        let panel=NSSavePanel();panel.nameFieldStringValue=url.lastPathComponent;panel.canCreateDirectories=true
        guard panel.runModal() == .OK,let destination=panel.url else{return}
        do {let data=try Data(contentsOf:url);try data.write(to:destination,options:.atomic)}
        catch {NSAlert(error:error).runModal()}
    }
    static func printDocument(_ url:URL) {
        guard let document=PDFDocument(url:url),let operation=document.printOperation(for:.shared,scalingMode:.pageScaleToFit,autoRotate:true) else{return}
        operation.run()
    }
}

enum MacReceiptImages {
    @MainActor static func file(_ url:URL) throws -> NSImage {
        guard url.isFileURL else{throw APIError.invalid("Elige una imagen local.")}
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<=20*1024*1024 else{throw APIError.invalid("El comprobante supera los 20 MB.")}
        let bytes=try Data(contentsOf:url)
        if let image=NSImage(data:bytes){return image}
        if let pdf=PDFDocument(data:bytes),!pdf.isLocked,let page=pdf.page(at:0){return page.thumbnail(of:NSSize(width:2400,height:3400),for:.mediaBox)}
        throw APIError.invalid("No se pudo leer el comprobante. Elige una imagen o PDF sin contraseña.")
    }
    @MainActor static func photograph(_ image:NSImage) throws -> Data {
        guard let input=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else{throw APIError.invalid("No se pudo leer la imagen.")}
        let scale=min(1,4096/Double(max(input.width,input.height))),width=max(1,Int(Double(input.width)*scale)),height=max(1,Int(Double(input.height)*scale))
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else{throw APIError.invalid("No se pudo preparar la imagen.")}
        context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height));context.draw(input,in:CGRect(x:0,y:0,width:width,height:height))
        guard let cg=context.makeImage(),let bytes=NSBitmapImageRep(cgImage:cg).representation(using:.jpeg,properties:[.compressionFactor:0.9]),bytes.count<=10*1024*1024 else{throw APIError.invalid("La foto supera los 10 MB.")}
        return bytes
    }
    #if DEBUG
    @MainActor static func fixture(logo:Bool) -> NSImage {
        let size=NSSize(width:1100,height:1350)
        return NSImage(size:size,flipped:true) {rect in
            NSColor.white.setFill();rect.fill()
            let lines=[logo ? "Frisby":"RESTAURANTE FICTICIO JAC","FACTURA DE PRUEBA","FECHA: 08/10/2026 13:45:20","Almuerzo de prueba","SUBTOTAL 40.000","IVA 7.600","TOTAL A PAGAR COP 47.600","EFECTIVO 50.000","CAMBIO 2.400","VENCIMIENTO: 10/10/2026 09:00"]
            for (i,line) in lines.enumerated() {(line as NSString).draw(at:NSPoint(x:60,y:60+i*125),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:44,weight:.medium),.foregroundColor:NSColor.black])};return true
        }
    }
    #endif
}

// AVFoundation captures locally. No image goes to an OCR service.
@MainActor final class MacReceiptCamera:NSObject,ObservableObject,AVCapturePhotoCaptureDelegate {
    let session=AVCaptureSession()
    let output=AVCapturePhotoOutput()
    @Published var error:String?
    @Published var ready=false
    var onImage:((NSImage?)->Void)?
    func start() async {
        guard await AVCaptureDevice.requestAccess(for:.video) else{error="Permite Cámara en Ajustes del Sistema o elige una imagen de Archivos.";return}
        do {
            guard let device=AVCaptureDevice.default(for:.video) else{throw APIError.message("No hay una cámara disponible. Elige una imagen guardada.")}
            let input=try AVCaptureDeviceInput(device:device)
            session.beginConfiguration();session.sessionPreset = .photo
            guard session.canAddInput(input),session.canAddOutput(output) else{session.commitConfiguration();throw APIError.message("No se pudo abrir la cámara.")}
            session.addInput(input);session.addOutput(output);session.commitConfiguration()
            // A dedicated serial queue keeps capture startup off the UI thread.
            let capture=session
            await Task.detached {capture.startRunning()}.value;ready=true
        } catch {self.error=error.localizedDescription}
    }
    func stop() {let capture=session;Task.detached{capture.stopRunning()}}
    nonisolated func photoOutput(_ output:AVCapturePhotoOutput,didFinishProcessingPhoto photo:AVCapturePhoto,error:Error?) {
        let bytes=photo.fileDataRepresentation()
        Task {@MainActor in if let error {self.error=error.localizedDescription} else {self.onImage?(bytes.flatMap(NSImage.init(data:)))}}
    }
}
struct TravelReceiptCamera:View {
    let onImage:(NSImage?)->Void
    @StateObject private var camera=MacReceiptCamera()
    var body:some View {
        VStack(spacing:16) {
            Text("Fotografiar comprobante").font(.title2)
            CameraPreview(session:camera.session).frame(width:640,height:400).clipped()
            if let error=camera.error {InlineError(message:error)}
            HStack {Button("Cancelar"){onImage(nil)};Spacer();Button("Tomar foto"){camera.output.capturePhoto(with:AVCapturePhotoSettings(),delegate:camera)}.disabled(!camera.ready)}
        }.padding(24).task{camera.onImage=onImage;await camera.start()}.onDisappear{camera.stop()}
    }
}
private struct CameraPreview:NSViewRepresentable {
    let session:AVCaptureSession
    func makeNSView(context:Context)->CameraLayerView {let view=CameraLayerView();view.preview.session=session;return view}
    func updateNSView(_ view:CameraLayerView,context:Context) {}
}
private final class CameraLayerView:NSView {
    let preview=AVCaptureVideoPreviewLayer()
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;preview.videoGravity = .resizeAspectFill;layer?.addSublayer(preview)}
    required init?(coder:NSCoder){fatalError("init(coder:) is unavailable")}
    override func layout(){super.layout();preview.frame=bounds}
}
