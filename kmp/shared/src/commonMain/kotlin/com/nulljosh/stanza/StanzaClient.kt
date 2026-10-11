package com.nulljosh.stanza

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.header
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
private data class Session(val access_token: String? = null, val user: U? = null, val msg: String? = null, val error_description: String? = null) {
    @Serializable data class U(val id: String)
}

/** Same Supabase project and anon key as the web app. RLS protects writes. */
class StanzaClient(private val http: HttpClient = defaultClient()) {
    var token: String? = null
    var userId: String? = null

    companion object {
        const val URL = "https://tjsxsqlxjmanwvmywwvw.supabase.co"
        const val ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqc3hzcWx4am1hbnd2bXl3d3Z3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0OTc0MDEsImV4cCI6MjA4NjA3MzQwMX0.LphLfho3wdQC20MhtcnBpzQUNuBoTOobrugQbNGxc68"
        fun defaultClient() = HttpClient {
            install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true; isLenient = true }) }
            install(HttpTimeout) { requestTimeoutMillis = 10_000; connectTimeoutMillis = 10_000 }
        }
    }

    private fun io.ktor.client.request.HttpRequestBuilder.auth() {
        header("apikey", ANON_KEY)
        header("Authorization", "Bearer ${token ?: ANON_KEY}")
        header("Prefer", "return=representation")
        contentType(ContentType.Application.Json)
    }

    suspend fun feed(): List<Poem> = try {
        http.get("$URL/rest/v1/stanza_poems?select=*&order=created_at.desc&limit=50") { auth() }.body()
    } catch (e: Exception) { emptyList() }

    /** Returns an error message, or null on success. */
    suspend fun signIn(email: String, password: String, signUp: Boolean): String? = try {
        val path = if (signUp) "/auth/v1/signup" else "/auth/v1/token?grant_type=password"
        val s: Session = http.post(URL + path) { auth(); setBody(mapOf("email" to email, "password" to password)) }.body()
        if (s.access_token != null && s.user != null) { token = s.access_token; userId = s.user.id; null }
        else s.error_description ?: s.msg ?: if (signUp) "Check your email to confirm." else "Sign in failed"
    } catch (e: Exception) { e.message }

    /** Sends the reset email; the link opens the web app to set a new password. */
    suspend fun forgot(email: String): String = try {
        http.post("$URL/auth/v1/recover?redirect_to=https://costanza.jaybulb.com/app%23/reset") { auth(); setBody(mapOf("email" to email)) }
        "Check your email for a reset link."
    } catch (e: Exception) { e.message ?: "Failed" }

    suspend fun publish(pen: String, title: String, body: String): Result<Poem> = try {
        val uid = userId ?: error("Not signed in")
        val r = http.post("$URL/rest/v1/stanza_poems") { auth(); setBody(mapOf("user_id" to uid, "pen_name" to pen, "title" to title, "body" to body)) }
        if (r.status.value in 200..299) Result.success(r.body<List<Poem>>().first()) else Result.failure(Exception(r.bodyAsText()))
    } catch (e: Exception) { Result.failure(e) }
}
