import express from "express"
import { getAllItems, getItemById, createItem, updateItem, deleteItem } from "../controllers/itemController.js"
import { authenticate, authorizeOwner } from "../middleware/auth.js"

const router = express.Router()

router.get("/", authenticate, getAllItems)
router.get("/:id", authenticate, getItemById)
router.post("/", authenticate, authorizeOwner, createItem)
router.put("/:id", authenticate, authorizeOwner, updateItem)
router.delete("/:id", authenticate, authorizeOwner, deleteItem)

export default router
