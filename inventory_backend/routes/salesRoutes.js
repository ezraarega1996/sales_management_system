import express from "express"
import {
  getAllSales,
  getSaleById,
  createSale,
  updateSale,
  deleteSale,
  getSalesByUser,
  getDashboardStats,
  getAvailableQuantity,
} from "../controllers/salesController.js"
import { authenticate, authorizeOwner } from "../middleware/auth.js"

const router = express.Router()

router.get("/", authenticate, getAllSales)
router.get("/available-quantity", authenticate, getAvailableQuantity)
router.get("/user", authenticate, getSalesByUser)
router.get("/dashboard", authenticate, getDashboardStats)
router.get("/:id", authenticate, getSaleById)
router.post("/", authenticate, createSale)
router.put("/:id", authenticate, authorizeOwner, updateSale)
router.delete("/:id", authenticate, authorizeOwner, deleteSale)

export default router
