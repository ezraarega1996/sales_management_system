// Gives existing stock its opening FIFO lots. Run once after deploying FIFO cost tracking:
//
//   npm run backfill:lots              -> create missing opening lots
//   npm run backfill:lots -- --check   -> only report stock rows whose lots don't add up
//
// For every stock row (AvailableItem) whose lots hold fewer units than the stock, one "opening"
// lot (no purchase) is created for the difference, costed at the latest purchase price of that
// item in that shop (else the item's catalogue purchase price). Safe to run again: rows that
// already add up are skipped. Past sales and their recorded profit are not touched.
import "dotenv/config"
import { sequelize, AvailableItem, StockLot, SaleCostAllocation } from "../models/index.js"
import { lockStock, addLot, fallbackUnitCost, num } from "../services/stockLedger.js"

const checkOnly = process.argv.includes("--check")
const EPS = 1e-4

const main = async () => {
  await sequelize.authenticate()
  // The server creates these tables on start; create them here too in case it hasn't run yet
  await StockLot.sync()
  await SaleCostAllocation.sync()

  const rows = await AvailableItem.findAll({ attributes: ["id", "businessId", "shopId", "itemId", "quantity"] })
  let created = 0
  let mismatched = 0

  for (const row of rows) {
    const key = { businessId: row.businessId, shopId: row.shopId, itemId: row.itemId }
    await sequelize.transaction(async (transaction) => {
      const stock = await lockStock(key, transaction)
      if (!stock || stock.id !== row.id) return // duplicate stock row: the oldest one is the real one
      const inLots = num(await StockLot.sum("remainingUnits", { where: key, transaction }))
      const missing = num(stock.quantity) - inLots
      if (Math.abs(missing) <= EPS) return

      if (checkOnly || missing < 0) {
        mismatched++
        console.log(`${missing < 0 ? "MORE IN LOTS THAN STOCK" : "missing lots"}: shop ${key.shopId} item ${key.itemId} stock ${num(stock.quantity)} lots ${inLots}`)
        return
      }
      const unitCost = await fallbackUnitCost(key, transaction)
      await addLot({ ...key, units: missing, unitCost, receivedAt: new Date(0) }, transaction)
      created++
    })
  }

  console.log(
    checkOnly
      ? `${rows.length} stock rows checked, ${mismatched} don't add up`
      : `${rows.length} stock rows checked, ${created} opening lots created, ${mismatched} need attention`,
  )
  await sequelize.close()
}

main().catch(async (error) => {
  console.error("Backfill failed:", error.message)
  await sequelize.close()
  process.exit(1)
})
