const express = require('express');
const mysql = require('mysql2/promise');

const app = express();
const port = process.env.PORT || 8080;

app.use(express.json());

// MySQL connection pool
const pool = mysql.createPool({
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 3306,
    user: process.env.DB_USER || 'appuser',
    password: process.env.DB_PASSWORD || 'apppass123',
    database: process.env.DB_NAME || 'appdb',
    connectionLimit: 10
});

// Health check endpoint (used by K8s readinessProbe)
app.get('/api/health', (req, res) => {
    res.status(200).json({ status: 'UP', service: 'backend' });
});

// Database connection test endpoint
app.get('/api/db-test', async (req, res) => {
    try {
        const connection = await pool.getConnection();
        await connection.query('SELECT 1');
        connection.release();
        res.json({ status: 'SUCCESS', message: 'Connected to MySQL database!' });
    } catch (error) {
        console.error('Database connection failed:', error);
        res.status(500).json({ status: 'ERROR', message: 'Database connection failed', error: error.message });
    }
});

// Root API endpoint
app.get('/api', (req, res) => {
    res.json({ message: 'Hello from the backend API!' });
});

app.listen(port, () => {
    console.log(`Backend server listening on port ${port}`);
});
