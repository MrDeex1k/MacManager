import Foundation
import Testing
@testable import MacManagerCore

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
