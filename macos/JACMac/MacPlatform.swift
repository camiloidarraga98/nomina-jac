import SwiftUI
import AppKit
import Quartz
import PDFKit
import AVFoundation

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
