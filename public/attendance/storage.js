/* Web records are encrypted before entering IndexedDB. The JAC session supplies only
   the current account's offline capability. Native uses protected on-device files. */
(() => {
  const native = window.webkit?.messageHandlers?.attendance;
  const encoder = new TextEncoder();
  let opening;
  function activeScope() {
    const match = document.cookie.match(/(?:^|;\s*)jac_attendance_scope=([a-f0-9-]{36})\.([A-Za-z0-9_-]{43})(?:;|$)/i);
    return match ? {account: match[1], secret: match[2]} : null;
  }
  function database() {
    return opening ??= new Promise((resolve, reject) => {
      const request = indexedDB.open('jac-attendance-pilot', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('records');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }
  async function access(account, op, key = '', value = null) {
    if (!/^[\da-f-]{36}$/i.test(account)) throw Error('Falta la cuenta del dispositivo.');
    if (native) return native.postMessage({action: 'storage', account, op, key, value});
    const scope = activeScope();
    if (scope?.account !== account) throw Error('Cambió la sesión del dispositivo.');
    const raw = Uint8Array.from(atob(scope.secret.replaceAll('-', '+').replaceAll('_', '/') + '='), c => c.charCodeAt(0));
    const cipher = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt']);
    const prefix = account + '/', id = prefix + key;
    const db = await database();
    const parameters = (record, iv) => ({name:'AES-GCM', iv, additionalData:encoder.encode(prefix + record)});
    let sealed;
    if (['write','device','enqueue'].includes(op)) {
      const iv = crypto.getRandomValues(new Uint8Array(12));
      const bytes = await crypto.subtle.encrypt(parameters(key, iv), cipher, encoder.encode(JSON.stringify(value)));
      sealed = {key, iv, bytes};
    }
    const result = await new Promise((resolve, reject) => {
      const tx = db.transaction('records', ['read', 'list'].includes(op) ? 'readonly' : 'readwrite');
      const store = tx.objectStore('records');
      let output = null;
      tx.oncomplete = () => resolve(output);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error || Error('Escritura interrumpida.'));
      if (op === 'read' || op === 'list') {
        const query = op === 'read' ? store.get(id) : store.getAll(IDBKeyRange.bound(id, id + '\uffff'));
        query.onsuccess = () => { output = query.result ?? null; };
      } else if (op === 'delete') {
        store.delete(id);
      } else if (op === 'write') {
        store.put(sealed, id);
      } else if (op === 'device') {
        const query = store.get(id);
        query.onsuccess = () => {
          output = query.result || sealed;
          if (!query.result) store.add(sealed, id);
        };
      } else if (op === 'enqueue') {
        const lock = prefix + 'last/' + value.employee + '/' + value.movement;
        const query = store.get(lock);
        query.onsuccess = () => {
          const time = Date.parse(value.device_time);
          if (query.result && Math.abs(time - query.result) < 3000) { output = false; return; }
          store.add(sealed, id);
          store.put(time, lock);
          output = true;
        };
      } else tx.abort();
    });
    if (activeScope()?.secret !== scope.secret) throw Error('Cambió la sesión del dispositivo.');
    async function open(record) {
      if (!record) return null;
      const plain = await crypto.subtle.decrypt(parameters(record.key, record.iv), cipher, record.bytes);
      return JSON.parse(new TextDecoder().decode(plain));
    }
    if (op === 'list') return Promise.all(result.map(open));
    return op === 'read' || op === 'device' ? open(result) : result;
  }
  window.AttendanceStorage = {access, native, activeAccount: () => activeScope()?.account};
})();
