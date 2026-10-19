import type {Metadata} from 'next';
import SharedFolder from './shared-folder';
export const dynamic='force-dynamic';
export const metadata:Metadata={title:'Carpeta compartida · JAC Music',description:'Fotos y videos compartidos contigo.',robots:{index:false,follow:false},referrer:'no-referrer'};
export default async function SharedPage({params}:{params:Promise<{token:string}>}){const {token}=await params;return <SharedFolder token={/^[A-Za-z0-9_-]{43}$/.test(token)?token:''}/>;}
