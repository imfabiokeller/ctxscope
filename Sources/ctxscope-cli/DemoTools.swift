import Foundation

/// The demo's tool definitions: the built-in set every request carries, and
/// the GitHub server's, which connects part way through. Descriptions are
/// written for the demo.
enum DemoTools {
  typealias Property = (name: String, type: String, about: String)

  static var builtIn: [[String: Any]] {
    [
      tool(
        "Agent",
        "Starts a subagent that works on a task by itself and returns one report. Use it for "
          + "wide searches and investigations whose intermediate output you do not need.",
        [
          ("description", "string", "A few words saying what the agent will do"),
          ("prompt", "string", "The full task, with everything the agent needs to know"),
          ("subagent_type", "string", "Which kind of agent to start"),
        ], required: ["description", "prompt"]),
      tool(
        "Bash",
        "Runs a shell command in the project folder and returns its output. Quote paths with "
          + "spaces. Prefer the dedicated tools for reading and searching files.",
        [
          ("command", "string", "The command to run"),
          ("description", "string", "What the command does, in a few words"),
          ("timeout", "number", "Milliseconds before the command is stopped, at most 600000"),
          ("run_in_background", "boolean", "Run it without waiting for it to finish"),
        ], required: ["command"]),
      tool(
        "BashOutput", "Returns new output from a command that runs in the background.",
        [("bash_id", "string", "The id the background command was given")],
        required: ["bash_id"]),
      tool(
        "KillShell", "Stops a command that runs in the background.",
        [("shell_id", "string", "The id of the command to stop")], required: ["shell_id"]),
      tool(
        "Glob",
        "Finds files whose paths match a glob pattern such as src/**/*.ts, newest first.",
        [
          ("pattern", "string", "The glob pattern"),
          ("path", "string", "The folder to search in, the project root when left out"),
        ], required: ["pattern"]),
      tool(
        "Grep",
        "Searches file contents with a regular expression. Can return matching lines, the "
          + "files that match, or counts, and can be limited by glob or file type.",
        [
          ("pattern", "string", "The regular expression"),
          ("path", "string", "File or folder to search"),
          ("glob", "string", "Only files matching this glob"),
          ("output_mode", "string", "content, files_with_matches or count"),
          ("-n", "boolean", "Show line numbers"),
          ("-i", "boolean", "Ignore case"),
          ("head_limit", "number", "Only the first N results"),
        ], required: ["pattern"]),
      tool(
        "Read",
        "Reads a file and returns it with line numbers. Reads the whole file unless an offset "
          + "and a limit are given. Also reads images and PDF documents.",
        [
          ("file_path", "string", "Absolute path of the file"),
          ("offset", "number", "Line to start at"),
          ("limit", "number", "Number of lines to read"),
        ], required: ["file_path"]),
      tool(
        "Edit",
        "Replaces an exact string in a file with another. The old string must appear exactly "
          + "once unless replace_all is set. Read the file before editing it.",
        [
          ("file_path", "string", "Absolute path of the file"),
          ("old_string", "string", "The text to replace"),
          ("new_string", "string", "The text to put in its place"),
          ("replace_all", "boolean", "Replace every occurrence"),
        ], required: ["file_path", "old_string", "new_string"]),
      tool(
        "Write", "Writes a file, replacing it if it exists. Prefer Edit for existing files.",
        [
          ("file_path", "string", "Absolute path of the file"),
          ("content", "string", "The whole content of the file"),
        ], required: ["file_path", "content"]),
      tool(
        "NotebookEdit", "Replaces, inserts or deletes one cell of a Jupyter notebook.",
        [
          ("notebook_path", "string", "Absolute path of the notebook"),
          ("cell_id", "string", "The cell to change"),
          ("new_source", "string", "The new source of the cell"),
          ("edit_mode", "string", "replace, insert or delete"),
        ], required: ["notebook_path", "new_source"]),
      tool(
        "WebFetch",
        "Fetches a URL, converts the page to text and answers a question about it with a "
          + "small model. Returns that answer, not the page.",
        [
          ("url", "string", "The page to fetch"),
          ("prompt", "string", "What to find out from the page"),
        ], required: ["url", "prompt"]),
      tool(
        "WebSearch", "Searches the web and returns result titles, links and snippets.",
        [
          ("query", "string", "The search terms"),
          ("allowed_domains", "array", "Only results from these domains"),
        ], required: ["query"]),
      tool(
        "TodoWrite",
        "Keeps the task list for this session. Send the whole list each time, with each item "
          + "pending, in_progress or completed. Only one item is in progress at a time.",
        [("todos", "array", "The items, each with content, status and activeForm")],
        required: ["todos"]),
      tool(
        "ExitPlanMode", "Presents a plan to the person and asks to start working on it.",
        [("plan", "string", "The plan, in Markdown")], required: ["plan"]),
      tool(
        "Skill", "Loads the instructions of an installed skill by name.",
        [("skill", "string", "The skill's name")], required: ["skill"]),
      tool(
        "SlashCommand", "Runs one of the project's slash commands.",
        [("command", "string", "The command with its arguments")], required: ["command"]),
      tool(
        "ToolSearch", "Loads the definitions of tools that are available but not loaded yet.",
        [("query", "string", "Tool names or keywords")], required: ["query"]),
      tool(
        "AskUserQuestion", "Asks the person a question with a few options to choose from.",
        [
          ("question", "string", "The question"),
          ("options", "array", "Two to four answers to offer"),
        ], required: ["question", "options"]),
    ]
  }

  /// One definition in the snapshot's shape. The schema is the record the
  /// API is given.
  static func tool(
    _ name: String, _ summary: String, _ properties: [Property], required: [String]
  ) -> [String: Any] {
    let description = notes[name].map { summary + "\n\n" + $0 } ?? summary
    return [
      "name": name, "description": description,
      "schema": schema(name, description, properties, required),
    ]
  }

  /// The longer usage notes the busiest tools carry.
  private static let notes: [String: String] = [
    "Agent": "Give the agent everything it needs: it does not see this conversation. Say what "
      + "to look for, where, what is already known, and what shape the report should take. "
      + "Several agents can run at once when their tasks are independent. The report comes "
      + "back to you, not to the person, so summarize what matters.",
    "Bash": "Commands run in a persistent shell with the project folder as the working "
      + "directory. Output longer than 30000 characters is cut in the middle. Use absolute "
      + "paths or paths relative to the project root, and avoid cd. Do not use find, grep, "
      + "cat, head or tail for files: the dedicated tools are faster and their output is "
      + "easier to read. Chain dependent commands with && and run independent ones in "
      + "separate calls. Never run interactive commands; they wait for input forever.",
    "Grep": "Built on ripgrep, so the pattern is a Rust regular expression and literal braces "
      + "need escaping. Prefer files_with_matches to find where something is, and content "
      + "with a head_limit to see how it is used. Searches of dependency folders are "
      + "usually noise; narrow them with glob or path.",
    "Read": "Lines are numbered from 1. Lines longer than 2000 characters are cut. Reading a "
      + "file you are about to edit is required: Edit refuses a file that was not read in "
      + "this session. When several files are needed, read them in one turn.",
    "Edit": "Keep old_string as short as it can be while still being unique, and copy its "
      + "indentation exactly as Read showed it, without the line number prefix. When the "
      + "same change is needed in many places, use replace_all rather than many edits.",
    "TodoWrite": "Use it for any task with three or more steps, and when the person gives a "
      + "list of things to do. Update it as soon as a step is finished rather than in "
      + "batches, so the person can follow along.",
    "WebFetch": "The answer is produced by a smaller model reading the page, so it may leave "
      + "things out or get details wrong. Fetches are cached for a short time. Redirects to "
      + "another host are reported instead of followed.",
    "Write": "Overwrites without asking. Read an existing file first so nothing is lost by "
      + "accident, and prefer Edit for anything short of a rewrite.",
  ]

  static func schema(
    _ name: String, _ description: String, _ properties: [Property], _ required: [String]
  ) -> [String: Any] {
    var fields: [String: Any] = [:]
    for property in properties {
      fields[property.name] = ["type": property.type, "description": property.about]
    }
    return [
      "name": name, "description": description,
      "input_schema": [
        "type": "object", "properties": fields, "required": required,
        "additionalProperties": false,
      ],
    ]
  }
}
