import express from "express"
import { createCheckoutSession, handleWebhook, getSubscriptionPlans } from "../controllers/paymentController.js"
import { authenticate } from "../middleware/auth.js"

const router = express.Router()

// Get subscription plans
router.get("/plans", getSubscriptionPlans)

// Create checkout session
router.post("/create-checkout-session", authenticate, createCheckoutSession)

// Webhook endpoint for Stripe
router.post("/webhook", express.raw({ type: "application/json" }), handleWebhook)

export default router
