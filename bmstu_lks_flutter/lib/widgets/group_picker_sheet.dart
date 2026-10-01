import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bmstu_groups_catalog.dart';
import '../providers/favorites_provider.dart';

class GroupPickerSheet extends StatefulWidget {
  final String? currentGroupTitle;
  final ValueChanged<BmstuGroup> onSelect;

  const GroupPickerSheet({
    super.key,
    this.currentGroupTitle,
    required this.onSelect,
  });

  static Future<BmstuGroup?> show(BuildContext context, {String? currentGroupTitle}) {
    return showModalBottomSheet<BmstuGroup>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GroupPickerSheet(
        currentGroupTitle: currentGroupTitle,
        onSelect: (group) => Navigator.of(ctx).pop(group),
      ),
    );
  }

  @override
  State<GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends State<GroupPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<BmstuGroup> _results = [];

  @override
  void initState() {
    super.initState();
    _results = BmstuGroupsCatalog.popularGroups;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    setState(() {
      _results = BmstuGroupsCatalog.search(query, limit: 100);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    FavoritesProvider? fav;
    try {
      fav = context.watch<FavoritesProvider>();
    } catch (_) {}

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Выбор группы',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${BmstuGroupsCatalog.allGroups.length} групп',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Поиск: ИУ7-43Б, СМ1-21, МТ...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 18, color: theme.colorScheme.onSurfaceVariant),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Favorite groups section
          if (fav != null && fav.favoriteGroups.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Избранные группы',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 38,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: fav.favoriteGroups.length,
                separatorBuilder: (_, index) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final fg = fav!.favoriteGroups[idx];
                  final isSel = widget.currentGroupTitle == fg.title;
                  return ActionChip(
                    avatar: const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                    label: Text(fg.title),
                    backgroundColor: isSel
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      color: isSel ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                    ),
                    onPressed: () => widget.onSelect(fg),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Results list
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      'Группа не найдена',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final group = _results[index];
                      final isSelected = widget.currentGroupTitle == group.title;
                      final isFav = fav?.isGroupFavorite(group.uuid) ?? false;

                      return ListTile(
                        onTap: () => widget.onSelect(group),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.groups_rounded,
                              size: 18,
                              color: isSelected
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        title: Text(
                          group.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20),
                              ),
                            IconButton(
                              icon: Icon(
                                isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                                color: isFav
                                    ? Colors.amber
                                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                                size: 22,
                              ),
                              tooltip: isFav ? 'Удалить из избранного' : 'Добавить в избранное',
                              onPressed: fav == null ? null : () => fav!.toggleGroupFavorite(group),
                            ),
                          ],
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
