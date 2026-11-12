import { SoldItem, Item, User, Fraction, AvailableItem, Shop, sequelize } from "../models/index.js"
import { Op } from "sequelize"
import {
  lockStock,
  consumeFifo,
  saveAllocations,
  returnSalesToStock,
  allocatedCost,
  num,
  round2,
} from "../services/stockLedger.js"

const DAY_MS = 24 * 60 * 60 * 1000

// Only the fields the app actually reads, to keep responses small on slow networks
const FRACTION_ATTRS = ["id", "name", "ratio", "sellingPrice", "purchasePrice", "isUnit", "itemId"]
const saleIncludes = () => [
  { model: Item, attributes: ["id", "name", "categoryId"], include: [{ model: Fraction, as: "fractions", attributes: FRACTION_ATTRS }] },
  { model: User, as: "salesman", attributes: ["id", "name", "username"] },
]

export const getAllSales = async (req, res) => {
  try {
    const sales = await SoldItem.findAll({
      where: salesScope(req),
      include: saleIncludes(),
      order: [["soldTime", "DESC"]],
    })
    res.json(sales)
  } catch (error) {
    console.error("Error fetching sales:", error.message)
    res.status(500).json({ message: "Error fetching sales", error: error.message })
  }
}

export const getSaleById = async (req, res) => {
  try {
    const sale = await SoldItem.findOne({
      where: { id: req.params.id, ...salesScope(req) },
      include: saleIncludes(),
    })
    if (!sale) {
      return res.status(404).json({ message: "Sale not found" })
    }
    res.json(sale)
  } catch (error) {
    res.status(500).json({ message: "Error fetching sale", error: error.message })
  }
}

/**
 * Records a sale. Safe to retry: when the app sends a `clientId` (generated on the phone, also for
 * sales queued while offline) and a sale with that id already exists, the existing sale is returned
 * and stock is not decremented again.
 */
/** What [quantity] of [fraction] costs at the catalogue (normal) selling price. */
const catalogueAmount = (fraction, quantity) => round2(parseFloat(fraction.sellingPrice || 0) * quantity)

/** Profit = the price actually charged minus what the sold units cost (FIFO, see stockLedger). */
const saleProfit = (amount, cost) => round2(num(amount) - cost)

export const createSale = async (req, res) => {
  const { itemId, fractionId, quantity, amount, shopId, clientId, soldTime } = req.body
  // Salesmen always sell from their own shop; owners choose the shop
  const selectedShopId = req.user.role === "salesman" ? req.user.shopId : shopId || req.user.shopId

  if (!selectedShopId) {
    return res.status(400).json({ message: "shopId is required to create a sale" })
  }
  // amount may be 0 (given away), but not missing or negative
  if (!itemId || !fractionId || !(quantity > 0) || !(amount >= 0)) {
    return res.status(400).json({ message: "All fields are required" })
  }

  try {
    if (clientId) {
      const existing = await SoldItem.findOne({ where: { clientId, businessId: req.user.businessId } })
      if (existing) return res.status(200).json(existing)
    }

    // The unit must belong to this item and to this business
    const fraction = await Fraction.findOne({
      where: { id: fractionId, itemId },
      include: [{ model: Item, attributes: ["id"], where: { businessId: req.user.businessId } }],
    })
    if (!fraction) {
      return res.status(404).json({ message: "Fraction not found" })
    }
    const quantityInUnits = quantity * fraction.ratio

    // Time the sale actually happened (may be earlier when it was queued offline), never in the future
    const parsed = soldTime ? new Date(soldTime) : null
    const saleTime = parsed && !isNaN(parsed) && parsed <= new Date() ? parsed : new Date()

    const sale = await sequelize.transaction(async (transaction) => {
      // Lock the stock row so two concurrent sales can't both pass the quantity check
      const stockKey = { businessId: req.user.businessId, shopId: selectedShopId, itemId }
      const availableItem = await lockStock(stockKey, transaction)
      if (!availableItem) {
        throw Object.assign(new Error("No available items found for this item"), { status: 400 })
      }
      if (parseFloat(availableItem.quantity) < quantityInUnits) {
        throw Object.assign(new Error("Not enough quantity available"), { status: 400 })
      }

      availableItem.quantity = parseFloat(availableItem.quantity) - quantityInUnits
      await availableItem.save({ transaction })
      // Cost of the units sold, oldest purchases first
      const { cost, parts } = await consumeFifo({ ...stockKey, units: quantityInUnits }, transaction)

      const created = await SoldItem.create(
        {
          itemId,
          fractionId,
          quantity,
          amount,
          // The catalogue price, so a price changed at the counter is visible to the owner
          expectedAmount: catalogueAmount(fraction, quantity),
          salesmanId: req.user.id,
          businessId: req.user.businessId,
          available_items_count: availableItem.quantity / fraction.ratio,
          availableItemId: availableItem.id,
          shopId: selectedShopId,
          // Worked out here from the price actually charged and the FIFO cost, not trusted from the phone
          profit: saleProfit(amount, cost),
          clientId: clientId || null,
          soldTime: saleTime,
          createdTime: saleTime,
        },
        { transaction },
      )
      await saveAllocations(created.id, parts, transaction)
      return created
    })

    res.status(201).json(sale)
  } catch (error) {
    if (error.status) {
      return res.status(error.status).json({ message: error.message })
    }
    // A retry raced with the original request: the unique clientId already exists
    if (error.name === "SequelizeUniqueConstraintError" && clientId) {
      const existing = await SoldItem.findOne({ where: { clientId, businessId: req.user.businessId } })
      if (existing) return res.status(200).json(existing)
    }
    console.error("Error creating sale:", error.message)
    res.status(500).json({ message: "Error creating sale", error: error.message })
  }
}

/** Salesmen only see their own shop's sales (for the shop summary); owners see the business. */
const salesScope = (req) =>
  req.user.role === "salesman"
    ? { businessId: req.user.businessId, shopId: req.user.shopId ?? null }
    : { businessId: req.user.businessId }

const UNDO_WINDOW_MS = 10 * 60 * 1000

/**
 * Records a basket (several items sold to one customer) as one receipt, all or nothing.
 * Body: { clientId, soldTime?, shopId?, lines: [{ itemId, fractionId, quantity, amount, profit? }] }
 * `clientId` becomes the receiptId of every line and makes retries safe: resending the same basket
 * returns the already-recorded lines without touching stock again.
 */
export const createBatchSale = async (req, res) => {
  const { clientId, soldTime, shopId, lines } = req.body
  const businessId = req.user.businessId
  // Salesmen always sell from their own shop; owners choose the shop
  const selectedShopId = req.user.role === "salesman" ? req.user.shopId : shopId || req.user.shopId

  if (!clientId) return res.status(400).json({ message: "clientId is required" })
  if (!selectedShopId) return res.status(400).json({ message: "shopId is required to create a sale" })
  if (!Array.isArray(lines) || lines.length === 0) return res.status(400).json({ message: "The basket is empty" })
  if (lines.some((l) => !l.itemId || !l.fractionId || !(l.quantity > 0) || !(l.amount >= 0))) {
    return res.status(400).json({ message: "Every line needs itemId, fractionId, quantity and amount" })
  }

  const parsed = soldTime ? new Date(soldTime) : null
  const saleTime = parsed && !isNaN(parsed) && parsed <= new Date() ? parsed : new Date()
  const findReceipt = (transaction) =>
    SoldItem.findAll({ where: { receiptId: clientId, businessId }, include: saleIncludes(), transaction, order: [["id", "ASC"]] })

  try {
    const result = await sequelize.transaction(async (transaction) => {
      // Serialize requests for the same basket so a retry racing the original can't record it twice
      await sequelize.query("SELECT pg_advisory_xact_lock(hashtext(:key))", { replacements: { key: clientId }, transaction })
      const existing = await findReceipt(transaction)
      if (existing.length) return { created: false, sales: existing }

      const fractions = await Fraction.findAll({
        where: { id: [...new Set(lines.map((l) => l.fractionId))] },
        include: [{ model: Item, attributes: ["id", "name", "businessId"] }],
        transaction,
      })
      const fractionById = new Map(fractions.map((f) => [f.id, f]))

      for (const line of lines) {
        const fraction = fractionById.get(line.fractionId)
        if (!fraction || fraction.itemId !== line.itemId || fraction.Item?.businessId !== businessId) {
          throw Object.assign(new Error("Item or unit not found"), { status: 404 })
        }
      }

      // Lock each stock row once (even if several lines sell the same item in different units), in a
      // fixed order so two baskets with the same items can't deadlock each other
      const stockByItem = new Map()
      for (const itemId of [...new Set(lines.map((l) => l.itemId))].sort()) {
        const stock = await lockStock({ businessId, shopId: selectedShopId, itemId }, transaction)
        if (!stock) {
          const name = fractionById.get(lines.find((l) => l.itemId === itemId).fractionId).Item.name
          throw Object.assign(new Error(`${name} is not stocked in this shop`), { status: 400 })
        }
        stockByItem.set(itemId, stock)
      }

      for (const line of lines) {
        const fraction = fractionById.get(line.fractionId)
        const stock = stockByItem.get(line.itemId)
        const units = line.quantity * fraction.ratio
        if (parseFloat(stock.quantity) < units - 1e-9) {
          throw Object.assign(new Error(`Not enough ${fraction.Item.name} in stock`), { status: 400 })
        }
        stock.quantity = parseFloat(stock.quantity) - units
        line._stock = stock
        line._ratio = fraction.ratio
        line._fraction = fraction
        // Lines of the same item take from the lots in turn, oldest purchases first
        line._cost = await consumeFifo({ businessId, shopId: selectedShopId, itemId: line.itemId, units }, transaction)
      }

      for (const stock of stockByItem.values()) await stock.save({ transaction })

      for (const line of lines) {
        const created = await SoldItem.create(
          {
            itemId: line.itemId,
            fractionId: line.fractionId,
            quantity: line.quantity,
            amount: line.amount,
            // The catalogue price, so a price changed at the counter is visible to the owner
            expectedAmount: catalogueAmount(line._fraction, line.quantity),
            // Worked out here from the price actually charged and the FIFO cost, not trusted from the phone
            profit: saleProfit(line.amount, line._cost.cost),
            salesmanId: req.user.id,
            businessId,
            shopId: selectedShopId,
            availableItemId: line._stock.id,
            available_items_count: parseFloat(line._stock.quantity) / line._ratio,
            receiptId: clientId,
            soldTime: saleTime,
            createdTime: saleTime,
          },
          { transaction },
        )
        await saveAllocations(created.id, line._cost.parts, transaction)
      }
      return { created: true, sales: await findReceipt(transaction) }
    })

    res.status(result.created ? 201 : 200).json(result.sales)
  } catch (error) {
    if (error.status) return res.status(error.status).json({ message: error.message })
    console.error("Error creating basket sale:", error.message)
    res.status(500).json({ message: "Error creating sale", error: error.message })
  }
}

/**
 * Cancels a receipt and puts its stock back. Salesmen may undo their own receipt for 10 minutes
 * (e.g. a mistake at the counter); owners and admins at any time.
 */
export const undoReceipt = async (req, res) => {
  const { receiptId } = req.params
  try {
    const restored = await sequelize.transaction(async (transaction) => {
      const sales = await SoldItem.findAll({ where: { receiptId, businessId: req.user.businessId }, transaction })
      if (!sales.length) throw Object.assign(new Error("Receipt not found"), { status: 404 })

      if (req.user.role === "salesman") {
        const ownSales = sales.every((s) => s.salesmanId === req.user.id)
        const recent = sales.every((s) => Date.now() - new Date(s.createdAt).getTime() <= UNDO_WINDOW_MS)
        if (!ownSales || !recent) {
          throw Object.assign(new Error("This sale can no longer be undone. Ask the owner."), { status: 403 })
        }
      }

      // Units go back into stock and into the exact purchase lots they came from
      await returnSalesToStock(sales, transaction)
      await SoldItem.destroy({ where: { receiptId, businessId: req.user.businessId }, transaction })
      return sales.length
    })
    res.json({ message: "Sale undone", restoredLines: restored })
  } catch (error) {
    if (error.status) return res.status(error.status).json({ message: error.message })
    console.error("Error undoing receipt:", error.message)
    res.status(500).json({ message: "Error undoing sale", error: error.message })
  }
}

export const updateSale = async (req, res) => {
  try {
    const { quantity, amount, expectedAmount, status, existing } = req.body
    if (quantity !== undefined) {
      return res.status(400).json({ message: "The quantity of a sale can't be changed. Delete the sale and sell again." })
    }
    if (amount !== undefined && !(parseFloat(amount) >= 0)) {
      return res.status(400).json({ message: "Amount must be 0 or more" })
    }

    const sale = await SoldItem.findOne({
      where: { id: req.params.id, businessId: req.user.businessId },
    })
    if (!sale) {
      return res.status(404).json({ message: "Sale not found" })
    }
    if (req.user.role !== "owner" && req.user.role !== "admin" && sale.salesmanId !== req.user.id) {
      return res.status(403).json({ message: "Not authorized to update this sale" })
    }

    if (amount !== undefined) {
      // Keep profit consistent with the new price: price minus the recorded cost of the units
      const cost = await allocatedCost(sale.id)
      if (cost != null) sale.profit = saleProfit(amount, cost)
      else if (sale.profit != null) sale.profit = round2(num(sale.profit) + num(amount) - num(sale.amount))
      sale.amount = amount
    }
    if (expectedAmount !== undefined) sale.expectedAmount = expectedAmount
    if (status !== undefined) sale.status = status
    if (existing !== undefined) sale.existing = existing
    await sale.save()

    res.json(await SoldItem.findByPk(sale.id, { include: saleIncludes() }))
  } catch (error) {
    res.status(500).json({ message: "Error updating sale", error: error.message })
  }
}

export const deleteSale = async (req, res) => {
  try {
    const sale = await SoldItem.findOne({
      where: { id: req.params.id, businessId: req.user.businessId },
    })
    if (!sale) {
      return res.status(404).json({ message: "Sale not found" })
    }
    if (req.user.role !== "owner" && req.user.role !== "admin") {
      return res.status(403).json({ message: "Not authorized to delete sales" })
    }
    await sequelize.transaction(async (transaction) => {
      // Deleting a sale cancels it: its units go back into stock and into their purchase lots
      await returnSalesToStock([sale], transaction)
      await sale.destroy({ transaction })
    })
    res.json({ message: "Sale deleted successfully" })
  } catch (error) {
    res.status(500).json({ message: "Error deleting sale", error: error.message })
  }
}

export const getSalesByUser = async (req, res) => {
  try {
    const sales = await SoldItem.findAll({
      where: { salesmanId: req.user.id, businessId: req.user.businessId },
      include: saleIncludes(),
      order: [["soldTime", "DESC"]],
    })
    res.json(sales)
  } catch (error) {
    res.status(500).json({ message: "Error fetching sales", error: error.message })
  }
}

/**
 * Dashboard numbers. Owners/admins see the whole business; a salesman sees only their own sales
 * and their shop's stock, without profit figures (purchase prices are owner-only).
 */
export const getDashboardStats = async (req, res) => {
  try {
    const businessId = req.user.businessId
    const isSalesman = req.user.role === "salesman"
    const salesWhere = isSalesman ? { businessId, salesmanId: req.user.id } : { businessId }
    const stockWhere = isSalesman ? { businessId, shopId: req.user.shopId ?? null } : { businessId }
    const startOfToday = new Date()
    startOfToday.setHours(0, 0, 0, 0)
    const last30Days = new Date(Date.now() - 30 * DAY_MS)
    const todayWhere = { ...salesWhere, soldTime: { [Op.gte]: startOfToday } }

    // All queries are independent, so run them in parallel
    const [
      totalSales,
      todaySales,
      salesCount,
      totalProfit,
      todayProfit,
      todayCount,
      salesByDay,
      topItems,
      salesByShopRows,
      stockRows,
    ] = await Promise.all([
      SoldItem.sum("amount", { where: salesWhere }),
      SoldItem.sum("amount", { where: todayWhere }),
      SoldItem.count({ where: salesWhere }),
      isSalesman ? null : SoldItem.sum("profit", { where: salesWhere }),
      isSalesman ? null : SoldItem.sum("profit", { where: todayWhere }),
      SoldItem.count({ where: todayWhere }),
      SoldItem.findAll({
        attributes: [
          [sequelize.fn("date", sequelize.col("soldTime")), "date"],
          [sequelize.fn("sum", sequelize.col("amount")), "total"],
        ],
        where: { ...salesWhere, soldTime: { [Op.gte]: last30Days } },
        group: [sequelize.fn("date", sequelize.col("soldTime"))],
        order: [[sequelize.fn("date", sequelize.col("soldTime")), "ASC"]],
      }),
      SoldItem.findAll({
        attributes: [
          "itemId",
          [sequelize.fn("sum", sequelize.col("quantity")), "totalQuantity"],
          [sequelize.fn("sum", sequelize.col("amount")), "totalAmount"],
        ],
        where: salesWhere,
        include: [{ model: Item, attributes: ["name"] }],
        group: ["itemId", "Item.id", "Item.name"],
        order: [[sequelize.fn("sum", sequelize.col("amount")), "DESC"]],
        limit: 5,
      }),
      // Per-shop breakdown is an owner view
      isSalesman
        ? []
        : SoldItem.findAll({
        attributes: [
          "shopId",
          [sequelize.fn("sum", sequelize.col("amount")), "total"],
          [sequelize.fn("count", sequelize.col("SoldItem.id")), "count"],
        ],
        where: { businessId, shopId: { [Op.ne]: null }, soldTime: { [Op.gte]: last30Days } },
        include: [{ model: Shop, attributes: ["name"] }],
        group: ["shopId", "Shop.id", "Shop.name"],
        order: [[sequelize.fn("sum", sequelize.col("amount")), "DESC"]],
      }),
      // Items with the least stock left
      AvailableItem.findAll({
        where: stockWhere,
        include: [
          { model: Item, as: "item", attributes: ["name"], include: [{ model: Fraction, as: "fractions", attributes: FRACTION_ATTRS }] },
          { model: Shop, as: "shop", attributes: ["name"] },
        ],
        order: [["quantity", "ASC"]],
        limit: 6,
      }),
    ])

    const salesByShop = salesByShopRows.map((r) => ({
      shopId: r.shopId,
      shopName: r.Shop?.name ?? "Unknown",
      total: Number(r.get("total")) || 0,
      count: Number(r.get("count")) || 0,
    }))

    // Express low stock in each item's unit fraction
    const lowStock = stockRows.map((r) => {
      const fractions = r.item?.fractions ?? []
      const unit = fractions.find((f) => f.isUnit) ?? fractions.find((f) => f.ratio === 1) ?? fractions[0]
      return {
        availableItemId: r.id,
        itemName: r.item?.name ?? "Unknown",
        shopName: r.shop?.name ?? "Unknown",
        quantity: Number(r.quantity) / (unit?.ratio || 1),
        unit: unit?.name ?? "",
      }
    })

    res.json({
      totalSales: totalSales || 0,
      salesCount,
      salesByDay,
      topItems,
      todaySales: todaySales || 0,
      totalProfit: isSalesman ? null : totalProfit || 0,
      todayProfit: isSalesman ? null : todayProfit || 0,
      todayCount,
      salesByShop,
      lowStock,
    })
  } catch (error) {
    console.error("Error fetching dashboard stats:", error.message)
    res.status(500).json({ message: "Error fetching dashboard stats", error: error.message })
  }
}
