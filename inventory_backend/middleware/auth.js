import jwt from "jsonwebtoken"
import { User, Business } from "../models/index.js"

/** Fields that reveal what the business pays for goods or earns on them: owner-only. */
const COST_FIELDS = new Set([
  "purchasePrice",
  "fractionPurchasePrice",
  "profit",
  "totalProfit",
  "todayProfit",
  "unitCost",
  "avgUnitCost",
  "stockValue",
])

/** Deep copy of [value] without cost fields (handles Sequelize instances via toJSON). */
const withoutCosts = (value) => {
  if (Array.isArray(value)) return value.map(withoutCosts)
  if (value && typeof value === "object") {
    // Dates (and other values with their own JSON form) stay as they are; a Date's toJSON gives a
    // string, which must not be walked like an object
    if (value instanceof Date) return value
    if (typeof value.toJSON === "function") {
      value = value.toJSON()
      if (!value || typeof value !== "object") return value
      if (Array.isArray(value)) return value.map(withoutCosts)
    }
    const out = {}
    for (const [key, v] of Object.entries(value)) {
      if (!COST_FIELDS.has(key)) out[key] = withoutCosts(v)
    }
    return out
  }
  return value
}

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
    // Salesmen must not see purchase prices or profit: strip them from every response
    if (user.role === "salesman") {
      const json = res.json.bind(res)
      res.json = (body) => json(withoutCosts(body))
    }
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
