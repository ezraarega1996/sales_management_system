import '../models/business.dart';
import '../models/subscription_plan.dart';
import '../utils/api.dart';

class BusinessService {
  /// Cached so the owner screens still show the business when offline.
  Future<Business> getBusinessById(String id) async {
    final response = await Api.getCached('businesses/$id');
    return Business.fromJson(response.data);
  }

  Future<Map<String, SubscriptionPlan>> getSubscriptionPlans() async {
    final response = await Api.get('subscription/plans');
    return Map<String, SubscriptionPlan>.fromEntries(
      (response as List).map((plan) => MapEntry(plan['name'], SubscriptionPlan.fromJson(plan))),
    );
  }

  Future<String?> createCheckoutSession(String planName) async {
    final response = await Api.post('subscription/checkout', {'planName': planName});
    return response['checkoutUrl'];
  }
}
