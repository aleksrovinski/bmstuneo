import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/teacher_search_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../screens/login_screen.dart';

/// Body of the teacher search: favourites and a hint while the query is empty,
/// then the found teachers.
class TeacherSearchResults extends StatelessWidget {
  final bool isLoading;
  final String query;
  final List<TeacherSearchItem> results;
  final ValueChanged<TeacherSearchItem> onSelect;

  const TeacherSearchResults({
    super.key,
    required this.isLoading,
    required this.query,
    required this.results,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    FavoritesProvider? fav;
    try {
      fav = context.watch<FavoritesProvider>();
    } catch (_) {}
    final favTeachers = fav?.favoriteTeachers ?? const [];

    if (query.trim().isEmpty) {
      final auth = context.read<AuthProvider>();
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          if (favTeachers.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Избранные преподаватели',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...favTeachers.map((ft) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isDark
                      ? theme.colorScheme.surfaceContainer
                      : theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: Colors.amber.withValues(alpha: 0.18),
                      child: const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                    ),
                    title: Text(
                      ft.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    subtitle: const Text('Преподаватель МГТУ', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => onSelect(ft),
                  ),
                ),
              );
            }),
            const Divider(height: 36),
          ],
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_search_rounded,
                    size: 64,
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Поиск по преподавателям',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    auth.isGuest
                        ? 'В гостевом режиме доступен поиск по преподавателям текущей группы. Для поиска по всем преподавателям МГТУ войдите в аккаунт ЛКС.'
                        : 'Введите фамилию преподавателя МГТУ им. Баумана для просмотра его полного расписания',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (auth.isGuest) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      },
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Войти в ЛКС'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 56,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Преподаватель не найден',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Попробуйте изменить запрос или ввести только фамилию',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: results.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = results[index];
        final isFav = fav?.isTeacherFavorite(item.uuid) ?? false;

        return Material(
          color: isDark
              ? theme.colorScheme.surfaceContainer
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onSelect(item),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 20,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Преподаватель МГТУ',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: isFav ? Colors.amber : theme.colorScheme.outline,
                    ),
                    tooltip: isFav ? 'Удалить из избранных' : 'Добавить в избранные',
                    onPressed: fav == null ? null : () => fav!.toggleTeacherFavorite(item),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
