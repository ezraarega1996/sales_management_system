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

// Associations that span several model files live here to avoid circular imports
Shop.hasMany(User, { foreignKey: "shopId", as: "salespeople" })
User.belongsTo(Shop, { foreignKey: "shopId" })

export { sequelize, User, Category, Item, Fraction, ItemBought, SoldItem, Business, Subscription, AvailableItem, Shop }
