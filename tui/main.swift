import Foundation

// costanza-tui                 the latest poems, title and opening lines
// costanza-tui by <pen name>   one poet's poems
// costanza-tui <poem id>       one poem in full
// Thin fetch of the same public read the web app makes (stanza_poems on api.jaybulb.com); nothing is stored.

struct Poem: Decodable { let id: String; let pen_name: String; let title: String; let body: String; let created_at: String }

let api = ProcessInfo.processInfo.environment["COSTANZA_API"] ?? "https://api.jaybulb.com"
let bold = "\u{1B}[1m", dim = "\u{1B}[2m", reset = "\u{1B}[0m"

func fetch(_ query: [URLQueryItem]) -> [Poem]? {
    var c = URLComponents(string: api + "/rest/stanza_poems")!
    c.queryItems = [URLQueryItem(name: "select", value: "id,pen_name,title,body,created_at"),
                    URLQueryItem(name: "order", value: "created_at.desc")] + query
    var req = URLRequest(url: c.url!); req.setValue("https://costanza.jaybulb.com", forHTTPHeaderField: "Origin")
    let done = DispatchSemaphore(value: 0); var out: [Poem]?
    URLSession.shared.dataTask(with: req) { data, _, _ in
        out = data.flatMap { try? JSONDecoder().decode([Poem].self, from: $0) }; done.signal()
    }.resume()
    done.wait(); return out
}

func day(_ iso: String) -> String { String(iso.prefix(10)) }

func card(_ p: Poem, full: Bool) -> String {
    let lines = p.body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let shown = full ? lines : Array(lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(2))
    var s = "\(bold)\(p.title)\(reset)\n\(dim)\(p.pen_name) · \(day(p.created_at))\(full ? "" : " · \(p.id)")\(reset)\n"
    s += shown.map { "  " + $0 }.joined(separator: "\n")
    if !full && lines.count > shown.count { s += "\n  \(dim)…\(reset)" }
    return s
}

let args = Array(CommandLine.arguments.dropFirst())
let poems: [Poem]?
var full = false
switch args.first {
case nil: poems = fetch([URLQueryItem(name: "limit", value: "10")])
case "by" where args.count > 1: poems = fetch([URLQueryItem(name: "pen_name", value: "eq." + args.dropFirst().joined(separator: " ")), URLQueryItem(name: "limit", value: "50")])
case "-h", "--help", "help":
    print("usage: costanza-tui [by <pen name> | <poem id>]"); exit(0)
case let id?: poems = fetch([URLQueryItem(name: "id", value: "eq." + id)]); full = true
}
guard let poems else { FileHandle.standardError.write("Could not reach \(api)\n".data(using: .utf8)!); exit(1) }
if poems.isEmpty { print(full ? "No poem with that id." : "No poems yet."); exit(0) }
print(poems.map { card($0, full: full) }.joined(separator: "\n\n"))
