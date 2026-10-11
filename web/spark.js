// spark.js: drop-in for the slice of supabase-js the apps use, pointed at spark-api. No dependencies, works in browsers and Node 18+.
//   import { createClient } from './spark.js'; const sb = createClient('https://api.heyitsmejosh.com');
// Same shapes as supabase-js: { data, error } everywhere, sb.auth.*, sb.from(t)...then, sb.rpc, sb.storage.from(b), sb.functions.invoke.
// ponytail: OAuth redirects (Google/Apple/GitHub/X web) are not here; signInWithOAuth returns an error until the Worker has them.

export function createClient(url, _anonKey, opts = {}) {
  const API = url.replace(/\/+$/, "");
  const store = opts.storage ?? (typeof localStorage !== "undefined" ? localStorage : { _m: {}, getItem(k) { return this._m[k] ?? null; }, setItem(k, v) { this._m[k] = v; }, removeItem(k) { delete this._m[k]; } });
  const KEY = "spark.session";
  const listeners = new Set();
  let session = null;
  try { session = JSON.parse(store.getItem(KEY)); } catch {}
  let recoveryToken = null;
  const fail = (message, status) => ({ data: null, error: Object.assign(new Error(message), { status }) });
  const emit = (event) => listeners.forEach((fn) => { try { fn(event, session); } catch (e) { console.error(e); } });
  const save = (s, event) => { session = s; try { s ? store.setItem(KEY, JSON.stringify(s)) : store.removeItem(KEY); } catch {} emit(event); };
  const expired = () => !session || (JSON.parse(atob(session.access_token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).exp - 30) * 1000 < Date.now();

  let refreshing = null;
  async function fresh() {
    if (session && expired()) {
      refreshing ??= raw("POST", "/auth/token?grant_type=refresh_token", { refresh_token: session.refresh_token }, false)
        .then((r) => { r.error ? save(null, "SIGNED_OUT") : save(r.data, "TOKEN_REFRESHED"); }).finally(() => { refreshing = null; });
      await refreshing;
    }
    return session?.access_token;
  }
  async function raw(method, path, body, authed = true, headers = {}) {
    const token = authed ? await fresh() : null;
    let res;
    try {
      res = await fetch(API + path, { method, headers: { ...(body !== undefined && !(body instanceof ArrayBuffer) && !(body instanceof Blob) && { "Content-Type": "application/json" }), ...(token && { Authorization: `Bearer ${token}` }), ...headers }, body: body === undefined ? undefined : body instanceof ArrayBuffer || body instanceof Blob || typeof body === "string" ? body : JSON.stringify(body) });
    } catch (e) { return fail(String(e.message || e), 0); }
    const text = await res.text(); let json = null; try { json = JSON.parse(text); } catch { json = text; }
    return res.ok ? { data: json, error: null } : fail(json?.error || res.statusText, res.status);
  }
  const startSession = (r, event = "SIGNED_IN") => { if (!r.error) save(r.data, event); return r.error ? r : { data: { session, user: session.user }, error: null }; };

  // password recovery links land on the app with ?recovery_token=...; surface it the way supabase-js did
  if (typeof location !== "undefined" && typeof history !== "undefined") {
    const u = new URL(location.href), t = u.searchParams.get("recovery_token");
    if (t) { recoveryToken = t; u.searchParams.delete("recovery_token"); history.replaceState(null, "", u); queueMicrotask(() => emit("PASSWORD_RECOVERY")); }
  }

  const auth = {
    onAuthStateChange(fn) { listeners.add(fn); queueMicrotask(() => fn(session ? "INITIAL_SESSION" : "SIGNED_OUT", session)); return { data: { subscription: { unsubscribe: () => listeners.delete(fn) } } }; },
    async getSession() { await fresh(); return { data: { session }, error: null }; },
    async getUser() { if (!(await fresh())) return fail("not signed in", 401); return raw("GET", "/auth/user"); },
    async signInWithPassword({ email, password }) { return startSession(await raw("POST", "/auth/token?grant_type=password", { email, password }, false)); },
    async signUp({ email, password, options = {} }) { return raw("POST", "/auth/signup", { email, password, data: options.data, redirect_to: options.emailRedirectTo }, false).then((r) => (r.error ? r : { data: { user: r.data, session: null }, error: null })); },
    async signInWithIdToken({ provider, token, nonce }) { return startSession(await raw("POST", "/auth/token?grant_type=id_token", { provider, id_token: token, nonce }, false)); },
    async signInWithOAuth() { return fail("Social sign-in is not available on this build yet. Use email.", 501); },
    async resetPasswordForEmail(email, options = {}) { return raw("POST", "/auth/recover", { email, redirect_to: options.redirectTo }, false); },
    async updateUser({ password, data }) {
      if (password && recoveryToken) { // arrived from a reset link: no session yet, the token is the credential
        const r = startSession(await raw("POST", "/auth/reset", { token: recoveryToken, password }, false), "USER_UPDATED");
        if (!r.error) recoveryToken = null;
        return r.error ? r : { data: { user: session.user }, error: null };
      }
      const r = await raw("PUT", "/auth/user", { password, data });
      if (!r.error && session) save({ ...session, user: r.data }, "USER_UPDATED");
      return r.error ? r : { data: { user: r.data }, error: null };
    },
    async signOut() { if (session) await raw("POST", "/auth/logout", {}); save(null, "SIGNED_OUT"); return { error: null }; },
    async deleteAccount() { const r = await raw("DELETE", "/auth/user"); if (!r.error) save(null, "SIGNED_OUT"); return r; },
  };

  // from(t): PostgREST-style builder. Awaiting it runs the request.
  const OPS = ["eq", "neq", "gt", "gte", "lt", "lte", "like", "ilike"];
  function from(table) {
    let method = "GET", body, qs = [], headers = {}, one = null, wantRows = false;
    const q = {
      select(cols = "*") { qs.push(["select", cols.replace(/\s+/g, "")]); wantRows = true; return q; },
      insert(rows) { method = "POST"; body = rows; return q; },
      upsert(rows, o = {}) { method = "POST"; body = rows; headers.Prefer = "resolution=merge-duplicates"; if (o.onConflict) qs.push(["on_conflict", o.onConflict]); return q; },
      update(v) { method = "PATCH"; body = v; return q; },
      delete() { method = "DELETE"; return q; },
      in(c, list) { qs.push([c, `in.(${list.map((x) => `"${x}"`).join(",")})`]); return q; },
      is(c, v) { qs.push([c, `is.${v}`]); return q; },
      order(c, { ascending = true } = {}) { qs.push(["order", `${c}.${ascending ? "asc" : "desc"}`]); return q; },
      limit(n) { qs.push(["limit", n]); return q; },
      range(a, b) { qs.push(["offset", a], ["limit", b - a + 1]); return q; },
      single() { one = "single"; return q; },
      maybeSingle() { one = "maybe"; return q; },
      async then(ok, bad) {
        const params = new URLSearchParams(); qs.forEach(([k, v]) => params.append(k, v));
        let r = await raw(method, `/rest/${table}${params.size ? `?${params}` : ""}`, body, true, headers);
        if (!r.error && one) {
          if (r.data.length === 1) r = { data: r.data[0], error: null };
          else if (one === "maybe" && !r.data.length) r = { data: null, error: null };
          else r = fail(r.data.length ? "multiple rows returned" : "no rows returned", 406);
        } else if (!r.error && method !== "GET" && !wantRows) r = { data: null, error: null };
        return Promise.resolve(r).then(ok, bad);
      },
    };
    for (const op of OPS) q[op] = (c, v) => { qs.push([c, `${op}.${v}`]); return q; };
    return q;
  }

  const storage = { from: (bucket) => ({
    async upload(path, file, o = {}) {
      const r = await raw(o.upsert ? "PUT" : "POST", `/storage/${bucket}/${path}`, file, true, { "Content-Type": o.contentType || file.type || "application/octet-stream" });
      return r.error ? r : { data: { path: r.data.path }, error: null };
    },
    getPublicUrl: (path) => ({ data: { publicUrl: `${API}/storage/${bucket}/${path}` } }),
  }) };

  return {
    auth, from, storage,
    rpc: (fn, args = {}) => { const p = raw("POST", `/rpc/${fn}`, args); p.single = () => p.then((r) => (r.error ? r : { data: Array.isArray(r.data) ? r.data[0] ?? null : r.data, error: null })); return p; },
    functions: { invoke: (name, o = {}) => raw("POST", `/functions/${name}`, o.body ?? {}) },
  };
}
