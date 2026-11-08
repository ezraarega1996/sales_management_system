// Sample data seeder for local development.
//
//   npm run seed            -> adds sample data next to existing data (skips if already seeded)
//   npm run seed -- --reset -> wipes ALL tables (including your own data) first, then seeds
//
// Mirrors the controllers' logic:
//   - AvailableItem.quantity is stored in base units (quantity * fraction.ratio)
//   - available_items_count = remaining base units / fraction.ratio
//   - sale amount = sellingPrice * qty, profit = (sellingPrice - purchasePrice) * qty
import "dotenv/config"
import {
  sequelize,
  Business,
  Subscription,
  Shop,
  User,
  Category,
  Item,
  Fraction,
  AvailableItem,
  ItemBought,
  SoldItem,
} from "./models/index.js"

const RESET = process.argv.includes("--reset")

// Deterministic pseudo-random numbers so every seed run produces the same data
let rngState = 42
const rand = () => {
  rngState = (rngState * 1664525 + 1013904223) % 4294967296
  return rngState / 4294967296
}
const randInt = (min, max) => Math.floor(rand() * (max - min + 1)) + min
const pick = (arr) => arr[Math.floor(rand() * arr.length)]

const daysAgo = (days, hour = 10, minute = 0) => {
  const d = new Date()
  d.setDate(d.getDate() - days)
  d.setHours(hour, minute, 0, 0)
  return d
}
const daysFromNow = (days) => {
  const d = new Date()
  d.setDate(d.getDate() + days)
  return d
}

// Sequelize always stamps createdAt with "now" on create, so backdate with a raw update
const backdate = (table, id, date, extraCols = []) => {
  const sets = ['"createdAt" = :date', '"updatedAt" = :date', ...extraCols.map((c) => `"${c}" = :date`)]
  return sequelize.query(`UPDATE "${table}" SET ${sets.join(", ")} WHERE id = :id`, {
    replacements: { id, date },
  })
}

// ---------------------------------------------------------------------------
// Data definitions
// ---------------------------------------------------------------------------
const BUSINESSES = [
  {
    business: {
      name: "Addis Mini Market",
      address: "Bole Road, Addis Ababa",
      phone: "+251911000001",
      email: "info@addisminimarket.et",
      subscriptionStatus: "active",
      subscriptionPlan: "premium",
      subscriptionEndsAt: daysFromNow(25),
    },
    subscription: { plan: "premium", status: "active", amount: 29.99, startedDaysAgo: 5, durationDays: 30, paymentMethod: "card" },
    owner: { name: "Abebe Kebede", username: "owner1", phone: "+251911100001", location: "Addis Ababa" },
    shops: [
      {
        name: "Bole Branch",
        address: "Bole, near Edna Mall",
        salesmen: [
          { name: "Sara Tesfaye", username: "sales1", phone: "+251911200001", location: "Bole" },
          { name: "Dawit Alemu", username: "sales2", phone: "+251911200002", location: "Bole" },
        ],
      },
      {
        name: "Piassa Branch",
        address: "Piassa, Churchill Ave",
        salesmen: [{ name: "Hana Girma", username: "sales3", phone: "+251911200003", location: "Piassa" }],
      },
    ],
    catalog: [
      {
        category: "Beverages",
        items: [
          { name: "Coca-Cola 330ml", fractions: [["Bottle", 1, 25, 18, true], ["Crate (24)", 24, 576, 410]], buy: [1, 24], buyFraction: 1 },
          { name: "Water 1L", fractions: [["Bottle", 1, 20, 13, true], ["Pack (12)", 12, 228, 150]], buy: [2, 12], buyFraction: 1 },
          { name: "Coffee Beans", fractions: [["kg", 1, 650, 480, true], ["500g", 0.5, 330, 240]], buy: [10, 40], buyFraction: 0 },
        ],
      },
      {
        category: "Food",
        items: [
          { name: "Sugar", fractions: [["kg", 1, 140, 110, true], ["Sack (50kg)", 50, 6800, 5400]], buy: [1, 3], buyFraction: 1, expiry: 365 },
          { name: "Rice", fractions: [["kg", 1, 160, 120, true], ["Bag (25kg)", 25, 3900, 2950]], buy: [1, 4], buyFraction: 1, expiry: 300 },
          { name: "Cooking Oil", fractions: [["Litre", 1, 260, 205, true], ["Jerrycan (5L)", 5, 1280, 1010]], buy: [6, 15], buyFraction: 1, expiry: 240 },
          { name: "Pasta 500g", fractions: [["Pack", 1, 75, 55, true], ["Carton (20)", 20, 1450, 1080]], buy: [2, 5], buyFraction: 1, expiry: 400 },
        ],
      },
      {
        category: "Household",
        items: [
          { name: "Laundry Soap", fractions: [["Piece", 1, 35, 24, true], ["Box (12)", 12, 400, 280]], buy: [3, 8], buyFraction: 1 },
          { name: "Toilet Paper", fractions: [["Roll", 1, 30, 20, true], ["Pack (10)", 10, 285, 190]], buy: [4, 10], buyFraction: 1 },
        ],
      },
    ],
  },
  {
    business: {
      name: "Hawassa Pharmacy",
      address: "Main Street, Hawassa",
      phone: "+251922000001",
      email: "contact@hawassapharmacy.et",
      subscriptionStatus: "trial",
      subscriptionPlan: "free",
      trialEndsAt: daysFromNow(10),
    },
    subscription: { plan: "free", status: "active", amount: 0, startedDaysAgo: 20, durationDays: 30, paymentMethod: null },
    owner: { name: "Meron Haile", username: "owner2", phone: "+251922100001", location: "Hawassa" },
    shops: [
      {
        name: "Hawassa Main Shop",
        address: "Piazza, Hawassa",
        salesmen: [{ name: "Yonas Bekele", username: "sales4", phone: "+251922200001", location: "Hawassa" }],
      },
    ],
    catalog: [
      {
        category: "Medicines",
        items: [
          { name: "Paracetamol 500mg", fractions: [["Tablet", 1, 2, 1, true], ["Strip (10)", 10, 18, 9], ["Box (100)", 100, 170, 85]], buy: [3, 6], buyFraction: 2, expiry: 540 },
          { name: "Amoxicillin 500mg", fractions: [["Capsule", 1, 5, 3, true], ["Strip (10)", 10, 45, 28]], buy: [20, 40], buyFraction: 1, expiry: 365 },
          { name: "ORS Sachet", fractions: [["Sachet", 1, 15, 9, true], ["Box (25)", 25, 350, 210]], buy: [2, 5], buyFraction: 1, expiry: 720 },
        ],
      },
      {
        category: "Personal Care",
        items: [
          { name: "Hand Sanitizer 250ml", fractions: [["Bottle", 1, 120, 80, true], ["Carton (24)", 24, 2700, 1850]], buy: [1, 2], buyFraction: 1, expiry: 600 },
          { name: "Face Mask", fractions: [["Piece", 1, 10, 5, true], ["Box (50)", 50, 450, 240]], buy: [2, 6], buyFraction: 1 },
        ],
      },
    ],
  },
]

const PASSWORDS = { admin: "admin123", owner: "owner123", salesman: "sales123" }

// ---------------------------------------------------------------------------
// Seeding
// ---------------------------------------------------------------------------
async function seed() {
  await sequelize.authenticate()
  await sequelize.sync({ alter: true })

  if (RESET) {
    console.log("Wiping all tables...")
    await sequelize.query(
      'TRUNCATE "SoldItems", "ItemBoughts", "AvailableItems", "Fractions", "Items", "Categories", "Users", "Shops", "Subscriptions", "Businesses" CASCADE',
    )
  } else if (await User.findOne({ where: { username: "admin" } })) {
    console.log("Sample data already exists. Run `npm run seed -- --reset` to wipe ALL data and reseed.")
    return
  }

  const summary = { businesses: 0, shops: 0, users: 0, categories: 0, items: 0, fractions: 0, boughts: 0, sales: 0 }

  // Platform admin (no business)
  await User.create({
    name: "System Admin",
    username: "admin",
    password: PASSWORDS.admin,
    phone: "+251900000000",
    location: "Addis Ababa",
    role: "admin",
  })
  summary.users++

  for (const def of BUSINESSES) {
    const business = await Business.create(def.business)
    await backdate("Businesses", business.id, daysAgo(40))
    summary.businesses++

    const s = def.subscription
    await Subscription.create({
      businessId: business.id,
      plan: s.plan,
      status: s.status,
      startDate: daysAgo(s.startedDaysAgo),
      endDate: daysFromNow(s.durationDays - s.startedDaysAgo),
      amount: s.amount,
      paymentMethod: s.paymentMethod,
      paymentId: s.amount > 0 ? `pi_sample_${business.id.slice(0, 8)}` : null,
    })

    await User.create({ ...def.owner, password: PASSWORDS.owner, role: "owner", businessId: business.id })
    summary.users++

    // Shops + salesmen
    const shops = []
    for (const shopDef of def.shops) {
      const shop = await Shop.create({ name: shopDef.name, address: shopDef.address, businessId: business.id })
      summary.shops++
      const salesmen = []
      for (const sm of shopDef.salesmen) {
        salesmen.push(
          await User.create({ ...sm, password: PASSWORDS.salesman, role: "salesman", businessId: business.id, shopId: shop.id }),
        )
        summary.users++
      }
      shops.push({ shop, salesmen })
    }

    // Catalog
    const products = [] // { item, fractions[], def }
    for (const catDef of def.catalog) {
      const category = await Category.create({ name: catDef.category, businessId: business.id })
      summary.categories++
      for (const itemDef of catDef.items) {
        const item = await Item.create({ name: itemDef.name, categoryId: category.id, businessId: business.id })
        summary.items++
        const fractions = []
        for (const [name, ratio, sellingPrice, purchasePrice, isUnit = false] of itemDef.fractions) {
          fractions.push(
            await Fraction.create({ name, ratio, sellingPrice, purchasePrice, isUnit, itemId: item.id, businessId: business.id }),
          )
          summary.fractions++
        }
        products.push({ item, fractions, def: itemDef })
      }
    }

    // Purchases (stock in): two deliveries per item per shop
    const stock = new Map() // `${shopId}:${itemId}` -> AvailableItem
    for (const { shop } of shops) {
      for (const p of products) {
        for (const deliveryDaysAgo of [28, 12]) {
          const fraction = p.fractions[p.def.buyFraction]
          const quantity = randInt(p.def.buy[0], p.def.buy[1])
          const quantityInUnits = quantity * fraction.ratio
          const key = `${shop.id}:${p.item.id}`

          let available = stock.get(key)
          if (available) {
            available.quantity = parseFloat(available.quantity) + quantityInUnits
            available.soldPrice = fraction.sellingPrice
            await available.save()
          } else {
            available = await AvailableItem.create({
              itemId: p.item.id,
              businessId: business.id,
              shopId: shop.id,
              quantity: quantityInUnits,
              soldPrice: fraction.sellingPrice,
            })
            stock.set(key, available)
          }

          const when = daysAgo(deliveryDaysAgo, 8, randInt(0, 59))
          const bought = await ItemBought.create({
            itemId: p.item.id,
            fractionId: fraction.id,
            fractionPurchasePrice: fraction.purchasePrice,
            fractionSoldPrice: fraction.sellingPrice,
            quantity,
            expiryDate: p.def.expiry ? daysFromNow(p.def.expiry) : null,
            businessId: business.id,
            shopId: shop.id,
            availableItemId: available.id,
            available_items_count: parseFloat(available.quantity) / fraction.ratio,
            createdTime: when,
          })
          await backdate("ItemBoughts", bought.id, when, ["createdTime"])
          summary.boughts++
        }
        await backdate("AvailableItems", stock.get(`${shop.id}:${p.item.id}`).id, daysAgo(28))
      }
    }

    // Sales (stock out): last 14 days including today, by each shop's salesmen
    for (const { shop, salesmen } of shops) {
      for (let day = 13; day >= 0; day--) {
        const salesToday = randInt(3, 7)
        for (let n = 0; n < salesToday; n++) {
          const p = pick(products)
          const available = stock.get(`${shop.id}:${p.item.id}`)
          // Mostly sell the unit fraction, sometimes a bigger pack
          const fraction = rand() < 0.8 ? p.fractions.find((f) => f.isUnit) : pick(p.fractions)
          const quantity = fraction.ratio < 1 ? randInt(1, 4) : randInt(1, fraction.ratio >= 10 ? 2 : 6)
          const quantityInUnits = quantity * fraction.ratio
          if (parseFloat(available.quantity) < quantityInUnits) continue

          available.quantity = parseFloat(available.quantity) - quantityInUnits
          await available.save()

          const amount = fraction.sellingPrice * quantity
          const profit = (fraction.sellingPrice - fraction.purchasePrice) * quantity
          const hour = day === 0 ? Math.min(randInt(8, 18), Math.max(8, new Date().getHours())) : randInt(8, 19)
          const when = daysAgo(day, hour, randInt(0, 59))

          const sale = await SoldItem.create({
            itemId: p.item.id,
            fractionId: fraction.id,
            quantity,
            amount,
            expectedAmount: amount,
            profit,
            status: "completed",
            salesmanId: pick(salesmen).id,
            businessId: business.id,
            shopId: shop.id,
            availableItemId: available.id,
            available_items_count: parseFloat(available.quantity) / fraction.ratio,
            soldTime: when,
            createdTime: when,
          })
          await backdate("SoldItems", sale.id, when, ["soldTime", "createdTime"])
          summary.sales++
        }
      }
    }
  }

  console.log("\nSeed complete:", summary)
  console.log("\nLogin accounts:")
  console.table([
    { role: "admin", username: "admin", password: PASSWORDS.admin, business: "-", shop: "-" },
    ...BUSINESSES.flatMap((b) => [
      { role: "owner", username: b.owner.username, password: PASSWORDS.owner, business: b.business.name, shop: "all" },
      ...b.shops.flatMap((s) =>
        s.salesmen.map((sm) => ({ role: "salesman", username: sm.username, password: PASSWORDS.salesman, business: b.business.name, shop: s.name })),
      ),
    ]),
  ])
}

seed()
  .catch((err) => {
    console.error("Seed failed:", err)
    process.exitCode = 1
  })
  .finally(() => sequelize.close())
