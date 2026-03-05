import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wonderpic/services/wonderpic_library_store.dart';

class WonderPicLibraryScreen extends StatefulWidget {
  const WonderPicLibraryScreen({super.key});

  @override
  State<WonderPicLibraryScreen> createState() => _WonderPicLibraryScreenState();
}

enum _LibraryFilter { all, image, video, voice }

class _WonderPicLibraryScreenState extends State<WonderPicLibraryScreen> {
  static const Color _pageBg = Color(0xFF23262C);
  static const Color _cardBg = Color(0xFF1E1F22);
  static const Color _stroke = Color(0x2B4F5358);
  static const Color _textMain = Color(0xFFF3F3F2);
  static const Color _textSub = Color(0xFFB8B7B5);
  static const Color _accent = Color(0xFFE6F24A);

  final WonderPicLibraryStore _libraryStore = WonderPicLibraryStore();
  bool _isLoading = true;
  _LibraryFilter _filter = _LibraryFilter.all;
  List<WonderPicLibraryItem> _items = <WonderPicLibraryItem>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<WonderPicLibraryItem> items = await _libraryStore.loadItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  List<WonderPicLibraryItem> get _filteredItems {
    switch (_filter) {
      case _LibraryFilter.all:
        return _items;
      case _LibraryFilter.image:
        return _items
            .where((item) => item.type == WonderPicLibraryItemType.image)
            .toList(growable: false);
      case _LibraryFilter.video:
        return _items
            .where((item) => item.type == WonderPicLibraryItemType.video)
            .toList(growable: false);
      case _LibraryFilter.voice:
        return _items
            .where((item) => item.type == WonderPicLibraryItemType.voice)
            .toList(growable: false);
    }
  }

  Future<void> _copyValue(String value, String label) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        backgroundColor: const Color(0xFF17181C),
      ),
    );
  }

  String _relativeTime(DateTime value) {
    final DateTime now = DateTime.now();
    final Duration delta = now.difference(value.toLocal());
    if (delta.inSeconds < 60) return 'Just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays < 30) return '${delta.inDays}d ago';
    final int months = (delta.inDays / 30).floor();
    return '${months < 1 ? 1 : months}mo ago';
  }

  IconData _iconForType(WonderPicLibraryItemType type) {
    switch (type) {
      case WonderPicLibraryItemType.image:
        return Icons.image_outlined;
      case WonderPicLibraryItemType.video:
        return Icons.videocam_outlined;
      case WonderPicLibraryItemType.voice:
        return Icons.graphic_eq_rounded;
    }
  }

  String _labelForType(WonderPicLibraryItemType type) {
    switch (type) {
      case WonderPicLibraryItemType.image:
        return 'Image';
      case WonderPicLibraryItemType.video:
        return 'Video';
      case WonderPicLibraryItemType.voice:
        return 'Voice';
    }
  }

  Widget _buildPreview(WonderPicLibraryItem item) {
    final String preview = (item.previewPath ?? item.localPath ?? '').trim();
    final bool canShowImage = preview.isNotEmpty &&
        File(preview).existsSync() &&
        item.type == WonderPicLibraryItemType.image;
    if (canShowImage) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        child: Image.file(
          File(preview),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          filterQuality: FilterQuality.medium,
        ),
      );
    }
    return Container(
      color: const Color(0xFF17181C),
      alignment: Alignment.center,
      child: Icon(
        _iconForType(item.type),
        size: 30,
        color: const Color(0xFFDDE2EC),
      ),
    );
  }

  Future<void> _openItemDetails(WonderPicLibraryItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        final String path = (item.localPath ?? '').trim();
        final String url = (item.remoteUrl ?? '').trim();
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF26292F),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _stroke, width: 0.8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_iconForType(item.type), size: 18, color: _accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textMain,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.subtitle?.trim().isNotEmpty == true
                      ? item.subtitle!
                      : 'No details',
                  style: const TextStyle(
                    color: _textSub,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Created ${_relativeTime(item.createdAt)}',
                  style: const TextStyle(
                    color: _textSub,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (path.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => _copyValue(path, 'Path'),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF17181C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: _stroke, width: 0.6),
                        ),
                      ),
                      child: const Text(
                        'Copy local path',
                        style: TextStyle(
                          color: _textMain,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                if (url.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => _copyValue(url, 'URL'),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF17181C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: _stroke, width: 0.6),
                        ),
                      ),
                      child: const Text(
                        'Copy remote URL',
                        style: TextStyle(
                          color: _textMain,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(_LibraryFilter value, String label) {
    final bool selected = _filter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        setState(() {
          _filter = value;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _accent : _cardBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.transparent : _stroke,
            width: selected ? 0 : 0.6,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF19191A) : _textMain,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<WonderPicLibraryItem> items = _filteredItems;
    final double width = MediaQuery.sizeOf(context).width;
    final int crossAxisCount = width >= 980
        ? 5
        : width >= 760
            ? 4
            : width >= 520
                ? 3
                : 2;
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        title: const Text(
          'Library',
          style: TextStyle(
            color: _textMain,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
            color: _textMain,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(_LibraryFilter.all, 'All'),
                  const SizedBox(width: 8),
                  _buildFilterChip(_LibraryFilter.image, 'Images'),
                  const SizedBox(width: 8),
                  _buildFilterChip(_LibraryFilter.video, 'Videos'),
                  const SizedBox(width: 8),
                  _buildFilterChip(_LibraryFilter.voice, 'Voice'),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: _accent,
                      strokeWidth: 2.2,
                    ),
                  )
                : items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 22),
                          child: Text(
                            'No generated items yet.\nStart generating images, videos, or voice to build your library.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _textSub,
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
                        itemCount: items.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.82,
                        ),
                        itemBuilder: (context, index) {
                          final WonderPicLibraryItem item = items[index];
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _openItemDetails(item),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _cardBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _stroke, width: 0.7),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 118,
                                    width: double.infinity,
                                    child: _buildPreview(item),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          10, 9, 10, 8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _textMain,
                                              fontSize: 12.2,
                                              fontWeight: FontWeight.w700,
                                              height: 1.25,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            item.subtitle?.trim().isNotEmpty ==
                                                    true
                                                ? item.subtitle!
                                                : _labelForType(item.type),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _textSub,
                                              fontSize: 10.8,
                                              fontWeight: FontWeight.w600,
                                              height: 1.25,
                                            ),
                                          ),
                                          const Spacer(),
                                          Row(
                                            children: [
                                              Icon(
                                                _iconForType(item.type),
                                                size: 13.5,
                                                color: _accent,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  _relativeTime(item.createdAt),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: _textSub,
                                                    fontSize: 10.4,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
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
      ),
    );
  }
}
