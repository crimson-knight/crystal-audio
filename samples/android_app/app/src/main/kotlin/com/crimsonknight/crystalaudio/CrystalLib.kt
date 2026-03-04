package com.crimsonknight.crystalaudio

object CrystalLib {
    // --- Audio lifecycle ---
    external fun init(): Int
    external fun startRecording(path: String): Int
    external fun stopRecording(): Int
    external fun isRecording(): Int
    external fun startPlayback(paths: Array<String>): Int
    external fun stopPlayback(): Int

    // --- Media session callbacks (called from MediaPlaybackService) ---
    external fun onMediaPlay()
    external fun onMediaPause()
    external fun onMediaNext()
    external fun onMediaPrevious()
    external fun onMediaSeek(positionMs: Long)
    external fun onMediaStop()

    // --- Now playing info (called from Crystal to update MediaSession) ---
    external fun updateNowPlaying(title: String, artist: String, durationMs: Long)
    external fun updatePlaybackState(state: Int, positionMs: Long)
}
