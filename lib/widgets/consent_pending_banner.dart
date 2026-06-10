import 'package:flutter/material.dart';

import '../models/parental_consent.dart';
import '../screens/consent/parental_consent_flow.dart';
import '../services/consent_service.dart';
import '../theme.dart';

/// Amber banner shown when a student has no active consent or needs re-consent.
///
/// Usage: place at the top of any dashboard that shows student data.
/// Pass [onTapAction] to launch the consent flow or navigate to the
/// guardian consent page.
///
/// If [hasConsent] is true, renders nothing.
class ConsentPendingBanner extends StatelessWidget {
  /// Whether the student already has a valid, current-version consent.
  final bool hasConsent;

  /// True when there is an old consent record but the version has changed.
  final bool isReConsent;

  /// Tapped when the guardian or coordinator wants to start/renew consent.
  final VoidCallback? onTapAction;

  /// If true the banner is shown as an app-level banner (top of screen).
  /// If false, it renders as a list-item card inside a column.
  final bool asTopBanner;

  const ConsentPendingBanner({
    super.key,
    required this.hasConsent,
    this.isReConsent = false,
    this.onTapAction,
    this.asTopBanner = false,
  });

  @override
  Widget build(BuildContext context) {
    if (hasConsent) return const SizedBox.shrink();

    final color = isReConsent ? Colors.orange.shade700 : AppTheme.warning;
    final bgColor = isReConsent
        ? Colors.orange.shade50
        : AppTheme.warning.withValues(alpha: 0.1);

    final title = isReConsent
        ? 'Consent Renewal Required'
        : 'Parental Consent Pending';

    final body = isReConsent
        ? 'The privacy notice has been updated. Guardian must renew consent to continue data processing.'
        : 'This student does not yet have parental consent on file. The school requires consent before processing student data.';

    final actionLabel = isReConsent ? 'Renew Now' : 'Provide Consent';

    if (asTopBanner) {
      return MaterialBanner(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        backgroundColor: bgColor,
        leading: Icon(Icons.warning_amber_rounded, color: color),
        content: Text(
          title,
          style: TextStyle(
              fontWeight: FontWeight.bold, color: color, fontSize: 13),
        ),
        actions: [
          if (onTapAction != null)
            TextButton(
              onPressed: onTapAction,
              child: Text(actionLabel,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: Text('Dismiss',
                style: TextStyle(color: Colors.grey.shade600)),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        bgColor,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: color, fontSize: 13)),
            const SizedBox(height: 4),
            Text(body,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            if (onTapAction != null) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: onTapAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Tiny badge for use in student list tiles when consent is missing.
class ConsentMissingBadge extends StatelessWidget {
  final bool hasConsent;

  const ConsentMissingBadge({super.key, required this.hasConsent});

  @override
  Widget build(BuildContext context) {
    if (hasConsent) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:        AppTheme.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: AppTheme.warning.withValues(alpha: 0.5)),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warning_amber_rounded,
            size: 11, color: AppTheme.warning),
        SizedBox(width: 3),
        Text('No Consent',
            style: TextStyle(
                fontSize: 10,
                color:  AppTheme.warning,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Full-page guardian consent section widget, used inside guardian_dashboard.dart.
class GuardianConsentSection extends StatefulWidget {
  final String studentDocId;
  final String studentName;
  final String guardianName;
  final String guardianPhone;
  final String? guardianEmail;

  const GuardianConsentSection({
    super.key,
    required this.studentDocId,
    required this.studentName,
    required this.guardianName,
    required this.guardianPhone,
    this.guardianEmail,
  });

  @override
  State<GuardianConsentSection> createState() => _GuardianConsentSectionState();
}

class _GuardianConsentSectionState extends State<GuardianConsentSection> {
  final _svc = ConsentService();

  bool _loading = true;
  List<ParentalConsent> _consents = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await _svc.getConsents(widget.studentDocId);
      if (mounted) setState(() { _consents = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to load consents. Please try again later.'; _loading = false; });
    }
  }

  Future<void> _withdraw(ParentalConsent c) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _WithdrawDialog(consentId: c.id),
    );
    if (reason == null || !mounted) return;
    try {
      await _svc.withdrawConsent(
        studentDocId: widget.studentDocId,
        consentId:    c.id,
        reason:       reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Consent withdrawn. School admin has been notified.'),
            backgroundColor: AppTheme.warning),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to withdraw consent. Please try again later.'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Could not load consents: $_error',
            style: const TextStyle(color: Colors.red, fontSize: 12)),
      );
    }

    final active   = _consents.where((c) => c.isActive).toList();
    final stale    = _consents.where((c) => c.isStale).toList();
    final withdrawn = _consents.where((c) => c.withdrawnAt != null).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Section header
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          const Icon(Icons.privacy_tip_outlined,
              color: AppTheme.primary, size: 18),
          const SizedBox(width: 8),
          const Text('Privacy & Consent',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryDark)),
          const Spacer(),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
      ),
      const SizedBox(height: 10),

      // Version info
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Consent version: $kCurrentConsentVersion',
          style: TextStyle(
              fontSize: 11, color: Colors.grey.shade600),
        ),
      ),
      const SizedBox(height: 12),

      if (active.isEmpty && stale.isEmpty && withdrawn.isEmpty) ...[
        _EmptyConsentCard(
          studentDocId: widget.studentDocId,
          studentName: widget.studentName,
          guardianName: widget.guardianName,
          guardianPhone: widget.guardianPhone,
          guardianEmail: widget.guardianEmail,
          onConsentCompleted: _load,
        ),
      ] else ...[
        if (stale.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ConsentPendingBanner(
              hasConsent:  false,
              isReConsent: true,
              onTapAction: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ParentalConsentFlow(
                      studentDocId: widget.studentDocId,
                      studentName: widget.studentName,
                      prefillGuardianName: widget.guardianName,
                      prefillGuardianPhone: widget.guardianPhone,
                      prefillGuardianEmail: widget.guardianEmail,
                      isReConsent: true,
                    ),
                    fullscreenDialog: true,
                  ),
                ).then((res) {
                  if (res != null) {
                    _load();
                  }
                });
              },
            ),
          ),
        for (final c in active) _ConsentCard(consent: c, onWithdraw: () => _withdraw(c)),
        for (final c in stale)  _ConsentCard(consent: c, onWithdraw: () => _withdraw(c), isStale: true),
        if (withdrawn.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Withdrawn Consents',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final c in withdrawn)
            _ConsentCard(consent: c, isWithdrawn: true),
        ],
      ],
    ]);
  }
}

class _EmptyConsentCard extends StatelessWidget {
  final String studentDocId;
  final String studentName;
  final String guardianName;
  final String guardianPhone;
  final String? guardianEmail;
  final VoidCallback? onConsentCompleted;

  const _EmptyConsentCard({
    required this.studentDocId,
    required this.studentName,
    required this.guardianName,
    required this.guardianPhone,
    this.guardianEmail,
    this.onConsentCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(
            color: AppTheme.warning.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        const Icon(Icons.lock_clock_outlined,
            color: AppTheme.warning, size: 36),
        const SizedBox(height: 8),
        Text('No consent on file for $studentName.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppTheme.warning)),
        const SizedBox(height: 4),
        const Text(
          'Please complete the parental consent process to enable data processing.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ParentalConsentFlow(
                  studentDocId: studentDocId,
                  studentName: studentName,
                  prefillGuardianName: guardianName,
                  prefillGuardianPhone: guardianPhone,
                  prefillGuardianEmail: guardianEmail,
                ),
                fullscreenDialog: true,
              ),
            ).then((res) {
              if (res != null) {
                onConsentCompleted?.call();
              }
            });
          },
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Provide Consent Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  final ParentalConsent consent;
  final VoidCallback? onWithdraw;
  final bool isStale;
  final bool isWithdrawn;

  const _ConsentCard({
    required this.consent,
    this.onWithdraw,
    this.isStale     = false,
    this.isWithdrawn = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color statusColor = isWithdrawn
        ? Colors.grey
        : (isStale ? Colors.orange : AppTheme.success);
    final String statusLabel = isWithdrawn
        ? 'Withdrawn'
        : (isStale ? 'Outdated' : 'Active');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(
            color: statusColor.withValues(alpha: 0.3)),
        boxShadow:    [
          BoxShadow(
            color:     Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:        statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(statusLabel,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:        Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(consent.method.label,
                style: TextStyle(
                    fontSize: 10, color: Colors.grey.shade600)),
          ),
          const Spacer(),
          Text('v${consent.consentVersion}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        ]),
        const SizedBox(height: 10),
        Text('Guardian: ${consent.guardianName}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Text(consent.guardianPhone,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Text(
          'Consented: ${_fmtDate(context, consent.consentedAt.toDate())}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
        if (consent.withdrawnAt != null)
          Text(
            'Withdrawn: ${_fmtDate(context, consent.withdrawnAt!.toDate())} — ${consent.withdrawnReason ?? ''}',
            style: const TextStyle(fontSize: 11, color: Colors.red),
          ),

        // Scopes
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: consent.scopes.map((s) => _ScopeChip(scope: s)).toList(),
        ),

        // Withdraw button
        if (onWithdraw != null && !isWithdrawn) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onWithdraw,
              icon: const Icon(Icons.remove_circle_outline, size: 15),
              label: const Text('Withdraw Consent'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side:            const BorderSide(color: Colors.red),
                padding:         const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                textStyle:       const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  String _fmtDate(BuildContext context, DateTime d) {
    try {
      return MaterialLocalizations.of(context).formatCompactDate(d);
    } catch (_) {
      final dayStr = d.day.toString().padLeft(2, '0');
      final monthStr = d.month.toString().padLeft(2, '0');
      return '$dayStr/$monthStr/${d.year}';
    }
  }
}

class _ScopeChip extends StatelessWidget {
  final ConsentScope scope;
  const _ScopeChip({required this.scope});

  @override
  Widget build(BuildContext context) {
    final color = scope.optedIn ? AppTheme.success : Colors.grey;
    final String rawType = scope.dataType;
    final label = rawType.replaceAll('_', ' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          scope.optedIn ? Icons.check : Icons.close,
          size:  10,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w500),
        ),
      ]),
    );
  }
}

class _WithdrawDialog extends StatefulWidget {
  final String consentId;
  const _WithdrawDialog({required this.consentId});

  @override
  State<_WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends State<_WithdrawDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Withdraw Consent'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
          'This will notify the school admin for data review. Please explain why you are withdrawing.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ctrl,
          maxLines:   3,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText:   'Reason (optional)',
            border:      OutlineInputBorder(),
            hintText:    'e.g. No longer enrolled',
          ),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Withdraw'),
        ),
      ],
    );
  }
}
