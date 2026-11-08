export const getAllSoldItems = async (req, res) => {
  try {
    const soldItems = await SoldItem.findAll({
      where: { businessId: req.user.businessId },
      include: [
        { 
           model: Item,
          include: [{ model: Fraction, as: "fractions" }]
        },
        // {
        //   model: Fraction,
        //   attributes: ['id', 'name', 'ratio']
        // }
      ],
      order: [["createdAt", "DESC"]],
    })
    res.json(soldItems)
  } catch (error) {
    console.log("errr in listing soldItems: ", error)
    res.status(500).json({ message: "Error fetching sold items", error: error.message })
  }
} 