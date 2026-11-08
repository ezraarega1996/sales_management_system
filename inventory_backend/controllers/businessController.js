import { Business, User, Subscription, Item, SoldItem } from "../models/index.js"
import sequelize from "../models/database.js"
import { Op } from "sequelize"


// Create a new business
export const createBusiness = async (req, res) => {
  try {
    const { name, ownerName, ownerPhone, ownerUsername, ownerPassword } = req.body
    
    // Create business with minimal information
    const business = await Business.create(
      {
        name,
        subscriptionStatus: "trial",
        subscriptionPlan: "free",
        trialEndsAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days trial
      },
    )

    // Create owner user
    if (ownerName && ownerPhone && ownerUsername && ownerPassword) {
      // Check if user with this username already exists
      const existingUser = await User.findOne({
        where: { username: ownerUsername },
      })
      if (existingUser) {
        return res.status(400).json({ message: "User with this username already exists" })
      }

      // Create owner user
      const owner = await User.create(
        {
          name: ownerName,
          phone: ownerPhone,
          location: "Not specified",
          username: ownerUsername,
          password: ownerPassword,
          role: "owner",
          businessId: business.id,
        },
      )    

      // Create initial subscription
      await Subscription.create(
        {
          businessId: business.id,
          plan: "free",
          status: "active",
          startDate: new Date(),
          endDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days trial
          amount: 0,
        },
      )

      res.status(201).json({
        message: "Business created successfully",
        business: {
          id: business.id,
          name: business.name,
        },
        owner: {
          id: owner.id,
          name: owner.name,
        },
      })
    } else {
      res.status(400).json({ message: "Owner information is required" })
    }
  } catch (error) {
    res.status(500).json({ message: "Error creating business", error: error.message })
  }
}

// Get all businesses (admin only)
export const getAllBusinesses = async (req, res) => {
  try {
    const businesses = await Business.findAll({
      include: [
        {
          model: User,
          where: { role: "owner" },
          attributes: ["id", "name", "phone"],
          required: false,
        },
        {
          model: Subscription,
          where: { status: "active" },
          required: false,
          order: [["createdAt", "DESC"]],
          limit: 1,
        },
      ],
    })

    res.json(businesses)
  } catch (error) {
    console.log("errr in listing businesses: ", error)
    res.status(500).json({ message: "Error fetching businesses", error: error.message })
  }
}

// Get business by ID
export const getBusinessById = async (req, res) => {
  try {
    const business = await Business.findByPk(req.params.id, {
      include: [
        {
          model: User,
          where: { role: "owner" },
          attributes: ["id", "name", "phone"],
          required: false,
        },
        {
          model: Subscription,
          where: { status: "active" },
          required: false,
          order: [["createdAt", "DESC"]],
          limit: 1,
        },
      ],
    })

    if (!business) {
      return res.status(404).json({ message: "Business not found" })
    }

    // Check if user belongs to this business or is admin
    if (req.user.role !== "admin" && req.user.businessId !== business.id) {
      return res.status(403).json({ message: "Not authorized to view this business" })
    }

    res.json(business)
  } catch (error) {
    res.status(500).json({ message: "Error fetching business", error: error.message })
  }
}

// Update business
export const updateBusiness = async (req, res) => {
  try {
    const { name, address, phone, logo } = req.body
    const business = await Business.findByPk(req.params.id)

    if (!business) {
      return res.status(404).json({ message: "Business not found" })
    }

    // Check if user is owner of this business or admin
    if (req.user.role !== "admin" && (req.user.role !== "owner" || req.user.businessId !== business.id)) {
      return res.status(403).json({ message: "Not authorized to update this business" })
    }

    // Update business
    if (name) business.name = name
    if (address) business.address = address
    if (phone) business.phone = phone
    if (logo) business.logo = logo

    await business.save()

    res.json(business)
  } catch (error) {
    res.status(500).json({ message: "Error updating business", error: error.message })
  }
}

// Update subscription
export const updateSubscription = async (req, res) => {
  try {
    const { plan, status, endDate, paymentMethod, paymentId, amount, currency, isAutoRenew } = req.body
    const business = await Business.findByPk(req.params.id)

    if (!business) {
      return res.status(404).json({ message: "Business not found" })
    }

    // Only admin can update subscription
    if (req.user.role !== "admin") {
      return res.status(403).json({ message: "Not authorized to update subscription" })
    }

    // Update business subscription status
    business.subscriptionStatus = status || business.subscriptionStatus
    business.subscriptionPlan = plan || business.subscriptionPlan
    business.subscriptionEndsAt = endDate ? new Date(endDate) : business.subscriptionEndsAt

    await business.save()

    // Create new subscription record
    const subscription = await Subscription.create({
      businessId: business.id,
      plan: plan || "free",
      status: status || "active",
      startDate: new Date(),
      endDate: endDate ? new Date(endDate) : null,
      paymentMethod,
      paymentId,
      amount: amount || 0,
      currency: currency || "USD",
      isAutoRenew: isAutoRenew !== undefined ? isAutoRenew : true,
    })

    res.json({
      business: {
        id: business.id,
        name: business.name,
        subscriptionStatus: business.subscriptionStatus,
        subscriptionPlan: business.subscriptionPlan,
        subscriptionEndsAt: business.subscriptionEndsAt,
      },
      subscription,
    })
  } catch (error) {
    res.status(500).json({ message: "Error updating subscription", error: error.message })
  }
}

// Get business statistics
export const getBusinessStats = async (req, res) => {
  try {
    const businessId = req.params.id

    // Check if business exists
    const business = await Business.findByPk(businessId)
    if (!business) {
      return res.status(404).json({ message: "Business not found" })
    }

    // Check if user belongs to this business or is admin
    if (req.user.role !== "admin" && req.user.businessId !== businessId) {
      return res.status(403).json({ message: "Not authorized to view this business stats" })
    }

    // Get user count
    const userCount = await User.count({
      where: { businessId },
    })

    // Get item count
    const itemCount = await Item.count({
      where: { businessId },
    })

    // Get total sales
    const salesData = await SoldItem.findAll({
      where: { businessId },
      attributes: [
        [sequelize.fn("sum", sequelize.col("amount")), "totalSales"],
        [sequelize.fn("count", sequelize.col("id")), "salesCount"],
      ],
    })

    // Get sales by month for the last 12 months
    const oneYearAgo = new Date();
    oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);

    const salesByMonth = await SoldItem.findAll({
      where: {
        businessId,
        soldTime: {
          [Op.gte]: oneYearAgo,
        },
      },
      attributes: [
        [sequelize.fn("to_char", sequelize.col("soldTime"), "YYYY-MM"), "month"],
        [sequelize.fn("sum", sequelize.col("amount")), "total"],
      ],
      group: [sequelize.fn("to_char", sequelize.col("soldTime"), "YYYY-MM")],
      order: [[sequelize.fn("to_char", sequelize.col("soldTime"), "YYYY-MM"), "ASC"]],
    })

    res.json({
      userCount,
      itemCount,
      totalSales: salesData[0]?.dataValues.totalSales || 0,
      salesCount: salesData[0]?.dataValues.salesCount || 0,
      salesByMonth: salesByMonth.map(item => ({
        month: item.getDataValue('month'),
        total: parseFloat(item.getDataValue('total')) || 0
      })),
    })
  } catch (error) {
    console.error("Error fetching business stats:", error);
    res.status(500).json({ message: "Error fetching business stats", error: error.message })
  }
}
