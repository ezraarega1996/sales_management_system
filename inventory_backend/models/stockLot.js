import { DataTypes } from "sequelize"
import sequelize from "./database.js"

/**
 * One batch of stock with its own cost, used for FIFO (first in, first out) cost of goods.
 *
 * Every purchase creates a lot; stock that existed before lots were introduced gets one
 * "opening" lot (itemBoughtId null). Sales use up the oldest lots first, so a sale's cost is what
 * those exact units were bought for.
 *
 * Invariant: for each (businessId, shopId, itemId) the remainingUnits of its lots add up to the
 * AvailableItem.quantity of that shop's stock row.
 */
const StockLot = sequelize.define(
  "StockLot",
  {
    id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
    businessId: { type: DataTypes.UUID, allowNull: false },
    shopId: { type: DataTypes.UUID, allowNull: false },
    itemId: { type: DataTypes.UUID, allowNull: false },
    // The purchase this lot came from; null for opening balances and returned uncosted units
    itemBoughtId: { type: DataTypes.UUID, allowNull: true },
    // FIFO order
    receivedAt: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW },
    // Cost of one base unit (fraction ratio 1); kept precise so e.g. 100 / 12 doesn't drift
    unitCost: { type: DataTypes.DECIMAL(14, 6), allowNull: false, defaultValue: 0 },
    // Base units the lot started with and how many are still in stock
    initialUnits: { type: DataTypes.DECIMAL(14, 4), allowNull: false },
    remainingUnits: { type: DataTypes.DECIMAL(14, 4), allowNull: false },
  },
  {
    indexes: [{ fields: ["businessId", "shopId", "itemId", "receivedAt"] }, { fields: ["itemBoughtId"] }],
  },
)

export default StockLot
