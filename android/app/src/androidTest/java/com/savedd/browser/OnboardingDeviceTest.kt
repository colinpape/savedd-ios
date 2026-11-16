package com.savedd.browser

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.After
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern

@RunWith(AndroidJUnit4::class)
class OnboardingDeviceTest {
    private val device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private val context=InstrumentationRegistry.getInstrumentation().targetContext
    private fun text(value:String)=By.text(value)
    private fun click(selector:BySelector) {
        repeat(5) {
            try {
                val node=device.wait(Until.findObject(selector),15_000)
                if(node==null) { screenshot("98-missing-control");fail("Missing control: $selector") }
                val bounds=node!!.visibleBounds
                assertTrue("Control is outside the viewport: $selector",!bounds.isEmpty)
                device.click(bounds.centerX(),bounds.centerY())
                device.waitForIdle()
                return
            } catch (_:StaleObjectException) {
                // Compose can replace a semantics node between discovery and a tap.
                device.waitForIdle()
            }
        }
        fail("Control did not stabilize: $selector")
    }
    private fun screenshot(name:String) {
        val folder=File(context.getExternalFilesDir(null),"screenshots").also {it.mkdirs()}
        val image=File(folder,"$name.png")
        assertTrue(device.takeScreenshot(image))
        device.executeShellCommand("mkdir -p /sdcard/Download/savedd-device-screenshots")
        device.executeShellCommand("cp ${image.absolutePath} /sdcard/Download/savedd-device-screenshots/$name.png")
        val hierarchy=File(folder,"$name.xml")
        device.dumpWindowHierarchy(hierarchy)
        device.executeShellCommand("cp ${hierarchy.absolutePath} /sdcard/Download/savedd-device-screenshots/$name.xml")
    }
    @After fun captureFinalState() {
        runCatching {
            screenshot("99-final-state")
            val hierarchy=File(context.getExternalFilesDir(null),"hierarchy.xml")
            device.dumpWindowHierarchy(hierarchy)
            device.executeShellCommand("cp ${hierarchy.absolutePath} /sdcard/Download/savedd-device-screenshots/hierarchy.xml")
        }
    }
    private fun web(root:View):WebView? {
        if(root is WebView && root.visibility==View.VISIBLE)return root
        if(root is ViewGroup)for(i in 0 until root.childCount)web(root.getChildAt(i))?.let {return it}
        return null
    }
    private fun evaluate(scenario:ActivityScenario<MainActivity>,script:String):String {
        val latch=CountDownLatch(1);var result=""
        scenario.onActivity {activity -> web(activity.window.decorView)!!.evaluateJavascript(script) { result=it;latch.countDown() } }
        assertTrue("WebView script timed out",latch.await(15,TimeUnit.SECONDS));return result
    }
    private fun waitFor(scenario:ActivityScenario<MainActivity>,expression:String) {
        repeat(200) { if(evaluate(scenario,expression)=="true")return;Thread.sleep(100) }
        fail("WebView assertion timed out: $expression")
    }
    @Test fun firstRunAndBrowserNavigationStayConsistent() {
        context.getSharedPreferences("savedd.native.v1",0).edit().clear().commit()
        ActivityScenario.launch(MainActivity::class.java).use {scenario ->
            assertTrue(device.wait(Until.hasObject(text("Get started")),15_000))
            screenshot("01-welcome")
            click(text("Get started"));screenshot("02-referral")
            click(text("Skip for now"));screenshot("03-preferences")
            click(text("Continue"))
            assertTrue(device.wait(Until.hasObject(By.textContains("Proverbs 18:15")),10_000))
            screenshot("04-daily-proverb")
            click(text("Maybe later"));screenshot("05-account")
            click(text("Continue without an account"))
            assertTrue(device.wait(Until.hasObject(By.desc("Settings")),15_000))
            // Cancel the network homepage and exercise a real WebView History API form.
            val fixture="""<html><head><meta name="viewport" content="width=device-width"><title>Navigation fixture</title></head><body><form onsubmit="event.preventDefault();history.pushState({},'', '?q=coffee');document.getElementById('result').textContent='Results: coffee'"><input value="coffee"><button>Search</button></form><h1 id="result">Home</h1></body></html>"""
            scenario.onActivity { activity -> web(activity.window.decorView)!!.apply {
                stopLoading()
                val realClient=webViewClient
                webViewClient=object:WebViewClient() {
                    override fun shouldInterceptRequest(view:WebView,request:WebResourceRequest):WebResourceResponse? =
                        if(request.isForMainFrame && request.url.host=="navigation.example.test")
                            WebResourceResponse("text/html","UTF-8",fixture.byteInputStream())
                        else realClient.shouldInterceptRequest(view,request)
                    override fun onPageStarted(view:WebView,url:String?,icon:android.graphics.Bitmap?)=realClient.onPageStarted(view,url,icon)
                    override fun onPageFinished(view:WebView,url:String?)=realClient.onPageFinished(view,url)
                    override fun doUpdateVisitedHistory(view:WebView,url:String?,reload:Boolean)=realClient.doUpdateVisitedHistory(view,url,reload)
                    override fun onReceivedError(view:WebView,request:WebResourceRequest,error:WebResourceError)=realClient.onReceivedError(view,request,error)
                    override fun shouldOverrideUrlLoading(view:WebView,request:WebResourceRequest)=realClient.shouldOverrideUrlLoading(view,request)
                }
                loadUrl("https://navigation.example.test/")
            } }
            waitFor(scenario,"document.title === 'Navigation fixture'")
            if(device.hasObject(text("OK")))click(text("OK"))
            scenario.onActivity {activity -> web(activity.window.decorView)!!.clearHistory()}
            evaluate(scenario,"document.querySelector('button').click(); true")
            waitFor(scenario,"location.search === '?q=coffee' && document.getElementById('result').textContent === 'Results: coffee'")
            click(By.desc("Settings"));click(text("Light"));screenshot("06-settings-light")
            click(text("Read today’s proverb"));screenshot("07-reading")
            val read=By.text(Pattern.compile("Read Proverbs [0-9]+"))
            repeat(4) { if(!device.hasObject(read))device.findObject(By.scrollable(true))?.scroll(Direction.DOWN,.6f) }
            click(read);assertTrue(device.wait(Until.hasObject(text("Hide full chapter")),5_000))
            click(By.desc("Close Daily Proverb"));click(By.desc("Close Settings"))
            waitFor(scenario,"location.search === '?q=coffee' && document.getElementById('result').textContent === 'Results: coffee'")
            scenario.onActivity {activity -> assertEquals("A redraw added an unwanted navigation",2,web(activity.window.decorView)!!.copyBackForwardList().size) }
            scenario.onActivity { activity -> assertTrue("Fixture must have a bookmarkable HTTPS history URL",web(activity.window.decorView)!!.url.orEmpty().startsWith("https://navigation.example.test/")) }
            click(By.desc("Share page"));click(text("Add bookmark"));screenshot("08-bookmark-editor")
            assertTrue("Bookmark save must be enabled",device.findObject(text("Save bookmark")).isEnabled)
            click(text("Save bookmark"))
            click(By.desc("Bookmarks"));assertTrue(device.wait(Until.hasObject(text("Navigation fixture")),5_000));screenshot("08-bookmarks")
            click(By.desc("Close Bookmarks"))
            click(By.desc("Tabs"));screenshot("09-tabs");click(By.desc("New tab"))
            if(device.hasObject(text("OK")))click(text("OK"))
            click(text("www.savedd.com"))
            assertTrue(device.wait(Until.hasObject(By.desc("Search or enter address")),5_000))
            val address=device.wait(Until.findObject(By.clazz("android.widget.EditText").focused(true)),10_000)
            assertNotNull("The actual address editor must receive focus",address)
            assertEquals("New-tab address field must start blank","",address!!.text.orEmpty())
            address.text="coffee"
            assertEquals("Typed text must remain visible","coffee",device.findObject(By.clazz("android.widget.EditText").focused(true)).text)
            screenshot("10-keyboard-address")
            device.pressBack()
        }
    }
    @Test fun notificationOpensTheMatchingOfflineReading() {
        context.getSharedPreferences("savedd.native.v1",0).edit().clear().commit()
        context.getSystemService(NotificationManager::class.java).cancelAll()
        AppStore(context).preferences=Preferences(reminders=true)
        ActivityScenario.launch(MainActivity::class.java).use {
            assertTrue(device.wait(Until.hasObject(text("Get started")),15_000))
            if(Build.VERSION.SDK_INT>=33)InstrumentationRegistry.getInstrumentation().uiAutomation.grantRuntimePermission(context.packageName,Manifest.permission.POST_NOTIFICATIONS)
            ProverbReminders.schedule(context)
            ProverbReminders.deliver(context)
            val notifications=context.getSystemService(NotificationManager::class.java).activeNotifications
            assertEquals(1,notifications.size)
            assertEquals("Savedd Daily Proverb",notifications[0].notification.extras.getString(Notification.EXTRA_TITLE))
            val day=java.time.LocalDate.now().dayOfMonth
            assertTrue(notifications[0].notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString().contains("Proverbs $day:"))
            notifications[0].notification.contentIntent.send()
            assertTrue(device.wait(Until.hasObject(By.desc("Close Daily Proverb")),10_000))
            assertTrue(device.hasObject(text("PROVERBS $day")))
            screenshot("11-notification-reading")
        }
    }
}
