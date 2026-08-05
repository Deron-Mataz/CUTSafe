import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

/// EXTEND: tapping a chat image/video now opens this fullscreen viewer
/// instead of doing nothing.
class FullscreenImageViewer extends StatelessWidget {
  final String imageUrl;
  const FullscreenImageViewer({super.key, required this.imageUrl});

  static void show(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FullscreenImageViewer(imageUrl: url),
      fullscreenDialog: true,
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
    body: Center(
      child: InteractiveViewer(
        minScale: 0.5, maxScale: 4,
        child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(color: Colors.white),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
      ),
    ),
  );
}

/// EXTEND: fullscreen video playback using the video_player package.
class FullscreenVideoViewer extends StatefulWidget {
  final String videoUrl;
  const FullscreenVideoViewer({super.key, required this.videoUrl});

  static void show(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FullscreenVideoViewer(videoUrl: url),
      fullscreenDialog: true,
    ));
  }

  @override
  State<FullscreenVideoViewer> createState() => _FullscreenVideoViewerState();
}

class _FullscreenVideoViewerState extends State<FullscreenVideoViewer> {
  late final VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
        _ctrl.play();
      }).catchError((_) {
        if (mounted) setState(() => _error = true);
      });
    _ctrl.setLooping(false);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
    body: Center(
      child: _error
          ? const Icon(Icons.error_outline, color: Colors.white54, size: 48)
          : !_initialized
              ? const CircularProgressIndicator(color: Colors.white)
              : GestureDetector(
                  onTap: () => setState(() => _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play()),
                  child: AspectRatio(
                    aspectRatio: _ctrl.value.aspectRatio,
                    child: Stack(alignment: Alignment.center, children: [
                      VideoPlayer(_ctrl),
                      if (!_ctrl.value.isPlaying)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                        ),
                    ]),
                  ),
                ),
    ),
    bottomNavigationBar: _initialized
        ? VideoProgressIndicator(_ctrl, allowScrubbing: true,
            colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white24, backgroundColor: Colors.white10))
        : null,
  );
}
