import { Business, Subscription } from "../models/index.js"
import { getSubscriptionPlan } from "../config/subscriptionPlans.js"
import Stripe from "stripe"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY)

// Create a checkout session for subscription
export const createCheckoutSession = async (req, res) => {
  try {
    const { planName, businessId } = req.body

    // Check if business exists
    const business = await Business.findByPk(businessId)
    if (!business) {
      return res.status(404).json({ message: "Business not found" })
    }

    // Check if user is owner of this business or admin
    if (req.user.role !== "admin" && (req.user.role !== "owner" || req.user.businessId !== businessId)) {
      return res.status(403).json({ message: "Not authorized to create checkout session for this business" })
    }

    // Get plan details
    const plan = getSubscriptionPlan(planName)
    if (!plan) {
      return res.status(400).json({ message: "Invalid subscription plan" })
    }

    // Create a checkout session
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card"],
      line_items: [
        {
          price_data: {
            currency: plan.currency,
            product_data: {
              name: `${plan.name} Plan - Inventory Management System`,
              description: plan.features.join(", "),
            },
            unit_amount: Math.round(plan.price * 100), // Convert to cents
          },
          quantity: 1,
        },
      ],
      mode: "subscription",
      success_url: `${process.env.FRONTEND_URL}/subscription/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${process.env.FRONTEND_URL}/subscription/cancel`,
      client_reference_id: businessId,
      metadata: {
        businessId,
        planName,
      },
    })

    res.json({ url: session.url })
  } catch (error) {
    res.status(500).json({ message: "Error creating checkout session", error: error.message })
  }
}

// Handle webhook events from Stripe
export const handleWebhook = async (req, res) => {
  const sig = req.headers["stripe-signature"]

  let event

  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET)
  } catch (err) {
    return res.status(400).send(`Webhook Error: ${err.message}`)
  }

  // Handle the event
  switch (event.type) {
    case "checkout.session.completed":
      const session = event.data.object
      await handleCheckoutSessionCompleted(session)
      break
    case "invoice.paid":
      const invoice = event.data.object
      await handleInvoicePaid(invoice)
      break
    case "customer.subscription.updated":
      const subscription = event.data.object
      await handleSubscriptionUpdated(subscription)
      break
    case "customer.subscription.deleted":
      const deletedSubscription = event.data.object
      await handleSubscriptionDeleted(deletedSubscription)
      break
    default:
      console.log(`Unhandled event type ${event.type}`)
  }

  res.json({ received: true })
}

// Handle checkout.session.completed event
const handleCheckoutSessionCompleted = async (session) => {
  try {
    const { businessId, planName } = session.metadata
    const business = await Business.findByPk(businessId)

    if (!business) {
      console.error(`Business not found: ${businessId}`)
      return
    }

    // Update business subscription
    business.subscriptionStatus = "active"
    business.subscriptionPlan = planName
    business.subscriptionEndsAt = null // Will be updated when we get invoice.paid event
    await business.save()

    // Create subscription record
    await Subscription.create({
      businessId,
      plan: planName,
      status: "active",
      startDate: new Date(),
      paymentMethod: "stripe",
      paymentId: session.subscription,
      amount: session.amount_total / 100, // Convert from cents
      currency: session.currency,
      isAutoRenew: true,
    })
  } catch (error) {
    console.error("Error handling checkout.session.completed:", error)
  }
}

// Handle invoice.paid event
const handleInvoicePaid = async (invoice) => {
  try {
    const subscription = await stripe.subscriptions.retrieve(invoice.subscription)
    const businessId = subscription.metadata.businessId

    if (!businessId) {
      console.error("No businessId found in subscription metadata")
      return
    }

    const business = await Business.findByPk(businessId)
    if (!business) {
      console.error(`Business not found: ${businessId}`)
      return
    }

    // Calculate subscription end date
    const endDate = new Date(subscription.current_period_end * 1000) // Convert from Unix timestamp

    // Update business subscription
    business.subscriptionEndsAt = endDate
    await business.save()

    // Update subscription record
    const existingSubscription = await Subscription.findOne({
      where: { paymentId: subscription.id },
    })

    if (existingSubscription) {
      existingSubscription.endDate = endDate
      await existingSubscription.save()
    }
  } catch (error) {
    console.error("Error handling invoice.paid:", error)
  }
}

// Handle customer.subscription.updated event
const handleSubscriptionUpdated = async (subscription) => {
  try {
    const businessId = subscription.metadata.businessId

    if (!businessId) {
      console.error("No businessId found in subscription metadata")
      return
    }

    const business = await Business.findByPk(businessId)
    if (!business) {
      console.error(`Business not found: ${businessId}`)
      return
    }

    // Update business subscription status
    if (subscription.status === "active") {
      business.subscriptionStatus = "active"
    } else if (subscription.status === "canceled") {
      business.subscriptionStatus = "cancelled"
    } else if (subscription.status === "unpaid" || subscription.status === "past_due") {
      business.subscriptionStatus = "expired"
    }

    // Update subscription end date
    business.subscriptionEndsAt = new Date(subscription.current_period_end * 1000)
    await business.save()

    // Update subscription record
    const existingSubscription = await Subscription.findOne({
      where: { paymentId: subscription.id },
    })

    if (existingSubscription) {
      existingSubscription.status = subscription.status === "active" ? "active" : "cancelled"
      existingSubscription.endDate = new Date(subscription.current_period_end * 1000)
      await existingSubscription.save()
    }
  } catch (error) {
    console.error("Error handling customer.subscription.updated:", error)
  }
}

// Handle customer.subscription.deleted event
const handleSubscriptionDeleted = async (subscription) => {
  try {
    const businessId = subscription.metadata.businessId

    if (!businessId) {
      console.error("No businessId found in subscription metadata")
      return
    }

    const business = await Business.findByPk(businessId)
    if (!business) {
      console.error(`Business not found: ${businessId}`)
      return
    }

    // Update business subscription
    business.subscriptionStatus = "cancelled"
    await business.save()

    // Update subscription record
    const existingSubscription = await Subscription.findOne({
      where: { paymentId: subscription.id },
    })

    if (existingSubscription) {
      existingSubscription.status = "cancelled"
      await existingSubscription.save()
    }
  } catch (error) {
    console.error("Error handling customer.subscription.deleted:", error)
  }
}

// Get subscription plans
export const getSubscriptionPlans = async (req, res) => {
  try {
    const { subscriptionPlans } = await import("../config/subscriptionPlans.js")
    res.json(subscriptionPlans)
  } catch (error) {
    res.status(500).json({ message: "Error fetching subscription plans", error: error.message })
  }
}
