import express from "express"
import {
  createBusiness,
  getAllBusinesses,
  getBusinessById,
  updateBusiness,
  updateSubscription,
  getBusinessStats,
} from "../controllers/businessController.js"
import { authenticate, authorizeAdmin } from "../middleware/auth.js"

const router = express.Router()

// Public route for business registration
router.post("/", createBusiness)

//Protected routes
router.get("/", authenticate, authorizeAdmin, getAllBusinesses)
router.get("/:id", authenticate, getBusinessById)
router.put("/:id", authenticate, updateBusiness)
router.put("/:id/subscription", authenticate, authorizeAdmin, updateSubscription)
router.get("/:id/stats", authenticate, getBusinessStats)


export default router
