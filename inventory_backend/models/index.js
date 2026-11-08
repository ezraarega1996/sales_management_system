import sequelize from "./database.js"
import User from "./user.js"
import Category from "./category.js"
import Item from "./item.js"
import Fraction from "./fraction.js"
import ItemBought from "./itemBought.js"
import SoldItem from "./soldItem.js"
import Business from "./business.js"
import Subscription from "./subscription.js"
import AvailableItem from "./availableItem.js"
import Bought from "./itemBought.js"
import Shop from "./shop.js"

// Define associations after all models are loaded to avoid circular dependencies
Shop.hasMany(User, { foreignKey: "shopId", as: "salespeople" })
User.belongsTo(Shop, { foreignKey: "shopId" })

ItemBought.belongsTo(Shop, { foreignKey: "shopId" })

const syncDatabase = async () => {
  try {
    await sequelize.sync({ alter: true })
    console.log("Database synchronized successfully")
  } catch (error) {
    console.error("Error synchronizing database:", error)
  }
}

export { sequelize, User, Category, Item, Fraction, ItemBought, SoldItem, Business, Subscription, AvailableItem, Bought, Shop, syncDatabase }
