import AuthenticationServices
import SwiftUI

struct ContentView: View {
    @State private var store = Store()
    @State private var writing: Poem?? = nil
    @State private var account = false
    @State private var path: [Route] = []
    @State private var query = ""
    @State private var scope: Shelf = .all

    enum Shelf: String, CaseIterable, Identifiable { case all = "Everyone", following = "Following", saved = "Saved"; var id: Self { self } }

    private var list: [Poem] {
        let base = switch scope {
        case .all: store.shown
        case .following: store.shown.filter { store.follows.contains($0.pen_name) }
        case .saved: store.shown.filter { store.saved.contains($0.id) }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { [$0.title, $0.pen_name, $0.body].contains { $0.lowercased().contains(q) } }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(list) { p in
                NavigationLink(value: Route.poem(p.id)) { PoemRow(poem: p) }
            }
            .listStyle(.plain)
            .readingColumn()
            .overlay {
                if list.isEmpty {
                    if !query.isEmpty { ContentUnavailableView.search(text: query) }
                    else if scope == .saved { ContentUnavailableView("Nothing saved", systemImage: "bookmark", description: Text("Save a poem to read it again here.")) }
                    else if scope == .following { ContentUnavailableView("Nobody followed yet", systemImage: "person.2", description: Text(store.token == nil ? "Sign in, then follow a poet from their page." : "Follow a poet from their page and their new poems land here.")) }
                    else { ContentUnavailableView("Nothing here yet", systemImage: "text.alignleft", description: Text("Write the first one.")) }
                }
            }
            .navigationTitle("Co-Stanza")
            .searchable(text: $query, prompt: "Poems and poets")
            .searchScopes($scope) { ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) } }
            .navigationDestination(for: Route.self) { r in
                switch r {
                case .poem(let id):
                    if let p = store.poems.first(where: { $0.id == id }) { PoemView(poem: p, store: store) { writing = p } }
                case .author(let name): AuthorView(name: name, store: store)
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { account = true } label: {
                        Label(store.token == nil ? "Sign in" : "Account", systemImage: store.token == nil ? "person.crop.circle" : "person.crop.circle.fill")
                    }
                }
                ToolbarItem {
                    Button { store.token == nil ? (account = true) : (writing = .some(nil)) } label: { Label("Write", systemImage: "square.and.pencil") }
                        .prominentGlass()
                }
            }
            .refreshable { await store.load() }
            .task {
                await store.load()
                // -shotPoem YES opens the newest poem, for store screenshots.
                if UserDefaults.standard.bool(forKey: "shotPoem"), let p = store.shown.first { path = [.poem(p.id)] }
                if UserDefaults.standard.bool(forKey: "shotAuthor"), let p = store.shown.first { path = [.author(p.pen_name)] }
            }
            .sheet(item: Binding(get: { writing.map(EditTarget.init) }, set: { if $0 == nil { writing = nil } })) { t in
                WriteView(store: store, editing: t.poem)
            }
            .sheet(isPresented: $account) { AccountView(store: store) }
        }
        .tint(.accentPink)
    }
}

enum Route: Hashable { case poem(String), author(String) }
private struct EditTarget: Identifiable { let poem: Poem?; var id: String { poem?.id ?? "new" } }

extension Color { static let accentPink = Color(red: 0.82, green: 0.16, blue: 0.36) } // brand #d12a5c

extension View {
    /// One centred column on iPad and Mac, like the poem page; a phone fills the width anyway.
    func readingColumn() -> some View { frame(maxWidth: 640).frame(maxWidth: .infinity) }

    /// The one prominent control gets tinted glass on iOS 26 and macOS 26; older systems keep the plain button.
    @ViewBuilder func prominentGlass() -> some View {
        if #available(iOS 26, macOS 26, *) { self.buttonStyle(.glassProminent) } else { self }
    }
}

/// When a poem went up, in words ("2 months ago"). Rows come as ISO 8601 or Postgres style
/// ("2026-09-09 17:36:57.461112+00"); the first 19 characters are always UTC wall time.
func ago(_ stamp: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let head = String(stamp.prefix(19)).replacingOccurrences(of: "T", with: " ")
    guard let d = f.date(from: head) else { return "" }
    return d.formatted(.relative(presentation: .named))
}

/// The opening stanza, at most four lines: what a reader decides on.
func opening(_ body: String) -> String {
    let stanza = body.components(separatedBy: "\n\n").first ?? body
    return stanza.split(separator: "\n", omittingEmptySubsequences: false).prefix(4).joined(separator: "\n")
}

struct Byline: View {
    let poem: Poem
    var size: CGFloat = 20
    var body: some View {
        HStack(spacing: 8) {
            PixelAvatar(seed: poem.pen_name).frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size / 5))
            Text(poem.pen_name).fontWeight(.medium)
            Text("·").foregroundStyle(.tertiary)
            Text(ago(poem.created_at)).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

struct PoemRow: View {
    let poem: Poem
    var byline = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if byline { Byline(poem: poem) } else { Text(ago(poem.created_at)).font(.subheadline).foregroundStyle(.secondary) }
            Text(poem.title).font(.title3.weight(.semibold))
            Text(opening(poem.body)).lineSpacing(4).foregroundStyle(.secondary).lineLimit(4)
        }
        .padding(.vertical, 12)
    }
}

struct PoemView: View {
    let poem: Poem
    var store: Store
    var edit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    private var mine: Bool { poem.user_id != nil && poem.user_id == store.userId }
    private var link: URL { URL(string: "https://costanza.jaybulb.com/app#/p/\(poem.id)")! }

    /// Reports go to a person who reads them and removes poems that break the rules within a day.
    private var reportURL: URL? {
        var c = URLComponents(string: "mailto:trommatic@icloud.com")
        c?.queryItems = [.init(name: "subject", value: "Co-Stanza report: \(poem.id)"),
                         .init(name: "body", value: "What is wrong with \"\(poem.title)\" by \(poem.pen_name)?\n\n\(link.absoluteString)")]
        return c?.url
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(poem.title).font(.largeTitle.bold())
                NavigationLink(value: Route.author(poem.pen_name)) { Byline(poem: poem, size: 24) }
                    .buttonStyle(.plain)
                Text(poem.body).font(.title3).lineSpacing(8).padding(.top, 20).textSelection(.enabled)
                KudosRow(poem: poem, store: store).padding(.top, 28)
            }
            .frame(maxWidth: 560, alignment: .leading).padding(24)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem {
                Button { store.toggleSaved(poem) } label: {
                    Label(store.saved.contains(poem.id) ? "Saved" : "Save", systemImage: store.saved.contains(poem.id) ? "bookmark.fill" : "bookmark")
                }
            }
            ToolbarItem { ShareLink(item: link, subject: Text(poem.title), message: Text("\(poem.title) by \(poem.pen_name)")) }
            ToolbarItem {
                Menu {
                    if mine {
                        Button("Edit", systemImage: "pencil") { edit() }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    } else {
                        if let url = reportURL { Link(destination: url) { Label("Report poem", systemImage: "flag") } }
                        Button("Hide poem", systemImage: "eye.slash") { store.hide(poem, author: false); dismiss() }
                        if poem.user_id != nil {
                            Button("Block author", systemImage: "hand.raised", role: .destructive) { store.hide(poem, author: true); dismiss() }
                        }
                    }
                } label: { Label("More", systemImage: "ellipsis") }
            }
        }
        .confirmationDialog("Delete this poem?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { if await store.delete(poem) { dismiss() } } }
        }
    }
}

struct WriteView: View {
    var store: Store
    var editing: Poem?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pen") private var pen = ""
    @State private var title = ""
    @State private var text = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Pen name", text: $pen)
                TextField("Title", text: $title)
                Section {
                    TextEditor(text: $text).frame(minHeight: 260)
                } footer: { Text("A blank line starts a new stanza.") }
                if !store.error.isEmpty { Text(store.error).foregroundStyle(.red) }
            }
            .navigationTitle(editing == nil ? "Write" : "Edit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Publish" : "Save") {
                        Task {
                            busy = true
                            let ok = if let editing { await store.update(editing, pen: pen, title: title, body: text) } else { await store.publish(pen: pen, title: title, body: text) }
                            if ok { dismiss() }
                            busy = false
                        }
                    }
                    .disabled(busy || pen.isEmpty || title.isEmpty || text.isEmpty)
                }
            }
            .onAppear { if let editing { pen = editing.pen_name; title = editing.title; text = editing.body } }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 480)
        #endif
    }
}

struct AccountView: View {
    var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var appleNonce = ""
    @State private var confirmingDelete = false
    @State private var deletingAccount = false

    var body: some View {
        NavigationStack {
            Form {
                if store.token != nil {
                    Button("Sign out") { store.signOut(); dismiss() }
                    Button("Delete account", role: .destructive) { confirmingDelete = true }
                        .disabled(deletingAccount)
                } else {
                    if store.hasSavedBiometricCredentials() {
                        Button { Task { await store.biometricLogin(); if store.token != nil { dismiss() } } } label: {
                            Label("Sign in with Face ID", systemImage: "faceid")
                        }
                    }
                    TextField("Email", text: $email).textContentType(.emailAddress)
                    SecureField("Password", text: $password)
                    Button("Sign in") { Task { await store.signIn(email: email, password: password, signUp: false); if store.token != nil { dismiss() } } }
                    Button("Create account") { Task { await store.signIn(email: email, password: password, signUp: true) } }
                    Button("Forgot password?") { Task { await store.forgot(email: email) } }.disabled(email.isEmpty)
                    SignInWithAppleButton(.signIn) { request in
                        appleNonce = randomNonce()
                        request.requestedScopes = [.email]
                        request.nonce = sha256(appleNonce)
                    } onCompletion: { result in
                        guard case .success(let auth) = result,
                              let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                              let tokenData = cred.identityToken,
                              let idToken = String(data: tokenData, encoding: .utf8) else { return }
                        Task {
                            await store.signInWithApple(idToken: idToken, nonce: appleNonce)
                            if store.token != nil { dismiss() }
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)

                    if !store.error.isEmpty { Text(store.error).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(store.token == nil ? "Sign in" : "Account")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog("Delete account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    deletingAccount = true
                    Task { if await store.deleteAccount() { dismiss() }; deletingAccount = false }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and all your poems. This cannot be undone.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 280)
        #endif
    }
}

import CryptoKit

private func randomNonce(length: Int = 32) -> String {
    let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length
    while remaining > 0 {
        var random: UInt8 = 0
        _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
        if random < chars.count { result.append(chars[Int(random)]); remaining -= 1 }
    }
    return result
}

private func sha256(_ input: String) -> String {
    SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
}
