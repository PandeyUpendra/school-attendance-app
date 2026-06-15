class LicensingService {
  static final LicensingService _instance = LicensingService._();
  LicensingService._();
  factory LicensingService() => _instance;

  static const String PLAN_FREE = 'free';
  static const String PLAN_BASIC = 'basic';
  static const String PLAN_PRO = 'pro';
  static const String PLAN_ENTERPRISE = 'enterprise';

  /// Maps features to the minimum plan required to access them.
  static const Map<String, String> _featureRequirements = {
    'expense_tracking': PLAN_PRO,
    'profit_loss': PLAN_ENTERPRISE,
    'advanced_analytics': PLAN_PRO,
    'biometric_integration': PLAN_ENTERPRISE,
    'custom_branding': PLAN_ENTERPRISE,
  };

  /// Returns true if the given [feature] is enabled for the [currentPlan].
  bool isFeatureEnabled({required String currentPlan, required String feature}) {
    final minimumRequired = _featureRequirements[feature];
    if (minimumRequired == null) {
      // If a feature is not mapped, it's open to all plans (free tier).
      return true;
    }

    final currentWeight = _getPlanWeight(currentPlan);
    final requiredWeight = _getPlanWeight(minimumRequired);

    return currentWeight >= requiredWeight;
  }

  int _getPlanWeight(String plan) {
    switch (plan.toLowerCase().trim()) {
      case PLAN_FREE:
        return 0;
      case PLAN_BASIC:
        return 1;
      case PLAN_PRO:
        return 2;
      case PLAN_ENTERPRISE:
        return 3;
      default:
        return 0;
    }
  }

  /// Helper to get user-friendly name of the subscription plan
  String getPlanDisplayName(String plan) {
    switch (plan.toLowerCase().trim()) {
      case PLAN_FREE:
        return 'Free Sandbox';
      case PLAN_BASIC:
        return 'SaaS Basic';
      case PLAN_PRO:
        return 'SaaS Pro';
      case PLAN_ENTERPRISE:
        return 'SaaS Enterprise';
      default:
        return 'Free Sandbox';
    }
  }

  /// Helper to get the price description for upgrades
  String getPlanPrice(String plan) {
    switch (plan.toLowerCase().trim()) {
      case PLAN_BASIC:
        return '₹20 / student / month';
      case PLAN_PRO:
        return '₹45 / student / month';
      case PLAN_ENTERPRISE:
        return '₹75 / student / month';
      default:
        return '';
    }
  }
}
