const express   = require('express'); 
const cors      = require('cors'); 
const helmet    = require('helmet'); 
const morgan    = require('morgan'); 
const { Sequelize, DataTypes } = require('sequelize'); 
const path      = require('path'); 
const { v4: uuidv4 } = require('uuid'); 
 
const app  = express(); 
const PORT = process.env.PORT || 3000; 

// Database configuratie
const DB_NAME = process.env.DB_NAME || 'leningendb';
const DB_USER = process.env.DB_USER || 'dbuser';
const DB_PASSWORD = process.env.DB_PASSWORD || '';  // Zorg dat dit een string is
const DB_HOST = process.env.DB_HOST || 'localhost';
const DB_PORT = process.env.DB_PORT || 5432;
 
// --- Middleware ----------------------------------- 
app.use(helmet()); 
app.use(cors()); 
app.use(express.json()); 
app.use(morgan('combined')); 
 
// --- Sequelize setup ------------------------------ 
const sequelize = new Sequelize( 
  DB_NAME, 
  DB_USER, 
  DB_PASSWORD, 
  { 
    host:     DB_HOST, 
    port:     DB_PORT, 
    dialect:  'postgres', 
    logging:  process.env.NODE_ENV === 'development' ? console.log : false, 
    pool: { 
      max:     5, 
      min:     0, 
      acquire: 30000, 
      idle:    10000 
    } 
  } 
); 
 
// test database 
(async () => { 
  try { 
    await sequelize.authenticate(); 
    console.log('✅ Database connection established.'); 
  } catch (err) { 
    console.error('❌ Unable to connect to the database:', err); 
  } 
})(); 
 
// --- Modellen ------------------------------------- 
const Lening = sequelize.define('Lening', { 
  id:             { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true }, 
  lening_id:      { type: DataTypes.STRING, unique: true, allowNull: false }, 
  kredietverstrekker: { type: DataTypes.STRING, allowNull: false }, 
  type:           { type: DataTypes.STRING, allowNull: false }, 
  startdatum:     { type: DataTypes.DATEONLY, allowNull: false }, 
  einddatum:      { type: DataTypes.DATEONLY, allowNull: true }, 
  bedrag:         { type: DataTypes.DECIMAL(15,2), allowNull: false }, 
  rentepercentage:{ type: DataTypes.DECIMAL(5,2), allowNull: false }, 
  rentetype:      { type: DataTypes.STRING, defaultValue: 'Vast' }, 
  status:         { type: DataTypes.STRING, defaultValue: 'Lopend' }, 
  opmerkingen:    { type: DataTypes.TEXT, allowNull: true } 
}, { 
  tableName: 'leningen', 
  timestamps: true, 
  createdAt:  'created_at', 
  updatedAt:  'updated_at' 
}); 
 
const Betaling = sequelize.define('Betaling', { 
  id:           { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true }, 
  betaling_id:  { type: DataTypes.STRING, unique: true, allowNull: false }, 
  lening_id:    { type: DataTypes.STRING, allowNull: false, references: { model: Lening, key: 'lening_id' }}, 
  datum:        { type: DataTypes.DATEONLY, allowNull: false }, 
  termijnbedrag:{ type: DataTypes.DECIMAL(15,2), allowNull: false }, 
  aflossing:    { type: DataTypes.DECIMAL(15,2), allowNull: false }, 
  rente:        { type: DataTypes.DECIMAL(15,2), allowNull: false }, 
  status:       { type: DataTypes.STRING, defaultValue: 'Betaald' } 
}, { 
  tableName: 'betalingen', 
  timestamps: true, 
  createdAt:  'created_at', 
  updatedAt:  'updated_at' 
}); 
 
// relaties 
Lening.hasMany(Betaling, { foreignKey: 'lening_id', sourceKey: 'lening_id' }); 
Betaling.belongsTo(Lening, { foreignKey: 'lening_id', targetKey: 'lening_id' }); 
 
// --- API routes ----------------------------------- 
// Leningen 
app.get('/api/leningen',     async (req, res) => { /* ... */ }); 
app.post('/api/leningen',    async (req, res) => { /* ... */ }); 
app.put('/api/leningen/:id', async (req, res) => { /* ... */ }); 
app.delete('/api/leningen/:id', async (req, res) => { /* ... */ }); 
 
// Betalingen 
app.get('/api/betalingen',     async (req, res) => { /* ... */ }); 
app.post('/api/betalingen',    async (req, res) => { /* ... */ }); 
app.put('/api/betalingen/:id', async (req, res) => { /* ... */ }); 
app.delete('/api/betalingen/:id', async (req, res) => { /* ... */ }); 
 
// Jaaroverzicht 
app.get('/api/jaaroverzicht/:jaar', async (req, res) => { /* ... */ }); 
 
// --- Static & Catch-All voor React SPA ------------- 
// 1) Serveer build/static assets 
app.use( 
  express.static( 
    path.join(__dirname, '../frontend/build'), 
    { index: false } 
  ) 
); 
 
// 2) vang alle overige GET-requests op met een regex 
app.get(/.*/, (req, res) => { 
  res.sendFile( 
    path.join(__dirname, '../frontend/build', 'index.html') 
  ); 
}); 
 
// --- Sync DB & Start server ------------------------ 
sequelize.sync() 
  .then(() => { 
    app.listen(PORT, () => { 
      console.log(`✅ Server draait op poort ${PORT}`); 
    }); 
  }) 
  .catch(err => { 
    console.error('❌ Error syncing database:', err); 
  });