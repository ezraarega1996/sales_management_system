import { DataTypes } from "sequelize"
import sequelize from "./database.js"
import Item from "./item.js"
import User from "./user.js"
import Business from "./business.js"
import Fraction from "./fraction.js"
import AvailableItem from "./availableItem.js"
import Shop from "./shop.js"

const SoldItem = sequelize.define("SoldItem", {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true,
  },
  soldTime: {
    type: DataTypes.DATE,
    defaultValue: DataTypes.NOW,
  },
  quantity: {
    type: DataTypes.FLOAT,
    allowNull: false,
  },
  fractionId: {
    type: DataTypes.STRING,
    allowNull: false,
  },
  amount: {
    type: DataTypes.FLOAT,
    allowNull: false,
  },
  expectedAmount: {
    type: DataTypes.FLOAT,
    allowNull: false,
  },
  existing: {
    type: DataTypes.BOOLEAN,
    defaultValue: true,
  },
  profit: {
    type: DataTypes.FLOAT,
    allowNull: true,
  },
  status: {
    type: DataTypes.ENUM("pending", "completed", "cancelled"),
    defaultValue: "completed",
  },
  createdTime: {
    type: DataTypes.DATE,
    defaultValue: DataTypes.NOW,
  },
  available_items_count: {
    type: DataTypes.DECIMAL(10, 2),
    allowNull: false,
  },
  availableItemId: {
    type: DataTypes.UUID,
    allowNull: true,
    references: {
      model: AvailableItem,
      key: "id",
    },
  },
  shopId: {
    type: DataTypes.UUID,
    allowNull: true,
    references: {
      model: "Shops",
      key: "id",
    },
  },
})

SoldItem.belongsTo(Item, { foreignKey: "itemId" })
Item.hasMany(SoldItem, { foreignKey: "itemId" })

SoldItem.belongsTo(User, { foreignKey: "salesmanId", as: "salesman" })
User.hasMany(SoldItem, { foreignKey: "salesmanId", as: "sales" })

// Add business association
SoldItem.belongsTo(Business, { foreignKey: "businessId" })
Business.hasMany(SoldItem, { foreignKey: "businessId" })

//SoldItem.belongsTo(Fraction, { foreignKey: "fractionId" })
SoldItem.belongsTo(AvailableItem, { foreignKey: "availableItemId" })

// Add the reverse association
AvailableItem.hasMany(SoldItem, {as: "soldTransactions", foreignKey: "availableItemId" })

// Associate each sale with a shop so frontend summaries can filter by shop
SoldItem.belongsTo(Shop, { foreignKey: "shopId" })

export default SoldItem
