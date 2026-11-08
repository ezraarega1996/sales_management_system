import { Fraction, Item } from "../models/index.js"
import { Op } from "sequelize"

export const getAllFractions = async (req, res) => {
  try {
    const fractions = await Fraction.findAll({
      where: { businessId: req.user.businessId },
      include: [{ model: Item }],
    })
    res.json(fractions)
  } catch (error) {
    console.log("errr in listing fractions: ", error)
    res.status(500).json({ message: "Error fetching fractions", error: error.message })
  }
}

export const getFractionById = async (req, res) => {
  try {
    const fraction = await Fraction.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
      include: [{ model: Item }],
    })

    if (!fraction) {
      return res.status(404).json({ message: "Fraction not found" })
    }

    res.json(fraction)
  } catch (error) {
    res.status(500).json({ message: "Error fetching fraction", error: error.message })
  }
}

export const createFraction = async (req, res) => {
  try {
    const { name, ratio, sellingPrice, purchasePrice, itemId, isUnit } = req.body

    // Check if item exists and belongs to the business
    const item = await Item.findOne({
      where: {
        id: itemId,
        businessId: req.user.businessId,
      },
    })

    if (!item) {
      return res.status(404).json({ message: "Item not found" })
    }

    // If trying to create a unit fraction, check if there's already a unit fraction
    if (isUnit) {
      const existingUnitFraction = await Fraction.findOne({
        where: {
          itemId,
          isUnit: true,
          businessId: req.user.businessId,
        },
      })

      if (existingUnitFraction) {
        return res.status(400).json({ 
          message: "An item can only have one unit fraction. Please unmark the existing unit fraction first." 
        })
      }
    }

    // Create fraction
    const fraction = await Fraction.create({
      name,
      ratio,
      sellingPrice,
      purchasePrice,
      itemId,
      businessId: req.user.businessId,
      isUnit: isUnit ?? false,
    })

    // Fetch the created fraction with its item
    const createdFraction = await Fraction.findByPk(fraction.id, {
      include: [{ model: Item }],
    })

    res.status(201).json(createdFraction)
  } catch (error) {
    res.status(500).json({ message: "Error creating fraction", error: error.message })
  }
}

export const updateFraction = async (req, res) => {
  try {
    const { name, ratio, sellingPrice, purchasePrice, isUnit } = req.body
    const fraction = await Fraction.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
    })

    if (!fraction) {
      return res.status(404).json({ message: "Fraction not found" })
    }

    // If trying to make this fraction a unit, check if there's already a unit fraction
    if (isUnit && !fraction.isUnit) {
      const existingUnitFraction = await Fraction.findOne({
        where: {
          itemId: fraction.itemId,
          isUnit: true,
          businessId: req.user.businessId,
          id: { [Op.ne]: fraction.id }, // Exclude current fraction
        },
      })

      if (existingUnitFraction) {
        return res.status(400).json({ 
          message: "An item can only have one unit fraction. Please unmark the existing unit fraction first." 
        })
      }
    }

    // Update fraction
    fraction.name = name || fraction.name
    fraction.ratio = ratio || fraction.ratio
    fraction.sellingPrice = sellingPrice ?? fraction.sellingPrice
    fraction.purchasePrice = purchasePrice ?? fraction.purchasePrice
    fraction.isUnit = isUnit ?? fraction.isUnit
    await fraction.save()

    // Fetch the updated fraction with its item
    const updatedFraction = await Fraction.findByPk(fraction.id, {
      include: [{ model: Item }],
    })

    res.json(updatedFraction)
  } catch (error) {
    res.status(500).json({ message: "Error updating fraction", error: error.message })
  }
}

export const deleteFraction = async (req, res) => {
  try {
    const fraction = await Fraction.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
    })

    if (!fraction) {
      return res.status(404).json({ message: "Fraction not found" })
    }

    await fraction.destroy()

    res.json({ message: "Fraction deleted successfully" })
  } catch (error) {
    res.status(500).json({ message: "Error deleting fraction", error: error.message })
  }
}
