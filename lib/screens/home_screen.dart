import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../models/video_file.dart';
import '../screens/player_screen.dart';
import '../theme/app_theme.dart';

// Native channel to query MediaStore content URIs
const _mediaStoreChannel = MethodChannel('cinemax/mediastore');

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  int _tabIndex = 0; // 0 = Library, 1 = Recent

  final List<VideoFile> _library = [];
  final List<VideoFile> _recent  = [];

  // Cache: path → thumbnail bytes (null = failed/loading)
  final Map<String, Uint8List?> _thumbCache = {};
  bool _isScanning = false;

  static const _videoExts = {
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', '3gp', 'ts', 'mpg', 'mpeg'
  };

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _scanDeviceVideos();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Android 13+ needs READ_MEDIA_VIDEO; older needs READ_EXTERNAL_STORAGE
      final androidInfo = await _getAndroidSdk();
      if (androidInfo >= 33) {
        final status = await Permission.videos.request();
        return status.isGranted;
      } else {
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    }
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted;
    }
    return true;
  }

  Future<int> _getAndroidSdk() async {
    try {
      final sdk = await const MethodChannel('cinemax/platform')
          .invokeMethod<int>('getSdkInt');
      return sdk ?? 30;
    } catch (_) {
      return 30;
    }
  }

  // ── Scan device via MediaStore ────────────────────────────────────────────

  Future<void> _scanDeviceVideos() async {
    final granted = await _requestPermissions();
    if (!granted) {
      _showPermissionDenied();
      return;
    }

    setState(() => _isScanning = true);

    List<VideoFile> found = [];

    try {
      // Query MediaStore through a native platform channel.
      // Returns List of maps: {path, uri, name, size}
      final List<dynamic> result = await _mediaStoreChannel
          .invokeMethod('queryVideos');

      found = result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        final path = map['path'] as String? ?? '';
        final uri  = map['uri']  as String? ?? '';
        final name = map['name'] as String? ?? path.split('/').last;
        final size = (map['size'] as int?) ?? 0;
        final ext  = name.contains('.') ? name.split('.').last.toLowerCase() : 'mp4';
        return VideoFile(
          path: path,
          name: name,
          extension: ext,
          sizeBytes: size,
          uri: uri,
        );
      }).where((v) => _videoExts.contains(v.extension)).toList();
    } catch (_) {
      // MediaStore channel not yet set up — fall back to directory scan
      found = await _scanByDirectory();
    }

    if (!mounted) return;
    setState(() {
      _library..clear()..addAll(found);
      _recent..clear()..addAll(found.take(5));
      _isScanning = false;
    });

    for (final v in found) {
      _loadThumbnail(v.uri ?? v.path);
    }
  }

  /// Fallback: scan common directories directly (works on Android ≤9 / non-MediaStore)
  Future<List<VideoFile>> _scanByDirectory() async {
    final found = <VideoFile>[];
    final searchDirs = [
      '/storage/emulated/0/Movies',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Videos',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/WhatsApp/Media/WhatsApp Video',
    ];
    for (final dirPath in searchDirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final ext = entity.path.split('.').last.toLowerCase();
          if (!_videoExts.contains(ext)) continue;
          final stat = await entity.stat();
          found.add(VideoFile(
            path: entity.path,
            name: entity.path.split('/').last,
            extension: ext,
            sizeBytes: stat.size,
          ));
        }
      } catch (_) {}
    }
    found.sort((a, b) {
      try {
        return File(b.path).lastModifiedSync()
            .compareTo(File(a.path).lastModifiedSync());
      } catch (_) { return 0; }
    });
    return found;
  }

  // ── Thumbnail loader ───────────────────────────────────────────────────────

  Future<void> _loadThumbnail(String videoUriOrPath) async {
    if (_thumbCache.containsKey(videoUriOrPath)) return;
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: videoUriOrPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        quality: 65,
      );
      if (mounted) setState(() => _thumbCache[videoUriOrPath] = bytes);
    } catch (_) {
      if (mounted) setState(() => _thumbCache[videoUriOrPath] = null);
    }
  }

  // ── Manual file picker ─────────────────────────────────────────────────────

  Future<void> _pickVideos() async {
    final granted = await _requestPermissions();
    if (!granted) { _showPermissionDenied(); return; }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    final newFiles = result.files
        .where((f) => f.path != null)
        .map((f) {
      // f.identifier holds the content:// URI on Android
      final id = f.identifier ?? '';
      return VideoFile(
        path: f.path!,
        name: f.name,
        extension: (f.extension ?? 'mp4').toLowerCase(),
        sizeBytes: f.size,
        uri: id.startsWith('content://') ? id : null,
      );
    })
        .where((v) => !_library.any((e) => e.path == v.path))
        .toList();

    if (newFiles.isEmpty) return;

    setState(() {
      _library.insertAll(0, newFiles);
      _recent.insertAll(0, newFiles);
    });

    for (final v in newFiles) {
      _loadThumbnail(v.uri ?? v.path);
    }
  }

  void _showPermissionDenied() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Storage permission required to browse videos.',
          style: GoogleFonts.dmSans(color: AppTheme.textPrimary),
        ),
        backgroundColor: AppTheme.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'Settings',
          textColor: AppTheme.accent,
          onPressed: openAppSettings,
        ),
      ),
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _openVideo(VideoFile video) {
    final playlist = _tabIndex == 1 ? _recent : _library;
    // Add to recent
    setState(() {
      _recent.removeWhere((v) => v.path == video.path);
      _recent.insert(0, video);
      if (_recent.length > 20) _recent.removeLast();
    });
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(video: video, playlist: playlist),
      ),
    );
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  List<VideoFile> get _activeList => _tabIndex == 0 ? _library : _recent;

  List<VideoFile> get _filtered {
    if (_query.isEmpty) return _activeList;
    final q = _query.toLowerCase();
    return _activeList.where((v) => v.name.toLowerCase().contains(q)).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          _orb(top: -80,   left: -60,  size: 280, color: AppTheme.accent.withOpacity(0.07)),
          _orb(top: 100,   right: -80, size: 240, color: AppTheme.accentBlue.withOpacity(0.06)),
          _orb(bottom: 200, left: 80,  size: 200, color: AppTheme.purple.withOpacity(0.05)),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAppBar(),
                _buildSearchBar(),
                _buildTabs(),
                Expanded(
                  child: _isScanning ? _buildScanningState() : _buildGrid(),
                ),
              ],
            ),
          ),

          Positioned(bottom: 32, right: 20, child: _buildFab()),
        ],
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.accent, AppTheme.accentBlue],
              ),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.3), blurRadius: 12)],
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 22),
          ),
          const SizedBox(width: 10),
          Text(
            'CINÉMA',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          _barBtn(icon: Icons.refresh_rounded,     color: AppTheme.accent,         onTap: _scanDeviceVideos),
          const SizedBox(width: 6),
          _barBtn(icon: Icons.folder_open_rounded, color: AppTheme.textSecondary,  onTap: _pickVideos),
        ],
      ),
    );
  }

  Widget _barBtn({required IconData icon, required Color color, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.bgElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.surface),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      );

  // ── Search bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.surface),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: GoogleFonts.dmSans(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search videos...',
                  hintStyle: GoogleFonts.dmSans(color: AppTheme.textMuted, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (_query.isNotEmpty)
              GestureDetector(
                onTap: () { _searchCtrl.clear(); setState(() => _query = ''); },
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Tabs ───────────────────────────────────────────────────────────────────

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          _tab(label: 'Library', count: _library.length, index: 0),
          const SizedBox(width: 8),
          _tab(label: 'Recent',  count: _recent.length,  index: 1),
        ],
      ),
    );
  }

  Widget _tab({required String label, required int count, required int index}) {
    final active = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.accent : AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? AppTheme.accent : AppTheme.surface),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                color: active ? Colors.black : AppTheme.textSecondary,
                fontSize: 14, fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: active ? Colors.black.withOpacity(0.2) : AppTheme.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.dmMono(
                  color: active ? Colors.black : AppTheme.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Content states ─────────────────────────────────────────────────────────

  Widget _buildScanningState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
      const SizedBox(height: 16),
      Text('Scanning device for videos...',
          style: GoogleFonts.dmSans(color: AppTheme.textSecondary, fontSize: 14)),
    ]),
  );

  Widget _buildGrid() {
    final items = _filtered;

    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam_off_rounded, color: AppTheme.textMuted, size: 48),
          const SizedBox(height: 12),
          Text(
            _query.isNotEmpty ? 'No results for "$_query"' : 'No videos found',
            style: GoogleFonts.dmSans(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text('Tap + Add Videos or the folder icon to browse',
              style: GoogleFonts.dmSans(color: AppTheme.textMuted, fontSize: 12)),
        ]),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _VideoCard(
        video: items[i],
        thumbnail: _thumbCache[items[i].uri ?? items[i].path],
        onTap: () => _openVideo(items[i]),
      ),
    );
  }

  // ── FAB ────────────────────────────────────────────────────────────────────

  Widget _buildFab() => GestureDetector(
    onTap: _pickVideos,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.35), blurRadius: 24, spreadRadius: 1)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.add_rounded, color: Colors.black, size: 20),
        const SizedBox(width: 8),
        Text('Add Videos',
            style: GoogleFonts.dmSans(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    ),
  );

  Widget _orb({double? top, double? bottom, double? left, double? right,
    required double size, required Color color}) =>
      Positioned(
        top: top, bottom: bottom, left: left, right: right,
        child: IgnorePointer(
          child: Container(
            width: size, height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [color, Colors.transparent]),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Video card widget — shows real thumbnail
// ─────────────────────────────────────────────────────────────────────────────

class _VideoCard extends StatelessWidget {
  final VideoFile video;
  final Uint8List? thumbnail;
  final VoidCallback onTap;

  const _VideoCard({required this.video, required this.thumbnail, required this.onTap});

  Color get _color {
    switch (video.extLabel) {
      case 'MKV': return AppTheme.purple;
      case 'AVI': return AppTheme.error;
      case 'MOV': return AppTheme.warning;
      default:    return AppTheme.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.withOpacity(0.25)),
          boxShadow: [BoxShadow(color: c.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail area ─────────────────────────────────────────────
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Real thumbnail or fallback
                    if (thumbnail != null)
                      Image.memory(thumbnail!, fit: BoxFit.cover)
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [c.withOpacity(0.15), const Color(0xFF161B2E), Colors.black],
                          ),
                        ),
                        child: Center(
                          child: Icon(Icons.movie_outlined, color: c.withOpacity(0.3), size: 36),
                        ),
                      ),

                    // Scrim so play button always reads well
                    Container(color: Colors.black.withOpacity(thumbnail != null ? 0.3 : 0.0)),

                    // Play button
                    Center(
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: c.withOpacity(0.45), blurRadius: 18)],
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 26),
                      ),
                    ),

                    // Extension badge
                    Positioned(
                      top: 9, left: 9,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.withOpacity(0.3)),
                        ),
                        child: Text(video.extLabel,
                            style: GoogleFonts.dmMono(color: c, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ),

                    // Duration badge
                    if (video.durationLabel.isNotEmpty)
                      Positioned(
                        bottom: 9, right: 9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(video.durationLabel,
                              style: GoogleFonts.dmMono(
                                  color: AppTheme.textPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Info row ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      color: AppTheme.textPrimary, fontSize: 12,
                      fontWeight: FontWeight.w600, height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(Icons.storage_rounded, color: AppTheme.textMuted, size: 10),
                      const SizedBox(width: 4),
                      Text(video.sizeLabel,
                          style: GoogleFonts.dmMono(color: AppTheme.textMuted, fontSize: 9)),
                      const Spacer(),
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, color: c,
                          boxShadow: [BoxShadow(color: c.withOpacity(0.5), blurRadius: 4)],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}