# Design

## Source of truth
- Status: Active
- Last refreshed: 2026-05-23
- Primary product surfaces: Spotlight-style search window, settings overlay, menu bar extra, first-run permission guide, filter popover, results table, preview pane.
- Evidence reviewed: `README.md`; `Sources/Needle/SearchWindow.swift`; `Sources/Needle/SettingsView.swift`; `Sources/Needle/NeedleApp.swift`; `Sources/Needle/GlobalShortcutController.swift`; current user feedback screenshots and interaction notes from the Needle app.

## Brand
- Personality: Native, quiet, precise, fast, trustworthy, and restrained.
- Trust signals: System-native controls, clear permission language, visible indexing state, predictable keyboard behavior, conservative motion, and no artificial visual effects that make the app feel like a web overlay.
- Avoid: Purple/default SaaS aesthetics, heavy glass blur, high-bounce animations, decorative gradients, fake depth, excessive icons, hidden state changes, and controls that feel custom for no reason.

## Product goals
- Goals: Make local file search feel instant, readable, and macOS-native; expose indexing and permissions clearly; support keyboard-first workflows; keep settings approachable for non-technical users.
- Non-goals: Pixel-copy Spotlight, reproduce all Everything query grammar in v1, file-content search, cloud sync, network indexing, and Mac App Store-first constraints.
- Success signals: Typing remains responsive on 40k+ indexed items; settings opens without visual jank; users understand how to grant permissions; results are scannable; main search can be used without reading documentation.

## Personas and jobs
- Primary personas: macOS power users, developers, operators, and knowledge workers who search large local folders frequently.
- User jobs: Find files/folders by name, path, extension, wildcard, or regex; open files quickly; reveal results in Finder; configure indexed locations and exclusions; keep the app running quietly in the background.
- Key contexts of use: Short search bursts, keyboard-driven navigation, permission setup, periodic index rebuilds, and background menu bar operation.

## Information architecture
- Primary navigation: Single main search window with toolbar actions; menu bar extra for background status and reopening; in-window settings overlay for configuration.
- Core routes/screens: Search surface, filter popover, settings overlay, permission guide, menu bar menu.
- Content hierarchy: Search input first; status and utility actions second; results table dominant; preview pane supportive; settings grouped by permissions, behavior, index locations, index rules, and search behavior.

## Design principles
- Principle 1: Prefer macOS defaults unless a custom design materially improves clarity or speed.
- Principle 2: Motion should explain hierarchy, not decorate state changes.
- Principle 3: Settings should feel like a temporary inspector, not a second app.
- Principle 4: Search should feel immediate even when indexing or filtering is expensive.
- Tradeoffs: A visible settings overlay is acceptable because settings interrupts search; excessive background blur is not acceptable because it adds visual noise and perceived lag.

## Visual language
- Color: Use `windowBackgroundColor`, `controlBackgroundColor`, system accent, `.secondary`, `.tertiary`, and semantic green/orange/red. Avoid broad tinted surfaces. Use green only for completed/healthy states.
- Typography: Use system San Francisco and rounded system design only for prominent search text or short status pills. Keep settings labels on standard system text styles.
- Spacing/layout rhythm: Use 8 pt increments. Main search header can be generous; settings should use tighter 12-18 pt vertical rhythm. Avoid large empty bands inside overlays.
- Shape/radius/elevation: Main window follows system window shape. Floating settings panel uses continuous 24-28 pt radius and one soft shadow. Cards use 14-18 pt radius. Do not layer multiple heavy rounded containers.
- Motion: Use native-feeling `smooth` or critically damped spring curves. Settings opens from center with subtle opacity/scale only. Avoid vertical drop, bounce, heavy blur, or dimming the whole app. Respect reduced motion by falling back to opacity-only transitions.
- Imagery/iconography: Prefer SF Symbols that resemble Heroicons/Bootstrap outline simplicity. Icons must clarify action or state, not decorate section titles.

## Components
- Existing components to reuse: `SearchWindow`, `ResultsList`, `PreviewPane`, `FilterPopover`, `SettingsPanel`, `SettingsView`, `StatusBadge`, `HelpTip`, `PermissionGuideView`.
- New/changed components: `DesignToken` or small local style helpers may be introduced only if repeated values become inconsistent. Avoid a large custom design system.
- Variants and states: Buttons need normal, disabled, scanning, completed, and destructive states. Badges need success, warning, neutral, and error states. Search results need selected, hover, empty, and loading states.
- Token/component ownership: Keep visual constants near UI files until repeated across 3+ surfaces; then extract to a small Needle UI style helper.

## Accessibility
- Target standard: Practical WCAG AA for contrast/readability plus macOS keyboard and VoiceOver behavior.
- Keyboard/focus behavior: Search field receives focus on open; Esc closes overlays first; arrow keys navigate results; Return opens; Command-Return reveals in Finder; Space previews when supported.
- Contrast/readability: Do not place important text over transparent material where underlying content reduces contrast. Settings panel should use near-opaque system background.
- Screen-reader semantics: Buttons and status badges need concrete Chinese labels. Avoid icon-only actions without `.help` or accessible labels.
- Reduced motion and sensory considerations: Reduce settings transition to fade when `accessibilityReduceMotion` is enabled. Avoid continuous spinners except during active indexing.

## Responsive behavior
- Supported breakpoints/devices: macOS 14+ desktop windows; minimum width 860 and minimum height 560 remain valid for v1.
- Layout adaptations: Preview pane can shrink or hide in future narrow widths; settings panel should stay centered and bounded to the visible window with at least 48 pt horizontal margins when possible.
- Touch/hover differences: Primary target is pointer/keyboard. Hover-only instructions must also be available through button help or visible labels.

## Interaction states
- Loading: Main and settings surfaces both show indexing/loading state. Avoid blocking the full window unless there is no usable data.
- Empty: Empty index explains adding indexed folders and links to settings.
- Error: Permission and degraded indexing errors are visible in settings and menu bar.
- Success: Completed index rebuild may show a green `已完成索引` button state for 3 seconds, then return to neutral.
- Disabled: Disabled buttons must retain labels and explain why through nearby context or help.
- Offline/slow network, if applicable: Not applicable for local-first v1.

## Content voice
- Tone: Clear, calm, direct Chinese UI copy.
- Terminology: Use `索引`, `索引位置`, `排除项`, `完全磁盘访问`, `辅助功能`, `重建索引`, `搜索路径`.
- Microcopy rules: Explain why a permission is needed, not only what to click. Prefer one-line examples for search syntax: `.swift`, `*.rpm`, `re:^IMG_.*\.jpg$`.

## Implementation constraints
- Framework/styling system: SwiftUI first, AppKit only for window behavior, Quick Look, global shortcuts, or platform gaps.
- Design-token constraints: Use system colors/materials instead of hard-coded palettes. If custom opacity/radius/shadow values are needed, keep them documented and conservative.
- Performance constraints: Search and filtering must not run synchronously on the main thread for large indexes. UI helper bridges must not recursively scan the AppKit view tree on every SwiftUI update.
- Compatibility constraints: Minimum macOS 14. Developer ID distribution is expected later; v1 local builds use ad-hoc signing.
- Test/screenshot expectations: Run `swift build`, `swift test`, `swift run NeedleCoreCheck`, package/install, and manually verify search input, settings open/close, Dock/menu bar behavior, and light/dark mode after visual changes.

## Proposed page and motion adjustments
- Main search window: Keep the current large search-first hierarchy, but reduce visual weight in the header by aligning icon buttons to one compact trailing cluster and using system secondary color consistently.
- Results area: Keep table density macOS-like. Avoid custom row animations. Prefer stable selection and fast redraw over decorative transitions.
- Preview pane: Use system background and softer section separation. Do not let Quick Look previews cause input lag; consider delayed preview updates if selection changes rapidly.
- Settings overlay: Treat it as a centered inspector panel over the existing window. No full-screen blur, no dim layer, no sheet-style drop. Use near-opaque `windowBackgroundColor`, continuous radius, and one soft shadow.
- Settings layout: Keep current section grouping, but reduce nested card weight. Use cards only where grouping contains multiple controls; permissions and behavior can be flatter system preference rows.
- Settings bottom bar: Keep it attached inside the rounded panel. Avoid hard dividers; use a subtle top gradient or spacing. Preserve bottom corner clipping.
- Motion curve: Use center opacity/scale transition: insertion scale around `0.96-0.98`, removal around `0.985`, no y-offset. Prefer `.smooth(duration: 0.22-0.28, extraBounce: 0)` or a critically damped spring. Avoid heavy spring bounce.
- State transitions: Button success state for index rebuild uses semantic green for 3 seconds, then returns to accent. Search results should update without animated table reshuffles.
- Reduced motion: If `accessibilityReduceMotion` is true, settings transition should use opacity only and skip scale.

## Open Design inspired optimization plan
- Reference model: `nexu-io/open-design` treats design work as a local-first, artifact-first loop with reusable design systems, composable skills, pre-flight questions, critique, and checklist culture. Needle should adopt the process discipline, not the web visual style.
- Chosen design system direction: `Apple + Minimal + Linear-like productivity`. This means native macOS surfaces first, quiet hierarchy second, and product-tool clarity third. Do not use Open Design's more expressive editorial, brutalist, gradient, or glassmorphism directions for the app shell.
- Design modes to keep available:
  - `Native Focus`: default search surface, very close to Spotlight/Finder behavior.
  - `Inspector Settings`: centered settings panel, near-opaque system background, flatter preference rows.
  - `Operational Status`: menu bar and indexing states, compact and semantic.
- Five-dimensional critique checklist for each UI pass:
  - Native fidelity: Does this look like a real macOS app rather than a web modal?
  - Responsiveness: Does any visual effect make typing, scrolling, or opening settings feel slower?
  - Hierarchy: Can the user identify search, results, preview, and settings status within one glance?
  - Accessibility: Does it preserve contrast, keyboard behavior, VoiceOver labels, and reduced motion?
  - Restraint: Is every icon, radius, shadow, and animation doing useful work?
- Page optimization sequence:
  - Pass 1: Settings panel. Flatten permissions and behavior into preference rows; keep cards only for index locations, rules, and search behavior. Remove unnecessary nested rounded rectangles.
  - Pass 2: Main search header. Make search field visually dominant and move info/filter/settings into a compact trailing control cluster with consistent SF Symbol weight.
  - Pass 3: Results and preview. Keep the table native and stable; soften preview pane separators; delay Quick Look refresh during rapid keyboard navigation if lag persists.
  - Pass 4: Menu bar. Keep status language short; expose only open, settings, rebuild, shortcut toggle, and quit. Avoid duplicating main-window controls.
- Motion system:
  - `Search open`: regular window show, no custom animation beyond macOS window activation.
  - `Settings open`: center scale `0.97 -> 1.0` plus opacity `0 -> 1`, no y-offset, no background blur, duration `0.22-0.28s`.
  - `Settings close`: opacity fade plus scale `1.0 -> 0.985`, duration `0.16-0.20s`.
  - `Filter popover`: system popover only; do not custom animate.
  - `Index completion`: semantic button state, green check for 3 seconds, then neutral.
  - `Reduced motion`: opacity-only for all custom overlay transitions.
- Color system:
  - Window: `windowBackgroundColor`.
  - Panels/cards: `controlBackgroundColor` or near-opaque `windowBackgroundColor`; avoid broad material transparency.
  - Borders: `.separator` or `.quaternary`, only where structure needs it.
  - Accent: system accent for primary action and selection.
  - Semantic: green for success, orange for permission/degraded warning, red only for actual error.
- Component rules:
  - Prefer native `Button`, `Toggle`, `Picker`, `Table`, `MenuBarExtra`, `ProgressView`.
  - Custom components must be small wrappers around native controls.
  - Avoid creating a large theme layer until values repeat across at least three files.
- Acceptance criteria for the first visual optimization implementation:
  - Settings opens and closes without visible jank on a 40k-item index.
  - No full-window blur, no dim overlay, no persistent custom scrollbars in settings.
  - Settings bottom bar respects rounded corners and shows indexing progress/completion.
  - Header icon group feels aligned and secondary to the search field.
  - Light and dark mode both keep text contrast and panel separation.
  - `swift build`, `swift test`, `swift run NeedleCoreCheck`, packaging, signing, and manual UI smoke checks pass.

## Open questions
- [ ] Should settings be a floating overlay permanently, or become a separate system Preferences-style window later? Owner: product. Impact: window management and Dock behavior.
- [ ] Should preview pane update be debounced to further reduce perceived lag during rapid keyboard navigation? Owner: engineering. Impact: responsiveness versus preview immediacy.
- [ ] Should light and dark mode have separate panel shadow/radius tuning? Owner: design/engineering. Impact: visual polish.
- [ ] Should Needle eventually define a small local token file for radius/shadow/motion constants? Owner: engineering. Impact: consistency versus abstraction overhead.
