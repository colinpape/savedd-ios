package com.savedd.browser

import android.graphics.Bitmap
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class HorizontalScrollDeviceTest {
    private val context=InstrumentationRegistry.getInstrumentation().targetContext
    private val device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private fun web(root:View):WebView? {
        if(root is WebView && root.visibility==View.VISIBLE)return root
        if(root is ViewGroup)for(i in 0 until root.childCount)web(root.getChildAt(i))?.let {return it}
        return null
    }
    private fun evaluate(scenario:ActivityScenario<MainActivity>,script:String):String {
        val latch=CountDownLatch(1);var result=""
        scenario.onActivity {activity -> web(activity.window.decorView)!!.evaluateJavascript(script) {result=it;latch.countDown()} }
        assertTrue("WebView script timed out",latch.await(10,TimeUnit.SECONDS));return result
    }
    private fun screenshot(name:String) {
        val file=File(context.getExternalFilesDir(null),"$name.png")
        assertTrue(device.takeScreenshot(file))
        device.executeShellCommand("mkdir -p /sdcard/Download/savedd-device-screenshots")
        device.executeShellCommand("cp ${file.absolutePath} /sdcard/Download/savedd-device-screenshots/$name.png")
    }
    private fun fixture(nested:Boolean):String = """<!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        *{box-sizing:border-box}html,body{margin:0;font:18px sans-serif;background:#0d223d;color:white}
        body{min-height:1800px}h1{font-size:20px;margin:0;padding:20px}
        #forecast{${if(nested)"width:100%;overflow-x:auto;" else "width:1200px;"}height:240px;}
        #days{display:flex;width:1200px;height:240px}
        .day{flex:0 0 200px;border-right:1px solid #345;padding:22px;background:#102c4d}
        #below{height:1400px;padding:30px}
        </style></head><body><h1>Forecast swipe fixture</h1><div id="forecast"><div id="days">
        ${(1..6).joinToString("") {"<div class='day'>Day $it<br><br>☁<br><br>6° | 11°<br>19 mm</div>"}}
        </div></div><div id="below">Vertical page scrolling must still work.</div></body></html>""".trimIndent()

    private fun runCase(scenario:ActivityScenario<MainActivity>,nested:Boolean,wide:Boolean,overview:Boolean):Boolean {
        val html=fixture(nested)
        scenario.onActivity {activity -> web(activity.window.decorView)!!.apply {
            stopLoading()
            settings.useWideViewPort=wide;settings.loadWithOverviewMode=overview
            val original=webViewClient
            webViewClient=object:WebViewClient() {
                override fun shouldInterceptRequest(view:WebView,request:WebResourceRequest):WebResourceResponse? =
                    if(request.isForMainFrame&&request.url.host=="scroll.example.test")WebResourceResponse("text/html","UTF-8",html.byteInputStream())
                    else original.shouldInterceptRequest(view,request)
                override fun onPageStarted(view:WebView,url:String?,icon:Bitmap?)=original.onPageStarted(view,url,icon)
                override fun onPageFinished(view:WebView,url:String?)=original.onPageFinished(view,url)
                override fun doUpdateVisitedHistory(view:WebView,url:String?,reload:Boolean)=original.doUpdateVisitedHistory(view,url,reload)
                override fun onReceivedError(view:WebView,request:WebResourceRequest,error:WebResourceError)=original.onReceivedError(view,request,error)
            }
            loadUrl("https://scroll.example.test/${if(nested)"nested" else "page"}/$wide/$overview")
        } }
        var loaded=false
        repeat(100) {
            if(!loaded) {
                loaded=evaluate(scenario,"document.getElementById('days') !== null")=="true"
                if(!loaded)Thread.sleep(100)
            }
        }
        assertTrue("The forecast fixture must load",loaded)
        Thread.sleep(300)
        fun metrics():JSONObject=JSONObject(evaluate(scenario,"""({width:innerWidth,documentWidth:document.documentElement.scrollWidth,pageX:scrollX,pageY:scrollY,stripX:document.getElementById('forecast').scrollLeft,stripWidth:document.getElementById('forecast').clientWidth,stripContentWidth:document.getElementById('forecast').scrollWidth})"""))
        val before=metrics()
        var left=0;var top=0;var width=0;var height=0
        scenario.onActivity {activity -> web(activity.window.decorView)!!.let {view ->
            val location=IntArray(2);view.getLocationOnScreen(location)
            left=location[0];top=location[1];width=view.width;height=view.height
        } }
        // Stay clear of Android's system back-gesture edge and swipe inside the forecast.
        val y=top+(140.0*width/before.getDouble("width")).toInt().coerceAtMost(height/2)
        assertTrue(device.swipe(left+width*4/5,y,left+width/5,y,35))
        Thread.sleep(500)
        val after=metrics()
        val moved=if(nested)after.getDouble("stripX")>before.getDouble("stripX")+20 else after.getDouble("pageX")>before.getDouble("pageX")+20
        println("HORIZONTAL_SCROLL nested=$nested wide=$wide overview=$overview moved=$moved before=$before after=$after")
        screenshot("scroll-${if(nested)"nested" else "page"}-$wide-$overview")
        return moved
    }

    @Test fun compareViewportSettingsWithRealSwipes() {
        context.getSharedPreferences("savedd.native.v1",0).edit().clear().commit()
        AppStore(context).preferences=Preferences(complete=true)
        ActivityScenario.launch(MainActivity::class.java).use {scenario ->
            val candidateResults=mutableListOf<Boolean>()
            for(nested in listOf(false,true)) {
                runCase(scenario,nested,wide=false,overview=false)
                candidateResults+=runCase(scenario,nested,wide=true,overview=false)
                runCase(scenario,nested,wide=true,overview=true)
            }
            assertTrue("Wide viewport must allow both full-page and nested horizontal panning",candidateResults.all {it})
        }
    }
}
