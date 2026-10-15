import type {Metadata} from 'next';
import './globals.css';
export const metadata:Metadata={title:'JAC Music | Nómina',description:'Liquidación quincenal de shows y nómina de JAC Music.',robots:{index:false,follow:false},icons:{icon:'/favicon.svg'}};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="es"><head><meta name="theme-color" content="#062f46"/><link rel="manifest" href="/manifest.webmanifest"/></head><body>{children}</body></html>}
