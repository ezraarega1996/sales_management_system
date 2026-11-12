import { ItemBought, Item, Fraction, Shop, StockLot, sequelize } from "../models/index.js"
import {
  lockStock,
  addLot,
  recostLot,
  removeUnitsNewestFirst,
  httpError,
  num,
} from "../services/stockLedger.js"

const FRACTION_ATTRS = ["id", "name", "ratio", "sellingPrice", "purchasePrice", "isUnit", "itemId"]
const boughtIncludes = () => [
  { model: Item, attributes: ["id", "name", "categoryId"], include: [{ model: Fraction, as: "fractions", attributes: FRACTION_ATTRS }] },
  { model: Shop, attributes: ["id", "name", "address"] },
]

/** Salesmen only see their own shop's purchases; owners see the business. */
const boughtScope = (req) =>
  req.user.role === "salesman"
    ? { businessId: req.user.businessId, shopId: req.user.shopId ?? null }
    : { businessId: req.user.businessId }

export const getAllBoughts = async (req, res) => {
  try {
    const boughts = await ItemBought.findAll({
      where: boughtScope(req),
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
      where: { id: req.params.id, ...boughtScope(req) },
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


const EPS = 1e-6

/** Validates the numbers of a purchase body; returns an error message or null. */
const invalidNumbers = ({ quantity, fractionPurchasePrice, fractionSoldPrice }, { partial = false } = {}) => {
  const bad = (v, check) => {
    if (partial && v === undefined) return false
    const n = parseFloat(v)
    return isNaN(n) || !check(n)
  }
  if (bad(quantity, (q) => q > 0)) return "Quantity must be more than 0"
  if (bad(fractionPurchasePrice, (p) => p >= 0)) return "Purchase price must be 0 or more"
  if (bad(fractionSoldPrice, (p) => p >= 0)) return "Selling price must be 0 or more"
  return null
}

/** Sends an error from a transaction callback as an HTTP response. */
const sendError = (res, error, what) => {
  if (error.status) return res.status(error.status).json({ message: error.message })
  console.error(`Error ${what}:`, error.message)
  res.status(500).json({ message: `Error ${what}`, error: error.message })
}

/** Finds a unit of an item that belongs to this business. */
const findFraction = (fractionId, itemId, businessId, transaction) =>
  Fraction.findOne({
    where: { id: fractionId, itemId },
    include: [{ model: Item, attributes: ["id"], where: { businessId } }],
    transaction,
  })

const SOLD_ALREADY = "Some of this purchase is already sold"

/**
 * Records a purchase: adds the units to the shop's stock and creates a stock lot at this
 * purchase's cost, which sales will use up first-in, first-out.
 */
export const createBought = async (req, res) => {
  const { itemId, fractionId, fractionPurchasePrice, fractionSoldPrice, quantity, expiryDate, shopId, clientId } = req.body
  const businessId = req.user.businessId
  const invalid = !itemId || !fractionId || !shopId ? "itemId, fractionId and shopId are required" : invalidNumbers(req.body)
  if (invalid) return res.status(400).json({ message: invalid })

  try {
    let repeated = false
    const boughtId = await sequelize.transaction(async (transaction) => {
      // The same save sent again (e.g. the phone timed out and retried): return the first one
      if (clientId) {
        await sequelize.query("SELECT pg_advisory_xact_lock(hashtext(:key))", {
          replacements: { key: `bought:${businessId}:${clientId}` },
          transaction,
        })
        const existing = await ItemBought.findOne({ where: { businessId, clientId: String(clientId) }, transaction })
        if (existing) {
          repeated = true
          return existing.id
        }
      }

      const [shop, fraction] = await Promise.all([
        Shop.findOne({ where: { id: shopId, businessId }, transaction }),
        findFraction(fractionId, itemId, businessId, transaction),
      ])
      if (!shop) throw httpError(404, "Shop not found")
      if (!fraction) throw httpError(404, "Item or unit not found")

      const ratio = num(fraction.ratio) || 1
      const units = num(quantity) * ratio
      const stock = await lockStock({ businessId, shopId, itemId, createIfMissing: true, soldPrice: fractionSoldPrice }, transaction)
      stock.quantity = num(stock.quantity) + units
      stock.soldPrice = fractionSoldPrice
      await stock.save({ transaction })

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
          available_items_count: num(stock.quantity) / ratio,
          availableItemId: stock.id,
          clientId: clientId ? String(clientId) : null,
        },
        { transaction },
      )
      await addLot(
        {
          businessId,
          shopId,
          itemId,
          itemBoughtId: bought.id,
          units,
          unitCost: num(fractionPurchasePrice) / ratio,
          receivedAt: bought.createdTime,
        },
        transaction,
      )
      return bought.id
    })
    res.status(repeated ? 200 : 201).json(await ItemBought.findByPk(boughtId, { include: boughtIncludes() }))
  } catch (error) {
    sendError(res, error, "creating bought item")
  }
}

/**
 * Edits a purchase. Stock changes only by the difference, never below what has already been
 * sold from this purchase. A corrected price also re-costs the sales that used this purchase.
 */
export const updateBought = async (req, res) => {
  const { fractionId, fractionPurchasePrice, fractionSoldPrice, quantity, expiryDate, shopId } = req.body
  const businessId = req.user.businessId
  const invalid = invalidNumbers(req.body, { partial: true })
  if (invalid) return res.status(400).json({ message: invalid })

  try {
    const boughtId = await sequelize.transaction(async (transaction) => {
      const bought = await ItemBought.findOne({ where: { id: req.params.id, businessId }, transaction })
      if (!bought) throw httpError(404, "Bought item not found")

      const newShopId = shopId || bought.shopId
      if (newShopId !== bought.shopId && !(await Shop.findOne({ where: { id: newShopId, businessId }, transaction }))) {
        throw httpError(404, "Shop not found")
      }
      const [oldFraction, newFraction] = await Promise.all([
        Fraction.findByPk(bought.fractionId, { transaction }),
        findFraction(fractionId || bought.fractionId, bought.itemId, businessId, transaction),
      ])
      if (!newFraction) throw httpError(404, "Item or unit not found")

      const oldRatio = num(oldFraction?.ratio) || 1
      const newRatio = num(newFraction.ratio) || 1
      const newQuantity = quantity !== undefined ? num(quantity) : num(bought.quantity)
      const newPurchasePrice =
        fractionPurchasePrice !== undefined ? num(fractionPurchasePrice) : num(bought.fractionPurchasePrice)
      const newSoldPrice = fractionSoldPrice !== undefined ? num(fractionSoldPrice) : num(bought.fractionSoldPrice)
      const oldUnits = num(bought.quantity) * oldRatio
      const newUnits = newQuantity * newRatio
      const newUnitCost = newPurchasePrice / newRatio
      const itemKey = { businessId, itemId: bought.itemId }

      const lot = await StockLot.findOne({ where: { itemBoughtId: bought.id }, lock: transaction.LOCK.UPDATE, transaction })
      const consumed = lot ? num(lot.initialUnits) - num(lot.remainingUnits) : 0

      let stock
      if (newShopId !== bought.shopId) {
        // Moving a purchase to another shop: only while none of it has been sold
        const movedOut = lot ? num(lot.remainingUnits) : oldUnits
        const oldStock = await lockStock({ ...itemKey, shopId: bought.shopId }, transaction)
        if (consumed > EPS || !oldStock || num(oldStock.quantity) < movedOut - EPS) {
          throw httpError(400, `${SOLD_ALREADY}, so its shop can't be changed`)
        }
        oldStock.quantity = num(oldStock.quantity) - movedOut
        await oldStock.save({ transaction })
        if (lot) await lot.destroy({ transaction })
        else await removeUnitsNewestFirst({ ...itemKey, shopId: bought.shopId, units: movedOut }, transaction)

        stock = await lockStock({ ...itemKey, shopId: newShopId, createIfMissing: true, soldPrice: newSoldPrice }, transaction)
        stock.quantity = num(stock.quantity) + newUnits
        await addLot(
          {
            ...itemKey,
            shopId: newShopId,
            itemBoughtId: bought.id,
            units: newUnits,
            unitCost: newUnitCost,
            receivedAt: bought.createdTime,
          },
          transaction,
        )
      } else {
        stock = await lockStock({ ...itemKey, shopId: bought.shopId, createIfMissing: true, soldPrice: newSoldPrice }, transaction)
        const delta = newUnits - oldUnits
        if (lot) {
          if (newUnits < consumed - EPS) throw httpError(400, `${SOLD_ALREADY}: the quantity can't go below that`)
          lot.initialUnits = newUnits
          lot.remainingUnits = newUnits - consumed
          await lot.save({ transaction })
          if (Math.abs(newUnitCost - num(lot.unitCost)) > 1e-9) await recostLot(lot, newUnitCost, transaction)
        } else if (delta > EPS) {
          // Purchase recorded before cost tracking: the extra units become a new lot at its price
          await addLot(
            { ...itemKey, shopId: bought.shopId, units: delta, unitCost: newUnitCost, receivedAt: bought.createdTime },
            transaction,
          )
        } else if (delta < -EPS) {
          if (num(stock.quantity) < -delta - EPS) throw httpError(400, `${SOLD_ALREADY}: the quantity can't go below that`)
          await removeUnitsNewestFirst({ ...itemKey, shopId: bought.shopId, units: -delta }, transaction)
        }
        stock.quantity = num(stock.quantity) + delta
      }
      stock.soldPrice = newSoldPrice
      await stock.save({ transaction })

      await bought.update(
        {
          fractionId: newFraction.id,
          fractionPurchasePrice: newPurchasePrice,
          fractionSoldPrice: newSoldPrice,
          quantity: newQuantity,
          expiryDate: expiryDate || bought.expiryDate,
          shopId: newShopId,
          available_items_count: num(stock.quantity) / newRatio,
          availableItemId: stock.id,
        },
        { transaction },
      )
      return bought.id
    })
    res.json(await ItemBought.findByPk(boughtId, { include: boughtIncludes() }))
  } catch (error) {
    sendError(res, error, "updating bought item")
  }
}

/** Deletes a purchase and takes its units out of stock, only if none of it has been sold. */
export const deleteBought = async (req, res) => {
  const businessId = req.user.businessId
  try {
    await sequelize.transaction(async (transaction) => {
      const bought = await ItemBought.findOne({ where: { id: req.params.id, businessId }, transaction })
      if (!bought) throw httpError(404, "Bought item not found")

      const fraction = await Fraction.findByPk(bought.fractionId, { transaction })
      const units = num(bought.quantity) * (num(fraction?.ratio) || 1)
      const key = { businessId, shopId: bought.shopId, itemId: bought.itemId }
      const stock = await lockStock(key, transaction)
      const lot = await StockLot.findOne({ where: { itemBoughtId: bought.id }, lock: transaction.LOCK.UPDATE, transaction })

      const soldMessage = `${SOLD_ALREADY}, so it can't be deleted. Reduce the quantity instead.`
      let removed = units
      if (lot) {
        if (num(lot.initialUnits) - num(lot.remainingUnits) > EPS) throw httpError(400, soldMessage)
        removed = num(lot.remainingUnits)
        await lot.destroy({ transaction })
      } else {
        // Recorded before cost tracking: the stock must still hold all of it
        if (!stock || num(stock.quantity) < units - EPS) throw httpError(400, soldMessage)
        await removeUnitsNewestFirst({ ...key, units }, transaction)
      }
      if (stock) {
        stock.quantity = Math.max(0, num(stock.quantity) - removed)
        await stock.save({ transaction })
      }
      await bought.destroy({ transaction })
    })
    res.json({ message: "Bought item deleted successfully" })
  } catch (error) {
    sendError(res, error, "deleting bought item")
  }
}
