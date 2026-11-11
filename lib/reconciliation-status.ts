/** Accounting's immutable invoice + identified third party already resolve the
 * review task. This is a derived classification, never a new income or invoice. */
export function hasAccountingIdentification(input:{thirdParty?:string;invoice?:string}):boolean {
 const normalize=(value:string|undefined)=>(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
 const known=(value:string)=>value.length>1&&!/^(?:n\/?a|no aplica|ninguno|ninguna|tercero|empresa|cliente|varios|consumidor final|null|undefined|0+|[-–—.\s]+)$/.test(value)&&!/(?:sin\s*(?:identificar|tercero|factura|datos|definir|asignar|especificar)|por\s*(?:identificar|confirmar|facturar)|pendiente|desconocid|no\s*(?:identificad|disponible|registrad|reportad|informad)|anulad|cancelad)/.test(value);
 const third=normalize(input.thirdParty),invoice=normalize(input.invoice);
 return known(third)&&/[a-z0-9]/.test(third)&&known(invoice)&&/[1-9]/.test(invoice);
}
