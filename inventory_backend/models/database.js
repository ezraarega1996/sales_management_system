import dotenv from 'dotenv';
import { Sequelize } from 'sequelize';

dotenv.config();

const sequelize = new Sequelize(process.env.DATABASE_URL, {
  dialect: "postgres",
  dialectOptions: {
    ssl: false
  },
  logging: false,
});

const connectWithRetry = async (retries = 10, delay = 5000) => {
  while (retries) {
    try {
      await sequelize.authenticate();
      console.log('✅ Connected to DB');
      await syncDatabase();
      return;
    } catch (err) {
      console.error(`❌ DB connection failed. Retries left: ${retries - 1}`);
      console.error(err.message);
      retries--;
      await new Promise(res => setTimeout(res, delay));
    }
  }

  console.error('❌ All retries exhausted. Exiting.');
  process.exit(1);
};

/**
 * Adds columns that exist in the models but not yet in the database (new features add columns,
 * and production never runs `alter`). Only ever ADDS columns: nothing is changed or dropped.
 * A required column without a default is added as nullable, so existing rows don't block it.
 */
const addMissingColumns = async () => {
  const qi = sequelize.getQueryInterface();
  for (const model of Object.values(sequelize.models)) {
    const table = model.getTableName();
    let existing;
    try {
      existing = await qi.describeTable(table);
    } catch {
      continue; // table doesn't exist yet: sync() creates it with every column
    }
    for (const [name, attribute] of Object.entries(model.getAttributes())) {
      const column = attribute.field || name;
      if (existing[column]) continue;
      const definition = { ...attribute };
      delete definition.references; // keep it a plain column; constraints stay as they are
      if (definition.allowNull === false && definition.defaultValue === undefined) definition.allowNull = true;
      await qi.addColumn(table, column, definition);
      console.log(`➕ Added missing column ${typeof table === 'string' ? table : table.tableName}.${column}`);
    }
  }
};

// `alter` inspects (and may rewrite) every table, which is slow and risky in production,
// so production only adds missing columns (above) and creates missing tables.
const syncDatabase = async () => {
  try {
    if (process.env.NODE_ENV === 'production') await addMissingColumns();
    await sequelize.sync({ alter: process.env.NODE_ENV !== 'production' });
    console.log('✅ Database synchronized');
  } catch (error) {
    console.error('❌ Database synchronization failed:', error.message);
    throw error;
  }
};

export { connectWithRetry, syncDatabase, addMissingColumns };
export default sequelize;
