export const MIN_ANGLE = 15;
export const MAX_ANGLE = 120;

export function clampAngle(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 110;
  return Math.min(MAX_ANGLE, Math.max(MIN_ANGLE, Math.round(parsed)));
}

export function angleFromVerticalDrag(startAngle, startY, currentY, pixelsPerDegree = 2.45) {
  return clampAngle(startAngle + (startY - currentY) / pixelsPerDegree);
}

export function angleDescription(angle) {
  if (angle <= 25) return `${angle} degrees, almost closed`;
  if (angle <= 55) return `${angle} degrees, low`;
  if (angle <= 90) return `${angle} degrees, half open`;
  return `${angle} degrees, nearly open`;
}

export function lidGeometry(value, strength = 72) {
  const angle = clampAngle(value);
  const closure = Math.min(1, Math.max(0, (110 - angle) / 95));
  const lidFold = angle >= 110 ? (angle - 110) * 0.32 : -closure * 74;
  const desktopFold = -(120 - angle) * (Math.min(100, Math.max(25, strength)) / 100) * 0.115;
  return { closure, lidFold, desktopFold };
}
