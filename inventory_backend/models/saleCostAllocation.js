import { DataTypes } from "sequelize"
import sequelize from "./database.js"

/**
 * Which lots a sale line took its units from, and at what cost. Lets an undone or deleted sale
 * put its units back into the exact lots, and lets a corrected purchase price re-cost the sales
 * that used that purchase.
 */
const SaleCostAllocation = sequelize.define(
  "SaleCostAllocation",
  {
    id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
    soldItemId: { type: DataTypes.UUID, allowNull: false },
    // Null when the lots ran short (old data) and the units were costed at a fallback price
    stockLotId: { type: DataTypes.UUID, allowNull: true },
    units: { type: DataTypes.DECIMAL(14, 4), allowNull: false },
    unitCost: { type: DataTypes.DECIMAL(14, 6), allowNull: false },
  },
  {
    indexes: [{ fields: ["soldItemId"] }, { fields: ["stockLotId"] }],
  },
)

export default SaleCostAllocation
