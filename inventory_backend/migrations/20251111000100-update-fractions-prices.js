'use strict';

/** @type {import('sequelize-cli').Migration} */
module.exports = {
  async up(queryInterface, Sequelize) {
    // Rename existing price column to sellingPrice if it exists
    const tableDesc = await queryInterface.describeTable('Fractions');
    if (tableDesc.price) {
      await queryInterface.renameColumn('Fractions', 'price', 'sellingPrice');
    }
    // Add purchasePrice column if missing
    if (!tableDesc.purchasePrice) {
      await queryInterface.addColumn('Fractions', 'purchasePrice', {
        type: Sequelize.FLOAT,
        allowNull: false,
        defaultValue: 0,
      });
    }
  },

  async down(queryInterface, Sequelize) {
    // Remove purchasePrice column if exists
    const tableDesc = await queryInterface.describeTable('Fractions');
    if (tableDesc.purchasePrice) {
      await queryInterface.removeColumn('Fractions', 'purchasePrice');
    }
    // Rename sellingPrice back to price if exists
    if (tableDesc.sellingPrice) {
      await queryInterface.renameColumn('Fractions', 'sellingPrice', 'price');
    }
  }
};


