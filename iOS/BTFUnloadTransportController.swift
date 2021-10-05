//
//  BTFUnloadTransportController.swift
//  BTF
//
//

import UIKit
import YUSKit

final class BTFUnloadTransportController: YUSViewController, UITableViewDataSource, UITableViewDelegate {
    private let session: BTFTransportSession
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let unloadItem = UIBarButtonItem()
    private var selectedIndex: Int?

    init(session: BTFTransportSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(tableView)
        tableView.configureForUnits(reuseIdentifier: "parkCell", delegate: self, bordered: false)
        title = session.title
        unloadItem.primaryAction = UIAction { [weak self] _ in self?.unload() }
        unloadItem.isEnabled = false
        navigationItem.rightBarButtonItems = closeAndLegendBarItems(unloadItem)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
    }
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { session.unitCount }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: "parkCell",
            for: indexPath
        ) as? BTFUnitCell else { return UITableViewCell() }
        cell.configure(with: session.unitSnapshot(at: indexPath.row))
        return cell
    }
    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedIndex = indexPath.row
        let ready = session.isUnitReady(at: indexPath.row)
        unloadItem.isEnabled = ready
        unloadItem.title = ready ? String(localized: "Unload", bundle: btfBundle) : nil
    }

    private func unload() {
        guard let selectedIndex, session.unloadUnit(at: selectedIndex) else { return }
        dismiss(animated: true)
    }
}
