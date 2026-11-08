import express from "express"
import {
  getAllShops,
  getShopById,
  createShop,
  updateShop,
  deleteShop,
  assignSalespersonToShop,
  removeSalespersonFromShop,
  getAvailableSalespeople,
} from "../controllers/shopController.js"
import { authenticate, authorizeOwner } from "../middleware/auth.js"

const router = express.Router()

// All routes require authentication
router.use(authenticate)

// Shop management routes (owner only)
router.get("/", authorizeOwner, getAllShops)
router.get("/available-salespeople", authorizeOwner, getAvailableSalespeople)
router.get("/:id", authorizeOwner, getShopById)
router.post("/", authorizeOwner, createShop)
router.put("/:id", authorizeOwner, updateShop)
router.delete("/:id", authorizeOwner, deleteShop)

// Salesperson assignment routes (owner only)
router.post("/:id/assign-salesperson", authorizeOwner, assignSalespersonToShop)
router.post("/:id/remove-salesperson", authorizeOwner, removeSalespersonFromShop)

export default router 