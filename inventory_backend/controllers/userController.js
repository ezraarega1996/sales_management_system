import { User, Business, Shop } from "../models/index.js"
import { checkSubscriptionLimits } from "../config/subscriptionPlans.js"
import { Op } from "sequelize"


export const getAllUsers = async (req, res) => {
  try {
    // For admin, return all users
    if (req.user.role === "admin") {
      const users = await User.findAll({
        attributes: { exclude: ["password"] },
      })
      return res.json(users)
    }

    // For owner, return only users from their business
    const users = await User.findAll({
      where: {
        businessId: req.user.businessId,
        role: "salesman",
      },
      attributes: { exclude: ["password"] },
    })
    res.json(users)
  } catch (error) {
    console.error("errr in listing users: ", error.message)
    res.status(500).json({ message: "Error fetching users", error: error.message })
  }
}

export const getUserById = async (req, res) => {
  try {
    const user = await User.findByPk(req.params.id, {
      attributes: { exclude: ["password"] },
    })

    if (!user) {
      return res.status(404).json({ message: "User not found" })
    }

    // Only admin, owner of the business, or the user themselves can view user details
    if (
      req.user.role !== "admin" &&
      (req.user.role !== "owner" || req.user.businessId !== user.businessId) &&
      req.user.id !== user.id
    ) {
      return res.status(403).json({ message: "Not authorized to view this user" })
    }

    res.json(user)
  } catch (error) {
    res.status(500).json({ message: "Error fetching user", error: error.message })
  }
}

export const createUser = async (req, res) => {
  try {
    const { name, phone, location, username, password, role, shopId } = req.body

    // Only admin or owner can create users
    if (req.user.role !== "admin" && req.user.role !== "owner") {
      return res.status(403).json({ message: "Not authorized to create users" })
    }
    // Owners add salesmen to their own business; only a platform admin may create owners or admins
    const newRole = role || "salesman"
    if (!["salesman", "owner", "admin"].includes(newRole)) {
      return res.status(400).json({ message: "Invalid role" })
    }
    if (req.user.role !== "admin" && newRole !== "salesman") {
      return res.status(403).json({ message: "Owners can only add salesmen" })
    }

    // If not admin, check subscription limits for user count
    if (req.user.role !== "admin") {
      const business = await Business.findByPk(req.user.businessId)

      if (!business) {
        return res.status(404).json({ message: "Business not found" })
      }

      // Count existing users for this business
      const userCount = await User.count({ where: { businessId: req.user.businessId } })

      // Check if adding a new user would exceed the limit
      const canAddUser = await checkSubscriptionLimits(business, "users", userCount)

      if (!canAddUser) {
        return res.status(403).json({
          message: "User limit reached for your subscription plan. Please upgrade to add more users.",
        })
      }
    }

    // Check if user already exists
    const existingUser = await User.findOne({
      where: {
        [Op.or]: [{ username }],
      },
    })

    if (existingUser) {
      return res.status(400).json({ message: "Username already exists" })
    }

    // Set businessId based on who is creating the user
    const businessId = req.user.role === "admin" ? req.body.businessId : req.user.businessId

    // A shop given for the new user must belong to the same business
    if (shopId && !(await Shop.findOne({ where: { id: shopId, businessId } }))) {
      return res.status(400).json({ message: "Shop not found in this business" })
    }

    // Create user
    const user = await User.create({
      name,
      phone,
      location,
      username,
      password,
      role: newRole,
      businessId,
      shopId,
    })

    res.status(201).json({
      id: user.id,
      name: user.name,
      phone: user.phone,
      location: user.location,
      username: user.username,
      role: user.role,
      businessId: user.businessId,
      shopId: user.shopId,
    })
  } catch (error) {
    res.status(500).json({ message: "Error creating user", error: error.message })
  }
}

export const updateUser = async (req, res) => {
  try {
    const { name, phone, location, password, shopId } = req.body

    const user = await User.findByPk(req.params.id)

    if (!user) {
      return res.status(404).json({ message: "User not found" })
    }

    // Only admin, owner of the business, or the user themselves can update user details
    if (
      req.user.role !== "admin" &&
      (req.user.role !== "owner" || req.user.businessId !== user.businessId) &&
      req.user.id !== user.id
    ) {
      return res.status(403).json({ message: "Not authorized to update this user" })
    }

    // Editing your own account: only contact details. A new password goes through
    // change-password (which asks for the current one), and the shop is the owner's decision.
    const managesUser = req.user.role === "admin" || (req.user.role === "owner" && req.user.id !== user.id)
    if (!managesUser && (password || shopId !== undefined)) {
      return res.status(403).json({ message: "Use Change Password to change your password; only the owner can change your shop" })
    }
    if (shopId && !(await Shop.findOne({ where: { id: shopId, businessId: user.businessId } }))) {
      return res.status(400).json({ message: "Shop not found in this business" })
    }

    // Update user
    if (name) user.name = name
    if (phone) user.phone = phone
    if (location) user.location = location
    if (password) user.password = password
    if (shopId !== undefined) user.shopId = shopId

    await user.save()

    res.json({
      id: user.id,
      name: user.name,
      phone: user.phone,
      location: user.location,
      username: user.username,
      role: user.role,
      businessId: user.businessId,
      shopId: user.shopId,
    })
  } catch (error) {
    res.status(500).json({ message: "Error updating user", error: error.message })
  }
}

export const deleteUser = async (req, res) => {
  try {
    const user = await User.findByPk(req.params.id)

    if (!user) {
      return res.status(404).json({ message: "User not found" })
    }

    // Only admin or owner of the business can delete users
    if (req.user.role !== "admin" && (req.user.role !== "owner" || req.user.businessId !== user.businessId)) {
      return res.status(403).json({ message: "Not authorized to delete users" })
    }

    // Prevent deleting owner accounts (except for admin)
    if (user.role === "owner" && req.user.role !== "admin") {
      return res.status(403).json({ message: "Cannot delete owner accounts" })
    }

    await user.destroy()

    res.json({ message: "User deleted successfully" })
  } catch (error) {
    res.status(500).json({ message: "Error deleting user", error: error.message })
  }
}
