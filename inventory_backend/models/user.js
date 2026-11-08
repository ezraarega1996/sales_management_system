import { DataTypes } from "sequelize"
import sequelize from "./database.js"
import bcrypt from "bcrypt"
import Business from "./business.js"

const User = sequelize.define(
  "User",
  {
    id: {
      type: DataTypes.UUID,
      defaultValue: DataTypes.UUIDV4,
      primaryKey: true,
    },
    name: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    phone: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    location: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    username: {
      type: DataTypes.STRING,
      allowNull: false,
      unique: true,
    },
    password: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    role: {
      type: DataTypes.ENUM("admin", "owner", "salesman"),
      allowNull: false,
      defaultValue: "salesman",
    },
    businessId: {
      type: DataTypes.UUID,
      allowNull: true,
      references: {
        model: Business,
        key: "id",
      },
    },
    shopId: {
      type: DataTypes.UUID,
      allowNull: true,
    },
    isActive: {
      type: DataTypes.BOOLEAN,
      defaultValue: true,
    },
  },
  {
    hooks: {
      beforeCreate: async (user) => {
        const salt = await bcrypt.genSalt(10)
        user.password = await bcrypt.hash(user.password, salt)
      },
      beforeUpdate: async (user) => {
        if (user.changed("password")) {
          const salt = await bcrypt.genSalt(10)
          user.password = await bcrypt.hash(user.password, salt)
        }
      },
    },
  },
)

User.prototype.validatePassword = async function (password) {
  return await bcrypt.compare(password, this.password)
}

// Add business association
User.belongsTo(Business, { foreignKey: "businessId" })
Business.hasMany(User, { foreignKey: "businessId" })

export default User
