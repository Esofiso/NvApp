package com.example.nvapp_mobile // <-- BURAYI KENDİ PAKET İSMİNLE KONTROL ET

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import com.example.nvapp_mobile.MainActivity 

class HomeScreenWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                
                // Verileri al, yoksa varsayılan değerleri göster
                val vakitAdi = widgetData.getString("vakit_adi", "NV")
                val kalanSure = widgetData.getString("kalan_sure", "Vakit")

                setTextViewText(R.id.widget_vakit_adi, vakitAdi)
                setTextViewText(R.id.widget_kalan_sure, kalanSure)

                // Tıklayınca uygulamayı aç
                val intent = Intent(context, MainActivity::class.java)
                val pendingIntent = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                
                setOnClickPendingIntent(R.id.widget_title, pendingIntent)
                setOnClickPendingIntent(R.id.widget_vakit_adi, pendingIntent)
                setOnClickPendingIntent(R.id.widget_kalan_sure, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}