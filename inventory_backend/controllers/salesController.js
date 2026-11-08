import { SoldItem, Item, User, Fraction, AvailableItem, Shop, sequelize } from "../models/index.js"
import { Op } from "sequelize"

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
      where: { businessId: req.user.businessId },
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
      where: { id: req.params.id, businessId: req.user.businessId },
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
export const createSale = async (req, res) => {
  const { itemId, fractionId, quantity, amount, shopId, profit, clientId, soldTime } = req.body
  const selectedShopId = shopId || req.user.shopId

  if (!selectedShopId) {
    return res.status(400).json({ message: "shopId is required to create a sale" })
  }
  if (!itemId || !fractionId || !quantity || !amount) {
    return res.status(400).json({ message: "All fields are required" })
  }

  try {
    if (clientId) {
      const existing = await SoldItem.findOne({ where: { clientId, businessId: req.user.businessId } })
      if (existing) return res.status(200).json(existing)
    }

    const fraction = await Fraction.findOne({ where: { id: fractionId, itemId } })
    if (!fraction) {
      return res.status(404).json({ message: "Fraction not found" })
    }
    const quantityInUnits = quantity * fraction.ratio

    // Time the sale actually happened (may be earlier when it was queued offline), never in the future
    const parsed = soldTime ? new Date(soldTime) : null
    const saleTime = parsed && !isNaN(parsed) && parsed <= new Date() ? parsed : new Date()

    const sale = await sequelize.transaction(async (transaction) => {
      // Lock the stock row so two concurrent sales can't both pass the quantity check
      const availableItem = await AvailableItem.findOne({
        where: { itemId, shopId: selectedShopId, businessId: req.user.businessId },
        lock: transaction.LOCK.UPDATE,
        transaction,
      })
      if (!availableItem) {
        throw Object.assign(new Error("No available items found for this item"), { status: 400 })
      }
      if (parseFloat(availableItem.quantity) < quantityInUnits) {
        throw Object.assign(new Error("Not enough quantity available"), { status: 400 })
      }

      availableItem.quantity = parseFloat(availableItem.quantity) - quantityInUnits
      await availableItem.save({ transaction })

      return SoldItem.create(
        {
          itemId,
          fractionId,
          quantity,
          amount,
          expectedAmount: amount,
          salesmanId: req.user.id,
          businessId: req.user.businessId,
          available_items_count: availableItem.quantity / fraction.ratio,
          availableItemId: availableItem.id,
          shopId: selectedShopId,
          profit: typeof profit === "number" ? profit : 0,
          clientId: clientId || null,
          soldTime: saleTime,
          createdTime: saleTime,
        },
        { transaction },
      )
    })

    res.status(201).json(sale)
  } catch (error) {
    if (error.status) {
      return res.status(error.status).json({ message: error.message })
    }
    // A retry raced with the original request: the unique clientId already exists
    if (error.name === "SequelizeUniqueConstraintError" && clientId) {
      const existing = await SoldItem.findOne({ where: { clientId } })
      if (existing) return res.status(200).json(existing)
    }
    console.error("Error creating sale:", error.message)
    res.status(500).json({ message: "Error creating sale", error: error.message })
  }
}

export const updateSale = async (req, res) => {
  try {
    const { quantity, amount, expectedAmount, status, existing } = req.body

    const sale = await SoldItem.findOne({
      where: { id: req.params.id, businessId: req.user.businessId },
    })
    if (!sale) {
      return res.status(404).json({ message: "Sale not found" })
    }
    if (req.user.role !== "owner" && req.user.role !== "admin" && sale.salesmanId !== req.user.id) {
      return res.status(403).json({ message: "Not authorized to update this sale" })
    }

    if (quantity !== undefined) sale.quantity = quantity
    if (amount !== undefined) sale.amount = amount
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
    await sale.destroy()
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
