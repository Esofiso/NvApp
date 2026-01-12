package com.example.nvapp_mobile // <-- Paket ismini kontrol et

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.graphics.Color

class ToggleWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_TOGGLE = "com.example.nvapp_mobile.ACTION_TOGGLE"
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        appWidgetIds.forEach { appWidgetId ->
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TOGGLE) {
            val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                toggleColor(context, appWidgetId)
            }
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val prefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
        val isGreen = prefs.getBoolean("is_green_$appWidgetId", false)

        val views = RemoteViews(context.packageName, R.layout.widget_toggle)
        
        // DİKKAT: Artık 'toggle_layout' değil, 'toggle_box' kullanıyoruz (ImageView)
        // ImageView olduğu için 'setColorFilter' kullanmak daha sağlıklıdır ama background da çalışır.
        // Biz yine de setInt ile backgroundColor yapalım, ImageView bunu destekler.
        
        if (isGreen) {
            // Koyu Yeşil (#006400)
            views.setInt(R.id.toggle_box, "setColorFilter", Color.parseColor("#025c02"))
        } else {
            // Koyu Kırmızı (#8B0000)
            views.setInt(R.id.toggle_box, "setColorFilter", Color.parseColor("#570202"))
        }

        val intent = Intent(context, ToggleWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        
        val pendingIntent = PendingIntent.getBroadcast(context, appWidgetId, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        
        // Tıklama özelliğini de iç kutuya veriyoruz
        views.setOnClickPendingIntent(R.id.toggle_box, pendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun toggleColor(context: Context, appWidgetId: Int) {
        val prefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
        val isGreen = prefs.getBoolean("is_green_$appWidgetId", false)
        prefs.edit().putBoolean("is_green_$appWidgetId", !isGreen).apply()
        updateAppWidget(context, AppWidgetManager.getInstance(context), appWidgetId)
    }
}