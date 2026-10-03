// Adapted from Tinycast, Copyright (C) 2026 Abue Ammar.
// AGPL-3.0-or-later; used under AGPL-3.0. Source: c5cff8cbb9b7e12ac75c058da9573045c76029b7.
// Integrated 2026-09-23: local evaluation only, no rate service or history.
import Foundation

struct CalcValue {
    enum Kind {
        case scalar
        case unit(UnitDef)
        case currency(CurrencyDef)
    }

    var amount: Double
    var kind: Kind
    var isPercent = false
    var isBoolean = false

    var effective: Double {
        isPercent ? amount / 100 : amount
    }
}
