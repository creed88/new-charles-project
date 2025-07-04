const express = require('express');
const { Pool } = require('pg');
const Vault = require('node-vault');

const app = express();
const port = 3000;

// Initialize Vault client
const vault = Vault({
  endpoint: process.env.VAULT_ADDR,
  token: process.env.VAULT_TOKEN
});

async function getDbCredentials() {
  const result = await vault.read('database/creds/app-role');
  return {
    user: result.data.username,
    password: result.data.password
  };
}

app.get('/api/data', async (req, res) => {
  try {
    const creds = await getDbCredentials();
    const pool = new Pool({
      host: process.env.DB_HOST,
      database: 'appdb',
      user: creds.user,
      password: creds.password,
      port: 5432,
      ssl: { rejectUnauthorized: true }
    });

    const result = await pool.query('SELECT * FROM items');
    await pool.end();
    res.json(result.rows);
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'OK' });
});

app.listen(port, () => {
  console.log(`Backend listening on port ${port}`);
});