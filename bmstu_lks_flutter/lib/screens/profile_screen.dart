import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/student_id_card.dart';
import '../widgets/profile_session_card.dart';
import '../models/user_profile.dart';
import 'settings_screen.dart';

/// The student and their session; everything configurable lives behind the gear.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();

    final user = auth.userProfile ??
        UserProfile(
          lastName: 'Студент',
          firstName: 'МГТУ',
          middleName: '',
          groupTitle: auth.currentGroupTitle,
          groupUuid: auth.currentGroupUuid,
          stageUuid: '',
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Настройки',
            onPressed: () => SettingsScreen.open(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          StudentIdCard(user: user, isGuest: auth.isGuest),
          const SizedBox(height: 16),
          const ProfileSessionCard(),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: Text(auth.isGuest ? 'Выйти из гостевого режима' : 'Выйти из аккаунта'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
              foregroundColor: theme.colorScheme.onErrorContainer,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
