//
//  BTFBuildingController.swift
//  BTF
//
//

import UIKit
import YUSKit

final class BTFBuildingController: YUSViewController, UITableViewDataSource, UITableViewDelegate {
    private let session: BTFContainerSession
    private let notchView = UIView()
    private let serviceTable = UITableView(frame: .zero, style: .insetGrouped)
    private let buildTable = UITableView(frame: .zero, style: .insetGrouped)
    private let activateButton = YUSButton(style: .tinted)
    private let repairButton = YUSButton(style: .tinted)
    private let loadCrystalsButton = YUSButton(style: .tinted)
    private let loadUnitsButton = YUSButton(style: .tinted)
    private let buildButton = YUSButton(style: .tinted)
    private var serviceIndex: Int?
    private var buildIndex: Int?
    var didMutate: (() -> Void)?

    init(session: BTFContainerSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(notchView)
        configureTable(serviceTable, reuseIdentifier: "serviceCell")
        configureTable(buildTable, reuseIdentifier: "factoryCell")
        configure(activateButton, title: String(localized: "Activate", bundle: btfBundle)) { [weak self] in self?.activate() }
        configure(repairButton, title: String(localized: "Repair", bundle: btfBundle)) { [weak self] in self?.repair() }
        configure(loadCrystalsButton, title: String(localized: "Load Crystals", bundle: btfBundle)) { [weak self] in self?.loadCrystals() }
        configure(loadUnitsButton, title: String(localized: "Load Units", bundle: btfBundle)) { [weak self] in self?.loadUnits() }
        configure(buildButton, title: String(localized: "Build", bundle: btfBundle)) { [weak self] in self?.build() }
        title = session.title
        navigationItem.rightBarButtonItems = closeAndLegendBarItems()
    }

    private func configure(_ button: YUSButton, title: String, handler: @escaping () -> Void) {
        notchView.addSubview(button)
        button.setTitle(title, for: .normal)
        button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        button.isHidden = true
    }

    private func configureTable(_ table: UITableView, reuseIdentifier: String) {
        notchView.addSubview(table)
        table.configureForUnits(reuseIdentifier: reuseIdentifier, delegate: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        notchView.frame = view.safeAreaLayoutGuide.layoutFrame.integral
        let size = notchView.bounds.size
        let height = YUSLayoutService.buttonHeight
        let pad: CGFloat = 20
        if size.width > size.height {
            let serviceWidth = floor(size.width * 2 / 3)
            let tableHeight = size.height - height
            let buttonWidth = floor((serviceWidth - pad) / 4)
            serviceTable.frame = CGRect(x: 0, y: 0, width: serviceWidth, height: tableHeight)
            for (index, button) in [activateButton, repairButton, loadCrystalsButton, loadUnitsButton].enumerated() {
                button.frame = CGRect(x: pad + buttonWidth * CGFloat(index), y: tableHeight,
                                      width: buttonWidth, height: height)
            }
            let buildWidth = floor(size.width / 3)
            buildTable.frame = CGRect(x: size.width - buildWidth, y: 0, width: buildWidth, height: tableHeight)
            buildButton.frame = CGRect(x: size.width - pad - buttonWidth, y: tableHeight,
                                       width: buttonWidth, height: height)
        } else {
            let buttonWidth: CGFloat = 100
            let tableWidth = size.width - buttonWidth
            let serviceHeight = floor(size.height * 2 / 3)
            serviceTable.frame = CGRect(x: 0, y: 0, width: tableWidth, height: serviceHeight)
            for (index, button) in [activateButton, repairButton, loadCrystalsButton, loadUnitsButton].enumerated() {
                button.frame = CGRect(x: tableWidth, y: pad + CGFloat(index) * (height + pad),
                                      width: buttonWidth, height: height)
            }
            buildTable.frame = CGRect(x: 0, y: serviceHeight, width: tableWidth,
                                      height: floor(size.height / 3))
            buildButton.frame = CGRect(x: tableWidth, y: serviceHeight + pad,
                                       width: buttonWidth, height: height)
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection _: Int) -> Int {
        tableView === serviceTable ? session.serviceUnitCount : session.buildUnitCount
    }
    func tableView(_ tableView: UITableView, titleForHeaderInSection _: Int) -> String? {
        tableView === serviceTable ? String(localized: "Service", bundle: btfBundle)
            : String(localized: "Build", bundle: btfBundle)
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = tableView === serviceTable ? "serviceCell" : "factoryCell"
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: identifier,
            for: indexPath
        ) as? BTFUnitCell else { return UITableViewCell() }
        cell.configure(with: tableView === serviceTable
            ? session.serviceSnapshot(at: indexPath.row) : session.buildSnapshot(at: indexPath.row))
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView === serviceTable {
            buildTable.indexPathForSelectedRow.map { buildTable.deselectRow(at: $0, animated: false) }
            buildIndex = nil
            serviceIndex = indexPath.row
        } else {
            serviceTable.indexPathForSelectedRow.map { serviceTable.deselectRow(at: $0, animated: false) }
            serviceIndex = nil
            buildIndex = indexPath.row
        }
        updateButtons()
    }

    private func updateButtons() {
        if let serviceIndex {
            activateButton.isHidden = !session.canActivateService(at: serviceIndex)
            repairButton.isHidden = !session.canRepairService(at: serviceIndex)
            loadCrystalsButton.isHidden = !session.canLoadCrystals(at: serviceIndex)
            loadUnitsButton.isHidden = !session.canLoadUnits(at: serviceIndex)
        } else {
            [activateButton, repairButton, loadCrystalsButton, loadUnitsButton].forEach { $0.isHidden = true }
        }
        buildButton.isHidden = buildIndex.map { !session.canBuild(at: $0) } ?? true
    }
    private func refresh() {
        title = session.title
        serviceTable.reloadData()
        buildTable.reloadData()
        // Reloading drops the highlight; keep it in step with the active buttons.
        serviceIndex.map { select(row: $0, in: serviceTable) }
        buildIndex.map { select(row: $0, in: buildTable) }
        updateButtons()
    }
    private func select(row: Int, in table: UITableView) {
        guard row < table.numberOfRows(inSection: 0) else { return }
        table.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
    }
    private func refreshAfterMutation() {
        refresh()
        didMutate?()
    }
    private func activate() {
        guard let serviceIndex, session.activateService(at: serviceIndex) else { return }
        dismiss(animated: true)
    }
    private func repair() {
        guard let serviceIndex, session.repairService(at: serviceIndex) else { return }
        refreshAfterMutation()
    }
    private func build() {
        guard let buildIndex, session.build(at: buildIndex) else { return }
        refreshAfterMutation()
    }
    private func loadCrystals() {
        guard let serviceIndex, let transport = session.transportSession(at: serviceIndex) else { return }
        let controller = BTFLoadCrystalsController(session: transport)
        controller.didLoad = { [weak self] in self?.refreshAfterMutation() }
        present(UINavigationController(rootViewController: controller), animated: true)
    }
    private func loadUnits() {
        guard let serviceIndex, let transport = session.transportSession(at: serviceIndex) else { return }
        let controller = BTFLoadUnitsController(session: transport)
        controller.didLoad = { [weak self] in
            self?.serviceIndex = nil
            self?.refreshAfterMutation()
        }
        present(UINavigationController(rootViewController: controller), animated: true)
    }
}
