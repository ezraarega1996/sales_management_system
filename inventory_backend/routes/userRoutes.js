import express from "express"
import { getAllUsers, getUserById, createUser, updateUser, deleteUser } from "../controllers/userController.js"
import { authenticate, authorizeOwner } from "../middleware/auth.js"

const router = express.Router()

router.get("/", authenticate, authorizeOwner, getAllUsers)
router.get("/:id", authenticate, getUserById)
router.post("/", authenticate, authorizeOwner, createUser)
router.put("/:id", authenticate, updateUser)
router.delete("/:id", authenticate, authorizeOwner, deleteUser)

export default router
