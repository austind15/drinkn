import jwt from 'jsonwebtoken';

const secret = process.env.SESSION_JWT_SECRET;
const expiresIn = process.env.SESSION_JWT_EXPIRES_IN || '30d';

if (!secret) {
  throw new Error('SESSION_JWT_SECRET must be set');
}

export function signSession(userId) {
  return jwt.sign({ sub: userId }, secret, { expiresIn });
}

export function verifySession(token) {
  return jwt.verify(token, secret);
}
