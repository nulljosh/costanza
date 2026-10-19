package com.nulljosh.stanza

import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState

fun main() = application {
    Window(
        onCloseRequest = ::exitApplication,
        title = "Co-Stanza",
        state = rememberWindowState(width = 720.dp, height = 720.dp),
    ) {
        StanzaTheme { AppScreen() }
    }
}
