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

enum EditorTool { move, pencil, text, clone }

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
  bool _isSyncingTextInput = false;

  @override
  void initState() {
    super.initState();
    _textInputController.addListener(_onTextInputChanged);
  }

  @override
  void dispose() {
    _textInputController.removeListener(_onTextInputChanged);
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
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _toolButton(
                  icon: Icons.near_me_outlined,
                  filled: _activeTool == EditorTool.move,
                  onTap: () => _setActiveTool(EditorTool.move),
                ),
                _toolButton(
                  icon: Icons.edit_outlined,
                  filled: _activeTool == EditorTool.pencil,
                  onTap: () => _setActiveTool(EditorTool.pencil),
                ),
                _toolButton(
                  icon: Icons.text_fields,
                  filled: _activeTool == EditorTool.text,
                  onTap: _createTextLayerAndOpenEditor,
                ),
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
      isCloneSourceArmed: _isCloneSourceArmed,
      selectedLayerId: _selectedLayerId,
      onLayerSelected: _onLayerSelected,
      onLayerTransformChanged: _onLayerTransformChanged,
      onLayerImageChanged: _onLayerImageChanged,
      onCloneSourcePicked: _onCloneSourcePicked,
      onCanvasMessage: _showToolMessage,
      onTextLayerDoubleTap: _onTextLayerDoubleTap,
    );
  }

  void _setActiveTool(EditorTool tool) {
    if (_activeTool == tool) return;
    setState(() {
      _activeTool = tool;
      if (tool != EditorTool.clone) {
        _isCloneSourceArmed = false;
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
      backgroundColor: const Color(0xFF23242A),
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
                        color: Color(0xFFE9ECF3),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: Color(0xFFD2D8E4),
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
            color: Color(0xFFE3E8F2),
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
                      ? const Color(0xFFF5F7FB)
                      : const Color(0xFFB9C0CE),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              selected: selected,
              backgroundColor: const Color(0xFF2E3037),
              selectedColor: const Color(0xFF4A4F5D),
              side: const BorderSide(color: Color(0xFF555A67)),
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
            color: Color(0xFFE3E8F2),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF2E3037),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3F4451)),
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
    _updateTextLayer(
      selectedTextLayer.id,
      textValue: _textInputController.text,
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
  }) {
    final int index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index < 0) return;
    final List<EditorLayer> nextLayers = List<EditorLayer>.from(_layers);
    final EditorLayer current = nextLayers[index];
    nextLayers[index] = current.copyWith(
      textValue: textValue,
      textFontFamily: textFontFamily,
      textFontWeight: textFontWeight,
      textColor: textColor,
    );
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

    setState(() {
      _layers = <EditorLayer>[..._layers, textLayer];
      _selectedLayerId = id;
      _activeTool = EditorTool.text;
      _isCloneSourceArmed = false;
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
            color: const Color(0xFF2E3037),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3F4451)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Text',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE8EDF7),
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
                  color: const Color(0xFFF3F6FC),
                  fontSize: 16,
                  fontFamily: selectedFamily,
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: 'Write your text here',
                  hintStyle: const TextStyle(
                    color: Color(0xFF98A2B5),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1F2127),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF424754)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF424754)),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF3A3F4C)),
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
              color: const Color(0xFF2E3037),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3F4451)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'No text layer selected',
                    style: TextStyle(
                      color: Color(0xFFB8C0CF),
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
                  color: const Color(0xFF2E3037),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3F4451)),
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
                                  color: const Color(0xFF2A2D36),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFF6F8BFF)
                                        : const Color(0xFF3F4451),
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
                                          color: const Color(0xFFEFF3FB),
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
                                          color: const Color(0xFFB9C2D2),
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
                  color: const Color(0xFF2E3037),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3F4451)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Weight',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE8EDF7),
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
                                    ? const Color(0xFF4A4F5D)
                                    : const Color(0xFF252831),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF6F8BFF)
                                      : const Color(0xFF3F4451),
                                  width: isSelected ? 1.3 : 1,
                                ),
                              ),
                              child: Text(
                                'B',
                                style: TextStyle(
                                  color: const Color(0xFFE8EDF7),
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
                  color: const Color(0xFF2E3037),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3F4451)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Text Color',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE8EDF7),
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
            color: const Color(0xFF2E3037),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3F4451)),
          ),
          child: Text(
            enabled
                ? (_isCloneSourceArmed
                    ? 'Tap on the image to set clone source.'
                    : 'Clone works on selected Image Layer only.')
                : 'Select an Image Layer first. Clone tool is disabled for Text, Vector, Mask, and Solid layers.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFB8C0CF),
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
                  enabled ? const Color(0xFF434A58) : const Color(0xFF353841),
              foregroundColor: const Color(0xFFF0F3FA),
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
    nextLayers[index] = current.copyWith(
      image: image,
      solidSize: _imageSourceSize(image),
    );
    setState(() {
      _layers = nextLayers;
    });
  }

  void _onLayerSelected(String? layerId) {
    if (_selectedLayerId == layerId) return;
    setState(() {
      _selectedLayerId = layerId;
      final EditorLayer? selected = _selectedLayer();
      if (selected == null || selected.type != EditorLayerType.image) {
        _isCloneSourceArmed = false;
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
      return;
    }

    nextLayers.insert(0, background);
    _layers = nextLayers;
    _selectedLayerId = layerId;
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
      return;
    }

    nextLayers.insert(0, background);
    _layers = nextLayers;
    _selectedLayerId = layerId;
  }

  Future<void> _openAddBottomSheet() async {
    if (_isPickingImage) return;
    final _AddAction? action = await showModalBottomSheet<_AddAction>(
      context: context,
      backgroundColor: const Color(0xFF23242A),
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
                    color: const Color(0xFF5E606A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: const Color(0xFF2E3037),
                  leading: const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: Color(0xFFE4E8F0),
                    size: 20,
                  ),
                  title: const Text(
                    'Add image',
                    style: TextStyle(
                      color: Color(0xFFE9ECF3),
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
                  tileColor: const Color(0xFF2E3037),
                  leading: const Icon(
                    Icons.dashboard_customize_outlined,
                    color: Color(0xFFE4E8F0),
                    size: 20,
                  ),
                  title: const Text(
                    'Add solid layer',
                    style: TextStyle(
                      color: Color(0xFFE9ECF3),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Square, Story, Portrait',
                    style: TextStyle(
                      color: Color(0xFFAEB6C6),
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
      backgroundColor: const Color(0xFF23242A),
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
                    color: const Color(0xFF5E606A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Solid Layer Presets',
                    style: TextStyle(
                      color: Colors.white,
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
                      tileColor: const Color(0xFF2E3037),
                      leading: const Icon(
                        Icons.crop_square_rounded,
                        color: Color(0xFFE5EAF6),
                      ),
                      title: Text(
                        preset.title,
                        style: const TextStyle(
                          color: Color(0xFFE9ECF3),
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        preset.subtitle,
                        style: const TextStyle(
                          color: Color(0xFFADB5C5),
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
      backgroundColor: const Color(0xFF23242A),
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
                        color: const Color(0xFF5E606A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Layers',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
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
                          color: const Color(0xFF2E3037),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'No layers yet. Add an image to create the background workspace.',
                          style: TextStyle(
                            color: Color(0xFFC8CDD8),
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
                                setState(() {
                                  _toggleLayerVisibility(layer.id);
                                });
                                setSheetState(() {});
                              },
                              onDelete: () {
                                setState(() {
                                  _deleteLayer(layer.id);
                                });
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
    final EditorLayer layer = nextLayers[index];
    nextLayers[index] = layer.copyWith(isVisible: !layer.isVisible);
    _layers = nextLayers;
    if (!nextLayers[index].isVisible && _selectedLayerId == layerId) {
      _selectedLayerId = null;
    }
  }

  void _deleteLayer(String layerId) {
    _layers = _layers.where((layer) => layer.id != layerId).toList();
    if (_selectedLayerId == layerId) {
      _selectedLayerId = null;
    }
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
            color: selected ? const Color(0xFF4A4F5D) : const Color(0xFF2E3037),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  selected ? const Color(0xFF6F8BFF) : const Color(0xFF3F4451),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? const Color(0xFFF5F8FE) : const Color(0xFFC0C7D6),
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
          inactiveTrackColor: Color(0xFF4A4F5D),
          thumbColor: Color(0xFFF3F6FC),
          overlayColor: Color(0x33444A58),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2E3037),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3F4451)),
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
                      color: Color(0xFFE8EDF7),
                    ),
                  ),
                ),
                Text(
                  valueText,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFAEB7C8),
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
        color: const Color(0xFF2E3037),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3F4451)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE7ECF6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFB2BBCB),
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
        color: const Color(0xFF2E3037),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? const Color(0xFF6F8BFF) : const Color(0xFF3F424C),
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
                color: const Color(0xFF3A3D47),
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
                            color: Color(0xFFF2F4F8),
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
                            color: const Color(0xFF4A5070),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Work Area',
                            style: TextStyle(
                              color: Colors.white,
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
                      color: Color(0xFFA9B0BF),
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
                color: const Color(0xFFD7DCE8),
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
      color: const Color(0xFFCDD3DF),
      size: 20,
    );
  }
}

enum _CanvasInteraction {
  none,
  drawing,
  cloning,
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
    required this.isCloneSourceArmed,
    required this.selectedLayerId,
    required this.onLayerSelected,
    required this.onLayerTransformChanged,
    required this.onLayerImageChanged,
    required this.onCloneSourcePicked,
    required this.onCanvasMessage,
    required this.onTextLayerDoubleTap,
  });

  final List<EditorLayer> layers;
  final EditorTool activeTool;
  final PencilSettings pencilSettings;
  final CloneStampSettings cloneSettings;
  final bool isCloneSourceArmed;
  final String? selectedLayerId;
  final ValueChanged<String?> onLayerSelected;
  final LayerTransformChanged onLayerTransformChanged;
  final LayerImageChanged onLayerImageChanged;
  final VoidCallback onCloneSourcePicked;
  final ValueChanged<String> onCanvasMessage;
  final ValueChanged<String> onTextLayerDoubleTap;

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
    if (widget.activeTool == EditorTool.clone) {
      _primeSelectedCloneLayerBitmap();
    }
    _cleanupCloneCaches();
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

    if (widget.activeTool != EditorTool.move) {
      _activeStroke = null;
      return;
    }

    _activeStroke = null;
    final EditorLayer? selectedLayer = _layerById(widget.selectedLayerId);
    final _TextLayerSceneData? selectedData = selectedLayer == null
        ? null
        : _buildTextLayerSceneData(
            layer: selectedLayer,
            artboard: artboard,
            workspaceSize: workspaceSize,
          );

    if (selectedData != null) {
      final double rotateHandleRadius = (34 / _scale).clamp(20, 42);
      final double cornerHandleRadius = (26 / _scale).clamp(14, 32);
      final double moveHitPadding = (12 / _scale).clamp(6, 18);
      if ((scenePoint - selectedData.rotateHandle).distance <=
          rotateHandleRadius) {
        _interaction = _CanvasInteraction.rotatingLayer;
        _gestureLayerId = selectedData.layerId;
        _layerStartRotation = selectedLayer!.layerRotation;
        _rotateStartAngle = math.atan2(scenePoint.dy - selectedData.center.dy,
            scenePoint.dx - selectedData.center.dx);
        return;
      }

      for (final Offset handle in selectedData.cornerHandles) {
        if ((scenePoint - handle).distance <= cornerHandleRadius) {
          _interaction = _CanvasInteraction.resizingLayer;
          _gestureLayerId = selectedData.layerId;
          _layerStartScale = selectedLayer!.layerScale;
          _resizeStartDistance = (scenePoint - selectedData.center).distance;
          if (_resizeStartDistance < 1) _resizeStartDistance = 1;
          return;
        }
      }

      if (_pointInRotatedTextBounds(
        scenePoint,
        selectedData,
        padding: moveHitPadding,
      )) {
        _interaction = _CanvasInteraction.movingLayer;
        _gestureLayerId = selectedData.layerId;
        _layerStartPosition = selectedLayer!.position ??
            Offset(workspaceSize.width / 2, workspaceSize.height / 2);
        _layerStartScenePoint = scenePoint;
        return;
      }

      // Do not drop selection when tapping close to transform controls.
      final double controlsPadding = (12 / _scale).clamp(6, 16);
      if (_pointNearTextTransformControls(
        scenePoint: scenePoint,
        data: selectedData,
        rotateHandleRadius: rotateHandleRadius + controlsPadding,
        cornerHandleRadius: cornerHandleRadius + controlsPadding,
        rotateLineDistance: (6 + controlsPadding * 0.6).clamp(6, 16),
      )) {
        _interaction = _CanvasInteraction.none;
        return;
      }
    }

    final EditorLayer? hitLayer = _hitTopTextLayer(
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
      _layerStartScenePoint = scenePoint;
      return;
    }

    widget.onLayerSelected(null);
    _interaction = _CanvasInteraction.none;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size canvasSize) {
    if (details.pointerCount > 1) {
      _activeStroke = null;
      _cancelClonePreviewTimer(clearLayerId: false);
      _interaction = _CanvasInteraction.none;
      _gestureLayerId = null;
      _activeCloneStroke = null;
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

    final String? layerId = _gestureLayerId;
    if (layerId == null) return;
    final EditorLayer? targetLayer = _layerById(layerId);
    if (targetLayer == null) return;
    final _TextLayerSceneData? data = _buildTextLayerSceneData(
      layer: targetLayer,
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
    _activeStroke = null;
    _interaction = _CanvasInteraction.none;
    _gestureLayerId = null;
    _activeCloneStroke = null;
    _cloneOffsetUv = null;
    _lastCloneDestUv = null;
    _cloneChangedLayer = false;
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
      if (layer.isBackground &&
          layer.isVisible &&
          _workspaceSourceSize(layer) != null) {
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
      if (_pointInRotatedTextBounds(
        scenePoint,
        data,
        padding: hitPadding,
      )) {
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

class _TextLayerSceneData {
  _TextLayerSceneData({
    required this.layerId,
    required this.center,
    required this.width,
    required this.height,
    required this.rotation,
    required this.textPainter,
  });

  final String layerId;
  final Offset center;
  final double width;
  final double height;
  final double rotation;
  final TextPainter textPainter;

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

Offset _rotateVector(Offset value, double angle) {
  final double c = math.cos(angle);
  final double s = math.sin(angle);
  return Offset(
    (value.dx * c) - (value.dy * s),
    (value.dx * s) + (value.dy * c),
  );
}

bool _pointInRotatedTextBounds(
  Offset scenePoint,
  _TextLayerSceneData data, {
  double padding = 0,
}) {
  final Offset local = _rotateVector(scenePoint - data.center, -data.rotation);
  return local.dx.abs() <= (data.halfWidth + padding) &&
      local.dy.abs() <= (data.halfHeight + padding);
}

bool _pointNearTextTransformControls({
  required Offset scenePoint,
  required _TextLayerSceneData data,
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
  });

  final List<_BrushStroke> strokes;
  final List<EditorLayer> layers;
  final Offset pan;
  final double scale;
  final String? selectedLayerId;
  final EditorTool activeTool;
  final Map<String, ui.Image> imageOverrides;
  final Offset? cloneSourcePointerUv;

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
    final _TextLayerSceneData? selectedTextLayer = _drawNonBackgroundLayers(
      canvas: canvas,
      artboard: artboard,
      workspaceSize: workspaceSize,
    );
    _drawStrokes(canvas, artboard);
    if (selectedTextLayer != null && activeTool == EditorTool.move) {
      _drawSelectionControls(canvas, selectedTextLayer);
    }
    if (activeTool == EditorTool.clone && cloneSourcePointerUv != null) {
      _drawCloneSourcePointer(canvas, artboard, cloneSourcePointerUv!);
    }
    canvas.restore();
  }

  _TextLayerSceneData? _drawNonBackgroundLayers({
    required Canvas canvas,
    required Rect artboard,
    required Size workspaceSize,
  }) {
    _TextLayerSceneData? selectedData;
    for (final EditorLayer layer in layers) {
      if (!layer.isVisible || layer.isBackground) continue;
      switch (layer.type) {
        case EditorLayerType.image:
          final ui.Image? image = _resolveLayerImage(layer);
          if (image != null) {
            final Rect sourceRect = Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            );
            canvas.drawImageRect(image, sourceRect, artboard, Paint());
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

  void _drawSelectionControls(Canvas canvas, _TextLayerSceneData data) {
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

  @override
  bool shouldRepaint(covariant _SkiaCanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.layers != layers ||
        oldDelegate.pan != pan ||
        oldDelegate.scale != scale ||
        oldDelegate.selectedLayerId != selectedLayerId ||
        oldDelegate.activeTool != activeTool ||
        oldDelegate.imageOverrides != imageOverrides ||
        oldDelegate.cloneSourcePointerUv != cloneSourcePointerUv;
  }

  EditorLayer? _backgroundLayer(List<EditorLayer> layers) {
    for (final EditorLayer layer in layers) {
      if (layer.isBackground &&
          layer.isVisible &&
          _workspaceSourceSize(layer) != null) {
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
