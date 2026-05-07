import Darwin
import EventKit
import Foundation

struct AgendaError: Error, CustomStringConvertible {
    let description: String
}

struct Options {
    var json = false
    var days = 7
    var limit = 10
    var calendar: String?
    var name: String?
    var source: String?
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch let error as AgendaError {
    writeStyledError("agenda: \(error.description)")
    exit(1)
} catch {
    writeStyledError("agenda: \(error)")
    exit(1)
}

func run(_ args: [String]) throws {
    let command = args.first ?? "help"
    let rest = Array(args.dropFirst())

    switch command {
    case "help", "--help", "-h":
        printUsage()
    case "status":
        let options = try parseOptions(rest, allowDays: false, allowLimit: false, allowCalendar: false)
        try printStatus(json: options.json)
    case "request-access":
        let options = try parseOptions(rest, allowDays: false, allowLimit: false, allowCalendar: false)
        try requestAccess(json: options.json)
    case "calendar/list":
        let options = try parseOptions(rest, allowDays: false, allowLimit: false, allowCalendar: false)
        try listCalendars(json: options.json)
    case "calendar/create":
        let options = try parseOptions(
            rest,
            allowDays: false,
            allowLimit: false,
            allowCalendar: false,
            allowName: true,
            allowSource: true
        )
        try createCalendar(options: options)
    case "event/list":
        let options = try parseOptions(rest, allowDays: true, allowLimit: true, allowCalendar: true)
        try listUpcoming(options: options)
    default:
        throw AgendaError(description: "unknown command '\(command)'\nRun 'agenda --help' for usage.")
    }
}

func parseOptions(
    _ args: [String],
    allowDays: Bool,
    allowLimit: Bool,
    allowCalendar: Bool,
    allowName: Bool = false,
    allowSource: Bool = false
) throws -> Options {
    var options = Options()
    var index = 0

    func requireValue(after flag: String) throws -> String {
        let valueIndex = index + 1
        if valueIndex >= args.count || args[valueIndex].hasPrefix("-") {
            throw AgendaError(description: "\(flag) requires a value")
        }
        return args[valueIndex]
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--json":
            options.json = true
        case "--days":
            guard allowDays else { throw AgendaError(description: "--days is not valid for this command") }
            let value = try requireValue(after: arg)
            guard let days = Int(value), days > 0 else {
                throw AgendaError(description: "--days must be a positive integer")
            }
            options.days = days
            index += 1
        case "--limit":
            guard allowLimit else { throw AgendaError(description: "--limit is not valid for this command") }
            let value = try requireValue(after: arg)
            guard let limit = Int(value), limit > 0 else {
                throw AgendaError(description: "--limit must be a positive integer")
            }
            options.limit = limit
            index += 1
        case "--calendar":
            guard allowCalendar else { throw AgendaError(description: "--calendar is not valid for this command") }
            options.calendar = try requireValue(after: arg)
            index += 1
        case "--name":
            guard allowName else { throw AgendaError(description: "--name is not valid for this command") }
            let value = try requireValue(after: arg)
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgendaError(description: "--name must not be empty")
            }
            options.name = value
            index += 1
        case "--source":
            guard allowSource else { throw AgendaError(description: "--source is not valid for this command") }
            options.source = try requireValue(after: arg)
            index += 1
        default:
            if arg.hasPrefix("-") {
                throw AgendaError(description: "unknown flag '\(arg)'")
            }
            throw AgendaError(description: "unexpected argument '\(arg)'")
        }
        index += 1
    }

    return options
}

func printUsage() {
    print("""
    agenda — read macOS Calendar data through EventKit

    Usage:
      agenda status [--json]
      agenda request-access [--json]
      agenda calendar list [--json]
      agenda calendar create --name NAME [--source SOURCE] [--json]
      agenda event list [--days N] [--limit N] [--calendar NAME_OR_ID] [--json]

    Commands:
      status           Show Calendar permission status without prompting
      request-access   Ask macOS for Calendar read access
      calendar list    List readable calendars
      calendar create  Create a calendar if it does not already exist
      event list       List upcoming events

    Notes:
      Only request-access triggers the macOS permission prompt.
      Read commands fail with guidance when access has not been granted.
    """)
}

func printStatus(json: Bool) throws {
    let status = EKEventStore.authorizationStatus(for: .event)
    let payload: [String: Any] = [
        "status": statusName(status),
        "canRead": canReadEvents(status),
        "needsPrompt": status == .notDetermined,
    ]

    if json {
        try printJSON(payload)
    } else {
        var rows = [
            ["Status", payload["status"] as! String],
            ["Can read events", (payload["canRead"] as! Bool) ? "yes" : "no"],
        ]
        if payload["needsPrompt"] as! Bool {
            rows.append(["Next", "run 'agenda request-access'"])
        }
        printTable(headers: ["KEY", "VALUE"], rows: rows)
    }
}

func requestAccess(json: Bool) throws {
    let before = EKEventStore.authorizationStatus(for: .event)
    let store = EKEventStore()
    let granted: Bool

    if canReadEvents(before) {
        granted = true
    } else if before == .denied || before == .restricted {
        granted = false
    } else {
        granted = try requestCalendarAccess(store)
    }

    let after = EKEventStore.authorizationStatus(for: .event)
    let payload: [String: Any] = [
        "before": statusName(before),
        "after": statusName(after),
        "granted": granted,
        "canRead": canReadEvents(after),
    ]

    if json {
        try printJSON(payload)
    } else {
        var rows = [
            ["Before", statusName(before)],
            ["After", statusName(after)],
            ["Granted", granted ? "yes" : "no"],
            ["Can read events", canReadEvents(after) ? "yes" : "no"],
        ]
        if after == .denied || after == .restricted {
            rows.append([
                "Next",
                "enable Calendar access for this terminal app in System Settings → Privacy & Security → Calendars",
            ])
        }
        printTable(headers: ["KEY", "VALUE"], rows: rows)
    }
}

func requestCalendarAccess(_ store: EKEventStore) throws -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<Bool, Error>?

    let finish: (Bool, Error?) -> Void = { granted, error in
        if let error = error {
            result = .failure(error)
        } else {
            result = .success(granted)
        }
        semaphore.signal()
    }

    if #available(macOS 14.0, *) {
        store.requestFullAccessToEvents(completion: finish)
    } else {
        store.requestAccess(to: .event, completion: finish)
    }

    semaphore.wait()
    return try result?.get() ?? false
}

func listCalendars(json: Bool) throws {
    try requireReadAccess()

    let store = EKEventStore()
    let calendars = store.calendars(for: .event).sorted { left, right in
        left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }

    let rows = calendars.map { calendarPayload($0) }
    if json {
        try printJSON(rows)
        return
    }

    printTable(
        headers: ["ID", "TITLE", "SOURCE", "TYPE", "WRITABLE"],
        rows: rows.map { row in
            [row["id"]!, row["title"]!, row["source"]!, row["type"]!, row["writable"]!]
        }
    )
}

func createCalendar(options: Options) throws {
    try requireWriteAccess()

    guard let name = options.name else {
        throw AgendaError(description: "--name is required")
    }

    let store = EKEventStore()
    if let existing = store.calendars(for: .event).first(where: { $0.title == name }) {
        let payload = calendarPayload(existing, created: false)
        if options.json {
            try printJSON(payload)
        } else {
            printTable(headers: ["KEY", "VALUE"], rows: calendarCreateRows(payload))
        }
        return
    }

    let source = try selectSource(store: store, requested: options.source)
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = name
    calendar.source = source

    try store.saveCalendar(calendar, commit: true)

    let payload = calendarPayload(calendar, created: true)
    if options.json {
        try printJSON(payload)
    } else {
        printTable(headers: ["KEY", "VALUE"], rows: calendarCreateRows(payload))
    }
}

func listUpcoming(options: Options) throws {
    try requireReadAccess()

    let store = EKEventStore()
    var calendars = store.calendars(for: .event)

    if let filter = options.calendar {
        calendars = calendars.filter { calendar in
            calendar.calendarIdentifier == filter || calendar.title == filter
        }
        if calendars.isEmpty {
            throw AgendaError(description: "no calendar matched '\(filter)'")
        }
    }

    let now = Date()
    guard let end = Calendar.current.date(byAdding: .day, value: options.days, to: now) else {
        throw AgendaError(description: "could not compute end date")
    }

    let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
    let events = store.events(matching: predicate)
        .sorted { $0.startDate < $1.startDate }
        .prefix(options.limit)
        .map(eventPayload)

    if options.json {
        try printJSON(Array(events))
        return
    }

    printTable(
        headers: ["START", "END", "TITLE", "CALENDAR"],
        rows: events.map { row in
            [row["start"]!, row["end"]!, row["title"]!, row["calendar"]!]
        }
    )
}

func requireWriteAccess() throws {
    let status = EKEventStore.authorizationStatus(for: .event)
    if !canWriteEvents(status) {
        throw AgendaError(
            description: "Calendar write access is \(statusName(status)). Run 'agenda request-access' first."
        )
    }
}

func requireReadAccess() throws {
    let status = EKEventStore.authorizationStatus(for: .event)
    if !canReadEvents(status) {
        throw AgendaError(
            description: "Calendar read access is \(statusName(status)). Run 'agenda request-access' first."
        )
    }
}

func statusName(_ status: EKAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorized: return "authorized"
    case .fullAccess: return "fullAccess"
    case .writeOnly: return "writeOnly"
    @unknown default: return "unknown(\(status.rawValue))"
    }
}

func canReadEvents(_ status: EKAuthorizationStatus) -> Bool {
    switch status {
    case .authorized, .fullAccess:
        return true
    default:
        return false
    }
}

func canWriteEvents(_ status: EKAuthorizationStatus) -> Bool {
    switch status {
    case .authorized, .fullAccess, .writeOnly:
        return true
    default:
        return false
    }
}

func selectSource(store: EKEventStore, requested: String?) throws -> EKSource {
    if let requested = requested {
        if let source = store.sources.first(where: { $0.sourceIdentifier == requested || $0.title == requested }) {
            return source
        }
        throw AgendaError(description: "no source matched '\(requested)'")
    }

    if let source = store.defaultCalendarForNewEvents?.source {
        return source
    }

    if let source = store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) {
        return source
    }

    guard let source = store.sources.first else {
        throw AgendaError(description: "no Calendar sources available")
    }
    return source
}

func calendarPayload(_ calendar: EKCalendar, created: Bool? = nil) -> [String: String] {
    var payload = [
        "id": calendar.calendarIdentifier,
        "title": calendar.title,
        "source": calendar.source.title,
        "type": calendarTypeName(calendar.type),
        "writable": calendar.allowsContentModifications ? "true" : "false",
    ]
    if let created = created {
        payload["created"] = created ? "true" : "false"
    }
    return payload
}

func calendarCreateRows(_ payload: [String: String]) -> [[String]] {
    [
        ["Created", payload["created"] ?? "false"],
        ["Title", payload["title"] ?? ""],
        ["ID", payload["id"] ?? ""],
        ["Source", payload["source"] ?? ""],
        ["Writable", payload["writable"] ?? ""],
    ]
}

func eventPayload(_ event: EKEvent) -> [String: String] {
    [
        "id": event.eventIdentifier ?? "",
        "title": event.title ?? "(untitled)",
        "start": formatDate(event.startDate, allDay: event.isAllDay),
        "end": formatDate(event.endDate, allDay: event.isAllDay),
        "allDay": event.isAllDay ? "true" : "false",
        "calendar": event.calendar.title,
        "calendarId": event.calendar.calendarIdentifier,
        "location": event.location ?? "",
        "notes": event.notes ?? "",
        "url": event.url?.absoluteString ?? "",
    ]
}

func calendarTypeName(_ type: EKCalendarType) -> String {
    switch type {
    case .local: return "local"
    case .calDAV: return "calDAV"
    case .exchange: return "exchange"
    case .subscription: return "subscription"
    case .birthday: return "birthday"
    @unknown default: return "unknown(\(type.rawValue))"
    }
}

func formatDate(_ date: Date?, allDay: Bool) -> String {
    guard let date = date else { return "" }
    if allDay {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
    return formatter.string(from: date)
}

func printJSON(_ value: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    guard let string = String(data: data, encoding: .utf8) else {
        throw AgendaError(description: "failed to encode JSON")
    }
    print(string)
}

func printTable(headers: [String], rows: [[String]]) {
    let input = ([headers] + rows)
        .map { row in row.map(sanitizeTableCell).joined(separator: "|") }
        .joined(separator: "\n") + "\n"

    if !runGum(["table", "-s", "|", "-p", "--border.foreground=240"], input: input) {
        print(headers.joined(separator: "\t"))
        for row in rows {
            print(row.map(sanitizeTableCell).joined(separator: "\t"))
        }
    }
}

func sanitizeTableCell(_ value: String) -> String {
    value
        .replacingOccurrences(of: "|", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
}

func writeStyledError(_ text: String) {
    let message = text.trimmingCharacters(in: .newlines)
    if !runGum(["style", "--foreground", "196", "--bold", message], output: .standardError) {
        writeError(message + "\n")
    }
}

@discardableResult
func runGum(_ args: [String], input: String? = nil, output: FileHandle = .standardOutput) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    let gum = ProcessInfo.processInfo.environment["GUM"] ?? "gum"
    process.arguments = [gum] + args

    let stdout = Pipe()
    let stderr = Pipe()
    let stdin = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    if input != nil {
        process.standardInput = stdin
    }

    do {
        try process.run()
    } catch {
        return false
    }

    if let input = input {
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try? stdin.fileHandleForWriting.close()
    }

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        return false
    }

    output.write(data)
    return true
}

func writeError(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}
