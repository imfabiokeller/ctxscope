import Foundation
import ScopeCore

struct DemoLane {
  static let model = "claude-opus-5"
  static let rates = EstimatorRates.prior
  // The few tokens the harness appends after the last cache breakpoint.
  static let uncached = 3
  // Keeps the first request under its recorded prefix, so the adapter scales the
  // recorded blocks instead of inventing a share for an unrecorded band.
  static let undershoot = 120

  let session: String
  let cwd: String
  let agentID: String?
  let prefix: DemoPrefix
  private var ids: DemoIDs
  private var parent: String?
  private var index = 0
  private var total = 0
  private var cachedAfter = 0
  private var output = 0
  private var pending = 0.0
  private var prefixRead = 0

  init(session: String, cwd: String, agentID: String?, prefix: DemoPrefix) {
    self.session = session
    self.cwd = cwd
    self.agentID = agentID
    self.prefix = prefix
    ids = DemoIDs(seed: agentID ?? session)
  }

  struct Spawned {
    let agent: DemoAgent
    let description: String
    let toolUseID: String
  }

  mutating func request(_ turn: DemoTurn, at times: DemoTimes) -> (
    entries: [[String: Any]], spawned: [Spawned]
  ) {
    var entries: [[String: Any]] = []
    for input in turn.inputs {
      entries.append(next(input.fields, at: times.inputs))
      pending += input.sized.reduce(0) { $0 + Self.estimate($1) }
    }
    if index == 0 { entries.append(next(prefix.snapshot, at: times.inputs)) }

    let usage = usage(for: turn)
    let message = "msg_" + ids.hex(24)
    let request = "req_" + ids.hex(24)
    var blocks: [[String: Any]] = []
    if let thinking = turn.thinking {
      let signature = ids.hex(min(4000, max(200, turn.thinkingTokens * 2)))
      blocks.append(["type": "thinking", "thinking": thinking, "signature": signature])
    }
    if let text = turn.text { blocks.append(["type": "text", "text": text]) }
    var callIDs: [String] = []
    for call in turn.calls {
      let id = "toolu_" + ids.hex(24)
      callIDs.append(id)
      blocks.append(["type": "tool_use", "id": id, "name": call.name, "input": call.input])
    }
    var callEntries: [String] = []
    for block in blocks {
      let fields: [String: Any] = [
        "type": "assistant", "requestId": request,
        "message": [
          "model": Self.model, "id": message, "type": "message", "role": "assistant",
          "content": [block], "stop_reason": turn.calls.isEmpty ? "end_turn" : "tool_use",
          "stop_sequence": NSNull(), "usage": usage,
        ],
      ]
      entries.append(next(fields, at: times.response))
      if block["type"] as? String == "tool_use", let uuid = parent { callEntries.append(uuid) }
    }

    pending = 0
    var spawned: [Spawned] = []
    for (position, call) in turn.calls.enumerated() {
      var fields: [String: Any] = [
        "type": "user", "sourceToolAssistantUUID": callEntries[position],
        "message": [
          "role": "user",
          "content": [
            ["type": "tool_result", "tool_use_id": callIDs[position], "content": call.result]
          ],
        ],
      ]
      if let record = call.record { fields["toolUseResult"] = record }
      let uuid = ids.uuid()
      entries.append(stamped(fields, uuid: uuid, parent: callEntries[position], at: times.results))
      pending += Self.estimate(call.result)
      if let agent = call.agent {
        let description = call.input["description"] as? String ?? agent.type
        spawned.append(
          Spawned(agent: agent, description: description, toolUseID: callIDs[position]))
      }
      if position == turn.calls.count - 1 { parent = uuid }
    }
    index += 1
    return (entries, spawned)
  }

  private mutating func usage(for turn: DemoTurn) -> [String: Any] {
    let framing = Self.rates.tokensPerRequest
    if index == 0 {
      total = Int((pending + framing + prefix.estimate).rounded()) - Self.undershoot
      // Cut mid last tool definition: all before it was read, nothing after it.
      prefixRead = Int(prefix.estimate - prefix.lastToolEstimate / 2) - Self.undershoot
    } else {
      total += output + Int((pending + framing).rounded(.up))
    }
    let read =
      switch turn.cache {
      case .warm: index == 0 ? 0 : cachedAfter
      case .prefix: prefixRead
      case .cold: 0
      }
    let written = total - read - Self.uncached
    cachedAfter = read + written

    var visible = 0.0
    if let text = turn.text { visible += Self.estimate(text) }
    for call in turn.calls {
      visible += Self.rates.estimate(
        characters: Self.compact(call.input).unicodeScalars.count, contentClass: .json)
    }
    output = turn.thinkingTokens + Int(visible.rounded(.up)) + 4
    return [
      "input_tokens": Self.uncached,
      "cache_read_input_tokens": read,
      "cache_creation_input_tokens": written,
      "output_tokens": output,
      "output_tokens_details": ["thinking_tokens": turn.thinkingTokens],
      "cache_creation": ["ephemeral_5m_input_tokens": written, "ephemeral_1h_input_tokens": 0],
      "service_tier": "standard",
    ]
  }

  private mutating func next(_ fields: [String: Any], at time: Date) -> [String: Any] {
    let uuid = ids.uuid()
    let entry = stamped(fields, uuid: uuid, parent: parent, at: time)
    parent = uuid
    return entry
  }

  private func stamped(_ fields: [String: Any], uuid: String, parent: String?, at time: Date)
    -> [String: Any]
  {
    var entry = fields
    entry["uuid"] = uuid
    entry["parentUuid"] = parent ?? NSNull()
    entry["timestamp"] = DemoTimes.stamp(time)
    entry["sessionId"] = session
    entry["cwd"] = cwd
    entry["version"] = "2.1.275"
    entry["gitBranch"] = "retry-policy"
    entry["userType"] = "external"
    entry["entrypoint"] = "cli"
    entry["isSidechain"] = agentID != nil
    if let agentID { entry["agentId"] = agentID }
    return entry
  }

  static func estimate(_ text: String) -> Double {
    rates.estimate(
      characters: text.unicodeScalars.count, contentClass: ContentClassifier.classify(text))
  }

  static func compact(_ value: Any) -> String {
    switch value {
    case let text as String: text
    case let list as [Any]: list.map(compact).joined(separator: ",")
    case let object as [String: Any]:
      object.keys.sorted().map { "\($0):\(compact(object[$0] ?? ""))" }.joined(separator: ",")
    default: "\(value)"
    }
  }
}

struct DemoIDs {
  private var state: UInt64

  init(seed: String) {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
    state = hash
  }

  mutating func hex(_ count: Int) -> String {
    var out = ""
    while out.count < count { out += String(next(), radix: 16).leftPadded(16) }
    return String(out.prefix(count))
  }

  mutating func uuid() -> String {
    let digits = Array(hex(32))
    return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(digits[$0]) }
      .joined(separator: "-")
  }

  // SplitMix64.
  private mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var value = state
    value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
    value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
    return value ^ (value >> 31)
  }
}

extension String {
  fileprivate func leftPadded(_ width: Int) -> String {
    String(repeating: "0", count: max(0, width - count)) + self
  }
}
