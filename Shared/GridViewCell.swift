/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Collection view cell for displaying an asset.
 */


import UIKit

class GridViewCell: UICollectionViewCell {

    @IBOutlet private var imageView: UIImageView!
    @IBOutlet private var livePhotoBadgeImageView: UIImageView!
    private var checkBoxView: CheckBoxView!

    var representedAssetIdentifier: String!

    var thumbnailImage: UIImage! {
        didSet {
            imageView.image = thumbnailImage
        }
    }
    var livePhotoBadgeImage: UIImage! {
        didSet {
            livePhotoBadgeImageView.image = livePhotoBadgeImage
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCheckBox()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupCheckBox()
    }
    
    override var isSelected: Bool {
        didSet {
            if isSelected {
                self.bringSubview(toFront: selectedBackgroundView!)
            } else {
                self.sendSubview(toBack: selectedBackgroundView!)
            }
        }
    }
    
    private func setupCheckBox() {
        let boxWidth = frame.width * 0.5
        let boxRect = CGRect(origin: .zero, size: CGSize(width: boxWidth, height: boxWidth))
        
        /*let falseBox = CheckBoxView(frame: boxRect, selected: false)
        self.addSubview(falseBox)*/
        
        let trueBox = CheckBoxView(frame: boxRect, selected: true)
        let backView = UIView(frame: frame)
        backView.backgroundColor = UIColor.clear
        backView.isUserInteractionEnabled = false
        backView.addSubview(trueBox)
        self.selectedBackgroundView = backView
        
        // backViewだけど最前面に持ってくる！！
        self.bringSubview(toFront: selectedBackgroundView!)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        livePhotoBadgeImageView.image = nil
    }
}
