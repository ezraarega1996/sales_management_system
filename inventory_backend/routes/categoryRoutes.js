import express from "express"
import {
  getAllCategories,
  getCategoryById,
  createCategory,
  updateCategory,
  deleteCategory,
} from "../controllers/categoryController.js"
import { authenticate, authorizeOwner } from "../middleware/auth.js"

const router = express.Router()

router.get("/", authenticate, getAllCategories)
router.get("/:id", authenticate, getCategoryById)
router.post("/", authenticate, authorizeOwner, createCategory)
router.put("/:id", authenticate, authorizeOwner, updateCategory)
router.delete("/:id", authenticate, authorizeOwner, deleteCategory)

export default router
