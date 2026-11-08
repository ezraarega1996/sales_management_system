import { Item, Category, Fraction } from "../models/index.js"
import { fn, col } from "sequelize"

export const getAllItems = async (req, res) => {
  try {
    const items = await Item.findAll({
      where: { businessId: req.user.businessId },
      include: [{ model: Category }, { model: Fraction, as: "fractions" }],
      order: [[fn('LOWER', col('Item.name')), 'ASC']],
    })
    res.json(items)
  } catch (error) {
    console.log("errr in listing items: ", error)
    res.status(500).json({ message: "Error fetching items", error: error.message })
  }
}

export const getItemById = async (req, res) => {
  try {
    const item = await Item.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
      include: [{ model: Category }, { model: Fraction, as: "fractions" }],
    })

    if (!item) {
      return res.status(404).json({ message: "Item not found" })
    }

    res.json(item)
  } catch (error) {
    res.status(500).json({ message: "Error fetching item", error: error.message })
  }
}

export const createItem = async (req, res) => {
  try {
    const { name, categoryId, fractions } = req.body

    // Check if category exists and belongs to the business
    const category = await Category.findOne({
      where: {
        id: categoryId,
        businessId: req.user.businessId,
      },
    })

    if (!category) {
      return res.status(404).json({ message: "Category not found" })
    }

    // Create item
    const item = await Item.create({
      name,
      categoryId,
      businessId: req.user.businessId,
    })

    // Create fractions if providede
    // if (fractions && Array.isArray(fractions)) {
    //   const fractionPromises = fractions.map((fraction) => {
    //     const sellingPrice = fraction.sellingPrice ?? fraction.price ?? 0
    //     const purchasePrice = fraction.purchasePrice ?? 0
    //     return Fraction.create({
    //       name: fraction.name,
    //       ratio: fraction.ratio,
    //       sellingPrice,
    //       purchasePrice,
    //       isUnit: fraction.isUnit ?? false,
    //       itemId: item.id,
    //       businessId: req.user.businessId,
    //     })
    //   })
    //   await Promise.all(fractionPromises)
    // }

    // Fetch the created item with its fractions
    const createdItem = await Item.findByPk(item.id, {
      include: [{ model: Category }, { model: Fraction, as: "fractions" }],
    })

    res.status(201).json(createdItem)
  } catch (error) {
    res.status(500).json({ message: "Error creating item", error: error.message })
  }
}

export const updateItem = async (req, res) => {
  try {
    const { name, categoryId } = req.body
    const item = await Item.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
    })

    if (!item) {
      return res.status(404).json({ message: "Item not found" })
    }

    // Check if category exists and belongs to the business if categoryId is provided
    if (categoryId) {
      const category = await Category.findOne({
        where: {
          id: categoryId,
          businessId: req.user.businessId,
        },
      })

      if (!category) {
        return res.status(404).json({ message: "Category not found" })
      }
    }

    // Update item
    item.name = name || item.name
    item.categoryId = categoryId || item.categoryId
    await item.save()

    // Fetch the updated item with its fractions
    const updatedItem = await Item.findByPk(item.id, {
      include: [{ model: Category }, { model: Fraction, as: "fractions" }],
    })

    res.json(updatedItem)
  } catch (error) {
    res.status(500).json({ message: "Error updating item", error: error.message })
  }
}

export const deleteItem = async (req, res) => {
  try {
    const item = await Item.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
    })

    if (!item) {
      return res.status(404).json({ message: "Item not found" })
    }

    await item.destroy()

    res.json({ message: "Item deleted successfully" })
  } catch (error) {
    res.status(500).json({ message: "Error deleting item", error: error.message })
  }
}
