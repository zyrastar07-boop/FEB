# Migration Guide — Design System Implementation

This document tracks the rollout of the new design system across the FEB app.
Session 1 (this session) shipped the design tokens and primitives. Sessions 2+
apply them to specific screens.

## What Was Shipped (Session 1)

### Tokens — `lib/design/`

| File | Purpose |
| --- | --- |
| `tokens.dart` | Colors, typography scale, spacing, radii, elevation, shadows, breakpoints |
| `motion.dart` | Durations, curves, spring presets, reduced-motion gate |

All tokens are accessed as `AppDesignTokens.X` and `AppMotion.X` (static const).
Do not introduce new inline literals in screens.

### Primitives — `lib/widgets/`

| Widget | Replaces | Use case |
| --- | --- | --- |
| `AppCard` | Ad-hoc `Container + BorderRadius + InkWell` | Cards, panels, list items |
| `AppButton` | `ElevatedButton`, `TextButton`, `Pressable` action buttons | CTAs, form actions |
| `AppChip` | `InputChip`, `Chip`, `ChoiceChip`, inline filter pills | Categories, filters, badges |
| `PosterCard` | `MovieCard`, `GlassmorphicMiniPoster`, inline poster builders | Movie/show cards on rails and grids |
| `SectionHeader` | Repeated `_buildSectionHeader` patterns | "Continue Watching", "Trending" headers |
| `ResponsiveLayout` | Direct `MediaQuery.sizeOf` width checks | Page-level content-width clamp |
| `ResponsiveGrid` | `AdaptiveGrid` | Adaptive grids with token-driven column counts |
| `ResponsiveRow` | `ListView.builder` scrollDirection: horizontal | Horizontal rails |

### Mobile-only Focus Strip

- `FocusableScale` is annotated `@Deprecated('mobile-only-strip')`.
- Existing call sites still compile (deprecation is a warning, not an error).
- New code MUST use `AppCard`, `AppButton`, or `AppChip` instead.
- Keyboard/D-pad activation is sacrificed per the agreed decision.
- Screen-reader announcements (TalkBack/VoiceOver) are preserved via `Semantics`.

## Migration Order

Sessions 2–5 will migrate surfaces in this priority order:

### Session 2 — Home Screen (`lib/screens/home_screen.dart`)

**Targets:**
1. Replace `MovieCard` with `PosterCard` in `HomeMediaRail` builders.
2. Replace inline `_buildSectionHeader` (line ~1132) with `SectionHeader`.
3. Replace `_buildSpecialsStrip` chip list (line ~1486) with `AppChip`.
4. Replace `_heroButton` (line ~1428) with `AppButton` (primary variant).
5. Wrap hero header content with `ResponsiveLayout` for tablet/desktop.
6. Replace inline `_prefAction` (line ~315) with `AppCard` + `AppButton`.

**Files touched:**
- `lib/screens/home_screen.dart`
- `lib/widgets/home_media_rail.dart` (uses PosterCard directly)
- `lib/widgets/top_ten_trending_section.dart`

**Verification:**
- `dart analyze lib/screens/home_screen.dart lib/widgets/home_media_rail.dart`
- Run on phone + tablet, verify hero, rails, specials strip render correctly.
- Verify focus/keyboard behavior is consistent (no FocusableScale in migrated parts).

### Session 3 — Search Screen (`lib/screens/search_screen.dart`)

**Targets:**
1. Replace inline `_buildPosterCard` (line ~1670) with `PosterCard`.
2. Replace inline category chips (line ~1466) with `AppChip` (secondary variant).
3. Replace suggestion chips (line ~1533) with `AppChip` (ghost variant).
4. Replace history chips (line ~1403) with `AppChip` (secondary + onDeleted).
5. Replace `InputChip` history chips with `AppChip`.
6. Replace `AdaptiveGrid` with `ResponsiveGrid`.

**Files touched:**
- `lib/screens/search_screen.dart`

**Verification:**
- `dart analyze lib/screens/search_screen.dart`
- Verify search → results grid → detail navigation works.
- Verify cache hit/miss paths still function.
- Test reduced-motion path (Settings → Accessibility → Reduce Motion).

### Session 4 — Detail Screen (`lib/screens/detail_screen.dart`)

**Targets:**
1. Wrap with `ResponsiveLayout` for tablet/desktop layout.
2. Replace inline action buttons (line ~989 `bottomActions`, `topActions`) with `AppButton`.
3. Replace `_buildActionsLoading` skeleton (line ~1700) with `AppCard` skeleton.
4. Replace `FocusableScale` usages on rating pills, episode buttons, season selector.
5. Apply `PosterCard` to similar/recommended sections (line ~similar_movies_section).

**Files touched:**
- `lib/screens/detail_screen.dart`
- `lib/widgets/similar_movies_section.dart`
- `lib/widgets/actors_horizontal_list.dart`

**Verification:**
- Detail screen renders on mobile/tablet/desktop.
- Cast list, similar movies, episodes all render with PosterCard.
- Reduced-motion gates are honored on detail enter animation.

### Session 5 — Cross-cutting cleanup

**Targets:**
1. Remove `FocusableScale` usages from `account_details_screen.dart`, `actor_detail_screen.dart`, `dev_picks_screen.dart`, `iptv_channel_list_screen.dart`, `iptv_player_screen.dart` (TV-only kept).
2. Remove `Pressable` from `downloads_tab_view.dart`, `actor_detail_screen.dart`.
3. Migrate all `LiquidGlassContainer` usages in `profile_screen.dart`, `manage_subscription_screen.dart`, `downloads_tab_view.dart`.
4. Convert all `Duration(milliseconds: N)` for animations and `Curves.easeOutCubic` to motion tokens.
5. Wrap each migrated file with `Center > ConstrainedBox(maxWidth: AppDesignTokens.contentWidth(context))` where appropriate.

**Files touched:**
- `lib/screens/account_details_screen.dart`
- `lib/screens/actor_detail_screen.dart`
- `lib/screens/dev_picks_screen.dart`
- `lib/screens/iptv_channel_list_screen.dart`
- `lib/screens/iptv_player_screen.dart` (kept all 10 `FocusableScale` — TV player)
- `lib/screens/custom_player_screen.dart`
- `lib/screens/profile_screen.dart`
- `lib/screens/manage_subscription_screen.dart`
- `lib/views/downloads_tab_view.dart`

**Verification:**
- `dart analyze lib/` returns 31 issues — all pre-existing (unused fields in player/services, deprecated screen_brightness APIs, deprecated `cacheExtent`, control-flow lints). **Zero new warnings.**
- Zero `LiquidGlassContainer` references in `lib/`.
- `FocusableScale` references: 10 (all in `iptv_player_screen.dart` for TV nav) + 5 in legacy widgets (`update_banner_widget.dart`, `stacked_list_card.dart`, `category_filter_bar.dart`, `category_stacked_card.dart`) + 1 definition in `focusable_scale.dart`.
- `Pressable` references: 2 (`home_screen.dart` hero header — redundant, kept for visual; `downloads_tab_view.dart:800` — review later).
- `MovieCard`, `GlassmorphicMiniPoster`, `Pressable` widgets still exist as public APIs for any code that hasn't migrated yet.

### Known Risks (updated)

1. **Detail screen split** — completed: Session 4 migrated the 2924-line detail_screen in-place rather than splitting. If future work needs to refactor, the file is now well-organized by builder name (`_buildActionButtons`, `_buildStudiosSection`, `_buildReviewsSection`, etc.) so partial extraction is straightforward.
2. **Hero tag collisions** — addressed. `PosterCard.heroTagPrefix` is set per surface (`'home-rail'`, `'search-trending'`, `'search-popular'`, `'search-results'`, `'detail-similar'`).
3. **Auto-scroll** — not addressed; pending future perf work.
4. **Player focus/keyboard** — addressed. `iptv_player_screen.dart` keeps `FocusableScale` for legitimate TV navigation. `custom_player_screen.dart` migrated all button shapes to `AppButton` and gesture containers to `AppCard`.

## How to Use the Primitives

### AppCard

```dart
AppCard(
  onTap: () => navigateToDetail(movie),
  elevation: AppCardElevation.medium,
  borderRadius: AppDesignTokens.radiusLg,
  semanticLabel: movie.title,
  child: Padding(
    padding: EdgeInsets.all(AppDesignTokens.space4),
    child: Text(movie.title),
  ),
)
```

### AppButton

```dart
AppButton(
  onPressed: () => play(movie),
  variant: AppButtonVariant.primary,
  size: AppButtonSize.medium,
  leadingIcon: Icon(Icons.play_arrow_rounded, size: 18),
  child: Text('Play'),
)
```

### AppChip

```dart
AppChip(
  label: 'Action',
  icon: Icon(Icons.flash_on_rounded, size: 14),
  variant: AppChipVariant.secondary,
  size: AppChipSize.medium,
  selected: isSelected,
  onTap: () => toggleFilter('Action'),
)
```

### PosterCard

```dart
PosterCard(
  movie: movie,
  size: PosterCardSize.medium,
  showQuickActions: true,
  showMetadata: true,
  heroTagPrefix: 'home-trending',
  onTap: () => openDetail(movie),
)
```

### SectionHeader

```dart
SectionHeader(
  title: 'Trending now',
  action: () => openViewMore('trending'),
  actionLabel: 'See all',
  actionIcon: Icons.arrow_forward_rounded,
  style: SectionHeaderStyle.compact,
)
```

### ResponsiveLayout / ResponsiveGrid / ResponsiveRow

```dart
ResponsiveLayout(
  child: Column(
    children: [
      SectionHeader(title: 'Trending now'),
      ResponsiveRow(
        itemCount: movies.length,
        itemBuilder: (context, i) => PosterCard(movie: movies[i]),
      ),
    ],
  ),
)

ResponsiveGrid(
  itemCount: results.length,
  mobileColumns: 2,
  tabletColumns: 4,
  desktopColumns: 6,
  itemBuilder: (context, i) => PosterCard(movie: results[i]),
)
```

## Token Reference

### Colors
- `gold` / `goldDim` / `goldSoft` — accent
- `bg` / `bgElevated` / `card` / `cardHover` / `surface` — surfaces
- `border` / `borderStrong` — dividers
- `textPrimary` / `textSecondary` / `textTertiary` / `textQuaternary` — text
- `error` / `success` / `warning` — feedback

### Type scale
- `displayLarge` / `displayMedium` / `displaySmall` — hero titles
- `headlineLarge` / `headlineMedium` / `headlineSmall` — section titles
- `titleLarge` / `titleMedium` / `titleSmall` — card titles, list items
- `bodyLarge` / `bodyMedium` / `bodySmall` — paragraphs, metadata
- `labelLarge` / `labelMedium` / `labelSmall` — chips, buttons, captions

### Spacing (4px base unit)
- `space1` (4) → `space16` (64), in 4px increments

### Radii
- `radiusXs` (4) → `radius3xl` (36), plus `radiusFull` (pill)

### Motion
- Durations: `instant`, `micro` (100ms), `fast` (150ms), `standard` (200ms), `medium` (300ms), `slow` (450ms)
- Curves: `easeOut` (Apple), `easeInOut`, `easeDrawer`, `ease`, `linear`
- Springs: `springDefault`, `springBouncy`, `springStiff`, `springGentle`
- Reduced-motion: `AppMotion.shouldReduceMotion(context)`, `durationOrInstant(...)`, `curveOrLinear(...)`, `springOrInstant(...)`

### Breakpoints
- `bpMobile` (600), `bpTablet` (900), `bpDesktop` (1200), `bpWide` (1600)
- Helpers: `contentWidth(context)`, `pagePadding(context)`, `gridColumns(context, ...)`

## Zero-Regression Checklist (per session)

Before merging a session's work, confirm:

1. **No `FocusableScale` imports remain** in migrated files.
2. **No inline color/type/spacing literals** — only `AppDesignTokens.X`.
3. **No inline durations/curves** — only `AppMotion.X` or token-driven constants.
4. **All `MediaQuery.sizeOf` reads** for width-based logic go through `ResponsiveLayout` or `AppDesignTokens.gridColumns`.
5. **`dart analyze lib/` is clean** (no new warnings).
6. **Screen-reader smoke test**: VoiceOver/TalkBack announces buttons and cards correctly.
7. **Reduced-motion test**: Settings → Reduce Motion → all animations collapse cleanly.
8. **Responsive test**: phone (375w), tablet (768w), desktop (1440w) all render.

## Known Risks

1. **Detail screen is 2924 lines.** Session 4 should split it into partial files first (`detail_header.dart`, `detail_actions.dart`, `detail_episodes.dart`, etc.) before migrating.
2. **Hero tag collisions** — `PosterCard` takes a `heroTagPrefix` param. When migrating MovieCard callers, pass the screen name as the prefix (`'home'`, `'search'`, `'library'`).
3. **The `_heroController` auto-scroll** in home_screen.dart — consider pausing permanently after first user scroll (per audit recommendation).
4. **`flutter_eval` / `flutter_inappwebview` / `youtube_player_flutter` player UIs** — these packages have their own focus/keyboard handling. Sessions 5+ may need to handle player-specific keyboard bindings separately.

## Notes for Future Sessions

- Do NOT add new inline `BorderRadius.circular(X)` literals. Always use `AppDesignTokens.radius*`.
- Do NOT add new `Color(0xFFXXXXXX)` literals outside of `tokens.dart`.
- Do NOT use `Curves.easeOutCubic` directly — use `AppMotion.easeOut` or `AppMotion.curveOrLinear(context, AppMotion.easeOut)`.
- For animation curves not in `motion.dart`, add them there, not inline.