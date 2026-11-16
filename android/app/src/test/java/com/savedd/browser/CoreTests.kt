package com.savedd.browser

import org.junit.Assert.*
import org.junit.Test
import java.time.*
import kotlinx.serialization.decodeFromString
import java.io.File

class CoreTests {
    @Test fun literalSearchPreservesQueryCharacters() {
        assertEquals("https://www.savedd.com/?q=faith%20%2B%20hope%20%26%20wisdom",Routing.destination("faith + hope & wisdom")!!.first)
        assertTrue(Routing.destination("how to search")!!.second)
        assertFalse(Routing.destination("example.com/path")!!.second)
        assertNull(Routing.destination("   "))
        assertEquals("https://example.com/",Routing.destination("http://example.com/")!!.first)
    }
    @Test fun emptyHomepageAndOrigins() {
        assertTrue(Routing.home("https://www.savedd.com/?ref=alex"))
        assertFalse(Routing.home("https://savedd.com/?q=coffee"))
        assertFalse(Routing.trusted("https://www.savedd.com.evil.test/"))
        assertFalse(Routing.trusted("http://savedd.com/"))
        assertFalse(Routing.trusted("https://savedd.com:444/"))
        assertFalse(Routing.trusted("https://user@savedd.com/"))
    }
    @Test fun callbackOnlyAcceptsFixedCodeShape() {
        assertEquals("https://www.savedd.com/?code=a%2Bb",Routing.callback("savedd://auth/callback?code=a%2Bb"))
        for(url in listOf("savedd://evil/callback?code=x","savedd://auth/callback?code=x&code=y","savedd://auth/callback?code=x&next=https://evil.test","savedd://auth/callback?code=","https://www.savedd.com/?code=x","savedd://user@auth/callback?code=x","savedd://auth/callback?code=x#access_token")) assertNull(url,Routing.callback(url))
    }
    @Test fun reminderFollowsLocalDayAcrossShortMonthsAndDst() {
        val zone=ZoneId.of("America/Toronto")
        val dates=listOf("2027-02-28T09:00:00","2028-02-29T09:00:00","2026-11-30T09:00:00","2026-12-31T09:00:00","2027-03-13T09:00:00")
        for(date in dates) {
            val now=LocalDateTime.parse(date).atZone(zone)
            val next=ReminderClock.next(now,8,0)
            assertTrue(next.isAfter(now));assertEquals(now.toLocalDate().plusDays(1),next.toLocalDate());assertEquals(8,next.hour)
            assertEquals(next.dayOfMonth,ReminderClock.chapter(next))
        }
        val spring=LocalDateTime.parse("2027-03-13T09:00:00").atZone(zone)
        val shifted=ReminderClock.next(spring,2,30)
        assertEquals(14,shifted.dayOfMonth);assertTrue(shifted.isAfter(spring))
    }
    @Test fun directoryUsesOnlyValidUniqueApprovedRecords() {
        val alex=Partner("alex","a".repeat(64),"Alex Newman")
        val items=listOf(alex,alex.copy(pubkey="b".repeat(64)),alex.copy(slug="admin"),alex.copy(slug="other",pubkey="bad"))
        assertEquals(listOf(alex),DirectoryValidation.approved(PartnerResponse(items,DirectoryConfig())))
        assertTrue(DirectoryValidation.approved(PartnerResponse(items,DirectoryConfig(false))).isEmpty())
    }
    @Test fun bundledReadingsHaveAllChaptersAndStaticExample() {
        val library=AppJson.decodeFromString<ProverbLibrary>(File(requireNotNull(System.getProperty("savedd.proverbs"))).readText())
        assertEquals((1..31).toList(),library.chapters.map {it.day})
        assertEquals(915,library.chapters.sumOf {it.verses.size})
        assertTrue(library.chapters.all {it.highlight.isNotBlank() && it.reflection.isNotBlank()})
        assertEquals("The heart of the discerning gets knowledge. The ear of the wise seeks knowledge.",library.chapters[17].verses.first {it.number==15}.text)
        assertEquals(2,library.chapters[10].highlightVerse)
    }
}
