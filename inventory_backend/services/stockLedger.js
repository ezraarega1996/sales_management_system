/**
 * Stock + FIFO cost bookkeeping shared by purchases and sales.
 *
 * Stock is one number per (business, shop, item): AvailableItem.quantity, in base units.
 * Underneath, every purchase is a StockLot with its own cost per base unit. Sales use up the
 * oldest lots first (FIFO), so a sale's cost is what those exact units were bought for, and each
 * sale line records which lots it used (SaleCostAllocation) so it can be undone exactly.
 *
 * Invariant kept by every function here: the remainingUnits of an item's lots in a shop add up
 * to that shop's AvailableItem.quantity.
 *
 * All functions must run inside a transaction. Functions that change units expect the caller to
 * hold the stock row lock from lockStock(), which serializes all work on one item in one shop.
 */
import { Op } from "sequelize"
import { AvailableItem, StockLot, SaleCostAllocation, ItemBought, Fraction, SoldItem, sequelize } from "../models/index.js"

const EPS = 1e-6
export const num = (v) => parseFloat(v ?? 0) || 0
const round4 = (n) => Math.round(n * 1e4) / 1e4
export const round2 = (n) => Math.round(n * 100) / 100

export const httpError = (status, message) => Object.assign(new Error(message), { status })

/**
 * Locks (and with [createIfMissing], creates) the stock row of an item in a shop. The advisory
 * lock makes two first purchases of a new item wait for each other instead of creating two rows.
 */
export async function lockStock({ businessId, shopId, itemId, createIfMissing = false, soldPrice = 0 }, transaction) {
  await sequelize.query("SELECT pg_advisory_xact_lock(hashtext(:key))", {
    replacements: { key: `stock:${businessId}:${shopId}:${itemId}` },
    transaction,
  })
  let stock = await AvailableItem.findOne({
    where: { businessId, shopId, itemId },
    order: [["createdAt", "ASC"]],
    lock: transaction.LOCK.UPDATE,
    transaction,
  })
  if (!stock && createIfMissing) {
    stock = await AvailableItem.create({ businessId, shopId, itemId, quantity: 0, soldPrice }, { transaction })
  }
  return stock
}

/** Adds a lot of [units] base units costing [unitCost] each. */
export function addLot({ businessId, shopId, itemId, itemBoughtId = null, units, unitCost, receivedAt }, transaction) {
  return StockLot.create(
    {
      businessId,
      shopId,
      itemId,
      itemBoughtId,
      receivedAt: receivedAt || new Date(),
      unitCost: Math.max(0, unitCost),
      initialUnits: round4(units),
      remainingUnits: round4(units),
    },
    { transaction },
  )
}

/**
 * Cost per base unit to use when there is no lot to take from (stock recorded before cost
 * tracking, or data that drifted): the newest lot, else the latest purchase, else the catalogue.
 */
export async function fallbackUnitCost({ businessId, shopId, itemId }, transaction) {
  const lot = await StockLot.findOne({
    where: { businessId, shopId, itemId },
    order: [["receivedAt", "DESC"]],
    transaction,
  })
  if (lot) return num(lot.unitCost)

  const bought = await ItemBought.findOne({
    where: { businessId, shopId, itemId },
    include: [{ model: Fraction, attributes: ["ratio"] }],
    order: [["createdTime", "DESC"]],
    transaction,
  })
  if (bought?.Fraction && num(bought.Fraction.ratio) > 0) {
    return num(bought.fractionPurchasePrice) / num(bought.Fraction.ratio)
  }

  const fractions = await Fraction.findAll({ where: { itemId }, transaction })
  const unit = fractions.find((f) => f.isUnit) ?? fractions.find((f) => num(f.ratio) === 1) ?? fractions[0]
  return unit && num(unit.ratio) > 0 ? num(unit.purchasePrice) / num(unit.ratio) : 0
}

/**
 * Takes [units] base units out of the item's lots, oldest first. Returns the total cost and the
 * parts taken (to be saved with saveAllocations once the sale line exists). Units the lots can't
 * cover are costed at fallbackUnitCost with no lot.
 */
export async function consumeFifo({ businessId, shopId, itemId, units }, transaction) {
  const lots = await StockLot.findAll({
    where: { businessId, shopId, itemId, remainingUnits: { [Op.gt]: 0 } },
    order: [
      ["receivedAt", "ASC"],
      ["id", "ASC"],
    ],
    lock: transaction.LOCK.UPDATE,
    transaction,
  })

  let left = units
  let cost = 0
  const parts = []
  for (const lot of lots) {
    if (left <= EPS) break
    const remaining = num(lot.remainingUnits)
    const take = Math.min(remaining, left)
    lot.remainingUnits = round4(remaining - take)
    await lot.save({ transaction })
    const unitCost = num(lot.unitCost)
    parts.push({ stockLotId: lot.id, units: round4(take), unitCost })
    cost += take * unitCost
    left -= take
  }
  if (left > EPS) {
    const unitCost = await fallbackUnitCost({ businessId, shopId, itemId }, transaction)
    parts.push({ stockLotId: null, units: round4(left), unitCost })
    cost += left * unitCost
  }
  return { cost: round2(cost), parts }
}

export function saveAllocations(soldItemId, parts, transaction) {
  return SaleCostAllocation.bulkCreate(
    parts.map((p) => ({ soldItemId, stockLotId: p.stockLotId, units: p.units, unitCost: p.unitCost })),
    { transaction },
  )
}

/**
 * Removes [units] base units from the item's lots without a sale (a purchase recorded before
 * cost tracking being reduced or deleted). Takes from the newest lots first, as those are the
 * most likely to still hold that purchase's units.
 */
export async function removeUnitsNewestFirst({ businessId, shopId, itemId, units }, transaction) {
  const lots = await StockLot.findAll({
    where: { businessId, shopId, itemId, remainingUnits: { [Op.gt]: 0 } },
    order: [
      ["receivedAt", "DESC"],
      ["id", "DESC"],
    ],
    lock: transaction.LOCK.UPDATE,
    transaction,
  })
  let left = units
  for (const lot of lots) {
    if (left <= EPS) break
    const remaining = num(lot.remainingUnits)
    const take = Math.min(remaining, left)
    lot.remainingUnits = round4(remaining - take)
    await lot.save({ transaction })
    left -= take
  }
}

/**
 * Puts sold units back: into stock and into the exact lots they came from. Used when a receipt is
 * undone or an owner deletes a sale line. Deletes the lines' cost allocations; the caller deletes
 * the sale rows themselves.
 */
export async function returnSalesToStock(sales, transaction) {
  if (!sales.length) return
  const fractions = await Fraction.findAll({ where: { id: [...new Set(sales.map((s) => s.fractionId))] }, transaction })
  const ratioById = new Map(fractions.map((f) => [f.id, num(f.ratio) || 1]))
  const allocations = await SaleCostAllocation.findAll({ where: { soldItemId: sales.map((s) => s.id) }, transaction })

  // Lock stock rows in a fixed order so two undos can't deadlock each other
  const sorted = [...sales].sort((a, b) => `${a.shopId}${a.itemId}`.localeCompare(`${b.shopId}${b.itemId}`))
  for (const sale of sorted) {
    if (!sale.shopId) continue // very old sales without a shop never had their stock tracked per shop
    const units = num(sale.quantity) * (ratioById.get(sale.fractionId) ?? 1)
    const key = { businessId: sale.businessId, shopId: sale.shopId, itemId: sale.itemId }
    const stock = await lockStock({ ...key, createIfMissing: true }, transaction)
    stock.quantity = round4(num(stock.quantity) + units)
    await stock.save({ transaction })

    // Back into the lots the units were taken from
    let restored = 0
    let lastCost = null
    for (const a of allocations.filter((x) => x.soldItemId === sale.id)) {
      lastCost = num(a.unitCost)
      const lot = a.stockLotId ? await StockLot.findByPk(a.stockLotId, { lock: transaction.LOCK.UPDATE, transaction }) : null
      if (!lot) continue
      lot.remainingUnits = round4(num(lot.remainingUnits) + num(a.units))
      await lot.save({ transaction })
      restored += num(a.units)
    }
    // Units with no lot to return to (sold before cost tracking, or costed at a fallback price)
    const rest = units - restored
    if (rest > EPS) {
      const unitCost = lastCost ?? (await fallbackUnitCost(key, transaction))
      await addLot({ ...key, units: rest, unitCost, receivedAt: sale.soldTime || new Date() }, transaction)
    }
  }
  await SaleCostAllocation.destroy({ where: { soldItemId: sales.map((s) => s.id) }, transaction })
}

/** Total recorded cost of a sale line (null when it was sold before cost tracking). */
export async function allocatedCost(soldItemId, transaction) {
  const allocations = await SaleCostAllocation.findAll({ where: { soldItemId }, transaction })
  if (!allocations.length) return null
  return round2(allocations.reduce((sum, a) => sum + num(a.units) * num(a.unitCost), 0))
}

/**
 * A purchase's price was corrected: its lot now costs [unitCost] per base unit, and the sales that
 * already used units from it are re-costed (their profit is updated) so a typo fix corrects profit.
 */
export async function recostLot(lot, unitCost, transaction) {
  lot.unitCost = Math.max(0, unitCost)
  await lot.save({ transaction })
  const allocations = await SaleCostAllocation.findAll({ where: { stockLotId: lot.id }, transaction })
  if (!allocations.length) return
  await SaleCostAllocation.update({ unitCost: lot.unitCost }, { where: { stockLotId: lot.id }, transaction })
  for (const soldItemId of new Set(allocations.map((a) => a.soldItemId))) {
    const sale = await SoldItem.findByPk(soldItemId, { transaction })
    const cost = await allocatedCost(soldItemId, transaction)
    if (sale && cost != null) {
      sale.profit = round2(num(sale.amount) - cost)
      await sale.save({ transaction })
    }
  }
}
