import jwt from "jsonwebtoken"
import { User, Business, sequelize, Shop } from "../models/index.js"

export const register = async (req, res) => {
  try {
    const { name, phone, location, username, password, role, businessId } = req.body

    // Check if user already exists
    const existingUser = await User.findOne({
      where: {
        [sequelize.Op.or]: [{ username }],
      },
    })

    if (existingUser) {
      return res.status(400).json({ message: "Username already exists" })
    }

    // If businessId is provided, check if it exists
    if (businessId) {
      const business = await Business.findByPk(businessId)
      if (!business) {
        return res.status(404).json({ message: "Business not found" })
      }
    }

    // Create new user
    const user = await User.create({
      name,
      phone,
      location,
      username,
      password, // Will be hashed by the model hook
      role: role || "salesman",
      businessId,
    })

    // Generate JWT token
    const token = jwt.sign({ id: user.id, role: user.role }, process.env.JWT_SECRET, { expiresIn: "7d" })

    res.status(201).json({
      message: "User registered successfully",
      token,
      user: {
        id: user.id,
        name: user.name,
        role: user.role,
        businessId: user.businessId,
      },
    })
  } catch (error) {
    console.error("Error registering user:", error)
    res.status(500).json({ message: "Error registering user", error: error.message })
  }
}

export const login = async (req, res) => {
  console.log("Login request received");
  console.log("Request body:", req.body);
  console.log("Request headers:", req.headers);
  
  try {
    const { username, password } = req.body

    console.log("Login attempt for username:", username);

    // Find user by username
    const user = await User.findOne({
      where: { username },
      include: [
        { model: Business },
        { model: Shop },
      ],
    })

    console.log("User found:", user ? "Yes" : "No");

    if (!user) {
      return res.status(401).json({ message: "Invalid credentials" })
    }

    // Validate password
    const isPasswordValid = await user.validatePassword(password)

    console.log("Password validation:", isPasswordValid ? "Valid" : "Invalid");

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

    console.log("JWT token generated successfully");

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
    
    console.log("Login response sent successfully");
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
