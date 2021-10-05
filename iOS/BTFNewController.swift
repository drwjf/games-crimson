//
//  BTFNewController.swift
//  BTF
//
//

import UIKit
import YUSKit

public final class BTFNewController: UIViewController, YUSNewController {
    public weak var delegate: (any YUSNewControllerDelegate)?

    private let game = BTFGame()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var isStarting = false

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = String(localized: "Choose a Scenario", bundle: btfBundle)
        view.backgroundColor = .systemBackground

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "scenario")
        view.addSubview(tableView)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.flashScrollIndicators()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
    }

    private func chooseSide(at index: Int) {
        guard let sideNames = game.sideNames(index: index) else {
            startScenario(at: index, side: 0)
            return
        }

        var actions = sideNames.enumerated().map { side, name in
            UIAlertAction(title: name, style: .default) { [weak self] _ in
                self?.startScenario(at: index, side: side)
            }
        }
        actions.append(UIAlertAction(title: String(localized: "Cancel", bundle: btfBundle), style: .cancel))
        yus_presentMenu(String(localized: "Choose a Side", bundle: btfBundle), actions: actions, promotes: false)
    }

    private func startScenario(at index: Int, side: Int) {
        guard !isStarting else { return }
        isStarting = true
        navigationController?.isModalInPresentation = true
        view.isUserInteractionEnabled = false

        let savedURL = game.startIfValid(index: index, side: side)
        guard let savedURL else {
            isStarting = false
            navigationController?.isModalInPresentation = false
            view.isUserInteractionEnabled = true
            yus_showMessage(String(localized: "Operation failed.", bundle: btfBundle))
            return
        }
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            delegate?.newController(self, didCreate: savedURL)
        }
    }
}

extension BTFNewController: UITableViewDataSource, UITableViewDelegate {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        game.scenarioNames.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "scenario", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = game.scenarioNames[indexPath.row]
        cell.contentConfiguration = content
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        chooseSide(at: indexPath.row)
    }
}
