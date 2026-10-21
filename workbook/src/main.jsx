import { createRoot } from 'react-dom/client'
import App from './App.jsx'
import './styles.css'

// No StrictMode: StPageFlip takes over the book DOM and can't survive a double mount.
createRoot(document.getElementById('root')).render(<App />)
