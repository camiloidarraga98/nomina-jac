import test from 'node:test';
import assert from 'node:assert/strict';
import {builtinModules} from 'node:module';
import {createHash, verify} from 'node:crypto';
import {build} from 'esbuild';
import {Miniflare} from 'miniflare';
import {unzipSync} from 'fflate';
import forge from 'node-forge';
import {createWalletFixture} from './helpers/wallet-synthetic.mjs';

// These keys/certificates are generated locally and have no Apple credentials.
// The test-only factory is never exposed by the production HTTP endpoint.
test('Workerd signs a real in-memory Wallet package with synthetic PKI and no outbound services',{timeout:120000},async()=>{
 const fixture=await createWalletFixture();
 const output=await build({
  stdin:{resolveDir:process.cwd(),loader:'ts',contents:`
   import {Buffer} from 'node:buffer';
   import {createWalletCrypto} from './lib/boarding-wallet-core';
   export default {async fetch(request:Request){
    const fixture=await request.json();
    const wallet=createWalletCrypto(fixture.rootPem);
    const credentials=await wallet.normalizeWalletCredentials(fixture.input);
    const bytes=await wallet.buildBoardingWalletPass(credentials,fixture.passInput);
    return new Response(Buffer.from(bytes),{headers:{
     'Content-Type':'application/vnd.apple.pkpass','Cache-Control':'private, no-store',
    }});
   }};
  `},
  bundle:true,platform:'node',format:'esm',write:false,
  external:['node:*',...builtinModules],
  // Forge uses CommonJS built-in imports. Workers supplies those built-ins via
  // nodejs_compat; this adapter does not replace or stub their implementation.
  // Inline Miniflare modules do not assign import.meta.url. No package or file
  // is loaded from this synthetic base; require only resolves Node built-ins.
  banner:{js:"import {createRequire} from 'node:module'; const require=createRequire('file:///wallet-runtime-fixture.mjs');"},
 });
 let outbound=0;
 const worker=new Miniflare({
  modules:true,compatibilityDate:'2026-05-15',compatibilityFlags:['nodejs_compat'],
  script:output.outputFiles[0].text,
  outboundService:async()=>{outbound++;throw new Error('Wallet runtime tests prohibit all outbound requests.');},
 });
 try{
  const response=await worker.dispatchFetch('https://wallet.example.invalid/synthetic-pass',{
   method:'POST',headers:{'Content-Type':'application/json'},
   body:JSON.stringify({rootPem:fixture.rootPem,input:fixture.input,passInput:fixture.passInput}),
  });
  if(response.status!==200)assert.fail('Wallet runtime returned '+response.status+': '+await response.text());
  assert.equal(response.headers.get('content-type'),'application/vnd.apple.pkpass');
  assert.equal(response.headers.get('cache-control'),'private, no-store');
  const bytes=new Uint8Array(await response.arrayBuffer());
  assert.ok(bytes.length>0&&bytes.length<=1024*1024);
  const files=unzipSync(bytes),json=JSON.parse(Buffer.from(files['pass.json']).toString('utf8'));
  assert.equal(json.passTypeIdentifier,fixture.input.passTypeId);
  assert.equal(json.teamIdentifier,fixture.input.teamId);
  assert.equal(json.serialNumber,fixture.passInput.serialNumber);
  assert.equal(json.boardingPass.transitType,'PKTransitTypeAir');
  assert.equal(json.barcodes[0].message,fixture.passInput.barcode.message);
  assert.equal(json.barcodes[0].format,fixture.passInput.barcode.format);
  assert.equal(json.barcodes[0].messageEncoding,'iso-8859-1');
  assert.equal(json.sharingProhibited,true);
  assert.ok(!json.webServiceURL&&!json.authenticationToken,'This copy has no invented Wallet update service.');

  const manifestBytes=Buffer.from(files['manifest.json']),manifest=JSON.parse(manifestBytes.toString('utf8'));
  for(const [name,contents] of Object.entries(files)){
   if(name==='manifest.json'||name==='signature')continue;
   assert.equal(manifest[name],createHash('sha1').update(contents).digest('hex'),name+' digest matches the bytes signed in Workerd');
  }
  const signed=forge.pkcs7.messageFromAsn1(forge.asn1.fromDer(Buffer.from(files.signature).toString('binary'),true));
  assert.equal(signed.certificates.length,2,'The signer and WWDR intermediate are included.');
  const capture=signed.rawCapture,attributes=capture.authenticatedAttributes;
  const messageDigest=attributes.find(attribute=>forge.asn1.derToOid(attribute.value[0].value)===forge.pki.oids.messageDigest);
  assert.equal(Buffer.from(messageDigest.value[1].value[0].value,'binary').toString('hex'),createHash('sha1').update(manifestBytes).digest('hex'));
  const attributeSet=forge.asn1.create(forge.asn1.Class.UNIVERSAL,forge.asn1.Type.SET,true,attributes);
  assert.ok(verify('RSA-SHA1',Buffer.from(forge.asn1.toDer(attributeSet).getBytes(),'binary'),fixture.signerPem,Buffer.from(capture.signature,'binary')),'The detached CMS signature created in Workerd verifies with independent Node crypto.');
  assert.equal(outbound,0);
 }finally{await worker.dispose();}
});
