export const MEDIA_IMAGE_LIMITS=[2_000_000,4_000_000,6_000_000,0] as const;
export type MediaImageLimit=typeof MEDIA_IMAGE_LIMITS[number];
export const mediaImageLimit=(value:unknown):MediaImageLimit=>(typeof value==='number'||typeof value==='string'&&/^(0|2000000|4000000|6000000)$/.test(value))&&MEDIA_IMAGE_LIMITS.includes(Number(value) as MediaImageLimit)?Number(value) as MediaImageLimit:2_000_000;
export const mediaImageQualityLabel=(limit:number)=>limit?'Hasta '+limit/1_000_000+' MB':'Sin compresión';
