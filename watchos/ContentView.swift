import SwiftUI

// ponytail: read-only glance, no sign-in/write on the watch. Same anon key/table as the other clients.
struct Poem: Codable, Identifiable {
    let id: String
    let pen_name: String
    let title: String
    let body: String
}

@MainActor
@Observable
final class WatchStore {
    static let url = "https://tjsxsqlxjmanwvmywwvw.supabase.co"
    static let anon = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqc3hzcWx4am1hbnd2bXl3d3Z3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0OTc0MDEsImV4cCI6MjA4NjA3MzQwMX0.LphLfho3wdQC20MhtcnBpzQUNuBoTOobrugQbNGxc68"

    var poems: [Poem] = []
    var error = ""

    func load() async {
        var r = URLRequest(url: URL(string: Self.url + "/rest/v1/stanza_poems?select=id,pen_name,title,body&order=created_at.desc&limit=20")!)
        r.setValue(Self.anon, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(Self.anon)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: r)
            poems = try JSONDecoder().decode([Poem].self, from: data)
        } catch { self.error = error.localizedDescription }
    }
}

struct ContentView: View {
    @State private var store = WatchStore()

    var body: some View {
        NavigationStack {
            List(store.poems) { p in
                NavigationLink(p.title) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.title).font(.headline)
                            Text(p.pen_name).font(.caption).foregroundStyle(.secondary)
                            Text(p.body).font(.body).padding(.top, 4)
                        }.padding()
                    }
                }
            }
            .overlay { if store.poems.isEmpty && store.error.isEmpty { ProgressView() } }
            .navigationTitle("Co-Stanza")
            .task { await store.load() }
            .refreshable { await store.load() }
        }
    }
}
