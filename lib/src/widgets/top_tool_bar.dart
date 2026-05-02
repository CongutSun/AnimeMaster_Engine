import 'dart:ui';

import 'package:flutter/material.dart';
import '../screens/search_page.dart';
import '../screens/collection_page.dart';
import '../screens/settings_page.dart';
import '../screens/download_center_page.dart';

class TopToolBar extends StatefulWidget {
  const TopToolBar({super.key});

  @override
  State<TopToolBar> createState() => _TopToolBarState();
}

class _TopToolBarState extends State<TopToolBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool get _isSearching =>
      _searchFocusNode.hasFocus || _searchController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _doSearch() {
    if (_searchController.text.trim().isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              SearchPage(keyword: _searchController.text.trim()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final bool isSearching = _isSearching;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: isDark ? 0.72 : 0.86),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.outlineVariant),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(child: _buildSearchField(context, isSearching)),
                  _AnimatedToolbarActionRail(
                    visible: !isSearching,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SizedBox(width: 8),
                        _ToolbarIconButton(
                          tooltip: '收藏',
                          icon: Icons.video_library_rounded,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CollectionPage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _ToolbarIconButton(
                          tooltip: '缓存中心',
                          icon: Icons.download_for_offline_rounded,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DownloadCenterPage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _ToolbarIconButton(
                          tooltip: '设置',
                          icon: Icons.settings_rounded,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SettingsPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _AnimatedToolbarActionRail(
                    visible: isSearching,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _collapseSearch,
                          style: TextButton.styleFrom(
                            splashFactory: NoSplash.splashFactory,
                            overlayColor: Colors.transparent,
                          ),
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, bool isSearching) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isSearching ? 18 : 16),
      ),
      child: TextField(
        focusNode: _searchFocusNode,
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜番剧、书籍',
          prefixIcon: Icon(
            Icons.search_rounded,
            color: colors.onSurfaceVariant,
            size: 20,
          ),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          fillColor: colors.surfaceContainerHighest.withValues(
            alpha: isDark ? 0.62 : 0.72,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(isSearching ? 18 : 16),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _doSearch(),
      ),
    );
  }

  void _collapseSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {});
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _ToolbarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      width: 40,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          splashFactory: NoSplash.splashFactory,
          overlayColor: Colors.transparent,
          backgroundColor: colors.surfaceContainerHighest.withValues(
            alpha: 0.82,
          ),
          foregroundColor: colors.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _AnimatedToolbarActionRail extends StatelessWidget {
  final bool visible;
  final Widget child;

  const _AnimatedToolbarActionRail({
    required this.visible,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerRight,
        widthFactor: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 210),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: visible ? 1 : 0.96,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
