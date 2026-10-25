/** Explicit flight details supplied beside one boarding pass. These values
 * describe a private document; they never select its recipient or alter its code.
 */
export type BoardingMessageDetails = {
  seat?: string;
  departureTime?: string;
  boardingTime?: string;
  airline?: string;
};

const MAX_MESSAGE = 2000;
const forbidden = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u202a-\u202e\u2066-\u2069]/u;
const fold = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[ \t]+/g, ' ').trim();
const unemphasize = (value: string) => value.trim().replace(/^\*{1,2}\s*/, '').replace(/\s*\*{1,2}$/, '').trim();
const labels = new Map<string, keyof BoardingMessageDetails>([
  ['silla', 'seat'],
  ['hora de salida', 'departureTime'],
  ['hora en sala', 'boardingTime'],
  ['aerolinea', 'airline'],
]);

/** A civil HH:mm value: do not convert to UTC or infer a timezone. */
export function normalizeBoardingMessageTime(value: unknown): string | undefined {
  if (typeof value !== 'string' || value.length > 40 || forbidden.test(value)) return undefined;
  const text = value.trim().toUpperCase().replace(/([AP])\s*\.?\s*M\.?/g, '$1M');
  const match = /^(\d{1,2}):(\d{2})(?:\s*(AM|PM))?$/.exec(text);
  if (!match) return undefined;
  let hour = Number(match[1]);
  const minute = Number(match[2]);
  if (minute > 59) return undefined;
  if (match[3]) {
    if (hour < 1 || hour > 12) return undefined;
    hour = hour % 12 + (match[3] === 'PM' ? 12 : 0);
  } else if (hour > 23) return undefined;
  return String(hour).padStart(2, '0') + ':' + String(minute).padStart(2, '0');
}

function normalizeSeat(value: string): string | undefined {
  if (['sin asignar', 'sin asignacion', 'no asignado', 'no asignada', 'pendiente'].includes(fold(value))) return '';
  const match = /^(\d{1,4})([A-Z]?)$/.exec(value.toUpperCase());
  if (!match || Number(match[1]) === 0 || Number(match[1]) > 999) return undefined;
  return String(Number(match[1])) + match[2];
}

/** Parse only labelled fields from this message. Repeated labels or an invalid
 * nonempty value reject the block, so two flights cannot silently be combined.
 * Unrelated lines are not saved in the canonical description.
 */
export function parseBoardingMessage(value: unknown): BoardingMessageDetails | undefined {
  if (typeof value !== 'string' || value.length > MAX_MESSAGE || forbidden.test(value)) return undefined;
  const details: BoardingMessageDetails = {};
  const seen = new Set<keyof BoardingMessageDetails>();
  for (const raw of value.replace(/\r\n?/g, '\n').split('\n')) {
    const line = raw.trim().replace(/^[-•]\s+/, '');
    const separator = line.indexOf(':');
    if (separator < 0) continue;
    const field = labels.get(fold(unemphasize(line.slice(0, separator))));
    if (!field) continue;
    if (seen.has(field)) return undefined;
    seen.add(field);
    const input = unemphasize(line.slice(separator + 1));
    if (!input) continue;
    if (field === 'seat') {
      const seat = normalizeSeat(input);
      if (seat === undefined) return undefined;
      details.seat = seat;
    } else if (field === 'departureTime' || field === 'boardingTime') {
      const time = normalizeBoardingMessageTime(input);
      if (time === undefined) return undefined;
      details[field] = time;
    } else {
      if (input.length > 80 || !/^[\p{L}\p{M}\p{N}][\p{L}\p{M}\p{N} .,'’()&+/-]*$/u.test(input)) return undefined;
      details.airline = input.replace(/[ \t]+/g, ' ');
    }
  }
  return Object.keys(details).length ? details : undefined;
}

/** Keep the smallest stable snapshot before the asynchronous Slack import. */
export function canonicalBoardingMessage(value: unknown): string {
  const details = parseBoardingMessage(value);
  if (!details) return '';
  return [
    ...(details.seat !== undefined ? ['Silla: ' + (details.seat || 'Sin asignar')] : []),
    ...(details.departureTime !== undefined ? ['Hora de salida: ' + details.departureTime] : []),
    ...(details.boardingTime !== undefined ? ['Hora en sala: ' + details.boardingTime] : []),
    ...(details.airline !== undefined ? ['Aerolínea: ' + details.airline] : []),
  ].join('\n');
}
