import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum FusionCutTrackType {
  video,
  audio,
  text,
  overlay,
  adjustment,
}

extension FusionCutTrackTypeUi on FusionCutTrackType {
  String get id {
    switch (this) {
      case FusionCutTrackType.video:
        return 'video';
      case FusionCutTrackType.audio:
        return 'audio';
      case FusionCutTrackType.text:
        return 'text';
      case FusionCutTrackType.overlay:
        return 'overlay';
      case FusionCutTrackType.adjustment:
        return 'adjustment';
    }
  }

  String get label {
    switch (this) {
      case FusionCutTrackType.video:
        return 'Video';
      case FusionCutTrackType.audio:
        return 'Audio';
      case FusionCutTrackType.text:
        return 'Text';
      case FusionCutTrackType.overlay:
        return 'Overlay';
      case FusionCutTrackType.adjustment:
        return 'Adjustment';
    }
  }

  IconData get icon {
    switch (this) {
      case FusionCutTrackType.video:
        return Icons.videocam_rounded;
      case FusionCutTrackType.audio:
        return Icons.graphic_eq_rounded;
      case FusionCutTrackType.text:
        return Icons.text_fields_rounded;
      case FusionCutTrackType.overlay:
        return Icons.layers_rounded;
      case FusionCutTrackType.adjustment:
        return Icons.tune_rounded;
    }
  }
}

enum FusionCutMediaKind { video, image, text, overlay, adjustment }

extension FusionCutMediaKindUi on FusionCutMediaKind {
  String get label {
    switch (this) {
      case FusionCutMediaKind.video:
        return 'Video';
      case FusionCutMediaKind.image:
        return 'Image';
      case FusionCutMediaKind.text:
        return 'Text';
      case FusionCutMediaKind.overlay:
        return 'Overlay';
      case FusionCutMediaKind.adjustment:
        return 'Adjustment';
    }
  }
}

class FusionCutMediaSource {
  const FusionCutMediaSource({
    required this.id,
    required this.kind,
    required this.label,
    this.filePath,
    this.durationSecond,
    this.width,
    this.height,
  });

  final String id;
  final FusionCutMediaKind kind;
  final String label;
  final String? filePath;
  final double? durationSecond;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'kind': kind.label,
      'label': label,
      'filePath': filePath,
      'durationSecond': durationSecond,
      'width': width,
      'height': height,
    };
  }
}

class FusionCutTimelineClip {
  FusionCutTimelineClip({
    required this.id,
    required this.label,
    required this.startSecond,
    required this.durationSecond,
    required this.color,
    this.sourceId,
    this.sourceOffsetSecond = 0.0,
    double? sourceDurationSecond,
  }) : sourceDurationSecond = sourceDurationSecond ?? durationSecond;

  final String id;
  final String label;
  double startSecond;
  double durationSecond;
  final Color color;
  final String? sourceId;
  double sourceOffsetSecond;
  final double sourceDurationSecond;

  FusionCutTimelineClip copy() {
    return FusionCutTimelineClip(
      id: id,
      label: label,
      startSecond: startSecond,
      durationSecond: durationSecond,
      color: color,
      sourceId: sourceId,
      sourceOffsetSecond: sourceOffsetSecond,
      sourceDurationSecond: sourceDurationSecond,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'startSecond': startSecond,
      'durationSecond': durationSecond,
      'color': color.value,
      'sourceId': sourceId,
      'sourceOffsetSecond': sourceOffsetSecond,
      'sourceDurationSecond': sourceDurationSecond,
    };
  }
}

class FusionCutTimelineTrack {
  FusionCutTimelineTrack({
    required this.type,
    List<FusionCutTimelineClip>? clips,
  }) : clips = clips ?? <FusionCutTimelineClip>[];

  final FusionCutTrackType type;
  final List<FusionCutTimelineClip> clips;

  String get id => type.id;
  String get label => type.label;

  FusionCutTimelineTrack copy() {
    return FusionCutTimelineTrack(
      type: type,
      clips: clips.map((FusionCutTimelineClip clip) => clip.copy()).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'clips':
          clips.map((FusionCutTimelineClip clip) => clip.toJson()).toList(),
    };
  }
}

class FusionCutProjectSummary {
  const FusionCutProjectSummary({
    required this.projectName,
    required this.durationSecond,
    required this.trackCount,
    required this.clipCount,
    required this.mediaSourceCount,
    required this.clipCountsByTrack,
  });

  final String projectName;
  final double durationSecond;
  final int trackCount;
  final int clipCount;
  final int mediaSourceCount;
  final Map<FusionCutTrackType, int> clipCountsByTrack;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'projectName': projectName,
      'durationSecond': durationSecond,
      'trackCount': trackCount,
      'clipCount': clipCount,
      'mediaSourceCount': mediaSourceCount,
      'clipCountsByTrack': <String, int>{
        for (final MapEntry<FusionCutTrackType, int> entry
            in clipCountsByTrack.entries)
          entry.key.id: entry.value,
      },
    };
  }
}

class FusionCutExportPreset {
  const FusionCutExportPreset({
    required this.id,
    required this.label,
    required this.container,
    required this.videoCodec,
    required this.audioCodec,
    required this.width,
    required this.height,
    required this.fps,
    required this.videoBitrateMbps,
    required this.audioBitrateKbps,
  });

  final String id;
  final String label;
  final String container;
  final String videoCodec;
  final String audioCodec;
  final int width;
  final int height;
  final int fps;
  final int videoBitrateMbps;
  final int audioBitrateKbps;

  static const FusionCutExportPreset standard1080p = FusionCutExportPreset(
    id: 'mp4_h264_1080p30',
    label: '1080p / 30fps / H.264',
    container: 'MP4',
    videoCodec: 'H.264',
    audioCodec: 'AAC',
    width: 1920,
    height: 1080,
    fps: 30,
    videoBitrateMbps: 16,
    audioBitrateKbps: 256,
  );

  static const List<FusionCutExportPreset> presets = <FusionCutExportPreset>[
    standard1080p,
    FusionCutExportPreset(
      id: 'mp4_h264_720p30',
      label: '720p / 30fps / H.264',
      container: 'MP4',
      videoCodec: 'H.264',
      audioCodec: 'AAC',
      width: 1280,
      height: 720,
      fps: 30,
      videoBitrateMbps: 8,
      audioBitrateKbps: 192,
    ),
    FusionCutExportPreset(
      id: 'mp4_h264_4k30',
      label: '4K / 30fps / H.264',
      container: 'MP4',
      videoCodec: 'H.264',
      audioCodec: 'AAC',
      width: 3840,
      height: 2160,
      fps: 30,
      videoBitrateMbps: 42,
      audioBitrateKbps: 320,
    ),
  ];

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'container': container,
      'videoCodec': videoCodec,
      'audioCodec': audioCodec,
      'width': width,
      'height': height,
      'fps': fps,
      'videoBitrateMbps': videoBitrateMbps,
      'audioBitrateKbps': audioBitrateKbps,
    };
  }
}

class FusionCutExportDraft {
  const FusionCutExportDraft({
    required this.projectName,
    required this.preset,
    required this.summary,
    required this.tracks,
    required this.mediaSources,
  });

  final String projectName;
  final FusionCutExportPreset preset;
  final FusionCutProjectSummary summary;
  final List<FusionCutTimelineTrack> tracks;
  final List<FusionCutMediaSource> mediaSources;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'projectName': projectName,
      'preset': preset.toJson(),
      'summary': summary.toJson(),
      'tracks':
          tracks.map((FusionCutTimelineTrack track) => track.toJson()).toList(),
      'mediaSources': mediaSources
          .map((FusionCutMediaSource item) => item.toJson())
          .toList(),
    };
  }

  String toPrettyJson() {
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }
}

class _FusionCutHistorySnapshot {
  const _FusionCutHistorySnapshot({
    required this.projectName,
    required this.clipSeed,
    required this.timelineZoom,
    required this.timelineCenterSecond,
    required this.hasClearedTemplate,
    required this.selectedClipIds,
    required this.tracks,
    required this.mediaSources,
  });

  final String projectName;
  final int clipSeed;
  final double timelineZoom;
  final double timelineCenterSecond;
  final bool hasClearedTemplate;
  final List<String> selectedClipIds;
  final List<FusionCutTimelineTrack> tracks;
  final List<FusionCutMediaSource> mediaSources;
}

class FusionCutSessionController extends ChangeNotifier {
  FusionCutSessionController._({
    required String projectName,
    required List<FusionCutTimelineTrack> tracks,
    required List<FusionCutMediaSource> mediaSources,
  })  : _projectName = projectName,
        _tracks = tracks,
        _mediaSources = mediaSources;

  static const double _defaultTimelineSeconds = 30.0;

  final List<FusionCutTimelineTrack> _tracks;
  final List<FusionCutMediaSource> _mediaSources;
  final List<String> _selectedClipIds = <String>[];
  final Map<String, double> _selectionDragBaseStarts = <String, double>{};
  final List<_FusionCutHistorySnapshot> _undoStack =
      <_FusionCutHistorySnapshot>[];
  final List<_FusionCutHistorySnapshot> _redoStack =
      <_FusionCutHistorySnapshot>[];

  String _projectName;
  int _clipSeed = 0;
  double _timelineZoom = 1.0;
  double _timelineCenterSecond = 0.0;
  bool _hasClearedTemplate = false;
  double _selectionDragRequestedDelta = 0.0;
  double _selectionGroupMinDelta = 0.0;
  double _selectionGroupMaxDelta = 0.0;
  _FusionCutHistorySnapshot? _selectionDragSnapshot;

  static FusionCutSessionController mockProject() {
    return FusionCutSessionController._(
      projectName: 'Fusion Cut Project',
      tracks: <FusionCutTimelineTrack>[
        FusionCutTimelineTrack(type: FusionCutTrackType.video),
        FusionCutTimelineTrack(type: FusionCutTrackType.audio),
        FusionCutTimelineTrack(type: FusionCutTrackType.text),
        FusionCutTimelineTrack(type: FusionCutTrackType.overlay),
        FusionCutTimelineTrack(type: FusionCutTrackType.adjustment),
      ],
      mediaSources: <FusionCutMediaSource>[],
    );
  }

  String get projectName => _projectName;
  double get timelineZoom => _timelineZoom;
  double get timelineCenterSecond => _timelineCenterSecond;
  UnmodifiableListView<FusionCutTimelineTrack> get tracks =>
      UnmodifiableListView<FusionCutTimelineTrack>(_tracks);
  UnmodifiableListView<String> get selectedClipIds =>
      UnmodifiableListView<String>(_selectedClipIds);
  UnmodifiableListView<FusionCutMediaSource> get mediaSources =>
      UnmodifiableListView<FusionCutMediaSource>(_mediaSources);
  bool get hasSelection => _selectedClipIds.isNotEmpty;
  int get selectedClipCount => _selectedClipIds.length;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get hasTimelineContent =>
      _mediaSources.isNotEmpty ||
      _tracks.any((FusionCutTimelineTrack track) => track.clips.isNotEmpty);

  double get timelineSeconds {
    double value = _defaultTimelineSeconds;
    for (final FusionCutTimelineTrack track in _tracks) {
      for (final FusionCutTimelineClip clip in track.clips) {
        value = math.max(value, clip.startSecond + clip.durationSecond);
      }
    }
    for (final FusionCutMediaSource mediaSource in _mediaSources) {
      final double? durationSecond = mediaSource.durationSecond;
      if (durationSecond != null &&
          durationSecond.isFinite &&
          durationSecond > 0) {
        value = math.max(value, durationSecond);
      }
    }
    return value;
  }

  void renameProject(String nextName) {
    final String trimmed = nextName.trim();
    if (trimmed.isEmpty || trimmed == _projectName) return;
    _pushUndoSnapshot();
    _projectName = trimmed;
    notifyListeners();
  }

  void setTimelineZoom(double value, {bool notify = true}) {
    final double next = value.clamp(0.30, 4.0).toDouble();
    if ((next - _timelineZoom).abs() <= 0.0001) return;
    _timelineZoom = next;
    if (notify) {
      notifyListeners();
    }
  }

  void setTimelineCenterSecond(double value, {bool notify = true}) {
    final double next = value.clamp(0.0, timelineSeconds).toDouble();
    if ((next - _timelineCenterSecond).abs() <= 0.0001) return;
    _timelineCenterSecond = next;
    if (notify) {
      notifyListeners();
    }
  }

  FusionCutTimelineTrack trackById(String trackId) {
    return _tracks
        .firstWhere((FusionCutTimelineTrack track) => track.id == trackId);
  }

  FusionCutTimelineClip? findClipById(String clipId) {
    for (final FusionCutTimelineTrack track in _tracks) {
      for (final FusionCutTimelineClip clip in track.clips) {
        if (clip.id == clipId) return clip;
      }
    }
    return null;
  }

  FusionCutTimelineTrack? trackForClipId(String clipId) {
    for (final FusionCutTimelineTrack track in _tracks) {
      for (final FusionCutTimelineClip clip in track.clips) {
        if (clip.id == clipId) {
          return track;
        }
      }
    }
    return null;
  }

  bool isClipSelected(FusionCutTimelineClip clip) {
    return _selectedClipIds.contains(clip.id);
  }

  void selectOnlyClip(FusionCutTimelineClip clip) {
    if (_selectedClipIds.length == 1 && _selectedClipIds.first == clip.id) {
      return;
    }
    _selectedClipIds
      ..clear()
      ..add(clip.id);
    notifyListeners();
  }

  List<FusionCutTimelineClip> selectedClips() {
    final List<FusionCutTimelineClip> selected = <FusionCutTimelineClip>[];
    for (final String clipId in _selectedClipIds) {
      final FusionCutTimelineClip? clip = findClipById(clipId);
      if (clip != null) {
        selected.add(clip);
      }
    }
    return selected;
  }

  void clearTemplateTimelineIfNeeded() {
    if (_hasClearedTemplate) return;
    for (final FusionCutTimelineTrack track in _tracks) {
      track.clips.clear();
    }
    _selectedClipIds.clear();
    _hasClearedTemplate = true;
    notifyListeners();
  }

  void registerPrimaryVideoSource({
    required String path,
    required double durationSecond,
    int? width,
    int? height,
  }) {
    final String label = path.split(RegExp(r'[\\/]')).last;
    _mediaSources.removeWhere(
        (FusionCutMediaSource source) => source.id == 'primary_video');
    _mediaSources.add(
      FusionCutMediaSource(
        id: 'primary_video',
        kind: FusionCutMediaKind.video,
        label: label,
        filePath: path,
        durationSecond: durationSecond,
        width: width,
        height: height,
      ),
    );
    notifyListeners();
  }

  void addClipToTrack({
    required FusionCutTrackType trackType,
    required String label,
    required Color color,
    required double durationSecond,
    String? sourceId,
    double? startSecond,
    double? sourceOffsetSecond,
    double? sourceDurationSecond,
  }) {
    _pushUndoSnapshot();
    final FusionCutTimelineTrack track = _tracks.firstWhere(
      (FusionCutTimelineTrack item) => item.type == trackType,
    );
    final double clampedDuration = math.max(0.25, durationSecond);
    final double maxStart = math.max(0.0, timelineSeconds - clampedDuration);
    final double resolvedStart =
        (startSecond ?? _timelineCenterSecond).clamp(0.0, maxStart).toDouble();
    _clipSeed += 1;
    track.clips.add(
      FusionCutTimelineClip(
        id: '${track.id}_$_clipSeed',
        label: label,
        startSecond: resolvedStart,
        durationSecond: clampedDuration,
        color: color,
        sourceId: sourceId,
        sourceOffsetSecond: sourceOffsetSecond ?? 0.0,
        sourceDurationSecond: sourceDurationSecond ?? clampedDuration,
      ),
    );
    _sortTrack(track);
    notifyListeners();
  }

  void toggleClipSelection(FusionCutTimelineClip clip,
      {int maxSelection = 12}) {
    if (_selectedClipIds.contains(clip.id)) {
      _selectedClipIds.remove(clip.id);
      notifyListeners();
      return;
    }
    while (_selectedClipIds.length >= maxSelection) {
      _selectedClipIds.removeAt(0);
    }
    _selectedClipIds.add(clip.id);
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedClipIds.isEmpty) return;
    _selectedClipIds.clear();
    notifyListeners();
  }

  void beginSelectionDrag() {
    _selectionDragSnapshot = null;
    _selectionDragBaseStarts.clear();
    _selectionDragRequestedDelta = 0.0;
    _selectionGroupMinDelta = 0.0;
    _selectionGroupMaxDelta = 0.0;
    final List<FusionCutTimelineClip> selected = selectedClips();
    if (selected.isEmpty) return;
    _selectionDragSnapshot = _createSnapshot();

    double minStart = double.infinity;
    double maxEnd = -double.infinity;
    for (final FusionCutTimelineClip clip in selected) {
      _selectionDragBaseStarts[clip.id] = clip.startSecond;
      minStart = math.min(minStart, clip.startSecond);
      maxEnd = math.max(maxEnd, clip.startSecond + clip.durationSecond);
    }
    _selectionGroupMinDelta = -minStart;
    _selectionGroupMaxDelta = timelineSeconds - maxEnd;
  }

  void applySelectionDragDelta(double deltaSeconds) {
    if (_selectedClipIds.isEmpty) return;
    _selectionDragRequestedDelta += deltaSeconds;
    final double clampedDelta = _selectionDragRequestedDelta
        .clamp(_selectionGroupMinDelta, _selectionGroupMaxDelta)
        .toDouble();
    final double effectiveDelta = _snapSelectionDelta(clampedDelta)
        .clamp(_selectionGroupMinDelta, _selectionGroupMaxDelta)
        .toDouble();
    bool changed = false;
    for (final String clipId in _selectedClipIds) {
      final FusionCutTimelineClip? clip = findClipById(clipId);
      final double? baseStart = _selectionDragBaseStarts[clipId];
      if (clip == null || baseStart == null) {
        continue;
      }
      final double nextStart = baseStart + effectiveDelta;
      if ((nextStart - clip.startSecond).abs() <= 0.0001) {
        continue;
      }
      clip.startSecond = nextStart;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void endSelectionDrag() {
    bool changed = false;
    for (final MapEntry<String, double> entry
        in _selectionDragBaseStarts.entries) {
      final FusionCutTimelineClip? clip = findClipById(entry.key);
      if (clip == null) continue;
      if ((clip.startSecond - entry.value).abs() > 0.0001) {
        changed = true;
        break;
      }
    }
    if (changed && _selectionDragSnapshot != null) {
      _undoStack.add(_selectionDragSnapshot!);
      _redoStack.clear();
    }
    for (final FusionCutTimelineTrack track in _tracks) {
      _sortTrack(track);
    }
    _selectionDragBaseStarts.clear();
    _selectionDragRequestedDelta = 0.0;
    _selectionGroupMinDelta = 0.0;
    _selectionGroupMaxDelta = 0.0;
    _selectionDragSnapshot = null;
  }

  bool splitPrimarySelectionAt(double second) {
    if (_selectedClipIds.length != 1) return false;
    final FusionCutTimelineClip? clip = findClipById(_selectedClipIds.first);
    final FusionCutTimelineTrack? track =
        trackForClipId(_selectedClipIds.first);
    if (clip == null || track == null) return false;
    final double snappedSecond =
        _snapTimelineSecond(second, excludeClipIds: <String>{clip.id});
    final double splitOffset = snappedSecond - clip.startSecond;
    if (splitOffset <= 0.15 || splitOffset >= clip.durationSecond - 0.15) {
      return false;
    }
    _pushUndoSnapshot();
    _clipSeed += 1;
    final FusionCutTimelineClip trailingClip = FusionCutTimelineClip(
      id: '${track.id}_split_$_clipSeed',
      label: '${clip.label} B',
      startSecond: snappedSecond,
      durationSecond: clip.durationSecond - splitOffset,
      color: clip.color,
      sourceId: clip.sourceId,
      sourceOffsetSecond: clip.sourceOffsetSecond + splitOffset,
      sourceDurationSecond: clip.sourceDurationSecond,
    );
    clip.durationSecond = splitOffset;
    track.clips.add(trailingClip);
    _sortTrack(track);
    _selectedClipIds
      ..clear()
      ..add(clip.id)
      ..add(trailingClip.id);
    notifyListeners();
    return true;
  }

  bool trimPrimarySelectionStartTo(double second) {
    if (_selectedClipIds.length != 1) return false;
    final FusionCutTimelineClip? clip = findClipById(_selectedClipIds.first);
    if (clip == null) return false;
    final double snappedSecond =
        _snapTimelineSecond(second, excludeClipIds: <String>{clip.id});
    final double nextStart = snappedSecond
        .clamp(0.0, clip.startSecond + clip.durationSecond)
        .toDouble();
    final double delta = nextStart - clip.startSecond;
    if (delta <= 0.05 || clip.durationSecond - delta < 0.25) {
      return false;
    }
    _pushUndoSnapshot();
    clip.startSecond = nextStart;
    clip.durationSecond -= delta;
    clip.sourceOffsetSecond = math.min(
      clip.sourceDurationSecond,
      clip.sourceOffsetSecond + delta,
    );
    final FusionCutTimelineTrack? track = trackForClipId(clip.id);
    if (track != null) {
      _sortTrack(track);
    }
    notifyListeners();
    return true;
  }

  bool trimPrimarySelectionEndTo(double second) {
    if (_selectedClipIds.length != 1) return false;
    final FusionCutTimelineClip? clip = findClipById(_selectedClipIds.first);
    if (clip == null) return false;
    final double snappedSecond =
        _snapTimelineSecond(second, excludeClipIds: <String>{clip.id});
    final double nextEnd = snappedSecond
        .clamp(clip.startSecond, clip.startSecond + clip.durationSecond)
        .toDouble();
    final double nextDuration = nextEnd - clip.startSecond;
    if (nextDuration < 0.25 ||
        (nextDuration - clip.durationSecond).abs() <= 0.05) {
      return false;
    }
    _pushUndoSnapshot();
    clip.durationSecond = nextDuration;
    notifyListeners();
    return true;
  }

  bool rippleDeleteSelectedClips() {
    if (_selectedClipIds.isEmpty) return false;
    _pushUndoSnapshot();
    final Set<String> ids = _selectedClipIds.toSet();
    for (final FusionCutTimelineTrack track in _tracks) {
      final List<FusionCutTimelineClip> selectedTrackClips = track.clips
          .where((FusionCutTimelineClip clip) => ids.contains(clip.id))
          .toList();
      if (selectedTrackClips.isEmpty) continue;
      double rangeStart = double.infinity;
      double rangeEnd = -double.infinity;
      for (final FusionCutTimelineClip clip in selectedTrackClips) {
        rangeStart = math.min(rangeStart, clip.startSecond);
        rangeEnd = math.max(rangeEnd, clip.startSecond + clip.durationSecond);
      }
      final double collapseDelta = math.max(0.0, rangeEnd - rangeStart);
      track.clips
          .removeWhere((FusionCutTimelineClip clip) => ids.contains(clip.id));
      for (final FusionCutTimelineClip clip in track.clips) {
        if (clip.startSecond >= rangeEnd - 0.0001) {
          clip.startSecond = math.max(0.0, clip.startSecond - collapseDelta);
        }
      }
      _sortTrack(track);
    }
    _selectedClipIds.clear();
    notifyListeners();
    return true;
  }

  bool deleteSelectedClips() {
    if (_selectedClipIds.isEmpty) return false;
    _pushUndoSnapshot();
    final Set<String> ids = _selectedClipIds.toSet();
    for (final FusionCutTimelineTrack track in _tracks) {
      track.clips
          .removeWhere((FusionCutTimelineClip clip) => ids.contains(clip.id));
    }
    _selectedClipIds.clear();
    notifyListeners();
    return true;
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final _FusionCutHistorySnapshot snapshot = _undoStack.removeLast();
    _redoStack.add(_createSnapshot());
    _applySnapshot(snapshot);
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final _FusionCutHistorySnapshot snapshot = _redoStack.removeLast();
    _undoStack.add(_createSnapshot());
    _applySnapshot(snapshot);
    notifyListeners();
  }

  FusionCutProjectSummary buildSummary() {
    final Map<FusionCutTrackType, int> clipCounts = <FusionCutTrackType, int>{};
    int totalClips = 0;
    for (final FusionCutTimelineTrack track in _tracks) {
      final int count = track.clips.length;
      clipCounts[track.type] = count;
      totalClips += count;
    }
    return FusionCutProjectSummary(
      projectName: _projectName,
      durationSecond: timelineSeconds,
      trackCount: _tracks.length,
      clipCount: totalClips,
      mediaSourceCount: _mediaSources.length,
      clipCountsByTrack: clipCounts,
    );
  }

  FusionCutExportDraft buildExportDraft({
    FusionCutExportPreset preset = FusionCutExportPreset.standard1080p,
  }) {
    return FusionCutExportDraft(
      projectName: _projectName,
      preset: preset,
      summary: buildSummary(),
      tracks:
          _tracks.map((FusionCutTimelineTrack track) => track.copy()).toList(),
      mediaSources: List<FusionCutMediaSource>.from(_mediaSources),
    );
  }

  _FusionCutHistorySnapshot _createSnapshot() {
    return _FusionCutHistorySnapshot(
      projectName: _projectName,
      clipSeed: _clipSeed,
      timelineZoom: _timelineZoom,
      timelineCenterSecond: _timelineCenterSecond,
      hasClearedTemplate: _hasClearedTemplate,
      selectedClipIds: List<String>.from(_selectedClipIds),
      tracks:
          _tracks.map((FusionCutTimelineTrack track) => track.copy()).toList(),
      mediaSources: List<FusionCutMediaSource>.from(_mediaSources),
    );
  }

  void _applySnapshot(_FusionCutHistorySnapshot snapshot) {
    _projectName = snapshot.projectName;
    _clipSeed = snapshot.clipSeed;
    _timelineZoom = snapshot.timelineZoom;
    _timelineCenterSecond = snapshot.timelineCenterSecond;
    _hasClearedTemplate = snapshot.hasClearedTemplate;
    _selectedClipIds
      ..clear()
      ..addAll(snapshot.selectedClipIds);
    _tracks
      ..clear()
      ..addAll(
        snapshot.tracks.map((FusionCutTimelineTrack track) => track.copy()),
      );
    _mediaSources
      ..clear()
      ..addAll(snapshot.mediaSources);
  }

  void _pushUndoSnapshot() {
    _undoStack.add(_createSnapshot());
    _redoStack.clear();
  }

  void _sortTrack(FusionCutTimelineTrack track) {
    track.clips.sort(
      (FusionCutTimelineClip a, FusionCutTimelineClip b) =>
          a.startSecond.compareTo(b.startSecond),
    );
  }

  double _snapSelectionDelta(
    double candidateDelta, {
    double toleranceSecond = 0.16,
  }) {
    if (_selectedClipIds.isEmpty) return candidateDelta;
    final Set<String> selectedIds = _selectedClipIds.toSet();
    final List<double> targets = _buildSnapTargets(
      excludeClipIds: selectedIds,
      includePlayhead: true,
      includeTimelineEnd: true,
    );
    double bestAdjustment = 0.0;
    double bestDistance = toleranceSecond + 1.0;
    for (final String clipId in _selectedClipIds) {
      final FusionCutTimelineClip? clip = findClipById(clipId);
      final double? baseStart = _selectionDragBaseStarts[clipId];
      if (clip == null || baseStart == null) continue;
      final double movedStart = baseStart + candidateDelta;
      final double movedEnd = movedStart + clip.durationSecond;
      for (final double target in targets) {
        final double startDistance = (target - movedStart).abs();
        if (startDistance < bestDistance) {
          bestDistance = startDistance;
          bestAdjustment = target - movedStart;
        }
        final double endDistance = (target - movedEnd).abs();
        if (endDistance < bestDistance) {
          bestDistance = endDistance;
          bestAdjustment = target - movedEnd;
        }
      }
    }
    if (bestDistance <= toleranceSecond) {
      return candidateDelta + bestAdjustment;
    }
    return candidateDelta;
  }

  double _snapTimelineSecond(
    double candidate, {
    Set<String> excludeClipIds = const <String>{},
    double toleranceSecond = 0.16,
  }) {
    final List<double> targets = _buildSnapTargets(
      excludeClipIds: excludeClipIds,
      includePlayhead: false,
      includeTimelineEnd: true,
    );
    double bestTarget = candidate;
    double bestDistance = toleranceSecond + 1.0;
    for (final double target in targets) {
      final double distance = (target - candidate).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestTarget = target;
      }
    }
    return bestDistance <= toleranceSecond ? bestTarget : candidate;
  }

  List<double> _buildSnapTargets({
    Set<String> excludeClipIds = const <String>{},
    bool includePlayhead = false,
    bool includeTimelineEnd = false,
  }) {
    final List<double> targets = <double>[0.0];
    if (includePlayhead) {
      targets.add(_timelineCenterSecond);
    }
    if (includeTimelineEnd) {
      targets.add(timelineSeconds);
    }
    for (final FusionCutTimelineTrack track in _tracks) {
      for (final FusionCutTimelineClip clip in track.clips) {
        if (excludeClipIds.contains(clip.id)) continue;
        targets.add(clip.startSecond);
        targets.add(clip.startSecond + clip.durationSecond);
      }
    }
    return targets;
  }
}
