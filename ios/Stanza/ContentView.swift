import AuthenticationServices
import LocalAuthentication
import Supabase
import SwiftUI

// Thin client on the same Supabase project the web app uses. The anon key ships in the web
// bundle already; RLS is what protects writes.
struct Poem: Codable, Identifiable {
    let id: String
    let user_id: String
    let pen_name: String
    let title: String
    let body: String
    let created_at: String
}

@Observable
final class Store {
    static let url = "https://tjsxsqlxjmanwvmywwvw.supabase.co"
    static let anon = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqc3hzcWx4am1hbnd2bXl3d3Z3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0OTc0MDEsImV4cCI6MjA4NjA3MzQwMX0.LphLfho3wdQC20MhtcnBpzQUNuBoTOobrugQbNGxc68"

    var poems: [Poem] = []
    var token: String? = UserDefaults.standard.string(forKey: "token")
    var userId: String? = UserDefaults.standard.string(forKey: "userId")
    var error = ""

    /// Used only for the Google/GitHub/X OAuth browser flow (PKCE), which needs a real
    /// client to drive ASWebAuthenticationSession. Everything else stays on raw REST above.
    private lazy var sbClient = SupabaseClient(supabaseURL: URL(string: Self.url)!, supabaseKey: Self.anon)

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: URL(string: Self.url + path)!)
        r.httpMethod = method
        r.httpBody = body
        r.setValue(Self.anon, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(token ?? Self.anon)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("return=representation", forHTTPHeaderField: "Prefer")
        return r
    }

    func load() async {
        do {
            let (data, _) = try await URLSession.shared.data(for: request("/rest/v1/stanza_poems?select=*&order=created_at.desc&limit=50"))
            poems = try JSONDecoder().decode([Poem].self, from: data)
        } catch { self.error = error.localizedDescription }
    }

    func signIn(email: String, password: String, signUp: Bool) async {
        struct Session: Decodable { let access_token: String?; let user: U?; let msg: String?; let error_description: String?; struct U: Decodable { let id: String } }
        let path = signUp ? "/auth/v1/signup" : "/auth/v1/token?grant_type=password"
        let body = try! JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        do {
            let (data, _) = try await URLSession.shared.data(for: request(path, method: "POST", body: body))
            let s = try JSONDecoder().decode(Session.self, from: data)
            if let t = s.access_token, let u = s.user?.id {
                token = t; userId = u
                UserDefaults.standard.set(t, forKey: "token"); UserDefaults.standard.set(u, forKey: "userId")
                error = ""
                if !signUp { saveBiometricCredentials(email: email, password: password) }
            } else { error = s.error_description ?? s.msg ?? (signUp ? "Check your email to confirm." : "Sign in failed") }
        } catch { self.error = error.localizedDescription }
    }

    // MARK: Face ID convenience sign-in
    // Optional shortcut for a returning user -- never a gate, poems stay public either way.
    private static let savedEmailKey = "costanza.biometric.email"

    func hasSavedBiometricCredentials() -> Bool {
        guard let email = UserDefaults.standard.string(forKey: Self.savedEmailKey) else { return false }
        return KeychainHelper.load(key: email) != nil
    }

    func biometricLogin() async {
        let context = LAContext()
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Sign in to Co-Stanza")
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard let email = UserDefaults.standard.string(forKey: Self.savedEmailKey),
              let data = KeychainHelper.load(key: email),
              let password = String(data: data, encoding: .utf8) else {
            error = "No saved sign-in found."
            return
        }
        await signIn(email: email, password: password, signUp: false)
    }

    private func saveBiometricCredentials(email: String, password: String) {
        guard let data = password.data(using: .utf8) else { return }
        UserDefaults.standard.set(email, forKey: Self.savedEmailKey)
        KeychainHelper.save(key: email, data: data)
    }

    private func clearBiometricCredentials() {
        if let email = UserDefaults.standard.string(forKey: Self.savedEmailKey) {
            KeychainHelper.delete(key: email)
        }
        UserDefaults.standard.removeObject(forKey: Self.savedEmailKey)
    }

    func signInWithApple(idToken: String, nonce: String) async {
        struct Session: Decodable { let access_token: String?; let user: U?; let msg: String?; let error_description: String?; struct U: Decodable { let id: String } }
        let body = try! JSONSerialization.data(withJSONObject: ["provider": "apple", "id_token": idToken, "nonce": nonce])
        do {
            let (data, _) = try await URLSession.shared.data(for: request("/auth/v1/token?grant_type=id_token", method: "POST", body: body))
            let s = try JSONDecoder().decode(Session.self, from: data)
            if let t = s.access_token, let u = s.user?.id {
                token = t; userId = u
                UserDefaults.standard.set(t, forKey: "token"); UserDefaults.standard.set(u, forKey: "userId")
                error = ""
            } else { error = s.error_description ?? s.msg ?? "Sign in with Apple failed" }
        } catch { self.error = error.localizedDescription }
    }

    /// `costanza://` must stay in the Supabase project's uri_allow_list and in
    /// CFBundleURLTypes on both platforms, or the callback lands nowhere.
    func signInWithOAuth(provider: Provider) async {
        do {
            try await sbClient.auth.signInWithOAuth(provider: provider, redirectTo: URL(string: "costanza://"))
            let session = try await sbClient.auth.session
            token = session.accessToken; userId = session.user.id.uuidString
            UserDefaults.standard.set(session.accessToken, forKey: "token")
            UserDefaults.standard.set(session.user.id.uuidString, forKey: "userId")
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Sends the reset email. The link opens the web app, which sets the new password.
    func forgot(email: String) async {
        let body = try! JSONSerialization.data(withJSONObject: ["email": email])
        var r = request("/auth/v1/recover", method: "POST", body: body)
        r.setValue("https://costanza.jaybulb.com/app#/reset", forHTTPHeaderField: "redirect_to")
        _ = try? await URLSession.shared.data(for: r)
        error = "Check your email for a reset link."
    }

    func signOut() {
        token = nil; userId = nil
        UserDefaults.standard.removeObject(forKey: "token"); UserDefaults.standard.removeObject(forKey: "userId")
        clearBiometricCredentials()
    }

    /// Calls the shared `delete-account` Edge Function on the spark Supabase project,
    /// which uses the service-role key to delete the authenticated user server-side
    /// (the anon-key client SDK has no permission to delete its own auth user).
    func deleteAccount() async -> Bool {
        guard let token else { return false }
        var r = URLRequest(url: URL(string: "\(Self.url)/functions/v1/delete-account")!)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (_, response) = try? await URLSession.shared.data(for: r),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            error = "Couldn't delete account. Try again."
            return false
        }
        signOut()
        return true
    }

    func publish(pen: String, title: String, body: String) async -> Bool {
        guard let userId else { return false }
        let json = try! JSONSerialization.data(withJSONObject: ["user_id": userId, "pen_name": pen, "title": title, "body": body])
        do {
            let (data, resp) = try await URLSession.shared.data(for: request("/rest/v1/stanza_poems", method: "POST", body: json))
            if (resp as? HTTPURLResponse)?.statusCode == 401 { signOut(); error = "Session expired. Sign in again."; return false }
            if let p = try? JSONDecoder().decode([Poem].self, from: data).first { poems.insert(p, at: 0); return true }
            error = String(data: data, encoding: .utf8) ?? "Publish failed"
        } catch { self.error = error.localizedDescription }
        return false
    }
}

struct ContentView: View {
    @State private var store = Store()
    @State private var writing = false
    @State private var account = false

    var body: some View {
        NavigationStack {
            List(store.poems) { p in
                NavigationLink(value: p.id) { PoemRow(poem: p) }
            }
            .listStyle(.plain)
            .overlay { if store.poems.isEmpty { ContentUnavailableView("Nothing here yet", systemImage: "text.alignleft", description: Text("Write the first one.")) } }
            .navigationTitle("Co-Stanza")
            .navigationDestination(for: String.self) { id in
                if let p = store.poems.first(where: { $0.id == id }) { PoemView(poem: p) }
            }
            .toolbar {
                ToolbarItem { Button(store.token == nil ? "Sign in" : "Account") { account = true } }
                ToolbarItem { Button("Write", systemImage: "square.and.pencil") { store.token == nil ? (account = true) : (writing = true) } }
            }
            .refreshable { await store.load() }
            .task { await store.load() }
            .sheet(isPresented: $writing) { WriteView(store: store) }
            .sheet(isPresented: $account) { AccountView(store: store) }
        }
    }
}

struct PoemRow: View {
    let poem: Poem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(poem.title).font(.headline)
            Text(poem.pen_name).font(.subheadline).foregroundStyle(.secondary)
            Text(poem.body.split(separator: "\n").first.map(String.init) ?? "").lineLimit(1).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
    }
}

struct PoemView: View {
    let poem: Poem
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(poem.title).font(.largeTitle.bold())
                Text(poem.pen_name).foregroundStyle(.secondary)
                Text(poem.body).font(.body).lineSpacing(6).padding(.top, 16)
            }
            .frame(maxWidth: 560, alignment: .leading).padding(24)
        }
    }
}

struct WriteView: View {
    var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pen") private var pen = ""
    @State private var title = ""
    @State private var text = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Your name", text: $pen)
                TextField("Title", text: $title)
                TextEditor(text: $text).frame(minHeight: 240)
                if !store.error.isEmpty { Text(store.error).foregroundStyle(.red) }
            }
            .navigationTitle("Write")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") { Task { busy = true; if await store.publish(pen: pen, title: title, body: text) { dismiss() }; busy = false } }
                        .disabled(busy || pen.isEmpty || title.isEmpty || text.isEmpty)
                }
            }
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

                    Button { Task { await store.signInWithOAuth(provider: .google); if store.token != nil { dismiss() } } } label: {
                        Text("Continue with Google").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                    Button { Task { await store.signInWithOAuth(provider: .github); if store.token != nil { dismiss() } } } label: {
                        Text("Continue with GitHub").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                    Button { Task { await store.signInWithOAuth(provider: .x); if store.token != nil { dismiss() } } } label: {
                        Text("Continue with X").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

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
