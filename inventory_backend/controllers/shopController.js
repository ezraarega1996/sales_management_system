import { Shop, User, Business, sequelize } from "../models/index.js"
import { Op } from "sequelize"

// Get all shops for a business
export const getAllShops = async (req, res) => {
  try {
    const shops = await Shop.findAll({
      where: { 
        businessId: req.user.businessId,
        isActive: true 
      },
      include: [
        {
          model: User,
          as: "salespeople",
          attributes: ["id", "name", "username", "phone"],
          where: { role: "salesman" },
          required: false,
        },
      ],
      order: [["createdAt", "DESC"]],
    })

    res.json(shops)
  } catch (error) {
    console.log("Error in listing shops: ", error)
    res.status(500).json({ message: "Error fetching shops", error: error.message })
  }
}

// Get shop by ID
export const getShopById = async (req, res) => {
  try {
    const shop = await Shop.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
        isActive: true,
      },
      include: [
        {
          model: User,
          as: "salespeople",
          attributes: ["id", "name", "username", "phone"],
          where: { role: "salesman" },
          required: false,
        },
      ],
    })

    if (!shop) {
      return res.status(404).json({ message: "Shop not found" })
    }

    res.json(shop)
  } catch (error) {
    res.status(500).json({ message: "Error fetching shop", error: error.message })
  }
}

// Create a new shop
export const createShop = async (req, res) => {
  try {
    const { name, address } = req.body

    if (!name || !address) {
      return res.status(400).json({ message: "Shop name and address are required" })
    }

    // Only owner can create shops
    if (req.user.role !== "owner") {
      return res.status(403).json({ message: "Not authorized to create shops" })
    }

    const shop = await Shop.create({
      name,
      address,
      businessId: req.user.businessId,
    })

    res.status(201).json({
      message: "Shop created successfully",
      shop,
    })
  } catch (error) {
    console.log("Error in creating shop: ", error)
    res.status(500).json({ message: "Error creating shop", error: error.message })
  }
}

// Update shop
export const updateShop = async (req, res) => {
  try {
    const { name, address, isActive } = req.body

    const shop = await Shop.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
    })

    if (!shop) {
      return res.status(404).json({ message: "Shop not found" })
    }

    // Only owner can update shops
    if (req.user.role !== "owner") {
      return res.status(403).json({ message: "Not authorized to update shops" })
    }

    // Update shop
    if (name !== undefined) shop.name = name
    if (address !== undefined) shop.address = address
    if (isActive !== undefined) shop.isActive = isActive

    await shop.save()

    res.json({
      message: "Shop updated successfully",
      shop,
    })
  } catch (error) {
    res.status(500).json({ message: "Error updating shop", error: error.message })
  }
}

// Delete shop (soft delete)
export const deleteShop = async (req, res) => {
  try {
    const shop = await Shop.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
    })

    if (!shop) {
      return res.status(404).json({ message: "Shop not found" })
    }

    // Only owner can delete shops
    if (req.user.role !== "owner") {
      return res.status(403).json({ message: "Not authorized to delete shops" })
    }

    // Check if shop has assigned salespeople
    const salespeopleCount = await User.count({
      where: {
        shopId: shop.id,
        role: "salesman",
      },
    })

    if (salespeopleCount > 0) {
      return res.status(400).json({ 
        message: "Cannot delete shop with assigned salespeople. Please reassign or remove salespeople first." 
      })
    }

    // Soft delete
    shop.isActive = false
    await shop.save()

    res.json({ message: "Shop deleted successfully" })
  } catch (error) {
    res.status(500).json({ message: "Error deleting shop", error: error.message })
  }
}

// Assign salesperson to shop
export const assignSalespersonToShop = async (req, res) => {
  try {
    const { salespersonId } = req.body

    if (!salespersonId) {
      return res.status(400).json({ message: "Salesperson ID is required" })
    }

    // Only owner can assign salespeople
    if (req.user.role !== "owner") {
      return res.status(403).json({ message: "Not authorized to assign salespeople" })
    }

    const shop = await Shop.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
        isActive: true,
      },
    })

    if (!shop) {
      return res.status(404).json({ message: "Shop not found" })
    }

    const salesperson = await User.findOne({
      where: {
        id: salespersonId,
        businessId: req.user.businessId,
        role: "salesman",
      },
    })

    if (!salesperson) {
      return res.status(404).json({ message: "Salesperson not found" })
    }

    // Update salesperson's shop assignment
    salesperson.shopId = shop.id
    await salesperson.save()

    res.json({
      message: "Salesperson assigned to shop successfully",
      salesperson,
    })
  } catch (error) {
    res.status(500).json({ message: "Error assigning salesperson", error: error.message })
  }
}

// Remove salesperson from shop
export const removeSalespersonFromShop = async (req, res) => {
  try {
    const { salespersonId } = req.body

    if (!salespersonId) {
      return res.status(400).json({ message: "Salesperson ID is required" })
    }

    // Only owner can remove salespeople
    if (req.user.role !== "owner") {
      return res.status(403).json({ message: "Not authorized to remove salespeople" })
    }

    const salesperson = await User.findOne({
      where: {
        id: salespersonId,
        businessId: req.user.businessId,
        role: "salesman",
        shopId: req.params.id,
      },
    })

    if (!salesperson) {
      return res.status(404).json({ message: "Salesperson not found in this shop" })
    }

    // Remove shop assignment
    salesperson.shopId = null
    await salesperson.save()

    res.json({
      message: "Salesperson removed from shop successfully",
      salesperson,
    })
  } catch (error) {
    res.status(500).json({ message: "Error removing salesperson", error: error.message })
  }
}

// Get available salespeople (not assigned to any shop)
export const getAvailableSalespeople = async (req, res) => {
  try {
    const salespeople = await User.findAll({
      where: {
        businessId: req.user.businessId,
        role: "salesman",
        shopId: null,
        isActive: true,
      },
      attributes: ["id", "name", "username", "phone"],
    })

    res.json(salespeople)
  } catch (error) {
    res.status(500).json({ message: "Error fetching available salespeople", error: error.message })
  }
} 