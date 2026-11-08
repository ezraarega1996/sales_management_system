import { DataTypes } from "sequelize"
import sequelize from "./database.js"
import Business from "./business.js"

const Shop = sequelize.define("Shop", {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true,
  },
  name: {
    type: DataTypes.STRING,
    allowNull: false,
  },
  address: {
    type: DataTypes.STRING,
    allowNull: false,
  },
  businessId: {
    type: DataTypes.UUID,
    allowNull: false,
    references: {
      model: Business,
      key: "id",
    },
  },
  isActive: {
    type: DataTypes.BOOLEAN,
    defaultValue: true,
  },
  createdAt: {
    type: DataTypes.DATE,
    defaultValue: DataTypes.NOW,
  },
  updatedAt: {
    type: DataTypes.DATE,
    defaultValue: DataTypes.NOW,
  },
})

// Define associations
Shop.belongsTo(Business, { foreignKey: "businessId" })
Business.hasMany(Shop, { foreignKey: "businessId" })

export default Shop 