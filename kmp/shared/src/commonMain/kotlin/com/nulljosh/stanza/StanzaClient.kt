package com.nulljosh.stanza

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.patch
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class Poem(val id: String, val user_id: String, val pen_name: String, val title: String, val body: String, val created_at: String)

@Serializable
private data class Session(val access_token: String? = null, val refresh_token: String? = null, val user: U? = null, val error: String? = null) {
    @Serializable data class U(val id: String)
}

/** jaybulb-api (api.jaybulb.com), the same backend as the web and Apple apps. The server owns writes: insert signed in, update and delete owner. */
class StanzaClient(private val http: HttpClient = defaultClient()) {
    var token: String? = null
    var userId: String? = null
    /** Kept on disk by the app so a relaunch stays signed in; it rotates on every use. */
    var refreshToken: String? = null

    companion object {
        const val URL = "https://api.jaybulb.com"
        fun defaultClient() = HttpClient {
            install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true; isLenient = true }) }
            install(HttpTimeout) { requestTimeoutMillis = 10_000; connectTimeoutMillis = 10_000 }
        }
    }

    private fun io.ktor.client.request.HttpRequestBuilder.auth() {
        token?.let { header("Authorization", "Bearer $it") }
        contentType(ContentType.Application.Json)
    }

    suspend fun feed(): List<Poem> = try {
        http.get("$URL/rest/stanza_poems?select=*&order=created_at.desc&limit=50") { auth() }.body()
    } catch (e: Exception) { emptyList() }

    /** Returns an error message, or null on success. */
    suspend fun signIn(email: String, password: String, signUp: Boolean): String? = try {
        val path = if (signUp) "/auth/signup" else "/auth/token?grant_type=password"
        val s: Session = http.post(URL + path) { auth(); setBody(mapOf("email" to email, "password" to password, "redirect_to" to "https://costanza.jaybulb.com/app")) }.body()
        if (s.access_token != null && s.user != null) { token = s.access_token; userId = s.user.id; refreshToken = s.refresh_token; null }
        else s.error ?: if (signUp) "Check your email to confirm." else "Sign in failed"
    } catch (e: Exception) { e.message }

    /** Trades a saved refresh token for a fresh session. False when it expired or was revoked. */
    suspend fun resume(refresh: String): Boolean = try {
        val s: Session = http.post("$URL/auth/token?grant_type=refresh_token") { auth(); setBody(mapOf("refresh_token" to refresh)) }.body()
        if (s.access_token != null && s.user != null) { token = s.access_token; userId = s.user.id; refreshToken = s.refresh_token; true } else false
    } catch (e: Exception) { false }

    fun signOut() { token = null; userId = null; refreshToken = null }

    /** Sends the reset email; the link opens the web app to set a new password. */
    suspend fun forgot(email: String): String = try {
        http.post("$URL/auth/recover") { auth(); setBody(mapOf("email" to email, "redirect_to" to "https://costanza.jaybulb.com/app#/reset")) }
        "Check your email for a reset link."
    } catch (e: Exception) { e.message ?: "Failed" }

    suspend fun publish(pen: String, title: String, body: String): Result<Poem> = try {
        if (token == null) error("Not signed in")
        val r = http.post("$URL/rest/stanza_poems") { auth(); setBody(mapOf("pen_name" to pen, "title" to title, "body" to body)) }
        if (r.status.value in 200..299) Result.success(r.body<List<Poem>>().first()) else Result.failure(Exception(r.bodyAsText()))
    } catch (e: Exception) { Result.failure(e) }

    /** Owner only; the server answers 0 rows for anyone else's poem. */
    suspend fun update(id: String, pen: String, title: String, body: String): Result<Poem> = try {
        if (token == null) error("Not signed in")
        val r = http.patch("$URL/rest/stanza_poems?id=eq.$id") { auth(); setBody(mapOf("pen_name" to pen, "title" to title, "body" to body)) }
        val rows = if (r.status.value in 200..299) r.body<List<Poem>>() else error(r.bodyAsText())
        rows.firstOrNull()?.let { Result.success(it) } ?: Result.failure(Exception("Only the poet can edit this poem."))
    } catch (e: Exception) { Result.failure(e) }
}
