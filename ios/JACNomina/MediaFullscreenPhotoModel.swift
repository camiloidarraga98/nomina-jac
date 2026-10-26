#if os(iOS)
import SwiftUI

/// Selection moves immediately. Loading and authorization never move the page
/// behind the user's finger; each result belongs to its own item and operation.
@MainActor
final class MediaFullscreenPhotoModel: ObservableObject {
    @Published private(set) var items:[MediaItem]
    @Published private(set) var selectedID:String
    @Published private(set) var documents:[String:ExportedDocument]=[:]
    @Published private(set) var progress:[String:Double]=[:]
    @Published private(set) var errors:[String:String]=[:]
    @Published private(set) var token:String
    @Published private(set) var paging=false
    @Published private(set) var pageError:String?
    private let folderID:String
    private let collectionID:String?
    private let load:(MediaItem,@escaping(Int64,Int64)->Void) async throws -> ExportedDocument
    private let validate:(MediaItem) async throws -> Void
    private let page:(String) async throws -> MediaFeed
    private let isCurrent:()->Bool
    private let denied:(Error)->Void
    private let improve:((MediaItem,ExportedDocument) async throws -> ExportedDocument?)?
    private var improvement:Task<Void,Never>?
    private var improvementID:UUID?
    private var improved=Set<String>()
    private var active=true
    private var started=false
    private var loads:[String:(id:UUID,task:Task<Void,Never>)]=[:]
    private var validation:Task<Void,Never>?
    private var pagination:Task<Void,Never>?
    private var seenTokens=Set<String>()
    private var accessOrder:[String]=[]

    init(selected:MediaItem,items:[MediaItem],token:String,folderID:String,collectionID:String?,load:@escaping(MediaItem,@escaping(Int64,Int64)->Void) async throws -> ExportedDocument,validate:@escaping(MediaItem) async throws -> Void,page:@escaping(String) async throws -> MediaFeed,isCurrent:@escaping()->Bool,denied:@escaping(Error)->Void,improve:((MediaItem,ExportedDocument) async throws -> ExportedDocument?)? = nil) {
        var seen=Set<String>()
        var photos=items.filter{$0.kind == "image" && seen.insert($0.id).inserted}
        if !photos.contains(where:{$0.id == selected.id}) {photos.insert(selected,at:0)}
        self.items=photos;self.selectedID=selected.id;self.token=token;self.folderID=folderID;self.collectionID=collectionID
        self.load=load;self.validate=validate;self.page=page;self.isCurrent=isCurrent;self.denied=denied
        self.improve=improve
    }
    var index:Int {items.firstIndex{$0.id == selectedID} ?? 0}
    var selected:MediaItem? {items.first{$0.id == selectedID}}
    var counter:String {"\(index+1) de \(items.count)"+(token.isEmpty ? "":"+")}
    var canPrevious:Bool {index>0}
    var canNext:Bool {index+1<items.count || !token.isEmpty}
    var urls:[String:URL] {documents.mapValues(\.url)}

    func start() {
        guard active,!started,isCurrent() else {return};started=true
        schedule();prefetchMetadata()
    }
    func select(_ id:String) {
        guard active,isCurrent(),id != selectedID,items.contains(where:{$0.id == id}) else{return}
        selectedID=id;touch(id);validation?.cancel();validation=nil
        improvement?.cancel();improvement=nil;improvementID=nil
        // Resident files were already authorized in this open viewer. Keep the
        // transition immediate, and revalidate their metadata on every revisit.
        if documents[id] != nil,let item=selected {revalidate(item);improveSelected()}
        schedule();prefetchMetadata()
    }
    func move(_ direction:Int) {
        guard active,direction == -1 || direction == 1 else{return}
        let target=index+direction
        if items.indices.contains(target) {select(items[target].id)}
        else if direction==1,!token.isEmpty {loadMore(advance:true)}
    }
    func retry(_ id:String) {
        guard active,isCurrent(),items.contains(where:{$0.id == id}) else{return}
        errors[id]=nil;progress[id]=0
        if id == selectedID {schedule()} else {select(id)}
    }
    func refreshAuthorization() {
        guard active,isCurrent(),let item=selected else {stop();return}
        revalidate(item)
        improveSelected()
    }
    func retryPage() {loadMore(advance:false)}
    private func revalidate(_ item:MediaItem) {
        validation?.cancel()
        validation=Task { [weak self] in
            guard let self else{return}
            do {try await self.validate(item);try Task.checkCancellation();if !self.isCurrent(){self.stop()}}
            catch {if self.active,!Task.isCancelled {self.handle(error,for:item.id)}}
        }
    }
    private func touch(_ id:String) {accessOrder.removeAll{$0==id};accessOrder.append(id)}
    private func schedule() {
        guard active,isCurrent() else {stop();return}
        var wanted=[selectedID]
        if index+1<items.count {wanted.append(items[index+1].id)}
        else if index>0 {wanted.append(items[index-1].id)}
        for id in Array(loads.keys) where !wanted.contains(id) {loads.removeValue(forKey:id)?.task.cancel();progress[id]=nil}
        for id in wanted where documents[id] == nil && loads[id] == nil && errors[id] == nil {
            guard let item=items.first(where:{$0.id==id}) else{continue}
            let operation=UUID();progress[id]=0
            let task=Task { [weak self] in
                guard let self else{return}
                defer {if self.loads[id]?.id==operation {self.loads[id]=nil}}
                do {
                    let document=try await self.load(item) { [weak self] received,total in
                        guard let self,self.active,self.isCurrent(),self.loads[id]?.id==operation else{return}
                        self.progress[id]=total>0 ? min(0.99,Double(max(0,received))/Double(total)):0
                    }
                    guard self.active,!Task.isCancelled,self.isCurrent(),self.loads[id]?.id==operation else {
                        TemporaryDocuments.remove(document)
                        if self.active,!self.isCurrent(){self.stop()}
                        return
                    }
                    if let old=self.documents[id] {TemporaryDocuments.remove(old)}
                    self.documents[id]=document;self.progress[id]=1;self.errors[id]=nil;self.touch(id);self.trimResidents()
                    if id == self.selectedID { self.improveSelected() }
                } catch {
                    guard self.active,!Task.isCancelled,self.loads[id]?.id==operation else{return}
                    self.handle(error,for:id)
                }
            }
            loads[id]=(operation,task)
        }
        trimResidents()
    }
    private func trimResidents() {
        let visible=Set(items[max(0,index-1)..<min(items.count,index+2)].map(\.id))
        while documents.count>5,let id=accessOrder.first(where:{!visible.contains($0) && documents[$0] != nil}) {
            if let old=documents.removeValue(forKey:id) {TemporaryDocuments.remove(old)}
            accessOrder.removeAll{$0==id};progress[id]=nil
        }
    }
    private func improveSelected() {
        guard active, isCurrent(), improvement == nil, let improve, let item=selected,
              let current=documents[item.id], !improved.contains(item.id) else { return }
        let operation=UUID();improvementID=operation
        improvement=Task { [weak self] in
            guard let self else { return }
            defer { if self.improvementID==operation { self.improvement=nil;self.improvementID=nil } }
            do {
                guard let document=try await improve(item,current) else { return }
                guard self.active,!Task.isCancelled,self.isCurrent(),self.selectedID==item.id,
                      self.improvementID==operation,self.documents[item.id]?.url==current.url else {
                    TemporaryDocuments.remove(document);return
                }
                self.documents[item.id]=document;self.improved.insert(item.id)
                if document.url != current.url {TemporaryDocuments.remove(current)}
            } catch {
                guard self.active,!Task.isCancelled,self.improvementID==operation else{return}
                if self.isAccessFailure(error) {self.handle(error,for:item.id)}
                // Keep the already visible decent preview if extra detail fails.
            }
        }
    }
    private func prefetchMetadata() {if index+2>=items.count,!token.isEmpty {loadMore(advance:false)}}
    private func loadMore(advance:Bool) {
        guard active,isCurrent(),!paging,!token.isEmpty else{return}
        paging=true;pageError=nil
        let previousCount=items.count,previousID=selectedID
        pagination=Task { [weak self] in
            guard let self else{return}
            defer {if self.active {self.paging=false;self.pagination=nil}}
            do {
                repeat {
                    let cursor=self.token
                    guard !self.seenTokens.contains(cursor) else {throw APIError.invalid("No pudimos continuar la carpeta. Actualízala e inténtalo de nuevo.")}
                    let result=try await self.page(cursor);try Task.checkCancellation()
                    guard self.active,self.isCurrent() else{throw CancellationError()}
                    guard result.connected,result.canRead else{throw APIError.forbidden("Esta carpeta ya no está disponible.")}
                    guard result.folder?.id==self.folderID,result.collectionID==self.collectionID else{
                        let failure=APIError.conflict("La carpeta cambió. Vuelve a abrirla para consultar su versión actual.")
                        self.pageError=failure.localizedDescription;self.stop();self.denied(failure);return
                    }
                    self.seenTokens.insert(cursor)
                    var ids=Set(self.items.map(\.id));self.items.append(contentsOf:result.items.filter{$0.kind=="image" && ids.insert($0.id).inserted})
                    self.token=result.nextPageToken ?? ""
                }while self.items.count==previousCount && !self.token.isEmpty
                if advance,self.selectedID==previousID,self.items.count>previousCount {self.select(self.items[previousCount].id)}
                else {self.schedule()}
            }catch {if self.active,!Task.isCancelled {if self.isAccessFailure(error){self.stop();self.denied(error)}else{self.pageError=error.localizedDescription}}}
        }
    }
    private func isAccessFailure(_ error:Error)->Bool {
        if case APIError.unauthorized=error {return true};if case APIError.forbidden=error{return true}
        return error is MediaFolderRemoved || error is MediaFileRemoved
    }
    private func handle(_ error:Error,for id:String) {
        if isAccessFailure(error) {stop();denied(error);return}
        if error is CancellationError || (error as? URLError)?.code == .cancelled {return}
        if AgendaOfflineCache.isUnavailable(error),documents[id] != nil {return}
        if let stale=documents.removeValue(forKey:id) {TemporaryDocuments.remove(stale)}
        errors[id]=error.localizedDescription;progress[id]=nil
    }
    func stop() {
        guard active else{return};active=false
        loads.values.forEach{$0.task.cancel()};loads=[:];validation?.cancel();validation=nil;pagination?.cancel();pagination=nil
        improvement?.cancel();improvement=nil;improvementID=nil;improved=[]
        documents.values.forEach{TemporaryDocuments.remove($0)};documents=[:];progress=[:];errors=[:];paging=false
    }
}
#endif
