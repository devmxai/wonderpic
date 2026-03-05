import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class WonderPicVideoEditingScreen extends StatefulWidget {
  const WonderPicVideoEditingScreen({super.key});

  @override
  State<WonderPicVideoEditingScreen> createState() =>
      _WonderPicVideoEditingScreenState();
}

enum _VideoEditTool {
  add,
  move,
  crop,
  text,
  erase,
  draw,
  clone,
  shape,
  grid,
}

enum _TimelineDragMode {
  none,
  scrub,
  moveSelection,
}

class _VideoToolAction {
  const _VideoToolAction({
    required this.id,
    required this.icon,
  });

  final _VideoEditTool id;
  final IconData icon;
}

class _TimelineClip {
  _TimelineClip({
    required this.id,
    required this.label,
    required this.startSecond,
    required this.durationSecond,
    required this.color,
  });

  final String id;
  final String label;
  double startSecond;
  final double durationSecond;
  final Color color;
}

class _TimelineTrack {
  _TimelineTrack({
    required this.id,
    required this.name,
    required this.icon,
    required this.clips,
  });

  final String id;
  final String name;
  final IconData icon;
  final List<_TimelineClip> clips;
}

enum _AddLayerAction {
  video,
  image,
  text,
  overlay,
  adjustment,
}

class _WonderPicVideoEditingScreenState
    extends State<WonderPicVideoEditingScreen> {
  static const Color _pageBg = Color(0xFF242833);
  static const Color _panelBg = Color(0xFF191D26);
  static const Color _panelBorder = Color(0xFF2C3241);
  static const Color _toolIdleBg = Color(0xFF161A22);
  static const Color _textMain = Color(0xFFF3F4F6);
  static const Color _textSub = Color(0xFFA5ACB8);
  static const Color _accent = Color(0xFFE6F24A);

  static const double _defaultTimelineSeconds = 30.0;
  static const double _timelineBasePixelsPerSecond = 30.0;
  static const double _timelineMinZoom = 0.30;
  static const double _timelineMaxZoom = 4.0;
  static const double _timelineRulerHeight = 16.0;
  static const double _trackLabelWidth = 40.0;
  static const double _trackLaneGap = 4.0;
  static const double _trackRowHeight = 38.0;
  static const double _clipTopInset = 4.0;
  static const double _timelineScrubSensitivity = 1.0;

  final List<_VideoToolAction> _tools = const <_VideoToolAction>[
    _VideoToolAction(
      id: _VideoEditTool.add,
      icon: Icons.add_rounded,
    ),
    _VideoToolAction(
      id: _VideoEditTool.move,
      icon: Icons.open_with_rounded,
    ),
    _VideoToolAction(
      id: _VideoEditTool.crop,
      icon: Icons.crop_rounded,
    ),
    _VideoToolAction(
      id: _VideoEditTool.text,
      icon: Icons.text_fields_rounded,
    ),
    _VideoToolAction(
      id: _VideoEditTool.erase,
      icon: Icons.auto_fix_off_rounded,
    ),
    _VideoToolAction(
      id: _VideoEditTool.draw,
      icon: Icons.edit_rounded,
    ),
    _VideoToolAction(
      id: _VideoEditTool.clone,
      icon: Icons.copy_all_rounded,
    ),
    _VideoToolAction(
      id: _VideoEditTool.shape,
      icon: Icons.crop_square_rounded,
    ),
    _VideoToolAction(
      id: _VideoEditTool.grid,
      icon: Icons.grid_view_rounded,
    ),
  ];

  final List<_TimelineTrack> _tracks = <_TimelineTrack>[
    _TimelineTrack(
      id: 'video',
      name: 'Video',
      icon: Icons.videocam_rounded,
      clips: <_TimelineClip>[
        _TimelineClip(
          id: 'video_main',
          label: 'Main Clip',
          startSecond: 0,
          durationSecond: 15,
          color: const Color(0xFF4F8CFF),
        ),
        _TimelineClip(
          id: 'video_broll',
          label: 'B-Roll',
          startSecond: 16,
          durationSecond: 11,
          color: const Color(0xFF6AA8FF),
        ),
      ],
    ),
    _TimelineTrack(
      id: 'sound',
      name: 'Sound',
      icon: Icons.graphic_eq_rounded,
      clips: <_TimelineClip>[
        _TimelineClip(
          id: 'sound_ambient',
          label: 'Ambient',
          startSecond: 0,
          durationSecond: 30,
          color: const Color(0xFF44D1C8),
        ),
      ],
    ),
    _TimelineTrack(
      id: 'text',
      name: 'Text',
      icon: Icons.text_fields_rounded,
      clips: <_TimelineClip>[
        _TimelineClip(
          id: 'text_title',
          label: 'Title',
          startSecond: 2,
          durationSecond: 7,
          color: const Color(0xFFBF7AFF),
        ),
        _TimelineClip(
          id: 'text_lower_third',
          label: 'Lower Third',
          startSecond: 17,
          durationSecond: 9,
          color: const Color(0xFFD092FF),
        ),
      ],
    ),
    _TimelineTrack(
      id: 'overlay',
      name: 'Overlay',
      icon: Icons.layers_rounded,
      clips: <_TimelineClip>[
        _TimelineClip(
          id: 'overlay_logo',
          label: 'Logo',
          startSecond: 1,
          durationSecond: 28,
          color: const Color(0xFFFF9A50),
        ),
      ],
    ),
    _TimelineTrack(
      id: 'adjustment',
      name: 'Adjustment',
      icon: Icons.tune_rounded,
      clips: <_TimelineClip>[],
    ),
  ];

  _VideoEditTool _activeTool = _VideoEditTool.move;
  _TimelineDragMode _dragMode = _TimelineDragMode.none;
  int? _dragTrackIndex;
  final List<String> _selectedClipIds = <String>[];
  bool _isTimelineScaleGesture = false;
  double _timelineZoom = 1.0;
  double _scaleGestureStartZoom = 1.0;
  final Map<String, double> _selectionDragBaseStarts = <String, double>{};
  double _selectionDragRequestedDelta = 0.0;
  double _selectionGroupMinDelta = 0.0;
  double _selectionGroupMaxDelta = 0.0;
  VideoPlayerController? _videoController;
  bool _isLoadingVideo = false;
  bool _isPlaying = false;
  String? _videoPath;
  int _clipSeed = 0;
  int _videoLoadToken = 0;
  int _lastRenderedPositionMs = -1000;
  bool _seekInFlight = false;
  double? _pendingSeekSecond;
  bool _hasClearedMockTimeline = false;

  double _timelineCenterSecond = 0.0;

  double get _timelineSeconds {
    double value = _defaultTimelineSeconds;
    final VideoPlayerController? controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      final double videoSeconds =
          controller.value.duration.inMilliseconds / 1000.0;
      if (videoSeconds.isFinite && videoSeconds > 0.0) {
        value = videoSeconds;
      }
    }
    for (final _TimelineTrack track in _tracks) {
      for (final _TimelineClip clip in track.clips) {
        value = math.max(value, clip.startSecond + clip.durationSecond);
      }
    }
    return value;
  }

  double get _pixelsPerSecond => _timelineBasePixelsPerSecond * _timelineZoom;
  double get _timelineCanvasWidth => _timelineSeconds * _pixelsPerSecond;

  double _timelineContentOffsetPx(double laneViewportWidth) {
    return (laneViewportWidth / 2) - (_timelineCenterSecond * _pixelsPerSecond);
  }

  double _timeFromLaneDx({
    required double localDx,
    required double laneViewportWidth,
  }) {
    return (localDx - _timelineContentOffsetPx(laneViewportWidth)) /
        _pixelsPerSecond;
  }

  @override
  void dispose() {
    final VideoPlayerController? controller = _videoController;
    if (controller != null) {
      controller.removeListener(_onVideoControllerTick);
      controller.dispose();
    }
    super.dispose();
  }

  _TimelineTrack _trackById(String trackId) {
    return _tracks.firstWhere((_) => _.id == trackId);
  }

  double _clampTimelineSecond(double seconds) {
    return seconds.clamp(0.0, _timelineSeconds).toDouble();
  }

  Duration _durationFromSecond(double second) {
    final int millis = (_clampTimelineSecond(second) * 1000).round();
    return Duration(milliseconds: millis);
  }

  void _onVideoControllerTick() {
    final VideoPlayerController? controller = _videoController;
    if (controller == null || !mounted) return;
    final VideoPlayerValue value = controller.value;
    if (!value.isInitialized) return;
    final int durationMs = value.duration.inMilliseconds;
    if (durationMs <= 0) return;
    final int positionMs = value.position.inMilliseconds.clamp(0, durationMs);
    final bool playingNow = value.isPlaying;
    final bool shouldRefreshPosition =
        (positionMs - _lastRenderedPositionMs).abs() >= 16;
    if (!shouldRefreshPosition && playingNow == _isPlaying) return;
    _lastRenderedPositionMs = positionMs;
    final double second = positionMs / 1000.0;
    setState(() {
      _timelineCenterSecond = _clampTimelineSecond(second);
      _isPlaying = playingNow;
    });
  }

  Future<void> _disposeVideoController(
      VideoPlayerController? controller) async {
    if (controller == null) return;
    controller.removeListener(_onVideoControllerTick);
    await controller.dispose();
  }

  Future<void> _loadVideoFile(String path) async {
    final int token = ++_videoLoadToken;
    final VideoPlayerController? oldController = _videoController;
    setState(() {
      _isLoadingVideo = true;
      _isPlaying = false;
      _videoPath = path;
      _pendingSeekSecond = null;
      _seekInFlight = false;
    });
    if (oldController != null) {
      await _disposeVideoController(oldController);
    }
    final VideoPlayerController nextController = VideoPlayerController.file(
      File(path),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
      ),
    );
    try {
      await nextController.initialize();
      if (!mounted || token != _videoLoadToken) {
        await nextController.dispose();
        return;
      }
      nextController.setLooping(false);
      nextController.addListener(_onVideoControllerTick);
      setState(() {
        _videoController = nextController;
        _timelineCenterSecond = 0.0;
        _isLoadingVideo = false;
        _isPlaying = false;
        _lastRenderedPositionMs = -1000;
      });
      await _queueVideoSeek(0.0);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
          _isPlaying = false;
          _videoController = null;
        });
      }
      await nextController.dispose();
    }
  }

  Future<void> _togglePlayPause() async {
    final VideoPlayerController? controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
      }
      return;
    }
    final double startSecond =
        _timelineCenterSecond >= (_timelineSeconds - 0.05)
            ? 0.0
            : _timelineCenterSecond;
    await controller.seekTo(_durationFromSecond(startSecond));
    await controller.play();
    if (mounted) {
      setState(() {
        _timelineCenterSecond = _clampTimelineSecond(startSecond);
        _isPlaying = true;
      });
    }
  }

  Future<void> _pausePlaybackForScrub() async {
    final VideoPlayerController? controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isPlaying) return;
    await controller.pause();
    if (mounted) {
      setState(() {
        _isPlaying = false;
      });
    }
  }

  Future<void> _queueVideoSeek(double second) async {
    final VideoPlayerController? controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    _pendingSeekSecond = _clampTimelineSecond(second);
    if (_seekInFlight) return;
    _seekInFlight = true;
    try {
      while (_pendingSeekSecond != null) {
        final double target = _pendingSeekSecond!;
        _pendingSeekSecond = null;
        await controller.seekTo(_durationFromSecond(target));
      }
    } catch (_) {
      // Ignore seek race errors from rapid gesture updates.
    } finally {
      _seekInFlight = false;
    }
  }

  String _basename(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final int index = normalized.lastIndexOf('/');
    if (index == -1 || index >= normalized.length - 1) return path;
    return normalized.substring(index + 1);
  }

  String _newClipId(String prefix) {
    _clipSeed += 1;
    return '${prefix}_$_clipSeed';
  }

  void _clearMockTimelineIfNeeded() {
    if (_hasClearedMockTimeline) return;
    for (final _TimelineTrack track in _tracks) {
      track.clips.clear();
    }
    _selectedClipIds.clear();
    _hasClearedMockTimeline = true;
  }

  void _addClipToTrack({
    required String trackId,
    required String label,
    required Color color,
    required double durationSecond,
  }) {
    final _TimelineTrack track = _trackById(trackId);
    final double clampedDuration = math.max(0.25, durationSecond);
    final double maxStart = math.max(0.0, _timelineSeconds - clampedDuration);
    final double startSecond = _timelineCenterSecond.clamp(0.0, maxStart);
    track.clips.add(
      _TimelineClip(
        id: _newClipId(trackId),
        label: label,
        startSecond: startSecond.toDouble(),
        durationSecond: clampedDuration,
        color: color,
      ),
    );
    track.clips.sort(
      (_TimelineClip a, _TimelineClip b) =>
          a.startSecond.compareTo(b.startSecond),
    );
  }

  Future<void> _handleAddLayerAction(_AddLayerAction action) async {
    switch (action) {
      case _AddLayerAction.video:
        final FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: false,
        );
        if (result == null || result.files.isEmpty) return;
        final String? path = result.files.single.path;
        if (path == null || path.isEmpty) return;
        await _loadVideoFile(path);
        if (!mounted) return;
        setState(() {
          _clearMockTimelineIfNeeded();
          final double videoDuration =
              _videoController != null && _videoController!.value.isInitialized
                  ? _videoController!.value.duration.inMilliseconds / 1000.0
                  : 10.0;
          _addClipToTrack(
            trackId: 'video',
            label: _basename(path),
            color: const Color(0xFF4F8CFF),
            durationSecond: math.max(1.0, videoDuration),
          );
        });
        return;
      case _AddLayerAction.image:
        final FilePickerResult? imageResult =
            await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        if (imageResult == null || imageResult.files.isEmpty) return;
        final String? imagePath = imageResult.files.single.path;
        if (imagePath == null || imagePath.isEmpty) return;
        if (!mounted) return;
        setState(() {
          _clearMockTimelineIfNeeded();
          _addClipToTrack(
            trackId: 'overlay',
            label: _basename(imagePath),
            color: const Color(0xFFFF9A50),
            durationSecond: 5.0,
          );
        });
        return;
      case _AddLayerAction.text:
        if (!mounted) return;
        setState(() {
          _clearMockTimelineIfNeeded();
          _addClipToTrack(
            trackId: 'text',
            label: 'Text',
            color: const Color(0xFFBF7AFF),
            durationSecond: 4.0,
          );
        });
        return;
      case _AddLayerAction.overlay:
        if (!mounted) return;
        setState(() {
          _clearMockTimelineIfNeeded();
          _addClipToTrack(
            trackId: 'overlay',
            label: 'Overlay',
            color: const Color(0xFFFF9A50),
            durationSecond: 4.5,
          );
        });
        return;
      case _AddLayerAction.adjustment:
        if (!mounted) return;
        setState(() {
          _clearMockTimelineIfNeeded();
          _addClipToTrack(
            trackId: 'adjustment',
            label: 'Adjustment',
            color: const Color(0xFF7AA4FF),
            durationSecond: 6.0,
          );
        });
        return;
    }
  }

  int? _clipIndexAtPosition({
    required int trackIndex,
    required double localDx,
    required double laneViewportWidth,
  }) {
    if (trackIndex < 0 || trackIndex >= _tracks.length) return null;
    final List<_TimelineClip> clips = _tracks[trackIndex].clips;
    if (clips.isEmpty) return null;
    final double touchSecond = _timeFromLaneDx(
      localDx: localDx,
      laneViewportWidth: laneViewportWidth,
    );
    for (int i = clips.length - 1; i >= 0; i--) {
      final _TimelineClip clip = clips[i];
      final double start = clip.startSecond;
      final double end = clip.startSecond + clip.durationSecond;
      if (touchSecond >= start && touchSecond <= end) {
        return i;
      }
    }
    return null;
  }

  _TimelineClip? _findClipById(String clipId) {
    for (final _TimelineTrack track in _tracks) {
      for (final _TimelineClip clip in track.clips) {
        if (clip.id == clipId) return clip;
      }
    }
    return null;
  }

  bool _isClipSelected(_TimelineClip clip) {
    return _selectedClipIds.contains(clip.id);
  }

  List<_TimelineClip> _selectedClips() {
    final List<_TimelineClip> selected = <_TimelineClip>[];
    for (final String clipId in _selectedClipIds) {
      final _TimelineClip? clip = _findClipById(clipId);
      if (clip != null) {
        selected.add(clip);
      }
    }
    return selected;
  }

  void _toggleClipSelection(_TimelineClip clip) {
    if (_selectedClipIds.contains(clip.id)) {
      _selectedClipIds.remove(clip.id);
      return;
    }
    if (_selectedClipIds.length >= 2) {
      _selectedClipIds.removeAt(0);
    }
    _selectedClipIds.add(clip.id);
  }

  void _prepareSelectionDragState() {
    _selectionDragBaseStarts.clear();
    _selectionDragRequestedDelta = 0.0;
    _selectionGroupMinDelta = 0.0;
    _selectionGroupMaxDelta = 0.0;
    final List<_TimelineClip> selected = _selectedClips();
    if (selected.isEmpty) return;

    double minStart = double.infinity;
    double maxEnd = -double.infinity;
    for (final _TimelineClip clip in selected) {
      _selectionDragBaseStarts[clip.id] = clip.startSecond;
      minStart = math.min(minStart, clip.startSecond);
      maxEnd = math.max(maxEnd, clip.startSecond + clip.durationSecond);
    }
    _selectionGroupMinDelta = -minStart;
    _selectionGroupMaxDelta = _timelineSeconds - maxEnd;
  }

  void _onTrackDoubleTapDown({
    required int trackIndex,
    required double localDx,
    required double laneViewportWidth,
  }) {
    final int? clipIndex = _clipIndexAtPosition(
      trackIndex: trackIndex,
      localDx: localDx,
      laneViewportWidth: laneViewportWidth,
    );
    setState(() {
      if (clipIndex == null) return;
      final _TimelineClip clip = _tracks[trackIndex].clips[clipIndex];
      _toggleClipSelection(clip);
    });
  }

  void _onTrackScaleStart({
    required int trackIndex,
    required double localDx,
    required double laneViewportWidth,
    required int pointerCount,
  }) async {
    if (pointerCount > 1) {
      setState(() {
        _isTimelineScaleGesture = true;
        _scaleGestureStartZoom = _timelineZoom;
        _dragMode = _TimelineDragMode.none;
        _dragTrackIndex = null;
      });
      return;
    }

    final int? clipIndex = _clipIndexAtPosition(
      trackIndex: trackIndex,
      localDx: localDx,
      laneViewportWidth: laneViewportWidth,
    );
    bool willScrub = true;
    setState(() {
      _isTimelineScaleGesture = false;
      _dragTrackIndex = trackIndex;
      if (clipIndex != null) {
        final _TimelineClip touchedClip = _tracks[trackIndex].clips[clipIndex];
        if (_isClipSelected(touchedClip)) {
          willScrub = false;
          _dragMode = _TimelineDragMode.moveSelection;
          _selectionDragRequestedDelta = 0.0;
          _prepareSelectionDragState();
          return;
        }
      }
      _dragMode = _TimelineDragMode.scrub;
      _selectionDragBaseStarts.clear();
      _selectionDragRequestedDelta = 0.0;
    });
    if (willScrub) {
      await _pausePlaybackForScrub();
      await _queueVideoSeek(_timelineCenterSecond);
    }
  }

  void _onTrackScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1 || _isTimelineScaleGesture) {
      if (!_isTimelineScaleGesture) {
        _isTimelineScaleGesture = true;
        _scaleGestureStartZoom = _timelineZoom;
        _dragMode = _TimelineDragMode.none;
        _dragTrackIndex = null;
      }
      final double nextZoom = (_scaleGestureStartZoom * details.scale)
          .clamp(_timelineMinZoom, _timelineMaxZoom)
          .toDouble();
      if ((nextZoom - _timelineZoom).abs() > 0.0001) {
        setState(() {
          _isTimelineScaleGesture = true;
          _timelineZoom = nextZoom;
        });
      }
      return;
    }
    _onTrackPanUpdate(details.focalPointDelta.dx);
  }

  void _onTrackPanUpdate(double deltaDx) {
    if (_isTimelineScaleGesture) return;
    if (deltaDx.abs() <= 0.0001) return;

    if (_dragMode == _TimelineDragMode.scrub) {
      final double deltaSeconds =
          (deltaDx / _pixelsPerSecond) * _timelineScrubSensitivity;
      final double nextCenter =
          (_timelineCenterSecond - deltaSeconds).clamp(0.0, _timelineSeconds);
      setState(() {
        _timelineCenterSecond = nextCenter.toDouble();
      });
      unawaited(_queueVideoSeek(nextCenter));
      return;
    }

    if (_dragMode != _TimelineDragMode.moveSelection) return;
    if (_selectedClipIds.isEmpty) {
      _dragMode = _TimelineDragMode.scrub;
      return;
    }

    final double deltaSeconds = deltaDx / _pixelsPerSecond;
    _selectionDragRequestedDelta += deltaSeconds;
    final double effectiveDelta = _selectionDragRequestedDelta
        .clamp(_selectionGroupMinDelta, _selectionGroupMaxDelta)
        .toDouble();
    setState(() {
      for (final String clipId in _selectedClipIds) {
        final _TimelineClip? clip = _findClipById(clipId);
        if (clip == null) continue;
        final double? baseStart = _selectionDragBaseStarts[clipId];
        if (baseStart == null) continue;
        clip.startSecond = baseStart + effectiveDelta;
      }
    });
  }

  void _onTrackScaleEnd() {
    if (_isTimelineScaleGesture) {
      setState(() {
        _isTimelineScaleGesture = false;
        _dragMode = _TimelineDragMode.none;
        _dragTrackIndex = null;
      });
      return;
    }
    _onTrackPanEnd();
  }

  void _onTrackPanEnd() {
    if (_dragMode == _TimelineDragMode.none &&
        _dragTrackIndex == null &&
        !_isTimelineScaleGesture) {
      return;
    }
    setState(() {
      _isTimelineScaleGesture = false;
      _scaleGestureStartZoom = _timelineZoom;
      _dragMode = _TimelineDragMode.none;
      _dragTrackIndex = null;
      _selectionDragBaseStarts.clear();
      _selectionDragRequestedDelta = 0.0;
      _selectionGroupMinDelta = 0.0;
      _selectionGroupMaxDelta = 0.0;
    });
  }

  void _openAddLayerSheet(double sheetHeight) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (BuildContext context) {
        final List<Map<String, dynamic>> addOptions = <Map<String, dynamic>>[
          <String, dynamic>{
            'icon': Icons.video_library_rounded,
            'label': 'Add Video',
            'action': _AddLayerAction.video,
          },
          <String, dynamic>{
            'icon': Icons.photo_library_rounded,
            'label': 'Add Image',
            'action': _AddLayerAction.image,
          },
          <String, dynamic>{
            'icon': Icons.text_fields_rounded,
            'label': 'Add Text',
            'action': _AddLayerAction.text,
          },
          <String, dynamic>{
            'icon': Icons.layers_rounded,
            'label': 'Add Overlay',
            'action': _AddLayerAction.overlay,
          },
          <String, dynamic>{
            'icon': Icons.tune_rounded,
            'label': 'Add Adjustment Layer',
            'action': _AddLayerAction.adjustment,
          },
        ];
        return SizedBox(
          height: sheetHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _panelBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              border: Border.all(
                color: _panelBorder,
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
              child: Column(
                children: [
                  Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A4151),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Add Layer',
                      style: TextStyle(
                        color: _textMain,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: addOptions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final Map<String, dynamic> option = addOptions[index];
                        final IconData icon = option['icon'] as IconData;
                        final String label = option['label'] as String;
                        final _AddLayerAction action =
                            option['action'] as _AddLayerAction;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              Navigator.of(context).pop();
                              await _handleAddLayerAction(action);
                            },
                            child: Ink(
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF202634),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF343B4B),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 12),
                                  Icon(icon, size: 18, color: _textMain),
                                  const SizedBox(width: 10),
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: _textMain,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double timelineHeight =
                (constraints.maxHeight * 0.27).clamp(190.0, 300.0).toDouble();
            return Column(
              children: [
                const SizedBox(height: 8),
                _buildTopToolStrip(),
                const SizedBox(height: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: _buildCanvasArea(),
                  ),
                ),
                _buildTimelinePanel(height: timelineHeight),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopToolStrip() {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _tools.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final _VideoToolAction tool = _tools[index];
          final bool selected = tool.id == _activeTool;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                if (tool.id == _VideoEditTool.add) {
                  final double sheetHeight =
                      (MediaQuery.of(context).size.height * 0.27)
                          .clamp(190.0, 300.0)
                          .toDouble();
                  _openAddLayerSheet(sheetHeight);
                  return;
                }
                setState(() {
                  _activeTool = tool.id;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                curve: Curves.easeOut,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? _accent : _toolIdleBg,
                  border: Border.all(
                    color: selected ? _accent : const Color(0xFF222734),
                    width: 1.1,
                  ),
                ),
                child: Icon(
                  tool.icon,
                  size: 19,
                  color: selected ? const Color(0xFF121317) : _textMain,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCanvasArea() {
    final VideoPlayerController? controller = _videoController;
    final bool hasVideo = controller != null && controller.value.isInitialized;
    final String layerName = (_videoPath == null || _videoPath!.isEmpty)
        ? 'Original Layer'
        : _basename(_videoPath!);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF202530),
        border: Border.all(color: const Color(0xFF2A3140), width: 1.1),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFF10131B),
                    Color(0xFF0F1219),
                  ],
                ),
                border: Border.all(color: const Color(0xFF343C4D), width: 1.1),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xC3212634),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFF3B4357),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        layerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textMain,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(1.5),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0xFF0E1118),
                          ),
                          child: hasVideo
                              ? FittedBox(
                                  fit: BoxFit.contain,
                                  child: SizedBox(
                                    width: controller.value.size.width,
                                    height: controller.value.size.height,
                                    child: VideoPlayer(controller),
                                  ),
                                )
                              : const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                  if (!hasVideo && !_isLoadingVideo)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Tap + then Add Video',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _textSub,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  if (_isLoadingVideo)
                    const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(_accent),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Text(
                      '${_formatTimelineTime(_timelineCenterSecond)} / ${_formatTimelineTime(_timelineSeconds)}',
                      style: const TextStyle(
                        color: _textMain,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Text(
                      hasVideo
                          ? '${controller.value.size.width.round()}x${controller.value.size.height.round()}'
                          : 'No source',
                      style: const TextStyle(
                        color: _textSub,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelinePanel({required double height}) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      child: Container(
        height: height,
        width: double.infinity,
        decoration: const BoxDecoration(
          color: _panelBg,
          border: Border(
            top: BorderSide(color: _panelBorder, width: 1),
            left: BorderSide(color: Color(0xFF232A38), width: 1),
            right: BorderSide(color: Color(0xFF232A38), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            children: [
              _buildTimelineHeader(panelHeight: height),
              const SizedBox(height: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double laneViewportWidth = math.max(
                      1.0,
                      constraints.maxWidth - _trackLabelWidth - _trackLaneGap,
                    );
                    final double playheadLeft = _trackLabelWidth +
                        _trackLaneGap +
                        (laneViewportWidth / 2) -
                        1;
                    return Stack(
                      children: [
                        Column(
                          children: [
                            _buildTimelineTimeRuler(
                              laneViewportWidth: laneViewportWidth,
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: _tracks.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (BuildContext context, int index) {
                                  return _buildTrackRow(
                                    trackIndex: index,
                                    track: _tracks[index],
                                    laneViewportWidth: laneViewportWidth,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          left: playheadLeft,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              width: 2,
                              color: _accent,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineHeader({required double panelHeight}) {
    return SizedBox(
      height: 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _buildTimelineActionButton(
              Icons.add_rounded,
              highlighted: true,
              circular: true,
              onTap: () => _openAddLayerSheet(panelHeight),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: _buildTimelineActionButton(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              highlighted: true,
              onTap: () {
                unawaited(_togglePlayPause());
              },
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTimelineActionButton(Icons.undo_rounded),
                const SizedBox(width: 6),
                _buildTimelineActionButton(Icons.redo_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineTimeRuler({required double laneViewportWidth}) {
    final double contentOffsetPx = _timelineContentOffsetPx(laneViewportWidth);
    final int majorStepSecond = _pixelsPerSecond >= 60
        ? 1
        : _pixelsPerSecond >= 36
            ? 2
            : 4;
    return SizedBox(
      height: _timelineRulerHeight,
      child: Row(
        children: [
          const SizedBox(width: _trackLabelWidth + _trackLaneGap),
          SizedBox(
            width: laneViewportWidth,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF202634),
                ),
                child: Transform.translate(
                  offset: Offset(contentOffsetPx, 0),
                  child: SizedBox(
                    width: _timelineCanvasWidth,
                    height: _timelineRulerHeight,
                    child: Stack(
                      children: [
                        for (int i = 0; i <= _timelineSeconds.floor(); i++)
                          Positioned(
                            left: i * _pixelsPerSecond,
                            top: i % majorStepSecond == 0 ? 2 : 6,
                            bottom: 2,
                            child: Container(
                              width: 1,
                              color: i % majorStepSecond == 0
                                  ? const Color(0xFF4A556B)
                                  : const Color(0xFF31394A),
                            ),
                          ),
                        for (int i = 0;
                            i <= _timelineSeconds.floor();
                            i += majorStepSecond)
                          Positioned(
                            left: i * _pixelsPerSecond + 2,
                            top: 1,
                            child: Text(
                              '${i}s',
                              style: const TextStyle(
                                color: Color(0xFF9AA2B1),
                                fontSize: 7,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineActionButton(
    IconData icon, {
    bool highlighted = false,
    bool circular = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(circular ? 999 : 6),
        onTap: onTap,
        child: Ink(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: highlighted ? _accent : const Color(0xFF202634),
            shape: circular ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circular ? null : BorderRadius.circular(6),
            border: Border.all(
              color: highlighted ? _accent : const Color(0xFF343B4B),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 14,
            color: highlighted ? const Color(0xFF121317) : _textMain,
          ),
        ),
      ),
    );
  }

  Widget _buildTrackRow({
    required int trackIndex,
    required _TimelineTrack track,
    required double laneViewportWidth,
  }) {
    final double contentOffsetPx = _timelineContentOffsetPx(laneViewportWidth);
    return SizedBox(
      height: _trackRowHeight,
      child: Row(
        children: [
          SizedBox(
            width: _trackLabelWidth,
            height: double.infinity,
            child: Center(
              child: Tooltip(
                message: track.name,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFF202634),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF363F51),
                      width: 1,
                    ),
                  ),
                  child: Icon(track.icon, size: 14, color: _textSub),
                ),
              ),
            ),
          ),
          const SizedBox(width: _trackLaneGap),
          SizedBox(
            width: laneViewportWidth,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTapDown: (TapDownDetails details) {
                  _onTrackDoubleTapDown(
                    trackIndex: trackIndex,
                    localDx: details.localPosition.dx,
                    laneViewportWidth: laneViewportWidth,
                  );
                },
                onDoubleTap: () {},
                onScaleStart: (ScaleStartDetails details) {
                  _onTrackScaleStart(
                    trackIndex: trackIndex,
                    localDx: details.localFocalPoint.dx,
                    laneViewportWidth: laneViewportWidth,
                    pointerCount: details.pointerCount,
                  );
                },
                onScaleUpdate: _onTrackScaleUpdate,
                onScaleEnd: (_) => _onTrackScaleEnd(),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: const Color(0xFF202634),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(contentOffsetPx, 0),
                      child: SizedBox(
                        width: _timelineCanvasWidth,
                        height: _trackRowHeight,
                        child: Stack(
                          children: [
                            for (int i = 0;
                                i < (_timelineSeconds / 2).floor();
                                i++)
                              Positioned(
                                left: i * 2 * _pixelsPerSecond,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: 0.8,
                                  color: const Color(0xFF2D3546),
                                ),
                              ),
                            for (int i = 0; i < track.clips.length; i++)
                              Positioned(
                                left: track.clips[i].startSecond *
                                    _pixelsPerSecond,
                                top: _clipTopInset,
                                child: _buildClipWidget(
                                  track.clips[i],
                                  isSelected: _isClipSelected(track.clips[i]),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClipWidget(
    _TimelineClip clip, {
    required bool isSelected,
  }) {
    final double width = math.max(44, clip.durationSecond * _pixelsPerSecond);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      width: width,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            clip.color.withOpacity(0.94),
            clip.color.withOpacity(0.70),
          ],
        ),
        border: Border.all(
          color: isSelected
              ? _accent.withOpacity(0.92)
              : Colors.white.withOpacity(0.16),
          width: isSelected ? 1.35 : 1,
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        clip.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFF7F7F8),
          fontSize: 10.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static String _formatTimelineTime(double seconds) {
    final Duration value =
        Duration(milliseconds: (seconds * 1000).round().clamp(0, 3600000));
    final String mm = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String ss = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}
