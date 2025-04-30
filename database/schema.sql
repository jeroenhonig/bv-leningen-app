-- Schema voor BV Leningen App

-- Leningen tabel
CREATE TABLE IF NOT EXISTS leningen (
  id SERIAL PRIMARY KEY,
  kredietverstrekker VARCHAR(255) NOT NULL,
  type VARCHAR(100) NOT NULL,
  startdatum DATE NOT NULL,
  einddatum DATE,
  bedrag DECIMAL(15, 2) NOT NULL,
  rentepercentage DECIMAL(5, 2) NOT NULL,
  rentetype VARCHAR(50) DEFAULT 'Vast',
  status VARCHAR(50) DEFAULT 'Lopend',
  opmerkingen TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Betalingen tabel
CREATE TABLE IF NOT EXISTS betalingen (
  id SERIAL PRIMARY KEY,
  lening_id INTEGER NOT NULL REFERENCES leningen(id) ON DELETE CASCADE,
  datum DATE NOT NULL,
  termijnbedrag DECIMAL(15, 2) NOT NULL,
  aflossing DECIMAL(15, 2) NOT NULL,
  rente DECIMAL(15, 2) NOT NULL,
  status VARCHAR(50) DEFAULT 'Betaald',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Triggers voor automatische update van updated_at
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = NOW(); 
   RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER update_leningen_modtime
BEFORE UPDATE ON leningen
FOR EACH ROW EXECUTE PROCEDURE update_modified_column();

CREATE TRIGGER update_betalingen_modtime
BEFORE UPDATE ON betalingen
FOR EACH ROW EXECUTE PROCEDURE update_modified_column();
