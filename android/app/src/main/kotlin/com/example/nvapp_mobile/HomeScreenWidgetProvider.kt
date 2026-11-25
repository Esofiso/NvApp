package com.example.nvapp_mobile // Mevcut paket adın neyse onu koru

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.widget.RemoteViews
import org.json.JSONArray

class HomeScreenWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_VAKIT_GECISI = "com.example.nvapp_mobile.ACTION_VAKIT_GECISI"
        private const val PREFS_NAME = "HomeWidgetPreferences"
        private const val ALARM_REQUEST_CODE = 7701
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action
        if (action == ACTION_VAKIT_GECISI ||
            action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_TIME_CHANGED ||
            action == Intent.ACTION_TIMEZONE_CHANGED
        ) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, HomeScreenWidgetProvider::class.java)
            val ids = appWidgetManager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                onUpdate(context, appWidgetManager, ids)
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val takvimJson = prefs.getString("vakit_takvimi", null)
        val siradaki = siradakiVaktiBul(takvimJson)

        for (widgetId in appWidgetIds) {
            // NOT: Buradaki R.layout.widget_layout adını kendi XML dosya adına göre değiştir
            val views = RemoteViews(context.packageName, R.layout.widget_layout)

            // Widget'a tıklayınca uygulamayı aç
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val clickPendingIntent = PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, clickPendingIntent)
            }

            if (siradaki != null) {
                val (vakitAdi, hedefMs) = siradaki
                val kalanMs = hedefMs - System.currentTimeMillis()
                val chronometerBase = SystemClock.elapsedRealtime() + kalanMs

                views.setTextViewText(R.id.widget_vakit_adi, vakitAdi)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    views.setChronometerCountDown(R.id.widget_kalan_sure, true)
                }
                views.setChronometer(R.id.widget_kalan_sure, chronometerBase, null, true)
            } else {
                views.setTextViewText(R.id.widget_vakit_adi, "NV")
                views.setChronometer(
                    R.id.widget_kalan_sure,
                    SystemClock.elapsedRealtime(),
                    null,
                    false
                )
                views.setTextViewText(R.id.widget_kalan_sure, "--:--")
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }

        // Bir sonraki vakit geçişi için tek seferlik uyandırma kur
        if (siradaki != null) {
            vakitGecisAlarmiKur(context, siradaki.second + 1000L)
        } else {
            vakitGecisAlarmiIptal(context)
        }
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        // Ana ekrandaki tüm widget'lar kaldırıldığında gereksiz alarmı temizle
        vakitGecisAlarmiIptal(context)
    }

    private fun siradakiVaktiBul(takvimJson: String?): Pair<String, Long>? {
        if (takvimJson.isNullOrEmpty()) return null
        val simdi = System.currentTimeMillis()
        return try {
            val arr = JSONArray(takvimJson)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val ms = obj.getLong("ms")
                if (ms > simdi) {
                    return Pair(obj.getString("ad"), ms)
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun alarmPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, HomeScreenWidgetProvider::class.java).apply {
            action = ACTION_VAKIT_GECISI
        }
        return PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun vakitGecisAlarmiKur(context: Context, triggerAtMs: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = alarmPendingIntent(context)
        alarmManager.cancel(pi)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            } else {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            }
        } else {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
        }
    }

    private fun vakitGecisAlarmiIptal(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(alarmPendingIntent(context))
    }
}