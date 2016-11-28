/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Manages the second-level collection view, a grid of photos in a collection (or all photos).
 */


import UIKit
import Photos
import PhotosUI

protocol SelectAssetsDelegate: class {
    func onFinishSelectingAssets(selectedAssets: [PHAsset], assetCollection: PHAssetCollection)
}

private extension UICollectionView {
    func indexPathsForElements(in rect: CGRect) -> [IndexPath] {
        let allLayoutAttributes = collectionViewLayout.layoutAttributesForElements(in: rect)!
        return allLayoutAttributes.map { $0.indexPath }
    }
}

class AssetGridViewController: UICollectionViewController {

    var fetchResult: PHFetchResult<PHAsset>!
    var assetCollection: PHAssetCollection!

    @IBOutlet var doneButtonItem: UIBarButtonItem!

    fileprivate let imageManager = PHCachingImageManager()
    fileprivate var thumbnailSize: CGSize!
    fileprivate var previousPreheatRect = CGRect.zero
    
    weak var delegate: SelectAssetsDelegate?
    
    var selectedAssets: [PHAsset] {
        return fetchResult.objects(at: IndexSet(self.collectionView!.indexPathsForSelectedItems!.map { $0.item }))
    }

    // MARK: UIViewController / Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        resetCachedAssets()
        PHPhotoLibrary.shared().register(self)

        // fetchResultが空ならallPhotosを取得
        if fetchResult == nil {
            let allPhotosOptions = PHFetchOptions()
            allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            fetchResult = PHAsset.fetchAssets(with: allPhotosOptions)
        }
        
        let gestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.onCellPressedLong(_:)))
        collectionView?.addGestureRecognizer(gestureRecognizer)
        
        collectionView?.allowsMultipleSelection = true
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // thumbnailsのサイズを計算
        let scale = UIScreen.main.scale
        // let cellSize = (collectionViewLayout as! UICollectionViewFlowLayout).itemSize
        let cellSize = self.cellSize
        thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)

        // 完了ボタン
        navigationItem.rightBarButtonItem = doneButtonItem
        doneButtonItem.action = #selector(self.onFinishSelectingAssets)
    }
    
    func onFinishSelectingAssets() {
        delegate?.onFinishSelectingAssets(selectedAssets: selectedAssets, assetCollection: assetCollection)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateCachedAssets()
    }

    // Asset詳細への遷移
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let destination = segue.destination as? AssetViewController else {
            fatalError("unexpected view controller for segue")
        }
        let indexPath = sender as! IndexPath
        destination.asset = fetchResult.object(at: indexPath.item)
        destination.assetCollection = assetCollection
    }

    // MARK: UICollectionView

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return fetchResult.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let asset = fetchResult.object(at: indexPath.item)

        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: GridViewCell.self), for: indexPath) as? GridViewCell else {
            fatalError("unexpected cell in collection view")
        }

        // Live Photoならバッジを表示
        if asset.mediaSubtypes.contains(.photoLive) {
            cell.livePhotoBadgeImage = PHLivePhotoView.livePhotoBadgeImage(options: .overContent)
        }
        
        cell.representedAssetIdentifier = asset.localIdentifier
        imageManager.requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil, resultHandler: { image, _ in
            // 遅延してすでに違う可能性を考慮
            if cell.representedAssetIdentifier == asset.localIdentifier {
                cell.thumbnailImage = image
            }
        })
        return cell
    }
    
    func onCellPressedLong(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.view! == collectionView! else {
            return
        }
        if recognizer.state == .began {
            let point = recognizer.location(in: recognizer.view)
            let indexPath = self.collectionView!.indexPathForItem(at: point)!
            self.performSegue(withIdentifier: "showAsset", sender: indexPath)
        }
    }
    
    // 本当はhilightでもアニメーションしたい

    // MARK: UIScrollView

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
         updateCachedAssets()
    }

    // MARK: Asset Caching

    fileprivate func resetCachedAssets() {
        imageManager.stopCachingImagesForAllAssets()
        previousPreheatRect = .zero
    }

    fileprivate func updateCachedAssets() {
        // visibleなときだけupdate
        guard isViewLoaded && view.window != nil else { return }

        // preheat windowは見える領域の倍の高さ
        let preheatRect = view!.bounds.insetBy(dx: 0, dy: -0.5 * view!.bounds.height)

        // Update only if the visible area is significantly different from the last preheated area.
        let delta = abs(preheatRect.midY - previousPreheatRect.midY)
        guard delta > view.bounds.height / 3 else { return }

        // キャッシュすべきアセットを計算、キャッシュ
        let (addedRects, removedRects) = differencesBetweenRects(previousPreheatRect, preheatRect)
        let addedAssets = addedRects
            .flatMap { rect in collectionView!.indexPathsForElements(in: rect) }
            .map { indexPath in fetchResult.object(at: indexPath.item) }
        let removedAssets = removedRects
            .flatMap { rect in collectionView!.indexPathsForElements(in: rect) }
            .map { indexPath in fetchResult.object(at: indexPath.item) }

        imageManager.startCachingImages(for: addedAssets,
            targetSize: thumbnailSize, contentMode: .aspectFill, options: nil)
        imageManager.stopCachingImages(for: removedAssets,
            targetSize: thumbnailSize, contentMode: .aspectFill, options: nil)

        previousPreheatRect = preheatRect
    }

    fileprivate func differencesBetweenRects(_ old: CGRect, _ new: CGRect) -> (added: [CGRect], removed: [CGRect]) {
        if old.intersects(new) {
            var added = [CGRect]()
            if new.maxY > old.maxY {
                added += [CGRect(x: new.origin.x, y: old.maxY,
                                    width: new.width, height: new.maxY - old.maxY)]
            }
            if old.minY > new.minY {
                added += [CGRect(x: new.origin.x, y: new.minY,
                                    width: new.width, height: old.minY - new.minY)]
            }
            var removed = [CGRect]()
            if new.maxY < old.maxY {
                removed += [CGRect(x: new.origin.x, y: new.maxY,
                                      width: new.width, height: old.maxY - new.maxY)]
            }
            if old.minY < new.minY {
                removed += [CGRect(x: new.origin.x, y: old.minY,
                                      width: new.width, height: new.minY - old.minY)]
            }
            return (added, removed)
        } else {
            return ([new], [old])
        }
    }
    
    // MARK: UI Actions

    @IBAction func addAsset(_ sender: AnyObject?) {

        // Create a dummy image of a random solid color and random orientation.
        let size = (arc4random_uniform(2) == 0) ?
            CGSize(width: 400, height: 300) :
            CGSize(width: 300, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        let color = UIColor(hue: CGFloat(arc4random_uniform(100))/100,
                            saturation: 1, brightness: 1, alpha: 1)
        let image = renderer.image { context in
            color.setFill()
            context.fill(context.format.bounds)
        }
        
        addAsset(image: image)
    }
    
    private func addAsset(image: UIImage) {
        // photo libraryに追加
        PHPhotoLibrary.shared().performChanges({
            let creationRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
            if let assetCollection = self.assetCollection {
                let addAssetRequest = PHAssetCollectionChangeRequest(for: assetCollection)
                addAssetRequest?.addAssets([creationRequest.placeholderForCreatedAsset!] as NSArray)
            }
        }) { success, error in
            if !success {
                print("error creating asset: \(error)")
            }
        }
    }

}

extension AssetGridViewController: UICollectionViewDelegateFlowLayout {
    // MARK: LayoutDelegates
    // 横に並ぶセルの数
    static let HORIZONTAL_CELLS_COUNT: CGFloat = 3
    // セルの間隔
    static let CELLS_MARGIN: CGFloat = 1
    // 周りの余白
    private var edgeInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
    
    fileprivate var cellSize: CGSize {
        let space = type(of: self).CELLS_MARGIN
        
        let contentWidth: CGFloat
        if let direction = (collectionViewLayout as? UICollectionViewFlowLayout)?.scrollDirection, direction == .horizontal {
            // 横スクロールなら縦並びのセル数として計算
            contentWidth = collectionView!.bounds.height - edgeInsets.top - edgeInsets.bottom
        } else {
            contentWidth = collectionView!.bounds.width - edgeInsets.right - edgeInsets.left
        }
        
        let cellLength = (contentWidth - space * (type(of: self).HORIZONTAL_CELLS_COUNT-1)) / type(of: self).HORIZONTAL_CELLS_COUNT
        
        return CGSize(width: cellLength, height: cellLength)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return cellSize
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return edgeInsets
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        let space = type(of: self).CELLS_MARGIN
        return space
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        let space = type(of: self).CELLS_MARGIN
        return space
    }
}

// MARK: PHPhotoLibraryChangeObserver
extension AssetGridViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let changes = changeInstance.changeDetails(for: fetchResult)
            else { return }

        DispatchQueue.main.sync {
            // 再フェッチして更新
            fetchResult = changes.fetchResultAfterChanges
            if changes.hasIncrementalChanges {
                guard let collectionView = self.collectionView else { fatalError() }
                collectionView.performBatchUpdates({
                    // delete, insert, reload, moveの順で更新するとインデックスがわかりやすい
                    if let removed = changes.removedIndexes, removed.count > 0 {
                        collectionView.deleteItems(at: removed.map({ IndexPath(item: $0, section: 0) }))
                    }
                    if let inserted = changes.insertedIndexes, inserted.count > 0 {
                        collectionView.insertItems(at: inserted.map({ IndexPath(item: $0, section: 0) }))
                    }
                    if let changed = changes.changedIndexes, changed.count > 0 {
                        collectionView.reloadItems(at: changed.map({ IndexPath(item: $0, section: 0) }))
                    }
                    changes.enumerateMoves { fromIndex, toIndex in
                        collectionView.moveItem(at: IndexPath(item: fromIndex, section: 0),
                                                to: IndexPath(item: toIndex, section: 0))
                    }
                })
            } else {
                collectionView!.reloadData()
            }
            resetCachedAssets()
        }
    }
}

