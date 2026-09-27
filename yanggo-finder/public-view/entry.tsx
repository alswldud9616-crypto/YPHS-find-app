import {createRoot} from 'react-dom/client';
import App from '../components/app';
import {AppProvider} from '../components/provider';
createRoot(document.getElementById('root')!).render(<AppProvider publicReadiness><App/></AppProvider>);
