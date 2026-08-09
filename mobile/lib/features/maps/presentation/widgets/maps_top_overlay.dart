import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../saved_routes_screen.dart';

const _mapsTopOverlayDisplaySnapshot = _MapsTopOverlayDisplaySnapshot(
  searchPlaceholder: 'Search routes or parks',
  savedActionLabel: 'Saved',
);

/// The search field and Saved shortcut floating over the maps tab.
///
/// An overlay rather than an app bar so the map fills the screen behind it.
/// Its copy comes from [_MapsTopOverlayDisplaySnapshot] instead of inline
/// strings, which keeps the widget renderable in a test without a map.
class MapsTopOverlay extends StatelessWidget {
  const MapsTopOverlay({
    required this.isSearchActive,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchTap,
    super.key,
  });

  final bool isSearchActive;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MapsSearchField(
            isSearchActive: isSearchActive,
            controller: searchController,
            focusNode: searchFocusNode,
            onTap: onSearchTap,
          ),
        ),
        const SizedBox(width: 8),
        const _SavedRoutesButton(),
      ],
    );
  }
}

class _MapsSearchField extends StatelessWidget {
  const _MapsSearchField({
    required this.isSearchActive,
    required this.controller,
    required this.focusNode,
    required this.onTap,
  });

  final bool isSearchActive;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const snapshot = _mapsTopOverlayDisplaySnapshot;

    return Semantics(
      label: 'Maps search',
      textField: true,
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: RuniacColors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSearchActive
                  ? RuniacColors.primaryBlue
                  : const Color(0xFFE1E7F5),
              width: isSearchActive ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSearchActive
                    ? const Color(0x242F50C7)
                    : const Color(0x14172033),
                blurRadius: isSearchActive ? 16 : 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.search,
                color: RuniacColors.primaryBlue,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('maps_search_field'),
                  controller: controller,
                  focusNode: focusNode,
                  onTap: onTap,
                  maxLines: 1,
                  textInputAction: TextInputAction.search,
                  textAlignVertical: TextAlignVertical.center,
                  cursorColor: RuniacColors.accentOrange,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: snapshot.searchPlaceholder,
                    hintStyle: const TextStyle(
                      color: RuniacColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedRoutesButton extends StatelessWidget {
  const _SavedRoutesButton();

  @override
  Widget build(BuildContext context) {
    const snapshot = _mapsTopOverlayDisplaySnapshot;

    return Semantics(
      label: snapshot.savedActionLabel,
      button: true,
      child: RuniacTappableSurface(
        onTap: () => Navigator.of(context).push(_buildSavedRoutesRoute()),
        borderRadius: BorderRadius.circular(999),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: RuniacColors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x332F50C7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14172033),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bookmark_border,
              color: RuniacColors.primaryBlue,
              size: 19,
            ),
            const SizedBox(width: 6),
            Text(
              snapshot.savedActionLabel,
              style: const TextStyle(
                color: RuniacColors.primaryBlue,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

PageRouteBuilder<void> _buildSavedRoutesRoute() {
  return PageRouteBuilder<void>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) {
      return const SavedRoutesScreen();
    },
  );
}

class _MapsTopOverlayDisplaySnapshot {
  const _MapsTopOverlayDisplaySnapshot({
    required this.searchPlaceholder,
    required this.savedActionLabel,
  });

  final String searchPlaceholder;
  final String savedActionLabel;
}
