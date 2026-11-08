import "dotenv/config"
import express from "express"
import cors from "cors"
import compression from "compression"
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

if (!process.env.JWT_SECRET) {
  process.env.JWT_SECRET = "your-super-secret-jwt-key-change-this-in-production"
  console.warn("⚠️  JWT_SECRET not set, using an insecure development default")
}

const app = express()
const PORT = process.env.PORT || 5000

app.use(cors())
// gzip responses: JSON lists shrink several times over, which matters most on slow mobile networks
app.use(compression())
// Stripe needs the raw body to verify webhook signatures, so it must skip the JSON parser
app.use((req, res, next) => (req.originalUrl === "/api/payments/webhook" ? next() : express.json()(req, res, next)))

app.get("/", (req, res) => {
  res.send("Inventory Management API is running")
})

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

connectWithRetry().then(() => {
  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server is running on port ${PORT}`)
  })
})

export default app
