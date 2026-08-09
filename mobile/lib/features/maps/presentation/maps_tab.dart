import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import 'widgets/maps_background.dart';
import 'widgets/maps_top_overlay.dart';
import 'widgets/shared_routes_sheet.dart';

class MapsTab extends StatefulWidget {
  const MapsTab({super.key});

  @override
  State<MapsTab> createState() => _MapsTabState();
}

class _MapsTabState extends State<MapsTab> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  bool _isSearchActive = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_handleSearchFocusChanged);
  }

  void _handleSearchFocusChanged() {
    setState(() {
      _isSearchActive =
          _searchFocusNode.hasFocus || _searchController.text.isNotEmpty;
    });
  }

  void _activateSearchPreview() {
    setState(() {
      _isSearchActive = true;
    });
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: RuniacColors.background,
      child: Stack(
        children: [
          const Positioned.fill(child: MapsBackground()),
          const SharedRoutesSheet(),
          Positioned(
            left: 14,
            right: 14,
            top: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(top: 14),
              child: MapsTopOverlay(
                isSearchActive: _isSearchActive,
                searchController: _searchController,
                searchFocusNode: _searchFocusNode,
                onSearchTap: _activateSearchPreview,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
