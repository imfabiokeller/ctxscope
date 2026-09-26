import Foundation
import ScopeCapture
import ScopeCore

let usage = """
  ctxscope command line

  ctxscope sessions [--limit N] [--project TEXT]
      Sessions on this machine, newest first.

  ctxscope analyze <session> [--lane ID] [--at REQUEST] [--json]
      REQUEST counts from one, the way the window shows it.
      Composition, cache, reused share and the largest unused blocks.

  ctxscope validate <session> [--lane ID] [--json]
      Checks that segment sizes sum to the API totals on every request, and
      reports the estimator residual.

  ctxscope export <session> --format json|csv [--lane ID] [--out PATH]
      The recording and its metrics. Every request number in an export counts
      from one, the same as the window and the lines above.

  ctxscope calibrate [--limit N]
      Refits the estimator prior from the sessions on this machine.

  ctxscope bench [--requests N] [--window N] [--capture-requests N]
      Times the analyzers on a synthetic recording of a given scale.

  ctxscope connect [--port N] [--yes]
      Adds ctxscope's hooks to ~/.claude/settings.json and installs the
      /ctxscope skill, after showing the exact diff and asking.

  ctxscope disconnect [--yes]
      Takes both out again, after showing the exact diff and asking.

  ctxscope doctor
      Says what is in place: settings file, our hooks and their port, the
      listener, the skill, the URL scheme.

  ctxscope demo --home DIR [--live SECONDS] [--start TIME]
      Writes a made-up session, "retry-policy" in ~/code/api-client, into
      DIR/.claude/projects, for screenshots in which nothing private can
      appear. --live writes the first 41 requests at once and the rest one
      at a time over SECONDS. --start dates the first request (ISO 8601);
      without it the session ends a minute ago. Never your own home.

  Common options:
      --window N        context window to measure fill against. Without it the
                        window is inferred as the smallest known one that fits
      --no-subagents    main lane only
  """

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))

do {
  switch arguments.command {
  case "sessions":
    try SessionsCommand.run(arguments)
  case "analyze":
    try AnalyzeCommand.run(arguments)
  case "validate":
    try ValidateCommand.run(arguments)
  case "export":
    try ExportCommand.run(arguments)
  case "calibrate":
    try CalibrateCommand.run(arguments)
  case "bench":
    try BenchCommand.run(arguments)
  case "connect":
    try ConnectCommand.connect(arguments)
  case "disconnect":
    try ConnectCommand.disconnect(arguments)
  case "doctor":
    try ConnectCommand.doctor(arguments)
  case "demo":
    try DemoCommand.run(arguments)
  case "help", "--help", "-h":
    Console.out(usage)
  default:
    Console.error("unknown command: \(arguments.command)")
    Console.out(usage)
    exit(2)
  }
} catch {
  Console.error("error: \(error)")
  exit(1)
}
