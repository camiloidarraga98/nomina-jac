#if os(iOS)
import SwiftUI

struct MediaFullscreenPhotoView:View {
    @StateObject private var photos:MediaFullscreenPhotoModel
    @EnvironmentObject private var store:PayrollStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    private let client:PayrollClient
    private let stamp:String?
    private let feed:MediaFeed
    private let denied:(Error)->Void
    @State private var prefetch=MediaFolderPhotoPrefetch()
    @StateObject private var photoSave=MediaFolderTransfer()

    init(selected:MediaItem,feed:MediaFeed,client:PayrollClient,denied:@escaping(Error)->Void) {
        self.client=client;self.feed=feed;self.denied=denied
        let expected=try? client.mediaAccessStamp();stamp=expected
        _photos=StateObject(wrappedValue:MediaFullscreenPhotoModel(selected:selected,items:feed.items,token:feed.nextPageToken ?? "",folderID:feed.folder?.id ?? "",collectionID:feed.collectionID,load:{try await client.mediaPhotoPreview($0,quality:.balanced,collectionID:feed.collectionID,progress:$1)},validate:{try await client.validateMediaItem($0)},page:{try await client.media(folder:feed.folder?.id ?? "",pageToken:$0)},isCurrent:{expected != nil && expected == client.mediaPresentationStamp},denied:denied,improve:{try await client.improveMediaPhotoPreview($0,current:$1)}))
    }
    private var folderName:String { feed.folder?.name ?? feed.breadcrumbs.last?.name ?? feed.root?.name ?? "Fotografía" }
    private func close() { photoSave.cancel();photos.stop();prefetch.stop();dismiss() }
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MediaFullscreenPhotoPager(items:photos.items,selectedID:photos.selectedID,documents:photos.urls,progress:photos.progress,errors:photos.errors,active:phase == .active,select:photos.select,retry:photos.retry,savePhoto:{ item in
                photoSave.start(client:client,plan:MediaDownloadPlan(folder:feed.folder ?? feed.root ?? MediaFolder(id:"photo",name:"Foto"),files:[item]),photos:true,writer:MediaPhotosExport.writer(client))
            },dismissPhoto:close)
                .ignoresSafeArea().accessibilityIdentifier("media.fullscreen")
                .accessibilityAction(.escape,close)
        }
        .safeAreaInset(edge:.top,spacing:0) {
            Text(folderName).font(.headline).foregroundStyle(.white).lineLimit(1)
                .frame(maxWidth:.infinity).padding(.horizontal,24).padding(.vertical,14)
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
                filmstrip
            }.padding(.vertical,10).background(.black.opacity(0.85))
        }
        .statusBarHidden().privacySensitive().preferredColorScheme(.dark)
        .task {
            photos.start()
            photos.refreshAuthorization()
            prefetch.start(feed,client:client,selectedID:photos.selectedID,denied:denied)
            while !Task.isCancelled {
                do {try await Task.sleep(for:.seconds(15))}catch{return}
                if phase == .active {photos.refreshAuthorization()}
                if phase == .active {prefetch.start(feed,client:client,selectedID:photos.selectedID,denied:denied)}
            }
        }
        .onChange(of:phase) {_,value in
            if value == .active {photos.refreshAuthorization();prefetch.start(feed,client:client,selectedID:photos.selectedID,denied:denied)}
            else {prefetch.stop()}
        }
        .onChange(of:photos.selectedID) {_,value in if phase == .active {prefetch.start(feed,client:client,selectedID:value,denied:denied)}}
        .onChange(of:client.mediaPresentationStamp) {_,value in if value != stamp {photoSave.cancel();photos.stop();prefetch.stop();dismiss()}}
        .onReceive(client.$cacheRevision) {_ in if let id=photos.selected?.id,let scope=try? client.mediaScope(),client.mediaOffline.isDeleted(id,scope:scope) {photos.stop();dismiss()}}
        .onChange(of:store.overview?.user.canReadMedia) {_,value in if value != true {photos.stop();dismiss()}}
        .onDisappear {photoSave.cancel();prefetch.stop();photos.stop()}
    }
    private var filmstrip:some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing:5) {
                    ForEach(Array(photos.items.enumerated()),id:\.element.id) { index,item in
                        Button {photos.select(item.id)} label: {
                            MediaFilmstripThumbnail(item:item,client:client,denied:denied)
                                .frame(width:44,height:56).clipShape(RoundedRectangle(cornerRadius:5))
                                .overlay(RoundedRectangle(cornerRadius:5).stroke(item.id==photos.selectedID ? Color.white:Color.clear,lineWidth:2))
                                .opacity(item.id==photos.selectedID ? 1:0.65)
                        }.buttonStyle(.plain).padding(.vertical,2).id(item.id)
                            .accessibilityLabel("Foto \(index+1)").accessibilityAddTraits(item.id==photos.selectedID ? .isSelected:[])
                            .accessibilityIdentifier("media.preview.strip."+item.id)
                    }
                }.padding(.horizontal,16)
            }.scrollIndicators(.hidden).frame(height:60).accessibilityIdentifier("media.preview.filmstrip")
                .onAppear {proxy.scrollTo(photos.selectedID,anchor:.center)}
                .onChange(of:photos.selectedID) {_,value in proxy.scrollTo(value,anchor:.center)}
        }
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
