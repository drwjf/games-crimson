//
//  BTFSettingsController.swift
//  BTF
//

import UIKit
import YUSKit

#if PREMIUM
import YUSPremium
#else
import YUSAd
#endif

final class BTFSettingsController: YUSSettingsController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let explanation = String(
            format: String(localized: "Each repair costs %llu mana.", bundle: btfBundle),
            YUSManaGate.actionCost
        )
        if let manaItem = YUSManaGate.makeManaItem(presenting: self, explanation: explanation) {
            sections.append([manaItem])
        }
    }
}
