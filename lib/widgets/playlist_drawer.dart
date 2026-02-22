import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/video_file.dart';
import '../theme/app_theme.dart';

class PlaylistDrawer extends StatelessWidget {
  final List<VideoFile> playlist;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  const PlaylistDrawer({
    super.key,
    required this.playlist,
    required this.currentIndex,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(left: BorderSide(color: AppTheme.surface)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 8,
              bottom: 16,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.surface)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PLAYLIST',
                        style: GoogleFonts.dmMono(
                          color: AppTheme.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${playlist.length} videos',
                        style: GoogleFonts.dmSans(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary, size: 20),
                ),
              ],
            ),
          ),

          // ── List ────────────────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: playlist.length,
              itemBuilder: (_, i) => _PlaylistItem(
                video: playlist[i],
                index: i,
                isCurrent: i == currentIndex,
                onTap: () => onSelect(i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistItem extends StatelessWidget {
  final VideoFile video;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;

  const _PlaylistItem({
    required this.video,
    required this.index,
    required this.isCurrent,
    required this.onTap,
  });

  // Colour per extension
  Color _extColor() {
    switch (video.extLabel) {
      case 'MKV': return AppTheme.purple;
      case 'AVI': return AppTheme.error;
      case 'MOV': return AppTheme.warning;
      default:    return AppTheme.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _extColor();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isCurrent ? AppTheme.surface.withOpacity(0.6) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isCurrent ? Border.all(color: AppTheme.accent.withOpacity(0.3)) : null,
        ),
        child: Row(
          children: [
            // Thumbnail / icon
            Container(
              width: 48,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              child: isCurrent
                  ? Icon(Icons.play_arrow_rounded, color: AppTheme.accent, size: 22)
                  : Center(
                child: Text(
                  video.extLabel,
                  style: GoogleFonts.dmMono(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Title + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      color: isCurrent ? AppTheme.textPrimary : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (video.durationLabel.isNotEmpty || video.sizeLabel.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (video.durationLabel.isNotEmpty)
                          Text(
                            video.durationLabel,
                            style: GoogleFonts.dmMono(
                              color: AppTheme.textMuted,
                              fontSize: 9,
                            ),
                          ),
                        if (video.durationLabel.isNotEmpty && video.sizeLabel.isNotEmpty)
                          Text(
                            '  ·  ',
                            style: GoogleFonts.dmMono(color: AppTheme.textMuted, fontSize: 9),
                          ),
                        if (video.sizeLabel.isNotEmpty)
                          Text(
                            video.sizeLabel,
                            style: GoogleFonts.dmMono(
                              color: AppTheme.textMuted,
                              fontSize: 9,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Playing indicator
            if (isCurrent)
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.5), blurRadius: 6)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}