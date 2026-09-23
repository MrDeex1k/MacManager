// Adapted from Tinycast, Copyright (C) 2026 Abue Ammar.
// AGPL-3.0-or-later; used under AGPL-3.0. Source: c5cff8cbb9b7e12ac75c058da9573045c76029b7.
// Integrated 2026-09-23: local evaluation only, no rate service or history.
struct CalcDimension: Hashable, Sendable {
    var length = 0.0
    var mass = 0.0
    var time = 0.0
    var data = 0.0
    var electricCurrent = 0.0
    var pixels = 0.0
    var currency = 0.0

    static let scalar = CalcDimension()

    func adding(_ other: Self, scale: Double = 1) -> Self {
        Self(
            length: length + other.length * scale, mass: mass + other.mass * scale,
            time: time + other.time * scale, data: data + other.data * scale,
            electricCurrent: electricCurrent + other.electricCurrent * scale,
            pixels: pixels + other.pixels * scale, currency: currency + other.currency * scale)
    }

    func raised(to power: Double) -> Self {
        Self(
            length: length * power, mass: mass * power, time: time * power, data: data * power,
            electricCurrent: electricCurrent * power, pixels: pixels * power, currency: currency * power)
    }
}
