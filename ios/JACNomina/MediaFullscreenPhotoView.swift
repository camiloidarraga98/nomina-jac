#if os(iOS)
import SwiftUI
import UIKit

struct MediaFullscreenPhotoView:View {
    @StateObject private var photos:MediaFullscreenPhotoModel
    @EnvironmentObject private var store:PayrollStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.isWorkspaceActive) private var isWorkspaceActive
    private let client:PayrollClient
    private let stamp:String?
    private let feed:MediaFeed
    private let denied:(Error)->Void
    private let embedded: Bool
    private let closeEmbedded: (() -> Void)?
    private let expand: ((MediaItem) -> Void)?
    private let requestedSelectionID: String
    private let selectionCommand: Int
    private let selectedChanged: ((MediaItem) -> Void)?
    @State private var prefetch=MediaFolderPhotoPrefetch()
    @StateObject private var photoSave=MediaFolderTransfer()

    init(selected:MediaItem,feed:MediaFeed,client:PayrollClient,embedded:Bool=false,close:(() -> Void)?=nil,expand:((MediaItem) -> Void)?=nil,selectionCommand:Int=0,selectedChanged:((MediaItem) -> Void)?=nil,denied:@escaping(Error)->Void) {
        self.client=client;self.feed=feed;self.denied=denied
        self.embedded=embedded;self.closeEmbedded=close;self.expand=expand
        self.requestedSelectionID=selected.id;self.selectedChanged=selectedChanged
        self.selectionCommand=selectionCommand
        // Construction can repeat while an embedded gallery scrolls. The RAM
        // identity is presentation only; each real load validates authorization.
        let expected=client.mediaPresentationStamp;stamp=expected
        _photos=StateObject(wrappedValue:MediaFullscreenPhotoModel(selected:selected,items:feed.items,token:feed.nextPageToken ?? "",folderID:feed.folder?.id ?? "",collectionID:feed.collectionID,load:{try await client.mediaPhotoPreview($0,quality:.balanced,collectionID:feed.collectionID,progress:$1)},validate:{try await client.validateMediaItem($0)},page:{try await client.media(folder:feed.folder?.id ?? "",pageToken:$0)},isCurrent:{expected != nil && expected == client.mediaPresentationStamp},denied:denied,improve:{try await client.improveMediaPhotoPreview($0,current:$1)}))
    }
    private var folderName:String { feed.folder?.name ?? feed.breadcrumbs.last?.name ?? feed.root?.name ?? "Fotografía" }
    private var viewActive: Bool { phase == .active && (!embedded || isWorkspaceActive) }
    private func close() { photoSave.cancel();photos.stop();prefetch.stop();if let closeEmbedded {closeEmbedded()}else{dismiss()} }
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MediaFullscreenPhotoPager(items:photos.items,selectedID:photos.selectedID,documents:photos.urls,progress:photos.progress,errors:photos.errors,active:viewActive,select:photos.select,retry:photos.retry,savePhoto:{ item in
                photoSave.start(client:client,plan:MediaDownloadPlan(folder:feed.folder ?? feed.root ?? MediaFolder(id:"photo",name:"Foto"),files:[item]),photos:true,writer:MediaPhotosExport.writer(client))
            },dismissPhoto:close)
                .ignoresSafeArea(edges: embedded ? [] : .all)
                .accessibilityIdentifier("media.fullscreen")
                .accessibilityAction(.escape,close)
        }
        .safeAreaInset(edge:.top,spacing:0) {
            HStack(spacing: 8) {
                Text(folderName).font(.headline).foregroundStyle(.white).lineLimit(1).frame(maxWidth: .infinity, alignment: embedded ? .leading : .center)
                if embedded, let expand {
                    Button { if let item = photos.selected { expand(item) } } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }
                        .foregroundStyle(.white).accessibilityLabel("Ver foto a pantalla completa").accessibilityIdentifier("media.wide.expand")
                }
            }.padding(.horizontal, embedded ? 12 : 24).padding(.vertical, embedded ? 2 : 14)
                .background(.black.opacity(0.65)).accessibilityIdentifier("media.preview.folder")
        }
        .safeAreaInset(edge:.bottom,spacing:0) {
            VStack(spacing:8) {
                if photoSave.running {ProgressView("Guardando en Fotos…").font(.caption).tint(.white).foregroundStyle(.white)}
                if let message=photoSave.message {Text(message).font(.caption).foregroundStyle(.white).accessibilityIdentifier("media.preview.saved")}
                if let failure=photoSave.failures.first {Text(failure).font(.caption).foregroundStyle(.orange).padding(.horizontal,16)}
                if photos.paging {ProgressView("Consultando más fotos…").font(.caption).tint(.white).foregroundStyle(.white)}
                if let error=photos.pageError {HStack {Text(error).font(.caption);Button("Reintentar"){photos.retryPage()}}.foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal,16)}
                Text(photos.counter).font(.caption2).monospacedDigit().foregroundStyle(.white.opacity(0.7)).accessibilityIdentifier("media.preview.counter")
                    #if DEBUG
                    .accessibilityValue(UITestBackend.photoProgressFixtureRequests() ?? "")
                    #endif
                filmstrip
            }.padding(.vertical,10).background(.black.opacity(0.85))
        }
        .statusBarHidden(!embedded).privacySensitive().preferredColorScheme(embedded ? nil : .dark)
        .environment(\.colorScheme, .dark)
        .task(id: viewActive) {
            guard viewActive else { photos.pause(); prefetch.stop(); return }
            photos.resume()
            photos.select(requestedSelectionID)
            photos.refreshAuthorization()
            prefetch.start(feed,client:client,selectedID:photos.selectedID,denied:denied)
            while !Task.isCancelled {
                do {try await Task.sleep(for:.seconds(15))}catch{return}
                if viewActive {photos.refreshAuthorization()}
                if viewActive {prefetch.start(feed,client:client,selectedID:photos.selectedID,denied:denied)}
            }
        }
        .onChange(of:viewActive) {_,value in
            if !value {photoSave.cancel();prefetch.stop();photos.pause()}
        }
        .onChange(of:photos.selectedID) {_,value in
            if let item = photos.selected { selectedChanged?(item) }
            #if DEBUG
            UITestBackend.selectedPhotoForProgressFixture(value)
            #endif
            if viewActive {prefetch.start(feed,client:client,selectedID:value,denied:denied)}
        }
        // A parent acknowledgement of our own drag is not an external command:
        // only a fullscreen selection explicitly requests a new inline page.
        .onChange(of: selectionCommand) { _, _ in photos.select(requestedSelectionID) }
        .onChange(of:client.mediaPresentationStamp) {_,value in if value != stamp {close()}}
        .onReceive(client.$cacheRevision) {_ in if let id=photos.selected?.id,let scope=try? client.mediaScope(),client.mediaOffline.isDeleted(id,scope:scope) {close()}}
        .onChange(of:store.overview?.user.canReadMedia) {_,value in if value != true {close()}}
        .onDisappear {photoSave.cancel();prefetch.stop();if embedded {photos.pause()}else{photos.stop()}}
    }
    private var filmstrip:some View {
        MediaPhotoFilmstrip(items:photos.items,selectedID:photos.selectedID,active:viewActive,
                            client:client,denied:denied,select:photos.select).frame(height:60)
    }

}

private struct MediaPhotoFilmstrip:UIViewRepresentable {
    let items:[MediaItem]
    let selectedID:String
    let active:Bool
    let client:PayrollClient
    let denied:(Error)->Void
    let select:(String)->Void

    func makeUIView(context:Context)->MediaPhotoFilmstripView {MediaPhotoFilmstripView()}
    func updateUIView(_ view:MediaPhotoFilmstripView,context:Context) {
        let stamp=client.mediaPresentationStamp ?? ""
        view.configure(items:items,selectedID:selectedID,active:active,content:{ item in
            UIHostingConfiguration {
                MediaFilmstripThumbnail(item:item,client:client,denied:denied)
                    .id(item.id+item.modifiedAt+stamp)
                    .frame(width:44,height:56).clipShape(RoundedRectangle(cornerRadius:5))
            }.margins(.all,0)
        },select:select)
    }
    static func dismantleUIView(_ view:MediaPhotoFilmstripView,coordinator:()) {view.stop()}
}

/// Only a user drag (including its inertia) publishes the thumbnail nearest the
/// center. Selection acknowledgements never recenter an ongoing drag. Cells use
/// the existing thumbnail loader; progress updates do not rebuild their content.
final class MediaPhotoFilmstripView:UIView,UICollectionViewDataSource,UICollectionViewDelegate {
    private let flow:UICollectionViewFlowLayout
    let collectionView:UICollectionView
    private var items:[MediaItem]=[]
    private(set) var selectedID=""
    private var enabled=false
    private var userScrolling=false
    private var changingLayout=false
    private var viewport=CGSize.zero
    private var content:((MediaItem)->UIContentConfiguration)?
    private var select:((String)->Void)?
    private let step:CGFloat=49

    override init(frame:CGRect) {
        let flow=UICollectionViewFlowLayout()
        self.flow=flow
        flow.scrollDirection = .horizontal
        flow.itemSize=CGSize(width:44,height:56)
        flow.minimumLineSpacing=5
        flow.minimumInteritemSpacing=0
        collectionView=UICollectionView(frame:.zero,collectionViewLayout:flow)
        super.init(frame:frame)
        collectionView.dataSource=self
        collectionView.delegate=self
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator=false
        collectionView.showsVerticalScrollIndicator=false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.scrollsToTop=false
        collectionView.bounces=false
        collectionView.decelerationRate = .fast
        collectionView.semanticContentAttribute = .forceLeftToRight
        collectionView.register(UICollectionViewCell.self,forCellWithReuseIdentifier:"photo")
        collectionView.accessibilityIdentifier="media.preview.filmstrip"
        addSubview(collectionView)
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}

    func configure(items:[MediaItem],selectedID:String,active:Bool,
                   content:@escaping(MediaItem)->UIContentConfiguration,select:@escaping(String)->Void) {
        guard active else {stop();return}
        enabled=true
        collectionView.isHidden=false
        collectionView.isScrollEnabled=true
        self.content=content
        self.select=select
        var seen=Set<String>()
        let next=items.filter {$0.kind == "image" && seen.insert($0.id).inserted}
        if next != self.items {
            let oldCount=self.items.count
            let append=next.starts(with:self.items)
            if !append {endInteraction()}
            self.items=next
            withoutSelection {
                if append,oldCount>0 {
                    // New metadata pages keep existing cells and the finger's
                    // offset, even when they arrive during deceleration.
                    UIView.performWithoutAnimation {
                        collectionView.insertItems(at:(oldCount..<next.count).map {IndexPath(item:$0,section:0)})
                        collectionView.layoutIfNeeded()
                    }
                } else {collectionView.reloadData()}
            }
        }
        let validID=next.contains(where:{$0.id==selectedID}) ? selectedID:(next.first?.id ?? "")
        if self.selectedID != validID {
            endInteraction()
            self.selectedID=validID
            centerSelection()
        } else if !userScrolling {centerSelection()}
        updateSelectionAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard viewport != bounds.size else {return}
        endInteraction()
        viewport=bounds.size
        withoutSelection {
            collectionView.frame=bounds
            let edge=max(0,(bounds.width-flow.itemSize.width)/2)
            flow.sectionInset=UIEdgeInsets(top:2,left:edge,bottom:2,right:edge)
            flow.invalidateLayout()
            collectionView.layoutIfNeeded()
        }
        centerSelection()
    }

    func stop() {
        guard enabled else {return}
        enabled=false
        endInteraction()
        collectionView.isHidden=true
        collectionView.isScrollEnabled=false
        collectionView.visibleCells.forEach {$0.contentConfiguration=nil}
        items=[]
        selectedID=""
        content=nil
        select=nil
        withoutSelection {collectionView.reloadData()}
    }

    private func withoutSelection(_ work:()->Void) {
        let previous=changingLayout
        changingLayout=true
        work()
        changingLayout=previous
    }
    private func endInteraction() {
        userScrolling=false
        withoutSelection {
            if collectionView.isDragging || collectionView.isDecelerating {
                collectionView.panGestureRecognizer.isEnabled=false
                collectionView.panGestureRecognizer.isEnabled=true
            }
            collectionView.setContentOffset(collectionView.contentOffset,animated:false)
        }
    }
    private func centerSelection() {
        guard bounds.width>0,let index=items.firstIndex(where:{$0.id==selectedID}) else {return}
        withoutSelection {
            collectionView.layoutIfNeeded()
            let point=CGPoint(x:CGFloat(index)*step,y:0)
            if collectionView.contentOffset != point {collectionView.setContentOffset(point,animated:false)}
        }
    }
    private func index(at offset:CGFloat)->Int? {
        guard !items.isEmpty,offset.isFinite else {return nil}
        return Int(min(CGFloat(items.count-1),max(0,(offset/step).rounded())))
    }
    private func publishSelection(_ index:Int) {
        guard enabled,items.indices.contains(index),items[index].id != selectedID else {return}
        selectedID=items[index].id
        updateSelectionAppearance()
        select?(selectedID)
    }
    private func updateSelectionAppearance() {
        for cell in collectionView.visibleCells {
            guard let index=collectionView.indexPath(for:cell)?.item,items.indices.contains(index) else {continue}
            style(cell,at:index)
        }
    }
    private func style(_ cell:UICollectionViewCell,at index:Int) {
        guard items.indices.contains(index) else {return}
        let selected=items[index].id==selectedID
        cell.layer.borderWidth=2
        cell.layer.cornerRadius=5
        cell.layer.borderColor=selected ? UIColor.white.cgColor:UIColor.clear.cgColor
        cell.alpha=selected ? 1:0.65
        cell.accessibilityTraits=selected ? [.button,.selected]:[.button]
    }
    func collectionView(_ collectionView:UICollectionView,numberOfItemsInSection section:Int)->Int {items.count}
    func collectionView(_ collectionView:UICollectionView,cellForItemAt indexPath:IndexPath)->UICollectionViewCell {
        let cell=collectionView.dequeueReusableCell(withReuseIdentifier:"photo",for:indexPath)
        cell.contentConfiguration=content?(items[indexPath.item])
        cell.isAccessibilityElement=true
        cell.accessibilityLabel="Foto \(indexPath.item+1)"
        cell.accessibilityIdentifier="media.preview.strip."+items[indexPath.item].id
        style(cell,at:indexPath.item)
        return cell
    }
    func collectionView(_ collectionView:UICollectionView,willDisplay cell:UICollectionViewCell,forItemAt indexPath:IndexPath) {
        guard enabled,items.indices.contains(indexPath.item) else {return}
        // Prefetching may redisplay a retained cell without asking the data
        // source for it again. Restore content released when it left the screen.
        if cell.contentConfiguration == nil {cell.contentConfiguration=content?(items[indexPath.item])}
        style(cell,at:indexPath.item)
    }
    func collectionView(_ collectionView:UICollectionView,didEndDisplaying cell:UICollectionViewCell,forItemAt indexPath:IndexPath) {
        cell.contentConfiguration=nil
    }
    func collectionView(_ collectionView:UICollectionView,didSelectItemAt indexPath:IndexPath) {
        endInteraction()
        publishSelection(indexPath.item)
        centerSelection()
    }
    func scrollViewWillBeginDragging(_ scrollView:UIScrollView) {userScrolling=enabled}
    func scrollViewDidScroll(_ scrollView:UIScrollView) {
        guard enabled,userScrolling,!changingLayout,let index=index(at:scrollView.contentOffset.x) else {return}
        publishSelection(index)
    }
    func scrollViewWillEndDragging(_ scrollView:UIScrollView,withVelocity velocity:CGPoint,targetContentOffset:UnsafeMutablePointer<CGPoint>) {
        guard enabled,userScrolling,let index=index(at:targetContentOffset.pointee.x) else {return}
        targetContentOffset.pointee=CGPoint(x:CGFloat(index)*step,y:0)
    }
    func scrollViewDidEndDragging(_ scrollView:UIScrollView,willDecelerate decelerate:Bool) {
        if !decelerate {finishScrolling()}
    }
    func scrollViewDidEndDecelerating(_ scrollView:UIScrollView) {finishScrolling()}
    private func finishScrolling() {
        scrollViewDidScroll(collectionView)
        userScrolling=false
        centerSelection()
    }
}

private struct MediaFilmstripThumbnail:View {
    let item:MediaItem
    let client:PayrollClient
    let denied:(Error)->Void
    @StateObject private var thumbnail=MediaTileThumbnail()
    var body:some View {
        ZStack {
            Color.white.opacity(0.12)
            if let image=thumbnail.image {Image(uiImage:image).resizable().scaledToFill()}
            else {Image(systemName:"photo").font(.caption).foregroundStyle(.white.opacity(0.5))}
        }.clipped().accessibilityHidden(true)
            .task(id:item.id+item.modifiedAt+(client.mediaPresentationStamp ?? "")) {
                let stamp=client.mediaPresentationStamp
                thumbnail.show(key:item.id+item.modifiedAt,authorized:{stamp != nil && stamp==client.mediaPresentationStamp && client.accessUser?.canReadMedia == true},cached:stamp.flatMap{MediaGridThumbnailLoader.shared.cachedImage(item,client:client,stamp:$0)},load:{try await MediaGridThumbnailLoader.shared.image(item,client:client,networkAllowed:!client.usingOfflineCopy)},denied:denied)
            }
            .onDisappear {thumbnail.hide()}
    }
}
#endif
