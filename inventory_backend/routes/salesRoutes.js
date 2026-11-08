import express from "express"
import {
  getAllSales,
  getSaleById,
  createSale,
  createBatchSale,
  undoReceipt,
  updateSale,
  deleteSale,
  getSalesByUser,
  getDashboardStats,
} from "../controllers/salesController.js"
import { authenticate, authorizeOwner } from "../middleware/auth.js"

const router = express.Router()

router.get("/", authenticate, getAllSales)
router.get("/user", authenticate, getSalesByUser)
router.get("/dashboard", authenticate, getDashboardStats)
router.get("/:id", authenticate, getSaleById)
router.post("/", authenticate, createSale)
router.post("/batch", authenticate, createBatchSale)
router.delete("/receipt/:receiptId", authenticate, undoReceipt)
router.put("/:id", authenticate, authorizeOwner, updateSale)
router.delete("/:id", authenticate, authorizeOwner, deleteSale)

export default router
