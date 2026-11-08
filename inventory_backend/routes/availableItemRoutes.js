import express from "express"
import {
  calculateAvailableItems,
  getAllAvailableItems,
  getAvailableItemById,
  assignToShop,
  getTodaySalesBySalesman,
} from "../controllers/availableItemController.js"
import { authenticate } from "../middleware/auth.js"

const router = express.Router()

router.get("/calculate", authenticate, calculateAvailableItems)
router.get("/today-sales", authenticate, getTodaySalesBySalesman)
router.get("/", authenticate, getAllAvailableItems)
router.get("/:id", authenticate, getAvailableItemById)
router.post("/:id/assign", authenticate, assignToShop)

export default router 