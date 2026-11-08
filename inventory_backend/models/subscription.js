import { DataTypes } from "sequelize"
import sequelize from "./database.js"
import Business from "./business.js"

const Subscription = sequelize.define("Subscription", {
  id: {
    type: DataTypes.UUID,
    defaultValue: DataTypes.UUIDV4,
    primaryKey: true,
  },
  plan: {
    type: DataTypes.ENUM("free", "basic", "premium", "enterprise"),
    allowNull: false,
  },
  status: {
    type: DataTypes.ENUM("active", "cancelled", "expired"),
    defaultValue: "active",
  },
  startDate: {
    type: DataTypes.DATE,
    defaultValue: DataTypes.NOW,
  },
  endDate: {
    type: DataTypes.DATE,
    allowNull: true,
  },
  paymentMethod: {
    type: DataTypes.STRING,
    allowNull: true,
  },
  paymentId: {
    type: DataTypes.STRING,
    allowNull: true,
  },
  amount: {
    type: DataTypes.FLOAT,
    allowNull: false,
  },
  currency: {
    type: DataTypes.STRING,
    defaultValue: "USD",
  },
  isAutoRenew: {
    type: DataTypes.BOOLEAN,
    defaultValue: true,
  },
})

Subscription.belongsTo(Business, { foreignKey: "businessId" })
Business.hasMany(Subscription, { foreignKey: "businessId" })

export default Subscription
