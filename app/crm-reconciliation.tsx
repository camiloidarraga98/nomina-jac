'use client';

import {useEffect, useRef} from 'react';
import './crm-reconciliation.css';

type ReconciliationState = {dirty: boolean; busy: boolean};

/** Financial data is loaded only by the session-protected reconciliation API. */
export default function CrmReconciliation({onStateChange}: {onStateChange: (state: ReconciliationState) => void}) {
  const frame = useRef<HTMLIFrameElement>(null);
  const current = useRef<ReconciliationState>({dirty: false, busy: false});
  useEffect(() => {
    const receive = (event: MessageEvent) => {
      if (event.origin !== location.origin || event.source !== frame.current?.contentWindow || event.data?.type !== 'jac-reconciliation-state') return;
      current.current = {dirty: event.data.dirty === true, busy: event.data.busy === true};
      onStateChange(current.current);
    };
    const leave = (event: BeforeUnloadEvent) => {
      if (!current.current.dirty && !current.current.busy) return;
      event.preventDefault();
      event.returnValue = '';
    };
    const navigate = (event: MouseEvent) => {
      const link = event.target instanceof Element ? event.target.closest<HTMLAnchorElement>('a[href]') : null;
      if (!link || link.target === '_blank' || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || (!current.current.dirty && !current.current.busy)) return;
      if (current.current.busy || !window.confirm('Tienes cambios de conciliación sin guardar. ¿Quieres salir sin guardarlos?')) {
        event.preventDefault(); event.stopImmediatePropagation(); return;
      }
      current.current = {...current.current, dirty: false};
      frame.current?.contentWindow?.postMessage({type: 'jac-reconciliation-discard'}, location.origin);
      onStateChange(current.current);
    };
    window.addEventListener('message', receive);
    window.addEventListener('beforeunload', leave);
    document.addEventListener('click', navigate, true);
    return () => {
      window.removeEventListener('message', receive);
      window.removeEventListener('beforeunload', leave);
      document.removeEventListener('click', navigate, true);
      onStateChange({dirty: false, busy: false});
    };
  }, [onStateChange]);
  return <section className="crm-reconciliation" aria-label="Conciliación de abonos">
    <div className="crm-reconciliation-intro">
      <p>Relaciona el archivo de contabilidad con los comprobantes de WhatsApp. Los abonos conciliados no se registran de nuevo en los saldos del CRM.</p>
      <a href="/crm/reconciliation" target="_blank" rel="noopener noreferrer">Abrir en pantalla completa ↗</a>
    </div>
    <iframe ref={frame} className="crm-reconciliation-frame" src="/crm/reconciliation?embedded=1" title="Herramienta de conciliación de abonos" referrerPolicy="same-origin" allow="clipboard-read 'self'" />
  </section>;
}
