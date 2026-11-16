package com.savedd.browser

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.URI
import java.net.URLEncoder
import java.time.*
import java.util.Locale

@Serializable data class Partner(val slug: String, val pubkey: String, val name: String) {
    val initials get() = name.split(" ").filter { it.isNotEmpty() }.take(2).joinToString("") { it.take(1).uppercase() }
    fun matches(query: String) = name.contains(query, true) || slug.contains(query, true) || pubkey.equals(query, true)
}
@Serializable data class Preferences(
    val dark: Boolean = true,
    val language: String = Locale.getDefault().language.takeIf { it.matches(Regex("[a-z]{2}")) } ?: "en",
    val privacy: Boolean = false,
    val referralCode: String = "",
    val partner: Partner? = null,
    val reminders: Boolean = false,
    val notificationAsked: Boolean = false,
    val hour: Int = 8,
    val minute: Int = 0,
    val complete: Boolean = false
)
@Serializable data class Bookmark(val id: String = java.util.UUID.randomUUID().toString(), val title: String, val url: String)
@Serializable data class RecentEntry(val text: String, val url: String, val search: Boolean)
@Serializable data class SavedTab(val id: String = java.util.UUID.randomUUID().toString(), val url: String = Routing.HOME, val title: String = "New Tab")
@Serializable data class Verse(val number: Int, val text: String)
@Serializable data class Chapter(val day: Int, val highlightVerse: Int, val reflection: String, val verses: List<Verse>) {
    val highlight get() = verses.first { it.number == highlightVerse }.text
    val reference get() = "Proverbs $day:$highlightVerse"
}
@Serializable data class ProverbLibrary(val translation: String, val chapters: List<Chapter>)
@Serializable data class DirectoryConfig(val enabled: Boolean = true)
@Serializable data class PartnerResponse(val partners: List<Partner>, val config: DirectoryConfig)
val AppJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

object Routing {
    const val HOME = "https://www.savedd.com/"
    const val LOGIN = "https://www.savedd.com/auth/email?client=android"
    fun trusted(url: String): Boolean = try {
        val uri = URI(url)
        uri.scheme == "https" && uri.host in setOf("savedd.com", "www.savedd.com") && uri.port in listOf(-1,443) && uri.userInfo == null
    } catch (_: Exception) { false }
    fun home(url: String): Boolean = try {
        val uri = URI(url)
        trusted(url) && uri.path in listOf("", "/") && !query(uri).containsKey("q")
    } catch (_: Exception) { false }
    private fun encoded(text: String) = URLEncoder.encode(text, "UTF-8").replace("+", "%20")
    fun destination(input: String): Pair<String, Boolean>? {
        val text = input.trim()
        if (text.isEmpty()) return null
        if (!text.any(Char::isWhitespace) && (text.startsWith("https://",true) || text.startsWith("http://",true) || (!text.contains("://") && text.contains('.')))) {
            try {
                val uri = URI(if (text.contains("://")) text else "https://$text")
                if (uri.scheme.lowercase() in listOf("http","https") && !uri.host.isNullOrEmpty() && uri.userInfo == null) return uri.toASCIIString().replaceFirst(Regex("^http:",RegexOption.IGNORE_CASE),"https:") to false
            } catch (_: Exception) { }
        }
        return HOME + "?q=" + encoded(text) to true
    }
    fun withReferral(url: String, preferences: Preferences): String {
        val code = preferences.partner?.slug ?: preferences.referralCode.trim()
        return if (code.isBlank()) url else url + (if ('?' in url) "&" else "?") + "ref=" + encoded(code)
    }
    fun callback(url: String): String? = try {
        val uri = URI(url)
        val params = query(uri)
        val code = params["code"]?.singleOrNull()
        if (uri.scheme.equals("savedd",true) && uri.host == "auth" && uri.path == "/callback" && uri.userInfo == null && uri.port == -1 && uri.fragment == null && params.size == 1 && !code.isNullOrEmpty() && code.length <= 2048) HOME + "?code=" + encoded(code) else null
    } catch (_: Exception) { null }
    private fun query(uri: URI): Map<String,List<String>> = uri.rawQuery?.split('&')?.groupBy(
        { java.net.URLDecoder.decode(it.substringBefore('='),"UTF-8") },
        { java.net.URLDecoder.decode(it.substringAfter('=',""),"UTF-8") }
    ) ?: emptyMap()
}

object ReminderClock {
    fun next(now: ZonedDateTime, hour: Int, minute: Int): ZonedDateTime {
        require(hour in 0..23 && minute in 0..59)
        val today = now.toLocalDate().atTime(hour,minute).atZone(now.zone)
        return if (today.isAfter(now)) today else now.toLocalDate().plusDays(1).atTime(hour,minute).atZone(now.zone)
    }
    fun chapter(now: ZonedDateTime) = now.dayOfMonth
}

object DirectoryValidation {
    private val reserved = "about admin api assets bookmarks build community dashboard docs explore goodbye heaven index instances network partners policy protocol remoteloginsuccess settings www".split(' ').toSet()
    fun approved(response: PartnerResponse): List<Partner> {
        if (!response.config.enabled) return emptyList()
        val slugs = mutableSetOf<String>(); val keys = mutableSetOf<String>()
        return response.partners.filter {
            val valid=it.slug.length in 2..32 && it.slug.matches(Regex("[a-z0-9]+(?:-[a-z0-9]+)*")) && it.slug !in reserved &&
                it.pubkey.matches(Regex("[a-f0-9]{64}")) && it.name.trim().isNotEmpty() && it.name.length <=60 &&
                it.slug !in slugs && it.pubkey !in keys
            if(valid) {slugs.add(it.slug);keys.add(it.pubkey)}
            valid
        }.sortedBy { it.name.lowercase() }
    }
}
