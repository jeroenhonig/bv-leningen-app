require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { Sequelize, DataTypes } = require('sequelize');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Sequelize setup
const sequelize = new Sequelize(
  process.env.DB_NAME,
  process.env.DB_USER,
  process.env.DB_PASSWORD,
  {
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    dialect: 'postgres',
    logging: process.env.NODE_ENV === 'development' ? console.log : false,
    pool: {
      max: 5,
      min: 0,
      acquire: 30000,
      idle: 10000
    }
  }
);

// Database connection test
async function testDatabaseConnection() {
  try {
    await sequelize.authenticate();
    console.log('Database connection established successfully.');
  } catch (error) {
    console.error('Unable to connect to the database:', error);
  }
}

testDatabaseConnection();

// Modellen definiëren
const Lening = sequelize.define('Lening', {
  id: {
    type: DataTypes.INTEGER,
    primaryKey: true,
    autoIncrement: true
  },
  lening_id: {
    type: DataTypes.STRING,
    unique: true,
    allowNull: false
  },
  kredietverstrekker: {
    type: DataTypes.STRING,
    allowNull: false
  },
  type: {
    type: DataTypes.STRING,
    allowNull: false
  },
  startdatum: {
    type: DataTypes.DATEONLY,
    allowNull: false
  },
  einddatum: {
    type: DataTypes.DATEONLY,
    allowNull: true
  },
  bedrag: {
    type: DataTypes.DECIMAL(15, 2),
    allowNull: false
  },
  rentepercentage: {
    type: DataTypes.DECIMAL(5, 2),
    allowNull: false
  },
  rentetype: {
    type: DataTypes.STRING,
    defaultValue: 'Vast'
  },
  status: {
    type: DataTypes.STRING,
    defaultValue: 'Lopend'
  },
  opmerkingen: {
    type: DataTypes.TEXT,
    allowNull: true
  }
}, {
  tableName: 'leningen',
  timestamps: true,
  createdAt: 'created_at',
  updatedAt: 'updated_at'
});

const Betaling = sequelize.define('Betaling', {
  id: {
    type: DataTypes.INTEGER,
    primaryKey: true,
    autoIncrement: true
  },
  betaling_id: {
    type: DataTypes.STRING,
    unique: true,
    allowNull: false
  },
  lening_id: {
    type: DataTypes.STRING,
    allowNull: false,
    references: {
      model: Lening,
      key: 'lening_id'
    }
  },
  datum: {
    type: DataTypes.DATEONLY,
    allowNull: false
  },
  termijnbedrag: {
    type: DataTypes.DECIMAL(15, 2),
    allowNull: false
  },
  aflossing: {
    type: DataTypes.DECIMAL(15, 2),
    allowNull: false
  },
  rente: {
    type: DataTypes.DECIMAL(15, 2),
    allowNull: false
  },
  status: {
    type: DataTypes.STRING,
    defaultValue: 'Betaald'
  }
}, {
  tableName: 'betalingen',
  timestamps: true,
  createdAt: 'created_at',
  updatedAt: 'updated_at'
});

// Relaties
Lening.hasMany(Betaling, { foreignKey: 'lening_id', sourceKey: 'lening_id' });
Betaling.belongsTo(Lening, { foreignKey: 'lening_id', targetKey: 'lening_id' });

// API routes
// Leningen endpoints
app.get('/api/leningen', async (req, res) => {
  try {
    const leningen = await Lening.findAll();
    res.json(leningen);
  } catch (error) {
    console.error('Error fetching leningen:', error);
    res.status(500).json({ error: 'Server error bij het ophalen van leningen' });
  }
});

app.post('/api/leningen', async (req, res) => {
  try {
    const leningData = req.body;
    leningData.lening_id = leningData.lening_id || uuidv4();
    
    const newLening = await Lening.create(leningData);
    res.status(201).json(newLening);
  } catch (error) {
    console.error('Error creating lening:', error);
    res.status(500).json({ error: 'Server error bij het aanmaken van lening' });
  }
});

app.put('/api/leningen/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const leningData = req.body;
    
    const lening = await Lening.findOne({ where: { lening_id: id } });
    
    if (!lening) {
      return res.status(404).json({ error: 'Lening niet gevonden' });
    }
    
    await lening.update(leningData);
    res.json(lening);
  } catch (error) {
    console.error('Error updating lening:', error);
    res.status(500).json({ error: 'Server error bij het bijwerken van lening' });
  }
});

app.delete('/api/leningen/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const lening = await Lening.findOne({ where: { lening_id: id } });
    
    if (!lening) {
      return res.status(404).json({ error: 'Lening niet gevonden' });
    }
    
    await lening.destroy();
    res.status(204).end();
  } catch (error) {
    console.error('Error deleting lening:', error);
    res.status(500).json({ error: 'Server error bij het verwijderen van lening' });
  }
});

// Betalingen endpoints
app.get('/api/betalingen', async (req, res) => {
  try {
    const betalingen = await Betaling.findAll();
    res.json(betalingen);
  } catch (error) {
    console.error('Error fetching betalingen:', error);
    res.status(500).json({ error: 'Server error bij het ophalen van betalingen' });
  }
});

app.post('/api/betalingen', async (req, res) => {
  try {
    const betalingData = req.body;
    betalingData.betaling_id = betalingData.betaling_id || uuidv4();
    
    const newBetaling = await Betaling.create(betalingData);
    res.status(201).json(newBetaling);
  } catch (error) {
    console.error('Error creating betaling:', error);
    res.status(500).json({ error: 'Server error bij het aanmaken van betaling' });
  }
});

app.put('/api/betalingen/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const betalingData = req.body;
    
    const betaling = await Betaling.findOne({ where: { betaling_id: id } });
    
    if (!betaling) {
      return res.status(404).json({ error: 'Betaling niet gevonden' });
    }
    
    await betaling.update(betalingData);
    res.json(betaling);
  } catch (error) {
    console.error('Error updating betaling:', error);
    res.status(500).json({ error: 'Server error bij het bijwerken van betaling' });
  }
});

app.delete('/api/betalingen/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const betaling = await Betaling.findOne({ where: { betaling_id: id } });
    
    if (!betaling) {
      return res.status(404).json({ error: 'Betaling niet gevonden' });
    }
    
    await betaling.destroy();
    res.status(204).end();
  } catch (error) {
    console.error('Error deleting betaling:', error);
    res.status(500).json({ error: 'Server error bij het verwijderen van betaling' });
  }
});

// Jaaroverzicht endpoint
app.get('/api/jaaroverzicht/:jaar', async (req, res) => {
  try {
    const { jaar } = req.params;
    const startDatum = `${jaar}-01-01`;
    const eindDatum = `${jaar}-12-31`;
    
    // Haal alle leningen op
    const leningen = await Lening.findAll();
    
    // Haal betalingen voor dit jaar op
    const betalingen = await Betaling.findAll({
      where: {
        datum: {
          [Sequelize.Op.between]: [startDatum, eindDatum]
        }
      }
    });
    
    // Bereken jaaroverzicht
    const jaaroverzicht = {};
    
    leningen.forEach(lening => {
      const leningId = lening.lening_id;
      
      // Filter betalingen voor deze lening
      const leningBetalingen = betalingen.filter(b => b.lening_id === leningId);
      
      if (leningBetalingen.length > 0) {
        const totaleAflossing = leningBetalingen.reduce(
          (sum, b) => sum + parseFloat(b.aflossing), 0
        );
        
        const totaleRente = leningBetalingen.reduce(
          (sum, b) => sum + parseFloat(b.rente), 0
        );
        
        jaaroverzicht[leningId] = {
          leningId,
          kredietverstrekker: lening.kredietverstrekker,
          totaleAflossing,
          totaleRente
        };
      }
    });
    
    res.json(jaaroverzicht);
  } catch (error) {
    console.error('Error fetching jaaroverzicht:', error);
    res.status(500).json({ error: 'Server error bij het ophalen van jaaroverzicht' });
  }
});

// Serveer statische frontend bestanden in productie
if (process.env.NODE_ENV === 'production') {
  app.use(express.static(path.join(__dirname, '../frontend/build')));
  
  app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, '../frontend/build', 'index.html'));
  });
}

// Sync database en start server
sequelize.sync().then(() => {
  app.listen(PORT, () => {
    console.log(`Server draait op poort ${PORT}`);
  });
}).catch(err => {
  console.error('Error syncing database:', err);
});
