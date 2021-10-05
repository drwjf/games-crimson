//
//  BTFLoadCrystalsController.swift
//  BTF
//
//

import UIKit
import YUSKit

final class BTFLoadCrystalsController: YUSViewController {
    private let session: BTFTransportSession
    private let notchView = UIView()
    private let crystalLabel = UILabel()
    private let crystalSlider = UISlider()
    var didLoad: (() -> Void)?

    init(session: BTFTransportSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(notchView)
        notchView.addSubview(crystalLabel)
        crystalLabel.textAlignment = .center
        notchView.addSubview(crystalSlider)
        crystalSlider.minimumValue = Float(session.minimumCrystals)
        crystalSlider.maximumValue = Float(session.maximumCrystals)
        crystalSlider.value = Float(session.currentCrystals)
        crystalSlider.accessibilityLabel = String(localized: "Crystals", bundle: btfBundle)
        crystalSlider.addAction(UIAction { [weak self] _ in self?.updateLabel() }, for: .valueChanged)
        title = session.title
        updateLabel()
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.done() })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        notchView.frame = view.safeAreaLayoutGuide.layoutFrame.integral
        let width = notchView.bounds.width - 20
        crystalLabel.frame = CGRect(x: 10, y: 0, width: width, height: YUSLayoutService.buttonHeight / 2)
        crystalSlider.frame = CGRect(x: 10, y: YUSLayoutService.buttonHeight / 2,
                                     width: width, height: YUSLayoutService.buttonHeight)
    }

    private func updateLabel() {
        crystalLabel.text = "\(Int(crystalSlider.value)) 💎"
        crystalSlider.accessibilityValue = "\(Int(crystalSlider.value))"
    }
    private func done() {
        session.applyCrystals(Int(crystalSlider.value))
        didLoad?()
        dismiss(animated: true)
    }
}
