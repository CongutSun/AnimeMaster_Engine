import { readFileSync, writeFileSync } from 'node:fs';
import { createPrivateKey, sign } from 'node:crypto';

const [keyPath, input, output] = process.argv.slice(2);
if (!output) throw new Error('Usage: node sign.mjs private.pem catalog.json signed.json');
const key = createPrivateKey(readFileSync(keyPath));
if (key.asymmetricKeyType !== 'rsa' || key.asymmetricKeyDetails.modulusLength !== 2048 ||
    key.asymmetricKeyDetails.publicExponent !== 65537n) throw new Error('Expected RSA-2048 with exponent 65537');
const payload = readFileSync(input);
JSON.parse(payload.toString('utf8'));
writeFileSync(output, JSON.stringify({payload:payload.toString('base64'),signature:sign('sha256', payload,key).toString('base64')}) + '\n');
