import Foundation
import SpacedCore

let usage = """
Usage: spaced [--ask "question"]... [--title "title"] [--wait] [file | -]

Opens a markdown document in Spaced for focused reading.

  file            Markdown file to open. Use - or pipe to read from stdin.
  -a, --ask       A question to keep in view while reading. Repeatable.
  -t, --title     Tab title. Defaults to the first heading or the file name.
  -w, --wait      Block until the review is finished, then print the notes
                  (blockquote + response) to stdout.
  -h, --help      Show this help.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("spaced: \(message)\n".utf8))
    exit(code)
}

var asks: [String] = []
var title: String?
var wait = false
var input: String?

var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "-a", "--ask":
        guard !arguments.isEmpty else { fail("\(argument) needs a value", code: 64) }
        asks.append(arguments.removeFirst())
    case "-t", "--title":
        guard !arguments.isEmpty else { fail("\(argument) needs a value", code: 64) }
        title = arguments.removeFirst()
    case "-w", "--wait":
        wait = true
    case "-h", "--help":
        print(usage)
        exit(0)
    case "-":
        input = "-"
    default:
        guard !argument.hasPrefix("-") else { fail("unknown option \(argument)\n\n\(usage)", code: 64) }
        input = argument
    }
}

var sourcePath: String?
let markdown: String
if let input, input != "-" {
    let url = URL(fileURLWithPath: input)
    guard let data = try? Data(contentsOf: url) else { fail("can't read \(input)") }
    markdown = String(decoding: data, as: UTF8.self)
    sourcePath = url.standardizedFileURL.path
} else {
    if input == nil, isatty(STDIN_FILENO) != 0 {
        print(usage)
        exit(64)
    }
    markdown = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
}

guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { fail("nothing to read") }

let paths = SpacedPaths.standard
let request = ReviewRequest(title: title, sourcePath: sourcePath, markdown: markdown, asks: asks, wait: wait)
do {
    try request.write(to: paths)
} catch {
    fail("can't write request: \(error.localizedDescription)")
}

/// The app bundle this binary ships inside (`Spaced.app/Contents/Helpers/spaced`), if any.
func enclosingAppBundle() -> String? {
    if let override = ProcessInfo.processInfo.environment["SPACED_APP"], !override.isEmpty {
        return override
    }
    guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
    let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return bundle.pathExtension == "app" ? bundle.path : nil
}

let open = Process()
open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
open.arguments = enclosingAppBundle().map { ["-a", $0] } ?? ["-b", "dev.spaced.Spaced"]
do {
    try open.run()
    open.waitUntilExit()
} catch {
    fail("can't launch Spaced: \(error.localizedDescription)")
}
guard open.terminationStatus == 0 else { fail("can't launch Spaced") }

if wait {
    while true {
        if let result = ReviewRequest.takeResult(for: request.id, in: paths) {
            print(result, terminator: result.hasSuffix("\n") ? "" : "\n")
            break
        }
        Thread.sleep(forTimeInterval: 0.25)
    }
}
