package com.crimsonknight.crystalaudio

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val initResult = CrystalLib.init()

        setContent {
            MaterialTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    CrystalAudioScreen(initResult = initResult)
                }
            }
        }
    }

    companion object {
        init {
            System.loadLibrary("crystal_audio")
        }
    }
}

@Composable
fun CrystalAudioScreen(initResult: Int) {
    var isRecording by remember { mutableStateOf(false) }
    var timerText by remember { mutableStateOf("00:00") }
    var statusText by remember { mutableStateOf(if (initResult == 0) "Ready" else "Init failed (code $initResult)") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = "Crystal Audio",
            fontSize = 28.sp,
            style = MaterialTheme.typography.headlineLarge,
            modifier = Modifier.padding(bottom = 24.dp)
        )

        Text(
            text = timerText,
            fontSize = 48.sp,
            style = MaterialTheme.typography.displayMedium,
            modifier = Modifier.padding(bottom = 32.dp)
        )

        Button(
            onClick = {
                if (isRecording) {
                    val result = CrystalLib.stopRecording()
                    isRecording = false
                    timerText = "00:00"
                    statusText = if (result == 0) "Recording stopped" else "Stop failed (code $result)"
                } else {
                    val outputPath = "/sdcard/crystal_audio_recording.wav"
                    val result = CrystalLib.startRecording(outputPath)
                    if (result == 0) {
                        isRecording = true
                        statusText = "Recording..."
                    } else {
                        statusText = "Start failed (code $result)"
                    }
                }
            },
            modifier = Modifier.padding(bottom = 16.dp)
        ) {
            Text(text = if (isRecording) "Stop" else "Record")
        }

        Text(
            text = statusText,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
