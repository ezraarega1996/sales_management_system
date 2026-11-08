import { ItemBought, Item, Fraction, AvailableItem, SoldItem, Shop } from "../models/index.js"
import sequelize from "../models/database.js"
import { parse } from "dotenv"

export const getAllBoughts = async (req, res) => {
  try {
    const boughts = await ItemBought.findAll({
      where: { businessId: req.user.businessId },
      include: [
        { 
          model: Item,
          include: [{ model: Fraction, as: "fractions" }]
        },
        {
          model: Shop,
          attributes: ['id', 'name', 'address']
        },
      ],
      order: [["createdTime", "DESC"]],
    })
    res.json(boughts)
  } catch (error) {
    console.log("errr in listing boughts: ", error)
    res.status(500).json({ message: "Error fetching bought items", error: error.message })
  }
}

export const getBoughtById = async (req, res) => {
  try {
    const bought = await ItemBought.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
      include: [
        { 
           model: Item,
          include: [{ model: Fraction, as: "fractions" }]
        },
        {
          model: Shop,
          attributes: ['id', 'name', 'address']
        },
      ],
    })

    if (!bought) {
      return res.status(404).json({ message: "Bought item not found" })
    }

    res.json(bought)
  } catch (error) {
    res.status(500).json({ message: "Error fetching bought item", error: error.message })
  }
}

// Helper function to convert quantity to unit fraction
async function convertToUnitQuantity(itemId, fractionId, quantity) {
  const fraction = await Fraction.findOne({
    where: { id: fractionId }
  });
  if (!fraction) {
    throw new Error('Fraction not found');
  }
  // If this is already a unit fraction, return the quantity as is
  if (fraction.isUnit) {
    return quantity;
  }

  // Find the unit fraction for this item
  const unitFraction = await Fraction.findOne({
    where: {
      itemId,
      isUnit: true
    }
  });
  if (!unitFraction) {
    throw new Error('Unit fraction not found for this item');
  }
  // Convert quantity to unit fraction equivalent
  return (quantity * fraction.ratio) / unitFraction.ratio;
}

export const createBought = async (req, res) => {
  console.log("createBought started")
  console.log("Request body:", req.body)
  console.log("Request user:", req.user)
  console.log("Request headers:", req.headers)
  
  const transaction = await sequelize.transaction()
  try {
    const { itemId, fractionId, fractionPurchasePrice, fractionSoldPrice, quantity, expiryDate, shopId } = req.body

    console.log("Extracted data:", { itemId, fractionId, fractionPurchasePrice, fractionSoldPrice, quantity, expiryDate, shopId })

    // Check if item exists and belongs to the business
    const item = await Item.findOne({
      where: {
        id: itemId,
        businessId: req.user.businessId,
      },
    })

    console.log("Found item:", item)

    if (!item) {
      await transaction.rollback()
      return res.status(404).json({ message: "Item not found" })
    }

    // Check if shop exists and belongs to the business
    const shop = await Shop.findOne({
      where: {
        id: shopId,
        businessId: req.user.businessId,
      },
    })

    console.log("Found shop:", shop)

    if (!shop) {
      await transaction.rollback()
      return res.status(404).json({ message: "Shop not found" })
    }

    // Get the fraction being used
    const fraction = await Fraction.findOne({
      where: { id: fractionId }
    })

    console.log("Found fraction:", fraction)

    if (!fraction) {
      await transaction.rollback()
      return res.status(404).json({ message: "Fraction not found" })
    }

    // Convert quantity to units based on fraction ratio
    const quantityInUnits = quantity * fraction.ratio

    // Find existing available item for this shop
    const existingAvailableItem = await AvailableItem.findOne({
      where: {
        itemId,
        businessId: req.user.businessId,
        shopId: shopId,
      },
      transaction
    })

    let availableItem;
    if (existingAvailableItem) {
      // Update existing available item by adding the new quantity
      existingAvailableItem.quantity = quantityInUnits + parseFloat(existingAvailableItem.quantity)
      existingAvailableItem.soldPrice = fractionSoldPrice
      await existingAvailableItem.save({ transaction })
      availableItem = existingAvailableItem;
    } else {
      // Create new available item with the current quantity
      availableItem = await AvailableItem.create({
        itemId,
        businessId: req.user.businessId,
        quantity: quantityInUnits,
        soldPrice: fractionSoldPrice,
        shopId,
      }, { transaction })
    }

    // Create bought item
    const bought = await ItemBought.create({
      itemId,
      fractionId,
      fractionPurchasePrice,
      fractionSoldPrice,
      quantity,
      expiryDate: expiryDate || null,
      businessId: req.user.businessId,
      shopId,
      available_items_count: availableItem.quantity / fraction.ratio,
      availableItemId: availableItem.id,
    }, { transaction })

    // Fetch the created bought item with its item and shop
    const createdBought = await ItemBought.findByPk(bought.id, {
      include: [
        { model: Item },
        { model: Shop, attributes: ['id', 'name', 'address'] },
        { model: AvailableItem }
      ],
      transaction
    })

    await transaction.commit()
    console.log("saved data.");
    res.status(201).json(createdBought)
  } catch (error) {
    console.log("error while creating boughtItems: ", error);
    await transaction.rollback()
    res.status(500).json({ message: "Error creating bought item", error: error.message })
  }
}

export const updateBought = async (req, res) => {
  const transaction = await sequelize.transaction()
  try {
    const { fractionId, fractionPurchasePrice, fractionSoldPrice, quantity,  expiryDate, shopId } = req.body
    console.log("one");
    const bought = await ItemBought.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
      transaction
    })
    console.log("two");

    if (!bought) {
      await transaction.rollback()
      return res.status(404).json({ message: "Bought item not found" })
    }

    // Check if shop exists and belongs to the business
    if (shopId) {
      const shop = await Shop.findOne({
        where: {
          id: shopId,
          businessId: req.user.businessId,
        },
        transaction
      })

      if (!shop) {
        await transaction.rollback()
        return res.status(404).json({ message: "Shop not found" })
      }
    }
    console.log("three");

    // Get the fraction being used
    const fraction = await Fraction.findOne({
      where: { id: fractionId || bought.fractionId }
    })

    if (!fraction) {
      await transaction.rollback()
      return res.status(404).json({ message: "Fraction not found" })
    }

    // Convert quantity to units based on fraction ratio
    const quantityInUnits = (quantity || bought.quantity) * fraction.ratio
    console.log("four");

    // Update available item
    if (bought.availableItemId) {
      const availableItem = await AvailableItem.findByPk(bought.availableItemId, { transaction })
      if (availableItem) {
        // Remove old quantity from available item
        availableItem.quantity = parseFloat(availableItem.quantity) - (bought.quantity * fraction.ratio)
        if (availableItem.quantity <= 0) {
          await availableItem.destroy({ transaction })
        } else {
          await availableItem.save({ transaction })
        }
      }
    }
    console.log("five");

    // Find or create available item for the new shop
    const newShopId = shopId || bought.shopId
    const existingAvailableItem = await AvailableItem.findOne({
      where: {
        itemId: bought.itemId,
        businessId: req.user.businessId,
        shopId: newShopId,
      },
      transaction
    })
    console.log("six");

    let availableItem;
    if (existingAvailableItem) {
      // Update existing available item by adding the new quantity
      existingAvailableItem.quantity = quantityInUnits + parseFloat(existingAvailableItem.quantity)
      existingAvailableItem.soldPrice = fractionSoldPrice || bought.fractionSoldPrice
      await existingAvailableItem.save({ transaction })
      availableItem = existingAvailableItem;
    } else {
      // Create new available item with the current quantity
      availableItem = await AvailableItem.create({
        itemId: bought.itemId,
        businessId: req.user.businessId,
        quantity: quantityInUnits,
        soldPrice: fractionSoldPrice || bought.fractionSoldPrice,
        shopId: newShopId,
      }, { transaction })
    }
    console.log("seven");

    // Update bought item
    await bought.update({
      fractionId: fractionId || bought.fractionId,
      fractionPurchasePrice: fractionPurchasePrice || bought.fractionPurchasePrice,
      fractionSoldPrice: fractionSoldPrice || bought.fractionSoldPrice,
      quantity: quantity || bought.quantity,
      expiryDate: expiryDate || bought.expiryDate,
      shopId: newShopId,
      available_items_count: availableItem.quantity / fraction.ratio,
      availableItemId: availableItem.id,
    }, { transaction })
    console.log("eight");

    // Fetch the updated bought item with its item and shop
    const updatedBought = await ItemBought.findByPk(bought.id, {
      include: [
        { model: Item },
        { model: Shop, attributes: ['id', 'name', 'address'] },
        { model: AvailableItem }
      ],
      transaction
    })
    console.log("nine");
    await transaction.commit()
    res.json(updatedBought)
  } catch (error) {
    console.log("error: ", error);

    await transaction.rollback()
    res.status(500).json({ message: "Error updating bought item", error: error.message })
  }
}

export const deleteBought = async (req, res) => {
  const transaction = await sequelize.transaction()
  try {
    const bought = await ItemBought.findOne({
      where: {
        id: req.params.id,
        businessId: req.user.businessId,
      },
      transaction
    })

    if (!bought) {
      await transaction.rollback()
      return res.status(404).json({ message: "Bought item not found" })
    }

    // Update available item
    if (bought.availableItemId) {
      const availableItem = await AvailableItem.findByPk(bought.availableItemId, { transaction })
      if (availableItem) {
        // Get the fraction to calculate the quantity to remove
        const fraction = await Fraction.findOne({
          where: { id: bought.fractionId }
        })
        
        if (fraction) {
          const quantityToRemove = bought.quantity * fraction.ratio
          availableItem.quantity = parseFloat(availableItem.quantity) - quantityToRemove
          
          if (availableItem.quantity <= 0) {
            await availableItem.destroy({ transaction })
          } else {
            await availableItem.save({ transaction })
          }
        }
      }
    }

    await bought.destroy({ transaction })
    await transaction.commit()
    res.json({ message: "Bought item deleted successfully" })
  } catch (error) {
    await transaction.rollback()
    res.status(500).json({ message: "Error deleting bought item", error: error.message })
  }
}
