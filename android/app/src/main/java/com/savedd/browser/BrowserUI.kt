@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class, androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.savedd.browser

import android.content.Intent
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.shape.*
import androidx.compose.foundation.text.*
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.*
import androidx.compose.ui.focus.*
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.*
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.font.*
import androidx.compose.ui.text.style.*
import androidx.compose.ui.unit.*
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.*

@Composable fun SaveddApp(controller:BrowserController,enableReminders:()->Unit,openNotifications:()->Unit) {
    SideEffect {
        val dark=!controller.prefs.complete||controller.prefs.dark
        androidx.core.view.WindowCompat.getInsetsController(controller.activity.window,controller.activity.window.decorView).apply {
            isAppearanceLightStatusBars=!dark
            isAppearanceLightNavigationBars=!dark
        }
    }
    Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background) {
        if(controller.prefs.complete)BrowserScreen(controller,enableReminders,openNotifications)
        else Onboarding(controller,enableReminders,openNotifications)
    }
    controller.readingDay?.let { day -> SaveddTheme(dark=true) { Reader(controller,day) { controller.readingDay=null } } }
    controller.error?.let { message -> AlertDialog(onDismissRequest={controller.error=null},title={Text("Savedd")},text={Text(message)},confirmButton={TextButton({controller.error=null}) {Text("OK")}}) }
}

@Composable fun FullPage(title:String,onClose:()->Unit,showClose:Boolean=true,content:@Composable ColumnScope.()->Unit) {
    Dialog(onDismissRequest=onClose,properties=DialogProperties(usePlatformDefaultWidth=false,decorFitsSystemWindows=false)) {
        val view=LocalView.current
        val light=MaterialTheme.colorScheme.background.luminance()>.5f
        SideEffect {
            (view.parent as? DialogWindowProvider)?.window?.let { window ->
                androidx.core.view.WindowCompat.getInsetsController(window,view).apply {
                    isAppearanceLightStatusBars=light;isAppearanceLightNavigationBars=light
                }
            }
        }
        Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background) {
            Column(Modifier.safeDrawingPadding().imePadding()) {
                Row(Modifier.fillMaxWidth().padding(start=24.dp,end=8.dp).heightIn(min=64.dp),verticalAlignment=Alignment.CenterVertically) {
                    Text(title,Modifier.weight(1f),style=MaterialTheme.typography.titleLarge)
                    if(showClose)IconButton(onClose) {Icon(Icons.Default.Close,"Close $title")}
                }
                Column(Modifier.weight(1f).fillMaxWidth(),content=content)
            }
        }
    }
}

@Composable fun BrowserScreen(controller:BrowserController,enableReminders:()->Unit,openNotifications:()->Unit) {
    var editing by rememberSaveable { mutableStateOf(false) }
    var input by remember { mutableStateOf(TextFieldValue()) }
    var tabsOpen by remember { mutableStateOf(false) }
    var bookmarksOpen by remember { mutableStateOf(false) }
    var settingsOpen by remember { mutableStateOf(false) }
    var shareOpen by remember { mutableStateOf(false) }
    var bookmarkDraft by remember { mutableStateOf<Bookmark?>(null) }
    var clearRecent by remember { mutableStateOf(false) }
    var historyDirection by remember { mutableIntStateOf(0) }
    val focus=remember { FocusRequester() };val manager=LocalFocusManager.current;val keyboard=LocalSoftwareKeyboardController.current
    fun stopEditing() {editing=false;manager.clearFocus();keyboard?.hide()}
    fun submit() {controller.submit(input.text);stopEditing()}
    fun beginEditing() {
        val text=if(Routing.home(controller.current.url))"" else controller.current.url
        input=TextFieldValue(text,TextRange(0,text.length));editing=true
    }
    LaunchedEffect(editing) { if(editing) { focus.requestFocus();keyboard?.show() } }
    LaunchedEffect(controller.voiceText) {
        controller.voiceText?.let {
            val wasEditing=editing
            input=TextFieldValue(it,TextRange(it.length));editing=true;controller.voiceText=null
            if(wasEditing) { focus.requestFocus();keyboard?.show() }
        }
    }
    BackHandler(enabled=editing||controller.current.back) { if(editing)stopEditing() else controller.current.web?.goBack() }
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).safeDrawingPadding().imePadding()) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            controller.tabs.forEachIndexed { index,tab -> key(tab.id) {
                AndroidView(factory={controller.createWebView(tab)},modifier=Modifier.fillMaxSize().zIndex(if(index==controller.active)1f else 0f),update={view ->
                    // Display state never issues navigation commands: History API URLs stay intact.
                    view.visibility=if(index==controller.active)View.VISIBLE else View.INVISIBLE
                })
            } }
            if(controller.current.loading)LinearProgressIndicator(Modifier.fillMaxWidth().align(Alignment.TopCenter))
        }
        Column(Modifier.fillMaxWidth().padding(horizontal=12.dp,vertical=8.dp)) {
            if(editing)Column(Modifier.fillMaxWidth().heightIn(max=200.dp).background(MaterialTheme.colorScheme.surface,RoundedCornerShape(12.dp))) {
                Row(Modifier.fillMaxWidth().padding(start=12.dp),verticalAlignment=Alignment.CenterVertically) {
                    Text("Recent searches & addresses",Modifier.weight(1f),style=MaterialTheme.typography.labelMedium)
                    TextButton({clearRecent=true},enabled=controller.recent.isNotEmpty()) {Text("Clear all")}
                }
                if(controller.prefs.privacy)Text("History is paused in Privacy Mode.",Modifier.padding(16.dp),color=MaterialTheme.colorScheme.onSurfaceVariant)
                else {
                    val query=if(input.text==controller.current.url)"" else input.text
                    val matches=controller.recent.filter { it.text.contains(query,true) }
                    if(matches.isEmpty())Text(if(controller.recent.isEmpty())"Your searches and addresses will appear here." else "No matching history",Modifier.padding(16.dp),color=MaterialTheme.colorScheme.onSurfaceVariant)
                    else LazyColumn {items(matches,key={it.text.lowercase()}) { item ->
                        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
                            Row(Modifier.weight(1f).clickable {input=TextFieldValue(item.text);controller.navigate(item.url);stopEditing()}.padding(12.dp),horizontalArrangement=Arrangement.spacedBy(10.dp)) {
                                Icon(if(item.search)Icons.Default.Search else Icons.Default.Public,null,tint=MaterialTheme.colorScheme.primary)
                                Text(item.text,maxLines=1,overflow=TextOverflow.Ellipsis)
                            }
                            IconButton({controller.removeRecent(item)}) {Icon(Icons.Default.Close,"Delete history: ${item.text}")}
                        }
                    } }
                }
            }
            Surface(Modifier.fillMaxWidth().padding(top=6.dp),shape=RoundedCornerShape(14.dp),color=MaterialTheme.colorScheme.surface) {
                Row(Modifier.fillMaxWidth().heightIn(min=56.dp),verticalAlignment=Alignment.CenterVertically) {
                    IconButton({settingsOpen=true}) {Icon(Icons.Default.Menu,"Settings")}
                    if(editing)BasicTextField(input,{input=it},modifier=Modifier.weight(1f).focusRequester(focus).semantics {contentDescription="Search or enter address"},singleLine=true,
                        textStyle=MaterialTheme.typography.bodyLarge.copy(color=MaterialTheme.colorScheme.onSurface),
                        keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Uri,imeAction=ImeAction.Go,autoCorrectEnabled=false),keyboardActions=KeyboardActions(onGo={submit()}),
                        decorationBox={field -> Box { if(input.text.isEmpty())Text("Search or enter address",color=MaterialTheme.colorScheme.onSurfaceVariant);field() }})
                    else Text(runCatching {java.net.URI(controller.current.url).host}.getOrNull() ?: controller.current.url,Modifier.weight(1f).clickable {beginEditing()}.padding(vertical=14.dp),maxLines=1,overflow=TextOverflow.Ellipsis,textAlign=TextAlign.Center)
                    IconButton({manager.clearFocus();keyboard?.hide();controller.voice?.invoke(controller.prefs.language)}) {Icon(Icons.Default.Mic,"Voice search",tint=MaterialTheme.colorScheme.primary)}
                    IconButton({if(editing)input=TextFieldValue() else controller.navigate(Routing.HOME)}) {Icon(Icons.Default.Close,if(editing)"Clear address" else "Home",tint=MaterialTheme.colorScheme.onSurfaceVariant)}
                }
            }
            if(editing)Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {
                TextButton({stopEditing()}) {Text("Cancel")};TextButton({submit()},enabled=input.text.isNotBlank()) {Text("Go")}
            } else Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceEvenly) {
                Icon(Icons.Default.ChevronLeft,"Back",tint=MaterialTheme.colorScheme.onSurface.copy(alpha=if(controller.current.back)1f else .35f),modifier=Modifier.size(48.dp).combinedClickable(enabled=controller.current.back,role=Role.Button,onClick={controller.current.web?.goBack()},onLongClick={historyDirection=-1}).padding(12.dp))
                Icon(Icons.Default.ChevronRight,"Forward",tint=MaterialTheme.colorScheme.onSurface.copy(alpha=if(controller.current.forward)1f else .35f),modifier=Modifier.size(48.dp).combinedClickable(enabled=controller.current.forward,role=Role.Button,onClick={controller.current.web?.goForward()},onLongClick={historyDirection=1}).padding(12.dp))
                IconButton({shareOpen=true}) {Icon(Icons.Default.Share,"Share page")}
                IconButton({bookmarksOpen=true}) {Icon(Icons.Default.Bookmarks,"Bookmarks")}
                IconButton({controller.captureTabs();tabsOpen=true}) {BadgedBox(badge={Badge {Text(controller.tabs.size.toString())}}) {Icon(Icons.Default.Tab,"Tabs")}}
            }
        }
    }
    if(tabsOpen)TabManager(controller) {tabsOpen=false}
    if(bookmarksOpen)BookmarkList(controller,onOpen={controller.navigate(it.url);bookmarksOpen=false},onEdit={bookmarkDraft=it}) {bookmarksOpen=false}
    if(settingsOpen)SettingsPage(controller,enableReminders,openNotifications) {settingsOpen=false}
    if(shareOpen)ModalBottomSheet(onDismissRequest={shareOpen=false}) {
        Text("Share page",Modifier.padding(horizontal=24.dp),style=MaterialTheme.typography.titleLarge)
        ListItem(headlineContent={Text("Add bookmark")},leadingContent={Icon(Icons.Default.BookmarkAdd,null)},modifier=Modifier.clickable {shareOpen=false;bookmarkDraft=Bookmark(title=controller.current.title.ifBlank {controller.current.url},url=controller.current.url)})
        ListItem(headlineContent={Text("Share link…")},leadingContent={Icon(Icons.Default.Share,null)},modifier=Modifier.clickable {
            shareOpen=false
            controller.activity.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT,controller.current.url).putExtra(Intent.EXTRA_TITLE,controller.current.title),"Share page"))
        })
        Spacer(Modifier.height(24.dp))
    }
    bookmarkDraft?.let { draft -> BookmarkEditor(draft,onSave={controller.saveBookmark(it);bookmarkDraft=null},onClose={bookmarkDraft=null}) }
    if(clearRecent)AlertDialog(onDismissRequest={clearRecent=false},title={Text("Clear recent searches and addresses?")},text={Text("Bookmarks and website logins are kept.")},confirmButton={TextButton({controller.clearRecent();clearRecent=false}) {Text("Clear history")}},dismissButton={TextButton({clearRecent=false}) {Text("Cancel")}})
    if(historyDirection!=0) {
        val web=controller.current.web
        val list=web?.copyBackForwardList()
        val offsets=if(historyDirection<0)(-1 downTo -(list?.currentIndex ?: 0)).toList() else (1 until ((list?.size?:0)-(list?.currentIndex?:0))).toList()
        FullPage(if(historyDirection<0)"Back history" else "Forward history",{historyDirection=0}) {
            LazyColumn {items(offsets) {offset ->
                val item=list?.getItemAtIndex(list.currentIndex+offset)
                if(item!=null)ListItem(headlineContent={Text(item.title ?: item.url)},supportingContent={Text(item.url,maxLines=1,overflow=TextOverflow.Ellipsis)},modifier=Modifier.clickable {
                    val current=web.copyBackForwardList();val target=current.currentIndex+offset
                    if(target in 0 until current.size && current.getItemAtIndex(target)?.url==item.url)web.goBackOrForward(offset)
                    historyDirection=0
                })
            } }
        }
    }
    controller.fullScreen?.let { video -> Dialog(onDismissRequest={controller.closeVideo()},properties=DialogProperties(usePlatformDefaultWidth=false,decorFitsSystemWindows=false)) {
        Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black).safeDrawingPadding()) {
            AndroidView(factory={video},Modifier.fillMaxSize())
            IconButton({controller.closeVideo()},Modifier.align(Alignment.TopEnd).background(androidx.compose.ui.graphics.Color.Black.copy(alpha=.5f),CircleShape)) {Icon(Icons.Default.Close,"Close video",tint=androidx.compose.ui.graphics.Color.White)}
        }
    } }
}

@Composable fun TabManager(controller:BrowserController,onClose:()->Unit) {
    FullPage("${controller.tabs.size} ${if(controller.tabs.size==1)"Tab" else "Tabs"}",onClose,showClose=false) {
        LazyVerticalGrid(GridCells.Adaptive(150.dp),Modifier.weight(1f).padding(horizontal=20.dp),horizontalArrangement=Arrangement.spacedBy(16.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
            items(controller.tabs,key={it.id}) {tab ->
                Card(border=BorderStroke(if(tab.id==controller.current.id)3.dp else 1.dp,if(tab.id==controller.current.id)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant)) {
                    Row(Modifier.fillMaxWidth().padding(start=12.dp),verticalAlignment=Alignment.CenterVertically) {
                        Text(tab.title,Modifier.weight(1f),maxLines=1,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.labelLarge)
                        IconButton({controller.closeTab(tab)}) {Icon(Icons.Default.Close,"Close tab: ${tab.title}")}
                    }
                    Column(Modifier.clickable {controller.active=controller.tabs.indexOf(tab);onClose()}) {
                        Box(Modifier.fillMaxWidth().aspectRatio(.65f).background(MaterialTheme.colorScheme.background),contentAlignment=Alignment.Center) {
                            if(tab.thumbnail!=null)Image(tab.thumbnail!!.asImageBitmap(),null,Modifier.fillMaxSize(),contentScale=androidx.compose.ui.layout.ContentScale.Crop,alignment=Alignment.TopCenter)
                            else Column(horizontalAlignment=Alignment.CenterHorizontally) {SaveddMark(Modifier.size(60.dp));Text(runCatching {java.net.URI(tab.url).host}.getOrNull().orEmpty(),maxLines=1,style=MaterialTheme.typography.labelSmall)}
                        }
                        Text(runCatching {java.net.URI(tab.url).host}.getOrNull().orEmpty(),Modifier.fillMaxWidth().padding(10.dp),maxLines=1,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.labelSmall)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=8.dp),horizontalArrangement=Arrangement.SpaceBetween) {
            IconButton({controller.addTab();onClose()}) {Icon(Icons.Default.Add,"New tab")}
            IconButton(onClose) {Icon(Icons.Default.CheckBox,"Done")}
        }
    }
}
@Composable fun BookmarkList(controller:BrowserController,onOpen:(Bookmark)->Unit,onEdit:(Bookmark)->Unit,onClose:()->Unit) {
    var removing by remember { mutableStateOf<Bookmark?>(null) }
    FullPage("Bookmarks",onClose) {
        if(controller.bookmarks.isEmpty())Text("Use Share → Add bookmark to save a page.",Modifier.padding(24.dp),color=MaterialTheme.colorScheme.onSurfaceVariant)
        LazyColumn {items(controller.bookmarks,key={it.id}) {item ->
            val icon by produceState<android.graphics.Bitmap?>(null,item.url) {value=controller.icons.get(item.url)}
            ListItem(headlineContent={Text(item.title)},supportingContent={Text(item.url,maxLines=1,overflow=TextOverflow.Ellipsis)},leadingContent={
                Box(Modifier.size(36.dp).background(MaterialTheme.colorScheme.surfaceVariant,RoundedCornerShape(8.dp)),contentAlignment=Alignment.Center) {
                    icon?.let {Image(it.asImageBitmap(),null,Modifier.padding(5.dp).fillMaxSize())} ?: Icon(Icons.Default.Public,null)
                }
            },trailingContent={Row {IconButton({onEdit(item)}) {Icon(Icons.Default.Edit,"Edit bookmark: ${item.title}")};IconButton({removing=item}) {Icon(Icons.Default.DeleteOutline,"Delete bookmark: ${item.title}")}}},modifier=Modifier.clickable {onOpen(item)})
        } }
    }
    removing?.let {item ->AlertDialog(onDismissRequest={removing=null},title={Text("Delete bookmark?")},text={Text(item.title)},confirmButton={TextButton({controller.removeBookmark(item);removing=null}) {Text("Delete")}},dismissButton={TextButton({removing=null}) {Text("Cancel")}})}
}
@Composable fun BookmarkEditor(draft:Bookmark,onSave:(Bookmark)->Unit,onClose:()->Unit) {
    var title by remember(draft.id) {mutableStateOf(draft.title)};var address by remember(draft.id) {mutableStateOf(draft.url)}
    val destination=Routing.destination(address)?.takeIf { !it.second }
    FullPage("Bookmark",onClose) {
        Column(Modifier.padding(24.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(20.dp)) {
            OutlinedTextField(title,{title=it},Modifier.fillMaxWidth(),label={Text("Title")})
            OutlinedTextField(address,{address=it},Modifier.fillMaxWidth(),label={Text("Website address")},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Uri),singleLine=true)
            GoldButton("Save bookmark",{onSave(draft.copy(title=title.trim(),url=destination!!.first))},title.isNotBlank()&&destination!=null)
        }
    }
}
@Composable fun SettingsPage(controller:BrowserController,enableReminders:()->Unit,openNotifications:()->Unit,onClose:()->Unit) {
    FullPage("Settings",onClose) {
        Column(Modifier.padding(24.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(20.dp)) {
            PreferenceControls(controller)
            HorizontalDivider()
            Text("Daily Proverb",style=MaterialTheme.typography.headlineMedium)
            OutlinedButton({controller.readingDay=java.time.LocalDate.now().dayOfMonth}) {Text("Read today’s proverb")}
            ReminderControls(controller,false,openNotifications)
            ReminderActions(controller,enableReminders)
            HorizontalDivider()
            Text("Account",style=MaterialTheme.typography.headlineMedium)
            GoldButton("Continue with email",{controller.navigate(Routing.withReferral(Routing.LOGIN,controller.prefs));onClose()})
            Text("Browser bookmarks, recent searches and reminder settings stay on this device. Website account controls can save supported search preferences.",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
@Composable fun Reader(controller:BrowserController,day:Int,onClose:()->Unit) {
    val chapter=remember(day) {Proverbs.chapter(controller.activity,day)}
    var full by rememberSaveable(day) {mutableStateOf(false)}
    FullPage("Daily Proverb",onClose) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
            Text("PROVERBS $day",color=MaterialTheme.colorScheme.primary,letterSpacing=2.sp)
            Text("A little wisdom, every day.",style=MaterialTheme.typography.headlineLarge)
            Text("“${chapter.highlight}”",fontFamily=FontFamily.Serif,fontSize=23.sp)
            Text("${chapter.reference} · World English Bible",color=MaterialTheme.colorScheme.primary)
            Card {Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {Text("A MOMENT TO REFLECT",letterSpacing=2.sp,style=MaterialTheme.typography.labelMedium);Text(chapter.reflection);Text("Reflection by Savedd",style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}}
            GoldButton(if(full)"Hide full chapter" else "Read Proverbs $day",{full=!full})
            if(full)SelectionContainer {Column(verticalArrangement=Arrangement.spacedBy(16.dp)) {chapter.verses.forEach {Text("${it.number}  ${it.text}",fontFamily=FontFamily.Serif)}}}
            OutlinedButton({controller.submit("Proverbs $day meaning and context");onClose()}) {Icon(Icons.Default.Search,null);Text("Explore this chapter with Savedd")}
            Text("Scripture: World English Bible (WEB), public domain. The same chapter returns each month.",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
