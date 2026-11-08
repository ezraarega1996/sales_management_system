'use strict';

/** @type {import('sequelize-cli').Migration} */
module.exports = {
  async up(queryInterface, Sequelize) {
    // Create shops table
    await queryInterface.createTable('Shops', {
      id: {
        type: Sequelize.UUID,
        defaultValue: Sequelize.UUIDV4,
        primaryKey: true,
      },
      name: {
        type: Sequelize.STRING,
        allowNull: false,
      },
      address: {
        type: Sequelize.STRING,
        allowNull: false,
      },
      businessId: {
        type: Sequelize.UUID,
        allowNull: false,
        references: {
          model: 'Businesses',
          key: 'id',
        },
        onUpdate: 'CASCADE',
        onDelete: 'CASCADE',
      },
      isActive: {
        type: Sequelize.BOOLEAN,
        defaultValue: true,
      },
      createdAt: {
        type: Sequelize.DATE,
        defaultValue: Sequelize.NOW,
      },
      updatedAt: {
        type: Sequelize.DATE,
        defaultValue: Sequelize.NOW,
      },
    });

    // Add shopId to Users table
    await queryInterface.addColumn('Users', 'shopId', {
      type: Sequelize.UUID,
      allowNull: true,
      references: {
        model: 'Shops',
        key: 'id',
      },
      onUpdate: 'CASCADE',
      onDelete: 'SET NULL',
    });

    // Add shopId to ItemBoughts table
    await queryInterface.addColumn('ItemBoughts', 'shopId', {
      type: Sequelize.UUID,
      allowNull: true,
      references: {
        model: 'Shops',
        key: 'id',
      },
      onUpdate: 'CASCADE',
      onDelete: 'SET NULL',
    });
  },

  async down(queryInterface, Sequelize) {
    // Remove shopId from ItemBoughts table
    await queryInterface.removeColumn('ItemBoughts', 'shopId');
    
    // Remove shopId from Users table
    await queryInterface.removeColumn('Users', 'shopId');
    
    // Drop shops table
    await queryInterface.dropTable('Shops');
  }
}; 