import sequelize from './models/database.js';
import { DataTypes } from 'sequelize';
import { ItemBought, AvailableItem, Shop } from './models/index.js';

async function updateBoughtToShop() {
  const transaction = await sequelize.transaction();
  
  try {
    console.log('Starting database update...');
    
    // Check if shopId column exists in ItemBoughts
    const itemBoughtTableInfo = await sequelize.getQueryInterface().describeTable('ItemBoughts');
    console.log('ItemBought table columns:', Object.keys(itemBoughtTableInfo));
    
    // Add shopId column to ItemBoughts if it doesn't exist
    if (!itemBoughtTableInfo.shopId) {
      console.log('Adding shopId column to ItemBoughts...');
      await sequelize.getQueryInterface().addColumn('ItemBoughts', 'shopId', {
        type: sequelize.DataTypes.UUID,
        allowNull: true,
        references: {
          model: 'Shops',
          key: 'id'
        }
      }, { transaction });
    }
    
    // Add shopId column to AvailableItems if it doesn't exist
    const availableItemTableInfo = await sequelize.getQueryInterface().describeTable('AvailableItems');
    console.log('AvailableItem table columns:', Object.keys(availableItemTableInfo));
    
    if (!availableItemTableInfo.shopId) {
      console.log('Adding shopId column to AvailableItems...');
      await sequelize.getQueryInterface().addColumn('AvailableItems', 'shopId', {
        type: DataTypes.UUID,
        allowNull: true,
        references: {
          model: 'Shops',
          key: 'id'
        }
      }, { transaction });
    }
    
    // Update existing ItemBought records to assign them to a default shop
    console.log('Updating existing ItemBought records...');
    const businesses = await sequelize.query(
      'SELECT DISTINCT "businessId" FROM "ItemBoughts" WHERE "shopId" IS NULL',
      { type: sequelize.QueryTypes.SELECT, transaction }
    );
    
    console.log('Found businesses:', businesses.length);
    
    for (const business of businesses) {
      const defaultShop = await sequelize.query(
        'SELECT id FROM "Shops" WHERE "businessId" = :businessId LIMIT 1',
        { 
          replacements: { businessId: business.businessId },
          type: sequelize.QueryTypes.SELECT,
          transaction 
        }
      );
      
      if (defaultShop.length > 0) {
        console.log(`Assigning ItemBoughts for business ${business.businessId} to shop ${defaultShop[0].id}`);
        await sequelize.query(
          'UPDATE "ItemBoughts" SET "shopId" = :shopId WHERE "businessId" = :businessId AND "shopId" IS NULL',
          { 
            replacements: { 
              shopId: defaultShop[0].id,
              businessId: business.businessId 
            },
            transaction 
          }
        );
      } else {
        console.log(`No shop found for business ${business.businessId}`);
      }
    }
    
    // Update existing AvailableItem records
    console.log('Updating existing AvailableItem records...');
    const availableItemBusinesses = await sequelize.query(
      'SELECT DISTINCT "businessId" FROM "AvailableItems" WHERE "shopId" IS NULL',
      { type: sequelize.QueryTypes.SELECT, transaction }
    );
    
    console.log('Found AvailableItem businesses:', availableItemBusinesses.length);
    
    for (const business of availableItemBusinesses) {
      const defaultShop = await sequelize.query(
        'SELECT id FROM "Shops" WHERE "businessId" = :businessId LIMIT 1',
        { 
          replacements: { businessId: business.businessId },
          type: sequelize.QueryTypes.SELECT,
          transaction 
        }
      );
      
      if (defaultShop.length > 0) {
        console.log(`Assigning AvailableItems for business ${business.businessId} to shop ${defaultShop[0].id}`);
        await sequelize.query(
          'UPDATE "AvailableItems" SET "shopId" = :shopId WHERE "businessId" = :businessId AND "shopId" IS NULL',
          { 
            replacements: { 
              shopId: defaultShop[0].id,
              businessId: business.businessId 
            },
            transaction 
          }
        );
      } else {
        console.log(`No shop found for AvailableItem business ${business.businessId}`);
      }
    }
    
    // Make shopId NOT NULL for ItemBoughts
    console.log('Making shopId NOT NULL for ItemBoughts...');
    await sequelize.getQueryInterface().changeColumn('ItemBoughts', 'shopId', {
      type: DataTypes.UUID,
      allowNull: false,
      references: {
        model: 'Shops',
        key: 'id'
      }
    }, { transaction });
    
    // Make shopId NOT NULL for AvailableItems
    console.log('Making shopId NOT NULL for AvailableItems...');
    await sequelize.getQueryInterface().changeColumn('AvailableItems', 'shopId', {
      type: DataTypes.UUID,
      allowNull: false,
      references: {
        model: 'Shops',
        key: 'id'
      }
    }, { transaction });
    
    // Remove salesmanId column from ItemBoughts if it exists
    if (itemBoughtTableInfo.salesmanId) {
      console.log('Removing salesmanId column from ItemBoughts...');
      await sequelize.getQueryInterface().removeColumn('ItemBoughts', 'salesmanId', { transaction });
    }
    
    // Remove salesmanId column from AvailableItems if it exists
    if (availableItemTableInfo.salesmanId) {
      console.log('Removing salesmanId column from AvailableItems...');
      await sequelize.getQueryInterface().removeColumn('AvailableItems', 'salesmanId', { transaction });
    }
    
    await transaction.commit();
    console.log('Database update completed successfully!');
    
  } catch (error) {
    await transaction.rollback();
    console.error('Error updating database:', error);
    throw error;
  } finally {
    await sequelize.close();
  }
}

updateBoughtToShop().catch(console.error); 