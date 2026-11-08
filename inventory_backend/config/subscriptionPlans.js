export const subscriptionPlans = {
  free: {
    name: "Free",
    price: 0,
    currency: "USD",
    features: ["1 Owner account", "2 Salesman accounts", "50 Items limit", "Basic reporting", "7-day data retention"],
    limits: {
      users: 3, // 1 owner + 2 salesmen
      items: 50,
      dataRetentionDays: 7,
    },
  },
  basic: {
    name: "Basic",
    price: 9.99,
    currency: "USD",
    features: [
      "1 Owner account",
      "5 Salesman accounts",
      "200 Items limit",
      "Basic reporting",
      "30-day data retention",
      "Email support",
    ],
    limits: {
      users: 6, // 1 owner + 5 salesmen
      items: 200,
      dataRetentionDays: 30,
    },
  },
  premium: {
    name: "Premium",
    price: 29.99,
    currency: "USD",
    features: [
      "3 Owner accounts",
      "15 Salesman accounts",
      "1000 Items limit",
      "Advanced reporting",
      "90-day data retention",
      "Priority email support",
      "Data export",
    ],
    limits: {
      users: 18, // 3 owners + 15 salesmen
      items: 1000,
      dataRetentionDays: 90,
    },
  },
  enterprise: {
    name: "Enterprise",
    price: 99.99,
    currency: "USD",
    features: [
      "10 Owner accounts",
      "Unlimited Salesman accounts",
      "Unlimited Items",
      "Advanced reporting & analytics",
      "Unlimited data retention",
      "Priority support",
      "Data export",
      "API access",
      "Custom branding",
    ],
    limits: {
      users: Number.POSITIVE_INFINITY,
      items: Number.POSITIVE_INFINITY,
      dataRetentionDays: Number.POSITIVE_INFINITY,
    },
  },
}

export const getSubscriptionPlan = (planName) => {
  return subscriptionPlans[planName] || subscriptionPlans.free
}

export const checkSubscriptionLimits = async (business, limitType, currentCount) => {
  const plan = getSubscriptionPlan(business.subscriptionPlan)
  const limit = plan.limits[limitType]

  // If limit is Infinity or current count is less than limit, return true
  return limit === Number.POSITIVE_INFINITY || currentCount < limit
}
