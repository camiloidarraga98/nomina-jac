import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { build } from 'esbuild';
import { createWalletFixture, verifyWalletPackage } from './helpers/wallet-synthetic.mjs';

const compiled = await build({ entryPoints: ['lib/boarding-wallet-core.ts'], bundle: true, platform: 'node', format: 'cjs', packages: 'external', write: false });
const coreModule = { exports: {} };
new Function('require', 'module', 'exports', compiled.outputFiles[0].text)(createRequire(import.meta.url), coreModule, coreModule.exports);
const core = coreModule.exports;

test('synthetic PKI produces a signed ZIP with the exact original barcode and supplied fields only', async () => {
  const fixture = await createWalletFixture();
  const crypto = core.createWalletCrypto(fixture.rootPem);
  const credentials = await crypto.normalizeWalletCredentials(fixture.input);
  assert.equal(credentials.teamId, fixture.input.teamId);
  assert.equal(credentials.passTypeId, fixture.input.passTypeId);
  assert.equal(credentials.expiresAt, new Date(Math.floor(Math.min(fixture.root.validity.notAfter.valueOf(), fixture.wwdr.validity.notAfter.valueOf(), fixture.signer.validity.notAfter.valueOf()) / 1000) * 1000).toISOString());
  assert(!Object.hasOwn(credentials, 'p12')); assert(!Object.hasOwn(credentials, 'password'));
  const bytes = await crypto.buildBoardingWalletPass(credentials, fixture.passInput);
  const { pass, files } = verifyWalletPackage(bytes, fixture);
  assert.equal(pass.formatVersion, 1); assert.equal(pass.organizationName, 'JAC'); assert.equal(pass.sharingProhibited, true);
  assert.equal(pass.passTypeIdentifier, fixture.input.passTypeId); assert.equal(pass.teamIdentifier, fixture.input.teamId);
  assert.equal(pass.serialNumber, fixture.passInput.serialNumber);
  assert.deepEqual(pass.barcodes, [{ ...fixture.barcode, messageEncoding: 'iso-8859-1' }]);
  assert.equal(Buffer.from(pass.barcodes[0].message, 'latin1').toString('hex'), Buffer.from(fixture.barcode.message, 'ascii').toString('hex'));
  assert.equal(pass.boardingPass.transitType, 'PKTransitTypeAir');
  assert.deepEqual(pass.boardingPass.primaryFields.map(field => [field.key, field.value]), [['origin', 'BOG'], ['destination', 'MDE']]);
  assert.deepEqual(pass.boardingPass.secondaryFields.map(field => [field.key, field.value]), [['passenger', 'Fixture Traveller']]);
  assert.deepEqual(pass.boardingPass.auxiliaryFields.map(field => [field.key, field.value]), [['travelDate', '2027-04-10']]);
  assert.match(pass.boardingPass.backFields[0].value, /JAC no emite ni actualiza/);
  for (const property of ['webServiceURL', 'authenticationToken', 'associatedStoreIdentifiers', 'appLaunchURL', 'relevantDate', 'expirationDate']) assert.equal(pass[property], undefined);
  assert.equal(Buffer.from(files['icon.png']).readUInt32BE(16), 29);
  assert.equal(Buffer.from(files['icon@2x.png']).readUInt32BE(16), 58);
  assert.equal(Buffer.from(files['icon@3x.png']).readUInt32BE(16), 87);
  const minimal = verifyWalletPackage(await crypto.buildBoardingWalletPass(credentials, { ...fixture.passInput, origin: undefined, destination: undefined, travelDate: undefined }), fixture).pass;
  assert.equal(minimal.boardingPass.primaryFields.length, 0); assert.equal(minimal.boardingPass.auxiliaryFields.length, 0);
  assert(!JSON.stringify(minimal).includes('flightNumber')); assert(!JSON.stringify(minimal).includes('gate'));
});

test('Wallet displays the reviewed traveller, route, local flight times and assigned seat without manufacturing missing fields', async () => {
  const fixture = await createWalletFixture(), crypto = core.createWalletCrypto(fixture.rootPem);
  const credentials = await crypto.normalizeWalletCredentials(fixture.input);
  const input = { ...fixture.passInput, passenger: 'Andrea Torres', origin: 'Medellín · MDE', destination: 'Bogotá · BOG', departureTime: '00:15', boardingTime: '23:40', seat: '12A' };
  const { pass } = verifyWalletPackage(await crypto.buildBoardingWalletPass(credentials, input), fixture);
  assert.deepEqual(pass.boardingPass.primaryFields.map(({ key, value }) => [key, value]), [['origin', input.origin], ['destination', input.destination]]);
  assert.deepEqual(pass.boardingPass.secondaryFields.map(({ key, value }) => [key, value]), [['passenger', input.passenger]]);
  assert.deepEqual(pass.boardingPass.headerFields.map(({ key, value }) => [key, value]), [['seat', input.seat]]);
  assert.deepEqual(pass.boardingPass.auxiliaryFields.map(({ key, value }) => [key, value]), [['departureTime', '00:15'], ['boardingTime', '23:40'], ['travelDate', input.travelDate]]);
  assert.deepEqual(pass.barcodes, [{ ...fixture.barcode, messageEncoding: 'iso-8859-1' }]);
  assert.equal(pass.relevantDate, undefined, 'A civil clock time has no fabricated timezone or absolute flight date.');
  const missing = verifyWalletPackage(await crypto.buildBoardingWalletPass(credentials, { ...fixture.passInput, passenger: undefined, origin: undefined, destination: undefined, travelDate: undefined }), fixture).pass;
  assert.deepEqual(missing.boardingPass.primaryFields, []); assert.deepEqual(missing.boardingPass.secondaryFields, []); assert.deepEqual(missing.boardingPass.headerFields, []); assert.deepEqual(missing.boardingPass.auxiliaryFields, []);
  for (const changes of [{ departureTime: '24:00' }, { boardingTime: '7:30' }, { departureTime: '07:60' }, { seat: '12 A' }, { seat: '0000' }, { seat: '12\nA' }, { passenger: 'Name\u202eOther' }]) await assert.rejects(() => crypto.buildBoardingWalletPass(credentials, { ...input, ...changes }));
});

test('PEM upload and DER upload normalize equally; the production trust root rejects synthetic Apple names', async () => {
  const fixture = await createWalletFixture();
  const crypto = core.createWalletCrypto(fixture.rootPem);
  const der = await crypto.normalizeWalletCredentials(fixture.input);
  const pem = await crypto.normalizeWalletCredentials({ ...fixture.input, wwdr: fixture.wwdrPem });
  const uploadedPem = await crypto.normalizeWalletCredentials({ ...fixture.input, wwdr: Buffer.from(fixture.wwdrPem).toString('base64') });
  assert.deepEqual(pem, der); assert.deepEqual(uploadedPem, der);
  await assert.rejects(() => core.normalizeWalletCredentials(fixture.input), /WWDR G4 original de Apple/);
});

test('credentials reject a wrong identity, key, issuer, CA role and certificate validity without leaking input', async () => {
  for (const options of [
    { signerTeamId: 'OTHERTEAM1' }, { signerPassTypeId: 'pass.co.other.fixture' }, { privateKeyMismatch: true },
    { wwdrUnit: 'G3' }, { wwdrOrganization: 'Names do not establish trust' }, { foreignIntermediateSignature: true }, { foreignLeafSignature: true },
    { wwdrCA: false }, { wwdrCertSign: false }, { signerCA: true }, { signerDigitalSignature: false },
    { signerValidity: 'expired' }, { signerValidity: 'future' }, { wwdrValidity: 'expired' }, { rootValidity: 'expired' },
  ]) {
    const fixture = await createWalletFixture(options);
    const crypto = core.createWalletCrypto(fixture.rootPem);
    await assert.rejects(() => crypto.normalizeWalletCredentials(fixture.input), error => {
      assert.equal(error.status, 400, JSON.stringify(options));
      assert(!error.message.includes(fixture.input.password)); assert(!error.message.includes('BEGIN')); assert(!error.message.includes(fixture.input.p12));
      return true;
    });
  }
  const fixture = await createWalletFixture(), crypto = core.createWalletCrypto(fixture.rootPem);
  await assert.rejects(() => crypto.normalizeWalletCredentials({ ...fixture.input, password: 'wrong-password-that-must-stay-private' }), error => !error.message.includes('wrong-password-that-must-stay-private'));
  const credentials = await crypto.normalizeWalletCredentials(fixture.input);
  await assert.rejects(() => crypto.buildBoardingWalletPass({ ...credentials, teamId: 'OTHERTEAM1' }, fixture.passInput), /no corresponde al Team ID/);
});

test('barcode validation preserves BCBP blanks and rejects control text, URLs and unsupported symbologies', async () => {
  const fixture = await createWalletFixture();
  for (const format of ['PKBarcodeFormatQR', 'PKBarcodeFormatPDF417', 'PKBarcodeFormatAztec']) assert.deepEqual(core.validateWalletBarcode({ format, message: fixture.barcode.message }), { format, message: fixture.barcode.message });
  for (const value of [null, {}, { ...fixture.barcode, format: 'PKBarcodeFormatDataMatrix' }, { ...fixture.barcode, format: 'PKBarcodeFormatCode128' },
    { ...fixture.barcode, format: 'prefixPKBarcodeFormatQRsuffix' }, { ...fixture.barcode, message: 'https://example.invalid/' + 'x'.repeat(60) },
    { ...fixture.barcode, message: 'M0' + ' '.repeat(60) }, { ...fixture.barcode, message: 'M5' + ' '.repeat(60) },
    { ...fixture.barcode, message: ' ' + fixture.barcode.message }, { ...fixture.barcode, message: fixture.barcode.message + '\n' },
    { ...fixture.barcode, message: fixture.barcode.message + '\0' }, { ...fixture.barcode, message: fixture.barcode.message + '\x7f' },
    { ...fixture.barcode, message: fixture.barcode.message + 'é' }, { ...fixture.barcode, message: fixture.barcode.message.slice(0, 59) },
    { ...fixture.barcode, message: 'M1' + ' '.repeat(4095) },
  ]) assert.throws(() => core.validateWalletBarcode(value), /código IATA/);
  const crypto = core.createWalletCrypto(fixture.rootPem), credentials = await crypto.normalizeWalletCredentials(fixture.input);
  await assert.rejects(() => crypto.buildBoardingWalletPass(credentials, { ...fixture.passInput, barcode: { ...fixture.barcode, message: 'https://example.invalid/' } }), /código IATA/);
});

test('archive and pass metadata limits reject oversized, malformed and high-cost inputs', async () => {
  const fixture = await createWalletFixture(), crypto = core.createWalletCrypto(fixture.rootPem);
  for (const input of [
    { ...fixture.input, p12: Buffer.alloc(core.MAX_WALLET_P12_BYTES + 1).toString('base64') },
    { ...fixture.input, p12: 'arbitrary-not-base64' }, { ...fixture.input, password: 'x'.repeat(257) },
    { ...fixture.input, wwdr: Buffer.alloc(core.MAX_WALLET_WWDR_BYTES + 1).toString('base64') },
    { ...fixture.input, wwdr: fixture.wwdrPem + fixture.wwdrPem }, { ...fixture.input, passTypeId: 'pass.invalid..fixture' },
    { ...fixture.input, teamId: 'TEST' },
  ]) await assert.rejects(() => crypto.normalizeWalletCredentials(input));
  const costly = await createWalletFixture({ iterations: 100_001 });
  await assert.rejects(() => crypto.normalizeWalletCredentials(costly.input), /100.000 iteraciones/);
  const credentials = await crypto.normalizeWalletCredentials(fixture.input);
  for (const input of [
    { ...fixture.passInput, serialNumber: '../anything' }, { ...fixture.passInput, passenger: 'Fixture\nTraveller' },
    { ...fixture.passInput, description: 'x'.repeat(201) }, { ...fixture.passInput, travelDate: '2027-02-30' },
    { ...fixture.passInput, origin: 'x'.repeat(101) },
  ]) await assert.rejects(() => crypto.buildBoardingWalletPass(credentials, input));
});
