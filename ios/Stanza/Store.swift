import Foundation
import LocalAuthentication
import Observation

// Thin client on jaybulb-api, the same backend the web app uses (Cloudflare Workers + D1), no SDK.
// The refresh token lives in the Keychain; the hour-long access token stays in memory.
struct Poem: Codable, Identifiable {
    let id: String
    let user_id: String?
    let pen_name: String
    let title: String
    let body: String
    let created_at: String
}

@Observable
final class Store {
    static let api = "https://api.jaybulb.com"
    private static let refreshKey = "costanza.refresh"

    var poems: [Poem] = []
    var token: String?
    var userId: String?
    var error = ""

    /// Poems and authors hidden on this device (App Review 1.2: hide and block for public posts).
    private(set) var hidden: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hidden") ?? [])
    var shown: [Poem] { poems.filter { !hidden.contains($0.id) && !hidden.contains("user:" + ($0.user_id ?? "")) } }

    /// Poems saved to read again, on this device only.
    private(set) var saved: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "saved") ?? [])
    func toggleSaved(_ p: Poem) {
        if saved.remove(p.id) == nil { saved.insert(p.id) }
        UserDefaults.standard.set(Array(saved), forKey: "saved")
    }

    func hide(_ p: Poem, author: Bool) {
        hidden.insert(author ? "user:" + (p.user_id ?? "") : p.id)
        UserDefaults.standard.set(Array(hidden), forKey: "hidden")
    }

    init() {
        UserDefaults.standard.removeObject(forKey: "token") // pre-jaybulb-api session, never valid here
        Task { _ = await refresh() }
    }

    private struct Session: Decodable { let access_token: String; let refresh_token: String; let user: U; struct U: Decodable { let id: String } }
    private struct Failure: Decodable { let error: String? }

    private func call(_ method: String, _ path: String, json: Any? = nil, authed: Bool = false) async throws -> Data {
        var r = URLRequest(url: URL(string: Self.api + path)!)
        r.httpMethod = method
        if let json { r.httpBody = try JSONSerialization.data(withJSONObject: json); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authed, let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, res) = try await URLSession.shared.data(for: r)
        let code = (res as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401, authed, token != nil, await refresh() { return try await call(method, path, json: json, authed: true) }
        guard code < 300 else {
            throw NSError(domain: "Co-Stanza", code: code, userInfo: [NSLocalizedDescriptionKey: (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? "Something went wrong"])
        }
        return data
    }

    private func start(_ data: Data) throws {
        let s = try JSONDecoder().decode(Session.self, from: data)
        token = s.access_token; userId = s.user.id
        Task { await loadFollows() }
        KeychainHelper.save(key: Self.refreshKey, data: Data(s.refresh_token.utf8))
        error = ""
    }

    private func refresh() async -> Bool {
        guard let d = KeychainHelper.load(key: Self.refreshKey), let rt = String(data: d, encoding: .utf8),
              let data = try? await call("POST", "/auth/token?grant_type=refresh_token", json: ["refresh_token": rt]),
              (try? start(data)) != nil else {
            token = nil; userId = nil
            return false
        }
        return true
    }

    func load() async {
        do { poems = try JSONDecoder().decode([Poem].self, from: await call("GET", "/rest/stanza_poems?select=*&order=created_at.desc&limit=50")) }
        catch { self.error = error.localizedDescription }
    }

    func signIn(email: String, password: String, signUp: Bool) async {
        do {
            if signUp {
                _ = try await call("POST", "/auth/signup", json: ["email": email, "password": password, "redirect_to": "https://costanza.jaybulb.com/app"])
                error = "Check your email to confirm, then sign in."
            } else {
                try start(await call("POST", "/auth/token?grant_type=password", json: ["email": email, "password": password]))
                saveBiometricCredentials(email: email, password: password)
            }
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

    /// The bundle id has to be in jaybulb-api's APPLE_AUDIENCES.
    func signInWithApple(idToken: String, nonce: String) async {
        do { try start(await call("POST", "/auth/token?grant_type=id_token", json: ["provider": "apple", "id_token": idToken, "nonce": nonce])) }
        catch { self.error = error.localizedDescription }
    }

    /// Sends the reset email. The link opens the web app, which sets the new password.
    func forgot(email: String) async {
        _ = try? await call("POST", "/auth/recover", json: ["email": email, "redirect_to": "https://costanza.jaybulb.com/app#/reset"])
        error = "Check your email for a reset link."
    }

    func signOut() {
        if token != nil { let t = token; Task { var r = URLRequest(url: URL(string: Self.api + "/auth/logout")!); r.httpMethod = "POST"; r.setValue("Bearer \(t ?? "")", forHTTPHeaderField: "Authorization"); _ = try? await URLSession.shared.data(for: r) } }
        token = nil; userId = nil; follows = []
        KeychainHelper.delete(key: Self.refreshKey)
        clearBiometricCredentials()
    }

    /// Deletes the account and every poem in it, server side (Apple 5.1.1(v)).
    func deleteAccount() async -> Bool {
        do { _ = try await call("DELETE", "/auth/user", authed: true) } catch {
            self.error = "Couldn't delete account. Try again."
            return false
        }
        poems.removeAll { $0.user_id == userId }
        signOut()
        return true
    }

    // MARK: Following and kudos (the web's, same tables). Your follow list and your kudos are yours alone;
    // only a poem's author sees how many kudos it has.

    private(set) var follows: Set<String> = []
    private struct Followed: Decodable { let pen_name: String }

    func loadFollows() async {
        guard token != nil, let d = try? await call("GET", "/rest/stanza_follows?select=pen_name", authed: true),
              let rows = try? JSONDecoder().decode([Followed].self, from: d) else { return }
        follows = Set(rows.map(\.pen_name))
    }

    func toggleFollow(_ name: String) async {
        let on = follows.contains(name)
        let q = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        do {
            if on { _ = try await call("DELETE", "/rest/stanza_follows?pen_name=eq.\(q)", authed: true); follows.remove(name) }
            else { _ = try await call("POST", "/rest/stanza_follows", json: ["pen_name": name], authed: true); follows.insert(name) }
        } catch { self.error = error.localizedDescription }
    }

    private struct Kudo: Decodable { let poem_id: String }
    private struct Count: Decodable { let count: Int }

    /// For a reader: whether they gave this poem kudos. For its author: how many it has.
    func kudos(for p: Poem) async -> (given: Bool, count: Int?) {
        guard token != nil else { return (false, nil) }
        if p.user_id == userId {
            let d = try? await call("POST", "/rpc/stanza_kudos_count", json: ["poem_id": p.id], authed: true)
            return (false, d.flatMap { try? JSONDecoder().decode(Count.self, from: $0) }?.count)
        }
        let d = try? await call("GET", "/rest/stanza_kudos?select=poem_id&poem_id=eq.\(p.id)", authed: true)
        return (!(d.flatMap { try? JSONDecoder().decode([Kudo].self, from: $0) } ?? []).isEmpty, nil)
    }

    func setKudos(_ p: Poem, given: Bool) async -> Bool {
        do {
            if given { _ = try await call("POST", "/rest/stanza_kudos", json: ["poem_id": p.id], authed: true) }
            else { _ = try await call("DELETE", "/rest/stanza_kudos?poem_id=eq.\(p.id)", authed: true) }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func update(_ p: Poem, pen: String, title: String, body: String) async -> Bool {
        do {
            let data = try await call("PATCH", "/rest/stanza_poems?id=eq.\(p.id)", json: ["pen_name": pen, "title": title, "body": body], authed: true)
            if let new = try JSONDecoder().decode([Poem].self, from: data).first, let i = poems.firstIndex(where: { $0.id == p.id }) { poems[i] = new; return true }
        } catch { self.error = error.localizedDescription }
        return false
    }

    func delete(_ p: Poem) async -> Bool {
        do { _ = try await call("DELETE", "/rest/stanza_poems?id=eq.\(p.id)", authed: true) } catch { self.error = error.localizedDescription; return false }
        poems.removeAll { $0.id == p.id }
        return true
    }

    func publish(pen: String, title: String, body: String) async -> Bool {
        guard token != nil else { error = "Sign in to publish."; return false }
        do {
            let data = try await call("POST", "/rest/stanza_poems", json: ["pen_name": pen, "title": title, "body": body], authed: true)
            if let p = try JSONDecoder().decode([Poem].self, from: data).first { poems.insert(p, at: 0); return true }
        } catch { self.error = error.localizedDescription }
        return false
    }
}
