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
      return syncDatabase()
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

const syncDatabase = async () => {
  try {
    await sequelize.sync({ alter: true });
    console.log('✅ Database synchronized');
  } catch (error) {
    console.error('❌ Database synchronization failed:', error.message);
    throw error;
  }
};

export { connectWithRetry, syncDatabase };
export default sequelize;
