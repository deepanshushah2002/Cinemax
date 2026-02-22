import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../models/video_file.dart';
import '../widgets/player_controls.dart';
import '../widgets/playlist_drawer.dart';

enum _GestureMode { none, seek, volume, brightness }

class PlayerScreen extends StatefulWidget {
  final VideoFile video;
  final List<VideoFile> playlist;
  const PlayerScreen({super.key, required this.video, required this.playlist});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  Timer? _hideTimer;
  late int _currentIndex;
  bool _showPlaylist = false;
  String? _errorMessage;

  // Gesture state
  _GestureMode _gestureMode = _GestureMode.none;
  double _volume = 1.0;
  double _brightness = 0.7;
  double _seekDeltaSeconds = 0;
  Duration _seekPreviewPosition = Duration.zero;
  bool _showGestureOverlay = false;
  double _dragStartY = 0;
  double _dragStartX = 0;
  double _volumeAtDragStart = 1.0;
  double _brightnessAtDragStart = 0.7;
  Duration _positionAtDragStart = Duration.zero;

  // Ripple state
  bool _showLeftRipple = false;
  bool _showRightRipple = false;

  late AnimationController _overlayFadeCtrl;
  late AnimationController _seekRippleCtrl;

  static const double _kGestureThreshold = 10.0;
  static const double _kSeekSensitivity = 0.25;
  static const double _kVertSensitivity = 0.006;

  @override
  void initState() {
    super.initState();
    _overlayFadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _seekRippleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _currentIndex = widget.playlist.indexWhere((v) => v.path == widget.video.path);
    if (_currentIndex < 0) _currentIndex = 0;
    _initVideo(widget.video);
    _scheduleHide();
  }

  Future<void> _initVideo(VideoFile video) async {
    final old = _controller;
    setState(() { _initialized = false; _errorMessage = null; });
    VideoPlayerController? controller;
    try {
      // Prefer content URI (works on Android 10+ scoped storage).
      // Fall back to File path for legacy / manually-picked files.
      if (video.hasUri) {
        controller = VideoPlayerController.contentUri(Uri.parse(video.uri!));
      } else {
        controller = VideoPlayerController.file(File(video.path));
      }
      await controller.initialize();
      if (!mounted) { controller.dispose(); return; }
      await controller.setVolume(_volume);
      setState(() { _controller = controller; _initialized = true; });
      controller.addListener(_videoListener);
      controller.play();
      old?.dispose();
    } catch (e) {
      // If content URI failed, retry with raw File path as fallback
      if (video.hasUri && controller != null) {
        try {
          controller.dispose();
          final fallback = VideoPlayerController.file(File(video.path));
          await fallback.initialize();
          if (!mounted) { fallback.dispose(); return; }
          await fallback.setVolume(_volume);
          setState(() { _controller = fallback; _initialized = true; });
          fallback.addListener(_videoListener);
          fallback.play();
          old?.dispose();
          return;
        } catch (_) {}
      }
      setState(() { _errorMessage = 'Cannot play: ${e.toString().split('\n').first}'; });
      old?.dispose();
    }
  }

  void _videoListener() {
    if (!mounted) return;
    setState(() {});
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized && !ctrl.value.isPlaying &&
        ctrl.value.position >= ctrl.value.duration) _playNext();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller?.value.isPlaying == true && _gestureMode == _GestureMode.none) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onTapScreen() {
    if (_gestureMode != _GestureMode.none) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  // ── Gesture handlers ─────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails d) {
    _hideTimer?.cancel();
    _dragStartX = d.localPosition.dx;
    _dragStartY = d.localPosition.dy;
    _volumeAtDragStart = _volume;
    _brightnessAtDragStart = _brightness;
    _positionAtDragStart = _controller?.value.position ?? Duration.zero;
    _seekDeltaSeconds = 0;
  }

  void _onDragUpdate(DragUpdateDetails d, double totalWidth) {
    final dx = d.localPosition.dx - _dragStartX;
    final dy = d.localPosition.dy - _dragStartY;
    final isRightHalf = _dragStartX > totalWidth / 2;

    if (_gestureMode == _GestureMode.none) {
      if (dx.abs() < _kGestureThreshold && dy.abs() < _kGestureThreshold) return;
      if (dx.abs() > dy.abs()) {
        setState(() { _gestureMode = _GestureMode.seek; _showGestureOverlay = true; });
        _overlayFadeCtrl.forward();
      } else {
        setState(() {
          _gestureMode = isRightHalf ? _GestureMode.volume : _GestureMode.brightness;
          _showGestureOverlay = true;
        });
        _overlayFadeCtrl.forward();
      }
    }

    switch (_gestureMode) {
      case _GestureMode.seek: _handleSeek(dx); break;
      case _GestureMode.volume: _handleVolume(dy); break;
      case _GestureMode.brightness: _handleBrightness(dy); break;
      case _GestureMode.none: break;
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_gestureMode == _GestureMode.seek) {
      _controller?.seekTo(_seekPreviewPosition);
      HapticFeedback.lightImpact();
    }
    _overlayFadeCtrl.reverse().then((_) {
      if (mounted) setState(() => _showGestureOverlay = false);
    });
    setState(() => _gestureMode = _GestureMode.none);
    _scheduleHide();
  }

  void _handleSeek(double dx) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final totalMs = ctrl.value.duration.inMilliseconds;
    if (totalMs == 0) return;
    final delta = dx * _kSeekSensitivity;
    final newMs = (_positionAtDragStart.inMilliseconds + delta * 1000).clamp(0.0, totalMs.toDouble());
    setState(() { _seekDeltaSeconds = delta; _seekPreviewPosition = Duration(milliseconds: newMs.round()); });
  }

  void _handleVolume(double dy) {
    final newVol = (_volumeAtDragStart - dy * _kVertSensitivity).clamp(0.0, 1.0);
    setState(() => _volume = newVol);
    _controller?.setVolume(_volume);
  }

  void _handleBrightness(double dy) {
    final newB = (_brightnessAtDragStart - dy * _kVertSensitivity).clamp(0.0, 1.0);
    setState(() => _brightness = newB);
    // In production: ScreenBrightness().setApplicationScreenBrightness(_brightness);
  }

  void _doubleTapLeft() {
    if (_controller == null) return;
    final newPos = Duration(milliseconds: max(0, _controller!.value.position.inMilliseconds - 10000));
    _controller!.seekTo(newPos);
    HapticFeedback.lightImpact();
    _triggerRipple(false);
  }

  void _doubleTapRight() {
    if (_controller == null) return;
    final cap = _controller!.value.duration.inMilliseconds;
    final newPos = Duration(milliseconds: min(cap, _controller!.value.position.inMilliseconds + 10000));
    _controller!.seekTo(newPos);
    HapticFeedback.lightImpact();
    _triggerRipple(true);
  }

  void _triggerRipple(bool right) {
    setState(() { if (right) _showRightRipple = true; else _showLeftRipple = true; });
    _seekRippleCtrl.forward(from: 0).then((_) {
      if (mounted) setState(() { _showLeftRipple = false; _showRightRipple = false; });
    });
  }

  void _playNext() {
    if (_currentIndex < widget.playlist.length - 1) {
      setState(() => _currentIndex++);
      _initVideo(widget.playlist[_currentIndex]);
    }
  }

  void _playPrev() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _initVideo(widget.playlist[_currentIndex]);
    }
  }

  void _playAt(int i) {
    setState(() { _currentIndex = i; _showPlaylist = false; });
    _initVideo(widget.playlist[i]);
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    _overlayFadeCtrl.dispose();
    _seekRippleCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.playlist.isNotEmpty ? widget.playlist[_currentIndex] : widget.video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Column(
            children: [
              if (!_isFullscreen) _buildTopBar(video),
              Expanded(child: _buildGestureZone()),
              if (!_isFullscreen) _buildBottomSection(),
            ],
          ),
          if (_showGestureOverlay) _buildGestureOverlay(),
          if (_showLeftRipple) _buildRipple(false),
          if (_showRightRipple) _buildRipple(true),
          if (_showControls && _initialized && _isFullscreen)
            Positioned.fill(child: _buildFullscreenControls(video)),
          if (_showPlaylist)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showPlaylist = false),
                child: Container(color: Colors.black54),
              ),
            ),
          if (_showPlaylist)
            Positioned(
              right: 0, top: 0, bottom: 0,
              width: MediaQuery.of(context).size.width * 0.75,
              child: PlaylistDrawer(
                playlist: widget.playlist,
                currentIndex: _currentIndex,
                onSelect: _playAt,
                onClose: () => setState(() => _showPlaylist = false),
              ).animate().slideX(begin: 1, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
            ),
        ],
      ),
    );
  }

  Widget _buildGestureZone() {
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      return GestureDetector(
        onTap: _onTapScreen,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: (d) => _onDragUpdate(d, w),
        onVerticalDragEnd: _onDragEnd,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: (d) => _onDragUpdate(d, w),
        onHorizontalDragEnd: _onDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideo(),
            Positioned(left: 0, top: 0, bottom: 0, width: w / 2,
                child: GestureDetector(onDoubleTap: _doubleTapLeft, child: Container(color: Colors.transparent))),
            Positioned(right: 0, top: 0, bottom: 0, width: w / 2,
                child: GestureDetector(onDoubleTap: _doubleTapRight, child: Container(color: Colors.transparent))),
          ],
        ),
      );
    });
  }

  Widget _buildVideo() {
    if (_errorMessage != null) {
      return Container(color: Colors.black, child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 52),
          const SizedBox(height: 16),
          Text('Playback Error', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_errorMessage!, textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.38), fontSize: 13))),
        ]),
      ));
    }
    if (!_initialized) {
      return Container(color: Colors.black, child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
          const SizedBox(height: 16),
          Text('Loading...', style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.38), fontSize: 13)),
        ]),
      ));
    }
    return Stack(fit: StackFit.expand, children: [
      Container(color: Colors.black),
      Center(child: AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: VideoPlayer(_controller!))),
      if (_brightness < 0.99)
        IgnorePointer(child: Container(color: Colors.black.withOpacity((1 - _brightness) * 0.85))),
    ]);
  }

  Widget _buildGestureOverlay() {
    return FadeTransition(
      opacity: _overlayFadeCtrl,
      child: IgnorePointer(child: Stack(fit: StackFit.expand, children: [
        if (_gestureMode == _GestureMode.seek) _seekIndicator(),
        if (_gestureMode == _GestureMode.volume) _volumeIndicator(),
        if (_gestureMode == _GestureMode.brightness) _brightnessIndicator(),
      ])),
    );
  }

  Widget _seekIndicator() {
    final ctrl = _controller;
    if (ctrl == null) return const SizedBox();
    final total = ctrl.value.duration;
    final fwd = _seekDeltaSeconds >= 0;
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.78),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.1), blurRadius: 30)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(fwd ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded, color: AppTheme.accent, size: 30),
            const SizedBox(width: 10),
            Text('${fwd ? "+" : ""}${_seekDeltaSeconds.round()}s',
                style: GoogleFonts.spaceGrotesk(color: AppTheme.accent, fontSize: 30, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            child: Stack(children: [
              Container(height: 3, decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(2))),
              FractionallySizedBox(
                widthFactor: total.inMilliseconds > 0
                    ? (_seekPreviewPosition.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0) : 0,
                child: Container(height: 3, decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppTheme.accent, Color(0xFF0080FF)]),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.6), blurRadius: 6)],
                )),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Text('${_fmt(_seekPreviewPosition)}  /  ${_fmt(total)}',
              style: GoogleFonts.dmMono(color: Colors.white.withOpacity(0.54), fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _volumeIndicator() => Align(
    alignment: const Alignment(0.82, 0),
    child: _verticalIndicator(
      value: _volume,
      icon: _volume == 0 ? Icons.volume_off_rounded : _volume < 0.4 ? Icons.volume_down_rounded : Icons.volume_up_rounded,
      color: AppTheme.accent,
      secondColor: const Color(0xFF0055FF),
      percent: '${(_volume * 100).round()}',
    ),
  );

  Widget _brightnessIndicator() => Align(
    alignment: const Alignment(-0.82, 0),
    child: _verticalIndicator(
      value: _brightness,
      icon: _brightness < 0.3 ? Icons.brightness_2_rounded : _brightness < 0.7 ? Icons.brightness_5_rounded : Icons.brightness_7_rounded,
      color: const Color(0xFFFFBE0B),
      secondColor: const Color(0xFFFF8800),
      percent: '${(_brightness * 100).round()}',
    ),
  );

  Widget _verticalIndicator({
    required double value,
    required IconData icon,
    required Color color,
    required Color secondColor,
    required String percent,
  }) {
    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.78),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 20)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 12),
        Container(
          width: 4, height: 110,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(2)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [color, secondColor],
                  ),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 8)],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(percent, style: GoogleFonts.dmMono(color: Colors.white.withOpacity(0.70), fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildRipple(bool right) {
    return Positioned(
      left: right ? null : 0, right: right ? 0 : null,
      top: 0, bottom: 0,
      width: MediaQuery.of(context).size.width * 0.44,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _seekRippleCtrl,
          builder: (_, __) {
            final v = _seekRippleCtrl.value;
            return Stack(children: [
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.09 * (1 - v)),
                  borderRadius: BorderRadius.horizontal(
                    left: right ? Radius.zero : const Radius.circular(200),
                    right: right ? const Radius.circular(200) : Radius.zero,
                  ),
                ),
              ),
              Center(child: Opacity(
                opacity: (1 - v * 1.5).clamp(0.0, 1.0),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(right ? Icons.forward_10_rounded : Icons.replay_10_rounded,
                      color: AppTheme.accent, size: 44),
                  const SizedBox(height: 4),
                  Text(right ? '10 seconds' : '10 seconds',
                      style: GoogleFonts.dmSans(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              )),
            ]);
          },
        ),
      ),
    );
  }

  Widget _buildTopBar(VideoFile video) {
    return AnimatedSlide(
      offset: _showControls ? Offset.zero : const Offset(0, -0.3),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 280),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, left: 8, right: 8, bottom: 8),
          decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent])),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(video.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              Text('${_currentIndex + 1} of ${widget.playlist.length}',
                  style: GoogleFonts.dmMono(color: Colors.white.withOpacity(0.38), fontSize: 11)),
            ])),
            // Gesture hint row
            Row(mainAxisSize: MainAxisSize.min, children: [
              _hintChip(Icons.brightness_medium_rounded, const Color(0xFFFFBE0B), 'Brightness'),
              const SizedBox(width: 4),
              _hintChip(Icons.swap_horiz_rounded, AppTheme.accent, 'Seek'),
              const SizedBox(width: 4),
              _hintChip(Icons.volume_up_rounded, AppTheme.accent, 'Volume'),
            ]),
            IconButton(icon: const Icon(Icons.queue_music_rounded, color: Colors.white70),
                onPressed: () => setState(() => _showPlaylist = !_showPlaylist)),
          ]),
        ),
      ),
    );
  }

  Widget _hintChip(IconData icon, Color color, String tip) => Tooltip(
    message: tip,
    child: Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, color: color.withOpacity(0.7), size: 13),
    ),
  );

  Widget _buildBottomSection() {
    return AnimatedSlide(
      offset: _showControls ? Offset.zero : const Offset(0, 0.3),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 280),
        child: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87, Colors.black])),
            child: PlayerControls(
              controller: _controller,
              onPrev: _currentIndex > 0 ? _playPrev : null,
              onNext: _currentIndex < widget.playlist.length - 1 ? _playNext : null,
              onFullscreen: _toggleFullscreen,
              isFullscreen: _isFullscreen,
              volume: _volume,
              onVolumeChanged: (v) { setState(() => _volume = v); _controller?.setVolume(v); },
              seekPreviewPosition: _gestureMode == _GestureMode.seek ? _seekPreviewPosition : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenControls(VideoFile video) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          stops: const [0, 0.3, 0.7, 1],
          colors: [Colors.black.withOpacity(0.7), Colors.transparent, Colors.transparent, Colors.black.withOpacity(0.9)])),
      child: Column(children: [
        _buildTopBar(video),
        const Spacer(),
        PlayerControls(
          controller: _controller,
          onPrev: _currentIndex > 0 ? _playPrev : null,
          onNext: _currentIndex < widget.playlist.length - 1 ? _playNext : null,
          onFullscreen: _toggleFullscreen,
          isFullscreen: _isFullscreen,
          volume: _volume,
          onVolumeChanged: (v) { setState(() => _volume = v); _controller?.setVolume(v); },
          seekPreviewPosition: _gestureMode == _GestureMode.seek ? _seekPreviewPosition : null,
        ),
      ]),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}