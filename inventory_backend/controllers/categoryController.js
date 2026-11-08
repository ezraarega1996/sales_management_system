import { Category } from "../models/index.js"

export const getAllCategories = async (req, res) => {
  try {
    // Filter categories by business ID
    const categories = await Category.findAll({
      where: { businessId: req.user.businessId },
    })
    res.json(categories)
  } catch (error) {
    console.log("errr in listing categoris: ", error)
    res.status(500).json({ message: "Error fetching categories", error: error.message })
  }
}

export const getCategoryById = async (req, res) => {
  try {
    const category = await Category.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
    })

    if (!category) {
      return res.status(404).json({ message: "Category not found" })
    }

    res.json(category)
  } catch (error) {
    res.status(500).json({ message: "Error fetching category", error: error.message })
  }
}

export const createCategory = async (req, res) => {
  try {
    const { name } = req.body

    const category = await Category.create({
      name,
      businessId: req.user.businessId,
    })

    res.status(201).json(category)
  } catch (error) {
    res.status(500).json({ message: "Error creating category", error: error.message })
  }
}

export const updateCategory = async (req, res) => {
  try {
    const { name } = req.body
    const category = await Category.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
    })

    if (!category) {
      return res.status(404).json({ message: "Category not found" })
    }

    category.name = name
    await category.save()

    res.json(category)
  } catch (error) {
    res.status(500).json({ message: "Error updating category", error: error.message })
  }
}

export const deleteCategory = async (req, res) => {
  try {
    const category = await Category.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
    })

    if (!category) {
      return res.status(404).json({ message: "Category not found" })
    }

    await category.destroy()

    res.json({ message: "Category deleted successfully" })
  } catch (error) {
    res.status(500).json({ message: "Error deleting category", error: error.message })
  }
}
