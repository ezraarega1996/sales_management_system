import express from "express"
import cors from "cors"
import dotenv from "dotenv"
import { sequelize, syncDatabase } from "./models/index.js"
import authRoutes from "./routes/authRoutes.js"
import userRoutes from "./routes/userRoutes.js"
import categoryRoutes from "./routes/categoryRoutes.js"
import itemRoutes from "./routes/itemRoutes.js"
import fractionRoutes from "./routes/fractionRoutes.js"
import salesRoutes from "./routes/salesRoutes.js"
import businessRoutes from "./routes/businessRoutes.js"
import paymentRoutes from "./routes/paymentRoutes.js"
import boughtRoutes from "./routes/boughtRoutes.js"
import availableItemRoutes from "./routes/availableItemRoutes.js"
import shopRoutes from "./routes/shopRoutes.js"
import { connectWithRetry } from "./models/database.js"


dotenv.config()

// Set default environment variables for development
if (!process.env.JWT_SECRET) {
  process.env.JWT_SECRET = 'your-super-secret-jwt-key-change-this-in-production';
  console.log('⚠️  JWT_SECRET not set, using default for development');
}

if (!process.env.DATABASE_URL) {
  process.env.DATABASE_URL = 'postgres://postgres:root@localhost:5432/inventory_db';
  console.log('⚠️  DATABASE_URL not set, using default for development');
}

const app = express()
const PORT = process.env.PORT || 5000

// Middleware
app.use(cors())
app.use(express.json())

// Special handling for Stripe webhook
app.use("/api/payments/webhook", express.raw({ type: "application/json" }))

app.get("/", (req, res) => {
  res.send("Inventory Management API is running")
})

// Routes
app.use("/api/auth", authRoutes)
app.use("/api/users", userRoutes)
app.use("/api/categories", categoryRoutes)
app.use("/api/items", itemRoutes)
app.use("/api/fractions", fractionRoutes)
app.use("/api/sales", salesRoutes)
app.use("/api/businesses", businessRoutes)
app.use("/api/payments", paymentRoutes)
app.use("/api/boughts", boughtRoutes)
app.use("/api/available-items", availableItemRoutes)
app.use("/api/shops", shopRoutes)

// Test database connection
connectWithRetry().then(() => {
  app.listen(5000, '0.0.0.0', () => {
  console.log('Server is running on port 5000');
});
});


export default app
