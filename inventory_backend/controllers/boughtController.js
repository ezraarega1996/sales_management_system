import { ItemBought, Item, Fraction, AvailableItem, Shop, sequelize } from "../models/index.js"

const FRACTION_ATTRS = ["id", "name", "ratio", "sellingPrice", "purchasePrice", "isUnit", "itemId"]
const boughtIncludes = () => [
  { model: Item, attributes: ["id", "name", "categoryId"], include: [{ model: Fraction, as: "fractions", attributes: FRACTION_ATTRS }] },
  { model: Shop, attributes: ["id", "name", "address"] },
]

export const getAllBoughts = async (req, res) => {
  try {
    const boughts = await ItemBought.findAll({
      where: { businessId: req.user.businessId },
      include: boughtIncludes(),
      order: [["createdTime", "DESC"]],
    })
    res.json(boughts)
  } catch (error) {
    console.error("Error fetching bought items:", error.message)
    res.status(500).json({ message: "Error fetching bought items", error: error.message })
  }
}

export const getBoughtById = async (req, res) => {
  try {
    const bought = await ItemBought.findOne({
      where: { id: req.params.id, businessId: req.user.businessId },
      include: boughtIncludes(),
    })
    if (!bought) {
      return res.status(404).json({ message: "Bought item not found" })
    }
    res.json(bought)
  } catch (error) {
    res.status(500).json({ message: "Error fetching bought item", error: error.message })
  }
}

/** Adds `quantityInUnits` to the shop's stock row for the item, creating it if needed. */
const addToStock = async ({ itemId, businessId, shopId, quantityInUnits, soldPrice }, transaction) => {
  const existing = await AvailableItem.findOne({ where: { itemId, businessId, shopId }, transaction })
  if (existing) {
    existing.quantity = quantityInUnits + parseFloat(existing.quantity)
    existing.soldPrice = soldPrice
    return existing.save({ transaction })
  }
  return AvailableItem.create({ itemId, businessId, shopId, quantity: quantityInUnits, soldPrice }, { transaction })
}

/** Removes a purchase's quantity from its stock row (deleting the row when it reaches 0). */
const removeFromStock = async (bought, ratio, transaction) => {
  if (!bought.availableItemId) return
  const availableItem = await AvailableItem.findByPk(bought.availableItemId, { transaction })
  if (!availableItem) return
  availableItem.quantity = parseFloat(availableItem.quantity) - bought.quantity * ratio
  if (availableItem.quantity <= 0) {
    await availableItem.destroy({ transaction })
  } else {
    await availableItem.save({ transaction })
  }
}

export const createBought = async (req, res) => {
  const { itemId, fractionId, fractionPurchasePrice, fractionSoldPrice, quantity, expiryDate, shopId } = req.body
  const businessId = req.user.businessId
  const transaction = await sequelize.transaction()
  try {
    const [item, shop, fraction] = await Promise.all([
      Item.findOne({ where: { id: itemId, businessId }, transaction }),
      Shop.findOne({ where: { id: shopId, businessId }, transaction }),
      Fraction.findOne({ where: { id: fractionId }, transaction }),
    ])
    if (!item || !shop || !fraction) {
      await transaction.rollback()
      const missing = !item ? "Item" : !shop ? "Shop" : "Fraction"
      return res.status(404).json({ message: `${missing} not found` })
    }

    const availableItem = await addToStock(
      { itemId, businessId, shopId, quantityInUnits: quantity * fraction.ratio, soldPrice: fractionSoldPrice },
      transaction,
    )

    const bought = await ItemBought.create(
      {
        itemId,
        fractionId,
        fractionPurchasePrice,
        fractionSoldPrice,
        quantity,
        expiryDate: expiryDate || null,
        businessId,
        shopId,
        available_items_count: availableItem.quantity / fraction.ratio,
        availableItemId: availableItem.id,
      },
      { transaction },
    )

    await transaction.commit()
    res.status(201).json(await ItemBought.findByPk(bought.id, { include: boughtIncludes() }))
  } catch (error) {
    await transaction.rollback()
    console.error("Error creating bought item:", error.message)
    res.status(500).json({ message: "Error creating bought item", error: error.message })
  }
}

export const updateBought = async (req, res) => {
  const { fractionId, fractionPurchasePrice, fractionSoldPrice, quantity, expiryDate, shopId } = req.body
  const businessId = req.user.businessId
  const transaction = await sequelize.transaction()
  try {
    const bought = await ItemBought.findOne({ where: { id: req.params.id, businessId }, transaction })
    if (!bought) {
      await transaction.rollback()
      return res.status(404).json({ message: "Bought item not found" })
    }

    if (shopId) {
      const shop = await Shop.findOne({ where: { id: shopId, businessId }, transaction })
      if (!shop) {
        await transaction.rollback()
        return res.status(404).json({ message: "Shop not found" })
      }
    }

    const [oldFraction, newFraction] = await Promise.all([
      Fraction.findByPk(bought.fractionId, { transaction }),
      Fraction.findByPk(fractionId || bought.fractionId, { transaction }),
    ])
    if (!newFraction) {
      await transaction.rollback()
      return res.status(404).json({ message: "Fraction not found" })
    }

    // Take the old purchase out of stock (using the fraction it was recorded with), then add the new one
    await removeFromStock(bought, oldFraction?.ratio ?? newFraction.ratio, transaction)

    const newShopId = shopId || bought.shopId
    const newQuantity = quantity || bought.quantity
    const newSoldPrice = fractionSoldPrice || bought.fractionSoldPrice
    const availableItem = await addToStock(
      { itemId: bought.itemId, businessId, shopId: newShopId, quantityInUnits: newQuantity * newFraction.ratio, soldPrice: newSoldPrice },
      transaction,
    )

    await bought.update(
      {
        fractionId: newFraction.id,
        fractionPurchasePrice: fractionPurchasePrice || bought.fractionPurchasePrice,
        fractionSoldPrice: newSoldPrice,
        quantity: newQuantity,
        expiryDate: expiryDate || bought.expiryDate,
        shopId: newShopId,
        available_items_count: availableItem.quantity / newFraction.ratio,
        availableItemId: availableItem.id,
      },
      { transaction },
    )

    await transaction.commit()
    res.json(await ItemBought.findByPk(bought.id, { include: boughtIncludes() }))
  } catch (error) {
    await transaction.rollback()
    console.error("Error updating bought item:", error.message)
    res.status(500).json({ message: "Error updating bought item", error: error.message })
  }
}

export const deleteBought = async (req, res) => {
  const transaction = await sequelize.transaction()
  try {
    const bought = await ItemBought.findOne({
      where: { id: req.params.id, businessId: req.user.businessId },
      transaction,
    })
    if (!bought) {
      await transaction.rollback()
      return res.status(404).json({ message: "Bought item not found" })
    }

    const fraction = await Fraction.findByPk(bought.fractionId, { transaction })
    if (fraction) await removeFromStock(bought, fraction.ratio, transaction)

    await bought.destroy({ transaction })
    await transaction.commit()
    res.json({ message: "Bought item deleted successfully" })
  } catch (error) {
    await transaction.rollback()
    res.status(500).json({ message: "Error deleting bought item", error: error.message })
  }
}
