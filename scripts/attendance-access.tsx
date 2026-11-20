import {createRoot} from 'react-dom/client';
import AccessScreen from '../app/acceso/access-screen';

createRoot(document.getElementById('acceso')!).render(<AccessScreen ready bootstrap={false}/>);
