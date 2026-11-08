import jwt from "jsonwebtoken"
import { User, Business, Shop } from "../models/index.js"

export const login = async (req, res) => {
  try {
    const { username, password } = req.body


    // Find user by username
    const user = await User.findOne({
      where: { username },
      include: [
        { model: Business },
        { model: Shop },
      ],
    })


    if (!user) {
      return res.status(401).json({ message: "Invalid credentials" })
    }

    // Validate password
    const isPasswordValid = await user.validatePassword(password)


    if (!isPasswordValid) {
      return res.status(401).json({ message: "Invalid credentials" })
    }

    // Check if user is active
    if (!user.isActive) {
      return res.status(403).json({ message: "Your account is inactive. Please contact support." })
    }

    // Check if business is active (except for admin users)
    if (user.role !== "admin" && user.Business && !user.Business.isActive) {
      return res.status(403).json({ message: "Your business account is inactive. Please contact support." })
    }

    // Check if subscription is active (except for admin users)
    if (
      user.role !== "admin" &&
      user.Business &&
      (user.Business.subscriptionStatus === "expired" || user.Business.subscriptionStatus === "cancelled")
    ) {
      return res
        .status(403)
        .json({ message: "Your business subscription has expired. Please renew your subscription." })
    }

    // Generate JWT token
    const token = jwt.sign({ id: user.id, role: user.role }, process.env.JWT_SECRET, { expiresIn: "7d" })


    res.json({
      message: "Login successful",
      token,
      user: {
        id: user.id,
        name: user.name,
        phone: user.phone,
        location: user.location,
        username: user.username,
        role: user.role,
        businessId: user.businessId,
        shopId: user.shopId,
        business: user.Business
          ? {
              id: user.Business.id,
              name: user.Business.name,
              subscriptionStatus: user.Business.subscriptionStatus,
              subscriptionPlan: user.Business.subscriptionPlan,
            }
          : null,
        shop: user.Shop
          ? {
              id: user.Shop.id,
              name: user.Shop.name,
              address: user.Shop.address,
              businessId: user.Shop.businessId,
              isActive: user.Shop.isActive,
            }
          : null,
      },
    })
    
  } catch (error) {
    console.error("Error logging in:", error)
    res.status(500).json({ message: "Error logging in", error: error.message })
  }
}

export const changePassword = async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body
    const userId = req.user.id // From auth middleware

    if (!currentPassword || !newPassword) {
      return res.status(400).json({ message: "Current password and new password are required" })
    }

    const user = await User.findByPk(userId)
    if (!user) {
      return res.status(404).json({ message: "User not found" })
    }

    // Verify current password
    const isCurrentPasswordValid = await user.validatePassword(currentPassword)
    if (!isCurrentPasswordValid) {
      return res.status(400).json({ message: "Current password is incorrect" })
    }

    // Update password
    user.password = newPassword // Will be hashed by the model hook
    await user.save()

    res.json({ message: "Password changed successfully" })
  } catch (error) {
    console.error("Error changing password:", error)
    res.status(500).json({ message: "Error changing password", error: error.message })
  }
}
