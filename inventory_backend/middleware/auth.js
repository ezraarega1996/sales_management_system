import jwt from "jsonwebtoken"
import { User, Business } from "../models/index.js"

export const authenticate = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({ message: "Authentication required" })
    }

    const token = authHeader.split(" ")[1]
    const decoded = jwt.verify(token, process.env.JWT_SECRET)

    const user = await User.findByPk(decoded.id, {
      include: [{ model: Business }],
    })

    if (!user) {
      return res.status(401).json({ message: "User not found" })
    }

    // Check if user is active
    if (!user.isActive) {
      return res.status(403).json({ message: "User account is inactive" })
    }

    // Check if business is active (except for admin users)
    if (user.role !== "admin" && user.Business && !user.Business.isActive) {
      return res.status(403).json({ message: "Business account is inactive" })
    }

    // Check if subscription is active (except for admin users)
    if (
      user.role !== "admin" &&
      user.Business &&
      (user.Business.subscriptionStatus === "expired" || user.Business.subscriptionStatus === "cancelled")
    ) {
      return res.status(403).json({ message: "Business subscription has expired" })
    }

    req.user = user
    next()
  } catch (error) {
    return res.status(401).json({ message: "Invalid token" })
  }
}

export const authorizeOwner = (req, res, next) => {
  if (req.user.role !== "owner" && req.user.role !== "admin") {
    return res.status(403).json({ message: "Access denied. Owner privileges required." })
  }
  next()
}

export const authorizeAdmin = (req, res, next) => {
  if (req.user.role !== "admin") {
    return res.status(403).json({ message: "Access denied. Admin privileges required." })
  }
  next()
}
