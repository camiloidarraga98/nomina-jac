const retired=()=>Response.json({error:'El registro de cumpleaños fue reemplazado por la herramienta de nómina.'},{status:410,headers:{'Cache-Control':'no-store'}});
export const GET=retired;
export const POST=retired;
export const DELETE=retired;
