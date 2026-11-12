import { AvailableItem, Item, SoldItem, Fraction, User, ItemBought, Shop, StockLot, sequelize } from "../models/index.js"
import { Op } from "sequelize"

const FRACTION_ATTRS = ["id", "name", "ratio", "sellingPrice", "purchasePrice", "isUnit", "itemId"]

// Stock list. Purchase/sale history is NOT embedded here (it grows without limit);
// it is loaded per item via GET /available-items/:id/transactions.
export const getAllAvailableItems = async (req, res) => {
  try {
    const { shopId } = req.query
    const where = { businessId: req.user.businessId }
    if (req.user.role === "salesman") {
      where.shopId = req.user.shopId
    } else if (shopId) {
      where.shopId = shopId
    }

    const availableItems = await AvailableItem.findAll({
      where,
      include: [
        {
          model: Item,
          as: "item",
          attributes: ["id", "name", "categoryId"],
          include: [{ model: Fraction, as: "fractions", attributes: FRACTION_ATTRS }],
        },
        { model: Shop, as: "shop", attributes: ["id", "name", "address"] },
      ],
      order: [[sequelize.literal('LOWER("item"."name")'), "ASC"]],
    })

    // Owners also get the cost of the stock on hand, per base unit (salesmen don't see costs):
    //   unitCost     what the next unit sold will cost (oldest lot with stock, FIFO; used for profit)
    //   avgUnitCost  weighted average cost of all units still in stock
    //   stockValue   what the units still in stock cost in total
    if (req.user.role === "salesman") return res.json(availableItems)
    const lots = await StockLot.findAll({
      where: { businessId: req.user.businessId, remainingUnits: { [Op.gt]: 0 }, ...(where.shopId ? { shopId: where.shopId } : {}) },
      attributes: ["shopId", "itemId", "unitCost", "remainingUnits", "receivedAt"],
      order: [["receivedAt", "ASC"], ["id", "ASC"]],
    })
    const costs = new Map()
    for (const lot of lots) {
      const key = `${lot.shopId}:${lot.itemId}`
      const units = parseFloat(lot.remainingUnits)
      const unitCost = parseFloat(lot.unitCost)
      const c = costs.get(key) ?? { next: unitCost, units: 0, value: 0 }
      c.units += units
      c.value += units * unitCost
      costs.set(key, c)
    }
    res.json(
      availableItems.map((a) => {
        const c = costs.get(`${a.shopId}:${a.itemId}`)
        return {
          ...a.toJSON(),
          unitCost: c?.next ?? null,
          avgUnitCost: c && c.units > 0 ? c.value / c.units : null,
          stockValue: c ? Math.round(c.value * 100) / 100 : null,
        }
      }),
    )
  } catch (error) {
    console.error("Error fetching available items:", error.message)
    res.status(500).json({ message: "Error fetching available items", error: error.message })
  }
}

export const getAvailableItemTransactions = async (req, res) => {
  try {
    const where = { id: req.params.id, businessId: req.user.businessId }
    if (req.user.role === "salesman") where.shopId = req.user.shopId

    const availableItem = await AvailableItem.findOne({ where, attributes: ["id"] })
    if (!availableItem) {
      return res.status(404).json({ message: "Available item not found" })
    }

    const [boughtTransactions, soldTransactions] = await Promise.all([
      ItemBought.findAll({
        where: { availableItemId: availableItem.id },
        include: [{ model: Fraction, attributes: ["id", "name", "ratio"] }],
        order: [["createdTime", "DESC"]],
      }),
      SoldItem.findAll({
        where: { availableItemId: availableItem.id },
        include: [{ model: User, as: "salesman", attributes: ["id", "name", "username"] }],
        order: [["soldTime", "DESC"]],
      }),
    ])

    res.json({ boughtTransactions, soldTransactions })
  } catch (error) {
    console.error("Error fetching item transactions:", error.message)
    res.status(500).json({ message: "Error fetching transactions", error: error.message })
  }
}

export const getTodaySalesBySalesman = async (req, res) => {
  try {
    const today = new Date()
    today.setHours(0, 0, 0, 0)

    const salesBySalesman = await SoldItem.findAll({
      where: { businessId: req.user.businessId, soldTime: { [Op.gte]: today } },
      include: [{ model: User, as: "salesman", attributes: ["id", "name", "username"] }],
      attributes: [
        "salesmanId",
        [sequelize.fn("SUM", sequelize.col("amount")), "totalAmount"],
        [sequelize.fn("COUNT", sequelize.col("SoldItem.id")), "totalTransactions"],
      ],
      group: ["salesmanId", "salesman.id", "salesman.name", "salesman.username"],
    })

    const formattedSales = salesBySalesman.map((sale) => ({
      salesmanId: sale.getDataValue("salesmanId"),
      salesmanName: sale.salesman?.name ?? "Unknown",
      totalAmount: parseFloat(sale.getDataValue("totalAmount") || 0),
      totalTransactions: parseInt(sale.getDataValue("totalTransactions") || 0),
    }))

    res.json({
      totalSales: formattedSales.reduce((sum, s) => sum + s.totalAmount, 0),
      salesBySalesman: formattedSales,
    })
  } catch (error) {
    console.error("Error fetching today's sales by salesman:", error.message)
    res.status(500).json({ message: "Error fetching today's sales", error: error.message })
  }
}
