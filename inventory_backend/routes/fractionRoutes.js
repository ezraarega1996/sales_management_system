import express from "express"
import {
  getAllFractions,
  getFractionById,
  createFraction,
  updateFraction,
  deleteFraction,
} from "../controllers/fractionController.js"
import { authenticate, authorizeOwner } from "../middleware/auth.js"

const router = express.Router()

router.get("/", authenticate, getAllFractions)
router.get("/:id", authenticate, getFractionById)
router.post("/", authenticate, authorizeOwner, createFraction)
router.put("/:id", authenticate, authorizeOwner, updateFraction)
router.delete("/:id", authenticate, authorizeOwner, deleteFraction)

export default router
