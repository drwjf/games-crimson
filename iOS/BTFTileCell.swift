//
//  BTFTileCell.swift
//  BTF
//
//

import QuartzCore
import UIKit

struct BTFUnitStatusFrames {
    let health: CGRect
    let experience: CGRect

    init(in bounds: CGRect) {
        let hpWidth = floor(bounds.height / 3)
        let hpHeight = floor(bounds.height / 8)
        health = CGRect(x: bounds.minX + hpWidth, y: bounds.maxY - hpHeight,
                        width: hpWidth, height: hpHeight)

        let xpWidth = floor(bounds.width / 6)
        let xpXOffset = floor(40 / 144 * bounds.width)
        let xpYOffset = floor(8 / 126 * bounds.width)
        experience = CGRect(x: bounds.maxX - xpXOffset - xpWidth,
                            y: bounds.minY + xpYOffset,
                            width: xpWidth, height: floor(xpWidth * 75 / 42))
    }
}

final class BTFTileCell: UICollectionViewCell {
    private let terrainLayer = CALayer()
    private let unitLayer = CALayer()
    private let doneLayer = CALayer()
    private let hpLayer = CALayer()
    private let xpLayer = CALayer()
    private let fogLayer = CALayer()
    private let cursorLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        [terrainLayer, unitLayer, doneLayer, hpLayer, xpLayer, fogLayer, cursorLayer]
            .forEach(contentView.layer.addSublayer)
        fogLayer.opacity = 0.5
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        [terrainLayer, unitLayer, doneLayer, fogLayer, cursorLayer].forEach { $0.frame = bounds }
        let statusFrames = BTFUnitStatusFrames(in: bounds)
        hpLayer.frame = statusFrames.health
        xpLayer.frame = statusFrames.experience
    }

    func configure(with snapshot: BTFTileSnapshot) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        terrainLayer.contents = BTFResources.image(named: snapshot.terrainImageName)?.cgImage
        unitLayer.contents = BTFResources.image(named: snapshot.unitImageName)?.cgImage
        doneLayer.contents = BTFResources.image(named: snapshot.doneImageName)?.cgImage
        hpLayer.contents = BTFResources.image(named: snapshot.hpImageName)?.cgImage
        xpLayer.contents = BTFResources.image(named: snapshot.xpImageName)?.cgImage
        fogLayer.contents = BTFResources.image(named: snapshot.fogImageName)?.cgImage
        cursorLayer.contents = BTFResources.image(named: snapshot.cursorImageName)?.cgImage
        CATransaction.commit()
        accessibilityLabel = snapshot.accessibilityText
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { .staticText }
        set {}
    }
}
