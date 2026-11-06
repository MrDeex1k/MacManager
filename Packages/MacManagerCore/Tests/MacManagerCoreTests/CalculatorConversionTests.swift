import Foundation
import Testing
@testable import MacManagerCore

/// Exercises both seasons to distinguish Nashville's changing UTC offset from Bali's fixed offset.
@Test func calculatorCityAliasesUseLocalZoneInWinterAndSummer() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_GB")
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    for month in [1, 7] {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: 15)))
        for (city, zone, expected) in [
            ("nashville", "Chicago", month == 1 ? "18:00" : "17:00"),
            ("bali", "Makassar", "04:00"), ("denpasar", "Makassar", "04:00")
        ] {
            let result = try #require(CalcTimeZone.evaluate("12:00 \(city) to utc", now: now, calendar: calendar))
            #expect(result.sourceBadge == zone)
            #expect(result.payload == .value(display: expected, copyText: expected))
        }
    }
}

/// Checks that unary signs preserve relative percentages without changing multiplication or exponent precedence.
@Test func calculatorPreservesSignedRelativePercentages() {
    for (query, expected) in [
        ("200 + -10%", "180"), ("200 - -10%", "220"),
        ("200 + (-10%)", "180"), ("200 + --10%", "220"),
        ("200 + +10%", "220"), ("-10%", "-0.1"),
        ("200 * -10%", "-20"), ("-2^2", "-4")
    ] {
        #expect(LocalCalculator.result(query, language: "en")?.action == .copy(expected), "Query: \(query)")
    }
}

/// Checks Polish function arguments with and without fractions alongside English comma-separated arguments.
@Test func calculatorAcceptsPolishArgumentSeparatorsWithoutDecimalFractions() {
    for (query, expected) in [
        ("max(1;2)", "2"), ("pow(2;3)", "8"),
        ("round(1,25;1)", "1.3"), ("max(1.5;2)", "2"),
        ("1.5+2", "3.5"), ("1,5+2", "3.5")
    ] {
        #expect(LocalCalculator.result(query, language: "pl")?.action == .copy(expected), "Query: \(query)")
    }
    #expect(LocalCalculator.result("max(1,2)", language: "en")?.action == .copy("2"))
}

/// Covers direct date parsing and date arithmetic at the supported calendar boundaries.
@Test func calculatorRejectsDatesOutsideSupportedYears() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let context = LocalCalculator.Context(language: "en", now: Date(timeIntervalSince1970: 0), calendar: calendar)
    for query in ["january 1 10000 at 12:00", "january 1 999999 at 12:00", "february 30 2026 at 12:00",
                  "january 1 -1 at 12:00", "today - 2000 years", "monday in 10000 years"] {
        #expect(LocalCalculator.result(query, context: context) == nil, "Query: \(query)")
    }
    #expect(LocalCalculator.result("january 1 9999 at 12:00", context: context) != nil)
    #expect(LocalCalculator.result("february 29 2024 at 12:00", context: context) != nil)
}

@Test func calculatorAcceptsBareDenominatorsWithoutChangingUnitJuxtaposition() {
    let cases = [
        ("100 / s", "100 Hz"), ("100 / (s)", "100 Hz"),
        ("1000 / (3/s)", "333.3333333 s"),
        ("65535 / (100/s) to minutes", "10.9225 min"),
        ("1000 / 3 / s", "333.3333333 Hz"), ("10 km / h", "10 km/hr"),
        ("day s", "86,400 s")
    ]
    for (query, expected) in cases {
        #expect(LocalCalculator.result(query, language: "en")?.title == expected, "Query: \(query)")
    }
    for query in ["100 / sec", "m s", "100 / s / 0"] {
        #expect(LocalCalculator.result(query, language: "en") == nil, "Query: \(query)")
    }
}

@Test func calculatorConversionBindsWholeTermsAndFunctionArguments() {
    let cases = [
        ("10 m in cm / 2", "500 cm"), ("2 * 5 m in cm / 2", "500 cm"),
        ("5 ft 3 in in cm / 2", "80.01 cm"),
        ("10 kg + 500 g to g", "10,500 g"),
        ("100km/h in m/s / 2", "13.88888889 m/s"),
        ("2m * 3m to cm2 + 1 cm2", "60,001 cm²"),
        ("round(10 m in cm)", "1,000 cm"),
        ("max(10 m in cm, 900 cm)", "1,000 cm"),
        ("min(round(10 m in cm), 900 cm)", "900 cm"),
        ("10 kg to g == 10000 g", "true")
    ]
    for (query, expected) in cases {
        #expect(LocalCalculator.result(query, language: "en")?.title == expected, "Query: \(query)")
    }
    #expect(LocalCalculator.result("10,5 m in cm / 2", language: "pl")?.title == "525 cm")
    for query in ["10 m in cm / 0", "10 m in cm / (2 - 2)", "10 m in cm nonsense / 2",
                  "10 m in cm / nonsense", "10 m in cm / (2 +)", "10 m in cm)",
                  "10 kg to lb to oz", "max(10 m in cm,)"] {
        #expect(LocalCalculator.result(query, language: "en") == nil, "Query: \(query)")
    }
}
