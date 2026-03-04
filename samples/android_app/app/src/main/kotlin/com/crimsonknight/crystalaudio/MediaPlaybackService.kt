package com.crimsonknight.crystalaudio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * MediaPlaybackService — foreground service for background audio + lock screen controls.
 *
 * Creates a MediaSession with transport control callbacks that forward
 * play/pause/next/previous events to the Crystal library via JNI.
 * Displays a persistent notification with media controls.
 */
class MediaPlaybackService : Service() {
    companion object {
        private const val TAG = "CrystalAudio"
        private const val CHANNEL_ID = "crystal_audio_playback"
        private const val NOTIFICATION_ID = 1
    }

    private lateinit var mediaSession: MediaSessionCompat
    private lateinit var stateBuilder: PlaybackStateCompat.Builder

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "MediaPlaybackService.onCreate")

        createNotificationChannel()

        mediaSession = MediaSessionCompat(this, "CrystalAudioSession").apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )

            stateBuilder = PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackStateCompat.ACTION_SEEK_TO or
                    PlaybackStateCompat.ACTION_STOP
                )

            setPlaybackState(stateBuilder.build())

            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    Log.i(TAG, "MediaSession: onPlay")
                    CrystalLib.onMediaPlay()
                    updatePlaybackState(PlaybackStateCompat.STATE_PLAYING)
                }

                override fun onPause() {
                    Log.i(TAG, "MediaSession: onPause")
                    CrystalLib.onMediaPause()
                    updatePlaybackState(PlaybackStateCompat.STATE_PAUSED)
                }

                override fun onSkipToNext() {
                    Log.i(TAG, "MediaSession: onSkipToNext")
                    CrystalLib.onMediaNext()
                }

                override fun onSkipToPrevious() {
                    Log.i(TAG, "MediaSession: onSkipToPrevious")
                    CrystalLib.onMediaPrevious()
                }

                override fun onSeekTo(pos: Long) {
                    Log.i(TAG, "MediaSession: onSeekTo $pos")
                    CrystalLib.onMediaSeek(pos)
                }

                override fun onStop() {
                    Log.i(TAG, "MediaSession: onStop")
                    CrystalLib.onMediaStop()
                    stopSelf()
                }
            })

            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        mediaSession.isActive = false
        mediaSession.release()
        super.onDestroy()
    }

    // --- Public API for Crystal JNI callbacks ---

    fun updateMetadata(title: String, artist: String, durationMs: Long) {
        val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
            .build()
        mediaSession.setMetadata(metadata)
        // Refresh notification
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIFICATION_ID, buildNotification())
    }

    fun updatePlaybackState(state: Int, positionMs: Long = 0L) {
        val pbState = stateBuilder
            .setState(state, positionMs, 1.0f)
            .build()
        mediaSession.setPlaybackState(pbState)
    }

    // --- Private ---

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Audio Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Crystal Audio playback controls"
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Crystal Audio")
            .setContentText("Playing audio")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .addAction(android.R.drawable.ic_media_previous, "Previous",
                createMediaAction(PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS))
            .addAction(android.R.drawable.ic_media_pause, "Pause",
                createMediaAction(PlaybackStateCompat.ACTION_PAUSE))
            .addAction(android.R.drawable.ic_media_next, "Next",
                createMediaAction(PlaybackStateCompat.ACTION_SKIP_TO_NEXT))
            .setOngoing(true)
            .build()
    }

    private fun createMediaAction(action: Long): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            setPackage(packageName)
        }
        return PendingIntent.getBroadcast(
            this, action.toInt(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
