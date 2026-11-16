package com.savedd.browser

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Message
import android.view.View
import android.webkit.*
import androidx.compose.runtime.*
import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import kotlinx.coroutines.*
import java.util.UUID

class BrowserTab(val id:String=UUID.randomUUID().toString(),initial:String=Routing.HOME,initialTitle:String="New Tab") {
    var url by mutableStateOf(initial)
    var title by mutableStateOf(initialTitle)
    var loading by mutableStateOf(false)
    var back by mutableStateOf(false)
    var forward by mutableStateOf(false)
    var thumbnail by mutableStateOf<Bitmap?>(null)
    var web:WebView?=null
    var script:ScriptHandler?=null
}

class BrowserController(val activity:Activity,val scope:CoroutineScope) {
    val store=AppStore(activity)
    var prefs by mutableStateOf(store.preferences)
        private set
    val tabs=mutableStateListOf<BrowserTab>()
    var active by mutableIntStateOf(0)
    val current get()=tabs[active.coerceIn(0,tabs.lastIndex)]
    var bookmarks by mutableStateOf(store.bookmarks)
    var recent by mutableStateOf(store.recent)
    var partners by mutableStateOf<List<Partner>>(emptyList())
    var directoryLoading by mutableStateOf(false)
    var directoryError by mutableStateOf<String?>(null)
    var programEnabled by mutableStateOf(true)
    private var directoryLoaded=false
    val icons=IconCache(activity.applicationContext)
    var error by mutableStateOf<String?>(null)
    var fullScreen by mutableStateOf<View?>(null)
    var fullScreenCallback:WebChromeClient.CustomViewCallback?=null
    var filePicker:((WebChromeClient.FileChooserParams,ValueCallback<Array<Uri>>)->Unit)?=null
    var download:((String,String?,String?,String?)->Unit)?=null
    var voice:((String)->Unit)?=null
    var voiceText by mutableStateOf<String?>(null)
    var readingDay by mutableStateOf<Int?>(null)
    var notificationsAllowed by mutableStateOf(ProverbReminders.allowed(activity))

    init {
        tabs.addAll(store.tabs.ifEmpty { listOf(SavedTab()) }.map { BrowserTab(it.id,it.url,it.title) })
        if(!prefs.complete)prefetchPartners()
    }
    fun update(value:Preferences) {
        val bridgeChanged=prefs.dark!=value.dark||prefs.language!=value.language||prefs.privacy!=value.privacy
        prefs=value;store.preferences=value
        if(bridgeChanged)tabs.forEach { tab -> tab.web?.let { web ->
            installBridge(tab,web)
            if(Routing.trusted(tab.url)) { web.evaluateJavascript(PreferenceBridge.script(prefs),null);web.reload() }
        } }
    }
    fun finishOnboarding(account:Boolean) {
        update(prefs.copy(complete=true))
        val target=Routing.withReferral(if(account)Routing.LOGIN else Routing.HOME,prefs)
        navigate(target)
    }
    fun prefetchPartners(force:Boolean=false) {
        if(directoryLoading || (directoryLoaded&&!force))return
        directoryLoading=true;directoryError=null
        scope.launch {
            try { val response=PartnerApi.fetch();partners=DirectoryValidation.approved(response);programEnabled=response.config.enabled;directoryLoaded=true }
            catch (e:CancellationException) { throw e }
            catch (_:Exception) { directoryError="We couldn’t load the partner directory. Try again, enter a code, or skip for now." }
            finally { directoryLoading=false }
        }
    }
    fun addTab(url:String=Routing.HOME):BrowserTab {
        val tab=BrowserTab(initial=url);tabs.add(tab);active=tabs.lastIndex;persistTabs();return tab
    }
    fun closeTab(tab:BrowserTab) {
        val selected=current.id
        tab.web?.stopLoading();removeBridge(tab);tab.web?.destroy();tab.web=null
        tabs.remove(tab)
        if(tabs.isEmpty())tabs.add(BrowserTab())
        active=tabs.indexOfFirst { it.id==selected }.takeIf { it>=0 } ?: (active.coerceAtMost(tabs.lastIndex))
        persistTabs()
    }
    fun navigate(url:String) {
        current.url=url
        current.web?.loadUrl(url)
        persistTabs()
    }
    fun submit(input:String) {
        val (url,search)=Routing.destination(input) ?: return
        if(!prefs.privacy) {
            recent=(listOf(RecentEntry(input.trim(),url,search))+recent.filterNot { it.text.equals(input.trim(),true) }).take(100)
            store.recent=recent
        }
        navigate(url)
    }
    fun removeRecent(item:RecentEntry) { recent=recent.filterNot { it==item };store.recent=recent }
    fun clearRecent() { recent=emptyList();store.recent=recent }
    fun saveBookmark(bookmark:Bookmark) {
        bookmarks=listOf(bookmark)+bookmarks.filterNot { it.id==bookmark.id };store.bookmarks=bookmarks
    }
    fun removeBookmark(item:Bookmark) { bookmarks=bookmarks.filterNot { it.id==item.id };store.bookmarks=bookmarks }
    fun persistTabs() { store.tabs=tabs.map { SavedTab(it.id,it.url,it.title) } }
    fun closeVideo() { fullScreen=null;fullScreenCallback?.onCustomViewHidden();fullScreenCallback=null }
    fun captureTabs() {
        tabs.forEach { tab -> tab.web?.let { web ->
            if(web.width>0&&web.height>0) runCatching {
                val width=300;val height=(web.height.toFloat()/web.width*width).toInt().coerceIn(1,600)
                val image=Bitmap.createBitmap(width,height,Bitmap.Config.RGB_565)
                val canvas=android.graphics.Canvas(image);canvas.scale(width.toFloat()/web.width,height.toFloat()/web.height)
                web.draw(canvas);tab.thumbnail=image
            }
        } }
    }
    private fun changed(tab:BrowserTab,web:WebView) {
        tab.url=web.url ?: tab.url;tab.title=web.title?.takeIf { it.isNotBlank() } ?: Uri.parse(tab.url).host.orEmpty()
        tab.back=web.canGoBack();tab.forward=web.canGoForward();persistTabs()
    }
    private fun removeBridge(tab:BrowserTab) {
        if(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT))tab.script?.remove()
        tab.script=null
    }
    private fun installBridge(tab:BrowserTab,web:WebView) {
        removeBridge(tab)
        if(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            tab.script=WebViewCompat.addDocumentStartJavaScript(web,PreferenceBridge.script(prefs),setOf("https://savedd.com","https://www.savedd.com"))
        }
    }
    @SuppressLint("SetJavaScriptEnabled")
    fun createWebView(tab:BrowserTab,initialLoad:Boolean=true):WebView {
        tab.web?.let { return it }
        val web=WebView(activity)
        tab.web=web
        web.setBackgroundColor(if(prefs.dark)android.graphics.Color.rgb(18,16,26) else android.graphics.Color.WHITE)
        web.settings.apply {
            javaScriptEnabled=true;domStorageEnabled=true
            allowFileAccess=false;allowContentAccess=true
            mixedContentMode=WebSettings.MIXED_CONTENT_NEVER_ALLOW
            setSupportMultipleWindows(true);javaScriptCanOpenWindowsAutomatically=false
            userAgentString += " SaveddApp/Android"
            builtInZoomControls=true;displayZoomControls=false;mediaPlaybackRequiresUserGesture=true
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(web,false)
        installBridge(tab,web)
        web.webViewClient=object:WebViewClient() {
            override fun onPageStarted(view:WebView,url:String?,favicon:Bitmap?) { tab.loading=true;changed(tab,view)
                if(!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)&&url!=null&&Routing.trusted(url))view.evaluateJavascript(PreferenceBridge.script(prefs),null)
            }
            override fun doUpdateVisitedHistory(view:WebView,url:String?,isReload:Boolean) { changed(tab,view) }
            override fun onPageFinished(view:WebView,url:String?) { tab.loading=false;changed(tab,view);CookieManager.getInstance().flush() }
            override fun onReceivedError(view:WebView,request:WebResourceRequest,failure:WebResourceError) {
                if(request.isForMainFrame && request.url.toString()==view.url && !failure.description.contains("ERR_ABORTED")) { tab.loading=false;error="This page couldn’t load. Check your connection or try another address." }
            }
            override fun shouldOverrideUrlLoading(view:WebView,request:WebResourceRequest):Boolean {
                val raw=request.url.toString()
                if(request.isForMainFrame && request.hasGesture())Routing.callback(raw)?.let { view.loadUrl(it);return true }
                if(request.url.scheme=="https")return false
                if(request.url.scheme=="http" && request.isForMainFrame) {
                    if(request.hasGesture())view.loadUrl(raw.replaceFirst(Regex("^http:",RegexOption.IGNORE_CASE),"https:"))
                    else error="Savedd requires a secure HTTPS connection. This page tried to use unencrypted HTTP."
                    return true
                }
                if(request.hasGesture() && request.url.scheme in listOf("mailto","tel","geo","market","nostr","nostrconnect")) {
                    runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW,request.url)) }.onFailure { error="No app is available to open this link." }
                }
                return true
            }
        }
        web.webChromeClient=object:WebChromeClient() {
            override fun onReceivedTitle(view:WebView,title:String?) { changed(tab,view) }
            override fun onReceivedIcon(view:WebView,icon:Bitmap?) { if(icon!=null)icons.save(tab.url,icon) }
            override fun onShowFileChooser(view:WebView,callback:ValueCallback<Array<Uri>>,params:FileChooserParams):Boolean {
                filePicker?.invoke(params,callback) ?: callback.onReceiveValue(null)
                return true
            }
            override fun onShowCustomView(view:View,callback:CustomViewCallback) { fullScreen=view;fullScreenCallback=callback }
            override fun onHideCustomView() { closeVideo() }
            override fun onCreateWindow(view:WebView,isDialog:Boolean,isUserGesture:Boolean,resultMsg:Message):Boolean {
                if(!isUserGesture)return false
                val target=addTab();val child=createWebView(target,initialLoad=false)
                (resultMsg.obj as WebView.WebViewTransport).webView=child
                resultMsg.sendToTarget();return true
            }
            override fun onPermissionRequest(request:PermissionRequest) { request.deny() }
        }
        web.setDownloadListener { url,agent,disposition,mime,_ -> download?.invoke(url,agent,disposition,mime) }
        if(initialLoad)web.loadUrl(tab.url)
        return web
    }
    fun destroy() { tabs.forEach { removeBridge(it);it.web?.destroy();it.web=null };closeVideo() }
}
