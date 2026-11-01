import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mail_provider.dart';
import '../services/mail_service.dart';

/// Sign-in to the student mail (student.bmstu.ru). Offers the saved LKS login,
/// which is usually the same unified BMSTU account.
class MailLoginForm extends StatefulWidget {
  const MailLoginForm({super.key});

  @override
  State<MailLoginForm> createState() => _MailLoginFormState();
}

class _MailLoginFormState extends State<MailLoginForm> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prefilled) {
      _prefilled = true;
      final mail = context.read<MailProvider>();
      _usernameController.text = mail.savedLogin ?? mail.lksLogin ?? '';
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Введите логин и пароль от почты'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    await context.read<MailProvider>().login(username, password);
  }

  InputDecoration _decoration(ThemeData theme, {required String hint, required IconData icon, Widget? suffix}) {
    final isDark = theme.brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
      prefixIcon: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      suffixIcon: suffix,
      filled: true,
      fillColor: isDark ? theme.colorScheme.surfaceContainer : theme.colorScheme.surfaceContainerLow,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mail = context.watch<MailProvider>();
    final busy = mail.status == MailStatus.signingIn;
    final lksLogin = mail.lksLogin;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(Icons.mail_rounded, size: 36, color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Студенческая почта',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Ящик @${MailService.host}. Логин и пароль обычно те же, что у единой учётной записи МГТУ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.35, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (mail.loginError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, size: 20, color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          mail.loginError!,
                          style: TextStyle(fontSize: 13, color: theme.colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _usernameController,
                autocorrect: false,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                decoration: _decoration(
                  theme,
                  hint: 'логин или логин@${MailService.host}',
                  icon: Icons.alternate_email_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autocorrect: false,
                enabled: !busy,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
                decoration: _decoration(
                  theme,
                  hint: 'пароль от почты',
                  icon: Icons.lock_outline_rounded,
                  suffix: IconButton(
                    tooltip: _obscurePassword ? 'Показать пароль' : 'Скрыть пароль',
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: busy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.onPrimary),
                      )
                    : const Text('Войти в почту', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              if (lksLogin != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => context.read<MailProvider>().loginWithLks(),
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: Text(
                    'Войти с данными ЛКС ($lksLogin)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Данные отправляются только на ${MailService.host} и хранятся в защищённом хранилище устройства.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
