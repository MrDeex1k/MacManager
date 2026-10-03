// Adapted from Tinycast, Copyright (C) 2026 Abue Ammar.
// AGPL-3.0-or-later; used under AGPL-3.0. Source: c5cff8cbb9b7e12ac75c058da9573045c76029b7.
// Integrated 2026-09-23: local evaluation only, no rate service or history.
import Foundation

enum CalcToken: Equatable, Sendable {
    case number(Double)
    /// Shorthand (`10k`, `1e5`), kept distinct so a lone one still earns a card.
    case compactNumber(Double)
    /// Radix-prefixed integer literal (0xff / 0b1010 / 0o777), kept exact for base conversion.
    case intLiteral(UInt64, base: CalcNumberBase)
    case ident(String)
    case op(CalcOperator)
    case arrow  // -> or →
    case comma
}
