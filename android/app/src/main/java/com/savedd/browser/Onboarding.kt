package com.savedd.browser

import android.app.TimePickerDialog
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.shape.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.*
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.*

val Languages=listOf("" to "Any language","en" to "English","da" to "Dansk","de" to "Deutsch","es" to "Español","fr" to "Français","it" to "Italiano","nl" to "Nederlands","no" to "Norsk","sv" to "Svenska","fi" to "Suomi","pl" to "Polski","pt" to "Português","ja" to "日本語","zh" to "中文","ru" to "Русский")

@Composable fun GoldButton(text:String,onClick:()->Unit,enabled:Boolean=true) {
    Button(onClick,Modifier.fillMaxWidth().heightIn(min=54.dp),enabled=enabled,shape=RoundedCornerShape(16.dp)) { Text(text,fontWeight=FontWeight.SemiBold) }
}
@Composable fun Heading(title:String,description:String) {
    Text(title,style=MaterialTheme.typography.headlineLarge)
    Text(description,color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.bodyLarge)
}
@Composable fun Onboarding(controller:BrowserController,enableReminders:()->Unit,openNotifications:()->Unit) {
    var step by rememberSaveable { mutableIntStateOf(0) }
    val titles=listOf("Welcome","Your invitation","Your preferences","Daily wisdom","Your account")
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).safeDrawingPadding().imePadding().padding(horizontal=24.dp)) {
        Row(Modifier.fillMaxWidth().height(56.dp),verticalAlignment=Alignment.CenterVertically) {
            if(step>0)IconButton({step--}) { Icon(Icons.Default.ChevronLeft,"Back") } else Spacer(Modifier.width(48.dp))
            Text("SAVEDD",Modifier.weight(1f),fontFamily=FontFamily.Serif,letterSpacing=3.sp,textAlign=TextAlign.Center)
            Text("${step+1} / 5",Modifier.width(48.dp),color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Row(horizontalArrangement=Arrangement.spacedBy(6.dp)) { repeat(5) { index ->
            Box(Modifier.weight(1f).height(3.dp).clip(CircleShape).background(if(index<=step)SaveddGold else MaterialTheme.colorScheme.surfaceVariant))
        } }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top=28.dp,bottom=20.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
            when(step) {
                0 -> Column(Modifier.fillMaxWidth(),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(20.dp)) {
                    SaveddMark(Modifier.size(112.dp).padding(10.dp))
                    Text("SAVEDD",fontSize=44.sp,fontFamily=FontFamily.Serif,letterSpacing=6.sp)
                    Text("Seek, and ye shall find.",color=SaveddGold,fontFamily=FontFamily.Serif,fontSize=23.sp,fontStyle=FontStyle.Italic,textAlign=TextAlign.Center)
                    Text("MATTHEW 7:7",style=MaterialTheme.typography.labelSmall,letterSpacing=3.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(10.dp))
                    Text("A better place to search.",style=MaterialTheme.typography.headlineMedium,textAlign=TextAlign.Center)
                    Text("Everyday search, informed by Christian values. Make Savedd feel like yours in a few simple steps.",color=MaterialTheme.colorScheme.onSurfaceVariant,textAlign=TextAlign.Center)
                }
                1 -> {
                    Heading("Who introduced you?","Find the person or community who shared Savedd with you. This step is optional.")
                    PartnerPicker(controller)
                }
                2 -> {
                    Heading("Make yourself at home.","Choose how you like to search. You can change these anytime in Settings.")
                    PreferenceControls(controller)
                }
                3 -> {
                    Heading("A little wisdom, every day.","Start a daily rhythm with Proverbs. Choose a time for a gentle reminder, or skip for now.")
                    ReminderControls(controller,staticExample=true,openNotifications=openNotifications)
                }
                4 -> {
                    Heading("Keep your settings with you.","Join or sign in with email. Savedd sends a secure sign-in link; an existing password or email code can also be used.")
                    Card { Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
                        Text("Your choices, ready to go",color=MaterialTheme.colorScheme.primary,fontWeight=FontWeight.Bold)
                        Summary("Appearance",if(controller.prefs.dark)"Dark" else "Light")
                        Summary("Search language",Languages.find { it.first==controller.prefs.language }?.second ?: controller.prefs.language)
                        Summary("Privacy Mode",if(controller.prefs.privacy)"On" else "Off")
                        Summary("Daily Proverb",if(controller.prefs.reminders&&controller.notificationsAllowed)"Daily at ${timeLabel(controller.prefs)}" else "Off")
                        controller.prefs.partner?.let { Summary("Introduced by",it.name) }
                    } }
                    Text("Your preferences are already saved on this device. Website account controls can save supported search preferences; reminders and browser bookmarks stay on this phone.",color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Column(Modifier.fillMaxWidth().padding(bottom=12.dp),horizontalAlignment=Alignment.CenterHorizontally) {
            when(step) {
                1 -> {
                    val code=controller.prefs.referralCode.trim()
                    GoldButton("Continue",{
                        val partner=controller.prefs.partner ?: controller.partners.find { it.slug.equals(code,true) }
                        controller.update(controller.prefs.copy(partner=partner,referralCode=partner?.slug ?: code.lowercase()));step++
                    },code.isBlank()||controller.prefs.partner!=null||code.matches(Regex("[A-Za-z0-9][A-Za-z0-9-]{1,31}")))
                    TextButton({controller.update(controller.prefs.copy(referralCode="",partner=null));step++}) { Text("Skip for now") }
                }
                3 -> {
                    ReminderActions(controller,enableReminders)
                    TextButton({step++}) { Text(if(controller.prefs.reminders&&controller.notificationsAllowed)"Continue" else "Maybe later") }
                }
                4 -> {
                    GoldButton("Continue with email",{controller.finishOnboarding(true)})
                    TextButton({controller.finishOnboarding(false)}) { Text("Continue without an account") }
                }
                else -> {
                    GoldButton(if(step==0)"Get started" else "Continue",{step++})
                    Text("Saved on this device. Always yours to change.",style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant,modifier=Modifier.padding(top=12.dp))
                }
            }
        }
    }
}
@Composable fun Summary(label:String,value:String) {
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(16.dp)) { Text(label,Modifier.weight(1f),color=MaterialTheme.colorScheme.onSurfaceVariant);Text(value,Modifier.weight(1f),textAlign=TextAlign.End) }
}
@Composable fun PartnerPicker(controller:BrowserController) {
    OutlinedTextField(controller.prefs.referralCode,{controller.update(controller.prefs.copy(referralCode=it.take(80),partner=null))},Modifier.fillMaxWidth(),label={Text("Partner name or referral code")},singleLine=true,leadingIcon={Icon(Icons.Default.Search,null)},trailingIcon={if(controller.prefs.referralCode.isNotBlank())IconButton({controller.update(controller.prefs.copy(referralCode="",partner=null))}) {Icon(Icons.Default.Close,"Clear partner search")}})
    controller.prefs.partner?.let { Text("Selected: ${it.name}",color=MaterialTheme.colorScheme.primary) }
    when {
        controller.directoryLoading -> Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {CircularProgressIndicator(Modifier.size(20.dp));Text("Finding Savedd partners…")}
        controller.directoryError!=null -> {Text(controller.directoryError!!);TextButton({controller.prefetchPartners(true)}) {Text("Try again")} }
        !controller.programEnabled -> Text("The referral program is paused. You can skip this step.")
        else -> {
            val matches=controller.partners.filter { it.matches(controller.prefs.referralCode.trim()) }
            if(matches.isEmpty())Text(if(controller.prefs.referralCode.isBlank())"No partners are listed yet. Have a code? Enter it above." else "No matching partner. You can save your code for later.",color=MaterialTheme.colorScheme.onSurfaceVariant)
            else LazyVerticalGrid(GridCells.Adaptive(130.dp),Modifier.fillMaxWidth().heightIn(max=340.dp),horizontalArrangement=Arrangement.spacedBy(12.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                items(matches,key={it.pubkey}) { partner ->
                    Card(onClick={controller.update(controller.prefs.copy(partner=partner,referralCode=partner.slug))},border=BorderStroke(if(partner==controller.prefs.partner)2.dp else 1.dp,if(partner==controller.prefs.partner)SaveddGold else MaterialTheme.colorScheme.outlineVariant)) {
                        Column(Modifier.fillMaxWidth().padding(16.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(10.dp)) {
                            Box(Modifier.size(56.dp).background(SaveddGold.copy(alpha=.12f),CircleShape),contentAlignment=Alignment.Center) { Text(partner.initials,color=SaveddGold,fontFamily=FontFamily.Serif,fontSize=24.sp) }
                            Text(partner.name,textAlign=TextAlign.Center);Text(partner.slug,style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}
@Composable fun PreferenceControls(controller:BrowserController) {
    Text("Appearance",fontWeight=FontWeight.Bold)
    Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
        listOf(true to "Dark",false to "Light").forEach { (dark,title) ->
            FilterChip(selected=controller.prefs.dark==dark,onClick={controller.update(controller.prefs.copy(dark=dark))},label={Text(title)},leadingIcon={Icon(if(dark)Icons.Default.DarkMode else Icons.Default.LightMode,null)})
        }
    }
    var languageMenu by remember { mutableStateOf(false) }
    Text("Search language",fontWeight=FontWeight.Bold)
    Box {
        OutlinedButton({languageMenu=true}) {Text(Languages.find { it.first==controller.prefs.language }?.second ?: controller.prefs.language);Icon(Icons.Default.ArrowDropDown,null)}
        DropdownMenu(languageMenu,{languageMenu=false},Modifier.heightIn(max=350.dp)) { Languages.forEach { (code,name) -> DropdownMenuItem({Text(name)},{controller.update(controller.prefs.copy(language=code));languageMenu=false}) } }
    }
    Card { Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment=Alignment.CenterVertically) {Text("Privacy Mode",Modifier.weight(1f),fontWeight=FontWeight.Bold);Switch(controller.prefs.privacy,{controller.update(controller.prefs.copy(privacy=it))})}
        Text("Use the community index instead of external search providers. You may see fewer results.",color=MaterialTheme.colorScheme.onSurfaceVariant)
        Text("This isn’t private browsing or a VPN. Pages you visit and optional AI answers can still connect to other services.",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    } }
}
fun timeLabel(p:Preferences)=String.format(java.util.Locale.getDefault(),"%02d:%02d",p.hour,p.minute)
@Composable fun ReminderControls(controller:BrowserController,staticExample:Boolean,openNotifications:()->Unit) {
    val context=LocalContext.current
    val day=if(staticExample)18 else java.time.LocalDate.now().dayOfMonth
    val chapter=remember(day) { Proverbs.chapter(context,day) }
    val verse=chapter.verses.first { it.number==if(staticExample)15 else chapter.highlightVerse }
    Card { Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
        Text("☀  DAILY PROVERB",color=SaveddGold,letterSpacing=2.sp,style=MaterialTheme.typography.labelMedium)
        Text("“${verse.text}”",fontFamily=FontFamily.Serif,fontSize=21.sp)
        Text("Proverbs $day:${verse.number} · World English Bible",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Text(if(staticExample)"Example notification · A new chapter each day" else "Notification preview · Today’s chapter",style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    } }
    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
        Text("Remind me at",Modifier.weight(1f))
        OutlinedButton({TimePickerDialog(context,{_,hour,minute->controller.update(controller.prefs.copy(hour=hour,minute=minute));ProverbReminders.schedule(context)},controller.prefs.hour,controller.prefs.minute,android.text.format.DateFormat.is24HourFormat(context)).show()}) {Text(timeLabel(controller.prefs))}
    }
    Text("The day of the month guides your reading: on the 8th, read Proverbs 8. Reminders follow your phone’s local time. No account needed.",color=MaterialTheme.colorScheme.onSurfaceVariant)
    Text("Android battery saving may delay delivery.",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    if(controller.prefs.reminders&&controller.notificationsAllowed)Text("Daily reminder set for ${timeLabel(controller.prefs)}",color=MaterialTheme.colorScheme.primary)
    if(!controller.notificationsAllowed && (controller.prefs.notificationAsked || android.os.Build.VERSION.SDK_INT<33))TextButton(openNotifications) { Text("Android notification settings") }
}
@Composable fun ReminderActions(controller:BrowserController,enableReminders:()->Unit) {
    val context=LocalContext.current
    if(controller.prefs.reminders)TextButton({controller.update(controller.prefs.copy(reminders=false));ProverbReminders.schedule(context)}) {Text("Turn off daily reminders")}
    else GoldButton("Enable daily reminder",enableReminders)
}
