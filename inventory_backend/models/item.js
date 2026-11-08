import { DataTypes } from "sequelize"
import sequelize from "./database.js"
import Category from "./category.js"
import Business from "./business.js"

const Item = sequelize.define("Item", {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true,
  },
  name: {
    type: DataTypes.STRING,
    allowNull: false,
  },
})

Item.belongsTo(Category, { foreignKey: "categoryId" })
Category.hasMany(Item, { foreignKey: "categoryId" })

// Add business association
Item.belongsTo(Business, { foreignKey: "businessId" })
Business.hasMany(Item, { foreignKey: "businessId" })

export default Item
