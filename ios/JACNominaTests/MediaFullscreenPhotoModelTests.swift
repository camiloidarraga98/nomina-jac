#if os(iOS)
import XCTest
import UIKit
@testable import JACNomina

@MainActor
final class MediaFullscreenPhotoModelTests: XCTestCase {
    private func photo(_ id: String, kind: String = "image") -> MediaItem {
        MediaItem(id: id, name: id + ".png", mimeType: kind == "image" ? "image/png" : "video/quicktime",
                  kind: kind, size: 25, modifiedAt: "fixture", thumbnailAvailable: true)
    }

    private func feed(_ items: [MediaItem], folderID: String = "folder", collectionID: String = "r2-test", next: String? = nil) -> MediaFeed {
        let folder = MediaFolder(id: folderID, name: "Carpeta ficticia")
        return MediaFeed(connected: true, canRead: true, canUpload: false, canConnect: false,
                         root: MediaFolder(id: "root", name: "Raíz ficticia"), folder: folder,
                         breadcrumbs: [folder], items: items, nextPageToken: next,
                         provider: "r2", collectionID: collectionID)
    }

    private func waitFor(_ message: String, file: StaticString = #filePath, line: UInt = #line,
                         condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail(message, file: file, line: line)
        throw PhotoModelTestFailure.timedOut
    }

    func testSelectingPendingPhotoIsImmediateAndShowsMeasuredProgress() async throws {
        let first = photo("one"), second = photo("two"), third = photo("three")
        let gate = PhotoModelLoadGate(), files = PhotoModelDocuments()
        let model = MediaFullscreenPhotoModel(selected: first, items: [first, second, third], token: "", folderID: "folder", collectionID: "r2-test",
            load: { try await gate.load($0, progress: $1) }, validate: { _ in },
            page: { _ in XCTFail("No hay otra página"); throw PhotoModelTestFailure.unexpectedPage },
            isCurrent: { true }, denied: { _ in XCTFail("No hay revocación en esta prueba") })
        defer { model.stop(); gate.close(); files.clear() }

        model.start()
        try await waitFor("Deben comenzar la foto actual y su vecina") { gate.has("one") && gate.has("two") }
        XCTAssertEqual(model.progress["two"], 0, "El progreso no debe adelantarse sin recibir bytes")
        gate.measure("two", received: 30, total: 100)
        XCTAssertEqual(try XCTUnwrap(model.progress["two"]), 0.3, accuracy: 0.0001)
        model.select("two")
        XCTAssertEqual(model.selectedID, "two", "Seleccionar no debe esperar al archivo")
        XCTAssertNil(model.documents["two"])
        XCTAssertEqual(model.counter, "2 de 3")
        gate.measure("two", received: 62, total: 100)
        XCTAssertEqual(try XCTUnwrap(model.progress["two"]), 0.62, accuracy: 0.0001)
        gate.measure("two", received: 150, total: 100)
        XCTAssertEqual(try XCTUnwrap(model.progress["two"]), 0.99, accuracy: 0.0001, "Recibir bytes no confirma todavía el archivo")
        let document = try files.make("two")
        try gate.succeed("two", document: document)
        try await waitFor("La foto seleccionada debe terminar de cargar") { model.documents["two"] != nil }
        XCTAssertEqual(model.selectedID, "two")
        XCTAssertEqual(model.documents["two"]?.url, document.url)
        XCTAssertEqual(model.progress["two"], 1)
    }

    func testReturningToResidentPhotoRevalidatesWithoutDownloadingAgain() async throws {
        let first = photo("one"), second = photo("two"), third = photo("three")
        let gate = PhotoModelLoadGate(), files = PhotoModelDocuments()
        var validations: [String] = []
        let model = MediaFullscreenPhotoModel(selected: first, items: [first, second, third], token: "", folderID: "folder", collectionID: "r2-test",
            load: { try await gate.load($0, progress: $1) }, validate: { validations.append($0.id) },
            page: { _ in throw PhotoModelTestFailure.unexpectedPage }, isCurrent: { true }, denied: { _ in XCTFail("No debe denegar") })
        defer { model.stop(); gate.close(); files.clear() }
        model.start()
        try await waitFor("Deben comenzar ambas descargas") { gate.has("one") && gate.has("two") }
        let original = try files.make("one")
        try gate.succeed("one", document: original)
        try gate.succeed("two", document: files.make("two"))
        try await waitFor("Ambas fotos deben quedar residentes") { model.documents.count == 2 }

        model.select("two")
        try await waitFor("Se revalida la vecina precargada al abrirla") { validations.contains("two") }
        model.select("one")
        XCTAssertEqual(model.selectedID, "one")
        XCTAssertEqual(model.documents["one"]?.url, original.url, "La vuelta debe usar de inmediato el archivo residente autorizado")
        try await waitFor("Volver a la foto requiere revalidar su permiso") { validations.contains("one") }
        XCTAssertEqual(gate.calls.filter { $0 == "one" }.count, 1)
        XCTAssertEqual(gate.calls.filter { $0 == "two" }.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
    }

    func testReversedResponsesDoNotMoveSelectionAndDiscardCancelledOriginal() async throws {
        let first = photo("one"), second = photo("two"), third = photo("three")
        let gate = PhotoModelLoadGate(), files = PhotoModelDocuments()
        let model = MediaFullscreenPhotoModel(selected: first, items: [first, second, third], token: "", folderID: "folder", collectionID: "r2-test",
            load: { try await gate.load($0, progress: $1) }, validate: { _ in },
            page: { _ in throw PhotoModelTestFailure.unexpectedPage }, isCurrent: { true }, denied: { _ in XCTFail("No debe denegar") })
        defer { model.stop(); gate.close(); files.clear() }
        model.start()
        try await waitFor("Primera y segunda deben estar pendientes") { gate.has("one") && gate.has("two") }
        model.select("two")
        try await waitFor("Se precarga la tercera") { gate.has("three") }
        model.select("three")
        XCTAssertEqual(model.selectedID, "three")

        try gate.succeed("three", document: files.make("three"))
        try await waitFor("La tercera debe cargarse primero") { model.documents["three"] != nil }
        try gate.succeed("two", document: files.make("two"))
        try await waitFor("La respuesta anterior puede quedar residente") { model.documents["two"] != nil }
        XCTAssertEqual(model.selectedID, "three")
        let cancelled = try files.make("cancelled-one")
        try gate.succeed("one", document: cancelled)
        try await waitFor("Un original de una operación cancelada debe retirarse") { !FileManager.default.fileExists(atPath: cancelled.url.path) }
        XCTAssertEqual(model.selectedID, "three")
        XCTAssertNil(model.documents["one"])
        XCTAssertNil(model.progress["one"])
    }

    func testStopRemovesResidentAndLateOriginals() async throws {
        let first = photo("one"), second = photo("two")
        let gate = PhotoModelLoadGate(), files = PhotoModelDocuments()
        let model = MediaFullscreenPhotoModel(selected: first, items: [first, second], token: "", folderID: "folder", collectionID: "r2-test",
            load: { try await gate.load($0, progress: $1) }, validate: { _ in },
            page: { _ in throw PhotoModelTestFailure.unexpectedPage }, isCurrent: { true }, denied: { _ in XCTFail("Cerrar no es revocar") })
        defer { model.stop(); gate.close(); files.clear() }
        model.start()
        try await waitFor("Ambas deben estar pendientes") { gate.has("one") && gate.has("two") }
        let resident = try files.make("one")
        try gate.succeed("one", document: resident)
        try await waitFor("La primera debe quedar residente") { model.documents["one"] != nil }
        model.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: resident.url.path))
        XCTAssertTrue(model.documents.isEmpty)
        XCTAssertTrue(model.progress.isEmpty)
        XCTAssertTrue(model.errors.isEmpty)
        gate.measure("two", received: 50, total: 100)
        XCTAssertTrue(model.progress.isEmpty, "Los callbacks tardíos no deben restaurar el progreso tras cerrar")

        let late = try files.make("late-two")
        try gate.succeed("two", document: late)
        try await waitFor("Cerrar retira también los resultados tardíos") { !FileManager.default.fileExists(atPath: late.url.path) }
        let calls = gate.calls
        model.start()
        model.select("two")
        await Task.yield()
        XCTAssertEqual(model.selectedID, "one")
        XCTAssertEqual(gate.calls, calls)
        XCTAssertTrue(model.documents.isEmpty)
    }

    func testForbiddenRevalidationRemovesEveryResidentWithoutFallback() async throws {
        let first = photo("one"), second = photo("two")
        let gate = PhotoModelLoadGate(), files = PhotoModelDocuments()
        var denied: [Error] = []
        let model = MediaFullscreenPhotoModel(selected: first, items: [first, second], token: "", folderID: "folder", collectionID: "r2-test",
            load: { try await gate.load($0, progress: $1) }, validate: { _ in throw APIError.forbidden("Permiso retirado") },
            page: { _ in throw PhotoModelTestFailure.unexpectedPage }, isCurrent: { true }, denied: { denied.append($0) })
        defer { model.stop(); gate.close(); files.clear() }
        model.start()
        try await waitFor("Ambas descargas deben empezar") { gate.has("one") && gate.has("two") }
        let firstDocument = try files.make("one"), secondDocument = try files.make("two")
        try gate.succeed("one", document: firstDocument)
        try gate.succeed("two", document: secondDocument)
        try await waitFor("Ambas quedan residentes antes de la revocación") { model.documents.count == 2 }
        model.select("two")
        try await waitFor("La revocación debe notificarse") { denied.count == 1 }
        guard case APIError.forbidden = try XCTUnwrap(denied.first) else { return XCTFail("Debe conservar el motivo403") }
        XCTAssertTrue(model.documents.isEmpty)
        XCTAssertTrue(model.progress.isEmpty)
        XCTAssertTrue(model.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDocument.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDocument.url.path))
        let calls = gate.calls
        model.select("one")
        await Task.yield()
        XCTAssertEqual(gate.calls, calls, "No se debe usar una copia para saltar la revocación")
    }

    func testPaginationKeepsOnlyUniqueImagesFromTheSameFolderAndCollection() async throws {
        let first = photo("one"), second = photo("two"), video = photo("movie", kind: "video"), folder = photo("nested", kind: "folder")
        let gate = PhotoModelLoadGate()
        var pageCalls: [String] = []
        let model = MediaFullscreenPhotoModel(selected: first, items: [first, video], token: "next", folderID: "folder", collectionID: "r2-test",
            load: { try await gate.load($0, progress: $1) }, validate: { _ in },
            page: { cursor in pageCalls.append(cursor); return self.feed([video, folder, first, second, second]) },
            isCurrent: { true }, denied: { _ in XCTFail("La página pertenece a esta carpeta") })
        defer { model.stop(); gate.close() }
        model.start()
        try await waitFor("La paginación debe agregar la segunda foto") { model.items.count == 2 && !model.paging }
        XCTAssertEqual(pageCalls, ["next"])
        XCTAssertEqual(model.items.map(\.id), ["one", "two"])
        XCTAssertEqual(model.selectedID, "one", "Precargar metadatos no mueve la selección")
        XCTAssertEqual(model.token, "")
        XCTAssertNil(model.pageError)
        XCTAssertEqual(model.counter, "1 de 2")
        try await waitFor("Solo se descargan imágenes") { gate.has("one") && gate.has("two") }
        XCTAssertFalse(gate.calls.contains("movie"))
        XCTAssertFalse(gate.calls.contains("nested"))
    }

    func testQualityUpgradeKeepsVisiblePreviewAndDiscardsALateReplacementAfterMoving() async throws {
        let first=photo("one"),second=photo("two"),files=PhotoModelDocuments()
        let original=try files.make("one"),next=try files.make("two")
        var reply:CheckedContinuation<ExportedDocument?,Error>?
        let model=MediaFullscreenPhotoModel(selected:first,items:[first,second],token:"",folderID:"folder",collectionID:"r2-test",
            load:{item,_ in item.id==first.id ? original:next},validate:{_ in},page:{_ in throw PhotoModelTestFailure.unexpectedPage},
            isCurrent:{true},denied:{_ in XCTFail("No se retiró permiso")},improve:{item,_ in
                if item.id != first.id {return nil}
                return try await withCheckedThrowingContinuation {reply=$0}
            })
        defer {model.stop();reply?.resume(returning:nil);files.clear()}
        model.start()
        try await waitFor("La versión decente se muestra mientras se prepara más calidad") {reply != nil && model.documents[first.id] != nil}
        XCTAssertEqual(model.documents[first.id]?.url,original.url)
        model.select(second.id)
        let late=try files.make("late-detail")
        reply?.resume(returning:late);reply=nil
        try await waitFor("Una mejora tardía no debe volver a mostrar otra foto") {!FileManager.default.fileExists(atPath:late.url.path)}
        XCTAssertEqual(model.selectedID,second.id)
        XCTAssertEqual(model.documents[first.id]?.url,original.url)
    }

    func testQualityUpgradeFailureKeepsTheDecentPreviewButDenialWithdrawsIt() async throws {
        for revoked in [false,true] {
            let first=photo("one"),files=PhotoModelDocuments(),original=try files.make("one")
            var completed=false,denials=0
            let model=MediaFullscreenPhotoModel(selected:first,items:[first],token:"",folderID:"folder",collectionID:"r2-test",
                load:{_,_ in original},validate:{_ in},page:{_ in throw PhotoModelTestFailure.unexpectedPage},isCurrent:{true},denied:{_ in denials+=1},
                improve:{_,_ in completed=true;if revoked {throw APIError.forbidden("Acceso retirado")};throw URLError(.timedOut)})
            defer {model.stop();files.clear()}
            model.start()
            try await waitFor("Debe intentar la mejora") {completed}
            if revoked {
                try await waitFor("403 debe retirar incluso los píxeles previos") {denials==1}
                XCTAssertTrue(model.documents.isEmpty);XCTAssertFalse(FileManager.default.fileExists(atPath:original.url.path))
            } else {XCTAssertEqual(model.documents[first.id]?.url,original.url);XCTAssertTrue(model.errors.isEmpty)}
        }
    }

    func testPaginationRejectsDifferentFolderAndDifferentCollection() async throws {
        for mismatch in ["folder", "collection"] {
            let first = photo("one"), second = photo("private-foreign-photo")
            let gate = PhotoModelLoadGate(), files = PhotoModelDocuments()
            var pageCalls: [String] = [], denials = 0
            var reply:CheckedContinuation<MediaFeed,Error>?
            let model = MediaFullscreenPhotoModel(selected: first, items: [first], token: "next", folderID: "folder", collectionID: "r2-test",
                load: { try await gate.load($0, progress: $1) }, validate: { _ in },
                page: { cursor in
                    pageCalls.append(cursor)
                    return try await withCheckedThrowingContinuation {reply=$0}
                }, isCurrent: { true }, denied: { _ in denials += 1 })
            defer { model.stop(); gate.close();reply?.resume(throwing:CancellationError());files.clear() }
            model.start()
            try await waitFor("El original y su siguiente página deben estar pendientes") {gate.has(first.id) && reply != nil}
            let shown=try files.make(first.id);try gate.succeed(first.id,document:shown)
            try await waitFor("Debe existir una foto autorizada antes de cambiar la colección") {model.documents[first.id] != nil}
            reply?.resume(returning:self.feed([second], folderID:mismatch == "folder" ? "other-folder":"folder",collectionID:mismatch == "collection" ? "other-collection":"r2-test"));reply=nil
            try await waitFor("No debe aceptar una página de otro ámbito: " + mismatch) { model.pageError != nil && !model.paging }
            XCTAssertEqual(pageCalls, ["next"])
            XCTAssertEqual(model.items.map(\.id), ["one"])
            XCTAssertFalse(gate.calls.contains(second.id))
            XCTAssertEqual(model.selectedID, "one")
            XCTAssertEqual(denials, 1, "Un cambio confirmado de carpeta o colección retira el visor anterior")
            XCTAssertTrue(model.documents.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath:shown.url.path))
        }
    }

    func testPaginationRejectsACyclicCursorWithoutIssuingItAgain() async throws {
        let first = photo("one"), video = photo("movie", kind: "video")
        let gate = PhotoModelLoadGate()
        var pageCalls: [String] = []
        let model = MediaFullscreenPhotoModel(selected: first, items: [first], token: "cycle", folderID: "folder", collectionID: "r2-test",
            load: { try await gate.load($0, progress: $1) }, validate: { _ in },
            page: { cursor in pageCalls.append(cursor); return self.feed([video], next: "cycle") },
            isCurrent: { true }, denied: { _ in XCTFail("Un cursor cíclico es error de paginación") })
        defer { model.stop(); gate.close() }
        model.start()
        try await waitFor("El ciclo debe detenerse con un error visible") { model.pageError != nil && !model.paging }
        XCTAssertEqual(pageCalls, ["cycle"])
        XCTAssertEqual(model.items.map(\.id), ["one"])
        XCTAssertEqual(model.selectedID, "one")
        model.move(1)
        try await waitFor("Repetir no debe emitir otra petición del cursor cíclico") { !model.paging }
        XCTAssertEqual(pageCalls, ["cycle"])
        XCTAssertNotNil(model.pageError)
    }
}

@MainActor
final class MediaPhotoFilmstripTests:XCTestCase {
    private func photos(_ count:Int)->[MediaItem] {
        (0..<count).map {MediaItem(id:"photo-\($0)",name:"Fixture \($0)",mimeType:"image/jpeg",kind:"image",size:25,modifiedAt:"fixture",thumbnailAvailable:true)}
    }
    private func configure(_ view:MediaPhotoFilmstripView,_ items:[MediaItem],_ selected:String,
                           active:Bool=true,select:@escaping(String)->Void) {
        view.configure(items:items,selectedID:selected,active:active,
                       content:{_ in UIListContentConfiguration.cell()},select:select)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    private func makeView()->MediaPhotoFilmstripView {MediaPhotoFilmstripView(frame:CGRect(x:0,y:0,width:320,height:60))}
    private func scroll(_ view:MediaPhotoFilmstripView,to offset:CGFloat) {
        view.collectionView.setContentOffset(CGPoint(x:offset,y:0),animated:false)
        view.scrollViewDidScroll(view.collectionView)
    }

    func testOpenExternalSelectionAndRepeatedTapNeverPublishScrollFeedback() {
        let view=makeView(),items=photos(12)
        var selected:[String]=[]
        configure(view,items,"photo-8") {selected.append($0)}
        XCTAssertEqual(view.collectionView.contentOffset.x,392,accuracy:0.01)
        view.scrollViewDidScroll(view.collectionView)
        configure(view,items,"photo-11") {selected.append($0)}
        XCTAssertEqual(view.collectionView.contentOffset.x,539,accuracy:0.01)
        view.collectionView(view.collectionView,didSelectItemAt:IndexPath(item:11,section:0))
        XCTAssertTrue(selected.isEmpty,"Abrir, centrar y volver a tocar la misma foto no publican selección")
        view.collectionView(view.collectionView,didSelectItemAt:IndexPath(item:0,section:0))
        XCTAssertEqual(selected,["photo-0"])
        XCTAssertEqual(view.collectionView.contentOffset.x,0,accuracy:0.01)
    }

    func testDragPublishesBeforeReleaseAndAcknowledgementKeepsFingerOffset() {
        let view=makeView(),items=photos(12)
        var selected:[String]=[]
        configure(view,items,"photo-0") {selected.append($0)}
        view.scrollViewWillBeginDragging(view.collectionView)
        scroll(view,to:27)
        XCTAssertEqual(selected,["photo-1"],"La foto cambia durante el gesto, sin tap ni soltar")
        configure(view,items,"photo-1") {selected.append($0)}
        XCTAssertEqual(view.collectionView.contentOffset.x,27,accuracy:0.01,"El eco del modelo no centra ni corta el gesto")
        scroll(view,to:45)
        XCTAssertEqual(selected,["photo-1"],"Los callbacks de la misma miniatura se deduplican")
        scroll(view,to:76)
        XCTAssertEqual(selected,["photo-1","photo-2"])
        view.scrollViewDidEndDragging(view.collectionView,willDecelerate:false)
        XCTAssertEqual(view.collectionView.contentOffset.x,98,accuracy:0.01)
        XCTAssertEqual(selected.count,2,"El ajuste final no vuelve a publicar")
    }

    func testFastDragAndInertiaReachBothEndsWithoutOutOfRangeOrDuplicateEvents() {
        let view=makeView(),items=photos(40)
        var selected:[String]=[]
        configure(view,items,"photo-0") {selected.append($0)}
        view.scrollViewWillBeginDragging(view.collectionView)
        scroll(view,to:173)
        view.scrollViewDidEndDragging(view.collectionView,willDecelerate:true)
        scroll(view,to:1060)
        scroll(view,to:5000)
        view.scrollViewDidEndDecelerating(view.collectionView)
        XCTAssertEqual(selected,["photo-4","photo-22","photo-39"])
        XCTAssertEqual(view.collectionView.contentOffset.x,1911,accuracy:0.01)
        view.scrollViewWillBeginDragging(view.collectionView)
        scroll(view,to:900)
        scroll(view,to:-200)
        view.scrollViewDidEndDragging(view.collectionView,willDecelerate:false)
        XCTAssertEqual(selected.suffix(2),["photo-18","photo-0"])
        XCTAssertEqual(view.collectionView.contentOffset.x,0,accuracy:0.01)
    }

    func testInertialTargetSnapsToValidThumbnailWithoutPublishingFutureSelection() {
        let view=makeView(),items=photos(3)
        var selected:[String]=[]
        configure(view,items,"photo-1") {selected.append($0)}
        view.scrollViewWillBeginDragging(view.collectionView)
        var target=CGPoint(x:10000,y:0)
        view.scrollViewWillEndDragging(view.collectionView,withVelocity:CGPoint(x:8,y:0),targetContentOffset:&target)
        XCTAssertEqual(target.x,98)
        target.x = -100
        view.scrollViewWillEndDragging(view.collectionView,withVelocity:CGPoint(x:-8,y:0),targetContentOffset:&target)
        XCTAssertEqual(target.x,0)
        XCTAssertTrue(selected.isEmpty,"La predicción de inercia no adelanta una selección que aún no se ve")
    }

    func testMainPhotoSelectionInterruptsInertiaAndIgnoresItsLateCallbacks() {
        let view=makeView(),items=photos(12)
        var selected:[String]=[]
        configure(view,items,"photo-0") {selected.append($0)}
        view.scrollViewWillBeginDragging(view.collectionView)
        scroll(view,to:180)
        view.scrollViewDidEndDragging(view.collectionView,willDecelerate:true)
        configure(view,items,"photo-9") {selected.append($0)}
        view.scrollViewDidEndDecelerating(view.collectionView)
        XCTAssertEqual(view.selectedID,"photo-9")
        XCTAssertEqual(view.collectionView.contentOffset.x,441,accuracy:0.01)
        XCTAssertEqual(selected,["photo-4"])
    }

    func testProgressiveAppendPreservesCellsOffsetAndOngoingInertia() {
        let view=makeView(),initial=photos(12),expanded=photos(24)
        var selected:[String]=[]
        configure(view,initial,"photo-2") {selected.append($0)}
        let cell=view.collectionView.cellForItem(at:IndexPath(item:2,section:0))
        XCTAssertNotNil(cell)
        view.scrollViewWillBeginDragging(view.collectionView)
        scroll(view,to:108)
        view.scrollViewDidEndDragging(view.collectionView,willDecelerate:true)
        configure(view,expanded,"photo-2") {selected.append($0)}
        XCTAssertEqual(view.collectionView.contentOffset.x,108,accuracy:0.01)
        XCTAssertTrue(cell === view.collectionView.cellForItem(at:IndexPath(item:2,section:0)),"Agregar una página no recarga las celdas existentes")
        XCTAssertEqual(view.collectionView.numberOfItems(inSection:0),24)
        XCTAssertTrue(selected.isEmpty,"Recibir metadatos no selecciona una foto")
        scroll(view,to:700)
        view.scrollViewDidEndDecelerating(view.collectionView)
        XCTAssertEqual(selected,["photo-14"])
    }

    func testStopInactiveAndReopenDoNotSelectFromAnOldOffset() {
        let view=makeView(),items=photos(12)
        var selected:[String]=[]
        configure(view,items,"photo-4") {selected.append($0)}
        view.scrollViewWillBeginDragging(view.collectionView)
        scroll(view,to:300)
        configure(view,items,"photo-6",active:false) {selected.append($0)}
        view.scrollViewDidEndDecelerating(view.collectionView)
        configure(view,items,"photo-1") {selected.append($0)}
        view.scrollViewDidScroll(view.collectionView)
        view.scrollViewDidEndDecelerating(view.collectionView)
        XCTAssertEqual(selected,["photo-6"])
        XCTAssertEqual(view.selectedID,"photo-1")
        XCTAssertEqual(view.collectionView.contentOffset.x,49,accuracy:0.01)
        view.stop()
        scroll(view,to:200)
        XCTAssertEqual(selected,["photo-6"])
    }

    func testResizeAndProgressUpdatesKeepSelectionWithoutRebuildingThumbnails() {
        let view=makeView(),items=photos(12)
        var selected:[String]=[],contents=0
        let content:(MediaItem)->UIContentConfiguration={_ in contents+=1;return UIListContentConfiguration.cell()}
        view.configure(items:items,selectedID:"photo-6",active:true,content:content,select:{selected.append($0)})
        view.layoutIfNeeded()
        let before=contents
        for _ in 0..<20 {
            view.configure(items:items,selectedID:"photo-6",active:true,content:content,select:{selected.append($0)})
        }
        XCTAssertEqual(contents,before,"Cambios de progreso no recrean ni recargan miniaturas")
        view.frame.size.width=700
        view.setNeedsLayout();view.layoutIfNeeded()
        XCTAssertEqual(view.selectedID,"photo-6")
        XCTAssertEqual(view.collectionView.contentOffset.x,294,accuracy:0.01)
        XCTAssertTrue(selected.isEmpty)
    }

    func testEmptySingleDuplicateAndReplacedItemsCannotPublishInvalidIndexes() {
        let view=makeView(),items=photos(3)
        var selected:[String]=[]
        configure(view,[],"missing") {selected.append($0)}
        view.scrollViewWillBeginDragging(view.collectionView)
        scroll(view,to:300)
        view.scrollViewDidEndDecelerating(view.collectionView)
        configure(view,[items[0],items[0]],"missing") {selected.append($0)}
        XCTAssertEqual(view.collectionView.numberOfItems(inSection:0),1)
        XCTAssertEqual(view.selectedID,"photo-0")
        view.scrollViewWillBeginDragging(view.collectionView)
        scroll(view,to:1000)
        view.scrollViewDidEndDragging(view.collectionView,willDecelerate:false)
        configure(view,items,"photo-2") {selected.append($0)}
        configure(view,[items[0]],"photo-2") {selected.append($0)}
        view.collectionView(view.collectionView,didSelectItemAt:IndexPath(item:20,section:0))
        XCTAssertEqual(view.selectedID,"photo-0")
        XCTAssertTrue(selected.isEmpty)
    }
}

private enum PhotoModelTestFailure: Error { case timedOut, unexpectedPage }

/// Cancellable views may finish after stop. Closing also rejects loads that
/// had been scheduled but had not yet entered this mock, so no continuation leaks.
@MainActor private final class PhotoModelLoadGate {
    private struct Held {
        let measured: (Int64, Int64) -> Void
        let continuation: CheckedContinuation<ExportedDocument, Error>
    }
    private var pending: [String: [Held]] = [:]
    private var closed = false
    private(set) var calls: [String] = []

    func load(_ item: MediaItem, progress: @escaping (Int64, Int64) -> Void) async throws -> ExportedDocument {
        guard !closed else { throw CancellationError() }
        calls.append(item.id)
        return try await withCheckedThrowingContinuation { continuation in
            pending[item.id, default: []].append(Held(measured: progress, continuation: continuation))
        }
    }

    func has(_ id: String) -> Bool { !(pending[id]?.isEmpty ?? true) }

    func measure(_ id: String, received: Int64, total: Int64) {
        pending[id]?.first?.measured(received, total)
    }

    func succeed(_ id: String, document: ExportedDocument, file: StaticString = #filePath, line: UInt = #line) throws {
        var held = try XCTUnwrap(pending[id], "No hay descarga pendiente para " + id, file: file, line: line)
        XCTAssertFalse(held.isEmpty, file: file, line: line)
        guard !held.isEmpty else { throw PhotoModelTestFailure.timedOut }
        let first = held.removeFirst()
        pending[id] = held.isEmpty ? nil : held
        first.continuation.resume(returning: document)
    }

    func close() {
        closed = true
        let held = pending.values.flatMap { $0 }
        pending = [:]
        held.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }
}

private final class PhotoModelDocuments {
    private var files: [ExportedDocument] = []
    func make(_ name: String) throws -> ExportedDocument {
        let file = try TemporaryDocuments.save(MediaFixture.photo, filename: name + ".png")
        files.append(file)
        return file
    }
    func clear() { files.forEach { TemporaryDocuments.remove($0) }; files = [] }
    deinit { clear() }
}
#endif
