import { DataTypes } from "sequelize"
import sequelize from "./database.js"
import Business from "./business.js"

const Category = sequelize.define("Category", {
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

// Add business association
Category.belongsTo(Business, { foreignKey: "businessId" })
Business.hasMany(Category, { foreignKey: "businessId" })

export default Category
