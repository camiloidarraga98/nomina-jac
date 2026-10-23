export type WalletBarcodeLeg = { origin: string; destination: string; seat?: string };
export type WalletBarcodeDetails = { passenger?: string; legs: WalletBarcodeLeg[] };

function passengerName(field: string): string | undefined {
  const name = field.trim();
  if (!name || !/^[A-Z ./'-]+$/.test(name) || !/[A-Z]/.test(name)) return undefined;
  const parts = name.split('/');
  if (parts.length > 2) return undefined;
  // BCBP supplies LAST/FIRST, sometimes truncated to its fixed-width field.
  // Reorder only the components actually present; never complete a name.
  return (parts.length === 2 ? [parts[1].trim(), parts[0].trim()] : parts)
    .filter(Boolean).join(' ').replace(/ +/g, ' ') || undefined;
}

function assignedSeat(field: string): string | undefined {
  const seat = field.trim();
  const match = seat.match(/^(\d{1,4})([A-Z]?)$/);
  if (!match || Number(match[1]) === 0 || (match[2] && match[1].length > 3)) return undefined;
  return String(Number(match[1])) + match[2];
}

function securityTail(tail: string): boolean {
  if (!tail.trim()) return true;
  const text = tail.trimStart();
  if (!/^\^[A-Z0-9][0-9A-F]{2}/.test(text)) return false;
  const length = Number.parseInt(text.slice(2, 4), 16);
  return text.length >= 4 + length && !text.slice(4 + length).trim();
}

/** Reads only unambiguous mandatory BCBP fields, without changing the payload.
 * A null result means that the original code still needs the caller's existing
 * validation and explicit document review; this is not signature validation.
 * Time, year, gate and a complete/truncated name are never inferred here.
 */
export function parseWalletBarcodeDetails(message: unknown): WalletBarcodeDetails | null {
  if (typeof message !== 'string' || message.length < 60 || message.length > 4096 ||
      !/^M[1-4]/.test(message) || /[^\x20-\x7e]/.test(message) || !/^[ E]$/.test(message[22])) return null;
  const count = Number(message[1]), legs: WalletBarcodeLeg[] = [];
  let offset = 23;
  for (let index = 0; index < count; index++) {
    if (offset + 37 > message.length) return null;
    const record = message.slice(offset, offset + 37);
    const origin = record.slice(7, 10), destination = record.slice(10, 13);
    const carrier = record.slice(13, 16).trim(), flight = record.slice(16, 21).trim();
    const julian = record.slice(21, 24), variableLength = record.slice(35, 37);
    if (!/^[A-Z0-9 ]{7}$/.test(record.slice(0, 7)) || !/^[A-Z]{3}$/.test(origin) ||
        !/^[A-Z]{3}$/.test(destination) || !/^[A-Z0-9]{2,3}$/.test(carrier) ||
        !/^[A-Z0-9]{1,5}$/.test(flight) || !/\d/.test(flight) || !/^\d{3}$/.test(julian) ||
        Number(julian) < 1 || Number(julian) > 366 || !/^[ A-Z0-9]$/.test(record[24]) ||
        !/^[ A-Z0-9]{5}$/.test(record.slice(29, 34)) || !/^[ A-Z0-9]$/.test(record[34]) ||
        !/^[0-9A-F]{2}$/.test(variableLength)) return null;
    const end = offset + 37 + Number.parseInt(variableLength, 16);
    if (end > message.length) return null;
    const seat = assignedSeat(record.slice(25, 29));
    legs.push({ origin, destination, ...(seat ? { seat } : {}) });
    offset = end;
  }
  if (!securityTail(message.slice(offset))) return null;
  const passenger = passengerName(message.slice(2, 22));
  return { ...(passenger ? { passenger } : {}), legs };
}
