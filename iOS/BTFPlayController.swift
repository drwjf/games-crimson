//
//  BTFPlayController.swift
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

private let contextButtonSpacing: CGFloat = 4

/// The actions of `unitOrdersView`, in display order.
private enum BTFUnitOrder: Int {
    case next, done, info
}

public final class BTFPlayController: YUSViewController, YUSTilesViewDelegate,
    YUSMiniMapViewDelegate, YUSAdTurnViewDelegate, BTFPlayBridgeUI
{
    private let savedURL: URL
    private let bridge = BTFPlayBridge()
    private let mapView: YUSTilesView
    private let topMenuView = YUSTopMenuView(frame: .zero)
    private let miniMapView = YUSMiniMapView(frame: .zero)
    private let unitInfoLabel = UILabel(frame: .zero)
    private let unitOrdersView = YUSTopMenuView(frame: .zero)
    private let sweepView = YUSTopMenuView(frame: .zero)
    private let unloadView = YUSTopMenuView(frame: .zero)
    private let repairView = YUSTopMenuView(frame: .zero)
    private let endTurnButton = YUSButton(style: .filled)
    private let crystalsButton = YUSButton(style: .status)
    private let turnButton = YUSButton(style: .status)
    private let turnView = YUSAdTurnView(frame: .zero)
    private var initialized = false
    private var needsComputerOpeningTurn = false
    private var maximumUnitInfoFrame = CGRect.zero
    private var lastBounds = CGRect.zero
    private var lastHUDMargins = UIEdgeInsets.zero
    private var pendingCenterTile: IndexPath?
    private var currentPanel: BTFPanelSnapshot?
    private var messages: [String] = []
    private var miniMapNeedsUpdate = true
    private var miniMapUpdateScheduled = false
    private var renderedMiniMapSize = CGSize.zero
    private var loadFailed = false
    private var loadErrorPresented = false
    private var gameOverSummary: (title: String, message: String)?
    private var gameOverPresented = false
    private var isProcessing = false {
        didSet {
            isModalInPresentation = isProcessing
            view.isUserInteractionEnabled = !isProcessing
            if !isProcessing, miniMapNeedsUpdate { scheduleMiniMapUpdate() }
        }
    }

    @objc public init(savedURL: URL) {
        self.savedURL = savedURL
        let layout = YUSHexagonLayout()
        layout.zoom = YUSLayoutService.zoomRatio
        layout.tileWidth = CGFloat(BTF_TILE_WIDTH)
        layout.tileHeight = CGFloat(BTF_TILE_HEIGHT)
        layout.tileShiftX = BTF_TILE_SHIFT_X
        layout.tileShiftY = CGFloat(BTF_TILE_SHIFT_Y)
        mapView = YUSTilesView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        bridge.ui = self
        guard bridge.start(withSavedURL: savedURL) else {
            loadFailed = true
            return
        }

        view.addSubview(mapView)
        mapView.register(BTFTileCell.self, forCellWithReuseIdentifier: YUSTilesViewCellReuseID)
        mapView.tileDelegate = self
        if let layout = mapView.collectionViewLayout as? YUSHexagonLayout {
            layout.mapX = bridge.mapWidth
            layout.mapY = bridge.mapHeight
        }

        view.addSubview(topMenuView)
        topMenuView.actions = [YUSAction(
            title: String(localized: "Game", bundle: btfBundle),
            image: YUSImages.menuImage,
            style: .default
        ) { [weak self] _ in self?.showGameMenu() }]

        view.addSubview(endTurnButton)
        endTurnButton.accessibilityLabel = String(localized: "End Turn", bundle: btfBundle)
        endTurnButton.setImage(YUSImages.endTurnImage, for: .normal)
        endTurnButton.tintColor = .white
        endTurnButton.addAction(UIAction { [weak self] _ in self?.endTurn() }, for: .touchUpInside)
        for button in [crystalsButton, turnButton] {
            button.addAction(UIAction { [weak self] _ in self?.showObjectives() }, for: .touchUpInside)
            view.addSubview(button)
        }

        view.addSubview(miniMapView)
        miniMapView.delegate = self
        miniMapView.mapX = bridge.mapWidth
        miniMapView.mapY = bridge.mapHeight

        YUSGame.setupInfoLabel(unitInfoLabel)
        view.addSubview(unitInfoLabel)
        view.addSubview(unitOrdersView)
        unitOrdersView.actions = [
            YUSAction(
                title: String(localized: "Next Unit", bundle: btfBundle),
                image: YUSImages.rightImage,
                style: .default
            ) { [weak self] _ in self?.selectNextUnit() },
            YUSAction(
                title: String(localized: "Finish Unit", bundle: btfBundle),
                image: YUSImages.acceptImage,
                style: .default
            ) { [weak self] _ in self?.finishUnit() },
            YUSAction(
                title: String(localized: "Info", bundle: btfBundle),
                image: YUSImages.infoImage,
                style: .default
            ) { [weak self] _ in self?.showPanelDetails() },
        ]
        view.addSubview(sweepView)
        sweepView.actions = [YUSAction(
            title: String(localized: "Sweep Mines", bundle: btfBundle),
            image: YUSImages.eraserImage,
            style: .default
        ) { [weak self] _ in self?.beginMineSweep() }]
        sweepView.isHidden = true
        view.addSubview(unloadView)
        unloadView.actions = [YUSAction(
            title: String(localized: "Unload", bundle: btfBundle),
            image: YUSImages.minimizeImage,
            style: .default
        ) { [weak self] _ in self?.showUnload() }]
        unloadView.isHidden = true
        view.addSubview(repairView)
        repairView.actions = [YUSAction(
            title: String(localized: "Repair", bundle: btfBundle),
            image: UIImage(systemName: "wrench.and.screwdriver"),
            style: .default
        ) { [weak self] _ in self?.repairSelectedUnit() }]
        repairView.isHidden = true

        view.addSubview(turnView)
        turnView.delegate = self
        turnView.isHidden = true

        for name in [UIAccessibility.voiceOverStatusDidChangeNotification,
                     UIAccessibility.switchControlStatusDidChangeNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(accessibilityStatusDidChange), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    /// Tiles and the unit panel switch between emoji and spoken labels with VoiceOver.
    @objc private func accessibilityStatusDidChange() {
        guard initialized, !loadFailed else { return }
        mapView.configAllItems()
        updatePanel(bridge.currentPanelSnapshot())
    }

    /// Autosave When Leaving App (YUSFileService, app-wide, default on): iOS may terminate a suspended
    /// app at any time, so keep what the player did this turn in the game's own file.
    /// Not while the turn report is up: its Quit restores the previous state.
    @objc private func applicationDidEnterBackground() {
        guard YUSFileService.autosaveWhenLeavingApp,
              initialized, !loadFailed, !isProcessing, turnView.isHidden else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "Save Game")
        defer { UIApplication.shared.endBackgroundTask(task) }
        _ = saveGame()
    }

    /// Saves the game to its own file, with an up-to-date Load Game thumbnail.
    private func saveGame() -> Bool {
        try? FileManager.default.createDirectory(at: savedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard bridge.save(to: savedURL) else { return false }
        updateMiniMap()
        if let image = miniMapView.image() { YUSFileService.dumpImage(image, forSavedURL: savedURL) }
        return true
    }

    deinit {
        MainActor.assumeIsolated {
            bridge.stop()
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !initialized, !loadFailed {
            needsComputerOpeningTurn = !bridge.initializeSession()
            initialized = true
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if loadFailed {
            showLoadError()
            return
        }
        updateMiniMap()
        YUSAudio.sharedInstance.loopMusic("default", inBundle: "btf")
        restorePendingCenterTile()
        showGameOverIfNeeded()
        if needsComputerOpeningTurn {
            // The player chose the side that moves second: show the computer's turn like any other.
            needsComputerOpeningTurn = false
            processTurn { $0.playComputerTurn() }
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !loadFailed, bridge.mapWidth > 0, bridge.mapHeight > 0 else { return }
        let margins = YUSLayoutService.hudMargins(for: view)
        guard lastBounds != view.bounds || lastHUDMargins != margins else { return }
        lastBounds = view.bounds
        lastHUDMargins = margins
        let size = view.bounds.size
        let insets = view.safeAreaInsets
        let buttonSize = YUSLayoutService.squareButtonSize
        topMenuView.frame = CGRect(x: margins.left, y: insets.top, width: buttonSize, height: buttonSize)
        topMenuView.layer.cornerRadius = buttonSize / 2
        endTurnButton.frame = CGRect(x: size.width - margins.right - buttonSize, y: insets.top,
                                     width: buttonSize, height: buttonSize)
        endTurnButton.layer.cornerRadius = buttonSize / 2
        endTurnButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: round(buttonSize * 0.4), weight: .semibold), forImageIn: .normal)
        // Status row between the top menu and End Turn, capped so it doesn't stretch on wide windows.
        let statusWidth = max(0, min(endTurnButton.frame.minX - topMenuView.frame.maxX, buttonSize * 6))
        let statusItemWidth = floor(statusWidth / 2)
        turnButton.frame = CGRect(x: endTurnButton.frame.minX - statusItemWidth, y: insets.top,
                                  width: statusItemWidth, height: buttonSize)
        crystalsButton.frame = turnButton.frame.offsetBy(dx: -statusItemWidth, dy: 0)
        for button in [crystalsButton, turnButton] {
            button.layer.cornerRadius = buttonSize / 2
        }

        let mapSize = bridge.mapPixelSize
        var miniWidth = YUSLayoutService.miniMapWidth
        var miniHeight = floor(mapSize.height * miniWidth / mapSize.width)
        // Stop above the unit orders and the context buttons on top of them.
        let bottomControlsHeight = unitInfoHeight + 2 * buttonSize + contextButtonSpacing
        let maximumHeight = max(1, size.height - insets.bottom - bottomControlsHeight - endTurnButton.frame.maxY)
        if miniHeight > maximumHeight {
            miniHeight = maximumHeight
            miniWidth = floor(mapSize.width * miniHeight / mapSize.height)
        }
        miniMapView.frame = CGRect(x: size.width - margins.right - miniWidth, y: endTurnButton.frame.maxY,
                                   width: miniWidth, height: miniHeight)
        layoutBottomControls()
        mapView.frame = view.bounds
        mapView.contentInset = UIEdgeInsets(top: miniMapView.frame.maxY,
                                            left: topMenuView.frame.maxX,
                                            bottom: insets.bottom + buttonSize + unitInfoHeight,
                                            right: margins.right + miniWidth)
        miniMapView.updateViewPort(of: mapView)
        turnView.frame = view.bounds
        if miniMapView.bounds.size != renderedMiniMapSize { scheduleMiniMapUpdate() }
    }

    public override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        // Unfolding can change the margins after the size transition; relayout the HUD.
        view.setNeedsLayout()
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // Folding, rotating, or resizing changes the map insets; keep the same tile centered.
        // Keep an earlier pending tile: while a full-screen controller covers the map, its bounds are stale.
        guard !loadFailed, bridge.mapWidth > 0 else { return }
        pendingCenterTile = pendingCenterTile ?? visibleCenterTile()
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.restorePendingCenterTile()
        }
    }

    /// Re-centers once the map is on screen again, so layout uses the final bounds.
    private func restorePendingCenterTile() {
        guard !loadFailed, bridge.mapWidth > 0, view.window != nil, let centerTile = pendingCenterTile else { return }
        pendingCenterTile = nil
        view.layoutIfNeeded()
        mapView.scrollToItem(at: centerTile, at: [.centeredVertically, .centeredHorizontally], animated: false)
        miniMapView.updateViewPort(of: mapView)
    }

    private func visibleCenterTile() -> IndexPath? {
        guard let layout = mapView.collectionViewLayout as? YUSTileLayoutHitTest else { return nil }
        // Match scrollToItem, which centers within the safe-area-adjusted insets.
        let visible = mapView.bounds.inset(by: mapView.adjustedContentInset)
        guard !visible.isEmpty else { return nil }
        return layout.indexPath(at: CGPoint(x: visible.midX, y: visible.midY))
    }

    public func configCell(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
        (cell as? BTFTileCell)?.configure(with: bridge.tileSnapshot(atRow: indexPath.row, section: indexPath.section))
    }
    public func tilesView(_ tilesView: YUSTilesView, didTap indexPath: IndexPath) {
        bridge.handleTap(atRow: indexPath.row, section: indexPath.section)
        bridge.centerOnCursor()
        updateContextButtons()
    }
    public func tilesView(_ tilesView: YUSTilesView, didLongPress indexPath: IndexPath) {
        yus_showMessage(bridge.information(atRow: indexPath.row, section: indexPath.section,
                                           emoji: !UIAccessibility.isVoiceOverRunning))
    }
    public func tilesViewDidEndScrolling(_ tilesView: YUSTilesView) { miniMapView.updateViewPort(of: tilesView) }
    public func tilesViewDidEndZooming(_ tilesView: YUSTilesView) { tilesViewDidEndScrolling(tilesView) }
    public func miniMapView(_: YUSMiniMapView, didTap indexPath: IndexPath) {
        guard isValidMapLocation(row: indexPath.row, section: indexPath.section) else { return }
        mapView.scrollToItem(at: indexPath, at: [.centeredVertically, .centeredHorizontally], animated: true)
    }

    private func isValidMapLocation(row: Int, section: Int) -> Bool {
        row >= 0 && row < bridge.mapWidth && section >= 0 && section < bridge.mapHeight
    }

    private func updateMiniMap() {
        let size = miniMapView.bounds.size
        guard !isProcessing, size.width > 0, size.height > 0,
              miniMapNeedsUpdate || size != renderedMiniMapSize else { return }
        miniMapView.update(with: bridge.miniMapImage(size: size))
        renderedMiniMapSize = size
        miniMapNeedsUpdate = false
    }

    private func scheduleMiniMapUpdate() {
        miniMapNeedsUpdate = true
        guard !miniMapUpdateScheduled else { return }
        miniMapUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            miniMapUpdateScheduled = false
            updateMiniMap()
        }
    }

    private func showLoadError() {
        guard !loadErrorPresented else { return }
        loadErrorPresented = true
        let title = String(localized: "Operation failed.", bundle: btfBundle)
        yus_showMenu(title, actions: [
            YUSAction(title: String(localized: "Exit Game", bundle: btfBundle), style: .cancel) { [weak self] _ in
                self?.quit()
            },
        ])
    }

    private func showGameMenu() {
        var actions: [YUSAction] = []
        if bridge.undoable {
            actions.append(YUSAction(title: String(localized: "Undo", bundle: btfBundle), style: .default) { [weak self] _ in
                guard let self else { return }
                bridge.undo()
                refreshGameState()
            })
        }
        actions += [
            YUSAction(title: String(localized: "Exit Game", bundle: btfBundle), style: .default) { [weak self] _ in self?.saveAndExit() },
            YUSAction(title: String(localized: "Game Objectives", bundle: btfBundle), style: .default) { [weak self] _ in self?.showObjectives() },
            YUSAction(title: String(localized: "Game Settings", bundle: btfBundle), style: .default) { [weak self] _ in self?.showSettings() },
            YUSAction(title: String(localized: "Save a Copy", bundle: btfBundle), style: .default) { [weak self] _ in self?.branchGame() },
            YUSAction(title: String(localized: "Continue", bundle: btfBundle), style: .cancel, handler: nil),
        ]
        if let manaAction = YUSManaGate.makeAction(from: self) {
            actions.insert(manaAction, at: actions.count - 1)
        }
        yus_showMenu(
            String(localized: "Game Menu", bundle: btfBundle),
            actions: actions,
            reportsBug: true,
            savedURL: savedURL
        )
    }

    private func saveAndExit() {
        guard !isProcessing else { return }
        guard saveGame() else {
            yus_showMessage(String(localized: "Operation failed.", bundle: btfBundle))
            return
        }
        quit()
    }
    private func quit() {
        guard !isProcessing else { return }
        dismiss(animated: true) { [bridge] in bridge.stop() }
    }
    private func showSettings() {
        present(UINavigationController(rootViewController: BTFSettingsController()), animated: true)
    }
    private func branchGame() {
        guard !isProcessing else { return }
        guard let url = bridge.branchSave(from: savedURL) else {
            yus_showMessage(String(localized: "Operation failed.", bundle: btfBundle))
            return
        }
        yus_presentBranchDone(url.lastPathComponent, completion: nil)
    }
    private func showObjectives() {
        guard let objectives = bridge.objectives(), objectives.count == 2 else { return }
        yus_showTitle(objectives[0], message: objectives[1])
    }
    private func endTurn() {
        processTurn { $0.endTurn() }
    }
    /// Runs engine turn processing behind the turn view, then shows its report.
    private func processTurn(_ body: @escaping @MainActor (BTFPlayBridge) -> Void) {
        guard !isProcessing else { return }
        isProcessing = true
        messages = []
        turnView.title = "\(String(localized: "Turn", bundle: btfBundle)) #\(bridge.turn)"
        turnView.startTurnProcessing()
        // The engine owns the main thread until the turn is over, so let the turn view reach the screen first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
            body(bridge)
            finishTurn()
        }
    }
    private func finishTurn() {
        isProcessing = false
        turnView.stopTurnProcessing()
        refreshGameState()
        if gameOverSummary != nil {
            turnView.isHidden = true
            showGameOverIfNeeded()
            return
        }
        bridge.centerOnCursor()
        if messages.isEmpty {
            messages.append(String(localized: "Nothing to report.", bundle: btfBundle))
        }
        turnView.reloadThenScrollToBottom()
    }
    /// The mission is finished for good; leaving is the only way forward.
    private func showGameOverIfNeeded() {
        guard let summary = gameOverSummary, !gameOverPresented, view.window != nil else { return }
        gameOverPresented = true
        turnView.isHidden = true
        unitOrdersView.isHidden = true
        endTurnButton.isHidden = true
        yus_showTitle(summary.title, message: summary.message) { [weak self] in
            guard let self else { return }
            yus_showMenu(summary.title, actions: [
                YUSAction(title: String(localized: "Exit Game", bundle: btfBundle), style: .cancel) { [weak self] _ in
                    self?.saveAndExit()
                },
            ])
        }
    }
    private func showPanelDetails() { currentPanel.map { yus_showMessage($0.details) } }
    private func selectNextUnit() {
        bridge.selectNextUnit()
        bridge.centerOnCursor()
    }
    private func finishUnit() {
        bridge.finishUnit()
        bridge.centerOnCursor()
    }
    private func beginMineSweep() {
        bridge.beginMineSweep()
        updateContextButtons()
    }
    private func repairSelectedUnit() {
        // Charges one mana with no free Continue when empty; Premium repairs for free.
        YUSManaGate.spend(from: self) { [weak self] in
            // The ad build's mana prompt runs this later; the game may have ended meanwhile.
            guard let self, !isProcessing else { return }
            bridge.repairSelectedUnit()
        }
    }
    private func showUnload() {
        guard let session = currentPanel?.transportSession else { return }
        present(UINavigationController(rootViewController: BTFUnloadTransportController(session: session)), animated: true)
    }
    private var unitInfoHeight: CGFloat {
        let height = ceil(unitInfoLabel.font.lineHeight)
        return view.bounds.width < view.bounds.height ? ceil(height * 1.5) : height
    }
    private func layoutUnitInfo() {
        guard unitInfoLabel.text != nil else {
            unitInfoLabel.frame = .zero
            return
        }
        unitInfoLabel.frame = maximumUnitInfoFrame
        unitInfoLabel.sizeToFit()
    }
    private func layoutBottomControls() {
        let insets = view.safeAreaInsets
        let margins = YUSLayoutService.hudMargins(for: view)
        let buttonSize = YUSLayoutService.squareButtonSize
        let infoTop = view.bounds.height - insets.bottom - unitInfoHeight
        let top = infoTop - buttonSize
        let ordersWidth = buttonSize * CGFloat(unitOrdersView.actions.count)
        unitOrdersView.frame = CGRect(x: view.bounds.width - margins.right - ordersWidth, y: top,
                                      width: ordersWidth, height: buttonSize)
        var x = unitOrdersView.frame.maxX
        for contextView in [unloadView, sweepView, repairView] where !contextView.isHidden {
            x -= buttonSize
            contextView.frame = CGRect(x: x, y: top - contextButtonSpacing - buttonSize,
                                       width: buttonSize, height: buttonSize)
        }
        maximumUnitInfoFrame = CGRect(x: margins.left, y: infoTop,
                                      width: view.bounds.width - margins.left - margins.right,
                                      height: unitInfoHeight)
        layoutUnitInfo()
    }
    private func updateContextButtons() {
        sweepView.isHidden = !bridge.canSweepMines
        unloadView.isHidden = currentPanel?.transportSession == nil
        repairView.isHidden = !bridge.canRepairSelectedUnit
        setOrder(.next, enabled: bridge.canSelectNextUnit)
        setOrder(.done, enabled: bridge.canFinishUnit)
        setOrder(.info, enabled: currentPanel != nil)
        layoutBottomControls()
    }
    private func setOrder(_ order: BTFUnitOrder, enabled: Bool) {
        guard let button = unitOrdersView.button(for: order.rawValue) else { return }
        button.isEnabled = enabled
        button.alpha = enabled ? 1 : 0.4
    }

    public func numberOfMessages(in _: YUSAdTurnView) -> Int { messages.count }
    public func adTurnView(_: YUSAdTurnView, messageAt index: Int) -> String? {
        messages.indices.contains(index) ? messages[index] : nil
    }
    public func adTurnViewDidTapQuit(_: YUSAdTurnView) { quit() }
    public func adTurnViewDidTapContinue(_: YUSAdTurnView) {
        guard !isProcessing else { return }
        refreshGameState()
        guard saveGame() else {
            yus_showMessage(String(localized: "Operation failed.", bundle: btfBundle))
            return
        }
        bridge.centerOnCursor()
    }

    public func refreshTile(atRow row: Int, section: Int, mapChanged: Bool) {
        guard !isProcessing, isValidMapLocation(row: row, section: section) else { return }
        mapView.configItems(at: [IndexPath(row: row, section: section)])
        if mapChanged { scheduleMiniMapUpdate() }
    }
    public func refreshAllTiles(mapChanged: Bool) {
        guard !isProcessing else { return }
        mapView.configAllItems()
        if mapChanged { scheduleMiniMapUpdate() }
    }
    public func centerMap(atRow row: Int, section: Int) {
        guard !isProcessing, isValidMapLocation(row: row, section: section) else { return }
        mapView.scrollToItem(at: IndexPath(row: row, section: section), at: [], animated: true)
        miniMapView.updateViewPort(of: mapView)
    }
    public func updatePanel(_ snapshot: BTFPanelSnapshot?) {
        currentPanel = snapshot
        unitInfoLabel.text = snapshot?.text.isEmpty == false ? snapshot?.text : nil
        updateContextButtons()
        updateStatus()
    }
    private func updateStatus() {
        let crystals = bridge.crystals
        crystalsButton.setTitle("💎 \(crystals)", for: .normal)
        crystalsButton.accessibilityLabel = "\(String(localized: "Crystals", bundle: btfBundle)) \(crystals)"
        let turn = String(format: String(localized: "Turn %ld", bundle: btfBundle), bridge.turn)
        turnButton.setTitle(turn, for: .normal)
        turnButton.accessibilityLabel = turn
    }
    public func present(containerSession session: BTFContainerSession) {
        let controller = BTFBuildingController(session: session)
        controller.didMutate = { [weak self] in self?.refreshGameState() }
        present(UINavigationController(rootViewController: controller), animated: true)
    }
    public func presentMessage(withTitle title: String, message: String) { yus_showTitle(title, message: message) }
    public func presentGameOver(withTitle title: String, message: String) {
        gameOverSummary = (title, message)
    }
    public func appendTurnMessage(_ message: String) {
        guard isProcessing else { return }
        messages.append(message)
    }

    private func refreshGameState() {
        mapView.configAllItems()
        updatePanel(bridge.currentPanelSnapshot())
        scheduleMiniMapUpdate()
    }
}
