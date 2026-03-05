import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:wonderpic/services/wonderpic_library_store.dart';

const Color _kVoicePageBg = Color(0xFF1B1E24);
const Color _kVoiceCardBg = Color(0xFF141820);
const Color _kVoiceStroke = Color(0xFF4B4A48);
const Color _kVoiceTextMain = Color(0xFFF3F3F2);
const Color _kVoiceTextSub = Color(0xFFB8B7B5);
const Color _kVoiceActiveAccent = Color(0xFFE6F24A);
const Color _kVoiceActiveAccentForeground = Color(0xFF19191A);
const String _kDefaultSupabaseUrl = 'https://pamlemagzhikexxmaxfz.supabase.co';
const String _kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: _kDefaultSupabaseUrl,
);

const String _kEmbeddedElevenLabsApiKey = '';

bool _isSupabaseVoiceProxyConfigured() {
  final String raw = _kSupabaseUrl.trim();
  if (raw.isEmpty) return false;
  final Uri? uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    return false;
  }
  final String scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

Uri _elevenLabsProxyUri(String upstreamPath) {
  final Uri base = Uri.parse('$_kSupabaseUrl/functions/v1/elevenlabs-proxy');
  return base.replace(
    queryParameters: <String, String>{'path': upstreamPath},
  );
}

enum _VoiceMode { tts, clone }

enum _VoiceSource { account, library }

class _VoiceQualityProfile {
  final double stability;
  final double similarity;
  final double style;
  final double speed;

  const _VoiceQualityProfile({
    required this.stability,
    required this.similarity,
    required this.style,
    required this.speed,
  });
}

class _TtsModel {
  final String id;
  final String name;
  final bool canUseStyle;
  final bool canUseSpeakerBoost;
  final Set<String> supportedLanguages;

  const _TtsModel({
    required this.id,
    required this.name,
    required this.canUseStyle,
    required this.canUseSpeakerBoost,
    required this.supportedLanguages,
  });
}

class _VoicePreset {
  final String id;
  final String label;
  final String language;
  final String accent;
  final String gender;
  final String age;
  final String? locale;
  final String? previewUrl;
  final bool isOwned;
  final bool isIraqiHint;

  const _VoicePreset({
    required this.id,
    required this.label,
    required this.language,
    required this.accent,
    required this.gender,
    required this.age,
    required this.locale,
    required this.previewUrl,
    required this.isOwned,
    required this.isIraqiHint,
  });
}

class WonderPicElevenLabsVoiceScreen extends StatefulWidget {
  const WonderPicElevenLabsVoiceScreen({super.key});

  @override
  State<WonderPicElevenLabsVoiceScreen> createState() =>
      _WonderPicElevenLabsVoiceScreenState();
}

class _WonderPicElevenLabsVoiceScreenState
    extends State<WonderPicElevenLabsVoiceScreen> {
  static const Map<String, String> _languageOptions = <String, String>{
    'en': 'English',
    'ar': 'Arabic',
  };
  static const Map<String, _VoiceQualityProfile> _qualityProfiles =
      <String, _VoiceQualityProfile>{
    'Creative': _VoiceQualityProfile(
      stability: 0.35,
      similarity: 0.70,
      style: 0.55,
      speed: 1.00,
    ),
    'Balanced': _VoiceQualityProfile(
      stability: 0.50,
      similarity: 0.82,
      style: 0.25,
      speed: 0.92,
    ),
    'Stable': _VoiceQualityProfile(
      stability: 0.72,
      similarity: 0.92,
      style: 0.10,
      speed: 0.88,
    ),
  };
  static const Map<String, String> _sourceLabels = <String, String>{
    'account': 'My Voices',
    'library': 'Voice Library',
  };
  static const Map<String, String> _audioOutputFormats = <String, String>{
    'mp3_44100_128': 'High (MP3 44.1kHz)',
    'mp3_22050_32': 'Fast (MP3 22kHz)',
  };
  static const List<String> _enhanceAudioTags = <String>[
    '[laughs]',
    '[starts laughing]',
    '[whispers]',
    '[shouts]',
    '[curious]',
    '[excited]',
    '[sarcastic]',
    '[sighs]',
    '[exhales]',
    '[clears throat]',
    '[crying]',
    '[snorts]',
    '[mischievously]',
    '[pause]',
  ];

  final TextEditingController _textController = TextEditingController();
  final TextEditingController _cloneNameController = TextEditingController();
  final TextEditingController _cloneDescriptionController =
      TextEditingController();
  final WonderPicLibraryStore _libraryStore = WonderPicLibraryStore();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _sampleRecorder = AudioRecorder();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Timer? _cloneRecordingTicker;

  bool _isLoadingVoices = false;
  bool _isLoadingModels = false;
  bool _isGenerating = false;
  bool _isCloning = false;
  bool _isDownloading = false;
  bool _isPreviewGenerating = false;
  bool _audioPlaybackSupported = true;
  bool _isPlaying = false;
  bool _isRecordingCloneSample = false;
  bool _removeCloneNoise = false;
  bool _isSeekDragging = false;
  bool _playbackCompleted = false;
  bool _isSpeechReady = false;
  bool _isListeningToPrompt = false;
  double _seekDragMs = 0;
  String _voiceTypingBaseText = '';
  String? _lastSpeechLocaleId;

  _VoiceMode _mode = _VoiceMode.tts;
  _VoiceSource _voiceSource = _VoiceSource.account;
  String _languageCode = 'en';
  String _selectedVoiceId = '';
  String _selectedArabicAccent = 'all';
  String _selectedQuality = 'Balanced';
  String _selectedModelId = 'eleven_v3';
  String _selectedOutputFormat = 'mp3_44100_128';
  double _stability = 0.50;
  double _similarity = 0.82;
  double _style = 0.25;
  double _speed = 0.92;
  bool _useSpeakerBoost = true;

  String? _statusMessage;
  String? _resultAudioPath;
  String? _loadedAudioSource;
  bool _loadedAudioIsLocal = false;
  String? _lastDownloadedFilePath;
  String? _latestCloneSamplePath;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  Duration _cloneRecordingDuration = Duration.zero;

  List<PlatformFile> _cloneFiles = <PlatformFile>[];
  List<_TtsModel> _allTtsModels = <_TtsModel>[];
  final Map<String, String> _generatedPreviewCache = <String, String>{};
  final Map<String, List<_VoicePreset>> _accountVoicesByLanguage =
      <String, List<_VoicePreset>>{
    'en': <_VoicePreset>[],
    'ar': <_VoicePreset>[],
  };
  final Map<String, List<_VoicePreset>> _libraryVoicesByLanguage =
      <String, List<_VoicePreset>>{
    'en': <_VoicePreset>[],
    'ar': <_VoicePreset>[],
  };

  String get _elevenLabsApiKey {
    if (_isSupabaseVoiceProxyConfigured()) {
      return 'edge-proxy';
    }
    return _kEmbeddedElevenLabsApiKey;
  }

  Map<String, List<_VoicePreset>> get _activeVoicesByLanguage {
    return _voiceSource == _VoiceSource.account
        ? _accountVoicesByLanguage
        : _libraryVoicesByLanguage;
  }

  List<_VoicePreset> get _allCurrentVoices {
    return _activeVoicesByLanguage[_languageCode] ?? const <_VoicePreset>[];
  }

  List<_VoicePreset> get _currentVoiceOptions {
    final List<_VoicePreset> voices = _allCurrentVoices;
    if (_languageCode != 'ar' || _selectedArabicAccent == 'all') {
      return voices;
    }
    if (_selectedArabicAccent == 'iraqi') {
      return voices.where((voice) => voice.isIraqiHint).toList(growable: false);
    }
    return voices
        .where(
          (voice) => voice.accent.toLowerCase().trim() == _selectedArabicAccent,
        )
        .toList(growable: false);
  }

  _VoicePreset? get _selectedVoice {
    final String selectedId = _selectedVoiceId.trim();
    if (selectedId.isEmpty) return null;
    for (final _VoicePreset voice in _allCurrentVoices) {
      if (voice.id == selectedId) return voice;
    }
    return null;
  }

  _TtsModel? get _selectedModel {
    for (final _TtsModel model in _currentModelOptions) {
      if (model.id == _selectedModelId) return model;
    }
    return null;
  }

  List<_TtsModel> get _currentModelOptions {
    if (_allTtsModels.isEmpty) return const <_TtsModel>[];
    final List<_TtsModel> filtered = _allTtsModels.where((model) {
      if (model.supportedLanguages.isEmpty) return true;
      return model.supportedLanguages.contains(_languageCode);
    }).toList(growable: false);
    return filtered.isEmpty ? _allTtsModels : filtered;
  }

  String get _previewCacheKey =>
      '$_languageCode|$_selectedVoiceId|$_selectedModelId|$_selectedOutputFormat|${_stability.toStringAsFixed(2)}|${_similarity.toStringAsFixed(2)}|${_style.toStringAsFixed(2)}|${_speed.toStringAsFixed(2)}|${_useSpeakerBoost ? "1" : "0"}';

  bool get _isCurrentPreviewPlaying {
    final _VoicePreset? voice = _selectedVoice;
    final String? voicePreview = voice?.previewUrl?.trim();
    if (voicePreview != null && voicePreview.isNotEmpty) {
      return _isPlaying &&
          !_loadedAudioIsLocal &&
          _loadedAudioSource == voicePreview;
    }
    final String? generatedPreviewPath =
        _generatedPreviewCache[_previewCacheKey];
    if (generatedPreviewPath == null || generatedPreviewPath.isEmpty) {
      return false;
    }
    return _isPlaying &&
        _loadedAudioIsLocal &&
        _loadedAudioSource == generatedPreviewPath;
  }

  List<String> get _arabicAccentOptions {
    final List<_VoicePreset> voices =
        _activeVoicesByLanguage['ar'] ?? <_VoicePreset>[];
    final Set<String> accents = <String>{};
    bool hasIraqi = false;
    for (final _VoicePreset voice in voices) {
      final String accent = voice.accent.trim().toLowerCase();
      if (accent.isNotEmpty) accents.add(accent);
      if (voice.isIraqiHint) hasIraqi = true;
    }
    final List<String> ordered = <String>['all'];
    if (hasIraqi) ordered.add('iraqi');
    final List<String> sorted = accents.toList()..sort();
    for (final String accent in sorted) {
      if (!ordered.contains(accent)) ordered.add(accent);
    }
    return ordered;
  }

  @override
  void initState() {
    super.initState();
    _cloneNameController.text = 'Iraqi Voice Clone';
    _applyQualityProfile(_selectedQuality, silent: true);
    _bindAudioPlayer();
    unawaited(_loadVoices());
    unawaited(_loadModels());
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _cloneRecordingTicker?.cancel();
    try {
      _sampleRecorder.dispose();
    } catch (_) {}
    try {
      _audioPlayer.dispose();
    } catch (_) {}
    try {
      _speechToText.stop();
    } catch (_) {}
    _textController.dispose();
    _cloneNameController.dispose();
    _cloneDescriptionController.dispose();
    super.dispose();
  }

  void _bindAudioPlayer() {
    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        if (state == PlayerState.completed) {
          _isPlaying = false;
          _playbackCompleted = true;
          _audioPosition = _audioDuration;
        } else {
          _isPlaying = state == PlayerState.playing;
        }
      });
    });
    _durationSub = _audioPlayer.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() {
        _audioDuration = duration;
      });
    });
    _positionSub = _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() {
        _audioPosition = position;
      });
    });
  }

  bool _looksIraqi({
    required String name,
    required String accent,
    required String locale,
    required String description,
  }) {
    final String haystack =
        '$name $accent $locale $description'.toLowerCase().trim();
    return haystack.contains('iraq') ||
        haystack.contains('iraqi') ||
        haystack.contains('ar-iq') ||
        haystack.contains('عراق');
  }

  bool _containsArabicScript(String input) {
    final RegExp pattern = RegExp(r'[\u0600-\u06FF]');
    return pattern.hasMatch(input);
  }

  String _normalizeLanguageCode(String raw) {
    final String value = raw.trim().toLowerCase();
    if (value.startsWith('ar')) return 'ar';
    if (value.startsWith('en')) return 'en';
    return value;
  }

  int _extractModelMajorVersion(String modelId) {
    final RegExpMatch? match =
        RegExp(r'v(\d+)', caseSensitive: false).firstMatch(modelId);
    if (match == null) return -1;
    return int.tryParse(match.group(1) ?? '') ?? -1;
  }

  bool _isModernTtsModel(String modelId) {
    return _extractModelMajorVersion(modelId) >= 3;
  }

  int _compareTtsModels(_TtsModel a, _TtsModel b) {
    final int aVersion = _extractModelMajorVersion(a.id);
    final int bVersion = _extractModelMajorVersion(b.id);
    final int versionCmp = bVersion.compareTo(aVersion);
    if (versionCmp != 0) return versionCmp;
    final int nameCmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (nameCmp != 0) return nameCmp;
    return a.id.toLowerCase().compareTo(b.id.toLowerCase());
  }

  String _recommendedModelIdForLanguage(String languageCode) {
    final List<_TtsModel> current = List<_TtsModel>.from(_currentModelOptions);
    final List<_TtsModel> languageMatched = current.where((model) {
      if (model.supportedLanguages.isEmpty) return true;
      return model.supportedLanguages.contains(languageCode);
    }).toList(growable: false);
    if (languageMatched.isNotEmpty) {
      final List<_TtsModel> sorted = List<_TtsModel>.from(languageMatched)
        ..sort(_compareTtsModels);
      return sorted.first.id;
    }
    if (current.isNotEmpty) {
      current.sort(_compareTtsModels);
      return current.first.id;
    }
    return _selectedModelId;
  }

  void _syncSelectedVoiceForCurrentContext() {
    final List<_VoicePreset> available = _currentVoiceOptions;
    if (available.isNotEmpty) {
      final bool selectedStillExists =
          available.any((voice) => voice.id.trim() == _selectedVoiceId.trim());
      if (!selectedStillExists) {
        _selectedVoiceId = available.first.id;
      }
      return;
    }
    final List<_VoicePreset> all = _allCurrentVoices;
    if (all.isNotEmpty) {
      _selectedVoiceId = all.first.id;
    }
  }

  void _syncSelectedModelForCurrentLanguage() {
    final List<_TtsModel> options = _currentModelOptions;
    if (options.isEmpty) return;
    final bool selectedExists =
        options.any((model) => model.id == _selectedModelId);
    if (selectedExists) return;
    _selectedModelId = _recommendedModelIdForLanguage(_languageCode);
  }

  void _applyQualityProfile(String label, {bool silent = false}) {
    final _VoiceQualityProfile profile =
        _qualityProfiles[label] ?? _qualityProfiles['Balanced']!;
    _selectedQuality = label;
    _stability = profile.stability;
    _similarity = profile.similarity;
    _style = profile.style;
    _speed = profile.speed;
    _useSpeakerBoost = label != 'Creative';
    if (!silent && mounted) {
      setState(() {});
    }
  }

  bool _isAudioPluginMissingError(Object error) {
    if (error is MissingPluginException) return true;
    if (error is PlatformException) {
      final String details = [
        error.code,
        error.message ?? '',
        error.details?.toString() ?? '',
      ].join(' ').toLowerCase();
      if (details.contains('audioplayers') ||
          details.contains('xyz.luan') ||
          details.contains('no implementation found')) {
        return true;
      }
    }
    final String text = error.toString().toLowerCase();
    return text.contains('missingpluginexception') &&
        text.contains('audioplayers');
  }

  void _markAudioPreviewUnsupported() {
    if (_audioPlaybackSupported) {
      if (mounted) {
        setState(() {
          _audioPlaybackSupported = false;
          _statusMessage =
              'Voice generated. Preview player unavailable in this build.';
        });
      } else {
        _audioPlaybackSupported = false;
      }
    }
  }

  Future<Map<String, dynamic>> _decodeJsonResponse(
    http.Response response, {
    required String contextLabel,
  }) async {
    final String body = utf8.decode(response.bodyBytes);
    final dynamic decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$contextLabel response is invalid.');
    }
    return decoded;
  }

  Future<List<dynamic>> _decodeJsonListResponse(
    http.Response response, {
    required String contextLabel,
  }) async {
    final String body = utf8.decode(response.bodyBytes);
    final dynamic decoded = jsonDecode(body);
    if (decoded is! List<dynamic>) {
      throw FormatException('$contextLabel response is invalid.');
    }
    return decoded;
  }

  String _parseElevenLabsError(
    int statusCode,
    String body, {
    required String fallback,
  }) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final dynamic detail = decoded['detail'];
        if (detail is Map<String, dynamic>) {
          final String message =
              (detail['message'] as String?)?.trim() ?? fallback;
          return 'ElevenLabs error ($statusCode): $message';
        }
        if (detail is String && detail.trim().isNotEmpty) {
          return 'ElevenLabs error ($statusCode): ${detail.trim()}';
        }
      }
    } catch (_) {}
    return 'ElevenLabs error ($statusCode): $fallback';
  }

  Future<List<_VoicePreset>> _fetchAccountVoices() async {
    final Uri uri = _elevenLabsProxyUri('/v1/voices?show_legacy=true');
    final http.Response response = await http.get(
      uri,
      headers: <String, String>{
        'xi-api-key': _elevenLabsApiKey,
        'accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        _parseElevenLabsError(
          response.statusCode,
          utf8.decode(response.bodyBytes),
          fallback: 'Unable to fetch account voices.',
        ),
      );
    }
    final Map<String, dynamic> decoded = await _decodeJsonResponse(
      response,
      contextLabel: 'ElevenLabs account voices',
    );
    final List<dynamic> voicesRaw = decoded['voices'] is List
        ? decoded['voices'] as List<dynamic>
        : <dynamic>[];
    final List<_VoicePreset> voices = <_VoicePreset>[];
    for (final dynamic entry in voicesRaw) {
      if (entry is! Map<String, dynamic>) continue;
      final String voiceId = (entry['voice_id'] as String?)?.trim() ?? '';
      final String name = (entry['name'] as String?)?.trim() ?? '';
      if (voiceId.isEmpty || name.isEmpty) continue;
      final bool isOwner = entry['is_owner'] == true;
      final Map<String, dynamic> labels =
          entry['labels'] is Map<String, dynamic>
              ? entry['labels'] as Map<String, dynamic>
              : <String, dynamic>{};
      final String labelsLanguage =
          _normalizeLanguageCode((labels['language'] as String?) ?? '');
      final String labelsAccent = (labels['accent'] as String?)?.trim() ?? '';
      final String labelsGender = (labels['gender'] as String?)?.trim() ?? '';
      final String labelsAge = (labels['age'] as String?)?.trim() ?? '';
      final String description =
          (entry['description'] as String?)?.trim() ?? '';
      final String previewUrl = (entry['preview_url'] as String?)?.trim() ?? '';
      final List<dynamic> verifiedRaw = entry['verified_languages'] is List
          ? entry['verified_languages'] as List<dynamic>
          : <dynamic>[];
      final Set<String> supportedLanguages = <String>{};
      final Map<String, String> accentByLanguage = <String, String>{};
      final Map<String, String> localeByLanguage = <String, String>{};
      if (labelsLanguage == 'en' || labelsLanguage == 'ar') {
        supportedLanguages.add(labelsLanguage);
      }
      for (final dynamic item in verifiedRaw) {
        if (item is! Map<String, dynamic>) continue;
        final String language =
            _normalizeLanguageCode((item['language'] as String?) ?? '');
        if (language != 'en' && language != 'ar') continue;
        supportedLanguages.add(language);
        final String accent = (item['accent'] as String?)?.trim() ?? '';
        if (accent.isNotEmpty && !accentByLanguage.containsKey(language)) {
          accentByLanguage[language] = accent;
        }
        final String locale = (item['locale'] as String?)?.trim() ?? '';
        if (locale.isNotEmpty && !localeByLanguage.containsKey(language)) {
          localeByLanguage[language] = locale;
        }
      }
      if (supportedLanguages.isEmpty && isOwner) {
        final bool likelyArabic = _containsArabicScript('$name $description') ||
            labelsLanguage == 'ar';
        if (likelyArabic) {
          supportedLanguages.add('ar');
        } else {
          supportedLanguages.addAll(const <String>{'en', 'ar'});
        }
      }
      if (supportedLanguages.isEmpty) {
        supportedLanguages.add('en');
      }
      for (final String language in supportedLanguages) {
        if (language != 'en' && language != 'ar') continue;
        final String accent = accentByLanguage[language] ?? labelsAccent;
        final String locale = localeByLanguage[language] ?? '';
        voices.add(
          _VoicePreset(
            id: voiceId,
            label: name,
            language: language,
            accent: accent,
            gender: labelsGender,
            age: labelsAge,
            locale: locale.isEmpty ? null : locale,
            previewUrl: previewUrl.isEmpty ? null : previewUrl,
            isOwned: isOwner,
            isIraqiHint: _looksIraqi(
              name: name,
              accent: accent,
              locale: locale,
              description: description,
            ),
          ),
        );
      }
    }
    return voices;
  }

  Future<List<_VoicePreset>> _fetchSharedVoices(String languageCode) async {
    int page = 1;
    bool hasMore = true;
    int safety = 0;
    final List<_VoicePreset> all = <_VoicePreset>[];
    while (hasMore && safety < 10) {
      safety++;
      final Map<String, String> query = <String, String>{
        'language': languageCode,
        'page_size': '100',
        'page': '$page',
      };
      final String queryString = query.entries
          .map((entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
          .join('&');
      final Uri uri = _elevenLabsProxyUri('/v1/shared-voices?$queryString');
      final http.Response response = await http.get(
        uri,
        headers: <String, String>{
          'xi-api-key': _elevenLabsApiKey,
          'accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 40));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          _parseElevenLabsError(
            response.statusCode,
            utf8.decode(response.bodyBytes),
            fallback: 'Unable to fetch shared voices.',
          ),
        );
      }
      final Map<String, dynamic> decoded = await _decodeJsonResponse(
        response,
        contextLabel: 'ElevenLabs shared voices',
      );
      final List<dynamic> voicesRaw = decoded['voices'] is List
          ? decoded['voices'] as List<dynamic>
          : <dynamic>[];
      for (final dynamic entry in voicesRaw) {
        if (entry is! Map<String, dynamic>) continue;
        final String voiceId = (entry['voice_id'] as String?)?.trim() ?? '';
        final String name = (entry['name'] as String?)?.trim() ?? '';
        if (voiceId.isEmpty || name.isEmpty) continue;
        final String accent = (entry['accent'] as String?)?.trim() ?? '';
        final String locale = (entry['locale'] as String?)?.trim() ?? '';
        final String gender = (entry['gender'] as String?)?.trim() ?? '';
        final String age = (entry['age'] as String?)?.trim() ?? '';
        final String description =
            (entry['description'] as String?)?.trim() ?? '';
        final String previewUrl =
            (entry['preview_url'] as String?)?.trim() ?? '';
        all.add(
          _VoicePreset(
            id: voiceId,
            label: name,
            language: languageCode,
            accent: accent,
            gender: gender,
            age: age,
            locale: locale.isEmpty ? null : locale,
            previewUrl: previewUrl.isEmpty ? null : previewUrl,
            isOwned: false,
            isIraqiHint: _looksIraqi(
              name: name,
              accent: accent,
              locale: locale,
              description: description,
            ),
          ),
        );
      }
      hasMore = decoded['has_more'] == true;
      page += 1;
    }
    return all;
  }

  List<_VoicePreset> _dedupeVoices(List<_VoicePreset> voices) {
    final Map<String, _VoicePreset> map = <String, _VoicePreset>{};
    for (final _VoicePreset voice in voices) {
      if (!map.containsKey(voice.id)) {
        map[voice.id] = voice;
        continue;
      }
      final _VoicePreset existing = map[voice.id]!;
      if (!existing.isOwned && voice.isOwned) {
        map[voice.id] = voice;
      }
    }
    final List<_VoicePreset> deduped = map.values.toList(growable: false);
    deduped.sort((a, b) {
      if (a.isIraqiHint && !b.isIraqiHint) return -1;
      if (!a.isIraqiHint && b.isIraqiHint) return 1;
      if (a.isOwned && !b.isOwned) return -1;
      if (!a.isOwned && b.isOwned) return 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return deduped;
  }

  Future<List<_TtsModel>> _fetchTtsModels() async {
    final Uri uri = _elevenLabsProxyUri('/v1/models');
    final http.Response response = await http.get(
      uri,
      headers: <String, String>{
        'xi-api-key': _elevenLabsApiKey,
        'accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        _parseElevenLabsError(
          response.statusCode,
          utf8.decode(response.bodyBytes),
          fallback: 'Unable to fetch models.',
        ),
      );
    }
    final List<dynamic> decoded = await _decodeJsonListResponse(
      response,
      contextLabel: 'ElevenLabs models',
    );
    final List<_TtsModel> models = <_TtsModel>[];
    for (final dynamic item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      if (item['can_do_text_to_speech'] != true) continue;
      final String modelId = (item['model_id'] as String?)?.trim() ?? '';
      final String name = (item['name'] as String?)?.trim() ?? modelId;
      if (modelId.isEmpty) continue;
      if (!_isModernTtsModel(modelId)) continue;
      final List<dynamic> languagesRaw = item['languages'] is List
          ? item['languages'] as List<dynamic>
          : <dynamic>[];
      final Set<String> supportedLanguages = <String>{};
      for (final dynamic languageEntry in languagesRaw) {
        if (languageEntry is! Map<String, dynamic>) continue;
        final String language = _normalizeLanguageCode(
            (languageEntry['language_id'] as String?) ?? '');
        if (language.isNotEmpty) {
          supportedLanguages.add(language);
        }
      }
      models.add(
        _TtsModel(
          id: modelId,
          name: name,
          canUseStyle: item['can_use_style'] == true,
          canUseSpeakerBoost: item['can_use_speaker_boost'] == true,
          supportedLanguages: supportedLanguages,
        ),
      );
    }
    models.sort(_compareTtsModels);
    return models;
  }

  Future<void> _loadModels({bool announce = false}) async {
    if (_isLoadingModels) return;
    setState(() {
      _isLoadingModels = true;
    });
    try {
      final List<_TtsModel> fetched = await _fetchTtsModels();
      if (!mounted) return;
      setState(() {
        _allTtsModels = fetched;
        _syncSelectedModelForCurrentLanguage();
      });
      if (announce) {
        _showMessage('Models refreshed.');
      }
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingModels = false;
        });
      }
    }
  }

  Future<void> _loadVoices({bool announce = false}) async {
    if (_isLoadingVoices) return;
    final String apiKey = _elevenLabsApiKey.trim();
    if (apiKey.isEmpty) {
      _showMessage(
        'ElevenLabs backend proxy is not configured. Add --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_PUBLISHABLE_KEY=...',
        isError: true,
      );
      return;
    }
    setState(() {
      _isLoadingVoices = true;
      _statusMessage = 'Loading ElevenLabs voice libraries...';
    });
    try {
      final List<dynamic> fetched =
          await Future.wait<dynamic>(<Future<dynamic>>[
        _fetchAccountVoices(),
        _fetchSharedVoices('en'),
        _fetchSharedVoices('ar'),
      ]);
      final List<_VoicePreset> account = fetched[0] as List<_VoicePreset>;
      final List<_VoicePreset> ownedOnly =
          account.where((voice) => voice.isOwned).toList(growable: false);
      final List<_VoicePreset> sharedEn = fetched[1] as List<_VoicePreset>;
      final List<_VoicePreset> sharedAr = fetched[2] as List<_VoicePreset>;
      final List<_VoicePreset> accountEn = ownedOnly
          .where((voice) => voice.language == 'en')
          .toList(growable: false);
      final List<_VoicePreset> accountAr = ownedOnly
          .where((voice) => voice.language == 'ar')
          .toList(growable: false);
      final List<_VoicePreset> accountEnVoices = _dedupeVoices(accountEn);
      final List<_VoicePreset> accountArVoices = _dedupeVoices(accountAr);
      final List<_VoicePreset> libraryEnVoices = _dedupeVoices(sharedEn);
      final List<_VoicePreset> libraryArVoices = _dedupeVoices(sharedAr);
      if (!mounted) return;
      setState(() {
        _accountVoicesByLanguage['en'] = accountEnVoices;
        _accountVoicesByLanguage['ar'] = accountArVoices;
        _libraryVoicesByLanguage['en'] = libraryEnVoices;
        _libraryVoicesByLanguage['ar'] = libraryArVoices;
        _syncSelectedVoiceForCurrentContext();
        _syncSelectedModelForCurrentLanguage();
        if (_selectedArabicAccent != 'all' &&
            !_arabicAccentOptions.contains(_selectedArabicAccent)) {
          _selectedArabicAccent = 'all';
        }
        _statusMessage =
            'Voices updated: ${accountArVoices.length + accountEnVoices.length} account, ${libraryArVoices.length + libraryEnVoices.length} library.';
      });
      if (announce) {
        _showMessage('Voice libraries refreshed.');
      }
    } catch (error) {
      _showMessage(error.toString(), isError: true);
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to load voices.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVoices = false;
        });
      }
    }
  }

  String _samplePreviewText(String languageCode) {
    if (languageCode == 'ar') {
      return 'شلونكم، هذا اختبار سريع للصوت باللهجة العراقية الطبيعية.';
    }
    return 'Hello, this is a quick preview sample.';
  }

  String _safeAudioExtensionFromContentType(String? contentType) {
    final String type = (contentType ?? '').toLowerCase();
    if (type.contains('audio/mpeg') || type.contains('audio/mp3')) {
      return 'mp3';
    }
    if (type.contains('audio/wav') || type.contains('audio/x-wav')) {
      return 'wav';
    }
    if (type.contains('audio/ogg')) return 'ogg';
    if (type.contains('audio/aac')) return 'aac';
    return 'mp3';
  }

  Future<String> _synthesizeSpeechToTempFile({
    required String voiceId,
    required String text,
    required String languageCode,
  }) async {
    final _TtsModel? model = _selectedModel;
    if (model == null) {
      throw StateError(
        'No supported TTS model available for selected language.',
      );
    }
    final Uri baseUri = _elevenLabsProxyUri('/v1/text-to-speech/$voiceId');
    final Uri uriWithFormat = _selectedOutputFormat.trim().isEmpty
        ? baseUri
        : baseUri.replace(queryParameters: <String, String>{
            'output_format': _selectedOutputFormat,
          });
    final Map<String, dynamic> voiceSettings = <String, dynamic>{
      'stability': double.parse(_stability.toStringAsFixed(2)),
      'similarity_boost': double.parse(_similarity.toStringAsFixed(2)),
      'speed': double.parse(_speed.toStringAsFixed(2)),
    };
    if (model.canUseStyle) {
      voiceSettings['style'] = double.parse(_style.toStringAsFixed(2));
    }
    if (model.canUseSpeakerBoost) {
      voiceSettings['use_speaker_boost'] = _useSpeakerBoost;
    }
    final Map<String, dynamic> payload = <String, dynamic>{
      'text': text,
      'model_id': model.id,
      'language_code': languageCode,
      'voice_settings': voiceSettings,
      'apply_text_normalization': 'auto',
    };
    Future<http.Response> postRequest(Uri uri) {
      return http
          .post(
            uri,
            headers: <String, String>{
              'xi-api-key': _elevenLabsApiKey,
              'accept': 'audio/mpeg',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(minutes: 2));
    }

    http.Response response = await postRequest(uriWithFormat);
    if ((response.statusCode < 200 || response.statusCode >= 300) &&
        uriWithFormat != baseUri) {
      final String bodyLower = utf8.decode(response.bodyBytes).toLowerCase();
      if (bodyLower.contains('output_format')) {
        response = await postRequest(baseUri);
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        _parseElevenLabsError(
          response.statusCode,
          utf8.decode(response.bodyBytes),
          fallback: 'Text-to-speech generation failed.',
        ),
      );
    }
    if (response.bodyBytes.isEmpty) {
      throw const FormatException('ElevenLabs returned empty audio.');
    }
    final String extension =
        _safeAudioExtensionFromContentType(response.headers['content-type']);
    final String path =
        '${Directory.systemTemp.path}/wonderpic_voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final File file = File(path);
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return path;
  }

  Future<void> _prepareAudio(String source, {required bool isLocal}) async {
    try {
      await _loadAudioSource(source, autoplay: false, isLocal: isLocal);
    } catch (error) {
      if (_isAudioPluginMissingError(error)) {
        _markAudioPreviewUnsupported();
        return;
      }
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Voice generated but preview is unavailable.';
      });
    }
  }

  Future<void> _loadAudioSource(
    String source, {
    required bool autoplay,
    required bool isLocal,
  }) async {
    await _audioPlayer.stop();
    if (mounted) {
      setState(() {
        _audioPosition = Duration.zero;
        _audioDuration = Duration.zero;
        _playbackCompleted = false;
        _isSeekDragging = false;
        _seekDragMs = 0;
      });
    }
    if (isLocal) {
      await _audioPlayer.setSourceDeviceFile(source);
    } else {
      await _audioPlayer.setSourceUrl(source);
    }
    if (mounted) {
      setState(() {
        _loadedAudioSource = source;
        _loadedAudioIsLocal = isLocal;
        _playbackCompleted = false;
      });
    } else {
      _loadedAudioSource = source;
      _loadedAudioIsLocal = isLocal;
      _playbackCompleted = false;
    }
    if (autoplay) {
      await _audioPlayer.resume();
    }
  }

  Future<void> _generateVoice() async {
    if (_isGenerating) return;
    final String text = _textController.text.trim();
    if (text.isEmpty) {
      _showMessage('Write the text first.', isError: true);
      return;
    }
    final String apiKey = _elevenLabsApiKey.trim();
    if (apiKey.isEmpty) {
      _showMessage(
        'ElevenLabs backend proxy is not configured. Add --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_PUBLISHABLE_KEY=...',
        isError: true,
      );
      return;
    }
    final _VoicePreset? selectedVoice = _selectedVoice;
    if (selectedVoice == null) {
      _showMessage('Choose a voice first.', isError: true);
      return;
    }
    if (_selectedModel == null) {
      _showMessage('Choose a supported model first.', isError: true);
      return;
    }
    if (_selectedModel == null) {
      _showMessage('Choose a supported model first.', isError: true);
      return;
    }
    setState(() {
      _isGenerating = true;
      _statusMessage = 'Generating voice with ElevenLabs...';
      _resultAudioPath = null;
      _lastDownloadedFilePath = null;
      _audioPosition = Duration.zero;
      _audioDuration = Duration.zero;
    });
    try {
      final String path = await _synthesizeSpeechToTempFile(
        voiceId: selectedVoice.id,
        text: text,
        languageCode: _languageCode,
      );
      if (!mounted) return;
      setState(() {
        _resultAudioPath = path;
        _statusMessage = 'Voice generated successfully.';
      });
      unawaited(
        _recordGeneratedVoiceInLibrary(
          text: text,
          localPath: path,
          voiceLabel: selectedVoice.label,
        ),
      );
      await _prepareAudio(path, isLocal: true);
      _showMessage('Voice generated.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Voice generation failed.';
      });
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _recordGeneratedVoiceInLibrary({
    required String text,
    required String localPath,
    required String voiceLabel,
  }) async {
    final String clean = text.trim();
    final String title = clean.isEmpty
        ? 'Generated voice'
        : (clean.length <= 52 ? clean : '${clean.substring(0, 52)}...');
    await _libraryStore.addItem(
      WonderPicLibraryItem(
        id: 'voice_${DateTime.now().microsecondsSinceEpoch}',
        type: WonderPicLibraryItemType.voice,
        title: title,
        subtitle: voiceLabel.trim().isEmpty ? 'Voice generation' : voiceLabel,
        createdAtIso: DateTime.now().toUtc().toIso8601String(),
        localPath: localPath.trim().isEmpty ? null : localPath.trim(),
      ),
    );
  }

  Future<void> _toggleVoicePreview() async {
    if (_isGenerating || _isPreviewGenerating || !_audioPlaybackSupported) {
      if (!_audioPlaybackSupported) {
        _showMessage(
          'Preview player unavailable in this build. Use Generate + Download.',
        );
      }
      return;
    }
    final _VoicePreset? selectedVoice = _selectedVoice;
    if (selectedVoice == null) {
      _showMessage('Choose a voice first.', isError: true);
      return;
    }
    final String? remotePreview = selectedVoice.previewUrl?.trim();
    final bool hasRemotePreview =
        remotePreview != null && remotePreview.isNotEmpty;
    final String? cachedGenerated = _generatedPreviewCache[_previewCacheKey];
    final String? currentPreviewSource =
        hasRemotePreview ? remotePreview : cachedGenerated;
    final bool currentPreviewIsLocal = !hasRemotePreview;
    if (currentPreviewSource != null &&
        currentPreviewSource.isNotEmpty &&
        _loadedAudioSource == currentPreviewSource &&
        _loadedAudioIsLocal == currentPreviewIsLocal) {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        final bool shouldRestart = _playbackCompleted ||
            (_audioDuration > Duration.zero &&
                _audioPosition >=
                    _audioDuration - const Duration(milliseconds: 200));
        if (shouldRestart) {
          await _audioPlayer.seek(Duration.zero);
          if (mounted) {
            setState(() {
              _audioPosition = Duration.zero;
              _playbackCompleted = false;
            });
          }
        }
        await _audioPlayer.resume();
      }
      return;
    }
    try {
      setState(() {
        _isPreviewGenerating = true;
        _statusMessage = 'Preparing voice preview...';
      });
      if (hasRemotePreview) {
        await _loadAudioSource(remotePreview, autoplay: true, isLocal: false);
      } else if (cachedGenerated != null && cachedGenerated.isNotEmpty) {
        await _loadAudioSource(cachedGenerated, autoplay: true, isLocal: true);
      } else {
        final String generated = await _synthesizeSpeechToTempFile(
          voiceId: selectedVoice.id,
          text: _samplePreviewText(_languageCode),
          languageCode: _languageCode,
        );
        _generatedPreviewCache[_previewCacheKey] = generated;
        await _loadAudioSource(generated, autoplay: true, isLocal: true);
      }
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Voice preview ready.';
      });
    } catch (error) {
      if (_isAudioPluginMissingError(error)) {
        _markAudioPreviewUnsupported();
        _showMessage(
          'Preview player unavailable in this build. Reinstall latest APK.',
        );
        return;
      }
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isPreviewGenerating = false;
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (!_audioPlaybackSupported) {
      _showMessage(
        'Built-in audio player unavailable in this build. Use Download.',
      );
      return;
    }
    final String? source = _resultAudioPath;
    if (source == null || source.isEmpty) return;
    final bool isLocal =
        !source.startsWith('http://') && !source.startsWith('https://');
    try {
      if (_loadedAudioSource != source || _loadedAudioIsLocal != isLocal) {
        await _loadAudioSource(source, autoplay: true, isLocal: isLocal);
        return;
      }
      if (_isPlaying) {
        await _audioPlayer.pause();
        return;
      }
      if (_playbackCompleted ||
          (_audioDuration > Duration.zero &&
              _audioPosition >=
                  _audioDuration - const Duration(milliseconds: 200))) {
        await _audioPlayer.seek(Duration.zero);
        _playbackCompleted = false;
      }
      await _audioPlayer.resume();
    } catch (error) {
      if (_isAudioPluginMissingError(error)) {
        _markAudioPreviewUnsupported();
        _showMessage(
          'Built-in audio player unavailable in this build. Use Download.',
        );
        return;
      }
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _seekAudio(double valueMs) async {
    if (!_audioPlaybackSupported) return;
    if (_audioDuration <= Duration.zero) return;
    final int safeMs = valueMs.round().clamp(0, _audioDuration.inMilliseconds);
    try {
      await _audioPlayer.seek(Duration(milliseconds: safeMs));
      if (mounted) {
        setState(() {
          _audioPosition = Duration(milliseconds: safeMs);
          _playbackCompleted = false;
        });
      }
    } catch (error) {
      if (_isAudioPluginMissingError(error)) {
        _markAudioPreviewUnsupported();
      }
    }
  }

  Future<void> _replayAudio() async {
    if (!_audioPlaybackSupported) return;
    final String? source = _resultAudioPath;
    if (source == null || source.isEmpty) return;
    final bool isLocal =
        !source.startsWith('http://') && !source.startsWith('https://');
    try {
      if (_loadedAudioSource != source || _loadedAudioIsLocal != isLocal) {
        await _loadAudioSource(source, autoplay: false, isLocal: isLocal);
      }
      await _audioPlayer.seek(Duration.zero);
      if (mounted) {
        setState(() {
          _audioPosition = Duration.zero;
          _playbackCompleted = false;
        });
      }
      await _audioPlayer.resume();
    } catch (error) {
      if (_isAudioPluginMissingError(error)) {
        _markAudioPreviewUnsupported();
        return;
      }
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _jumpAudio(Duration delta) async {
    if (!_audioPlaybackSupported) return;
    if (_audioDuration <= Duration.zero) return;
    final int targetMs = (_audioPosition.inMilliseconds + delta.inMilliseconds)
        .clamp(0, _audioDuration.inMilliseconds);
    await _seekAudio(targetMs.toDouble());
    if (_isPlaying) {
      try {
        await _audioPlayer.resume();
      } catch (_) {}
    }
  }

  Future<String?> _pickSpeechLocaleId() async {
    final List<stt.LocaleName> locales = await _speechToText.locales();
    if (locales.isEmpty) return null;
    final List<String> candidates = _languageCode == 'ar'
        ? <String>['ar-IQ', 'ar-SA', 'ar-AE', 'ar-EG', 'ar']
        : <String>['en-US', 'en-GB', 'en'];
    for (final String candidate in candidates) {
      final String lower = candidate.toLowerCase();
      for (final stt.LocaleName locale in locales) {
        if (locale.localeId.toLowerCase() == lower) {
          return locale.localeId;
        }
      }
    }
    final String prefix = _languageCode == 'ar' ? 'ar' : 'en';
    for (final stt.LocaleName locale in locales) {
      if (locale.localeId.toLowerCase().startsWith(prefix)) {
        return locale.localeId;
      }
    }
    return locales.first.localeId;
  }

  Future<bool> _ensureSpeechReady() async {
    if (_isSpeechReady) return true;
    try {
      final bool available = await _speechToText.initialize(
        onStatus: (String status) {
          if (!mounted) return;
          final String normalized = status.trim().toLowerCase();
          final bool listening = normalized == 'listening';
          if (!listening && _isListeningToPrompt) {
            setState(() {
              _isListeningToPrompt = false;
            });
            return;
          }
          if (listening != _isListeningToPrompt) {
            setState(() {
              _isListeningToPrompt = listening;
            });
          }
        },
        onError: (dynamic error) {
          if (!mounted) return;
          setState(() {
            _isListeningToPrompt = false;
          });
          final String message =
              (error?.errorMsg ?? error?.toString() ?? 'unknown error')
                  .toString();
          _showMessage(
            'Voice typing error: $message',
            isError: true,
          );
        },
        debugLogging: false,
      );
      if (!mounted) return available;
      setState(() {
        _isSpeechReady = available;
      });
      if (!available) {
        _showMessage(
          'Voice typing is unavailable on this device.',
          isError: true,
        );
      }
      return available;
    } catch (error) {
      if (!mounted) return false;
      _showMessage(
        'Unable to start voice typing: $error',
        isError: true,
      );
      return false;
    }
  }

  Future<void> _togglePromptVoiceTyping() async {
    if (_isGenerating) return;
    if (_isListeningToPrompt) {
      try {
        await _speechToText.stop();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isListeningToPrompt = false;
        });
      }
      return;
    }
    final bool ready = await _ensureSpeechReady();
    if (!ready) return;
    final String? localeId = await _pickSpeechLocaleId();
    _lastSpeechLocaleId = localeId;
    _voiceTypingBaseText = _textController.text.trimRight();
    try {
      await _speechToText.listen(
        onResult: (dynamic result) {
          if (!mounted) return;
          final String spoken =
              (result?.recognizedWords ?? '').toString().trim();
          if (spoken.isEmpty) return;
          final String nextText = _voiceTypingBaseText.isEmpty
              ? spoken
              : '${_voiceTypingBaseText.trimRight()} $spoken';
          setState(() {
            _textController.value = TextEditingValue(
              text: nextText,
              selection: TextSelection.collapsed(offset: nextText.length),
            );
          });
          final bool isFinal = result?.finalResult == true;
          if (isFinal) {
            _voiceTypingBaseText = nextText;
          }
        },
        localeId: localeId,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(minutes: 1),
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
      if (!mounted) return;
      if (!_speechToText.isListening) {
        _showMessage('Unable to start voice typing.', isError: true);
        return;
      }
      setState(() {
        _isListeningToPrompt = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isListeningToPrompt = false;
      });
      _showMessage(
        'Unable to start voice typing: $error',
        isError: true,
      );
    }
  }

  Future<String> _buildDownloadPath(String extension) async {
    final String fileName =
        'wonderpic_voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
    if (Platform.isAndroid) {
      final Directory androidDownload =
          Directory('/storage/emulated/0/Download');
      if (await androidDownload.exists()) {
        return '${androidDownload.path}/$fileName';
      }
    }
    return '${Directory.systemTemp.path}/$fileName';
  }

  Future<void> _downloadAudioToTemp() async {
    final String? source = _resultAudioPath;
    if (source == null || source.isEmpty || _isDownloading) return;
    setState(() {
      _isDownloading = true;
    });
    try {
      final bool local =
          !source.startsWith('http://') && !source.startsWith('https://');
      if (local) {
        final File src = File(source);
        if (!await src.exists()) {
          throw StateError('Generated audio file is missing.');
        }
        final String extension = source.toLowerCase().endsWith('.wav')
            ? 'wav'
            : source.toLowerCase().endsWith('.ogg')
                ? 'ogg'
                : source.toLowerCase().endsWith('.aac')
                    ? 'aac'
                    : 'mp3';
        final String path = await _buildDownloadPath(extension);
        await src.copy(path);
        if (!mounted) return;
        setState(() {
          _lastDownloadedFilePath = path;
        });
        _showMessage('Audio copied to download path.');
        return;
      }
      final http.Response response =
          await http.get(Uri.parse(source)).timeout(const Duration(minutes: 3));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Audio download failed (${response.statusCode}).');
      }
      final String extension =
          _safeAudioExtensionFromContentType(response.headers['content-type']);
      final String path = await _buildDownloadPath(extension);
      final File file = File(path);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      if (!mounted) return;
      setState(() {
        _lastDownloadedFilePath = path;
      });
      _showMessage('Audio downloaded.');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _pickCloneFiles() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const <String>[
          'mp3',
          'wav',
          'm4a',
          'ogg',
          'aac',
          'flac',
          'webm',
        ],
      );
      if (result == null || result.files.isEmpty) return;
      final List<PlatformFile> picked = result.files
          .where((file) => (file.path ?? '').trim().isNotEmpty)
          .toList(growable: false);
      if (picked.isEmpty) return;
      setState(() {
        _cloneFiles = picked.take(6).toList(growable: false);
      });
    } catch (error) {
      if (error is MissingPluginException) {
        _showMessage(
          'File picker unavailable in this build. Reinstall latest APK.',
          isError: true,
        );
        return;
      }
      _showMessage(error.toString(), isError: true);
    }
  }

  String _fileNameFromPath(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final int idx = normalized.lastIndexOf('/');
    if (idx < 0 || idx >= normalized.length - 1) return normalized;
    return normalized.substring(idx + 1);
  }

  String _formatRecordingDuration(Duration duration) {
    final int minutes = duration.inMinutes;
    final int seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _replaceArabicToken(String source, String from, String to) {
    final RegExp pattern = RegExp(
      '(^|[\\s\\.,!؟،:؛\\-\\n])${RegExp.escape(from)}(?=([\\s\\.,!؟،:؛\\-\\n]|\\\$))',
    );
    return source.replaceAllMapped(
      pattern,
      (match) => '${match.group(1) ?? ''}$to',
    );
  }

  String _rewriteToIraqiDialect(String input) {
    String output = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (output.isEmpty) return output;

    const List<MapEntry<String, String>> phraseReplacements =
        <MapEntry<String, String>>[
      MapEntry<String, String>('كيف حالكم', 'شلونكم'),
      MapEntry<String, String>('كيف حالك', 'شلونك'),
      MapEntry<String, String>('ما هذا', 'شنو هذا'),
      MapEntry<String, String>('ما هذه', 'شنو هاي'),
      MapEntry<String, String>('لماذا', 'ليش'),
      MapEntry<String, String>('ماذا', 'شنو'),
      MapEntry<String, String>('أين', 'وين'),
      MapEntry<String, String>('الآن', 'هسه'),
      MapEntry<String, String>('الان', 'هسه'),
      MapEntry<String, String>('جداً', 'كلش'),
      MapEntry<String, String>('جدا', 'كلش'),
      MapEntry<String, String>('سوف', 'راح'),
      MapEntry<String, String>('مرحبا', 'هلا'),
      MapEntry<String, String>('مرحباً', 'هلا'),
      MapEntry<String, String>('شكراً', 'ممنون'),
      MapEntry<String, String>('شكرا', 'ممنون'),
      MapEntry<String, String>('نعم', 'إي'),
      MapEntry<String, String>('حسناً', 'زين'),
      MapEntry<String, String>('حسنا', 'زين'),
      MapEntry<String, String>('لا أستطيع', 'ما أگدر'),
      MapEntry<String, String>('لا استطيع', 'ما اگدر'),
      MapEntry<String, String>('أستطيع', 'أگدر'),
      MapEntry<String, String>('استطيع', 'اگدر'),
      MapEntry<String, String>('هذا', 'هاذ'),
      MapEntry<String, String>('هذه', 'هاي'),
    ];

    for (final MapEntry<String, String> entry in phraseReplacements) {
      output = _replaceArabicToken(output, entry.key, entry.value);
    }

    output = output.replaceAll(RegExp(r'\s+([،.!؟:؛])'), r'$1');
    output = output.replaceAll(RegExp(r'\s+'), ' ').trim();
    return output;
  }

  void _applyIraqiEnhance() {
    final String current = _textController.text.trim();
    if (current.isEmpty) {
      _showMessage('اكتب النص أولاً ثم استخدم Iraqi Enhance.', isError: true);
      return;
    }
    if (_languageCode != 'ar' || !_containsArabicScript(current)) {
      _showMessage(
        'Iraqi Enhance يعمل مع النص العربي فقط. اختر Arabic أولاً.',
        isError: true,
      );
      return;
    }

    final String rewritten = _rewriteToIraqiDialect(current);
    if (rewritten.isEmpty) return;
    _textController.value = TextEditingValue(
      text: rewritten,
      selection: TextSelection.collapsed(offset: rewritten.length),
    );

    setState(() {
      if (_arabicAccentOptions.contains('iraqi')) {
        _selectedArabicAccent = 'iraqi';
      }
      if (_selectedQuality == 'Stable') {
        _selectedQuality = 'Balanced';
      }
    });

    _showMessage('تم تطبيق Iraqi Enhance على النص.');
  }

  void _insertEnhanceTag(String tag) {
    final String current = _textController.text;
    final TextSelection selection = _textController.selection;
    int start = selection.start;
    int end = selection.end;
    if (start < 0 ||
        end < 0 ||
        start > current.length ||
        end > current.length) {
      start = current.length;
      end = current.length;
    }
    final String separatorPrefix =
        start == 0 || current[start - 1].trim().isEmpty ? '' : ' ';
    final String separatorSuffix =
        end < current.length && current[end].trim().isNotEmpty ? ' ' : '';
    final String insertion = '$separatorPrefix$tag$separatorSuffix';
    final String updated = current.replaceRange(start, end, insertion);
    final int cursor = start + insertion.length;
    _textController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  Future<void> _openEnhanceTagsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF26292F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: SizedBox(
                    width: 40,
                    child: Divider(color: _kVoiceTextSub, thickness: 3),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enhance Tags',
                  style: TextStyle(
                    color: _kVoiceTextMain,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Official Eleven v3 prompt tags for emotion and expression.',
                  style: TextStyle(
                    color: _kVoiceTextSub,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _enhanceAudioTags.map((tag) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        _insertEnhanceTag(tag);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _kVoiceCardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kVoiceStroke),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            color: _kVoiceTextMain,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleCloneRecording() async {
    if (_isRecordingCloneSample) {
      await _stopCloneRecording();
      return;
    }
    await _startCloneRecording();
  }

  Future<void> _startCloneRecording() async {
    try {
      if (_isCloning) return;
      final bool hasPermission = await _sampleRecorder.hasPermission();
      if (!hasPermission) {
        _showMessage('Microphone permission is required for voice recording.',
            isError: true);
        return;
      }
      final String path =
          '${Directory.systemTemp.path}/wonderpic_clone_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _sampleRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
          numChannels: 1,
        ),
        path: path,
      );
      _cloneRecordingTicker?.cancel();
      _cloneRecordingTicker =
          Timer.periodic(const Duration(seconds: 1), (Timer timer) {
        if (!mounted || !_isRecordingCloneSample) return;
        setState(() {
          _cloneRecordingDuration += const Duration(seconds: 1);
        });
      });
      if (!mounted) return;
      setState(() {
        _isRecordingCloneSample = true;
        _cloneRecordingDuration = Duration.zero;
      });
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _stopCloneRecording() async {
    try {
      final String? path = await _sampleRecorder.stop();
      _cloneRecordingTicker?.cancel();
      _cloneRecordingTicker = null;
      if (!mounted) return;
      setState(() {
        _isRecordingCloneSample = false;
      });
      if (path == null || path.trim().isEmpty) {
        return;
      }
      final File file = File(path);
      if (!await file.exists()) {
        return;
      }
      final int size = await file.length();
      final PlatformFile recorded = PlatformFile(
        name: _fileNameFromPath(path),
        path: path,
        size: size,
      );
      setState(() {
        final List<PlatformFile> merged = <PlatformFile>[
          ..._cloneFiles,
          recorded,
        ];
        _cloneFiles = merged.take(6).toList(growable: false);
        _latestCloneSamplePath = path;
      });
      _showMessage('Microphone sample added.');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
      if (mounted) {
        setState(() {
          _isRecordingCloneSample = false;
        });
      }
    }
  }

  Future<void> _createInstantVoiceClone() async {
    if (_isCloning) return;
    if (_isRecordingCloneSample) {
      await _stopCloneRecording();
    }
    final String apiKey = _elevenLabsApiKey.trim();
    if (apiKey.isEmpty) {
      _showMessage(
        'ElevenLabs backend proxy is not configured. Add --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_PUBLISHABLE_KEY=...',
        isError: true,
      );
      return;
    }
    final String cloneName = _cloneNameController.text.trim();
    if (cloneName.isEmpty) {
      _showMessage('Write a clone name first.', isError: true);
      return;
    }
    if (_cloneFiles.isEmpty) {
      _showMessage('Upload at least one clean voice sample.', isError: true);
      return;
    }
    setState(() {
      _isCloning = true;
      _statusMessage = 'Creating instant voice clone...';
    });
    try {
      final Uri uri = _elevenLabsProxyUri('/v1/voices/add');
      final http.MultipartRequest request = http.MultipartRequest('POST', uri)
        ..headers['xi-api-key'] = apiKey
        ..headers['accept'] = 'application/json'
        ..fields['name'] = cloneName
        ..fields['remove_background_noise'] =
            _removeCloneNoise ? 'true' : 'false';
      final String description = _cloneDescriptionController.text.trim();
      if (description.isNotEmpty) {
        request.fields['description'] = description;
      }
      final Map<String, String> labels = <String, String>{
        'language': _languageCode,
      };
      if (_languageCode == 'ar' && _selectedArabicAccent != 'all') {
        labels['accent'] = _selectedArabicAccent;
      }
      request.fields['labels'] = jsonEncode(labels);
      for (final PlatformFile file in _cloneFiles) {
        final String path = file.path ?? '';
        if (path.trim().isEmpty) continue;
        request.files.add(
          await http.MultipartFile.fromPath(
            'files',
            path,
            filename: file.name,
          ),
        );
      }
      final http.StreamedResponse streamed =
          await request.send().timeout(const Duration(minutes: 2));
      final http.Response response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          _parseElevenLabsError(
            response.statusCode,
            utf8.decode(response.bodyBytes),
            fallback: 'Instant voice clone failed.',
          ),
        );
      }
      final Map<String, dynamic> decoded = await _decodeJsonResponse(
        response,
        contextLabel: 'ElevenLabs clone',
      );
      final String newVoiceId = (decoded['voice_id'] as String?)?.trim() ?? '';
      if (newVoiceId.isEmpty) {
        throw const FormatException('Clone created but voice_id is missing.');
      }
      if (!mounted) return;
      await _loadVoices(announce: false);
      if (!mounted) return;
      setState(() {
        _voiceSource = _VoiceSource.account;
        _selectedVoiceId = newVoiceId;
        _mode = _VoiceMode.tts;
        _statusMessage = 'Clone created and selected.';
      });
      _showMessage('Instant Voice Clone created successfully.');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
      if (mounted) {
        setState(() {
          _statusMessage = 'Instant Voice Clone failed.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCloning = false;
        });
      }
    }
  }

  String _accentLabel(String raw) {
    switch (raw) {
      case 'all':
        return 'All';
      case 'iraqi':
        return 'Iraqi';
      default:
        return raw
            .split(RegExp(r'[\s_-]+'))
            .where((part) => part.trim().isNotEmpty)
            .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' ');
    }
  }

  Widget _buildLanguageChip(String value, String label) {
    final bool active = _languageCode == value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _isGenerating || _isCloning
          ? null
          : () {
              setState(() {
                _languageCode = value;
                if (value != 'ar') {
                  _selectedArabicAccent = 'all';
                }
                _syncSelectedVoiceForCurrentContext();
                _syncSelectedModelForCurrentLanguage();
              });
            },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _kVoiceActiveAccent : _kVoiceCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kVoiceStroke),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? _kVoiceActiveAccentForeground : _kVoiceTextMain,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildQualityChip(String label, _VoiceQualityProfile profile) {
    final bool active = _selectedQuality == label;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _isGenerating
          ? null
          : () {
              setState(() {
                _applyQualityProfile(label, silent: true);
              });
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _kVoiceActiveAccent : _kVoiceCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kVoiceStroke),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? _kVoiceActiveAccentForeground : _kVoiceTextMain,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    Widget chip(_VoiceMode mode, String title) {
      final bool active = _mode == mode;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _isGenerating || _isCloning
              ? null
              : () {
                  setState(() {
                    _mode = mode;
                  });
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? _kVoiceActiveAccent : _kVoiceCardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kVoiceStroke),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: active ? _kVoiceActiveAccentForeground : _kVoiceTextMain,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(_VoiceMode.tts, 'Text to Speech'),
        const SizedBox(width: 8),
        chip(_VoiceMode.clone, 'Instant Voice Clone'),
      ],
    );
  }

  Widget _buildSourceChip(_VoiceSource source, String title) {
    final bool active = _voiceSource == source;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _isGenerating || _isCloning
          ? null
          : () {
              setState(() {
                _voiceSource = source;
                _syncSelectedVoiceForCurrentContext();
              });
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _kVoiceActiveAccent : _kVoiceCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kVoiceStroke),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: active ? _kVoiceActiveAccentForeground : _kVoiceTextMain,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  String _voiceDropdownLabel(_VoicePreset voice) {
    final List<String> chunks = <String>[voice.label];
    if (voice.accent.trim().isNotEmpty) {
      chunks.add(voice.accent.trim());
    }
    if (voice.gender.trim().isNotEmpty) {
      chunks.add(voice.gender.trim());
    }
    return chunks.join(' · ');
  }

  String _modelDropdownLabel(_TtsModel model) {
    if (model.id == _recommendedModelIdForLanguage(_languageCode)) {
      return '${model.name} (Recommended)';
    }
    return model.name;
  }

  Widget _buildSettingSlider({
    required String title,
    required double value,
    required double min,
    required double max,
    int divisions = 100,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _kVoiceTextMain,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              value.toStringAsFixed(2),
              style: const TextStyle(
                color: _kVoiceTextSub,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          onChanged: _isGenerating ? null : onChanged,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: _kVoiceActiveAccent,
          inactiveColor: const Color(0xFF303643),
        ),
      ],
    );
  }

  Widget _buildArabicAccentSection() {
    if (_languageCode != 'ar') return const SizedBox.shrink();
    final List<String> accents = _arabicAccentOptions;
    if (accents.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dialect',
          style: TextStyle(
            color: _kVoiceTextMain,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: accents.map((accent) {
            final bool active = _selectedArabicAccent == accent;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _isGenerating || _isCloning
                  ? null
                  : () {
                      setState(() {
                        _selectedArabicAccent = accent;
                        final List<_VoicePreset> filtered =
                            _currentVoiceOptions;
                        if (filtered.isNotEmpty &&
                            !filtered
                                .any((voice) => voice.id == _selectedVoiceId)) {
                          _selectedVoiceId = filtered.first.id;
                        }
                      });
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? _kVoiceActiveAccent : _kVoiceCardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kVoiceStroke),
                ),
                child: Text(
                  _accentLabel(accent),
                  style: TextStyle(
                    color: active
                        ? _kVoiceActiveAccentForeground
                        : _kVoiceTextMain,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildGeneratedAudioCard() {
    final String? source = _resultAudioPath;
    if (source == null || source.isEmpty) return const SizedBox.shrink();
    final double maxMs =
        math.max<double>(_audioDuration.inMilliseconds.toDouble(), 1);
    final double valueMs =
        _audioPosition.inMilliseconds.toDouble().clamp(0, maxMs);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kVoiceCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kVoiceStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Generated Voice',
            style: TextStyle(
              color: _kVoiceTextMain,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF11151C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kVoiceStroke),
            ),
            child: Row(
              children: [
                IconButton(
                  splashRadius: 20,
                  onPressed: _togglePlayback,
                  icon: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: _kVoiceTextMain,
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                        ),
                        child: Slider(
                          value: _isSeekDragging
                              ? _seekDragMs.clamp(0, maxMs)
                              : valueMs,
                          min: 0,
                          max: maxMs,
                          onChangeStart: (value) {
                            setState(() {
                              _isSeekDragging = true;
                              _seekDragMs = value;
                            });
                          },
                          onChanged: (value) {
                            setState(() {
                              _seekDragMs = value;
                            });
                          },
                          onChangeEnd: (value) async {
                            setState(() {
                              _isSeekDragging = false;
                            });
                            await _seekAudio(value);
                          },
                          activeColor: _kVoiceActiveAccent,
                          inactiveColor: const Color(0xFF303643),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Text(
                              _formatDuration(_audioPosition),
                              style: const TextStyle(
                                color: _kVoiceTextSub,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatDuration(_audioDuration),
                              style: const TextStyle(
                                color: _kVoiceTextSub,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            splashRadius: 18,
                            onPressed: () =>
                                _jumpAudio(const Duration(seconds: -10)),
                            icon: const Icon(
                              Icons.replay_10_rounded,
                              color: _kVoiceTextSub,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            splashRadius: 20,
                            onPressed: _replayAudio,
                            icon: const Icon(
                              Icons.restart_alt_rounded,
                              color: _kVoiceTextSub,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            splashRadius: 18,
                            onPressed: () =>
                                _jumpAudio(const Duration(seconds: 10)),
                            icon: const Icon(
                              Icons.forward_10_rounded,
                              color: _kVoiceTextSub,
                              size: 20,
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isDownloading ? null : _downloadAudioToTemp,
              icon: _isDownloading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(_isDownloading ? 'Downloading...' : 'Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kVoiceCardBg,
                foregroundColor: _kVoiceTextMain,
                side: const BorderSide(color: _kVoiceStroke),
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ),
          if (_lastDownloadedFilePath != null &&
              _lastDownloadedFilePath!.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              _lastDownloadedFilePath!,
              style: const TextStyle(
                color: _kVoiceTextSub,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 8),
          SelectableText(
            source,
            style: const TextStyle(
              color: _kVoiceTextSub,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloneSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _cloneNameController,
          enabled: !_isCloning,
          style: const TextStyle(
            color: _kVoiceTextMain,
            fontSize: 13.5,
            height: 1.35,
          ),
          decoration: InputDecoration(
            hintText: 'Clone name (e.g. Iraqi Female Voice)',
            hintStyle: const TextStyle(
              color: _kVoiceTextSub,
              fontSize: 12.5,
            ),
            filled: true,
            fillColor: const Color(0xFF11151C),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _cloneDescriptionController,
          enabled: !_isCloning,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(
            color: _kVoiceTextMain,
            fontSize: 13.5,
            height: 1.35,
          ),
          decoration: InputDecoration(
            hintText: 'Clone description (dialect, style, use case)...',
            hintStyle: const TextStyle(
              color: _kVoiceTextSub,
              fontSize: 12.5,
            ),
            filled: true,
            fillColor: const Color(0xFF11151C),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isCloning ? null : _pickCloneFiles,
                icon: const Icon(Icons.audio_file_rounded, size: 18),
                label: Text(
                  _cloneFiles.isEmpty ? 'Upload Files' : 'Replace Files',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kVoiceTextMain,
                  side: const BorderSide(color: _kVoiceStroke),
                  minimumSize: const Size.fromHeight(42),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isCloning ? null : _toggleCloneRecording,
                icon: Icon(
                  _isRecordingCloneSample
                      ? Icons.stop_circle_outlined
                      : Icons.mic_none_rounded,
                  size: 18,
                ),
                label: Text(
                  _isRecordingCloneSample
                      ? 'Stop ${_formatRecordingDuration(_cloneRecordingDuration)}'
                      : 'Record Mic',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _isRecordingCloneSample
                      ? const Color(0xFFE37B7B)
                      : _kVoiceTextMain,
                  side: BorderSide(
                    color: _isRecordingCloneSample
                        ? const Color(0xFFE37B7B)
                        : _kVoiceStroke,
                  ),
                  minimumSize: const Size.fromHeight(42),
                ),
              ),
            ),
          ],
        ),
        if (_cloneFiles.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF11151C),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kVoiceStroke),
            ),
            child: Column(
              children: _cloneFiles.asMap().entries.map((entry) {
                final int index = entry.key;
                final PlatformFile file = entry.value;
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        file.name,
                        style: const TextStyle(
                          color: _kVoiceTextMain,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      splashRadius: 18,
                      onPressed: _isCloning
                          ? null
                          : () {
                              setState(() {
                                _cloneFiles =
                                    List<PlatformFile>.from(_cloneFiles)
                                      ..removeAt(index);
                              });
                            },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: _kVoiceTextSub,
                        size: 18,
                      ),
                    ),
                  ],
                );
              }).toList(growable: false),
            ),
          ),
        ],
        if (_latestCloneSamplePath != null &&
            _latestCloneSamplePath!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Latest mic sample: ${_fileNameFromPath(_latestCloneSamplePath!)}',
              style: const TextStyle(
                color: _kVoiceTextSub,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _removeCloneNoise,
          onChanged: _isCloning
              ? null
              : (value) {
                  setState(() {
                    _removeCloneNoise = value;
                  });
                },
          dense: true,
          title: const Text(
            'Remove Background Noise',
            style: TextStyle(
              color: _kVoiceTextMain,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: const Text(
            'Official ElevenLabs setting for cleaner clone samples.',
            style: TextStyle(
              color: _kVoiceTextSub,
              fontSize: 11.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Text(
          'For Iraqi quality: use 2-6 clean Iraqi samples (10-30s) and keep spoken text naturally Iraqi.',
          style: TextStyle(
            color: _kVoiceTextSub,
            fontSize: 11.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isCloning ? null : _createInstantVoiceClone,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kVoiceActiveAccent,
              foregroundColor: _kVoiceActiveAccentForeground,
              disabledBackgroundColor: _kVoiceCardBg,
              disabledForegroundColor: _kVoiceTextSub,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _isCloning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mic_external_on_rounded, size: 20),
            label: Text(
              _isCloning ? 'Cloning...' : 'Create Instant Voice Clone',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _inferNearestQuality() {
    String nearest = _qualityProfiles.keys.first;
    double minDiff = double.infinity;
    _qualityProfiles.forEach((label, profile) {
      final double diff = (_stability - profile.stability).abs() +
          (_similarity - profile.similarity).abs() +
          (_style - profile.style).abs() +
          (_speed - profile.speed).abs();
      if (diff < minDiff) {
        minDiff = diff;
        nearest = label;
      }
    });
    return nearest;
  }

  String _formatDuration(Duration value) {
    final int minutes = value.inMinutes;
    final int seconds = value.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFB3261E) : _kVoiceCardBg,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<_VoicePreset> currentVoices = _currentVoiceOptions;
    final List<_TtsModel> currentModels = _currentModelOptions;
    final _TtsModel? selectedModel = _selectedModel;
    final int accountVoiceCount =
        (_accountVoicesByLanguage[_languageCode] ?? const <_VoicePreset>[])
            .length;
    final int libraryVoiceCount =
        (_libraryVoicesByLanguage[_languageCode] ?? const <_VoicePreset>[])
            .length;
    final bool noArabicVoicesAfterFilter =
        _languageCode == 'ar' && currentVoices.isEmpty;
    return Scaffold(
      backgroundColor: _kVoicePageBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    splashRadius: 20,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: _kVoiceTextMain,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Text(
                    'Generate Voice',
                    style: TextStyle(
                      color: _kVoiceTextMain,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Provider: ElevenLabs Official API',
                style: TextStyle(
                  color: _kVoiceTextSub,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF171A20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kVoiceStroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModeSelector(),
                    const SizedBox(height: 12),
                    const Text(
                      'Language',
                      style: TextStyle(
                        color: _kVoiceTextMain,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _languageOptions.entries
                          .map((entry) =>
                              _buildLanguageChip(entry.key, entry.value))
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Voice Source',
                      style: TextStyle(
                        color: _kVoiceTextMain,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSourceChip(
                          _VoiceSource.account,
                          _sourceLabels['account']!,
                        ),
                        _buildSourceChip(
                          _VoiceSource.library,
                          _sourceLabels['library']!,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          _voiceSource == _VoiceSource.account
                              ? 'Account Voices: $accountVoiceCount'
                              : 'Library Voices: $libraryVoiceCount',
                          style: const TextStyle(
                            color: _kVoiceTextSub,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          splashRadius: 18,
                          onPressed: _isLoadingVoices || _isLoadingModels
                              ? null
                              : () async {
                                  await _loadVoices(announce: true);
                                  await _loadModels(announce: true);
                                },
                          icon: (_isLoadingVoices || _isLoadingModels)
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(
                                  Icons.refresh_rounded,
                                  color: _kVoiceTextSub,
                                  size: 18,
                                ),
                        ),
                      ],
                    ),
                    if (_languageCode == 'ar' &&
                        _voiceSource == _VoiceSource.library)
                      const Text(
                        'Official library currently has very limited/no Iraqi-accent voices. For true Iraqi quality use My Voices + Clone.',
                        style: TextStyle(
                          color: _kVoiceTextSub,
                          fontSize: 11.2,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    _buildArabicAccentSection(),
                    if (_languageCode == 'ar') const SizedBox(height: 10),
                    if (_mode == _VoiceMode.tts) ...[
                      const Text(
                        'Model',
                        style: TextStyle(
                          color: _kVoiceTextMain,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: currentModels.any(
                          (model) => model.id == _selectedModelId,
                        )
                            ? _selectedModelId
                            : (currentModels.isNotEmpty
                                ? currentModels.first.id
                                : null),
                        isExpanded: true,
                        dropdownColor: _kVoiceCardBg,
                        iconEnabledColor: _kVoiceTextMain,
                        style: const TextStyle(
                          color: _kVoiceTextMain,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF11151C),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _kVoiceStroke),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _kVoiceStroke),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: _kVoiceActiveAccent),
                          ),
                        ),
                        items: currentModels
                            .map(
                              (model) => DropdownMenuItem<String>(
                                value: model.id,
                                child: Text(
                                  _modelDropdownLabel(model),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _isGenerating || _isCloning
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _selectedModelId = value;
                                });
                              },
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Voice',
                        style: TextStyle(
                          color: _kVoiceTextMain,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: currentVoices.any(
                          (voice) => voice.id == _selectedVoiceId,
                        )
                            ? _selectedVoiceId
                            : (currentVoices.isNotEmpty
                                ? currentVoices.first.id
                                : null),
                        isExpanded: true,
                        dropdownColor: _kVoiceCardBg,
                        iconEnabledColor: _kVoiceTextMain,
                        style: const TextStyle(
                          color: _kVoiceTextMain,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF11151C),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _kVoiceStroke),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _kVoiceStroke),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: _kVoiceActiveAccent),
                          ),
                        ),
                        items: currentVoices
                            .map(
                              (voice) => DropdownMenuItem<String>(
                                value: voice.id,
                                child: Text(
                                  _voiceDropdownLabel(voice),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _isGenerating || _isCloning
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _selectedVoiceId = value;
                                });
                              },
                      ),
                      if (noArabicVoicesAfterFilter) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'No Arabic voices match this filter. Try "All" or create an Iraqi clone.',
                          style: TextStyle(
                            color: _kVoiceTextSub,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isPreviewGenerating ||
                                  _isGenerating ||
                                  !_audioPlaybackSupported ||
                                  currentVoices.isEmpty
                              ? null
                              : _toggleVoicePreview,
                          icon: _isPreviewGenerating
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  _isCurrentPreviewPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            !_audioPlaybackSupported
                                ? 'Preview Unavailable'
                                : (_isPreviewGenerating
                                    ? 'Preparing preview...'
                                    : (_isCurrentPreviewPlaying
                                        ? 'Pause Voice Preview'
                                        : 'Preview Voice')),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _kVoiceTextMain,
                            side: const BorderSide(color: _kVoiceStroke),
                            minimumSize: const Size.fromHeight(42),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _textController,
                        enabled: !_isGenerating,
                        minLines: 4,
                        maxLines: 8,
                        style: const TextStyle(
                          color: _kVoiceTextMain,
                          fontSize: 13.5,
                          height: 1.35,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Write the text to generate as voice...',
                          hintStyle: const TextStyle(
                            color: _kVoiceTextSub,
                            fontSize: 12.5,
                          ),
                          suffixIcon: IconButton(
                            onPressed:
                                _isGenerating ? null : _togglePromptVoiceTyping,
                            tooltip: _isListeningToPrompt
                                ? 'Stop voice typing'
                                : 'Voice typing',
                            icon: Icon(
                              _isListeningToPrompt
                                  ? Icons.mic_rounded
                                  : Icons.mic_none_rounded,
                              color: _isListeningToPrompt
                                  ? _kVoiceActiveAccent
                                  : _kVoiceTextSub,
                            ),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF11151C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_lastSpeechLocaleId != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _isListeningToPrompt
                              ? 'Listening ($_lastSpeechLocaleId)...'
                              : 'Voice typing locale: $_lastSpeechLocaleId',
                          style: const TextStyle(
                            color: _kVoiceTextSub,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            if (_languageCode == 'ar')
                              OutlinedButton.icon(
                                onPressed:
                                    _isGenerating ? null : _applyIraqiEnhance,
                                icon: const Icon(
                                  Icons.record_voice_over_rounded,
                                  size: 16,
                                ),
                                label: const Text('Iraqi Enhance'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _kVoiceActiveAccent,
                                  side: const BorderSide(
                                    color: _kVoiceActiveAccent,
                                  ),
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed:
                                  _isGenerating ? null : _openEnhanceTagsSheet,
                              icon: const Icon(Icons.auto_awesome_rounded,
                                  size: 16),
                              label: const Text('Enhance'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _kVoiceTextMain,
                                side: const BorderSide(color: _kVoiceStroke),
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Quality Preset',
                        style: TextStyle(
                          color: _kVoiceTextMain,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _qualityProfiles.entries
                            .map(
                              (entry) =>
                                  _buildQualityChip(entry.key, entry.value),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 8),
                      _buildSettingSlider(
                        title: 'Speed',
                        value: _speed,
                        min: 0.70,
                        max: 1.20,
                        divisions: 50,
                        onChanged: (value) {
                          setState(() {
                            _speed = value;
                            _selectedQuality = _inferNearestQuality();
                          });
                        },
                      ),
                      _buildSettingSlider(
                        title: 'Stability',
                        value: _stability,
                        min: 0.0,
                        max: 1.0,
                        divisions: 100,
                        onChanged: (value) {
                          setState(() {
                            _stability = value;
                            _selectedQuality = _inferNearestQuality();
                          });
                        },
                      ),
                      _buildSettingSlider(
                        title: 'Similarity',
                        value: _similarity,
                        min: 0.0,
                        max: 1.0,
                        divisions: 100,
                        onChanged: (value) {
                          setState(() {
                            _similarity = value;
                            _selectedQuality = _inferNearestQuality();
                          });
                        },
                      ),
                      if (selectedModel?.canUseStyle == true)
                        _buildSettingSlider(
                          title: 'Style',
                          value: _style,
                          min: 0.0,
                          max: 1.0,
                          divisions: 100,
                          onChanged: (value) {
                            setState(() {
                              _style = value;
                              _selectedQuality = _inferNearestQuality();
                            });
                          },
                        ),
                      if (selectedModel?.canUseSpeakerBoost == true)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _useSpeakerBoost,
                          onChanged: _isGenerating
                              ? null
                              : (value) {
                                  setState(() {
                                    _useSpeakerBoost = value;
                                  });
                                },
                          title: const Text(
                            'Speaker Boost',
                            style: TextStyle(
                              color: _kVoiceTextMain,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 2),
                      const Text(
                        'Official controls: model_id, language_code, stability, similarity_boost, speed, style, speaker_boost.',
                        style: TextStyle(
                          color: _kVoiceTextSub,
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Output Quality',
                        style: TextStyle(
                          color: _kVoiceTextMain,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedOutputFormat,
                        isExpanded: true,
                        dropdownColor: _kVoiceCardBg,
                        iconEnabledColor: _kVoiceTextMain,
                        style: const TextStyle(
                          color: _kVoiceTextMain,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF11151C),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _kVoiceStroke),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _kVoiceStroke),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: _kVoiceActiveAccent),
                          ),
                        ),
                        items: _audioOutputFormats.entries
                            .map(
                              (entry) => DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _isGenerating
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _selectedOutputFormat = value;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isGenerating ||
                                  currentVoices.isEmpty ||
                                  currentModels.isEmpty
                              ? null
                              : _generateVoice,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kVoiceActiveAccent,
                            foregroundColor: _kVoiceActiveAccentForeground,
                            disabledBackgroundColor: _kVoiceCardBg,
                            disabledForegroundColor: _kVoiceTextSub,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _isGenerating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.graphic_eq_rounded, size: 20),
                          label: Text(
                            _isGenerating ? 'Generating...' : 'Generate Voice',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      _buildCloneSection(),
                    ],
                    if (_statusMessage != null &&
                        _statusMessage!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        _statusMessage!,
                        style: const TextStyle(
                          color: _kVoiceTextSub,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_resultAudioPath != null && _resultAudioPath!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildGeneratedAudioCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
