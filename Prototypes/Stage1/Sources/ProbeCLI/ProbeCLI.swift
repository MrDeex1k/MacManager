import Foundation
import ProbeCore

struct Options {
    var command = "help"
    var samples = 3
    var interval = 1.0
    var checkPublic = false
    var reveal = false
    var observeSeconds = 0.0

    init(_ arguments: [String]) throws {
        guard let command = arguments.first else { return }
        self.command = command
        guard ["metrics", "network", "input", "help", "--help"].contains(command) else {
            throw CLIError.invalid("Unknown command.")
        }
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            func next() throws -> String {
                guard index + 1 < arguments.count else { throw CLIError.invalid("Missing option value.") }
                index += 1
                return arguments[index]
            }
            switch (command, flag) {
            case ("metrics", "--samples"):
                guard let count = Int(try next()), (2...120).contains(count) else {
                    throw CLIError.invalid("--samples must be 2...120.")
                }
                samples = count
            case ("metrics", "--interval"):
                guard let duration = Double(try next()), duration.isFinite, (0.2...5).contains(duration) else {
                    throw CLIError.invalid("--interval must be 0.2...5 seconds.")
                }
                interval = duration
            case ("network", "--public-ip"): checkPublic = true
            case ("network", "--show-addresses"): reveal = true
            case ("input", "--observe-seconds"):
                guard let duration = Double(try next()), duration.isFinite, (1...60).contains(duration) else {
                    throw CLIError.invalid("--observe-seconds must be 1...60.")
                }
                observeSeconds = duration
            default: throw CLIError.invalid("Unsupported option for this command.")
            }
            index += 1
        }
    }
}

enum CLIError: Error { case invalid(String) }

@main
struct ProbeCLI {
    static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }

    static func main() async {
        do {
            let options = try Options(Array(CommandLine.arguments.dropFirst()))
            switch options.command {
            case "metrics":
                let probe = MetricsProbe()
                for index in 0..<options.samples {
                    try printJSON(probe.sample())
                    if index < options.samples - 1 {
                        try await Task.sleep(for: .seconds(options.interval))
                    }
                }
            case "network":
                try await printJSON(NetworkProbe.sample(checkPublic: options.checkPublic, reveal: options.reveal))
            case "input":
                try printJSON(InputProbe.sample(observeSeconds: options.observeSeconds))
            default:
                print("""
                mac-manager-probe: Stage 1 feasibility tools (macOS 26+, Apple Silicon)
                  metrics [--samples 3] [--interval 1]
                  network [--public-ip] [--show-addresses]
                  input [--observe-seconds 15]

                JSON lines on stdout. Network addresses are redacted by default.
                --public-ip contacts api.ipify.org through the normal system route.
                Input observation is passive and requires existing Input Monitoring permission.
                No administrator helper, SMC writes, permission prompts or scroll modification.
                """)
            }
        } catch CLIError.invalid(let message) {
            FileHandle.standardError.write(Data("Error: \(message) Use --help.\n".utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("Probe failed.\n".utf8))
            exit(1)
        }
    }
}
