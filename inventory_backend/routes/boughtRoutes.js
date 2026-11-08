import express from "express"
import {
  getAllBoughts,
  getBoughtById,
  createBought,
  updateBought,
  deleteBought,
} from "../controllers/boughtController.js"
import { authenticate, authorizeOwner } from "../middleware/auth.js"

const router = express.Router()

router.get("/", authenticate, getAllBoughts)
router.get("/:id", authenticate, getBoughtById)
router.post("/", authenticate, authorizeOwner, createBought)
router.put("/:id", authenticate, authorizeOwner, updateBought)
router.delete("/:id", authenticate, authorizeOwner, deleteBought)

export default router
