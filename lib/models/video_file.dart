class VideoFile {
  final String path;
  final String name;
  final String extension;
  final int sizeBytes;
  final Duration? duration;

  /// Content URI from MediaStore e.g. content://media/external/video/media/42
  /// Use this for VideoPlayerController.contentUri() on Android 10+
  final String? uri;

  const VideoFile({
    required this.path,
    required this.name,
    required this.extension,
    this.sizeBytes = 0,
    this.duration,
    this.uri,
  });

  /// True when a MediaStore content URI is available
  bool get hasUri => uri != null && uri!.isNotEmpty;

  /// Friendly file-size string e.g. "2.4 GB" or "780 MB"
  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).round()} MB';
  }

  /// Extension uppercased e.g. "MP4"
  String get extLabel => extension.toUpperCase().replaceAll('.', '');

  /// Duration formatted as mm:ss or h:mm:ss
  String get durationLabel {
    final d = duration;
    if (d == null) return '';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  String toString() => 'VideoFile(name: $name, uri: $uri, path: $path)';
}