import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/licensing_service.dart';
import '../providers/school_settings_provider.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';

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
    
    final featName = featureNameOverride ?? _getDefaultFeatureName(context, feature);
    final featDesc = featureDescOverride ?? _getDefaultFeatureDesc(context, feature);

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
                    context.tr('availableOnPlan').replaceAll('{plan}', targetPlanLabel),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (targetPlanPrice.isNotEmpty)
                    Text(
                      context.tr('startingAtPrice').replaceAll('{price}', targetPlanPrice),
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
                          child: Text(context.tr('goBack')),
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
                          child: Text(context.tr('upgradePlan')),
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

  String _getDefaultFeatureName(BuildContext context, String feat) {
    switch (feat) {
      case 'expense_tracking':
        return context.tr('featExpenseLedger');
      case 'profit_loss':
        return context.tr('featProfitLoss');
      case 'advanced_analytics':
        return context.tr('featAdvancedAnalytics');
      case 'biometric_integration':
        return context.tr('featBiometricIntegration');
      case 'custom_branding':
        return context.tr('featCustomBranding');
      default:
        return context.tr('featPremiumOperations');
    }
  }

  String _getDefaultFeatureDesc(BuildContext context, String feat) {
    switch (feat) {
      case 'expense_tracking':
        return context.tr('featExpenseLedgerDesc');
      case 'profit_loss':
        return context.tr('featProfitLossDesc');
      case 'advanced_analytics':
        return context.tr('featAdvancedAnalyticsDesc');
      case 'biometric_integration':
        return context.tr('featBiometricIntegrationDesc');
      case 'custom_branding':
        return context.tr('featCustomBrandingDesc');
      default:
        return context.tr('featPremiumOperationsDesc');
    }
  }

  void _simulateUpgradeRequest(BuildContext context, String featureName, String targetPlan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.mark_email_read_outlined, color: Colors.green),
            const SizedBox(width: 8),
            Text(context.tr('requestSent')),
          ],
        ),
        content: Text(
          context.tr('upgradeRequestSentDesc').replaceAll('{plan}', targetPlan).replaceAll('{feature}', featureName),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            child: Text(context.tr('ok')),
          ),
        ],
      ),
    );
  }
}
