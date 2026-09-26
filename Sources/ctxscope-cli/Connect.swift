import Foundation
import ScopeConnect

// `--claude-home` is left out of the usage text: it exists so tests never touch the real home.
enum ConnectCommand {
  static func home(_ arguments: Arguments) -> ClaudeHome {
    guard let path = arguments.value("claude-home") else { return .real() }
    return ClaudeHome(root: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
  }

  static func port(_ arguments: Arguments, service: ConnectService) -> UInt16 {
    if let asked = arguments.integer("port"), let value = UInt16(exactly: asked) { return value }
    return (try? service.status())?.port ?? HookWiring.defaultPort
  }

  static func connect(_ arguments: Arguments) throws {
    let service = ConnectService(home: home(arguments))
    try run(
      .connect(port: port(arguments, service: service)), with: service, arguments: arguments,
      nothingToDo: "already connected, nothing to write", done: "written. run doctor to check it")
  }

  static func disconnect(_ arguments: Arguments) throws {
    try run(
      .disconnect, with: ConnectService(home: home(arguments)), arguments: arguments,
      nothingToDo: "nothing of ctxscope's to remove", done: "removed")
  }

  private static func run(
    _ change: ConnectService.Change, with service: ConnectService, arguments: Arguments,
    nothingToDo: String, done: String
  ) throws {
    let plan = try service.plan(change)
    guard !plan.isEmpty else { return Console.out(nothingToDo) }
    show(plan)
    guard agreed(arguments) else { return Console.out("nothing was written") }
    do {
      try service.apply(plan)
    } catch Refusal.moved {
      Console.out("")
      Console.out("the settings file changed while this was worked out. Nothing was written.")
      Console.out("this is what it would do now:")
      Console.out("")
      let again = try service.plan(change)
      guard !again.isEmpty else { return Console.out(nothingToDo) }
      show(again)
      guard agreed(arguments) else { return Console.out("nothing was written") }
      try service.apply(again)
    }
    Console.out("")
    Console.out(done)
  }

  static func doctor(_ arguments: Arguments) throws {
    let report = ConnectService(home: home(arguments)).report()
    for line in report.lines { Console.out(line) }
    if !report.isHealthy { exit(1) }
  }

  private static func agreed(_ arguments: Arguments) -> Bool {
    if arguments.has("yes") { return true }
    guard isatty(STDIN_FILENO) == 1 else {
      Console.out("")
      Console.out("this is not a terminal. Pass --yes to write it.")
      return false
    }
    Console.out("")
    FileHandle.standardOutput.write(Data("write this? [y/N] ".utf8))
    guard let answer = readLine() else { return false }
    return ["y", "yes"].contains(answer.trimmingCharacters(in: .whitespaces).lowercased())
  }

  private static func show(_ plan: ConnectService.Plan) {
    let diff = plan.diff()
    if diff.isEmpty {
      Console.out("the settings file does not change")
    } else {
      Console.out(diff)
    }
    if plan.removesSettings { Console.out("the settings file goes, because ctxscope wrote it") }
    if plan.backup != nil { Console.out("a backup of the settings file is written beside it") }
    switch plan.skill {
    case .none: break
    case .install: Console.out("the /ctxscope skill is installed")
    case .remove: Console.out("the /ctxscope skill is removed")
    case .keepEdited:
      Console.out("the /ctxscope skill was edited by hand, so it stays where it is")
    }
  }
}
