package com.savedd.browser

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import org.jsoup.Jsoup
import java.io.File
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

class AppStore(context: Context) {
    private val disk = context.applicationContext.getSharedPreferences("savedd.native.v1",Context.MODE_PRIVATE)
    private inline fun <reified T> read(key:String, fallback:T):T = runCatching { AppJson.decodeFromString<T>(disk.getString(key,null) ?: return fallback) }.getOrDefault(fallback)
    var preferences: Preferences
        get() = read("preferences",Preferences())
        set(value) { disk.edit().putString("preferences",AppJson.encodeToString(value)).apply() }
    var bookmarks: List<Bookmark>
        get() = read("bookmarks", emptyList())
        set(value) { disk.edit().putString("bookmarks",AppJson.encodeToString(value)).apply() }
    var recent: List<RecentEntry>
        get() = read("recent", emptyList())
        set(value) { disk.edit().putString("recent",AppJson.encodeToString(value.take(100))).apply() }
    var tabs: List<SavedTab>
        get() = read("tabs", listOf(SavedTab()))
        set(value) { disk.edit().putString("tabs",AppJson.encodeToString(value)).apply() }
    var lastProverbDay: String
        get() = disk.getString("lastProverbDay","") ?: ""
        set(value) { disk.edit().putString("lastProverbDay",value).apply() }
}

object PreferenceBridge {
    fun script(p: Preferences):String {
        val payload = buildJsonObject {
            put("theme",if(p.dark) "dark" else "light")
            put("privacyMode",p.privacy)
            putJsonArray("languageFilter") { if(p.language.isNotBlank()) add(p.language) }
        }.toString()
        return """
            (() => {
              if (window !== window.top || !['https://savedd.com','https://www.savedd.com'].includes(location.origin)) return;
              try {
                const settings = $payload;
                const revision = JSON.stringify(settings);
                if (localStorage.getItem('savedd:android-applied-preferences') === revision) return;
                const current = JSON.parse(localStorage.getItem('savedd:app-config') || '{}');
                localStorage.setItem('savedd:app-config', JSON.stringify({...current,...settings}));
                localStorage.setItem('savedd:android-applied-preferences', revision);
              } catch (_) { }
            })();
        """.trimIndent()
    }
}

object PartnerApi {
    const val ENDPOINT = "https://iofxuntxecxcqihuugcr.supabase.co/functions/v1/referrals"
    private const val KEY = "sb_publishable_oqVo1X1z9GlHeozNVs_RsQ_kD3ZLW98"
    private val client = OkHttpClient.Builder().callTimeout(15,TimeUnit.SECONDS).build()
    suspend fun fetch(): PartnerResponse = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(ENDPOINT).header("apikey",KEY)
            .post("""{"action":"public"}""".toRequestBody("application/json".toMediaType())).build()
        client.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "The partner directory is unavailable. Please try again." }
            val raw = response.body?.string() ?: error("Empty partner response")
            check(raw.length <= 2_000_000)
            AppJson.decodeFromString<PartnerResponse>(raw)
        }
    }
}

class IconCache(context:Context) {
    private val directory = File(context.cacheDir,"favicons").also { it.mkdirs() }
    private val images = LruCache<String,Bitmap>(150)
    private val unavailable = ConcurrentHashMap<String,Long>()
    private val pending = mutableMapOf<String,Deferred<Bitmap?>>()
    private val mutex = Mutex()
    private val scope = CoroutineScope(SupervisorJob()+Dispatchers.IO)
    private val client = OkHttpClient.Builder().callTimeout(8,TimeUnit.SECONDS).build()
    private fun origin(url:String):String? = runCatching {
        val uri=URI(url)
        if(uri.scheme != "https" || uri.host==null || uri.userInfo!=null) null
        else URI(uri.scheme,null,uri.host,uri.port,"/",null,null).toString()
    }.getOrNull()
    private fun file(key:String) = File(directory,MessageDigest.getInstance("SHA-256").digest(key.toByteArray()).joinToString("") { "%02x".format(it) }+".png")
    fun save(url:String, bitmap:Bitmap) {
        val key=origin(url) ?: return
        val small=if(bitmap.width>128||bitmap.height>128) Bitmap.createScaledBitmap(bitmap,128,128,true) else bitmap
        images.put(key,small)
        scope.launch { runCatching { file(key).outputStream().use { small.compress(Bitmap.CompressFormat.PNG,100,it) } } }
    }
    suspend fun get(url:String):Bitmap? {
        val key=origin(url) ?: return null
        images.get(key)?.let { return it }
        if((unavailable[key]?:0)>System.currentTimeMillis())return null
        val task=mutex.withLock { pending.getOrPut(key) { scope.async { fetch(key) } } }
        val bitmap=task.await()
        mutex.withLock { if(pending[key]===task)pending.remove(key) }
        return bitmap
    }
    private fun bytes(url:String, limit:Int):ByteArray? = runCatching {
        if(!url.startsWith("https://")) return null
        client.newCall(Request.Builder().url(url).build()).execute().use { response ->
            if(!response.isSuccessful)return null
            response.body?.byteStream()?.use { stream ->
                val output=java.io.ByteArrayOutputStream()
                val buffer=ByteArray(8192)
                while(true) {
                    val count=stream.read(buffer)
                    if(count<0)break
                    if(output.size()+count>limit)return null
                    output.write(buffer,0,count)
                }
                output.toByteArray()
            }
        }
    }.getOrNull()
    private fun fetch(key:String):Bitmap? {
        val stored=file(key)
        if(stored.exists() && System.currentTimeMillis()-stored.lastModified()<7*86_400_000L) {
            BitmapFactory.decodeFile(stored.path)?.let { images.put(key,it); return it }
        }
        val candidates=mutableListOf<String>()
        bytes(key,500_000)?.let { html ->
            val document=Jsoup.parse(String(html),key)
            candidates += document.select("link[rel~=icon]").sortedBy { if(it.attr("rel").contains("apple")) 0 else 1 }.map { it.absUrl("href") }.take(4)
        }
        candidates += key+"favicon.ico"
        for(url in candidates.distinct()) {
            val data=bytes(url,1_000_000) ?: continue
            val bounds=BitmapFactory.Options().apply { inJustDecodeBounds=true }
            BitmapFactory.decodeByteArray(data,0,data.size,bounds)
            if(bounds.outWidth !in 1..16384 || bounds.outHeight !in 1..16384)continue
            var sample=1
            while(maxOf(bounds.outWidth,bounds.outHeight)/sample>128)sample*=2
            val options=BitmapFactory.Options().apply { inSampleSize=sample }
            val image=BitmapFactory.decodeByteArray(data,0,data.size,options) ?: continue
            save(key,image);return images.get(key)
        }
        unavailable[key]=System.currentTimeMillis()+600_000
        return null
    }
}
