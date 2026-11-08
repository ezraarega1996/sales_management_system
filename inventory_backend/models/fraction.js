import { DataTypes } from "sequelize"
import sequelize from "./database.js"
import Item from "./item.js"
import Business from "./business.js"

const Fraction = sequelize.define("Fraction", {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true,
  },
  name: {
    type: DataTypes.STRING,
    allowNull: false,
  },
  ratio: {
    type: DataTypes.FLOAT,
    allowNull: false,
  },
  sellingPrice: {
    type: DataTypes.FLOAT,
    allowNull: false,
  },
  purchasePrice: {
    type: DataTypes.FLOAT,
    allowNull: false,
    defaultValue: 0,
  },
  isUnit: {
    type: DataTypes.BOOLEAN,
    allowNull: false,
    defaultValue: false,
  },
})

Fraction.belongsTo(Item, { foreignKey: "itemId" })
Item.hasMany(Fraction, {as: "fractions", foreignKey: "itemId" })

// Add business association
Fraction.belongsTo(Business, { foreignKey: "businessId" })
Business.hasMany(Fraction, { foreignKey: "businessId" })

export default Fraction
