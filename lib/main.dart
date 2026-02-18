import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const WonderPicApp());
}

class WonderPicApp extends StatelessWidget {
  const WonderPicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WonderPic',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const WonderPicEditorScreen(),
    );
  }
}

class WonderPicEditorScreen extends StatefulWidget {
  const WonderPicEditorScreen({super.key});

  static const Color _pageBg = Color(0xFFE7E9ED);
  static const Color _panelBg = Color(0xFFF4F5F7);
  static const Color _barsFill = Colors.white;
  static const Color _iconColor = Color(0xFF4C5562);
  static const Color _textColor = Color(0xFF616A77);

  @override
  State<WonderPicEditorScreen> createState() => _WonderPicEditorScreenState();
}

enum EditorLayerType { image, text, vector, mask, solid }

extension EditorLayerTypeUi on EditorLayerType {
  String get label {
    switch (this) {
      case EditorLayerType.image:
        return 'Image';
      case EditorLayerType.text:
        return 'Text';
      case EditorLayerType.vector:
        return 'Vector';
      case EditorLayerType.mask:
        return 'Mask';
      case EditorLayerType.solid:
        return 'Solid';
    }
  }

  IconData get icon {
    switch (this) {
      case EditorLayerType.image:
        return Icons.image_outlined;
      case EditorLayerType.text:
        return Icons.text_fields;
      case EditorLayerType.vector:
        return Icons.polyline_outlined;
      case EditorLayerType.mask:
        return Icons.gradient_outlined;
      case EditorLayerType.solid:
        return Icons.crop_square_rounded;
    }
  }
}

enum EditorTool { move, pencil, text, clone, marquee }

enum MarqueeSelectionMode { rectangular, elliptical, freehand, object }

extension MarqueeSelectionModeUi on MarqueeSelectionMode {
  String get label {
    switch (this) {
      case MarqueeSelectionMode.rectangular:
        return 'Rectangle';
      case MarqueeSelectionMode.elliptical:
        return 'Ellipse';
      case MarqueeSelectionMode.freehand:
        return 'Free';
      case MarqueeSelectionMode.object:
        return 'Object';
    }
  }

  IconData get icon {
    switch (this) {
      case MarqueeSelectionMode.rectangular:
        return Icons.crop_din_rounded;
      case MarqueeSelectionMode.elliptical:
        return Icons.circle_outlined;
      case MarqueeSelectionMode.freehand:
        return Icons.gesture_rounded;
      case MarqueeSelectionMode.object:
        return Icons.select_all_rounded;
    }
  }
}

enum _AddAction { image, solid }

enum PencilBrushType { round, soft, marker, calligraphy }

enum _TextFontLocale { english, arabic }

extension PencilBrushTypeUi on PencilBrushType {
  String get label {
    switch (this) {
      case PencilBrushType.round:
        return 'Round';
      case PencilBrushType.soft:
        return 'Soft';
      case PencilBrushType.marker:
        return 'Marker';
      case PencilBrushType.calligraphy:
        return 'Calligraphy';
    }
  }
}

typedef LayerTransformChanged = void Function(
  String layerId, {
  Offset? position,
  double? layerScale,
  double? layerRotation,
});

typedef LayerImageChanged = void Function(String layerId, ui.Image image);

class PencilSettings {
  const PencilSettings({
    this.size = 8,
    this.hardness = 75,
    this.opacity = 100,
    this.angle = 0,
    this.type = PencilBrushType.round,
    this.color = const Color(0xFF3A4350),
  });

  final double size;
  final double hardness;
  final double opacity;
  final double angle;
  final PencilBrushType type;
  final Color color;

  PencilSettings copyWith({
    double? size,
    double? hardness,
    double? opacity,
    double? angle,
    PencilBrushType? type,
    Color? color,
  }) {
    return PencilSettings(
      size: size ?? this.size,
      hardness: hardness ?? this.hardness,
      opacity: opacity ?? this.opacity,
      angle: angle ?? this.angle,
      type: type ?? this.type,
      color: color ?? this.color,
    );
  }
}

class CloneStampSettings {
  const CloneStampSettings({
    this.size = 28,
    this.hardness = 75,
    this.opacity = 100,
  });

  final double size;
  final double hardness;
  final double opacity;

  CloneStampSettings copyWith({
    double? size,
    double? hardness,
    double? opacity,
  }) {
    return CloneStampSettings(
      size: size ?? this.size,
      hardness: hardness ?? this.hardness,
      opacity: opacity ?? this.opacity,
    );
  }
}

class MarqueeSelection {
  const MarqueeSelection({
    required this.layerId,
    required this.mode,
    required this.boundsUv,
    this.freePathUv = const <Offset>[],
  });

  final String layerId;
  final MarqueeSelectionMode mode;
  final Rect boundsUv;
  final List<Offset> freePathUv;

  bool get hasUsableArea {
    if (boundsUv.width <= 0 || boundsUv.height <= 0) return false;
    if (mode == MarqueeSelectionMode.freehand) {
      return freePathUv.length >= 3;
    }
    return true;
  }

  MarqueeSelection copyWith({
    String? layerId,
    MarqueeSelectionMode? mode,
    Rect? boundsUv,
    List<Offset>? freePathUv,
  }) {
    return MarqueeSelection(
      layerId: layerId ?? this.layerId,
      mode: mode ?? this.mode,
      boundsUv: boundsUv ?? this.boundsUv,
      freePathUv: freePathUv ?? this.freePathUv,
    );
  }
}

class _MarqueeClipboard {
  const _MarqueeClipboard({
    required this.pixels,
    required this.width,
    required this.height,
    required this.sourceBoundsUv,
  });

  final Uint8List pixels;
  final int width;
  final int height;
  final Rect sourceBoundsUv;
}

class _SelectionPixelBounds {
  const _SelectionPixelBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;
}

class _SelectionRaster {
  const _SelectionRaster({
    required this.pixels,
    required this.width,
    required this.height,
    required this.bounds,
    required this.hasVisiblePixels,
  });

  final Uint8List pixels;
  final int width;
  final int height;
  final _SelectionPixelBounds bounds;
  final bool hasVisiblePixels;
}

class EditorLayer {
  const EditorLayer({
    required this.id,
    required this.name,
    required this.type,
    this.isVisible = true,
    this.isBackground = false,
    this.image,
    this.thumbnailBytes,
    this.solidColor,
    this.solidSize,
    this.textValue,
    this.textColor,
    this.textFontSize,
    this.textFontFamily,
    this.textFontWeight,
    this.position,
    this.layerScale = 1.0,
    this.layerRotation = 0.0,
  });

  final String id;
  final String name;
  final EditorLayerType type;
  final bool isVisible;
  final bool isBackground;
  final ui.Image? image;
  final Uint8List? thumbnailBytes;
  final Color? solidColor;
  final Size? solidSize;
  final String? textValue;
  final Color? textColor;
  final double? textFontSize;
  final String? textFontFamily;
  final int? textFontWeight;
  final Offset? position;
  final double layerScale;
  final double layerRotation;

  EditorLayer copyWith({
    String? id,
    String? name,
    EditorLayerType? type,
    bool? isVisible,
    bool? isBackground,
    ui.Image? image,
    Uint8List? thumbnailBytes,
    Color? solidColor,
    Size? solidSize,
    String? textValue,
    Color? textColor,
    double? textFontSize,
    String? textFontFamily,
    int? textFontWeight,
    Offset? position,
    double? layerScale,
    double? layerRotation,
  }) {
    return EditorLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      isVisible: isVisible ?? this.isVisible,
      isBackground: isBackground ?? this.isBackground,
      image: image ?? this.image,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      solidColor: solidColor ?? this.solidColor,
      solidSize: solidSize ?? this.solidSize,
      textValue: textValue ?? this.textValue,
      textColor: textColor ?? this.textColor,
      textFontSize: textFontSize ?? this.textFontSize,
      textFontFamily: textFontFamily ?? this.textFontFamily,
      textFontWeight: textFontWeight ?? this.textFontWeight,
      position: position ?? this.position,
      layerScale: layerScale ?? this.layerScale,
      layerRotation: layerRotation ?? this.layerRotation,
    );
  }
}

class _TextFontOption {
  const _TextFontOption({
    required this.family,
    required this.label,
    required this.preview,
    required this.direction,
  });

  final String family;
  final String label;
  final String preview;
  final TextDirection direction;
}

class _SolidProjectPreset {
  const _SolidProjectPreset({
    required this.title,
    required this.size,
    required this.subtitle,
  });

  final String title;
  final Size size;
  final String subtitle;
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.layers,
    required this.selectedLayerId,
    required this.activeTool,
    required this.nextLayerId,
    required this.isCloneSourceArmed,
    required this.textFontLocale,
    required this.marqueeMode,
    required this.marqueeSelection,
  });

  final List<EditorLayer> layers;
  final String? selectedLayerId;
  final EditorTool activeTool;
  final int nextLayerId;
  final bool isCloneSourceArmed;
  final _TextFontLocale textFontLocale;
  final MarqueeSelectionMode marqueeMode;
  final MarqueeSelection? marqueeSelection;
}

const List<Color> _kPencilPalette = <Color>[
  Color(0xFF111827),
  Color(0xFF1F2937),
  Color(0xFF374151),
  Color(0xFF4B5563),
  Color(0xFF6B7280),
  Color(0xFF9CA3AF),
  Color(0xFFE5E7EB),
  Color(0xFFFFFFFF),
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFF59E0B),
  Color(0xFFEAB308),
  Color(0xFF22C55E),
  Color(0xFF10B981),
  Color(0xFF14B8A6),
  Color(0xFF06B6D4),
  Color(0xFF0EA5E9),
  Color(0xFF3B82F6),
  Color(0xFF6366F1),
  Color(0xFF8B5CF6),
  Color(0xFFA855F7),
  Color(0xFFD946EF),
  Color(0xFFEC4899),
  Color(0xFFF43F5E),
];

const List<_TextFontOption> _kEnglishFontOptions = <_TextFontOption>[
  _TextFontOption(
    family: 'Barlow',
    label: 'Barlow',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Cabin',
    label: 'Cabin',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'CrimsonText',
    label: 'Crimson Text',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'DMSerifDisplay',
    label: 'DM Serif Display',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'FiraSans',
    label: 'Fira Sans',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Inter',
    label: 'Inter',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Karla',
    label: 'Karla',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Lato',
    label: 'Lato',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Manrope',
    label: 'Manrope',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Merriweather',
    label: 'Merriweather',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Montserrat',
    label: 'Montserrat',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Mulish',
    label: 'Mulish',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Nunito',
    label: 'Nunito',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Oswald',
    label: 'Oswald',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'PlayfairDisplay',
    label: 'Playfair Display',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Poppins',
    label: 'Poppins',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Quicksand',
    label: 'Quicksand',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'Raleway',
    label: 'Raleway',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'SourceSans3',
    label: 'Source Sans 3',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
  _TextFontOption(
    family: 'WorkSans',
    label: 'Work Sans',
    preview: 'The quick brown fox jumps 123',
    direction: TextDirection.ltr,
  ),
];

const List<_TextFontOption> _kArabicFontOptions = <_TextFontOption>[
  _TextFontOption(
    family: 'Cairo',
    label: 'القاهرة',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'Tajawal',
    label: 'تجوال',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'Almarai',
    label: 'المراعي',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'Changa',
    label: 'شانجا',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'ElMessiri',
    label: 'المسيري',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'ReemKufi',
    label: 'ريم كوفي',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'Amiri',
    label: 'أميري',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'NotoNaskhArabic',
    label: 'نسخ عربي',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'NotoKufiArabic',
    label: 'كوفي عربي',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'MarkaziText',
    label: 'مركزي',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'Harmattan',
    label: 'هرمتان',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'Katibeh',
    label: 'كاتبه',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'Lateef',
    label: 'لطيف',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'Mada',
    label: 'مدى',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'Mirza',
    label: 'ميرزا',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'Rakkas',
    label: 'ركاز',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'Lemonada',
    label: 'ليمونادة',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'BalooBhaijaan2',
    label: 'بالو بهيجان',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'ArefRuqaa',
    label: 'عارف رقعة',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
  _TextFontOption(
    family: 'ScheherazadeNew',
    label: 'شهرزاد',
    preview: 'اكتب نصك هنا للمعاينة',
    direction: TextDirection.rtl,
  ),
];

const List<int> _kDefaultFontWeights = <int>[400];
const List<int> _kVariableFontWeights = <int>[
  300,
  400,
  500,
  600,
  700,
  800,
  900
];

const Map<String, List<int>> _kFontWeightSupport = <String, List<int>>{
  'Inter': _kVariableFontWeights,
  'Nunito': _kVariableFontWeights,
  'Merriweather': _kVariableFontWeights,
  'PlayfairDisplay': _kVariableFontWeights,
  'Oswald': _kVariableFontWeights,
  'Montserrat': _kVariableFontWeights,
  'Raleway': _kVariableFontWeights,
  'Rubik': _kVariableFontWeights,
  'Quicksand': _kVariableFontWeights,
  'Karla': _kVariableFontWeights,
  'Cabin': _kVariableFontWeights,
  'Manrope': _kVariableFontWeights,
  'Mulish': _kVariableFontWeights,
  'SourceSans3': _kVariableFontWeights,
  'WorkSans': _kVariableFontWeights,
  'Cairo': _kVariableFontWeights,
  'Changa': _kVariableFontWeights,
  'ElMessiri': _kVariableFontWeights,
  'ReemKufi': _kVariableFontWeights,
  'NotoNaskhArabic': _kVariableFontWeights,
  'NotoKufiArabic': _kVariableFontWeights,
  'MarkaziText': _kVariableFontWeights,
  'Mada': _kVariableFontWeights,
  'Lemonada': _kVariableFontWeights,
  'BalooBhaijaan2': _kVariableFontWeights,
};

const List<Color> _kTextPalette = <Color>[
  Color(0xFF000000),
  Color(0xFF111827),
  Color(0xFF1F2937),
  Color(0xFF374151),
  Color(0xFF4B5563),
  Color(0xFF6B7280),
  Color(0xFF9CA3AF),
  Color(0xFFD1D5DB),
  Color(0xFFE5E7EB),
  Color(0xFFF3F4F6),
  Color(0xFFFFFFFF),
  Color(0xFF7F1D1D),
  Color(0xFFB91C1C),
  Color(0xFFEF4444),
  Color(0xFFF87171),
  Color(0xFF7C2D12),
  Color(0xFFEA580C),
  Color(0xFFF97316),
  Color(0xFFF59E0B),
  Color(0xFFFACC15),
  Color(0xFF365314),
  Color(0xFF4D7C0F),
  Color(0xFF65A30D),
  Color(0xFF84CC16),
  Color(0xFFA3E635),
  Color(0xFF14532D),
  Color(0xFF166534),
  Color(0xFF16A34A),
  Color(0xFF22C55E),
  Color(0xFF4ADE80),
  Color(0xFF064E3B),
  Color(0xFF047857),
  Color(0xFF0D9488),
  Color(0xFF14B8A6),
  Color(0xFF2DD4BF),
  Color(0xFF0C4A6E),
  Color(0xFF0369A1),
  Color(0xFF0284C7),
  Color(0xFF0EA5E9),
  Color(0xFF38BDF8),
  Color(0xFF1E3A8A),
  Color(0xFF1D4ED8),
  Color(0xFF2563EB),
  Color(0xFF3B82F6),
  Color(0xFF60A5FA),
  Color(0xFF312E81),
  Color(0xFF6D28D9),
  Color(0xFFA21CAF),
  Color(0xFFDB2777),
];

class _WonderPicEditorScreenState extends State<WonderPicEditorScreen> {
  static const int _historyLimit = 120;
  final ImagePicker _picker = ImagePicker();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _textInputController = TextEditingController();
  final FocusNode _textInputFocusNode = FocusNode();
  List<EditorLayer> _layers = <EditorLayer>[];
  int _nextLayerId = 1;
  bool _isPickingImage = false;
  EditorTool _activeTool = EditorTool.move;
  String? _selectedLayerId;
  PencilSettings _pencilSettings = const PencilSettings();
  CloneStampSettings _cloneSettings = const CloneStampSettings();
  bool _isCloneSourceArmed = false;
  _TextFontLocale _textFontLocale = _TextFontLocale.english;
  MarqueeSelectionMode _marqueeMode = MarqueeSelectionMode.rectangular;
  MarqueeSelection? _marqueeSelection;
  _MarqueeClipboard? _marqueeClipboard;
  bool _isMarqueeActionInProgress = false;
  bool _isSyncingTextInput = false;
  final List<_EditorSnapshot> _undoStack = <_EditorSnapshot>[];
  final List<_EditorSnapshot> _redoStack = <_EditorSnapshot>[];
  bool _isTransformHistoryCaptured = false;
  bool _isTextEditHistoryCaptured = false;

  @override
  void initState() {
    super.initState();
    _textInputController.addListener(_onTextInputChanged);
    _textInputFocusNode.addListener(_onTextFocusChanged);
  }

  @override
  void dispose() {
    _textInputController.removeListener(_onTextInputChanged);
    _textInputFocusNode.removeListener(_onTextFocusChanged);
    _textInputController.dispose();
    _textInputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: WonderPicEditorScreen._pageBg,
      resizeToAvoidBottomInset: false,
      endDrawer: _buildToolSettingsSidebar(context),
      endDrawerEnableOpenDragGesture: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              _buildTopTools(),
              const SizedBox(height: 14),
              Expanded(
                child: _buildEditorCanvasPanel(),
              ),
              const SizedBox(height: 12),
              _buildBottomNav(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopTools() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WonderPicEditorScreen._barsFill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _toolButton(icon: Icons.menu, filled: false),
          const SizedBox(width: 8),
          _toolbarSectionDivider(),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _toolButton(
                    icon: Icons.open_with_rounded,
                    filled: _activeTool == EditorTool.move,
                    onTap: () => _setActiveTool(EditorTool.move),
                  ),
                  const SizedBox(width: 8),
                  _toolButton(
                    icon: Icons.edit_outlined,
                    filled: _activeTool == EditorTool.pencil,
                    onTap: () => _setActiveTool(EditorTool.pencil),
                  ),
                  const SizedBox(width: 8),
                  _toolButton(
                    icon: Icons.crop_din_rounded,
                    filled: _activeTool == EditorTool.marquee,
                    onTap: () => _setActiveTool(EditorTool.marquee),
                  ),
                  const SizedBox(width: 8),
                  _toolButton(
                    filled: _activeTool == EditorTool.clone,
                    onTap: () => _setActiveTool(EditorTool.clone),
                    customChild: const _CloneStampToolIcon(
                      color: WonderPicEditorScreen._iconColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _toolbarSectionDivider(),
          const SizedBox(width: 8),
          _toolButton(
            filled: false,
            onTap: _openToolSettingsSidebar,
            customChild: const Icon(
              Icons.tune_rounded,
              size: 16,
              color: WonderPicEditorScreen._iconColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbarSectionDivider() {
    return Container(
      width: 1.2,
      height: 34,
      color: const Color(0xFFC7CDD8),
    );
  }

  Widget _toolButton({
    IconData? icon,
    required bool filled,
    Widget? customChild,
    VoidCallback? onTap,
  }) {
    final Widget button = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color:
            filled ? const Color(0xFFE0E7F1) : WonderPicEditorScreen._panelBg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFD5DAE1)),
      ),
      child: customChild ??
          Icon(icon, size: 18, color: WonderPicEditorScreen._iconColor),
    );
    if (onTap == null) return button;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: button,
      ),
    );
  }

  Widget _buildEditorCanvasPanel() {
    return _SkiaEditorCanvas(
      layers: _layers,
      activeTool: _activeTool,
      pencilSettings: _pencilSettings,
      cloneSettings: _cloneSettings,
      marqueeMode: _marqueeMode,
      marqueeSelection: _marqueeSelection,
      isCloneSourceArmed: _isCloneSourceArmed,
      selectedLayerId: _selectedLayerId,
      onLayerSelected: _onLayerSelected,
      onLayerTransformChanged: _onLayerTransformChanged,
      onLayerImageChanged: _onLayerImageChanged,
      onMarqueeSelectionChanged: _onMarqueeSelectionChanged,
      onCloneSourcePicked: _onCloneSourcePicked,
      onCanvasMessage: _showToolMessage,
      onTextLayerDoubleTap: _onTextLayerDoubleTap,
      onTransformInteractionStart: _onTransformInteractionStart,
      onTransformInteractionEnd: _onTransformInteractionEnd,
    );
  }

  void _setActiveTool(EditorTool tool) {
    if (_activeTool == tool) return;
    setState(() {
      _activeTool = tool;
      if (tool != EditorTool.clone) {
        _isCloneSourceArmed = false;
      }
      if (tool != EditorTool.marquee && _marqueeSelection != null) {
        _marqueeSelection = null;
      }
    });
  }

  void _openToolSettingsSidebar() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  Widget _buildToolSettingsSidebar(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width * 0.75;
    return Drawer(
      width: width,
      backgroundColor: const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          bottomLeft: Radius.circular(18),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _toolSettingsTitle(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2F3743),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: Color(0xFF4C5562),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: SingleChildScrollView(
                  child: _buildToolSettingsContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  EditorTool? _resolvedSettingsTool() {
    if (_activeTool == EditorTool.move) {
      final EditorLayer? selectedLayer = _selectedLayer();
      if (selectedLayer?.type == EditorLayerType.text) {
        return EditorTool.text;
      }
      return null;
    }
    return _activeTool;
  }

  String _toolSettingsTitle() {
    final EditorTool? resolved = _resolvedSettingsTool();
    switch (resolved) {
      case EditorTool.move:
        return 'Layer Settings';
      case EditorTool.pencil:
        return 'Pencil Tool Settings';
      case EditorTool.text:
        return 'Text Tool Settings';
      case EditorTool.clone:
        return 'Clone Tool Settings';
      case EditorTool.marquee:
        return 'Selection Tool Settings';
      case null:
        final EditorLayer? selectedLayer = _selectedLayer();
        if (_activeTool == EditorTool.move) {
          if (selectedLayer == null) return 'Layer Settings';
          return '${selectedLayer.type.label} Layer Settings';
        }
        return 'Tool Settings';
    }
  }

  Widget _buildToolSettingsContent() {
    final EditorTool? resolved = _resolvedSettingsTool();
    switch (resolved) {
      case EditorTool.move:
        return const _ToolHintCard(
          title: 'Layer Settings',
          message:
              'Selection tool has no direct settings. Select a layer to view related options.',
        );
      case EditorTool.pencil:
        return _buildPencilSettingsPanel();
      case EditorTool.text:
        return _buildTextSettingsPanel();
      case EditorTool.clone:
        return _buildCloneSettingsPanel();
      case EditorTool.marquee:
        return _buildMarqueeSettingsPanel();
      case null:
        final EditorLayer? selectedLayer = _selectedLayer();
        if (_activeTool == EditorTool.move) {
          if (selectedLayer == null) {
            return const _ToolHintCard(
              title: 'No Layer Selected',
              message:
                  'Selection tool has no direct settings. Select a layer to control transform and layer-specific options.',
            );
          }
          return _ToolHintCard(
            title: '${selectedLayer.type.label} Layer',
            message:
                'Selection tool has no dedicated settings. This panel reflects ${selectedLayer.type.label.toLowerCase()} layer context.',
          );
        }
        return const _ToolHintCard(
          title: 'Settings',
          message: 'No settings available for current context.',
        );
    }
  }

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  _EditorSnapshot _captureSnapshot() {
    return _EditorSnapshot(
      layers: List<EditorLayer>.from(_layers),
      selectedLayerId: _selectedLayerId,
      activeTool: _activeTool,
      nextLayerId: _nextLayerId,
      isCloneSourceArmed: _isCloneSourceArmed,
      textFontLocale: _textFontLocale,
      marqueeMode: _marqueeMode,
      marqueeSelection: _marqueeSelection,
    );
  }

  bool _snapshotsEqual(_EditorSnapshot a, _EditorSnapshot b) {
    if (a.selectedLayerId != b.selectedLayerId) return false;
    if (a.activeTool != b.activeTool) return false;
    if (a.nextLayerId != b.nextLayerId) return false;
    if (a.isCloneSourceArmed != b.isCloneSourceArmed) return false;
    if (a.textFontLocale != b.textFontLocale) return false;
    if (a.marqueeMode != b.marqueeMode) return false;
    if (!_marqueeSelectionsEqual(a.marqueeSelection, b.marqueeSelection)) {
      return false;
    }
    if (a.layers.length != b.layers.length) return false;
    for (int i = 0; i < a.layers.length; i++) {
      if (!identical(a.layers[i], b.layers[i])) return false;
    }
    return true;
  }

  void _pushUndoSnapshot() {
    final _EditorSnapshot snapshot = _captureSnapshot();
    if (_undoStack.isNotEmpty && _snapshotsEqual(_undoStack.last, snapshot)) {
      return;
    }
    _undoStack.add(snapshot);
    if (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _applySnapshot(_EditorSnapshot snapshot) {
    setState(() {
      _layers = List<EditorLayer>.from(snapshot.layers);
      _selectedLayerId = snapshot.selectedLayerId;
      _activeTool = snapshot.activeTool;
      _nextLayerId = snapshot.nextLayerId;
      _isCloneSourceArmed = snapshot.isCloneSourceArmed;
      _textFontLocale = snapshot.textFontLocale;
      _marqueeMode = snapshot.marqueeMode;
      _marqueeSelection = snapshot.marqueeSelection;
      _isTransformHistoryCaptured = false;
      _isTextEditHistoryCaptured = false;
    });
    _syncTextInputFromSelectedLayer();
  }

  void _undo() {
    if (!_canUndo) return;
    final _EditorSnapshot current = _captureSnapshot();
    final _EditorSnapshot target = _undoStack.removeLast();
    _redoStack.add(current);
    if (_redoStack.length > _historyLimit) {
      _redoStack.removeAt(0);
    }
    _applySnapshot(target);
  }

  void _redo() {
    if (!_canRedo) return;
    final _EditorSnapshot current = _captureSnapshot();
    final _EditorSnapshot target = _redoStack.removeLast();
    _undoStack.add(current);
    if (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
    _applySnapshot(target);
  }

  void _onTransformInteractionStart() {
    if (_isTransformHistoryCaptured) return;
    _pushUndoSnapshot();
    _isTransformHistoryCaptured = true;
  }

  void _onTransformInteractionEnd() {
    _isTransformHistoryCaptured = false;
  }

  bool _marqueeSelectionsEqual(MarqueeSelection? a, MarqueeSelection? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.layerId != b.layerId) return false;
    if (a.mode != b.mode) return false;
    if (a.boundsUv != b.boundsUv) return false;
    if (a.freePathUv.length != b.freePathUv.length) return false;
    for (int i = 0; i < a.freePathUv.length; i++) {
      if (a.freePathUv[i] != b.freePathUv[i]) return false;
    }
    return true;
  }

  void _onMarqueeSelectionChanged(MarqueeSelection? selection) {
    final MarqueeSelection? sanitized =
        selection != null && selection.hasUsableArea ? selection : null;
    if (_marqueeSelectionsEqual(_marqueeSelection, sanitized)) return;
    setState(() {
      _marqueeSelection = sanitized;
    });
  }

  void _onTextFocusChanged() {
    if (_textInputFocusNode.hasFocus) return;
    _isTextEditHistoryCaptured = false;
  }

  Widget _buildPencilSettingsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSliderTile(
          label: 'Brush Size',
          value: _pencilSettings.size,
          min: 1,
          max: 80,
          valueText: _pencilSettings.size.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              _pencilSettings = _pencilSettings.copyWith(size: value);
            });
          },
        ),
        const SizedBox(height: 10),
        _SettingsSliderTile(
          label: 'Hardness',
          value: _pencilSettings.hardness,
          min: 0,
          max: 100,
          valueText: '${_pencilSettings.hardness.toStringAsFixed(0)}%',
          onChanged: (value) {
            setState(() {
              _pencilSettings = _pencilSettings.copyWith(hardness: value);
            });
          },
        ),
        const SizedBox(height: 10),
        _SettingsSliderTile(
          label: 'Opacity',
          value: _pencilSettings.opacity,
          min: 1,
          max: 100,
          valueText: '${_pencilSettings.opacity.toStringAsFixed(0)}%',
          onChanged: (value) {
            setState(() {
              _pencilSettings = _pencilSettings.copyWith(opacity: value);
            });
          },
        ),
        const SizedBox(height: 10),
        _SettingsSliderTile(
          label: 'Brush Angle',
          value: _pencilSettings.angle,
          min: -180,
          max: 180,
          valueText: '${_pencilSettings.angle.toStringAsFixed(0)}°',
          onChanged: (value) {
            setState(() {
              _pencilSettings = _pencilSettings.copyWith(angle: value);
            });
          },
        ),
        const SizedBox(height: 14),
        const Text(
          'Brush Type',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2F3743),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PencilBrushType.values.map((type) {
            final bool selected = _pencilSettings.type == type;
            return ChoiceChip(
              label: Text(
                type.label,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF2F3743)
                      : const Color(0xFF6B7482),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              selected: selected,
              backgroundColor: const Color(0xFFF4F5F7),
              selectedColor: const Color(0xFFE0E7F1),
              side: const BorderSide(color: Color(0xFFC7CDD8)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              onSelected: (_) {
                setState(() {
                  _pencilSettings = _pencilSettings.copyWith(type: type);
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        const Text(
          'Brush Color',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2F3743),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD5DAE1)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kPencilPalette.map((color) {
              final bool selected = _pencilSettings.color == color;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _pencilSettings = _pencilSettings.copyWith(color: color);
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFF6F8FC)
                          : const Color(0x80424754),
                      width: selected ? 2.2 : 1,
                    ),
                    boxShadow: selected
                        ? const [
                            BoxShadow(
                              color: Color(0x552A2F3B),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check,
                          size: 14,
                          color: Color(0xFF1E2430),
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  EditorLayer? _selectedLayer() {
    if (_selectedLayerId == null) return null;
    for (final EditorLayer layer in _layers) {
      if (layer.id == _selectedLayerId) {
        return layer;
      }
    }
    return null;
  }

  EditorLayer? _selectedImageLayer() {
    final EditorLayer? layer = _selectedLayer();
    if (layer == null) return null;
    if (!layer.isVisible) return null;
    if (layer.type != EditorLayerType.image) return null;
    if (layer.image == null) return null;
    return layer;
  }

  EditorLayer? _selectedMarqueeLayer() {
    final EditorLayer? layer = _selectedImageLayer();
    if (layer == null) return null;
    if (!layer.isBackground) return null;
    return layer;
  }

  EditorLayer? _selectedTextLayer() {
    final EditorLayer? layer = _selectedLayer();
    if (layer == null) return null;
    if (!layer.isVisible) return null;
    if (layer.type != EditorLayerType.text) return null;
    return layer;
  }

  void _onTextInputChanged() {
    if (_isSyncingTextInput) return;
    final EditorLayer? selectedTextLayer = _selectedTextLayer();
    if (selectedTextLayer == null) return;
    if (!_isTextEditHistoryCaptured) {
      _pushUndoSnapshot();
      _isTextEditHistoryCaptured = true;
    }
    _updateTextLayer(
      selectedTextLayer.id,
      textValue: _textInputController.text,
      recordHistory: false,
    );
  }

  void _syncTextInputFromSelectedLayer() {
    final EditorLayer? selectedTextLayer = _selectedTextLayer();
    if (selectedTextLayer == null) return;
    final String value = selectedTextLayer.textValue ?? 'Write your text here';
    if (_textInputController.text != value) {
      _isSyncingTextInput = true;
      _textInputController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      _isSyncingTextInput = false;
    }
  }

  void _syncTextLocaleFromFamily(String? family) {
    if (family == null) return;
    if (_kArabicFontOptions.any((option) => option.family == family)) {
      _textFontLocale = _TextFontLocale.arabic;
      return;
    }
    if (_kEnglishFontOptions.any((option) => option.family == family)) {
      _textFontLocale = _TextFontLocale.english;
    }
  }

  List<int> _availableWeightsForFamily(String family) {
    return _kFontWeightSupport[family] ?? _kDefaultFontWeights;
  }

  int _resolveSupportedWeight(String family, int requestedWeight) {
    final List<int> supported = _availableWeightsForFamily(family);
    int nearest = supported.first;
    int nearestDistance = (requestedWeight - nearest).abs();
    for (final int value in supported) {
      final int distance = (requestedWeight - value).abs();
      if (distance < nearestDistance) {
        nearest = value;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  FontWeight _fontWeightFromValue(int weight) {
    return _fontWeightFromNumeric(weight);
  }

  void _updateTextLayer(
    String layerId, {
    String? textValue,
    String? textFontFamily,
    int? textFontWeight,
    Color? textColor,
    bool recordHistory = true,
  }) {
    final int index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index < 0) return;
    final List<EditorLayer> nextLayers = List<EditorLayer>.from(_layers);
    final EditorLayer current = nextLayers[index];
    final String nextTextValue = textValue ?? current.textValue ?? '';
    final String currentTextValue = current.textValue ?? '';
    final String nextFontFamily =
        textFontFamily ?? current.textFontFamily ?? '';
    final String currentFontFamily = current.textFontFamily ?? '';
    final int nextFontWeight = textFontWeight ?? current.textFontWeight ?? 400;
    final int currentFontWeight = current.textFontWeight ?? 400;
    final Color nextTextColor =
        textColor ?? current.textColor ?? const Color(0xFF1F2937);
    final Color currentTextColor = current.textColor ?? const Color(0xFF1F2937);
    if (nextTextValue == currentTextValue &&
        nextFontFamily == currentFontFamily &&
        nextFontWeight == currentFontWeight &&
        nextTextColor == currentTextColor) {
      return;
    }
    final EditorLayer next = current.copyWith(
      textValue: textValue,
      textFontFamily: textFontFamily,
      textFontWeight: textFontWeight,
      textColor: textColor,
    );
    nextLayers[index] = next;
    if (recordHistory) {
      _pushUndoSnapshot();
    }
    setState(() {
      _layers = nextLayers;
    });
  }

  void _openTextSidebar({required bool requestFocus}) {
    _scaffoldKey.currentState?.openEndDrawer();
    if (!requestFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        _textInputFocusNode.requestFocus();
      });
    });
  }

  void _createTextLayerAndOpenEditor() {
    final String? layerId = _createTextLayer(shouldShowError: true);
    if (layerId == null) return;
    _syncTextInputFromSelectedLayer();
    _openTextSidebar(requestFocus: true);
  }

  String? _createTextLayer({required bool shouldShowError}) {
    final EditorLayer? workspace = _workspaceLayerForEdit(_layers);
    final Size? workspaceSize =
        workspace == null ? null : _workspaceSourceSize(workspace);
    if (workspaceSize == null) {
      if (shouldShowError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add a background image or solid layer first'),
          ),
        );
      }
      return null;
    }

    final int textCount =
        _layers.where((layer) => layer.type == EditorLayerType.text).length;
    final String id = 'layer_${_nextLayerId++}';
    final EditorLayer textLayer = EditorLayer(
      id: id,
      name: textCount == 0 ? 'Text' : 'Text ${textCount + 1}',
      type: EditorLayerType.text,
      isVisible: true,
      textValue: 'Write your text here',
      textColor: const Color(0xFF1F2937),
      textFontSize: 92,
      textFontFamily: _kEnglishFontOptions.first.family,
      textFontWeight: 400,
      position: Offset(workspaceSize.width / 2, workspaceSize.height / 2),
      layerScale: 1.0,
      layerRotation: 0.0,
    );

    _pushUndoSnapshot();
    setState(() {
      _layers = <EditorLayer>[..._layers, textLayer];
      _selectedLayerId = id;
      _activeTool = EditorTool.text;
      _isCloneSourceArmed = false;
      _isTextEditHistoryCaptured = false;
      _isTransformHistoryCaptured = false;
    });
    return id;
  }

  void _onTextLayerDoubleTap(String layerId) {
    final int index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index < 0) return;
    final EditorLayer layer = _layers[index];
    if (layer.type != EditorLayerType.text) return;
    setState(() {
      _selectedLayerId = layerId;
      _activeTool = EditorTool.text;
      _isCloneSourceArmed = false;
    });
    _syncTextInputFromSelectedLayer();
    _openTextSidebar(requestFocus: true);
  }

  Widget _buildTextSettingsPanel() {
    final EditorLayer? selectedTextLayer = _selectedTextLayer();
    if (selectedTextLayer != null) {
      _syncTextInputFromSelectedLayer();
    }

    final List<_TextFontOption> options =
        _textFontLocale == _TextFontLocale.english
            ? _kEnglishFontOptions
            : _kArabicFontOptions;
    final String selectedFamily =
        selectedTextLayer?.textFontFamily ?? options.first.family;
    final int selectedWeight = _resolveSupportedWeight(
      selectedFamily,
      selectedTextLayer?.textFontWeight ?? 400,
    );
    final List<int> availableWeights =
        _availableWeightsForFamily(selectedFamily);
    final Color selectedColor =
        selectedTextLayer?.textColor ?? const Color(0xFF1F2937);
    const double fontCardHeight = 76;
    const double fontCardSpacing = 8;
    const double fontListVisibleCards = 5;
    const double fontListHeight = (fontCardHeight * fontListVisibleCards) +
        (fontCardSpacing * (fontListVisibleCards - 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD5DAE1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Text',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2F3743),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _textInputController,
                focusNode: _textInputFocusNode,
                enabled: selectedTextLayer != null,
                minLines: 2,
                maxLines: 4,
                style: TextStyle(
                  color: const Color(0xFF2F3743),
                  fontSize: 16,
                  fontFamily: selectedFamily,
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: 'Write your text here',
                  hintStyle: const TextStyle(
                    color: Color(0xFF6B7482),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFFFFFF),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFD5DAE1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFD5DAE1)),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFD5DAE1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF667185)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _TextLocaleToggleButton(
                label: 'English',
                selected: _textFontLocale == _TextFontLocale.english,
                onTap: () {
                  setState(() {
                    _textFontLocale = _TextFontLocale.english;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TextLocaleToggleButton(
                label: 'عربي',
                selected: _textFontLocale == _TextFontLocale.arabic,
                onTap: () {
                  setState(() {
                    _textFontLocale = _TextFontLocale.arabic;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (selectedTextLayer == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD5DAE1)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'No text layer selected',
                    style: TextStyle(
                      color: Color(0xFF6B7482),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _createTextLayerAndOpenEditor,
                  child: const Text('Add Text'),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD5DAE1)),
                ),
                child: SizedBox(
                  height: fontListHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ListView.separated(
                      primary: false,
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: fontCardSpacing),
                      itemBuilder: (context, index) {
                        final _TextFontOption option = options[index];
                        final bool selected = selectedFamily == option.family;
                        final int previewWeight = _resolveSupportedWeight(
                          option.family,
                          600,
                        );
                        return SizedBox(
                          height: fontCardHeight,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                final int nextWeight = _resolveSupportedWeight(
                                  option.family,
                                  selectedWeight,
                                );
                                _updateTextLayer(
                                  selectedTextLayer.id,
                                  textFontFamily: option.family,
                                  textFontWeight: nextWeight,
                                );
                                setState(() {
                                  _syncTextLocaleFromFamily(option.family);
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFFFF),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFF6F8BFF)
                                        : const Color(0xFFD5DAE1),
                                    width: selected ? 1.4 : 1,
                                  ),
                                ),
                                child: Directionality(
                                  textDirection: option.direction,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        option.label,
                                        style: TextStyle(
                                          color: const Color(0xFF2F3743),
                                          fontSize: 14.5,
                                          fontWeight: _fontWeightFromValue(
                                              previewWeight),
                                          fontFamily: option.family,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        option.preview,
                                        style: TextStyle(
                                          color: const Color(0xFF6B7482),
                                          fontSize: 12.5,
                                          height: 1.15,
                                          fontWeight: _fontWeightFromValue(
                                            _resolveSupportedWeight(
                                              option.family,
                                              400,
                                            ),
                                          ),
                                          fontFamily: option.family,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD5DAE1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Weight',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2F3743),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableWeights.map((weightValue) {
                        final bool isSelected = selectedWeight == weightValue;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              _updateTextLayer(
                                selectedTextLayer.id,
                                textFontWeight: weightValue,
                              );
                            },
                            child: Container(
                              width: 44,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFE0E7F1)
                                    : const Color(0xFFFFFFFF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF6F8BFF)
                                      : const Color(0xFFD5DAE1),
                                  width: isSelected ? 1.3 : 1,
                                ),
                              ),
                              child: Text(
                                'B',
                                style: TextStyle(
                                  color: const Color(0xFF2F3743),
                                  fontSize: 18,
                                  fontFamily: selectedFamily,
                                  fontWeight: _fontWeightFromValue(weightValue),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD5DAE1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Text Color',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2F3743),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _kTextPalette.map((color) {
                        final bool isSelected = selectedColor == color;
                        return GestureDetector(
                          onTap: () {
                            _updateTextLayer(
                              selectedTextLayer.id,
                              textColor: color,
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFF6F8FC)
                                    : const Color(0x80424754),
                                width: isSelected ? 2.2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? const [
                                      BoxShadow(
                                        color: Color(0x552A2F3B),
                                        blurRadius: 6,
                                        offset: Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    size: 13,
                                    color: Color(0xFF1E2430),
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildCloneSettingsPanel() {
    final EditorLayer? selectedImageLayer = _selectedImageLayer();
    final bool enabled = selectedImageLayer != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD5DAE1)),
          ),
          child: Text(
            enabled
                ? (_isCloneSourceArmed
                    ? 'Tap on the image to set clone source.'
                    : 'Clone works on selected Image Layer only.')
                : 'Select an Image Layer first. Clone tool is disabled for Text, Vector, Mask, and Solid layers.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7482),
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  enabled ? const Color(0xFFE0E7F1) : const Color(0xFFE8ECF3),
              foregroundColor: const Color(0xFF2F3743),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            onPressed: enabled ? _armCloneSourceSelection : null,
            icon: const Icon(Icons.control_point_duplicate, size: 18),
            label: Text(
              _isCloneSourceArmed ? 'Waiting For Source Tap' : 'Select Source',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        IgnorePointer(
          ignoring: !enabled,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Column(
              children: [
                _SettingsSliderTile(
                  label: 'Brush Size',
                  value: _cloneSettings.size,
                  min: 1,
                  max: 140,
                  valueText: _cloneSettings.size.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(() {
                      _cloneSettings = _cloneSettings.copyWith(size: value);
                    });
                  },
                ),
                const SizedBox(height: 10),
                _SettingsSliderTile(
                  label: 'Hardness',
                  value: _cloneSettings.hardness,
                  min: 0,
                  max: 100,
                  valueText: '${_cloneSettings.hardness.toStringAsFixed(0)}%',
                  onChanged: (value) {
                    setState(() {
                      _cloneSettings = _cloneSettings.copyWith(hardness: value);
                    });
                  },
                ),
                const SizedBox(height: 10),
                _SettingsSliderTile(
                  label: 'Opacity',
                  value: _cloneSettings.opacity,
                  min: 1,
                  max: 100,
                  valueText: '${_cloneSettings.opacity.toStringAsFixed(0)}%',
                  onChanged: (value) {
                    setState(() {
                      _cloneSettings = _cloneSettings.copyWith(opacity: value);
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarqueeSettingsPanel() {
    final EditorLayer? selectedImageLayer = _selectedMarqueeLayer();
    final bool imageReady = selectedImageLayer != null;
    final bool hasSelection = _marqueeSelection != null &&
        _marqueeSelection!.hasUsableArea &&
        _marqueeSelection!.layerId == selectedImageLayer?.id;
    final bool canPaste = imageReady && _marqueeClipboard != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD5DAE1)),
          ),
          child: Text(
            imageReady
                ? (hasSelection
                    ? 'Selection active on Image Layer. Use actions below.'
                    : 'Drag on the image to create selection.')
                : 'Select the Background Image Layer first. Selection tool currently edits workspace image pixels.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7482),
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD5DAE1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selection Type',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2F3743),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MarqueeSelectionMode.values.map((mode) {
                  final bool selected = _marqueeMode == mode;
                  return ChoiceChip(
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        _marqueeMode = mode;
                        _marqueeSelection = null;
                      });
                    },
                    avatar: Icon(
                      mode.icon,
                      size: 16,
                      color: selected
                          ? const Color(0xFF2F3743)
                          : const Color(0xFF6B7482),
                    ),
                    label: Text(
                      mode.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? const Color(0xFF2F3743)
                            : const Color(0xFF6B7482),
                      ),
                    ),
                    backgroundColor: const Color(0xFFFFFFFF),
                    selectedColor: const Color(0xFFE0E7F1),
                    side: BorderSide(
                      color: selected
                          ? const Color(0xFF6F8BFF)
                          : const Color(0xFFD5DAE1),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IgnorePointer(
          ignoring: _isMarqueeActionInProgress,
          child: Opacity(
            opacity: _isMarqueeActionInProgress ? 0.65 : 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double tileWidth = (constraints.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MarqueeActionTile(
                      width: tileWidth,
                      icon: Icons.copy_rounded,
                      label: 'Copy',
                      enabled: hasSelection,
                      onTap: () => _runMarqueeAction(_copyMarqueeSelection),
                    ),
                    _MarqueeActionTile(
                      width: tileWidth,
                      icon: Icons.content_cut_rounded,
                      label: 'Cut',
                      enabled: hasSelection,
                      onTap: () => _runMarqueeAction(_cutMarqueeSelection),
                    ),
                    _MarqueeActionTile(
                      width: tileWidth,
                      icon: Icons.paste_rounded,
                      label: 'Paste',
                      enabled: canPaste,
                      onTap: () => _runMarqueeAction(_pasteMarqueeClipboard),
                    ),
                    _MarqueeActionTile(
                      width: tileWidth,
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      enabled: hasSelection,
                      onTap: () => _runMarqueeAction(_deleteMarqueeSelection),
                    ),
                    _MarqueeActionTile(
                      width: tileWidth,
                      icon: Icons.layers_outlined,
                      label: 'New Layer',
                      enabled: hasSelection,
                      onTap: () =>
                          _runMarqueeAction(_createLayerFromMarqueeSelection),
                    ),
                    _MarqueeActionTile(
                      width: tileWidth,
                      icon: Icons.crop_rounded,
                      label: 'Crop',
                      enabled: hasSelection,
                      onTap: () => _runMarqueeAction(_cropToMarqueeSelection),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _runMarqueeAction(Future<void> Function() action) async {
    if (_isMarqueeActionInProgress) return;
    setState(() {
      _isMarqueeActionInProgress = true;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _isMarqueeActionInProgress = false;
        });
      }
    }
  }

  Future<void> _copyMarqueeSelection() async {
    final EditorLayer? layer = _selectedMarqueeLayer();
    final MarqueeSelection? selection = _marqueeSelection;
    if (layer == null || selection == null || selection.layerId != layer.id) {
      return;
    }
    final Uint8List? sourcePixels = await _readImagePixels(layer.image!);
    if (sourcePixels == null) return;
    final _SelectionRaster? raster = _rasterizeSelection(
      sourcePixels: sourcePixels,
      imageWidth: layer.image!.width,
      imageHeight: layer.image!.height,
      selection: selection,
    );
    if (raster == null || !raster.hasVisiblePixels) return;
    if (!mounted) return;
    setState(() {
      _marqueeClipboard = _MarqueeClipboard(
        pixels: raster.pixels,
        width: raster.width,
        height: raster.height,
        sourceBoundsUv: selection.boundsUv,
      );
    });
  }

  Future<void> _cutMarqueeSelection() async {
    final EditorLayer? layer = _selectedMarqueeLayer();
    final MarqueeSelection? selection = _marqueeSelection;
    if (layer == null || selection == null || selection.layerId != layer.id) {
      return;
    }
    final Uint8List? sourcePixels = await _readImagePixels(layer.image!);
    if (sourcePixels == null) return;
    final _SelectionRaster? raster = _rasterizeSelection(
      sourcePixels: sourcePixels,
      imageWidth: layer.image!.width,
      imageHeight: layer.image!.height,
      selection: selection,
    );
    if (raster == null || !raster.hasVisiblePixels) return;

    final Uint8List nextPixels = Uint8List.fromList(sourcePixels);
    _eraseSelectionFromPixels(
      pixels: nextPixels,
      imageWidth: layer.image!.width,
      imageHeight: layer.image!.height,
      selection: selection,
      bounds: raster.bounds,
    );
    final ui.Image nextImage = await _buildUiImageFromRgba(
      pixels: nextPixels,
      width: layer.image!.width,
      height: layer.image!.height,
    );
    if (!mounted) return;

    _pushUndoSnapshot();
    setState(() {
      _replaceLayerImage(layer.id, nextImage);
      _marqueeClipboard = _MarqueeClipboard(
        pixels: raster.pixels,
        width: raster.width,
        height: raster.height,
        sourceBoundsUv: selection.boundsUv,
      );
    });
  }

  Future<void> _deleteMarqueeSelection() async {
    final EditorLayer? layer = _selectedMarqueeLayer();
    final MarqueeSelection? selection = _marqueeSelection;
    if (layer == null || selection == null || selection.layerId != layer.id) {
      return;
    }
    final Uint8List? sourcePixels = await _readImagePixels(layer.image!);
    if (sourcePixels == null) return;
    final _SelectionPixelBounds? bounds = _selectionPixelBounds(
      selection: selection,
      imageWidth: layer.image!.width,
      imageHeight: layer.image!.height,
    );
    if (bounds == null) return;

    final Uint8List nextPixels = Uint8List.fromList(sourcePixels);
    _eraseSelectionFromPixels(
      pixels: nextPixels,
      imageWidth: layer.image!.width,
      imageHeight: layer.image!.height,
      selection: selection,
      bounds: bounds,
    );
    final ui.Image nextImage = await _buildUiImageFromRgba(
      pixels: nextPixels,
      width: layer.image!.width,
      height: layer.image!.height,
    );
    if (!mounted) return;

    _pushUndoSnapshot();
    setState(() {
      _replaceLayerImage(layer.id, nextImage);
    });
  }

  Future<void> _createLayerFromMarqueeSelection() async {
    final EditorLayer? layer = _selectedMarqueeLayer();
    final MarqueeSelection? selection = _marqueeSelection;
    if (layer == null || selection == null || selection.layerId != layer.id) {
      return;
    }
    final EditorLayer? workspaceLayer = _workspaceLayerForEdit(_layers);
    final Size? workspaceSize =
        workspaceLayer == null ? null : _workspaceSourceSize(workspaceLayer);
    if (workspaceSize == null) return;
    final Uint8List? sourcePixels = await _readImagePixels(layer.image!);
    if (sourcePixels == null) return;
    final _SelectionRaster? raster = _rasterizeSelection(
      sourcePixels: sourcePixels,
      imageWidth: layer.image!.width,
      imageHeight: layer.image!.height,
      selection: selection,
    );
    if (raster == null || !raster.hasVisiblePixels) return;

    final ui.Image extractedImage = await _buildUiImageFromRgba(
      pixels: raster.pixels,
      width: raster.width,
      height: raster.height,
    );
    if (!mounted) return;

    final Offset selectionCenter = Offset(
      selection.boundsUv.center.dx * workspaceSize.width,
      selection.boundsUv.center.dy * workspaceSize.height,
    );

    _pushUndoSnapshot();
    setState(() {
      final int overlayImageCount = _layers
          .where((entry) =>
              entry.type == EditorLayerType.image && !entry.isBackground)
          .length;
      final String newId = 'layer_${_nextLayerId++}';
      final EditorLayer extractedLayer = EditorLayer(
        id: newId,
        name: overlayImageCount == 0
            ? 'Selection Layer'
            : 'Selection Layer ${overlayImageCount + 1}',
        type: EditorLayerType.image,
        isVisible: true,
        image: extractedImage,
        solidSize: _imageSourceSize(extractedImage),
        position: selectionCenter,
        layerScale: 1.0,
        layerRotation: 0.0,
      );
      _layers = <EditorLayer>[..._layers, extractedLayer];
      _selectedLayerId = newId;
      _activeTool = EditorTool.move;
      _marqueeSelection = null;
    });
  }

  Future<void> _pasteMarqueeClipboard() async {
    final EditorLayer? layer = _selectedMarqueeLayer();
    final _MarqueeClipboard? clipboard = _marqueeClipboard;
    if (layer == null || clipboard == null) return;
    final EditorLayer? workspaceLayer = _workspaceLayerForEdit(_layers);
    final Size? workspaceSize =
        workspaceLayer == null ? null : _workspaceSourceSize(workspaceLayer);
    if (workspaceSize == null) return;
    final Rect targetBoundsUv = (_marqueeSelection != null &&
            _marqueeSelection!.layerId == layer.id &&
            _marqueeSelection!.hasUsableArea)
        ? _marqueeSelection!.boundsUv
        : clipboard.sourceBoundsUv;
    final MarqueeSelection targetSelection = MarqueeSelection(
      layerId: layer.id,
      mode: MarqueeSelectionMode.rectangular,
      boundsUv: targetBoundsUv,
    );
    final _SelectionPixelBounds? targetBounds = _selectionPixelBounds(
      selection: targetSelection,
      imageWidth: layer.image!.width,
      imageHeight: layer.image!.height,
    );
    if (targetBounds == null) return;

    final Uint8List pastedPixels =
        Uint8List(targetBounds.width * targetBounds.height * 4);
    for (int y = 0; y < targetBounds.height; y++) {
      final int srcY = ((y * clipboard.height) / targetBounds.height)
          .floor()
          .clamp(0, clipboard.height - 1);
      for (int x = 0; x < targetBounds.width; x++) {
        final int srcX = ((x * clipboard.width) / targetBounds.width)
            .floor()
            .clamp(0, clipboard.width - 1);
        final int sourceIndex = ((srcY * clipboard.width) + srcX) * 4;
        final int destIndex = ((y * targetBounds.width) + x) * 4;
        pastedPixels[destIndex] = clipboard.pixels[sourceIndex];
        pastedPixels[destIndex + 1] = clipboard.pixels[sourceIndex + 1];
        pastedPixels[destIndex + 2] = clipboard.pixels[sourceIndex + 2];
        pastedPixels[destIndex + 3] = clipboard.pixels[sourceIndex + 3];
      }
    }
    final ui.Image pastedImage = await _buildUiImageFromRgba(
      pixels: pastedPixels,
      width: targetBounds.width,
      height: targetBounds.height,
    );
    if (!mounted) return;
    final Offset pasteCenter = Offset(
      targetBoundsUv.center.dx * workspaceSize.width,
      targetBoundsUv.center.dy * workspaceSize.height,
    );

    _pushUndoSnapshot();
    setState(() {
      final int overlayImageCount = _layers
          .where((entry) =>
              entry.type == EditorLayerType.image && !entry.isBackground)
          .length;
      final String newId = 'layer_${_nextLayerId++}';
      final EditorLayer pastedLayer = EditorLayer(
        id: newId,
        name: overlayImageCount == 0
            ? 'Pasted Layer'
            : 'Pasted Layer ${overlayImageCount + 1}',
        type: EditorLayerType.image,
        isVisible: true,
        image: pastedImage,
        solidSize: _imageSourceSize(pastedImage),
        position: pasteCenter,
        layerScale: 1.0,
        layerRotation: 0.0,
      );
      _layers = <EditorLayer>[..._layers, pastedLayer];
      _selectedLayerId = newId;
      _activeTool = EditorTool.move;
      _marqueeSelection = null;
    });
  }

  Future<void> _cropToMarqueeSelection() async {
    final EditorLayer? layer = _selectedMarqueeLayer();
    final MarqueeSelection? selection = _marqueeSelection;
    if (layer == null || selection == null || selection.layerId != layer.id) {
      return;
    }
    final Uint8List? sourcePixels = await _readImagePixels(layer.image!);
    if (sourcePixels == null) return;
    final _SelectionRaster? raster = _rasterizeSelection(
      sourcePixels: sourcePixels,
      imageWidth: layer.image!.width,
      imageHeight: layer.image!.height,
      selection: selection,
    );
    if (raster == null || !raster.hasVisiblePixels) return;

    final ui.Image croppedImage = await _buildUiImageFromRgba(
      pixels: raster.pixels,
      width: raster.width,
      height: raster.height,
    );
    if (!mounted) return;

    _pushUndoSnapshot();
    setState(() {
      _replaceLayerImage(layer.id, croppedImage);
      _marqueeSelection = null;
    });
  }

  Future<Uint8List?> _readImagePixels(ui.Image image) async {
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return Uint8List.fromList(data.buffer.asUint8List(0, data.lengthInBytes));
  }

  Future<ui.Image> _buildUiImageFromRgba({
    required Uint8List pixels,
    required int width,
    required int height,
  }) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image image) => completer.complete(image),
    );
    return completer.future;
  }

  _SelectionRaster? _rasterizeSelection({
    required Uint8List sourcePixels,
    required int imageWidth,
    required int imageHeight,
    required MarqueeSelection selection,
  }) {
    final _SelectionPixelBounds? bounds = _selectionPixelBounds(
      selection: selection,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    if (bounds == null) return null;

    final Uint8List outPixels = Uint8List(bounds.width * bounds.height * 4);
    bool hasVisiblePixels = false;
    for (int y = bounds.top; y < bounds.bottom; y++) {
      for (int x = bounds.left; x < bounds.right; x++) {
        final Offset uv = Offset(
          (x + 0.5) / imageWidth,
          (y + 0.5) / imageHeight,
        );
        if (!_selectionContainsUv(selection, uv)) continue;
        final int sourceIndex = ((y * imageWidth) + x) * 4;
        final int destIndex =
            (((y - bounds.top) * bounds.width) + (x - bounds.left)) * 4;
        outPixels[destIndex] = sourcePixels[sourceIndex];
        outPixels[destIndex + 1] = sourcePixels[sourceIndex + 1];
        outPixels[destIndex + 2] = sourcePixels[sourceIndex + 2];
        outPixels[destIndex + 3] = sourcePixels[sourceIndex + 3];
        if (outPixels[destIndex + 3] > 0) {
          hasVisiblePixels = true;
        }
      }
    }
    return _SelectionRaster(
      pixels: outPixels,
      width: bounds.width,
      height: bounds.height,
      bounds: bounds,
      hasVisiblePixels: hasVisiblePixels,
    );
  }

  _SelectionPixelBounds? _selectionPixelBounds({
    required MarqueeSelection selection,
    required int imageWidth,
    required int imageHeight,
  }) {
    final int left =
        (selection.boundsUv.left * imageWidth).floor().clamp(0, imageWidth - 1);
    final int top = (selection.boundsUv.top * imageHeight)
        .floor()
        .clamp(0, imageHeight - 1);
    final int right =
        (selection.boundsUv.right * imageWidth).ceil().clamp(1, imageWidth);
    final int bottom =
        (selection.boundsUv.bottom * imageHeight).ceil().clamp(1, imageHeight);
    if (right <= left || bottom <= top) return null;
    return _SelectionPixelBounds(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  bool _selectionContainsUv(MarqueeSelection selection, Offset uv) {
    switch (selection.mode) {
      case MarqueeSelectionMode.rectangular:
      case MarqueeSelectionMode.object:
        return selection.boundsUv.contains(uv);
      case MarqueeSelectionMode.elliptical:
        final Rect bounds = selection.boundsUv;
        if (bounds.width <= 0 || bounds.height <= 0) return false;
        final double dx = (uv.dx - bounds.center.dx) / (bounds.width / 2);
        final double dy = (uv.dy - bounds.center.dy) / (bounds.height / 2);
        return (dx * dx) + (dy * dy) <= 1;
      case MarqueeSelectionMode.freehand:
        if (selection.freePathUv.length < 3) return false;
        return _pointInPolygon(uv, selection.freePathUv);
    }
  }

  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final Offset a = polygon[i];
      final Offset b = polygon[j];
      final bool intersect = ((a.dy > point.dy) != (b.dy > point.dy)) &&
          (point.dx <
              ((b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy + 0.0000001)) +
                  a.dx);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  void _eraseSelectionFromPixels({
    required Uint8List pixels,
    required int imageWidth,
    required int imageHeight,
    required MarqueeSelection selection,
    required _SelectionPixelBounds bounds,
  }) {
    for (int y = bounds.top; y < bounds.bottom; y++) {
      for (int x = bounds.left; x < bounds.right; x++) {
        final Offset uv = Offset(
          (x + 0.5) / imageWidth,
          (y + 0.5) / imageHeight,
        );
        if (!_selectionContainsUv(selection, uv)) continue;
        final int index = ((y * imageWidth) + x) * 4;
        pixels[index] = 0;
        pixels[index + 1] = 0;
        pixels[index + 2] = 0;
        pixels[index + 3] = 0;
      }
    }
  }

  void _replaceLayerImage(String layerId, ui.Image image) {
    final int layerIndex = _layers.indexWhere((entry) => entry.id == layerId);
    if (layerIndex < 0) return;
    final List<EditorLayer> nextLayers = List<EditorLayer>.from(_layers);
    final EditorLayer current = nextLayers[layerIndex];
    nextLayers[layerIndex] = current.copyWith(
      image: image,
      solidSize: _imageSourceSize(image),
      thumbnailBytes: null,
    );
    _layers = nextLayers;
  }

  void _armCloneSourceSelection() {
    setState(() {
      _isCloneSourceArmed = true;
    });
    Navigator.of(context).maybePop();
  }

  void _onCloneSourcePicked() {
    if (!_isCloneSourceArmed) return;
    setState(() {
      _isCloneSourceArmed = false;
    });
  }

  void _showToolMessage(String message) {}

  void _onLayerImageChanged(String layerId, ui.Image image) {
    final int index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index < 0) return;
    final List<EditorLayer> nextLayers = List<EditorLayer>.from(_layers);
    final EditorLayer current = nextLayers[index];
    _pushUndoSnapshot();
    nextLayers[index] = current.copyWith(
      image: image,
      solidSize: _imageSourceSize(image),
    );
    setState(() {
      _layers = nextLayers;
      if (_marqueeSelection != null && _marqueeSelection!.layerId != layerId) {
        _marqueeSelection = null;
      }
    });
  }

  void _onLayerSelected(String? layerId) {
    if (_selectedLayerId == layerId) return;
    _isTransformHistoryCaptured = false;
    _isTextEditHistoryCaptured = false;
    setState(() {
      _selectedLayerId = layerId;
      final EditorLayer? selected = _selectedLayer();
      if (selected == null || selected.type != EditorLayerType.image) {
        _isCloneSourceArmed = false;
      }
      if (_marqueeSelection != null && _marqueeSelection!.layerId != layerId) {
        _marqueeSelection = null;
      }
      if (selected?.type == EditorLayerType.text) {
        _syncTextLocaleFromFamily(selected?.textFontFamily);
      }
    });
    _syncTextInputFromSelectedLayer();
  }

  void _onLayerTransformChanged(
    String layerId, {
    Offset? position,
    double? layerScale,
    double? layerRotation,
  }) {
    final int index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index < 0) return;
    final List<EditorLayer> nextLayers = List<EditorLayer>.from(_layers);
    final EditorLayer current = nextLayers[index];
    nextLayers[index] = current.copyWith(
      position: position,
      layerScale: layerScale,
      layerRotation: layerRotation,
    );
    setState(() {
      _layers = nextLayers;
    });
  }

  Future<void> _pickImageFromGallery() async {
    if (_isPickingImage) return;
    setState(() {
      _isPickingImage = true;
    });

    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
        imageQuality: 98,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final ui.Image image = await _decodeUiImage(bytes);
      if (!mounted) return;

      _pushUndoSnapshot();
      setState(() {
        _upsertBackgroundLayer(
          image: image,
          thumbnailBytes: bytes,
        );
      });
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gallery access failed. Please allow photo access and try again.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load image from gallery')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
        });
      }
    }
  }

  void _upsertBackgroundLayer({
    required ui.Image image,
    required Uint8List thumbnailBytes,
  }) {
    final List<EditorLayer> nextLayers = List<EditorLayer>.from(_layers);
    final int existingIndex =
        nextLayers.indexWhere((layer) => layer.isBackground);
    final String layerId = existingIndex >= 0
        ? nextLayers[existingIndex].id
        : 'layer_${_nextLayerId++}';

    final EditorLayer background = EditorLayer(
      id: layerId,
      name: 'Background',
      type: EditorLayerType.image,
      isBackground: true,
      isVisible: true,
      image: image,
      thumbnailBytes: thumbnailBytes,
      solidSize: _imageSourceSize(image),
    );

    if (existingIndex >= 0) {
      nextLayers[existingIndex] = background;
      _layers = nextLayers;
      _selectedLayerId = layerId;
      if (_marqueeSelection != null && _marqueeSelection!.layerId != layerId) {
        _marqueeSelection = null;
      }
      return;
    }

    nextLayers.insert(0, background);
    _layers = nextLayers;
    _selectedLayerId = layerId;
    if (_marqueeSelection != null && _marqueeSelection!.layerId != layerId) {
      _marqueeSelection = null;
    }
  }

  void _upsertSolidBackground({
    required Size solidSize,
    required String name,
  }) {
    final List<EditorLayer> nextLayers = List<EditorLayer>.from(_layers);
    final int existingIndex =
        nextLayers.indexWhere((layer) => layer.isBackground);
    final String layerId = existingIndex >= 0
        ? nextLayers[existingIndex].id
        : 'layer_${_nextLayerId++}';

    final EditorLayer background = EditorLayer(
      id: layerId,
      name: name,
      type: EditorLayerType.solid,
      isBackground: true,
      isVisible: true,
      solidColor: const Color(0xFFFFFFFF),
      solidSize: solidSize,
    );

    if (existingIndex >= 0) {
      nextLayers[existingIndex] = background;
      _layers = nextLayers;
      _selectedLayerId = layerId;
      if (_marqueeSelection != null && _marqueeSelection!.layerId != layerId) {
        _marqueeSelection = null;
      }
      return;
    }

    nextLayers.insert(0, background);
    _layers = nextLayers;
    _selectedLayerId = layerId;
    if (_marqueeSelection != null && _marqueeSelection!.layerId != layerId) {
      _marqueeSelection = null;
    }
  }

  Future<void> _openAddBottomSheet() async {
    if (_isPickingImage) return;
    final _AddAction? action = await showModalBottomSheet<_AddAction>(
      context: context,
      backgroundColor: const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC7CDD8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: const Color(0xFFF4F5F7),
                  leading: const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: Color(0xFF4C5562),
                    size: 20,
                  ),
                  title: const Text(
                    'Add image',
                    style: TextStyle(
                      color: Color(0xFF2F3743),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop(_AddAction.image);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: const Color(0xFFF4F5F7),
                  leading: const Icon(
                    Icons.dashboard_customize_outlined,
                    color: Color(0xFF4C5562),
                    size: 20,
                  ),
                  title: const Text(
                    'Add solid layer',
                    style: TextStyle(
                      color: Color(0xFF2F3743),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Square, Story, Portrait',
                    style: TextStyle(
                      color: Color(0xFF6B7482),
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop(_AddAction.solid);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == _AddAction.image) {
      await _pickImageFromGallery();
    } else if (action == _AddAction.solid) {
      await _openSolidLayerPresetBottomSheet();
    }
  }

  Future<void> _openSolidLayerPresetBottomSheet() async {
    const List<_SolidProjectPreset> presets = <_SolidProjectPreset>[
      _SolidProjectPreset(
        title: 'Square',
        subtitle: '1080 x 1080',
        size: Size(1080, 1080),
      ),
      _SolidProjectPreset(
        title: 'Story',
        subtitle: '1080 x 1920',
        size: Size(1080, 1920),
      ),
      _SolidProjectPreset(
        title: 'Portrait',
        subtitle: '1080 x 1350',
        size: Size(1080, 1350),
      ),
    ];

    final _SolidProjectPreset? selected =
        await showModalBottomSheet<_SolidProjectPreset>(
      context: context,
      backgroundColor: const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC7CDD8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Solid Layer Presets',
                    style: TextStyle(
                      color: Color(0xFF2F3743),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ...presets.map(
                  (preset) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      tileColor: const Color(0xFFF4F5F7),
                      leading: const Icon(
                        Icons.crop_square_rounded,
                        color: Color(0xFF4C5562),
                      ),
                      title: Text(
                        preset.title,
                        style: const TextStyle(
                          color: Color(0xFF2F3743),
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        preset.subtitle,
                        style: const TextStyle(
                          color: Color(0xFF6B7482),
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(preset),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;
    _pushUndoSnapshot();
    setState(() {
      _upsertSolidBackground(
        solidSize: selected.size,
        name: 'Background',
      );
    });
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      return frameInfo.image;
    } catch (_) {
      return painting.decodeImageFromList(bytes);
    }
  }

  Size _imageSourceSize(ui.Image image) {
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  Future<void> _openLayersBottomSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFC7CDD8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Layers',
                              style: TextStyle(
                                color: Color(0xFF2F3743),
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        _HistorySheetActionButton(
                          icon: Icons.undo_rounded,
                          enabled: _canUndo,
                          onTap: () {
                            _undo();
                            setSheetState(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                        _HistorySheetActionButton(
                          icon: Icons.redo_rounded,
                          enabled: _canRedo,
                          onTap: () {
                            _redo();
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_layers.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F5F7),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'No layers yet. Add an image to create the background workspace.',
                          style: TextStyle(
                            color: Color(0xFF6B7482),
                            fontSize: 12.5,
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _layers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final EditorLayer layer =
                                _layers[_layers.length - 1 - index];
                            return _LayerRow(
                              layer: layer,
                              selected: _selectedLayerId == layer.id,
                              onTap: () {
                                _onLayerSelected(layer.id);
                                setSheetState(() {});
                              },
                              onToggleVisibility: () {
                                _toggleLayerVisibility(layer.id);
                                setSheetState(() {});
                              },
                              onDelete: () {
                                _deleteLayer(layer.id);
                                setSheetState(() {});
                              },
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _toggleLayerVisibility(String layerId) {
    final List<EditorLayer> nextLayers = List<EditorLayer>.from(_layers);
    final int index = nextLayers.indexWhere((layer) => layer.id == layerId);
    if (index < 0) return;
    _pushUndoSnapshot();
    final EditorLayer layer = nextLayers[index];
    nextLayers[index] = layer.copyWith(isVisible: !layer.isVisible);
    setState(() {
      _layers = nextLayers;
      if (!nextLayers[index].isVisible && _selectedLayerId == layerId) {
        _selectedLayerId = null;
      }
      if (!nextLayers[index].isVisible &&
          _marqueeSelection != null &&
          _marqueeSelection!.layerId == layerId) {
        _marqueeSelection = null;
      }
    });
  }

  void _deleteLayer(String layerId) {
    final int index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index < 0) return;
    final EditorLayer target = _layers[index];
    _pushUndoSnapshot();
    setState(() {
      final List<EditorLayer> nextLayers = List<EditorLayer>.from(_layers);
      if (target.isBackground) {
        final Size? workspaceSize = _workspaceSourceSize(target);
        if (workspaceSize != null) {
          nextLayers[index] = EditorLayer(
            id: target.id,
            name: 'Background',
            type: EditorLayerType.solid,
            isVisible: true,
            isBackground: true,
            solidColor: const Color(0xFFFFFFFF),
            solidSize: workspaceSize,
          );
        } else {
          nextLayers.removeAt(index);
        }
      } else {
        nextLayers.removeAt(index);
      }
      _layers = nextLayers;
      if (_selectedLayerId == layerId && !target.isBackground) {
        _selectedLayerId = null;
      }
      if (_marqueeSelection != null && _marqueeSelection!.layerId == layerId) {
        _marqueeSelection = null;
      }
    });
  }

  Widget _buildBottomNav() {
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: WonderPicEditorScreen._barsFill,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: _NavItem(
              icon: Icons.layers_outlined,
              label: 'Layers',
              onTap: _openLayersBottomSheet,
            ),
          ),
          const Expanded(
              child: _NavItem(icon: Icons.home_outlined, label: 'Home')),
          Expanded(
            child: _NavItem(
              icon: Icons.add,
              label: _isPickingImage ? 'Loading' : 'Add',
              onTap: _openAddBottomSheet,
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.text_fields,
              label: 'Text',
              onTap: _createTextLayerAndOpenEditor,
            ),
          ),
          const Expanded(child: _NavItem(icon: Icons.search, label: 'Search')),
          const Expanded(
              child: _NavItem(icon: Icons.save_alt_outlined, label: 'Save')),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: WonderPicEditorScreen._iconColor),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              height: 1,
              fontWeight: FontWeight.w600,
              color: WonderPicEditorScreen._textColor,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _HistorySheetActionButton extends StatelessWidget {
  const _HistorySheetActionButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFFFFF),
              border: Border.all(color: const Color(0xFFD5DAE1), width: 1.2),
            ),
            child: Icon(
              icon,
              size: 18,
              color: const Color(0xFF4C5562),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarqueeActionTile extends StatelessWidget {
  const _MarqueeActionTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color borderColor =
        enabled ? const Color(0xFFD5DAE1) : const Color(0xFFE3E6EB);
    final Color iconColor =
        enabled ? const Color(0xFF4C5562) : const Color(0xFF9AA3B0);
    final Color textColor =
        enabled ? const Color(0xFF2F3743) : const Color(0xFF9AA3B0);
    final Color fillColor =
        enabled ? const Color(0xFFFFFFFF) : const Color(0xFFF0F2F6);

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: enabled ? onTap : null,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextLocaleToggleButton extends StatelessWidget {
  const _TextLocaleToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE0E7F1) : const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  selected ? const Color(0xFF6F8BFF) : const Color(0xFFD5DAE1),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? const Color(0xFF2F3743) : const Color(0xFF6B7482),
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSliderTile extends StatelessWidget {
  const _SettingsSliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueText,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String valueText;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFFC3CBD9),
          inactiveTrackColor: Color(0xFFC7CDD8),
          thumbColor: Color(0xFFF3F6FC),
          overlayColor: Color(0x33444A58),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F5F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD5DAE1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2F3743),
                    ),
                  ),
                ),
                Text(
                  valueText,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7482),
                  ),
                ),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolHintCard extends StatelessWidget {
  const _ToolHintCard({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD5DAE1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2F3743),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7482),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.layer,
    required this.selected,
    required this.onTap,
    required this.onToggleVisibility,
    required this.onDelete,
  });

  final EditorLayer layer;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggleVisibility;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? const Color(0xFF6F8BFF) : const Color(0xFFD5DAE1),
          width: selected ? 1.4 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 44,
                height: 44,
                color: const Color(0xFFE6EAF1),
                child: _buildLayerThumbnail(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          layer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF2F3743),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (layer.isBackground)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0E7F1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Work Area',
                            style: TextStyle(
                              color: Color(0xFF4C5562),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    layer.type.label,
                    style: const TextStyle(
                      color: Color(0xFF6B7482),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              splashRadius: 18,
              visualDensity: VisualDensity.compact,
              onPressed: onToggleVisibility,
              icon: Icon(
                layer.isVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 19,
                color: const Color(0xFF4C5562),
              ),
            ),
            IconButton(
              splashRadius: 18,
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_outline,
                size: 19,
                color: Color(0xFFFF8E8E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerThumbnail() {
    if (layer.type == EditorLayerType.image && layer.thumbnailBytes != null) {
      return Image.memory(layer.thumbnailBytes!, fit: BoxFit.cover);
    }
    if (layer.type == EditorLayerType.solid) {
      return Container(
        color: layer.solidColor ?? Colors.white,
        alignment: Alignment.center,
        child: const Icon(
          Icons.crop_square_rounded,
          color: Color(0xFF939CAF),
          size: 17,
        ),
      );
    }
    return Icon(
      layer.type.icon,
      color: const Color(0xFF6B7482),
      size: 20,
    );
  }
}

enum _CanvasInteraction {
  none,
  drawing,
  cloning,
  marqueeSelecting,
  movingLayer,
  resizingLayer,
  rotatingLayer,
}

class _SkiaEditorCanvas extends StatefulWidget {
  const _SkiaEditorCanvas({
    required this.layers,
    required this.activeTool,
    required this.pencilSettings,
    required this.cloneSettings,
    required this.marqueeMode,
    required this.marqueeSelection,
    required this.isCloneSourceArmed,
    required this.selectedLayerId,
    required this.onLayerSelected,
    required this.onLayerTransformChanged,
    required this.onLayerImageChanged,
    required this.onMarqueeSelectionChanged,
    required this.onCloneSourcePicked,
    required this.onCanvasMessage,
    required this.onTextLayerDoubleTap,
    required this.onTransformInteractionStart,
    required this.onTransformInteractionEnd,
  });

  final List<EditorLayer> layers;
  final EditorTool activeTool;
  final PencilSettings pencilSettings;
  final CloneStampSettings cloneSettings;
  final MarqueeSelectionMode marqueeMode;
  final MarqueeSelection? marqueeSelection;
  final bool isCloneSourceArmed;
  final String? selectedLayerId;
  final ValueChanged<String?> onLayerSelected;
  final LayerTransformChanged onLayerTransformChanged;
  final LayerImageChanged onLayerImageChanged;
  final ValueChanged<MarqueeSelection?> onMarqueeSelectionChanged;
  final VoidCallback onCloneSourcePicked;
  final ValueChanged<String> onCanvasMessage;
  final ValueChanged<String> onTextLayerDoubleTap;
  final VoidCallback onTransformInteractionStart;
  final VoidCallback onTransformInteractionEnd;

  @override
  State<_SkiaEditorCanvas> createState() => _SkiaEditorCanvasState();
}

class _SkiaEditorCanvasState extends State<_SkiaEditorCanvas> {
  final List<_BrushStroke> _strokes = <_BrushStroke>[];
  final Map<String, _EditableImageBuffer> _editableImages =
      <String, _EditableImageBuffer>{};
  final Set<String> _bitmapLoadInFlight = <String>{};
  final Map<String, Offset> _clonePointerUvByLayer = <String, Offset>{};
  final Map<String, _CloneBrushMask> _cloneBrushMaskCache =
      <String, _CloneBrushMask>{};

  _BrushStroke? _activeStroke;
  _CanvasInteraction _interaction = _CanvasInteraction.none;
  String? _gestureLayerId;
  _CloneStrokeSession? _activeCloneStroke;
  Offset? _cloneOffsetUv;
  Offset? _lastCloneDestUv;
  bool _cloneChangedLayer = false;
  Timer? _clonePreviewTimer;
  String? _clonePreviewLayerId;
  bool _clonePreviewPending = false;

  Offset _pan = Offset.zero;
  double _scale = 1.0;
  Offset _startFocal = Offset.zero;
  Offset _startPan = Offset.zero;
  double _startScale = 1.0;

  Offset _layerStartPosition = Offset.zero;
  Offset _layerStartScenePoint = Offset.zero;
  double _layerStartScale = 1.0;
  double _layerStartRotation = 0.0;
  double _resizeStartDistance = 1.0;
  double _rotateStartAngle = 0.0;
  Offset? _marqueeStartUv;
  final List<Offset> _freeMarqueePointsUv = <Offset>[];

  static const double _minScale = 0.6;
  static const double _maxScale = 3.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size canvasSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) => _onScaleStart(details, canvasSize),
          onScaleUpdate: (details) => _onScaleUpdate(details, canvasSize),
          onScaleEnd: _onScaleEnd,
          onDoubleTapDown: (details) => _onDoubleTapDown(details, canvasSize),
          child: CustomPaint(
            painter: _SkiaCanvasPainter(
              strokes: _strokes,
              layers: widget.layers,
              pan: _pan,
              scale: _scale,
              selectedLayerId: widget.selectedLayerId,
              activeTool: widget.activeTool,
              imageOverrides: _currentImageOverrides(),
              cloneSourcePointerUv: _activeClonePointerUv(),
              marqueeSelection: widget.marqueeSelection,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _cancelClonePreviewTimer(clearLayerId: true);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SkiaEditorCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final EditorLayer? oldBackground = _backgroundLayer(oldWidget.layers);
    final EditorLayer? newBackground = _backgroundLayer(widget.layers);
    final Size? oldSize =
        oldBackground == null ? null : _workspaceSourceSize(oldBackground);
    final Size? newSize =
        newBackground == null ? null : _workspaceSourceSize(newBackground);
    if (widget.activeTool != EditorTool.pencil &&
        _interaction == _CanvasInteraction.drawing) {
      _activeStroke = null;
      _interaction = _CanvasInteraction.none;
    }
    if (widget.activeTool != EditorTool.clone &&
        _interaction == _CanvasInteraction.cloning) {
      _cancelClonePreviewTimer(clearLayerId: true);
      _interaction = _CanvasInteraction.none;
      _gestureLayerId = null;
      _activeCloneStroke = null;
      _cloneOffsetUv = null;
      _lastCloneDestUv = null;
      _cloneChangedLayer = false;
    }
    if (widget.activeTool != EditorTool.marquee &&
        _interaction == _CanvasInteraction.marqueeSelecting) {
      _interaction = _CanvasInteraction.none;
      _gestureLayerId = null;
      _marqueeStartUv = null;
      _freeMarqueePointsUv.clear();
    }
    if (widget.activeTool == EditorTool.clone) {
      _primeSelectedCloneLayerBitmap();
    }
    _cleanupCloneCaches();

    final Map<String, EditorLayer> oldById = <String, EditorLayer>{
      for (final EditorLayer layer in oldWidget.layers) layer.id: layer,
    };
    for (final EditorLayer layer in widget.layers) {
      if (layer.type != EditorLayerType.image || layer.image == null) {
        continue;
      }
      final EditorLayer? oldLayer = oldById[layer.id];
      final bool imageChanged = oldLayer == null ||
          oldLayer.type != EditorLayerType.image ||
          !identical(oldLayer.image, layer.image);
      if (!imageChanged) continue;
      _editableImages.remove(layer.id);
      _bitmapLoadInFlight.remove(layer.id);
    }

    if (oldBackground?.id != newBackground?.id ||
        oldBackground?.thumbnailBytes != newBackground?.thumbnailBytes ||
        oldSize != newSize ||
        oldBackground?.solidColor != newBackground?.solidColor) {
      _cancelClonePreviewTimer(clearLayerId: true);
      setState(() {
        _strokes.clear();
        _activeStroke = null;
        _pan = Offset.zero;
        _scale = 1.0;
        _interaction = _CanvasInteraction.none;
        _gestureLayerId = null;
        _activeCloneStroke = null;
        _editableImages.clear();
        _bitmapLoadInFlight.clear();
        _cloneBrushMaskCache.clear();
        _clonePointerUvByLayer.clear();
        _cloneOffsetUv = null;
        _lastCloneDestUv = null;
        _cloneChangedLayer = false;
      });
    }
  }

  void _onScaleStart(ScaleStartDetails details, Size canvasSize) {
    _startFocal = details.localFocalPoint;
    _startPan = _pan;
    _startScale = _scale;
    _interaction = _CanvasInteraction.none;
    _gestureLayerId = null;
    _activeCloneStroke = null;
    _cloneOffsetUv = null;
    _lastCloneDestUv = null;
    _cloneChangedLayer = false;
    _cancelClonePreviewTimer(clearLayerId: false);

    if (details.pointerCount > 1) {
      _activeStroke = null;
      return;
    }

    final EditorLayer? workspace = _backgroundLayer(widget.layers);
    if (workspace == null) return;
    final Size? workspaceSize = _workspaceSourceSize(workspace);
    if (workspaceSize == null) return;

    final Rect artboard = _computeArtboardRect(
      canvasSize: canvasSize,
      workspaceSize: workspaceSize,
    );
    final Offset scenePoint = _toScenePoint(details.localFocalPoint);

    if (widget.activeTool == EditorTool.pencil) {
      if (!artboard.contains(scenePoint)) return;
      final Offset local = scenePoint - artboard.topLeft;
      final PencilSettings settings = widget.pencilSettings;
      final _BrushStroke stroke = _BrushStroke(
        points: <Offset>[local],
        color: settings.color.withOpacity(settings.opacity / 100),
        width: settings.size,
        hardness: settings.hardness,
        brushType: settings.type,
        angle: settings.angle,
      );
      setState(() {
        _activeStroke = stroke;
        _strokes.add(stroke);
        _interaction = _CanvasInteraction.drawing;
      });
      return;
    }

    if (widget.activeTool == EditorTool.clone) {
      _activeStroke = null;
      _startCloneGesture(scenePoint: scenePoint, artboard: artboard);
      return;
    }

    if (widget.activeTool == EditorTool.marquee) {
      _activeStroke = null;
      _startMarqueeGesture(scenePoint: scenePoint, artboard: artboard);
      return;
    }

    if (widget.activeTool != EditorTool.move) {
      _activeStroke = null;
      return;
    }

    _activeStroke = null;
    final EditorLayer? selectedLayer = _layerById(widget.selectedLayerId);
    final _TransformLayerSceneData? selectedData =
        _buildSelectedTransformLayerData(
      selectedLayer: selectedLayer,
      artboard: artboard,
      workspaceSize: workspaceSize,
    );

    if (selectedData != null) {
      // Keep move dominant inside text, but make rotate handle capture reliable.
      final double minLayerExtent =
          math.min(selectedData.width, selectedData.height);
      final bool isTinyLayer = minLayerExtent < 56;
      final double tinyBoost =
          ((56 - minLayerExtent).clamp(0, 32) / 32).toDouble();
      final double rotateHandleRadius =
          ((20 / _scale).clamp(14, 28) + (tinyBoost * 10)).clamp(14, 38);
      final double cornerHandleRadius =
          ((18 / _scale).clamp(12, 24) + (tinyBoost * 9)).clamp(12, 34);
      final double moveHitPadding = (2 / _scale).clamp(0.5, 3);
      if ((scenePoint - selectedData.rotateHandle).distance <=
          rotateHandleRadius) {
        _interaction = _CanvasInteraction.rotatingLayer;
        _gestureLayerId = selectedData.layerId;
        _layerStartRotation = selectedLayer!.layerRotation;
        widget.onTransformInteractionStart();
        _rotateStartAngle = math.atan2(scenePoint.dy - selectedData.center.dy,
            scenePoint.dx - selectedData.center.dx);
        return;
      }

      for (final Offset handle in selectedData.cornerHandles) {
        if ((scenePoint - handle).distance <= cornerHandleRadius) {
          _interaction = _CanvasInteraction.resizingLayer;
          _gestureLayerId = selectedData.layerId;
          _layerStartScale = selectedLayer!.layerScale;
          widget.onTransformInteractionStart();
          _resizeStartDistance = (scenePoint - selectedData.center).distance;
          if (_resizeStartDistance < 1) _resizeStartDistance = 1;
          return;
        }
      }

      if (_pointInRotatedLayerBounds(
        scenePoint,
        selectedData,
        padding: moveHitPadding,
      )) {
        _interaction = _CanvasInteraction.movingLayer;
        _gestureLayerId = selectedData.layerId;
        _layerStartPosition = selectedLayer!.position ??
            Offset(workspaceSize.width / 2, workspaceSize.height / 2);
        widget.onTransformInteractionStart();
        _layerStartScenePoint = scenePoint;
        return;
      }

      // Do not drop selection when tapping close to transform controls.
      final double controlsPadding = (10 / _scale).clamp(5, 14);
      if (_pointNearLayerTransformControls(
        scenePoint: scenePoint,
        data: selectedData,
        rotateHandleRadius: rotateHandleRadius + controlsPadding,
        cornerHandleRadius: cornerHandleRadius + controlsPadding,
        rotateLineDistance: (10 / _scale).clamp(5, 12),
      )) {
        // For very small layers, resolve to the nearest control to avoid
        // dead zones where handles are visually tiny and hard to reacquire.
        if (isTinyLayer) {
          final double rotateDistance =
              (scenePoint - selectedData.rotateHandle).distance;
          double nearestCornerDistance = double.infinity;
          for (final Offset handle in selectedData.cornerHandles) {
            final double distance = (scenePoint - handle).distance;
            if (distance < nearestCornerDistance) {
              nearestCornerDistance = distance;
            }
          }
          if (rotateDistance <= nearestCornerDistance) {
            _interaction = _CanvasInteraction.rotatingLayer;
            _gestureLayerId = selectedData.layerId;
            _layerStartRotation = selectedLayer!.layerRotation;
            widget.onTransformInteractionStart();
            _rotateStartAngle = math.atan2(
              scenePoint.dy - selectedData.center.dy,
              scenePoint.dx - selectedData.center.dx,
            );
            return;
          }
          _interaction = _CanvasInteraction.resizingLayer;
          _gestureLayerId = selectedData.layerId;
          _layerStartScale = selectedLayer!.layerScale;
          widget.onTransformInteractionStart();
          _resizeStartDistance = (scenePoint - selectedData.center).distance;
          if (_resizeStartDistance < 1) _resizeStartDistance = 1;
          return;
        }
        _interaction = _CanvasInteraction.none;
        return;
      }
    }

    final EditorLayer? hitLayer = _hitTopTransformLayer(
      scenePoint: scenePoint,
      artboard: artboard,
      workspaceSize: workspaceSize,
    );
    if (hitLayer != null) {
      widget.onLayerSelected(hitLayer.id);
      _interaction = _CanvasInteraction.movingLayer;
      _gestureLayerId = hitLayer.id;
      _layerStartPosition = hitLayer.position ??
          Offset(workspaceSize.width / 2, workspaceSize.height / 2);
      widget.onTransformInteractionStart();
      _layerStartScenePoint = scenePoint;
      return;
    }

    // Keep current selection when tapping near the selected text layer bounds.
    if (selectedData != null &&
        _pointInRotatedLayerBounds(
          scenePoint,
          selectedData,
          padding: (20 / _scale).clamp(10, 24),
        )) {
      _interaction = _CanvasInteraction.none;
      return;
    }

    widget.onLayerSelected(null);
    _interaction = _CanvasInteraction.none;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size canvasSize) {
    if (details.pointerCount > 1) {
      final bool wasTransforming =
          _interaction == _CanvasInteraction.movingLayer ||
              _interaction == _CanvasInteraction.resizingLayer ||
              _interaction == _CanvasInteraction.rotatingLayer;
      if (_interaction == _CanvasInteraction.marqueeSelecting) {
        _finalizeMarqueeSelection();
      }
      _activeStroke = null;
      _cancelClonePreviewTimer(clearLayerId: false);
      _interaction = _CanvasInteraction.none;
      _gestureLayerId = null;
      _activeCloneStroke = null;
      if (wasTransforming) {
        widget.onTransformInteractionEnd();
      }
      final double nextScale =
          (_startScale * details.scale).clamp(_minScale, _maxScale);
      final Offset nextPan = _clampPan(
        _startPan + (details.localFocalPoint - _startFocal),
        canvasSize,
      );
      setState(() {
        _scale = nextScale;
        _pan = nextPan;
      });
      return;
    }

    final EditorLayer? workspace = _backgroundLayer(widget.layers);
    if (workspace == null) return;
    final Size? workspaceSize = _workspaceSourceSize(workspace);
    if (workspaceSize == null) return;

    final Rect artboard = _computeArtboardRect(
      canvasSize: canvasSize,
      workspaceSize: workspaceSize,
    );
    final Offset scenePoint = _toScenePoint(details.localFocalPoint);

    if (_interaction == _CanvasInteraction.drawing) {
      if (_activeStroke == null) return;
      final Offset local = scenePoint - artboard.topLeft;
      setState(() {
        _activeStroke!.points.add(
          Offset(
            _clampDouble(local.dx, 0, artboard.width),
            _clampDouble(local.dy, 0, artboard.height),
          ),
        );
      });
      return;
    }

    if (_interaction == _CanvasInteraction.cloning) {
      _updateCloneGesture(scenePoint: scenePoint, artboard: artboard);
      return;
    }

    if (_interaction == _CanvasInteraction.marqueeSelecting) {
      _updateMarqueeGesture(scenePoint: scenePoint, artboard: artboard);
      return;
    }

    final String? layerId = _gestureLayerId;
    if (layerId == null) return;
    final EditorLayer? targetLayer = _layerById(layerId);
    if (targetLayer == null) return;
    final _TransformLayerSceneData? data = _buildSelectedTransformLayerData(
      selectedLayer: targetLayer,
      artboard: artboard,
      workspaceSize: workspaceSize,
    );
    if (data == null) return;

    if (_interaction == _CanvasInteraction.movingLayer) {
      final double sourcePerScene = workspaceSize.width / artboard.width;
      final Offset deltaScene = scenePoint - _layerStartScenePoint;
      final Offset nextPos = Offset(
        _layerStartPosition.dx + (deltaScene.dx * sourcePerScene),
        _layerStartPosition.dy + (deltaScene.dy * sourcePerScene),
      );
      widget.onLayerTransformChanged(
        layerId,
        position: Offset(
          _clampDouble(nextPos.dx, 0, workspaceSize.width),
          _clampDouble(nextPos.dy, 0, workspaceSize.height),
        ),
      );
      return;
    }

    if (_interaction == _CanvasInteraction.resizingLayer) {
      final double newDistance = (scenePoint - data.center).distance;
      final double nextScale =
          (_layerStartScale * (newDistance / _resizeStartDistance))
              .clamp(0.2, 12.0);
      widget.onLayerTransformChanged(layerId, layerScale: nextScale);
      return;
    }

    if (_interaction == _CanvasInteraction.rotatingLayer) {
      final double currentAngle = math.atan2(
          scenePoint.dy - data.center.dy, scenePoint.dx - data.center.dx);
      final double nextRotation =
          _layerStartRotation + (currentAngle - _rotateStartAngle);
      widget.onLayerTransformChanged(layerId, layerRotation: nextRotation);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final bool endedTransform =
        _interaction == _CanvasInteraction.movingLayer ||
            _interaction == _CanvasInteraction.resizingLayer ||
            _interaction == _CanvasInteraction.rotatingLayer;
    _cancelClonePreviewTimer(clearLayerId: false);
    if (_interaction == _CanvasInteraction.cloning && _cloneChangedLayer) {
      final String? layerId = _gestureLayerId;
      final _CloneStrokeSession? stroke = _activeCloneStroke;
      if (layerId != null && stroke != null) {
        final _EditableImageBuffer? buffer = _editableImages[layerId];
        if (buffer != null) {
          if (buffer.usesPreview) {
            _queueEditableImageRefresh(layerId);
            _enqueueFullResolutionCommit(
              layerId: layerId,
              stroke: stroke.freeze(),
            );
          } else {
            _queueEditableImageRefresh(layerId, notifyParent: true);
          }
        }
      }
    }
    if (_interaction == _CanvasInteraction.marqueeSelecting) {
      _finalizeMarqueeSelection();
    }
    _activeStroke = null;
    _interaction = _CanvasInteraction.none;
    _gestureLayerId = null;
    _activeCloneStroke = null;
    _cloneOffsetUv = null;
    _lastCloneDestUv = null;
    _cloneChangedLayer = false;
    _marqueeStartUv = null;
    _freeMarqueePointsUv.clear();
    if (endedTransform) {
      widget.onTransformInteractionEnd();
    }
  }

  void _onDoubleTapDown(TapDownDetails details, Size canvasSize) {
    if (widget.activeTool != EditorTool.text) return;

    final EditorLayer? workspace = _backgroundLayer(widget.layers);
    if (workspace == null) return;
    final Size? workspaceSize = _workspaceSourceSize(workspace);
    if (workspaceSize == null) return;

    final Rect artboard = _computeArtboardRect(
      canvasSize: canvasSize,
      workspaceSize: workspaceSize,
    );
    final Offset scenePoint = _toScenePoint(details.localPosition);
    final EditorLayer? hitLayer = _hitTopTextLayer(
      scenePoint: scenePoint,
      artboard: artboard,
      workspaceSize: workspaceSize,
    );
    if (hitLayer == null) return;

    widget.onLayerSelected(hitLayer.id);
    widget.onTextLayerDoubleTap(hitLayer.id);
  }

  Map<String, ui.Image> _currentImageOverrides() {
    final Map<String, ui.Image> overrides = <String, ui.Image>{};
    _editableImages.forEach((layerId, buffer) {
      overrides[layerId] = buffer.displayImage;
    });
    return overrides;
  }

  Offset? _activeClonePointerUv() {
    if (widget.activeTool != EditorTool.clone) return null;
    final EditorLayer? selectedLayer = _selectedImageLayerForClone();
    if (selectedLayer == null) return null;
    return _clonePointerUvByLayer[selectedLayer.id];
  }

  void _cleanupCloneCaches() {
    final Set<String> validImageLayerIds = widget.layers
        .where(
          (layer) => layer.type == EditorLayerType.image && layer.image != null,
        )
        .map((layer) => layer.id)
        .toSet();

    _editableImages
        .removeWhere((layerId, _) => !validImageLayerIds.contains(layerId));
    _clonePointerUvByLayer.removeWhere(
      (layerId, _) => !validImageLayerIds.contains(layerId),
    );
    _bitmapLoadInFlight
        .removeWhere((layerId) => !validImageLayerIds.contains(layerId));
  }

  EditorLayer? _selectedImageLayerForClone({String? layerId}) {
    final EditorLayer? layer = _layerById(layerId ?? widget.selectedLayerId);
    if (layer == null) return null;
    if (!layer.isVisible) return null;
    if (layer.type != EditorLayerType.image) return null;
    if (layer.image == null) return null;
    return layer;
  }

  EditorLayer? _selectedBackgroundImageLayerForMarquee() {
    final EditorLayer? layer = _selectedImageLayerForClone();
    if (layer == null) return null;
    if (!layer.isBackground) return null;
    return layer;
  }

  void _primeSelectedCloneLayerBitmap() {
    final EditorLayer? selectedLayer = _selectedImageLayerForClone();
    if (selectedLayer == null) return;
    _prepareEditableImageBuffer(selectedLayer);
  }

  Future<void> _prepareEditableImageBuffer(EditorLayer layer) async {
    if (layer.image == null) return;
    if (_editableImages.containsKey(layer.id) ||
        _bitmapLoadInFlight.contains(layer.id)) {
      return;
    }
    _bitmapLoadInFlight.add(layer.id);
    try {
      final ByteData? data = await layer.image!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (!mounted || data == null) return;
      final int fullWidth = layer.image!.width;
      final int fullHeight = layer.image!.height;
      final Uint8List fullPixels =
          Uint8List.fromList(data.buffer.asUint8List(0, data.lengthInBytes));

      int previewWidth = fullWidth;
      int previewHeight = fullHeight;
      double previewScale = 1.0;
      Uint8List previewPixels = fullPixels;
      ui.Image previewImage = layer.image!;

      const int maxPreviewDimension = 2048;
      final int maxSide = math.max(fullWidth, fullHeight);
      if (maxSide > maxPreviewDimension) {
        previewScale = maxPreviewDimension / maxSide;
        previewWidth = math.max(1, (fullWidth * previewScale).round());
        previewHeight = math.max(1, (fullHeight * previewScale).round());
        previewPixels = _downscaleRgbaNearest(
          sourcePixels: fullPixels,
          sourceWidth: fullWidth,
          sourceHeight: fullHeight,
          targetWidth: previewWidth,
          targetHeight: previewHeight,
        );
        previewImage = await _imageFromPixels(
          pixels: previewPixels,
          width: previewWidth,
          height: previewHeight,
        );
      }
      if (!mounted) return;
      setState(() {
        _editableImages[layer.id] = _EditableImageBuffer(
          fullWidth: fullWidth,
          fullHeight: fullHeight,
          fullPixels: fullPixels,
          fullImage: layer.image!,
          previewWidth: previewWidth,
          previewHeight: previewHeight,
          previewPixels: previewPixels,
          previewImage: previewImage,
          previewScale: previewScale,
        );
      });
    } catch (_) {
      if (mounted) {
        widget.onCanvasMessage('Could not prepare image for clone');
      }
    } finally {
      _bitmapLoadInFlight.remove(layer.id);
    }
  }

  void _startCloneGesture({
    required Offset scenePoint,
    required Rect artboard,
  }) {
    final EditorLayer? layer = _selectedImageLayerForClone();
    if (layer == null) {
      widget.onCanvasMessage(
        'Clone tool works only when an Image Layer is selected',
      );
      return;
    }
    if (!artboard.contains(scenePoint)) return;

    final Offset tapUv = _toUv(scenePoint, artboard);

    if (widget.isCloneSourceArmed) {
      setState(() {
        _clonePointerUvByLayer[layer.id] = tapUv;
      });
      widget.onCloneSourcePicked();
      return;
    }

    final Offset? sourceUv = _clonePointerUvByLayer[layer.id];
    if (sourceUv == null) {
      return;
    }

    final _EditableImageBuffer? buffer = _editableImages[layer.id];
    if (buffer == null) {
      _prepareEditableImageBuffer(layer);
      widget.onCanvasMessage('Preparing layer for clone, try again');
      return;
    }

    _interaction = _CanvasInteraction.cloning;
    _gestureLayerId = layer.id;
    _cloneOffsetUv = sourceUv - tapUv;
    _lastCloneDestUv = tapUv;
    _activeCloneStroke = _CloneStrokeSession(
      layerId: layer.id,
      sourceOffsetUv: _cloneOffsetUv!,
      settings: widget.cloneSettings,
      artboardWidth: artboard.width,
      destPointsUv: <Offset>[tapUv],
    );

    _applyCloneSegment(
      layerId: layer.id,
      buffer: buffer,
      fromDestUv: tapUv,
      toDestUv: tapUv,
      stroke: _activeCloneStroke!,
    );
    _queueEditableImageRefresh(layer.id);

    _cloneChangedLayer = true;
  }

  void _startMarqueeGesture({
    required Offset scenePoint,
    required Rect artboard,
  }) {
    final EditorLayer? selectedImage =
        _selectedBackgroundImageLayerForMarquee();
    if (selectedImage == null) {
      widget.onMarqueeSelectionChanged(null);
      return;
    }
    if (!artboard.contains(scenePoint)) return;

    final Offset startUv = _toUv(scenePoint, artboard);
    _interaction = _CanvasInteraction.marqueeSelecting;
    _gestureLayerId = selectedImage.id;
    _marqueeStartUv = startUv;
    _freeMarqueePointsUv.clear();

    if (widget.marqueeMode == MarqueeSelectionMode.freehand) {
      _freeMarqueePointsUv.add(startUv);
      widget.onMarqueeSelectionChanged(
        _buildFreehandSelection(selectedImage.id),
      );
      return;
    }
    widget.onMarqueeSelectionChanged(
      _buildBoundsSelection(
        layerId: selectedImage.id,
        startUv: startUv,
        endUv: startUv,
      ),
    );
  }

  void _updateMarqueeGesture({
    required Offset scenePoint,
    required Rect artboard,
  }) {
    final String? layerId = _gestureLayerId;
    if (layerId == null) return;
    if (!artboard.contains(scenePoint)) return;
    final Offset currentUv = _toUv(scenePoint, artboard);

    if (widget.marqueeMode == MarqueeSelectionMode.freehand) {
      if (_freeMarqueePointsUv.isEmpty ||
          (_freeMarqueePointsUv.last - currentUv).distance > 0.002) {
        _freeMarqueePointsUv.add(currentUv);
        widget.onMarqueeSelectionChanged(_buildFreehandSelection(layerId));
      }
      return;
    }

    final Offset? startUv = _marqueeStartUv;
    if (startUv == null) return;
    widget.onMarqueeSelectionChanged(
      _buildBoundsSelection(
        layerId: layerId,
        startUv: startUv,
        endUv: currentUv,
      ),
    );
  }

  void _finalizeMarqueeSelection() {
    final MarqueeSelection? selection = widget.marqueeSelection;
    if (selection != null && !selection.hasUsableArea) {
      widget.onMarqueeSelectionChanged(null);
    }
  }

  MarqueeSelection _buildBoundsSelection({
    required String layerId,
    required Offset startUv,
    required Offset endUv,
  }) {
    final Rect bounds = Rect.fromLTRB(
      math.min(startUv.dx, endUv.dx),
      math.min(startUv.dy, endUv.dy),
      math.max(startUv.dx, endUv.dx),
      math.max(startUv.dy, endUv.dy),
    );
    return MarqueeSelection(
      layerId: layerId,
      mode: widget.marqueeMode,
      boundsUv: bounds,
    );
  }

  MarqueeSelection _buildFreehandSelection(String layerId) {
    if (_freeMarqueePointsUv.isEmpty) {
      return MarqueeSelection(
        layerId: layerId,
        mode: MarqueeSelectionMode.freehand,
        boundsUv: Rect.zero,
      );
    }
    double minX = _freeMarqueePointsUv.first.dx;
    double minY = _freeMarqueePointsUv.first.dy;
    double maxX = _freeMarqueePointsUv.first.dx;
    double maxY = _freeMarqueePointsUv.first.dy;
    for (final Offset point in _freeMarqueePointsUv) {
      if (point.dx < minX) minX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy > maxY) maxY = point.dy;
    }
    return MarqueeSelection(
      layerId: layerId,
      mode: MarqueeSelectionMode.freehand,
      boundsUv: Rect.fromLTRB(minX, minY, maxX, maxY),
      freePathUv: List<Offset>.from(_freeMarqueePointsUv),
    );
  }

  void _updateCloneGesture({
    required Offset scenePoint,
    required Rect artboard,
  }) {
    final String? layerId = _gestureLayerId;
    final Offset? sourceOffsetUv = _cloneOffsetUv;
    final _CloneStrokeSession? stroke = _activeCloneStroke;
    if (layerId == null || sourceOffsetUv == null || stroke == null) return;
    final _EditableImageBuffer? buffer = _editableImages[layerId];
    if (buffer == null) return;

    final Offset nextDestUv = _toUv(scenePoint, artboard);
    final Offset fromDestUv = _lastCloneDestUv ?? nextDestUv;
    final double movementPx =
        (nextDestUv - fromDestUv).distance * buffer.previewWidth;
    if (movementPx < 0.25) return;

    _applyCloneSegment(
      layerId: layerId,
      buffer: buffer,
      fromDestUv: fromDestUv,
      toDestUv: nextDestUv,
      stroke: stroke,
    );

    stroke.destPointsUv.add(nextDestUv);
    _lastCloneDestUv = nextDestUv;
    _cloneChangedLayer = true;
  }

  void _applyCloneSegment({
    required String layerId,
    required _EditableImageBuffer buffer,
    required Offset fromDestUv,
    required Offset toDestUv,
    required _CloneStrokeSession stroke,
  }) {
    _paintCloneSegmentOnPixels(
      pixels: buffer.previewPixels,
      targetWidth: buffer.previewWidth,
      targetHeight: buffer.previewHeight,
      fromDestUv: fromDestUv,
      toDestUv: toDestUv,
      sourceOffsetUv: stroke.sourceOffsetUv,
      settings: stroke.settings,
      artboardWidth: stroke.artboardWidth,
      onSourceAdvanced: (sourceUv) {
        _clonePointerUvByLayer[layerId] = sourceUv;
      },
    );
    _scheduleClonePreviewRefresh(layerId);
  }

  void _paintCloneSegmentOnPixels({
    required Uint8List pixels,
    required int targetWidth,
    required int targetHeight,
    required Offset fromDestUv,
    required Offset toDestUv,
    required Offset sourceOffsetUv,
    required CloneStampSettings settings,
    required double artboardWidth,
    ValueChanged<Offset>? onSourceAdvanced,
  }) {
    final double radiusPx =
        math.max(1.0, (settings.size * targetWidth / artboardWidth) / 2);
    final _CloneBrushMask brushMask = _resolveCloneBrushMask(
      radiusPx: radiusPx,
      hardness: settings.hardness,
    );
    final Offset delta = toDestUv - fromDestUv;
    final double distancePx = delta.distance * targetWidth;
    final int steps = math.max(
      1,
      (distancePx / math.max(1.0, radiusPx * 0.55)).ceil(),
    );
    for (int i = 0; i <= steps; i++) {
      final double t = steps == 0 ? 1 : i / steps;
      final Offset destUv = _clampUv(
        Offset.lerp(fromDestUv, toDestUv, t) ?? toDestUv,
      );
      final Offset sourceUv = _clampUv(destUv + sourceOffsetUv);
      _applyCloneStamp(
        pixels: pixels,
        width: targetWidth,
        height: targetHeight,
        sourceUv: sourceUv,
        destUv: destUv,
        brushMask: brushMask,
        opacityFactor: settings.opacity / 100,
      );
      onSourceAdvanced?.call(sourceUv);
    }
  }

  void _applyCloneStamp({
    required Uint8List pixels,
    required int width,
    required int height,
    required Offset sourceUv,
    required Offset destUv,
    required _CloneBrushMask brushMask,
    required double opacityFactor,
  }) {
    final int sourceX = (sourceUv.dx * (width - 1)).round();
    final int sourceY = (sourceUv.dy * (height - 1)).round();
    final int destX = (destUv.dx * (width - 1)).round();
    final int destY = (destUv.dy * (height - 1)).round();
    final int radius = brushMask.radius;
    final int maskWidth = brushMask.size;
    final List<double> alphaGrid = brushMask.alphaGrid;

    for (int y = -radius; y <= radius; y++) {
      final int sy = sourceY + y;
      final int dy = destY + y;
      if (sy < 0 || sy >= height || dy < 0 || dy >= height) continue;
      for (int x = -radius; x <= radius; x++) {
        final int sx = sourceX + x;
        final int dx = destX + x;
        if (sx < 0 || sx >= width || dx < 0 || dx >= width) continue;
        final int maskIndex = ((y + radius) * maskWidth) + (x + radius);
        final double alpha = (alphaGrid[maskIndex] * opacityFactor).clamp(
          0.0,
          1.0,
        );
        if (alpha <= 0) continue;

        final int sourceIndex = ((sy * width) + sx) * 4;
        final int destIndex = ((dy * width) + dx) * 4;
        final int sr = pixels[sourceIndex];
        final int sg = pixels[sourceIndex + 1];
        final int sb = pixels[sourceIndex + 2];
        final int sa = pixels[sourceIndex + 3];

        pixels[destIndex] = _blendChannel(pixels[destIndex], sr, alpha);
        pixels[destIndex + 1] = _blendChannel(pixels[destIndex + 1], sg, alpha);
        pixels[destIndex + 2] = _blendChannel(pixels[destIndex + 2], sb, alpha);
        pixels[destIndex + 3] = _blendChannel(pixels[destIndex + 3], sa, alpha);
      }
    }
  }

  void _enqueueFullResolutionCommit({
    required String layerId,
    required _CloneStrokeSession stroke,
  }) {
    if (stroke.layerId != layerId) return;
    final _EditableImageBuffer? buffer = _editableImages[layerId];
    if (buffer == null) return;
    buffer.pendingCommits.add(stroke);
    if (buffer.isCommittingFull) return;
    buffer.isCommittingFull = true;
    unawaited(_runFullResolutionCommitQueue(layerId));
  }

  Future<void> _runFullResolutionCommitQueue(String layerId) async {
    while (mounted) {
      final _EditableImageBuffer? buffer = _editableImages[layerId];
      if (buffer == null) return;
      if (buffer.pendingCommits.isEmpty) {
        buffer.isCommittingFull = false;
        return;
      }

      final _CloneStrokeSession stroke = buffer.pendingCommits.removeAt(0);
      await _replayStrokeOnFullBuffer(
        buffer: buffer,
        stroke: stroke,
      );

      final Uint8List fullSnapshot = Uint8List.fromList(buffer.fullPixels);
      final ui.Image renderedImage = await _imageFromPixels(
        pixels: fullSnapshot,
        width: buffer.fullWidth,
        height: buffer.fullHeight,
      );
      if (!mounted) return;

      final _EditableImageBuffer? latest = _editableImages[layerId];
      if (latest == null) return;
      latest.fullImage = renderedImage;
      widget.onLayerImageChanged(layerId, renderedImage);
    }
  }

  Future<void> _replayStrokeOnFullBuffer({
    required _EditableImageBuffer buffer,
    required _CloneStrokeSession stroke,
  }) async {
    if (stroke.destPointsUv.isEmpty) return;

    Offset previous = stroke.destPointsUv.first;
    for (int i = 0; i < stroke.destPointsUv.length; i++) {
      final Offset current = stroke.destPointsUv[i];
      _paintCloneSegmentOnPixels(
        pixels: buffer.fullPixels,
        targetWidth: buffer.fullWidth,
        targetHeight: buffer.fullHeight,
        fromDestUv: i == 0 ? current : previous,
        toDestUv: current,
        sourceOffsetUv: stroke.sourceOffsetUv,
        settings: stroke.settings,
        artboardWidth: stroke.artboardWidth,
      );
      previous = current;
      if (i % 4 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
    }
  }

  Uint8List _downscaleRgbaNearest({
    required Uint8List sourcePixels,
    required int sourceWidth,
    required int sourceHeight,
    required int targetWidth,
    required int targetHeight,
  }) {
    final Uint8List targetPixels = Uint8List(targetWidth * targetHeight * 4);
    for (int y = 0; y < targetHeight; y++) {
      final int sourceY = ((y * sourceHeight) / targetHeight).floor().clamp(
            0,
            sourceHeight - 1,
          );
      for (int x = 0; x < targetWidth; x++) {
        final int sourceX = ((x * sourceWidth) / targetWidth).floor().clamp(
              0,
              sourceWidth - 1,
            );
        final int sourceIndex = ((sourceY * sourceWidth) + sourceX) * 4;
        final int targetIndex = ((y * targetWidth) + x) * 4;
        targetPixels[targetIndex] = sourcePixels[sourceIndex];
        targetPixels[targetIndex + 1] = sourcePixels[sourceIndex + 1];
        targetPixels[targetIndex + 2] = sourcePixels[sourceIndex + 2];
        targetPixels[targetIndex + 3] = sourcePixels[sourceIndex + 3];
      }
    }
    return targetPixels;
  }

  int _blendChannel(int base, int source, double alpha) {
    final double mixed = base + ((source - base) * alpha);
    return mixed.clamp(0, 255).round();
  }

  _CloneBrushMask _resolveCloneBrushMask({
    required double radiusPx,
    required double hardness,
  }) {
    final int radius = math.max(1, radiusPx.ceil());
    final int hardnessInt = hardness.round().clamp(0, 100);
    final String key = '${radius}_$hardnessInt';
    final _CloneBrushMask? cached = _cloneBrushMaskCache[key];
    if (cached != null) return cached;

    final int size = (radius * 2) + 1;
    final double radiusSquared = radiusPx * radiusPx;
    final double hardRadius = radiusPx * (hardnessInt / 100);
    final double hardRadiusSquared = hardRadius * hardRadius;
    final List<double> alphaGrid = List<double>.filled(size * size, 0);

    for (int y = -radius; y <= radius; y++) {
      for (int x = -radius; x <= radius; x++) {
        final double distSquared = ((x * x) + (y * y)).toDouble();
        if (distSquared > radiusSquared) continue;
        double alpha = 1.0;
        if (hardRadius < radiusPx && distSquared > hardRadiusSquared) {
          final double dist = math.sqrt(distSquared);
          alpha = 1 - ((dist - hardRadius) / (radiusPx - hardRadius));
        }
        final int index = ((y + radius) * size) + (x + radius);
        alphaGrid[index] = alpha.clamp(0.0, 1.0);
      }
    }

    final _CloneBrushMask mask = _CloneBrushMask(
      radius: radius,
      size: size,
      alphaGrid: alphaGrid,
    );
    if (_cloneBrushMaskCache.length >= 48) {
      _cloneBrushMaskCache.remove(_cloneBrushMaskCache.keys.first);
    }
    _cloneBrushMaskCache[key] = mask;
    return mask;
  }

  void _scheduleClonePreviewRefresh(String layerId) {
    _clonePreviewLayerId = layerId;
    if (_clonePreviewTimer != null) {
      _clonePreviewPending = true;
      return;
    }

    _clonePreviewTimer = Timer(const Duration(milliseconds: 42), () {
      _clonePreviewTimer = null;
      final String? pendingLayerId = _clonePreviewLayerId;
      if (pendingLayerId == null) return;
      _queueEditableImageRefresh(pendingLayerId);
      if (_clonePreviewPending) {
        _clonePreviewPending = false;
        _scheduleClonePreviewRefresh(pendingLayerId);
      }
    });
  }

  void _cancelClonePreviewTimer({required bool clearLayerId}) {
    _clonePreviewTimer?.cancel();
    _clonePreviewTimer = null;
    _clonePreviewPending = false;
    if (clearLayerId) {
      _clonePreviewLayerId = null;
    }
  }

  void _queueEditableImageRefresh(String layerId, {bool notifyParent = false}) {
    final _EditableImageBuffer? buffer = _editableImages[layerId];
    if (buffer == null) return;
    if (notifyParent) {
      buffer.notifyParentAfterBuild = true;
    }
    if (buffer.isBuildingPreviewImage) {
      buffer.previewNeedsAnotherBuild = true;
      return;
    }

    buffer.isBuildingPreviewImage = true;
    final Uint8List snapshot = Uint8List.fromList(buffer.previewPixels);
    unawaited(
      _imageFromPixels(
        pixels: snapshot,
        width: buffer.previewWidth,
        height: buffer.previewHeight,
      )
          .then((ui.Image renderedImage) {
            if (!mounted) return;
            final _EditableImageBuffer? latest = _editableImages[layerId];
            if (latest == null) return;
            final bool notifyLayerChange = latest.notifyParentAfterBuild;
            setState(() {
              latest.previewImage = renderedImage;
              if (!latest.usesPreview) {
                latest.fullImage = renderedImage;
              }
              latest.notifyParentAfterBuild = false;
            });
            if (notifyLayerChange && !latest.usesPreview) {
              widget.onLayerImageChanged(layerId, renderedImage);
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            final _EditableImageBuffer? latest = _editableImages[layerId];
            if (latest == null) return;
            latest.isBuildingPreviewImage = false;
            if (latest.previewNeedsAnotherBuild) {
              latest.previewNeedsAnotherBuild = false;
              _queueEditableImageRefresh(layerId);
            }
          }),
    );
  }

  Future<ui.Image> _imageFromPixels({
    required Uint8List pixels,
    required int width,
    required int height,
  }) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image image) => completer.complete(image),
    );
    return completer.future;
  }

  Offset _toUv(Offset scenePoint, Rect artboard) {
    final double u = (scenePoint.dx - artboard.left) / artboard.width;
    final double v = (scenePoint.dy - artboard.top) / artboard.height;
    return _clampUv(Offset(u, v));
  }

  Offset _clampUv(Offset uv) {
    return Offset(
      _clampDouble(uv.dx, 0, 1),
      _clampDouble(uv.dy, 0, 1),
    );
  }

  double _clampDouble(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  Offset _toScenePoint(Offset localPoint) {
    return Offset(
      (localPoint.dx - _pan.dx) / _scale,
      (localPoint.dy - _pan.dy) / _scale,
    );
  }

  Offset _clampPan(Offset rawPan, Size canvasSize) {
    final double maxPanX = canvasSize.width * 1.2;
    final double maxPanY = canvasSize.height * 1.2;
    return Offset(
      _clampDouble(rawPan.dx, -maxPanX, maxPanX),
      _clampDouble(rawPan.dy, -maxPanY, maxPanY),
    );
  }

  EditorLayer? _backgroundLayer(List<EditorLayer> layers) {
    for (final EditorLayer layer in layers) {
      if (layer.isBackground && _workspaceSourceSize(layer) != null) {
        return layer;
      }
    }
    return null;
  }

  EditorLayer? _layerById(String? layerId) {
    if (layerId == null) return null;
    for (final EditorLayer layer in widget.layers) {
      if (layer.id == layerId) return layer;
    }
    return null;
  }

  _TransformLayerSceneData? _buildSelectedTransformLayerData({
    required EditorLayer? selectedLayer,
    required Rect artboard,
    required Size workspaceSize,
  }) {
    if (selectedLayer == null) return null;
    switch (selectedLayer.type) {
      case EditorLayerType.text:
        return _buildTextLayerSceneData(
          layer: selectedLayer,
          artboard: artboard,
          workspaceSize: workspaceSize,
        );
      case EditorLayerType.image:
        if (selectedLayer.isBackground || selectedLayer.image == null) {
          return null;
        }
        final ui.Image image =
            _currentImageOverrides()[selectedLayer.id] ?? selectedLayer.image!;
        return _buildImageLayerSceneData(
          layer: selectedLayer,
          image: image,
          artboard: artboard,
          workspaceSize: workspaceSize,
        );
      case EditorLayerType.vector:
      case EditorLayerType.mask:
      case EditorLayerType.solid:
        return null;
    }
  }

  EditorLayer? _hitTopTransformLayer({
    required Offset scenePoint,
    required Rect artboard,
    required Size workspaceSize,
  }) {
    for (int i = widget.layers.length - 1; i >= 0; i--) {
      final EditorLayer layer = widget.layers[i];
      if (!layer.isVisible || layer.isBackground) continue;
      final _TransformLayerSceneData? data = _buildSelectedTransformLayerData(
        selectedLayer: layer,
        artboard: artboard,
        workspaceSize: workspaceSize,
      );
      if (data == null) continue;
      final double hitPadding = (10 / _scale).clamp(5, 14);
      if (_pointInRotatedLayerBounds(
        scenePoint,
        data,
        padding: hitPadding,
      )) {
        return layer;
      }
    }
    return null;
  }

  EditorLayer? _hitTopTextLayer({
    required Offset scenePoint,
    required Rect artboard,
    required Size workspaceSize,
  }) {
    for (int i = widget.layers.length - 1; i >= 0; i--) {
      final EditorLayer layer = widget.layers[i];
      if (!layer.isVisible || layer.isBackground) continue;
      if (layer.type != EditorLayerType.text) continue;
      final _TextLayerSceneData? data = _buildTextLayerSceneData(
        layer: layer,
        artboard: artboard,
        workspaceSize: workspaceSize,
      );
      if (data == null) continue;
      final double hitPadding = (10 / _scale).clamp(5, 14);
      if (_pointInRotatedLayerBounds(scenePoint, data, padding: hitPadding)) {
        return layer;
      }
    }
    return null;
  }
}

class _BrushStroke {
  _BrushStroke({
    required this.points,
    required this.color,
    required this.width,
    this.hardness = 75,
    this.brushType = PencilBrushType.round,
    this.angle = 0,
  });

  final List<Offset> points;
  final Color color;
  final double width;
  final double hardness;
  final PencilBrushType brushType;
  final double angle;
}

class _EditableImageBuffer {
  _EditableImageBuffer({
    required this.fullWidth,
    required this.fullHeight,
    required this.fullPixels,
    required this.fullImage,
    required this.previewWidth,
    required this.previewHeight,
    required this.previewPixels,
    required this.previewImage,
    required this.previewScale,
  });

  final int fullWidth;
  final int fullHeight;
  final Uint8List fullPixels;
  ui.Image fullImage;

  final int previewWidth;
  final int previewHeight;
  final Uint8List previewPixels;
  ui.Image previewImage;
  final double previewScale;

  bool isBuildingPreviewImage = false;
  bool previewNeedsAnotherBuild = false;
  bool notifyParentAfterBuild = false;
  bool isCommittingFull = false;
  final List<_CloneStrokeSession> pendingCommits = <_CloneStrokeSession>[];

  bool get usesPreview => previewScale < 0.999;
  ui.Image get displayImage => previewImage;
}

class _CloneStrokeSession {
  _CloneStrokeSession({
    required this.layerId,
    required this.sourceOffsetUv,
    required this.settings,
    required this.artboardWidth,
    required this.destPointsUv,
  });

  final String layerId;
  final Offset sourceOffsetUv;
  final CloneStampSettings settings;
  final double artboardWidth;
  final List<Offset> destPointsUv;

  _CloneStrokeSession freeze() {
    return _CloneStrokeSession(
      layerId: layerId,
      sourceOffsetUv: sourceOffsetUv,
      settings: settings,
      artboardWidth: artboardWidth,
      destPointsUv: List<Offset>.from(destPointsUv),
    );
  }
}

class _CloneBrushMask {
  const _CloneBrushMask({
    required this.radius,
    required this.size,
    required this.alphaGrid,
  });

  final int radius;
  final int size;
  final List<double> alphaGrid;
}

abstract class _TransformLayerSceneData {
  const _TransformLayerSceneData({
    required this.layerId,
    required this.center,
    required this.width,
    required this.height,
    required this.rotation,
  });

  final String layerId;
  final Offset center;
  final double width;
  final double height;
  final double rotation;

  double get halfWidth => width / 2;
  double get halfHeight => height / 2;

  Offset _toScene(Offset local) => center + _rotateVector(local, rotation);

  List<Offset> get cornerHandles => <Offset>[
        _toScene(Offset(-halfWidth, -halfHeight)),
        _toScene(Offset(halfWidth, -halfHeight)),
        _toScene(Offset(halfWidth, halfHeight)),
        _toScene(Offset(-halfWidth, halfHeight)),
      ];

  Offset get rotateLineStart => _toScene(Offset(0, halfHeight));

  Offset get rotateHandle => _toScene(Offset(0, halfHeight + 28));
}

class _TextLayerSceneData extends _TransformLayerSceneData {
  _TextLayerSceneData({
    required super.layerId,
    required super.center,
    required super.width,
    required super.height,
    required super.rotation,
    required this.textPainter,
  });

  final TextPainter textPainter;
}

class _ImageLayerSceneData extends _TransformLayerSceneData {
  const _ImageLayerSceneData({
    required super.layerId,
    required super.center,
    required super.width,
    required super.height,
    required super.rotation,
    required this.image,
  });

  final ui.Image image;
}

EditorLayer? _workspaceLayerForEdit(List<EditorLayer> layers) {
  for (final EditorLayer layer in layers) {
    if (layer.isBackground && _workspaceSourceSize(layer) != null) {
      return layer;
    }
  }
  return null;
}

_TextLayerSceneData? _buildTextLayerSceneData({
  required EditorLayer layer,
  required Rect artboard,
  required Size workspaceSize,
}) {
  if (layer.type != EditorLayerType.text) return null;
  final String text = layer.textValue ?? 'Write your text here';
  final bool isArabicText = _containsArabicCharacters(text);
  final double unitScale = artboard.width / workspaceSize.width;
  final Offset sourcePos = layer.position ??
      Offset(workspaceSize.width / 2, workspaceSize.height / 2);
  final Offset center = artboard.topLeft +
      Offset(sourcePos.dx * unitScale, sourcePos.dy * unitScale);
  final double fontSize =
      ((layer.textFontSize ?? 92) * unitScale * layer.layerScale).clamp(8, 500);

  final TextPainter painter = TextPainter(
    textDirection: isArabicText ? TextDirection.rtl : TextDirection.ltr,
    maxLines: 3,
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: layer.textColor ?? const Color(0xFF1F2937),
        fontSize: fontSize,
        fontWeight: _fontWeightFromNumeric(layer.textFontWeight ?? 400),
        height: 1.05,
        fontFamily: layer.textFontFamily,
      ),
    ),
  )..layout(maxWidth: artboard.width * 0.92);

  return _TextLayerSceneData(
    layerId: layer.id,
    center: center,
    width: painter.width,
    height: painter.height,
    rotation: layer.layerRotation,
    textPainter: painter,
  );
}

_ImageLayerSceneData? _buildImageLayerSceneData({
  required EditorLayer layer,
  required ui.Image image,
  required Rect artboard,
  required Size workspaceSize,
}) {
  if (layer.type != EditorLayerType.image) return null;
  final double unitScale = artboard.width / workspaceSize.width;
  final Offset sourcePos = layer.position ??
      Offset(workspaceSize.width / 2, workspaceSize.height / 2);
  final Offset center = artboard.topLeft +
      Offset(sourcePos.dx * unitScale, sourcePos.dy * unitScale);
  final double drawWidth = image.width * unitScale * layer.layerScale;
  final double drawHeight = image.height * unitScale * layer.layerScale;
  return _ImageLayerSceneData(
    layerId: layer.id,
    center: center,
    width: drawWidth,
    height: drawHeight,
    rotation: layer.layerRotation,
    image: image,
  );
}

Offset _rotateVector(Offset value, double angle) {
  final double c = math.cos(angle);
  final double s = math.sin(angle);
  return Offset(
    (value.dx * c) - (value.dy * s),
    (value.dx * s) + (value.dy * c),
  );
}

bool _pointInRotatedLayerBounds(
  Offset scenePoint,
  _TransformLayerSceneData data, {
  double padding = 0,
}) {
  final Offset local = _rotateVector(scenePoint - data.center, -data.rotation);
  return local.dx.abs() <= (data.halfWidth + padding) &&
      local.dy.abs() <= (data.halfHeight + padding);
}

bool _pointNearLayerTransformControls({
  required Offset scenePoint,
  required _TransformLayerSceneData data,
  required double rotateHandleRadius,
  required double cornerHandleRadius,
  required double rotateLineDistance,
}) {
  if ((scenePoint - data.rotateHandle).distance <= rotateHandleRadius) {
    return true;
  }
  for (final Offset handle in data.cornerHandles) {
    if ((scenePoint - handle).distance <= cornerHandleRadius) {
      return true;
    }
  }
  final double distanceToLine = _distancePointToSegment(
    point: scenePoint,
    segmentStart: data.rotateLineStart,
    segmentEnd: data.rotateHandle,
  );
  return distanceToLine <= rotateLineDistance;
}

double _distancePointToSegment({
  required Offset point,
  required Offset segmentStart,
  required Offset segmentEnd,
}) {
  final Offset segment = segmentEnd - segmentStart;
  final double lengthSquared =
      segment.dx * segment.dx + segment.dy * segment.dy;
  if (lengthSquared <= 0.000001) {
    return (point - segmentStart).distance;
  }
  final Offset fromStart = point - segmentStart;
  final double tRaw =
      ((fromStart.dx * segment.dx) + (fromStart.dy * segment.dy)) /
          lengthSquared;
  final double t = tRaw.clamp(0.0, 1.0).toDouble();
  final Offset projection = Offset(
    segmentStart.dx + (segment.dx * t),
    segmentStart.dy + (segment.dy * t),
  );
  return (point - projection).distance;
}

bool _containsArabicCharacters(String value) {
  return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
}

FontWeight _fontWeightFromNumeric(int weight) {
  switch (weight) {
    case <= 150:
      return FontWeight.w100;
    case <= 250:
      return FontWeight.w200;
    case <= 350:
      return FontWeight.w300;
    case <= 450:
      return FontWeight.w400;
    case <= 550:
      return FontWeight.w500;
    case <= 650:
      return FontWeight.w600;
    case <= 750:
      return FontWeight.w700;
    case <= 850:
      return FontWeight.w800;
    default:
      return FontWeight.w900;
  }
}

Size? _workspaceSourceSize(EditorLayer layer) {
  if (layer.type == EditorLayerType.image && layer.image != null) {
    return Size(layer.image!.width.toDouble(), layer.image!.height.toDouble());
  }
  if (layer.type == EditorLayerType.solid && layer.solidSize != null) {
    return layer.solidSize;
  }
  return null;
}

Rect _computeArtboardRect({
  required Size canvasSize,
  required Size workspaceSize,
}) {
  const double horizontalPadding = 10;
  const double topPadding = 12;
  const double bottomPadding = 12;

  final double maxWidth = canvasSize.width - (horizontalPadding * 2);
  final double maxHeight = canvasSize.height - topPadding - bottomPadding;

  final double sourceWidth = workspaceSize.width;
  final double sourceHeight = workspaceSize.height;
  final double scale = (maxWidth / sourceWidth < maxHeight / sourceHeight)
      ? (maxWidth / sourceWidth)
      : (maxHeight / sourceHeight);

  final double artboardWidth = sourceWidth * scale;
  final double artboardHeight = sourceHeight * scale;
  final double left = (canvasSize.width - artboardWidth) / 2;

  return Rect.fromLTWH(left, topPadding, artboardWidth, artboardHeight);
}

class _SkiaCanvasPainter extends CustomPainter {
  _SkiaCanvasPainter({
    required this.strokes,
    required this.layers,
    required this.pan,
    required this.scale,
    required this.selectedLayerId,
    required this.activeTool,
    required this.imageOverrides,
    required this.cloneSourcePointerUv,
    required this.marqueeSelection,
  });

  final List<_BrushStroke> strokes;
  final List<EditorLayer> layers;
  final Offset pan;
  final double scale;
  final String? selectedLayerId;
  final EditorTool activeTool;
  final Map<String, ui.Image> imageOverrides;
  final Offset? cloneSourcePointerUv;
  final MarqueeSelection? marqueeSelection;

  @override
  void paint(Canvas canvas, Size size) {
    final EditorLayer? workspace = _backgroundLayer(layers);
    if (workspace == null) {
      return;
    }
    final Size? workspaceSize = _workspaceSourceSize(workspace);
    if (workspaceSize == null) {
      return;
    }
    final Rect artboard = _computeArtboardRect(
      canvasSize: size,
      workspaceSize: workspaceSize,
    );

    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);
    canvas.clipRect(artboard);
    if (workspace.isVisible) {
      final ui.Image? workspaceImage = _resolveLayerImage(workspace);
      if (workspace.type == EditorLayerType.image && workspaceImage != null) {
        final Rect sourceRect = Rect.fromLTWH(
          0,
          0,
          workspaceImage.width.toDouble(),
          workspaceImage.height.toDouble(),
        );
        canvas.drawImageRect(workspaceImage, sourceRect, artboard, Paint());
      } else if (workspace.type == EditorLayerType.solid) {
        final Paint solidPaint = Paint()
          ..color = workspace.solidColor ?? Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawRect(artboard, solidPaint);
      }
    }
    final _TransformLayerSceneData? selectedTransformLayer =
        _drawNonBackgroundLayers(
      canvas: canvas,
      artboard: artboard,
      workspaceSize: workspaceSize,
    );
    _drawStrokes(canvas, artboard);
    if (marqueeSelection != null && activeTool == EditorTool.marquee) {
      _drawMarqueeSelection(canvas, artboard, marqueeSelection!);
    }
    if (selectedTransformLayer != null && activeTool == EditorTool.move) {
      _drawSelectionControls(canvas, selectedTransformLayer);
    }
    if (activeTool == EditorTool.clone && cloneSourcePointerUv != null) {
      _drawCloneSourcePointer(canvas, artboard, cloneSourcePointerUv!);
    }
    canvas.restore();
  }

  _TransformLayerSceneData? _drawNonBackgroundLayers({
    required Canvas canvas,
    required Rect artboard,
    required Size workspaceSize,
  }) {
    _TransformLayerSceneData? selectedData;
    for (final EditorLayer layer in layers) {
      if (!layer.isVisible || layer.isBackground) continue;
      switch (layer.type) {
        case EditorLayerType.image:
          final ui.Image? image = _resolveLayerImage(layer);
          if (image != null) {
            final _ImageLayerSceneData? data = _buildImageLayerSceneData(
              layer: layer,
              image: image,
              artboard: artboard,
              workspaceSize: workspaceSize,
            );
            if (data == null) break;
            final Rect sourceRect = Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            );
            final Rect destinationRect = Rect.fromCenter(
              center: Offset.zero,
              width: data.width,
              height: data.height,
            );
            canvas.save();
            canvas.translate(data.center.dx, data.center.dy);
            canvas.rotate(data.rotation);
            canvas.drawImageRect(image, sourceRect, destinationRect, Paint());
            canvas.restore();
            if (selectedLayerId == layer.id) {
              selectedData = data;
            }
          }
          break;
        case EditorLayerType.text:
          final _TextLayerSceneData? data = _buildTextLayerSceneData(
            layer: layer,
            artboard: artboard,
            workspaceSize: workspaceSize,
          );
          if (data == null) break;
          canvas.save();
          canvas.translate(data.center.dx, data.center.dy);
          canvas.rotate(data.rotation);
          data.textPainter.paint(
            canvas,
            Offset(-data.width / 2, -data.height / 2),
          );
          canvas.restore();
          if (selectedLayerId == layer.id) {
            selectedData = data;
          }
          break;
        case EditorLayerType.vector:
          break;
        case EditorLayerType.mask:
          break;
        case EditorLayerType.solid:
          final Paint solidPaint = Paint()
            ..color = layer.solidColor ?? Colors.white
            ..style = PaintingStyle.fill;
          canvas.drawRect(artboard, solidPaint);
          break;
      }
    }
    return selectedData;
  }

  void _drawSelectionControls(Canvas canvas, _TransformLayerSceneData data) {
    final Paint frame = Paint()
      ..color = const Color(0xFF5B7CFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final Path path = Path()
      ..moveTo(data.cornerHandles[0].dx, data.cornerHandles[0].dy)
      ..lineTo(data.cornerHandles[1].dx, data.cornerHandles[1].dy)
      ..lineTo(data.cornerHandles[2].dx, data.cornerHandles[2].dy)
      ..lineTo(data.cornerHandles[3].dx, data.cornerHandles[3].dy)
      ..close();
    canvas.drawPath(path, frame);

    final Paint handleFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final Paint handleStroke = Paint()
      ..color = const Color(0xFF5B7CFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (final Offset handle in data.cornerHandles) {
      canvas.drawCircle(handle, 6.0, handleFill);
      canvas.drawCircle(handle, 6.0, handleStroke);
    }

    final Paint linePaint = Paint()
      ..color = const Color(0xFF5B7CFF)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(data.rotateLineStart, data.rotateHandle, linePaint);
    canvas.drawCircle(data.rotateHandle, 9.0, handleFill);
    canvas.drawCircle(data.rotateHandle, 9.0, handleStroke);
    _drawRotateGlyph(canvas, data.rotateHandle);
  }

  void _drawRotateGlyph(Canvas canvas, Offset center) {
    final Paint arcPaint = Paint()
      ..color = const Color(0xFF5B7CFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;
    final Rect arcRect = Rect.fromCircle(center: center, radius: 4.2);
    canvas.drawArc(arcRect, -0.2 * math.pi, 1.5 * math.pi, false, arcPaint);
    final Offset tip = Offset(
      center.dx + (math.cos(1.25 * math.pi) * 4.2),
      center.dy + (math.sin(1.25 * math.pi) * 4.2),
    );
    final Path arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 2.2, tip.dy + 0.6)
      ..lineTo(tip.dx - 0.8, tip.dy - 1.5)
      ..close();
    final Paint fill = Paint()..color = const Color(0xFF5B7CFF);
    canvas.drawPath(arrow, fill);
  }

  void _drawStrokes(Canvas canvas, Rect artboard) {
    for (final _BrushStroke stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final Paint paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;

      switch (stroke.brushType) {
        case PencilBrushType.round:
          paint
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
          break;
        case PencilBrushType.soft:
          paint
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              (100 - stroke.hardness).clamp(0, 100) / 20,
            );
          break;
        case PencilBrushType.marker:
          paint
            ..strokeCap = StrokeCap.square
            ..strokeJoin = StrokeJoin.miter;
          break;
        case PencilBrushType.calligraphy:
          paint
            ..strokeCap = StrokeCap.square
            ..strokeJoin = StrokeJoin.round;
          break;
      }

      if (stroke.points.length == 1) {
        canvas.drawCircle(
          artboard.topLeft + stroke.points.first,
          stroke.width / 2,
          paint,
        );
        continue;
      }

      final Path path = Path();
      final Offset firstPoint = artboard.topLeft + stroke.points.first;
      path.moveTo(firstPoint.dx, firstPoint.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        final Offset prev = artboard.topLeft + stroke.points[i - 1];
        final Offset curr = artboard.topLeft + stroke.points[i];
        final Offset mid =
            Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
        path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
      }
      canvas.drawPath(path, paint);

      if (stroke.brushType == PencilBrushType.calligraphy) {
        final double rad = stroke.angle * (math.pi / 180);
        final Offset offset = Offset(
          math.cos(rad) * (stroke.width * 0.18),
          math.sin(rad) * (stroke.width * 0.18),
        );
        canvas.save();
        canvas.translate(offset.dx, offset.dy);
        final Paint secondPass = Paint()
          ..color = stroke.color.withOpacity(stroke.color.opacity * 0.65)
          ..strokeWidth = stroke.width * 0.72
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
        canvas.drawPath(path, secondPass);
        canvas.restore();
      }
    }
  }

  void _drawCloneSourcePointer(Canvas canvas, Rect artboard, Offset uv) {
    final Offset center = Offset(
      artboard.left + (uv.dx * artboard.width),
      artboard.top + (uv.dy * artboard.height),
    );
    final Paint outer = Paint()
      ..color = const Color(0xFFE8EEF9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;
    final Paint inner = Paint()
      ..color = const Color(0xFF4C5562)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;
    canvas.drawCircle(center, 9, outer);
    canvas.drawCircle(center, 8, inner);
    canvas.drawLine(
      Offset(center.dx - 12, center.dy),
      Offset(center.dx + 12, center.dy),
      inner,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 12),
      Offset(center.dx, center.dy + 12),
      inner,
    );
  }

  void _drawMarqueeSelection(
    Canvas canvas,
    Rect artboard,
    MarqueeSelection selection,
  ) {
    final Path path = _buildMarqueePath(artboard, selection);
    if (path.computeMetrics().isEmpty) return;

    final Paint darkStroke = Paint()
      ..color = const Color(0xFF1F2430)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..isAntiAlias = true;
    final Paint lightStroke = Paint()
      ..color = const Color(0xFFEFF3FA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..isAntiAlias = true;
    _drawDashedPath(
      canvas: canvas,
      source: path,
      paint: darkStroke,
      dashLength: 7,
      gapLength: 5,
      phase: 0,
    );
    _drawDashedPath(
      canvas: canvas,
      source: path,
      paint: lightStroke,
      dashLength: 7,
      gapLength: 5,
      phase: 7,
    );
  }

  Path _buildMarqueePath(Rect artboard, MarqueeSelection selection) {
    final Path path = Path();
    final Rect sceneBounds = Rect.fromLTRB(
      artboard.left + (selection.boundsUv.left * artboard.width),
      artboard.top + (selection.boundsUv.top * artboard.height),
      artboard.left + (selection.boundsUv.right * artboard.width),
      artboard.top + (selection.boundsUv.bottom * artboard.height),
    );
    switch (selection.mode) {
      case MarqueeSelectionMode.rectangular:
      case MarqueeSelectionMode.object:
        path.addRect(sceneBounds);
        return path;
      case MarqueeSelectionMode.elliptical:
        path.addOval(sceneBounds);
        return path;
      case MarqueeSelectionMode.freehand:
        if (selection.freePathUv.length < 2) return path;
        final Offset first = selection.freePathUv.first;
        path.moveTo(
          artboard.left + (first.dx * artboard.width),
          artboard.top + (first.dy * artboard.height),
        );
        for (int i = 1; i < selection.freePathUv.length; i++) {
          final Offset point = selection.freePathUv[i];
          path.lineTo(
            artboard.left + (point.dx * artboard.width),
            artboard.top + (point.dy * artboard.height),
          );
        }
        path.close();
        return path;
    }
  }

  void _drawDashedPath({
    required Canvas canvas,
    required Path source,
    required Paint paint,
    required double dashLength,
    required double gapLength,
    required double phase,
  }) {
    final double dashCycle = dashLength + gapLength;
    for (final ui.PathMetric metric in source.computeMetrics()) {
      final double total = metric.length;
      if (total <= 0) continue;
      double distance = -phase;
      while (distance < total) {
        final double from = distance < 0 ? 0 : distance;
        final double to = math.min(from + dashLength, total);
        if (to > from) {
          canvas.drawPath(metric.extractPath(from, to), paint);
        }
        distance += dashCycle;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SkiaCanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.layers != layers ||
        oldDelegate.pan != pan ||
        oldDelegate.scale != scale ||
        oldDelegate.selectedLayerId != selectedLayerId ||
        oldDelegate.activeTool != activeTool ||
        oldDelegate.imageOverrides != imageOverrides ||
        oldDelegate.cloneSourcePointerUv != cloneSourcePointerUv ||
        oldDelegate.marqueeSelection != marqueeSelection;
  }

  EditorLayer? _backgroundLayer(List<EditorLayer> layers) {
    for (final EditorLayer layer in layers) {
      if (layer.isBackground && _workspaceSourceSize(layer) != null) {
        return layer;
      }
    }
    return null;
  }

  ui.Image? _resolveLayerImage(EditorLayer layer) {
    if (layer.type != EditorLayerType.image) return null;
    return imageOverrides[layer.id] ?? layer.image;
  }
}

class _CloneStampToolIcon extends StatelessWidget {
  const _CloneStampToolIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Center(
        child: SizedBox(
          width: 15,
          height: 15,
          child: CustomPaint(
            painter: _CloneStampToolPainter(color),
          ),
        ),
      ),
    );
  }
}

class _CloneStampToolPainter extends CustomPainter {
  _CloneStampToolPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.22),
      size.width * 0.16,
      fill,
    );

    final neckPath = Path()
      ..moveTo(size.width * 0.40, size.height * 0.33)
      ..quadraticBezierTo(
        size.width * 0.42,
        size.height * 0.30,
        size.width * 0.45,
        size.height * 0.30,
      )
      ..lineTo(size.width * 0.55, size.height * 0.30)
      ..quadraticBezierTo(
        size.width * 0.58,
        size.height * 0.30,
        size.width * 0.60,
        size.height * 0.33,
      )
      ..lineTo(size.width * 0.60, size.height * 0.56)
      ..lineTo(size.width * 0.40, size.height * 0.56)
      ..close();
    canvas.drawPath(neckPath, fill);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.12,
          size.height * 0.56,
          size.width * 0.76,
          size.height * 0.23,
        ),
        Radius.circular(size.width * 0.08),
      ),
      fill,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.20,
          size.height * 0.82,
          size.width * 0.60,
          size.height * 0.10,
        ),
        Radius.circular(size.width * 0.06),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _CloneStampToolPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
