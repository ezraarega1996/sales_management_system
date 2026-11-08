import { AvailableItem, Item, Bought, SoldItem, Fraction, User, ItemBought, Shop } from "../models/index.js"
import { Op, fn, col } from "sequelize"
import sequelize from "../models/database.js"

export const calculateAvailableItems = async (req, res) => {
  try {
    const { businessId } = req.user

    // Get all items for the business
    const items = await Item.findAll({
      where: { businessId },
      include: [
        {
          model: Bought,
          where: { businessId },
          required: false,
        },
        {
          model: SoldItem,
          where: { businessId },
          required: false,
        },
      ],
    })

    // Calculate available items for each item
    for (const item of items) {
      // Calculate total bought quantity
      const totalBought = item.Boughts?.reduce((sum, bought) => sum + bought.quantity, 0) || 0

      // Calculate total sold quantity
      const totalSold = item.SoldItems?.reduce((sum, sold) => sum + sold.quantity, 0) || 0

      // Calculate available quantity
      const availableQuantity = totalBought - totalSold

      // Get the latest sold price from bought items
      const latestBought = item.Boughts?.sort((a, b) => b.createdTime - a.createdTime)[0]
      const soldPrice = latestBought?.fractionSoldPrice || 0

      // Find existing available item
      const existingAvailableItem = await AvailableItem.findOne({
        where: {
          itemId: item.id,
          businessId,
        },
      });

      if (existingAvailableItem) {
        // Update existing available item
        await existingAvailableItem.update({
          quantity: availableQuantity,
          soldPrice,
        });
      } else {
        // Create new available item only if it doesn't exist
        await AvailableItem.create({
          itemId: item.id,
          businessId,
          quantity: availableQuantity,
          soldPrice,
        });
      }
    }

    // Fetch all available items with their items
    const availableItems = await AvailableItem.findAll({
      where: { businessId },
      include: [
        { 
           model: Item,
          include: [{ model: Fraction, as: "fractions" }]
        }
      ],
    })

    res.json(availableItems)
  } catch (error) {
    res.status(500).json({ message: "Error calculating available items", error: error.message })
  }
}

export const getAllAvailableItems = async (req, res) => {
  try {
    const { shopId } = req.query;
    const where = { businessId: req.user.businessId };
    // Only restrict by shopId for salesmen
    if (req.user.role === 'salesman') {
      where.shopId = req.user.shopId;
    } else if (shopId) {
      where.shopId = shopId;
    }
    const availableItems = await AvailableItem.findAll({
      where,
      include: [
        { 
          model: Item,
          as: 'item',
          include: [{ model: Fraction, as: "fractions" }]
        },
        {
          model: Shop,
          as: 'shop',
          attributes: ['id', 'name', 'address'],
        },
        {
          model: ItemBought,
          as: 'boughtTransactions',
          required: false,
          include: [
            {
              model: Fraction,
              attributes: ['id', 'name', 'ratio']
            }
          ]
        },
        {
          model: SoldItem,
          as: 'soldTransactions',
          required: false,
          include: [
            {
              model: User,
              as: 'salesman',
              attributes: ['id', 'name', 'username']
            }
          ]
        }
      ],
      order: [[sequelize.literal('LOWER("item"."name")'), 'ASC']],
    })

    res.json(availableItems)
  } catch (error) {
    console.log("error fetching available items.", error);
    res.status(500).json({ message: "Error fetching available items", error: error.message })
  }
}

export const getAvailableItemById = async (req, res) => {
  try {
    const availableItem = await AvailableItem.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
      include: [
        { 
          model: Item,
          include: [{ model: Fraction, as: "fractions" }]
        }
      ],
    })

    if (!availableItem) {
      return res.status(404).json({ message: "Available item not found" })
    }

    res.json(availableItem)
  } catch (error) {
    res.status(500).json({ message: "Error fetching available item", error: error.message })
  }
}

export const assignToShop = async (req, res) => {
  const transaction = await sequelize.transaction();
  try {
    const { shopId, quantity, soldPrice } = req.body;
    const { id } = req.params;

    // Find the available item
    const availableItem = await AvailableItem.findOne({
      where: {
        id,
        businessId: req.user.businessId,
      },
      transaction,
    });

    if (!availableItem) {
      await transaction.rollback();
      return res.status(404).json({ message: "Available item not found" });
    }

    if (quantity > availableItem.quantity) {
      await transaction.rollback();
      return res.status(400).json({ message: "Quantity cannot be greater than available quantity" });
    }

    // Create a new available item for the shop
    await AvailableItem.create({
      itemId: availableItem.itemId,
      businessId: req.user.businessId,
      quantity,
      soldPrice,
      shopId,
    }, { transaction });

    // Update the original available item
    await availableItem.update({
      quantity: availableItem.quantity - quantity,
    }, { transaction });

    await transaction.commit();
    res.json({ message: "Item assigned to shop successfully" });
  } catch (error) {
    await transaction.rollback();
    res.status(500).json({ message: "Error assigning item to shop", error: error.message });
  }
};

export const getTodaySalesBySalesman = async (req, res) => {
  try {
    const { businessId } = req.user;
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const salesBySalesman = await SoldItem.findAll({
      where: {
        businessId,
        createdAt: {
          [Op.gte]: today
        }
      },
      include: [
        {
          model: User,
          as: 'salesman',
          attributes: ['id', 'name', 'username']
        }
      ],
      attributes: [
        'salesmanId',
        [sequelize.fn('SUM', sequelize.col('amount')), 'totalAmount'],
        [sequelize.fn('COUNT', sequelize.col('SoldItem.id')), 'totalTransactions']
      ],
      group: ['salesmanId', 'salesman.id', 'salesman.name', 'salesman.username'],
    });

    // Calculate total sales for all salesmen
    const totalSales = salesBySalesman.reduce((sum, sale) => {
      return sum + parseFloat(sale.getDataValue('totalAmount') || 0);
    }, 0);

    // Format the response
    const formattedSales = salesBySalesman.map(sale => ({
      salesmanId: sale.getDataValue('salesmanId'),
      salesmanName: sale.salesman.name,
      totalAmount: parseFloat(sale.getDataValue('totalAmount') || 0),
      totalTransactions: parseInt(sale.getDataValue('totalTransactions') || 0)
    }));

    res.json({
      totalSales,
      salesBySalesman: formattedSales
    });
  } catch (error) {
    console.error("Error fetching today's sales by salesman:", error);
    res.status(500).json({ message: "Error fetching today's sales", error: error.message });
  }
}; 