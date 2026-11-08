import { DataTypes } from "sequelize"
import sequelize from "./database.js"
import {  Item, Shop } from "./index.js"
import Business from "./business.js"

const AvailableItem = sequelize.define("AvailableItem", {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true,
  },
  itemId: {
    type: DataTypes.UUID,
    allowNull: false,
  },
  businessId: {
    type: DataTypes.UUID,
    allowNull: false,
  },
  quantity: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false,
    defaultValue: 0,
  },
  soldPrice: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false,
  },
  shopId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: 'Shops',
      key: 'id',
    },
  },
})

// Define associations
AvailableItem.belongsTo(Item, {as: 'item', foreignKey: "itemId" })

// Add business association
AvailableItem.belongsTo(Business, { foreignKey: "businessId" })
Business.hasMany(AvailableItem, { foreignKey: "businessId" })

AvailableItem.belongsTo(Shop, { foreignKey: 'shopId', as: 'shop' })

export default AvailableItem 