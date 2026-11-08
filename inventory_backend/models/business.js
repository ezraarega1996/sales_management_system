import { DataTypes } from "sequelize"
import sequelize from "./database.js"

const Business = sequelize.define("Business", {
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
    allowNull: true,
  },
  phone: {
    type: DataTypes.STRING,
    allowNull: true,
  },
  email: {
    type: DataTypes.STRING,
    allowNull: true,
  },
  logo: {
    type: DataTypes.STRING,
    allowNull: true,
  },
  isActive: {
    type: DataTypes.BOOLEAN,
    defaultValue: true,
  },
  subscriptionStatus: {
    type: DataTypes.ENUM("trial", "active", "expired", "cancelled"),
    defaultValue: "trial",
  },
  subscriptionPlan: {
    type: DataTypes.ENUM("free", "basic", "premium", "enterprise"),
    defaultValue: "free",
  },
  trialEndsAt: {
    type: DataTypes.DATE,
    allowNull: true,
  },
  subscriptionEndsAt: {
    type: DataTypes.DATE,
    allowNull: true,
  },
})

export default Business
