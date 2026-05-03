// Round latitude/longitude to ~100 m resolution by truncating to 3 decimal places.
// 0.001 degrees of latitude ≈ 111 m. Longitude varies by latitude but at most
// equal to 111 m, so 3 decimals gives us a coarse bucket suitable for privacy.
export function blurCoordinate(value) {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 1000) / 1000;
}
