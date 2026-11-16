package com.savedd.browser

import androidx.compose.foundation.Canvas
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontFamily

val SaveddGold=Color(0xFFD6AF52)
private val Dark=darkColorScheme(primary=SaveddGold,onPrimary=Color(0xFF12101A),background=Color(0xFF12101A),onBackground=Color(0xFFF0ECE5),surface=Color(0xFF191523),onSurface=Color(0xFFF0ECE5),surfaceVariant=Color(0xFF292332),onSurfaceVariant=Color(0xFFB9B0A2))
private val Light=lightColorScheme(primary=Color(0xFF80601C),onPrimary=Color.White,background=Color(0xFFF5F0E6),onBackground=Color(0xFF211A25),surface=Color(0xFFFFFBF3),onSurface=Color(0xFF211A25),surfaceVariant=Color(0xFFE8E0D2),onSurfaceVariant=Color(0xFF655B64))
@Composable fun SaveddTheme(dark:Boolean,content:@Composable ()->Unit) {
    val defaults=Typography()
    MaterialTheme(colorScheme=if(dark)Dark else Light,typography=defaults.copy(
        headlineLarge=defaults.headlineLarge.copy(fontFamily=FontFamily.Serif),
        headlineMedium=defaults.headlineMedium.copy(fontFamily=FontFamily.Serif),
        titleLarge=defaults.titleLarge.copy(fontFamily=FontFamily.Serif)
    ),content=content)
}
@Composable fun SaveddMark(modifier:Modifier=Modifier) {
    Canvas(modifier) {
        val u=size.minDimension/64f
        drawCircle(SaveddGold,17.25f*u,Offset(27.5f*u,27.5f*u),style=Stroke(3.1f*u))
        drawLine(SaveddGold,Offset(40.4f*u,40.4f*u),Offset(53.2f*u,53.2f*u),3.4f*u)
        drawRect(SaveddGold,Offset(25.35f*u,16.8f*u),Size(4.3f*u,21.4f*u))
        drawRect(SaveddGold,Offset(18.9f*u,22.15f*u),Size(17.2f*u,4.15f*u))
    }
}
