import { SoldItem, Item, User, Fraction, AvailableItem, sequelize } from "../models/index.js"
import { Op } from "sequelize"

export const getAllSales = async (req, res) => {
  try {
    const sales = await SoldItem.findAll({
      where: { businessId: req.user.businessId },
      include: [
        { 
           model: Item,
          include: [{ model: Fraction, as: "fractions" }]
        }, 
        { model: User, as: "salesman", attributes: ["id", "name", "username"] }
      ],
      order: [["soldTime", "DESC"]],
    })

    // Transform the response to include fraction data directly
    const transformedSales = sales.map(sale => {
      const saleJson = sale.toJSON();
      const fraction = saleJson.Item?.Fractions?.findOne(f => f.id === saleJson.fractionId);
      if (fraction) {
        saleJson.fraction = fraction;
      }
      return saleJson;
    });

    res.json(transformedSales)
  } catch (error) {
    console.log("errr in listing sales: ", error)
    res.status(500).json({ message: "Error fetching sales", error: error.message })
  }
}

export const getSaleById = async (req, res) => {
  try {
    const sale = await SoldItem.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
      include: [
        { 
           model: Item,
          include: [{ model: Fraction, as: "fractions" }]
        }, 
        { model: User, as: "salesman", attributes: ["id", "name", "username"] }
      ],
    })

    if (!sale) {
      return res.status(404).json({ message: "Sale not found" })
    }

    // Transform the response to include fraction data directly
    const saleJson = sale.toJSON();
    const fraction = saleJson.Item?.Fractions?.find(f => f.id === saleJson.fractionId);
    if (fraction) {
      saleJson.fraction = fraction;
    }

    res.json(saleJson)
  } catch (error) {
    res.status(500).json({ message: "Error fetching sale", error: error.message })
  }
}

export const createSale = async (req, res) => {
  try {
    const { itemId, fractionId, quantity, amount, shopId, profit } = req.body;
    const salesmanId = req.user.id;

    // Always prefer the shopId coming from the frontend (it is derived from the
    // selected AvailableItem's shop). Fallback to the user's assigned shopId
    // only if the payload omits it.
    const selectedShopId = shopId || req.user.shopId;

    if (!selectedShopId) {
      return res.status(400).json({ message: "shopId is required to create a sale" });
    }
    console.log("selectedShopId: ", selectedShopId)
    // Validate required fields
    if (!itemId || !fractionId || !quantity || !amount) {
      return res.status(400).json({ message: 'All fields are required' });
    }
    // Get item and fraction details
    const item = await Item.findByPk(itemId, {
      include: [{ model: Fraction, as: 'fractions' }]
    });
    if (!item) {
      return res.status(404).json({ message: 'Item not found' });
    }

    const fraction = item.fractions.find(f => f.id === fractionId);
    if (!fraction) {
      return res.status(404).json({ message: 'Fraction not found' });
    }

    // Convert quantity to units based on fraction ratio
    const quantityInUnits = quantity * fraction.ratio;

    // Update available items
    const availableItem = await AvailableItem.findOne({
      where: {
        itemId,
        shopId: selectedShopId,
        businessId: req.user.businessId,
      },
    });

    if (!availableItem) {
      return res.status(400).json({ message: 'No available items found for this item' });
    }

    if (availableItem.quantity < quantityInUnits) {
      return res.status(400).json({ message: 'Not enough quantity available' });
    }

    availableItem.quantity = parseFloat(availableItem.quantity) - quantityInUnits;
    await availableItem.save();

    // Create sale
    const sale = new SoldItem({
      itemId,
      fractionId,
      quantity,
      amount,
      expectedAmount: amount,
      salesmanId,
      businessId: req.user.businessId,
      available_items_count: availableItem.quantity / fraction.ratio,
      availableItemId: availableItem.id,
      shopId: selectedShopId,
      // Use profit calculated on the frontend if provided; otherwise fall back to 0
      profit: typeof profit === "number" ? profit : 0,
    });

    await sale.save();

    // Fetch the created sale with its related data
    const createdSale = await SoldItem.findByPk(sale.id, {
      include: [
        { model: Item, include: [{ model: Fraction, as: 'fractions' }] },
        { model: User, as: 'salesman', attributes: ['id', 'name', 'username'] },
        { model: AvailableItem }
      ]
    });

    res.status(201).json(createdSale);
  } catch (error) {
    res.status(500).json({ message: 'Error creating sale', error: error.message });
  }
};

export const updateSale = async (req, res) => {
  try {
    const { quantity, amount, expectedAmount, status, existing } = req.body

    const sale = await SoldItem.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
    })

    if (!sale) {
      return res.status(404).json({ message: "Sale not found" })
    }

    // Check if user is owner or the salesman who created the sale
    if (req.user.role !== "owner" && req.user.role !== "admin" && sale.salesmanId !== req.user.id) {
      return res.status(403).json({ message: "Not authorized to update this sale" })
    }

    // Update sale
    if (quantity !== undefined) sale.quantity = quantity
    if (amount !== undefined) sale.amount = amount
    if (expectedAmount !== undefined) sale.expectedAmount = expectedAmount
    if (status !== undefined) sale.status = status
    if (existing !== undefined) sale.existing = existing

    await sale.save()

    // Fetch the updated sale with its item and salesman
    const updatedSale = await SoldItem.findByPk(sale.id, {
      include: [{ model: Item }, { model: User, as: "salesman", attributes: ["id", "name", "username"] }],
    })

    res.json(updatedSale)
  } catch (error) {
    res.status(500).json({ message: "Error updating sale", error: error.message })
  }
}

export const deleteSale = async (req, res) => {
  try {
    const sale = await SoldItem.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
    })

    if (!sale) {
      return res.status(404).json({ message: "Sale not found" })
    }

    // Only owner or admin can delete sales
    if (req.user.role !== "owner" && req.user.role !== "admin") {
      return res.status(403).json({ message: "Not authorized to delete sales" })
    }

    await sale.destroy()

    res.json({ message: "Sale deleted successfully" })
  } catch (error) {
    res.status(500).json({ message: "Error deleting sale", error: error.message })
  }
}

export const getSalesByUser = async (req, res) => {
  try {
    const sales = await SoldItem.findAll({
      where: {
        salesmanId: req.user.id,
        businessId: req.user.businessId,
      },
      include: [
        { 
           model: Item,
          include: [{ model: Fraction, as: "fractions" }]
        },
        { model: User, as: "salesman", attributes: ["id", "name", "username"] }
      ],
      order: [["soldTime", "DESC"]],
    })
    res.json(sales)
  } catch (error) {
    res.status(500).json({ message: "Error fetching sales", error: error.message })
  }
}

export const getDashboardStats = async (req, res) => {
  try {
    // Get total sales amount for this business
    const totalSales = await SoldItem.sum("amount", {
      where: { businessId: req.user.businessId },
    })

    // Get today's sales amount for this business
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);

    const todaySales = await SoldItem.sum("amount", {
      where: {
      businessId: req.user.businessId,
      soldTime: {
        [Op.gte]: startOfToday,
      },
      },
    });
    // Get sales count for this business
    const salesCount = await SoldItem.count({
      where: { businessId: req.user.businessId },
    })

    // Get sales by day for the last 30 days for this business
    const salesByDay = await SoldItem.findAll({
      attributes: [
        [sequelize.fn("date", sequelize.col("soldTime")), "date"],
        [sequelize.fn("sum", sequelize.col("amount")), "total"],
      ],
      where: {
        businessId: req.user.businessId,
        soldTime: {
          [Op.gte]: new Date(new Date() - 30 * 24 * 60 * 60 * 1000), // Last 30 days
        },
      },
      group: [sequelize.fn("date", sequelize.col("soldTime"))],
      order: [[sequelize.fn("date", sequelize.col("soldTime")), "ASC"]],
    })


    // Get top selling items for this business
    const topItems = await SoldItem.findAll({
      attributes: [
        "itemId",
        [sequelize.fn("sum", sequelize.col("quantity")), "totalQuantity"],
        [sequelize.fn("sum", sequelize.col("amount")), "totalAmount"],
      ],
      where: { businessId: req.user.businessId },
      include: [
        {
          model: Item,
          attributes: ["name"],
        },
      ],
      group: ["itemId", "Item.id", "Item.name"],
      order: [[sequelize.fn("sum", sequelize.col("amount")), "DESC"]],
      limit: 5,
    })
    res.json({
      totalSales,
      salesCount,
      salesByDay,
      topItems,
      todaySales,
    })
  } catch (error) {
    console.error("Error fetching dashboard stats: ", error);
    res.status(500).json({ message: "Error fetching dashboard stats", error: error.message })
  }
}

export const getAvailableQuantity = async (req, res) => {
  try {
    const { itemId, fractionId } = req.query

    if (!itemId || !fractionId) {
      return res.status(400).json({ message: "Item ID and Fraction ID are required" })
    }

    // Get the fraction to calculate ratio
    const fraction = await Fraction.findOne({
      where: { id: fractionId }
    })

    if (!fraction) {
      return res.status(404).json({ message: "Fraction not found" })
    }

    // Get available item
    const availableItem = await AvailableItem.findOne({
      where: {
        itemId,
        businessId: req.user.businessId,
        // If user is a salesman, only show items assigned to them
        // If user is owner or admin, show all items
        salesmanId: req.user.role === 'salesman' ? req.user.id : null,
      }
    })

    if (!availableItem) {
      return res.json({ availableQuantity: 0 })
    }

    // Convert available quantity from units to the requested fraction
    const availableQuantity = availableItem.quantity / fraction.ratio

    res.json({ availableQuantity })
  } catch (error) {
    res.status(500).json({ message: "Error fetching available quantity", error: error.message })
  }
}
