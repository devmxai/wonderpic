# WonderPic

WonderPic is a Flutter-based mobile photo editor prototype focused on a professional canvas workflow (PicsArt/Photoshop-style interaction model) with a clean UI and tool-driven editing.

This README is a full handoff document for engineers and AI models.
If a new model/session takes over, this file should be enough to continue development without losing context.

## 0. Latest Continuation Notes (March 1, 2026)

This section is the **latest handoff checkpoint** and has higher priority than older notes when conflicts appear.

### 0.1 Recent integrations
- Firebase bootstrap files were added:
  - `lib/firebase_options.dart`
  - `android/app/google-services.json`
  - `ios/Runner/GoogleService-Info.plist`
- Auth flow wiring was added in `lib/main.dart`:
  - Email/Password sign-up + login UI
  - Google sign-in button and handling
- iOS Google callback integration is present in:
  - `ios/Runner/AppDelegate.swift`
  - `ios/Runner/Info.plist` (`GIDClientID` + URL schemes)
- iOS keychain/session entitlement integration was added:
  - `ios/Runner/Runner.entitlements`
  - `ios/Runner.xcodeproj/project.pbxproj` with `CODE_SIGN_ENTITLEMENTS` for Debug/Release/Profile

### 0.2 Known active issue (high priority)
- Android Google sign-in works after SHA setup + refreshed `google-services.json`.
- iOS auth can still fail with:
  - `Google sign-in failed ... com.google.GIDSignIn ... keychain error`
  - similar keychain error for email/password session persistence.
- This points to iOS runtime signing/keychain environment consistency (not only UI logic).

### 0.3 Mandatory iOS auth resume checklist
1. Verify bundle ID consistency across:
   - Firebase iOS app
   - Runner target
   - `GoogleService-Info.plist`
2. Verify `Runner.entitlements` is included by `CODE_SIGN_ENTITLEMENTS` in all Runner configs.
3. In Xcode Runner target, ensure:
   - Signing: Automatic
   - Valid Team selected
   - Keychain Sharing capability enabled
4. Rebuild from clean state before retest:
   - `flutter clean`
   - `flutter pub get`
   - `cd ios && pod install`
   - remove app from simulator/device
5. Re-test Google + email/password auth on iOS.

### 0.4 Thread continuity rule
- Starting a new chat/thread does **not** change project files.
- Assistant memory from prior thread is not guaranteed.
- Continue from:
  - latest git commit
  - current working tree
  - this README section.

### 0.5 Latest Handoff (March 2, 2026) - Regenerate Tool

This subsection is the newest checkpoint for the next thread.

#### What was implemented in this session
- `Regenerate` now closes its bottom sheet immediately on submit, then runs generation outside the sheet (to avoid lifecycle/state crashes).
- Regenerate now uses the same KIE generation pipeline used by the `+` -> `Generate Image` flow (`createTask` -> `recordInfo` -> output download).
- During regenerate:
  - canvas keeps magic shimmer on selected layer
  - center progress is now a plain `%` text over canvas (no big boxed card UI)
- Image upload path was hardened:
  - retries with backoff
  - stream-upload fallback when large payloads fail base64 upload

#### Current unresolved issue (still active)
- Regenerate is still unstable in real runs:
  - slow requests (long wait)
  - then upload/network failure in some attempts
- Most recent reproducible error from device/simulator:
  - `ClientException with SocketException: Connection reset by peer ... kieai.redpandaai.co/api/file-base64-upload`

#### Critical note for next thread
- Do **not** re-architect UI first.
- First, stabilize the KIE upload + task path for regenerate with concrete request/response logging and endpoint verification against current KIE docs.
- Focus specifically on model behavior for:
  - `Nano Banana 2`
  - `Flux 2 Pro`
  - `Seedream 5 Lite` (highest priority)

#### Exact code areas touched for regenerate
- `lib/main.dart`:
  - `_openRegenerateBottomSheet`
  - `_runRegenerateRequest`
  - `_resolveRegenerateQuality`
  - `_buildAiCanvasGeneratingOverlay`
  - `_startAiCanvasGeneratingProgressEstimator`
  - `_uploadKieReferenceFile` (retry + stream/base64 fallback)
  - `_generateImageWithKie`

#### Next-thread first checklist (strict order)
1. Add temporary debug logging for regenerate only:
   - upload endpoint chosen (base64 vs stream)
   - upload response code/body snippet
   - createTask payload (sanitized) and response code/body snippet
   - recordInfo state transitions and failMsg
2. Re-test each model separately with:
   - one reference (selected layer only)
   - two references (selected layer + uploaded image)
3. Confirm final payload keys for image-to-image for each model according to latest KIE docs.
4. After API stability is confirmed, tune latency and keep current UI behavior.

### 0.6 Thread-Split Handoff (March 2, 2026 - Latest)

This subsection supersedes older regenerate notes when conflicts appear.

#### Current blocker (still unresolved)
- `Regenerate` is not production-stable yet:
  - often very slow
  - sometimes fails after long wait
  - inconsistent failures across models

#### Latest observed errors (must reproduce first)
- Network/upload failure:
  - `ClientException with SocketException: Connection reset by peer ... /api/file-base64-upload`
- Server/model processing failure:
  - `Internal image processing error. Please try again.`
- Prior UI/runtime assertion seen during regenerate flow:
  - `'package:flutter/src/widgets/framework.dart': Failed assertion: line 5917 ... '_dependents.isEmpty': is not true.`

#### Confirmed UX requirement (do not regress)
- On pressing `Regenerate`:
  - close bottom sheet immediately
  - show magic shimmer on canvas layer
  - show a small center `%` counter from `0` to `100` (no boxed loader card)

#### Likely root-cause zones
- KIE reference upload path (`base64` vs stream fallback) is still unstable for some payloads.
- Model-specific image-to-image payload mapping may still be incorrect/incomplete for:
  - `Nano Banana 2`
  - `Flux 2 Pro`
  - `C Dream 5 Lite`
- Some failures are likely transport-level (connection reset), not only UI logic.

#### Mandatory first steps in the next thread
1. Add scoped debug logs for regenerate only:
   - upload strategy used
   - upload status code + short response snippet
   - createTask payload shape (sanitized) + response snippet
   - polling transitions/fail reason
2. Test matrix per model:
   - base layer only
   - base layer + uploaded reference image
3. Validate exact KIE payload keys per model against current docs before more UI changes.
4. Keep current shimmer/percent UX while fixing backend reliability and latency.

#### Files to start from
- `lib/main.dart` (regenerate + KIE upload/generate/poll path)
- `README.md` (this handoff section)

### 0.7 Latest Handoff (March 2, 2026 - Model Stability Update)

This subsection is now the latest checkpoint and supersedes older regenerate blocker notes when conflicts appear.

#### Current status (verified)
- `Regenerate` is working for all three models:
  - `Nano Banana 2`
  - `Flux 2 Pro`
  - `Seedream 5 Lite`
- The tool works on any selected `image` layer:
  - `Background` image layer
  - `Overlay` image layer

#### Root cause found for Nano Banana 2
- The Nano 2 path was not enforcing strict second-reference transfer behavior in prompt instructions.
- With two references, Nano treated image 2 more like optional style guidance in practice, not mandatory source transfer.
- Nano path also benefited from stricter upload/input stability controls:
  - `google_search: false`
  - preserve reference format when possible
  - prefer stream upload for references

#### Fixes applied (Nano 2 only)
- Strengthened Nano two-reference prompt contract to force strict merge behavior:
  - image 1 = base scene
  - image 2 = required source reference
  - if text conflicts with image 2 appearance, image 2 wins
- For regenerate with Nano + second reference:
  - keep uploaded second reference bytes as-is (avoid extra recompress in that path)
- Kept existing regenerate UX unchanged:
  - close sheet immediately
  - magic shimmer on selected layer
  - center `%` progress text

#### Implementation pointers
- `lib/main.dart`
  - `_buildNanoBananaPrompt`
  - `_runRegenerateRequest`
  - `_buildKieImageInput` (`google_search: false` for Nano)
  - `_uploadKieReferenceFile` / `_generateImageWithKie` (stream-first toggle support)

#### Workflow rule for next threads (mandatory)
- After any behavior change to generation/regenerate/models:
  1. update `README.md` handoff section in the same work session
  2. push the updated code + README to GitHub
- Purpose: any new model/session can continue immediately from README without missing behavior changes.

### 0.8 Latest Handoff (March 2, 2026 - AI Generate Canvas Progress UX)

This subsection is the latest checkpoint for `+` -> `Generate Image` loading UX.

#### Issue that was fixed
- During `Generate Image`, the loading card was centered on the full screen, not on the canvas/artboard area.
- The loading card used a fixed square size (`148x148`) and did not reflect the selected generation size preset (`Square/Portrait/Story`).
- No rotating wait-status messages were shown during progress.

#### Root cause
- `_buildAiCanvasGeneratingOverlay` was attached at root-screen stack level and rendered with `Center(...)`, so alignment followed the screen center, not canvas center.
- `_AiMagicProgressIndicator` had hard-coded dimensions (`148x148`) instead of using the active artboard size.

#### Fixes applied
- Moved AI generating overlay rendering into `_buildEditorCanvasPanel` stack so placement is tied to the canvas viewport.
- Added dynamic artboard targeting for loading state:
  - if workspace exists: use workspace source size
  - if workspace does not exist yet: use the selected generate preset size
  - compute display rect via `_computeArtboardRect(...)`
- Upgraded `_AiMagicProgressIndicator` to accept:
  - `panelSize` (dynamic width/height)
  - `statusText` (dynamic status copy)
- Added staged status text updates by progress:
  - `Preparing your image...`
  - `Uploading references...`
  - `Generating image details...`
  - `Refining composition...`
  - `Almost done, your image is on the way...`
  - `Finalizing output...`
- Kept existing shimmer + `%` behavior, now centered on the canvas/artboard target.
- Embedded API key constants were cleared to satisfy GitHub push protection; runtime keys must now be supplied via `--dart-define` environment values.

#### State wiring updates
- Added `_aiCanvasGeneratingSizePreset` to preserve requested size while generation is running.
- Set/reset this state in:
  - `_runAiImageGenerateRequest`
  - `_runRegenerateRequest`

#### Primary code touchpoints
- `lib/main.dart`
  - `_buildEditorCanvasPanel`
  - `_buildAiCanvasGeneratingOverlay`
  - `_AiMagicProgressIndicator`
  - `_aiCanvasGeneratingArtboardRect`
  - `_aiCanvasGeneratingStatusText`
  - `_runAiImageGenerateRequest`
  - `_runRegenerateRequest`

### 0.9 Latest Handoff (March 2, 2026 - Generate Crash + API Key Guard)

This subsection supersedes the unstable part of 0.8 related to runtime crash.

#### Crash root cause
- The AI generate overlay was computing artboard bounds through `_currentCanvasViewportSize()` during widget build.
- That path used `BuildContext.size`, which can assert (`Element.size`) when read in build timing before stable layout.

#### Hotfix applied
- `_buildAiCanvasGeneratingOverlay` now computes canvas size via `LayoutBuilder` constraints (build-safe).
- `_aiCanvasGeneratingArtboardRect` now receives explicit `canvasSize` instead of reading viewport context size internally.
- `_currentCanvasViewportSize()` was hardened to use `RenderBox` + `hasSize` check (no `context.size` direct read).

#### API key behavior adjustment
- Added early guard in both:
  - `_runAiImageGenerateRequest`
  - `_runRegenerateRequest`
- If `KIE_API_KEY` is missing, flow exits before entering generating state and shows clear message:
  - `KIE API key missing. Add --dart-define=KIE_API_KEY=...`

#### Important runtime note
- `KIE` key is currently embedded directly in code for runtime generation.
- `--dart-define=KIE_API_KEY=...` still works as an override when needed.

### 0.10 Latest Handoff (March 2, 2026 - Deactivated Context Snackbar Fix)

#### Symptom
- Runtime red-screen assertion:
  - `Failed assertion: ... _dependents.isEmpty: is not true`
- Followed by repeated framework errors:
  - `Looking up a deactivated widget's ancestor is unsafe.`

#### Root cause
- Snackbar calls inside `WonderPicEditorScreen` used `ScaffoldMessenger.of(context)` from async action paths.
- In some transition states (sheet close / route lifecycle), that `context` can be deactivated and ancestor lookup asserts in debug mode.

#### Fix applied
- Replaced editor snackbar lookups to use a dedicated `ScaffoldMessenger` key (no inherited-context lookup in async paths).
- Updated all direct editor snackbar call sites:
  - `_showExportMessage`
  - `_createTextLayer` (no-workspace warning)
  - `_pickImageFromGallery` error branches

#### Result
- Snackbar lookup no longer depends on a potentially deactivated widget context.
- This removes the unsafe ancestor-lookup path that was triggering the assertion chain.

### 0.11 Latest Handoff (March 2, 2026 - Generate Workspace Contract)

#### True root-cause split
- The `API key` and `red-screen assertion` are two different issues:
  - API key: generation depends on valid KIE key configuration (embedded key or runtime override).
  - UI assertion/lifecycle instability: generate flow previously relied on context-sensitive lookups during transient UI states.

#### Generate mechanism hardening (professional flow)
- On `+` -> `Generate Image`, if no workspace exists yet:
  - create a solid background workspace immediately using the selected generate size preset.
  - this guarantees canvas/artboard dimensions are available before async generation starts.
- During generation:
  - keep same magic shimmer + center progress behavior over the canvas/artboard.
- On success:
  - if workspace was created by this generate action, replace that background with generated image (not overlay).
  - if workspace already existed before generate, insert generated result as overlay layer (existing behavior).

#### Why this matters
- Workspace size now always matches the selected generation size in blank-state flows.
- Generate loader targets a real workspace rect instead of relying on inferred fallback only.
- This removes a major source of runtime instability in blank-first generate scenarios.

### 0.12 Latest Handoff (March 2, 2026 - Unified Magic Shimmer + Jitter Smoothing)

#### Request addressed
- Use one consistent "magic shimmer" style across:
  - Generate progress card
  - Upscale/Remove Background layer magic effect
  - Expand preview shimmer

#### Changes applied
- Generate progress card shimmer tone now matches the same glass sweep style used in floating magic panels (neutral white sweep, same movement profile).
- Upscale/Remove Background layer shimmer motion was stabilized:
  - switched from rect-fraction interpolation to beam-travel motion (`beamWidth` + `beamTravel`) for smoother movement while layer geometry changes.
  - softened sparkle pulse intensity to reduce perceived flicker/jitter.
- Expand preview shimmer motion was stabilized with the same beam-travel approach and smoother twinkle frequency.

#### Practical result
- Visual style is now much closer and more consistent across tools.
- While dragging handles (up/right/left), shimmer movement is more stable and less jumpy.

## 1. Current Product State (Source of Truth)

Status captured from codebase on **February 18, 2026**.

Implemented and working:
- Custom editor UI (thin top toolbar + thin bottom navigation).
- Selection/Move tool in top toolbar now uses a directional move icon style (`open_with_rounded`) instead of pointer-style icon.
- Dynamic right settings sidebar (80% width overlay, does not relayout canvas).
- Settings sidebar + all editor bottom sheets now use the app light style (white surfaces, light cards, dark text).
- Workspace/artboard creation through:
  - `Add image` (gallery picker)
  - `Add solid layer` presets: Square, Story, Portrait
- Layer system foundation with layer list bottom sheet.
- Text tool with live editing, EN/AR fonts, weight controls, color palette, outline stroke, and drop shadow controls.
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
- Dedicated Remove Background tool (PhotoRoom) as a standalone top-toolbar tool (not inside Selection sidebar).
- Remove Background now uses an embedded PhotoRoom Sandbox key by default (free mode), with optional runtime override via `--dart-define=PHOTOROOM_API_KEY=...`.
- Remove Background endpoint is configured to `https://sdk.photoroom.com/v1/segment` (PhotoRoom Segment API).
- Remove Background now supports dual engines in one professional flow:
  - PhotoRoom (Cloud): highest quality cutout.
  - ML Kit On-device Logo mode: fixed no-slider background removal tuned for logos/icons/vector-style assets with solid white/black backgrounds.
- Crop tool (new top toolbar tool next to Clone) with floating controls.
- Crop overlay workflow with real-time preview:
  - dimmed outside area
  - rule-of-thirds grid
  - drag-to-move crop area
  - resize from corners and edges
- Crop ratio presets in floating panel: `Free Size`, `1:1`, `4:5`, `16:9 Portrait`.
- Crop transform controls in floating panel:
  - rotate canvas (90° steps left/right)
  - straighten angle slider (-30°..+30°)
- Crop apply pipeline:
  - optional rotate/straighten processing
  - final pixel crop commit to selected image layer
  - done/cancel behavior via floating panel actions
- AI Vector PNG generator (OpenAI + Gemini APIs) from short prompt:
  - Vectors bottom-nav action opens generator sheet
  - prompt + engine/model/type/style/quality/size/background options
  - Gemini cheapest mode added: `gemini-2.5-flash-image` (Nano Banana)
  - background color options are enabled only when workspace/background exists; otherwise generation is forced transparent
  - defaults to `GPT Image 1.5` with auto-fallback to `GPT Image 1` if account access is limited
  - prompt is tuned for clean flat icon output by default, with other styles available
  - in-sheet live generation preview with shimmer loading state
  - action flow: `Generate` -> `Regenerate` / `Use`
  - selected result is inserted directly into canvas as layer
- Clone performance pipeline for high-resolution images (preview + deferred full-res commit).
- Undo/redo history system with snapshot stacks and circular controls in the Layers bottom sheet.
- Pencil strokes are now persisted in history snapshots, so Pencil supports Undo/Redo like other edit operations.

Not implemented yet (planned/incomplete):
- Save/export pipeline.
- Vectors/Stickers browsing libraries (currently UI placeholders; AI generation path is implemented for Vectors).
- Full vector/mask editing pipeline.
- General transform controls for non-text foreground layers (future layer types).

---

## 2. Tech Stack

- Flutter (Material 3)
- Dart SDK constraint: `>=3.2.6 <4.0.0`
- Main dependencies:
  - `image_picker: ^1.0.8`
  - `image_gallery_saver_plus: ^3.0.5`
  - `image: ^4.2.0`
  - `http: ^1.2.0` (PhotoRoom API calls)

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
  - text data: `textValue`, `textColor`, `textFontSize`, `textFontFamily`, `textFontWeight`, `textStrokeColor`, `textStrokeWidth`, `textShadowColor`, `textShadowOffsetX`, `textShadowOffsetY`, `textShadowBlur`, `textShadowSpread`, `textShadowOpacity`
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
- crop tool (`crop_rounded`)
- remove background tool (`auto_awesome_rounded`)
- settings button (opens right sidebar)
- Left menu and right settings remain fixed; center tool rail is horizontally scrollable for future tool expansion.
- Vertical separators are rendered between fixed side actions and the scrollable center tool rail.

### 6.2 Bottom nav
Contains:
- Layers
- Add
- Text
- Vectors (AI PNG generation entry)
- Stickers (placeholder)
- Save (placeholder)

### 6.3 Right settings sidebar
- Implemented as `endDrawer`, width = `80%` of screen.
- Visual style is light: white base background, light card surfaces, dark typography/icons.
- Dynamic content based on active tool context:
  - `pencil` -> Pencil settings
  - `text` -> Text settings
  - `clone` -> Clone settings
  - `crop` -> Crop settings (opens crop floating controls)
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
- Crop uses normalized UV rect (`Rect` in `0..1`) per selected image layer.

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
- fixed top text block (not scrollable) containing a lightweight text input field
  - this field is for editing only (no heavy local effect preview rendering)
  - font family/weight selection is reflected in this field for quick font preview
  - text effects preview/rendering happens on canvas only for smoother sidebar performance
- only lower text controls are scrollable
- compact spacing/typography sizing (~25% smaller) to preserve workspace inside sidebar
- locale toggle: English / Arabic
- font list area showing 4 visible cards with scrolling
- weight selector (`B` cards) based on font-supported weights
- text color strip: rectangular swatches with horizontal scrolling
- stroke section: outline width slider + rectangular color strip with horizontal scrolling
- drop shadow section:
  - opacity slider
  - blur slider
  - vertical slider (up/down)
  - horizontal slider (left/right)
  - rectangular shadow color strip with horizontal scrolling
- stroke/shadow floating-edit mode:
  - header button opens a fixed floating panel above bottom nav
  - floating panel uses a glass-style surface (semi-transparent + blur) with light borders
  - sidebar closes while floating panel is active to maximize canvas visibility
  - `Cancel` reverts effect values to the state before opening the panel and closes it
  - `Done` keeps current effect values and closes the panel

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
- Each finished stroke is committed as one history step, so Undo/Redo works per stroke.

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
- After source tap, clone immediately exits source-arming mode locally in canvas (no delayed mode switch between taps).
- Canvas message snackbars for clone are currently suppressed by design (`_showToolMessage` is no-op).
- Clone tap behavior is immediate on mobile: first tap can set source (when armed) or place a single clone stamp without requiring drag.
- Clone sampling uses a per-stroke source snapshot (separate read buffer) to avoid smear/distortion from read-write overlap.
- Clone settings support floating panel mode (matching text effects pattern):
  - floating popup includes source button (icon + `Select Source`) and sliders (`Brush Size`, `Hardness`, `Opacity`)
  - `Done` keeps current values
  - `Cancel` restores values captured before opening floating mode
- While clone floating popup is open, a live white brush preview indicator is shown at canvas center:
  - diameter follows `Brush Size`
  - edge softness follows `Hardness`
  - indicator density/visibility follows `Opacity`

### 13.5 Performance pipeline (important)
To handle high-resolution images smoothly:
- Editable image buffers are prepared in RGBA.
- If image max side > 2048, a preview buffer is generated (downscaled nearest).
- Brush paint applies immediately to preview buffer.
- Preview redraw is throttled by frame callbacks (one visual update per frame).
- After stroke end, a queued full-resolution replay commits changes back to full image.
- Full-resolution replay runs in isolate and applies each stroke from a per-stroke source snapshot for stable results.

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
- Each snapshot stores: `layers`, `pencilStrokes`, `selectedLayerId`, `activeTool`, `nextLayerId`, clone-source armed state, text locale, marquee mode, and marquee selection.
- Two stacks are used: `undoStack` and `redoStack` (with size cap).

Recorded operations:
- Add/replace background image.
- Add solid background preset.
- Add/delete/toggle layer visibility.
- Text content/style updates.
- Text transform gestures (move/resize/rotate), grouped at gesture start/end.
- Pencil stroke commits (one undo step per completed stroke).
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
- `READ_MEDIA_IMAGES`
- `READ_EXTERNAL_STORAGE` (max SDK 32)
- `WRITE_EXTERNAL_STORAGE` (max SDK 29)

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
4. `Search` and `Home` actions are still UI placeholders.

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

1. Add explicit export progress details (estimated size/file size before save).
2. Undo/redo command history.
3. Modular refactor of `main.dart` with parity tests.
4. Add real non-background image layers and transform handles.
5. Add vector/mask pipelines and corresponding tool settings.

---

## 23. Export Pipeline (Implemented)

Export entry:
- Bottom nav `Save` opens a white render sheet.
- User chooses:
  - Format: `PNG` or `JPG`
  - Quality preset: `Low`, `Medium`, `High`, `Ultra`

Render strategy:
- Uses Skia (`ui.PictureRecorder` + `Canvas`) to render the full composition, not a screen screenshot.
- Renders background + visible layers (image/text/solid overlays) in layer order.
- Replays committed pencil strokes in export output.
- Applies transforms (`position`, `layerScale`, `layerRotation`) consistently with canvas rendering.

Quality behavior:
- `Low` caps longest edge to ~1280.
- `Medium` caps longest edge to ~2048.
- `High` caps longest edge to ~3072.
- `Ultra` keeps full workspace resolution.

Encoding and save:
- `PNG`: encoded directly from `ui.ImageByteFormat.png`.
- `JPG`: encoded from RGBA pixels via `package:image` with preset-based JPEG quality.
- Saves directly to system gallery via `image_gallery_saver_plus`.
- iOS save uses add-only mode (`isReturnImagePathOfIOS: false`) to avoid plugin hangs tied to reading `fullSizeImageURL`.
- Export save call is guarded with timeout fallback to prevent indefinite `Saving` state.

Export UI reliability:
- Export progress overlay is responsive-width and text-ellipsis safe.
- Fixed iOS overflow warning (`RenderFlex overflowed by 2.5px`) in the export status chip.

Packages added:
- `image_gallery_saver_plus`
- `image`

Android build baseline for export plugins:
- `compileSdkVersion 34`
- `minSdkVersion 21`

---

## 24. Overlay Shape Cut (Implemented)

Scope:
- Available only when selected layer is an `Image` overlay (non-background).
- Shown from Settings Sidebar while Move/selection context is active.

Flow:
1. Select overlay image layer.
2. Open `Settings` sidebar.
3. Use `Shape Cut` and open floating panel.
4. Pick shape + position/size.
5. Press `Cut` to apply non-destructive intent as destructive pixel mask on the selected overlay.

Shapes added:
- Circle Sharp
- Circle Rounded
- Rect Sharp
- Rect Rounded
- Triangle

Behavior:
- Default preview appears centered at 50% size.
- Shape preview is drawn live on top of selected overlay.
- `Cancel` restores floating baseline and closes panel.
- `Cut` applies mask (outside becomes transparent), closes popup, and records Undo snapshot.

Technical notes:
- Cut uses RGBA pixel processing on selected overlay layer only.
- Background and other layers are untouched.
- Preview path and pixel mask share the same shape geometry helper to keep visual/result parity.

---

## 25. Add Image Behavior (Fixed)

Previous issue:
- Adding a second image replaced the first image and incorrectly reset workspace/background.

Current behavior:
- First image added becomes the `Background / Work Area`.
- Any later image added becomes an `Image Overlay` layer (non-background).
- Background remains unchanged.

Overlay insertion behavior:
- New overlay is centered in workspace.
- If overlay is larger than workspace, initial scale is auto-fitted (`contain`) so it appears inside the canvas.
- New overlay is auto-selected after insertion.

---

## 26. Overlay Cut UX Upgrade + Sidebar Decoupling (Implemented)

Layer settings access:
- Settings sidebar no longer requires `Move` tool to be enabled just to access selected-layer context.
- When no active tool is enabled:
  - If an overlay image layer is selected, sidebar shows `Overlay Layer Settings`.
  - If another layer type is selected, sidebar shows layer-context guidance.

Overlay Shape Cut floating panel:
- Reworked to a thinner floating style to preserve workspace visibility.
- Shape options are now a horizontal scrolling strip of chips.
- Removed size/position sliders from floating panel.

Overlay Shape Cut on-canvas interaction:
- While floating panel is open, shape editing is done directly on canvas:
  - Drag inside shape: move shape.
  - Drag corner handles (4 corners): resize shape.
- Selection transform handles are hidden during active shape-cut editing to avoid gesture conflicts.
- `Cancel` closes popup and restores baseline; `Cut` applies mask and closes popup.

---

## 27. Overlay Cut Handle System Upgrade (Implemented)

The on-canvas Overlay Shape Cut transform now supports 8 handles:
- 4 corner handles
- 4 edge-middle handles (left/right/top/bottom)

Behavior:
- Corner drag: proportional resize (locked ratio behavior).
- Edge-middle drag:
  - Left/Right handle changes width only.
  - Top/Bottom handle changes height only.
- Drag inside shape: move shape.

Implementation notes:
- Edge drag resizes from the dragged side while opposite side remains anchored.
- Shape bounds remain clamped inside overlay image bounds.
- Selection layer transform handles are still hidden while Overlay Cut editing is active to prevent gesture conflicts.
