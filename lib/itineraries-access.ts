import type {PayrollState} from './payroll';
export const itineraryViews=['itinerarios','agenda','alertas','cuenta','notificaciones','configuracion'];
export function itineraryWorkspace():PayrollState{return {employees:[],concepts:[],periods:[],settings:{company:'JAC MUSIC ESTUDIOS SAS',nit:'',hourDivisor:210,hourFactors:[0.35,0.9,1.25,1.25,1.75,2.15,2.65]}};}
