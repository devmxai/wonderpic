# WonderPic

WonderPic is a Flutter-based mobile photo editor prototype focused on a professional canvas workflow (PicsArt/Photoshop-style interaction model) with a clean UI and tool-driven editing.

This README is a full handoff document for engineers and AI models.
If a new model/session takes over, this file should be enough to continue development without losing context.

## 1. Current Product State (Source of Truth)

Status captured from codebase on **February 18, 2026**.

Implemented and working:
- Custom editor UI (thin top toolbar + thin bottom navigation).
- Selection/Move tool in top toolbar now uses a directional move icon style (`open_with_rounded`) instead of pointer-style icon.
- Dynamic right settings sidebar (75% width overlay, does not relayout canvas).
- Settings sidebar + all editor bottom sheets now use the app light style (white surfaces, light cards, dark text).
- Workspace/artboard creation through:
  - `Add image` (gallery picker)
  - `Add solid layer` presets: Square, Story, Portrait
- Layer system foundation with layer list bottom sheet.
- Text tool with live editing, EN/AR fonts, weight controls, and color palette.
- Selection/transform for text layers and image overlay layers:
  - move
  - resize (corner handles)
  - rotate (bottom rotate handle)
- Marquee `New Layer` and `Paste` now create true cropped overlay image layers with independent transform state (position/scale/rotation), while the original background stays unchanged.
- Hiding the background no longer collapses the workspace; overlays remain visible on the artboard. Deleting background image converts work area to solid background to keep the project editable.
- Selection hit-testing tuned: taps inside text bounds prioritize `move`, while `resize/rotate` trigger only from their dedicated handles.
- Overlay resize-handle capture was strengthened: larger adaptive hit zones + nearest-control resolution near handles/rotate line for more reliable resize initiation.
- Rotation handle capture was reinforced with larger, scale-aware touch radius and control-line guard to prevent accidental deselect when pressing rotate.
- Resize-handle capture was also reinforced (larger scale-aware corner hit area + deselect guard near selected text bounds) to keep selection stable while interacting with corner handles.
- Tiny text-layer handling was added: when a text layer becomes very small, transform handle hit zones expand adaptively and near-control taps resolve to the nearest control (resize/rotate) to avoid dead-zone interactions.
- Pencil drawing tool (active only when pencil tool is selected).
- Marquee Selection tool for image layers with modes: Rectangle, Ellipse, Free, and Object (manual box).
- Selection actions in sidebar: Copy, Cut, Paste, Delete, New Layer, Crop.
- Clone Stamp tool for image layers with source picking and brush settings.
- Clone performance pipeline for high-resolution images (preview + deferred full-res commit).
- Undo/redo history system with snapshot stacks and circular controls in the Layers bottom sheet.

Not implemented yet (planned/incomplete):
- Save/export pipeline.
- Search/Home actions.
- Full vector/mask editing pipeline.
- General transform controls for non-text foreground layers (future layer types).

---

## 2. Tech Stack

- Flutter (Material 3)
- Dart SDK constraint: `>=3.2.6 <4.0.0`
- Main dependency: `image_picker: ^1.0.8`

Project path used during development:
- `/Users/mx/Documents/my app pro/wonderpic`

---

## 3. Project Structure

Key files:
- `lib/main.dart`
  - Contains the full editor implementation (UI + state + canvas + painter + clone engine).
- `pubspec.yaml`
  - Dependencies and font registrations.
- `ios/Runner/Info.plist`
  - iOS photo usage descriptions.
- `android/app/src/main/AndroidManifest.xml`
  - Android app manifest.

Important note:
- The core editor is currently monolithic in `lib/main.dart`.
- Refactor to feature modules is recommended later, but keep behavior parity.

---

## 4. Runtime Architecture

### 4.1 Top-level widget tree
- `WonderPicApp` -> `MaterialApp` -> `WonderPicEditorScreen`.
- `WonderPicEditorScreen` owns editor state and business logic.

### 4.2 Canvas/rendering pipeline
- Interactive canvas widget: `_SkiaEditorCanvas` (stateful).
- Rendering painter: `_SkiaCanvasPainter`.
- Gesture handling happens in `_SkiaEditorCanvasState` using `GestureDetector` scale callbacks.
- View transform:
  - `_pan`
  - `_scale` (clamped between `0.6` and `3.5`)

### 4.3 Data model
- `EditorLayerType`: `image`, `text`, `vector`, `mask`, `solid`.
- `EditorLayer` is the central entity:
  - identity: `id`, `name`, `type`
  - visibility/role: `isVisible`, `isBackground`
  - image data: `image`, `thumbnailBytes`
  - solid data: `solidColor`, `solidSize`
  - text data: `textValue`, `textColor`, `textFontSize`, `textFontFamily`, `textFontWeight`
  - transform: `position`, `layerScale`, `layerRotation`

---

## 5. Core Product Rules (Do Not Break)

These are intentional product decisions and must stay true unless explicitly changed:

1. No workspace/artboard is shown when the app first opens.
2. Workspace appears only after adding a background source (`Add image` or `Add solid layer`).
3. The first/active background is the work area (`isBackground == true`).
4. Background is fixed as workspace and is not transformed like movable overlays.
5. Drawing is NOT globally active; it works only when `Pencil` tool is active.
6. Clone tool is active only when a visible `Image` layer is selected.
7. Move tool is transform-only behavior for text layers; Marquee tool has its own sidebar settings/actions.
8. Sidebar overlays content (drawer), it must not push/rebuild layout of canvas.
9. Newly added layers are auto-selected.
10. Keep thin/minimal toolbar + navbar visual style.

---

## 6. UI Layout and Interaction

### 6.1 Top toolbar
Contains:
- menu button
- move/select tool
- pencil tool
- marquee selection tool (square selection icon)
- clone stamp tool (custom painted icon)
- settings button (opens right sidebar)
- Left menu and right settings remain fixed; center tool rail is horizontally scrollable for future tool expansion.
- Vertical separators are rendered between fixed side actions and the scrollable center tool rail.

### 6.2 Bottom nav
Contains:
- Layers
- Home (placeholder)
- Add
- Text
- Search (placeholder)
- Save (placeholder)

### 6.3 Right settings sidebar
- Implemented as `endDrawer`, width = `75%` of screen.
- Visual style is light: white base background, light card surfaces, dark typography/icons.
- Dynamic content based on active tool context:
  - `pencil` -> Pencil settings
  - `text` -> Text settings
  - `clone` -> Clone settings
  - `marquee` -> Selection mode + actions (`Copy/Cut/Paste/Delete/New Layer/Crop`)
  - `move` -> no direct selection-tool settings; resolves to selected layer context
- For `move` + selected text layer, text settings are shown.

---

## 7. Workspace/Artboard Mechanics

- Background source size (`image dimensions` or `solidSize`) is the canonical workspace size.
- Displayed artboard rectangle is computed by `_computeArtboardRect(...)`:
  - centered horizontally
  - top/bottom paddings
  - fitted preserving aspect ratio

Coordinate systems:
- Screen/local gesture coordinates -> scene coordinates via `_toScenePoint`.
- Clone uses normalized UV coordinates (`0..1`) on artboard.

---

## 8. Layer System (Current)

Layer list UI:
- Open via bottom `Layers` button.
- Bottom sheet lists all layers from top-most to bottom-most.
- Top-right actions: circular `Undo` and `Redo` buttons.
- Each row supports:
  - select layer
  - visibility toggle
  - delete layer
- Background row is tagged as `Work Area`.

Selection:
- `_selectedLayerId` tracks active layer.
- If selected layer is hidden/deleted, selection clears.

Current creation paths:
- Background image layer (upsert behavior).
- Background solid layer preset (upsert behavior).
- Text overlay layer.

Layer types defined but not fully used yet:
- `vector`, `mask` are present in model and painter switch but currently placeholders.

---

## 9. Add Flow

### 9.1 Add button behavior
Bottom sheet offers:
1. `Add image`
2. `Add solid layer`

All add/layer/preset bottom sheets are aligned to the light app style (white sheet background + light tiles).

### 9.2 Add image
- Uses `ImagePicker.pickImage` with `ImageSource.gallery`.
- Decodes bytes to `ui.Image`.
- Upserts `Background` image layer at index `0`.
- Auto-selects background layer.

### 9.3 Add solid layer
Presets:
- Square: `1080 x 1080`
- Story: `1080 x 1920`
- Portrait: `1080 x 1350`

Creates/updates a white `solid` background layer and auto-selects it.

---

## 10. Text Tool System

### 10.1 Creation
Text can be created from:
- bottom nav text button

On creation:
- layer name: `Text`, `Text 2`, ...
- default text: `Write your text here`
- centered on workspace
- auto-selected
- active tool becomes `text`
- settings sidebar opens and text input gets focus

### 10.2 Sidebar behavior
Text sidebar includes:
- editable text field (live updates to canvas)
- locale toggle: English / Arabic
- font list area showing 5 visible cards with scrolling
- weight selector (`B` cards) based on font-supported weights
- color palette for text color

### 10.3 Font system
- 20 English fonts + 20 Arabic fonts are registered in `pubspec.yaml`.
- Font families are stored in `_kEnglishFontOptions` and `_kArabicFontOptions`.
- Weight support is controlled by `_kFontWeightSupport` map.
- If a requested weight is unsupported, nearest supported weight is chosen.

### 10.4 Double tap behavior
- Double tap text on canvas opens text editor flow.
- Current implementation checks this in text-tool interaction path.

---

## 11. Selection/Transform System

Current transform controls are implemented for text layers and non-background image overlay layers:
- Move by dragging inside text bounds.
- Resize via 4 corner handles.
- Rotate via bottom rotation handle.

Recent stability improvements:
- Larger and scale-aware hit areas for move/handles.
- Additional guard to avoid accidental unselect near transform controls.
- Rotation handle interactions are preserved without deselecting the layer.

---

## 12. Pencil Tool

Settings:
- Brush size
- Hardness
- Opacity
- Brush angle
- Brush type (`round`, `soft`, `marker`, `calligraphy`)
- Brush color palette

Behavior:
- Draws only when active tool is `pencil`.
- Single-finger draws.
- Two-finger gesture pans/zooms canvas.

---

## 13. Clone Stamp Tool

### 13.1 Activation constraints
- Works only on selected, visible `Image` layer.
- Disabled for text/vector/mask/solid layers.

### 13.2 Workflow
1. Open clone settings.
2. Tap `Select Source` (arms source mode).
3. Tap image once to set source point.
4. Paint elsewhere to clone from source offset.

### 13.3 Brush settings
- Size
- Hardness
- Opacity

### 13.4 Behavior details
- Source pointer is maintained per image layer.
- Source selection is not reset when changing brush settings.
- Canvas message snackbars for clone are currently suppressed by design (`_showToolMessage` is no-op).

### 13.5 Performance pipeline (important)
To handle high-resolution images smoothly:
- Editable image buffers are prepared in RGBA.
- If image max side > 2048, a preview buffer is generated (downscaled nearest).
- Brush paint applies immediately to preview buffer.
- Preview redraw is throttled (~42ms timer).
- After stroke end, a queued full-resolution replay commits changes back to full image.

This design is key for reducing lag on large images.

---

## 14. Marquee Selection Tool

### 14.1 Activation constraints
- Works only on selected, visible `Image` layer.
- Disabled logically for text/vector/mask/solid layers.

### 14.2 Selection modes
- Rectangle
- Ellipse
- Free (lasso)
- Object (manual box flow for now)

### 14.3 Sidebar actions
- Copy
- Cut
- Paste
- Delete
- New Layer
- Crop

### 14.4 Behavior notes
- Selection shape is drawn on canvas using dashed marquee outline.
- Copy/Cut extract only selected pixels (with transparency preserved).
- Paste creates a new cropped overlay image layer from clipboard content.
- New Layer creates a new cropped overlay image layer from selected pixels.
- Crop replaces selected image layer with cropped selection result.
- New overlay layers are auto-selected and editor switches to Move tool for immediate transform.

---

### 14.5 Undo / Redo history

History model:
- Snapshot-based history stored in-memory.
- Each snapshot stores: `layers`, `selectedLayerId`, `activeTool`, `nextLayerId`, clone-source armed state, text locale, marquee mode, and marquee selection.
- Two stacks are used: `undoStack` and `redoStack` (with size cap).

Recorded operations:
- Add/replace background image.
- Add solid background preset.
- Add/delete/toggle layer visibility.
- Text content/style updates.
- Text transform gestures (move/resize/rotate), grouped at gesture start/end.
- Image updates from clone commits.
- Marquee destructive pixel edits (cut/delete/crop) and selection layer creation/paste.

Behavior:
- Any new edit clears `redoStack`.
- Buttons disable automatically when no step is available.
- Applying undo/redo restores full editor snapshot and re-syncs text input context.

---

## 15. Fonts and Assets

Registered font families:
- English: Barlow, Cabin, CrimsonText, DMSerifDisplay, FiraSans, Inter, Karla, Lato, Manrope, Merriweather, Montserrat, Mulish, Nunito, Oswald, PlayfairDisplay, Poppins, Quicksand, Raleway, SourceSans3, WorkSans
- Arabic: Cairo, Tajawal, Almarai, Changa, ElMessiri, ReemKufi, Amiri, NotoNaskhArabic, NotoKufiArabic, MarkaziText, Harmattan, Katibeh, Lateef, Mada, Mirza, Rakkas, Lemonada, BalooBhaijaan2, ArefRuqaa, ScheherazadeNew

Font files live under:
- `assets/fonts/english`
- `assets/fonts/arabic`

---

## 16. Platform Permissions

### iOS (`ios/Runner/Info.plist`)
Configured:
- `NSPhotoLibraryUsageDescription`
- `NSPhotoLibraryAddUsageDescription`

### Android
- Uses `image_picker` default integration.
- Manifest is currently default template.

---

## 17. Development Workflow

### 16.1 Setup
```bash
flutter pub get
```

### 16.2 Run
```bash
flutter run
```

### 16.3 During active run session
- Hot reload: press `r`
- Full restart: press `R`

### 16.4 Analysis
```bash
flutter analyze
```

---

## 18. Known Issues / Technical Debt

1. `test/widget_test.dart` is still default boilerplate and currently broken (`MyApp` reference).
2. Editor logic is concentrated in a single large file (`lib/main.dart`), needs modularization.
3. `vector` and `mask` are data-model placeholders only (no full editing pipeline yet).
4. `Save`, `Search`, `Home` actions are UI placeholders.
5. No export/render pipeline yet.

---

## 19. Refactor Plan (Safe Incremental)

Recommended order:
1. Split `main.dart` into modules:
   - `models/` (layer/tool/settings)
   - `editor/` (state + controller)
   - `canvas/` (gesture + painter)
   - `ui/` (toolbars/sheets/sidebar widgets)
2. Keep behavior parity while splitting (no product regression).
3. Add deterministic widget/integration tests for:
   - add image/solid flow
   - text creation/editing
   - transform interactions
   - clone source + paint behavior
4. Extend snapshot policy for future vector/mask operations before adding more destructive tools.

---

## 20. AI Handoff Checklist (For Next Model)

Before changing anything, confirm these invariants in code:
- `EditorLayer` remains single source of truth.
- Background layer semantics are preserved.
- Move tool stays transform-focused; Marquee tool handles pixel-region selection/edit actions.
- Sidebar remains overlay (`endDrawer`) and does not shift canvas layout.
- Tools remain opt-in (no always-on drawing/cloning).
- New layers auto-select after insertion.

When adding a new tool:
1. Extend `EditorTool` enum.
2. Add top toolbar button.
3. Add settings panel branch in sidebar resolver.
4. Add gesture/render branches in `_SkiaEditorCanvasState` and painter.
5. Keep layer-type gating explicit.

When adding new layer types:
1. Extend `EditorLayerType` behavior and thumbnail rendering.
2. Define creation flow + bottom sheet actions.
3. Implement hit testing + transform policy.
4. Integrate with layer list operations.

---

## 21. Practical Notes for Continuation

- If gallery load fails in simulator, verify photo library permission prompt and simulator media availability.
- The clone pipeline is sensitive to performance changes; benchmark before modifying preview/full commit logic.
- Transform UX is tuned with scale-aware hit radii. Avoid shrinking hit areas without UX testing.
- Text rendering uses `TextPainter` with font-family + weight fallback logic; keep this consistent with sidebar controls.

---

## 21. License and Asset Responsibility

This repository currently includes many bundled font files.
Before production release:
- verify each font license
- include required notices/attribution if needed
- ensure redistribution compliance

---

## 22. Immediate Next Product Milestones

1. Export/save edited result to device gallery.
2. Undo/redo command history.
3. Modular refactor of `main.dart` with parity tests.
4. Add real non-background image layers and transform handles.
5. Add vector/mask pipelines and corresponding tool settings.
