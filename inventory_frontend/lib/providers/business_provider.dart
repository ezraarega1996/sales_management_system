import 'package:flutter/foundation.dart';
import '../models/business.dart';
import '../models/subscription_plan.dart';
import '../services/business_service.dart';

class BusinessProvider with ChangeNotifier {
  final BusinessService _businessService;
  Business? _currentBusiness;
  Map<String, SubscriptionPlan> _subscriptionPlans = {};
  String? _error;

  BusinessProvider(this._businessService);

  Business? get currentBusiness => _currentBusiness;
  Map<String, SubscriptionPlan> get subscriptionPlans => _subscriptionPlans;
  String? get error => _error;

  Future<void> loadCurrentBusiness(String id) async {
    _error = null;
    try {
      _currentBusiness = await _businessService.getBusinessById(id);
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<void> loadSubscriptionPlans() async {
    _error = null;
    try {
      _subscriptionPlans = await _businessService.getSubscriptionPlans();
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<String?> createCheckoutSession(String planName) async {
    _error = null;
    try {
      return await _businessService.createCheckoutSession(planName);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Forgets everything loaded for the signed-in user (called on logout), so the next person
  /// using this phone never sees it.
  void reset() {
    _currentBusiness = null;
    _subscriptionPlans = {};
    _error = null;
    notifyListeners();
  }
}
