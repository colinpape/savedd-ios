package com.savedd.browser

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import kotlinx.serialization.decodeFromString
import java.time.ZonedDateTime

object Proverbs {
    @Volatile private var cached:ProverbLibrary?=null
    fun library(context:Context):ProverbLibrary = cached ?: synchronized(this) {
        cached ?: AppJson.decodeFromString<ProverbLibrary>(context.assets.open("Proverbs.json").bufferedReader().use { it.readText() }).also { cached=it }
    }
    fun chapter(context:Context,day:Int) = library(context).chapters.first { it.day==day }
}
object ProverbReminders {
    const val CHANNEL="daily-proverb"
    fun allowed(context:Context):Boolean = NotificationManagerCompat.from(context).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT<33 || ContextCompat.checkSelfPermission(context,Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED)
    private fun alarm(context:Context):PendingIntent = PendingIntent.getBroadcast(context,40,Intent(context,ProverbAlarmReceiver::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun channel(context:Context) {
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(CHANNEL,"Daily Proverb",NotificationManager.IMPORTANCE_DEFAULT).apply { description="A daily chapter of Proverbs, with a highlighted verse" })
    }
    fun schedule(context:Context) {
        val manager=context.getSystemService(AlarmManager::class.java)
        manager.cancel(alarm(context))
        val prefs=AppStore(context).preferences
        if(!prefs.reminders || !allowed(context))return
        channel(context)
        val next=ReminderClock.next(ZonedDateTime.now(),prefs.hour,prefs.minute)
        // No restricted exact-alarm permission. Android may defer this under battery saving.
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,next.toInstant().toEpochMilli(),alarm(context))
    }
    fun deliver(context:Context) {
        val store=AppStore(context);val now=ZonedDateTime.now()
        if(!store.preferences.reminders||!allowed(context))return
        if(store.lastProverbDay==now.toLocalDate().toString())return
        val chapter=Proverbs.chapter(context,ReminderClock.chapter(now))
        val intent=Intent(context,MainActivity::class.java).putExtra("proverbDay",chapter.day).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val tap=PendingIntent.getActivity(context,100+chapter.day,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        channel(context)
        val body="${chapter.highlight} — ${chapter.reference} (WEB)"
        val notification=NotificationCompat.Builder(context,CHANNEL).setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Savedd Daily Proverb").setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(tap).setAutoCancel(true).build()
        try {
            NotificationManagerCompat.from(context).notify(50,notification)
            store.lastProverbDay=now.toLocalDate().toString()
        } catch (_: SecurityException) { }
    }
}
class ProverbAlarmReceiver:BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent) {
        val pending=goAsync()
        CoroutineScope(Dispatchers.IO).launch { try { ProverbReminders.deliver(context);ProverbReminders.schedule(context) } finally { pending.finish() } }
    }
}
class ProverbRescheduleReceiver:BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent) {
        if(intent.action in setOf(Intent.ACTION_BOOT_COMPLETED,Intent.ACTION_TIME_CHANGED,Intent.ACTION_TIMEZONE_CHANGED,Intent.ACTION_MY_PACKAGE_REPLACED))ProverbReminders.schedule(context)
    }
}
