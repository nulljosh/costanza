package com.nulljosh.stanza

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

@Composable
fun StanzaTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = lightColorScheme(), content = content)

private enum class Screen { Feed, Poem, Write, Account }

// ponytail: session is in-memory; sign in again after relaunch. Persist via multiplatform-settings if asked.
@Composable
fun AppScreen(client: StanzaClient = remember { StanzaClient() }) {
    val scope = rememberCoroutineScope()
    var poems by remember { mutableStateOf(listOf<Poem>()) }
    var screen by remember { mutableStateOf(Screen.Feed) }
    var open by remember { mutableStateOf<Poem?>(null) }
    var signedIn by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { poems = client.feed() }

    Surface(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().widthIn(max = 640.dp).padding(24.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                TextButton({ screen = Screen.Feed }) { Text("Co-Stanza", style = MaterialTheme.typography.titleLarge) }
                Spacer(Modifier.weight(1f))
                TextButton({ screen = if (signedIn) Screen.Write else Screen.Account }) { Text("Write") }
                TextButton({ screen = Screen.Account }) { Text(if (signedIn) "Account" else "Sign in") }
            }
            HorizontalDivider()
            when (screen) {
                Screen.Feed -> LazyColumn {
                    if (poems.isEmpty()) item { Text("Nothing here yet. Write the first one.", Modifier.padding(32.dp), color = MaterialTheme.colorScheme.outline) }
                    items(poems) { p ->
                        Column(Modifier.fillMaxWidth().padding(vertical = 16.dp)) {
                            TextButton({ open = p; screen = Screen.Poem }, contentPadding = PaddingValues(0.dp)) { Text(p.title, style = MaterialTheme.typography.titleMedium) }
                            Text(p.pen_name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                            Text(p.body, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 8.dp))
                        }
                        HorizontalDivider()
                    }
                }
                Screen.Poem -> open?.let { p ->
                    Column(Modifier.verticalScroll(rememberScrollState()).padding(top = 16.dp)) {
                        Text(p.title, style = MaterialTheme.typography.headlineMedium)
                        Text(p.pen_name, color = MaterialTheme.colorScheme.outline)
                        Text(p.body, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = 16.dp))
                    }
                }
                Screen.Write -> {
                    var pen by remember { mutableStateOf("") }
                    var title by remember { mutableStateOf("") }
                    var body by remember { mutableStateOf("") }
                    var err by remember { mutableStateOf("") }
                    Column(Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(pen, { pen = it }, label = { Text("Your name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(title, { title = it }, label = { Text("Title") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(body, { body = it }, label = { Text("The poem") }, modifier = Modifier.fillMaxWidth().height(280.dp))
                        Button({ scope.launch { client.publish(pen, title, body).onSuccess { poems = listOf(it) + poems; open = it; screen = Screen.Poem }.onFailure { err = it.message ?: "Failed" } } },
                            enabled = pen.isNotBlank() && title.isNotBlank() && body.isNotBlank()) { Text("Publish") }
                        if (err.isNotEmpty()) Text(err, color = MaterialTheme.colorScheme.error)
                    }
                }
                Screen.Account -> {
                    var email by remember { mutableStateOf("") }
                    var pw by remember { mutableStateOf("") }
                    var msg by remember { mutableStateOf("") }
                    Column(Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (signedIn) Button({ client.token = null; client.userId = null; signedIn = false; screen = Screen.Feed }) { Text("Sign out") }
                        else {
                            OutlinedTextField(email, { email = it }, label = { Text("Email") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(pw, { pw = it }, label = { Text("Password") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button({ scope.launch { msg = client.signIn(email, pw, false) ?: ""; if (client.token != null) { signedIn = true; screen = Screen.Write } } }) { Text("Sign in") }
                                OutlinedButton({ scope.launch { msg = client.signIn(email, pw, true) ?: "" } }) { Text("Create account") }
                            }
                            TextButton({ scope.launch { msg = client.forgot(email) } }, enabled = email.isNotBlank()) { Text("Forgot password?") }
                            if (msg.isNotEmpty()) Text(msg, color = MaterialTheme.colorScheme.outline)
                        }
                    }
                }
            }
        }
    }
}
