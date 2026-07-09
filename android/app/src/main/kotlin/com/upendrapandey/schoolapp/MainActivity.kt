package com.upendrapandey.schoolapp

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

class MainActivity: FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "default"
            val channelName = "Default Notifications"
            val channelDescription = "Notifications for messages and updates"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
                enableLights(true)
                enableVibration(true)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
}
