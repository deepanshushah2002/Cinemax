<div align="center">

# 🎬 CINÉMA

**A beautifully crafted local video player for Android, built with Flutter.**

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=flat-square&logo=dart&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-00E5FF?style=flat-square)

</div>

---

## ✨ Features

### 📚 Library Screen
- **Auto-scans** device storage on launch — finds videos in `Movies`, `DCIM`, `Videos`, `Download`, and `WhatsApp Video`
- **Real video thumbnails** — extracts actual frames from every video file
- **Search** — filter your library instantly by filename
- **Library / Recent tabs** — browse all videos or jump back to what you watched last
- **Manual file picker** — add individual videos from anywhere on the device
- **Grid layout** — colour-coded by format: cyan for MP4, purple for MKV, red for AVI, yellow for MOV

### 🎮 Player Screen
- **Smooth playback** — powered by `video_player` with auto-advance to next in playlist
- **Gesture controls** — swipe anywhere on screen:
  - ↔ Horizontal drag → scrub / seek
  - ↕ Right side drag → volume
  - ↕ Left side drag → brightness
- **Double-tap seek** — double tap left/right side to jump ±10 seconds with a ripple animation
- **Playback speeds** — 0.25× to 2.0× with an animated speed picker
- **Fullscreen mode** — immersive landscape playback with system UI hidden
- **Playlist drawer** — slides in from the right, shows all videos with current playing indicator
- **Volume toggle** — mute/unmute from the controls bar

### 🎨 Design
- Deep dark theme — `#060810` background with layered elevation
- Cyan `#00E5FF` accent with blue `#0055FF` gradient
- Space Grotesk + DM Sans + DM Mono font trio
- Ambient radial orbs on the home screen
- Cinematic letterbox bars in the player

### 🌀 Animations
| Element | Animation |
|---|---|
| Controls bar | Slides up/down on show/hide |
| Top bar | Slides down from above |
| Play/Pause icon | Cross-fades with scale transition |
| Play button glow | Expands when playing, shrinks when paused |
| Any icon button tap | Spring bounce |
| Progress bar | Expands height while dragging |
| Seek thumb | Scales up + glows brighter on drag |
| Timestamp text | Turns cyan while scrubbing |
| Speed menu | Slides up + fades in |
| Speed chips | Scale bounce on selection |
| Playlist drawer | Slides in from right (cubic ease) |
| Double-tap ripple | Radial wave with icon fade |

---

## 📦 Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  video_player: ^2.9.2          # Core video playback
  google_fonts: ^6.2.1           # Space Grotesk, DM Sans, DM Mono
  flutter_animate: ^4.5.0        # Playlist drawer slide animation
  file_picker: ^8.1.2            # Manual video file selection
  permission_handler: ^11.3.1    # Storage permissions (Android 12/13+)
  video_thumbnail: ^0.5.3        # Thumbnail frame extraction
  cupertino_icons: ^1.0.8
```

---

## 🚀 Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/yourusername/cinema.git
cd cinema
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Android permissions

Add to `android/app/src/main/AndroidManifest.xml` **before** the `<application>` tag:

```xml
<!-- Android 12 and below -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />

<!-- Android 13+ -->
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />

<!-- Required by video_player -->
<uses-permission android:name="android.permission.INTERNET" />
```

### 4. Run

```bash
flutter run
```

---

## 🗂 Project Structure

```
lib/
├── main.dart                   # App entry point
├── theme/
│   └── app_theme.dart          # Colours, text styles, ThemeData
├── models/
│   └── video_file.dart         # VideoFile data model
├── screens/
│   ├── home_screen.dart        # Library + file scanning
│   └── player_screen.dart      # Video player + gestures
└── widgets/
    ├── player_controls.dart    # Animated playback controls
    └── playlist_drawer.dart    # Side playlist panel
```

---

## 🎯 Supported Formats

| Format | Extension |
|--------|-----------|
| MPEG-4 | `.mp4`, `.m4v` |
| Matroska | `.mkv` |
| AVI | `.avi` |
| QuickTime | `.mov` |
| Windows Media | `.wmv` |
| Flash Video | `.flv` |
| WebM | `.webm` |
| 3GPP | `.3gp` |
| MPEG | `.mpg`, `.mpeg`, `.ts` |

> Actual playback support depends on the Android device's media codecs.

---

## 📱 Requirements

- **Flutter** 3.0+
- **Dart** 3.0+
- **Android** 6.0 (API 23) minimum
- **Android** 13 (API 33) fully supported with granular media permissions

---

## 🔮 Roadmap

- [ ] iOS support
- [ ] Subtitle support (.srt, .ass)
- [ ] Picture-in-picture (PiP) mode
- [ ] Sleep timer
- [ ] Gesture sensitivity settings
- [ ] Custom equalizer
- [ ] Cast to Chromecast / AirPlay

---

## 📄 License

```
MIT License — feel free to use, modify, and distribute.
```

---

<div align="center">
  Made with Flutter &nbsp;·&nbsp; Dark theme only, no apologies
</div>
