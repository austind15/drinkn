import 'dotenv/config';
import express from 'express';
import cors from 'cors';

import authRoutes from './routes/auth.js';
import usersRoutes from './routes/users.js';
import beersRoutes from './routes/beers.js';
import groupsRoutes from './routes/groups.js';
import votesRoutes from './routes/votes.js';
import followsRoutes from './routes/follows.js';

const app = express();

app.use(cors());
app.use(express.json({ limit: '1mb' }));

// Request logger
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const ms = Date.now() - start;
    const tag = res.statusCode >= 400 ? '❌' : '✅';
    console.log(`${tag} ${req.method} ${req.originalUrl} → ${res.statusCode} (${ms}ms)`);
  });
  next();
});

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'beer-tracker-backend' });
});

app.use('/auth', authRoutes);
app.use('/users', usersRoutes);
app.use('/beers', beersRoutes);
app.use('/groups', groupsRoutes);
app.use('/votes', votesRoutes);
app.use('/follows', followsRoutes);

app.use((err, _req, res, _next) => {
  console.error('Unhandled error:', err);
  const status = err.status || 500;
  res.status(status).json({ error: err.message || 'Internal server error' });
});

const port = Number(process.env.PORT || 3000);
app.listen(port, () => {
  console.log(`🍺 Beer Tracker API listening on :${port}`);
});
