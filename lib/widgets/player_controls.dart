import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';

class PlayerControls extends StatefulWidget {
  final VideoPlayerController? controller;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onFullscreen;
  final bool isFullscreen;
  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final Duration? seekPreviewPosition;

  const PlayerControls({
    super.key,
    required this.controller,
    required this.onPrev,
    required this.onNext,
    required this.onFullscreen,
    required this.isFullscreen,
    this.volume = 1.0,
    required this.onVolumeChanged,
    this.seekPreviewPosition,
  });

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls>
    with TickerProviderStateMixin {
  double _playbackSpeed = 1.0;
  bool _showSpeedMenu = false;
  bool _isDraggingBar = false;

  // ── Animation controllers ──────────────────────────────────────────────────

  // Play/pause button: scale pulse on tap
  late AnimationController _playPulseCtrl;
  late Animation<double> _playPulseAnim;

  // Play/pause icon: flip transition
  late AnimationController _iconFlipCtrl;
  late Animation<double> _iconFlipAnim;
  bool _wasPlaying = false;

  // Speed menu: slide + fade
  late AnimationController _speedMenuCtrl;
  late Animation<double> _speedMenuFade;
  late Animation<Offset> _speedMenuSlide;

  // Progress bar: height expands when dragging
  late AnimationController _barExpandCtrl;
  late Animation<double> _barHeightAnim;
  late Animation<double> _thumbScaleAnim;

  // Entire controls: slide up on appear
  late AnimationController _appearCtrl;
  late Animation<Offset> _appearSlide;
  late Animation<double> _appearFade;

  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  VideoPlayerController? get ctrl => widget.controller;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Play pulse
    _playPulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _playPulseAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.82), weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 0.82, end: 1.08)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 60),
    ]).animate(_playPulseCtrl);

    // Icon flip
    _iconFlipCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _iconFlipAnim = Tween(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _iconFlipCtrl, curve: Curves.easeInOut));

    // Speed menu
    _speedMenuCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _speedMenuFade =
        CurvedAnimation(parent: _speedMenuCtrl, curve: Curves.easeOut);
    _speedMenuSlide = Tween(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _speedMenuCtrl, curve: Curves.easeOutCubic));

    // Progress bar expand
    _barExpandCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _barHeightAnim = Tween(begin: 3.0, end: 5.0)
        .animate(CurvedAnimation(parent: _barExpandCtrl, curve: Curves.easeOut));
    _thumbScaleAnim = Tween(begin: 1.0, end: 1.5)
        .animate(CurvedAnimation(parent: _barExpandCtrl, curve: Curves.easeOut));

    // Appear slide
    _appearCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _appearSlide = Tween(begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(CurvedAnimation(parent: _appearCtrl, curve: Curves.easeOutCubic));
    _appearFade =
        CurvedAnimation(parent: _appearCtrl, curve: Curves.easeOut);
    _appearCtrl.forward();
  }

  @override
  void didUpdateWidget(PlayerControls old) {
    super.didUpdateWidget(old);
    final isPlaying = widget.controller?.value.isPlaying ?? false;
    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      // Flip icon
      if (isPlaying) {
        _iconFlipCtrl.forward(from: 0);
      } else {
        _iconFlipCtrl.reverse(from: 1);
      }
    }
  }

  @override
  void dispose() {
    _playPulseCtrl.dispose();
    _iconFlipCtrl.dispose();
    _speedMenuCtrl.dispose();
    _barExpandCtrl.dispose();
    _appearCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _onBarDragStart() {
    setState(() => _isDraggingBar = true);
    _barExpandCtrl.forward();
  }

  void _onBarDragEnd() {
    setState(() => _isDraggingBar = false);
    _barExpandCtrl.reverse();
  }

  void _toggleSpeedMenu() {
    setState(() => _showSpeedMenu = !_showSpeedMenu);
    if (_showSpeedMenu) {
      _speedMenuCtrl.forward(from: 0);
    } else {
      _speedMenuCtrl.reverse();
    }
  }

  void _onPlayTap() {
    if (ctrl == null) return;
    HapticFeedback.lightImpact();
    _playPulseCtrl.forward(from: 0);
    ctrl!.value.isPlaying ? ctrl!.pause() : ctrl!.play();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final value = ctrl?.value;
    final isPlaying = value?.isPlaying ?? false;
    final position = widget.seekPreviewPosition ?? (value?.position ?? Duration.zero);
    final duration = value?.duration ?? Duration.zero;
    final buffered = value?.buffered ?? [];
    final bufferedEnd = buffered.isNotEmpty ? buffered.last.end : Duration.zero;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final bufferedProgress = duration.inMilliseconds > 0
        ? (bufferedEnd.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return FadeTransition(
      opacity: _appearFade,
      child: SlideTransition(
        position: _appearSlide,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16, top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildProgressBar(progress, bufferedProgress, position, duration),
              const SizedBox(height: 12),
              _buildControlsRow(isPlaying, position, duration),
              // Speed menu with animated reveal
              if (_showSpeedMenu)
                SlideTransition(
                  position: _speedMenuSlide,
                  child: FadeTransition(
                    opacity: _speedMenuFade,
                    child: _buildSpeedMenu(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Controls row ───────────────────────────────────────────────────────────

  Widget _buildControlsRow(bool isPlaying, Duration position, Duration duration) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _IconBtn(icon: Icons.skip_previous_rounded, size: 24,
            onTap: widget.onPrev, disabled: widget.onPrev == null),

        _IconBtn(icon: Icons.replay_10_rounded, size: 22,
            onTap: () => ctrl?.seekTo(position - const Duration(seconds: 10))),

        // ── Play / Pause ────────────────────────────────────────────────────
        ScaleTransition(
          scale: _playPulseAnim,
          child: GestureDetector(
            onTap: _onPlayTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withOpacity(isPlaying ? 0.55 : 0.25),
                    blurRadius: isPlaying ? 24 : 12,
                    spreadRadius: isPlaying ? 3 : 1,
                  ),
                ],
              ),
              // AnimatedSwitcher flips between play and pause icons
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(isPlaying),
                  color: Colors.black,
                  size: 28,
                ),
              ),
            ),
          ),
        ),

        _IconBtn(icon: Icons.forward_10_rounded, size: 22,
            onTap: () => ctrl?.seekTo(position + const Duration(seconds: 10))),

        _IconBtn(icon: Icons.skip_next_rounded, size: 24,
            onTap: widget.onNext, disabled: widget.onNext == null),

        _buildSpeedButton(),

        _IconBtn(
          icon: widget.volume == 0
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
          size: 20,
          onTap: () => widget.onVolumeChanged(widget.volume > 0 ? 0.0 : 1.0),
        ),

        _IconBtn(
          icon: widget.isFullscreen
              ? Icons.screen_rotation_rounded
              : Icons.screen_rotation_outlined,
          size: 18,
          onTap: widget.onFullscreen,
        ),
      ],
    );
  }

  // ── Progress bar ───────────────────────────────────────────────────────────

  Widget _buildProgressBar(double progress, double buffered, Duration pos, Duration dur) {
    return Column(
      children: [
        // Timestamps — animate colour when dragging
        Row(
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: GoogleFonts.dmMono(
                color: _isDraggingBar
                    ? AppTheme.accent
                    : Colors.white.withOpacity(0.60),
                fontSize: 11,
                fontWeight: _isDraggingBar ? FontWeight.w700 : FontWeight.w400,
              ),
              child: Text(_fmt(pos)),
            ),
            const Spacer(),
            Text(_fmt(dur),
                style: GoogleFonts.dmMono(
                    color: Colors.white.withOpacity(0.38), fontSize: 11)),
          ],
        ),
        const SizedBox(height: 6),

        // Bar + thumb
        GestureDetector(
          onHorizontalDragStart: (_) => _onBarDragStart(),
          onHorizontalDragUpdate: (d) {
            if (ctrl == null || dur.inMilliseconds == 0) return;
            final box = context.findRenderObject() as RenderBox;
            final w = box.size.width - 32;
            final dx = d.localPosition.dx.clamp(0.0, w);
            ctrl!.seekTo(Duration(
                milliseconds: (dx / w * dur.inMilliseconds).round()));
          },
          onHorizontalDragEnd: (_) => _onBarDragEnd(),
          onTapDown: (d) {
            if (ctrl == null || dur.inMilliseconds == 0) return;
            final box = context.findRenderObject() as RenderBox;
            final w = box.size.width - 32;
            final dx = d.localPosition.dx.clamp(0.0, w);
            ctrl!.seekTo(Duration(
                milliseconds: (dx / w * dur.inMilliseconds).round()));
          },
          child: AnimatedBuilder(
            animation: _barExpandCtrl,
            builder: (_, __) {
              final barH = _barHeightAnim.value;
              final thumbScale = _thumbScaleAnim.value;
              final thumbSize = 12.0 * thumbScale;

              return SizedBox(
                height: 20,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Track
                      Container(
                        height: barH,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(barH),
                        ),
                      ),
                      // Buffered
                      FractionallySizedBox(
                        widthFactor: buffered,
                        child: Container(
                          height: barH,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(barH),
                          ),
                        ),
                      ),
                      // Progress
                      FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          height: barH,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [AppTheme.accent, Color(0xFF0080FF)]),
                            borderRadius: BorderRadius.circular(barH),
                            boxShadow: [
                              BoxShadow(
                                  color: AppTheme.accent.withOpacity(0.5),
                                  blurRadius: 6)
                            ],
                          ),
                        ),
                      ),
                      // Thumb
                      Positioned(
                        left: (progress *
                            (MediaQuery.of(context).size.width - 64))
                            .clamp(0, double.infinity) -
                            thumbSize / 2,
                        top: -(thumbSize - barH) / 2,
                        child: Container(
                          width: thumbSize,
                          height: thumbSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.accent,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accent
                                    .withOpacity(_isDraggingBar ? 0.8 : 0.5),
                                blurRadius: _isDraggingBar ? 14 : 8,
                                spreadRadius: _isDraggingBar ? 2 : 0,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Speed button ───────────────────────────────────────────────────────────

  Widget _buildSpeedButton() {
    return GestureDetector(
      onTap: _toggleSpeedMenu,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _showSpeedMenu
              ? AppTheme.accent
              : Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
          boxShadow: _showSpeedMenu
              ? [BoxShadow(color: AppTheme.accent.withOpacity(0.4), blurRadius: 10)]
              : [],
        ),
        child: Text(
          '${_playbackSpeed}x',
          style: GoogleFonts.dmMono(
            color: _showSpeedMenu ? Colors.black : Colors.white.withOpacity(0.70),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Speed menu ─────────────────────────────────────────────────────────────

  Widget _buildSpeedMenu() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surface),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 4))
          ],
        ),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _speeds.map((s) {
            final selected = s == _playbackSpeed;
            return _SpeedChip(
              speed: s,
              selected: selected,
              onTap: () {
                setState(() {
                  _playbackSpeed = s;
                  _showSpeedMenu = false;
                });
                _speedMenuCtrl.reverse();
                ctrl?.setPlaybackSpeed(s);
                HapticFeedback.selectionClick();
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated icon button — bounces on tap
// ─────────────────────────────────────────────────────────────────────────────

class _IconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool disabled;

  const _IconBtn({
    required this.icon,
    this.onTap,
    this.size = 24,
    this.disabled = false,
  });

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 160));
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.72), weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 0.72, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 60),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    if (widget.disabled || widget.onTap == null) return;
    HapticFeedback.lightImpact();
    _ctrl.forward(from: 0);
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: ScaleTransition(
        scale: _scale,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: widget.disabled ? 0.15 : 0.70,
            child: Icon(widget.icon,
                color: Colors.white, size: widget.size),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Speed chip — animated selection
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedChip extends StatefulWidget {
  final double speed;
  final bool selected;
  final VoidCallback onTap;

  const _SpeedChip({
    required this.speed,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SpeedChip> createState() => _SpeedChipState();
}

class _SpeedChipState extends State<_SpeedChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 130));
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.85), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.0), weight: 60),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _ctrl.forward(from: 0);
        widget.onTap();
      },
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.selected ? AppTheme.accent : AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: widget.selected
                ? [BoxShadow(
                color: AppTheme.accent.withOpacity(0.35),
                blurRadius: 8)]
                : [],
          ),
          child: Text(
            '${widget.speed}x',
            style: GoogleFonts.dmMono(
              color: widget.selected ? Colors.black : Colors.white.withOpacity(0.70),
              fontSize: 12,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}