import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum WonderPicLibraryItemType { image, video, voice }

extension WonderPicLibraryItemTypeCodec on WonderPicLibraryItemType {
  String get apiValue {
    switch (this) {
      case WonderPicLibraryItemType.image:
        return 'image';
      case WonderPicLibraryItemType.video:
        return 'video';
      case WonderPicLibraryItemType.voice:
        return 'voice';
    }
  }

  static WonderPicLibraryItemType fromRaw(String raw) {
    final String normalized = raw.trim().toLowerCase();
    switch (normalized) {
      case 'video':
        return WonderPicLibraryItemType.video;
      case 'voice':
      case 'audio':
        return WonderPicLibraryItemType.voice;
      case 'image':
      default:
        return WonderPicLibraryItemType.image;
    }
  }
}

class WonderPicLibraryItem {
  const WonderPicLibraryItem({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAtIso,
    this.subtitle,
    this.previewPath,
    this.localPath,
    this.remoteUrl,
  });

  final String id;
  final WonderPicLibraryItemType type;
  final String title;
  final String? subtitle;
  final String createdAtIso;
  final String? previewPath;
  final String? localPath;
  final String? remoteUrl;

  DateTime get createdAt {
    final DateTime? parsed = DateTime.tryParse(createdAtIso);
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.apiValue,
      'title': title,
      'subtitle': subtitle,
      'createdAtIso': createdAtIso,
      'previewPath': previewPath,
      'localPath': localPath,
      'remoteUrl': remoteUrl,
    };
  }

  factory WonderPicLibraryItem.fromJson(Map<String, dynamic> json) {
    return WonderPicLibraryItem(
      id: (json['id'] as String? ?? '').trim(),
      type: WonderPicLibraryItemTypeCodec.fromRaw(
        (json['type'] as String? ?? '').trim(),
      ),
      title: (json['title'] as String? ?? 'Untitled').trim(),
      subtitle: (json['subtitle'] as String?)?.trim(),
      createdAtIso: (json['createdAtIso'] as String? ?? '').trim(),
      previewPath: (json['previewPath'] as String?)?.trim(),
      localPath: (json['localPath'] as String?)?.trim(),
      remoteUrl: (json['remoteUrl'] as String?)?.trim(),
    );
  }
}

class WonderPicLibraryStore {
  static const String _storageKey = 'wonderpic_library_items_v1';
  static const int _maxItems = 500;

  Future<List<WonderPicLibraryItem>> loadItems() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString(_storageKey) ?? '';
    if (raw.trim().isEmpty) return const <WonderPicLibraryItem>[];

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return const <WonderPicLibraryItem>[];
      final List<WonderPicLibraryItem> items = <WonderPicLibraryItem>[];
      for (final dynamic entry in decoded) {
        if (entry is! Map) continue;
        final Map<String, dynamic> map =
            entry.map((key, value) => MapEntry(key.toString(), value));
        final WonderPicLibraryItem item = WonderPicLibraryItem.fromJson(map);
        if (item.id.isEmpty) continue;
        items.add(item);
      }
      items.sort(
        (a, b) => b.createdAt.millisecondsSinceEpoch
            .compareTo(a.createdAt.millisecondsSinceEpoch),
      );
      return items;
    } catch (_) {
      return const <WonderPicLibraryItem>[];
    }
  }

  Future<void> addItem(WonderPicLibraryItem item) async {
    final List<WonderPicLibraryItem> next = await loadItems();
    next.removeWhere((existing) => existing.id == item.id);
    next.insert(0, item);
    if (next.length > _maxItems) {
      next.removeRange(_maxItems, next.length);
    }
    await _saveItems(next);
  }

  Future<void> clearAll() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<void> _saveItems(List<WonderPicLibraryItem> items) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(
      items.map((item) => item.toJson()).toList(growable: false),
    );
    await prefs.setString(_storageKey, encoded);
  }
}
