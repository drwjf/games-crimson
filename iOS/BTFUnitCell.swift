//
//  BTFUnitCell.swift
//  BTF
//
//

import UIKit
import YUSKit
#if PREMIUM
import YUSPremium
#else
import YUSAd
#endif

final class BTFUnitCell: UITableViewCell {
    private let contentStack = UIStackView()
    private let unitView = UIView()
    private let unitImageView = UIImageView()
    private let doneImageView = UIImageView()
    private let hpImageView = UIImageView()
    private let xpImageView = UIImageView()
    private let unitLabel = UILabel()
    private let selectedSwitch = UISwitch()
    private var selectionChanged: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .blue
        separatorInset = .zero
        [unitImageView, doneImageView, hpImageView, xpImageView].forEach(unitView.addSubview)
        [unitView, unitLabel, selectedSwitch].forEach(contentStack.addArrangedSubview)
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            unitView.widthAnchor.constraint(equalToConstant: 48),
            unitView.heightAnchor.constraint(equalToConstant: 42),
        ])
        unitLabel.numberOfLines = 0
        unitLabel.textAlignment = .left
        unitLabel.font = .preferredFont(forTextStyle: .footnote)
        unitLabel.adjustsFontForContentSizeCategory = true
        unitLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        selectedSwitch.setContentCompressionResistancePriority(.required, for: .horizontal)
        selectedSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            selectionChanged?(selectedSwitch.isOn)
        }, for: .valueChanged)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        selectionChanged = nil
        selectedSwitch.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        unitImageView.frame = unitView.bounds
        doneImageView.frame = unitImageView.frame
        let statusFrames = BTFUnitStatusFrames(in: unitView.bounds)
        hpImageView.frame = statusFrames.health
        xpImageView.frame = statusFrames.experience
    }

    func configure(with snapshot: BTFUnitSnapshot, selectionChanged: ((Bool) -> Void)? = nil) {
        unitImageView.image = BTFResources.image(named: snapshot.unitImageName)
        doneImageView.image = BTFResources.image(named: snapshot.doneImageName)
        hpImageView.image = BTFResources.image(named: snapshot.hpImageName)
        xpImageView.image = BTFResources.image(named: snapshot.xpImageName)
        unitLabel.text = snapshot.text
        selectedSwitch.isHidden = !snapshot.selectable
        selectedSwitch.isOn = snapshot.selected
        selectedSwitch.accessibilityLabel = snapshot.text
        self.selectionChanged = selectionChanged
    }
}

extension UITableView {
    /// The setup shared by every table of unit cells.
    func configureForUnits(reuseIdentifier: String, delegate: UITableViewDataSource & UITableViewDelegate,
                           bordered: Bool = true) {
        YUSGame.setupTableView(self)
        register(BTFUnitCell.self, forCellReuseIdentifier: reuseIdentifier)
        rowHeight = UITableView.automaticDimension
        estimatedRowHeight = 50
        dataSource = delegate
        self.delegate = delegate
        if bordered {
            layer.borderColor = UIColor.secondaryLabel.cgColor
            layer.borderWidth = 0.5
            if #available(iOS 17.0, *) {
                // A CGColor does not follow light/dark changes by itself.
                registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (table: UITableView, _: UITraitCollection) in
                    table.layer.borderColor = UIColor.secondaryLabel.resolvedColor(with: table.traitCollection).cgColor
                }
            }
        }
    }
}

extension UIViewController {
    /// Close and emoji-legend buttons, followed by any screen-specific items.
    func closeAndLegendBarItems(_ extraItems: UIBarButtonItem...) -> [UIBarButtonItem] {
        let legendItem = UIBarButtonItem(image: YUSImages.questionImage, primaryAction: UIAction { [weak self] _ in
            self?.yus_showMessage(BTFPlayBridge.emojiLegends)
        })
        legendItem.accessibilityLabel = String(localized: "Legend", bundle: btfBundle,
                                               comment: "Accessibility label of the button that explains the emoji in unit and terrain info.")
        return [
            UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }),
            legendItem,
        ] + extraItems
    }
}
