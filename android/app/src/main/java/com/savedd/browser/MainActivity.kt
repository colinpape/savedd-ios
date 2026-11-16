package com.savedd.browser

import android.Manifest
import android.app.DownloadManager
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.speech.RecognizerIntent
import android.webkit.*
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import kotlinx.coroutines.*

class MainActivity:ComponentActivity() {
    private val appScope=CoroutineScope(SupervisorJob()+Dispatchers.Main.immediate)
    private lateinit var browser:BrowserController
    private var upload:ValueCallback<Array<Uri>>?=null
    private var pendingDownload:(()->Unit)?=null
    private val uploadLauncher=registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        upload?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(it.resultCode,it.data));upload=null
    }
    private val speechLauncher=registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        it.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.let { text -> browser.voiceText=text }
    }
    private val notificationPermission=registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        browser.notificationsAllowed=ProverbReminders.allowed(this)
        if(granted) { browser.update(browser.prefs.copy(reminders=true));ProverbReminders.schedule(this) }
        else browser.error="Notifications were not enabled. You can change this in Android notification settings."
    }
    private val storagePermission=registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if(granted) pendingDownload?.invoke() else browser.error="Storage permission is needed to save downloads on this Android version."
        pendingDownload=null
    }
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window,false)
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)
        browser=BrowserController(this,appScope)
        browser.filePicker={ params,callback ->
            upload?.onReceiveValue(null);upload=callback
            runCatching { uploadLauncher.launch(params.createIntent()) }.onFailure { upload?.onReceiveValue(null);upload=null;browser.error="No file picker is available." }
        }
        browser.download={ url,agent,disposition,mime ->
            android.app.AlertDialog.Builder(this).setTitle("Download file?")
                .setMessage(URLUtil.guessFileName(url,disposition,mime))
                .setPositiveButton("Download") { _,_ -> download(url,agent,disposition,mime) }
                .setNegativeButton("Cancel",null).show()
        }
        browser.voice={ language ->
            val intent=Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_PROMPT,"Search or enter an address")
            if(language.isNotBlank())intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE,language)
            runCatching { speechLauncher.launch(intent) }.onFailure { browser.error="Voice input isn’t available on this device. You can use your keyboard’s microphone instead." }
        }
        receive(intent)
        setContent { SaveddTheme(dark=!browser.prefs.complete||browser.prefs.dark) { SaveddApp(browser,::enableReminders,::notificationSettings) } }
    }
    override fun onNewIntent(intent:Intent) { super.onNewIntent(intent);setIntent(intent);receive(intent) }
    private fun receive(intent:Intent) {
        intent.data?.toString()?.let { raw -> Routing.callback(raw)?.let { url ->
            if(browser.prefs.complete)browser.navigate(url) else browser.error="Finish setup, then request a new sign-in email inside Savedd."
        } }
        val day=intent.getIntExtra("proverbDay",0)
        if(day in 1..31)browser.readingDay=day
    }
    private fun enableReminders() {
        if(Build.VERSION.SDK_INT>=33 && ContextCompat.checkSelfPermission(this,Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) {
            if(browser.prefs.notificationAsked && !shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) {
                browser.error="Enable notifications in Android notification settings, then return to Savedd."
            } else {
                browser.update(browser.prefs.copy(notificationAsked=true))
                notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        } else if(!ProverbReminders.allowed(this)) {
            browser.error="Notifications are off for Savedd. Enable them in Android notification settings."
        } else { browser.update(browser.prefs.copy(reminders=true));browser.notificationsAllowed=true;ProverbReminders.schedule(this) }
    }
    private fun notificationSettings() { startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,packageName)) }
    private fun download(url:String,agent:String?,disposition:String?,mime:String?) {
        if(Uri.parse(url).scheme != "https") { browser.error="Downloads require a secure HTTPS connection.";return }
        val action={
            runCatching {
                val name=URLUtil.guessFileName(url,disposition,mime).replace(Regex("[\\\\/:*?\"<>|]"),"_")
                val request=DownloadManager.Request(Uri.parse(url)).setTitle(name).setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                    .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS,name)
                mime?.let { request.setMimeType(it) };agent?.let { request.addRequestHeader("User-Agent",it) }
                CookieManager.getInstance().getCookie(url)?.let { request.addRequestHeader("Cookie",it) }
                getSystemService(DownloadManager::class.java).enqueue(request)
                Toast.makeText(this,"Download started",Toast.LENGTH_SHORT).show()
            }.onFailure { browser.error="The download couldn’t start. Please try again." }
            Unit
        }
        if(Build.VERSION.SDK_INT<29 && ContextCompat.checkSelfPermission(this,Manifest.permission.WRITE_EXTERNAL_STORAGE)!=PackageManager.PERMISSION_GRANTED) {
            pendingDownload=action;storagePermission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        } else action()
    }
    override fun onResume() {
        super.onResume()
        if(::browser.isInitialized) { browser.notificationsAllowed=ProverbReminders.allowed(this);ProverbReminders.schedule(this);browser.tabs.forEach { it.web?.onResume() } }
    }
    override fun onPause() { if(::browser.isInitialized) { CookieManager.getInstance().flush();browser.tabs.forEach { it.web?.onPause() };browser.persistTabs() };super.onPause() }
    override fun onDestroy() { if(::browser.isInitialized)browser.destroy();upload?.onReceiveValue(null);appScope.cancel();super.onDestroy() }
}
