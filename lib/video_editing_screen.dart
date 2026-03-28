import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wonderpic/fusion_cut/fusion_cut_engine.dart';

class WonderPicVideoEditingScreen extends StatefulWidget {
  const WonderPicVideoEditingScreen({super.key});

  @override
  State<WonderPicVideoEditingScreen> createState() =>
      _WonderPicVideoEditingScreenState();
}

enum _TimelineDragMode {
  none,
  scrub,
  moveSelection,
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
  static const double _timelineSnapToleranceSecond = 0.16;
  static const Duration _scrubSeekDebounceDelay = Duration(milliseconds: 48);

  late final FusionCutSessionController _session;
  _TimelineDragMode _dragMode = _TimelineDragMode.none;
  int? _dragTrackIndex;
  bool _isTimelineScaleGesture = false;
  double _scaleGestureStartZoom = 1.0;
  VideoPlayerController? _videoController;
  bool _isLoadingVideo = false;
  bool _isPlaying = false;
  String? _videoPath;
  int _videoLoadToken = 0;
  int _lastRenderedPositionMs = -1000;
  bool _seekInFlight = false;
  double? _pendingSeekSecond;
  Timer? _scrubSeekDebounce;

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
    return math.max(value, _session.timelineSeconds);
  }

  double get _pixelsPerSecond =>
      _timelineBasePixelsPerSecond * _session.timelineZoom;
  double get _timelineCanvasWidth => _timelineSeconds * _pixelsPerSecond;

  double _timelineContentOffsetPx(double laneViewportWidth) {
    return (laneViewportWidth / 2) -
        (_session.timelineCenterSecond * _pixelsPerSecond);
  }

  double _timeFromLaneDx({
    required double localDx,
    required double laneViewportWidth,
  }) {
    return (localDx - _timelineContentOffsetPx(laneViewportWidth)) /
        _pixelsPerSecond;
  }

  @override
  void initState() {
    super.initState();
    _session = FusionCutSessionController.mockProject();
    _session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _scrubSeekDebounce?.cancel();
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    final VideoPlayerController? controller = _videoController;
    if (controller != null) {
      controller.removeListener(_onVideoControllerTick);
      controller.dispose();
    }
    super.dispose();
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
        (positionMs - _lastRenderedPositionMs).abs() >= 33;
    if (!shouldRefreshPosition && playingNow == _isPlaying) return;
    _lastRenderedPositionMs = positionMs;
    final double second = positionMs / 1000.0;
    _session.setTimelineCenterSecond(
      _clampTimelineSecond(second),
      notify: false,
    );
    setState(() {
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
      final Size videoSize = nextController.value.size;
      _session.registerPrimaryVideoSource(
        path: path,
        durationSecond: nextController.value.duration.inMilliseconds / 1000.0,
        width: videoSize.width.round(),
        height: videoSize.height.round(),
      );
      setState(() {
        _videoController = nextController;
        _isLoadingVideo = false;
        _isPlaying = false;
        _lastRenderedPositionMs = -1000;
      });
      _session.setTimelineCenterSecond(0.0);
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
        _session.timelineCenterSecond >= (_timelineSeconds - 0.05)
            ? 0.0
            : _session.timelineCenterSecond;
    await controller.seekTo(_durationFromSecond(startSecond));
    await controller.play();
    _session.setTimelineCenterSecond(_clampTimelineSecond(startSecond));
    if (mounted) {
      setState(() {
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

  void _clearMockTimelineIfNeeded() {
    _session.clearTemplateTimelineIfNeeded();
  }

  void _addClipToTrack({
    required String trackId,
    required String label,
    required Color color,
    required double durationSecond,
  }) {
    _session.addClipToTrack(
      trackType: FusionCutTrackType.values.firstWhere(
        (FusionCutTrackType item) => item.id == trackId,
      ),
      label: label,
      color: color,
      durationSecond: durationSecond,
      startSecond: _session.timelineCenterSecond,
    );
  }

  Future<void> _handleAddLayerAction(_AddLayerAction action) async {
    switch (action) {
      case _AddLayerAction.video:
        String? path;
        final FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: false,
        );
        if (result != null && result.files.isNotEmpty) {
          path = result.files.single.path;
        }
        if (path == null || path.isEmpty) return;
        await _loadVideoFile(path);
        if (!mounted) return;
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
        _clearMockTimelineIfNeeded();
        _addClipToTrack(
          trackId: 'overlay',
          label: _basename(imagePath),
          color: const Color(0xFFFF9A50),
          durationSecond: 5.0,
        );
        return;
      case _AddLayerAction.text:
        if (!mounted) return;
        _clearMockTimelineIfNeeded();
        _addClipToTrack(
          trackId: 'text',
          label: 'Text',
          color: const Color(0xFFBF7AFF),
          durationSecond: 4.0,
        );
        return;
      case _AddLayerAction.overlay:
        if (!mounted) return;
        _clearMockTimelineIfNeeded();
        _addClipToTrack(
          trackId: 'overlay',
          label: 'Overlay',
          color: const Color(0xFFFF9A50),
          durationSecond: 4.5,
        );
        return;
      case _AddLayerAction.adjustment:
        if (!mounted) return;
        _clearMockTimelineIfNeeded();
        _addClipToTrack(
          trackId: 'adjustment',
          label: 'Adjustment',
          color: const Color(0xFF7AA4FF),
          durationSecond: 6.0,
        );
        return;
    }
  }

  int? _clipIndexAtPosition({
    required int trackIndex,
    required double localDx,
    required double laneViewportWidth,
  }) {
    if (trackIndex < 0 || trackIndex >= _session.tracks.length) return null;
    final List<FusionCutTimelineClip> clips = _session.tracks[trackIndex].clips;
    if (clips.isEmpty) return null;
    final double touchSecond = _timeFromLaneDx(
      localDx: localDx,
      laneViewportWidth: laneViewportWidth,
    );
    for (int i = clips.length - 1; i >= 0; i--) {
      final FusionCutTimelineClip clip = clips[i];
      final double start = clip.startSecond;
      final double end = clip.startSecond + clip.durationSecond;
      if (touchSecond >= start && touchSecond <= end) {
        return i;
      }
    }
    return null;
  }

  bool _isClipSelected(FusionCutTimelineClip clip) {
    return _session.isClipSelected(clip);
  }

  void _toggleClipSelection(FusionCutTimelineClip clip) {
    _session.toggleClipSelection(clip);
  }

  void _selectOnlyClip(FusionCutTimelineClip clip) {
    _session.selectOnlyClip(clip);
  }

  void _prepareSelectionDragState() {
    _session.beginSelectionDrag();
  }

  void _onTrackTapDown({
    required int trackIndex,
    required double localDx,
    required double laneViewportWidth,
  }) {
    final int? clipIndex = _clipIndexAtPosition(
      trackIndex: trackIndex,
      localDx: localDx,
      laneViewportWidth: laneViewportWidth,
    );
    if (clipIndex == null) {
      _session.clearSelection();
      return;
    }
    final FusionCutTimelineClip clip =
        _session.tracks[trackIndex].clips[clipIndex];
    _selectOnlyClip(clip);
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
      if (clipIndex == null) {
        _session.clearSelection();
        return;
      }
      final FusionCutTimelineClip clip =
          _session.tracks[trackIndex].clips[clipIndex];
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
        _scaleGestureStartZoom = _session.timelineZoom;
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
        final FusionCutTimelineClip touchedClip =
            _session.tracks[trackIndex].clips[clipIndex];
        if (_isClipSelected(touchedClip)) {
          willScrub = false;
          _dragMode = _TimelineDragMode.moveSelection;
          _prepareSelectionDragState();
          return;
        }
      }
      _dragMode = _TimelineDragMode.scrub;
    });
    if (willScrub) {
      await _pausePlaybackForScrub();
      await _queueVideoSeek(_session.timelineCenterSecond);
    }
  }

  void _onTrackScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1 || _isTimelineScaleGesture) {
      if (!_isTimelineScaleGesture) {
        _isTimelineScaleGesture = true;
        _scaleGestureStartZoom = _session.timelineZoom;
        _dragMode = _TimelineDragMode.none;
        _dragTrackIndex = null;
      }
      final double nextZoom = (_scaleGestureStartZoom * details.scale)
          .clamp(_timelineMinZoom, _timelineMaxZoom)
          .toDouble();
      if ((nextZoom - _session.timelineZoom).abs() > 0.0001) {
        setState(() {
          _isTimelineScaleGesture = true;
          _session.setTimelineZoom(nextZoom, notify: false);
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
      final double nextCenter = (_session.timelineCenterSecond - deltaSeconds)
          .clamp(0.0, _timelineSeconds);
      _session.setTimelineCenterSecond(nextCenter.toDouble(), notify: false);
      setState(() {});
      _scheduleScrubSeek(nextCenter.toDouble());
      return;
    }

    if (_dragMode != _TimelineDragMode.moveSelection) return;
    if (_session.selectedClipIds.isEmpty) {
      _dragMode = _TimelineDragMode.scrub;
      return;
    }

    _session.applySelectionDragDelta(deltaDx / _pixelsPerSecond);
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
    _scrubSeekDebounce?.cancel();
    if (_dragMode == _TimelineDragMode.none &&
        _dragTrackIndex == null &&
        !_isTimelineScaleGesture) {
      return;
    }
    setState(() {
      _isTimelineScaleGesture = false;
      _scaleGestureStartZoom = _session.timelineZoom;
      _dragMode = _TimelineDragMode.none;
      _dragTrackIndex = null;
      _session.endSelectionDrag();
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

  void _showSurfaceMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _scheduleScrubSeek(double second) {
    _scrubSeekDebounce?.cancel();
    _scrubSeekDebounce = Timer(_scrubSeekDebounceDelay, () {
      unawaited(_queueVideoSeek(second));
    });
  }

  Future<File> _writeExportDraftManifest(FusionCutExportDraft draft) async {
    final String safeName = draft.projectName
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '')
        .toLowerCase();
    final String fileName =
        '${safeName.isEmpty ? 'fusion_cut_project' : safeName}_phase1_export.json';
    final File file = File('${Directory.systemTemp.path}/$fileName');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(draft.toJson()),
    );
    return file;
  }

  Future<void> _openExportSheet() async {
    FusionCutExportPreset selectedPreset = FusionCutExportPreset.standard1080p;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final FusionCutExportDraft draft = _session.buildExportDraft(
              preset: selectedPreset,
            );
            final FusionCutProjectSummary summary = draft.summary;
            return Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: _panelBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                border: Border.all(color: _panelBorder, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 34,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A4151),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Phase 1 Export Draft',
                      style: TextStyle(
                        color: _textMain,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'This is the first engine hook for Fusion Cut: project snapshot, timeline summary, and export preset manifest.',
                      style: TextStyle(
                        color: _textSub,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildExportInfoRow('Project', summary.projectName),
                    _buildExportInfoRow(
                      'Duration',
                      _formatTimelineTime(summary.durationSecond),
                    ),
                    _buildExportInfoRow(
                      'Timeline',
                      '${summary.trackCount} tracks • ${summary.clipCount} clips',
                    ),
                    _buildExportInfoRow(
                      'Sources',
                      '${summary.mediaSourceCount} media items',
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Preset',
                      style: TextStyle(
                        color: _textMain,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: FusionCutExportPreset.presets
                          .map((FusionCutExportPreset preset) {
                        final bool selected = preset.id == selectedPreset.id;
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setSheetState(() {
                              selectedPreset = preset;
                            });
                          },
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  selected ? _accent : const Color(0xFF202634),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? _accent
                                    : const Color(0xFF343B4B),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              preset.label,
                              style: TextStyle(
                                color: selected
                                    ? const Color(0xFF121317)
                                    : _textMain,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _textMain,
                              side: const BorderSide(color: Color(0xFF394255)),
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: const Text('Close'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final File file =
                                  await _writeExportDraftManifest(draft);
                              if (!mounted) return;
                              Navigator.of(context).pop();
                              _showSurfaceMessage(
                                'Export draft ready: ${file.path}',
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: const Color(0xFF121317),
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: const Text(
                              'Prepare Draft',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExportInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: _textSub,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _textMain,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSplitSelection() async {
    unawaited(_pausePlaybackForScrub());
    final bool success =
        _session.splitPrimarySelectionAt(_session.timelineCenterSecond);
    if (!success) {
      _showSurfaceMessage(
        'Select one clip, then place the playhead inside it to split.',
      );
    }
  }

  Future<void> _handleTrimStartSelection() async {
    unawaited(_pausePlaybackForScrub());
    final bool success =
        _session.trimPrimarySelectionStartTo(_session.timelineCenterSecond);
    if (!success) {
      _showSurfaceMessage(
        'Select one clip, then move the playhead forward to trim the start.',
      );
    }
  }

  Future<void> _handleTrimEndSelection() async {
    unawaited(_pausePlaybackForScrub());
    final bool success =
        _session.trimPrimarySelectionEndTo(_session.timelineCenterSecond);
    if (!success) {
      _showSurfaceMessage(
        'Select one clip, then place the playhead before its end to trim out.',
      );
    }
  }

  void _handleDeleteSelection() {
    final bool success = _session.deleteSelectedClips();
    if (!success) {
      _showSurfaceMessage('Select at least one clip to delete.');
    }
  }

  void _handleRippleDeleteSelection() {
    final bool success = _session.rippleDeleteSelectedClips();
    if (!success) {
      _showSurfaceMessage('Select at least one clip to ripple delete.');
    }
  }

  void _handleUndo() {
    if (!_session.canUndo) return;
    _session.undo();
  }

  void _handleRedo() {
    if (!_session.canRedo) return;
    _session.redo();
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
    final bool singleClip = _session.selectedClipCount == 1;
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _buildTopActionCircle(
            icon: Icons.content_cut_rounded,
            tooltip: 'Split',
            enabled: singleClip,
            onTap: () {
              unawaited(_handleSplitSelection());
            },
          ),
          _buildTopActionCircle(
            icon: Icons.first_page_rounded,
            tooltip: 'Trim In',
            enabled: singleClip,
            onTap: () {
              unawaited(_handleTrimStartSelection());
            },
          ),
          _buildTopActionCircle(
            icon: Icons.last_page_rounded,
            tooltip: 'Trim Out',
            enabled: singleClip,
            onTap: () {
              unawaited(_handleTrimEndSelection());
            },
          ),
          _buildTopActionCircle(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            enabled: _session.hasSelection,
            danger: true,
            onTap: _handleDeleteSelection,
          ),
          _buildTopActionCircle(
            icon: Icons.keyboard_double_arrow_left_rounded,
            tooltip: 'Ripple Delete',
            enabled: _session.hasSelection,
            danger: true,
            onTap: _handleRippleDeleteSelection,
          ),
        ],
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
                    child: _session.hasTimelineContent
                        ? Text(
                            '${_formatTimelineTime(_session.timelineCenterSecond)} / ${_formatTimelineTime(_timelineSeconds)}',
                            style: const TextStyle(
                              color: _textMain,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (_session.hasTimelineContent)
                    Positioned(
                      right: 12,
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
                          'Snap ${(_timelineSnapToleranceSecond * 1000).round()}ms',
                          style: const TextStyle(
                            color: _textSub,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
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
                                itemCount: _session.tracks.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (BuildContext context, int index) {
                                  return _buildTrackRow(
                                    trackIndex: index,
                                    track: _session.tracks[index],
                                    laneViewportWidth: laneViewportWidth,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        if (_session.hasTimelineContent)
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
                _buildTimelineActionButton(
                  Icons.ios_share_rounded,
                  highlighted: true,
                  onTap: () {
                    unawaited(_openExportSheet());
                  },
                ),
                const SizedBox(width: 6),
                _buildTimelineActionButton(
                  Icons.undo_rounded,
                  onTap: _session.canUndo ? _handleUndo : null,
                ),
                const SizedBox(width: 6),
                _buildTimelineActionButton(
                  Icons.redo_rounded,
                  onTap: _session.canRedo ? _handleRedo : null,
                ),
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
    final bool enabled = onTap != null;
    final Color fillColor = highlighted
        ? (enabled ? _accent : _accent.withOpacity(0.35))
        : const Color(0xFF202634);
    final Color borderColor = highlighted
        ? (enabled ? _accent : _accent.withOpacity(0.35))
        : const Color(0xFF343B4B);
    final Color iconColor = highlighted
        ? (enabled
            ? const Color(0xFF121317)
            : const Color(0xFF121317).withOpacity(0.45))
        : (enabled ? _textMain : _textSub.withOpacity(0.45));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(circular ? 999 : 6),
        onTap: onTap,
        child: Ink(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: fillColor,
            shape: circular ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circular ? null : BorderRadius.circular(6),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 14,
            color: iconColor,
          ),
        ),
      ),
    );
  }

  Widget _buildTopActionCircle({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final Color activeBg =
        danger ? const Color(0xFF3A222A) : const Color(0xFF161A22);
    final Color activeBorder =
        danger ? const Color(0xFF7A4450) : const Color(0xFF2C3341);
    final Color activeText = danger ? const Color(0xFFFFCED4) : _textMain;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: enabled ? onTap : null,
            child: Ink(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? activeBg : const Color(0xFF11151D),
                border: Border.all(
                  color: enabled ? activeBorder : const Color(0xFF212734),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: enabled ? activeText : _textSub.withOpacity(0.45),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackRow({
    required int trackIndex,
    required FusionCutTimelineTrack track,
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
                message: track.label,
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
                  child: Icon(track.type.icon, size: 14, color: _textSub),
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
                onTapDown: (TapDownDetails details) {
                  _onTrackTapDown(
                    trackIndex: trackIndex,
                    localDx: details.localPosition.dx,
                    laneViewportWidth: laneViewportWidth,
                  );
                },
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
    FusionCutTimelineClip clip, {
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
