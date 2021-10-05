//
//  BTFLoadUnitsController.swift
//  BTF
//
//

import UIKit
import YUSKit

final class BTFLoadUnitsController: YUSViewController, UITableViewDataSource, UITableViewDelegate {
    private let session: BTFTransportSession
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    var didLoad: (() -> Void)?

    init(session: BTFTransportSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(tableView)
        tableView.configureForUnits(reuseIdentifier: "parkCell", delegate: self)
        title = session.title
        navigationItem.rightBarButtonItems = closeAndLegendBarItems(
            UIBarButtonItem(title: String(localized: "Load", bundle: btfBundle), primaryAction: UIAction { [weak self] _ in self?.load() })
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
    }
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { session.loadableUnitCount }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: "parkCell",
            for: indexPath
        ) as? BTFUnitCell else { return UITableViewCell() }
        cell.configure(with: session.loadableUnitSnapshot(at: indexPath.row)) { [weak session] selected in
            session?.setLoadableUnitSelected(selected, at: indexPath.row)
        }
        return cell
    }

    private func load() {
        guard session.loadSelectedUnits() else {
            yus_showMessage(String(localized: "Select units that fit in the transport.", bundle: btfBundle))
            return
        }
        didLoad?()
        dismiss(animated: true)
    }
}
