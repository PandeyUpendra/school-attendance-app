import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/licensing_service.dart';
import '../providers/school_settings_provider.dart';
import '../../theme.dart';

class PremiumFeatureGate extends StatelessWidget {
  final String feature;
  final Widget child;
  final String? featureNameOverride;
  final String? featureDescOverride;

  const PremiumFeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.featureNameOverride,
    this.featureDescOverride,
  });

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SchoolSettingsProvider>(context);
    final plan = settings.subscriptionPlan;
    final licensing = LicensingService();

    final isEnabled = licensing.isFeatureEnabled(currentPlan: plan, feature: feature);

    if (isEnabled) {
      return child;
    }

    // Determine target plan requirements
    String targetPlan = LicensingService.PLAN_PRO;
    if (feature == 'profit_loss' || feature == 'biometric_integration' || feature == 'custom_branding') {
      targetPlan = LicensingService.PLAN_ENTERPRISE;
    }

    final targetPlanLabel = licensing.getPlanDisplayName(targetPlan);
    final targetPlanPrice = licensing.getPlanPrice(targetPlan);
    
    final featName = featureNameOverride ?? _getDefaultFeatureName(feature);
    final featDesc = featureDescOverride ?? _getDefaultFeatureDesc(feature);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Blurred background containing a dummy presentation of what's locked
          Opacity(
            opacity: 0.15,
            child: child,
          ),
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
              child: Container(
                color: Colors.black.withValues(alpha: 0.05),
              ),
            ),
          ),
          // Premium Glassmorphism Lock Card
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Lock Icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_person_outlined,
                      color: AppTheme.primary,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Locked Feature Name
                  Text(
                    featName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // Locked Feature Description
                  Text(
                    featDesc,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1),
                  const SizedBox(height: 20),
                  // Upgrade callout
                  Text(
                    'Available on $targetPlanLabel',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (targetPlanPrice.isNotEmpty)
                    Text(
                      'Starting at $targetPlanPrice',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const SizedBox(height: 24),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            // Close screen / go back
                            Navigator.maybePop(context);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: AppTheme.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Go Back'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _simulateUpgradeRequest(context, featName, targetPlanLabel);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Upgrade Plan'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getDefaultFeatureName(String feat) {
    switch (feat) {
      case 'expense_tracking':
        return 'Expense Ledger & Budgeting';
      case 'profit_loss':
        return 'School Profit & Loss Ledger';
      case 'advanced_analytics':
        return 'Advanced Financial Analytics';
      case 'biometric_integration':
        return 'RFID & Biometric Gate Sync';
      case 'custom_branding':
        return 'White-Labeled Branding';
      default:
        return 'Premium Operations Module';
    }
  }

  String _getDefaultFeatureDesc(String feat) {
    switch (feat) {
      case 'expense_tracking':
        return 'Log, filter, and track salaries, utilities, and maintenance costs to maintain a healthy budget.';
      case 'profit_loss':
        return 'Generate statements and visual charts comparing parent fee income against school expenses.';
      case 'advanced_analytics':
        return 'Analyze fee collection rates, overdue metrics, and operational cost breakdowns over time.';
      case 'biometric_integration':
        return 'Automatically mark students present using physical smart cards, gate scans, or biometric hardware.';
      case 'custom_branding':
        return 'Display your own institution logo, brand colors, custom app store publishing, and subdomain.';
      default:
        return 'This module is restricted to commercial subscription tiers.';
    }
  }

  void _simulateUpgradeRequest(BuildContext context, String featureName, String targetPlan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.mark_email_read_outlined, color: Colors.green),
            SizedBox(width: 8),
            Text('Request Sent'),
          ],
        ),
        content: Text(
          'A subscription upgrade request to $targetPlan has been sent to your Account Manager. '
          'We will reach out to the school administration within 24 hours to activate $featureName.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
