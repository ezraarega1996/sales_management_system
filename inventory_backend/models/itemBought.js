import { DataTypes } from "sequelize"
import sequelize from "./database.js"
import Item from "./item.js"
import Business from "./business.js"
import Shop from "./shop.js"
import Fraction from "./fraction.js"
import AvailableItem from "./availableItem.js"

const ItemBought = sequelize.define("ItemBought", {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true,
  },
  itemId: {
    type: DataTypes.UUID,
    allowNull: false,
  },
  fractionId: {
    type: DataTypes.UUID,
    allowNull: false,
  },
  fractionPurchasePrice: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false,
  },
  fractionSoldPrice: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false,
  },
  quantity: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false,
  },
  expiryDate: {
    type: DataTypes.DATE,
    allowNull: true,
  },
  businessId: {
    type: DataTypes.UUID,
    allowNull: false,
  },
  shopId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: Shop,
      key: "id",
    },
  },
  availableItemId: {
    type: DataTypes.UUID,
    allowNull: true,
    references: {
      model: AvailableItem,
      key: "id",
    },
  },
  available_items_count: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false,
  },
  createdTime: {
    type: DataTypes.DATE,
    defaultValue: DataTypes.NOW,
  },
})

ItemBought.belongsTo(Item, { foreignKey: "itemId" })
ItemBought.belongsTo(Business, { foreignKey: "businessId" })
ItemBought.belongsTo(Shop, { foreignKey: "shopId" })
ItemBought.belongsTo(Fraction, { foreignKey: "fractionId" })
ItemBought.belongsTo(AvailableItem, { foreignKey: "availableItemId" })

// Add the reverse association
AvailableItem.hasMany(ItemBought, {as: "boughtTransactions", foreignKey: "availableItemId" })

export default ItemBought
