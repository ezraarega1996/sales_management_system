import sequelize from "./database.js"
import Business from "./business.js"
import Shop from "./shop.js"
import User from "./user.js"
import Category from "./category.js"
import Item from "./item.js"
import Fraction from "./fraction.js"
import AvailableItem from "./availableItem.js"
import ItemBought from "./itemBought.js"
import SoldItem from "./soldItem.js"
import Subscription from "./subscription.js"
import StockLot from "./stockLot.js"
import SaleCostAllocation from "./saleCostAllocation.js"

// Associations that span several model files live here to avoid circular imports
Shop.hasMany(User, { foreignKey: "shopId", as: "salespeople" })
User.belongsTo(Shop, { foreignKey: "shopId" })

// FIFO cost of goods: purchases create lots, sale lines record which lots they used
ItemBought.hasOne(StockLot, { foreignKey: "itemBoughtId" })
StockLot.belongsTo(ItemBought, { foreignKey: "itemBoughtId" })
SoldItem.hasMany(SaleCostAllocation, { foreignKey: "soldItemId", as: "costAllocations" })
SaleCostAllocation.belongsTo(SoldItem, { foreignKey: "soldItemId" })
StockLot.hasMany(SaleCostAllocation, { foreignKey: "stockLotId" })
SaleCostAllocation.belongsTo(StockLot, { foreignKey: "stockLotId" })

export { sequelize, User, Category, Item, Fraction, ItemBought, SoldItem, Business, Subscription, AvailableItem, Shop, StockLot, SaleCostAllocation }
