package com.krypton.player

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.MediaItem
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors
import kotlinx.coroutines.launch

private val Ink = Color(0xFF090B10)
private val Panel = Color(0xFF151923)
private val Muted = Color(0xFF9299A8)
private val Cyan = Color(0xFF8BE9F2)

class MainActivity : ComponentActivity() {
    private var controller by mutableStateOf<MediaController?>(null)
    private var tracks by mutableStateOf<List<Track>>(emptyList())
    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        if (it) loadTracks()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val token = SessionToken(this, android.content.ComponentName(this, PlaybackService::class.java))
        val future = MediaController.Builder(this, token).buildAsync()
        future.addListener({ controller = future.get() }, MoreExecutors.directExecutor())
        val readPermission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
            else Manifest.permission.READ_EXTERNAL_STORAGE
        if (ContextCompat.checkSelfPermission(this, readPermission) == PackageManager.PERMISSION_GRANTED) loadTracks()
        else permission.launch(readPermission)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme(
                background = Ink, surface = Panel, primary = Cyan,
                onBackground = Color.White, onSurface = Color.White
            )) {
                KryptonApp(
                    tracks = tracks,
                    controller = controller,
                    onRefresh = ::loadTracks,
                    onPlay = { track ->
                        val c = controller ?: return@KryptonApp
                        val items = tracks.map { MediaItem.fromUri(it.uri) }
                        c.setMediaItems(items, tracks.indexOf(track), 0L)
                        c.prepare()
                        c.play()
                    }
                )
            }
        }
    }

    private fun loadTracks() {
        tracks = MusicLibrary.query(this)
    }

    override fun onDestroy() {
        controller?.release()
        super.onDestroy()
    }
}

@Composable
private fun KryptonApp(
    tracks: List<Track>,
    controller: MediaController?,
    onRefresh: () -> Unit,
    onPlay: (Track) -> Unit
) {
    var selected by remember { mutableStateOf("Library") }
    var currentTitle by remember { mutableStateOf("Choose a track") }
    var playing by remember { mutableStateOf(false) }
    LaunchedEffect(controller) {
        while (controller != null) {
            currentTitle = controller.mediaMetadata.title?.toString() ?: "Choose a track"
            playing = controller.isPlaying
            kotlinx.coroutines.delay(500)
        }
    }
    Scaffold(
        containerColor = Ink,
        bottomBar = {
            NavigationBar(containerColor = Panel, contentColor = Color.White) {
                listOf("Library", "Playlists", "Settings").forEach { tab ->
                    NavigationBarItem(
                        selected = selected == tab,
                        onClick = { selected = tab },
                        icon = { Icon(
                            when(tab) { "Library" -> Icons.Default.LibraryMusic; "Playlists" -> Icons.Default.QueueMusic; else -> Icons.Default.Tune },
                            contentDescription = tab
                        ) },
                        label = { Text(tab) },
                        colors = NavigationBarItemDefaults.colors(selectedIconColor = Cyan, indicatorColor = Color(0xFF26333B))
                    )
                }
            }
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(horizontal = 20.dp)) {
            Row(Modifier.fillMaxWidth().padding(top = 24.dp, bottom = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("KRYPTON", color = Cyan, fontSize = 12.sp, letterSpacing = 4.sp, fontWeight = FontWeight.Bold)
                    Text(selected, fontSize = 30.sp, fontWeight = FontWeight.Bold)
                }
                IconButton(onClick = onRefresh) { Icon(Icons.Default.Refresh, "Rescan", tint = Muted) }
            }
            when (selected) {
                "Library" -> {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        StatCard("TRACKS", tracks.size.toString(), Modifier.weight(1f))
                        StatCard("MODE", "OFFLINE", Modifier.weight(1f))
                    }
                    Spacer(Modifier.height(18.dp))
                    Text("YOUR MUSIC", color = Muted, fontSize = 11.sp, letterSpacing = 2.sp)
                    Spacer(Modifier.height(8.dp))
                    if (tracks.isEmpty()) {
                        EmptyLibrary()
                    } else {
                        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(tracks, key = { it.id }) { track ->
                                TrackRow(track) { currentTitle = track.title; onPlay(track) }
                            }
                        }
                    }
                }
                "Playlists" -> {
                    Text("Your listening space", color = Muted)
                    Spacer(Modifier.height(14.dp))
                    FeatureCard("Favorites", "Your saved tracks", Icons.Default.Favorite)
                    FeatureCard("Recently played", "Pick up where you left off", Icons.Default.History)
                    FeatureCard("Up next", "Queue and reorder tracks", Icons.Default.QueueMusic)
                }
                else -> {
                    Text("PLAYBACK", color = Muted, fontSize = 11.sp, letterSpacing = 2.sp)
                    FeatureCard("10-band equalizer", "Equalizer, bass boost and virtualizer", Icons.Default.Equalizer)
                    FeatureCard("Lyrics", "Embedded tags and .LRC / .TXT sidecars", Icons.Default.Lyrics)
                    FeatureCard("Sleep timer", "Set a gentle stop time", Icons.Default.Bedtime)
                    FeatureCard("Appearance", "Dynamic artwork-inspired accents", Icons.Default.Palette)
                }
            }
            Spacer(Modifier.weight(1f))
            MiniPlayer(currentTitle, playing, onToggle = {
                controller?.let { if (it.isPlaying) it.pause() else it.play() }
            })
        }
    }
}

@Composable
private fun StatCard(label: String, value: String, modifier: Modifier) {
    Card(modifier, colors = CardDefaults.cardColors(containerColor = Panel), shape = RoundedCornerShape(18.dp)) {
        Column(Modifier.padding(16.dp)) {
            Text(label, color = Muted, fontSize = 10.sp, letterSpacing = 1.5.sp)
            Text(value, fontSize = 21.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun EmptyLibrary() {
    Column(Modifier.fillMaxWidth().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Default.MusicNote, null, tint = Cyan, modifier = Modifier.size(48.dp))
        Spacer(Modifier.height(12.dp))
        Text("Your library is quiet", fontWeight = FontWeight.SemiBold)
        Text("Add audio files to your device, then tap rescan.", color = Muted)
    }
}

@Composable
private fun TrackRow(track: Track, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(Panel, RoundedCornerShape(16.dp)).clickable(onClick = onClick).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(48.dp).background(
            Brush.linearGradient(listOf(Color(0xFF283B48), Color(0xFF17202C))), RoundedCornerShape(12.dp)
        ), contentAlignment = Alignment.Center) { Icon(Icons.Default.MusicNote, null, tint = Cyan) }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(track.title, maxLines = 1, fontWeight = FontWeight.SemiBold)
            Text(track.artist, color = Muted, fontSize = 12.sp, maxLines = 1)
        }
        Icon(Icons.Default.PlayCircle, null, tint = Cyan, modifier = Modifier.size(28.dp))
    }
}

@Composable
private fun FeatureCard(title: String, subtitle: String, icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp).background(Panel, RoundedCornerShape(16.dp)).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Cyan)
        Spacer(Modifier.width(14.dp))
        Column {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = Muted, fontSize = 12.sp)
        }
    }
}

@Composable
private fun MiniPlayer(title: String, playing: Boolean, onToggle: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 10.dp).background(
            Brush.horizontalGradient(listOf(Color(0xFF1C2933), Panel)), RoundedCornerShape(18.dp)
        ).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(38.dp).background(Color(0xFF263B46), RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
            Icon(Icons.Default.GraphicEq, null, tint = Cyan)
        }
        Spacer(Modifier.width(10.dp))
        Text(title, Modifier.weight(1f), maxLines = 1, fontWeight = FontWeight.Medium)
        IconButton(onClick = onToggle) {
            Icon(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, "Play or pause", tint = Cyan)
        }
    }
}
