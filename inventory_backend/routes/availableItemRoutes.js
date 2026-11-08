import express from "express"
import {
  getAllAvailableItems,
  getAvailableItemTransactions,
  getTodaySalesBySalesman,
} from "../controllers/availableItemController.js"
import { authenticate } from "../middleware/auth.js"

const router = express.Router()

router.get("/today-sales", authenticate, getTodaySalesBySalesman)
router.get("/", authenticate, getAllAvailableItems)
router.get("/:id/transactions", authenticate, getAvailableItemTransactions)

export default router
