import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import 'qr_pass_dialog.dart';

class StudentIdCard extends StatefulWidget {
  final UserProfile user;
  final bool isGuest;

  const StudentIdCard({
    super.key,
    required this.user,
    this.isGuest = false,
  });

  @override
  State<StudentIdCard> createState() => _StudentIdCardState();
}

class _StudentIdCardState extends State<StudentIdCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.user;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.tertiary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Row: University Logo & Student Card Number
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.school_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'МГТУ им. Н.Э. Баумана',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onPrimary,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Card Number Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        widget.isGuest
                            ? 'ГОСТЬ'
                            : (user.cardNumber != null ? '№ ${user.cardNumber}' : 'БИЛЕТ СТУДЕНТА'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Middle: Avatar + Name + Group + Course/Semester
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar / Initials
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.25),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          widget.isGuest ? 'Г' : user.initials,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isGuest ? 'Гостевой доступ' : user.fullName,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              // Group
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  user.groupTitle,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              // Course & Semester
                              if (!widget.isGuest)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${user.course} курс • ${user.semester} сем.',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Speciality & Study Type Chips
                if (!widget.isGuest && user.specialityTitle != null) ...[
                  Text(
                    user.specialityTitle!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                ],

                // Status Bar (Обучается + Основа обучения)
                Row(
                  children: [
                    // Status Badge (Pulsing green indicator)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            user.state,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Study Type
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        user.studyTypeTitle,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withValues(alpha: 0.8),
                      size: 22,
                    ),
                  ],
                ),

                // Expanded Section: Specialization, Agreements, QR Pass Button
                if (_isExpanded) ...[
                  const SizedBox(height: 14),
                  Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
                  const SizedBox(height: 12),

                  if (user.specializationTitle != null && user.specializationTitle!.isNotEmpty) ...[
                    _buildInfoRow('Специализация', user.specializationTitle!),
                    const SizedBox(height: 8),
                  ],

                  if (user.agreements.isNotEmpty) ...[
                    _buildInfoRow('Договор', '${user.agreements.first.number} от ${user.agreements.first.date}'),
                    const SizedBox(height: 8),
                  ],

                  _buildInfoRow('Общежитие', user.hasDormitory ? 'Предоставляется' : 'Не требуется'),
                  const SizedBox(height: 12),

                  if (user.qrUrl != null && user.qrUrl!.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: theme.colorScheme.primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => QrPassDialog.show(
                          context,
                          qrUrl: user.qrUrl!,
                          studentName: user.fullName,
                          groupTitle: user.groupTitle,
                        ),
                        icon: const Icon(Icons.qr_code_rounded, size: 18),
                        label: const Text(
                          'Открыть QR-пропуск на турникет',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
